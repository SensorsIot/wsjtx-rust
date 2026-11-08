#![forbid(unsafe_code)]
// WstxStrategy::FreeTxSlot worked by hand: compared values in dB per candidate written here, the
// detailed bin of 12000/4096 Hz, and the operator's rule (lowest whole dB, a tie keeps the current
// Tx, else nearer, then lower; 50 Hz from the called station and from his decoded frequencies;
// #66: my Rx periods only, the recent ones, each slot's largest rise above the WSJT-X passband
// floor, clear of the stations decoded in them). A flat floor F is its own lowest tenth in every
// segment, so its fit is F exactly and the floor F + 0.65 dB.
use super::*;

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
    let all = w.periods(job, EVEN + 6 * 30_000);
    assert_eq!(all.len(), 6, "the transmitted periods are not kept");
    assert_eq!(all[0].levels[0], 25.0, "the mean of the two rows");
    let starts = |now: i64, since: i64| {
        Judged::new(&all, Mode::Ft8, Parity::Even, since, now, &[])
            .counted
            .iter()
            .map(|c| c.period.start_ms)
            .collect::<Vec<i64>>()
    };
    let at = |n: i64| EVEN + n * 30_000;
    // 1 s into the even period 6: the last 4 even periods before it. In the odd period after it,
    // the even period 6 (not received) is one of the 4 and 2 is no longer.
    assert_eq!(
        recent_starts(Mode::Ft8, Parity::Even, at(6) + 1_000),
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
        Judged::new(&all, Mode::Ft8, Parity::Odd, i64::MIN, at(6) + 1_000, &[]).count(),
        0
    );
    // After a band change at 4 only later periods count.
    assert_eq!(starts(at(6) + 1_000, at(4) - 500), [at(4), at(5)]);
    // FT4: my last 4 even periods of 7.5 s, the last minute.
    assert_eq!(
        recent_starts(Mode::Ft4, Parity::Even, EVEN + 1_000),
        [EVEN - 15_000, EVEN - 30_000, EVEN - 45_000, EVEN - 60_000]
    );
    // The open period counts once it has ended, and not before.
    w.row(job, ODD + 6 * 30_000, 15_000, &row(40, None), false);
    assert_eq!(w.periods(job, ODD + 6 * 30_000 + 14_999).len(), 6);
    assert_eq!(w.periods(job, ODD + 6 * 30_000 + 15_000).len(), 7);
    // Another live job reads nothing of this one and starts empty.
    assert!(w.periods(("other", 1), EVEN + 9 * 30_000).is_empty());
    w.row(("job", 2), EVEN + 9 * 30_000, 15_000, &row(20, None), false);
    assert!(w.periods(job, EVEN + 10 * 30_000).is_empty());
    assert_eq!(w.periods(("job", 2), EVEN + 10 * 30_000).len(), 1);
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
    let j = Judged::new(&periods, Mode::Ft8, Parity::Even, i64::MIN, NOW, &[]);
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
        Judged::new(&none, Mode::Ft8, Parity::Even, i64::MIN, NOW, &[]).numbers(1000),
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
    let j = Judged::new(&periods, Mode::Ft8, Parity::Even, i64::MIN, NOW, &[]);
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
// falling to 15 dB from 2400 to 2700 Hz, AA3B 12 dB above it at 2621..2711 Hz) against the
// independent numpy fourth-order fit of each reference vector: the levels are the vector's, and
// every floor bin lies within its tolerance.
#[test]
fn tc_039_050_the_roll_off_floor_matches_the_numpy_reference() {
    for v in floor_vectors() {
        let case = v["case"].as_str().unwrap();
        let levels: Vec<f32> = v["levels_db"]
            .as_array()
            .unwrap()
            .iter()
            .map(|l| l.as_f64().unwrap() as f32)
            .collect();
        let expected = v["floor_db"].as_array().unwrap();
        let first = v["first_bin"].as_u64().unwrap() as usize;
        let tolerance = v["tolerance_db"].as_f64().unwrap();
        let floor = passband_floor(&levels).unwrap();
        assert_eq!(first, floor_bins().0, "{case}");
        assert_eq!(expected.len(), floor_bins().1 - first + 1, "{case}");
        for (i, e) in expected.iter().enumerate() {
            let e = e.as_f64().unwrap();
            assert!(
                (floor[first + i] - e).abs() <= tolerance,
                "{case}: bin {}: {} against numpy {e}",
                first + i,
                floor[first + i]
            );
        }
    }
}

// #66 decoded stations (TC-066-002). Oracle: the operator's rule of 2026-11-08 (issue #66
// Functionality 5): a candidate f is left out while another is free when |f - d| is below the width
// (FT8 50 Hz, FT4 90 Hz) for a station decoded at d in a counted period; with none free all come
// back; his end applies among those left.

/// The listed hz of a decision, checked against the choice (1.7 Agreement) and, while a candidate
/// is free, against the decoded stations.
fn list(
    mode: Mode,
    current: u32,
    avoid: &[u32],
    decoded: &[f64],
    his: Option<&[u32]>,
    numbers: &dyn Fn(u32) -> Option<Numbers>,
) -> Vec<u32> {
    let listed = free_slots(mode, current, avoid, decoded, his, numbers);
    let chosen = quietest_clear(mode, current, avoid, decoded, his, &|f| {
        numbers(f).map(|n| n.rise)
    });
    match listed.first() {
        Some(first) => assert_eq!(
            (first.hz, Some(first.rise_db)),
            (chosen.hz, chosen.power_db),
            "the first listed is the chosen slot"
        ),
        None => assert_eq!(chosen.power_db, None, "an empty list only without power"),
    }
    assert!(listed.len() <= SLOTS_LISTED);
    let (low, high) = band(mode);
    let width = width_hz(mode);
    let free = (low..=high)
        .step_by(STEP_HZ as usize)
        .any(|f| clear_of_all(f, avoid, width) && !occupied(f, decoded, width));
    if free {
        assert!(
            listed.iter().all(|l| !occupied(l.hz, decoded, width)),
            "{listed:?} on {decoded:?}"
        );
    }
    listed.iter().map(|l| l.hz).collect()
}
/// A value table as Numbers: `floor` everywhere, the listed candidates at their own value; the
/// level 20 dB above the floor of 20 plus the value.
fn values(floor: f64, levels: &[(u32, f64)]) -> impl Fn(u32) -> Option<Numbers> {
    let t = table(floor, levels);
    move |f| {
        t(f).map(|rise| Numbers {
            rise,
            level: 20.0 + rise,
            floor: 20.0,
        })
    }
}

// Proves: CL-039-09, CL-065-01; TC-066-002 (b), (c), (j). The overlap boundary is the width: a
// station decoded at 1000.0 Hz leaves out FT8 960 and 1040 (40 Hz) and keeps 950 and 1050 (50 Hz),
// FT4 920 and 1080 (80 Hz) out and 910 and 1090 (90 Hz) kept; at 1000.4 Hz 1050 (49.6 Hz) is out.
// Each case makes the tested candidate the only quiet one (20 against 40). Stations decoded every
// 40 Hz overlap every candidate: all come back, the quietest 1800 chosen and first listed.
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
        let listed = list(
            mode,
            1500,
            &[],
            &[1000.0],
            None,
            &values(40.0, &[(quiet, 0.0)]),
        );
        assert_eq!(listed[0] == quiet, kept, "{mode:?} {quiet} listed");
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
        list(
            Mode::Ft8,
            1500,
            &[],
            &everywhere,
            None,
            &values(40.0, &[(1800, 0.0)])
        )[0],
        1800
    );
}

// Proves: CL-039-09, CL-039-22; TC-066-002 (d), (e), (j). Only my Rx parity is judged. My even
// periods: a flat floor of 30 with 1460..1560 at 40 (on the current Tx 1500), so the nearest floor
// slot is 1560 (60 Hz; 1410 is 90 Hz away). A station 20 dB up at 1560 decoded only in my odd (Tx)
// period is neither left out nor raised: 1560 is chosen at -0.65 (-1). A CQ: with its Tx parity
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
        NOW,
        &[(odd_start, 1560.0)],
    );
    assert!(j.decoded().is_empty(), "a Tx-parity decode counts nowhere");
    assert!(close(j.numbers(1560).unwrap().rise, -0.65));
    assert_eq!(
        quietest_clear(Mode::Ft8, 1500, &[], j.decoded(), None, &rises(&j)),
        slot(1560, Some(-1), HisEnd::Unknown)
    );
    assert_eq!(
        list(Mode::Ft8, 1500, &[], j.decoded(), None, &|f| j.numbers(f))[0],
        1560
    );
    let cq = [
        period(1, false, 30, &[]),
        period(1, true, 30, &[(1500, 1550, 50)]),
    ];
    for (rx, expected) in [(Parity::Even, 1500), (Parity::Odd, 1450)] {
        let j = Judged::new(&cq, Mode::Ft8, rx, i64::MIN, NOW, &[]);
        assert_eq!(j.count(), 1);
        assert_eq!(
            quietest_clear(Mode::Ft8, 1500, &[], j.decoded(), None, &rises(&j)),
            slot(expected, Some(-1), HisEnd::Unknown),
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
            NOW,
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
// 1550 (both 50 Hz away) the lower, his_end no. The first listed is the choice.
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
    let flat = values(0.0, &[]);
    assert_eq!(
        list(Mode::Ft8, 1500, &[], &[1500.0], Some(&[1450]), &flat)[0],
        1550
    );
    assert_eq!(
        list(Mode::Ft8, 1500, &[], &[1500.0], Some(&his), &flat)[0],
        1450
    );
}

// #65 WstxStrategy::FreeTxSlots (TC-065-001). Oracle: the operator's rules of 2026-11-08 (issue #65
// Functionality 1.2-1.7), worked by hand in each test from value tables written here; every list is
// also checked against the choice (1.7): its first slot is quietest_clear's hz and power_db.

/// The listed hz of a decision without decoded stations.
fn listed(
    mode: Mode,
    current: u32,
    avoid: &[u32],
    his: Option<&[u32]>,
    numbers: &dyn Fn(u32) -> Option<Numbers>,
) -> Vec<u32> {
    list(mode, current, avoid, &[], his, numbers)
}

// Proves: CL-065-01; TC-065-001 (count, rank order, no power). Seven separate quiet places from Tx
// 1500 on a floor of value 10: 400 at -2, 700 at -1, 1000, 1300 and 1800 at 0, 2100 at 1, 2400 at 2.
// Rank: -2, -1, then the three at 0 by distance to 1500 (1300 200 Hz, 1800 300 Hz, 1000 500 Hz):
// exactly 5, 2100 and 2400 are not listed. Three candidates only: called stations every 150 to 200
// Hz leave exactly 1000, 1500 and 2000 (each excludes the 19 grid slots within 90 Hz), all at value
// 0: 1500 (the current Tx), then 1000 and 2000 at 500 Hz, the lower first; 3 listed. No power: an
// empty list, also when one candidate alone has none (the choice's "No power yet").
#[test]
fn tc_065_001_five_listed_in_rank_order_fewer_when_fewer_none_without_power() {
    let seven = values(
        10.0,
        &[
            (400, -2.0),
            (700, -1.0),
            (1000, 0.0),
            (1300, 0.0),
            (1800, 0.0),
            (2100, 1.0),
            (2400, 2.0),
        ],
    );
    assert_eq!(
        listed(Mode::Ft8, 1500, &[], None, &seven),
        [400, 700, 1300, 1800, 1000]
    );
    let called = [
        300, 450, 600, 750, 900, 1100, 1250, 1400, 1600, 1750, 1900, 2100, 2250, 2400, 2550, 2700,
    ];
    assert_eq!(
        listed(Mode::Ft8, 1500, &called, None, &values(0.0, &[])),
        [1500, 1000, 2000]
    );
    assert_eq!(
        listed(Mode::Ft8, 1500, &[], None, &|_| None),
        Vec::<u32>::new()
    );
    let one_without = |f: u32| {
        (f != 2000).then_some(Numbers {
            rise: 0.0,
            level: 20.0,
            floor: 20.0,
        })
    };
    assert_eq!(
        free_slots(Mode::Ft8, 1500, &[], &[], None, &one_without),
        Vec::new()
    );
}

// Proves: CL-065-01; TC-065-001 (whole dB and the tie rule). Tx 1500 at 0.4 against 1800 at 0.0 on a
// floor of 5: both are 0 in whole dB, a tie, and the current Tx comes first; at 0.6 1500 is 1 dB and
// 1800 comes first. Equal values on both sides of Tx 1500: 1300 and 1600 at 0, the nearer (1600,
// 100 Hz) first; 1400 and 1600 at 0, equally near: the lower first.
#[test]
fn tc_065_001_ties_in_whole_db_keep_the_current_tx_then_nearer_then_lower() {
    let tied = listed(
        Mode::Ft8,
        1500,
        &[],
        None,
        &values(5.0, &[(1500, 0.4), (1800, 0.0)]),
    );
    assert_eq!(tied[..2], [1500, 1800]);
    let louder = listed(
        Mode::Ft8,
        1500,
        &[],
        None,
        &values(5.0, &[(1500, 0.6), (1800, 0.0)]),
    );
    assert_eq!(louder[..2], [1800, 1500]);
    let sides = listed(
        Mode::Ft8,
        1500,
        &[],
        None,
        &values(5.0, &[(1300, 0.0), (1600, 0.0)]),
    );
    assert_eq!(sides[..2], [1600, 1300]);
    let equal = listed(
        Mode::Ft8,
        1500,
        &[],
        None,
        &values(5.0, &[(1400, 0.0), (1600, 0.0)]),
    );
    assert_eq!(equal[..2], [1400, 1600]);
}

// Proves: CL-065-01; TC-065-001 (non-overlap at the slot width). FT8 (50 Hz), Tx 1500, floor 10:
// 1000 at 0, 1040 at 1, 1050 at 2. 1040 is 40 Hz from the listed 1000 and skipped, 1050 is 50 Hz
// away and listed; then the floor by distance to 1500: 1500, 1450 and 1550 (each 50 Hz from 1500).
// FT4 (90 Hz): 1000 at 0, 1080 at 1, 1090 at 2: 1080 skipped, 1090 listed, then 1500, 1410, 1590.
#[test]
fn tc_065_001_a_candidate_closer_than_the_slot_width_is_skipped() {
    let ft8 = values(10.0, &[(1000, 0.0), (1040, 1.0), (1050, 2.0)]);
    assert_eq!(
        listed(Mode::Ft8, 1500, &[], None, &ft8),
        [1000, 1050, 1500, 1450, 1550]
    );
    let ft4 = values(10.0, &[(1000, 0.0), (1080, 1.0), (1090, 2.0)]);
    assert_eq!(
        listed(Mode::Ft4, 1500, &[], None, &ft4),
        [1000, 1090, 1500, 1410, 1590]
    );
}

// Proves: CL-065-01; TC-065-001 (the decision's candidates). The called station at 1000 forbids
// 910..1090 (FT8: 50 Hz signal, 50 Hz clearance): 950 at -5 and 1090 at -6 are never listed, 1100 at
// -5 (100 Hz above him) is first. My Rx at 1000 with Hold Tx on is in `avoid` as well (the station
// at 2000): 1050 at -5 is not listed; with Hold Tx off only the station is: 1050 is first. His
// decoded frequency 1200 of my Tx parity excludes 1160..1240: 1200 at -5 is not listed, 1250 at -4
// (50 Hz away) is first; his frequencies everywhere leave every candidate, 1200 first.
#[test]
fn tc_065_001_only_the_decisions_candidates_are_listed() {
    let near_him = values(10.0, &[(950, -5.0), (1090, -6.0), (1100, -5.0)]);
    let l = listed(Mode::Ft8, 1500, &[1000], None, &near_him);
    assert_eq!(l[0], 1100);
    assert!(l.iter().all(|f| !(910..=1090).contains(f)), "{l:?}");
    let near_rx = values(10.0, &[(1050, -5.0)]);
    assert!(!listed(Mode::Ft8, 1500, &[2000, 1000], None, &near_rx).contains(&1050));
    assert_eq!(listed(Mode::Ft8, 1500, &[2000], None, &near_rx)[0], 1050);
    let at_his = values(10.0, &[(1200, -5.0), (1250, -4.0)]);
    let l = listed(Mode::Ft8, 1500, &[], Some(&[1200]), &at_his);
    assert_eq!(l[0], 1250);
    assert!(l.iter().all(|f| !(1160..=1240).contains(f)), "{l:?}");
    let everywhere: Vec<u32> = (300..=2700).step_by(10).collect();
    assert_eq!(
        listed(Mode::Ft8, 1500, &[], Some(&everywhere), &at_his)[0],
        1200
    );
}

// Proves: CL-065-01; TC-065-001 (the numbers). A value of -1.4 (level 18.4, floor 19.8) is listed as
// rise_db -1, level_db 18, floor_db 20: each rounded on its own. My Tx parity higher changes
// nothing (#66): my Rx parity even flat 20 (floor 20.65), my odd period flat 30: 1500 reads rise
// -0.65, level 20, floor 20.65 and is listed {1500, -1, 20, 21}, for a selection and for a CQ alike;
// the period counts are {even {now 1}, odd {now null}}, and the other way round for my Rx parity
// odd.
#[test]
fn tc_065_001_rise_level_and_floor_round_alone_and_my_tx_parity_changes_nothing() {
    let numbers = |f: u32| {
        Some(if f == 1000 {
            Numbers {
                rise: -1.4,
                level: 18.4,
                floor: 19.8,
            }
        } else {
            Numbers {
                rise: 5.0,
                level: 25.0,
                floor: 20.0,
            }
        })
    };
    assert_eq!(
        free_slots(Mode::Ft8, 1500, &[], &[], None, &numbers)[0],
        Listed {
            hz: 1000,
            rise_db: -1,
            level_db: 18,
            floor_db: 20
        }
    );
    assert_eq!(listed(Mode::Ft8, 1500, &[], None, &numbers)[0], 1000);
    let periods = [period(1, false, 20, &[]), period(1, true, 30, &[])];
    let j = Judged::new(&periods, Mode::Ft8, Parity::Even, i64::MIN, NOW, &[]);
    let n = j.numbers(1500).unwrap();
    assert!(close(n.rise, -0.65) && close(n.level, 20.0) && close(n.floor, 20.65));
    assert_eq!(
        free_slots(Mode::Ft8, 1500, &[], &[], None, &|f| j.numbers(f))[0],
        Listed {
            hz: 1500,
            rise_db: -1,
            level_db: 20,
            floor_db: 21
        }
    );
    assert_eq!(
        period_counts(Parity::Even, j.count()),
        json!({"even":{"now":1},"odd":{"now":null}})
    );
    assert_eq!(
        period_counts(Parity::Odd, 3),
        json!({"even":{"now":null},"odd":{"now":3}})
    );
}
