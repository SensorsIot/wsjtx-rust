#![forbid(unsafe_code)]
// Proves: CL-009-05, CL-009-02; TC-006-003. The station clock state from its own SNTP
// measurement: RFC 4330/5905 offset arithmetic (hand-computed timestamps), reply
// validation, server fallback against fake responders on 127.0.0.1, the
// synchronized/unsynchronized/unknown rule and PlanTransmitStart admission.
use std::net::UdpSocket;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, mpsc};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use wstx_rust::decoder::Mode;
use wstx_rust::transmit::clock::{
    self, MAX_AGE, MAX_STEP_MS, Measurement, Monitor, ReplyError, Sntp, Source, offset, state,
};
use wstx_rust::transmit::{ClockState, ScheduleError, plan_start};

/// NTP 32.32 timestamp of `ms` milliseconds after the NTP epoch (independent encoder).
fn ts(ms: u64) -> u64 {
    ((ms / 1000) << 32) | (((ms % 1000) << 32) / 1000)
}
/// A server reply written field by field from RFC 5905 figure 8.
fn reply(first: u8, stratum: u8, origin: u64, receive: u64, transmit: u64) -> Vec<u8> {
    let mut p = vec![0u8; 48];
    p[0] = first;
    p[1] = stratum;
    p[24..32].copy_from_slice(&origin.to_be_bytes());
    p[32..40].copy_from_slice(&receive.to_be_bytes());
    p[40..48].copy_from_slice(&transmit.to_be_bytes());
    p
}
const SERVER_V4: u8 = 0b00_100_100; // LI 0, version 4, mode 4

#[test]
fn offset_and_round_trip_follow_the_rfc_formula() {
    // T1 100.000 s, T2 100.600, T3 100.601, T4 100.021 (hand calculation):
    // offset ((0.600)+(0.580))/2 = 0.590 s; round trip 0.021-0.001 = 0.020 s.
    let (t1, t2, t3, t4) = (ts(100_000), ts(100_600), ts(100_601), ts(100_021));
    assert_eq!(
        offset(&reply(SERVER_V4, 2, t1, t2, t3), t1, t4),
        Ok((590, 20))
    );
    // Server behind: T2 99.300, T3 99.301 with T4 100.011:
    // offset ((-0.700)+(-0.710))/2 = -0.705 s; round trip 0.011-0.001 = 0.010 s.
    let (t2, t3, t4) = (ts(99_300), ts(99_301), ts(100_011));
    assert_eq!(
        offset(&reply(SERVER_V4, 1, t1, t2, t3), t1, t4),
        Ok((-705, 10))
    );
    // Across the NTP era boundary: T1 0.2 s before 2^32 s, server 0.3 s after it.
    // offset ((0.5)+(0.3-(-0.19)))/2 = 0.495 s; round trip 0.010 s.
    let t1 = 0u64.wrapping_sub(ts(200));
    let (t2, t3) = (ts(300), ts(300));
    let t4 = t1.wrapping_add(ts(10));
    assert_eq!(
        offset(&reply(SERVER_V4, 3, t1, t2, t3), t1, t4),
        Ok((495, 10))
    );
}

#[test]
fn invalid_replies_are_refused() {
    let (t1, t2, t3, t4) = (ts(100_000), ts(100_010), ts(100_011), ts(100_020));
    let good = reply(SERVER_V4, 2, t1, t2, t3);
    assert!(offset(&good, t1, t4).is_ok());
    assert_eq!(offset(&good[..47], t1, t4), Err(ReplyError::Short));
    // Mode 3 (a client), mode 5 (broadcast).
    assert_eq!(
        offset(&reply(0b00_100_011, 2, t1, t2, t3), t1, t4),
        Err(ReplyError::Mode)
    );
    assert_eq!(
        offset(&reply(0b00_100_101, 2, t1, t2, t3), t1, t4),
        Err(ReplyError::Mode)
    );
    // Stratum 0 (kiss-of-death) and 16 (unsynchronized); 1 and 15 are the bounds.
    assert_eq!(
        offset(&reply(SERVER_V4, 0, t1, t2, t3), t1, t4),
        Err(ReplyError::Stratum)
    );
    assert_eq!(
        offset(&reply(SERVER_V4, 16, t1, t2, t3), t1, t4),
        Err(ReplyError::Stratum)
    );
    assert!(offset(&reply(SERVER_V4, 15, t1, t2, t3), t1, t4).is_ok());
    assert_eq!(
        offset(&reply(SERVER_V4, 2, t1, t2, 0), t1, t4),
        Err(ReplyError::ZeroTransmit)
    );
    assert_eq!(
        offset(&reply(SERVER_V4, 2, t1 + 1, t2, t3), t1, t4),
        Err(ReplyError::OriginMismatch)
    );
    // Leap indicator 3: the server itself is not synchronized.
    assert_eq!(
        offset(&reply(0b11_100_100, 2, t1, t2, t3), t1, t4),
        Err(ReplyError::Alarm)
    );
}

enum Behaviour {
    Silent,
    /// Answers with the request's transmit timestamp plus this many ms.
    Ahead(u64),
    /// Answers stratum 0 (kiss-of-death).
    KissOfDeath,
}
/// A fake SNTP server on 127.0.0.1; returns its address and its request counter.
fn responder(behaviour: Behaviour) -> (String, Arc<AtomicUsize>) {
    let socket = UdpSocket::bind("127.0.0.1:0").unwrap();
    let address = socket.local_addr().unwrap().to_string();
    let count = Arc::new(AtomicUsize::new(0));
    let seen = count.clone();
    std::thread::spawn(move || {
        let mut buffer = [0u8; 128];
        while let Ok((n, peer)) = socket.recv_from(&mut buffer) {
            seen.fetch_add(1, Ordering::SeqCst);
            assert_eq!(n, 48, "SNTP request size");
            assert_eq!(buffer[0] & 7, 3, "client mode");
            let origin = u64::from_be_bytes(buffer[40..48].try_into().unwrap());
            let answer = match behaviour {
                Behaviour::Silent => continue,
                Behaviour::Ahead(ms) => {
                    let t = origin.wrapping_add(ts(ms));
                    reply(SERVER_V4, 2, origin, t, t)
                }
                Behaviour::KissOfDeath => reply(SERVER_V4, 0, origin, origin, origin),
            };
            let _ = socket.send_to(&answer, peer);
        }
    });
    (address, count)
}
fn sntp(servers: &[&str]) -> Sntp {
    Sntp {
        servers: servers.iter().map(|s| s.to_string()).collect(),
        timeout: Duration::from_millis(300),
        // A fake station clock: the responder answers relative to it.
        now: || UNIX_EPOCH + Duration::from_secs(1_790_000_000),
    }
}

#[test]
fn servers_are_tried_in_order_until_one_answers() {
    assert_eq!(
        clock::SERVERS,
        ["ch.pool.ntp.org", "time.windows.com", "pool.ntp.org"]
    );
    let (silent, silent_count) = responder(Behaviour::Silent);
    let (refusing, refusing_count) = responder(Behaviour::KissOfDeath);
    let (good, good_count) = responder(Behaviour::Ahead(3_000));
    let (later, later_count) = responder(Behaviour::Ahead(0));
    let started = Instant::now();
    let m = sntp(&[&silent, &refusing, &good, &later])
        .measure()
        .expect("third server answers");
    assert_eq!(m.server, good);
    assert!((2_980..=3_000).contains(&m.offset_ms), "{}", m.offset_ms);
    assert!((0..300).contains(&m.round_trip_ms));
    assert_eq!(
        (
            silent_count.load(Ordering::SeqCst),
            refusing_count.load(Ordering::SeqCst),
            good_count.load(Ordering::SeqCst),
            later_count.load(Ordering::SeqCst)
        ),
        (1, 1, 1, 0),
        "one request each, in order, none after the answer"
    );
    // Two per-server timeouts, then the answer.
    assert!(started.elapsed() >= Duration::from_millis(590));
    assert!(started.elapsed() < Duration::from_secs(3));
    // Nobody answers: no measurement.
    assert_eq!(sntp(&[&silent, &refusing]).measure(), None);
}

/// The fake station system clock at the measurement.
fn system0() -> SystemTime {
    UNIX_EPOCH + Duration::from_secs(1_790_000_000)
}
static JUMP_CALLS: AtomicUsize = AtomicUsize::new(0);
/// A fake station clock that steps +10 s after its first reading (the request).
fn jumping_now() -> SystemTime {
    let base = UNIX_EPOCH + Duration::from_secs(1_790_000_000);
    if JUMP_CALLS.fetch_add(1, Ordering::SeqCst) == 0 {
        base
    } else {
        base + Duration::from_secs(10)
    }
}

#[test]
fn a_clock_step_during_the_exchange_does_not_distort_the_offset() {
    // The responder answers 3 s ahead of the request's transmit timestamp. If the
    // receive time T4 were read from the stepped clock, the offset would be about
    // (3 + (3 - 10)) / 2 = -2 s; T4 = T1 + monotonic elapsed keeps it at 3 s.
    let (good, _) = responder(Behaviour::Ahead(3_000));
    let mut source = Sntp {
        servers: vec![good],
        timeout: Duration::from_millis(500),
        now: jumping_now,
    };
    let m = source.measure().expect("answer");
    assert!(JUMP_CALLS.load(Ordering::SeqCst) >= 1);
    assert!((2_980..=3_000).contains(&m.offset_ms), "{}", m.offset_ms);
    // The offset describes the clock before the step; read now on the stepped clock the
    // measurement no longer holds, so the state is unknown (not unsynchronized/synchronized).
    assert_eq!(state(Some(&m), m.taken, jumping_now()), ClockState::Unknown);
}

fn measured(offset_ms: i64, taken: Instant) -> Measurement {
    Measurement {
        server: "ch.pool.ntp.org".into(),
        offset_ms,
        round_trip_ms: 20,
        taken,
        system: system0(),
    }
}

fn state_at(m: Option<&Measurement>, (now, system): (Instant, SystemTime)) -> ClockState {
    state(m, now, system)
}

#[test]
fn clock_state_rule_and_transmit_admission() {
    let taken = Instant::now();
    // Monotonic and system time advance together: no clock step.
    let at = |age: Duration| (taken + age, system0() + age);
    let fresh = Duration::from_secs(1);
    for (offset_ms, expected) in [
        (0, ClockState::Synchronized),
        (500, ClockState::Synchronized),
        (-500, ClockState::Synchronized),
        (501, ClockState::Unsynchronized),
        (-501, ClockState::Unsynchronized),
        (30_000, ClockState::Unsynchronized),
    ] {
        assert_eq!(
            state_at(Some(&measured(offset_ms, taken)), at(fresh)),
            expected,
            "{offset_ms}"
        );
    }
    assert_eq!(
        state_at(Some(&measured(10, taken)), at(MAX_AGE)),
        ClockState::Synchronized
    );
    assert_eq!(
        state_at(
            Some(&measured(10, taken)),
            at(MAX_AGE + Duration::from_millis(1))
        ),
        ClockState::Unknown
    );
    assert_eq!(
        state_at(
            Some(&measured(900, taken)),
            at(MAX_AGE + Duration::from_millis(1))
        ),
        ClockState::Unknown
    );
    assert_eq!(state_at(None, at(fresh)), ClockState::Unknown);
    assert_eq!(MAX_STEP_MS, 100);
    // The system clock stepped after the measurement (e.g. Dimension 4 by 2 s): the
    // measured offset no longer describes it, so the state is unknown, not synchronized.
    let stepped = |age: Duration, step_ms: i64| {
        let system = if step_ms >= 0 {
            system0() + age + Duration::from_millis(step_ms as u64)
        } else {
            system0() + age - Duration::from_millis((-step_ms) as u64)
        };
        (taken + age, system)
    };
    for (step_ms, expected) in [
        (100, ClockState::Synchronized),
        (-100, ClockState::Synchronized),
        (101, ClockState::Unknown),
        (-101, ClockState::Unknown),
        (2_000, ClockState::Unknown),
        (-2_000, ClockState::Unknown),
    ] {
        assert_eq!(
            state_at(
                Some(&measured(0, taken)),
                stepped(Duration::from_secs(30), step_ms)
            ),
            expected,
            "step {step_ms}"
        );
    }
    // Also an unsynchronized measurement becomes unknown after a step (it may now be right).
    assert_eq!(
        state_at(
            Some(&measured(2_089, taken)),
            stepped(Duration::from_secs(30), 2_089)
        ),
        ClockState::Unknown
    );
    assert_eq!(MAX_AGE, Duration::from_secs(600));

    // PlanTransmitStart with each derived state, FT8 and FT4, a period starting now.
    let period = 1_790_000_010_000i64 - 1_790_000_010_000i64.rem_euclid(15_000);
    for mode in [Mode::Ft8, Mode::Ft4] {
        let plan = |offset_ms: Option<i64>, age: Duration| {
            let m = offset_ms.map(|o| measured(o, taken));
            plan_start(mode, period, state_at(m.as_ref(), at(age)), period, 48_000)
        };
        assert!(plan(Some(500), fresh).is_ok());
        assert_eq!(
            plan(Some(-501), fresh),
            Err(ScheduleError::ClockNotSynchronized)
        );
        assert_eq!(plan(None, fresh), Err(ScheduleError::ClockNotSynchronized));
        assert_eq!(
            plan(Some(0), MAX_AGE + fresh),
            Err(ScheduleError::ClockNotSynchronized)
        );
        // A 2 s step after a synchronized measurement never keys.
        let m = measured(0, taken);
        let (now, system) = stepped(fresh, 2_000);
        assert_eq!(
            plan_start(mode, period, state(Some(&m), now, system), period, 48_000),
            Err(ScheduleError::ClockNotSynchronized)
        );
    }
}

/// A measurement taken now on the real clocks (what Monitor::state compares against).
fn measured_now(offset_ms: i64) -> Measurement {
    Measurement {
        system: SystemTime::now(),
        ..measured(offset_ms, Instant::now())
    }
}
struct Scripted(mpsc::Receiver<Option<Measurement>>);
impl Source for Scripted {
    fn measure(&mut self) -> Option<Measurement> {
        // Blocks like a slow network until the test supplies the next result.
        self.0.recv().unwrap_or(None)
    }
}

#[test]
fn monitor_measures_off_the_reading_thread_and_keeps_the_last_answer() {
    let (send, receive) = mpsc::channel();
    let monitor = Monitor::start(Box::new(Scripted(receive)), Duration::from_millis(5)).unwrap();
    // The measurement is blocked: reading answers at once, unknown.
    let started = Instant::now();
    assert_eq!(monitor.state(), ClockState::Unknown);
    assert!(started.elapsed() < Duration::from_millis(50));
    send.send(Some(measured_now(42))).unwrap();
    let until = Instant::now() + Duration::from_secs(5);
    while monitor.latest().is_none() && Instant::now() < until {
        std::thread::sleep(Duration::from_millis(5));
    }
    assert_eq!(monitor.state(), ClockState::Synchronized);
    // A round without an answer keeps the previous measurement (it ages out later).
    send.send(None).unwrap();
    send.send(Some(measured_now(700))).unwrap();
    let until = Instant::now() + Duration::from_secs(5);
    while monitor.latest().map(|m| m.offset_ms) != Some(700) && Instant::now() < until {
        std::thread::sleep(Duration::from_millis(5));
    }
    assert_eq!(monitor.state(), ClockState::Unsynchronized);
    let quiet = Monitor::new();
    quiet.record(Some(measured_now(1)));
    quiet.record(None);
    assert_eq!(quiet.latest().map(|m| m.offset_ms), Some(1));
}

#[test]
fn server_override_list_is_comma_separated_and_may_be_empty() {
    assert_eq!(
        clock::server_list(" 127.0.0.1:1230, ,time.example "),
        ["127.0.0.1:1230", "time.example"]
    );
    assert!(clock::server_list("").is_empty());
    // No server: no measurement, never a network request.
    assert_eq!(sntp(&[]).measure(), None);
}
