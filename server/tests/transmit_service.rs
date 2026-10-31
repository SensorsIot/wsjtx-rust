#![deny(unsafe_code)]
// Proves: CL-009-03, CL-009-04; TC-008-003.
// Virtual-clock transmit owner against a recording hardware double, and the real
// CI-V actor against an emulated IC-7300 peer. No device, radio or RF.
use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicI64, Ordering},
    },
    time::{Duration, Instant},
};
use wstx_rust::decoder::Mode;
use wstx_rust::radio_control::{
    self as cat, Authority, Configuration, actor::Actor, catalogue::Catalogue, executor::Transport,
};
use wstx_rust::transmit::ClockState;
use wstx_rust::transmit::service::*;

const P: i64 = 1_800_000_000_000; // an even FT8 period (multiple of 30 s)

#[derive(Clone, Debug, PartialEq)]
enum Event {
    Open,
    Key(bool),
    Play { skip: usize, len: usize },
    Stop,
}
#[derive(Default)]
struct Bench {
    now: AtomicI64,
    clock: Mutex<Option<ClockState>>,
    capability: Mutex<Option<Capability>>,
    revision: Mutex<Option<u64>>,
    log: Mutex<Vec<(i64, Event)>>,
    audio: Mutex<Option<AudioPoll>>,
    key_error: Mutex<Option<PttError>>,
    unkey_error: Mutex<Option<PttError>>,
    open_error: AtomicBool,
    stopped_by_handle: AtomicBool,
    /// Wall-clock delay of each PTT exchange (Service real-time tests).
    ptt_delay_ms: AtomicI64,
    radio_tx: Mutex<Option<bool>>,
    /// Wall-clock delay inside open_audio (halt-during-open tests).
    open_delay_ms: AtomicI64,
    /// poll_audio panics (owner fault tests).
    panic_poll: AtomicBool,
}
#[derive(Clone)]
struct Fake(Arc<Bench>);
impl Fake {
    fn new() -> Self {
        let b = Bench::default();
        b.now.store(P - 20_000, Ordering::SeqCst);
        *b.capability.lock().unwrap() = Some(Capability::Available);
        *b.revision.lock().unwrap() = Some(7);
        *b.clock.lock().unwrap() = Some(ClockState::Synchronized);
        Self(Arc::new(b))
    }
    fn at(&self, t: i64) {
        self.0.now.store(t, Ordering::SeqCst);
    }
    fn log(&self) -> Vec<(i64, Event)> {
        self.0.log.lock().unwrap().clone()
    }
    fn keys(&self) -> Vec<(i64, bool)> {
        self.log()
            .into_iter()
            .filter_map(|(t, e)| {
                if let Event::Key(on) = e {
                    Some((t, on))
                } else {
                    None
                }
            })
            .collect()
    }
    fn record(&self, e: Event) {
        let t = self.0.now.load(Ordering::SeqCst);
        self.0.log.lock().unwrap().push((t, e));
    }
}
impl Hardware for Fake {
    fn now_utc_ms(&self) -> i64 {
        self.0.now.load(Ordering::SeqCst)
    }
    fn clock(&self) -> ClockState {
        self.0.clock.lock().unwrap().unwrap()
    }
    fn context(&self) -> Context {
        Context {
            capability: self.0.capability.lock().unwrap().unwrap(),
            safety_revision: *self.0.revision.lock().unwrap(),
            radio_transmitting: *self.0.radio_tx.lock().unwrap(),
        }
    }
    fn ptt(&mut self, on: bool) -> Result<(), PttError> {
        let delay = self.0.ptt_delay_ms.load(Ordering::SeqCst);
        if delay > 0 {
            std::thread::sleep(Duration::from_millis(delay as u64));
        }
        self.record(Event::Key(on));
        let error = if on {
            &self.0.key_error
        } else {
            &self.0.unkey_error
        };
        match *error.lock().unwrap() {
            Some(e) => Err(e),
            None => Ok(()),
        }
    }
    fn open_audio(&mut self) -> Result<(), AudioError> {
        self.record(Event::Open);
        let delay = self.0.open_delay_ms.load(Ordering::SeqCst);
        if delay > 0 {
            std::thread::sleep(Duration::from_millis(delay as u64));
        }
        if self.0.open_error.load(Ordering::SeqCst) {
            return Err(AudioError::Unavailable);
        }
        Ok(())
    }
    fn play(&mut self, program: Program) -> Result<(), AudioError> {
        let (skip, len) = match program {
            Program::Waveform { samples, skip } => (skip, samples.len()),
            Program::Tone { .. } => (0, 0),
        };
        self.record(Event::Play { skip, len });
        *self.0.audio.lock().unwrap() = Some(AudioPoll::Playing);
        Ok(())
    }
    fn poll_audio(&mut self) -> AudioPoll {
        if self.0.panic_poll.load(Ordering::SeqCst) {
            panic!("fixture: output poll panics");
        }
        self.0.audio.lock().unwrap().unwrap_or(AudioPoll::Idle)
    }
    fn stop_audio(&mut self) {
        *self.0.audio.lock().unwrap() = None;
        self.record(Event::Stop);
    }
    fn audio_stopper(&self) -> Arc<dyn Fn() + Send + Sync> {
        let b = self.0.clone();
        Arc::new(move || b.stopped_by_handle.store(true, Ordering::SeqCst))
    }
}
fn request(seq: u64, period: i64, text: &str) -> Request {
    Request {
        contact_id: None,
        request_sequence: seq,
        mode: Mode::Ft8,
        period_start_utc_ms: period,
        message_text: text.into(),
        tx_offset_hz: 1500,
    }
}
fn kinds(core: &Core<Fake>) -> Vec<(u64, OutcomeKind)> {
    core.view()
        .outcomes
        .iter()
        .map(|o| (o.request_sequence, o.kind))
        .collect()
}
/// Ticks every millisecond from the current time to `until`.
fn run(core: &mut Core<Fake>, f: &Fake, until: i64) {
    let mut t = f.now_utc_ms();
    while t <= until {
        f.at(t);
        core.tick();
        t += 1;
    }
}

#[test]
fn nothing_is_keyed_or_played_without_explicit_armed_authority() {
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    let v = core.view();
    assert_eq!(
        (v.arm_state, v.last_disarm_cause),
        (ArmState::Disarmed, DisarmCause::Startup)
    );
    let o = core.submit(request(1, P, "CQ HB9BLA JN47"));
    assert_eq!(o.refusal, Some(TransmitRefusal::NotArmed));
    run(&mut core, &f, P + 15_000);
    assert!(f.log().is_empty(), "disarmed station emitted {:?}", f.log());
    // Receive-only configuration is not transmit capability; stale revision is not authority.
    *f.0.capability.lock().unwrap() = Some(Capability::Unsupported);
    assert_eq!(core.arm(7), Err(TransmitRefusal::TransmitUnsupported));
    *f.0.capability.lock().unwrap() = Some(Capability::Unavailable);
    assert_eq!(core.arm(7), Err(TransmitRefusal::RadioUnavailable));
    *f.0.capability.lock().unwrap() = Some(Capability::Available);
    assert_eq!(core.arm(6), Err(TransmitRefusal::NotAuthorized));
    assert_eq!(core.view().arm_state, ArmState::Disarmed);
    assert!(core.set_tune(true, 1500).is_err());
    assert!(f.log().is_empty());
}

#[test]
fn ptt_is_keyed_at_period_start_with_readback_before_audio_at_planned_sample() {
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    f.at(P - 3_000);
    core.arm(7).unwrap();
    let o = core.submit(request(1, P, "CQ HB9BLA JN47"));
    assert_eq!(o.kind, OutcomeKind::Accepted);
    run(&mut core, &f, P - 1);
    assert!(f.log().is_empty(), "nothing before the period start");
    run(&mut core, &f, P + 499);
    assert_eq!(f.log(), vec![(P, Event::Open), (P, Event::Key(true))]);
    run(&mut core, &f, P + 500);
    assert_eq!(
        f.log()[2],
        (
            P + 500,
            Event::Play {
                skip: 0,
                len: 606_720
            }
        )
    );
    let started = core.view().outcomes.last().cloned().unwrap();
    assert_eq!(
        (started.kind, started.audio_start_utc_ms),
        (OutcomeKind::Started, Some(P + 500))
    );
    assert!(core.view().transmitting);
    assert_eq!(core.view().last_text.as_deref(), Some("CQ HB9BLA JN47"));
    f.at(P + 13_140);
    *f.0.audio.lock().unwrap() = Some(AudioPoll::Finished);
    core.tick();
    assert_eq!(f.keys(), vec![(P, true), (P + 13_140, false)]);
    assert_eq!(
        kinds(&core),
        vec![
            (1, OutcomeKind::Accepted),
            (1, OutcomeKind::Started),
            (1, OutcomeKind::Completed)
        ]
    );
    let v = core.view();
    assert_eq!(
        (v.arm_state, v.ptt, v.transmitting),
        (ArmState::Armed, PttState::Released, false)
    );
}

#[test]
fn late_start_skips_the_elapsed_prefix_and_stale_or_unsynchronized_requests_are_refused() {
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    f.at(P + 2_000);
    core.arm(7).unwrap();
    assert_eq!(
        core.submit(request(1, P, "CQ HB9BLA JN47")).kind,
        OutcomeKind::Accepted
    );
    core.tick();
    f.at(P + 2_010);
    core.tick();
    assert_eq!(
        f.log(),
        vec![
            (P + 2_000, Event::Open),
            (P + 2_000, Event::Key(true)),
            (
                P + 2_010,
                Event::Play {
                    skip: (2_010 - 500) * 48,
                    len: 606_720
                }
            )
        ]
    );
    core.halt();
    // Stale: from 75 % of the period on; never moved to a later period.
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    f.at(P + 11_250);
    core.arm(7).unwrap();
    let o = core.submit(request(1, P, "CQ HB9BLA JN47"));
    assert_eq!(o.refusal, Some(TransmitRefusal::StalePeriod));
    assert_eq!(core.view().last_disarm_cause, DisarmCause::Refused);
    run(&mut core, &f, P + 31_000);
    assert!(f.keys().is_empty());
    for (clock, refusal) in [
        (
            ClockState::Unsynchronized,
            TransmitRefusal::ClockNotSynchronized,
        ),
        (ClockState::Unknown, TransmitRefusal::ClockNotSynchronized),
    ] {
        let f = Fake::new();
        *f.0.clock.lock().unwrap() = Some(clock);
        let mut core = Core::new(f.clone());
        core.arm(7).unwrap();
        assert_eq!(
            core.submit(request(1, P, "CQ HB9BLA JN47")).refusal,
            Some(refusal)
        );
        assert_eq!(core.view().arm_state, ArmState::Disarmed);
    }
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    core.arm(7).unwrap();
    assert_eq!(
        core.submit(request(1, P + 1, "CQ")).refusal,
        Some(TransmitRefusal::MisalignedPeriod)
    );
    core.arm(7).unwrap();
    let mut r = request(2, P, "CQ HB9BLA JN47");
    r.tx_offset_hz = 2_951;
    assert_eq!(
        core.submit(r).refusal,
        Some(TransmitRefusal::FrequencyOutOfRange)
    );
    core.arm(7).unwrap();
    assert_eq!(
        core.submit(request(3, P, "CQ;X")).refusal,
        Some(TransmitRefusal::PackRefused)
    );
    core.arm(7).unwrap();
    // A duplicate (retry) changes nothing.
    assert_eq!(
        core.submit(request(3, P, "CQ HB9BLA JN47")).refusal,
        Some(TransmitRefusal::DuplicateSequence)
    );
    assert_eq!(core.view().arm_state, ArmState::Armed);
}

#[test]
fn pending_request_is_replaced_until_audio_start_then_queued_for_the_next_period() {
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    f.at(P - 2_000);
    core.arm(7).unwrap();
    core.submit(request(1, P, "CQ HB9BLA JN47"));
    assert_eq!(
        core.submit(request(2, P, "DL1ABC HB9BLA JN47")).kind,
        OutcomeKind::Accepted
    );
    assert_eq!(core.view().pending_sequence, Some(2));
    run(&mut core, &f, P + 100); // keyed
    // Still replaceable while keyed but before the first sample.
    assert_eq!(
        core.submit(request(3, P, "DL1ABC HB9BLA -10")).kind,
        OutcomeKind::Accepted
    );
    run(&mut core, &f, P + 500);
    assert_eq!(core.view().last_text.as_deref(), Some("DL1ABC HB9BLA -10"));
    let o = core.submit(request(4, P, "DL1ABC HB9BLA R-10"));
    assert_eq!(o.refusal, Some(TransmitRefusal::AudioStarted));
    assert_eq!(
        core.view().arm_state,
        ArmState::Armed,
        "audioStarted does not disarm"
    );
    assert_eq!(
        core.submit(request(5, P + 30_000, "DL1ABC HB9BLA R-10"))
            .kind,
        OutcomeKind::Accepted
    );
    assert_eq!(core.view().pending_sequence, Some(5));
    f.at(P + 13_200);
    *f.0.audio.lock().unwrap() = Some(AudioPoll::Finished);
    core.tick();
    run(&mut core, &f, P + 30_500);
    assert_eq!(core.view().last_text.as_deref(), Some("DL1ABC HB9BLA R-10"));
    assert_eq!(
        kinds(&core),
        vec![
            (1, OutcomeKind::Accepted),
            (1, OutcomeKind::Replaced),
            (2, OutcomeKind::Accepted),
            (2, OutcomeKind::Replaced),
            (3, OutcomeKind::Accepted),
            (3, OutcomeKind::Started),
            (4, OutcomeKind::Refused),
            (5, OutcomeKind::Accepted),
            (3, OutcomeKind::Completed),
            (5, OutcomeKind::Started),
        ]
    );
    assert_eq!(
        f.keys(),
        vec![(P, true), (P + 13_200, false), (P + 30_000, true)]
    );
}

#[test]
fn halt_mid_audio_stops_audio_and_releases_ptt_and_disarms() {
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    f.at(P - 1_000);
    core.arm(7).unwrap();
    core.submit(request(1, P, "CQ HB9BLA JN47"));
    run(&mut core, &f, P + 1_000);
    core.submit(request(2, P + 30_000, "CQ HB9BLA JN47"));
    run(&mut core, &f, P + 6_000);
    let before = f.log().len();
    assert_eq!(core.halt(), HaltState::Stopped);
    assert_eq!(
        &f.log()[before..],
        &[(P + 6_000, Event::Stop), (P + 6_000, Event::Key(false))]
    );
    let v = core.view();
    assert_eq!(
        (v.arm_state, v.last_disarm_cause, v.ptt),
        (ArmState::Disarmed, DisarmCause::Halt, PttState::Released)
    );
    assert!(kinds(&core).contains(&(1, OutcomeKind::Halted)));
    run(&mut core, &f, P + 45_000);
    assert_eq!(
        f.keys(),
        vec![(P, true), (P + 6_000, false)],
        "halt never replays"
    );
    assert_eq!(core.halt(), HaltState::Idle, "idempotent");
}

#[test]
fn service_halt_is_confirmed_within_the_bound_while_the_owner_is_busy() {
    let f = Fake::new();
    f.0.ptt_delay_ms.store(30, Ordering::SeqCst);
    let service = Service::start(f.clone()).unwrap();
    // Real clock: the fake time follows wall time from P.
    let origin = Instant::now();
    let clock = f.clone();
    let stop = Arc::new(AtomicBool::new(false));
    let ticking = stop.clone();
    let driver = std::thread::spawn(move || {
        while !ticking.load(Ordering::SeqCst) {
            clock.at(P - 100 + origin.elapsed().as_millis() as i64);
            std::thread::sleep(Duration::from_millis(1));
        }
    });
    std::thread::sleep(Duration::from_millis(5));
    service.with(|c| {
        c.arm(7).unwrap();
        c.submit(request(1, P, "CQ HB9BLA JN47"))
    });
    while !service.view().transmitting {
        assert!(origin.elapsed() < Duration::from_secs(3));
        std::thread::sleep(Duration::from_millis(1));
    }
    let started = Instant::now();
    let state = service.halt("00000000-0000-4000-8000-0000000000aa");
    let elapsed = started.elapsed();
    assert_eq!(state, HaltState::Stopped);
    assert!(
        elapsed < Duration::from_millis(HALT_BOUND_MS),
        "{elapsed:?}"
    );
    assert!(
        f.0.stopped_by_handle.load(Ordering::SeqCst),
        "audio stopped without the core lock"
    );
    assert_eq!(f.keys().last().map(|k| k.1), Some(false));
    assert_eq!(
        service.halt("00000000-0000-4000-8000-0000000000aa"),
        HaltState::Stopped
    );
    stop.store(true, Ordering::SeqCst);
    driver.join().unwrap();
}

#[test]
fn audio_loss_cat_loss_and_ptt_errors_release_and_disarm() {
    // Audio device lost mid-play.
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    core.arm(7).unwrap();
    core.submit(request(1, P, "CQ HB9BLA JN47"));
    run(&mut core, &f, P + 3_000);
    *f.0.audio.lock().unwrap() = Some(AudioPoll::Failed(AudioError::DeviceLost));
    core.tick();
    let last = core.view().outcomes.last().cloned().unwrap();
    assert_eq!(
        (last.kind, last.failure),
        (OutcomeKind::Failed, Some(TransmitFailure::AudioDeviceLost))
    );
    assert_eq!(f.keys().last(), Some(&(P + 3_000, false)));
    assert_eq!(core.view().last_disarm_cause, DisarmCause::DeviceLost);
    // CAT lost mid-play.
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    core.arm(7).unwrap();
    core.submit(request(1, P, "CQ HB9BLA JN47"));
    run(&mut core, &f, P + 3_000);
    *f.0.capability.lock().unwrap() = Some(Capability::Unavailable);
    *f.0.unkey_error.lock().unwrap() = Some(PttError::Unavailable);
    core.tick();
    let v = core.view();
    assert_eq!(
        v.outcomes.last().unwrap().failure,
        Some(TransmitFailure::RadioLost)
    );
    assert_eq!(
        (v.ptt, v.last_disarm_cause),
        (PttState::Indeterminate, DisarmCause::DeviceLost)
    );
    assert!(f.log().iter().any(|(_, e)| *e == Event::Stop));
    assert_eq!(
        core.arm(7),
        Err(TransmitRefusal::RadioUnavailable),
        "no re-arm while indeterminate"
    );
    // Reconnect: off-only recovery, never a key.
    *f.0.capability.lock().unwrap() = Some(Capability::Available);
    *f.0.unkey_error.lock().unwrap() = None;
    assert!(core.recover_release());
    assert_eq!(core.view().ptt, PttState::Released);
    assert_eq!(f.keys().iter().filter(|k| k.1).count(), 1);
    // CAT timeout while keying: audio never starts, release is attempted.
    let f = Fake::new();
    *f.0.key_error.lock().unwrap() = Some(PttError::Timeout);
    let mut core = Core::new(f.clone());
    core.arm(7).unwrap();
    core.submit(request(1, P, "CQ HB9BLA JN47"));
    run(&mut core, &f, P + 1_000);
    assert!(!f.log().iter().any(|(_, e)| matches!(e, Event::Play { .. })));
    assert_eq!(f.keys(), vec![(P, true), (P, false)]);
    assert_eq!(
        core.view().outcomes.last().unwrap().failure,
        Some(TransmitFailure::PttTimeout)
    );
    assert_eq!(core.view().arm_state, ArmState::Disarmed);
    // Output device unavailable: PTT is never keyed.
    let f = Fake::new();
    f.0.open_error.store(true, Ordering::SeqCst);
    let mut core = Core::new(f.clone());
    core.arm(7).unwrap();
    core.submit(request(1, P, "CQ HB9BLA JN47"));
    run(&mut core, &f, P + 1_000);
    assert!(f.keys().is_empty());
    assert_eq!(
        core.view().outcomes.last().unwrap().failure,
        Some(TransmitFailure::AudioUnavailable)
    );
    // Safety revision change (profile/control edit) while armed disarms.
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    core.arm(7).unwrap();
    *f.0.revision.lock().unwrap() = Some(8);
    core.tick();
    assert_eq!(core.view().last_disarm_cause, DisarmCause::AuthorityChanged);
}

#[test]
fn restart_never_resumes_an_armed_station_or_its_request() {
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    core.arm(7).unwrap();
    core.submit(request(1, P, "CQ HB9BLA JN47"));
    drop(core);
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    run(&mut core, &f, P + 15_000);
    let v = core.view();
    assert_eq!(
        (v.arm_state, v.last_disarm_cause, v.pending_sequence),
        (ArmState::Disarmed, DisarmCause::Startup, None)
    );
    assert!(f.log().is_empty());
}

#[test]
fn tx_watchdog_expiry_halts_and_disarms_and_tune_ends_at_its_limit() {
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    core.set_watchdogs(1, 2).unwrap();
    assert!(core.set_watchdogs(0, 90).is_err() && core.set_watchdogs(100, 90).is_err());
    assert!(core.set_watchdogs(6, 0).is_err() && core.set_watchdogs(6, 301).is_err());
    let t0 = P - 20_000;
    core.arm(7).unwrap();
    assert_eq!(core.view().tx_remaining_minutes, 1);
    core.submit(request(1, P, "CQ HB9BLA JN47"));
    run(&mut core, &f, P + 13_000);
    *f.0.audio.lock().unwrap() = Some(AudioPoll::Finished);
    run(&mut core, &f, t0 + 59_999);
    assert_eq!(
        core.view().arm_state,
        ArmState::Armed,
        "changed text at P+500 reset the count"
    );
    f.at(P + 500 + 59_999);
    core.tick();
    assert_eq!(core.view().arm_state, ArmState::Armed);
    f.at(P + 500 + 60_000);
    core.tick();
    let v = core.view();
    assert_eq!(
        (v.arm_state, v.last_disarm_cause, v.tx_expired),
        (ArmState::Disarmed, DisarmCause::TxWatchdog, true)
    );
    assert_eq!(f.keys().last().map(|k| k.1), Some(false));
    // Tune: armed, 2 s limit, released through PTT at expiry.
    core.arm(7).unwrap();
    let t = f.now_utc_ms();
    core.set_tune(true, 1500).unwrap();
    assert!(core.view().tune);
    f.at(t + 1_999);
    core.tick();
    assert!(core.view().tune);
    f.at(t + 2_000);
    core.tick();
    assert!(!core.view().tune);
    assert_eq!(f.keys().last(), Some(&(t + 2_000, false)));
    core.set_tune(true, 1500).unwrap();
    assert_eq!(core.halt(), HaltState::Stopped);
    assert!(!core.view().tune);
}

// ---------------------------------------------------------------- emulated IC-7300
#[derive(Default)]
struct Radio {
    transmitting: bool,
    writes: Vec<(Instant, Vec<u8>)>,
    pending: Vec<u8>,
    /// Ignore the next PTT setter (timeout).
    mute_ptt: bool,
}
struct Peer(Arc<Mutex<Radio>>);
impl Transport for Peer {
    fn configure(&mut self, _: u32) -> cat::Result<()> {
        Ok(())
    }
    fn write(&mut self, bytes: &[u8], _: Instant, _: &AtomicBool) -> cat::Result<usize> {
        let mut r = self.0.lock().unwrap();
        r.writes.push((Instant::now(), bytes.to_vec()));
        let body = &bytes[4..bytes.len() - 1];
        let reply = |data: &[u8]| [&[0xfe, 0xfe, 0xe0, 0x94][..], data, &[0xfd]].concat();
        let answer = match body {
            [3] => reply(&[3, 0, 0x40, 7, 0x14, 0]),
            [4] => reply(&[4, 1, 1]),
            [0x1a, 6] => reply(&[0x1a, 6, 1, 1]),
            [0x0f] => reply(&[0x0f, 0]),
            [0x1c, 0] => reply(&[0x1c, 0, u8::from(r.transmitting)]),
            [0x1c, 0, x] if *x <= 1 => {
                if r.mute_ptt {
                    r.mute_ptt = false;
                    Vec::new()
                } else {
                    r.transmitting = *x == 1;
                    reply(&[0xfb])
                }
            }
            _ => reply(&[0xfa]),
        };
        r.pending.extend(answer);
        Ok(bytes.len())
    }
    fn read(&mut self, out: &mut [u8], deadline: Instant, _: &AtomicBool) -> cat::Result<usize> {
        loop {
            {
                let mut r = self.0.lock().unwrap();
                if !r.pending.is_empty() {
                    let n = r.pending.len().min(out.len());
                    out[..n].copy_from_slice(&r.pending[..n]);
                    r.pending.drain(..n);
                    return Ok(n);
                }
            }
            if Instant::now() >= deadline {
                return Err(cat::Error::Timeout);
            }
            std::thread::sleep(Duration::from_millis(1));
        }
    }
    fn quiet(&mut self, _: Instant, _: &AtomicBool) -> cat::Result<()> {
        Ok(())
    }
    fn close(&mut self) -> cat::Result<()> {
        Ok(())
    }
}
fn radio() -> (Arc<Actor>, Arc<Mutex<Radio>>) {
    let state = Arc::new(Mutex::new(Radio::default()));
    let owned = state.clone();
    let actor = Actor::begin(
        Configuration::parse("COM3").unwrap(),
        Authority {
            profile_id: "p".into(),
            boot_id: "b".into(),
            profile_revision: 0,
            resource_id: "emulated".into(),
            connection_generation: 1,
        },
        Catalogue::builtin().unwrap(),
        move |_, _| Ok(Peer(owned)),
    )
    .unwrap();
    let start = Instant::now();
    while actor.snapshot().unwrap().state != cat::State::Ready {
        assert!(start.elapsed() < Duration::from_secs(5));
        std::thread::sleep(Duration::from_millis(1));
    }
    (Arc::new(actor), state)
}
fn ptt_frames(r: &Radio) -> Vec<Vec<u8>> {
    r.writes
        .iter()
        .filter(|(_, w)| w.len() > 5 && w[4] == 0x1c)
        .map(|(_, w)| w.clone())
        .collect()
}
const KEY: &[u8] = &[0xfe, 0xfe, 0x94, 0xe0, 0x1c, 0, 1, 0xfd];
const UNKEY: &[u8] = &[0xfe, 0xfe, 0x94, 0xe0, 0x1c, 0, 0, 0xfd];
const READ: &[u8] = &[0xfe, 0xfe, 0x94, 0xe0, 0x1c, 0, 0xfd];

#[test]
fn ci_v_ptt_bytes_readback_and_hold_exclude_polling() {
    let (actor, state) = radio();
    // Automatic polling alone (the read-only lifecycle path) never writes a setter.
    std::thread::sleep(Duration::from_millis(1_300));
    assert!(
        state
            .lock()
            .unwrap()
            .writes
            .iter()
            .all(|(_, w)| w.len() <= 7),
        "polling wrote a setter"
    );
    actor_ptt(&actor, true, Duration::from_secs(1)).unwrap();
    assert!(state.lock().unwrap().transmitting);
    let keyed_at = Instant::now();
    std::thread::sleep(Duration::from_millis(1_500));
    actor_ptt(&actor, false, Duration::from_secs(1)).unwrap();
    let r = state.lock().unwrap();
    assert!(!r.transmitting);
    let frames = ptt_frames(&r);
    let tail = &frames[frames.len() - 4..];
    assert_eq!(
        tail,
        &[KEY.to_vec(), READ.to_vec(), UNKEY.to_vec(), READ.to_vec()]
    );
    let during = r
        .writes
        .iter()
        .filter(|(t, w)| *t > keyed_at && w != UNKEY && w != READ)
        .count();
    assert_eq!(
        during, 0,
        "no poll or operation while the transmit hold is held"
    );
    drop(r);
    assert!(!actor.ptt_indeterminate());
}

#[test]
fn closing_a_keyed_connection_sends_one_off_only_switch_and_timeouts_close() {
    let (actor, state) = radio();
    actor_ptt(&actor, true, Duration::from_secs(1)).unwrap();
    actor.request_close();
    let start = Instant::now();
    while !actor.close_complete() {
        assert!(start.elapsed() < Duration::from_secs(2));
        std::thread::sleep(Duration::from_millis(1));
    }
    let r = state.lock().unwrap();
    assert!(!r.transmitting);
    assert_eq!(ptt_frames(&r).iter().filter(|w| *w == UNKEY).count(), 1);
    drop(r);
    // A key whose ACK never comes times out, closes the connection and stays indeterminate.
    let (actor, state) = radio();
    state.lock().unwrap().mute_ptt = true;
    assert_eq!(
        actor_ptt(&actor, true, Duration::from_millis(300)),
        Err(PttError::Timeout)
    );
    assert!(actor.ptt_indeterminate());
    assert_ne!(actor.snapshot().unwrap().state, cat::State::Ready);
}

#[test]
fn halt_through_the_real_actor_unkeys_mid_audio_within_the_bound() {
    struct Station {
        fake: Fake,
        actor: Arc<Actor>,
    }
    impl Hardware for Station {
        fn now_utc_ms(&self) -> i64 {
            self.fake.now_utc_ms()
        }
        fn clock(&self) -> ClockState {
            ClockState::Synchronized
        }
        fn context(&self) -> Context {
            self.fake.context()
        }
        fn ptt(&mut self, on: bool) -> Result<(), PttError> {
            actor_ptt(&self.actor, on, Duration::from_secs(1))
        }
        fn open_audio(&mut self) -> Result<(), AudioError> {
            self.fake.open_audio()
        }
        fn play(&mut self, p: Program) -> Result<(), AudioError> {
            self.fake.play(p)
        }
        fn poll_audio(&mut self) -> AudioPoll {
            self.fake.poll_audio()
        }
        fn stop_audio(&mut self) {
            self.fake.stop_audio()
        }
        fn audio_stopper(&self) -> Arc<dyn Fn() + Send + Sync> {
            self.fake.audio_stopper()
        }
    }
    let (actor, state) = radio();
    let fake = Fake::new();
    fake.at(P + 400);
    let mut core = Core::new(Station {
        fake: fake.clone(),
        actor,
    });
    core.arm(7).unwrap();
    core.submit(request(1, P, "CQ HB9BLA JN47"));
    core.tick(); // keys
    assert!(state.lock().unwrap().transmitting);
    fake.at(P + 600);
    core.tick(); // audio
    assert!(core.view().transmitting);
    let start = Instant::now();
    assert_eq!(core.halt(), HaltState::Stopped);
    assert!(start.elapsed() < Duration::from_millis(HALT_BOUND_MS));
    let r = state.lock().unwrap();
    assert!(!r.transmitting);
    let frames = ptt_frames(&r);
    assert_eq!(frames.iter().filter(|w| *w == KEY).count(), 1);
    assert_eq!(frames.iter().filter(|w| *w == UNKEY).count(), 1);
}

#[test]
fn output_renderer_plays_from_the_planned_sample_on_every_channel_then_silence() {
    use wstx_rust::audio::{Encoding, NativeFormat};
    use wstx_rust::playback::{Renderer, Source};
    let samples: Arc<[f32]> = vec![0.0, 0.25, -0.5, 1.0].into();
    let mut r = Renderer::new(Source::Samples { samples, skip: 1 }, PLAYBACK_SCALE);
    let format = NativeFormat {
        rate: 48_000,
        channels: 2,
        encoding: Encoding::Pcm16,
    };
    let mut out = vec![0u8; 4 * 4];
    r.fill(format, &mut out, 4);
    let values: Vec<i16> = out
        .chunks(2)
        .map(|b| i16::from_le_bytes([b[0], b[1]]))
        .collect();
    // 0.25, -0.5, 1.0 at -6.02 dBFS on both channels, then silence.
    assert_eq!(values, vec![4096, 4096, -8192, -8192, 16384, 16384, 0, 0]);
    assert!(r.exhausted());
    let mut tone = Renderer::new(Source::Tone { hz: 12_000.0 }, 1.0);
    let format = NativeFormat {
        rate: 48_000,
        channels: 1,
        encoding: Encoding::Float32,
    };
    let mut out = vec![0u8; 4 * 4];
    tone.fill(format, &mut out, 4);
    let v: Vec<f32> = out
        .chunks(4)
        .map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
        .collect();
    assert!(
        v[0].abs() < 1e-6
            && (v[1] - 1.0).abs() < 1e-6
            && v[2].abs() < 1e-6
            && (v[3] + 1.0).abs() < 1e-6
    );
    assert!(!tone.exhausted());
}

// Proves: CL-009-04, CL-022-03; TC-008-003.
#[test]
fn startup_safety_release_is_off_only_once_per_boot_and_only_when_tx_is_observed() {
    // Radio found transmitting before this boot keyed: exactly one release.
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    core.tick();
    assert_eq!(core.view().startup_release, StartupRelease::Pending);
    assert!(f.keys().is_empty(), "no readback, no action");
    *f.0.radio_tx.lock().unwrap() = Some(true);
    core.tick();
    core.tick();
    assert_eq!(f.keys(), vec![(P - 20_000, false)]);
    assert_eq!(core.view().startup_release, StartupRelease::Released);
    // Radio in receive at boot: nothing.
    let f = Fake::new();
    *f.0.radio_tx.lock().unwrap() = Some(false);
    let mut core = Core::new(f.clone());
    run(&mut core, &f, P - 19_000);
    *f.0.radio_tx.lock().unwrap() = Some(true); // later TX (e.g. the operator's mic) is not ours to end
    run(&mut core, &f, P - 18_000);
    assert!(f.keys().is_empty());
    assert_eq!(core.view().startup_release, StartupRelease::NotNeeded);
    // This boot keyed first: TX is our own transmission, no extra switch.
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    f.at(P - 100);
    core.arm(7).unwrap();
    core.submit(request(1, P, "CQ HB9BLA JN47"));
    run(&mut core, &f, P + 10);
    *f.0.radio_tx.lock().unwrap() = Some(true);
    run(&mut core, &f, P + 20);
    assert_eq!(f.keys(), vec![(P, true)]);
    assert_eq!(core.view().startup_release, StartupRelease::NotNeeded);
    // A release that is not confirmed is attempted once; Arm stays refused.
    let f = Fake::new();
    *f.0.radio_tx.lock().unwrap() = Some(true);
    *f.0.unkey_error.lock().unwrap() = Some(PttError::Timeout);
    let mut core = Core::new(f.clone());
    run(&mut core, &f, P - 19_000);
    assert_eq!(f.keys().len(), 1);
    assert_eq!(core.view().startup_release, StartupRelease::Failed);
    assert_eq!(core.arm(7), Err(TransmitRefusal::RadioUnavailable));
}

/// Wall-clock driver: the fake UTC follows real time from `start`.
fn drive(f: &Fake, start: i64) -> (Arc<AtomicBool>, std::thread::JoinHandle<()>) {
    let origin = Instant::now();
    let clock = f.clone();
    let stop = Arc::new(AtomicBool::new(false));
    let ticking = stop.clone();
    clock.at(start);
    let handle = std::thread::spawn(move || {
        while !ticking.load(Ordering::SeqCst) {
            clock.at(start + origin.elapsed().as_millis() as i64);
            std::thread::sleep(Duration::from_millis(1));
        }
    });
    (stop, handle)
}
fn wait_for(what: &str, limit: Duration, done: impl Fn() -> bool) {
    let start = Instant::now();
    while !done() {
        assert!(start.elapsed() < limit, "timed out waiting for {what}");
        std::thread::sleep(Duration::from_millis(1));
    }
}

// Proves: CL-009-04; TC-008-003. Review finding 1: the release never depends on the
// device reporting the end.
#[test]
fn ptt_is_released_at_the_hard_deadline_when_the_device_never_finishes_or_stalls() {
    for stuck in [AudioPoll::Playing, AudioPoll::Idle] {
        let f = Fake::new();
        let mut core = Core::new(f.clone());
        f.at(P - 100);
        core.arm(7).unwrap();
        core.submit(request(1, P, "CQ HB9BLA JN47"));
        run(&mut core, &f, P + 600);
        *f.0.audio.lock().unwrap() = Some(stuck);
        // Disarm does not unbound the keyed transmission.
        core.disarm(DisarmCause::Operator);
        let deadline = P + 500 + 606_720 * 1000 / 48_000 + 500;
        run(&mut core, &f, deadline - 1);
        assert_eq!(f.keys(), vec![(P, true)], "still keyed before the deadline");
        run(&mut core, &f, deadline);
        assert_eq!(f.keys(), vec![(P, true), (deadline, false)], "{stuck:?}");
        let last = core.view().outcomes.last().cloned().unwrap();
        assert_eq!(last.kind, OutcomeKind::Failed);
        assert!(last.failure.is_some());
        assert_eq!(core.view().ptt, PttState::Released);
    }
}

// Proves: CL-009-04; TC-008-003. Review finding 3: an owner panic fails closed.
#[test]
fn owner_panic_mid_audio_fails_closed_releases_and_halt_still_answers() {
    let f = Fake::new();
    let (stop, driver) = drive(&f, P + 300);
    let service = Service::start(f.clone()).unwrap();
    service.with(|c| {
        c.arm(7).unwrap();
        c.submit(request(1, P, "CQ HB9BLA JN47"))
    });
    wait_for("audio start", Duration::from_secs(3), || {
        service.view().transmitting
    });
    f.0.panic_poll.store(true, Ordering::SeqCst);
    wait_for("fail-closed release", Duration::from_secs(2), || {
        f.keys().last().map(|k| k.1) == Some(false)
    });
    let v = service.view();
    assert_eq!(
        (v.arm_state, v.ptt, v.transmitting),
        (ArmState::Disarmed, PttState::Released, false)
    );
    let started = Instant::now();
    let state = service.halt("00000000-0000-4000-8000-0000000000c1");
    assert!(started.elapsed() < Duration::from_millis(HALT_BOUND_MS));
    assert_ne!(state, HaltState::Pending, "halt answers after a fault");
    assert!(
        service.with(|c| c.arm(7)).is_err(),
        "a faulted owner never re-arms"
    );
    stop.store(true, Ordering::SeqCst);
    driver.join().unwrap();
}

// Proves: CL-009-04; TC-008-003. Review finding 2: a halt during the output open
// prevents keying.
#[test]
fn halt_during_a_slow_output_open_never_keys() {
    let f = Fake::new();
    f.0.open_delay_ms.store(300, Ordering::SeqCst);
    let (stop, driver) = drive(&f, P - 50);
    let service = Service::start(f.clone()).unwrap();
    service.with(|c| {
        c.arm(7).unwrap();
        c.submit(request(1, P, "CQ HB9BLA JN47"))
    });
    wait_for("open", Duration::from_secs(2), || {
        f.log().iter().any(|(_, e)| *e == Event::Open)
    });
    let state = service.halt("00000000-0000-4000-8000-0000000000c2");
    std::thread::sleep(Duration::from_millis(700));
    assert!(
        f.keys().iter().all(|k| !k.1),
        "keyed after halt: {:?}",
        f.log()
    );
    assert_ne!(state, HaltState::Stopped, "nothing was keyed");
    assert_eq!(service.view().arm_state, ArmState::Disarmed);
    stop.store(true, Ordering::SeqCst);
    driver.join().unwrap();
}

// Proves: CL-009-04; TC-008-003. A halt while the key exchange runs releases within the bound.
#[test]
fn halt_during_a_slow_key_releases_within_the_bound() {
    let f = Fake::new();
    f.0.ptt_delay_ms.store(80, Ordering::SeqCst);
    let (stop, driver) = drive(&f, P - 50);
    let service = Service::start(f.clone()).unwrap();
    service.with(|c| {
        c.arm(7).unwrap();
        c.submit(request(1, P, "CQ HB9BLA JN47"))
    });
    wait_for("open", Duration::from_secs(2), || {
        f.log().iter().any(|(_, e)| *e == Event::Open)
    });
    let started = Instant::now();
    let state = service.halt("00000000-0000-4000-8000-0000000000c3");
    assert!(started.elapsed() < Duration::from_millis(HALT_BOUND_MS + 20));
    std::thread::sleep(Duration::from_millis(300));
    let keys = f.keys();
    assert!(
        keys.is_empty() || keys.last().map(|k| k.1) == Some(false),
        "{keys:?}"
    );
    assert_ne!(state, HaltState::Pending);
    assert!(!f.log().iter().any(|(_, e)| matches!(e, Event::Play { .. })));
    stop.store(true, Ordering::SeqCst);
    driver.join().unwrap();
}

// Proves: CL-009-04; TC-008-003. Review finding 4.
#[test]
fn watchdog_expiry_reports_the_true_halt_state_when_release_fails() {
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    core.set_watchdogs(1, 90).unwrap();
    f.at(P - 100);
    core.arm(7).unwrap();
    core.submit(request(1, P, "CQ HB9BLA JN47"));
    run(&mut core, &f, P + 600);
    *f.0.unkey_error.lock().unwrap() = Some(PttError::Timeout);
    f.at(P + 500 + 60_000);
    core.tick();
    let v = core.view();
    assert_eq!(v.last_disarm_cause, DisarmCause::TxWatchdog);
    assert_eq!(
        (v.halt_state, v.ptt),
        (HaltState::Pending, PttState::Indeterminate)
    );
}

// Proves: CL-009-03; TC-008-003. Mutation guards named by the review.
#[test]
fn arm_is_refused_while_ptt_is_indeterminate_and_submit_checks_the_safety_revision() {
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    f.at(P - 100);
    core.arm(7).unwrap();
    core.submit(request(1, P, "CQ HB9BLA JN47"));
    run(&mut core, &f, P + 600);
    *f.0.unkey_error.lock().unwrap() = Some(PttError::Rejected);
    assert_eq!(core.halt(), HaltState::Pending);
    assert_eq!(core.view().ptt, PttState::Indeterminate);
    // Capability stays available: only the indeterminate switch refuses Arm.
    assert_eq!(core.arm(7), Err(TransmitRefusal::RadioUnavailable));
    let f = Fake::new();
    let mut core = Core::new(f.clone());
    core.arm(7).unwrap();
    *f.0.revision.lock().unwrap() = Some(8); // no tick in between
    let o = core.submit(request(1, P, "CQ HB9BLA JN47"));
    assert_eq!(o.refusal, Some(TransmitRefusal::NotAuthorized));
    assert_eq!(core.view().arm_state, ArmState::Disarmed);
}

#[test]
fn render_drain_stops_topping_up_and_watchdog_flags_a_stall() {
    use wstx_rust::playback::{Fill, Progress, Renderer, Source, plan_fill};
    let samples: Arc<[f32]> = vec![0.1; 10].into();
    let mut r = Renderer::new(Source::Samples { samples, skip: 0 }, 1.0);
    assert_eq!(plan_fill(None, 100, 480), Fill::Silence(380));
    assert_eq!(plan_fill(Some(&r), 470, 480), Fill::Program(10));
    let format = wstx_rust::audio::NativeFormat {
        rate: 48_000,
        channels: 1,
        encoding: wstx_rust::audio::Encoding::Float32,
    };
    r.fill(format, &mut [0; 40], 10);
    assert_eq!(
        plan_fill(Some(&r), 300, 480),
        Fill::Nothing,
        "no silence after the end"
    );
    assert_eq!(plan_fill(Some(&r), 0, 480), Fill::Finished);
    let mut p = Progress::new(0);
    p.wrote(480);
    p.observe(480, 100);
    p.observe(480, 600);
    assert!(p.stalled(601), "no consumption for 601 ms");
    p.observe(400, 650);
    assert!(!p.stalled(1_100));
}

#[test]
fn a_halt_aborts_a_key_waiting_for_the_cat_owner_without_bytes() {
    let (actor, state) = radio();
    let lease = actor.reserve_transition().unwrap();
    let abort = Arc::new(AtomicBool::new(false));
    let (a, flag) = (actor.clone(), abort.clone());
    let waiter = std::thread::spawn(move || {
        let started = Instant::now();
        let result = actor_ptt_abortable(&a, Duration::from_secs(2), &flag);
        (result, started.elapsed())
    });
    std::thread::sleep(Duration::from_millis(50));
    abort.store(true, Ordering::SeqCst);
    let (result, elapsed) = waiter.join().unwrap();
    assert_eq!(result, Err(PttError::Busy));
    assert!(elapsed < Duration::from_millis(250), "{elapsed:?}");
    drop(lease);
    assert!(ptt_frames(&state.lock().unwrap()).is_empty());
    assert!(!actor.ptt_indeterminate());
}
