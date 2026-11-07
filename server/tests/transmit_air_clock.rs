#![forbid(unsafe_code)]
// Proves: CL-043-02, CL-043-03, CL-009-05; TC-043-001, TC-043-002. The clock from the air:
// robust estimates of hand-written DT distributions (station offsets -2 s and +1.5 s,
// outliers, few stations, a station with a bad clock, the station's own echo), the
// admission state and its residual bound, the combination by clock source, and a closed
// receive loop proving the applied correction converges without oscillating.
use std::time::{Instant, SystemTime};
use wstx_rust::decoder::{Call, CallKind, Exchange, Fields, Mode};
use wstx_rust::transmit::air::{
    AirClock, Basis, MAX_AGE_MS, Source, StationClock, combine, estimate, sender,
};
use wstx_rust::transmit::clock::{Measurement, Monitor};
use wstx_rust::transmit::{ClockState, ScheduleError, plan_start};

/// True DT of twelve stations with good clocks (ms), median of the twelve = +25 ms.
const CROWD: [i64; 12] = [-250, -150, -100, -50, 0, 0, 50, 100, 150, 200, 300, 400];

fn calls(n: usize) -> Vec<String> {
    (0..n).map(|i| format!("K{i}ABC")).collect()
}
fn samples(names: &[String], dts: &[i64]) -> Vec<(String, i64)> {
    names.iter().cloned().zip(dts.iter().copied()).collect()
}
fn estimated(s: &[(String, i64)]) -> Option<wstx_rust::transmit::air::Estimate> {
    estimate(s.iter().map(|(c, d)| (c.as_str(), *d)))
}

// Proves: TC-043-001.
#[test]
fn estimates_of_known_dt_distributions() {
    let names = calls(13);
    // A station clock 2 s ahead of UTC (offset -2000): every raw DT is 2 s late.
    // The twelve votes' median is (0 + 50) / 2 = 25 ms late of the crowd, so -2025.
    let ahead: Vec<i64> = CROWD.iter().map(|d| d + 2000).collect();
    let e = estimated(&samples(&names, &ahead)).unwrap();
    assert_eq!(
        (e.offset_ms, e.stations, e.heard, e.confidence_pct),
        (-2025, 12, 12, 100)
    );
    assert!(e.confident());
    // 1.5 s behind (offset +1500): raw DT 1.5 s early, estimate +1475.
    let behind: Vec<i64> = CROWD.iter().map(|d| d - 1500).collect();
    let e = estimated(&samples(&names, &behind)).unwrap();
    assert_eq!((e.offset_ms, e.stations), (1475, 12));
    // One station with a bad clock (+1.2 s): votes 13, median 50 (+2050), the bad one
    // is 1150 ms away and trimmed; the estimate stays -2025 at 12 of 13 (92 %).
    let mut bad = ahead.clone();
    bad.push(1200 + 2000);
    let e = estimated(&samples(&names, &bad)).unwrap();
    assert_eq!(
        (e.offset_ms, e.stations, e.heard, e.confidence_pct),
        (-2025, 12, 13, 92)
    );
    // One vote per station: a station decoded twenty times at +2400 counts once.
    let mut chatty = samples(&names[..12], &ahead);
    chatty.extend((0..20).map(|_| ("W1LOUD".to_string(), 2400)));
    let e = estimated(&chatty).unwrap();
    assert_eq!((e.offset_ms, e.stations, e.heard), (-2050, 13, 13));
    // Never from one or two stations; three give an estimate that is not confident.
    assert_eq!(estimated(&samples(&names, &ahead[..2])), None);
    let e = estimated(&samples(&names, &ahead[..3])).unwrap();
    assert_eq!((e.offset_ms, e.stations, e.confident()), (-1850, 3, false));
    // Four agreeing stations are confident.
    assert!(
        estimated(&samples(&names, &[2000, 2100, 2050, 1950]))
            .unwrap()
            .confident()
    );
    // Scattered DT: 5 agree, 4 outliers -> 5 of 9 (55 %) is not confident.
    let e = estimated(&samples(
        &names,
        &[0, 20, -20, 40, -40, 900, -900, 1500, -1500],
    ))
    .unwrap();
    assert_eq!((e.offset_ms, e.stations, e.confidence_pct), (0, 5, 55));
    assert!(!e.confident());
    // A crowd split 1 s apart has no inliers around its median: not confident.
    let e = estimated(&samples(&names, &[0, 0, 0, 0, 1000, 1000, 1000, 1000])).unwrap();
    assert_eq!((e.stations, e.confident()), (0, false));
}

fn standard(from: &str) -> Fields {
    let call = |text: &str, kind| Call {
        kind,
        text: Some(text.into()),
        hash_bits: None,
        hash_value: None,
    };
    Fields::Standard {
        to: call("CQ", CallKind::Token),
        from: call(from, CallKind::Call),
        ack: false,
        exchange: Exchange::Grid("FN42".into()),
    }
}
// Proves: TC-043-001.
#[test]
fn observations_exclude_own_echo_weak_and_implausible_decodes() {
    assert_eq!(sender(&standard("K1ABC")), Some("K1ABC"));
    let hashed = Fields::Standard {
        to: Call {
            kind: CallKind::Call,
            text: Some("HB9BLA".into()),
            hash_bits: None,
            hash_value: None,
        },
        from: Call {
            kind: CallKind::Hash,
            text: None,
            hash_bits: Some(22),
            hash_value: Some(7),
        },
        ack: false,
        exchange: Exchange::Blank(()),
    };
    assert_eq!(sender(&hashed), None, "no station identity");
    assert_eq!(
        sender(&Fields::FreeText {
            value: "TNX 73".into()
        }),
        None
    );
    let mut air = AirClock::default();
    let mut t = 0;
    let mut admit = |call: &str, dt: i64, snr: Option<f64>| {
        t += 10;
        air.observe(t, t, call, "HB9BLA", dt, snr)
    };
    assert!(!admit("HB9BLA", 0, Some(0.0)), "own call");
    assert!(!admit("hb9bla", 0, Some(0.0)), "own call, any case");
    assert!(!admit("K1ABC", 0, Some(-20.5)), "below -20 dB");
    assert!(!admit("K1ABC", 0, None), "no SNR");
    assert!(!admit("K1ABC", 0, Some(f64::NAN)), "invalid SNR");
    assert!(!admit("K1ABC", 3001, Some(0.0)), "implausible DT");
    assert!(!admit("K1ABC", -3001, Some(0.0)), "implausible DT");
    assert!(admit("K1ABC", 3000, Some(-20.0)));
    assert!(admit("K2ABC", -3000, Some(5.0)));
    assert_eq!(
        air.observed(),
        [("K1ABC".to_string(), 3000), ("K2ABC".to_string(), -3000)]
    );
}

/// Feeds one period of the crowd with raw DT `raw(d)` at (mono, system) `t` ms.
fn period(air: &mut AirClock, t: i64, raw: &[i64]) {
    for (call, dt) in calls(raw.len()).iter().zip(raw) {
        air.observe(t, t, call, "HB9BLA", *dt, Some(-5.0));
    }
}
// Proves: TC-043-001.
#[test]
fn admission_follows_confidence_residual_age_and_steps() {
    let ahead: Vec<i64> = CROWD.iter().map(|d| d + 2000).collect();
    let mut air = AirClock::default();
    assert_eq!(air.state(0, 0), ClockState::Unknown, "nothing heard");
    period(&mut air, 0, &ahead);
    // Rate limit: the first completed window moves the correction 1000 ms of 2025.
    assert!(air.period_done(1, 1));
    assert_eq!(air.applied_ms(), -1000);
    assert_eq!(
        air.state(1, 1),
        ClockState::Unsynchronized,
        "residual 1025 ms"
    );
    assert!(air.period_done(2, 2));
    assert_eq!(air.applied_ms(), -2000);
    assert_eq!(air.state(2, 2), ClockState::Synchronized, "residual 25 ms");
    // Hysteresis: 25 ms is not followed.
    assert!(!air.period_done(3, 3));
    assert_eq!(air.applied_ms(), -2000);
    // Age: synchronized up to MAX_AGE_MS after the last estimate, then unknown.
    assert_eq!(
        air.state(3 + MAX_AGE_MS, 3 + MAX_AGE_MS),
        ClockState::Synchronized
    );
    assert_eq!(
        air.state(4 + MAX_AGE_MS, 4 + MAX_AGE_MS),
        ClockState::Unknown
    );
    // A system clock step of 101 ms since the last observation: unknown.
    assert_eq!(air.state(10, 111), ClockState::Unknown);
    assert_eq!(air.state(10, 110), ClockState::Synchronized);
    // The operator steps the 2 s fast system clock back to UTC: the next window forgets
    // the observations from before the step and takes the step out of the correction,
    // so station UTC is continuous (correction 0 for the now correct clock).
    air.period_done(10, 10 - 2000);
    assert!(air.observed().is_empty());
    assert_eq!(air.latest(10), None);
    assert_eq!(air.applied_ms(), 0);
    assert_eq!(air.state(10, 10 - 2000), ClockState::Unknown);
    // A step leaving a correction beyond 3 s restarts from 0.
    let mut far = AirClock::default();
    period(&mut far, 0, &ahead);
    far.period_done(1, 1);
    far.period_done(2, 2);
    far.period_done(3, 3 + 5000);
    assert_eq!(far.applied_ms(), 0);
    // Residual bound 500 ms: offsets -1500 / -1501 after the first 1000 ms step.
    for (offset, expected) in [
        (-1500, ClockState::Synchronized),
        (-1501, ClockState::Unsynchronized),
    ] {
        let mut air = AirClock::default();
        let raw: Vec<i64> = [0, 0, 0, 0, 0].iter().map(|d| d - offset).collect();
        period(&mut air, 0, &raw);
        air.period_done(1, 1);
        assert_eq!(air.applied_ms(), -1000);
        assert_eq!(air.state(1, 1), expected, "offset {offset}");
    }
    // A quiet band (two stations) never synchronizes: transmit is refused, not guessed.
    let mut quiet = AirClock::default();
    period(&mut quiet, 0, &ahead[..2]);
    quiet.period_done(1, 1);
    assert_eq!(
        (quiet.state(1, 1), quiet.applied_ms()),
        (ClockState::Unknown, 0)
    );
    for state in [ClockState::Unknown, ClockState::Unsynchronized] {
        assert_eq!(
            plan_start(Mode::Ft8, 0, state, 0, 48000),
            Err(ScheduleError::ClockNotSynchronized)
        );
    }
    assert!(plan_start(Mode::Ft8, 0, ClockState::Synchronized, 0, 48000).is_ok());
}

// Proves: TC-043-001.
#[test]
fn clock_source_combines_ntp_and_air() {
    use ClockState::*;
    for (ntp, air) in [(Synchronized, Unknown), (Unknown, Synchronized)] {
        assert_eq!(combine(Source::Ntp, ntp, air), (ntp, Basis::Ntp));
        assert_eq!(combine(Source::Air, ntp, air), (air, Basis::Air));
    }
    assert_eq!(
        combine(Source::Both, Synchronized, Unsynchronized),
        (Synchronized, Basis::Ntp)
    );
    assert_eq!(
        combine(Source::Both, Unsynchronized, Synchronized),
        (Synchronized, Basis::Air)
    );
    assert_eq!(
        combine(Source::Both, Unknown, Synchronized),
        (Synchronized, Basis::Air)
    );
    assert_eq!(
        combine(Source::Both, Unsynchronized, Unknown),
        (Unsynchronized, Basis::Air)
    );
    assert_eq!(
        combine(Source::Both, Unknown, Unknown),
        (Unknown, Basis::Air)
    );
    assert_eq!(Source::default(), Source::Ntp);
    assert_eq!(Source::parse("both"), Some(Source::Both));
    assert_eq!(Source::parse("NTP"), None);
}

fn measured(ntp: &Monitor, offset_ms: i64) {
    ntp.record(Some(Measurement {
        server: "ch.pool.ntp.org".into(),
        offset_ms,
        round_trip_ms: 20,
        taken: Instant::now(),
        system: SystemTime::now(),
    }));
}
/// Makes the station clock's air estimate confident at -2025 with -2000 applied.
fn heard(clock: &StationClock) {
    for _ in 0..2 {
        for (call, d) in calls(12).iter().zip(CROWD) {
            clock.observe(call, d + 2000, Some(-3.0));
        }
        clock.period_done();
    }
}
// Proves: TC-043-001.
#[test]
fn station_clock_applies_air_by_source_and_warns_on_disagreement() {
    let ntp = Monitor::new();
    let clock = StationClock::new(ntp.clone(), Source::Ntp);
    clock.set_own_call("HB9BLA");
    clock.observe("HB9BLA", 2000, Some(10.0));
    heard(&clock);
    // NTP source: never corrected, the SNTP state decides (none yet: unknown).
    let v = clock.view();
    assert_eq!(
        (v.state, v.basis, v.correction_ms),
        (ClockState::Unknown, Basis::Ntp, 0)
    );
    assert_eq!(v.air_state, ClockState::Synchronized);
    let (e, age) = v.air.unwrap();
    assert_eq!(
        (e.offset_ms, e.stations, e.heard),
        (-2025, 12, 12),
        "own echo excluded"
    );
    assert!(age < 5_000);
    assert_eq!(clock.correction_ms(), 0);
    // From the air: corrected by the applied -2000 ms and admitted.
    clock.set_source(Source::Air);
    assert_eq!(clock.state(), ClockState::Synchronized);
    assert_eq!(clock.correction_ms(), -2000);
    // Both: NTP synchronized (+12 ms) is preferred, uncorrected; it disagrees with the
    // air by 2037 ms, which is a warning in Both only.
    clock.set_source(Source::Both);
    measured(&ntp, 12);
    let v = clock.view();
    assert_eq!(
        (v.state, v.basis, v.correction_ms),
        (ClockState::Synchronized, Basis::Ntp, 0)
    );
    assert_eq!((v.disagreement_ms, v.warning), (Some(2037), true));
    clock.set_source(Source::Air);
    assert!(!clock.view().warning);
    // Both with NTP measuring the same 2 s error (unsynchronized, -1900 ms): the air
    // corrects; 125 ms apart is no warning, 201 ms is.
    clock.set_source(Source::Both);
    measured(&ntp, -1900);
    let v = clock.view();
    assert_eq!(
        (v.state, v.basis, v.correction_ms),
        (ClockState::Synchronized, Basis::Air, -2000)
    );
    assert_eq!((v.disagreement_ms, v.warning), (Some(125), false));
    measured(&ntp, -2226);
    assert!(clock.view().warning);
    measured(&ntp, -2225);
    assert!(!clock.view().warning, "200 ms is within the bound");
}

/// Live receive coverage of corrected DT (#47 LIVE_WINDOWS: prompt FT8 window DT -1.7 to
/// +0.66 s, late window +0.2 to +2.56 s): a station is decoded only inside it.
const DECODABLE: std::ops::RangeInclusive<i64> = -1700..=2560;
/// Runs `periods` FT8 periods of the crowd plus one station with a bad clock (+1.2 s) on
/// a station clock `offset` ms off: each period decodes the stations whose corrected DT is
/// decodable, feeding raw DT, and completes the prompt and late windows. Returns the
/// applied correction after each period.
fn closed_loop(offset: i64, periods: i64) -> Vec<i64> {
    let mut air = AirClock::default();
    let mut applied = vec![];
    let names = calls(13);
    for p in 0..periods {
        let t = p * 15_000;
        for (call, d) in names.iter().zip(CROWD.iter().chain([1200].iter())) {
            let raw = d - offset;
            if DECODABLE.contains(&(raw + air.applied_ms())) {
                air.observe(t + 13_800, t + 13_800, call, "HB9BLA", raw, Some(-8.0));
            }
        }
        air.period_done(t + 14_000, t + 14_000);
        air.period_done(t + 15_900, t + 15_900);
        applied.push(air.applied_ms());
    }
    applied
}
#[test]
fn applied_correction_converges_without_oscillation() {
    // -2 s: everything is decodable at once; 2 x 1000 ms then the 25 ms hysteresis.
    // +1.5 s: at first only stations with true DT >= -200 ms (and the bad clock) are
    // decodable, a truncated crowd (+1450), then the full crowd (+1475).
    // +2 s (slow clock beyond the late window edge): too few stations decode until the
    // acquisition shift of +1000 ms after four windows, then the full crowd (+1975).
    for (offset, expected) in [
        (-2000, -2025),
        (1500, 1475),
        (600, 575),
        (0, -25),
        (2000, 1975),
    ] {
        let applied = closed_loop(offset, 40);
        let last = *applied.last().unwrap();
        assert!(
            (last - expected).abs() <= 50,
            "offset {offset}: settled at {last}, expected {expected}: {applied:?}"
        );
        let settled = applied.iter().position(|a| *a == last).unwrap();
        assert!(
            settled <= 2,
            "offset {offset}: settled after {settled} periods"
        );
        assert!(
            applied[settled..].iter().all(|a| *a == last),
            "offset {offset}: never moves again: {applied:?}"
        );
        // Monotone approach: the distance to the final value never grows.
        let distance: Vec<i64> = applied.iter().map(|a| (a - last).abs()).collect();
        assert!(distance.windows(2).all(|w| w[1] <= w[0]), "{applied:?}");
    }
    // Outside the capture range (+3 s: at most three stations decodable at 0 or +1000 ms)
    // the station never synchronizes and transmit stays refused.
    let mut air = AirClock::default();
    for p in 0..20 {
        let t = p * 15_000;
        for (call, d) in calls(13).iter().zip(CROWD.iter().chain([1200].iter())) {
            if DECODABLE.contains(&(d - 3000 + air.applied_ms())) {
                air.observe(t, t, call, "HB9BLA", d - 3000, Some(-8.0));
            }
        }
        air.period_done(t + 1, t + 1);
        air.period_done(t + 2, t + 2);
        assert_eq!(air.state(t + 2, t + 2), ClockState::Unknown, "period {p}");
        assert!([0, 1000].contains(&air.applied_ms()));
    }
    // Negative control: estimating from DT that already includes the correction and
    // applying it in full alternates between the error and zero every window.
    let raw: Vec<(String, i64)> = samples(&calls(12), &CROWD.map(|d| d + 2000));
    let mut naive = 0;
    let mut history = vec![];
    for _ in 0..6 {
        let corrected: Vec<(String, i64)> =
            raw.iter().map(|(c, d)| (c.clone(), d + naive)).collect();
        naive = estimated(&corrected).unwrap().offset_ms;
        history.push(naive);
    }
    assert_eq!(history, [-2025, 0, -2025, 0, -2025, 0]);
}
