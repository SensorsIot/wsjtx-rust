#![forbid(unsafe_code)]
//! WstxTransmit slice B (#9): the station's single transmit owner. It holds the armed
//! state, admits TransmitRequests, replaces the pending request until its audio starts,
//! keys PTT with readback before audio, releases it after the last sample, halts with
//! priority, runs Tune and the Tx watchdog, and reports every TransmitOutcome.
//! Hardware, clock and station context are injected (`Hardware`), so the same core runs
//! against the CI-V actor and WASAPI output in the station and against emulators on a
//! virtual clock in tests.
use super::{
    ClockState, PackError, SampleRate, ScheduleError, WaveformError, encode, encode_ft4,
    plan_start, waveform, waveform_ft4,
};
use crate::decoder::Mode;
use std::{
    collections::VecDeque,
    sync::{
        Arc, Condvar, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};

/// Native playback rate of every transmission (WstxTransmit::Ft8WaveformContract).
pub const SAMPLE_RATE_HZ: u32 = 48_000;
/// WstxTransmit::TransmitTiming haltMs: audio stopped, PTT released and read back.
pub const HALT_BOUND_MS: u64 = 250;
/// Playback scale of the unit-peak waveform (-6.02 dBFS, TransmitTiming playbackScale).
pub const PLAYBACK_SCALE: f32 = 0.5;
/// WstxTransmit::TransmitTiming releaseMarginMs: PTT is released at the latest this long
/// after the waveform's last sample was due, whatever the device reports.
pub const RELEASE_MARGIN_MS: i64 = 500;
pub const MAX_SAFE: u64 = 9_007_199_254_740_991;
const OUTCOMES: usize = 32;
const HALT_RECEIPTS: usize = 16;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ArmState {
    Disarmed,
    Armed,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DisarmCause {
    Operator,
    Halt,
    ContactCompleted,
    ContactCancelled,
    TxWatchdog,
    Refused,
    Failed,
    DeviceLost,
    Startup,
    AuthorityChanged,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TransmitRefusal {
    TransmitUnsupported,
    NotArmed,
    AudioStarted,
    DuplicateSequence,
    StaleRequest,
    ClockNotSynchronized,
    MisalignedPeriod,
    StalePeriod,
    PackRefused,
    FrequencyOutOfRange,
    Busy,
    NotAuthorized,
    RadioUnavailable,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TransmitFailure {
    PttTimeout,
    PttRejected,
    PttReadbackMismatch,
    PttIndeterminate,
    RadioLost,
    AudioUnavailable,
    AudioDeviceLost,
    /// The device did not report the end in time (release deadline or stalled render).
    AudioStalled,
    AuthorityChanged,
    /// The transmit owner thread panicked; it failed closed.
    OwnerFault,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OutcomeKind {
    Accepted,
    Replaced,
    Started,
    Completed,
    Halted,
    Refused,
    Failed,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Outcome {
    /// Station-wide publication order of outcomes in this boot.
    pub outcome_sequence: u64,
    pub request_sequence: u64,
    pub kind: OutcomeKind,
    pub refusal: Option<TransmitRefusal>,
    pub failure: Option<TransmitFailure>,
    pub audio_start_utc_ms: Option<i64>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Capability {
    /// No transmit configuration (PTT disabled, no CAT or no output device).
    Unsupported,
    /// Configured, but the transmit authority's radio/grant preconditions are not met now.
    Unavailable,
    Available,
}
/// Station facts the transmit authority is evaluated against (WstxTransmit::TransmitAuthority).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Context {
    pub capability: Capability,
    /// Current CL-022 safety revision of the selected radio scope.
    pub safety_revision: Option<u64>,
    /// The radio's transmit state from the latest fresh (confirmed) 1C 00 readback of
    /// the CAT owner, whoever queried it; None when no fresh readback exists.
    pub radio_transmitting: Option<bool>,
}
/// WstxTransmit::StartupSafetyRelease: the once-per-boot off-only release.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StartupRelease {
    /// No fresh transmit-state readback yet in this boot.
    Pending,
    /// The first fresh readback showed receive, or this boot had already keyed.
    NotNeeded,
    /// TX was observed before this boot ever keyed; one release was confirmed.
    Released,
    /// The one release attempt was not confirmed (PTT indeterminate).
    Failed,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Request {
    pub contact_id: Option<String>,
    pub request_sequence: u64,
    pub mode: Mode,
    pub period_start_utc_ms: i64,
    pub message_text: String,
    pub tx_offset_hz: u32,
}
/// Audio the output device plays from its first written sample.
#[derive(Clone, Debug)]
pub enum Program {
    /// Waveform samples from `skip` (late start) to the end, scaled by PLAYBACK_SCALE.
    Waveform { samples: Arc<[f32]>, skip: usize },
    /// Unmodulated Tune tone.
    Tone { hz: f64 },
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PttError {
    Busy,
    Unavailable,
    Timeout,
    Rejected,
    ReadbackMismatch,
    Indeterminate,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AudioError {
    Unavailable,
    DeviceLost,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AudioPoll {
    Idle,
    Playing,
    /// Every sample was played.
    Finished,
    Failed(AudioError),
}
pub trait Hardware: Send {
    fn now_utc_ms(&self) -> i64;
    /// Monotonic milliseconds for the release deadline (never steps with UTC). The
    /// default follows `now_utc_ms`, for virtual-clock doubles only.
    fn monotonic_ms(&self) -> i64 {
        self.now_utc_ms()
    }
    fn clock(&self) -> ClockState;
    /// The measurement behind `clock` (TransmitClock), shown on the wire; none for doubles.
    fn clock_measurement(&self) -> Option<super::clock::Measurement> {
        None
    }
    fn context(&self) -> Context;
    /// Key or release the transmit switch; Ok only after a matching readback.
    fn ptt(&mut self, on: bool) -> Result<(), PttError>;
    /// Open the selected output device (silence) before PTT is keyed.
    fn open_audio(&mut self) -> Result<(), AudioError>;
    /// Start `program` now on the opened device.
    fn play(&mut self, program: Program) -> Result<(), AudioError>;
    fn poll_audio(&mut self) -> AudioPoll;
    /// Stop and close output; bounded and idempotent.
    fn stop_audio(&mut self);
    /// A handle that stops output from any thread without the core lock (priority halt).
    fn audio_stopper(&self) -> Arc<dyn Fn() + Send + Sync>;
    /// The priority-halt flag; device waits (output open, CAT key wait) abort on it.
    fn attach_abort(&mut self, abort: Arc<AtomicBool>) {
        let _ = abort;
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PttState {
    Released,
    Keyed,
    /// A release was not confirmed by readback; RF may still be on.
    Indeterminate,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HaltState {
    Idle,
    Pending,
    Stopped,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct View {
    pub capability: Capability,
    pub arm_state: ArmState,
    pub last_disarm_cause: DisarmCause,
    pub tune: bool,
    pub pending_sequence: Option<u64>,
    pub last_text: Option<String>,
    pub last_period_utc_ms: Option<i64>,
    pub halt_state: HaltState,
    pub refusal: Option<TransmitRefusal>,
    pub ptt: PttState,
    pub transmitting: bool,
    pub clock: ClockState,
    pub clock_measurement: Option<super::clock::Measurement>,
    pub tx_minutes: u32,
    pub tx_remaining_minutes: u32,
    pub tx_expired: bool,
    pub tune_seconds: u32,
    pub tune_remaining_seconds: u32,
    pub outcomes: Vec<Outcome>,
    pub startup_release: StartupRelease,
}

struct Prepared {
    request: Request,
    text: String,
    samples: Arc<[f32]>,
}
struct Job {
    prepared: Prepared,
    keyed: bool,
    audio_start_utc_ms: Option<i64>,
    /// Device-independent release deadline once audio started.
    release_by_mono_ms: Option<i64>,
}
struct Tune {
    hz: f64,
    until_utc_ms: i64,
    keyed: bool,
}

/// The transmit owner's state machine. Single-threaded; `Service` adds the thread and
/// the lock-free priority halt.
pub struct Core<H: Hardware> {
    hardware: H,
    arm: ArmState,
    armed_revision: Option<u64>,
    cause: DisarmCause,
    last_sequence: u64,
    current: Option<Job>,
    next: Option<Prepared>,
    tune: Option<Tune>,
    ptt: PttState,
    last_text: Option<String>,
    last_period: Option<i64>,
    halt_state: HaltState,
    refusal: Option<TransmitRefusal>,
    outcomes: VecDeque<Outcome>,
    outcome_sequence: u64,
    tx_minutes: u32,
    tune_seconds: u32,
    watchdog_from: Option<i64>,
    tx_expired: bool,
    ever_keyed: bool,
    startup_release: StartupRelease,
    abort: Arc<AtomicBool>,
    faulted: bool,
}

fn schedule_refusal(error: ScheduleError) -> TransmitRefusal {
    match error {
        ScheduleError::ClockNotSynchronized => TransmitRefusal::ClockNotSynchronized,
        ScheduleError::MisalignedPeriod => TransmitRefusal::MisalignedPeriod,
        ScheduleError::StalePeriod => TransmitRefusal::StalePeriod,
    }
}
fn ptt_failure(error: PttError) -> TransmitFailure {
    match error {
        PttError::Timeout => TransmitFailure::PttTimeout,
        PttError::Rejected => TransmitFailure::PttRejected,
        PttError::ReadbackMismatch => TransmitFailure::PttReadbackMismatch,
        PttError::Unavailable | PttError::Busy => TransmitFailure::RadioLost,
        PttError::Indeterminate => TransmitFailure::PttIndeterminate,
    }
}
fn audio_delay_ms(mode: Mode) -> i64 {
    match mode {
        Mode::Ft8 => 500,
        Mode::Ft4 => 300,
    }
}
/// Packs, encodes and renders the 48 kHz waveform of a request.
fn prepare(request: &Request) -> Result<Prepared, TransmitRefusal> {
    let pack = |e: PackError| {
        let _ = e;
        TransmitRefusal::PackRefused
    };
    let wave = |e: WaveformError| match e {
        WaveformError::FrequencyOutOfRange => TransmitRefusal::FrequencyOutOfRange,
        WaveformError::InvalidTone => TransmitRefusal::PackRefused,
    };
    let f0 = f64::from(request.tx_offset_hz);
    let (text, samples) = match request.mode {
        Mode::Ft8 => {
            let frame = encode(&request.message_text).map_err(pack)?;
            let samples = waveform(&frame.tones, f0, SampleRate::Hz48000).map_err(wave)?;
            (frame.packed.text, samples)
        }
        Mode::Ft4 => {
            let frame = encode_ft4(&request.message_text).map_err(pack)?;
            let samples = waveform_ft4(&frame.tones, f0, SampleRate::Hz48000).map_err(wave)?;
            (frame.packed.text, samples)
        }
    };
    Ok(Prepared {
        request: request.clone(),
        text,
        samples: samples.into(),
    })
}

impl<H: Hardware> Core<H> {
    /// A new boot: disarmed (DisarmCause startup), nothing pending, nothing replayed.
    pub fn new(hardware: H) -> Self {
        Self {
            hardware,
            arm: ArmState::Disarmed,
            armed_revision: None,
            cause: DisarmCause::Startup,
            last_sequence: 0,
            current: None,
            next: None,
            tune: None,
            ptt: PttState::Released,
            last_text: None,
            last_period: None,
            halt_state: HaltState::Idle,
            refusal: None,
            outcomes: VecDeque::new(),
            outcome_sequence: 0,
            tx_minutes: 6,
            tune_seconds: 90,
            watchdog_from: None,
            tx_expired: false,
            ever_keyed: false,
            startup_release: StartupRelease::Pending,
            abort: Arc::new(AtomicBool::new(false)),
            faulted: false,
        }
    }
    /// Shares the priority-halt flag with the hardware's device waits.
    pub fn attach_abort(&mut self, abort: Arc<AtomicBool>) {
        self.hardware.attach_abort(abort.clone());
        self.abort = abort;
    }
    fn aborted(&self) -> bool {
        self.abort.load(Ordering::Acquire)
    }
    pub fn hardware(&self) -> &H {
        &self.hardware
    }
    pub fn hardware_mut(&mut self) -> &mut H {
        &mut self.hardware
    }
    fn emit(&mut self, request_sequence: u64, kind: OutcomeKind) -> Outcome {
        self.emit_full(request_sequence, kind, None, None, None)
    }
    fn emit_full(
        &mut self,
        request_sequence: u64,
        kind: OutcomeKind,
        refusal: Option<TransmitRefusal>,
        failure: Option<TransmitFailure>,
        audio_start_utc_ms: Option<i64>,
    ) -> Outcome {
        self.outcome_sequence += 1;
        let outcome = Outcome {
            outcome_sequence: self.outcome_sequence,
            request_sequence,
            kind,
            refusal,
            failure,
            audio_start_utc_ms,
        };
        if self.outcomes.len() == OUTCOMES {
            self.outcomes.pop_front();
        }
        self.outcomes.push_back(outcome.clone());
        outcome
    }
    fn disarm_with(&mut self, cause: DisarmCause) {
        self.arm = ArmState::Disarmed;
        self.armed_revision = None;
        self.cause = cause;
        self.watchdog_from = None;
    }
    /// Disarm and drop every request whose audio has not started and that is not keyed
    /// (before-key Disarm cancels; a keyed or started transmission finishes).
    fn cancel_unstarted(&mut self, kind: OutcomeKind, refusal: Option<TransmitRefusal>) {
        if let Some(next) = self.next.take() {
            self.emit_full(next.request.request_sequence, kind, refusal, None, None);
        }
        if self.current.as_ref().is_some_and(|j| !j.keyed) {
            let job = self.current.take().unwrap();
            self.emit_full(
                job.prepared.request.request_sequence,
                kind,
                refusal,
                None,
                None,
            );
        }
    }
    /// Arm under the station's explicit transmit authority: the transmit capability is
    /// available now and `safety_revision` is the current CL-022 revision.
    pub fn arm(&mut self, safety_revision: u64) -> Result<(), TransmitRefusal> {
        let context = self.hardware.context();
        let refusal = match context.capability {
            Capability::Unsupported => Some(TransmitRefusal::TransmitUnsupported),
            Capability::Unavailable => Some(TransmitRefusal::RadioUnavailable),
            Capability::Available if context.safety_revision != Some(safety_revision) => {
                Some(TransmitRefusal::NotAuthorized)
            }
            Capability::Available => None,
        };
        if let Some(refusal) = refusal {
            self.refusal = Some(refusal);
            return Err(refusal);
        }
        if self.ptt == PttState::Indeterminate
            || self.startup_release == StartupRelease::Failed
            || self.faulted
        {
            self.refusal = Some(TransmitRefusal::RadioUnavailable);
            return Err(TransmitRefusal::RadioUnavailable);
        }
        self.arm = ArmState::Armed;
        self.armed_revision = Some(safety_revision);
        self.refusal = None;
        self.tx_expired = false;
        self.watchdog_from = Some(self.hardware.now_utc_ms());
        Ok(())
    }
    /// Operator or contact disarm; no new request is sent.
    pub fn disarm(&mut self, cause: DisarmCause) {
        self.disarm_with(cause);
        self.cancel_unstarted(OutcomeKind::Refused, Some(TransmitRefusal::NotArmed));
    }
    /// Accepted operating activity resets the Tx watchdog (WstxContact::TxWatchdog).
    pub fn activity(&mut self) {
        if self.arm == ArmState::Armed {
            self.watchdog_from = Some(self.hardware.now_utc_ms());
        }
    }
    pub fn set_watchdogs(
        &mut self,
        tx_minutes: u32,
        tune_seconds: u32,
    ) -> Result<(), TransmitRefusal> {
        if !(1..=99).contains(&tx_minutes) || !(1..=300).contains(&tune_seconds) {
            return Err(TransmitRefusal::FrequencyOutOfRange);
        }
        self.tx_minutes = tx_minutes;
        self.tune_seconds = tune_seconds;
        Ok(())
    }
    fn refuse(&mut self, sequence: u64, refusal: TransmitRefusal, disarm: bool) -> Outcome {
        self.refusal = Some(refusal);
        if disarm && self.arm == ArmState::Armed {
            self.disarm_with(DisarmCause::Refused);
            self.cancel_unstarted(OutcomeKind::Refused, Some(TransmitRefusal::NotArmed));
        }
        self.emit_full(sequence, OutcomeKind::Refused, Some(refusal), None, None)
    }
    /// Admit, replace or refuse a TransmitRequest. Refusals other than duplicateSequence
    /// disarm; a duplicate (retry) changes nothing.
    pub fn submit(&mut self, request: Request) -> Outcome {
        let sequence = request.request_sequence;
        if sequence == 0 || sequence > MAX_SAFE || sequence <= self.last_sequence {
            return self.refuse(sequence, TransmitRefusal::DuplicateSequence, false);
        }
        self.last_sequence = sequence;
        let context = self.hardware.context();
        if context.capability == Capability::Unsupported {
            return self.refuse(sequence, TransmitRefusal::TransmitUnsupported, true);
        }
        if self.arm != ArmState::Armed {
            return self.refuse(sequence, TransmitRefusal::NotArmed, false);
        }
        if context.capability != Capability::Available {
            return self.refuse(sequence, TransmitRefusal::RadioUnavailable, true);
        }
        if context.safety_revision != self.armed_revision {
            return self.refuse(sequence, TransmitRefusal::NotAuthorized, true);
        }
        if self.tune.is_some() {
            return self.refuse(sequence, TransmitRefusal::Busy, true);
        }
        let now = self.hardware.now_utc_ms();
        if let Err(e) = plan_start(
            request.mode,
            now,
            self.hardware.clock(),
            request.period_start_utc_ms,
            SAMPLE_RATE_HZ,
        ) {
            return self.refuse(sequence, schedule_refusal(e), true);
        }
        let same_period = |job: &Job| {
            job.prepared.request.period_start_utc_ms == request.period_start_utc_ms
                && job.prepared.request.mode == request.mode
        };
        // Replacement window: only while the audio of the pending request has not started.
        let slot = match &self.current {
            Some(job) if job.audio_start_utc_ms.is_some() && same_period(job) => {
                return self.refuse(sequence, TransmitRefusal::AudioStarted, false);
            }
            Some(job) if job.audio_start_utc_ms.is_some() => 1,
            Some(job) if job.keyed && !same_period(job) => {
                return self.refuse(sequence, TransmitRefusal::Busy, true);
            }
            _ => 0,
        };
        let prepared = match prepare(&request) {
            Ok(p) => p,
            Err(refusal) => return self.refuse(sequence, refusal, true),
        };
        self.refusal = None;
        if slot == 1 {
            if let Some(old) = self.next.replace(prepared) {
                self.emit(old.request.request_sequence, OutcomeKind::Replaced);
            }
        } else if let Some(job) = &mut self.current {
            let old = std::mem::replace(&mut job.prepared, prepared);
            self.emit(old.request.request_sequence, OutcomeKind::Replaced);
        } else {
            self.current = Some(Job {
                prepared,
                keyed: false,
                audio_start_utc_ms: None,
                release_by_mono_ms: None,
            });
        }
        self.emit(sequence, OutcomeKind::Accepted)
    }
    /// Priority stop of a transmission or Tune: stop audio, release PTT with readback,
    /// cancel every request and disarm (DisarmCause halt). Idempotent.
    pub fn halt(&mut self) -> HaltState {
        let active = self.current.as_ref().is_some_and(|j| j.keyed)
            || self.tune.is_some()
            || self.ptt != PttState::Released;
        self.hardware.stop_audio();
        let released = if active { self.release() } else { true };
        self.tune = None;
        if let Some(job) = self.current.take() {
            self.emit(job.prepared.request.request_sequence, OutcomeKind::Halted);
        }
        if let Some(next) = self.next.take() {
            self.emit(next.request.request_sequence, OutcomeKind::Halted);
        }
        self.disarm_with(DisarmCause::Halt);
        self.halt_state = if !active {
            HaltState::Idle
        } else if released {
            HaltState::Stopped
        } else {
            HaltState::Pending
        };
        self.halt_state
    }
    /// Releases PTT with readback; on failure the switch is indeterminate.
    fn release(&mut self) -> bool {
        match self.hardware.ptt(false) {
            Ok(()) => {
                self.ptt = PttState::Released;
                true
            }
            Err(_) => {
                self.ptt = PttState::Indeterminate;
                false
            }
        }
    }
    fn fail_current(&mut self, failure: TransmitFailure, cause: DisarmCause) {
        self.hardware.stop_audio();
        let keyed =
            self.current.as_ref().is_some_and(|j| j.keyed) || self.ptt != PttState::Released;
        if keyed {
            self.release();
        }
        if let Some(job) = self.current.take() {
            self.emit_full(
                job.prepared.request.request_sequence,
                OutcomeKind::Failed,
                None,
                Some(failure),
                job.audio_start_utc_ms,
            );
        }
        self.disarm_with(cause);
        self.cancel_unstarted(OutcomeKind::Refused, Some(TransmitRefusal::NotArmed));
    }
    fn refuse_current(&mut self, refusal: TransmitRefusal) {
        self.hardware.stop_audio();
        if self.current.as_ref().is_some_and(|j| j.keyed) {
            self.release();
        }
        if let Some(job) = self.current.take() {
            self.refusal = Some(refusal);
            self.emit_full(
                job.prepared.request.request_sequence,
                OutcomeKind::Refused,
                Some(refusal),
                None,
                None,
            );
        }
        self.disarm_with(DisarmCause::Refused);
        self.cancel_unstarted(OutcomeKind::Refused, Some(TransmitRefusal::NotArmed));
    }
    /// Starts an unmodulated Tune tone at `hz` (armed, nothing pending).
    pub fn set_tune(&mut self, enable: bool, hz: u32) -> Result<(), TransmitRefusal> {
        if !enable {
            if self.tune.take().is_some() {
                self.hardware.stop_audio();
                self.release();
            }
            return Ok(());
        }
        let context = self.hardware.context();
        let refusal = if context.capability == Capability::Unsupported {
            Some(TransmitRefusal::TransmitUnsupported)
        } else if self.arm != ArmState::Armed {
            Some(TransmitRefusal::NotArmed)
        } else if context.capability != Capability::Available {
            Some(TransmitRefusal::RadioUnavailable)
        } else if context.safety_revision != self.armed_revision {
            Some(TransmitRefusal::NotAuthorized)
        } else if self.current.is_some() || self.tune.is_some() {
            Some(TransmitRefusal::Busy)
        } else if !(200..=2950).contains(&hz) {
            Some(TransmitRefusal::FrequencyOutOfRange)
        } else {
            None
        };
        if let Some(refusal) = refusal {
            self.refusal = Some(refusal);
            return Err(refusal);
        }
        if self.hardware.open_audio().is_err() || self.aborted() {
            self.hardware.stop_audio();
            self.refusal = Some(TransmitRefusal::Busy);
            return Err(TransmitRefusal::Busy);
        }
        self.ever_keyed = true;
        if let Err(e) = self.hardware.ptt(true) {
            self.hardware.stop_audio();
            self.release();
            let _ = e;
            self.refusal = Some(TransmitRefusal::RadioUnavailable);
            return Err(TransmitRefusal::RadioUnavailable);
        }
        self.ptt = PttState::Keyed;
        if self
            .hardware
            .play(Program::Tone { hz: f64::from(hz) })
            .is_err()
        {
            self.hardware.stop_audio();
            self.release();
            self.refusal = Some(TransmitRefusal::Busy);
            return Err(TransmitRefusal::Busy);
        }
        let now = self.hardware.now_utc_ms();
        self.tune = Some(Tune {
            hz: f64::from(hz),
            until_utc_ms: now + i64::from(self.tune_seconds) * 1000,
            keyed: true,
        });
        self.refusal = None;
        Ok(())
    }
    /// One scheduling step at the injected clock. Called at least every few milliseconds.
    pub fn tick(&mut self) {
        let now = self.hardware.now_utc_ms();
        let context = self.hardware.context();
        // Startup safety release: the first fresh transmit-state readback of this boot
        // that shows TX, before this boot ever keyed, gets exactly one off-only release.
        if self.startup_release == StartupRelease::Pending
            && let Some(transmitting) = context.radio_transmitting
        {
            self.startup_release = if transmitting && !self.ever_keyed {
                if self.hardware.ptt(false).is_ok() {
                    StartupRelease::Released
                } else {
                    // Exactly one attempt; Arm stays refused for this boot.
                    StartupRelease::Failed
                }
            } else {
                StartupRelease::NotNeeded
            };
        }
        // Tune: limit, device loss, authority.
        if let Some(tune) = &self.tune {
            let _ = (tune.hz, tune.keyed);
            let lost = context.capability != Capability::Available
                || context.safety_revision != self.armed_revision;
            let audio = self.hardware.poll_audio();
            if now >= tune.until_utc_ms || lost || matches!(audio, AudioPoll::Failed(_)) {
                self.tune = None;
                self.hardware.stop_audio();
                self.release();
                if lost || matches!(audio, AudioPoll::Failed(_)) {
                    self.disarm_with(DisarmCause::DeviceLost);
                }
            }
        }
        // Tx watchdog.
        if self.arm == ArmState::Armed
            && self
                .watchdog_from
                .is_some_and(|from| now - from >= i64::from(self.tx_minutes) * 60_000)
        {
            // halt() records the true halt state (pending if the release failed).
            self.halt();
            self.cause = DisarmCause::TxWatchdog;
            self.tx_expired = true;
            return;
        }
        // Authority/radio loss while armed.
        if self.arm == ArmState::Armed {
            if context.safety_revision != self.armed_revision
                && context.capability != Capability::Unsupported
            {
                if self.current.as_ref().is_some_and(|j| j.keyed) {
                    self.fail_current(
                        TransmitFailure::AuthorityChanged,
                        DisarmCause::AuthorityChanged,
                    );
                } else {
                    self.disarm(DisarmCause::AuthorityChanged);
                }
                return;
            }
            if context.capability != Capability::Available {
                if self.current.as_ref().is_some_and(|j| j.keyed) {
                    self.fail_current(TransmitFailure::RadioLost, DisarmCause::DeviceLost);
                } else {
                    self.disarm(DisarmCause::DeviceLost);
                }
                return;
            }
        } else if context.capability != Capability::Available
            && self.current.as_ref().is_some_and(|j| j.keyed)
        {
            self.fail_current(TransmitFailure::RadioLost, DisarmCause::DeviceLost);
            return;
        }
        let Some(job) = &self.current else {
            return;
        };
        let request = &job.prepared.request;
        let mode = request.mode;
        let period = request.period_start_utc_ms;
        let sequence = request.request_sequence;
        if job.audio_start_utc_ms.is_none() {
            if now < period {
                return;
            }
            if !job.keyed {
                // Key at the period start (audio delay before the first sample), or at
                // once for a late admitted start; output is opened before PTT.
                if let Err(e) = plan_start(mode, now, self.hardware.clock(), period, SAMPLE_RATE_HZ)
                {
                    self.refuse_current(schedule_refusal(e));
                    return;
                }
                if self.aborted() {
                    return;
                }
                if self.hardware.open_audio().is_err() {
                    if self.aborted() {
                        self.hardware.stop_audio();
                        return;
                    }
                    self.fail_current(TransmitFailure::AudioUnavailable, DisarmCause::DeviceLost);
                    return;
                }
                // A halt received while the output opened: never key.
                if self.aborted() {
                    self.hardware.stop_audio();
                    return;
                }
                self.ever_keyed = true;
                if let Err(e) = self.hardware.ptt(true) {
                    self.ptt = PttState::Indeterminate;
                    let cause = match e {
                        PttError::Unavailable | PttError::Timeout | PttError::Indeterminate => {
                            DisarmCause::DeviceLost
                        }
                        _ => DisarmCause::Failed,
                    };
                    if e == PttError::Busy {
                        // No bytes were written: nothing was keyed.
                        self.ptt = PttState::Released;
                        self.hardware.stop_audio();
                        self.refuse_current(TransmitRefusal::Busy);
                        return;
                    }
                    self.fail_current(ptt_failure(e), cause);
                    return;
                }
                self.ptt = PttState::Keyed;
                if let Some(job) = &mut self.current {
                    job.keyed = true;
                }
                return;
            }
            if now < period + audio_delay_ms(mode) {
                return;
            }
            // Audio starts now at the sample planned for now (late start skips the
            // elapsed prefix, never replays it).
            let start = match plan_start(mode, now, self.hardware.clock(), period, SAMPLE_RATE_HZ) {
                Ok(s) => s,
                Err(e) => {
                    self.refuse_current(schedule_refusal(e));
                    return;
                }
            };
            let samples = job.prepared.samples.clone();
            let job_len = samples.len();
            let text = job.prepared.text.clone();
            if let Err(e) = self.hardware.play(Program::Waveform {
                samples,
                skip: start.skipped_samples as usize,
            }) {
                let failure = match e {
                    AudioError::Unavailable => TransmitFailure::AudioUnavailable,
                    AudioError::DeviceLost => TransmitFailure::AudioDeviceLost,
                };
                self.fail_current(failure, DisarmCause::DeviceLost);
                return;
            }
            if self.last_text.as_deref() != Some(text.as_str()) && self.arm == ArmState::Armed {
                self.watchdog_from = Some(now);
            }
            self.last_text = Some(text);
            self.last_period = Some(period);
            let remaining = (job_len - start.skipped_samples as usize) as i64 * 1000
                / i64::from(SAMPLE_RATE_HZ);
            if let Some(job) = &mut self.current {
                job.audio_start_utc_ms = Some(now);
                job.release_by_mono_ms =
                    Some(self.hardware.monotonic_ms() + remaining + RELEASE_MARGIN_MS);
            }
            self.emit_full(sequence, OutcomeKind::Started, None, None, Some(now));
            return;
        }
        // Device-independent bound: PTT is released at the deadline whatever the device
        // reports (stalled, silent, never finishing).
        if self
            .current
            .as_ref()
            .and_then(|j| j.release_by_mono_ms)
            .is_some_and(|by| self.hardware.monotonic_ms() >= by)
        {
            self.fail_current(TransmitFailure::AudioStalled, DisarmCause::DeviceLost);
            return;
        }
        match self.hardware.poll_audio() {
            AudioPoll::Playing | AudioPoll::Idle => {}
            AudioPoll::Failed(_) => {
                self.fail_current(TransmitFailure::AudioDeviceLost, DisarmCause::DeviceLost);
            }
            AudioPoll::Finished => {
                self.hardware.stop_audio();
                let start = self.current.as_ref().and_then(|j| j.audio_start_utc_ms);
                if self.release() {
                    self.current = None;
                    self.emit_full(sequence, OutcomeKind::Completed, None, None, start);
                    if let Some(next) = self.next.take() {
                        self.current = Some(Job {
                            prepared: next,
                            keyed: false,
                            audio_start_utc_ms: None,
                            release_by_mono_ms: None,
                        });
                    }
                } else {
                    self.current = None;
                    self.emit_full(
                        sequence,
                        OutcomeKind::Failed,
                        None,
                        Some(TransmitFailure::PttIndeterminate),
                        start,
                    );
                    self.disarm_with(DisarmCause::DeviceLost);
                    self.cancel_unstarted(OutcomeKind::Refused, Some(TransmitRefusal::NotArmed));
                }
            }
        }
    }
    /// Off-only recovery of an indeterminate switch (never keys): one release attempt.
    pub fn recover_release(&mut self) -> bool {
        if self.ptt != PttState::Indeterminate || self.current.is_some() || self.tune.is_some() {
            return false;
        }
        if self.hardware.context().capability != Capability::Available {
            return false;
        }
        self.release()
    }
    /// Fail closed after an owner fault: stop audio, one release attempt, drop every
    /// request, disarm (failed) and refuse Arm for the rest of the boot.
    pub fn fail_closed(&mut self) -> HaltState {
        self.faulted = true;
        let keyed = self.current.as_ref().is_some_and(|j| j.keyed)
            || self.tune.is_some()
            || self.ptt != PttState::Released;
        let _ =
            std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| self.hardware.stop_audio()));
        let released = !keyed
            || std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                self.hardware.ptt(false).is_ok()
            }))
            .unwrap_or(false);
        self.ptt = if released {
            PttState::Released
        } else {
            PttState::Indeterminate
        };
        self.tune = None;
        if let Some(job) = self.current.take() {
            self.emit_full(
                job.prepared.request.request_sequence,
                OutcomeKind::Failed,
                None,
                Some(TransmitFailure::OwnerFault),
                job.audio_start_utc_ms,
            );
        }
        if let Some(next) = self.next.take() {
            self.emit_full(
                next.request.request_sequence,
                OutcomeKind::Failed,
                None,
                Some(TransmitFailure::OwnerFault),
                None,
            );
        }
        self.disarm_with(DisarmCause::Failed);
        self.halt_state = if !keyed {
            HaltState::Idle
        } else if released {
            HaltState::Stopped
        } else {
            HaltState::Pending
        };
        self.halt_state
    }
    pub fn view(&self) -> View {
        let now = self.hardware.now_utc_ms();
        let context = self.hardware.context();
        let pending_sequence = self
            .next
            .as_ref()
            .map(|p| p.request.request_sequence)
            .or_else(|| {
                self.current
                    .as_ref()
                    .filter(|j| j.audio_start_utc_ms.is_none())
                    .map(|j| j.prepared.request.request_sequence)
            });
        let tx_remaining_minutes = match (self.arm, self.watchdog_from) {
            (ArmState::Armed, Some(from)) => {
                let left = i64::from(self.tx_minutes) * 60_000 - (now - from);
                u32::try_from((left.max(0) + 59_999) / 60_000).unwrap_or(0)
            }
            _ => 0,
        };
        View {
            capability: context.capability,
            arm_state: self.arm,
            last_disarm_cause: self.cause,
            tune: self.tune.is_some(),
            pending_sequence,
            last_text: self.last_text.clone(),
            last_period_utc_ms: self.last_period,
            halt_state: self.halt_state,
            refusal: self.refusal,
            ptt: self.ptt,
            transmitting: self
                .current
                .as_ref()
                .is_some_and(|j| j.audio_start_utc_ms.is_some())
                || self.tune.is_some(),
            clock: self.hardware.clock(),
            clock_measurement: self.hardware.clock_measurement(),
            tx_minutes: self.tx_minutes,
            tx_remaining_minutes,
            tx_expired: self.tx_expired,
            tune_seconds: self.tune_seconds,
            tune_remaining_seconds: self.tune.as_ref().map_or(0, |t| {
                u32::try_from(((t.until_utc_ms - now).max(0) + 999) / 1000).unwrap_or(0)
            }),
            outcomes: self.outcomes.iter().cloned().collect(),
            startup_release: self.startup_release,
        }
    }
    /// Outcomes published after `after` (contact consumer cursor).
    pub fn outcomes_since(&self, after: u64) -> Vec<Outcome> {
        self.outcomes
            .iter()
            .filter(|o| o.outcome_sequence > after)
            .cloned()
            .collect()
    }
}

/// Lock-free priority halt signal shared between callers and the transmit thread.
struct HaltSignal {
    requested: Arc<AtomicBool>,
    generation: Mutex<(u64, u64, HaltState)>,
    done: Condvar,
}

/// The station's transmit owner thread. Commands lock the core; `halt` never waits for
/// the core lock: it stops audio through the hardware stopper at once and the thread
/// releases PTT before any other step.
pub struct Service<H: Hardware + 'static> {
    core: Arc<Mutex<Core<H>>>,
    halt: Arc<HaltSignal>,
    stopper: Arc<dyn Fn() + Send + Sync>,
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
    receipts: Mutex<VecDeque<(String, HaltState)>>,
}
impl<H: Hardware + 'static> Service<H> {
    pub fn start(hardware: H) -> std::io::Result<Self> {
        let stopper = hardware.audio_stopper();
        let halt = Arc::new(HaltSignal {
            requested: Arc::new(AtomicBool::new(false)),
            generation: Mutex::new((0, 0, HaltState::Idle)),
            done: Condvar::new(),
        });
        let mut owner = Core::new(hardware);
        owner.attach_abort(halt.requested.clone());
        let core = Arc::new(Mutex::new(owner));
        let stop = Arc::new(AtomicBool::new(false));
        let (c, h, s) = (core.clone(), halt.clone(), stop.clone());
        let thread = thread::Builder::new()
            .name("transmit".into())
            .spawn(move || {
                let lock = || c.lock().unwrap_or_else(|p| p.into_inner());
                let mut faulted = false;
                while !s.load(Ordering::Acquire) {
                    if h.requested.load(Ordering::Acquire) {
                        let target = h.generation.lock().map(|g| g.0).unwrap_or(0);
                        let mut core = lock();
                        let state = if faulted {
                            core.fail_closed()
                        } else {
                            match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                                core.halt()
                            })) {
                                Ok(state) => state,
                                Err(_) => {
                                    faulted = true;
                                    core.fail_closed()
                                }
                            }
                        };
                        drop(core);
                        h.requested.store(false, Ordering::Release);
                        if let Ok(mut g) = h.generation.lock() {
                            g.1 = target;
                            g.2 = state;
                        }
                        h.done.notify_all();
                        continue;
                    }
                    if !faulted {
                        let mut core = lock();
                        let stepped =
                            std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                                core.tick();
                                if core.ptt == PttState::Indeterminate {
                                    core.recover_release();
                                }
                            }));
                        if stepped.is_err() {
                            // A panicking owner fails closed and stays faulted.
                            faulted = true;
                            core.fail_closed();
                        }
                    }
                    thread::sleep(Duration::from_millis(2));
                }
                // Shutdown never leaves TX active.
                let mut core = lock();
                if std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| core.halt())).is_err() {
                    core.fail_closed();
                }
            })?;
        Ok(Self {
            core,
            halt,
            stopper,
            stop,
            thread: Some(thread),
            receipts: Mutex::new(VecDeque::new()),
        })
    }
    pub fn with<R>(&self, f: impl FnOnce(&mut Core<H>) -> R) -> R {
        let mut core = self.core.lock().unwrap_or_else(|p| p.into_inner());
        f(&mut core)
    }
    pub fn view(&self) -> View {
        self.with(|c| c.view())
    }
    /// HaltTransmit. Returns the receipt halt_state; a repeated command_id returns the
    /// same receipt. Waits at most HALT_BOUND_MS for the confirmed stop.
    pub fn halt(&self, command_id: &str) -> HaltState {
        if let Ok(receipts) = self.receipts.lock()
            && let Some((_, state)) = receipts.iter().find(|(id, _)| id == command_id)
        {
            return *state;
        }
        (self.stopper)();
        let target = {
            let mut g = self
                .halt
                .generation
                .lock()
                .unwrap_or_else(|p| p.into_inner());
            g.0 += 1;
            g.0
        };
        self.halt.requested.store(true, Ordering::Release);
        let deadline = Instant::now() + Duration::from_millis(HALT_BOUND_MS);
        let mut g = self
            .halt
            .generation
            .lock()
            .unwrap_or_else(|p| p.into_inner());
        while g.1 < target {
            let left = deadline.saturating_duration_since(Instant::now());
            if left.is_zero() {
                break;
            }
            g = self
                .halt
                .done
                .wait_timeout(g, left)
                .map(|(g, _)| g)
                .unwrap_or_else(|p| p.into_inner().0);
        }
        let state = if g.1 >= target {
            g.2
        } else {
            HaltState::Pending
        };
        drop(g);
        if let Ok(mut receipts) = self.receipts.lock() {
            if receipts.len() == HALT_RECEIPTS {
                receipts.pop_front();
            }
            receipts.push_back((command_id.to_owned(), state));
        }
        state
    }
}
impl<H: Hardware + 'static> Drop for Service<H> {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Release);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

/// Keys through the CI-V owner; a priority halt before the frame is sent aborts the
/// wait with Busy (no bytes).
pub fn actor_ptt_abortable(
    actor: &crate::radio_control::actor::Actor,
    exchange: Duration,
    abort: &AtomicBool,
) -> Result<(), PttError> {
    actor
        .ptt_abortable(true, Instant::now() + exchange, abort)
        .map_err(map_actor_error)
}
fn map_actor_error(e: crate::radio_control::Error) -> PttError {
    use crate::radio_control::Error;
    match e {
        Error::Busy => PttError::Busy,
        Error::Timeout | Error::Cancelled | Error::PartialWrite => PttError::Timeout,
        Error::Rejected => PttError::Rejected,
        Error::ReadbackMismatch => PttError::ReadbackMismatch,
        Error::Indeterminate | Error::Protocol | Error::Limit => PttError::Indeterminate,
        _ => PttError::Unavailable,
    }
}
/// PTT through the station's single CI-V owner (WstxTransmit::PttControl).
pub fn actor_ptt(
    actor: &crate::radio_control::actor::Actor,
    on: bool,
    exchange: Duration,
) -> Result<(), PttError> {
    use crate::radio_control::Error;
    actor
        .ptt(on, Instant::now() + exchange)
        .map_err(|e| match e {
            Error::Busy => PttError::Busy,
            Error::Timeout | Error::Cancelled | Error::PartialWrite => PttError::Timeout,
            Error::Rejected => PttError::Rejected,
            Error::ReadbackMismatch => PttError::ReadbackMismatch,
            Error::Indeterminate | Error::Protocol | Error::Limit => PttError::Indeterminate,
            _ => PttError::Unavailable,
        })
}

/// A station may select its hardware at runtime (devices or fixtures).
impl Hardware for Box<dyn Hardware> {
    // Every method, including those with default bodies, is forwarded.
    fn now_utc_ms(&self) -> i64 {
        (**self).now_utc_ms()
    }
    fn monotonic_ms(&self) -> i64 {
        (**self).monotonic_ms()
    }
    fn attach_abort(&mut self, abort: Arc<AtomicBool>) {
        (**self).attach_abort(abort)
    }
    fn clock(&self) -> ClockState {
        (**self).clock()
    }
    fn clock_measurement(&self) -> Option<super::clock::Measurement> {
        (**self).clock_measurement()
    }
    fn context(&self) -> Context {
        (**self).context()
    }
    fn ptt(&mut self, on: bool) -> Result<(), PttError> {
        (**self).ptt(on)
    }
    fn open_audio(&mut self) -> Result<(), AudioError> {
        (**self).open_audio()
    }
    fn play(&mut self, program: Program) -> Result<(), AudioError> {
        (**self).play(program)
    }
    fn poll_audio(&mut self) -> AudioPoll {
        (**self).poll_audio()
    }
    fn stop_audio(&mut self) {
        (**self).stop_audio()
    }
    fn audio_stopper(&self) -> Arc<dyn Fn() + Send + Sync> {
        (**self).audio_stopper()
    }
}
