#![forbid(unsafe_code)]
// WstxStrategy::FreeTxSlot worked by hand: compared values in dB per candidate written here, the
// detailed bin of 12000/4096 Hz, and the operator's rule (lowest whole dB, a tie keeps the current
// Tx, else nearer, then lower; 50 Hz from the called station and from his decoded frequencies;
// #66: my Rx periods only, the recent ones, each slot's largest rise above the WSJT-X passband
// floor, clear of the stations decoded in them). A flat floor F is its own lowest tenth in every
// segment, so its fit is F exactly and the floor F + 0.65 dB.
use super::*;
use crate::automation_tests::due_at;

/// A value table: `floor` everywhere, the listed candidates at their own value.
fn table(floor: f64, levels: &[(u32, f64)]) -> impl Fn(u32) -> Option<f64> {
    let levels = levels.to_vec();
    move |f| {
        Some(
            levels
                .iter()
                .find(|(hz, _)| *hz == f)
                .map_or(floor, |(_, level)| *level),
        )
    }
}
fn ft8(
    current: u32,
    called: Option<u32>,
    his: Option<&[u32]>,
    power: &dyn Fn(u32) -> Option<f64>,
) -> Slot {
    quietest(Mode::Ft8, current, called, &[], his, power)
}
fn slot(hz: u32, power_db: Option<i64>, his_end: HisEnd) -> Slot {
    Slot {
        hz,
        power_db,
        his_end,
    }
}

// Proves: TC-039-010. One lowest slot wins; the current Tx tying it is kept; two lowest without
// the current Tx: the nearer to it, at equal distance the lower.
#[test]
fn tc_039_010_the_lowest_power_wins_and_a_tie_keeps_the_current_tx() {
    use HisEnd::Unknown;
    assert_eq!(
        ft8(1500, None, None, &table(40.0, &[(1800, 20.0)])),
        slot(1800, Some(20), Unknown)
    );
    assert_eq!(
        ft8(
            1500,
            None,
            None,
            &table(40.0, &[(1800, 20.0), (1500, 20.0)])
        ),
        slot(1500, Some(20), Unknown),
        "the current Tx among the quietest stays"
    );
    assert_eq!(
        ft8(
            1500,
            None,
            None,
            &table(40.0, &[(1800, 20.0), (1300, 20.0)])
        ),
        slot(1300, Some(20), Unknown),
        "200 Hz away before 300 Hz away"
    );
    assert_eq!(
        ft8(
            1500,
            None,
            None,
            &table(40.0, &[(1700, 20.0), (1300, 20.0)])
        ),
        slot(1300, Some(20), Unknown),
        "equally near: the lower"
    );
    // A current Tx off the 10 Hz grid is a candidate itself.
    assert_eq!(
        ft8(
            1505,
            None,
            None,
            &table(40.0, &[(1505, 20.0), (1300, 20.0)])
        ),
        slot(1505, Some(20), Unknown)
    );
}

// Proves: TC-039-010, TC-039-022. Power compares in whole dB: 40.4 and 40.0 are one dB and tie, so
// the current Tx stays (the slot check keeps a tied slot); 40.6 is 41 dB and loses to 40.0. There is
// no threshold beyond that.
#[test]
fn tc_039_010_whole_db_decides_the_tie() {
    let tied = table(50.0, &[(1500, 40.4), (1800, 40.0)]);
    assert_eq!(
        ft8(1500, None, None, &tied),
        slot(1500, Some(40), HisEnd::Unknown)
    );
    let louder = table(50.0, &[(1500, 40.6), (1800, 40.0)]);
    assert_eq!(
        ft8(1500, None, None, &louder),
        slot(1800, Some(40), HisEnd::Unknown)
    );
    // 41 dB against 40 dB moves, however close.
    let one = table(50.0, &[(1500, 41.0), (1510, 40.0)]);
    assert_eq!(ft8(1500, None, None, &one).hz, 1510);
    // #66: a rise at or under the floor is free, 0: -2 at 1500 and -5 at 1800 tie, the current Tx
    // stays with power_db 0; free (-0.6) beats 0.6 (1 dB).
    let under = table(50.0, &[(1500, -2.0), (1800, -5.0)]);
    assert_eq!(
        ft8(1500, None, None, &under),
        slot(1500, Some(0), HisEnd::Unknown)
    );
    let free = table(50.0, &[(1500, 0.6), (1800, -0.6)]);
    assert_eq!(
        ft8(1500, None, None, &free),
        slot(1800, Some(0), HisEnd::Unknown)
    );
}

// Proves: TC-039-010. The range edges: FT8 300..2650 and FT4 300..2610 (90 Hz wide), my whole
// signal below 2700 Hz; a quiet slot outside is never taken.
#[test]
fn tc_039_010_never_outside_the_tx_range() {
    let edges = table(40.0, &[(290, 0.0), (300, 20.0), (2650, 20.0), (2660, 0.0)]);
    assert_eq!(
        ft8(2600, None, None, &edges).hz,
        2650,
        "the upper edge, nearer"
    );
    assert_eq!(
        ft8(400, None, None, &edges).hz,
        300,
        "the lower edge, nearer"
    );
    let ft4 = table(40.0, &[(2610, 20.0), (2620, 0.0), (2650, 0.0)]);
    assert_eq!(
        quietest(Mode::Ft4, 1500, None, &[], None, &ft4),
        slot(2610, Some(20), HisEnd::Unknown)
    );
    // A current Tx outside the range is no candidate.
    let outside = table(40.0, &[(2700, 0.0)]);
    assert_eq!(ft8(2700, None, None, &outside).hz, 2650);
    assert_eq!(band(Mode::Ft8), (300, 2650));
    assert_eq!(band(Mode::Ft4), (300, 2610));
}

// Proves: TC-039-010. Never within 50 Hz of the called station's signal: an FT8 station at 1800
// forbids 1710..1890 (my 50 Hz signal keeps 50 Hz from its 50 Hz), so the quietest away from it.
#[test]
fn tc_039_010_never_within_50_hz_of_the_called_station() {
    let quiet_on_him = table(
        40.0,
        &[
            (1800, 10.0),
            (1760, 10.0),
            (1850, 10.0),
            (1700, 20.0),
            (1900, 20.0),
        ],
    );
    assert_eq!(
        ft8(1500, Some(1800), None, &quiet_on_him),
        slot(1700, Some(20), HisEnd::Unknown),
        "1700 and 1900 tie; 1700 is nearer to 1500"
    );
    // FT4 is 90 Hz wide: a station at 1800 forbids 1661..1939.
    let ft4 = table(
        40.0,
        &[(1660, 20.0), (1670, 10.0), (1930, 10.0), (1940, 15.0)],
    );
    assert_eq!(
        quietest(Mode::Ft4, 1500, Some(1800), &[], None, &ft4).hz,
        1940
    );
}

// Proves: TC-039-010. His end: a frequency he decodes (of my Tx parity, chosen by the feed) within
// 50 Hz excludes the slot, 50 Hz away does not; when every candidate is excluded his end is not
// used and the status says no; none known: unknown.
#[test]
fn tc_039_010_his_end_excludes_and_is_ignored_when_it_leaves_nothing() {
    let power = table(40.0, &[(1800, 20.0), (1200, 25.0)]);
    assert_eq!(
        ft8(1500, None, Some(&[1830]), &power),
        slot(1200, Some(25), HisEnd::Yes),
        "1800 is 30 Hz from 1830: the next quietest"
    );
    assert_eq!(
        ft8(1500, None, Some(&[1850]), &power),
        slot(1800, Some(20), HisEnd::Yes),
        "exactly 50 Hz away is free"
    );
    let all: Vec<u32> = (300..=2650).step_by(40).collect();
    assert_eq!(
        ft8(1500, None, Some(&all), &power),
        slot(1800, Some(20), HisEnd::No),
        "everything excluded: his end ignored"
    );
    assert_eq!(
        ft8(1500, None, Some(&[]), &power),
        slot(1800, Some(20), HisEnd::Unknown)
    );
    assert_eq!(ft8(1500, None, None, &power).his_end, HisEnd::Unknown);
}

// Proves: TC-039-010. No power yet: the current Tx is kept, or when it is too near the called
// station the nearest candidate away from it (the lower on a tie), power_db null.
#[test]
fn tc_039_010_no_power_keeps_the_current_tx() {
    let none = |_: u32| None;
    assert_eq!(
        ft8(1500, Some(2400), None, &none),
        slot(1500, None, HisEnd::Unknown)
    );
    assert_eq!(
        ft8(1500, Some(1500), None, &none),
        slot(1400, None, HisEnd::Unknown),
        "1400 and 1600 are equally near: the lower"
    );
    assert_eq!(ft8(1500, Some(1530), None, &none).hz, 1430);
    assert_eq!(
        ft8(1500, None, Some(&[1520]), &none),
        slot(1500, None, HisEnd::No)
    );
    assert_eq!(
        ft8(1500, None, Some(&[1600]), &none),
        slot(1500, None, HisEnd::Yes)
    );
    assert_eq!(
        slot(1500, None, HisEnd::No).json(),
        json!({"hz":1500,"power_db":null,"his_end":"no"})
    );
}

/// :00 and :30 of an FT8 minute are even periods, :15 and :45 odd.
const EVEN: i64 = 1_762_430_400_000;
const ODD: i64 = EVEN + 15_000;
/// The station time of the decisions below: 1 s into the even period EVEN, so that my last 4 Rx
/// (even) periods on the clock start 30, 60, 90 and 120 s before EVEN.
const NOW: i64 = EVEN + 1_000;
/// A detailed row: `floor` in every bin, `raised` over [from, to) Hz.
fn row(floor: u8, raised: Option<(u32, u32, u8)>) -> Vec<u8> {
    bands_row(floor, raised.as_slice())
}
/// A detailed row of 1024 bins: `floor` in every bin, each band [from, to) Hz at its level.
fn bands_row(floor: u8, bands: &[(u32, u32, u8)]) -> Vec<u8> {
    (0..1024)
        .map(|bin| {
            let hz = bin as f64 * BIN_HZ;
            bands
                .iter()
                .find(|(from, to, _)| hz >= f64::from(*from) && hz < f64::from(*to))
                .map_or(floor, |b| b.2)
        })
        .collect()
}
/// The received period `back` FT8 periods of 30 s before EVEN (my even Rx parity, back >= 1, or
/// with `odd` the odd period 15 s after it): `floor` with `bands` raised.
fn period(back: i64, odd: bool, floor: u8, bands: &[(u32, u32, u8)]) -> Period {
    Period {
        start_ms: EVEN - 30_000 * back + if odd { 15_000 } else { 0 },
        levels: bands_row(floor, bands).into_iter().map(f32::from).collect(),
    }
}
/// The compared value of `j`'s decision as the choice reads it.
fn rises<'a>(j: &'a Judged<'a>) -> impl Fn(u32) -> Option<f64> + 'a {
    move |f| j.numbers(f).map(|n| n.rise)
}
fn close(a: f64, b: f64) -> bool {
    (a - b).abs() < 1e-9
}

// Proves: TC-039-010; TC-039-050 (f), (g). The received periods: the mean level of each bin over
// the rows of a period; a period I transmitted in is not kept; a new live job starts empty; the
// open period counts once it has ended. Of them only my Rx parity's among its last 4 periods on
// the clock before the period in progress count (FT8 the last 2 minutes, FT4 the last minute): a
// gap is not filled by an older one, after two minutes without one none counts, and from a band
// change on only later ones.
#[test]
fn tc_039_010_the_counted_periods_are_my_recent_rx_periods() {
    let job = ("job", 1);
    let mut w = Waterfall::default();
    // Six even periods (rows of 20 and 30 dB) and my own odd periods, loud but transmitted in.
    for n in 0..6 {
        let start = EVEN + n * 30_000;
        w.row(job, start, 15_000, &row(20, None), false);
        w.row(job, start, 15_000, &row(30, None), false);
        w.row(job, start + 15_000, 15_000, &row(90, None), true);
    }
    let all = w.periods(job, due_at(EVEN + 6 * 30_000, None));
    assert_eq!(all.len(), 6, "the transmitted periods are not kept");
    assert_eq!(all[0].levels[0], 25.0, "the mean of the two rows");
    // No complete publication of a period in progress (#89): only ended periods are due.
    let starts = |now: i64, since: i64| {
        Judged::new(&all, Mode::Ft8, Parity::Even, since, due_at(now, None), &[])
            .counted
            .iter()
            .map(|c| c.period.start_ms)
            .collect::<Vec<i64>>()
    };
    let at = |n: i64| EVEN + n * 30_000;
    // 1 s into the even period 6: the last 4 even periods before it. In the odd period after it,
    // the even period 6 (not received) is one of the 4 and 2 is no longer.
    assert_eq!(
        recent_starts(Mode::Ft8, Parity::Even, due_at(at(6) + 1_000, None)),
        [at(5), at(4), at(3), at(2)]
    );
    assert_eq!(
        starts(at(6) + 1_000, i64::MIN),
        [at(2), at(3), at(4), at(5)]
    );
    assert_eq!(starts(at(6) + 16_000, i64::MIN), [at(3), at(4), at(5)]);
    // One minute on, the periods 6 and 7 were not received: 4 and 5 count, 2 and 3 do not fill in.
    assert_eq!(starts(at(8) + 1_000, i64::MIN), [at(4), at(5)]);
    assert!(
        starts(at(10) + 1_000, i64::MIN).is_empty(),
        "two minutes on"
    );
    // My Rx parity odd: every odd period was transmitted in.
    assert_eq!(
        Judged::new(
            &all,
            Mode::Ft8,
            Parity::Odd,
            i64::MIN,
            due_at(at(6) + 1_000, None),
            &[]
        )
        .count(),
        0
    );
    // After a band change at 4 only later periods count.
    assert_eq!(starts(at(6) + 1_000, at(4) - 500), [at(4), at(5)]);
    // FT4: my last 4 even periods of 7.5 s, the last minute.
    assert_eq!(
        recent_starts(Mode::Ft4, Parity::Even, due_at(EVEN + 1_000, None)),
        [EVEN - 15_000, EVEN - 30_000, EVEN - 45_000, EVEN - 60_000]
    );
    // The open period counts once it has ended, and not before (without its publication).
    w.row(job, ODD + 6 * 30_000, 15_000, &row(40, None), false);
    let at_ms = |now: i64| due_at(now, None);
    assert_eq!(w.periods(job, at_ms(ODD + 6 * 30_000 + 14_999)).len(), 6);
    assert_eq!(w.periods(job, at_ms(ODD + 6 * 30_000 + 15_000)).len(), 7);
    // Another live job reads nothing of this one and starts empty.
    assert!(w.periods(("other", 1), at_ms(EVEN + 9 * 30_000)).is_empty());
    w.row(("job", 2), EVEN + 9 * 30_000, 15_000, &row(20, None), false);
    assert!(w.periods(job, at_ms(EVEN + 10 * 30_000)).is_empty());
    assert_eq!(w.periods(("job", 2), at_ms(EVEN + 10 * 30_000)).len(), 1);
}

// Proves: TC-039-010; TC-039-050 (b). A slot covers the bins of [f, f + width) and reads their mean
// level above the floor's mean over them: a flat floor of 20 (floor 20.65) with a 60 dB band at
// 1000..1100 Hz (bins 342..375, at most 34 of a segment's 81): 900 reads level 20, floor 20.65,
// rise -0.65; 1000 level 60, rise 39.35; 1100 the floor again (the band ends below 1100);
// 1080..1130 is bins 369..385 (1081.1..1127.9 Hz), of them 369..375 (to 1098.6 Hz) raised, so
// (7 x 60 + 10 x 20) / 17. No period: no numbers.
#[test]
fn tc_039_010_a_slot_reads_its_bins_above_the_floor() {
    let periods = [period(1, false, 20, &[(1000, 1100, 60)])];
    let j = Judged::new(
        &periods,
        Mode::Ft8,
        Parity::Even,
        i64::MIN,
        due_at(NOW, None),
        &[],
    );
    let n = |f: u32| j.numbers(f).unwrap();
    assert!(close(n(900).level, 20.0) && close(n(900).floor, 20.65));
    assert!(close(n(900).rise, -0.65), "{:?}", n(900));
    assert!(close(n(1000).rise, 39.35), "{:?}", n(1000));
    assert!(close(n(1100).rise, -0.65), "the band ends below 1100");
    let level = (7.0 * 60.0 + 10.0 * 20.0) / 17.0;
    assert!(close(n(1080).level, level), "{:?}", n(1080));
    assert!(close(n(1080).rise, level - 20.65));
    let none: [Period; 0] = [];
    assert_eq!(
        Judged::new(
            &none,
            Mode::Ft8,
            Parity::Even,
            i64::MIN,
            due_at(NOW, None),
            &[]
        )
        .numbers(1000),
        None
    );
}

// Proves: CL-039-09; TC-039-050 (b), (c), (d). The compared value is a slot's largest rise over the
// counted periods (the busiest, of equal rises the latest): on a flat floor of 30 (30.65), a slot
// on the floor in 3 periods and 6 dB above it in one is 6 - 0.65 = 5.35, one 3 dB above in all 4 is
// 2.35, so 2 beats 5 (their means, 0.85 and 2.35, would rank them the other way); a floor slot
// under floors of 30, 30, 32 and 32 reads -0.65 in each and counts the latest period: level 32,
// floor 32.65.
#[test]
fn tc_039_050_the_busiest_counted_period_counts() {
    let periods = [
        period(4, false, 30, &[(1000, 1050, 36), (1200, 1250, 33)]),
        period(3, false, 30, &[(1200, 1250, 33)]),
        period(2, false, 32, &[(1200, 1250, 35)]),
        period(1, false, 32, &[(1200, 1250, 35)]),
    ];
    let j = Judged::new(
        &periods,
        Mode::Ft8,
        Parity::Even,
        i64::MIN,
        due_at(NOW, None),
        &[],
    );
    let a = j.numbers(1000).unwrap();
    let b = j.numbers(1200).unwrap();
    assert!(close(a.rise, 5.35) && close(a.level, 36.0), "{a:?}");
    assert!(close(b.rise, 2.35), "{b:?}");
    assert!(
        close(b.level, 35.0) && close(b.floor, 32.65),
        "equal rises: the latest {b:?}"
    );
    let floor = j.numbers(1500).unwrap();
    assert!(close(floor.rise, -0.65), "{floor:?}");
    assert!(
        close(floor.level, 32.0) && close(floor.floor, 32.65),
        "{floor:?}"
    );
}

// Proves: CL-039-09; TC-039-050 (i). The WSJT-X passband floor of a period (oracle: a flat floor F
// is the lowest tenth of every segment, so the fourth-order fit is F and the floor F + 0.65): the
// floor bins are 103..921 (300..2700 Hz); a flat 30 gives 30.65 on every floor bin; a segment
// (bins 346..426) where only its 8 lowest bins sit at 30 and the rest at 45 still gives 30.65
// everywhere, its cutoff being its 8th lowest level; with 7 there the cutoff is 45, the whole
// segment is fitted and the floor bends up. Coverage: levels reaching bin 921 have a floor, levels
// ending at bin 920 none.
#[test]
fn tc_039_050_the_passband_floor_of_a_flat_period_and_its_coverage() {
    assert_eq!(floor_bins(), (103, 921));
    let flat = vec![30.0f32; 1024];
    let at_floor = |floor: &[f64]| (103..=921).all(|k| close(floor[k], 30.65));
    assert!(at_floor(&passband_floor(&flat).unwrap()));
    let mut eight = flat.clone();
    eight[354..427].fill(45.0);
    assert!(at_floor(&passband_floor(&eight).unwrap()), "8 points");
    let mut seven = flat.clone();
    seven[353..427].fill(45.0);
    let bent = passband_floor(&seven).unwrap();
    assert!(
        (103..=921).any(|k| bent[k] > 31.15),
        "7 points: the segment's cutoff is 45"
    );
    assert!(passband_floor(&flat[..922]).is_some(), "to bin 921");
    assert!(passband_floor(&flat[..921]).is_none(), "to bin 920");
}

/// The reference vectors of the sloped floors (server/tests/vectors/freeslot/*.json, each with
/// its source and tolerance), written by an independent numpy fit.
fn floor_vectors() -> Vec<Value> {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/vectors/freeslot");
    let mut vectors: Vec<Value> = std::fs::read_dir(&dir)
        .map(|d| {
            d.filter_map(Result::ok)
                .map(|e| e.path())
                .filter(|p| p.extension().is_some_and(|x| x == "json"))
                .map(|p| serde_json::from_slice(&std::fs::read(&p).unwrap()).unwrap())
                .collect()
        })
        .unwrap_or_default();
    vectors.sort_by_key(|v: &Value| v["case"].as_str().unwrap_or("").to_owned());
    assert!(
        !vectors.is_empty(),
        "no reference vector in {}: run the numpy script there",
        dir.display()
    );
    vectors
}

// Proves: CL-039-09; TC-039-050 (a). The sloped floor of the 2026-11-07 FT4 roll-off table (30 dB
// flat to 2400 Hz, falling to 15 dB at 2700 Hz, AA3B 12 dB above it at 2621..2711 Hz; once
// without and once with a station 18 dB above the floor at 1500.5..1590.5 Hz) against the independent
// numpy fourth-order fit of each run of each reference vector: every floor bin lies within the
// vector's tolerance, and the compared value of every candidate deciding the choice (no farther
// from the current Tx than the chosen slot) lies at least 0.1 dB from a half dB (margin_db), so
// that the whole-dB rounding of the choice is unambiguous.
#[test]
fn tc_039_050_the_roll_off_floor_matches_the_numpy_reference() {
    for v in floor_vectors() {
        let case = v["case"].as_str().unwrap();
        let first = v["first_bin"].as_u64().unwrap() as usize;
        let tolerance = v["tolerance_db"].as_f64().unwrap();
        assert_eq!(first, floor_bins().0, "{case}");
        let runs = v["runs"].as_array().unwrap();
        assert!(!runs.is_empty(), "{case}: no run");
        for run in runs {
            let name = format!("{case} {}", run["name"]);
            let levels: Vec<f32> = run["levels_db"]
                .as_array()
                .unwrap()
                .iter()
                .map(|l| l.as_f64().unwrap() as f32)
                .collect();
            let expected = run["floor_db"].as_array().unwrap();
            let floor = passband_floor(&levels).unwrap();
            assert_eq!(expected.len(), floor_bins().1 - first + 1, "{name}");
            for (i, e) in expected.iter().enumerate() {
                let e = e.as_f64().unwrap();
                assert!(
                    (floor[first + i] - e).abs() <= tolerance,
                    "{name}: bin {}: {} against numpy {e}",
                    first + i,
                    floor[first + i]
                );
            }
            let margin = run["choice"]["margin_db"].as_f64().unwrap();
            assert!(margin >= 0.1, "{name}: margin {margin} dB");
        }
    }
}

// #66 decoded stations (TC-066-002). Oracle: the operator's rule of 2026-11-08 (issue #66
// Functionality 5): a candidate f is left out while another is free when |f - d| is below the width
// (FT8 50 Hz, FT4 90 Hz) for a station decoded at d in a counted period; with none free all come
// back; his end applies among those left. #82: the marks are the open slots of the same decoded
// stations (TC-066-002 (j)): no open signal overlaps a counted decode, also where every candidate
// is overlapped (open is [], no fallback, while the choice still uses all candidates).

/// The open frequencies of one build (`open_slots`), checked never to overlap a decoded station.
fn open_of(mode: Mode, decoded: &[f64], value: &dyn Fn(u32) -> Option<f64>) -> Vec<u32> {
    let open = open_slots(mode, decoded, value);
    let width = width_hz(mode);
    assert!(
        open.iter().all(|f| !occupied(*f, decoded, width)),
        "{open:?} on {decoded:?}"
    );
    open
}

// Proves: CL-039-09, CL-065-01; TC-066-002 (b), (c), (j). The overlap boundary is the width: a
// station decoded at 1000.0 Hz leaves out FT8 960 and 1040 (40 Hz) and keeps 950 and 1050 (50 Hz),
// FT4 920 and 1080 (80 Hz) out and 910 and 1090 (90 Hz) kept; at 1000.4 Hz 1050 (49.6 Hz) is out.
// Each case makes the tested candidate the only quiet one (20 against 40); with it the only one at
// 0 it is the only open slot when kept, and none is open when left out. Stations decoded every 40 Hz
// overlap every candidate: all come back for the choice, the quietest 1800 chosen, and open is [].
#[test]
fn tc_066_002_a_candidate_on_a_decoded_station_is_left_out_while_one_is_free() {
    let chosen = |mode: Mode, quiet: u32, decoded: f64| {
        let quiet = [(quiet, 20.0)];
        let power = table(40.0, &quiet);
        quietest_clear(mode, 1500, &[], &[decoded], None, &power).hz
    };
    for (mode, quiet, kept) in [
        (Mode::Ft8, 950, true),
        (Mode::Ft8, 960, false),
        (Mode::Ft8, 1040, false),
        (Mode::Ft8, 1050, true),
        (Mode::Ft4, 910, true),
        (Mode::Ft4, 920, false),
        (Mode::Ft4, 1080, false),
        (Mode::Ft4, 1090, true),
    ] {
        assert_eq!(
            chosen(mode, quiet, 1000.0) == quiet,
            kept,
            "{mode:?} {quiet}"
        );
        let open = open_of(mode, &[1000.0], &table(40.0, &[(quiet, 0.0)]));
        let expected = if kept { vec![quiet] } else { vec![] };
        assert_eq!(open, expected, "{mode:?} {quiet} open");
    }
    assert_ne!(chosen(Mode::Ft8, 1050, 1000.4), 1050, "49.6 Hz");
    let everywhere: Vec<f64> = (280..=2700).step_by(40).map(f64::from).collect();
    let power = table(40.0, &[(1800, 20.0)]);
    assert_eq!(
        quietest_clear(Mode::Ft8, 1500, &[], &everywhere, None, &power),
        slot(1800, Some(20), HisEnd::Unknown),
        "all overlapped: all back"
    );
    assert_eq!(
        open_of(Mode::Ft8, &everywhere, &table(40.0, &[(1800, 0.0)])),
        Vec::<u32>::new(),
        "all overlapped: no open slot, no fallback"
    );
}

// Proves: CL-039-09, CL-039-22; TC-066-002 (d), (e), (j). Only my Rx parity is judged. My even
// periods: a flat floor of 30 with 1460..1560 at 40 (on the current Tx 1500), so the nearest floor
// slot is 1560 (60 Hz; 1410 is 90 Hz away). A station 20 dB up at 1560 decoded only in my odd (Tx)
// period is neither left out nor raised: 1560 is chosen at -0.65, free (0). A CQ: with its Tx parity
// odd my Rx parity is even, so a slot loud only in the odd period (1500) is kept; with its Tx
// parity even my Rx parity is odd and the same slot is avoided, the nearest floor slot 1450 (50 Hz,
// the lower of 1450 and 1550).
#[test]
fn tc_066_002_only_my_rx_parity_is_judged() {
    let periods = [
        period(1, false, 30, &[(1460, 1560, 40)]),
        period(1, true, 30, &[(1560, 1610, 50)]),
    ];
    let odd_start = periods[1].start_ms;
    let j = Judged::new(
        &periods,
        Mode::Ft8,
        Parity::Even,
        i64::MIN,
        due_at(NOW, None),
        &[(odd_start, 1560.0)],
    );
    assert!(j.decoded().is_empty(), "a Tx-parity decode counts nowhere");
    assert!(close(j.numbers(1560).unwrap().rise, -0.65));
    assert_eq!(
        quietest_clear(Mode::Ft8, 1500, &[], j.decoded(), None, &rises(&j)),
        slot(1560, Some(0), HisEnd::Unknown)
    );
    let open = open_of(Mode::Ft8, j.decoded(), &rises(&j));
    assert!(open.contains(&1560) && !open.contains(&1500), "{open:?}");
    let cq = [
        period(1, false, 30, &[]),
        period(1, true, 30, &[(1500, 1550, 50)]),
    ];
    for (rx, expected) in [(Parity::Even, 1500), (Parity::Odd, 1450)] {
        let j = Judged::new(&cq, Mode::Ft8, rx, i64::MIN, due_at(NOW, None), &[]);
        assert_eq!(j.count(), 1);
        assert_eq!(
            quietest_clear(Mode::Ft8, 1500, &[], j.decoded(), None, &rises(&j)),
            slot(expected, Some(0), HisEnd::Unknown),
            "my Rx parity {rx:?}"
        );
    }
}

// Proves: CL-039-09; TC-066-002 (f). Only the counted periods' decodes count. A station decoded at
// 1500 (the current Tx, every slot on a flat floor of 30): in my last Rx period it leaves 1500 out
// (Tx to 1450, 50 Hz, the lower); in a 5th older Rx period, in a period of the window before a band
// change, and in a period older than the window while the window holds two received ones, it
// leaves nothing out and 1500 stays.
#[test]
fn tc_066_002_decodes_of_periods_that_do_not_count_leave_nothing_out() {
    let five: Vec<Period> = (1..=5).rev().map(|b| period(b, false, 30, &[])).collect();
    let at = |b: i64| EVEN - 30_000 * b;
    let choose = |periods: &[Period], since: i64, decode: i64| {
        let j = Judged::new(
            periods,
            Mode::Ft8,
            Parity::Even,
            since,
            due_at(NOW, None),
            &[(decode, 1500.0)],
        );
        let chosen = quietest_clear(Mode::Ft8, 1500, &[], j.decoded(), None, &rises(&j));
        (j.count(), j.decoded().to_vec(), chosen.hz)
    };
    assert_eq!(choose(&five, i64::MIN, at(1)), (4, vec![1500.0], 1450));
    assert_eq!(
        choose(&five, i64::MIN, at(5)),
        (4, vec![], 1500),
        "5th older"
    );
    assert_eq!(
        choose(&five, at(2) - 500, at(3)),
        (2, vec![], 1500),
        "before a band change"
    );
    let gap = [
        period(6, false, 30, &[]),
        period(2, false, 30, &[]),
        period(1, false, 30, &[]),
    ];
    assert_eq!(
        choose(&gap, i64::MIN, at(6)),
        (2, vec![], 1500),
        "older than the window"
    );
}

// Proves: CL-039-09, CL-065-01; TC-066-002 (i), (j). His end applies among the candidates the
// decoded stations leave: a station decoded at 1500 leaves out 1460..1540 and his frequency 1450 of
// my Tx parity 1410..1490, so on a flat table the nearest left is 1550 (his_end yes); his
// frequencies every 40 Hz leave none, his end is ignored, and of the decode-free ones 1450 and
// 1550 (both 50 Hz away) the lower, his_end no. The open slots apply no his end (#82 D1): 1450
// stays open, 1460..1540 (on the decoded station) do not.
#[test]
fn tc_066_002_his_end_applies_among_the_candidates_left_by_decodes() {
    let flat = table(20.0, &[]);
    assert_eq!(
        quietest_clear(Mode::Ft8, 1500, &[], &[1500.0], Some(&[1450]), &flat),
        slot(1550, Some(20), HisEnd::Yes)
    );
    let his: Vec<u32> = (300..=2700).step_by(40).collect();
    assert_eq!(
        quietest_clear(Mode::Ft8, 1500, &[], &[1500.0], Some(&his), &flat),
        slot(1450, Some(20), HisEnd::No)
    );
    let open = open_of(Mode::Ft8, &[1500.0], &table(0.0, &[]));
    assert!(open.contains(&1450) && open.contains(&1550), "{open:?}");
    assert!(!open.iter().any(|f| (1460..=1540).contains(f)), "{open:?}");
}

// #82 WstxStrategy::FreeTxSlots Open and Open ranges (TC-082-001). Oracle: the open rule of
// CL-065-01 (value 0 and no counted decode overlapped, no other filter, no fallback, no ranking, no
// limit) and FreeTxSlot's floor and value, the flat-floor floor F + 0.65 of TC-039-050; every range
// below is a hand computation written in the comment above its test.

/// The open ranges of one build as [lo, hi) pairs.
fn ranges_of(mode: Mode, decoded: &[f64], value: &dyn Fn(u32) -> Option<f64>) -> Vec<(u32, u32)> {
    open_ranges(mode, &open_of(mode, decoded, value))
}
/// Four counted even FT8 periods (my Rx parity even at NOW), each a flat 30 with `bands` raised.
fn four(bands: &[(u32, u32, u8)]) -> Vec<Period> {
    (1..=4).rev().map(|b| period(b, false, 30, bands)).collect()
}

// Proves: CL-065-01; TC-082-001 (a), (b), TC-065-001 (#82: replaced by TC-082-001). (a) Four counted periods flat 30 (floor 30.65, rise -0.65
// everywhere, value 0) with an undecoded station band 12 dB up over 1000..1050 Hz (bins 342..358):
// 950 covers bins 325..341 (to 999.0 Hz), all on the floor: open; 960 covers 328..344, 3 of them
// raised, (3 x 42 + 14 x 30) / 17 - 30.65 = 1.47, 1: closed; 1040 covers 355..371, 4 raised, 2.17,
// 2: closed; 1050 covers 359..375, none raised: open. The open grid 300..950 joins (10 Hz steps,
// 50 Hz signals) into [300, 1000), 1050..2650 into [1050, 2700). (b) The flat floor and a station
// decoded at 1000.0 Hz: FT8 960..1040 closed (|f - 1000| below 50), 950 and 1050 open: the same
// ranges; FT4 (90 Hz, 300..2610) 920..1080 closed, 910 and 1090 open: [300, 1000), [1090, 2700).
#[test]
fn tc_082_001_a_station_closes_its_slots_and_the_open_ones_join_into_ranges() {
    let periods = four(&[(1000, 1050, 42)]);
    let j = Judged::new(
        &periods,
        Mode::Ft8,
        Parity::Even,
        i64::MIN,
        due_at(NOW, None),
        &[],
    );
    assert_eq!(j.count(), 4);
    let open = open_of(Mode::Ft8, j.decoded(), &rises(&j));
    assert!(open.contains(&950) && open.contains(&1050), "{open:?}");
    assert!(!open.iter().any(|f| (960..=1040).contains(f)), "{open:?}");
    let expected = vec![(300, 1000), (1050, 2700)];
    assert_eq!(open_ranges(Mode::Ft8, &open), expected, "(a)");
    let flat = table(-0.65, &[]);
    assert_eq!(ranges_of(Mode::Ft8, &[1000.0], &flat), expected, "(b) FT8");
    let ft4 = open_of(Mode::Ft4, &[1000.0], &flat);
    assert!(ft4.contains(&910) && ft4.contains(&1090), "{ft4:?}");
    assert!(!ft4.iter().any(|f| (920..=1080).contains(f)), "{ft4:?}");
    assert_eq!(
        open_ranges(Mode::Ft4, &ft4),
        [(300, 1000), (1090, 2700)],
        "(b) FT4"
    );
}

// Proves: CL-065-01; TC-082-001 (c). The join of half-open signals [f, f + width): FT8 2110 and
// 2160 touch (2160 = 2110 + 50) and stay two ranges; 2100, 2110 and 2130 overlap into [2100,
// 2180); the top slot 2650 is [2650, 2700); every 5th grid point 300, 350, ..., 2650 touches the
// next: 48 ranges (2400 / 50), the worst case. FT4 (90 Hz): 300 is [300, 390); 300 and 390 touch:
// two ranges. Every range is at least one width long, ascending and disjoint.
#[test]
fn tc_082_001_touching_signals_stay_apart_and_overlapping_ones_join() {
    assert_eq!(
        open_ranges(Mode::Ft8, &[2110, 2160]),
        [(2110, 2160), (2160, 2210)]
    );
    assert_eq!(open_ranges(Mode::Ft8, &[2100, 2110, 2130]), [(2100, 2180)]);
    assert_eq!(open_ranges(Mode::Ft8, &[2650]), [(2650, 2700)]);
    let fifth: Vec<u32> = (300..=2650).step_by(50).collect();
    let worst = open_ranges(Mode::Ft8, &fifth);
    assert_eq!(worst.len(), 48);
    assert_eq!(
        worst,
        fifth.iter().map(|f| (*f, f + 50)).collect::<Vec<_>>()
    );
    assert_eq!(open_ranges(Mode::Ft4, &[300]), [(300, 390)]);
    assert_eq!(
        open_ranges(Mode::Ft4, &[300, 390]),
        [(300, 390), (390, 480)]
    );
    assert_eq!(open_ranges(Mode::Ft8, &[]), Vec::<(u32, u32)>::new());
    for r in [&worst, &open_ranges(Mode::Ft8, &[300, 310, 900, 2650])] {
        assert!(r.iter().all(|(lo, hi)| hi - lo >= 50), "{r:?}");
        assert!(r.windows(2).all(|w| w[0].1 <= w[1].0), "{r:?}");
    }
}

// Proves: CL-065-01; TC-082-001 (d), (g), (h). (d) Values compare in whole dB: a slot whose largest
// rise is 0.4 dB is 0, open; one at 0.6 dB is 1, closed (every other slot 5 dB, closed): exactly
// 1200 (0.0) and 1500 (0.4) open. (g) Stations decoded every 40 Hz overlap every grid point: open
// [] (no fallback). (h) No counted period: no value, open [], periods 0.
#[test]
fn tc_082_001_whole_db_no_fallback_and_no_counted_period() {
    let values = table(5.0, &[(1200, 0.0), (1500, 0.4), (1800, 0.6)]);
    assert_eq!(open_of(Mode::Ft8, &[], &values), [1200, 1500], "(d)");
    let everywhere: Vec<f64> = (280..=2700).step_by(40).map(f64::from).collect();
    assert_eq!(
        ranges_of(Mode::Ft8, &everywhere, &table(-0.65, &[])),
        Vec::<(u32, u32)>::new(),
        "(g) all overlapped"
    );
    let none: [Period; 0] = [];
    let j = Judged::new(
        &none,
        Mode::Ft8,
        Parity::Even,
        i64::MIN,
        due_at(NOW, None),
        &[],
    );
    assert_eq!(j.count(), 0);
    assert_eq!(
        ranges_of(Mode::Ft8, j.decoded(), &rises(&j)),
        Vec::<(u32, u32)>::new(),
        "(h)"
    );
}

// Proves: CL-065-01; TC-082-001 (e), (f), (i). (e) A station decoded and 20 dB above the floor at
// 1560..1610 Hz only in the odd periods (the other parity, my Rx parity even): it closes nothing,
// open [[300, 2700]]. (f) A station decoded at 1500 in a period that does not count closes nothing:
// the 5th older even period, a period before a band change, a period older than the last 4 of the
// parity on the clock; in the last counted period it closes 1460..1540: [300, 1500), [1550, 2700).
// (i) A slot on the floor in 3 periods and 3 dB above it in one (1500..1550, bins 512..529, at 33
// in the oldest): its busiest period counts, 33 - 30.65 = 2.35, 2: closed. Its neighbours read k
// raised bins of 17 in that period, 3k / 17 - 0.65: 1470 (bins 502..518, k 7) and 1530 (523..539,
// k 7) 0.59, 1: closed; 1460 (499..515) and 1540 (526..542), k 4, 0.06, 0: open. So [300, 1510),
// [1540, 2700).
#[test]
fn tc_082_001_other_parity_and_uncounted_decodes_close_nothing_the_busiest_period_counts() {
    let mut both = four(&[]);
    both.push(period(1, true, 30, &[(1560, 1610, 50)]));
    let odd = both[4].start_ms;
    let j = Judged::new(
        &both,
        Mode::Ft8,
        Parity::Even,
        i64::MIN,
        due_at(NOW, None),
        &[(odd, 1560.0)],
    );
    let all = vec![(300, 2700)];
    assert_eq!(ranges_of(Mode::Ft8, j.decoded(), &rises(&j)), all, "(e)");
    let five: Vec<Period> = (1..=5).rev().map(|b| period(b, false, 30, &[])).collect();
    let at = |b: i64| EVEN - 30_000 * b;
    let gap = [
        period(6, false, 30, &[]),
        period(2, false, 30, &[]),
        period(1, false, 30, &[]),
    ];
    let on_1500 = vec![(300, 1500), (1550, 2700)];
    for (name, periods, since, decode, expected) in [
        ("counted", &five[..], i64::MIN, at(1), &on_1500),
        ("5th older", &five[..], i64::MIN, at(5), &all),
        ("before a band change", &five[..], at(2) - 500, at(3), &all),
        ("older than the window", &gap[..], i64::MIN, at(6), &all),
    ] {
        let j = Judged::new(
            periods,
            Mode::Ft8,
            Parity::Even,
            since,
            due_at(NOW, None),
            &[(decode, 1500.0)],
        );
        assert_eq!(
            &ranges_of(Mode::Ft8, j.decoded(), &rises(&j)),
            expected,
            "(f) {name}"
        );
    }
    let mut busiest = four(&[]);
    busiest[0] = period(4, false, 30, &[(1500, 1550, 33)]);
    let j = Judged::new(
        &busiest,
        Mode::Ft8,
        Parity::Even,
        i64::MIN,
        due_at(NOW, None),
        &[],
    );
    assert!(close(j.numbers(1500).unwrap().rise, 2.35));
    assert_eq!(
        ranges_of(Mode::Ft8, j.decoded(), &rises(&j)),
        [(300, 1510), (1540, 2700)],
        "(i)"
    );
}

// Proves: CL-065-01; TC-082-001, TC-065-001 (#82: replaced by TC-082-001). The value of one build has exactly {at_utc_ms, mode, rx_parity,
// qso, periods, open} with the ranges as [lo_hz, hi_hz] integer pairs (WstxStrategy::FreeTxSlots
// Value): no run_id, listening, slots or per-slot numbers.
#[test]
fn tc_082_001_the_value_of_a_build() {
    assert_eq!(
        value(
            NOW,
            Mode::Ft4,
            Parity::Odd,
            true,
            3,
            &[(300, 1000), (1090, 2700)]
        ),
        json!({"at_utc_ms":NOW,"mode":"ft4","rx_parity":"odd","qso":true,"periods":3,
            "open":[[300,1000],[1090,2700]]})
    );
    assert_eq!(
        value(NOW, Mode::Ft8, Parity::Even, false, 0, &[]),
        json!({"at_utc_ms":NOW,"mode":"ft8","rx_parity":"even","qso":false,"periods":0,"open":[]})
    );
}

// #89 WstxStrategy::FreeTxSlot Due (TC-089-001). Oracle: the operator's rule of 2026-11-09 ("Count
// once decoded"): a period is due once it has ended, or earlier, while in progress, once its
// complete publication is published, never before it starts; the counted periods are the last 4
// due ones of my Rx parity. Every number below is a hand computation written above its test.

/// The odd FT8 period P of TC-089-001 (my Rx parity odd), P the newest odd period.
const P: i64 = ODD + 4 * 30_000;
const JOB: (&str, u64) = ("job", 1);
/// The odd periods P - 120 s .. P - 30 s received, one flat row of 30 each (the even periods
/// between them, the other parity, not received), then `p_rows` of P (P open).
fn with_p(p_rows: &[Vec<u8>]) -> Waterfall {
    let mut w = Waterfall::default();
    for b in (1..=4).rev() {
        w.row(JOB, P - 30_000 * b, 15_000, &row(30, None), false);
    }
    for r in p_rows {
        w.row(JOB, P, 15_000, r, false);
    }
    w
}
/// One judgement of my odd Rx parity at `now` with `published` (the period start of the latest
/// complete publication) and `decodes`: the counted starts, the decoded stations, the open slots.
fn judge_p(
    w: &Waterfall,
    now: i64,
    published: Option<i64>,
    decodes: &[(i64, f64)],
) -> (Vec<i64>, Vec<f64>, Vec<u32>) {
    let periods = w.periods(JOB, due_at(now, published));
    let j = Judged::new(
        &periods,
        Mode::Ft8,
        Parity::Odd,
        i64::MIN,
        due_at(now, published),
        decodes,
    );
    let starts = j.counted.iter().map(|c| c.period.start_ms).collect();
    let open = open_of(Mode::Ft8, j.decoded(), &rises(&j));
    (starts, j.decoded().to_vec(), open)
}

// Proves: CL-039-09, CL-065-01; TC-089-001 (a), (b), (c), (g). Every period flat 30 (floor 30.65,
// every slot -0.65, free). (a) At P + 14.1 s (P in progress) with P's complete publication: P is
// due, so the last 4 due odd periods are P, P - 30, P - 60 and P - 90 s; P - 120 s is the 5th and
// does not count. A station decoded at 2340 Hz in P closes the candidates f with |f - 2340| below
// 50: 2300..2380; 2290 and 2390 (50 Hz) stay open. (b) The same instant without it: P is not due,
// the 4 before it count (P - 120 .. P - 30 s), 2340 closes nothing. (c) A partial publication is no
// complete one: the station passes no publication (automation published_start; router: TC-089-003
// (c)), so as (b). (g) A complete publication naming P + 30 s (the next odd period) while P + 15 s
// is in progress, at P + 20 s: P + 30 s has not started, so it is not due and its decode at 1200
// closes nothing; P has ended: P .. P - 90 s count. Red on the parent: (a) P not counted and 2340
// open.
#[test]
fn tc_089_001_the_newest_rx_period_counts_once_its_complete_publication_is_there() {
    let w = with_p(&[row(30, None)]);
    let now = P + 14_100;
    let (starts, decoded, open) = judge_p(&w, now, Some(P), &[(P, 2340.0)]);
    assert_eq!(
        recent_starts(Mode::Ft8, Parity::Odd, due_at(now, Some(P))),
        [P, P - 30_000, P - 60_000, P - 90_000],
        "(a)"
    );
    assert_eq!(starts, [P - 90_000, P - 60_000, P - 30_000, P], "(a)");
    assert_eq!(decoded, [2340.0], "(a)");
    assert!(
        (2300..=2380).step_by(10).all(|f| !open.contains(&f)),
        "(a) 2300..2380 closed: {open:?}"
    );
    assert!(open.contains(&2290) && open.contains(&2390), "(a) {open:?}");
    let (starts, decoded, open) = judge_p(&w, now, None, &[(P, 2340.0)]);
    assert_eq!(
        starts,
        [P - 120_000, P - 90_000, P - 60_000, P - 30_000],
        "(b), (c)"
    );
    assert!(decoded.is_empty(), "(b), (c)");
    assert!(open.contains(&2340), "(b), (c) {open:?}");
    let later = P + 20_000;
    let (starts, decoded, open) = judge_p(&w, later, Some(P + 30_000), &[(P + 30_000, 1200.0)]);
    assert_eq!(
        starts,
        [P - 90_000, P - 60_000, P - 30_000, P],
        "(g) P + 30 s not due"
    );
    assert!(decoded.is_empty(), "(g)");
    assert!(open.contains(&1200), "(g) {open:?}");
}

// Proves: CL-039-09; TC-089-001 (d). Undecoded, every odd period flat 30 (floor 30.65), except in P
// the 18 bins 512..529 of slot 1500 ([1500, 1550) Hz: ceil(1500 / 2.9297) = 512, ceil(1550 /
// 2.9297) - 1 = 529) at 42 in P's rows 3..64 (62 rows) and 30 in its other rows; those 18 bins lie
// above the 8th lowest level of their floor segment (bins 508..588), so the flat-floor fit stands.
// At P + 14.1 s with P's complete publication and its rows 0..69: level (62 x 42 + 8 x 30) / 70 =
// 40.629, rise 9.979, value 10. Then rows 70..74 and P + 15.2 s (P ended, all 75 rows): (62 x 42 +
// 13 x 30) / 75 = 39.92, rise 9.27, value 9. A slot off the band (1000, 2000) is 0. Red on the
// parent: value 0 at P + 14.1 s (P not counted).
#[test]
fn tc_089_001_the_newest_period_counts_by_its_rows_so_far() {
    let p_row = |k: usize| {
        let mut r = vec![30u8; 1024];
        if (3..=64).contains(&k) {
            r[512..=529].fill(42);
        }
        r
    };
    let rows: Vec<Vec<u8>> = (0..70).map(p_row).collect();
    let mut w = with_p(&rows);
    let numbers = |w: &Waterfall, now: i64| {
        let periods = w.periods(JOB, due_at(now, Some(P)));
        let j = Judged::new(
            &periods,
            Mode::Ft8,
            Parity::Odd,
            i64::MIN,
            due_at(now, Some(P)),
            &[],
        );
        let others = [1000, 2000].map(|f| compared(j.numbers(f).unwrap().rise));
        (j.numbers(1500).unwrap(), others)
    };
    let (n, others) = numbers(&w, P + 14_100);
    let level = (62.0 * 42.0 + 8.0 * 30.0) / 70.0;
    assert!((n.level - level).abs() < 1e-4, "{n:?}");
    assert!((n.floor - 30.65).abs() < 1e-6, "{n:?}");
    assert!((n.rise - (level - 30.65)).abs() < 1e-4, "{n:?}");
    assert_eq!(compared(n.rise), 10, "at P + 14.1 s");
    assert_eq!(others, [0, 0]);
    for k in 70..75 {
        w.row(JOB, P, 15_000, &p_row(k), false);
    }
    let (n, others) = numbers(&w, P + 15_200);
    let level = (62.0 * 42.0 + 13.0 * 30.0) / 75.0;
    assert!((n.level - level).abs() < 1e-4, "{n:?}");
    assert!((n.rise - 9.27).abs() < 1e-4, "{n:?}");
    assert_eq!(compared(n.rise), 9, "at P + 15.2 s");
    assert_eq!(others, [0, 0]);
}

// Proves: CL-039-09, CL-065-01; TC-089-001 (e), (f). (e) At P + 15.2 s P has ended without its
// publication: it counts by its levels (P - 90 .. P), and with no decode of it 2340 is open; once
// its complete publication brings the station at 2340, 2300..2380 close (unchanged, #82). (f) FT4
// (7.5 s periods, my Rx parity Q's): at Q + 6.9 s with Q's complete publication Q is due, the last
// 4 due periods of its parity are Q, Q - 15, Q - 30 and Q - 45 s, and Q counts by its row so far.
#[test]
fn tc_089_001_an_ended_period_and_ft4() {
    let w = with_p(&[row(30, None)]);
    let after = P + 15_200;
    let (starts, decoded, open) = judge_p(&w, after, None, &[]);
    assert_eq!(starts, [P - 90_000, P - 60_000, P - 30_000, P], "(e)");
    assert!(decoded.is_empty() && open.contains(&2340), "(e) {open:?}");
    let (starts, decoded, open) = judge_p(&w, after, Some(P), &[(P, 2340.0)]);
    assert_eq!(starts, [P - 90_000, P - 60_000, P - 30_000, P], "(e)");
    assert_eq!(decoded, [2340.0], "(e)");
    assert!(
        (2300..=2380).step_by(10).all(|f| !open.contains(&f)),
        "(e) {open:?}"
    );
    let q = EVEN + 7_500 * 5;
    let rx = parity(Mode::Ft4, q);
    let mut w = Waterfall::default();
    for b in (1..=4).rev() {
        w.row(JOB, q - 15_000 * b, 7_500, &row(30, None), false);
    }
    w.row(JOB, q, 7_500, &row(30, None), false);
    let at = due_at(q + 6_900, Some(q));
    assert_eq!(
        recent_starts(Mode::Ft4, rx, at),
        [q, q - 15_000, q - 30_000, q - 45_000],
        "(f)"
    );
    let periods = w.periods(JOB, at);
    let j = Judged::new(&periods, Mode::Ft4, rx, i64::MIN, at, &[]);
    let starts: Vec<i64> = j.counted.iter().map(|c| c.period.start_ms).collect();
    assert_eq!(starts, [q - 45_000, q - 30_000, q - 15_000, q], "(f)");
}
