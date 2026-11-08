#![forbid(unsafe_code)]
// WstxStrategy::FreeTxSlot worked by hand: power tables in dB per candidate written here, the
// detailed bin of 12000/4096 Hz, and the operator's rule (lowest whole dB, a tie keeps the current
// Tx, else nearer, then lower; 50 Hz from the called station and from his decoded frequencies).
use super::*;

/// A power table: `floor` everywhere, the listed candidates at their own level.
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
    quietest(Mode::Ft8, current, called, his, power)
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
        quietest(Mode::Ft4, 1500, None, None, &ft4),
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
    assert_eq!(quietest(Mode::Ft4, 1500, Some(1800), None, &ft4).hz, 1940);
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
/// A period's mean levels: `floor` in every bin, `raised` over [from, to) Hz.
fn levels(floor: u8, raised: Option<(u32, u32, u8)>) -> Vec<f32> {
    row(floor, raised).into_iter().map(f32::from).collect()
}
/// A detailed row: `floor` in every bin, `raised` over [from, to) Hz.
fn row(floor: u8, raised: Option<(u32, u32, u8)>) -> Vec<u8> {
    (0..1024)
        .map(|bin| {
            let hz = bin as f64 * BIN_HZ;
            raised
                .filter(|(from, to, _)| hz >= f64::from(*from) && hz < f64::from(*to))
                .map_or(floor, |(_, _, level)| level)
        })
        .collect()
}

// Proves: TC-039-010. The per-period power: the mean level of each bin over the rows of a period;
// a period I transmitted in is not counted; the last 4 of a parity; a new live job starts empty;
// the open period counts once it has ended.
#[test]
fn tc_039_010_the_waterfall_counts_received_periods_of_each_parity() {
    let job = ("job", 1);
    let mut w = Waterfall::default();
    // Six even periods: 20 dB, except a 60 dB band 1000..1100 Hz in the oldest two.
    for n in 0..6 {
        let start = EVEN + n * 30_000;
        let raised = (n < 2).then_some((1000, 1100, 60));
        w.row(job, start, 15_000, &row(20, raised), false);
        w.row(job, start, 15_000, &row(30, raised), false);
        // My own odd periods: a loud band, but transmitted in.
        w.row(job, start + 15_000, 15_000, &row(90, None), true);
    }
    let all = w.periods(job, EVEN + 6 * 30_000);
    assert_eq!(all.len(), 6, "the transmitted periods are not counted");
    assert_eq!(all[0].levels[0], 25.0, "the mean of the two rows");
    let even = recent(&all, Mode::Ft8, Parity::Even, i64::MIN);
    assert_eq!(even.len(), 4, "the last 4");
    assert_eq!(even[0].start_ms, EVEN + 2 * 30_000);
    assert_eq!(
        slot_power(&even, 1000, 50),
        Some(25.0),
        "the raised band is older"
    );
    assert!(recent(&all, Mode::Ft8, Parity::Odd, i64::MIN).is_empty());
    // After a band change only periods from then on count.
    assert_eq!(
        recent(&all, Mode::Ft8, Parity::Even, EVEN + 4 * 30_000).len(),
        2
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

// Proves: TC-039-010. The power of a slot is over the bins of [f, f + width): a 60 dB band at
// 1000..1100 Hz on a 20 dB floor; while only listening the louder parity counts.
#[test]
fn tc_039_010_slot_power_is_over_its_width_and_listening_takes_the_louder_parity() {
    let quiet = Period {
        start_ms: EVEN,
        levels: levels(20, Some((1000, 1100, 60))),
    };
    let periods = [&quiet];
    assert_eq!(slot_power(&periods, 900, 50), Some(20.0));
    assert_eq!(slot_power(&periods, 1000, 50), Some(60.0));
    assert_eq!(
        slot_power(&periods, 1100, 50),
        Some(20.0),
        "the band ends below 1100"
    );
    // 1080..1130: bins 369..385 (1081.1..1127.9 Hz), of them 369..375 (to 1098.6 Hz) raised.
    let raised = (369..=375).count() as f64;
    let all = (369..=385).count() as f64;
    let expected = (raised * 60.0 + (all - raised) * 20.0) / all;
    assert_eq!(slot_power(&periods, 1080, 50), Some(expected));
    assert_eq!(slot_power(&[], 1000, 50), None, "no period");
    // Listening: even quiet at 1800, odd loud there: the louder counts, so 1800 is no slot; the
    // nearest at the 30 dB floor are 1740 (bins to 1787 Hz) and 1860, equally near: the lower.
    let even = Period {
        start_ms: EVEN,
        levels: levels(30, Some((1790, 1860, 10))),
    };
    let odd = Period {
        start_ms: ODD,
        levels: levels(30, Some((1790, 1860, 70))),
    };
    let both = |f: u32| {
        let a = slot_power(&[&even], f, 50)?;
        let b = slot_power(&[&odd], f, 50)?;
        Some(a.max(b))
    };
    assert_eq!(quietest(Mode::Ft8, 1800, None, None, &both).hz, 1740);
}

// #65 WstxStrategy::FreeTxSlots (TC-065-001). Oracle: the operator's rules of 2026-11-08 (issue #65
// Functionality 1.2-1.7), worked by hand in each test from rise tables written here; every list is
// also checked against the choice (1.7): its first slot is quietest_clear's hz and power_db.

/// A rise table: `floor` everywhere, the listed candidates at their own rise; each slot's usual
/// level 20 dB and its power now 20 dB plus its rise.
fn rises(floor: f64, levels: &[(u32, f64)]) -> impl Fn(u32) -> Option<Numbers> {
    let t = table(floor, levels);
    move |f| {
        t(f).map(|rise| Numbers {
            rise,
            level: 20.0 + rise,
            usual: 20.0,
        })
    }
}
/// The listed hz of a decision, checked against the choice (1.7 Agreement).
fn list(
    mode: Mode,
    current: u32,
    avoid: &[u32],
    his: Option<&[u32]>,
    numbers: &dyn Fn(u32) -> Option<Numbers>,
) -> Vec<u32> {
    let listed = free_slots(mode, current, avoid, his, numbers);
    let chosen = quietest_clear(mode, current, avoid, his, &|f| numbers(f).map(|n| n.rise));
    match listed.first() {
        Some(first) => assert_eq!(
            (first.hz, Some(first.rise_db)),
            (chosen.hz, chosen.power_db),
            "the first listed is the chosen slot"
        ),
        None => assert_eq!(chosen.power_db, None, "an empty list only without power"),
    }
    assert!(listed.len() <= SLOTS_LISTED);
    listed.iter().map(|l| l.hz).collect()
}

// Proves: CL-065-01; TC-065-001 (count, rank order, no power). Seven separate quiet places from Tx
// 1500 on a floor of rise 10: 400 at -2, 700 at -1, 1000, 1300 and 1800 at 0, 2100 at 1, 2400 at 2.
// Rank: -2, -1, then the three at 0 by distance to 1500 (1300 200 Hz, 1800 300 Hz, 1000 500 Hz):
// exactly 5, 2100 and 2400 are not listed. Three candidates only: called stations every 150 to 200
// Hz leave exactly 1000, 1500 and 2000 (each excludes the 19 grid slots within 90 Hz), all at rise
// 0: 1500 (the current Tx), then 1000 and 2000 at 500 Hz, the lower first; 3 listed. No power: an
// empty list, also when one candidate alone has none (the choice's "No power yet").
#[test]
fn tc_065_001_five_listed_in_rank_order_fewer_when_fewer_none_without_power() {
    let seven = rises(
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
        list(Mode::Ft8, 1500, &[], None, &seven),
        [400, 700, 1300, 1800, 1000]
    );
    let called = [
        300, 450, 600, 750, 900, 1100, 1250, 1400, 1600, 1750, 1900, 2100, 2250, 2400, 2550, 2700,
    ];
    assert_eq!(
        list(Mode::Ft8, 1500, &called, None, &rises(0.0, &[])),
        [1500, 1000, 2000]
    );
    assert_eq!(
        list(Mode::Ft8, 1500, &[], None, &|_| None),
        Vec::<u32>::new()
    );
    let one_without = |f: u32| {
        (f != 2000).then_some(Numbers {
            rise: 0.0,
            level: 20.0,
            usual: 20.0,
        })
    };
    assert_eq!(
        free_slots(Mode::Ft8, 1500, &[], None, &one_without),
        Vec::new()
    );
}

// Proves: CL-065-01; TC-065-001 (whole dB and the tie rule). Tx 1500 at 0.4 against 1800 at 0.0 on a
// floor of 5: both are 0 in whole dB, a tie, and the current Tx comes first; at 0.6 1500 is 1 dB and
// 1800 comes first. Equal rises on both sides of Tx 1500: 1300 and 1600 at 0, the nearer (1600,
// 100 Hz) first; 1400 and 1600 at 0, equally near: the lower first.
#[test]
fn tc_065_001_ties_in_whole_db_keep_the_current_tx_then_nearer_then_lower() {
    let tied = list(
        Mode::Ft8,
        1500,
        &[],
        None,
        &rises(5.0, &[(1500, 0.4), (1800, 0.0)]),
    );
    assert_eq!(tied[..2], [1500, 1800]);
    let louder = list(
        Mode::Ft8,
        1500,
        &[],
        None,
        &rises(5.0, &[(1500, 0.6), (1800, 0.0)]),
    );
    assert_eq!(louder[..2], [1800, 1500]);
    let sides = list(
        Mode::Ft8,
        1500,
        &[],
        None,
        &rises(5.0, &[(1300, 0.0), (1600, 0.0)]),
    );
    assert_eq!(sides[..2], [1600, 1300]);
    let equal = list(
        Mode::Ft8,
        1500,
        &[],
        None,
        &rises(5.0, &[(1400, 0.0), (1600, 0.0)]),
    );
    assert_eq!(equal[..2], [1400, 1600]);
}

// Proves: CL-065-01; TC-065-001 (non-overlap at the slot width). FT8 (50 Hz), Tx 1500, floor 10:
// 1000 at 0, 1040 at 1, 1050 at 2. 1040 is 40 Hz from the listed 1000 and skipped, 1050 is 50 Hz
// away and listed; then the floor by distance to 1500: 1500, 1450 and 1550 (each 50 Hz from 1500).
// FT4 (90 Hz): 1000 at 0, 1080 at 1, 1090 at 2: 1080 skipped, 1090 listed, then 1500, 1410, 1590.
#[test]
fn tc_065_001_a_candidate_closer_than_the_slot_width_is_skipped() {
    let ft8 = rises(10.0, &[(1000, 0.0), (1040, 1.0), (1050, 2.0)]);
    assert_eq!(
        list(Mode::Ft8, 1500, &[], None, &ft8),
        [1000, 1050, 1500, 1450, 1550]
    );
    let ft4 = rises(10.0, &[(1000, 0.0), (1080, 1.0), (1090, 2.0)]);
    assert_eq!(
        list(Mode::Ft4, 1500, &[], None, &ft4),
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
    let near_him = rises(10.0, &[(950, -5.0), (1090, -6.0), (1100, -5.0)]);
    let listed = list(Mode::Ft8, 1500, &[1000], None, &near_him);
    assert_eq!(listed[0], 1100);
    assert!(
        listed.iter().all(|f| !(910..=1090).contains(f)),
        "{listed:?}"
    );
    let near_rx = rises(10.0, &[(1050, -5.0)]);
    assert!(!list(Mode::Ft8, 1500, &[2000, 1000], None, &near_rx).contains(&1050));
    assert_eq!(list(Mode::Ft8, 1500, &[2000], None, &near_rx)[0], 1050);
    let at_his = rises(10.0, &[(1200, -5.0), (1250, -4.0)]);
    let listed = list(Mode::Ft8, 1500, &[], Some(&[1200]), &at_his);
    assert_eq!(listed[0], 1250);
    assert!(
        listed.iter().all(|f| !(1160..=1240).contains(f)),
        "{listed:?}"
    );
    let everywhere: Vec<u32> = (300..=2700).step_by(10).collect();
    assert_eq!(
        list(Mode::Ft8, 1500, &[], Some(&everywhere), &at_his)[0],
        1200
    );
}

// Proves: CL-065-01; TC-065-001 (the numbers). A rise of -1.4 (power now 18.4, usual 19.8) is listed
// as rise_db -1, level_db 18, usual_db 20: each rounded on its own. Listening (FT8, my Rx parity
// even): an even period flat 20 and an odd one flat 30: the usual level is 20 (the lowest period),
// the power now the larger parity's 30, so rise 10 and level 30; for a selection (my Rx parity alone)
// level 20, rise 0. The period counts: one of each parity now while listening, the odd (Tx parity)
// null for a selection; one of each in the usual level.
#[test]
fn tc_065_001_rise_level_and_usual_round_alone_and_listening_takes_the_larger_level() {
    let numbers = |f: u32| {
        Some(if f == 1000 {
            Numbers {
                rise: -1.4,
                level: 18.4,
                usual: 19.8,
            }
        } else {
            Numbers {
                rise: 5.0,
                level: 25.0,
                usual: 20.0,
            }
        })
    };
    assert_eq!(
        free_slots(Mode::Ft8, 1500, &[], None, &numbers)[0],
        Listed {
            hz: 1000,
            rise_db: -1,
            level_db: 18,
            usual_db: 20
        }
    );
    assert_eq!(list(Mode::Ft8, 1500, &[], None, &numbers)[0], 1000);
    let periods = [
        Period {
            start_ms: EVEN,
            levels: levels(20, None),
        },
        Period {
            start_ms: ODD,
            levels: levels(30, None),
        },
    ];
    let at = |listening| numbers_of(&periods, listening);
    assert_eq!(
        at(true),
        Some(Numbers {
            rise: 10.0,
            level: 30.0,
            usual: 20.0
        })
    );
    assert_eq!(
        at(false),
        Some(Numbers {
            rise: 0.0,
            level: 20.0,
            usual: 20.0
        })
    );
    let listening = |l: bool| {
        free_slots(Mode::Ft8, 1500, &[], None, &|f| {
            crate::freeslot::numbers(&periods, Mode::Ft8, Parity::Even, i64::MIN, f, l)
        })[0]
    };
    assert_eq!(
        listening(true),
        Listed {
            hz: 1500,
            rise_db: 10,
            level_db: 30,
            usual_db: 20
        }
    );
    assert_eq!(
        period_counts(&periods, Mode::Ft8, Parity::Even, i64::MIN, true),
        json!({"even":{"now":1,"usual":1},"odd":{"now":1,"usual":1}})
    );
    assert_eq!(
        period_counts(&periods, Mode::Ft8, Parity::Even, i64::MIN, false),
        json!({"even":{"now":1,"usual":1},"odd":{"now":null,"usual":1}})
    );
}
fn numbers_of(periods: &[Period], listening: bool) -> Option<Numbers> {
    numbers(periods, Mode::Ft8, Parity::Even, i64::MIN, 1500, listening)
}
