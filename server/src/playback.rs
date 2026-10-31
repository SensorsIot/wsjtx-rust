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
pub use windows::{Output, system_time_disciplined};

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
