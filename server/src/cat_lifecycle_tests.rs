#![forbid(unsafe_code)]
// Proves: CL-022-03, CL-022-04; TC-022-009. Injected monotonic time drives the policy;
// an independent scripted CI-V peer (not the production codec) counts every native
// open, raw byte and close.
use crate::cat_lifecycle::{Action, DELAYS, Gate, Key, Lifecycle, Observed};
use crate::recording::Recording;
use std::{
    collections::VecDeque,
    path::PathBuf,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};
use wstx_rust::radio_control::{self as cat, executor::Transport};

pub(crate) const ENDPOINT: &str = "icom7300://COM3?baud=9600&radio=94&controller=E0";

fn key(revision: u64) -> Key {
    Key {
        radio_id: "00000000-0000-4000-8000-0000000000aa".into(),
        safety_revision: revision,
        profile_revision: 0,
        endpoint: ENDPOINT.into(),
    }
}
fn eligible(revision: u64) -> Gate {
    Gate::Eligible {
        key: key(revision),
        configuration: cat::Configuration::parse(ENDPOINT).unwrap(),
    }
}
fn secs(base: Instant, s: f64) -> Instant {
    base + Duration::from_secs_f64(s)
}

#[test]
fn policy_startup_is_immediate_then_backoff_1_2_4_8_8_without_catch_up() {
    let mut p = Lifecycle::new();
    let t0 = Instant::now();
    let gate = eligible(1);
    assert_eq!(p.step(&gate, Observed::Absent, t0), Action::Attempt);
    let mut now = t0;
    let mut observed_delays = Vec::new();
    for _ in 0..7 {
        // The attempt completes after an arbitrary time and its release is confirmed.
        now += Duration::from_millis(300);
        assert_eq!(
            p.step(
                &gate,
                Observed::FailedReleased(cat::Error::Unavailable),
                now
            ),
            Action::None
        );
        let (condition, error, retry) = p.status();
        assert_eq!(condition, "retryWaiting");
        assert_eq!(error, Some("radio_unavailable"));
        let failed_at = now;
        // 10 ms ticks never start an early or extra attempt.
        let mut attempts = 0;
        loop {
            now += Duration::from_millis(10);
            match p.step(
                &gate,
                Observed::FailedReleased(cat::Error::Unavailable),
                now,
            ) {
                Action::Attempt => {
                    attempts += 1;
                    break;
                }
                Action::None => {}
                Action::Close => panic!("released failure is not closed again"),
            }
        }
        assert_eq!(attempts, 1);
        let delay = (now - failed_at).as_millis() as u64;
        observed_delays.push(delay.div_ceil(1000));
        assert!(retry.unwrap() <= 8000);
    }
    assert_eq!(observed_delays, vec![1, 2, 4, 8, 8, 8, 8]);
    assert_eq!(DELAYS, [1, 2, 4, 8]);
    // A long stall (no ticks for an hour) yields one attempt, never a backlog.
    now += Duration::from_millis(300);
    p.step(&gate, Observed::FailedReleased(cat::Error::Timeout), now);
    now += Duration::from_secs(3600);
    assert_eq!(
        p.step(&gate, Observed::FailedReleased(cat::Error::Timeout), now),
        Action::Attempt
    );
    assert_eq!(p.step(&gate, Observed::Connecting, now), Action::None);
}

#[test]
fn policy_reset_only_after_fresh_readback() {
    let mut p = Lifecycle::new();
    let t0 = Instant::now();
    let gate = eligible(1);
    let fail = Observed::FailedReleased(cat::Error::Timeout);
    assert_eq!(p.step(&gate, Observed::Absent, t0), Action::Attempt);
    let mut now = t0;
    for expected in [1.0, 2.0, 4.0] {
        now += Duration::from_millis(100);
        p.step(&gate, fail, now);
        assert_eq!(
            p.step(&gate, fail, secs(now, expected - 0.01)),
            Action::None
        );
        now = secs(now, expected);
        assert_eq!(p.step(&gate, fail, now), Action::Attempt);
    }
    // Connecting is not success; only Ready (actual readback) resets the series.
    p.step(&gate, Observed::Connecting, now);
    now += Duration::from_millis(100);
    p.step(&gate, fail, now);
    assert_eq!(p.step(&gate, fail, secs(now, 7.99)), Action::None);
    now = secs(now, 8.0);
    assert_eq!(p.step(&gate, fail, now), Action::Attempt);
    p.step(&gate, Observed::Ready, now);
    assert_eq!(p.status(), ("ready", None, None));
    now += Duration::from_secs(60);
    p.step(&gate, fail, now);
    assert_eq!(p.status().2, Some(1000));
    assert_eq!(p.step(&gate, fail, secs(now, 1.0)), Action::Attempt);
}

#[test]
fn policy_missing_preconditions_never_attempt_and_cancel_live_owner() {
    let t0 = Instant::now();
    for (gate, condition) in [
        (Gate::Disabled, "disabled"),
        (Gate::Unauthorized, "unauthorized"),
        (Gate::CommissioningRequired, "commissioningRequired"),
        (Gate::InvalidConfiguration, "waitingForDevice"),
    ] {
        let mut p = Lifecycle::new();
        for second in 0..600 {
            for observed in [Observed::Absent, Observed::Closed] {
                assert_eq!(
                    p.step(&gate, observed, secs(t0, second as f64)),
                    Action::None
                );
            }
        }
        assert_eq!(p.status().0, condition);
        for live in [
            Observed::Connecting,
            Observed::Ready,
            Observed::FailedReleased(cat::Error::Timeout),
        ] {
            assert_eq!(p.step(&gate, live, t0), Action::Close, "{condition}");
        }
        // Re-enable after release: one immediate fresh attempt.
        assert_eq!(p.step(&eligible(1), Observed::Closing, t0), Action::None);
        assert_eq!(p.step(&eligible(1), Observed::Closed, t0), Action::Attempt);
    }
}

#[test]
fn policy_identity_change_cancels_then_attempts_after_release() {
    let mut p = Lifecycle::new();
    let t0 = Instant::now();
    assert_eq!(p.step(&eligible(1), Observed::Absent, t0), Action::Attempt);
    assert_eq!(p.step(&eligible(1), Observed::Connecting, t0), Action::None);
    assert_eq!(
        p.step(&eligible(2), Observed::Connecting, t0),
        Action::Close
    );
    assert_eq!(p.step(&eligible(2), Observed::Closing, t0), Action::None);
    assert_eq!(p.step(&eligible(2), Observed::Closed, t0), Action::Attempt);
}

#[test]
fn policy_failed_close_quarantines_without_timed_reopen() {
    let mut p = Lifecycle::new();
    let t0 = Instant::now();
    p.step(&eligible(1), Observed::Absent, t0);
    for second in 0..7200 {
        let now = secs(t0, second as f64);
        assert_eq!(
            p.step(&eligible(1), Observed::FailedClose, now),
            Action::None
        );
        assert_eq!(
            p.status(),
            ("quarantined", Some("radio_failed_close"), None)
        );
    }
    // Disable/re-enable or a new configuration is not a release proof.
    p.step(&Gate::Disabled, Observed::FailedClose, t0);
    for observed in [Observed::FailedClose, Observed::Closed, Observed::Absent] {
        assert_eq!(
            p.step(&eligible(2), observed, secs(t0, 9000.0)),
            Action::None
        );
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(crate) enum Device {
    Absent,
    Busy,
    Silent,
    Present,
    Removed,
}
pub(crate) struct Peer {
    pub device: Device,
    pub fail_close: bool,
    pub opens: usize,
    pub closes: usize,
    pub writes: Vec<Vec<u8>>,
}
struct Port {
    peer: Arc<Mutex<Peer>>,
    pending: VecDeque<u8>,
}
impl Transport for Port {
    fn configure(&mut self, baud: u32) -> cat::Result<()> {
        assert_eq!(baud, 9600);
        Ok(())
    }
    fn write(&mut self, bytes: &[u8], _: Instant, cancel: &AtomicBool) -> cat::Result<usize> {
        if cancel.load(Ordering::Acquire) {
            return Err(cat::Error::Cancelled);
        }
        let mut peer = self.peer.lock().unwrap();
        peer.writes.push(bytes.to_vec());
        if peer.device != Device::Present {
            return Ok(bytes.len());
        }
        assert_eq!(&bytes[..4], &[0xfe, 0xfe, 0x94, 0xe0]);
        let reply: Vec<u8> = match &bytes[4..bytes.len() - 1] {
            [3] => vec![3, 0, 0x40, 7, 7, 0],
            [4] => vec![4, 1, 1],
            [0x1a, 6] => vec![0x1a, 6, 1, 1],
            [0x1c, 0] => vec![0x1c, 0, 0],
            [0x0f] => vec![0x0f, 0],
            _ => vec![0xfa],
        };
        self.pending.extend([0xfe, 0xfe, 0xe0, 0x94]);
        self.pending.extend(reply);
        self.pending.push_back(0xfd);
        Ok(bytes.len())
    }
    fn read(
        &mut self,
        bytes: &mut [u8],
        deadline: Instant,
        cancel: &AtomicBool,
    ) -> cat::Result<usize> {
        // A silent radio answers nothing; the transport honours its deadline and
        // the <=50 ms cancellation checkpoint.
        while self.peer.lock().unwrap().device == Device::Silent {
            if cancel.load(Ordering::Acquire) {
                return Err(cat::Error::Cancelled);
            }
            if Instant::now() >= deadline {
                return Err(cat::Error::Timeout);
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        if cancel.load(Ordering::Acquire) {
            return Err(cat::Error::Cancelled);
        }
        match self.peer.lock().unwrap().device {
            Device::Removed => return Err(cat::Error::Unavailable),
            _ => {}
        }
        let count = bytes.len().min(self.pending.len());
        for b in bytes.iter_mut().take(count) {
            *b = self.pending.pop_front().unwrap();
        }
        Ok(count)
    }
    fn quiet(&mut self, _: Instant, _: &AtomicBool) -> cat::Result<()> {
        Ok(())
    }
    fn close(&mut self) -> cat::Result<()> {
        let mut peer = self.peer.lock().unwrap();
        peer.closes += 1;
        if peer.fail_close {
            Err(cat::Error::FailedClose)
        } else {
            Ok(())
        }
    }
}

/// Installs the independent scripted peer as the station's only physical transport.
pub(crate) fn attach_peer(recording: &Recording, device: Device) -> Arc<Mutex<Peer>> {
    let peer = Arc::new(Mutex::new(Peer {
        device,
        fail_close: false,
        opens: 0,
        closes: 0,
        writes: Vec::new(),
    }));
    let physical = peer.clone();
    recording.fixture_cat_transport(Arc::new(move |_, _, _| {
        let mut p = physical.lock().unwrap();
        p.opens += 1;
        match p.device {
            Device::Absent => Err(cat::Error::Unavailable),
            Device::Busy => Err(cat::Error::ResourceInUse),
            _ => Ok(Box::new(Port {
                peer: physical.clone(),
                pending: VecDeque::new(),
            }) as Box<dyn Transport>),
        }
    }));
    peer
}

struct Station {
    recording: Arc<Recording>,
    peer: Arc<Mutex<Peer>>,
    directory: PathBuf,
}
impl Station {
    fn new(device: Device) -> Self {
        let directory = std::env::temp_dir().join(format!(
            "wstx-cat-life-{}",
            crate::profile::new_uuid().unwrap()
        ));
        std::fs::create_dir_all(&directory).unwrap();
        let recording = Recording::open(
            &directory,
            crate::profile::new_uuid().unwrap(),
            crate::profile::new_uuid().unwrap(),
        );
        let peer = attach_peer(&recording, device);
        Self {
            recording,
            peer,
            directory,
        }
    }
    fn set(&self, device: Device) {
        self.peer.lock().unwrap().device = device;
    }
    /// Attempts are counted synchronously by the owner's connection generation;
    /// native opens happen on the actor thread and are compared after settling.
    fn attempts(&self) -> usize {
        self.recording.radio_view()["connection_generation"]
            .as_u64()
            .unwrap() as usize
    }
    fn state(&self) -> Option<cat::State> {
        self.recording
            .radio_actor()
            .map(|a| a.snapshot().unwrap().state)
    }
    /// Real-time wait for the actor thread only; policy time stays injected.
    fn settle(&self, done: impl Fn(Option<cat::State>) -> bool) {
        let deadline = Instant::now() + Duration::from_secs(5);
        while !done(self.state()) {
            assert!(
                Instant::now() < deadline,
                "actor did not settle: {:?}",
                self.state()
            );
            std::thread::sleep(Duration::from_millis(2));
        }
    }
    fn tick(&self, gate: &Gate, now: Instant) {
        self.recording.cat_maintain(gate, now);
    }
    fn frequency_confirmed(&self) -> bool {
        self.recording.selection_snapshot(true).unwrap()["radio"]["observations"]["frequency"]
            ["confirmed"]
            .as_bool()
            .unwrap()
    }
    fn assert_read_only(&self) {
        self.settle(|state| state != Some(cat::State::Connecting));
        // A cancelled attempt may end before its open; never more than one open each.
        assert!(
            self.peer.lock().unwrap().opens <= self.attempts(),
            "at most one native open per attempt"
        );
        let queries: [&[u8]; 5] = [&[3], &[4], &[0x1a, 6], &[0x1c, 0], &[0x0f]];
        for w in &self.peer.lock().unwrap().writes {
            assert!(
                w.len() >= 6 && queries.contains(&&w[4..w.len() - 1]),
                "automatic lifecycle sent a non-query (setter/PTT) frame {w:02x?}"
            );
        }
    }
}
impl Drop for Station {
    fn drop(&mut self) {
        if let Some(actor) = self.recording.radio_actor() {
            actor.request_close();
        }
        let _ = std::fs::remove_dir_all(&self.directory);
    }
}
const FAILED: fn(Option<cat::State>) -> bool = |s| s == Some(cat::State::Unavailable);
const READY: fn(Option<cat::State>) -> bool = |s| s == Some(cat::State::Ready);

#[test]
fn station_absent_then_returns_then_cable_removed_and_returns_with_query_bytes_only() {
    let s = Station::new(Device::Absent);
    let gate = eligible(1);
    let t0 = Instant::now();
    s.tick(&gate, t0);
    assert_eq!(
        s.attempts(),
        1,
        "startup makes exactly one immediate attempt"
    );
    s.settle(FAILED);
    s.tick(&gate, secs(t0, 0.1));
    let (condition, error, retry) = s.recording.cat_status();
    assert_eq!(
        (condition, error, retry),
        ("retryWaiting", Some("radio_unavailable"), Some(1000))
    );
    assert!(!s.frequency_confirmed());
    s.tick(&gate, secs(t0, 1.09));
    assert_eq!(s.attempts(), 1, "no attempt before the 1 s delay");
    s.tick(&gate, secs(t0, 1.1));
    assert_eq!(s.attempts(), 2);
    s.settle(FAILED);
    s.tick(&gate, secs(t0, 1.2));
    assert_eq!(s.recording.cat_status().2, Some(2000));
    // Radio powered on / plugged in: the next due attempt connects and reads back.
    s.set(Device::Present);
    s.tick(&gate, secs(t0, 3.19));
    assert_eq!(s.attempts(), 2);
    s.tick(&gate, secs(t0, 3.2));
    assert_eq!(s.attempts(), 3);
    s.settle(READY);
    s.tick(&gate, secs(t0, 3.3));
    assert_eq!(s.recording.cat_status(), ("ready", None, None));
    assert!(s.frequency_confirmed(), "fresh readback is confirmed");
    assert_eq!(
        s.recording.radio_view()["observation"]["frequency_hz"],
        7_074_000
    );
    // Cable removal: the next poll fails, the transport is released and retained
    // frequency is no longer presented as fresh. Reset made the next delay 1 s.
    s.set(Device::Removed);
    s.settle(FAILED);
    assert!(!s.frequency_confirmed());
    s.tick(&gate, secs(t0, 10.0));
    assert_eq!(s.recording.cat_status().0, "retryWaiting");
    assert_eq!(s.recording.cat_status().2, Some(1000));
    assert!(s.peer.lock().unwrap().closes >= 1);
    s.set(Device::Present);
    s.tick(&gate, secs(t0, 11.0));
    assert_eq!(s.attempts(), 4);
    s.settle(READY);
    s.tick(&gate, secs(t0, 11.1));
    assert!(s.frequency_confirmed());
    assert_eq!(s.peer.lock().unwrap().opens, 4);
    s.assert_read_only();
}

#[test]
fn station_open_failure_and_timeout_report_reason_and_release() {
    for (device, reason) in [
        (Device::Busy, "radio_unavailable"),
        (Device::Silent, "radio_timeout"),
    ] {
        let s = Station::new(device);
        let gate = eligible(1);
        let t0 = Instant::now();
        s.tick(&gate, t0);
        s.settle(FAILED);
        s.tick(&gate, secs(t0, 0.1));
        assert_eq!(
            s.recording.cat_status(),
            ("retryWaiting", Some(reason), Some(1000))
        );
        let peer = s.peer.lock().unwrap();
        assert_eq!(peer.opens, 1);
        assert_eq!(peer.closes, usize::from(device == Device::Silent));
        drop(peer);
        s.assert_read_only();
    }
}

#[test]
fn station_failed_close_is_quarantined_and_never_reopened() {
    let s = Station::new(Device::Present);
    let gate = eligible(1);
    let t0 = Instant::now();
    s.tick(&gate, t0);
    s.settle(READY);
    s.peer.lock().unwrap().fail_close = true;
    s.set(Device::Removed);
    s.settle(|state| state == Some(cat::State::Closing));
    for second in 1..400 {
        s.tick(&gate, secs(t0, second as f64 * 10.0));
    }
    assert_eq!(
        s.attempts(),
        1,
        "failed close retains the owner; no timed reopen"
    );
    assert_eq!(s.recording.cat_status().0, "quarantined");
    assert!(!s.frequency_confirmed());
    s.assert_read_only();
}

#[test]
fn station_revocation_or_invalid_commissioning_cancels_and_releases_then_no_io() {
    for gate in [
        Gate::Unauthorized,
        Gate::CommissioningRequired,
        Gate::Disabled,
    ] {
        let s = Station::new(Device::Present);
        let t0 = Instant::now();
        s.tick(&eligible(1), t0);
        s.settle(READY);
        let cancelled = Instant::now();
        s.tick(&gate, secs(t0, 1.0));
        s.settle(|state| state == Some(cat::State::Closed));
        assert!(
            cancelled.elapsed() <= Duration::from_millis(250),
            "RF release bound"
        );
        let closes = s.peer.lock().unwrap().closes;
        assert!(closes >= 1);
        let writes = s.peer.lock().unwrap().writes.len();
        for second in 2..200 {
            s.tick(&gate, secs(t0, second as f64));
        }
        assert_eq!(s.attempts(), 1);
        assert_eq!(
            s.peer.lock().unwrap().writes.len(),
            writes,
            "zero bytes after cancel"
        );
        assert!(!s.frequency_confirmed());
        // Re-authorized / re-commissioned: one fresh immediate attempt.
        s.tick(&eligible(1), secs(t0, 300.0));
        assert_eq!(s.attempts(), 2);
        s.settle(READY);
        s.assert_read_only();
    }
}

#[test]
fn station_missing_preconditions_cause_zero_native_open() {
    for gate in [
        Gate::Disabled,
        Gate::Unauthorized,
        Gate::CommissioningRequired,
        Gate::InvalidConfiguration,
    ] {
        let s = Station::new(Device::Present);
        let t0 = Instant::now();
        for tick in 0..100 {
            s.tick(&gate, secs(t0, tick as f64 * 0.5));
        }
        let peer = s.peer.lock().unwrap();
        assert_eq!(
            (peer.opens, peer.writes.len(), peer.closes),
            (0, 0, 0),
            "{gate:?}"
        );
    }
}

#[test]
fn station_identity_change_mid_attempt_fences_late_result() {
    let s = Station::new(Device::Silent);
    let t0 = Instant::now();
    // A Silent device keeps the attempt in its 1 s probe; change identity meanwhile.
    s.tick(&eligible(1), t0);
    assert_eq!(s.state(), Some(cat::State::Connecting));
    let generation = s.recording.radio_view()["connection_generation"].clone();
    let cancelled = Instant::now();
    s.tick(&eligible(2), secs(t0, 0.01));
    s.settle(|state| state == Some(cat::State::Closed));
    assert!(
        cancelled.elapsed() <= Duration::from_millis(250),
        "cancel/release bound"
    );
    s.set(Device::Present);
    s.tick(&eligible(2), secs(t0, 0.02));
    assert_eq!(
        s.attempts(),
        2,
        "new identity gets one immediate attempt after release"
    );
    s.settle(READY);
    assert_ne!(
        s.recording.radio_view()["connection_generation"],
        generation
    );
    s.assert_read_only();
}
