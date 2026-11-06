#![deny(unsafe_code)]
//! Transmit audio output (WstxTransmit::AudioPlayback): one shared-mode output stream
//! on the profile's exact `audio.output_device`, opened before PTT, playing one program
//! (waveform from its planned sample, or a Tune tone) on every channel of the 48 kHz
//! mix format. Capture never opens it; it never touches CAT.
use crate::audio::{Encoding, NativeFormat};
use std::sync::Arc;

#[cfg(windows)]
#[path = "playback/windows.rs"]
#[allow(unsafe_code)]
mod windows;
#[cfg(windows)]
pub use windows::{Output, install_exit_guard};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OutputError {
    /// Missing/inactive endpoint or open failure.
    Unavailable,
    /// The mix format is not 48 kHz float/PCM.
    UnsupportedFormat,
    /// The endpoint failed or disappeared while open.
    DeviceLost,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OutputState {
    Opening,
    /// Open, streaming silence, no program.
    Ready,
    Playing,
    /// Every program sample was handed to and drained by the device.
    Finished,
    Failed(OutputError),
    Closed,
}
#[derive(Clone, Debug)]
pub enum Source {
    Samples { samples: Arc<[f32]>, skip: usize },
    Tone { hz: f64 },
}

/// Pure frame writer: mono program to all channels of `format`, then silence.
pub struct Renderer {
    source: Source,
    position: usize,
    scale: f32,
    phase: f64,
}
impl Renderer {
    pub fn new(source: Source, scale: f32) -> Self {
        let position = match &source {
            Source::Samples { skip, .. } => *skip,
            Source::Tone { .. } => 0,
        };
        Self {
            source,
            position,
            scale,
            phase: 0.,
        }
    }
    /// #44 the Tx level of a running Tune, without a phase step in the tone.
    pub fn set_scale(&mut self, scale: f32) {
        self.scale = scale;
    }
    /// True once every program sample has been written (a tone never ends).
    pub fn exhausted(&self) -> bool {
        match &self.source {
            Source::Samples { samples, .. } => self.position >= samples.len(),
            Source::Tone { .. } => false,
        }
    }
    /// Samples written so far, counted from the waveform's first sample.
    pub fn position(&self) -> usize {
        self.position
    }
    fn next(&mut self, rate: u32) -> f32 {
        match &self.source {
            Source::Samples { samples, .. } => {
                let value = samples.get(self.position).copied().unwrap_or(0.);
                if self.position < samples.len() {
                    self.position += 1;
                }
                value * self.scale
            }
            Source::Tone { hz } => {
                let value = self.phase.sin() as f32 * self.scale;
                self.phase = (self.phase + std::f64::consts::TAU * hz / f64::from(rate))
                    % std::f64::consts::TAU;
                self.position += 1;
                value
            }
        }
    }
    /// Fills `frames` interleaved frames of `format` into `out`.
    pub fn fill(&mut self, format: NativeFormat, out: &mut [u8], frames: usize) {
        let width = format.frame_bytes() / usize::from(format.channels);
        for frame in 0..frames {
            let value = self.next(format.rate).clamp(-1., 1.);
            for channel in 0..usize::from(format.channels) {
                let at = (frame * usize::from(format.channels) + channel) * width;
                write_sample(format.encoding, value, &mut out[at..at + width]);
            }
        }
    }
}
pub fn write_sample(encoding: Encoding, value: f32, out: &mut [u8]) {
    match encoding {
        Encoding::Float32 => out.copy_from_slice(&value.to_le_bytes()),
        Encoding::Pcm16 => {
            out.copy_from_slice(&((value * 32767.).round() as i16).to_le_bytes());
        }
        Encoding::Pcm24 => {
            let v = (f64::from(value) * 8_388_607.).round() as i32;
            out.copy_from_slice(&v.to_le_bytes()[..3]);
        }
        Encoding::Pcm32 => {
            let v = (f64::from(value) * 2_147_483_647.).round() as i32;
            out.copy_from_slice(&v.to_le_bytes());
        }
    }
}

/// Requested shared-mode render buffer (WstxTransmit::AudioPlayback renderBufferMs). The
/// program keeps up to this much queued, so a render thread delayed by CPU load does
/// not underrun the device and stretch the transmission (#49).
pub const RENDER_BUFFER_MS: u32 = 100;
/// Silence kept queued while no program plays (silencePrefillMs, 20 ms at 48 kHz): the
/// first program sample is never queued behind a full buffer of silence.
pub const SILENCE_FRAMES: u32 = 960;
/// What the render loop does with the device buffer (WstxTransmit::AudioPlayback drain
/// rule): silence is topped up to SILENCE_FRAMES, a program fills the whole buffer;
/// after the program is exhausted nothing more is written, so the device padding
/// drains to zero and the end is reported once every program frame was consumed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Fill {
    Program(u32),
    Silence(u32),
    Nothing,
    Finished,
}
pub fn plan_fill(program: Option<&Renderer>, padding: u32, capacity: u32) -> Fill {
    let available = capacity.saturating_sub(padding);
    match program {
        Some(r) if r.exhausted() => {
            if padding == 0 {
                Fill::Finished
            } else {
                Fill::Nothing
            }
        }
        _ if available == 0 => Fill::Nothing,
        Some(_) => Fill::Program(available),
        None if padding >= SILENCE_FRAMES => Fill::Nothing,
        None => Fill::Silence(available.min(SILENCE_FRAMES - padding)),
    }
}
/// Render progress watchdog: frames the device actually consumed (written minus padding)
/// must advance at least every `STALL_MS`, otherwise the output is treated as lost.
pub const STALL_MS: u64 = 500;
#[derive(Clone, Copy, Debug, Default)]
pub struct Progress {
    written: u64,
    consumed: u64,
    at_ms: u64,
}
impl Progress {
    pub fn new(now_ms: u64) -> Self {
        Self {
            at_ms: now_ms,
            ..Self::default()
        }
    }
    pub fn wrote(&mut self, frames: u32) {
        self.written += u64::from(frames);
    }
    pub fn observe(&mut self, padding: u32, now_ms: u64) {
        let consumed = self.written.saturating_sub(u64::from(padding));
        if consumed > self.consumed {
            self.consumed = consumed;
            self.at_ms = now_ms;
        }
    }
    pub fn stalled(&self, now_ms: u64) -> bool {
        now_ms.saturating_sub(self.at_ms) > STALL_MS
    }
    pub fn last_progress_ms(&self) -> u64 {
        self.at_ms
    }
}
