//! Bounded live receive input. Identity and DSP scheduling belong to the receive owner.
use crate::source::{
    CANONICAL_HZ, EpochLatch, LIVE_BLOCK_FRAMES, MAX_COUNTER, SampleBlock, SampleSource,
    SourceDescriptor, SourceError, SourcePoll, SourceTiming,
};
use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

#[cfg(windows)]
#[path = "audio/windows.rs"]
mod windows;
#[cfg(windows)]
pub use windows::{AudioController, CaptureHandle, InputDevice, enumerate_inputs, system_clock};

pub const MAX_NATIVE_PACKET: usize = 8192;
pub const FILTER_TAPS: usize = 257;
pub const FILTER_DELAY: usize = (FILTER_TAPS - 1) / 2;

/// Retain the complete native owner until Stop acknowledges release. A failure is terminal
/// for this accepted capture even if a later close retry succeeds.
#[cfg(any(windows, test))]
pub(crate) fn finish_capture_owner<O>(
    mut owner: O,
    prior: Result<(), SourceError>,
    mut stop: impl FnMut(&mut O) -> Result<(), SourceError>,
    failed_close: impl FnOnce(),
    mut wait: impl FnMut(),
) -> Result<(), SourceError> {
    if stop(&mut owner).is_ok() {
        return prior;
    }
    failed_close();
    loop {
        wait();
        if stop(&mut owner).is_ok() {
            return Err(SourceError::FailedClose);
        }
    }
}
pub const SILENT: u32 = 2;
pub const DATA_DISCONTINUITY: u32 = 1;
pub const TIMESTAMP_ERROR: u32 = 4;

#[derive(Clone, Copy)]
pub(crate) enum CaptureEvent {
    QueueContention,
    QueueFull,
    PoolExhausted,
    InvalidPacket,
    ClockStep,
    TimestampError,
    NativeDiscontinuity,
    FrameBackstep,
}

/// Diagnostic event counts only; they do not allocate identities or alter epoch policy.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CaptureDiagnostics {
    pub queue_contention: u64,
    pub queue_full: u64,
    pub pool_exhausted: u64,
    pub invalid_packet: u64,
    pub clock_step: u64,
    pub timestamp_error: u64,
    pub native_discontinuity: u64,
    pub frame_backstep: u64,
    pub native_channel_zero_samples: u64,
    pub native_channel_zero_full_scale: u64,
    pub native_channel_zero_peak_bits: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Encoding {
    Float32,
    Pcm16,
    Pcm24,
    Pcm32,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct NativeFormat {
    pub rate: u32,
    pub channels: u16,
    pub encoding: Encoding,
}
impl NativeFormat {
    pub fn validate(self) -> Result<Self, SourceError> {
        if !matches!(self.rate, 44_100 | 48_000) || !matches!(self.channels, 1 | 2) {
            return Err(SourceError::UnsupportedFormat);
        }
        Ok(self)
    }
    /// Validates the little-endian WAVEFORMATEX plus its declared extension.
    pub fn from_wave_format(bytes: &[u8]) -> Result<Self, SourceError> {
        if bytes.len() < 18 {
            return Err(SourceError::UnsupportedFormat);
        }
        let word = |at: usize| u16::from_le_bytes([bytes[at], bytes[at + 1]]);
        let dword = |at: usize| {
            u32::from_le_bytes([bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]])
        };
        if bytes.len() != 18 + usize::from(word(16)) {
            return Err(SourceError::UnsupportedFormat);
        }
        let mut tag = word(0);
        let bits = word(14);
        if tag == 0xfffe {
            if bytes.len() < 40 || word(18) != bits {
                return Err(SourceError::UnsupportedFormat);
            }
            let guid = &bytes[24..40];
            let suffix = [0, 0, 16, 0, 128, 0, 0, 170, 0, 56, 155, 113];
            if guid[4..] != suffix || guid[1..4] != [0, 0, 0] {
                return Err(SourceError::UnsupportedFormat);
            }
            tag = match guid[0] {
                1 => 1,
                3 => 3,
                _ => return Err(SourceError::UnsupportedFormat),
            };
        }
        let encoding = match (tag, bits) {
            (3, 32) => Encoding::Float32,
            (1, 16) => Encoding::Pcm16,
            (1, 24) => Encoding::Pcm24,
            (1, 32) => Encoding::Pcm32,
            _ => return Err(SourceError::UnsupportedFormat),
        };
        let format = Self {
            rate: dword(4),
            channels: word(2),
            encoding,
        }
        .validate()?;
        if usize::from(word(12)) != format.frame_bytes()
            || dword(8) != format.rate.saturating_mul(format.frame_bytes() as u32)
        {
            return Err(SourceError::UnsupportedFormat);
        }
        Ok(format)
    }
    pub fn frame_bytes(self) -> usize {
        usize::from(self.channels)
            * match self.encoding {
                Encoding::Pcm16 => 2,
                Encoding::Pcm24 => 3,
                _ => 4,
            }
    }
    pub fn channel_zero(
        self,
        bytes: &[u8],
        frames: usize,
        silent: bool,
    ) -> Result<Vec<f32>, SourceError> {
        self.validate()?;
        if frames > MAX_NATIVE_PACKET
            || (!silent
                && bytes.len()
                    != frames
                        .checked_mul(self.frame_bytes())
                        .ok_or(SourceError::InvalidBlock)?)
        {
            return Err(SourceError::InvalidBlock);
        }
        if silent {
            return Ok(vec![0.0; frames]);
        }
        let mut out = Vec::with_capacity(frames);
        for frame in bytes.chunks_exact(self.frame_bytes()) {
            let value = match self.encoding {
                Encoding::Float32 => f32::from_le_bytes(
                    frame[..4]
                        .try_into()
                        .map_err(|_| SourceError::InvalidBlock)?,
                ),
                Encoding::Pcm16 => {
                    f32::from(i16::from_le_bytes(
                        frame[..2]
                            .try_into()
                            .map_err(|_| SourceError::InvalidBlock)?,
                    )) / 32768.0
                }
                Encoding::Pcm24 => {
                    let n = i32::from_le_bytes([
                        frame[0],
                        frame[1],
                        frame[2],
                        if frame[2] & 128 != 0 { 255 } else { 0 },
                    ]);
                    n as f32 / 8_388_608.0
                }
                Encoding::Pcm32 => {
                    i32::from_le_bytes(
                        frame[..4]
                            .try_into()
                            .map_err(|_| SourceError::InvalidBlock)?,
                    ) as f32
                        / 2_147_483_648.0
                }
            };
            if !value.is_finite() {
                return Err(SourceError::InvalidBlock);
            }
            out.push(value);
        }
        Ok(out)
    }
}

#[derive(Clone, Debug)]
pub struct NativePacket {
    pub bytes: Vec<u8>,
    pub frames: usize,
    pub first_frame: u64,
    pub qpc_100ns: u64,
    pub flags: u32,
}
struct QueueState {
    packets: VecDeque<NativePacket>,
    free: Vec<Vec<u8>>,
    frames: usize,
    error: Option<SourceError>,
}
/// Preallocated packet bytes; I/O drops instead of waiting for the DSP owner.
pub struct PacketQueue {
    state: Mutex<QueueState>,
    capacity: usize,
    pub(crate) loss: AtomicBool,
    pub(crate) cancelled: AtomicBool,
    events: [AtomicU64; 8],
    native_samples: AtomicU64,
    native_full_scale: AtomicU64,
    native_peak: AtomicU32,
}
impl PacketQueue {
    pub fn new(format: NativeFormat) -> Result<Arc<Self>, SourceError> {
        format.validate()?;
        Ok(Arc::new(Self {
            state: Mutex::new(QueueState {
                packets: VecDeque::with_capacity(64),
                free: (0..64)
                    .map(|_| Vec::with_capacity(MAX_NATIVE_PACKET * format.frame_bytes()))
                    .collect(),
                frames: 0,
                error: None,
            }),
            capacity: format.rate as usize / 2,
            loss: AtomicBool::new(false),
            cancelled: AtomicBool::new(false),
            events: std::array::from_fn(|_| AtomicU64::new(0)),
            native_samples: AtomicU64::new(0),
            native_full_scale: AtomicU64::new(0),
            native_peak: AtomicU32::new(0),
        }))
    }
    pub(crate) fn record_event(&self, event: CaptureEvent) {
        let _ = self.events[event as usize].try_update(Ordering::Relaxed, Ordering::Relaxed, |n| {
            Some(n.saturating_add(1))
        });
    }
    pub(crate) fn mark_loss(&self, event: CaptureEvent) {
        self.record_event(event);
        self.loss.store(true, Ordering::Release);
    }
    pub fn diagnostics(&self) -> CaptureDiagnostics {
        let values = self.events.each_ref().map(|v| v.load(Ordering::Relaxed));
        CaptureDiagnostics {
            queue_contention: values[0],
            queue_full: values[1],
            pool_exhausted: values[2],
            invalid_packet: values[3],
            clock_step: values[4],
            timestamp_error: values[5],
            native_discontinuity: values[6],
            frame_backstep: values[7],
            native_channel_zero_samples: self.native_samples.load(Ordering::Relaxed),
            native_channel_zero_full_scale: self.native_full_scale.load(Ordering::Relaxed),
            native_channel_zero_peak_bits: self.native_peak.load(Ordering::Relaxed),
        }
    }
    fn record_native_levels(&self, samples: &[f32]) {
        let peak = samples.iter().map(|v| v.abs()).fold(0.0_f32, f32::max);
        self.native_peak
            .fetch_max(peak.to_bits(), Ordering::Relaxed);
        let _ = self
            .native_samples
            .try_update(Ordering::Relaxed, Ordering::Relaxed, |n| {
                Some(n.saturating_add(samples.len() as u64))
            });
        let full_scale = samples.iter().filter(|v| v.abs() >= 1.0).count() as u64;
        let _ = self
            .native_full_scale
            .try_update(Ordering::Relaxed, Ordering::Relaxed, |n| {
                Some(n.saturating_add(full_scale))
            });
    }
    pub fn push(
        &self,
        bytes: &[u8],
        frames: usize,
        first_frame: u64,
        qpc_100ns: u64,
        flags: u32,
    ) -> bool {
        if self.cancelled.load(Ordering::Acquire) {
            return false;
        }
        let Ok(mut state) = self.state.try_lock() else {
            self.mark_loss(CaptureEvent::QueueContention);
            return false;
        };
        if frames == 0 || frames > MAX_NATIVE_PACKET {
            self.mark_loss(CaptureEvent::InvalidPacket);
            return false;
        }
        if state.frames.saturating_add(frames) > self.capacity || state.packets.len() == 64 {
            self.mark_loss(CaptureEvent::QueueFull);
            return false;
        }
        let Some(mut data) = state.free.pop() else {
            self.mark_loss(CaptureEvent::PoolExhausted);
            return false;
        };
        if bytes.len() > data.capacity() {
            state.free.push(data);
            self.mark_loss(CaptureEvent::InvalidPacket);
            return false;
        }
        data.clear();
        data.extend_from_slice(bytes);
        state.frames += frames;
        state.packets.push_back(NativePacket {
            bytes: data,
            frames,
            first_frame,
            qpc_100ns,
            flags,
        });
        true
    }
    fn pop(&self) -> Option<NativePacket> {
        let mut s = self.state.try_lock().ok()?;
        let p = s.packets.pop_front()?;
        s.frames -= p.frames;
        Some(p)
    }
    fn recycle(&self, mut packet: NativePacket) {
        packet.bytes.clear();
        if let Ok(mut s) = self.state.lock() {
            s.free.push(packet.bytes);
        }
    }
    pub fn fail(&self, error: SourceError) {
        if let Ok(mut s) = self.state.lock() {
            s.error = Some(error);
        }
    }
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
    }
    pub fn queued_frames(&self) -> usize {
        self.state.lock().map_or(0, |s| s.frames)
    }
}

/// Exact rational phase; the 257 native samples must all have actually been captured.
pub struct Converter {
    rate: u32,
    coefficients: Vec<Vec<f64>>,
    history: VecDeque<f32>,
    history_start: u64,
    end: u64,
    next: u64,
}
impl Converter {
    pub fn new(rate: u32) -> Result<Self, SourceError> {
        if !matches!(rate, 44_100 | 48_000) {
            return Err(SourceError::UnsupportedFormat);
        }
        let phases = if rate == 44_100 { 40 } else { 1 };
        let mut coefficients = Vec::with_capacity(phases);
        for phase in 0..phases {
            let fraction = phase as f64 / phases as f64;
            let mut taps = Vec::with_capacity(FILTER_TAPS);
            for j in 0..FILTER_TAPS {
                let x = j as f64 - FILTER_DELAY as f64 - fraction;
                let z = 2.0 * 4500.0 / f64::from(rate) * x;
                let sinc = if z.abs() < 1e-15 {
                    1.0
                } else {
                    (std::f64::consts::PI * z).sin() / (std::f64::consts::PI * z)
                };
                let r = (j as f64 - FILTER_DELAY as f64) / FILTER_DELAY as f64;
                taps.push(
                    2.0 * 4500.0 / f64::from(rate)
                        * sinc
                        * bessel(8.6 * (1.0 - r * r).max(0.0).sqrt())
                        / bessel(8.6),
                );
            }
            let sum: f64 = taps.iter().sum();
            for t in &mut taps {
                *t /= sum;
            }
            coefficients.push(taps);
        }
        Ok(Self {
            rate,
            coefficients,
            history: VecDeque::with_capacity(MAX_NATIVE_PACKET + FILTER_TAPS),
            history_start: 0,
            end: 0,
            next: 0,
        })
    }
    pub fn delay_native_frames(&self) -> f64 {
        FILTER_DELAY as f64
    }
    pub fn reset_at(&mut self, native_frame: u64) -> Result<(), SourceError> {
        if native_frame > MAX_COUNTER {
            return Err(SourceError::CounterExhausted);
        }
        self.next = u64::try_from(
            (u128::from(native_frame) * u128::from(CANONICAL_HZ)).div_ceil(u128::from(self.rate)),
        )
        .map_err(|_| SourceError::CounterExhausted)?;
        self.history.clear();
        self.history_start = native_frame;
        self.end = native_frame;
        Ok(())
    }
    /// Canonical n represents native position origin + 128 + n * native_rate / 12000.
    /// SourceTiming.native_anchor_frame already includes 128; delay metadata is not added twice.
    pub fn convert(&mut self, samples: &[f32]) -> Result<(u64, Vec<f32>), SourceError> {
        if samples.len() > MAX_NATIVE_PACKET || !samples.iter().all(|x| x.is_finite()) {
            return Err(SourceError::InvalidBlock);
        }
        self.end = self
            .end
            .checked_add(samples.len() as u64)
            .filter(|n| *n <= MAX_COUNTER)
            .ok_or(SourceError::CounterExhausted)?;
        self.history.extend(samples);
        let first = self.next;
        let mut output = Vec::with_capacity(samples.len() / 3 + 1);
        loop {
            let numerator = u128::from(self.next) * u128::from(self.rate);
            let left = u64::try_from(numerator / u128::from(CANONICAL_HZ))
                .map_err(|_| SourceError::CounterExhausted)?;
            if left
                .checked_add(FILTER_TAPS as u64)
                .is_none_or(|n| n > self.end)
            {
                break;
            }
            let offset = usize::try_from(
                left.checked_sub(self.history_start)
                    .ok_or(SourceError::InvalidBlock)?,
            )
            .map_err(|_| SourceError::InvalidBlock)?;
            let phase = if self.rate == 44_100 {
                (numerator % 12000) / 300
            } else {
                0
            } as usize;
            let value = self.coefficients[phase]
                .iter()
                .enumerate()
                .map(|(j, t)| *t * f64::from(self.history[offset + j]))
                .sum::<f64>();
            let sample = value as f32;
            if !sample.is_finite() {
                return Err(SourceError::InvalidBlock);
            }
            output.push(sample);
            self.next = self
                .next
                .checked_add(1)
                .filter(|n| *n <= MAX_COUNTER)
                .ok_or(SourceError::CounterExhausted)?;
        }
        let keep = u64::try_from(u128::from(self.next) * u128::from(self.rate) / 12000)
            .map_err(|_| SourceError::CounterExhausted)?;
        while self.history_start < keep.min(self.end) {
            self.history.pop_front();
            self.history_start += 1;
        }
        Ok((first, output))
    }
    pub fn response_taps(&self) -> &[Vec<f64>] {
        &self.coefficients
    }
}
fn bessel(x: f64) -> f64 {
    let mut sum = 1.0;
    let mut term = 1.0;
    for k in 1..=40 {
        term *= x * x / (4.0 * f64::from(k * k));
        sum += term;
        if term < sum * 1e-16 {
            break;
        }
    }
    sum
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ClockCorrelation {
    pub qpc_100ns: u64,
    pub utc_filetime_100ns: u64,
    pub uncertainty_ns: u64,
}
impl ClockCorrelation {
    pub fn bracket(before: u64, utc: u64, after: u64) -> Option<Self> {
        let span = after.checked_sub(before)?;
        let uncertainty_ns = span.checked_mul(50)?;
        (uncertainty_ns <= 2_000_000).then_some(Self {
            qpc_100ns: before + span / 2,
            utc_filetime_100ns: utc,
            uncertainty_ns,
        })
    }
    /// A rejected bracket cannot erase the last valid reference for jump detection.
    pub fn observe(previous: &mut Option<Self>, next: Option<Self>) -> bool {
        let Some(next) = next else {
            return false;
        };
        let jumped = previous.is_some_and(|old| old.jumped(next));
        *previous = Some(next);
        jumped
    }
    pub fn offset_100ns(self) -> i128 {
        i128::from(self.utc_filetime_100ns) - i128::from(self.qpc_100ns)
    }
    pub fn jumped(self, other: Self) -> bool {
        (self.offset_100ns() - other.offset_100ns()).abs() > 200_000
    }
    pub fn utc_at(self, qpc: u64) -> Option<u64> {
        u64::try_from(self.offset_100ns() + i128::from(qpc)).ok()
    }
}

pub struct LiveSource {
    queue: Arc<PacketQueue>,
    format: NativeFormat,
    converter: Converter,
    epochs: EpochLatch,
    notify: u64,
    origin: Option<u64>,
    expected: Option<u64>,
    ready: VecDeque<(u64, Arc<[f32]>)>,
    discontinuity: bool,
    terminal: Option<SourceError>,
}
impl LiveSource {
    pub fn new(queue: Arc<PacketQueue>, format: NativeFormat) -> Result<Self, SourceError> {
        format.validate()?;
        Ok(Self {
            queue,
            format,
            converter: Converter::new(format.rate)?,
            epochs: EpochLatch::default(),
            notify: 0,
            origin: None,
            expected: None,
            ready: VecDeque::new(),
            discontinuity: true,
            terminal: None,
        })
    }
    pub fn stop(&mut self) {
        self.queue.cancel();
        self.ready.clear();
    }
    fn process(
        &mut self,
        packet: &NativePacket,
    ) -> Result<Option<crate::source::EpochProposal>, SourceError> {
        let loss = self.queue.loss.swap(false, Ordering::AcqRel);
        if packet.flags & TIMESTAMP_ERROR != 0 {
            self.queue.record_event(CaptureEvent::TimestampError);
        }
        if packet.flags & DATA_DISCONTINUITY != 0 {
            self.queue.record_event(CaptureEvent::NativeDiscontinuity);
        }
        if self.expected.is_some_and(|n| packet.first_frame < n) {
            self.queue.record_event(CaptureEvent::FrameBackstep);
        }
        let unknown = loss
            || packet.flags & TIMESTAMP_ERROR != 0
            || self.expected.is_some_and(|n| packet.first_frame < n)
            || (packet.flags & DATA_DISCONTINUITY != 0
                && self.expected == Some(packet.first_frame));
        let epoch = self.origin.is_none() || unknown;
        if epoch {
            if packet
                .first_frame
                .checked_add(FILTER_DELAY as u64)
                .is_none_or(|n| n > MAX_COUNTER)
            {
                return Err(SourceError::CounterExhausted);
            }
            self.origin = Some(packet.first_frame);
            self.expected = None;
            self.ready.clear();
            self.converter.reset_at(0)?;
            self.discontinuity = true;
        }
        let relative = packet
            .first_frame
            .checked_sub(self.origin.ok_or(SourceError::InvalidContext)?)
            .ok_or(SourceError::InvalidBlock)?;
        if self.expected.is_some_and(|n| n != packet.first_frame) {
            self.converter.reset_at(relative)?;
            self.ready.clear();
            self.discontinuity = true;
        }
        let end = packet
            .first_frame
            .checked_add(packet.frames as u64)
            .filter(|n| *n <= MAX_COUNTER)
            .ok_or(SourceError::CounterExhausted)?;
        let samples =
            self.format
                .channel_zero(&packet.bytes, packet.frames, packet.flags & SILENT != 0)?;
        self.queue.record_native_levels(&samples);
        let (first, output) = self.converter.convert(&samples)?;
        for (i, chunk) in output.chunks(LIVE_BLOCK_FRAMES).enumerate() {
            self.ready
                .push_back((first + (i * LIVE_BLOCK_FRAMES) as u64, Arc::from(chunk)));
        }
        self.expected = Some(end);
        if epoch {
            return self
                .epochs
                .propose(
                    if unknown {
                        "capture_loss"
                    } else {
                        "capture_start"
                    },
                    self.format.rate,
                    packet.first_frame,
                    if packet.flags & TIMESTAMP_ERROR == 0 {
                        Some(packet.qpc_100ns)
                    } else {
                        None
                    },
                    self.converter.delay_native_frames(),
                )
                .map(Some);
        }
        Ok(None)
    }
}
impl SampleSource for LiveSource {
    fn descriptor(&self) -> Option<Arc<SourceDescriptor>> {
        self.epochs.context().map(|c| c.descriptor.clone())
    }
    fn poll(&mut self) -> SourcePoll {
        if self.queue.cancelled.load(Ordering::Acquire) {
            self.ready.clear();
            return SourcePoll::Failed(SourceError::Cancelled);
        }
        if let Ok(state) = self.queue.state.try_lock()
            && let Some(error) = state.error
        {
            self.terminal = Some(error);
        }
        if let Some(error) = self.terminal {
            self.ready.clear();
            return SourcePoll::Failed(error);
        }
        if self.queue.loss.load(Ordering::Acquire) {
            self.ready.clear();
        }
        if let Some(proposal) = self.epochs.pending() {
            if self.notify != proposal.proposal_counter {
                self.notify = proposal.proposal_counter;
                return SourcePoll::EpochChanged(proposal.clone());
            }
            return SourcePoll::Pending;
        }
        if self.ready.is_empty()
            && let Some(packet) = self.queue.pop()
        {
            let result = self.process(&packet);
            self.queue.recycle(packet);
            match result {
                Err(e) => {
                    self.terminal = Some(e);
                    return SourcePoll::Failed(e);
                }
                Ok(Some(p)) => {
                    self.notify = p.proposal_counter;
                    return SourcePoll::EpochChanged(p);
                }
                Ok(None) => {}
            }
        }
        if let Some((first, samples)) = self.ready.pop_front()
            && let Some(context) = self.epochs.context()
        {
            let discontinuity = std::mem::replace(&mut self.discontinuity, false);
            return match SampleBlock::live(context, first, samples, discontinuity) {
                Ok(b) => SourcePoll::Block(b),
                Err(e) => SourcePoll::Failed(e),
            };
        }
        SourcePoll::Pending
    }
    fn acknowledge_epoch(
        &mut self,
        counter: u64,
        descriptor: Arc<SourceDescriptor>,
        timing: SourceTiming,
    ) -> Result<(), SourceError> {
        if timing.native_anchor_frame
            != self.origin.ok_or(SourceError::InvalidContext)? as f64 + FILTER_DELAY as f64
            || timing.canonical_anchor_frame != 0
        {
            return Err(SourceError::InvalidContext);
        }
        self.epochs.acknowledge(counter, descriptor, timing)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AudioState {
    Closed,
    Opening,
    Running,
    Closing,
    Unavailable,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct AudioStatus {
    pub state: AudioState,
    pub error: Option<SourceError>,
    pub retry_after_ms: Option<u64>,
}
/// Monotonic time in milliseconds; no dependency on UTC or external clock providers.
pub struct Lifecycle {
    pub wanted: bool,
    pub state: AudioState,
    pub error: Option<SourceError>,
    retry_at: Option<u64>,
    attempt: u8,
}
impl Default for Lifecycle {
    fn default() -> Self {
        Self {
            wanted: false,
            state: AudioState::Closed,
            error: None,
            retry_at: None,
            attempt: 0,
        }
    }
}
impl Lifecycle {
    pub fn request_start(&mut self) {
        self.wanted = true;
        self.state = AudioState::Opening;
        self.error = None;
        self.retry_at = None;
        self.attempt = 0;
    }
    pub fn request_stop(&mut self) {
        self.wanted = false;
        self.state = AudioState::Closing;
        self.retry_at = None;
    }
    pub fn running(&mut self) {
        self.state = AudioState::Running;
        self.error = None;
        self.retry_at = None;
    }
    pub fn failed(&mut self, error: SourceError, now_ms: u64) {
        self.state = AudioState::Unavailable;
        self.error = Some(error);
        self.retry_at = if self.wanted
            && !matches!(
                error,
                SourceError::UnsupportedFormat
                    | SourceError::CounterExhausted
                    | SourceError::FailedClose
            ) {
            let delay = 1000_u64 << self.attempt.min(3);
            self.attempt = self.attempt.saturating_add(1);
            Some(now_ms.saturating_add(delay))
        } else {
            None
        };
    }
    pub fn closed(&mut self) {
        self.state = AudioState::Closed;
        self.error = None;
        self.retry_at = None;
    }
    pub fn due(&self, now_ms: u64) -> bool {
        self.wanted && self.retry_at.is_some_and(|at| now_ms >= at)
    }
    pub fn status(&self, now_ms: u64) -> AudioStatus {
        AudioStatus {
            state: self.state,
            error: self.error,
            retry_after_ms: self.retry_at.map(|at| at.saturating_sub(now_ms)),
        }
    }
}
