#![forbid(unsafe_code)]
use super::*;
use serde_json::json;

const FT8: (u32, u32) = (300, 2650);

/// FT8 signals of the given frequencies.
fn ft8(list: &[u32]) -> Vec<Signal> {
    list.iter().map(|hz| (*hz, 50)).collect()
}

// Proves: TC-039-010. A FT8 signal at f forbids the slots strictly between f-100 and f+100
// (50 Hz of mine and the gap below it; 50 Hz of its own and the gap above it).
#[test]
fn tc_039_010_the_free_slot_table() {
    // (occupied, current, expected slot, what the row shows)
    let table: &[(&[u32], u32, u32, &str)] = &[
        (&[], 1500, 1500, "an empty band keeps the current Tx"),
        (&[1400], 1500, 1500, "exactly 50 Hz clear above is free"),
        (&[1600], 1500, 1500, "exactly 50 Hz clear below is free"),
        (&[1401], 1500, 1501, "1 Hz less above moves up by 1 Hz"),
        (&[1599], 1500, 1499, "1 Hz less below moves down by 1 Hz"),
        (&[1500], 1500, 1400, "a tie takes the lower slot"),
        (&[1480, 1620], 1500, 1380, "below the merged range"),
        (&[1540, 1380], 1500, 1640, "above the merged range"),
        (&[1400, 1600], 1500, 1500, "a slot exactly fitting a gap"),
        (&[1401, 1600], 1500, 1301, "a gap 1 Hz too small is skipped"),
        (&[], 250, 300, "under the lower edge moves to it"),
        (&[], 2800, 2650, "over the upper edge moves to it"),
        (&[300], 300, 400, "next to the lower edge goes up"),
        (&[2650], 2650, 2550, "next to the upper edge goes down"),
        (&[], 2650, 2650, "the highest FT8 slot ends at 2700 Hz"),
    ];
    for (occupied, current, expected, why) in table {
        assert_eq!(
            choose(&ft8(occupied), FT8, 50, *current, &[]),
            Some(*expected),
            "{why}"
        );
    }
}

// Proves: TC-039-010. Signals every 190 Hz leave no slot: each forbids 199 of them.
#[test]
fn tc_039_010_a_full_band_has_no_slot() {
    let full: Vec<u32> = (0..13).map(|i| 300 + 190 * i).collect();
    assert_eq!(choose(&ft8(&full), FT8, 50, 1500, &[]), None);
    assert_eq!(choose(&ft8(&full), FT8, 50, 1500, &[900, 2000]), None);
    // Without the signal at 2580 Hz the band above 2490 Hz is free.
    assert_eq!(choose(&ft8(&full[..12]), FT8, 50, 1500, &[]), Some(2490));
}

// Proves: TC-039-010. The extension for the later #39 slice.
#[test]
fn tc_039_010_preferred_frequencies_win_over_the_current_tx() {
    // (occupied, current, preferred, expected)
    let table: &[(&[u32], u32, &[u32], u32)] = &[
        (&[], 1500, &[900], 900),
        (&[], 1500, &[100], 300),
        (&[], 1500, &[3000], 2650),
        // The first preferred is taken, the second is free.
        (&[700], 1500, &[700, 1000], 1000),
        // 900 is busy: 800 and 1000 tie for it; 1000 is nearer the current Tx.
        (&[900], 1500, &[900], 1000),
        // The same tie, the current Tx exactly between them: the lowest.
        (&[900], 900, &[900], 800),
        // The slot it leaves goes in as occupied: another slot, near the preferred.
        (&[1500], 1500, &[1500], 1400),
    ];
    for (occupied, current, preferred, expected) in table {
        assert_eq!(
            choose(&ft8(occupied), FT8, 50, *current, preferred),
            Some(*expected),
            "{occupied:?} {current} {preferred:?}"
        );
    }
}

// Proves: TC-039-010. A FT4 signal is 90 Hz wide: at f it forbids f-140 < slot < f+140.
#[test]
fn tc_039_010_ft4_width_and_bounds() {
    assert_eq!(band(Mode::Ft8), FT8);
    assert_eq!(band(Mode::Ft4), (300, 2610));
    let signal = [(1500, width_hz(Mode::Ft4))];
    let bounds = band(Mode::Ft4);
    let width = width_hz(Mode::Ft4);
    assert_eq!(choose(&signal, bounds, width, 1640, &[]), Some(1640));
    assert_eq!(choose(&signal, bounds, width, 1639, &[]), Some(1640));
    assert_eq!(choose(&signal, bounds, width, 1361, &[]), Some(1360));
    assert_eq!(choose(&[], bounds, width, 2700, &[]), Some(2610));
}

fn decode(period: &str, hz: Value) -> Value {
    json!({"period_start_utc":period,"frequency_hz":hz})
}

// Proves: TC-039-010. :15 and :45 are odd FT8 periods, :00 and :30 even.
#[test]
fn tc_039_010_recent_means_four_decoding_periods_of_my_parity() {
    let records = [
        decode("2026-11-06T12:00:15.000Z", json!(100.0)),
        decode("2026-11-06T12:00:45.000Z", json!(200.4)),
        decode("2026-11-06T12:01:00.000Z", json!(250.0)),
        decode("2026-11-06T12:01:15.000Z", json!(299.6)),
        decode("2026-11-06T12:01:15.000Z", json!(310.0)),
        // 12:01:45 decoded nothing (my own Tx): the 12:00:45 period still counts.
        decode("2026-11-06T12:02:15.000Z", json!(400.0)),
        decode("2026-11-06T12:02:45.000Z", json!(500.0)),
        decode("not a time", json!(600.0)),
        decode("2026-11-06T12:02:45.000Z", Value::Null),
    ];
    assert_eq!(
        recent_signals(&records, Mode::Ft8, Parity::Odd, 4),
        [(200, 50), (300, 50), (310, 50), (400, 50), (500, 50)]
    );
    assert_eq!(
        recent_signals(&records, Mode::Ft8, Parity::Odd, 1),
        [(500, 50)]
    );
    assert_eq!(
        recent_signals(&records, Mode::Ft8, Parity::Even, 4),
        [(250, 50)]
    );
    assert_eq!(recent_signals(&[], Mode::Ft8, Parity::Odd, 4), []);
    // FT4: 7.5 s periods; :07.5 is odd and its signal 90 Hz wide.
    let ft4 = [
        decode("2026-11-06T12:00:00.000Z", json!(700.0)),
        decode("2026-11-06T12:00:07.500Z", json!(800.0)),
    ];
    assert_eq!(recent_signals(&ft4, Mode::Ft4, Parity::Odd, 4), [(800, 90)]);
}

/// One odd FT8 period per entry, the oldest first; `FULL` is a whole band of signals.
const FULL: &[f64] = &[
    300.0, 490.0, 680.0, 870.0, 1060.0, 1250.0, 1440.0, 1630.0, 1820.0, 2010.0, 2200.0, 2390.0,
    2580.0,
];
fn periods(list: &[&[f64]]) -> Vec<Value> {
    list.iter()
        .enumerate()
        .flat_map(|(i, signals)| {
            let period = format!("2026-11-06T12:{:02}:15.000Z", i);
            signals.iter().map(move |hz| decode(&period, json!(hz)))
        })
        .collect()
}

// Proves: TC-039-010. Worked by hand: an FT8 signal at f forbids f-100 < slot < f+100.
#[test]
fn tc_039_010_a_busy_band_looks_at_fewer_periods_and_never_at_the_called_station() {
    // (odd periods, current, called, expected, what the row shows)
    type Row<'a> = (&'a [&'a [f64]], u32, Option<u32>, (u32, bool), &'a str);
    let table: &[Row] = &[
        (
            &[&[1500.0]],
            1500,
            None,
            (1400, true),
            "one period, the tie",
        ),
        (
            &[FULL, &[1350.0], &[2000.0], &[1500.0]],
            1500,
            None,
            (1600, true),
            "4 fill: 3 forbid 1250..1600, 1900..2100",
        ),
        (
            &[FULL, FULL, &[1350.0], &[1500.0]],
            1500,
            None,
            (1600, true),
            "4 and 3 fill: 2 forbid 1250..1600",
        ),
        (
            &[FULL, FULL, FULL, &[1500.0]],
            1500,
            None,
            (1400, true),
            "4, 3 and 2 fill: the latest forbids 1400..1600",
        ),
        (
            &[&[1500.0], FULL],
            1600,
            None,
            (1600, false),
            "the latest fills: Tx keeps its frequency",
        ),
        (
            &[FULL],
            250,
            None,
            (250, false),
            "no called station: also outside the band",
        ),
        (
            &[FULL],
            1500,
            Some(2400),
            (1500, false),
            "the called station is far away",
        ),
        (
            &[FULL],
            1500,
            Some(1500),
            (1400, false),
            "never on the called station: the tie",
        ),
        (
            &[FULL],
            1500,
            Some(1450),
            (1550, false),
            "never next to it: 1350 < slot < 1550 forbidden",
        ),
        (
            &[&[1500.0]],
            1500,
            Some(1600),
            (1400, true),
            "the called station counts in every look",
        ),
    ];
    for (list, current, called, expected, why) in table {
        assert_eq!(
            decide(&periods(list), Mode::Ft8, Parity::Odd, *current, *called),
            *expected,
            "{why}"
        );
    }
}
