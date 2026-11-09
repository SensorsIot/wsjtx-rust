#![forbid(unsafe_code)]
// Proves: CL-043-02, CL-043-03, CL-009-05; TC-043-001, TC-043-002, TC-092-001, TC-092-002,
// TC-092-003. The clock from the air is the reference (#92, operator 2026-11-09): votes of
// hand-written DT distributions, the evidence rule (4 stations, 80 % on one side beyond
// 0.1 s), the move toward the middle (at most 1000 ms per period), never unknown, Tx refused
// only beyond 1 s, system clock steps, the SNTP state only warning, and a closed receive
// loop converging without oscillating. Every expected value is hand-computed in the
// comments from the model's rule, never taken from the code under test.
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime};
use wstx_rust::decoder::{Call, CallKind, Exchange, Fields, Mode};
use wstx_rust::transmit::air::{
    AirClock, Estimate, MAX_AGE_MS, StationClock, Warning, estimate, sender, warning,
};
use wstx_rust::transmit::clock::{self, Measurement, Monitor, Sntp, Source};
use wstx_rust::transmit::{ClockState, ScheduleError, plan_start};

use ClockState::{Synchronized, Unsynchronized};

const FT8: i64 = 15_000;
const FT4: i64 = 7_500;
/// True DT of twelve stations with good clocks (ms), median of the twelve = +25 ms.
const CROWD: [i64; 12] = [-250, -150, -100, -50, 0, 0, 50, 100, 150, 200, 300, 400];

fn calls(n: usize) -> Vec<String> {
    (0..n).map(|i| format!("K{i}ABC")).collect()
}
/// One decode window of distinct stations with raw DT `raw`, observed at `t` and completed
/// 200 ms later (monotonic and system time equal: no step). Returns whether it moved.
fn window_at(air: &mut AirClock, t: i64, period_ms: i64, raw: &[i64]) -> bool {
    for (call, dt) in calls(raw.len()).iter().zip(raw) {
        air.observe(t, t, call, "HB9BLA", *dt, Some(-5.0));
    }
    air.period_done(t + 200, t + 200, period_ms)
}
/// The prompt window of FT8 period `p` (completes at +14.0 s).
fn window(air: &mut AirClock, p: i64, raw: &[i64]) -> bool {
    window_at(air, p * FT8 + 13_800, FT8, raw)
}
fn state(air: &AirClock, p: i64) -> ClockState {
    let t = p * FT8 + 14_000;
    air.state(t, t)
}
fn latest(air: &AirClock, p: i64) -> Estimate {
    air.latest(p * FT8 + 14_000).unwrap().0
}
fn crowd(shift: i64) -> Vec<i64> {
    CROWD.iter().map(|d| d + shift).collect()
}

// Proves: TC-043-001, TC-092-001. One vote per station (the median of its raw DT plus the
// correction), the median of all votes without trimming, plus and minus beyond 100 ms.
#[test]
fn votes_median_and_sides_of_known_dt_distributions() {
    let at = |raw: &[i64], correction: i64| {
        let names = calls(raw.len());
        estimate(
            names.iter().map(String::as_str).zip(raw.iter().copied()),
            correction,
        )
    };
    // 2 s ahead: raw 1750..2400, median (2000 + 2050) / 2 = 2025, all twelve plus.
    let e = at(&crowd(2000), 0).unwrap();
    assert_eq!(
        (e.median_dt_ms, e.stations, e.plus, e.minus, e.evidence()),
        (2025, 12, 12, 0, true)
    );
    // With the correction -2000 applied the votes are the true DT: median 25, plus
    // 150/200/300/400, minus -250/-150 (-100 is not beyond the margin): mixed.
    let e = at(&crowd(2000), -2000).unwrap();
    assert_eq!(
        (e.median_dt_ms, e.plus, e.minus, e.evidence()),
        (25, 4, 2, false)
    );
    // One vote per station: a station decoded twenty times at +2400 counts once (13 votes,
    // the 7th of 1750,1850,1900,1950,2000,2000,2050,2100,2150,2200,2300,2400,2400 = 2050).
    let mut chatty: Vec<(String, i64)> = calls(12).into_iter().zip(crowd(2000)).collect();
    chatty.extend((0..20).map(|_| ("W1LOUD".to_string(), 2400)));
    let e = estimate(chatty.iter().map(|(c, d)| (c.as_str(), *d)), 0).unwrap();
    assert_eq!((e.median_dt_ms, e.stations), (2050, 13));
    // No estimate without a vote; two and three stations are no evidence.
    assert_eq!(at(&[], 0), None);
    assert!(!at(&[1850; 2], 0).unwrap().evidence());
    assert!(!at(&[1850; 3], 0).unwrap().evidence());
    assert!(at(&[1850; 4], 0).unwrap().evidence());
    // Five at +1850 among nine (55 %): no evidence; a crowd split at -500/+500 (50 %): none.
    assert!(
        !at(&[1850, 1850, 1850, 1850, 1850, 0, 20, -20, 40], 0)
            .unwrap()
            .evidence()
    );
    let split = at(&[-500, -500, -500, -500, 500, 500, 500, 500], 0).unwrap();
    assert_eq!(
        (
            split.median_dt_ms,
            split.plus,
            split.minus,
            split.evidence()
        ),
        (0, 4, 4, false)
    );
    // An even count: the floor of the mean of the middle pair, (-339 + -50) / 2 = -194.5.
    assert_eq!(at(&[-339, -50], 0).unwrap().median_dt_ms, -195);
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

// Proves: TC-043-001. The crowds of TC-043-001 over successive FT8 periods.
#[test]
fn crowds_move_the_correction_to_the_middle_and_keep_it() {
    // 2 s ahead: median +2025 -> -1000 (unsynchronized, 2025 > 1000); votes then median
    // +1025 -> -2000 (still unsynchronized: 1025 > 1000); then votes median +25, 4 plus and
    // 2 minus (mixed): -2000 kept, synchronized.
    let mut air = AirClock::default();
    assert!(window(&mut air, 0, &crowd(2000)));
    assert_eq!((air.applied_ms(), state(&air, 0)), (-1000, Unsynchronized));
    assert!(window(&mut air, 1, &crowd(2000)));
    assert_eq!(latest(&air, 1).median_dt_ms, 1025);
    assert_eq!((air.applied_ms(), state(&air, 1)), (-2000, Unsynchronized));
    assert!(!window(&mut air, 2, &crowd(2000)));
    let e = latest(&air, 2);
    assert_eq!((e.median_dt_ms, e.plus, e.minus), (25, 4, 2));
    assert_eq!((air.applied_ms(), state(&air, 2)), (-2000, Synchronized));
    // 1.5 s behind: median -1475 -> +1000 (unsynchronized); then votes -750..-100 with 11
    // of 12 minus (evidence), median -475 -> +1475; then 4 plus and 3 minus: kept.
    let mut air = AirClock::default();
    window(&mut air, 0, &crowd(-1500));
    assert_eq!((air.applied_ms(), state(&air, 0)), (1000, Unsynchronized));
    window(&mut air, 1, &crowd(-1500));
    let e = latest(&air, 1);
    assert_eq!((e.median_dt_ms, e.minus, e.stations), (-475, 11, 12));
    assert_eq!((air.applied_ms(), state(&air, 1)), (1475, Synchronized));
    assert!(!window(&mut air, 2, &crowd(-1500)));
    let e = latest(&air, 2);
    assert_eq!((e.plus, e.minus, air.applied_ms()), (4, 3, 1475));
    // With a bad clock at raw +800: 13 votes all plus, the 7th of 800,1750,...,2400 is
    // +2000 -> -1000; then -200 and 750..1400 (12 of 13 plus), median +1000 -> -2000;
    // then -1200 and the true DT: 4 plus, 3 minus: kept.
    let mut bad = crowd(2000);
    bad.push(800);
    let mut air = AirClock::default();
    window(&mut air, 0, &bad);
    assert_eq!(
        (latest(&air, 0).median_dt_ms, latest(&air, 0).plus),
        (2000, 13)
    );
    assert_eq!(air.applied_ms(), -1000);
    window(&mut air, 1, &bad);
    assert_eq!(air.applied_ms(), -2000);
    window(&mut air, 2, &bad);
    let e = latest(&air, 2);
    assert_eq!((e.plus, e.minus, air.applied_ms()), (4, 3, -2000));
    // Two and three stations at +1850: no evidence, 0; four: -1000 then -1850.
    for n in [2, 3] {
        let mut air = AirClock::default();
        assert!(!window(&mut air, 0, &vec![1850; n]));
        assert_eq!((air.applied_ms(), state(&air, 0)), (0, Synchronized));
    }
    let mut air = AirClock::default();
    window(&mut air, 0, &[1850; 4]);
    assert_eq!(air.applied_ms(), -1000);
    window(&mut air, 1, &[1850; 4]);
    assert_eq!(air.applied_ms(), -1850);
    // Five of nine (55 %) and the split crowd (50 %): no change.
    for raw in [
        vec![1850, 1850, 1850, 1850, 1850, 0, 20, -20, 40],
        vec![-500, -500, -500, -500, 500, 500, 500, 500],
    ] {
        let mut air = AirClock::default();
        assert!(!window(&mut air, 0, &raw));
        assert_eq!(air.applied_ms(), 0);
    }
    // A quiet band after the correction keeps it, synchronized.
    let mut air = AirClock::default();
    for p in 0..3 {
        window(&mut air, p, &crowd(2000));
    }
    for p in 3..25 {
        window(&mut air, p, &[]);
        assert_eq!((air.applied_ms(), state(&air, p)), (-2000, Synchronized));
    }
    // That 2 s ahead estimate (median +2025) with no further window: unsynchronized at
    // 60 s, synchronized at 60 s + 1 ms; the correction -1000 both times.
    let mut air = AirClock::default();
    window(&mut air, 0, &crowd(2000));
    let done = 14_000;
    assert_eq!(
        air.state(done + MAX_AGE_MS, done + MAX_AGE_MS),
        Unsynchronized
    );
    assert_eq!(
        air.state(done + MAX_AGE_MS + 1, done + MAX_AGE_MS + 1),
        Synchronized
    );
    assert_eq!(air.applied_ms(), -1000);
}

// Proves: TC-043-001. System clock steps with correction -2000 ms.
#[test]
fn system_clock_steps_keep_station_utc_continuous() {
    let corrected = || {
        let mut air = AirClock::default();
        for p in 0..3 {
            window(&mut air, p, &crowd(2000));
        }
        assert_eq!(air.applied_ms(), -2000);
        air
    };
    let t = 3 * FT8;
    // 100 ms: nothing changes; 101 ms forward: the window is cleared, -2000 - 101 = -2101.
    let mut air = corrected();
    air.observe(t, t + 100, "K1ABC", "HB9BLA", 2000, Some(-5.0));
    assert_eq!((air.observed().len(), air.applied_ms()), (37, -2000));
    let mut air = corrected();
    air.observe(t, t + 101, "K1ABC", "HB9BLA", 2000, Some(-5.0));
    assert_eq!((air.observed().len(), air.applied_ms()), (1, -2101));
    assert_eq!(air.latest(t), None);
    // The 2 s fast system clock stepped back to UTC: -2000 - (-2000) = 0.
    let mut air = corrected();
    air.period_done(t, t - 2000, FT8);
    assert_eq!(air.applied_ms(), 0);
    assert!(air.observed().is_empty());
    // A +5 s step: -7000 is beyond 3000 ms, restart at 0.
    let mut air = corrected();
    air.period_done(t, t + 5000, FT8);
    assert_eq!(air.applied_ms(), 0);
    // Only synchronized plans a transmit start.
    for state in [ClockState::Unknown, Unsynchronized] {
        assert_eq!(
            plan_start(Mode::Ft8, 0, state, 0, 48000),
            Err(ScheduleError::ClockNotSynchronized)
        );
    }
    assert!(plan_start(Mode::Ft8, 0, Synchronized, 0, 48000).is_ok());
}

// Proves: TC-092-001. The evidence rule, case by case from start (correction 0).
#[test]
fn evidence_rule_of_the_clock_from_the_air() {
    let fresh = |raw: &[i64]| {
        let mut air = AirClock::default();
        window(&mut air, 0, raw);
        air
    };
    // No station: no estimate; three at +1500: no evidence; correction 0, synchronized.
    let mut air = AirClock::default();
    assert!(!air.period_done(14_000, 14_000, FT8));
    assert_eq!(
        (air.latest(14_000), air.applied_ms(), state(&air, 0)),
        (None, 0, Synchronized)
    );
    let air = fresh(&[1500; 3]);
    assert_eq!((air.applied_ms(), state(&air, 0)), (0, Synchronized));
    // Four at +1500: -1000 (unsynchronized: 1500 > 1000), then votes +500: -1500, synchronized.
    let mut air = fresh(&[1500; 4]);
    assert_eq!((air.applied_ms(), state(&air, 0)), (-1000, Unsynchronized));
    window(&mut air, 1, &[1500; 4]);
    assert_eq!(latest(&air, 1).median_dt_ms, 500);
    assert_eq!((air.applied_ms(), state(&air, 1)), (-1500, Synchronized));
    // 15 of 19 at +600 (78.9 %): no change; 16 of 20 (80 %): median +600 -> -600.
    let mixed = |plus: usize| [vec![600; plus], vec![-600; 4]].concat();
    assert_eq!(fresh(&mixed(15)).applied_ms(), 0);
    assert_eq!(fresh(&mixed(16)).applied_ms(), -600);
    // Four at +-100 are not beyond the margin; +-101 are.
    for (dt, expected) in [(100, 0), (101, -101), (-100, 0), (-101, 101)] {
        assert_eq!(fresh(&[dt; 4]).applied_ms(), expected, "four at {dt}");
    }
    // Four +600 and four -600: mixed.
    assert_eq!(
        fresh(&[600, 600, 600, 600, -600, -600, -600, -600]).applied_ms(),
        0
    );
    // Four at +1000: synchronized, -1000; at +1001: unsynchronized until the next estimate
    // (votes +1, no evidence: synchronized, -1000 kept).
    let air = fresh(&[1000; 4]);
    assert_eq!((air.applied_ms(), state(&air, 0)), (-1000, Synchronized));
    let mut air = fresh(&[1001; 4]);
    assert_eq!((air.applied_ms(), state(&air, 0)), (-1000, Unsynchronized));
    window(&mut air, 1, &[1001; 4]);
    assert_eq!(latest(&air, 1).median_dt_ms, 1);
    assert_eq!((air.applied_ms(), state(&air, 1)), (-1000, Synchronized));
    // Four at +2500, two windows in the first period: -1000 (the second window adds
    // nothing), -2000 (median +1500, unsynchronized), -2500 (median +500, synchronized).
    let mut air = AirClock::default();
    assert!(window_at(&mut air, 12_000, FT8, &[2500; 4]));
    assert!(!window_at(&mut air, 14_500, FT8, &[2500; 4]));
    assert_eq!(air.applied_ms(), -1000);
    window(&mut air, 1, &[2500; 4]);
    assert_eq!(
        (
            latest(&air, 1).median_dt_ms,
            air.applied_ms(),
            state(&air, 1)
        ),
        (1500, -2000, Unsynchronized)
    );
    window(&mut air, 2, &[2500; 4]);
    assert_eq!(
        (
            latest(&air, 2).median_dt_ms,
            air.applied_ms(),
            state(&air, 2)
        ),
        (500, -2500, Synchronized)
    );
    // A quiet band for 20 periods after -1500: kept, synchronized, no alternation.
    let mut air = fresh(&[1500; 4]);
    window(&mut air, 1, &[1500; 4]);
    for p in 2..22 {
        window(&mut air, p, &[]);
        assert_eq!(
            (air.applied_ms(), state(&air, p)),
            (-1500, Synchronized),
            "period {p}"
        );
    }
    // Four votes at +1500 in one window, then none: unsynchronized at 60 s, synchronized at
    // 60 s + 1 ms, -1000 both times.
    let air = fresh(&[1500; 4]);
    let done = 14_000 + MAX_AGE_MS;
    assert_eq!(
        (air.state(done, done), air.applied_ms()),
        (Unsynchronized, -1000)
    );
    assert_eq!(
        (air.state(done + 1, done + 1), air.applied_ms()),
        (Synchronized, -1000)
    );
    // Observations count at 120 s and not at 120 s + 1 ms.
    for (age, counted) in [(120_000, Some(4)), (120_001, None)] {
        let mut air = AirClock::default();
        for call in calls(4) {
            air.observe(0, 0, &call, "HB9BLA", 1500, Some(-5.0));
        }
        air.period_done(age, age, FT8);
        assert_eq!(
            air.latest(age).map(|(e, _)| e.stations),
            counted,
            "age {age}"
        );
    }
    // A 100 ms step changes nothing, a 101 ms step clears the window.
    let mut air = fresh(&[1500; 4]);
    air.observe(20_000, 20_100, "K9ABC", "HB9BLA", 0, Some(-5.0));
    assert_eq!((air.observed().len(), air.applied_ms()), (5, -1000));
    air.observe(30_000, 30_201, "K9ABC", "HB9BLA", 0, Some(-5.0));
    assert_eq!(air.observed().len(), 1);
    // With correction -1000: a forward step of 2000 leaves -3000, of 2001 restarts at 0.
    for (step, expected) in [(2000, -3000), (2001, 0)] {
        let mut air = fresh(&[1500; 4]);
        air.period_done(20_000, 20_000 + step, FT8);
        assert_eq!(air.applied_ms(), expected, "step {step}");
    }
    // With correction 0 a +525 ms step leaves 0.
    let mut air = AirClock::default();
    air.period_done(1_000, 1_000, FT8);
    air.period_done(2_000, 2_525, FT8);
    assert_eq!(air.applied_ms(), 0);
}

fn measured(offset_ms: i64) -> Measurement {
    Measurement {
        server: "ch.pool.ntp.org".into(),
        offset_ms,
        round_trip_ms: 20,
        taken: Instant::now(),
        system: SystemTime::now(),
    }
}
/// A station clock on `ntp` and the (monotonic, system) base of its estimator.
fn station(ntp: &Arc<Monitor>) -> (Arc<StationClock>, i64, i64) {
    let clock = StationClock::new(ntp.clone());
    clock.set_own_call("HB9BLA");
    let (mono, system) = clock.now_ms();
    (clock, mono, system)
}
/// Window `k` of `period_ms` periods on the station clock's own time base (consistent with
/// its reads: no step).
fn heard(clock: &StationClock, base: (i64, i64), k: i64, period_ms: i64, raw: &[i64]) {
    let t = k * period_ms + period_ms - 1000;
    clock.with_air(|a| {
        for (call, dt) in calls(raw.len()).iter().zip(raw) {
            a.observe(base.0 + t, base.1 + t, call, "HB9BLA", *dt, Some(-5.0));
        }
        a.period_done(base.0 + t + 200, base.1 + t + 200, period_ms);
    });
}

// Proves: TC-043-001. The 2 s ahead crowd gives the same correction and state with SNTP
// +12 ms, -1900 ms and none (never applied); only the warning differs.
#[test]
fn sntp_is_never_applied_and_only_warns() {
    let mut seen = vec![];
    for sntp in [Some(12), Some(-1900), None] {
        let ntp = Monitor::new();
        if let Some(offset) = sntp {
            ntp.record(Some(measured(offset)));
        }
        let (clock, m, s) = station(&ntp);
        for k in 0..3 {
            heard(&clock, (m, s), k, FT8, &crowd(2000));
        }
        let v = clock.view();
        seen.push((v.state, v.correction_ms, v.warning));
    }
    assert_eq!(
        seen,
        [
            (Synchronized, -2000, Some(Warning::StationsOff)),
            (Synchronized, -2000, Some(Warning::PcClockOff)),
            (Synchronized, -2000, None),
        ]
    );
}

/// Live receive coverage of corrected DT (#47 LIVE_WINDOWS: prompt FT8 window DT -1.7 to
/// +0.66 s, late window +0.2 to +2.56 s): a station is decoded only inside it.
const DECODABLE: std::ops::RangeInclusive<i64> = -1700..=2560;
/// Runs `periods` FT8 periods of the crowd plus one station with a bad clock (+1.2 s) on
/// a station clock `offset` ms off: each period decodes the stations whose corrected DT is
/// decodable, feeding raw DT, and completes the prompt (+14.0 s) and late (+15.9 s, in the
/// next period) windows. Returns the applied correction after each period.
fn closed_loop(offset: i64, periods: i64) -> (Vec<i64>, Vec<ClockState>) {
    let mut air = AirClock::default();
    let (mut applied, mut states) = (vec![], vec![]);
    let names = calls(13);
    for p in 0..periods {
        let t = p * FT8;
        for (call, d) in names.iter().zip(CROWD.iter().chain([1200].iter())) {
            let raw = d - offset;
            if DECODABLE.contains(&(raw + air.applied_ms())) {
                air.observe(t + 13_800, t + 13_800, call, "HB9BLA", raw, Some(-8.0));
            }
        }
        air.period_done(t + 14_000, t + 14_000, FT8);
        air.period_done(t + 15_900, t + 15_900, FT8);
        applied.push(air.applied_ms());
        states.push(air.state(t + 15_900, t + 15_900));
    }
    (applied, states)
}
// Proves: TC-043-002. Hand-computed: -2 s settles at -2000 (2025, then 1025 -> -1000 each,
// then mixed); +1.5 s at +1425 (11 crowd plus the bad clock at -1425 -> +1000, then -425 ->
// +425, then 4 plus 4 minus); +0.6 s at +550 (12 of 13 minus, 7th vote -550, then mixed); 0
// keeps 0 (5 of 13 plus); +2 s and +3 s decode at most three stations: 0, synchronized.
#[test]
fn applied_correction_converges_without_oscillation() {
    for (offset, settled_at) in [(-2000, -2000), (1500, 1425), (600, 550)] {
        let (applied, _) = closed_loop(offset, 40);
        let last = *applied.last().unwrap();
        assert_eq!(last, settled_at, "offset {offset}: {applied:?}");
        assert!(
            (last - (offset - 25)).abs() <= 50,
            "within 50 ms of the error - 25 ms"
        );
        let settled = applied.iter().position(|a| *a == last).unwrap();
        assert!(
            settled <= 2,
            "offset {offset}: settled after {settled} periods"
        );
        assert!(applied[settled..].iter().all(|a| *a == last), "{applied:?}");
        let distance: Vec<i64> = applied.iter().map(|a| (a - last).abs()).collect();
        assert!(distance.windows(2).all(|w| w[1] <= w[0]), "{applied:?}");
    }
    let (applied, _) = closed_loop(0, 20);
    assert!(applied.iter().all(|a| *a == 0), "{applied:?}");
    for offset in [2000, 3000] {
        let (applied, states) = closed_loop(offset, 20);
        assert!(
            applied.iter().all(|a| *a == 0),
            "offset {offset}: {applied:?}"
        );
        assert!(states.iter().all(|s| *s == Synchronized), "offset {offset}");
    }
    // Negative control: estimating from DT that already includes the correction and
    // applying it in full alternates between the error and zero every window.
    let names = calls(12);
    let mut naive = 0;
    let mut history = vec![];
    for _ in 0..6 {
        let corrected: Vec<i64> = crowd(2000).iter().map(|d| d + naive).collect();
        naive = -estimate(names.iter().map(String::as_str).zip(corrected), 0)
            .unwrap()
            .median_dt_ms;
        history.push(naive);
    }
    assert_eq!(history, [-2025, 0, -2025, 0, -2025, 0]);
}

// Proves: TC-092-002. The 10 m FT4 refusals of 2026-11-09 replayed: SNTP +525 ms
// (unsynchronized), four at -339, one at -50 and one at +100 (4 of 6 = 66 %): no change;
// five at -339 and one at +100 (5 of 6 = 83 %): median -339, +339; then 2 and no stations:
// +339 kept; synchronized and every start planned in each window, pc_clock_off throughout.
#[test]
fn replay_of_the_ft4_refusals_of_2026_11_09() {
    let ntp = Monitor::new();
    ntp.record(Some(measured(525)));
    let (clock, m, s) = station(&ntp);
    let check = |expected: i64| {
        let v = clock.view();
        assert_eq!(
            (v.state, v.correction_ms, v.warning),
            (Synchronized, expected, Some(Warning::PcClockOff))
        );
        assert!(plan_start(Mode::Ft4, 0, clock.state(), 0, 48000).is_ok());
    };
    let first = [-339, -339, -339, -339, -50, 100];
    for k in 0..3 {
        heard(&clock, (m, s), k, FT4, &first);
        check(0);
    }
    // More than 120 s later (the first crowd has left the window).
    let second = [-339, -339, -339, -339, -339, 100];
    heard(&clock, (m, s), 20, FT4, &second);
    let e = clock.view().air.unwrap().0;
    assert_eq!((e.median_dt_ms, e.minus, e.stations), (-339, 5, 6));
    check(339);
    for k in 40..43 {
        heard(&clock, (m, s), k, FT4, &[-339, 100]);
        check(339);
    }
    for k in 60..84 {
        heard(&clock, (m, s), k, FT4, &[]);
        check(339);
    }
}

/// A measurement `age` old at `now`, describing system time `system - age`.
fn aged(offset_ms: i64, now: Instant, system: SystemTime, age: Duration) -> Measurement {
    Measurement {
        server: "ch.pool.ntp.org".into(),
        offset_ms,
        round_trip_ms: 20,
        taken: now - age,
        system: system - age,
    }
}
// Proves: TC-092-003. The three situations on the station clock with a fake SNTP monitor:
// votes correct on every SNTP state, the warnings by TransmitClock's 500 ms / 600 s / 100 ms,
// SNTP never applied, steps leave a correction of 0 at 0.
#[test]
fn three_situations_correction_state_and_warnings() {
    // SNTP +12 (synchronized): four at +1500 -> -1000, -1500, stations_off.
    let ntp = Monitor::new();
    ntp.record(Some(measured(12)));
    let (clock, m, s) = station(&ntp);
    heard(&clock, (m, s), 0, FT8, &[1500; 4]);
    assert_eq!(clock.view().correction_ms, -1000);
    heard(&clock, (m, s), 1, FT8, &[1500; 4]);
    let v = clock.view();
    assert_eq!(
        (v.state, v.correction_ms, v.warning),
        (Synchronized, -1500, Some(Warning::StationsOff))
    );
    // stations_off: null at -500, set at -501 (four at +500 / +501 with SNTP +12).
    for (dt, expected) in [(500, None), (501, Some(Warning::StationsOff))] {
        let (clock, m, s) = station(&ntp);
        heard(&clock, (m, s), 0, FT8, &[dt; 4]);
        let v = clock.view();
        assert_eq!((v.correction_ms, v.warning), (-dt, expected), "{dt}");
    }
    // SNTP +500 null, +501 pc_clock_off; correction 0 and state synchronized unchanged.
    for (offset, expected) in [
        (500, None),
        (501, Some(Warning::PcClockOff)),
        (-1900, Some(Warning::PcClockOff)),
    ] {
        let ntp = Monitor::new();
        ntp.record(Some(measured(offset)));
        let v = StationClock::new(ntp).view();
        assert_eq!(
            (v.state, v.correction_ms, v.warning),
            (Synchronized, 0, expected),
            "{offset}"
        );
    }
    // One round asked, no answer, no measurement: ntp_unreachable, synchronized.
    let ntp = Monitor::new();
    ntp.round(true, None);
    let v = StationClock::new(ntp).view();
    assert_eq!(
        (v.state, v.warning),
        (Synchronized, Some(Warning::NtpUnreachable))
    );
    // No round yet, and an empty server list (its rounds ask none): no warning.
    assert_eq!(StationClock::new(Monitor::new()).view().warning, None);
    let empty = Sntp {
        servers: vec![],
        timeout: Duration::from_millis(10),
        now: SystemTime::now,
    };
    assert!(!empty.asks());
    let ntp = Monitor::new();
    ntp.round(empty.asks(), None);
    assert_eq!(StationClock::new(ntp).view().warning, None);
    // A measurement 600 s old after failed rounds: still synchronized, null; 600 s + 1 ms:
    // unknown, ntp_unreachable. A 101 ms step with a young measurement: unknown, null.
    let (now, system) = (Instant::now(), SystemTime::now());
    for (age, ntp_state, expected) in [
        (Duration::from_secs(600), Synchronized, None),
        (
            Duration::from_millis(600_001),
            ClockState::Unknown,
            Some(Warning::NtpUnreachable),
        ),
    ] {
        let m = aged(12, now, system, age);
        assert_eq!(clock::state(Some(&m), now, system), ntp_state);
        assert_eq!(warning(ntp_state, Some(age), true, 0), expected, "{age:?}");
    }
    let young = aged(12, now, system, Duration::from_secs(5));
    let stepped = clock::state(Some(&young), now, system + Duration::from_millis(101));
    assert_eq!(stepped, ClockState::Unknown);
    assert_eq!(
        warning(stepped, Some(Duration::from_secs(5)), true, 0),
        None
    );
    // System clock steps of +300 and -300 ms with correction 0 leave 0.
    for step in [300, -300] {
        let mut air = AirClock::default();
        window(&mut air, 0, &[0, 20, -20, 300, -300, 600]);
        air.period_done(20_000, 20_000 + step, FT8);
        assert_eq!(air.applied_ms(), 0, "{step}");
    }
    // The 2026-11-09 recovery: SNTP +525 with the mixed crowd of TC-092-002 (0,
    // pc_clock_off); Windows Time steps the system clock +525 ms (correction 0 stays 0; the
    // SNTP step gap is unknown with a young measurement: null); the next round +3 ms: null.
    let mut air = AirClock::default();
    window(&mut air, 0, &[-339, -339, -339, -339, -50, 100]);
    let before = aged(525, now, system, Duration::from_secs(10));
    let s = clock::state(Some(&before), now, system);
    assert_eq!(
        (
            air.applied_ms(),
            warning(s, Some(Duration::from_secs(10)), true, 0)
        ),
        (0, Some(Warning::PcClockOff))
    );
    air.observe(20_000, 20_525, "K1ABC", "HB9BLA", -339, Some(-5.0));
    assert_eq!(air.applied_ms(), 0);
    let gap = clock::state(Some(&before), now, system + Duration::from_millis(525));
    assert_eq!(
        (gap, warning(gap, Some(Duration::from_secs(10)), true, 0)),
        (ClockState::Unknown, None)
    );
    let after = aged(3, now, system, Duration::ZERO);
    let s = clock::state(Some(&after), now, system);
    assert_eq!(
        (s, warning(s, Some(Duration::ZERO), true, 0)),
        (Synchronized, None)
    );
    assert_eq!(
        (air.applied_ms(), air.state(20_000, 20_525)),
        (0, Synchronized)
    );
    // Correction -2000 is kept through every SNTP change (SNTP never resets it).
    let ntp = Monitor::new();
    let (clock, m, s) = station(&ntp);
    for k in 0..3 {
        heard(&clock, (m, s), k, FT8, &crowd(2000));
    }
    for offset in [12, 600, 12] {
        ntp.record(Some(measured(offset)));
        assert_eq!(clock.view().correction_ms, -2000, "SNTP {offset}");
    }
}

// The real Windows Time service query (W32Time, query rights only, no administrator rights)
// reads a state on the development PC, where Windows Time runs; a query asking for more
// rights than a user holds (for example SERVICE_START) fails and reads unknown.
// Proves: CL-043-03, TC-092-003.
#[cfg(windows)]
#[test]
fn windows_time_service_state_is_read_without_administrator_rights() {
    let state = clock::windows_time();
    assert_ne!(state, clock::WindowsTime::Unknown);
    assert_eq!(
        StationClock::new(Monitor::new()).windows_time(),
        state,
        "the station clock's default reader is the real query"
    );
}

/// A source whose rounds ask a server that never answers.
struct Silent;
impl Source for Silent {
    fn measure(&mut self) -> Option<Measurement> {
        None
    }
}
// Proves: TC-092-003. The measuring thread records whether its rounds asked a server.
#[test]
fn rounds_record_whether_a_server_was_asked() {
    let asking = Monitor::start(Box::new(Silent), Duration::from_millis(5)).unwrap();
    let empty = Monitor::start(
        Box::new(Sntp {
            servers: vec![],
            timeout: Duration::from_millis(10),
            now: SystemTime::now,
        }),
        Duration::from_millis(5),
    )
    .unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    while !asking.asked() {
        assert!(Instant::now() < deadline, "no round asked");
        std::thread::sleep(Duration::from_millis(5));
    }
    std::thread::sleep(Duration::from_millis(50));
    assert!(!empty.asked());
    assert_eq!(
        StationClock::new(asking).view().warning,
        Some(Warning::NtpUnreachable)
    );
    assert_eq!(StationClock::new(empty).view().warning, None);
}
