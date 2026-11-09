#![forbid(unsafe_code)]
// Proves: CL-063-01, CL-063-02, CL-063-03, CL-063-04, CL-063-05, CL-063-06; TC-063-003, TC-063-004,
// TC-063-007, TC-063-009, TC-063-010, TC-063-011.
// Proves: CL-039-01, CL-039-02, CL-039-03, CL-039-05, CL-039-06, CL-039-09, CL-039-10, CL-042-01, CL-042-02,
// CL-042-03, CL-042-04; TC-039-001..005, TC-039-010, TC-039-030..032, TC-042-001, TC-042-002,
// TC-042-004, TC-042-006 (each test names its case below). Hand-authored records, logs and
// strategies; the expected verdicts, orders, stop reasons and requests are the WstxStrategy
// tables written in these tests (entities from the cited cty.dat columns), not evaluator output.
// Integration cases use the actual station router, contact engine and #9 transmit owner
// on the recording hardware double (virtual UTC; no audio, PTT or radio).
use super::*;
use crate::automation_tests::{at_even, not_keyed_in, publish, run_state, transmit_own_period};
use crate::contact_http_tests::{period_text, record};
use crate::dxcc::Logged;
use crate::mcp_tests::{Mcp, station};
use std::sync::Arc;
use std::sync::atomic::Ordering;
use wstx_rust::transmit::service::Hardware;
// #81 WstxStrategy::StartedQso (TC-081-001..005), on this file's station helpers.
#[path = "autofinish_tests.rs"]
mod autofinish;

fn rows(list: &[(&str, Option<f64>)]) -> Vec<Value> {
    list.iter()
        .enumerate()
        .map(|(i, (text, snr))| {
            let mut r = record(text, 1000.0 + i as f64 * 100.0, *snr);
            r["sequence"] = json!(i);
            r
        })
        .collect()
}
fn me() -> Station {
    Station {
        my_call: "HB9BLA".into(),
        my_continent: Some("EU".into()),
        band: Some("40m".into()),
        mode: "FT8".into(),
        worked: Some(Arc::new(Worked::default())),
        ..Station::default()
    }
}
fn award(goals: &[Goal]) -> Strategy {
    Strategy {
        name: "T".into(),
        goals: goals.to_vec(),
        needed: Needed::NotWorked,
        region: Region::All,
        min_snr_db: None,
        value: vec![Criterion::MostWanted],
        callers_first: true,
        cq_when_no_target: false,
        repetitions: 3,
        quiet_minutes: 10,
        treat_73_as_cq: false,
        window: Window::All,
    }
}
/// (call, band, mode, grid, confirmed).
type LogRow<'a> = (
    &'a str,
    Option<&'a str>,
    Option<&'a str>,
    Option<&'a str>,
    bool,
);
fn worked(log: &[LogRow]) -> Arc<Worked> {
    let logged: Vec<Logged> = log
        .iter()
        .map(|(call, band, mode, grid, confirmed)| Logged {
            call: (*call).into(),
            grid: grid.map(Into::into),
            band: band.map(Into::into),
            mode: mode.map(Into::into),
            confirmed: *confirmed,
            date: Some(20_260_101),
        })
        .collect();
    Arc::new(Worked::from_log(&crate::dxcc::Table::default(), &logged))
}
fn ranks(s: &Strategy, records: &[Value], st: &Station) -> Vec<(u64, Option<usize>, bool)> {
    let mut v: Vec<(u64, Option<usize>, bool)> = evaluate(s, records, st)
        .into_iter()
        .map(|v| (v.facts.sequence, v.rank, v.grey))
        .collect();
    v.sort_by_key(|x| x.0);
    v
}
/// The ranked calls in value order.
fn called(s: &Strategy, records: &[Value], st: &Station) -> Vec<String> {
    evaluate(s, records, st)
        .into_iter()
        .filter(|v| v.rank.is_some())
        .map(|v| v.facts.from)
        .collect()
}
fn table() -> Vec<Value> {
    rows(&[
        ("CQ K1ABC FN42", Some(-12.0)),      // 0 NA
        ("CQ DL1XYZ JO62", Some(-3.0)),      // 1 EU
        ("CQ NA W1AW FN31", Some(-5.0)),     // 2 directed NA: not for EU
        ("CQ EU G4ABC IO91", Some(-8.0)),    // 3 directed EU: for me
        ("CQ DX OH1AA KP20", Some(-1.0)),    // 4 DX from EU: not for me
        ("CQ DX JA1XYZ PM95", Some(-15.0)),  // 5 DX from AS: for me
        ("W1AW K1ABC RR73", Some(-6.0)),     // 6 K1ABC ends a QSO
        ("HB9BLA VK2ABC QF56", Some(-20.0)), // 7 calls me
        ("CQ TEST N1MM FN31", Some(-2.0)),   // 8 not continent-directed
    ])
}

// Proves: TC-039-002
#[test]
fn tc_039_002_continent_and_directed_cq_rule() {
    // #55: the continent of a station is its cty.dat entity's (the continent column of
    // the cited cty.dat lines), whatever grid it sends.
    let st = me();
    for (call, continent) in [
        ("HB9BLA", "EU"), // Switzerland, line 1118
        ("K1ABC", "NA"),  // United States, line 1251
        ("OH1AA", "EU"),  // Finland
        ("JA1XYZ", "AS"), // Japan, line 1223
        ("VK2ABC", "OC"), // Australia, line 3977
        ("PY1AA", "SA"),  // Brazil
        ("ZS6AA", "AF"),  // South Africa
        ("CE9AA", "SA"),  // Antarctica: cty.dat files it under SA, line 541
        ("UA9ABC", "AS"), // Asiatic Russia, line 3384
    ] {
        assert_eq!(st.dxcc.continent(call), Some(continent), "{call}");
    }
    assert_eq!(st.dxcc.continent("Q1ABC"), None);
    assert_eq!(st.dxcc.continent("K1ABC/MM"), None);
    for (target, mine, sender, expected) in [
        ("EU", Some("EU"), None, true),
        ("NA", Some("EU"), Some("NA"), false),
        ("EU", None, Some("EU"), false),
        ("DX", Some("EU"), Some("EU"), false),
        ("DX", Some("EU"), Some("AS"), true),
        ("DX", Some("EU"), None, false),
        // #39 2026-11-04: every other directive excludes me.
        ("TEST", Some("EU"), Some("NA"), false),
        ("POTA", None, None, false),
        ("JA", Some("EU"), Some("AS"), false),
        // A non-EU profile (K1ABC, NA).
        ("NA", Some("NA"), Some("NA"), true),
        ("EU", Some("NA"), Some("EU"), false),
        ("DX", Some("NA"), Some("AS"), true),
        ("DX", Some("NA"), Some("NA"), false),
    ] {
        assert_eq!(
            answerable(Some(target), mine, sender),
            expected,
            "CQ {target} mine {mine:?} sender {sender:?}"
        );
    }
}

// Proves: TC-039-002
#[test]
fn tc_039_002_verdicts_grey_reasons_and_treat_73() {
    let records = table();
    let st = me();
    let s = award(&[Goal::NewCall]);
    let list = evaluate(&s, &records, &st);
    assert_eq!(
        list.iter()
            .map(|v| (v.facts.sequence, v.rank, v.grey))
            .collect::<Vec<_>>(),
        vec![
            (7, Some(0), false), // the caller first
            (1, Some(1), false), // all new DXCC: SNR -3
            (3, Some(2), false), // -8
            (0, Some(3), false), // -12
            (5, Some(4), false), // -15
            (2, None, true),
            (4, None, true),
            (6, None, false), // an RR73 without Treat 73 as CQ
            (8, None, true),
        ],
        "display order: by rank, then the rest in their order"
    );
    let why: HashMap<u64, String> = list
        .iter()
        .map(|v| (v.facts.sequence, v.why.clone()))
        .collect();
    assert_eq!(why[&7], "calls my call");
    assert_eq!(why[&0], "needed: new_call");
    assert_eq!(why[&2], "CQ NA — not for EU");
    assert_eq!(why[&6], "not a CQ");
    let json = list[0].json(true);
    assert_eq!(
        json,
        json!({"sequence":7,"rank":0,"grey":false,"why":"calls my call"})
    );
    assert_eq!(
        list[5].json(false),
        json!({"sequence":2,"rank":null,"grey":true})
    );
    // Treat 73 as CQ: K1ABC's RR73 is a candidate; a message to me is never cq-like.
    let treat = Strategy {
        treat_73_as_cq: true,
        ..award(&[Goal::NewCall])
    };
    assert!(ranks(&treat, &records, &st)[6].1.is_some());
    assert!(st.cq_like(&facts(&records[6]).unwrap(), true));
    let to_me = rows(&[("HB9BLA K1ABC RR73", Some(-1.0))]);
    assert!(!st.cq_like(&facts(&to_me[0]).unwrap(), true));
    // Its own RR73 to me is no caller.
    assert_eq!(
        evaluate(&treat, &to_me, &st)[0].rank,
        None,
        "RR73 to me: neither caller nor candidate"
    );
    // Unknown continent: every directive greyed; plain CQs stay.
    let mut unknown = me();
    unknown.my_continent = None;
    let greyed: Vec<u64> = ranks(&s, &records, &unknown)
        .into_iter()
        .filter(|r| r.2)
        .map(|r| r.0)
        .collect();
    assert_eq!(greyed, vec![2, 3, 4, 5, 8]);
    // A CQ from my own call and the callsign guard.
    let own = rows(&[("CQ HB9BLA JN47", Some(1.0)), ("CQ W1AW/R FN31", Some(1.0))]);
    let list = evaluate(&s, &own, &st);
    assert_eq!(
        (
            list[0].rank,
            list[0].why.as_str(),
            list[1].rank,
            list[1].why.as_str()
        ),
        (None, "my own message", None, "callsign guard")
    );
    for (call, sane) in [
        ("W1AW", true),
        ("K1", false),
        ("ABCDE", false),
        ("W1AW/R", false),
    ] {
        assert_eq!(sane_call(call), sane, "{call}");
    }
}

// Entity columns of cty.dat: DL Fed. Rep. of Germany (CQ 14), F
// France (14), JA Japan (25), K United States (5), VK Australia (30); XX1ABC has no entity.
fn goal_log() -> Arc<Worked> {
    worked(&[
        ("DL1ABC", Some("40m"), Some("FT8"), Some("JO62"), false),
        ("F1ABC", Some("40m"), Some("FT4"), Some("JN18"), true),
        ("JA1XYZ", Some("20m"), Some("FT8"), Some("PM95"), true),
        ("K2ABC", None, None, None, false),
        ("Q1ABC", Some("40m"), Some("FT8"), Some("JO70"), true),
    ])
}
fn goal_rows() -> Vec<Value> {
    rows(&[
        ("CQ DL2XYZ JO50", Some(-1.0)),
        ("CQ F5ABC JN05", Some(-2.0)),
        ("CQ JA2ABC PM85", Some(-3.0)),
        ("CQ VK2ABC QF56", Some(-4.0)),
        ("CQ K1ABC FN42", Some(-5.0)),
        ("CQ XX1ABC JO62", Some(-6.0)),
        ("CQ DL1ABC JO62", Some(-7.0)),
    ])
}
const G1: &str = "DL2XYZ";
const G2: &str = "F5ABC";
const G3: &str = "JA2ABC";
const G4: &str = "VK2ABC";
const G5: &str = "K1ABC";
const G6: &str = "XX1ABC";
const G7: &str = "DL1ABC";
/// The candidates of one goal, in row order.
fn of_goal(goal: Goal, needed: Needed, st: &Station) -> Vec<&'static str> {
    let s = Strategy {
        needed,
        ..award(&[goal])
    };
    let got = called(&s, &goal_rows(), st);
    [G1, G2, G3, G4, G5, G6, G7]
        .into_iter()
        .filter(|c| got.iter().any(|g| g == c))
        .collect()
}

// Proves: TC-039-030, TC-042-001
#[test]
fn tc_039_030_each_goal_in_both_needed_settings() {
    let st = Station {
        worked: Some(goal_log()),
        ..me()
    };
    assert_eq!(st.dxcc.lookup("XX1ABC"), None, "no entity");
    use Goal::*;
    use Needed::*;
    for (goal, needed, expected) in [
        (Dxcc, NotWorked, vec![G4]),
        (DxccBand, NotWorked, vec![G3, G4, G5]),
        (DxccSlot, NotWorked, vec![G2, G3, G4, G5]),
        (Waz, NotWorked, vec![G4]),
        (Wpx, NotWorked, vec![G1, G2, G3, G4, G5, G6]),
        (Grid, NotWorked, vec![G1, G2, G3, G4, G5]),
        (NewCall, NotWorked, vec![G1, G2, G3, G4, G5, G6]),
        // Germany and the U.S. are worked, not confirmed; France and Japan confirmed.
        (Dxcc, NotConfirmed, vec![G1, G4, G5, G7]),
        (DxccBand, NotConfirmed, vec![G1, G3, G4, G5, G7]),
        (DxccSlot, NotConfirmed, vec![G1, G2, G3, G4, G5, G7]),
        // Zone 14 is confirmed by F1ABC, 25 by JA1XYZ; zone 5 only worked.
        (Waz, NotConfirmed, vec![G4, G5]),
        (Wpx, NotConfirmed, vec![G1, G2, G3, G4, G5, G6, G7]),
        (Grid, NotConfirmed, vec![G1, G2, G3, G4, G5, G6, G7]),
        (NewCall, NotConfirmed, vec![G1, G2, G3, G4, G5, G6, G7]),
    ] {
        assert_eq!(of_goal(goal, needed, &st), expected, "{goal:?} {needed:?}");
    }
    // Multiple goals: needed when at least one is.
    let both = award(&[Dxcc, DxccBand]);
    // In value order: without a list the strongest first.
    assert_eq!(called(&both, &goal_rows(), &st), vec![G3, G4, G5]);
    // The station band unknown: the band goals never hold, the others unchanged.
    let unknown = Station {
        band: None,
        worked: Some(goal_log()),
        ..me()
    };
    assert_eq!(of_goal(DxccBand, NotWorked, &unknown), Vec::<&str>::new());
    assert_eq!(of_goal(DxccSlot, NotWorked, &unknown), Vec::<&str>::new());
    assert_eq!(of_goal(Dxcc, NotWorked, &unknown), vec![G4]);
    assert_eq!(of_goal(Waz, NotWorked, &unknown), vec![G4]);
    // The log unreadable: no claim of needed, whatever the goal.
    let unreadable = Station {
        worked: None,
        ..me()
    };
    for goal in [Dxcc, DxccBand, DxccSlot, Waz, Wpx, Grid, NewCall] {
        assert_eq!(of_goal(goal, NotWorked, &unreadable), Vec::<&str>::new());
    }
}

// Proves: TC-039-030
#[test]
fn tc_039_030_a_missing_grid_is_unknown_never_new() {
    let st = Station {
        worked: Some(worked(&[
            ("K2ABC", Some("40m"), Some("FT8"), None, false),
            ("K3ABC", Some("40m"), Some("FT8"), Some(""), false),
            ("K4ABC", Some("40m"), Some("FT8"), Some("FN42"), false),
        ])),
        ..me()
    };
    let s = Strategy {
        treat_73_as_cq: true,
        ..award(&[Goal::Grid])
    };
    for (text, expected, why) in [
        // No grid in the decoded message: not a candidate on this goal.
        ("W1AW DL9ZZ RR73", None, "not needed"),
        // A sender in the log with a QSO without a grid: its grid status is unknown.
        ("CQ K2ABC FN55", None, "not needed"),
        ("CQ K3ABC FN55", None, "not needed"),
        // A sender logged with a grid and a new grid; a new sender.
        ("CQ K4ABC FN55", Some(0), "needed: grid"),
        ("CQ K5ABC FN66", Some(0), "needed: grid"),
        // The grid is worked.
        ("CQ K6ABC FN42", None, "not needed"),
    ] {
        let v = evaluate(&s, &rows(&[(text, Some(0.0))]), &st);
        assert_eq!((v[0].rank, v[0].why.as_str()), (expected, why), "{text}");
    }
}

// Proves: TC-039-030
#[test]
fn tc_039_030_region_min_snr_for_an_eu_and_a_non_eu_profile() {
    let records = rows(&[
        ("CQ K1ABC FN42", Some(-10.0)),
        ("CQ DL2XYZ JO50", Some(-5.0)),
        ("CQ JA2ABC PM85", Some(-1.0)),
        ("CQ XX1ABC JO01", Some(0.0)),
    ]);
    let region = |r: Region, st: &Station| {
        called(
            &Strategy {
                region: r,
                ..award(&[Goal::NewCall])
            },
            &records,
            st,
        )
    };
    let eu = me();
    let na = Station {
        my_continent: Some("NA".into()),
        ..me()
    };
    let none = Station {
        my_continent: None,
        ..me()
    };
    let all = |list: &[&str]| list.iter().map(|c| c.to_string()).collect::<Vec<_>>();
    assert_eq!(
        region(Region::All, &eu),
        all(&["XX1ABC", "JA2ABC", "DL2XYZ", "K1ABC"])
    );
    // dx: another continent than mine, an unknown continent never.
    assert_eq!(region(Region::Dx, &eu), all(&["JA2ABC", "K1ABC"]));
    assert_eq!(region(Region::Dx, &na), all(&["JA2ABC", "DL2XYZ"]));
    assert_eq!(region(Region::Dx, &none), all(&[]));
    assert_eq!(
        region(Region::Selected(vec!["AS".into(), "NA".into()]), &eu),
        all(&["JA2ABC", "K1ABC"])
    );
    assert_eq!(region(Region::Selected(vec!["SA".into()]), &eu), all(&[]));
    // min SNR is inclusive; an unknown SNR is below any minimum.
    let snr = |min: Option<i64>, snr: Option<f64>| {
        let s = Strategy {
            min_snr_db: min,
            ..award(&[Goal::NewCall])
        };
        evaluate(&s, &rows(&[("CQ K1ABC FN42", snr)]), &eu)[0].rank
    };
    assert_eq!(snr(Some(-10), Some(-10.0)), Some(0));
    assert_eq!(snr(Some(-10), Some(-11.0)), None);
    assert_eq!(snr(Some(-10), None), None);
    assert_eq!(snr(None, None), Some(0));
}

// Proves: TC-039-030
#[test]
fn tc_039_030_a_caller_beats_a_most_wanted_station_and_ignores_goal_region_and_snr() {
    let list = crate::most_wanted::List::parse(r#"{"1":"150"}"#, "2026-11-06");
    let st = Station {
        // The caller is worked and confirmed on every goal; Australia is rank 1.
        worked: Some(worked(&[(
            "DL1ABC",
            Some("40m"),
            Some("FT8"),
            Some("JO62"),
            true,
        )])),
        most_wanted: list.map(Arc::new),
        ..me()
    };
    let s = Strategy {
        goals: vec![Goal::NewCall],
        region: Region::Selected(vec!["OC".into()]),
        min_snr_db: Some(20),
        ..award(&[Goal::NewCall])
    };
    let records = rows(&[
        ("CQ VK2ABC QF56", Some(25.0)),
        ("HB9BLA DL1ABC -15", Some(-20.0)),
    ]);
    assert_eq!(
        ranks(&s, &records, &st),
        vec![(0, Some(1), false), (1, Some(0), false)]
    );
    let v = evaluate(&s, &records, &st);
    assert_eq!(v[1].why, "needed: new_call · Most Wanted #1");
    // An ignored caller is neither: it has no rank.
    let mut ignored = st.clone();
    ignored.ignored.insert("DL1ABC".into(), Tier::Session);
    assert_eq!(ranks(&s, &records, &ignored)[1], (1, None, false));
    // Two callers: strongest first.
    assert_eq!(
        called(
            &s,
            &rows(&[
                ("HB9BLA K1ABC -10", Some(-9.0)),
                ("HB9BLA K2ABC -10", Some(-2.0))
            ]),
            &st
        ),
        vec!["K2ABC", "K1ABC"]
    );
}

// Proves: TC-039-030
#[test]
fn tc_039_030_value_order_with_and_without_a_list() {
    // Germany on 20m only, France on 40m FT4 only, England on 40m FT8.
    let log = worked(&[
        ("DL1ABC", Some("20m"), Some("FT8"), Some("JO62"), false),
        ("F1ABC", Some("40m"), Some("FT4"), Some("JN18"), false),
        ("G1ABC", Some("40m"), Some("FT8"), Some("IO91"), false),
    ]);
    let records = rows(&[
        ("CQ G4XYZ IO92", Some(5.0)),
        ("CQ F5ABC JN05", Some(0.0)),
        ("CQ DL2XYZ JO50", Some(-2.0)),
        ("CQ VK2ABC QF56", Some(-20.0)),
        ("CQ JA2ABC PM85", Some(-5.0)),
    ]);
    let s = award(&[Goal::NewCall]);
    let plain = Station {
        worked: Some(log.clone()),
        ..me()
    };
    assert_eq!(
        called(&s, &records, &plain),
        vec!["G4XYZ", "F5ABC", "DL2XYZ", "JA2ABC", "VK2ABC"],
        "no list: the strongest first, whatever is new"
    );
    // ADIF 230 Germany, 150 Australia: on the list first, by rank; the others after, strongest.
    let listed = Station {
        worked: Some(log),
        most_wanted: crate::most_wanted::List::parse(r#"{"1":"230","2":"150","3":"999"}"#, "d")
            .map(Arc::new),
        ..me()
    };
    assert_eq!(
        called(&s, &records, &listed),
        vec!["DL2XYZ", "VK2ABC", "G4XYZ", "F5ABC", "JA2ABC"]
    );
    // Same entity, same rank: the SNR decides, then the sequence.
    assert_eq!(
        called(
            &s,
            &rows(&[
                ("CQ DL2AAA JO50", Some(-9.0)),
                ("CQ DL2BBB JO50", Some(-1.0)),
                ("CQ DL2CCC JO50", Some(-1.0)),
            ]),
            &listed
        ),
        vec!["DL2BBB", "DL2CCC", "DL2AAA"]
    );
}

// Proves: TC-039-030
#[test]
fn tc_039_030_worked_window_from_dated_records() {
    let table = crate::dxcc::Table::default();
    let log = |call: &str, date: Option<u32>| Logged {
        call: call.into(),
        grid: None,
        band: Some("40m".into()),
        mode: Some("FT8".into()),
        confirmed: false,
        date,
    };
    let logged = vec![
        log("DL1ABC", Some(20_261_101)),
        log("F1ABC", Some(20_261_106)),
        log("K2ABC", None),
    ];
    let s = |w: &Worked, c: &str| w.call_standing(c).worked;
    let all = Worked::from_log(&table, &logged);
    assert!(
        s(&all, "DL1ABC") && s(&all, "F1ABC") && s(&all, "K2ABC"),
        "all time"
    );
    let first = Worked::from_log_window(&table, &logged, Some((20_261_101, 20_261_105)));
    assert_eq!(
        (s(&first, "DL1ABC"), s(&first, "F1ABC"), s(&first, "K2ABC")),
        (true, false, false),
        "from-to; a record without a date counts only for all time"
    );
    let day = Worked::from_log_window(&table, &logged, Some((20_261_106, 20_261_106)));
    assert_eq!(
        (s(&day, "DL1ABC"), s(&day, "F1ABC"), s(&day, "K2ABC")),
        (false, true, false),
        "one UTC date, both bounds inclusive"
    );
    // A strategy on that window: DL1ABC is new again outside it.
    let st = Station {
        worked: Some(Arc::new(day)),
        ..me()
    };
    assert_eq!(
        called(
            &award(&[Goal::NewCall]),
            &rows(&[("CQ DL1ABC JO62", Some(0.0)), ("CQ F1ABC JN18", Some(0.0))]),
            &st
        ),
        vec!["DL1ABC"]
    );
}

// Proves: TC-039-002
#[test]
fn tc_039_002_my_continent_from_config_call_and_locator() {
    let table = crate::dxcc::Table::default();
    let open = Config::default();
    let set = Config {
        continent: Some("OC".into()),
        ..Config::default()
    };
    assert_eq!(
        my_continent(&set, Some("HB9BLA"), Some("JN37"), &table).as_deref(),
        Some("OC"),
        "configured first"
    );
    assert_eq!(
        my_continent(&open, Some("HB9BLA"), Some("FN42"), &table).as_deref(),
        Some("EU"),
        "the callsign before the locator"
    );
    assert_eq!(
        my_continent(&open, Some("K1ABC"), None, &table).as_deref(),
        Some("NA")
    );
    // A call without an entity: the nearest cty.dat entity to the locator.
    for (grid, continent) in [
        ("JN37", "EU"),
        ("FN42", "NA"),
        ("PM95", "AS"),
        ("QF56", "OC"),
        ("GG87", "SA"),
    ] {
        assert_eq!(
            my_continent(&open, Some("K1ABC/MM"), Some(grid), &table).as_deref(),
            Some(continent),
            "{grid}"
        );
    }
    assert_eq!(my_continent(&open, None, None, &table), None);
}

pub(crate) fn strategy_json(name: &str) -> Value {
    json!({"name":name,"class":"award","goals":["new_call"],"needed":"not_worked","region":{"kind":"all"},
        "min_snr_db":null,"value":["snr"],"callers_first":true,"cq_when_no_target":false,
        "repetitions":2,"quiet_minutes":1,"treat_73_as_cq":true,"window":{"kind":"all"}})
}
fn config(active: Option<&str>) -> Value {
    json!({"continent":null,"active":active,"strategies":[strategy_json("Test calls")],
        "ignore_calls":[],"session_ignore_minutes":30})
}

// Proves: TC-039-001, TC-039-030
#[test]
fn tc_039_001_configuration_is_exact() {
    let mut full = config(Some("Test calls"));
    full["strategies"] = json!([{"name":"Test calls","class":"award",
        "goals":["dxcc","dxcc_band","dxcc_slot","waz","wpx","grid","new_call","new_call_band"],
        "needed":"not_confirmed","region":{"kind":"selected","continents":["AF","AS"]},
        "min_snr_db":-15,"value":["most_wanted","distance"],"callers_first":false,
        "cq_when_no_target":true,"repetitions":5,"quiet_minutes":15,"treat_73_as_cq":false,
        "window":{"kind":"from_to","from":"2024-02-29","to":"2026-11-06"}},
        {"name":"B","class":"award","goals":["grid"],"needed":"not_worked","region":{"kind":"dx"},
        "min_snr_db":null,"value":["new_dxcc","new_dxcc_band","new_dxcc_slot","new_grid",
        "new_grid_band","new_call","new_call_band","most_wanted","distance","snr"],
        "callers_first":true,"cq_when_no_target":false,"repetitions":20,"quiet_minutes":120,
        "treat_73_as_cq":true,"window":{"kind":"today"}},
        {"name":"C","class":"award","goals":["new_call"],"needed":"not_worked","region":{"kind":"all"},
        "min_snr_db":null,"value":[],"callers_first":true,"cq_when_no_target":false,
        "repetitions":1,"quiet_minutes":1,"treat_73_as_cq":true,"window":{"kind":"all"}}]);
    let ok = parse_config(&full).unwrap();
    assert_eq!(ok.json(), full, "round trip, the empty value list too");
    let parsed = ok.active_strategy().unwrap();
    assert_eq!(parsed.window, Window::FromTo(20_240_229, 20_261_106));
    assert_eq!(parsed.needed, Needed::NotConfirmed);
    assert_eq!(
        (
            parsed.value.clone(),
            parsed.callers_first,
            parsed.cq_when_no_target,
            parsed.repetitions,
            parsed.quiet_minutes
        ),
        (
            vec![Criterion::MostWanted, Criterion::Distance],
            false,
            true,
            5,
            15
        )
    );
    let set = |path: &[&str], v: Value| {
        let mut c = config(Some("Test calls"));
        let mut node = &mut c;
        for k in &path[..path.len() - 1] {
            node = match k.parse::<usize>() {
                Ok(i) => &mut node[i],
                Err(_) => &mut node[*k],
            };
        }
        node[*path.last().unwrap()] = v;
        parse_config(&c)
    };
    let s0 = |k: &str| format!("strategies[0].{k}");
    for (path, value, field) in [
        (&["continent"][..], json!("XX"), "continent".to_owned()),
        (&["active"][..], json!("missing"), "active".to_owned()),
        (
            &["strategies", "0", "name"][..],
            json!(" padded"),
            s0("name"),
        ),
        (&["strategies", "0", "name"][..], json!(""), s0("name")),
        // Contest is #63: refused on the wire until then.
        (
            &["strategies", "0", "class"][..],
            json!("contest"),
            s0("class"),
        ),
        (&["strategies", "0", "goals"][..], json!([]), s0("goals")),
        (
            &["strategies", "0", "goals"][..],
            json!("dxcc"),
            s0("goals"),
        ),
        (
            &["strategies", "0", "goals"][..],
            json!(["dxcc", "dxcc"]),
            s0("goals[1]"),
        ),
        (
            &["strategies", "0", "goals"][..],
            json!(["rarest"]),
            s0("goals[0]"),
        ),
        (
            &["strategies", "0", "needed"][..],
            json!("any"),
            s0("needed"),
        ),
        (
            &["strategies", "0", "region"][..],
            json!({"kind":"east"}),
            s0("region.kind"),
        ),
        (
            &["strategies", "0", "region"][..],
            json!("all"),
            s0("region.kind"),
        ),
        (
            &["strategies", "0", "region"][..],
            json!({"kind":"all","continents":[]}),
            s0("region"),
        ),
        (
            &["strategies", "0", "region"][..],
            json!({"kind":"dx","continents":["EU"]}),
            s0("region"),
        ),
        (
            &["strategies", "0", "region"][..],
            json!({"kind":"selected"}),
            s0("region"),
        ),
        (
            &["strategies", "0", "region"][..],
            json!({"kind":"selected","continents":[]}),
            s0("region.continents"),
        ),
        (
            &["strategies", "0", "region"][..],
            json!({"kind":"selected","continents":["EU","EU"]}),
            s0("region.continents[1]"),
        ),
        (
            &["strategies", "0", "region"][..],
            json!({"kind":"selected","continents":["XX"]}),
            s0("region.continents[0]"),
        ),
        (
            &["strategies", "0", "min_snr_db"][..],
            json!(50),
            s0("min_snr_db"),
        ),
        (
            &["strategies", "0", "min_snr_db"][..],
            json!(-51),
            s0("min_snr_db"),
        ),
        (
            &["strategies", "0", "min_snr_db"][..],
            json!(1.5),
            s0("min_snr_db"),
        ),
        (
            &["strategies", "0", "repetitions"][..],
            json!(0),
            s0("repetitions"),
        ),
        (
            &["strategies", "0", "repetitions"][..],
            json!(21),
            s0("repetitions"),
        ),
        (
            &["strategies", "0", "quiet_minutes"][..],
            json!(0),
            s0("quiet_minutes"),
        ),
        (
            &["strategies", "0", "quiet_minutes"][..],
            json!(121),
            s0("quiet_minutes"),
        ),
        (
            &["strategies", "0", "value"][..],
            json!(["snr", "rarest"]),
            s0("value[1]"),
        ),
        (
            &["strategies", "0", "value"][..],
            json!(["snr", "distance", "snr"]),
            s0("value[2]"),
        ),
        (
            &["strategies", "0", "value"][..],
            json!([
                "new_dxcc",
                "new_dxcc_band",
                "new_dxcc_slot",
                "new_grid",
                "new_grid_band",
                "new_call",
                "new_call_band",
                "most_wanted",
                "distance",
                "snr",
                "snr"
            ]),
            s0("value"),
        ),
        (&["strategies", "0", "value"][..], json!("snr"), s0("value")),
        (
            &["strategies", "0", "callers_first"][..],
            json!(1),
            s0("callers_first"),
        ),
        (
            &["strategies", "0", "cq_when_no_target"][..],
            json!("no"),
            s0("cq_when_no_target"),
        ),
        // calls_per_station is gone: refused by its own path (strategydef).
        (
            &["strategies", "0", "calls_per_station"][..],
            json!(3),
            s0("calls_per_station"),
        ),
        (
            &["strategies", "0", "treat_73_as_cq"][..],
            json!("yes"),
            s0("treat_73_as_cq"),
        ),
        (
            &["strategies", "0", "window"][..],
            json!({"kind":"week"}),
            s0("window.kind"),
        ),
        (
            &["strategies", "0", "window"][..],
            json!({"kind":"all","from":"2026-01-01"}),
            s0("window"),
        ),
        (
            &["strategies", "0", "window"][..],
            json!({"kind":"from_to","from":"2026-01-01"}),
            s0("window"),
        ),
        (
            &["strategies", "0", "window"][..],
            json!({"kind":"from_to","from":"20260101","to":"2026-01-01"}),
            s0("window.from"),
        ),
        (
            &["strategies", "0", "window"][..],
            json!({"kind":"from_to","from":"2026-02-30","to":"2026-03-01"}),
            s0("window.from"),
        ),
        (
            &["strategies", "0", "window"][..],
            json!({"kind":"from_to","from":"1929-12-31","to":"2026-03-01"}),
            s0("window.from"),
        ),
        (
            &["strategies", "0", "window"][..],
            json!({"kind":"from_to","from":"2026-03-01","to":"2100-01-01"}),
            s0("window.to"),
        ),
        (
            &["strategies", "0", "window"][..],
            json!({"kind":"from_to","from":"2026-03-02","to":"2026-03-01"}),
            s0("window.to"),
        ),
    ] {
        assert_eq!(set(path, value.clone()), Err(field), "{path:?}={value}");
    }
    // Removed names are refused, not ignored.
    for extra in [
        "rules",
        "sort",
        "auto_role",
        "switch_after",
        "skip_after",
        "apply_to_callers",
    ] {
        let mut c = config(None);
        c["strategies"][0][extra] = json!(1);
        assert_eq!(
            parse_config(&c),
            Err(s0("").trim_end_matches('.').to_owned()),
            "{extra}"
        );
    }
    let mut c = config(None);
    c["highlight"] = json!(true);
    assert_eq!(
        parse_config(&c),
        Err("configuration".into()),
        "highlight is gone"
    );
    let mut c = config(None);
    c["strategies"] = json!([strategy_json("A"), strategy_json("a")]);
    assert_eq!(
        parse_config(&c),
        Err("strategies[1].name".into()),
        "names unique ignoring case"
    );
    let mut c = config(None);
    c["strategies"] = json!(
        (0..17)
            .map(|i| strategy_json(&format!("S{i}")))
            .collect::<Vec<_>>()
    );
    assert_eq!(parse_config(&c), Err("strategies".into()));
}

// Proves: TC-039-030 (WstxStrategy::StrategyConfiguration upgrade and restart).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_030_an_old_file_upgrades_and_active_never_survives_a_restart() {
    let f = station(true).await;
    let write = |schema: u64, revision: u64, configuration: Value| {
        std::fs::write(
            f.dir.join(FILE_NAME),
            serde_json::to_vec(&json!({"schema_version":schema,"profile_id":f.id,
                "revision":revision,"configuration":configuration}))
            .unwrap(),
        )
        .unwrap();
    };
    let read = || {
        let owner = Owner::default();
        let snapshot = owner.snapshot(&f.state);
        (
            snapshot["revision"].clone(),
            snapshot["configuration"].clone(),
            snapshot["configuration_error"].clone(),
        )
    };
    // An old file with rules, sort, highlight and an active strategy.
    let rule = json!({"name":"NA first","rules":[{"conditions":[{"kind":"message","negate":false,"value":"cq"}]}],
        "sort":"strongest","treat_73_as_cq":true,"apply_to_callers":false,"skip_after":2,"auto_role":"cq","switch_after":2});
    write(
        1,
        7,
        json!({"continent":"AS","active":"NA first","highlight":true,"strategies":[rule],
            "ignore_calls":["K1ABC"],"session_ignore_minutes":45}),
    );
    assert_eq!(
        read(),
        (
            json!(7),
            json!({"continent":"AS","active":null,"strategies":[],"ignore_calls":["K1ABC"],
                "session_ignore_minutes":45}),
            Value::Null
        ),
        "strategies dropped, active None, continent and ignore lists kept"
    );
    // Written before #42: neither ignore key.
    write(
        1,
        3,
        json!({"continent":null,"active":null,"highlight":false,"strategies":[rule]}),
    );
    assert_eq!(
        read().1,
        json!({"continent":null,"active":null,"strategies":[],"ignore_calls":[],
            "session_ignore_minutes":30})
    );
    // Malformed: exactly one of them, a bad continent, an unknown schema.
    write(
        1,
        3,
        json!({"continent":null,"active":null,"highlight":false,"strategies":[],"ignore_calls":[]}),
    );
    assert_eq!(read().2, json!("invalid_configuration"));
    write(
        1,
        3,
        json!({"continent":"XX","active":null,"highlight":false,"strategies":[]}),
    );
    assert_eq!(read().2, json!("invalid_configuration"));
    write(4, 3, config(None));
    assert_eq!(read().2, json!("invalid_configuration"));
    // A current file, even with an active name, reads active None after a restart.
    write(3, 9, config(Some("Test calls")));
    assert_eq!(read().1, config(None));
    assert_eq!(read().0, json!(9));
    std::fs::remove_file(f.dir.join(FILE_NAME)).unwrap();
}

async fn put(f: &Mcp, revision: Value, configuration: Value) -> crate::mcp_tests::Reply {
    f.browser(
        "PUT",
        "/strategy",
        Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,
        "expected_revision":revision,"configuration":configuration})),
    )
    .await
}

// Proves: TC-039-003
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_003_store_routes_and_evaluate() {
    let f = station(true).await;
    let g = f.browser("GET", "/strategy", None).await;
    assert_eq!(g.status, StatusCode::OK);
    assert_eq!(
        (
            g.json["revision"].clone(),
            g.json["configuration"].clone(),
            g.json["my_continent"].clone()
        ),
        (
            json!(0),
            json!({"continent":null,"active":null,"strategies":[],
                "ignore_calls":[],"session_ignore_minutes":30}),
            json!("EU")
        ),
        "default: no strategy; continent derived from JN47AA"
    );
    let p = put(&f, json!(0), config(None)).await;
    assert_eq!(p.status, StatusCode::OK, "{}", p.json);
    assert_eq!(p.json["revision"], 1);
    let saved: Value =
        serde_json::from_slice(&std::fs::read(f.dir.join(FILE_NAME)).unwrap()).unwrap();
    assert_eq!(
        saved,
        json!({"schema_version":3,"profile_id":f.id,"revision":1,"configuration":config(None)})
    );
    // A fresh owner (next boot) reads the same file.
    let reopened = Owner::default();
    assert_eq!(reopened.snapshot(&f.state)["configuration"], config(None));
    let mut other = config(None);
    other["continent"] = json!("AS");
    for (body, status, code, field) in [
        (
            json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"expected_revision":0,"configuration":other}),
            409,
            "stale_revision",
            json!("expected_revision"),
        ),
        (
            json!({"v":1,"profile_id":profile::new_uuid().unwrap(),"boot_id":f.boot,"expected_revision":1,"configuration":other}),
            403,
            "wrong_profile",
            json!("profile_id"),
        ),
        (
            json!({"v":1,"profile_id":f.id,"boot_id":profile::new_uuid().unwrap(),"expected_revision":1,"configuration":other}),
            409,
            "state_conflict",
            json!("boot_id"),
        ),
        (
            json!({"v":2,"profile_id":f.id,"boot_id":f.boot,"expected_revision":1,"configuration":other}),
            400,
            "unsupported_version",
            json!("v"),
        ),
        (
            json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"expected_revision":1,"configuration":other,"x":1}),
            400,
            "invalid_request",
            Value::Null,
        ),
    ] {
        let r = f.browser("PUT", "/strategy", Some(body)).await;
        assert_eq!(
            (
                r.status.as_u16(),
                r.json["error"]["code"].clone(),
                r.json["error"]["field"].clone()
            ),
            (status, json!(code), field)
        );
    }
    // Contest is #63: refused on the wire.
    let mut contest = config(None);
    contest["strategies"][0]["class"] = json!("contest");
    let r = put(&f, json!(1), contest).await;
    assert_eq!(
        (r.status.as_u16(), r.json["error"]["field"].clone()),
        (400, json!("strategies[0].class"))
    );
    let foreign = f
        .http(
            "PUT",
            "/strategy",
            &[
                ("origin", "https://evil.example".into()),
                ("cookie", f.cookie()),
                ("content-type", "application/json".into()),
            ],
            Some(b"{}".to_vec()),
        )
        .await;
    assert_eq!(foreign.status, StatusCode::FORBIDDEN);
    let unauthorized = f.http("GET", "/strategy", &[], None).await;
    assert_eq!(unauthorized.status, StatusCode::UNAUTHORIZED);
    let r = put(&f, json!(1), other.clone()).await;
    assert_eq!(
        (r.json["revision"].clone(), r.json["my_continent"].clone()),
        (json!(2), json!("AS")),
        "configured continent wins"
    );
    other["continent"] = Value::Null;
    put(&f, json!(2), other).await;

    // Evaluate retained live rows with the saved strategy and with a draft.
    let (source, job, generation) = f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    publish(
        &f,
        e,
        &[
            ("CQ K1ABC FN42", 1500.0, Some(-12.0)),
            ("CQ NA W1AW FN31", 900.0, Some(-3.0)),
            ("HB9BLA G4ABC IO91", 700.0, Some(1.0)),
            ("CQ DL1XYZ JO62", 1200.0, Some(-1.0)),
        ],
    );
    let body = |strategy: Value, explain: bool| {
        json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"source_id":source,"job_id":job,
        "generation":generation,"first_sequence":0,"next_sequence":4,"strategy":strategy,"explain":explain})
    };
    let none = f
        .browser("POST", "/strategy/evaluate", Some(body(Value::Null, false)))
        .await;
    assert_eq!(
        (
            none.status.as_u16(),
            none.json["error"]["code"].clone(),
            none.json["error"]["field"].clone()
        ),
        (409, json!("not_configured"), json!("strategy")),
        "no active strategy"
    );
    let v = f
        .browser(
            "POST",
            "/strategy/evaluate",
            Some(body(strategy_json("Draft"), true)),
        )
        .await;
    assert_eq!(v.status, StatusCode::OK, "{}", v.json);
    assert_eq!(v.json["strategy"], "Draft");
    assert_eq!(
        v.json["verdicts"],
        json!([
            {"sequence":2,"rank":0,"grey":false,"why":"calls my call"},
            {"sequence":3,"rank":1,"grey":false,"why":"needed: new_call"},
            {"sequence":0,"rank":2,"grey":false,"why":"needed: new_call"},
            {"sequence":1,"rank":null,"grey":true,"why":"CQ NA — not for EU"},
        ]),
        "explain lists every decoded row in display order"
    );
    // The same rows with the selected strategy, without the reasons.
    let revision = f.browser("GET", "/strategy", None).await.json["revision"].clone();
    let selected = put(&f, revision, config(Some("Test calls"))).await;
    assert_eq!(selected.status, StatusCode::OK, "{}", selected.json);
    let v = f
        .browser("POST", "/strategy/evaluate", Some(body(Value::Null, false)))
        .await;
    assert_eq!(
        v.json["verdicts"],
        json!([{"sequence":2,"rank":0,"grey":false},{"sequence":3,"rank":1,"grey":false},
            {"sequence":0,"rank":2,"grey":false},{"sequence":1,"rank":null,"grey":true}])
    );
    let mut stale = body(Value::Null, false);
    stale["job_id"] = json!(profile::new_uuid().unwrap());
    let r = f.browser("POST", "/strategy/evaluate", Some(stale)).await;
    assert_eq!(
        (r.status.as_u16(), r.json["error"]["code"].clone()),
        (409, json!("stale_request"))
    );
    let mut wide = body(Value::Null, false);
    wide["next_sequence"] = json!(2049);
    let r = f.browser("POST", "/strategy/evaluate", Some(wide)).await;
    assert_eq!(
        (r.status.as_u16(), r.json["error"]["field"].clone()),
        (400, json!("next_sequence"))
    );
    assert_eq!(f.keys(), 0, "evaluation never keys");
}

// Proves: TC-039-032 (the expected table is written here from the contract).
#[test]
fn tc_039_032_the_builtin_table_and_what_a_configuration_may_say() {
    // BuiltinStrategies: needed not_worked, min SNR none, callers first, 4 repetitions, 10
    // minutes quiet, Treat 73 as CQ, window all, region all, value [most_wanted] and no CQ
    // unless stated.
    let common = |name: &str, goal: &str| {
        json!({"name":name,"class":"award","goals":[goal],"needed":"not_worked",
            "region":{"kind":"all"},"min_snr_db":null,"value":["most_wanted"],
            "callers_first":true,"cq_when_no_target":false,"repetitions":4,"quiet_minutes":10,
            "treat_73_as_cq":true,"window":{"kind":"all"}})
    };
    let with_fields = |mut v: Value, fields: Value| {
        for (k, x) in fields.as_object().unwrap() {
            v[k] = x.clone();
        }
        v
    };
    assert_eq!(
        builtins().iter().map(Strategy::json).collect::<Vec<_>>(),
        vec![
            common("New DXCC", "dxcc"),
            common("New DXCC on band", "dxcc_band"),
            common("DXCC slots", "dxcc_slot"),
            common("New calls", "new_call"),
            with_fields(
                common("DX hunting", "new_call"),
                json!({"region":{"kind":"dx"}})
            ),
            with_fields(
                common("Strongest new on band", "new_call_band"),
                json!({"value":["snr"]})
            ),
            with_fields(
                common("Farthest new on band", "new_call_band"),
                json!({"value":["distance"]})
            ),
            with_fields(
                common("Casual 20 m", "new_call_band"),
                json!({"value":["snr"],"window":{"kind":"today"},"cq_when_no_target":true})
            ),
        ]
    );
    let with = |active: Value, strategies: Value| {
        parse_config(
            &json!({"continent":null,"active":active,"strategies":strategies,
            "ignore_calls":[],"session_ignore_minutes":30}),
        )
    };
    let ok = with(json!("DX hunting"), json!([])).unwrap();
    assert_eq!(ok.active_strategy().unwrap().region, Region::Dx);
    assert_eq!(
        with(json!("dx hunting"), json!([])),
        Err("active".to_owned()),
        "exactly as listed"
    );
    for name in ["New DXCC", "new dxcc"] {
        assert_eq!(
            with(Value::Null, json!([strategy_json(name)])),
            Err("strategies[0].name".to_owned()),
            "{name}: a built-in cannot be edited"
        );
    }
    let mut marked = strategy_json("Mine");
    marked["builtin"] = json!(true);
    assert_eq!(
        with(Value::Null, json!([marked])),
        Err("strategies[0]".to_owned())
    );
    assert!(with(Value::Null, json!([strategy_json("New DXCC copy")])).is_ok());
}

// Proves: TC-039-032
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_032_a_builtin_is_selected_like_any_strategy_and_never_stored() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let g = f.browser("GET", "/strategy", None).await.json;
    assert_eq!(g["configuration"]["strategies"], json!([]));
    let listed = g["builtin_strategies"].as_array().unwrap();
    assert_eq!(
        listed
            .iter()
            .map(|b| (b["name"].as_str().unwrap(), b["builtin"].clone()))
            .collect::<Vec<_>>(),
        [
            "New DXCC",
            "New DXCC on band",
            "DXCC slots",
            "New calls",
            "DX hunting",
            "Strongest new on band",
            "Farthest new on band",
            "Casual 20 m"
        ]
        .into_iter()
        .map(|n| (n, json!(true)))
        .collect::<Vec<_>>()
    );
    let chosen = json!({"continent":null,"active":"DX hunting","strategies":[],
        "ignore_calls":[],"session_ignore_minutes":30});
    select(&f, chosen).await;
    publish(
        &f,
        e,
        &[
            ("CQ DL1XYZ JO62", 1200.0, Some(9.0)),
            ("CQ K1ABC FN42", 1500.0, Some(-15.0)),
        ],
    );
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed")),
        "region DX: my own continent is no candidate, although stronger"
    );
    let saved: Value =
        serde_json::from_slice(&std::fs::read(f.dir.join(FILE_NAME)).unwrap()).unwrap();
    assert_eq!(
        saved["configuration"]["strategies"],
        json!([]),
        "never stored"
    );
    assert_eq!(saved["configuration"]["active"], Value::Null);
    assert_eq!(
        Owner::default().snapshot(&f.state)["configuration"]["active"],
        Value::Null,
        "a restart reads None"
    );
    // A PUT cannot edit one.
    let revision = f.browser("GET", "/strategy", None).await.json["revision"].clone();
    let r = put(
        &f,
        revision,
        json!({"continent":null,"active":"DX hunting","strategies":[strategy_json("DX hunting")],
            "ignore_calls":[],"session_ignore_minutes":30}),
    )
    .await;
    assert_eq!(
        (
            r.status.as_u16(),
            r.json["error"]["code"].clone(),
            r.json["error"]["field"].clone()
        ),
        (400, json!("invalid_request"), json!("strategies[0].name"))
    );
    // HALT turns Auto off and keeps the selection, as for any strategy (strategydef).
    halt(&f).await;
    assert_eq!(active_of(&f).await, json!("DX hunting"));
    assert_eq!(
        f.browser("GET", "/strategy", None).await.json["auto"],
        false
    );
    // A file from before the presets: the strategy with a built-in's name is dropped.
    std::fs::write(
        f.dir.join(FILE_NAME),
        serde_json::to_vec(&json!({"schema_version":3,"profile_id":f.id,"revision":5,
            "configuration":{"continent":null,"active":null,
                "strategies":[strategy_json("New calls"),strategy_json("Kept")],
                "ignore_calls":[],"session_ignore_minutes":30}}))
        .unwrap(),
    )
    .unwrap();
    let read = Owner::default().snapshot(&f.state);
    assert_eq!(read["configuration_error"], Value::Null);
    assert_eq!(
        read["configuration"]["strategies"],
        json!([strategy_json("Kept")])
    );
    std::fs::remove_file(f.dir.join(FILE_NAME)).unwrap();
}

// ------------------------------------------------------------------ strategy runs
/// POST /strategy/auto from the browser (WstxStrategy::AutoToggle).
pub(crate) async fn auto(f: &Mcp, on: bool, confirmed: Option<bool>) -> crate::mcp_tests::Reply {
    let mut body = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"auto":on});
    if let Some(c) = confirmed {
        body["automation_confirmed"] = json!(c);
    }
    f.browser("POST", "/strategy/auto", Some(body)).await
}
/// The browser's selection with Auto on (strategydef: a selection alone only marks): a save
/// with the strategy or contest selected, then Auto on (confirmed for a contest).
async fn select(f: &Mcp, configuration: Value) {
    let selected = !configuration["active"].is_null() || !configuration["contest"].is_null();
    let contest = !configuration["contest"].is_null();
    save(f, configuration).await;
    if selected {
        let r = auto(f, true, contest.then_some(true)).await;
        assert_eq!(r.status, StatusCode::OK, "{}", r.json);
    }
}
async fn save(f: &Mcp, configuration: Value) {
    let revision = f.browser("GET", "/strategy", None).await.json["revision"].clone();
    let r = put(f, revision, configuration).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);
}
/// A save that is not the browser's route: no run starts (the store only).
fn store_only(f: &Mcp, configuration: Value) {
    let station = f.state.recording.contact.get().unwrap();
    let revision = station.strategy.snapshot(&f.state)["revision"].clone();
    station
        .strategy
        .put(
            &f.state,
            json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"expected_revision":revision,
                "configuration":configuration}),
        )
        .unwrap();
    f.state.logbook.worked_set().unwrap();
}
async fn contact(f: &Mcp) -> (Value, Value, Value) {
    let c = f.read("contact").await;
    (
        c["contact"]["dx_call"].clone(),
        c["contact"]["state"].clone(),
        c["transmit"]["arm_state"].clone(),
    )
}
async fn active_of(f: &Mcp) -> Value {
    f.browser("GET", "/strategy", None).await.json["configuration"]["active"].clone()
}
async fn halt(f: &Mcp) {
    let h = f.browser("POST", "/transmit/halt", Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap()}))).await;
    assert_eq!(h.status, StatusCode::ACCEPTED);
    f.tick();
}

// Proves: TC-039-004
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_selecting_starts_a_run_that_calls_by_value_and_never_calls_cq() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    // Selecting starts it: no other request; the run waits and no CQ is armed.
    select(&f, config(Some("Test calls"))).await;
    f.tick();
    f.tick();
    let run = f.read("automation").await;
    assert_eq!(
        (
            run["run"]["state"].clone(),
            run["run"]["reason"].clone(),
            run["configuration"]["strategy"].clone(),
            run["configuration"]["max_contacts"].clone(),
            run["configuration"]["max_run_minutes"].clone(),
        ),
        (
            json!("waiting"),
            Value::Null,
            json!(true),
            Value::Null,
            Value::Null
        )
    );
    assert_eq!(
        contact(&f).await,
        (Value::Null, Value::Null, json!("disarmed")),
        "never a CQ"
    );
    // CQ NA (not for EU), a country and a number directive are never answered; of the rest
    // both are new DXCC, so the strongest.
    publish(
        &f,
        e,
        &[
            ("CQ NA W1AW FN31", 900.0, Some(5.0)),
            ("CQ JA JA1XYZ PM95", 600.0, Some(9.0)),
            ("CQ 290 N1MM FN31", 700.0, Some(8.0)),
            ("CQ DL1XYZ JO62", 1200.0, Some(0.0)),
            ("CQ K1ABC FN42", 1400.0, Some(-15.0)),
        ],
    );
    assert_eq!(
        contact(&f).await,
        (json!("DL1XYZ"), json!("replying"), json!("armed"))
    );
    // Proves: CL-039-08; TC-039-009: after the strategy's pick Tx stays (clear of the station);
    // with Hold Tx on Rx follows the row (#39 holdtx D16, WstxStrategy::FreeTxSlot).
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["settings"]["rx_hz"].clone(),
            c["settings"]["tx_hz"].clone()
        ),
        (json!(1200), json!(1500))
    );
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (
            run["state"].clone(),
            run["last_decision"]["candidates"].clone(),
            run["last_decision"]["selected_call"].clone()
        ),
        (json!("contact_active"), json!(2), json!("DL1XYZ"))
    );
    // #39 holdtx: the run's Rx = Tx steps below run with Hold Tx explicitly off (TC-039-004; with
    // it on: TC-039-049).
    hold_off(&f).await;
    // Repetitions 2: two partner periods without an answer leave DL1XYZ, quiet for a minute
    // (quiet_minutes 1); no stop.
    publish(&f, e + 30_000, &[]);
    publish(&f, e + 60_000, &[]);
    assert_eq!(contact(&f).await.2, json!("disarmed"));
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (
            run["state"].clone(),
            run["left"].clone(),
            run["quiet"][0]["call"].clone(),
            run["reason"].clone()
        ),
        (
            json!("waiting"),
            json!({"call":"DL1XYZ","reason":"repetitions"}),
            json!("DL1XYZ"),
            Value::Null
        )
    );
    let tx = f.read("contact").await["settings"]["tx_hz"].clone();
    publish(
        &f,
        e + 90_000,
        &[
            ("CQ DL1XYZ JO62", 1200.0, Some(9.0)),
            ("W1AW K1ABC RR73", 1700.0, Some(-9.0)),
        ],
    );
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["contact"]["dx_call"].clone(),
            c["contact"]["messages"][0].clone(),
            c["transmit"]["arm_state"].clone()
        ),
        (json!("K1ABC"), json!("K1ABC HB9BLA JN47"), json!("armed")),
        "DL1XYZ is quiet"
    );
    assert_eq!(
        (
            c["settings"]["tx_hz"].clone(),
            c["settings"]["rx_hz"].clone()
        ),
        (tx.clone(), tx),
        "after a 73 Tx stays on its slot, Rx = Tx"
    );
    // K1ABC left in turn; its CQ is not called during its quiet minute, and is after it.
    publish(&f, e + 120_000, &[]);
    publish(&f, e + 150_000, &[]);
    publish(&f, e + 180_000, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    assert_eq!(contact(&f).await.2, json!("disarmed"), "quiet");
    at_skew(&f, 60);
    publish(&f, e + 210_000, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    assert_eq!(contact(&f).await.0, json!("K1ABC"), "after its quiet time");
    // None stops it: the armed contact is disarmed, the run stopped.
    save(&f, config(None)).await;
    assert_eq!(contact(&f).await.2, json!("disarmed"));
    assert_eq!(run_state(&f).await, ("stopped".into(), json!("stopped")));
    assert_eq!(f.keys(), 0);
}

// Proves: TC-039-004
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_a_run_goes_on_after_each_qso_without_a_limit() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("Test calls"))).await;
    let _client = f.state.recording.clients.session();
    // No limit on the contacts, and the run goes on before its 8 hours.
    *f.state
        .recording
        .contact
        .get()
        .unwrap()
        .automation
        .skew
        .lock()
        .unwrap() = Duration::from_secs(479 * 60);
    f.tick();
    assert_eq!(run_state(&f).await, ("waiting".into(), Value::Null));
    *f.state
        .recording
        .contact
        .get()
        .unwrap()
        .automation
        .skew
        .lock()
        .unwrap() = Duration::ZERO;
    // A caller is answered with a report; after its R-report and 73 the contact completes.
    for (i, call) in ["K1ABC", "K2ABC", "K3ABC"].into_iter().enumerate() {
        let at = e + 180_000 * i as i64;
        let (first, second, third) = (
            format!("HB9BLA {call} FN42"),
            format!("HB9BLA {call} R-05"),
            format!("HB9BLA {call} 73"),
        );
        publish(&f, at, &[(first.as_str(), 1500.0, Some(-10.0))]);
        assert_eq!(contact(&f).await.0, json!(call));
        publish(&f, at + 30_000, &[(second.as_str(), 1500.0, Some(-10.0))]);
        publish(&f, at + 60_000, &[(third.as_str(), 1500.0, Some(-10.0))]);
        assert_eq!(contact(&f).await.1, json!("completed"), "{call}");
        f.tick();
        let run = f.read("automation").await["run"].clone();
        assert_eq!(
            (
                run["state"].clone(),
                run["completed_contacts"].clone(),
                run["reason"].clone()
            ),
            (json!("waiting"), json!(i + 1), Value::Null),
            "it waits for the next opportunity and never calls CQ"
        );
        assert_eq!(contact(&f).await.2, json!("disarmed"));
    }
    // A station completed in this run is not called again.
    publish(&f, e + 600_000, &[("CQ K1ABC FN42", 1500.0, Some(0.0))]);
    assert_eq!(contact(&f).await.1, json!("completed"));
}

// Proves: TC-039-004
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_halt_turns_auto_off_keeps_the_selection_and_esc_and_a_cancel_do_not() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("Test calls"))).await;
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    assert_eq!(contact(&f).await.2, json!("armed"));
    // An operator's cancel keeps the strategy and the run.
    browser_ok(&f, "cancel", json!({})).await;
    f.tick();
    f.tick();
    assert_eq!(active_of(&f).await, json!("Test calls"));
    assert_eq!(run_state(&f).await.0, "waiting");
    // Esc sends abort: the strategy stays selected, the station is given up, the run goes on.
    publish(&f, e + 15_000, &[("CQ G4ABC IO91", 1100.0, Some(-1.0))]);
    assert_eq!(contact(&f).await.0, json!("G4ABC"));
    assert_eq!(contact(&f).await.2, json!("armed"));
    let halts = f
        .state
        .recording
        .transmit
        .get()
        .unwrap()
        .service
        .halt_requests();
    browser_ok(&f, "abort", json!({})).await;
    f.tick();
    f.tick();
    assert_eq!(active_of(&f).await, json!("Test calls"), "Esc is no HALT");
    assert_eq!(
        f.state
            .recording
            .transmit
            .get()
            .unwrap()
            .service
            .halt_requests(),
        halts
    );
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (
            run["state"].clone(),
            run["reason"].clone(),
            run["given_up"].clone()
        ),
        (json!("waiting"), Value::Null, json!(["K1ABC", "G4ABC"]))
    );
    assert_eq!(contact(&f).await.2, json!("disarmed"));
    publish(&f, e + 22_500, &[("CQ G4ABC IO91", 1100.0, Some(-1.0))]);
    assert_eq!(contact(&f).await.0, Value::Null, "not selected again");
    // HALT: run stopped halted, Auto off, the selection kept (strategydef Q5), a new revision
    // the browser is told of.
    let before = f.browser("GET", "/strategy", None).await.json["revision"].clone();
    halt(&f).await;
    assert_eq!(run_state(&f).await, ("stopped".into(), json!("halted")));
    let s = f.browser("GET", "/strategy", None).await.json;
    assert_eq!(
        (s["configuration"]["active"].clone(), s["auto"].clone()),
        (json!("Test calls"), json!(false))
    );
    assert_eq!(s["revision"], json!(before.as_u64().unwrap() + 1));
    let station_owner = f.state.recording.contact.get().unwrap();
    assert_eq!(
        json!(station_owner.strategy.revision()),
        s["revision"],
        "strategy.state"
    );
    // A HALT with Auto already off changes nothing: the selection stays, no revision.
    halt(&f).await;
    let again = f.browser("GET", "/strategy", None).await.json;
    assert_eq!(
        (
            again["configuration"]["active"].clone(),
            again["revision"].clone()
        ),
        (json!("Test calls"), s["revision"].clone())
    );
    // Auto on starts it again and it answers (a HALT before it does not count).
    let r = auto(&f, true, None).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);
    f.tick();
    assert_eq!(
        (
            active_of(&f).await,
            f.browser("GET", "/strategy", None).await.json["auto"].clone()
        ),
        (json!("Test calls"), json!(true)),
        "the HALT before it does not count"
    );
    assert_eq!(run_state(&f).await, ("waiting".into(), Value::Null));
    publish(&f, e + 30_000, &[("CQ DL1XYZ JO62", 1200.0, Some(-1.0))]);
    assert_eq!(contact(&f).await.0, json!("DL1XYZ"));
    // G4ABC's own period had begun when Esc came: its one transmission, key on then released.
    assert_eq!(
        f.bench
            .keys
            .lock()
            .unwrap()
            .iter()
            .map(|(_, on)| *on)
            .collect::<Vec<_>>(),
        vec![true, false]
    );
}

// Proves: TC-039-004
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_a_strategy_stays_selected_across_receive_and_without_a_grant() {
    let f = station(true).await;
    let e = at_even(&f);
    // No receive: the strategy is selected and waits with its reason; nothing armed.
    select(&f, config(Some("Test calls"))).await;
    f.tick();
    assert_eq!(run_state(&f).await, ("waiting".into(), json!("no_receive")));
    assert_eq!(active_of(&f).await, json!("Test calls"));
    // Receive starts: it identifies and answers.
    f.state.recording.fixture_live_job("ft8");
    f.tick();
    assert_eq!(run_state(&f).await, ("waiting".into(), Value::Null));
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
    // The live identity changes in a contact: disarmed and cancelled, the run waits.
    f.state.recording.fixture_live_job("ft8");
    f.tick();
    assert_eq!(run_state(&f).await, ("waiting".into(), Value::Null));
    let c = contact(&f).await;
    assert_eq!((c.1, c.2), (json!("cancelled"), json!("disarmed")));
    assert_eq!(active_of(&f).await, json!("Test calls"));
    publish(&f, e + 30_000, &[("CQ DL1XYZ JO62", 1200.0, Some(-1.0))]);
    assert_eq!(contact(&f).await.0, json!("DL1XYZ"), "on the new identity");
    // Auto Seq off: it finishes nothing new; the reason is shown while it waits.
    save(&f, config(None)).await;
    browser_ok(&f, "cancel", json!({})).await;
    browser_ok(&f, "set_auto_seq", json!({"enabled":false})).await;
    select(&f, config(Some("Test calls"))).await;
    f.tick();
    assert_eq!(run_state(&f).await, ("waiting".into(), json!("auto_seq")));
    publish(&f, e + 60_000, &[("CQ G4ABC IO91", 1200.0, Some(-1.0))]);
    assert_eq!(contact(&f).await.1, json!("cancelled"), "selects nothing");
    browser_ok(&f, "set_auto_seq", json!({"enabled":true})).await;
    f.tick();
    assert_eq!(run_state(&f).await, ("waiting".into(), Value::Null));
    // A pounce or MCP run ends by the selection (one run at a time; the operator's choice).
    save(&f, config(None)).await;
    assert_eq!(
        configure_run(&f, pounce_json(json!("K1ABC"), 2))
            .await
            .status,
        StatusCode::ACCEPTED
    );
    f.state.recording.fixture_band("40m");
    assert_eq!(start_run(&f).await.status, StatusCode::ACCEPTED);
    assert!(f.read("automation").await["run"]["pounce"].is_object());
    select(&f, config(Some("Test calls"))).await;
    let a = f.read("automation").await;
    assert_eq!(
        (
            a["run"]["pounce"].clone(),
            a["configuration"]["strategy"].clone()
        ),
        (Value::Null, json!(true))
    );
    // Without a grant (the plain route) no run starts: selected, the reason named.
    save(&f, config(None)).await;
    let station_owner = f.state.recording.contact.get().unwrap();
    store_only(&f, config(Some("Test calls")));
    assert!(
        !station_owner
            .automation
            .selected(station_owner, &f.state, None, true)
    );
    let a = f.read("automation").await;
    assert_eq!(
        (
            a["strategy_refusal"].clone(),
            a["run"]["state"].clone(),
            active_of(&f).await
        ),
        (
            json!("transmit_unavailable"),
            json!("stopped"),
            json!("Test calls")
        )
    );
    // An MCP client cannot select one: strategy true is refused, PUT has no tool (401 guard).
    let mut cfg = crate::automation_tests::config_json();
    cfg["strategy"] = json!(true);
    let body = json!({"command":{"v":1,"profile_id":f.id,"boot_id":f.boot,
        "command_id":profile::new_uuid().unwrap(),"action":"configure",
        "expected_policy_revision":a["policy_revision"],"configuration":cfg}});
    let v = f.tool("wstx_automation_command", body).await;
    assert_eq!(
        (
            v["result"]["error"]["code"].clone(),
            v["result"]["error"]["field"].clone()
        ),
        (json!("operator_required"), json!("strategy")),
        "{v}"
    );
    assert_eq!(f.keys(), 0);
}

// Proves: TC-039-004
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_callers_come_first_and_a_cancelled_station_never_again() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    // A goal nobody below meets, a region that excludes the caller, a high min SNR.
    let mut c = config(Some("Test calls"));
    c["strategies"][0]["region"] = json!({"kind":"selected","continents":["OC"]});
    c["strategies"][0]["min_snr_db"] = json!(10);
    select(&f, c).await;
    publish(
        &f,
        e,
        &[
            ("CQ VK2ABC QF56", 1000.0, Some(15.0)),
            ("HB9BLA DL1XYZ JO62", 1200.0, Some(-20.0)),
        ],
    );
    assert_eq!(
        contact(&f).await,
        (json!("DL1XYZ"), json!("report"), json!("armed")),
        "the caller first"
    );
    // The operator cancels it: never again in this run, not as a caller either.
    browser_ok(&f, "cancel", json!({})).await;
    f.tick();
    f.tick();
    publish(
        &f,
        e + 30_000,
        &[("HB9BLA DL1XYZ JO62", 1200.0, Some(-20.0))],
    );
    assert_eq!(contact(&f).await.1, json!("cancelled"));
    let run = f.read("automation").await["run"].clone();
    assert_eq!(run["given_up"], json!(["DL1XYZ"]));
    publish(&f, e + 60_000, &[("CQ VK2ABC QF56", 1000.0, Some(15.0))]);
    assert_eq!(contact(&f).await.0, json!("VK2ABC"));
}

// Proves: TC-039-004. Review 6683200740 finding 1: a stopped strategy run is restarted only
// by a selection; an MCP stop then start is refused.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_an_mcp_client_cannot_restart_a_stopped_strategy() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("Test calls"))).await;
    f.tick();
    let auto = |action: &str, extra: Value| {
        let mut b = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),"action":action});
        b.as_object_mut()
            .unwrap()
            .extend(extra.as_object().unwrap().clone());
        json!({ "command": b })
    };
    let a = f.read("automation").await;
    let stop = f
        .tool(
            "wstx_automation_command",
            auto("stop", json!({"run_id":a["run"]["id"]})),
        )
        .await;
    assert_eq!(stop["status"], 202, "{stop}");
    let a = f.read("automation").await;
    let safety = f.read("contact").await["transmit"]["safety_revision"].clone();
    let start = auto(
        "start",
        json!({"expected_policy_revision":a["policy_revision"],"expected_run_revision":a["run_revision"],
            "mode":"ft8","safety_revision":safety}),
    );
    let r = f.tool("wstx_automation_command", start.clone()).await;
    assert_eq!(
        (
            r["result"]["error"]["code"].clone(),
            r["result"]["error"]["field"].clone()
        ),
        (json!("operator_required"), json!("strategy")),
        "{r}"
    );
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    assert_eq!(contact(&f).await.2, json!("disarmed"));
    assert_eq!(run_state(&f).await.0, "stopped");
    // The browser's start route is no path either: only PUT /strategy selects.
    let body = start["command"].clone();
    let mut browser = body.clone();
    browser["command_id"] = json!(profile::new_uuid().unwrap());
    let r = f
        .browser("POST", "/automation/command", Some(browser))
        .await;
    assert_eq!(r.json["error"]["code"], "operator_required", "{}", r.json);
    // An MCP client's own policy replaces the stored one and starts as ever.
    let a = f.read("automation").await;
    let cfg = crate::automation_tests::config_json();
    let c = f
        .tool(
            "wstx_automation_command",
            auto(
                "configure",
                json!({"expected_policy_revision":a["policy_revision"],"configuration":cfg}),
            ),
        )
        .await;
    assert_eq!(c["status"], 202, "{c}");
    let a = f.read("automation").await;
    let r = f
        .tool(
            "wstx_automation_command",
            auto(
                "start",
                json!({"expected_policy_revision":a["policy_revision"],"expected_run_revision":a["run_revision"],
                    "mode":"ft8","safety_revision":safety}),
            ),
        )
        .await;
    assert_eq!(r["status"], 202, "{r}");
    assert_eq!(
        f.read("automation").await["configuration"]["strategy"],
        json!(false)
    );
}

// Proves: TC-039-004, TC-039-043. A station left after its repetitions is quiet (QuietTime): when it
// calls my call it is not answered, the stronger CQ is called instead.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_a_station_left_is_not_answered_in_its_quiet_time() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("Test calls"))).await;
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-10.0))]);
    publish(&f, e + 30_000, &[]);
    publish(&f, e + 60_000, &[]);
    assert_eq!(
        f.read("automation").await["run"]["left"],
        json!({"call":"K1ABC","reason":"repetitions"})
    );
    publish(
        &f,
        e + 90_000,
        &[
            ("HB9BLA K1ABC -10", 1500.0, Some(-10.0)),
            ("CQ DL1XYZ JO62", 1200.0, Some(9.0)),
        ],
    );
    let c = contact(&f).await;
    assert_eq!(c.0, json!("DL1XYZ"), "the quiet caller is not answered");
    assert_eq!(c.2, json!("armed"));
}

// Proves: TC-039-004. Review finding 3, coordinator's decision: a reload, second tab or 401
// recovery (a new proof of the grant) does not stop a strategy; the grant does. The transport's
// 8 h deadline does not bind it; a policy run keeps its transport (tc_020_003).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_a_strategy_run_follows_the_grant_not_the_transport() {
    let mut f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("Test calls"))).await;
    let client = f.state.recording.clients.session();
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    assert_eq!(contact(&f).await.2, json!("armed"));
    // A new proof, as a page load makes: the run and its contact go on.
    f.renew().await;
    f.tick();
    assert_eq!(run_state(&f).await, ("contact_active".into(), Value::Null));
    assert_eq!(contact(&f).await.2, json!("armed"));
    // Past the transport's 8 h deadline: still running.
    let skew = |d: Duration| {
        *f.state
            .recording
            .contact
            .get()
            .unwrap()
            .automation
            .skew
            .lock()
            .unwrap() = d;
    };
    skew(Duration::from_secs(8 * 3600 + 1));
    f.tick();
    assert_eq!(run_state(&f).await, ("contact_active".into(), Value::Null));
    skew(Duration::ZERO);
    drop(client);
    // The grant revoked: it stops, a contact it armed is disarmed.
    {
        let mut store = f.state.store.lock().unwrap();
        let mut owner = f.state.authorization.lock().unwrap();
        owner
            .as_mut()
            .unwrap()
            .authority
            .revoke(&mut store, &f.gid, &profile::new_uuid().unwrap(), false)
            .unwrap();
    }
    f.tick();
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("authority_lost"))
    );
    assert_eq!(
        f.state
            .recording
            .transmit
            .get()
            .unwrap()
            .service
            .view()
            .arm_state,
        wstx_rust::transmit::service::ArmState::Disarmed
    );
}

/// The run state without an MCP request (a request counts as a client).
fn quiet_run(f: &Mcp) -> (String, Value) {
    let a = f
        .state
        .recording
        .contact
        .get()
        .unwrap()
        .automation
        .snapshot(&f.state.recording);
    (
        a["run"]["state"].as_str().unwrap_or("").to_owned(),
        a["run"]["reason"].clone(),
    )
}
/// The contact the browser reads (no MCP request).
async fn quiet_contact(f: &Mcp) -> (Value, Value, Value) {
    let c = f.browser("GET", "/contact", None).await.json;
    (
        c["contact"]["dx_call"].clone(),
        c["contact"]["state"].clone(),
        c["transmit"]["arm_state"].clone(),
    )
}
fn at_skew(f: &Mcp, seconds: u64) {
    *f.state
        .recording
        .contact
        .get()
        .unwrap()
        .automation
        .skew
        .lock()
        .unwrap() = Duration::from_secs(seconds);
    f.tick();
}

// Proves: TC-039-033 (WstxStrategy::StrategyRun, coordinator default): with no client for 60 s a
// strategy selects nothing new, the exchange in progress runs on, then it stops no_client.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_033_without_a_client_for_60_s_nothing_new_and_the_exchange_ends() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("Test calls"))).await;
    // 59 s: it still calls.
    at_skew(&f, 59);
    assert_eq!(quiet_run(&f), ("waiting".into(), Value::Null));
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    assert_eq!(
        quiet_contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
    // 60 s: the exchange in progress runs on to its end.
    at_skew(&f, 60);
    assert_eq!(quiet_run(&f), ("contact_active".into(), Value::Null));
    publish(&f, e + 30_000, &[("HB9BLA K1ABC -05", 1505.0, Some(-6.0))]);
    assert_eq!(quiet_run(&f).0, "contact_active");
    publish(&f, e + 60_000, &[("HB9BLA K1ABC RR73", 1505.0, Some(-6.0))]);
    transmit_own_period(&f, e + 15_000).await;
    assert_eq!(quiet_contact(&f).await.1, json!("completed"));
    f.tick();
    f.tick();
    assert_eq!(quiet_run(&f), ("stopped".into(), json!("no_client")));
    assert_eq!(
        f.browser("GET", "/strategy", None).await.json["configuration"]["active"],
        json!("Test calls"),
        "it stays selected with the reason"
    );
    // Nothing new is selected.
    publish(&f, e + 150_000, &[("CQ DL1XYZ JO62", 1200.0, Some(9.0))]);
    assert_eq!(quiet_contact(&f).await.2, json!("disarmed"));
    assert_eq!(quiet_contact(&f).await.0, json!("K1ABC"));
    // No automatic and no MCP restart: only a new selection.
    let a = f.read("automation").await;
    let safety = f.read("contact").await["transmit"]["safety_revision"].clone();
    let r = f
        .tool(
            "wstx_automation_command",
            json!({"command":{"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),
                "action":"start","expected_policy_revision":a["policy_revision"],
                "expected_run_revision":a["run_revision"],"mode":"ft8","safety_revision":safety}}),
        )
        .await;
    assert_eq!(r["result"]["error"]["code"], "operator_required", "{r}");
    save(&f, config(None)).await;
    select(&f, config(Some("Test calls"))).await;
    assert_eq!(quiet_run(&f), ("waiting".into(), Value::Null));
    publish(&f, e + 180_000, &[("CQ DL1XYZ JO62", 1200.0, Some(9.0))]);
    assert_eq!(quiet_contact(&f).await.0, json!("DL1XYZ"));
    assert_eq!(f.keys(), 2, "key on and off of the one own period above");
}

/// A run with goal dxcc_band and one QSO with K1ABC completed on 40m; the station then on 20m.
async fn worked_on_40m_now_on_20m() -> (Mcp, i64, crate::automation::ClientSession) {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    f.state.recording.fixture_band("40m");
    let e = at_even(&f);
    let client = f.state.recording.clients.session();
    let mut c = config(Some("Test calls"));
    c["strategies"][0]["goals"] = json!(["dxcc_band"]);
    select(&f, c).await;
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    publish(&f, e + 30_000, &[("HB9BLA K1ABC -05", 1505.0, Some(-6.0))]);
    publish(&f, e + 60_000, &[("HB9BLA K1ABC RR73", 1505.0, Some(-6.0))]);
    transmit_own_period(&f, e + 15_000).await;
    assert_eq!(quiet_contact(&f).await.1, json!("completed"));
    f.tick();
    f.tick();
    f.state.logbook.worked_set().unwrap();
    (f, e, client)
}

// Proves: TC-039-004. Review 6685870468 finding 1: a station completed in a run is left out on
// that band and mode only: after a retune it is a candidate again.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_a_station_completed_on_one_band_is_called_on_another() {
    let (f, e, _client) = worked_on_40m_now_on_20m().await;
    // A caller of the same station on the same band: completed here, not answered again.
    publish(
        &f,
        e + 120_000,
        &[("HB9BLA K1ABC FN42", 1500.0, Some(-1.0))],
    );
    assert_eq!(
        quiet_run(&f).0,
        "waiting",
        "completed on this band and mode"
    );
    f.state.recording.fixture_band("20m");
    publish(&f, e + 150_000, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    assert_eq!(quiet_run(&f).0, "contact_active");
    assert_eq!(
        quiet_contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
}

// Proves: TC-039-004. The same for a caller: always answered on the new band.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_a_station_completed_on_one_band_is_answered_on_another() {
    let (f, e, _client) = worked_on_40m_now_on_20m().await;
    f.state.recording.fixture_band("20m");
    publish(
        &f,
        e + 150_000,
        &[("HB9BLA K1ABC FN42", 1500.0, Some(-1.0))],
    );
    assert_eq!(
        quiet_contact(&f).await,
        (json!("K1ABC"), json!("report"), json!("armed"))
    );
}

// Proves: TC-039-004, TC-039-043. The quiet time of a left station holds on its band and mode only;
// the station the operator gave up stays given up for the rest of the run.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_a_retune_leaves_the_quiet_time_behind_not_the_operators_give_up() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    f.state.recording.fixture_band("40m");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    select(&f, config(Some("Test calls"))).await;
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    publish(&f, e + 30_000, &[]);
    publish(&f, e + 60_000, &[]);
    assert_eq!(
        f.read("automation").await["run"]["quiet"][0]["band"],
        json!("40m")
    );
    f.state.recording.fixture_band("20m");
    publish(
        &f,
        e + 90_000,
        &[
            ("CQ K1ABC FN42", 1500.0, Some(9.0)),
            ("CQ DL1XYZ JO62", 1200.0, Some(-9.0)),
        ],
    );
    assert_eq!(
        quiet_contact(&f).await.0,
        json!("K1ABC"),
        "the strongest: quiet only on 40 m"
    );
    browser_ok(&f, "cancel", json!({})).await;
    f.tick();
    f.tick();
    f.state.recording.fixture_band("15m");
    publish(&f, e + 120_000, &[("CQ K1ABC FN42", 1500.0, Some(9.0))]);
    assert_eq!(
        quiet_run(&f).0,
        "waiting",
        "given up for the rest of the run"
    );
}

// Proves: TC-039-033: the status WebSocket itself is what counts: an actual upgrade over the
// served router with the browser's cookie holds a run past 60 s, its close lets the 60 s run.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_033_a_real_status_websocket_keeps_a_strategy_and_its_close_ends_that() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    at_even(&f);
    select(&f, config(Some("Test calls"))).await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let app = f.app.clone();
    let server = tokio::spawn(async move {
        axum::serve(listener, crate::router(app)).await.unwrap();
    });
    let (origin, cookie) = (f.app.origin.clone(), f.cookie());
    let (stream, line) = tokio::task::spawn_blocking(move || {
        use std::io::{BufRead, Write};
        let mut stream = std::net::TcpStream::connect(address).unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        let request = [
            "GET /ws HTTP/1.1".to_owned(),
            format!("Host: {address}"),
            format!("Origin: {origin}"),
            "Connection: Upgrade".to_owned(),
            "Upgrade: websocket".to_owned(),
            "Sec-WebSocket-Version: 13".to_owned(),
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==".to_owned(),
            "Sec-WebSocket-Protocol: wstx.v1".to_owned(),
            format!("Cookie: {cookie}"),
            String::new(),
            String::new(),
        ]
        .join("\r\n");
        stream.write_all(request.as_bytes()).unwrap();
        let mut line = String::new();
        std::io::BufReader::new(stream.try_clone().unwrap())
            .read_line(&mut line)
            .unwrap();
        (stream, line)
    })
    .await
    .unwrap();
    assert!(line.starts_with("HTTP/1.1 101"), "{line}");
    let clients = &f.state.recording.clients;
    let deadline = Instant::now() + Duration::from_secs(5);
    while clients.sessions_open() != 1 {
        assert!(Instant::now() < deadline, "the upgrade opens one session");
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    at_skew(&f, 61);
    assert_eq!(quiet_run(&f), ("waiting".into(), Value::Null), "past 60 s");
    at_skew(&f, 300);
    assert_eq!(quiet_run(&f), ("waiting".into(), Value::Null));
    // The browser goes away: the session ends and the 60 s count from there.
    drop(stream);
    let deadline = Instant::now() + Duration::from_secs(10);
    while clients.sessions_open() != 0 {
        assert!(Instant::now() < deadline, "the close ends the session");
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    at_skew(&f, 359);
    assert_eq!(quiet_run(&f), ("waiting".into(), Value::Null));
    at_skew(&f, 360);
    assert_eq!(quiet_run(&f), ("stopped".into(), json!("no_client")));
    server.abort();
}

// Proves: TC-039-033 (operator decision 2026-11-06): a run lasts at most 8 hours from its
// selection, also with a client connected throughout; a new selection starts again.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_033_a_strategy_run_lasts_at_most_8_hours_from_its_selection() {
    const H8: u64 = 8 * 3600;
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    select(&f, config(Some("Test calls"))).await;
    // Just before: it still selects.
    at_skew(&f, H8 - 1);
    assert_eq!(quiet_run(&f), ("waiting".into(), Value::Null));
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    assert_eq!(quiet_contact(&f).await.0, json!("K1ABC"));
    assert_eq!(quiet_contact(&f).await.2, json!("armed"));
    // At 8 h: the exchange in progress runs on to its end, then the run stops.
    at_skew(&f, H8);
    assert_eq!(quiet_run(&f), ("contact_active".into(), Value::Null));
    publish(&f, e + 30_000, &[("HB9BLA K1ABC -05", 1505.0, Some(-6.0))]);
    assert_eq!(quiet_run(&f).0, "contact_active");
    publish(&f, e + 60_000, &[("HB9BLA K1ABC RR73", 1505.0, Some(-6.0))]);
    transmit_own_period(&f, e + 15_000).await;
    assert_eq!(quiet_contact(&f).await.1, json!("completed"));
    f.tick();
    f.tick();
    assert_eq!(quiet_run(&f), ("stopped".into(), json!("run_limit")));
    assert_eq!(
        f.browser("GET", "/strategy", None).await.json["configuration"]["active"],
        json!("Test calls"),
        "it stays selected with the reason"
    );
    // No new station.
    publish(&f, e + 150_000, &[("CQ DL1XYZ JO62", 1200.0, Some(9.0))]);
    assert_eq!(quiet_contact(&f).await.2, json!("disarmed"));
    assert_eq!(quiet_contact(&f).await.0, json!("K1ABC"));
    // A new selection starts a new 8 hours, also from here on.
    save(&f, config(None)).await;
    select(&f, config(Some("Test calls"))).await;
    at_skew(&f, H8 + H8 - 1);
    assert_eq!(quiet_run(&f), ("waiting".into(), Value::Null));
    publish(&f, e + 180_000, &[("CQ DL1XYZ JO62", 1200.0, Some(9.0))]);
    assert_eq!(quiet_contact(&f).await.0, json!("DL1XYZ"));
    // Waiting at the limit: it stops at once.
    browser_ok(&f, "cancel", json!({})).await;
    f.tick();
    f.tick();
    assert_eq!(quiet_run(&f).0, "waiting");
    at_skew(&f, H8 + H8);
    assert_eq!(quiet_run(&f), ("stopped".into(), json!("run_limit")));
}

// Proves: TC-039-033
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_033_waiting_stops_at_60_s_and_a_client_or_reload_keeps_it() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("Test calls"))).await;
    at_skew(&f, 60);
    assert_eq!(quiet_run(&f), ("stopped".into(), json!("no_client")));
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    assert_eq!(quiet_contact(&f).await.0, Value::Null, "nothing selected");
    // A status session keeps it, however long; after it the 60 s count from its end. A reload
    // inside them (a new session) keeps it too.
    at_skew(&f, 0);
    save(&f, config(None)).await;
    select(&f, config(Some("Test calls"))).await;
    let session = f.state.recording.clients.session();
    at_skew(&f, 120);
    assert_eq!(quiet_run(&f), ("waiting".into(), Value::Null));
    drop(session);
    at_skew(&f, 150);
    assert_eq!(quiet_run(&f).0, "waiting");
    let reloaded = f.state.recording.clients.session();
    at_skew(&f, 300);
    drop(reloaded);
    at_skew(&f, 359);
    assert_eq!(quiet_run(&f), ("waiting".into(), Value::Null));
    at_skew(&f, 360);
    assert_eq!(quiet_run(&f), ("stopped".into(), json!("no_client")));
    // An authenticated MCP request: its time counts.
    at_skew(&f, 0);
    save(&f, config(None)).await;
    select(&f, config(Some("Test calls"))).await;
    at_skew(&f, 59);
    f.read("transmit").await;
    f.tick();
    assert_eq!(quiet_run(&f), ("waiting".into(), Value::Null));
    at_skew(&f, 118);
    assert_eq!(quiet_run(&f).0, "waiting");
    at_skew(&f, 119);
    assert_eq!(quiet_run(&f), ("stopped".into(), json!("no_client")));
    // A client back before the contact's end: no stop.
    at_skew(&f, 0);
    save(&f, config(None)).await;
    select(&f, config(Some("Test calls"))).await;
    publish(&f, e + 30_000, &[("CQ DL1XYZ JO62", 1200.0, Some(-1.0))]);
    assert_eq!(quiet_contact(&f).await.0, json!("DL1XYZ"));
    at_skew(&f, 61);
    assert_eq!(quiet_run(&f).0, "contact_active");
    let back = f.state.recording.clients.session();
    f.tick();
    browser_ok(&f, "cancel", json!({})).await;
    f.tick();
    f.tick();
    assert_eq!(quiet_run(&f), ("waiting".into(), Value::Null));
    drop(back);
    assert_eq!(f.keys(), 0);
}

// Proves: TC-039-030 (WstxStrategy::WorkedWindow through the store): a QSO of this UTC date
// counts in today, not in a window that ended before.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_030_today_and_from_to_read_the_log_of_the_window() {
    let f = station(true).await;
    let (source, job, generation) = f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("Test calls"))).await;
    publish(&f, e, &[("HB9BLA K1ABC FN42", 1500.0, Some(-10.0))]);
    publish(
        &f,
        e + 30_000,
        &[("HB9BLA K1ABC R-05", 1500.0, Some(-10.0))],
    );
    publish(&f, e + 60_000, &[("HB9BLA K1ABC 73", 1500.0, Some(-10.0))]);
    assert_eq!(contact(&f).await.1, json!("completed"));
    save(&f, config(None)).await;
    publish(&f, e + 90_000, &[("CQ K1ABC FN42", 1500.0, Some(-10.0))]);
    let first = f
        .state
        .recording
        .live_records_after(None, 0)
        .unwrap()
        .2
        .len() as u64
        - 1;
    let rank = async |window: Value| {
        let mut s = strategy_json("W");
        s["window"] = window;
        let body = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"source_id":source,"job_id":job,
            "generation":generation,"first_sequence":first,"next_sequence":first + 1,"strategy":s,"explain":true});
        let v = f.browser("POST", "/strategy/evaluate", Some(body)).await;
        assert_eq!(v.status, StatusCode::OK, "{}", v.json);
        v.json["verdicts"][0]["rank"].clone()
    };
    assert_eq!(rank(json!({"kind":"all"})).await, Value::Null, "logged");
    assert_eq!(
        rank(json!({"kind":"today"})).await,
        Value::Null,
        "logged today"
    );
    assert_eq!(
        rank(json!({"kind":"from_to","from":"2020-01-01","to":"2020-12-31"})).await,
        json!(0),
        "not in that window"
    );
    let today = utc_date();
    let today = format!(
        "{:04}-{:02}-{:02}",
        today / 10000,
        today / 100 % 100,
        today % 100
    );
    assert_eq!(
        rank(json!({"kind":"from_to","from":today,"to":today})).await,
        Value::Null
    );
}

// Proves: TC-039-031
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_031_update_most_wanted_status_failures_and_mcp_refusal() {
    let f = station(true).await;
    let update = async || {
        let body = json!({"v":1,"profile_id":f.id,"boot_id":f.boot});
        f.browser("POST", "/strategy/most-wanted/download", Some(body))
            .await
    };
    let g = f.browser("GET", "/strategy", None).await.json;
    assert_eq!(
        (
            g["most_wanted"].clone(),
            g["most_wanted_unreadable"].clone(),
            g["most_wanted_attribution"].clone()
        ),
        (
            Value::Null,
            json!(false),
            json!("Club Log Most Wanted list, Club Log (c) Michael Wells G7VJR, clublog.org")
        )
    );
    let owner = f.state.recording.contact.get().unwrap();
    // Status with the unknown number counted; a new owner reads the file.
    let today = utc_date();
    let today = format!(
        "{:04}-{:02}-{:02}",
        today / 10000,
        today / 100 % 100,
        today % 100
    );
    *owner.strategy.fetch.lock().unwrap() = Some(Ok("{\"1\":\"150\",\"2\":\"9999\"}".into()));
    let r = update().await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);
    assert_eq!(
        r.json["most_wanted"],
        json!({"date":today,"entries":2,"unmapped":1})
    );
    let file: Value =
        serde_json::from_slice(&std::fs::read(f.dir.join(crate::most_wanted::FILE_NAME)).unwrap())
            .unwrap();
    assert_eq!(
        file,
        json!({"schema_version":1,"profile_id":f.id,"date":today,"list":{"1":"150","2":"9999"}})
    );
    let reopened = Owner::default();
    reopened.most_wanted_load(&f.state);
    assert_eq!(
        reopened.snapshot(&f.state)["most_wanted"],
        r.json["most_wanted"]
    );
    assert_eq!(
        reopened.most_wanted_read().unwrap().rank("Australia"),
        Some(1)
    );
    // A failed fetch and a reply that is no list keep the list and name the reason.
    *owner.strategy.fetch.lock().unwrap() = Some(Err("status 503".into()));
    let d = update().await;
    assert_eq!(
        (d.status.as_u16(), d.json["error"].clone()),
        (502, json!({"code":"download_failed","reason":"status 503"}))
    );
    *owner.strategy.fetch.lock().unwrap() = Some(Ok("<html>".into()));
    let d = update().await;
    assert_eq!(
        (d.status.as_u16(), d.json["error"]["reason"].clone()),
        (502, json!("the reply is not a Most Wanted list"))
    );
    assert_eq!(
        f.browser("GET", "/strategy", None).await.json["most_wanted"]["entries"],
        json!(2),
        "the list stays"
    );
    // Exact keys.
    let extra = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"x":1});
    let r = f
        .browser("POST", "/strategy/most-wanted/download", Some(extra))
        .await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
    // There is no upload route.
    let r = f
        .browser(
            "POST",
            "/strategy/most-wanted",
            Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"text":"{\"1\":\"150\"}"})),
        )
        .await;
    assert!(matches!(r.status.as_u16(), 404 | 405), "{}", r.status);
    // The MCP principal may not change it.
    let internal = crate::mcp_tests::internal_transport(&f, &f.mcp);
    let m = crate::mcp_tests::with_cookie(
        &f,
        "POST",
        "/strategy/most-wanted/download",
        &internal,
        Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot})),
    )
    .await;
    assert_eq!(m.status, StatusCode::UNAUTHORIZED);
    // An unreadable file: no list, flagged.
    std::fs::write(f.dir.join(crate::most_wanted::FILE_NAME), b"{").unwrap();
    let broken = Owner::default();
    broken.most_wanted_load(&f.state);
    let s = broken.snapshot(&f.state);
    assert_eq!(
        (
            s["most_wanted"].clone(),
            s["most_wanted_unreadable"].clone()
        ),
        (Value::Null, json!(true))
    );
}

/// The operator switches Hold Tx off (#39 holdtx: the Rx = Tx rule of WstxStrategy::FreeTxSlot).
async fn hold_off(f: &Mcp) {
    browser_ok(f, "set_hold_tx", json!({"enabled":false})).await;
    assert_eq!(f.read("contact").await["settings"]["hold_tx"], false);
}
/// The operator sets Tx to `hz` (Rx unchanged).
async fn set_tx(f: &Mcp, hz: u32) {
    browser_ok(f, "set_frequency", json!({"rx_hz":null,"tx_hz":hz})).await;
    assert_eq!(f.read("contact").await["settings"]["tx_hz"], json!(hz));
}
/// (Rx, Tx, the run's slot status).
async fn frequencies(f: &Mcp) -> (Value, Value, Value) {
    let settings = f.read("contact").await["settings"].clone();
    let slot = f.read("automation").await["run"]["tx_slot"].clone();
    (settings["rx_hz"].clone(), settings["tx_hz"].clone(), slot)
}

// Proves: CL-039-09; TC-039-010. Hold Tx explicitly off (#39 holdtx; with it on: TC-039-049 (f)).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_010_never_on_the_called_station_also_with_hold_tx_off() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    hold_off(&f).await;
    select(&f, config(Some("Test calls"))).await;
    // A station on my Tx, no power yet: 1400 and 1600 tie, the lower; Rx = Tx.
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-5.0))]);
    assert_eq!(
        frequencies(&f).await,
        (
            json!(1400),
            json!(1400),
            json!({"hz":1400,"power_db":null,"his_end":"unknown"})
        )
    );
    // Repetitions 2 leave K1ABC. Hold Tx off: the selection moves Tx, the run takes it back.
    publish(&f, e + 30_000, &[]);
    publish(&f, e + 60_000, &[]);
    assert_eq!(contact(&f).await.2, json!("disarmed"));
    mcp_contact(&f, "set_hold_tx", json!({"enabled":false})).await;
    publish(&f, e + 90_000, &[("CQ DL1XYZ JO62", 1700.0, Some(-5.0))]);
    assert_eq!(
        contact(&f).await,
        (json!("DL1XYZ"), json!("replying"), json!("armed"))
    );
    assert_eq!(
        frequencies(&f).await,
        (
            json!(1400),
            json!(1400),
            json!({"hz":1400,"power_db":null,"his_end":"unknown"})
        )
    );
    assert_eq!(f.keys(), 0);
}

// Proves: CL-039-05, CL-039-09; TC-039-010. Between the run's select_row and its Tx
// move the operator replaces the contact: the set_frequency is refused stale and the operator's
// contact stands.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_010_a_double_click_racing_the_slot_move_stays_the_operators() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("Test calls"))).await;
    let state = f.state.clone();
    let (id, boot) = (f.id.clone(), f.boot.clone());
    *f.state
        .recording
        .contact
        .get()
        .unwrap()
        .automation
        .before_slot_move
        .lock()
        .unwrap() = Some(Box::new(move || {
        let (identity, _, records) = state.recording.live_records_after(None, 0).unwrap();
        let record = records
            .iter()
            .find(|r| r["text"] == "CQ DL1XYZ JO62")
            .unwrap();
        let row = json!({"source_id":identity.0,"job_id":identity.1,"generation":identity.2,"sequence":record["sequence"]});
        let station = state.recording.contact.get().unwrap();
        let body = json!({"v":1,"profile_id":id,"boot_id":boot,"command_id":profile::new_uuid().unwrap(),
                "contact_revision":station.facts().0,"action":"select_row","row":row,"replace":true});
        station
            .operate_as(&state, body, true, authorization::Principal::Browser)
            .unwrap();
    }));
    // K1ABC (strongest) is on my Tx 1500, so the run must move it.
    publish(
        &f,
        e,
        &[
            ("CQ K1ABC FN42", 1500.0, Some(-3.0)),
            ("CQ DL1XYZ JO62", 1200.0, Some(-5.0)),
        ],
    );
    assert_eq!(
        contact(&f).await.0,
        json!("DL1XYZ"),
        "the operator's contact stands"
    );
    assert_eq!(run_state(&f).await, ("manual".to_owned(), Value::Null));
}

// Proves: CL-039-09; TC-039-010. A pounce answers as a strategy run does (Hold Tx explicitly off,
// #39 holdtx; with it on: TC-039-049 (k)).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_010_a_pounce_never_calls_on_the_called_station() {
    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    hold_off(&f).await;
    assert_eq!(pounce(&f, "K1ABC", 5).await.status, StatusCode::ACCEPTED);
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-5.0))]);
    assert_eq!(contact(&f).await.0, json!("K1ABC"));
    assert_eq!(
        frequencies(&f).await,
        (
            json!(1400),
            json!(1400),
            json!({"hz":1400,"power_db":null,"his_end":"unknown"})
        )
    );
}

/// Moves the bench to 30 ms before the own period `own` and ticks until the transmitter
/// is disarmed (the Tx watchdog refuses to key it).
// Proves: TC-039-004
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_a_double_click_is_a_manual_intervention_and_the_strategy_resumes() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("Test calls"))).await;
    let run_state =
        async |f: &Mcp| f.browser("GET", "/automation", None).await.json["run"]["state"].clone();
    // The run selects K1ABC. The operator double-clicks another station.
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-3.0))]);
    assert_eq!(contact(&f).await.0, json!("K1ABC"));
    publish(&f, e + 15_000, &[("CQ DL1XYZ JO62", 1200.0, Some(-5.0))]);
    let identity = live_row(&f, "CQ DL1XYZ JO62");
    let reply = f
        .browser(
            "POST",
            "/contact/command",
            Some(browser_command(&f, "select_row", json!({"row":identity,"replace":true})).await),
        )
        .await;
    assert_eq!(reply.status, StatusCode::ACCEPTED, "{}", reply.json);
    f.tick();
    assert_eq!(run_state(&f).await, json!("manual"));
    assert_eq!(
        contact(&f).await.0,
        json!("DL1XYZ"),
        "the manual contact stands"
    );
    assert_eq!(
        f.browser("GET", "/strategy", None).await.json["configuration"]["active"],
        json!("Test calls")
    );
    // While manual the strategy selects nothing.
    publish(&f, e + 30_000, &[("CQ W1AW FN31", 1000.0, Some(-1.0))]);
    assert_eq!(contact(&f).await.0, json!("DL1XYZ"));
    // The manual QSO ends: the strategy resumes and answers the next match.
    let cancel = f
        .browser(
            "POST",
            "/contact/command",
            Some(browser_command(&f, "cancel", json!({})).await),
        )
        .await;
    assert_eq!(cancel.status, StatusCode::ACCEPTED);
    f.tick();
    assert_eq!(run_state(&f).await, json!("waiting"));
    publish(&f, e + 60_000, &[("CQ W1AW FN31", 1000.0, Some(-1.0))]);
    assert_eq!(contact(&f).await.0, json!("W1AW"));
    assert_eq!(run_state(&f).await, json!("contact_active"));
    // Cancelling the run's own contact gives that station up; the strategy goes on.
    let cancel = f
        .browser(
            "POST",
            "/contact/command",
            Some(browser_command(&f, "cancel", json!({})).await),
        )
        .await;
    assert_eq!(cancel.status, StatusCode::ACCEPTED);
    f.tick();
    f.tick();
    assert_eq!(run_state(&f).await, json!("waiting"));
    publish(&f, e + 90_000, &[("CQ W1AW FN31", 1000.0, Some(-1.0))]);
    assert_eq!(
        contact(&f).await.1,
        json!("cancelled"),
        "W1AW is not selected again"
    );
    publish(&f, e + 120_000, &[("CQ G4ABC IO91", 1000.0, Some(-9.0))]);
    assert_eq!(contact(&f).await.0, json!("G4ABC"));
}

// Proves: TC-039-002
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_002_a_selection_of_a_cq_not_for_me_is_a_warning_only_the_browser_confirms() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    publish(
        &f,
        e,
        &[
            ("CQ NA W1AW FN31", 1000.0, Some(-1.0)),
            ("CQ EU G4ABC IO91", 1100.0, Some(-2.0)),
        ],
    );
    let (na, eu) = (
        live_row(&f, "CQ NA W1AW FN31"),
        live_row(&f, "CQ EU G4ABC IO91"),
    );
    let w = f
        .browser(
            "POST",
            "/contact/command",
            Some(browser_command(&f, "select_row", json!({"row":na,"replace":false})).await),
        )
        .await;
    assert_eq!(w.status, StatusCode::CONFLICT, "{}", w.json);
    assert_eq!(w.json["error"]["code"], "directive_not_answerable");
    assert_eq!(w.json["error"]["reason"], "CQ NA — not for EU");
    assert_eq!(
        contact(&f).await.0,
        Value::Null,
        "nothing selected by the warning"
    );
    // A client that is not the browser cannot confirm it.
    let m = mcp_contact(
        &f,
        "select_row",
        json!({"row":na,"replace":false,"directive_confirmed":true}),
    )
    .await;
    assert_eq!(
        m["result"]["error"]["code"], "directive_not_answerable",
        "{m}"
    );
    assert_eq!(contact(&f).await.0, Value::Null);
    // The operator's confirmation selects it; a CQ for my continent asks nothing.
    let c = f
        .browser(
            "POST",
            "/contact/command",
            Some(
                browser_command(
                    &f,
                    "select_row",
                    json!({"row":na,"replace":false,"directive_confirmed":true}),
                )
                .await,
            ),
        )
        .await;
    assert_eq!(c.status, StatusCode::ACCEPTED, "{}", c.json);
    assert_eq!(contact(&f).await.0, json!("W1AW"));
    let c = f
        .browser(
            "POST",
            "/contact/command",
            Some(browser_command(&f, "select_row", json!({"row":eu,"replace":true})).await),
        )
        .await;
    assert_eq!(c.status, StatusCode::ACCEPTED, "{}", c.json);
    assert_eq!(contact(&f).await.0, json!("G4ABC"));
    // During a contact the directive is checked before contact_active: a plain click stays silent.
    publish(&f, e + 30_000, &[("CQ NA W9XYZ EN52", 900.0, Some(-1.0))]);
    let click = live_row(&f, "CQ NA W9XYZ EN52");
    let during = f
        .browser(
            "POST",
            "/contact/command",
            Some(browser_command(&f, "select_row", json!({"row":click,"replace":false})).await),
        )
        .await;
    assert_eq!(during.status, StatusCode::CONFLICT, "{}", during.json);
    assert_eq!(during.json["error"]["code"], "directive_not_answerable");
    assert_eq!(contact(&f).await.0, json!("G4ABC"), "the contact stands");
    // The body key is optional and exact.
    let bad = f
        .browser(
            "POST",
            "/contact/command",
            Some(
                browser_command(
                    &f,
                    "select_row",
                    json!({"row":eu,"replace":true,"directive_confirmed":"yes"}),
                )
                .await,
            ),
        )
        .await;
    assert_eq!(bad.status, StatusCode::BAD_REQUEST);
}

// Proves: TC-039-004
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_a_manual_qso_while_the_strategy_waits_completes_and_the_strategy_resumes() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("Test calls"))).await;
    // A row the strategy skips, so the run keeps waiting; the operator confirms and arms it.
    publish(&f, e, &[("CQ NA W9XYZ EN52", 900.0, Some(-3.0))]);
    assert_eq!(run_state(&f).await.0, "waiting");
    browser_ok(
        &f,
        "select_row",
        json!({"row":live_row(&f, "CQ NA W9XYZ EN52"),"replace":false,"directive_confirmed":true}),
    )
    .await;
    let safety = f.read("contact").await["transmit"]["safety_revision"].clone();
    browser_ok(
        &f,
        "enable_tx",
        json!({"enabled":true,"safety_revision":safety}),
    )
    .await;
    f.tick();
    assert_eq!(run_state(&f).await.0, "manual");
    assert_eq!(
        contact(&f).await,
        (json!("W9XYZ"), json!("replying"), json!("armed"))
    );
    assert_eq!(
        f.browser("GET", "/strategy", None).await.json["configuration"]["active"],
        json!("Test calls")
    );
    // The partner's report and RR73: completed; the strategy waits and answers the next match.
    publish(&f, e + 30_000, &[("HB9BLA W9XYZ -05", 905.0, Some(-6.0))]);
    publish(&f, e + 60_000, &[("HB9BLA W9XYZ RR73", 905.0, Some(-6.0))]);
    transmit_own_period(&f, e + 15_000).await;
    assert_eq!(contact(&f).await.1, json!("completed"));
    f.tick();
    assert_eq!(run_state(&f).await.0, "waiting");
    publish(&f, e + 120_000, &[("CQ K1ABC FN42", 1500.0, Some(-3.0))]);
    assert_eq!(contact(&f).await.0, json!("K1ABC"));
    assert_eq!(run_state(&f).await.0, "contact_active");
}

// Proves: TC-039-004
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_stop_and_halt_while_manual() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("Test calls"))).await;
    // A double-click while it waits: manual; the operator arms; the contact stands.
    publish(&f, e, &[("CQ NA W9XYZ EN52", 900.0, Some(-3.0))]);
    browser_ok(
        &f,
        "select_row",
        json!({"row":live_row(&f, "CQ NA W9XYZ EN52"),"replace":true,"directive_confirmed":true}),
    )
    .await;
    let safety = f.read("contact").await["transmit"]["safety_revision"].clone();
    browser_ok(
        &f,
        "enable_tx",
        json!({"enabled":true,"safety_revision":safety}),
    )
    .await;
    f.tick();
    assert_eq!(run_state(&f).await.0, "manual");
    assert_eq!(contact(&f).await.0, json!("W9XYZ"));
    assert_eq!(contact(&f).await.2, json!("armed"));
    // None while manual leaves the operator's contact armed.
    save(&f, config(None)).await;
    assert_eq!(run_state(&f).await.0, "stopped");
    assert_eq!(
        contact(&f).await.2,
        json!("armed"),
        "the run disarms nothing"
    );
    // Halt while manual stops the run halted.
    browser_ok(&f, "cancel", json!({})).await;
    select(&f, config(Some("Test calls"))).await;
    f.tick();
    assert_eq!(run_state(&f).await.0, "waiting");
    publish(&f, e + 30_000, &[("CQ NA W8ABC EN80", 950.0, Some(-3.0))]);
    let row = live_row(&f, "CQ NA W8ABC EN80");
    browser_ok(
        &f,
        "select_row",
        json!({"row":row,"replace":true,"directive_confirmed":true}),
    )
    .await;
    f.tick();
    assert_eq!(run_state(&f).await.0, "manual");
    halt(&f).await;
    assert_eq!(run_state(&f).await, ("stopped".to_owned(), json!("halted")));
}

// Proves: TC-039-004
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_a_double_click_racing_the_run_selection_stays_the_operators() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("Test calls"))).await;
    let state = f.state.clone();
    let (id, boot) = (f.id.clone(), f.boot.clone());
    // Between the run's select_row and enable_tx the operator replaces the contact.
    *f.state
        .recording
        .contact
        .get()
        .unwrap()
        .automation
        .before_enable
        .lock()
        .unwrap() = Some(Box::new(move || {
        let (identity, _, records) = state.recording.live_records_after(None, 0).unwrap();
        let record = records
            .iter()
            .find(|r| r["text"] == "CQ DL1XYZ JO62")
            .unwrap();
        let row = json!({"source_id":identity.0,"job_id":identity.1,"generation":identity.2,"sequence":record["sequence"]});
        let station = state.recording.contact.get().unwrap();
        let body = json!({"v":1,"profile_id":id,"boot_id":boot,"command_id":profile::new_uuid().unwrap(),
                "contact_revision":station.facts().0,"action":"select_row","row":row,"replace":true});
        station
            .operate_as(&state, body, true, authorization::Principal::Browser)
            .unwrap();
    }));
    publish(
        &f,
        e,
        &[
            ("CQ K1ABC FN42", 1500.0, Some(-3.0)),
            ("CQ DL1XYZ JO62", 1200.0, Some(-5.0)),
        ],
    );
    f.tick();
    assert_eq!(
        contact(&f).await.0,
        json!("DL1XYZ"),
        "the operator's contact stands"
    );
    assert_eq!(run_state(&f).await, ("manual".to_owned(), Value::Null));
}

async fn browser_ok(f: &Mcp, action: &str, extra: Value) {
    let body = browser_command(f, action, extra).await;
    let r = f.browser("POST", "/contact/command", Some(body)).await;
    assert_eq!(r.status, StatusCode::ACCEPTED, "{action}: {}", r.json);
}
/// The ContactCommand row of the live record with this text.
fn live_row(f: &Mcp, text: &str) -> Value {
    let (identity, _, records) = f.state.recording.live_records_after(None, 0).unwrap();
    let record = records.iter().find(|r| r["text"] == text).unwrap();
    json!({"source_id":identity.0,"job_id":identity.1,"generation":identity.2,"sequence":record["sequence"]})
}
async fn browser_command(f: &Mcp, action: &str, extra: Value) -> Value {
    let revision = f.read("contact").await["contact_revision"].clone();
    let mut b = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),"contact_revision":revision,"action":action});
    b.as_object_mut()
        .unwrap()
        .extend(extra.as_object().unwrap().clone());
    b
}

/// Moves the bench to 30 ms before the own period `own` and ticks until the transmitter
/// is disarmed (the Tx watchdog refuses to key it).
// Proves: TC-039-005
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_005_automation_never_resets_the_tx_watchdog() {
    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    browser_watchdog(&f, 2).await;
    let mut c = config(Some("Test calls"));
    c["strategies"][0]["repetitions"] = json!(20);
    // A pounce keeps the stop at N; a strategy run has none (TC-039-022).
    let started = pounce(&f, "K1ABC", 20).await;
    assert_eq!(started.status, StatusCode::ACCEPTED, "{}", started.json);
    let halt_state = f.read("contact").await["transmit"]["halt_state"].clone();
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-10.0))]);
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
    // Each call counts; the run's selection does not reset it; the next is never keyed.
    transmit_own_period(&f, e + 15_000).await;
    assert_eq!(f.read("contact").await["watchdog"]["tx_remaining_calls"], 1);
    transmit_own_period(&f, e + 45_000).await;
    let keys = f.keys();
    not_keyed_in(&f, e + 75_000).await;
    assert_eq!(f.keys(), keys, "never keyed after the limit");
    f.tick();
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("tx_watchdog"))
    );
    let s = f.read("contact").await;
    assert_eq!(
        (
            s["watchdog"]["tx_expired"].clone(),
            s["transmit"]["last_disarm_cause"].clone(),
            s["transmit"]["halt_state"].clone(),
        ),
        (json!(true), json!("tx_watchdog"), halt_state),
        "stopped without a halt"
    );
    // A selection from the browser is an operator action: it arms again.
    browser_ok(&f, "cancel", json!({})).await;
    select(&f, c).await;
    publish(&f, e + 90_000, &[("CQ DL1XYZ JO62", 1200.0, Some(-1.0))]);
    assert_eq!(contact(&f).await.2, json!("armed"));
}

/// A strategy run calling K1ABC at 1800 Hz on 40 m from Tx 1500 with the Tx watchdog at `limit`,
/// with the feed `set` prepares once the run has its target. e is the even period of the CQ.
async fn run_at_limit(limit: u64, calls: u64, set: impl FnOnce(&crate::pskr::Feed)) -> (Mcp, i64) {
    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    browser_watchdog(&f, limit).await;
    let dir = std::env::temp_dir().join(format!("wstx-pskr-{}", profile::new_uuid().unwrap()));
    std::fs::create_dir(&dir).unwrap();
    let feed = crate::pskr::Feed::start(&dir, &f.id, &f.boot, None, crate::pskr::Timing::BROKER);
    f.state.recording.pskr.set(feed.clone()).ok().unwrap();
    let mut c = config(Some("Test calls"));
    c["strategies"][0]["repetitions"] = json!(calls);
    select(&f, c).await;
    publish(&f, e, &[("CQ K1ABC FN42", 1800.0, Some(-10.0))]);
    assert_eq!(contact(&f).await.0, json!("K1ABC"));
    assert_eq!(f.read("contact").await["settings"]["tx_hz"], 1500);
    f.tick();
    set(&feed);
    (f, e)
}
fn spot(sender: &str, hz: u64, band: &str, age_s: i64) -> String {
    let t = crate::contact_http_tests::now_ms() / 1000 - age_s;
    json!({"f":hz,"md":"FT8","t":t,"sc":sender,"rc":"K1ABC","b":band}).to_string()
}
// Proves: CL-039-21; TC-039-022. The unattended bounds hold for a target that hears us: with no
// client it is left after its calls and the run stops no_client, and likewise at the run limit.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_022_a_target_that_hears_us_does_not_outlive_the_run_bounds() {
    for (skew, reason) in [
        (crate::automation::CLIENT_GONE.as_secs(), "no_client"),
        (9 * 3600, "run_limit"),
    ] {
        let (f, e) = run_at_limit(2, 2, |feed| {
            feed.inject(&spot("HB9BLA", 7_075_500, "40m", 60));
        })
        .await;
        // Heard and attended: it stays.
        publish(&f, e + 30_000, &[]);
        publish(&f, e + 60_000, &[]);
        publish(&f, e + 90_000, &[]);
        assert_eq!(contact(&f).await.2, json!("armed"), "{reason}");
        // That read counted as a client: this step takes it, and none comes after it.
        f.tick();
        at_skew(&f, skew);
        publish(&f, e + 120_000, &[]);
        publish(&f, e + 150_000, &[]);
        publish(&f, e + 180_000, &[]);
        f.tick();
        assert_eq!(quiet_run(&f), ("stopped".into(), json!(reason)));
        assert_eq!(quiet_contact(&f).await.2, json!("disarmed"), "{reason}");
    }
}
// Proves: CL-039-21; TC-039-022. With no client, or past the run limit, the stop at N is back at once,
// so the run cannot go on transmitting even when no publication ever arrives to end its contact.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_022_unattended_the_stop_at_n_is_back_without_a_publication() {
    for (skew, reason) in [
        (crate::automation::CLIENT_GONE.as_secs(), "no_client"),
        (9 * 3600, "run_limit"),
    ] {
        let (f, e) = run_at_limit(2, 20, |feed| {
            feed.inject(&spot("HB9BLA", 7_075_500, "40m", 60));
        })
        .await;
        for own in [15_000, 45_000, 75_000] {
            transmit_own_period(&f, e + own).await;
            f.tick();
        }
        assert_eq!(
            quiet_contact(&f).await.2,
            json!("armed"),
            "past N, attended"
        );
        at_skew(&f, skew);
        let keys = f.keys();
        not_keyed_in(&f, e + 105_000).await;
        assert_eq!(f.keys(), keys, "never keyed again");
        assert_eq!(quiet_run(&f), ("stopped".into(), json!(reason)));
    }
}
// Proves: CL-039-20; CL-039-21; TC-039-022. Only a strategy run's own contact subscribes to its
// target: not a pounce, nor the same contact after the run ended.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_022_only_a_strategy_run_subscribes_to_its_target() {
    let (f, _) = run_at_limit(2, 20, |feed| {
        assert_eq!(feed.target().as_deref(), Some("K1ABC"), "the run's contact");
    })
    .await;
    let feed = f.state.recording.pskr.get().unwrap().clone();
    halt(&f).await;
    f.tick();
    assert_eq!(feed.target(), None, "the run ended, the contact stays");

    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let dir = std::env::temp_dir().join(format!("wstx-pskr-{}", profile::new_uuid().unwrap()));
    std::fs::create_dir(&dir).unwrap();
    let feed = crate::pskr::Feed::start(&dir, &f.id, &f.boot, None, crate::pskr::Timing::BROKER);
    f.state.recording.pskr.set(feed.clone()).ok().unwrap();
    assert_eq!(pounce(&f, "K1ABC", 20).await.status, StatusCode::ACCEPTED);
    publish(&f, e, &[("CQ K1ABC FN42", 1800.0, Some(-10.0))]);
    assert_eq!(contact(&f).await.0, json!("K1ABC"));
    f.tick();
    assert_eq!(feed.target(), None, "a pounce reads no spots");
}
// Proves: TC-039-005
#[test]
fn tc_039_005_core_watchdog_needs_an_operator_and_keeps_the_count_for_automation() {
    use wstx_rust::transmit::service::{ArmState, Core};
    let bench = crate::contact_http_tests::Bench::default();
    bench.unsupported.store(false, Ordering::SeqCst);
    let mut core = Core::new(Box::new(bench.clone()) as Box<dyn Hardware>);
    let revision = core.hardware().context().safety_revision.unwrap();
    assert!(
        core.watchdog_spent(),
        "no operator action yet: automation may not arm"
    );
    core.activity();
    assert!(!core.watchdog_spent());
    core.set_watchdogs(2, 90).unwrap();
    core.arm_automatic(revision).unwrap();
    assert_eq!(core.view().tx_remaining_calls, 2);
    core.disarm(wstx_rust::transmit::service::DisarmCause::Operator);
    core.arm(revision).unwrap();
    assert_eq!(
        core.view().tx_remaining_calls,
        2,
        "an operator arm starts at 0"
    );
    assert_eq!(core.view().arm_state, ArmState::Armed);
}

// ------------------------------------------------------------------ operator actions
async fn mcp_contact(f: &Mcp, action: &str, extra: Value) -> Value {
    let revision = f.read("contact").await["contact_revision"]
        .as_u64()
        .unwrap();
    f.tool(
        "wstx_contact_command",
        json!({"command":f.command(revision, action, extra)}),
    )
    .await
}
/// A browser (human) action that sets the Tx watchdog to `calls` unanswered calls.
async fn browser_watchdog(f: &Mcp, calls: u64) {
    let c = f.browser("GET", "/contact", None).await.json;
    let body = f.command(
        c["contact_revision"].as_u64().unwrap(),
        "set_watchdogs",
        json!({"tx_calls":calls,"tune_seconds":90}),
    );
    let r = f.browser("POST", "/contact/command", Some(body)).await;
    assert_eq!(r.status, StatusCode::ACCEPTED, "{}", r.json);
}

// Proves: TC-039-005
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_005_only_a_browser_action_counts_for_the_watchdog() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let service = &f.state.recording.transmit.get().unwrap().service;
    let armed = || service.view().arm_state == wstx_rust::transmit::service::ArmState::Armed;
    let spent = || service.with(|c| c.watchdog_spent());
    // No browser action since boot: an MCP Enable Tx is refused.
    let v = mcp_contact(&f, "enable_tx", json!({"enabled":true,"safety_revision":3})).await;
    assert_eq!(
        (v["status"].clone(), v["result"]["error"]["code"].clone()),
        (json!(409), json!("tx_watchdog")),
        "{v}"
    );
    assert!(!armed());
    // (1) Limit 1 from the browser; an MCP Enable Tx calls CQ, which is Rep 1.
    browser_watchdog(&f, 1).await;
    assert!(!spent());
    let v = mcp_contact(&f, "enable_tx", json!({"enabled":true,"safety_revision":3})).await;
    assert_eq!(v["status"], 202, "{v}");
    transmit_own_period(&f, e + 15_000).await;
    assert!(!spent(), "only a stop spends it");
    // MCP commands never restart it, and MCP may not lengthen it.
    let v = mcp_contact(&f, "set_frequency", json!({"rx_hz":1200,"tx_hz":null})).await;
    assert_eq!(v["status"], 202, "{v}");
    let v = mcp_contact(
        &f,
        "set_watchdogs",
        json!({"tx_calls":99,"tune_seconds":90}),
    )
    .await;
    assert_eq!(v["result"]["error"]["code"], "operator_required", "{v}");
    // The next CQ is never keyed; a later MCP Enable Tx is refused.
    let keys = f.keys();
    not_keyed_in(&f, e + 45_000).await;
    assert_eq!(f.keys(), keys);
    assert!(spent());
    // A station calling me after the stop is no human: the watchdog stays spent.
    publish(&f, e + 30_000, &[("HB9BLA DL1XYZ JO62", 900.0, Some(-7.0))]);
    assert!(spent(), "an answer after the stop does not re-open arming");
    let v = mcp_contact(&f, "enable_tx", json!({"enabled":true,"safety_revision":3})).await;
    assert_eq!(v["result"]["error"]["code"], "tx_watchdog", "{v}");
    assert!(!armed());
    // (2) An MCP run start is no operator action either: it stops tx_watchdog unarmed.
    let auto = |action: &str, extra: Value| {
        let mut b = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),"action":action});
        b.as_object_mut()
            .unwrap()
            .extend(extra.as_object().unwrap().clone());
        json!({ "command": b })
    };
    let _ = mcp_contact(&f, "cancel", json!({})).await;
    let a = f.read("automation").await;
    let cfg = crate::automation_tests::config_json();
    let c = f
        .tool(
            "wstx_automation_command",
            auto(
                "configure",
                json!({"expected_policy_revision":a["policy_revision"],"configuration":cfg}),
            ),
        )
        .await;
    assert_eq!(c["status"], 202, "{c}");
    let a = f.read("automation").await;
    let s = f
        .tool(
            "wstx_automation_command",
            auto("start", json!({"expected_policy_revision":a["policy_revision"],"expected_run_revision":a["run_revision"],"mode":"ft8","safety_revision":3})),
        )
        .await;
    assert_eq!(s["status"], 202, "{s}");
    publish(&f, e + 60_000, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("tx_watchdog")),
        "the MCP start is no operator action"
    );
    assert!(!armed());
    assert_eq!(f.keys(), keys);
    // (3) Another browser request ends nothing; a browser Enable Tx does: MCP may arm again.
    browser_watchdog(&f, 1).await;
    assert!(spent());
    let c = f.browser("GET", "/contact", None).await.json;
    let body = f.command(
        c["contact_revision"].as_u64().unwrap(),
        "enable_tx",
        json!({"enabled":true,"safety_revision":3}),
    );
    let r = f.browser("POST", "/contact/command", Some(body)).await;
    assert_eq!(r.status, StatusCode::ACCEPTED, "{}", r.json);
    assert!(!spent());
    let v = mcp_contact(&f, "enable_tx", json!({"enabled":true,"safety_revision":3})).await;
    assert_eq!(v["status"], 202, "{v}");
    assert!(armed());
}

// ------------------------------------------------------------------ #42 ignore lists
// Proves: TC-042-002 (WstxStrategy::IgnoreLists; the expected tiers, reasons, expiries
// and selections are written here from the contract, not evaluator output).
#[test]
fn tc_042_002_ignore_configuration_is_exact() {
    let mut c = config(Some("Test calls"));
    c["ignore_calls"] = json!(["K1ABC", "VK2ABC/P"]);
    c["session_ignore_minutes"] = json!(720);
    let ok = parse_config(&c).unwrap();
    assert_eq!(
        (ok.ignore_calls.clone(), ok.session_ignore_minutes),
        (vec!["K1ABC".to_owned(), "VK2ABC/P".to_owned()], 720)
    );
    assert_eq!(ok.json(), c, "round trip keeps both keys");
    let calls_101: Vec<String> = (0..101).map(|i| format!("K{i}ABC")).collect();
    for (key, value, field) in [
        ("ignore_calls", json!(["K1ABC", "K1ABC"]), "ignore_calls[1]"),
        ("ignore_calls", json!(["k1abc"]), "ignore_calls[0]"),
        ("ignore_calls", json!(["K1ABCDEFGHIJKL"]), "ignore_calls[0]"),
        ("ignore_calls", json!([""]), "ignore_calls[0]"),
        ("ignore_calls", json!(calls_101), "ignore_calls"),
        ("ignore_calls", json!("K1ABC"), "ignore_calls"),
        ("session_ignore_minutes", json!(0), "session_ignore_minutes"),
        (
            "session_ignore_minutes",
            json!(721),
            "session_ignore_minutes",
        ),
        (
            "session_ignore_minutes",
            json!(1.5),
            "session_ignore_minutes",
        ),
    ] {
        let mut bad = c.clone();
        bad[key] = value.clone();
        assert_eq!(parse_config(&bad), Err(field.to_owned()), "{key}={value}");
    }
    let mut missing = c.clone();
    missing.as_object_mut().unwrap().remove("ignore_calls");
    assert_eq!(
        parse_config(&missing),
        Err("configuration".to_owned()),
        "a PUT names both keys"
    );
    let mut empty = c.clone();
    empty["ignore_calls"] = json!([]);
    empty["session_ignore_minutes"] = json!(1);
    assert!(parse_config(&empty).is_ok(), "an empty list, one minute");
}

// Proves: TC-042-002
#[test]
fn tc_042_002_ignored_senders_never_match() {
    let records = rows(&[
        ("CQ K1ABC FN42", Some(-12.0)),      // 0
        ("CQ DL1XYZ JO62", Some(-3.0)),      // 1
        ("CQ NA W1AW FN31", Some(-5.0)),     // 2 greyed for EU unless ignored
        ("HB9BLA VK2ABC QF56", Some(-20.0)), // 3 calls me (no CQ)
    ]);
    let s = award(&[Goal::NewCall]);
    let mut st = me();
    assert_eq!(
        ranks(&s, &records, &st),
        vec![
            (0, Some(2), false),
            (1, Some(1), false),
            (2, None, true),
            (3, Some(0), false)
        ]
    );
    st.ignored.insert("K1ABC".into(), Tier::Permanent);
    st.ignored.insert("W1AW".into(), Tier::Session);
    let v = evaluate(&s, &records, &st);
    let why = |seq: u64| {
        v.iter()
            .find(|v| v.facts.sequence == seq)
            .unwrap()
            .why
            .clone()
    };
    assert_eq!(
        ranks(&s, &records, &st),
        vec![
            (0, None, false),
            (1, Some(1), false),
            (2, None, false),
            (3, Some(0), false)
        ]
    );
    assert_eq!(why(0), "K1ABC is ignored (permanent list)");
    assert_eq!(why(2), "W1AW is ignored (session list)");
    // A caller that is ignored is no caller.
    st.ignored.insert("VK2ABC".into(), Tier::Session);
    assert_eq!(ranks(&s, &records, &st)[3], (3, None, false));
    // Exact calls, not prefixes.
    let mut prefix = me();
    prefix.ignored.insert("K1".into(), Tier::Permanent);
    assert!(ranks(&s, &records, &prefix)[0].1.is_some());
}

// Proves: TC-042-002
#[test]
fn tc_042_002_session_list_expiry_renewal_capacity_and_band_change() {
    let t0 = std::time::Instant::now();
    let min = std::time::Duration::from_secs(60);
    let mut l = Session::default();
    l.observe_band(Some("40m"));
    l.add("K1ABC", Some("40m"), 2, t0);
    l.add("DL1XYZ", Some("40m"), 30, t0 + min);
    assert_eq!(
        l.entries(t0),
        vec![
            ("K1ABC".to_owned(), Some("40m".to_owned()), 120),
            ("DL1XYZ".to_owned(), Some("40m".to_owned()), 1860)
        ]
    );
    // Remaining seconds rounded up; the entry ends exactly at its expiry.
    let just = t0 + std::time::Duration::from_millis(119_001);
    assert_eq!(l.entries(just)[0].2, 1);
    assert_eq!(
        l.entries(t0 + 2 * min)
            .into_iter()
            .map(|e| e.0)
            .collect::<Vec<_>>(),
        vec!["DL1XYZ".to_owned()],
        "K1ABC ended at added + 2 min"
    );
    // Renewal moves a call last with a new expiry.
    l.add("K1ABC", Some("40m"), 5, t0 + 2 * min);
    l.add("DL1XYZ", Some("40m"), 1, t0 + 3 * min);
    assert_eq!(
        l.entries(t0 + 3 * min),
        vec![
            ("K1ABC".to_owned(), Some("40m".to_owned()), 240),
            ("DL1XYZ".to_owned(), Some("40m".to_owned()), 60)
        ]
    );
    l.remove("K1ABC");
    l.remove("NOT1LISTED");
    assert_eq!(l.entries(t0 + 3 * min).len(), 1);
    // The same band keeps the list; another band (or an unknown one) empties it.
    l.observe_band(Some("40m"));
    assert_eq!(l.entries(t0 + 3 * min).len(), 1);
    l.observe_band(Some("20m"));
    assert!(l.entries(t0 + 3 * min).is_empty(), "band change clears");
    l.add("K1ABC", Some("20m"), 30, t0);
    l.observe_band(None);
    assert!(l.entries(t0).is_empty(), "band unknown is a change");
    l.add("K1ABC", None, 30, t0);
    l.observe_band(None);
    assert_eq!(l.entries(t0).len(), 1, "still unknown: no change");
    // At most 64 entries: the 65th add drops the oldest.
    let mut full = Session::default();
    for i in 0..65 {
        full.add(&format!("K{i}AA"), Some("40m"), 30, t0);
    }
    let e = full.entries(t0);
    assert_eq!(
        (e.len(), e[0].0.as_str(), e[63].0.as_str()),
        (64, "K1AA", "K64AA")
    );
}

async fn ignore(f: &Mcp, call: Value, on: Value) -> crate::mcp_tests::Reply {
    f.browser(
        "POST",
        "/strategy/ignore",
        Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"call":call,"ignore":on})),
    )
    .await
}

// Proves: TC-042-002
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_042_002_ignore_route_store_and_band_change() {
    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.tick();
    // A configuration saved before #42 reads with an empty list and 30 minutes.
    let legacy = json!({"continent":null,"active":null,"highlight":true,"strategies":[]});
    std::fs::write(
        f.dir.join(FILE_NAME),
        serde_json::to_vec(
            &json!({"schema_version":1,"profile_id":f.id,"revision":3,"configuration":legacy}),
        )
        .unwrap(),
    )
    .unwrap();
    let old = Owner::default().snapshot(&f.state);
    assert_eq!(
        (
            old["revision"].clone(),
            old["configuration"]["ignore_calls"].clone(),
            old["configuration"]["session_ignore_minutes"].clone(),
            old["configuration_error"].clone()
        ),
        (json!(3), json!([]), json!(30), Value::Null)
    );
    let mut one = legacy.clone();
    one["ignore_calls"] = json!([]);
    std::fs::write(
        f.dir.join(FILE_NAME),
        serde_json::to_vec(
            &json!({"schema_version":1,"profile_id":f.id,"revision":3,"configuration":one}),
        )
        .unwrap(),
    )
    .unwrap();
    let half = Owner::default().snapshot(&f.state);
    assert_eq!(
        (
            half["configuration"].clone(),
            half["configuration_error"].clone()
        ),
        (Value::Null, json!("invalid_configuration"))
    );
    std::fs::remove_file(f.dir.join(FILE_NAME)).unwrap();

    let g = f.browser("GET", "/strategy", None).await;
    assert_eq!(
        (
            g.json["configuration"]["ignore_calls"].clone(),
            g.json["configuration"]["session_ignore_minutes"].clone(),
            g.json["session_ignore"].clone()
        ),
        (json!([]), json!(30), json!([])),
        "default: empty lists, 30 minutes"
    );
    let r = ignore(&f, json!("K1ABC"), json!(true)).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);
    assert_eq!(
        (r.json["revision"].clone(), r.json["session_ignore"].clone()),
        (
            json!(0),
            json!([{"call":"K1ABC","band":"40m","remaining_s":1800}])
        ),
        "the session list changes no revision"
    );
    for (body, status, code, field) in [
        (
            json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"call":"K1ABC","ignore":true,"x":1}),
            400,
            "invalid_request",
            Value::Null,
        ),
        (
            json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"call":"k1abc","ignore":true}),
            400,
            "invalid_request",
            json!("call"),
        ),
        (
            json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"call":"K1ABC","ignore":"yes"}),
            400,
            "invalid_request",
            json!("ignore"),
        ),
        (
            json!({"v":2,"profile_id":f.id,"boot_id":f.boot,"call":"K1ABC","ignore":true}),
            400,
            "unsupported_version",
            json!("v"),
        ),
        (
            json!({"v":1,"profile_id":profile::new_uuid().unwrap(),"boot_id":f.boot,"call":"K1ABC","ignore":true}),
            403,
            "wrong_profile",
            json!("profile_id"),
        ),
        (
            json!({"v":1,"profile_id":f.id,"boot_id":profile::new_uuid().unwrap(),"call":"K1ABC","ignore":true}),
            409,
            "state_conflict",
            json!("boot_id"),
        ),
    ] {
        let r = f.browser("POST", "/strategy/ignore", Some(body)).await;
        assert_eq!(
            (
                r.status.as_u16(),
                r.json["error"]["code"].clone(),
                r.json["error"]["field"].clone()
            ),
            (status, json!(code), field)
        );
    }
    let foreign = f
        .http(
            "POST",
            "/strategy/ignore",
            &[
                ("origin", "https://evil.example".into()),
                ("cookie", f.cookie()),
                ("content-type", "application/json".into()),
            ],
            Some(b"{}".to_vec()),
        )
        .await;
    assert_eq!(foreign.status, StatusCode::FORBIDDEN);
    // The permanent list and the session minutes are saved with PUT /strategy.
    let mut c = config(Some("Test calls"));
    c["ignore_calls"] = json!(["DL1XYZ"]);
    c["session_ignore_minutes"] = json!(5);
    save(&f, c.clone()).await;
    let r = ignore(&f, json!("W1AW"), json!(true)).await;
    assert_eq!(
        r.json["session_ignore"],
        json!([{"call":"K1ABC","band":"40m","remaining_s":1800},{"call":"W1AW","band":"40m","remaining_s":300}])
    );
    let r = ignore(&f, json!("K1ABC"), json!(false)).await;
    assert_eq!(
        r.json["session_ignore"],
        json!([{"call":"W1AW","band":"40m","remaining_s":300}])
    );
    // Evaluation sees both tiers.
    // The unranked rows are in sequence order here also by SNR (W1AW -1, DL1XYZ -3).
    let (source, job, generation) = f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    publish(
        &f,
        e,
        &[
            ("CQ K1ABC FN42", 1500.0, Some(-12.0)),
            ("CQ W1AW FN31", 900.0, Some(-1.0)),
            ("CQ DL1XYZ JO62", 1200.0, Some(-3.0)),
        ],
    );
    let body = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"source_id":source,"job_id":job,
        "generation":generation,"first_sequence":0,"next_sequence":3,"strategy":null,"explain":true});
    let v = f
        .browser("POST", "/strategy/evaluate", Some(body.clone()))
        .await;
    assert_eq!(
        v.json["verdicts"],
        json!([{"sequence":0,"rank":0,"grey":false,"why":"needed: new_call"},
            {"sequence":1,"rank":null,"grey":false,"why":"W1AW is ignored (session list)"},
            {"sequence":2,"rank":null,"grey":false,"why":"DL1XYZ is ignored (permanent list)"}])
    );
    // The station step on another band empties the session list.
    f.state.recording.fixture_band("20m");
    f.tick();
    let g = f.browser("GET", "/strategy", None).await;
    assert_eq!(g.json["session_ignore"], json!([]));
    let v = f.browser("POST", "/strategy/evaluate", Some(body)).await;
    assert_eq!(
        v.json["verdicts"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| (v["sequence"].clone(), v["why"].clone()))
            .collect::<Vec<_>>(),
        vec![
            (json!(1), json!("needed: new_call")),
            (json!(0), json!("needed: new_call")),
            (json!(2), json!("DL1XYZ is ignored (permanent list)"))
        ],
        "W1AW is no longer ignored on 20m; the permanent list stays"
    );
    assert_eq!(f.keys(), 0, "ignore lists never key");
}

// Proves: TC-042-002
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_042_002_a_run_never_selects_an_ignored_station() {
    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let mut c = config(Some("Test calls"));
    c["ignore_calls"] = json!(["K1ABC"]);
    select(&f, c).await;
    assert_eq!(
        ignore(&f, json!("W1AW"), json!(true)).await.status,
        StatusCode::OK
    );
    // K1ABC (permanent) and W1AW (session) would rank first (strongest).
    publish(
        &f,
        e,
        &[
            ("CQ K1ABC FN42", 1500.0, Some(9.0)),
            ("CQ W1AW FN31", 900.0, Some(5.0)),
            ("CQ DL1XYZ JO62", 1200.0, Some(-10.0)),
        ],
    );
    assert_eq!(
        contact(&f).await,
        (json!("DL1XYZ"), json!("replying"), json!("armed"))
    );
    let run = f.read("automation").await["run"].clone();
    assert_eq!(run["last_decision"]["candidates"], json!(1));
    assert_eq!(f.keys(), 0);
}

// Proves: TC-042-002
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_042_002_a_run_never_answers_an_ignored_caller() {
    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("Test calls"))).await;
    assert_eq!(
        ignore(&f, json!("K1ABC"), json!(true)).await.status,
        StatusCode::OK
    );
    publish(
        &f,
        e,
        &[
            ("HB9BLA K1ABC FN42", 1500.0, Some(9.0)),
            ("HB9BLA DL1XYZ JO62", 1200.0, Some(-10.0)),
        ],
    );
    assert_eq!(
        contact(&f).await,
        (json!("DL1XYZ"), json!("report"), json!("armed"))
    );
    let run = f.read("automation").await["run"].clone();
    assert_eq!(run["last_decision"]["candidates"], json!(1));
    assert_eq!(f.keys(), 0);
}

// ------------------------------------------------------------------ #42 Pounce
/// The browser's Pounce configuration (WstxStrategy::Pounce) with these unanswered periods.
fn pounce_json(call: Value, unanswered: u64) -> Value {
    json!({"modes":["ft8"],"ranking":"first_seen","min_snr_db":null,"allowed_calls":[],"blocked_calls":[],
        "max_contacts":1,"max_unanswered_periods":unanswered,"completion_action":"stop","max_run_minutes":480,
        "strategy":false,"pounce":call})
}
/// Configure and start a plain policy run from the browser.
async fn plain_run(f: &Mcp) -> crate::mcp_tests::Reply {
    let c = configure_run(f, crate::automation_tests::config_json()).await;
    assert_eq!(c.status, StatusCode::ACCEPTED, "{}", c.json);
    start_run(f).await
}
async fn configure_run(f: &Mcp, cfg: Value) -> crate::mcp_tests::Reply {
    let a = f.browser("GET", "/automation", None).await.json;
    f.browser("POST", "/automation/command", Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,
        "command_id":profile::new_uuid().unwrap(),"action":"configure","expected_policy_revision":a["policy_revision"],"configuration":cfg}))).await
}
async fn start_run(f: &Mcp) -> crate::mcp_tests::Reply {
    let a = f.browser("GET", "/automation", None).await.json;
    let safety = f.read("contact").await["transmit"]["safety_revision"].clone();
    f.browser("POST", "/automation/command", Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,
        "command_id":profile::new_uuid().unwrap(),"action":"start","expected_policy_revision":a["policy_revision"],
        "expected_run_revision":a["run_revision"],"mode":"ft8","safety_revision":safety}))).await
}
/// Configure and start a pounce from the browser (cookie grant), as Band Activity does.
async fn pounce(f: &Mcp, call: &str, unanswered: u64) -> crate::mcp_tests::Reply {
    let c = configure_run(f, pounce_json(json!(call), unanswered)).await;
    assert_eq!(c.status, StatusCode::ACCEPTED, "{}", c.json);
    start_run(f).await
}
fn last_text(f: &Mcp) -> Option<String> {
    f.state
        .recording
        .transmit
        .get()
        .unwrap()
        .service
        .view()
        .last_text
}

// Proves: TC-042-004 (WstxStrategy::Pounce, WstxMcp::AutomationConfiguration pounce key)
#[test]
fn tc_042_004_pounce_configuration_is_exact() {
    use crate::automation::parse_config as automation_config;
    let mut absent = pounce_json(Value::Null, 5);
    absent.as_object_mut().unwrap().remove("pounce");
    assert_eq!(automation_config(&absent).unwrap().unwrap().pounce, None);
    assert_eq!(
        automation_config(&pounce_json(Value::Null, 5))
            .unwrap()
            .unwrap()
            .pounce,
        None
    );
    let ok = automation_config(&pounce_json(json!("K1ABC"), 5))
        .unwrap()
        .unwrap();
    assert_eq!(ok.pounce.as_deref(), Some("K1ABC"));
    assert_eq!(
        ok.json()["pounce"],
        json!("K1ABC"),
        "the snapshot shows pounce"
    );
    assert_eq!(
        automation_config(&absent).unwrap().unwrap().json()["pounce"],
        Value::Null
    );
    for bad in [json!("k1abc"), json!("K1"), json!("K1ABC/R"), json!(7)] {
        assert_eq!(
            automation_config(&pounce_json(bad.clone(), 5)),
            Err(("invalid_request", Some("pounce"))),
            "{bad}"
        );
    }
    let mut with_strategy = pounce_json(json!("K1ABC"), 5);
    with_strategy["strategy"] = json!(true);
    assert_eq!(
        automation_config(&with_strategy),
        Err(("operator_required", Some("strategy")))
    );
    let mut blocked = pounce_json(json!("K1ABC"), 5);
    blocked["blocked_calls"] = json!(["K1ABC"]);
    assert_eq!(
        automation_config(&blocked),
        Err(("invalid_request", Some("pounce")))
    );
}

// Proves: TC-042-004
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_042_004_pounce_answers_the_chosen_call_in_the_next_own_period_and_ends_on_success() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    // No known station band: a pounce cannot say where it waits.
    let r = pounce(&f, "K1ABC", 5).await;
    assert_eq!(
        (
            r.json["error"]["code"].clone(),
            r.json["error"]["field"].clone()
        ),
        (json!("not_ready"), json!("band")),
        "{}",
        r.json
    );
    f.state.recording.fixture_band("40m");
    let r = pounce(&f, "K1ABC", 5).await;
    assert_eq!(r.status, StatusCode::ACCEPTED, "{}", r.json);
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (run["state"].clone(), run["pounce"].clone()),
        (json!("waiting"), json!({"call":"K1ABC","band":"40m"}))
    );
    // One run at a time: no Auto or second pounce beside it.
    let again = configure_run(&f, pounce_json(json!("W1AW"), 5)).await;
    assert_eq!(
        (again.status.as_u16(), again.json["error"]["field"].clone()),
        (409, json!("run"))
    );
    assert_eq!(
        start_run(&f).await.json["error"]["field"],
        json!("run"),
        "a second start is state_conflict run"
    );
    // Other calls are never answered, whatever they send.
    publish(
        &f,
        e - 30_000,
        &[
            ("CQ W1AW FN31", 900.0, Some(5.0)),
            ("CQ DL1XYZ JO62", 1200.0, Some(0.0)),
        ],
    );
    assert_eq!(f.read("contact").await["contact"], Value::Null);
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (
            run["state"].clone(),
            run["last_decision"]["candidates"].clone()
        ),
        (json!("waiting"), json!(0))
    );
    // The chosen call's CQ is answered as a double-click: select, Enable Tx.
    publish(
        &f,
        e,
        &[
            ("CQ DL1XYZ JO62", 1200.0, Some(0.0)),
            ("CQ K1ABC FN42", 1500.0, Some(-15.0)),
        ],
    );
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["contact"]["dx_call"].clone(),
            c["contact"]["state"].clone(),
            c["contact"]["messages"][0].clone(),
            c["settings"]["parity"].clone(),
            c["transmit"]["arm_state"].clone()
        ),
        (
            json!("K1ABC"),
            json!("replying"),
            json!("K1ABC HB9BLA JN47"),
            json!("odd"),
            json!("armed")
        ),
        "{c}"
    );
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (run["state"].clone(), run["selected"]["call"].clone()),
        (json!("contact_active"), json!("K1ABC"))
    );
    // The next own period calls K1ABC.
    transmit_own_period(&f, e + 15_000).await;
    assert_eq!(last_text(&f).as_deref(), Some("K1ABC HB9BLA JN47"));
    // Auto Seq runs the QSO; its completion ends the pounce.
    publish(&f, e + 30_000, &[("HB9BLA K1ABC -05", 1505.0, Some(-6.0))]);
    publish(&f, e + 60_000, &[("HB9BLA K1ABC RR73", 1505.0, Some(-6.0))]);
    transmit_own_period(&f, e + 45_000).await;
    assert_eq!(last_text(&f).as_deref(), Some("K1ABC HB9BLA 73"));
    assert_eq!(contact(&f).await.1, json!("completed"));
    f.tick();
    assert_eq!(run_state(&f).await, ("stopped".into(), json!("completed")));
    // A later CQ of K1ABC is not answered: the pounce is over.
    publish(&f, e + 90_000, &[("CQ K1ABC FN42", 1500.0, Some(-15.0))]);
    assert_eq!(contact(&f).await.2, json!("disarmed"));
}

// Proves: TC-042-004
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_042_004_pounce_answers_a_73_holding_tx_and_never_an_ignored_or_directed_cq() {
    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    assert_eq!(
        ignore(&f, json!("K1ABC"), json!(true)).await.status,
        StatusCode::OK
    );
    // Hold Tx off: "after a 73 Tx stays on its free slot" below is the automation's own rule, not the default.
    mcp_contact(&f, "set_hold_tx", json!({"enabled":false})).await;
    assert_eq!(f.read("contact").await["settings"]["hold_tx"], json!(false));
    assert_eq!(pounce(&f, "K1ABC", 5).await.status, StatusCode::ACCEPTED);
    // The ignore lists win over the pounce.
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-15.0))]);
    assert_eq!(f.read("contact").await["contact"], Value::Null);
    assert_eq!(
        ignore(&f, json!("K1ABC"), json!(false)).await.status,
        StatusCode::OK
    );
    // CQ NA is not for my continent (EU): never answered (DirectedCqRule).
    publish(&f, e + 30_000, &[("CQ NA K1ABC FN42", 1500.0, Some(-15.0))]);
    assert_eq!(f.read("contact").await["contact"], Value::Null);
    assert_eq!(run_state(&f).await, ("waiting".into(), Value::Null));
    // K1ABC ends its QSO with W1AW: answered, my Tx frequency held (TC-039-010: a pounce
    // takes the free slot, and Hold Tx off moved Tx to the station).
    let tx = f.read("contact").await["settings"]["tx_hz"].clone();
    publish(&f, e + 60_000, &[("W1AW K1ABC RR73", 1700.0, Some(-9.0))]);
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["contact"]["dx_call"].clone(),
            c["contact"]["messages"][0].clone(),
            c["transmit"]["arm_state"].clone(),
            c["settings"]["tx_hz"].clone(),
            c["settings"]["rx_hz"].clone()
        ),
        (
            json!("K1ABC"),
            json!("K1ABC HB9BLA JN47"),
            json!("armed"),
            tx.clone(),
            tx
        ),
        "after a 73 Tx stays on its slot, and Rx = Tx"
    );
    assert_eq!(f.keys(), 0);
}

// Proves: TC-042-004
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_042_004_pounce_waits_again_without_an_answer_and_ends_on_a_band_change() {
    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    assert_eq!(pounce(&f, "K1ABC", 2).await.status, StatusCode::ACCEPTED);
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-15.0))]);
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
    // Two partner periods without an answer: the contact ends, the pounce stays.
    publish(&f, e + 30_000, &[]);
    publish(&f, e + 60_000, &[]);
    let c = f.read("contact").await;
    assert_eq!(c["transmit"]["arm_state"], json!("disarmed"));
    assert!(
        c["contact"].is_null() || c["contact"]["state"] == json!("cancelled"),
        "{c}"
    );
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (
            run["state"].clone(),
            run["reason"].clone(),
            run["pounce"]["call"].clone()
        ),
        (json!("waiting"), Value::Null, json!("K1ABC"))
    );
    // It answers K1ABC's next CQ again.
    publish(&f, e + 90_000, &[("CQ K1ABC FN42", 1500.0, Some(-15.0))]);
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
    // A band change ends the pounce and disarms its contact.
    f.state.recording.fixture_band("20m");
    f.tick();
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("band_changed"))
    );
    assert_eq!(contact(&f).await.2, json!("disarmed"));
    // A waiting pounce ends the same way (the operator first clears the left contact).
    let revision = f.read("contact").await["contact_revision"].clone();
    let cancel = f
        .browser(
            "POST",
            "/contact/command",
            Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,
        "command_id":profile::new_uuid().unwrap(),"contact_revision":revision,"action":"cancel"})),
        )
        .await;
    assert_eq!(cancel.status, StatusCode::ACCEPTED, "{}", cancel.json);
    assert_eq!(pounce(&f, "K1ABC", 2).await.status, StatusCode::ACCEPTED);
    f.state.recording.fixture_band("40m");
    f.tick();
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("band_changed"))
    );
    assert_eq!(f.keys(), 0);
}

// Proves: CL-024-01; TC-024-003 (g) (#24 S1b). Station automation stays standard-only: a
// run does not start with a nonstandard profile callsign.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn automation_does_not_start_with_a_nonstandard_own_call() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let code = |r: &crate::mcp_tests::Reply| {
        (
            r.json["error"]["code"].clone(),
            r.json["error"]["field"].clone(),
        )
    };
    f.state.store.lock().unwrap().document.callsign = "DL/HB9BLA".into();
    assert_eq!(
        code(&plain_run(&f).await),
        (json!("not_ready"), json!("call"))
    );
    // A strategy waits with the reason instead of being refused.
    select(&f, config(Some("Test calls"))).await;
    f.tick();
    assert_eq!(run_state(&f).await, ("waiting".into(), json!("call")));
    save(&f, config(None)).await;
    f.state.store.lock().unwrap().document.callsign = "HB9BLA".into();
    let started = plain_run(&f).await;
    assert_eq!(started.status, StatusCode::ACCEPTED, "{}", started.json);
}

// Proves: CL-024-02; TC-024-005 (e) (#24 S2a). Station automation only observes in a contest
// activity: a run does not start.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn automation_does_not_start_in_a_contest_activity() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let contact = f.state.recording.contact.get().unwrap();
    let body = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),
        "contact_revision":contact.revision(),"action":"set_activity","activity":"ww_digi"});
    contact.operate(&f.state, body, true).unwrap();
    let r = plain_run(&f).await;
    assert_eq!(
        (
            r.json["error"]["code"].clone(),
            r.json["error"]["field"].clone()
        ),
        (json!("not_ready"), json!("activity"))
    );
    select(&f, config(Some("Test calls"))).await;
    f.tick();
    assert_eq!(run_state(&f).await, ("waiting".into(), json!("activity")));
}

// Proves: CL-024-04; TC-024-012 (#24 S4b). Station automation does not start as a Hound.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn automation_does_not_start_as_a_hound() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let contact = f.state.recording.contact.get().unwrap();
    let body = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),
        "contact_revision":contact.revision(),"action":"set_activity","activity":"hound"});
    contact.operate(&f.state, body, true).unwrap();
    let r = plain_run(&f).await;
    assert_eq!(
        (
            r.json["error"]["code"].clone(),
            r.json["error"]["field"].clone()
        ),
        (json!("not_ready"), json!("activity"))
    );
    select(&f, config(Some("Test calls"))).await;
    f.tick();
    assert_eq!(run_state(&f).await, ("waiting".into(), json!("activity")));
}

// ------------------------------------------------------------------ #42 Alert
/// The strategy "Alerts": rule 1 (call prefix K, no alert), rule 2 (any CQ, alert).
fn alerts_strategy() -> Value {
    json!({"name":"Alerts","class":"award","goals":["new_call"],"needed":"not_worked","region":{"kind":"all"},
        "min_snr_db":null,"value":["most_wanted"],"callers_first":true,"cq_when_no_target":false,
        "repetitions":2,"quiet_minutes":10,"treat_73_as_cq":false,"window":{"kind":"all"}})
}

async fn alerts(f: &Mcp) -> Value {
    let g = f.browser("GET", "/strategy/alerts", None).await;
    assert_eq!(g.status, StatusCode::OK, "{}", g.json);
    g.json
}
fn calls_of(v: &Value) -> Vec<String> {
    v["alerts"]
        .as_array()
        .unwrap()
        .iter()
        .map(|a| a["call"].as_str().unwrap().to_owned())
        .collect()
}

// Proves: TC-042-006
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_042_006_alert_records_one_alert_per_call_and_band_and_never_transmits() {
    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let empty = alerts(&f).await;
    assert_eq!(
        empty,
        json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"revision":0,"alerts":[]})
    );
    // Before a strategy is active: the cursor passes JA1XYZ, which never alerts later.
    publish(&f, e, &[("CQ JA1XYZ PM95", 1100.0, Some(-15.0))]);
    let mut c = config(Some("Alerts"));
    c["strategies"] = json!([alerts_strategy()]);
    // The store only: this test is about alerts, and a selection's run would transmit.
    store_only(&f, c);
    assert_eq!(
        ignore(&f, json!("G4ABC"), json!(true)).await.status,
        StatusCode::OK
    );
    let p1 = e + 30_000;
    publish(
        &f,
        p1,
        &[
            ("CQ K1ABC FN42", 1500.0, Some(-12.0)),
            ("CQ DL1XYZ JO62", 1200.0, Some(-3.0)),
            ("CQ NA W1AW FN31", 900.0, Some(-5.0)),
            ("CQ G4ABC IO91", 700.0, Some(-8.0)),
            ("HB9BLA VK2ABC QF56", 1800.0, Some(-20.0)),
        ],
    );
    let utc = period_text(p1);
    let a = alerts(&f).await;
    assert_eq!(
        a,
        json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"revision":2,"alerts":[
            {"id":1,"utc":utc,"call":"K1ABC","message":"CQ K1ABC FN42","rule":"Alerts",
                "band":"40m","mode":"ft8","snr_db":-12.0,"dxcc":"United States"},
            {"id":2,"utc":utc,"call":"DL1XYZ","message":"CQ DL1XYZ JO62","rule":"Alerts",
                "band":"40m","mode":"ft8","snr_db":-3.0,"dxcc":"Fed. Rep. of Germany"}]})
    );
    // Dedupe: K1ABC 30 s later is no new alert; exactly 10 minutes after the first it is.
    publish(&f, p1 + 30_000, &[("CQ K1ABC FN42", 1500.0, Some(-11.0))]);
    assert_eq!(alerts(&f).await["revision"], 2);
    publish(&f, p1 + 600_000, &[("CQ K1ABC FN42", 1500.0, Some(-10.0))]);
    let a = alerts(&f).await;
    assert_eq!(
        (
            a["revision"].clone(),
            a["alerts"][2]["id"].clone(),
            a["alerts"][2]["snr_db"].clone()
        ),
        (json!(3), json!(3), json!(-10.0))
    );
    // Another band is another dedupe key.
    f.state.recording.fixture_band("20m");
    f.tick();
    publish(&f, p1 + 630_000, &[("CQ K1ABC FN42", 1500.0, Some(-9.0))]);
    let a = alerts(&f).await;
    assert_eq!(
        (
            a["revision"].clone(),
            calls_of(&a),
            a["alerts"][3]["band"].clone()
        ),
        (
            json!(4),
            vec!["K1ABC", "DL1XYZ", "K1ABC", "K1ABC"]
                .into_iter()
                .map(String::from)
                .collect::<Vec<_>>(),
            json!("20m")
        )
    );
    // The MCP client reads exactly the browser's history; its principal may not clear.
    assert_eq!(f.read("alerts").await, a);
    let internal = crate::mcp_tests::internal_transport(&f, &f.mcp);
    let mcp_get =
        crate::mcp_tests::with_cookie(&f, "GET", "/strategy/alerts", &internal, None).await;
    assert_eq!(mcp_get.status, StatusCode::OK);
    let mcp_clear = crate::mcp_tests::with_cookie(
        &f,
        "POST",
        "/strategy/alerts/clear",
        &internal,
        Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot})),
    )
    .await;
    assert_eq!(mcp_clear.status, StatusCode::UNAUTHORIZED);
    for (body, status, code, field) in [
        (
            json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"x":1}),
            400,
            "invalid_request",
            Value::Null,
        ),
        (
            json!({"v":2,"profile_id":f.id,"boot_id":f.boot}),
            400,
            "unsupported_version",
            json!("v"),
        ),
        (
            json!({"v":1,"profile_id":profile::new_uuid().unwrap(),"boot_id":f.boot}),
            403,
            "wrong_profile",
            json!("profile_id"),
        ),
        (
            json!({"v":1,"profile_id":f.id,"boot_id":profile::new_uuid().unwrap()}),
            409,
            "state_conflict",
            json!("boot_id"),
        ),
    ] {
        let r = f
            .browser("POST", "/strategy/alerts/clear", Some(body))
            .await;
        assert_eq!(
            (
                r.status.as_u16(),
                r.json["error"]["code"].clone(),
                r.json["error"]["field"].clone()
            ),
            (status, json!(code), field)
        );
    }
    assert_eq!(alerts(&f).await, a, "refusals leave the history");
    let cleared = f
        .browser(
            "POST",
            "/strategy/alerts/clear",
            Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot})),
        )
        .await;
    assert_eq!(cleared.status, StatusCode::OK, "{}", cleared.json);
    assert_eq!(
        cleared.json,
        json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"revision":5,"alerts":[]})
    );
    // Clear keeps the dedupe memory: K1ABC on 20m one period later is still no alert.
    publish(&f, p1 + 660_000, &[("CQ K1ABC FN42", 1500.0, Some(-9.0))]);
    assert_eq!(alerts(&f).await["revision"], 5);
    // The history keeps the last 100: 101 CQs from different calls in one period.
    let calls: Vec<String> = (0..101)
        .map(|i| format!("K{}{}Q", i % 10, (b'A' + (i / 10) as u8) as char))
        .collect();
    let texts: Vec<String> = calls.iter().map(|c| format!("CQ {c} FN42")).collect();
    let list: Vec<(&str, f64, Option<f64>)> = texts
        .iter()
        .map(|t| (t.as_str(), 1000.0, Some(-10.0)))
        .collect();
    publish(&f, p1 + 690_000, &list);
    let a = alerts(&f).await;
    assert_eq!(
        (a["revision"].clone(), calls_of(&a)),
        (json!(106), calls[1..].to_vec())
    );
    assert_eq!(a["alerts"][0]["id"], 6);
    // Alerts never select, arm or key.
    let contact = f.read("contact").await;
    assert_eq!(
        (
            contact["contact"].clone(),
            contact["transmit"]["arm_state"].clone()
        ),
        (Value::Null, json!("disarmed"))
    );
    assert_eq!(f.keys(), 0);
}

// Proves: TC-063-004
#[test]
fn tc_063_004_the_directive_table_in_a_contest_activity() {
    use crate::contact::Activity as A;
    for (activity, target, expected) in [
        (A::None, "TEST", false),
        (A::NaVhf, "TEST", true),
        (A::ArrlDigi, "TEST", true),
        (A::WwDigi, "TEST", false),
        (A::WwDigi, "WW", true),
        (A::ArrlDigi, "WW", false),
        (A::FieldDay, "FD", true),
        (A::WwDigi, "FD", false),
        (A::Rtty, "RU", true),
        (A::Hound, "TEST", false),
        // The other directives keep their rule in an activity.
        (A::WwDigi, "NA", false),
        (A::WwDigi, "EU", true),
        (A::WwDigi, "POTA", false),
    ] {
        assert_eq!(
            answerable_in(activity, Some(target), Some("EU"), Some("NA")),
            expected,
            "CQ {target} in {activity:?}"
        );
    }
    assert!(answerable_in(A::WwDigi, None, Some("EU"), Some("NA")));
    // With my continent unknown a matching word still holds: it is not about me.
    assert!(answerable_in(A::WwDigi, Some("WW"), None, None));
    // The verdict follows: CQ WW is a candidate in WW Digi and greyed without it.
    let records = rows(&[("CQ WW K1ABC FN42", Some(-5.0))]);
    let s = award(&[Goal::NewCall]);
    let plain = evaluate(&s, &records, &me());
    assert_eq!((plain[0].rank, plain[0].grey), (None, true));
    let st = Station {
        activity: A::WwDigi,
        ..me()
    };
    let contest = evaluate(&s, &records, &st);
    assert_eq!((contest[0].rank, contest[0].grey), (Some(0), false));
}

// Proves: TC-063-004
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_063_004_a_selection_of_the_activitys_cq_needs_no_confirmation() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    publish(&f, e, &[("CQ WW K1ABC FN42", 1000.0, Some(-1.0))]);
    let row = live_row(&f, "CQ WW K1ABC FN42");
    let refused = f
        .browser(
            "POST",
            "/contact/command",
            Some(browser_command(&f, "select_row", json!({"row":row,"replace":false})).await),
        )
        .await;
    assert_eq!(refused.status, StatusCode::CONFLICT, "{}", refused.json);
    assert_eq!(refused.json["error"]["code"], "directive_not_answerable");
    browser_ok(&f, "set_activity", json!({"activity":"ww_digi"})).await;
    let selected = f
        .browser(
            "POST",
            "/contact/command",
            Some(browser_command(&f, "select_row", json!({"row":row,"replace":false})).await),
        )
        .await;
    assert_eq!(selected.status, StatusCode::ACCEPTED, "{}", selected.json);
    assert_eq!(contact(&f).await.0, "K1ABC");
}

// Proves: CL-099-02; TC-099-002 (g). In eu_vhf a CQ TEST is the activity's own word: the
// operator's selection needs no directive_confirmed.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_099_002_cq_test_needs_no_confirmation_in_eu_vhf() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    publish(&f, e, &[("CQ TEST K1ABC FN42", 1000.0, Some(-1.0))]);
    let row = live_row(&f, "CQ TEST K1ABC FN42");
    browser_ok(&f, "set_activity", json!({"activity":"eu_vhf"})).await;
    let selected = f
        .browser(
            "POST",
            "/contact/command",
            Some(browser_command(&f, "select_row", json!({"row":row,"replace":false})).await),
        )
        .await;
    assert_eq!(selected.status, StatusCode::ACCEPTED, "{}", selected.json);
    assert_eq!(contact(&f).await.0, "K1ABC");
}

// Proves: TC-063-003
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_063_003_the_contests_route() {
    let f = station(true).await;
    let g = f.browser("GET", "/strategy/contests", None).await;
    assert_eq!(g.status, StatusCode::OK, "{}", g.json);
    assert_eq!(g.json["v"], 1);
    assert_eq!(g.json["profile_id"], f.id.as_str());
    let list = g.json["profiles"].as_array().expect("a list");
    assert_eq!(list.len(), crate::contest::PROFILES.len());
    assert_eq!(list[0]["id"], "ww_digi");
    assert_eq!(list[0]["automation"], "forbidden");
    // The period is the rule's, at the station's clock: it has not ended.
    let end = list[0]["period"]["end"].as_str().expect("a period end");
    let end = crate::contact::parse_utc(&format!("{}:00Z", end.trim_end_matches('Z')))
        .expect("a UTC time");
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("a clock")
        .as_millis() as i64;
    assert!(end > now);
    // No credentials: 401; a query is refused; POST has no route.
    let u = f.http("GET", "/strategy/contests", &[], None).await;
    assert_eq!(u.status, StatusCode::UNAUTHORIZED);
    assert_eq!(u.json["error"]["code"], "unauthorized");
    let q = f.browser("GET", "/strategy/contests?x=1", None).await;
    assert_eq!(q.status, StatusCode::BAD_REQUEST);
    assert_eq!(q.json["error"]["code"], "invalid_request");
    assert_eq!(
        f.browser("POST", "/strategy/contests", Some(json!({})))
            .await
            .status,
        StatusCode::METHOD_NOT_ALLOWED
    );
}

// Proves: TC-063-007
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_063_007_a_contest_selection_store_and_evaluation() {
    let f = station(true).await;
    let (source, job, generation) = f.state.recording.fixture_live_job("ft8");
    f.state.recording.fixture_band("40m");
    // A QSO inside the period and one before it, from the stored log.
    let adi = "<call:5>W1DUP <gridsquare:4>EM12 <qso_date:8>20260829 <time_on:4>1300 <band:3>40m <mode:3>FT8 <eor>\n<call:5>K1OLD <gridsquare:4>FN20 <qso_date:8>20260829 <time_on:4>1130 <band:3>40m <mode:3>FT8 <eor>\n";
    let id = crate::profile::new_uuid().unwrap();
    let open = |p: &mut dyn FnMut() -> std::io::Result<()>| -> Result<std::io::Result<()>, crate::authorization::Error> { Ok(p()) };
    let sha: String = ring::digest::digest(&ring::digest::SHA256, adi.as_bytes())
        .as_ref()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    let now = std::time::Instant::now();
    let log = &f.state.logbook;
    log.reserve(&id, adi.len() as u64, &sha, now).unwrap();
    log.chunk(&id, 0, adi.len() as u64, adi.as_bytes(), now, &open)
        .unwrap();
    let e = at_even(&f);
    publish(
        &f,
        e,
        &[
            ("CQ WW W1DUP EM12", 1000.0, Some(-1.0)),
            ("CQ WW K1OLD FN20", 1100.0, Some(-2.0)),
            ("CQ WW JA1XYZ PM95", 1200.0, Some(-15.0)),
        ],
    );
    browser_ok(&f, "set_activity", json!({"activity":"ww_digi"})).await;
    let contest = json!({"profile":"ww_digi","start":"2026-08-29T12:00Z",
        "end":"2026-08-30T12:00Z","operation":"sp","repetitions":2,"quiet_minutes":10});
    let mut selected = config(None);
    selected["contest"] = contest.clone();
    let p = put(&f, json!(0), selected.clone()).await;
    assert_eq!(p.status, StatusCode::OK, "{}", p.json);
    assert_eq!(p.json["configuration"]["contest"], contest);
    // The file never holds it; a new owner reads no contest.
    let saved: Value =
        serde_json::from_slice(&std::fs::read(f.dir.join(FILE_NAME)).unwrap()).unwrap();
    assert_eq!(saved["configuration"], config(None));
    let reopened = Owner::default();
    assert!(
        reopened.snapshot(&f.state)["configuration"]
            .get("contest")
            .is_none()
    );
    // Auto off: no run starts (strategydef: a selection alone only marks).
    assert_eq!(f.read("automation").await["run"], Value::Null);
    // Refusals: a strategy and a contest at once; a bad period; a stale revision.
    let mut both = config(Some("New calls"));
    both["contest"] = contest.clone();
    let r = put(&f, json!(1), both).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
    assert_eq!(r.json["error"]["field"], "contest");
    let mut bad = selected.clone();
    bad["contest"]["end"] = json!("2026-08-29T12:00Z");
    let r = put(&f, json!(1), bad).await;
    assert_eq!(r.json["error"]["field"], "contest.end");
    // Evaluated by the contest: the dupe of the period is marked, the QSO before it is not.
    let body = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"source_id":source,"job_id":job,
        "generation":generation,"first_sequence":0,"next_sequence":3,"strategy":null,"explain":false});
    let v = f
        .browser("POST", "/strategy/evaluate", Some(body.clone()))
        .await;
    assert_eq!(v.status, StatusCode::OK, "{}", v.json);
    assert_eq!(v.json["strategy"], "WW Digi");
    assert_eq!(
        v.json["contest"],
        json!({"qsos":1,"multipliers":1,"points":3,"score":3}),
        "W1DUP only: JN47-EM12 is 8469.4 km, 3 points"
    );
    assert_eq!(
        v.json["verdicts"],
        json!([
            {"sequence":2,"rank":0,"grey":false,"dupe":false,"new_multiplier":true,"points":4},
            {"sequence":1,"rank":1,"grey":false,"dupe":false,"new_multiplier":true,"points":3},
            {"sequence":0,"rank":null,"grey":false,"dupe":true,"new_multiplier":false,"points":null}
        ])
    );
    // None ends the contest; a later evaluation has nothing to evaluate.
    let mut none = selected.clone();
    none.as_object_mut().unwrap().remove("contest");
    let r = put(&f, json!(1), none).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);
    assert!(r.json["configuration"].get("contest").is_none());
    let v = f.browser("POST", "/strategy/evaluate", Some(body)).await;
    assert_eq!(v.json["error"]["code"], "not_configured");
}

/// A contest selection around the bench's period e; `start_h` hours from e.
fn contest_config(e: i64, operation: &str, start_h: i64) -> Value {
    let hour = 3_600_000;
    let mut c = config(None);
    c["contest"] = json!({"profile":"ww_digi",
        "start":crate::contest::utc_text(e + start_h * hour),
        "end":crate::contest::utc_text(e + (start_h + 2) * hour),
        "operation":operation,"repetitions":2,"quiet_minutes":10});
    c
}
fn import_adi(f: &Mcp, adi: &str) {
    let id = crate::profile::new_uuid().unwrap();
    let open = |p: &mut dyn FnMut() -> std::io::Result<()>| -> Result<std::io::Result<()>, crate::authorization::Error> { Ok(p()) };
    let sha: String = ring::digest::digest(&ring::digest::SHA256, adi.as_bytes())
        .as_ref()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    let now = std::time::Instant::now();
    let log = &f.state.logbook;
    log.reserve(&id, adi.len() as u64, &sha, now).unwrap();
    log.chunk(&id, 0, adi.len() as u64, adi.as_bytes(), now, &open)
        .unwrap();
}
/// The QSO of `call` a minute before e, on 20m in FT8.
fn logged_before(call: &str, grid: &str, e: i64) -> String {
    format!(
        "<call:{}>{call} <gridsquare:4>{grid} <qso_date:8>{} <time_on:4>{} <band:3>20m <mode:3>FT8 <eor>\n",
        call.len(),
        crate::contact::adif_date(e - 60_000),
        &crate::contact::adif_time(e - 60_000)[..4],
    )
}

/// The shared scripted IC-7300 (cat_lifecycle_tests) on COM3, its dial on 14.074 MHz (20 m):
/// the confirmed dial from which the record of a completed QSO takes its BAND
/// (WstxContact::DirectLog) and the station its band. With it the contest tests let the
/// product log the QSO itself instead of importing the entry.
fn dial_20m(f: &Mcp) -> Arc<Mutex<crate::cat_lifecycle_tests::Peer>> {
    use crate::cat_lifecycle_tests::{Device, attach_peer};
    let r = &f.state.recording;
    let peer = attach_peer(r, Device::Present);
    peer.lock().unwrap().dial = 14_074_000;
    let revision = f.state.store.lock().unwrap().document.revision;
    r.radio_connect(
        wstx_rust::radio_control::Configuration::parse("COM3").unwrap(),
        revision,
    )
    .unwrap();
    retune(f, &peer, 14_074_000);
    peer
}
/// Turns the scripted dial to `hz` and waits until the CAT owner's poll has confirmed it.
fn retune(f: &Mcp, peer: &Mutex<crate::cat_lifecycle_tests::Peer>, hz: u64) {
    peer.lock().unwrap().dial = hz;
    let deadline = std::time::Instant::now() + Duration::from_secs(5);
    while crate::contact_http::confirmed_dial(&f.state.recording) != Some(hz) {
        assert!(
            std::time::Instant::now() < deadline,
            "dial {hz} not confirmed"
        );
        std::thread::sleep(Duration::from_millis(5));
    }
}
/// The contest QSOs the log holds now, as (call, grid, band, mode), oldest first.
fn logged(f: &Mcp, e: i64) -> Vec<(String, Option<String>, Option<String>, String)> {
    let (_, mut list) = f
        .state
        .logbook
        .contest_qsos(e - 3_600_000, e + 3_600_000)
        .unwrap();
    list.sort_by_key(|q| q.ms);
    list.into_iter()
        .map(|q| (q.call, q.grid, q.band, q.mode))
        .collect()
}
fn qso(call: &str, grid: &str) -> (String, Option<String>, Option<String>, String) {
    (
        call.into(),
        Some(grid.into()),
        Some("20m".into()),
        "FT8".into(),
    )
}

// Proves: TC-063-009
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_063_009_search_and_pounce_calls_the_most_valuable_and_waits_for_what_it_needs() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    f.state.recording.fixture_band("20m");
    import_adi(&f, &logged_before("W1DUP", "EM12", e));
    // strategydef: the confirmation and colouring are refused on PUT with their field.
    let mut confirmed = contest_config(e, "sp", -1);
    confirmed["contest"]["automation_confirmed"] = json!(true);
    let r = put(&f, json!(0), confirmed).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
    assert_eq!(r.json["error"]["field"], "contest.automation_confirmed");
    let r = put(&f, json!(0), contest_config(e, "colouring", -1)).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
    assert_eq!(r.json["error"]["field"], "contest.operation");
    assert_eq!(f.read("automation").await["run"], Value::Null);
    // Choosing an activity sets no strategy.
    browser_ok(&f, "set_activity", json!({"activity":"ww_digi"})).await;
    assert!(f.browser("GET", "/strategy", None).await.json["configuration"]["contest"].is_null());
    assert_eq!(f.read("automation").await["run"], Value::Null);
    // Selected with Auto off it only marks. WW Digi forbids automatic operation: Auto on
    // without the confirmation is refused, Auto stays off and nothing runs.
    browser_ok(&f, "set_activity", json!({"activity":"none"})).await;
    save(&f, contest_config(e, "sp", -1)).await;
    f.tick();
    assert_eq!(f.read("automation").await["run"], Value::Null);
    for confirmation in [None, Some(false)] {
        let r = auto(&f, true, confirmation).await;
        assert_eq!(
            (r.status, r.json["error"]["field"].clone()),
            (StatusCode::BAD_REQUEST, json!("automation_confirmed")),
            "{confirmation:?}"
        );
    }
    assert_eq!(
        f.browser("GET", "/strategy", None).await.json["auto"],
        false
    );
    assert_eq!(f.read("automation").await["run"], Value::Null);
    // Each reason it waits for: the activity, the band, the period; never a CQ in S&P.
    let r = auto(&f, true, Some(true)).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);
    assert_eq!(r.json["auto"], true);
    f.tick();
    assert_eq!(run_state(&f).await, ("waiting".into(), json!("activity")));
    browser_ok(&f, "set_activity", json!({"activity":"ww_digi"})).await;
    f.state.recording.fixture_band("30m");
    f.tick();
    assert_eq!(run_state(&f).await, ("waiting".into(), json!("band")));
    f.state.recording.fixture_band("20m");
    f.tick();
    assert_eq!(run_state(&f).await, ("waiting".into(), Value::Null));
    assert_eq!(contact(&f).await.2, json!("disarmed"), "S&P never calls CQ");
    // New multiplier far before the rest; the dupe of the period is never called, also strongest.
    publish(
        &f,
        e,
        &[
            ("CQ WW W1DUP EM12", 900.0, Some(9.0)),
            ("CQ WW K1ABC FN42", 1200.0, Some(0.0)),
            ("CQ WW JA1XYZ PM95", 1400.0, Some(-18.0)),
        ],
    );
    assert_eq!(
        contact(&f).await,
        (json!("JA1XYZ"), json!("report"), json!("armed"))
    );
    // The contest message: the grid is the exchange (Tx1 is disabled in a contest).
    assert_eq!(
        f.read("contact").await["contact"]["messages"][1],
        "JA1XYZ HB9BLA JN47"
    );
    // At the contest's repetitions (2) JA1XYZ is left and quiet for its 10 minutes (LeaveRule,
    // QuietTime); nothing armed for the dupe alone, nor for JA1XYZ while quiet.
    publish(&f, e + 30_000, &[]);
    assert_eq!(run_state(&f).await.0, "contact_active");
    publish(&f, e + 60_000, &[]);
    f.tick();
    assert_eq!(run_state(&f).await, ("waiting".into(), Value::Null));
    assert_eq!(contact(&f).await.2, json!("disarmed"));
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (run["left"].clone(), run["quiet"].clone()),
        (
            json!({"call":"JA1XYZ","reason":"repetitions"}),
            json!([{"call":"JA1XYZ","band":"20m","mode":"ft8","remaining_s":600}])
        )
    );
    publish(&f, e + 150_000, &[("CQ WW W1DUP EM12", 900.0, Some(9.0))]);
    assert_eq!(contact(&f).await.2, json!("disarmed"), "a dupe alone");
    publish(
        &f,
        e + 180_000,
        &[("CQ WW JA1XYZ PM95", 1400.0, Some(-18.0))],
    );
    assert_eq!(contact(&f).await.2, json!("disarmed"), "JA1XYZ quiet");
    // Outside the period it waits: selected to start in an hour.
    let revision = f.browser("GET", "/strategy", None).await.json["revision"].clone();
    let p = put(&f, revision, contest_config(e, "sp", 1)).await;
    assert_eq!(p.status, StatusCode::OK, "{}", p.json);
    // WW Digi forbids automatic operation: the change turns Auto off, the run stops; only an
    // Auto on with the confirmation starts the new one.
    assert_eq!(p.json["auto"], false);
    assert_eq!(run_state(&f).await.0, "stopped");
    assert_eq!(auto(&f, true, Some(true)).await.status, StatusCode::OK);
    f.tick();
    assert_eq!(
        run_state(&f).await,
        ("waiting".into(), json!("outside_period"))
    );
    publish(&f, e + 180_000, &[("CQ WW K1ABC FN42", 1200.0, Some(0.0))]);
    assert_eq!(contact(&f).await.2, json!("disarmed"));
}

/// Ticks until the ContestLog was rebuilt by the run itself (the seam starts no build).
async fn built_qsos(f: &Mcp, qsos: u64) {
    let strategy = &f.state.recording.contact.get().unwrap().strategy;
    let deadline = std::time::Instant::now() + Duration::from_secs(5);
    while strategy.contest_log_built_qsos() != Some(qsos) {
        assert!(
            std::time::Instant::now() < deadline,
            "{:?}",
            strategy.contest_log_built_qsos()
        );
        f.tick();
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
}

// Proves: TC-063-009
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_063_009_a_manual_qso_of_the_period_is_a_dupe_for_the_next_evaluation() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    f.state.recording.fixture_band("20m");
    dial_20m(&f);
    browser_ok(&f, "set_activity", json!({"activity":"ww_digi"})).await;
    select(&f, contest_config(e, "sp", -1)).await;
    f.tick();
    assert_eq!(logged(&f, e), vec![], "the log starts empty");
    // A row the run skips, so that it keeps waiting; the operator confirms and arms it.
    publish(&f, e, &[("CQ NA W9XYZ EN52", 900.0, Some(-3.0))]);
    assert_eq!(run_state(&f).await.0, "waiting");
    browser_ok(
        &f,
        "select_row",
        json!({"row":live_row(&f, "CQ NA W9XYZ EN52"),"replace":false,"directive_confirmed":true}),
    )
    .await;
    let safety = f.read("contact").await["transmit"]["safety_revision"].clone();
    browser_ok(
        &f,
        "enable_tx",
        json!({"enabled":true,"safety_revision":safety}),
    )
    .await;
    f.tick();
    assert_eq!(run_state(&f).await.0, "manual");
    publish(
        &f,
        e + 30_000,
        &[("HB9BLA W9XYZ R EN52", 905.0, Some(-6.0))],
    );
    publish(&f, e + 60_000, &[("HB9BLA W9XYZ 73", 905.0, Some(-6.0))]);
    assert_eq!(contact(&f).await.1, json!("completed"));
    f.tick();
    assert_eq!(run_state(&f).await.0, "waiting");
    // The completed QSO wrote its own log entry, on the confirmed dial's band; nothing imported.
    assert_eq!(logged(&f, e), vec![qso("W9XYZ", "EN52")]);
    built_qsos(&f, 1).await;
    // Its CQ in the next period: a dupe alone, nothing armed.
    publish(&f, e + 120_000, &[("CQ WW W9XYZ EN52", 900.0, Some(9.0))]);
    assert_eq!(contact(&f).await.2, json!("disarmed"));
    assert_eq!(run_state(&f).await.0, "waiting");
}

// Proves: TC-063-011
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_063_011_the_tx_watchdog_stops_a_run_on_a_silent_band() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    f.state.recording.fixture_band("20m");
    browser_ok(&f, "set_activity", json!({"activity":"ww_digi"})).await;
    browser_watchdog(&f, 2).await;
    select(&f, contest_config(e, "run", -1)).await;
    f.tick();
    assert_eq!(run_state(&f).await.0, "calling_cq");
    transmit_own_period(&f, e + 15_000).await;
    transmit_own_period(&f, e + 45_000).await;
    let keys = f.keys();
    not_keyed_in(&f, e + 75_000).await;
    f.tick();
    f.tick();
    f.tick();
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("tx_watchdog"))
    );
    assert_eq!(contact(&f).await.2, json!("disarmed"));
    // Nothing keys it again; the contest stays selected with the reason.
    publish(&f, e + 90_000, &[("HB9BLA K1ABC FN42", 1500.0, Some(-5.0))]);
    f.tick();
    assert_eq!(contact(&f).await.2, json!("disarmed"));
    assert_eq!(f.keys(), keys);
    // The stop turned Auto off (strategydef); the contest keeps its operation.
    let s = f.browser("GET", "/strategy", None).await.json;
    assert_eq!(
        (
            s["configuration"]["contest"]["operation"].clone(),
            s["auto"].clone()
        ),
        (json!("run"), json!(false))
    );
    // Only Auto on restarts it, also after Enable Tx off left its CQ.
    browser_watchdog(&f, 20).await;
    assert_eq!(auto(&f, true, Some(true)).await.status, StatusCode::OK);
    f.tick();
    assert_eq!(run_state(&f).await.0, "calling_cq");
    browser_ok(
        &f,
        "enable_tx",
        json!({"enabled":false,"safety_revision":null}),
    )
    .await;
    f.tick();
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("transmit_stopped"))
    );
    assert_eq!(
        f.browser("GET", "/strategy", None).await.json["auto"],
        false
    );
    assert_eq!(auto(&f, true, Some(true)).await.status, StatusCode::OK);
    f.tick();
    assert_eq!(run_state(&f).await.0, "calling_cq", "no CQ left behind");
}

// Proves: TC-063-010
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_063_010_run_calls_cq_and_answers_the_most_valuable_caller() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    f.state.recording.fixture_band("20m");
    let dial = dial_20m(&f);
    import_adi(&f, &logged_before("W1DUP", "EM12", e));
    browser_ok(&f, "set_activity", json!({"activity":"ww_digi"})).await;
    select(&f, contest_config(e, "run", -1)).await;
    f.tick();
    let run = f.read("automation").await["run"].clone();
    assert_eq!(run["state"], "calling_cq");
    let c = f.read("contact").await;
    assert_eq!(c["contact"]["state"], "calling");
    assert_eq!(c["transmit"]["arm_state"], "armed");
    assert_eq!(c["contact"]["messages"][5], "CQ WW HB9BLA JN47");
    // Several callers: a dupe, the first decoded with a known value and the most valuable.
    publish(
        &f,
        e,
        &[
            ("HB9BLA W1DUP EM12", 900.0, Some(9.0)),
            ("HB9BLA K1ABC FN42", 1200.0, Some(5.0)),
            ("HB9BLA JA1XYZ PM95", 1400.0, Some(-18.0)),
        ],
    );
    assert_eq!(
        contact(&f).await,
        (json!("JA1XYZ"), json!("roger_report"), json!("armed")),
        "not the first decoded (Call 1st), not the strongest, not the dupe"
    );
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (
            run["state"].clone(),
            run["last_decision"]["candidates"].clone()
        ),
        (json!("contact_active"), json!(2))
    );
    // The QSO to its end; then the next CQ goes out by itself and the worked one is not answered.
    publish(
        &f,
        e + 30_000,
        &[("HB9BLA JA1XYZ RR73", 1400.0, Some(-18.0))],
    );
    transmit_own_period(&f, e + 15_000).await;
    assert_eq!(contact(&f).await.1, json!("completed"));
    f.tick();
    f.tick();
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (run["state"].clone(), run["completed_contacts"].clone()),
        (json!("calling_cq"), json!(1))
    );
    // The completed QSO wrote its own log entry beside the earlier W1DUP; nothing imported.
    assert_eq!(
        logged(&f, e),
        vec![qso("W1DUP", "EM12"), qso("JA1XYZ", "PM95")]
    );
    built_qsos(&f, 2).await;
    publish(
        &f,
        e + 90_000,
        &[("HB9BLA JA1XYZ PM95", 1400.0, Some(-18.0))],
    );
    assert_eq!(contact(&f).await.1, json!("calling"), "worked in this run");
    // The next evaluation counts that QSO: PM is no new multiplier now, FN is, whatever the points.
    publish(
        &f,
        e + 120_000,
        &[
            ("HB9BLA JA2ABC PM85", 1200.0, Some(0.0)),
            ("HB9BLA K1NEW FN42", 1400.0, Some(-10.0)),
        ],
    );
    assert_eq!(contact(&f).await.0, json!("K1NEW"));
    browser_ok(&f, "abort", json!({})).await;
    f.tick();
    f.tick();
    f.tick();
    assert_eq!(
        run_state(&f).await.0,
        "calling_cq",
        "Esc on a caller's QSO gives that station up, the run calls again"
    );
    // No caller keeps the CQ on the air.
    publish(&f, e + 150_000, &[]);
    assert_eq!(run_state(&f).await.0, "calling_cq");
    // Esc on the run's own CQ ends that CQ; the run calls again, a new CQ on the same selection.
    let id = f.read("contact").await["contact"]["id"].clone();
    browser_ok(&f, "abort", json!({})).await;
    f.tick();
    f.tick();
    f.tick();
    assert_eq!(run_state(&f).await.0, "calling_cq");
    assert_eq!(contact(&f).await.2, json!("armed"));
    assert_ne!(f.read("contact").await["contact"]["id"], id);
    assert_eq!(
        f.browser("GET", "/strategy", None).await.json["configuration"]["contest"]["operation"],
        "run"
    );
    // A reason appearing ends the CQ: a band outside the contest, disarmed; back, it calls again.
    // The station band is the radio's: the dial moves to 30 m and back.
    f.state.recording.fixture_band("30m");
    retune(&f, &dial, 10_136_000);
    f.tick();
    assert_eq!(run_state(&f).await, ("waiting".into(), json!("band")));
    assert_eq!(contact(&f).await.2, json!("disarmed"));
    f.state.recording.fixture_band("20m");
    retune(&f, &dial, 14_074_000);
    f.tick();
    f.tick();
    assert_eq!(run_state(&f).await.0, "calling_cq");
    assert_eq!(contact(&f).await.2, json!("armed"));
    // The end of the period, by the station clock: the same, and it stays.
    crate::automation_tests::jump_and_tick(&f, 3 * 3_600_000);
    assert_eq!(
        run_state(&f).await,
        ("waiting".into(), json!("outside_period"))
    );
    assert_eq!(contact(&f).await.2, json!("disarmed"));
}

// Proves: TC-063-011
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_063_011_the_safety_of_a_contest_run_stays_on_the_server() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let session = f.state.recording.clients.session();
    f.state.recording.fixture_band("20m");
    browser_ok(&f, "set_activity", json!({"activity":"ww_digi"})).await;
    let start = async |f: &Mcp| {
        select(f, contest_config(e, "run", -1)).await;
        f.tick();
        assert_eq!(quiet_run(f).0, "calling_cq");
    };
    start(&f).await;
    // An MCP client cannot start it again: only a selection does.
    let m = f
        .tool(
            "wstx_automation_command",
            json!({"command":{"v":1,"profile_id":f.id,"boot_id":f.boot,
            "command_id":crate::profile::new_uuid().unwrap(),"action":"configure",
            "expected_policy_revision":0,"configuration":{"modes":["ft8"],"ranking":"first_seen",
            "min_snr_db":null,"allowed_calls":[],"blocked_calls":[],"max_contacts":1,
            "max_unanswered_periods":1,"completion_action":"stop","strategy":true}}}),
        )
        .await;
    assert_eq!(m["result"]["error"]["code"], "operator_required", "{m}");
    // A double-click on a CQ during the run's CQ: a manual QSO, the run stands aside, resumes.
    publish(&f, e, &[("CQ WW K1ABC FN42", 1200.0, Some(5.0))]);
    let row = live_row(&f, "CQ WW K1ABC FN42");
    let d = f
        .browser(
            "POST",
            "/contact/command",
            Some(browser_command(&f, "select_row", json!({"row":row,"replace":true})).await),
        )
        .await;
    assert_eq!(d.status, StatusCode::ACCEPTED, "{}", d.json);
    f.tick();
    assert_eq!(quiet_run(&f).0, "manual");
    assert_eq!(quiet_contact(&f).await.0, json!("K1ABC"));
    // Abort QSO (Esc) ends the QSO, not the run: it calls CQ again.
    browser_ok(&f, "abort", json!({})).await;
    f.tick();
    f.tick();
    f.tick();
    assert_eq!(quiet_run(&f).0, "calling_cq");
    let active = |c: Value| {
        (
            c["configuration"]["contest"]["operation"].clone(),
            c["auto"].clone(),
        )
    };
    assert_eq!(
        active(f.browser("GET", "/strategy", None).await.json),
        (json!("run"), json!(true))
    );
    // HALT from any source ends the run and turns Auto off; the contest keeps its operation.
    let h = f
        .browser(
            "POST",
            "/transmit/halt",
            Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,
                "command_id":crate::profile::new_uuid().unwrap()})),
        )
        .await;
    assert!(h.status.is_success(), "{}", h.json);
    f.tick();
    assert_eq!(quiet_run(&f), ("stopped".into(), json!("halted")));
    assert_eq!(
        active(f.browser("GET", "/strategy", None).await.json),
        (json!("run"), json!(false))
    );
    assert_eq!(quiet_contact(&f).await.2, json!("disarmed"));
    // The 8 h limit ends the CQ at once and leaves the contest selected with the reason.
    start(&f).await;
    at_skew(&f, 8 * 3600);
    assert_eq!(quiet_run(&f), ("stopped".into(), json!("run_limit")));
    assert_eq!(quiet_contact(&f).await.2, json!("disarmed"));
    assert_eq!(
        active(f.browser("GET", "/strategy", None).await.json),
        (json!("run"), json!(false))
    );
    at_skew(&f, 0);
    // With every browser gone for 60 s likewise; only Auto on restarts it.
    start(&f).await;
    drop(session);
    at_skew(&f, 60);
    assert_eq!(quiet_run(&f), ("stopped".into(), json!("no_client")));
    assert_eq!(quiet_contact(&f).await.2, json!("disarmed"));
    at_skew(&f, 0);
    // Auto off (colouring only): the run ends at once, disarmed, no run in its place.
    let _back = f.state.recording.clients.session();
    start(&f).await;
    assert_eq!(auto(&f, false, None).await.status, StatusCode::OK);
    f.tick();
    assert_eq!(quiet_run(&f), ("stopped".into(), json!("stopped")));
    assert_eq!(quiet_contact(&f).await.2, json!("disarmed"));
    // Its CQ is not left behind: the next Auto on calls again.
    start(&f).await;
}

// ------------------------------------------------------------------ strategydef
/// TC-039-040 rows (HB9BLA JN47AA, EU, on 20 m FT8): (text, audio Hz, SNR), sequence in order.
const VALUE_ROWS: [(&str, f64, f64); 7] = [
    ("CQ K1ABC FN42", 1200.0, -12.0),
    ("CQ JA1XYZ PM95", 900.0, -15.0),
    ("CQ DL1XYZ JO62", 1500.0, -3.0),
    ("CQ VK2ABC QF56", 600.0, -20.0),
    ("CQ ZS6AA", 2000.0, -8.0),
    ("CQ OH1AA KP20", 1400.0, -3.0),
    ("HB9BLA W1AW FN31", 1000.0, -25.0),
];
fn value_rows(list: &[(&str, f64, f64)]) -> Vec<Value> {
    list.iter()
        .enumerate()
        .map(|(i, (text, hz, snr))| {
            let mut r = record(text, *hz, Some(*snr));
            r["sequence"] = json!(i);
            r
        })
        .collect()
}
/// (call, band, mode, grid, QSO_DATE).
type DatedRow<'a> = (&'a str, &'a str, &'a str, Option<&'a str>, u32);
fn dated(log: &[DatedRow], window: Option<(u32, u32)>) -> Arc<Worked> {
    let logged: Vec<Logged> = log
        .iter()
        .map(|(call, band, mode, grid, date)| Logged {
            call: (*call).into(),
            grid: grid.map(Into::into),
            band: Some((*band).into()),
            mode: Some((*mode).into()),
            confirmed: false,
            date: Some(*date),
        })
        .collect();
    Arc::new(Worked::from_log_window(
        &crate::dxcc::Table::default(),
        &logged,
        window,
    ))
}
/// HB9BLA JN47AA (EU) on 20 m FT8 with the log of TC-039-040: K1ABC and W1AW on 20 m, DL1XYZ
/// on 40 m only; Most Wanted JA (Japan, ADIF 339) rank 40 and VK (Australia, ADIF 150) rank 90.
fn value_station(log: &[DatedRow]) -> Station {
    Station {
        my_call: "HB9BLA".into(),
        my_continent: Some("EU".into()),
        band: Some("20m".into()),
        mode: "FT8".into(),
        my_locator: Some("JN47AA".into()),
        worked: Some(dated(log, None)),
        most_wanted: crate::most_wanted::List::parse(r#"{"40":"339","90":"150"}"#, "d")
            .map(Arc::new),
        ..Station::default()
    }
}
const VALUE_LOG: [DatedRow; 3] = [
    ("K1ABC", "20m", "FT8", Some("FN42"), 20_260_101),
    ("W1AW", "20m", "FT8", Some("FN31"), 20_260_101),
    ("DL1XYZ", "40m", "FT8", Some("JO62"), 20_260_101),
];
fn valued(goals: &[Goal], value: &[Criterion], callers_first: bool) -> Strategy {
    Strategy {
        value: value.to_vec(),
        callers_first,
        ..award(goals)
    }
}
/// The great-circle distance written here: haversine on a sphere of 6371 km between two
/// (lat, lon east) points, truncated to whole km.
fn test_km(a: (f64, f64), b: (f64, f64)) -> u64 {
    let r = std::f64::consts::PI / 180.0;
    let (p1, p2) = (a.0 * r, b.0 * r);
    let (dp, dl) = ((b.0 - a.0) * r, (b.1 - a.1) * r);
    let h = (dp / 2.0).sin().powi(2) + p1.cos() * p2.cos() * (dl / 2.0).sin().powi(2);
    (2.0 * 6371.0 * h.sqrt().asin()).floor() as u64
}

// Proves: TC-039-040. new_call_band and the value list ranked by hand: [snr], [distance] (the
// haversine written here; the cty.dat entity centre without a grid), [most_wanted], two
// criteria, [new_dxcc, snr]; the exact tie; callers first on and off; the empty list; a caller
// failing every filter line; the band unknown; the window today; decode order is no ranking.
#[test]
fn tc_039_040_the_filter_and_the_value_order() {
    use Criterion::*;
    let rows = value_rows(&VALUE_ROWS);
    let st = value_station(&VALUE_LOG);
    let band = |value: &[Criterion], callers_first: bool| {
        called(
            &valued(&[Goal::NewCallBand], value, callers_first),
            &rows,
            &st,
        )
    };
    // new_call_band: K1ABC (on 20 m) is no candidate, DL1XYZ (40 m only) is; W1AW calls me.
    // [snr]: DL1XYZ and OH1AA tie at -3 dB, the lower audio frequency first (1400 < 1500).
    assert_eq!(
        band(&[Snr], true),
        ["W1AW", "OH1AA", "DL1XYZ", "ZS6AA", "JA1XYZ", "VK2ABC"]
    );
    // [distance], farther first, from the centre of JN47AA (47.0208 N, 8.0417 E): QF56
    // (-33.5, 151), PM95 (35.5, 139), ZS6AA without grid at the South Africa centre of cty.dat
    // (-29.07, 22.63), KP20 (60.5, 25), JO62 (52.5, 13).
    let me = (47.0 + 1.0 / 48.0, 8.0 + 1.0 / 24.0);
    let km = |call: &str| {
        let r = rows
            .iter()
            .filter_map(facts)
            .find(|f| f.from == call)
            .unwrap();
        station_distance(&st, &r)
    };
    for (call, centre) in [
        ("VK2ABC", (-33.5, 151.0)),
        ("JA1XYZ", (35.5, 139.0)),
        ("ZS6AA", (-29.07, 22.63)),
        ("OH1AA", (60.5, 25.0)),
        ("DL1XYZ", (52.5, 13.0)),
    ] {
        assert_eq!(km(call), Some(test_km(me, centre)), "{call}");
    }
    assert_eq!(
        band(&[Distance], true),
        ["W1AW", "VK2ABC", "JA1XYZ", "ZS6AA", "OH1AA", "DL1XYZ"]
    );
    // [most_wanted]: JA #40, VK #90, then the rest by the hidden SNR.
    assert_eq!(
        band(&[MostWanted], true),
        ["W1AW", "JA1XYZ", "VK2ABC", "OH1AA", "DL1XYZ", "ZS6AA"]
    );
    // [most_wanted, distance]: the listed by rank, the rest by distance.
    assert_eq!(
        band(&[MostWanted, Distance], true),
        ["W1AW", "JA1XYZ", "VK2ABC", "ZS6AA", "OH1AA", "DL1XYZ"]
    );
    // [new_dxcc, snr]: Germany is worked (on 40 m): DL1XYZ after the needed ones.
    assert_eq!(
        band(&[NewDxcc, Snr], true),
        ["W1AW", "OH1AA", "ZS6AA", "JA1XYZ", "VK2ABC", "DL1XYZ"]
    );
    // Callers first off with [snr]: W1AW ranked by its SNR, the weakest, last.
    assert_eq!(
        band(&[Snr], false),
        ["OH1AA", "DL1XYZ", "ZS6AA", "JA1XYZ", "VK2ABC", "W1AW"]
    );
    // The empty list: the hidden SNR alone.
    assert_eq!(band(&[], true), band(&[Snr], true));
    // The reasons name the needed goals; no Most Wanted suffix without that criterion.
    let why = |s: &Strategy, call: &str| {
        evaluate(s, &rows, &st)
            .into_iter()
            .find(|v| v.facts.from == call)
            .unwrap()
            .why
    };
    let snr = valued(&[Goal::NewCallBand], &[Snr], true);
    assert_eq!(why(&snr, "OH1AA"), "needed: new_call_band");
    assert_eq!(why(&snr, "W1AW"), "calls my call");
    assert_eq!(why(&snr, "K1ABC"), "not needed");
    assert_eq!(
        why(&valued(&[Goal::NewCallBand], &[MostWanted], true), "JA1XYZ"),
        "needed: new_call_band · Most Wanted #40"
    );
    // The caller fails every filter line (worked on 20 m, region AS only, min SNR -10): ranked.
    let strict = Strategy {
        region: Region::Selected(vec!["AS".into()]),
        min_snr_db: Some(-10),
        ..valued(&[Goal::NewCallBand], &[Snr], true)
    };
    assert_eq!(called(&strict, &rows, &st), ["W1AW"]);
    // The band unknown: new_call_band needs none; the caller is still answered.
    let unknown = Station {
        band: None,
        ..value_station(&VALUE_LOG)
    };
    assert_eq!(
        called(&valued(&[Goal::NewCallBand], &[Snr], true), &rows, &unknown),
        ["W1AW"]
    );
    // Decode order is no ranking: the same rows in the reverse sequence rank the same.
    let mut reversed = rows.clone();
    for (i, r) in reversed.iter_mut().enumerate() {
        r["sequence"] = json!(VALUE_ROWS.len() - i);
    }
    reversed.reverse();
    assert_eq!(
        called(&valued(&[Goal::NewCallBand], &[Snr], true), &reversed, &st),
        band(&[Snr], true)
    );
    // An exact tie of SNR and frequency: by the call, whatever the sequence.
    let tied = value_rows(&[
        ("CQ AB1AA FN42", 700.0, -10.0),
        ("CQ AA1AA FN42", 700.0, -10.0),
    ]);
    assert_eq!(
        called(&valued(&[Goal::NewCall], &[Snr], true), &tied, &st),
        ["AA1AA", "AB1AA"]
    );
    // The window today: OH1AA worked on 20 m today is not needed, DL1XYZ worked on 20 m in 2025
    // is; with the window all neither is.
    let today = utc_date();
    let log: [DatedRow; 2] = [
        ("OH1AA", "20m", "FT8", Some("KP20"), today),
        ("DL1XYZ", "20m", "FT8", Some("JO62"), 20_250_101),
    ];
    let in_window = |window: Option<(u32, u32)>| Station {
        worked: Some(dated(&log, window)),
        ..value_station(&[])
    };
    let s = valued(&[Goal::NewCallBand], &[Snr], false);
    assert_eq!(
        called(&s, &rows, &in_window(Some((today, today)))),
        ["DL1XYZ", "ZS6AA", "K1ABC", "JA1XYZ", "VK2ABC", "W1AW"]
    );
    assert_eq!(
        called(&s, &rows, &in_window(None)),
        ["ZS6AA", "K1ABC", "JA1XYZ", "VK2ABC", "W1AW"]
    );
}

// Proves: TC-039-040. Each needed-first criterion alone, each with its own log, before the hidden
// SNR (goal new_call, grid or dxcc_slot so that every row stays a candidate; callers first off,
// so the caller W1AW is ranked by the criterion too).
#[test]
fn tc_039_040_each_needed_first_criterion_with_its_own_log() {
    use Criterion::*;
    let rows = value_rows(&VALUE_ROWS);
    let goals = [Goal::NewCall, Goal::Grid, Goal::DxccSlot];
    let order = |c: Criterion, log: &[DatedRow], band: Option<&str>| {
        let st = Station {
            band: band.map(Into::into),
            most_wanted: None,
            ..value_station(log)
        };
        called(&valued(&goals, &[c], false), &rows, &st)
    };
    let d = 20_260_101;
    let twenty = Some("20m");
    for (c, log, band, expected) in [
        // Germany worked on 40 m: DL1XYZ after the rest.
        (
            NewDxcc,
            vec![("DL9ZZZ", "40m", "FT8", Some("JO50"), d)],
            twenty,
            vec![
                "OH1AA", "ZS6AA", "K1ABC", "JA1XYZ", "VK2ABC", "W1AW", "DL1XYZ",
            ],
        ),
        // On 20 m Germany (40 m only) is needed; the USA (K9ZZZ on 20 m) is not.
        (
            NewDxccBand,
            vec![
                ("DL9ZZZ", "40m", "FT8", Some("JO50"), d),
                ("K9ZZZ", "20m", "FT8", Some("EM10"), d),
            ],
            twenty,
            vec![
                "OH1AA", "DL1XYZ", "ZS6AA", "JA1XYZ", "VK2ABC", "K1ABC", "W1AW",
            ],
        ),
        // Japan only in FT4 on 20 m: needed in FT8 (another mode); Australia in FT8: not.
        (
            NewDxccSlot,
            vec![
                ("JA9ZZZ", "20m", "FT4", Some("PM85"), d),
                ("VK3ZZZ", "20m", "FT8", Some("QF22"), d),
            ],
            twenty,
            vec![
                "OH1AA", "DL1XYZ", "ZS6AA", "K1ABC", "JA1XYZ", "W1AW", "VK2ABC",
            ],
        ),
        // K1ABC and W1AW logged (from EM00, so K1ABC stays a candidate by its grid).
        (
            NewCall,
            vec![
                ("K1ABC", "20m", "FT8", Some("EM00"), d),
                ("W1AW", "20m", "FT8", Some("EM00"), d),
            ],
            twenty,
            vec![
                "OH1AA", "DL1XYZ", "ZS6AA", "JA1XYZ", "VK2ABC", "K1ABC", "W1AW",
            ],
        ),
        // K1ABC, W1AW and OH1AA on 20 m: after the rest.
        (
            NewCallBand,
            vec![
                ("K1ABC", "20m", "FT8", Some("EM00"), d),
                ("W1AW", "20m", "FT8", Some("EM00"), d),
                ("OH1AA", "20m", "FT8", Some("KP00"), d),
            ],
            twenty,
            vec![
                "DL1XYZ", "ZS6AA", "JA1XYZ", "VK2ABC", "OH1AA", "K1ABC", "W1AW",
            ],
        ),
        // FN42 logged on 40 m: K1ABC's grid is worked; ZS6AA sends no grid (D13): both after.
        (
            NewGrid,
            vec![("K9ZZZ", "40m", "FT8", Some("FN42"), d)],
            twenty,
            vec![
                "OH1AA", "DL1XYZ", "JA1XYZ", "VK2ABC", "W1AW", "ZS6AA", "K1ABC",
            ],
        ),
        // FN42 only on 40 m: K1ABC needed on 20 m; no grid (ZS6AA) and an unknown grid status
        // (JA1XYZ, a 20 m QSO without grid, a candidate by dxcc_slot) are not.
        (
            NewGridBand,
            vec![
                ("K9ZZZ", "40m", "FT8", Some("FN42"), d),
                ("JA1XYZ", "20m", "FT4", None, d),
            ],
            twenty,
            vec![
                "OH1AA", "DL1XYZ", "K1ABC", "VK2ABC", "W1AW", "ZS6AA", "JA1XYZ",
            ],
        ),
        // The band unknown: new_grid_band needs nothing, the hidden SNR alone; JA1XYZ (logged,
        // gridless, dxcc_slot needs a band) is no candidate.
        (
            NewGridBand,
            vec![
                ("K9ZZZ", "40m", "FT8", Some("FN42"), d),
                ("JA1XYZ", "20m", "FT4", None, d),
            ],
            None,
            vec!["OH1AA", "DL1XYZ", "ZS6AA", "K1ABC", "VK2ABC", "W1AW"],
        ),
    ] {
        assert_eq!(order(c, &log, band), expected, "{c:?} {band:?}");
    }
}

// Proves: TC-039-041. A schema 2 file reads at its revision with calls_per_station dropped and
// the defaults added, and the next PUT writes schema 3; a malformed schema 2 strategy makes the
// file malformed; the eight built-ins are listed.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_041_a_schema_2_file_upgrades_and_is_written_as_schema_3() {
    let f = station(true).await;
    let write = |schema: u64, strategies: Value| {
        std::fs::write(
            f.dir.join(FILE_NAME),
            serde_json::to_vec(
                &json!({"schema_version":schema,"profile_id":f.id,"revision":7,
                "configuration":{"continent":null,"active":null,"strategies":strategies,
                "ignore_calls":[],"session_ignore_minutes":30}}),
            )
            .unwrap(),
        )
        .unwrap();
    };
    let old = json!({"name":"Mine","class":"award","goals":["new_call"],"needed":"not_worked",
        "region":{"kind":"all"},"min_snr_db":null,"calls_per_station":5,"treat_73_as_cq":true,
        "window":{"kind":"all"}});
    write(2, json!([old]));
    let owner = Owner::default();
    let s = owner.snapshot(&f.state);
    assert_eq!(
        (s["revision"].clone(), s["configuration_error"].clone()),
        (json!(7), Value::Null)
    );
    let mine = json!({"name":"Mine","class":"award","goals":["new_call"],"needed":"not_worked",
        "region":{"kind":"all"},"min_snr_db":null,"value":["most_wanted"],"callers_first":true,
        "cq_when_no_target":false,"repetitions":4,"quiet_minutes":10,"treat_73_as_cq":true,
        "window":{"kind":"all"}});
    assert_eq!(s["configuration"]["strategies"], json!([mine]));
    // The next PUT writes schema 3 at revision 8 with those keys.
    let mut changed = s["configuration"].clone();
    changed["continent"] = json!("AS");
    owner
        .put(
            &f.state,
            json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"expected_revision":7,
                "configuration":changed}),
        )
        .unwrap();
    let saved: Value =
        serde_json::from_slice(&std::fs::read(f.dir.join(FILE_NAME)).unwrap()).unwrap();
    assert_eq!(
        saved,
        json!({"schema_version":3,"profile_id":f.id,"revision":8,"configuration":changed})
    );
    assert_eq!(saved["configuration"]["strategies"][0], mine);
    // A schema 2 strategy that is otherwise malformed: the file reads configuration null.
    let with = |k: &str, v: Value| {
        let mut s = old.clone();
        s[k] = v;
        s
    };
    let mut missing = old.clone();
    missing.as_object_mut().unwrap().remove("calls_per_station");
    for bad in [
        with("calls_per_station", json!(0)),
        with("calls_per_station", json!(21)),
        with("region", json!({"kind":"east"})),
        with("value", json!(["snr"])),
        missing,
    ] {
        write(2, json!([bad.clone()]));
        let s = Owner::default().snapshot(&f.state);
        assert_eq!(
            (s["configuration"].clone(), s["configuration_error"].clone()),
            (Value::Null, json!("invalid_configuration")),
            "{bad}"
        );
    }
    // A schema 3 file is read as it is; schema 3 keys in it are required.
    write(3, json!([mine]));
    assert_eq!(
        Owner::default().snapshot(&f.state)["configuration"]["strategies"],
        json!([mine])
    );
    write(3, json!([old]));
    assert_eq!(
        Owner::default().snapshot(&f.state)["configuration_error"],
        "invalid_configuration"
    );
    // The eight built-ins (their fields: TC-039-032).
    assert_eq!(
        owner.snapshot(&f.state)["builtin_strategies"]
            .as_array()
            .unwrap()
            .len(),
        8
    );
    std::fs::remove_file(f.dir.join(FILE_NAME)).unwrap();
}

/// The armed state of the transmit owner.
fn armed(f: &Mcp) -> bool {
    f.state
        .recording
        .transmit
        .get()
        .unwrap()
        .service
        .view()
        .arm_state
        == wstx_rust::transmit::service::ArmState::Armed
}
async fn strategy_view(f: &Mcp) -> (Value, Value, u64) {
    let s = f.browser("GET", "/strategy", None).await.json;
    (
        s["configuration"]["active"].clone(),
        s["auto"].clone(),
        s["revision"].as_u64().unwrap(),
    )
}

// Proves: TC-039-042. Auto is station memory, off at start: a selection alone only marks; Auto on
// starts the run, another selection while on restarts it, Auto off ends it at once; Auto on
// without a selection is refused; None and HALT (route and MCP) turn it off and HALT keeps the
// selection; one strategy.state per change; the refusals; a restart reads it off.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_042_auto_starts_and_ends_the_run_and_a_selection_only_marks() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let owner = f.state.recording.contact.get().unwrap();
    let g = f.browser("GET", "/strategy", None).await.json;
    assert_eq!(
        (g["auto"].clone(), g["strategy_refusal"].clone()),
        (json!(false), Value::Null),
        "off by default"
    );
    // Auto on without a selection: 409 not_configured strategy, Auto stays off.
    let r = auto(&f, true, None).await;
    assert_eq!(
        (
            r.status,
            r.json["error"]["code"].clone(),
            r.json["error"]["field"].clone()
        ),
        (
            StatusCode::CONFLICT,
            json!("not_configured"),
            json!("strategy")
        )
    );
    assert_eq!(strategy_view(&f).await.1, json!(false));
    // A selection with Auto off only marks: K1ABC has a rank, nothing is armed or keyed.
    let (source, job, generation) = f
        .state
        .recording
        .live_identity()
        .map(|(s, j, g, _)| (s, j, g))
        .unwrap();
    save(&f, config(Some("New calls"))).await;
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-10.0))]);
    publish(&f, e + 30_000, &[("CQ K1ABC FN42", 1500.0, Some(-10.0))]);
    let v = f
        .browser(
            "POST",
            "/strategy/evaluate",
            Some(
                json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"source_id":source,
                "job_id":job,"generation":generation,"first_sequence":0,"next_sequence":2,
                "strategy":null,"explain":false}),
            ),
        )
        .await;
    assert_eq!(v.json["verdicts"][0]["rank"], 0, "{}", v.json);
    assert_eq!(f.read("automation").await["run"], Value::Null);
    assert_eq!(contact(&f).await.0, Value::Null);
    assert!(!armed(&f));
    assert_eq!(f.keys(), 0);
    // Auto on: one revision, the run starts and calls K1ABC at the next publication.
    let before = owner.strategy.revision();
    let r = auto(&f, true, None).await;
    assert_eq!(
        (r.status, r.json["auto"].clone()),
        (StatusCode::OK, json!(true)),
        "{}",
        r.json
    );
    assert_eq!(owner.strategy.revision(), before + 1, "one strategy.state");
    assert_eq!(run_state(&f).await, ("waiting".into(), Value::Null));
    publish(&f, e + 60_000, &[("CQ K1ABC FN42", 1500.0, Some(-10.0))]);
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
    // Auto on again while it runs changes nothing.
    let id = f.read("automation").await["run"]["id"].clone();
    let r = auto(&f, true, None).await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(f.read("automation").await["run"]["id"], id);
    assert_eq!(owner.strategy.revision(), before + 1);
    // Another selection with Auto on: the old run ends (its contact disarmed and cancelled),
    // the new one starts, Auto stays on.
    save(&f, config(Some("DX hunting"))).await;
    let a = f.read("automation").await;
    assert_ne!(a["run"]["id"], id);
    assert_eq!(a["run"]["state"], "waiting");
    assert_eq!(strategy_view(&f).await.0, json!("DX hunting"));
    assert_eq!(strategy_view(&f).await.1, json!(true));
    let c = contact(&f).await;
    assert_eq!((c.1, c.2), (json!("cancelled"), json!("disarmed")));
    // Auto off ends the run at once: disarmed and cancelled, the selection kept.
    publish(&f, e + 90_000, &[("CQ K1ABC FN42", 1500.0, Some(-10.0))]);
    assert_eq!(contact(&f).await.2, json!("armed"));
    let before = owner.strategy.revision();
    let r = auto(&f, false, None).await;
    assert_eq!(
        (r.status, r.json["auto"].clone()),
        (StatusCode::OK, json!(false))
    );
    assert_eq!(owner.strategy.revision(), before + 1, "one strategy.state");
    assert_eq!(run_state(&f).await, ("stopped".into(), json!("stopped")));
    let c = contact(&f).await;
    assert_eq!((c.1, c.2), (json!("cancelled"), json!("disarmed")));
    assert_eq!(strategy_view(&f).await.0, json!("DX hunting"));
    // A repeated Auto off is no change: no revision.
    assert_eq!(auto(&f, false, None).await.status, StatusCode::OK);
    assert_eq!(owner.strategy.revision(), before + 1);
    // None turns Auto off and stops the run.
    assert_eq!(auto(&f, true, None).await.status, StatusCode::OK);
    save(&f, config(None)).await;
    assert_eq!(strategy_view(&f).await.1, json!(false));
    assert_eq!(run_state(&f).await.0, "stopped");
    // The MCP principal is refused 401 and changes nothing.
    save(&f, config(Some("New calls"))).await;
    let internal = crate::mcp_tests::internal_transport(&f, &f.mcp);
    let m = crate::mcp_tests::with_cookie(
        &f,
        "POST",
        "/strategy/auto",
        &internal,
        Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"auto":true})),
    )
    .await;
    assert_eq!(m.status, StatusCode::UNAUTHORIZED);
    assert_eq!(strategy_view(&f).await.1, json!(false));
    assert_eq!(run_state(&f).await.0, "stopped");
    // The refusals of POST /strategy/ignore.
    let body = |k: &str, v: Value| {
        let mut b = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"auto":true});
        b[k] = v;
        b
    };
    for (b, status, code, field) in [
        (body("extra", json!(1)), 400, "invalid_request", Value::Null),
        (
            body("auto", json!("on")),
            400,
            "invalid_request",
            json!("auto"),
        ),
        (
            body("automation_confirmed", json!(1)),
            400,
            "invalid_request",
            json!("automation_confirmed"),
        ),
        (body("v", json!(2)), 400, "unsupported_version", json!("v")),
        (
            body("profile_id", json!(profile::new_uuid().unwrap())),
            403,
            "wrong_profile",
            json!("profile_id"),
        ),
        (
            body("boot_id", json!(profile::new_uuid().unwrap())),
            409,
            "state_conflict",
            json!("boot_id"),
        ),
    ] {
        let r = f.browser("POST", "/strategy/auto", Some(b.clone())).await;
        assert_eq!(
            (
                r.status.as_u16(),
                r.json["error"]["code"].clone(),
                r.json["error"]["field"].clone()
            ),
            (status, json!(code), field),
            "{b}"
        );
    }
    assert_eq!(strategy_view(&f).await.1, json!(false));
    // HALT by the route: Auto off, the run stopped halted, the selection kept; one revision.
    assert_eq!(auto(&f, true, None).await.status, StatusCode::OK);
    let before = owner.strategy.revision();
    halt(&f).await;
    assert_eq!(run_state(&f).await, ("stopped".into(), json!("halted")));
    let (active, on, revision) = strategy_view(&f).await;
    assert_eq!(
        (active, on, revision),
        (json!("New calls"), json!(false), before + 1)
    );
    // HALT by MCP likewise.
    assert_eq!(auto(&f, true, None).await.status, StatusCode::OK);
    let halt_body =
        json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap()});
    assert_eq!(
        f.tool("wstx_transmit_halt", json!({"halt":halt_body}))
            .await["status"],
        202
    );
    f.tick();
    assert_eq!(run_state(&f).await, ("stopped".into(), json!("halted")));
    assert_eq!(strategy_view(&f).await.0, json!("New calls"));
    assert_eq!(strategy_view(&f).await.1, json!(false));
    // Every run end turns Auto off: a stop by the run itself (Enable Tx off by the operator;
    // tx_watchdog, run_limit and no_client: tc_063_011).
    assert_eq!(auto(&f, true, None).await.status, StatusCode::OK);
    publish(&f, e + 120_000, &[("CQ K1ABC FN42", 1500.0, Some(-10.0))]);
    assert_eq!(contact(&f).await.2, json!("armed"));
    browser_ok(
        &f,
        "enable_tx",
        json!({"enabled":false,"safety_revision":null}),
    )
    .await;
    f.tick();
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("transmit_stopped"))
    );
    assert_eq!(strategy_view(&f).await.1, json!(false));
    // A station restart: a new owner reads Auto off and no selection.
    let reopened = Owner::default().snapshot(&f.state);
    assert_eq!(
        (
            reopened["auto"].clone(),
            reopened["configuration"]["active"].clone()
        ),
        (json!(false), Value::Null)
    );
    assert_eq!(f.keys(), 0, "no PTT exchange");
}

// Proves: TC-039-042, TC-063-009. A contest whose rules forbid automatic operation needs
// automation_confirmed on Auto on (strategy_tests::tc_063_009_search_and_pounce...); a silent one
// (FT8 Activity) needs none; a selection change to a forbidding contest while Auto is on turns
// Auto off instead of starting it.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_042_a_silent_contest_switches_auto_on_without_a_confirmation() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let mut c = contest_config(e, "sp", -1);
    c["contest"]["profile"] = json!("ft8_activity");
    save(&f, c).await;
    let r = auto(&f, true, None).await;
    assert_eq!(
        (r.status, r.json["auto"].clone()),
        (StatusCode::OK, json!(true)),
        "{}",
        r.json
    );
    assert_eq!(
        f.read("automation").await["configuration"]["strategy"],
        true
    );
    // A selection change while Auto is on to WW Digi, whose rules forbid automatic operation:
    // the run ends, no run starts and Auto goes off (the confirmation goes only with Auto on).
    let run_id = f.read("automation").await["run"]["id"].clone();
    save(&f, contest_config(e, "run", -1)).await;
    let a = f.read("automation").await;
    assert_eq!(
        (a["run"]["id"].clone(), a["run"]["state"].clone()),
        (run_id, json!("stopped"))
    );
    assert_eq!(strategy_view(&f).await.1, json!(false));
    // Auto on: refused without the confirmation, accepted with it.
    let r = auto(&f, true, Some(false)).await;
    assert_eq!(
        (r.status, r.json["error"]["field"].clone()),
        (StatusCode::BAD_REQUEST, json!("automation_confirmed"))
    );
    assert_eq!(strategy_view(&f).await.1, json!(false));
    let r = auto(&f, true, Some(true)).await;
    assert_eq!(r.json["auto"], true, "{}", r.json);
}

// Proves: TC-039-042. An Auto on from the browser is the operator's action that ends a Tx watchdog
// stop (WatchdogFromOperator): the run arms afterwards.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_042_a_browser_auto_on_ends_a_watchdog_stop_and_arms() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let service = &f.state.recording.transmit.get().unwrap().service;
    let spent = || service.with(|c| c.watchdog_spent());
    // The strategy selected with Auto off; then an MCP CQ spends the watchdog at its limit 1.
    browser_watchdog(&f, 1).await;
    save(&f, config(Some("New calls"))).await;
    let v = mcp_contact(&f, "enable_tx", json!({"enabled":true,"safety_revision":3})).await;
    assert_eq!(v["status"], 202, "{v}");
    transmit_own_period(&f, e + 15_000).await;
    not_keyed_in(&f, e + 45_000).await;
    assert!(spent());
    let _ = mcp_contact(&f, "cancel", json!({})).await;
    let v = mcp_contact(&f, "enable_tx", json!({"enabled":true,"safety_revision":3})).await;
    assert_eq!(v["result"]["error"]["code"], "tx_watchdog", "{v}");
    // The browser's Auto on ends the stop: the run calls K1ABC and arms.
    let r = auto(&f, true, None).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);
    assert!(!spent());
    publish(&f, e + 60_000, &[("CQ K1ABC FN42", 1500.0, Some(-10.0))]);
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
}

// ------------------------------------------------------------------ strategydef S2: the run
/// A PSK Reporter feed without a connection (hand-authored spots), on the 14074000 Hz dial.
fn attach_feed(f: &Mcp) -> Arc<crate::pskr::Feed> {
    let dir = std::env::temp_dir().join(format!("wstx-pskr-{}", profile::new_uuid().unwrap()));
    std::fs::create_dir(&dir).unwrap();
    let feed = crate::pskr::Feed::start(&dir, &f.id, &f.boot, None, crate::pskr::Timing::BROKER);
    f.state.recording.pskr.set(feed.clone()).ok().unwrap();
    *feed.dial.lock().unwrap() = Some(14_074_000);
    feed
}
/// A spot from `sender` heard by `receiver` at `hz` on `band` FT8, sent at `t_tx` (UTC s), rp -12.
fn spot_of(sender: &str, receiver: &str, hz: u64, band: &str, t_tx: i64) -> String {
    json!({"f":hz,"md":"FT8","t":t_tx + 13,"t_tx":t_tx,"sc":sender,"rc":receiver,"b":band,"rp":-12})
        .to_string()
}
/// A spot of my call at K1ABC on 20 m, `age_s` old.
fn heard_spot(age_s: i64) -> String {
    spot_of(
        "HB9BLA",
        "K1ABC",
        14_075_500,
        "20m",
        crate::contact_http_tests::now_ms() / 1000 - age_s,
    )
}
/// The run snapshot.
async fn run_of(f: &Mcp) -> Value {
    f.read("automation").await["run"].clone()
}
/// The WD:n the engine reports: the run's count of this step, reported at the next.
async fn wd(f: &Mcp) -> Value {
    f.tick();
    f.tick();
    f.read("contact").await["watchdog"]["tx_remaining_calls"].clone()
}
/// An attended strategy run with Auto on, on 20 m: "Test calls" (goal new_call, value [snr],
/// repetitions 4, quiet_minutes 10, callers first) changed by `edit`, the feed attached; `first`
/// published in the even period e selects the target.
struct Leaving {
    f: Mcp,
    e: i64,
    feed: Arc<crate::pskr::Feed>,
    client: Option<crate::automation::ClientSession>,
}
async fn leaving(edit: impl FnOnce(&mut Value), first: &[(&str, f64, Option<f64>)]) -> Leaving {
    leaving_from(true, edit, first).await
}
/// `leaving` with Hold Tx `hold_tx` before the selection (#39 holdtx: the Rx = Tx steps of
/// TC-039-010, -022 and -045 run with Hold Tx explicitly off).
async fn leaving_from(
    hold_tx: bool,
    edit: impl FnOnce(&mut Value),
    first: &[(&str, f64, Option<f64>)],
) -> Leaving {
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let client = f.state.recording.clients.session();
    if !hold_tx {
        hold_off(&f).await;
    }
    let feed = attach_feed(&f);
    let mut c = config(Some("Test calls"));
    c["strategies"][0]["repetitions"] = json!(4);
    c["strategies"][0]["quiet_minutes"] = json!(10);
    edit(&mut c);
    select(&f, c).await;
    publish(&f, e, first);
    // The feed follows the run's target from this step on.
    f.tick();
    Leaving {
        f,
        e,
        feed,
        client: Some(client),
    }
}
const K1ABC_CQ: (&str, f64, Option<f64>) = ("CQ K1ABC FN42", 1800.0, Some(-10.0));
/// The partner period k after e.
fn rep(e: i64, k: i64) -> i64 {
    e + 30_000 * k
}
async fn left_and_quiet(f: &Mcp) -> (Value, Value, Value) {
    let run = run_of(f).await;
    (
        run["state"].clone(),
        run["left"].clone(),
        run["quiet"].clone(),
    )
}
fn quiet_entry(call: &str, remaining_s: u64) -> Value {
    json!([{"call":call,"band":"20m","mode":"ft8","remaining_s":remaining_s}])
}

// Proves: TC-039-043 (a), (b). Situations 1 and 2 count alike: K1ABC silent, or calling CQ again,
// is armed after 3 repetitions and left at the 4th: disarmed and cancelled, left {K1ABC,
// repetitions}, quiet for 600 s on 20 m FT8, the run waiting. WD:4, 3, 2, 1 (TC-039-022).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_043_a_silent_or_repeating_target_is_left_at_the_4th() {
    for again in [false, true] {
        let t = leaving(|_| {}, &[K1ABC_CQ]).await;
        let (f, e) = (&t.f, t.e);
        let rows: &[(&str, f64, Option<f64>)] = if again { &[K1ABC_CQ] } else { &[] };
        assert_eq!(wd(f).await, json!(4), "again {again}");
        for k in 1..=3 {
            publish(f, rep(e, k), rows);
            assert_eq!(
                contact(f).await,
                (json!("K1ABC"), json!("replying"), json!("armed"))
            );
            assert_eq!(wd(f).await, json!(4 - k), "again {again}, repetition {k}");
        }
        publish(f, rep(e, 4), rows);
        assert_eq!(
            contact(f).await,
            (Value::Null, json!("cancelled"), json!("disarmed"))
        );
        assert_eq!(
            left_and_quiet(f).await,
            (
                json!("waiting"),
                json!({"call":"K1ABC","reason":"repetitions"}),
                quiet_entry("K1ABC", 600)
            ),
            "again {again}"
        );
    }
}

// Proves: TC-039-043 (c). A spot of my call at K1ABC 60 s old doubles x: armed after 7, left at
// the 8th, WD:8 down to 1; with Use PSK Reporter off the spot is not used: left at the 4th.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_043_a_target_that_hears_us_is_left_at_2x_and_use_off_at_x() {
    let t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    t.feed.inject(&heard_spot(60));
    assert_eq!(wd(f).await, json!(8));
    for k in 1..=7 {
        publish(f, rep(e, k), &[]);
        assert_eq!(contact(f).await.2, json!("armed"), "repetition {k}");
        assert_eq!(wd(f).await, json!(8 - k));
    }
    assert_eq!(run_of(f).await["hearing"]["state"], "heard");
    publish(f, rep(e, 8), &[]);
    assert_eq!(contact(f).await.2, json!("disarmed"));
    assert_eq!(
        run_of(f).await["left"],
        json!({"call":"K1ABC","reason":"repetitions"})
    );

    let t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    t.feed.inject(&heard_spot(60));
    t.feed.switch_use(false);
    for k in 1..=3 {
        publish(f, rep(e, k), &[]);
        assert_eq!(contact(f).await.2, json!("armed"));
    }
    assert_eq!(run_of(f).await["hearing"]["state"], "unknown");
    publish(f, rep(e, 4), &[]);
    assert_eq!(contact(f).await.2, json!("disarmed"), "Use off: at x");
}

// Proves: TC-039-043 (d), the #63 fix. A repeated message of the target to my call is progress:
// K1ABC answering -05 after the 2nd repetition and repeating it for 6 periods is never left, the
// count back to 0 at each.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_043_a_repeated_report_is_progress_and_never_leaves() {
    let t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    publish(f, rep(e, 1), &[]);
    publish(f, rep(e, 2), &[]);
    assert_eq!(run_of(f).await["unanswered_periods"], 2);
    for k in 3..=8 {
        publish(f, rep(e, k), &[("HB9BLA K1ABC -05", 1800.0, Some(-5.0))]);
        assert_eq!(contact(f).await.2, json!("armed"), "repeat {k}");
        assert_eq!(run_of(f).await["unanswered_periods"], 0, "repeat {k}");
    }
    assert_eq!(contact(f).await.0, json!("K1ABC"));
    assert_eq!(run_of(f).await["left"], Value::Null);
}

// Proves: TC-039-043 (e). A caller selected on its call that repeats that call has not answered:
// W1AW repeating its first call is left at the 4th.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_043_a_caller_repeating_its_first_call_is_left_at_the_4th() {
    let call = ("HB9BLA W1AW FN31", 1200.0, Some(-10.0));
    let t = leaving(|_| {}, &[call]).await;
    let (f, e) = (&t.f, t.e);
    assert_eq!(contact(f).await.0, json!("W1AW"));
    for k in 1..=3 {
        publish(f, rep(e, k), &[call]);
        assert_eq!(contact(f).await.2, json!("armed"), "repeat {k}");
    }
    publish(f, rep(e, 4), &[call]);
    assert_eq!(contact(f).await.2, json!("disarmed"));
    assert_eq!(
        run_of(f).await["left"],
        json!({"call":"W1AW","reason":"repetitions"})
    );
}

// Proves: TC-039-043 (f). No change before an exit criterion: a stronger new CQ DL1XYZ from the 2nd
// repetition on never ends the contact with K1ABC; DL1XYZ is selected at the step after the 4th.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_043_a_more_valuable_cq_waits_for_the_exit() {
    let t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    let dl = ("CQ DL1XYZ JO62", 1200.0, Some(9.0));
    publish(f, rep(e, 1), &[]);
    for k in 2..=3 {
        publish(f, rep(e, k), &[dl]);
        assert_eq!(contact(f).await.0, json!("K1ABC"), "repetition {k}");
    }
    publish(f, rep(e, 4), &[dl]);
    assert_eq!(
        contact(f).await,
        (Value::Null, json!("cancelled"), json!("disarmed"))
    );
    publish(f, rep(e, 5), &[dl]);
    assert_eq!(
        contact(f).await,
        (json!("DL1XYZ"), json!("replying"), json!("armed"))
    );
}

// Proves: TC-039-043 (g). A caller of my call is answered at once while the target has not
// answered: left {K1ABC, caller} and JA1XYZ selected from the same publication; with Callers of my
// call first off, with JA1XYZ in its quiet time and after K1ABC has answered K1ABC is kept.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_043_a_caller_is_answered_at_once_unless_off_quiet_or_answered() {
    let ja = ("HB9BLA JA1XYZ PM95", 1100.0, Some(-15.0));
    let t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    publish(f, rep(e, 1), &[]);
    publish(f, rep(e, 2), &[ja]);
    assert_eq!(
        contact(f).await,
        (json!("JA1XYZ"), json!("report"), json!("armed"))
    );
    let run = run_of(f).await;
    assert_eq!(run["left"], json!({"call":"K1ABC","reason":"caller"}));
    assert_eq!(run["quiet"], quiet_entry("K1ABC", 600));

    let t = leaving(
        |c| c["strategies"][0]["callers_first"] = json!(false),
        &[K1ABC_CQ],
    )
    .await;
    let (f, e) = (&t.f, t.e);
    publish(f, rep(e, 1), &[]);
    publish(f, rep(e, 2), &[ja]);
    assert_eq!(contact(f).await.0, json!("K1ABC"), "callers first off");

    // JA1XYZ left first (silent), so in its quiet time.
    let t = leaving(|_| {}, &[("CQ JA1XYZ PM95", 1100.0, Some(-15.0))]).await;
    let (f, e) = (&t.f, t.e);
    for k in 1..=4 {
        publish(f, rep(e, k), &[]);
    }
    assert_eq!(run_of(f).await["left"]["call"], "JA1XYZ");
    publish(f, rep(e, 5), &[K1ABC_CQ]);
    assert_eq!(contact(f).await.0, json!("K1ABC"));
    publish(f, rep(e, 6), &[ja]);
    assert_eq!(
        contact(f).await,
        (json!("K1ABC"), json!("replying"), json!("armed")),
        "quiet"
    );

    let t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    publish(f, rep(e, 1), &[("HB9BLA K1ABC -05", 1800.0, Some(-5.0))]);
    publish(f, rep(e, 2), &[ja]);
    assert_eq!(contact(f).await.0, json!("K1ABC"), "K1ABC has answered");
    assert_eq!(contact(f).await.2, json!("armed"));
}

// Proves: TC-039-043 (h). A left station is quiet for 10 minutes: its call to my call is not
// answered at 5 min, its CQ is not selected at 9 min 59 s; at 10 min it is selected again.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_043_the_quiet_time_excludes_selection_and_answering() {
    let t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    for k in 1..=4 {
        publish(f, rep(e, k), &[]);
    }
    assert_eq!(run_of(f).await["left"]["call"], "K1ABC");
    at_skew(f, 300);
    assert_eq!(run_of(f).await["quiet"], quiet_entry("K1ABC", 300));
    publish(f, rep(e, 5), &[("HB9BLA K1ABC FN42", 1800.0, Some(-10.0))]);
    assert_eq!(
        contact(f).await.2,
        json!("disarmed"),
        "not answered at 5 min"
    );
    assert_eq!(run_of(f).await["state"], "waiting");
    at_skew(f, 599);
    publish(f, rep(e, 6), &[K1ABC_CQ]);
    assert_eq!(
        contact(f).await.2,
        json!("disarmed"),
        "not selected at 9:59"
    );
    at_skew(f, 600);
    assert_eq!(run_of(f).await["quiet"], json!([]));
    publish(f, rep(e, 7), &[K1ABC_CQ]);
    assert_eq!(
        contact(f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
}

// Proves: TC-039-043 (i). Repetitions 1: left at the 1st.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_043_one_repetition_leaves_at_the_first() {
    let t = leaving(
        |c| c["strategies"][0]["repetitions"] = json!(1),
        &[K1ABC_CQ],
    )
    .await;
    let (f, e) = (&t.f, t.e);
    assert_eq!(wd(f).await, json!(1));
    publish(f, rep(e, 1), &[]);
    assert_eq!(contact(f).await.2, json!("disarmed"));
    assert_eq!(
        run_of(f).await["left"],
        json!({"call":"K1ABC","reason":"repetitions"})
    );
}

// Proves: TC-039-043 (j). Ends at once, with no quiet time: a band change in the contact, a new
// live identity (FT4), Auto off and HALT disarm and cancel at the next step, left stays null; after
// the band change the run waits and selects from the next publication, after Auto off and HALT it
// has stopped.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_043_band_mode_auto_off_and_halt_end_the_contact_at_once() {
    let t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    publish(f, rep(e, 1), &[]);
    f.state.recording.fixture_band("40m");
    f.tick();
    assert_eq!(
        contact(f).await,
        (Value::Null, json!("cancelled"), json!("disarmed"))
    );
    assert_eq!(
        left_and_quiet(f).await,
        (json!("waiting"), Value::Null, json!([]))
    );
    publish(f, rep(e, 2), &[("CQ DL1XYZ JO62", 1200.0, Some(-5.0))]);
    assert_eq!(
        contact(f).await,
        (json!("DL1XYZ"), json!("replying"), json!("armed"))
    );

    let t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let f = &t.f;
    f.state.recording.fixture_live_job("ft4");
    f.tick();
    assert_eq!(contact(f).await.2, json!("disarmed"));
    assert_eq!(contact(f).await.1, json!("cancelled"));
    assert_eq!(
        left_and_quiet(f).await,
        (json!("waiting"), Value::Null, json!([]))
    );

    let t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let f = &t.f;
    assert_eq!(auto(f, false, None).await.status, StatusCode::OK);
    f.tick();
    assert_eq!(
        contact(f).await,
        (Value::Null, json!("cancelled"), json!("disarmed"))
    );
    assert_eq!(run_state(f).await, ("stopped".into(), json!("stopped")));
    assert_eq!(run_of(f).await["quiet"], json!([]));

    let t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let f = &t.f;
    halt(f).await;
    assert_eq!(
        contact(f).await,
        (Value::Null, json!("cancelled"), json!("disarmed"))
    );
    assert_eq!(run_state(f).await, ("stopped".into(), json!("halted")));
    assert_eq!(run_of(f).await["quiet"], json!([]));
}

/// A contest run with Auto on (WW Digi, 20 m, the period in force, W1DUP a dupe in the log,
/// repetitions 2, quiet_minutes 10 unless `edit` changes them), the feed attached.
async fn contest_leaving(operation: &str, edit: impl FnOnce(&mut Value)) -> Leaving {
    contest_leaving_with(operation, edit, |_, _| {}).await
}
/// `contest_leaving` with `before` run before the selection (waterfall rows for the CQ's slot).
async fn contest_leaving_with(
    operation: &str,
    edit: impl FnOnce(&mut Value),
    before: impl FnOnce(&Mcp, i64),
) -> Leaving {
    contest_leaving_from(true, operation, edit, before).await
}
/// `contest_leaving_with` with Hold Tx `hold_tx` before the selection (#39 holdtx: the Rx = Tx
/// steps of TC-039-044 run with Hold Tx explicitly off).
async fn contest_leaving_from(
    hold_tx: bool,
    operation: &str,
    edit: impl FnOnce(&mut Value),
    before: impl FnOnce(&Mcp, i64),
) -> Leaving {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    before(&f, e);
    let client = f.state.recording.clients.session();
    if !hold_tx {
        hold_off(&f).await;
    }
    f.state.recording.fixture_band("20m");
    import_adi(&f, &logged_before("W1DUP", "EM12", e));
    browser_ok(&f, "set_activity", json!({"activity":"ww_digi"})).await;
    let feed = attach_feed(&f);
    let mut c = contest_config(e, operation, -1);
    edit(&mut c);
    select(&f, c).await;
    f.tick();
    Leaving {
        f,
        e,
        feed,
        client: Some(client),
    }
}
const K1ABC_WW: (&str, f64, Option<f64>) = ("CQ WW K1ABC FN42", 1800.0, Some(-10.0));
const JA1XYZ_WW: (&str, f64, Option<f64>) = ("CQ WW JA1XYZ PM95", 1100.0, Some(-15.0));
/// The S&P contest run calling K1ABC (new multiplier), the feed following it.
async fn contest_calling(edit: impl FnOnce(&mut Value)) -> Leaving {
    let t = contest_leaving("sp", edit).await;
    publish(&t.f, t.e, &[K1ABC_WW]);
    t.f.tick();
    assert_eq!(contact(&t.f).await.0, json!("K1ABC"));
    t
}

// Proves: TC-039-044 (a), (b). A contest leaves at x = 2; a spot of my call at K1ABC doubles it in
// situation 2 (not decoded): left at the 4th.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_044_a_contest_leaves_at_2_and_at_4_with_a_spot() {
    let t = contest_calling(|_| {}).await;
    let (f, e) = (&t.f, t.e);
    publish(f, rep(e, 1), &[]);
    assert_eq!(contact(f).await.2, json!("armed"));
    publish(f, rep(e, 2), &[]);
    assert_eq!(contact(f).await.2, json!("disarmed"));
    assert_eq!(
        run_of(f).await["left"],
        json!({"call":"K1ABC","reason":"repetitions"})
    );

    let t = contest_calling(|_| {}).await;
    let (f, e) = (&t.f, t.e);
    t.feed.inject(&heard_spot(60));
    for k in 1..=3 {
        publish(f, rep(e, k), &[]);
        assert_eq!(contact(f).await.2, json!("armed"), "repetition {k}");
    }
    publish(f, rep(e, 4), &[]);
    assert_eq!(contact(f).await.2, json!("disarmed"));
}

// Proves: TC-039-044 (c), (d). Situation 1 with the spot: K1ABC calling CQ again stays all 10
// repetitions while nothing more valuable is listed, and the dupe W1DUP calling my call never ends
// the stay (the #63 fix); JA1XYZ (more valuable) at the 6th leaves at once and is selected next;
// JA1XYZ from the 1st: K1ABC kept until the 2nd, then left and JA1XYZ selected.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_044_a_heard_target_stays_until_a_more_valuable_station() {
    let dupe = ("HB9BLA W1DUP EM12", 900.0, Some(9.0));
    let t = contest_calling(|_| {}).await;
    let (f, e) = (&t.f, t.e);
    t.feed.inject(&heard_spot(60));
    for k in 1..=10 {
        publish(f, rep(e, k), &[K1ABC_WW, dupe]);
        assert_eq!(
            contact(f).await,
            (json!("K1ABC"), json!("report"), json!("armed")),
            "{k}"
        );
    }
    assert_eq!(run_of(f).await["left"], Value::Null);
    assert_eq!(run_of(f).await["unanswered_periods"], 10);

    let t = contest_calling(|_| {}).await;
    let (f, e) = (&t.f, t.e);
    t.feed.inject(&heard_spot(60));
    for k in 1..=5 {
        publish(f, rep(e, k), &[K1ABC_WW]);
    }
    assert_eq!(contact(f).await.2, json!("armed"));
    publish(f, rep(e, 6), &[K1ABC_WW, JA1XYZ_WW]);
    assert_eq!(contact(f).await.2, json!("disarmed"), "left at once");
    assert_eq!(
        run_of(f).await["left"],
        json!({"call":"K1ABC","reason":"repetitions"})
    );
    publish(f, rep(e, 7), &[K1ABC_WW, JA1XYZ_WW]);
    assert_eq!(
        contact(f).await,
        (json!("JA1XYZ"), json!("report"), json!("armed"))
    );

    let t = contest_calling(|_| {}).await;
    let (f, e) = (&t.f, t.e);
    t.feed.inject(&heard_spot(60));
    publish(f, rep(e, 1), &[K1ABC_WW, JA1XYZ_WW]);
    assert_eq!(
        contact(f).await.0,
        json!("K1ABC"),
        "no change before the exit"
    );
    assert_eq!(contact(f).await.2, json!("armed"));
    publish(f, rep(e, 2), &[K1ABC_WW, JA1XYZ_WW]);
    assert_eq!(contact(f).await.2, json!("disarmed"));
    publish(f, rep(e, 3), &[JA1XYZ_WW]);
    assert_eq!(contact(f).await.0, json!("JA1XYZ"));
}

// Proves: TC-039-044 (e). A non-dupe caller K2NEW at the 1st repetition: left {K1ABC, caller} at
// once and K2NEW selected from the same publication.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_044_a_contest_caller_is_answered_at_once() {
    let t = contest_calling(|_| {}).await;
    let (f, e) = (&t.f, t.e);
    publish(f, rep(e, 1), &[("HB9BLA K2NEW FN31", 1200.0, Some(-8.0))]);
    assert_eq!(contact(f).await.0, json!("K2NEW"));
    assert_eq!(contact(f).await.2, json!("armed"));
    assert_eq!(
        run_of(f).await["left"],
        json!({"call":"K1ABC","reason":"caller"})
    );
}

// Proves: TC-039-044 (f), (g). Run: the caller K2NEW is answered from the CQ's slot (900 stays, not
// the quietest of my Rx parity), then silent it is left at the 2nd, the run calls CQ again and does
// not answer K2NEW in its quiet time. Repetitions 3 and quiet_minutes 1 from the selection: left at
// the 3rd, answered again after 1 minute. Hold Tx explicitly off (#39 holdtx; with it on the
// Run's CQ stays on the held Tx: TC-039-049 (j)); the CQ's slot 900, the quiet one of my Rx
// parity (cq_quiet_rows, #66).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_044_run_leaves_a_silent_caller_and_keeps_it_quiet() {
    let k2 = ("HB9BLA K2NEW FN31", 1200.0, Some(-8.0));
    let t = contest_leaving_from(false, "run", |_| {}, cq_quiet_rows).await;
    let (f, e) = (&t.f, t.e);
    assert_eq!(run_of(f).await["state"], "calling_cq");
    assert_eq!(frequencies(f).await.1, json!(900), "the CQ's slot");
    publish(f, e, &[k2]);
    assert_eq!(contact(f).await.0, json!("K2NEW"));
    assert_eq!(contact(f).await.2, json!("armed"));
    let s = frequencies(f).await;
    assert_eq!(
        (s.0, s.1),
        (json!(900), json!(900)),
        "answered from the CQ's slot"
    );
    publish(f, rep(e, 1), &[]);
    assert_eq!(contact(f).await.2, json!("armed"));
    publish(f, rep(e, 2), &[]);
    f.tick();
    assert_eq!(run_of(f).await["state"], "calling_cq");
    assert_eq!(
        run_of(f).await["left"],
        json!({"call":"K2NEW","reason":"repetitions"})
    );
    publish(f, rep(e, 3), &[k2]);
    assert_eq!(
        run_of(f).await["state"],
        "calling_cq",
        "quiet: not answered"
    );
    assert_eq!(contact(f).await.1, json!("calling"));

    let t = contest_leaving_from(
        false,
        "run",
        |c| {
            c["contest"]["repetitions"] = json!(3);
            c["contest"]["quiet_minutes"] = json!(1);
        },
        |_, _| {},
    )
    .await;
    let (f, e) = (&t.f, t.e);
    publish(f, e, &[k2]);
    for k in 1..=2 {
        publish(f, rep(e, k), &[]);
        assert_eq!(contact(f).await.2, json!("armed"), "{k}");
    }
    publish(f, rep(e, 3), &[]);
    f.tick();
    assert_eq!(
        run_of(f).await["quiet"],
        json!([{"call":"K2NEW","band":"20m","mode":"ft8","remaining_s":60}])
    );
    at_skew(f, 60);
    f.tick();
    publish(f, rep(e, 4), &[k2]);
    assert_eq!(contact(f).await.0, json!("K2NEW"), "after 1 minute");
    assert_eq!(run_of(f).await["state"], "contact_active");
}

// Proves: TC-039-044 (h). The end of the period in a contact disarms and cancels at once and the run
// waits outside_period; the contest deselected in a contact stops it, Auto off.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_044_period_end_and_deselect_end_the_contact_at_once() {
    let t = contest_calling(|_| {}).await;
    let f = &t.f;
    crate::automation_tests::jump_and_tick(f, 3 * 3_600_000);
    assert_eq!(
        contact(f).await,
        (Value::Null, json!("cancelled"), json!("disarmed"))
    );
    assert_eq!(
        run_state(f).await,
        ("waiting".into(), json!("outside_period"))
    );
    assert_eq!(run_of(f).await["quiet"], json!([]));

    let t = contest_calling(|_| {}).await;
    let f = &t.f;
    save(f, config(None)).await;
    f.tick();
    assert_eq!(contact(f).await.2, json!("disarmed"));
    assert_eq!(contact(f).await.1, json!("cancelled"));
    assert_eq!(run_state(f).await, ("stopped".into(), json!("stopped")));
    assert_eq!(
        f.browser("GET", "/strategy", None).await.json["auto"],
        false
    );
}

/// "Casual 20 m" with Auto on (new call on band today, value [snr], CQ when no target), W1AW worked
/// on 20 m today; `cq` false: a user copy with the option off.
async fn casual(cq: bool) -> Leaving {
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let client = f.state.recording.clients.session();
    import_adi(&f, &logged_before("W1AW", "FN31", e));
    f.state.logbook.worked_set().unwrap();
    let feed = attach_feed(&f);
    let mut c = config(Some("Casual 20 m"));
    if !cq {
        let mut s = strategy_json("Casual copy");
        s["goals"] = json!(["new_call_band"]);
        s["window"] = json!({"kind":"today"});
        s["cq_when_no_target"] = json!(false);
        c["strategies"] = json!([s]);
        c["active"] = json!("Casual copy");
    }
    select(&f, c).await;
    f.tick();
    Leaving {
        f,
        e,
        feed,
        client: Some(client),
    }
}

// Proves: TC-039-045. CQ when no target: waiting after one empty publication, calling CQ (Tx6
// "CQ HB9BLA JN47", armed) after the second (W1AW, worked today, is not listed); W1AW calling my
// call is answered from the CQ with Enable Tx kept; after its QSO two empty publications call CQ
// again; a candidate appearing ends the CQ and is called. Off: never a CQ.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_045_cq_when_no_target_calls_answers_and_calls_a_candidate() {
    let t = casual(true).await;
    let (f, e) = (&t.f, t.e);
    publish(f, e, &[]);
    assert_eq!(run_of(f).await["state"], "waiting");
    publish(f, rep(e, 1), &[("CQ W1AW FN31", 900.0, Some(-1.0))]);
    let c = f.read("contact").await;
    assert_eq!(run_of(f).await["state"], "calling_cq", "nothing listed");
    assert_eq!(c["contact"]["state"], "calling");
    assert_eq!(c["contact"]["messages"][5], "CQ HB9BLA JN47");
    assert_eq!(c["transmit"]["arm_state"], "armed");
    publish(f, rep(e, 2), &[]);
    assert_eq!(run_of(f).await["state"], "calling_cq");
    // The caller is answered from the CQ, whatever the filter.
    publish(f, rep(e, 3), &[("HB9BLA W1AW FN31", 1200.0, Some(-10.0))]);
    assert_eq!(
        contact(f).await,
        (json!("W1AW"), json!("report"), json!("armed"))
    );
    assert_eq!(run_of(f).await["state"], "contact_active");
    publish(f, rep(e, 4), &[("HB9BLA W1AW R-05", 1200.0, Some(-10.0))]);
    publish(f, rep(e, 5), &[("HB9BLA W1AW 73", 1200.0, Some(-10.0))]);
    assert_eq!(contact(f).await.1, json!("completed"));
    f.tick();
    assert_eq!(run_of(f).await["state"], "waiting");
    publish(f, rep(e, 6), &[]);
    assert_eq!(run_of(f).await["state"], "waiting");
    publish(f, rep(e, 7), &[]);
    assert_eq!(run_of(f).await["state"], "calling_cq");
    publish(f, rep(e, 8), &[("CQ DL1XYZ JO62", 1500.0, Some(-5.0))]);
    assert_eq!(
        contact(f).await,
        (json!("DL1XYZ"), json!("replying"), json!("armed"))
    );
    assert_eq!(run_of(f).await["state"], "contact_active");

    let t = casual(false).await;
    let (f, e) = (&t.f, t.e);
    for k in 0..6 {
        publish(f, rep(e, k), &[]);
        assert_eq!(run_of(f).await["state"], "waiting");
        assert_eq!(contact(f).await.2, json!("disarmed"));
    }
}

/// The bins of [from, to) Hz: ceil(from / bin) .. ceil(to / bin), as a slot at `from` reads them.
fn bins(from: u32, to: u32) -> std::ops::Range<usize> {
    let bin = |hz: u32| (f64::from(hz) / crate::freeslot::BIN_HZ).ceil() as usize;
    bin(from)..bin(to)
}
/// A busy passband for the hand computations (#66): every bin at `busy`, except in each of the ten
/// segments of the WSJT-X passband floor (81 bins from bin 103) its bins 40..47 at `floor`
/// (418.9..439.5, 656.2..676.8, 893.6..914.1, 1130.9..1151.4, 1368.2..1388.7, 1605.5..1626.0,
/// 1842.8..1863.3, 2080.1..2100.6, 2317.4..2337.9 and 2554.7..2575.2 Hz), and the `bands` (bins,
/// the first that holds a bin) at their own level. Every segment keeps 8 bins at `floor` and none
/// below, so its cutoff is `floor` and the floor `floor` + 0.65 exactly; a slot of 17 or 18 bins
/// off the bands holds at most 8 of them, so with floor 20 and busy 40 it reads at least
/// (8 x 20 + 9 x 40) / 17 = 30.6, a value of 10.
fn comb_row(
    f: &Mcp,
    start: i64,
    floor: u8,
    busy: u8,
    bands: &[(std::ops::Range<usize>, u8)],
    tx: bool,
) {
    let levels: Vec<u8> = (0..1024usize)
        .map(|bin| {
            if let Some(b) = bands.iter().find(|b| b.0.contains(&bin)) {
                return b.1;
            }
            let gap = (103..=912).contains(&bin) && (40..48).contains(&((bin - 103) % 81));
            if gap { floor } else { busy }
        })
        .collect();
    f.state.recording.fixture_detail_row(start, &levels, tx);
}
/// The CQ's table (#66: judged in my Rx parity only): my 4 even (Rx) periods before e busy
/// (comb_row, floor 20, busy 40) except 900..950 at the floor, my odd periods flat 20. 900 reads
/// rise -0.65, free: value 0; 890 (bins 304..320) holds one busy bin, 1 dB; 910 (311..327) three,
/// 3 dB; every other slot more. So a CQ from Tx 1500 takes 900, value 0.
fn cq_quiet_rows(f: &Mcp, e: i64) {
    for k in 0..4 {
        comb_row(
            f,
            rep(e, k) - 120_000,
            20,
            40,
            &[(bins(900, 950), 20)],
            false,
        );
        wf_row(f, rep(e, k) - 105_000, 20, &[], false);
    }
}
/// 4 periods of each parity before e, flat 20, the parity `loud` (my Rx parity even, my Tx parity
/// odd) 60 at 1500..1550 (bins 512..529), the current Tx's slot.
fn cq_rows(f: &Mcp, e: i64, loud: wstx_rust::transmit::Parity) {
    let band = |p| {
        if p == loud {
            vec![(1500, 1550, 60)]
        } else {
            vec![]
        }
    };
    for k in 0..4 {
        use wstx_rust::transmit::Parity::{Even, Odd};
        wf_row(f, rep(e, k) - 120_000, 20, &band(Even), false);
        wf_row(f, rep(e, k) - 105_000, 20, &band(Odd), false);
    }
}
/// A detailed waterfall row of the period starting at `start`: `floor` in every bin, each band
/// [from, to) Hz at its level; `tx`: a period I transmitted in.
fn wf_row(f: &Mcp, start: i64, floor: u8, bands: &[(u32, u32, u8)], tx: bool) {
    let levels: Vec<u8> = (0..1024)
        .map(|bin| {
            let hz = f64::from(bin) * crate::freeslot::BIN_HZ;
            bands
                .iter()
                .find(|(from, to, _)| hz >= f64::from(*from) && hz < f64::from(*to))
                .map_or(floor, |b| b.2)
        })
        .collect();
    f.state.recording.fixture_detail_row(start, &levels, tx);
}

// Proves: TC-039-045. The Tx watchdog stops the run's CQ at its limit (stopped tx_watchdog, Auto off,
// not keyed again); the CQ's slot is the quiet one of my Rx parity (cq_quiet_rows: 900, value 0);
// unattended the CQ is disarmed and cancelled at once (stopped no_client).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_045_the_watchdog_and_no_client_end_the_cq_and_its_slot_is_quiet() {
    let t = casual(true).await;
    let (f, e) = (&t.f, t.e);
    // #39 holdtx: Hold Tx explicitly off, the CQ takes its slot (with it on: TC-039-049 (h)).
    hold_off(f).await;
    browser_watchdog(f, 2).await;
    cq_quiet_rows(f, e);
    publish(f, e, &[]);
    publish(f, rep(e, 1), &[]);
    assert_eq!(run_of(f).await["state"], "calling_cq");
    assert_eq!(
        frequencies(f).await,
        (
            json!(900),
            json!(900),
            json!({"hz":900,"power_db":0,"his_end":"unknown"})
        )
    );
    transmit_own_period(f, e + 15_000).await;
    transmit_own_period(f, rep(e, 1) + 15_000).await;
    let keys = f.keys();
    not_keyed_in(f, rep(e, 2) + 15_000).await;
    f.tick();
    f.tick();
    assert_eq!(run_state(f).await, ("stopped".into(), json!("tx_watchdog")));
    assert_eq!(
        f.browser("GET", "/strategy", None).await.json["auto"],
        false
    );
    assert_eq!(f.keys(), keys, "not keyed again");

    let mut t = casual(true).await;
    let e = t.e;
    publish(&t.f, e, &[]);
    publish(&t.f, rep(e, 1), &[]);
    assert_eq!(run_of(&t.f).await["state"], "calling_cq");
    drop(t.client.take());
    let f = &t.f;
    f.tick();
    at_skew(f, 60);
    assert_eq!(quiet_run(f), ("stopped".into(), json!("no_client")));
    assert_eq!(
        quiet_contact(f).await,
        (Value::Null, json!("idle"), json!("disarmed")),
        "the CQ cancelled"
    );
}

// Proves: CL-039-22; TC-039-045 (the slot of the CQ with one parity loud, #66). The CQ judges my
// Rx parity only (even, the other of its odd Tx parity): 4 periods of each parity flat 20, one
// parity 60 at 1500..1550 (the current Tx). Loud in my Tx parity: ignored, the CQ stays on 1500,
// value 0 (rise -0.65 under the floor 20.65, free); loud in my Rx parity: avoided, the CQ goes to the nearest floor slot, 1450
// and 1550 both 50 Hz away, the lower. Red on the parent: it takes the larger rise of both parities
// while listening and leaves 1500 in both.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_045_the_cqs_slot_is_judged_in_my_rx_parity() {
    use wstx_rust::transmit::Parity::{Even, Odd};
    for (loud, expected) in [(Odd, 1500), (Even, 1450)] {
        let t = casual(true).await;
        let (f, e) = (&t.f, t.e);
        hold_off(f).await;
        cq_rows(f, e, loud);
        publish(f, e, &[]);
        publish(f, rep(e, 1), &[]);
        assert_eq!(run_of(f).await["state"], "calling_cq");
        assert_eq!(
            frequencies(f).await,
            (
                json!(expected),
                json!(expected),
                json!({"hz":expected,"power_db":0,"his_end":"unknown"})
            ),
            "loud in {loud:?}"
        );
    }
}

// Proves: TC-039-010. The router: my Rx parity (even, K1ABC's) is busy (comb_row, floor 20, busy
// 40) except a quiet band at 1800..1850 Hz in its last 3 received periods; the 5th older (quiet at
// 600, 90 at 1800) and a transmitted period (90, quiet at 600) do not count, nor my odd periods
// (flat 20, #66). Tx and Rx 1800 before the first call, tx_slot {1800, 0, unknown}: 1800 reads its
// floor 20 against the floor 20.65 (1810 also holds only floor bins, the band and the segment's
// floor bins 629..636, but is farther from 1500; every other slot holds busy bins); the whole QSO
// stays there; with Hold Tx off the selection's Tx goes back to the slot. Hold Tx explicitly off
// from the start (with it on: TC-039-049).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_010_the_run_calls_from_the_quietest_slot_of_its_rx_parity() {
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    hold_off(&f).await;
    select(&f, config(Some("Test calls"))).await;
    let quiet = [(bins(1800, 1850), 20)];
    comb_row(
        &f,
        e - 150_000,
        20,
        40,
        &[(bins(600, 650), 20), (bins(1800, 1850), 90)],
        false,
    );
    wf_row(&f, e - 135_000, 20, &[], false);
    for k in 1..=3 {
        comb_row(&f, e - 150_000 + k * 30_000, 20, 40, &quiet, false);
        wf_row(&f, e - 135_000 + k * 30_000, 20, &[], false);
    }
    wf_row(&f, e - 30_000, 90, &[(600, 650, 0)], true);
    wf_row(&f, e - 15_000, 20, &[], false);
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-5.0))]);
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
    assert_eq!(
        frequencies(&f).await,
        (
            json!(1800),
            json!(1800),
            json!({"hz":1800,"power_db":0,"his_end":"unknown"})
        )
    );
    publish(&f, rep(e, 1), &[("HB9BLA K1ABC -10", 1500.0, Some(-10.0))]);
    assert_eq!(contact(&f).await.1, json!("roger_report"));
    assert_eq!(frequencies(&f).await.1, json!(1800));
    publish(&f, rep(e, 2), &[("HB9BLA K1ABC RR73", 1500.0, Some(-10.0))]);
    transmit_own_period(&f, e + 15_000).await;
    assert_eq!(contact(&f).await.1, json!("completed"));
    assert_eq!(frequencies(&f).await.1, json!(1800));
    f.tick();
    // Hold Tx off: the selection moves Tx to the station, the run takes it back to the slot.
    mcp_contact(&f, "set_hold_tx", json!({"enabled":false})).await;
    assert_eq!(f.read("contact").await["settings"]["hold_tx"], false);
    publish(&f, rep(e, 3), &[("CQ DL1XYZ JO62", 1300.0, Some(-5.0))]);
    assert_eq!(contact(&f).await.0, json!("DL1XYZ"));
    assert_eq!(frequencies(&f).await.1, json!(1800));
}

// Proves: TC-039-010. After a station band change within the job only the new band's periods count:
// no power yet keeps Tx (power_db null); a caller on my slot is answered from the quietest slot away
// from it; a pounce calls from the quietest slot. Hold Tx explicitly off (#39 holdtx). The new
// band's even period: a flat floor of 20 (floor 20.65, a free slot 0) with 1350..1450 at 40; its
// odd period 0 (my Tx parity, not judged, #66). The caller at 1500 on my Tx forbids 1410..1590: the
// free slots nearest to 1500 are 1600 (100 Hz) and 1300 (200 Hz; 1310..1400 hold busy bins), so
// 1600. The pounce on G4ABC at 1650 forbids 1560..1740 for my Tx 1600: 1550 (50 Hz, its bins
// 530..546 free) before 1750.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_010_a_band_change_a_caller_on_my_slot_and_a_pounce() {
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    hold_off(&f).await;
    select(&f, config(Some("Test calls"))).await;
    for k in 0..4 {
        wf_row(&f, e - 120_000 + k * 30_000, 40, &[(1800, 1850, 20)], false);
    }
    f.tick();
    f.state.recording.fixture_band("40m");
    f.tick();
    // The station clock two minutes on, so that the new band's periods below have ended.
    f.bench.offset.fetch_add(120_000, Ordering::SeqCst);
    publish(&f, e, &[("CQ K1ABC FN42", 1000.0, Some(-5.0))]);
    assert_eq!(
        frequencies(&f).await,
        (
            json!(1500),
            json!(1500),
            json!({"hz":1500,"power_db":null,"his_end":"unknown"})
        ),
        "the 20 m periods do not count"
    );
    browser_ok(&f, "cancel", json!({})).await;
    f.tick();
    f.tick();
    // The new band's periods: a flat 20 with 1350..1450 at 40; my odd period 0.
    wf_row(&f, rep(e, 2), 20, &[(1350, 1450, 40)], false);
    wf_row(&f, rep(e, 2) + 15_000, 0, &[], false);
    // A caller on 1500, my slot: answered from the quietest slot away from it.
    publish(
        &f,
        rep(e, 3),
        &[("HB9BLA DL1XYZ JO62", 1500.0, Some(-10.0))],
    );
    assert_eq!(contact(&f).await.0, json!("DL1XYZ"));
    let s = frequencies(&f).await;
    assert_eq!(
        (s.1, s.2),
        (
            json!(1600),
            json!({"hz":1600,"power_db":0,"his_end":"unknown"})
        )
    );
    // A pounce calls from the quietest slot.
    let p = f.state.recording.contact.get().unwrap();
    p.automation.end_strategy_run(p, &f.state);
    f.tick();
    assert_eq!(pounce(&f, "G4ABC", 5).await.status, StatusCode::ACCEPTED);
    publish(&f, rep(e, 4), &[("CQ G4ABC IO91", 1650.0, Some(-5.0))]);
    assert_eq!(contact(&f).await.0, json!("G4ABC"));
    assert_eq!(
        frequencies(&f).await,
        (
            json!(1550),
            json!(1550),
            json!({"hz":1550,"power_db":0,"his_end":"unknown"})
        )
    );
}

/// The TC-039-022 run: Tx watchdog 2, repetitions 4, calling K1ABC (CQ at 1800 Hz) from Tx 1500 on
/// 20 m with no power yet, Hold Tx explicitly off (#39 holdtx; with it on: TC-039-049); `set`
/// prepares the feed. My odd period before the run transmits reads 0 everywhere (my Tx parity, not
/// judged, #66). The even rows of `slot_rows` move the quietest slot: 1400 at the 1st repetition,
/// 1300 at the 2nd, tied with 1300 at the 3rd.
async fn slot_check(set: impl FnOnce(&crate::pskr::Feed)) -> Leaving {
    let t = leaving_from(false, |_| {}, &[K1ABC_CQ]).await;
    browser_watchdog(&t.f, 2).await;
    assert_eq!(frequencies(&t.f).await.1, json!(1500));
    wf_row(&t.f, t.e - 15_000, 0, &[], false);
    set(&t.feed);
    t
}
/// The even row of repetition `k`, in the period before its publication: a flat floor of 20
/// (floor 20.65, a free slot 0), at the 1st 1450..1650 at 40, so that from Tx 1500 (K1ABC's 1800
/// forbids 1710..1890) the nearest free slot is 1400 (100 Hz; 1650 is 150 Hz away); at the 2nd
/// 1350..1650 at 40, so that 1400 is busy in its busiest period and from 1400 the nearest slot free
/// in both is 1300 (100 Hz; 1650 is 250 Hz away); from the 3rd flat, so 1300 stays tied.
fn slot_rows(f: &Mcp, e: i64, k: i64) {
    let bands: &[(u32, u32, u8)] = match k {
        1 => &[(1450, 1650, 40)],
        2 => &[(1350, 1650, 40)],
        _ => &[],
    };
    let start = rep(e, k) - 30_000;
    wf_row(f, start, 20, bands, false);
    // The period has ended by the station clock, so that it counts.
    let now = f.bench.now_utc_ms();
    if now < start + 15_000 {
        f.bench
            .offset
            .fetch_add(start + 15_000 - now, Ordering::SeqCst);
    }
}

// Proves: TC-039-022. Without a known hearing (no spot, 601 s, 40 m, Use off, feed off) Tx and Rx
// move to the quietest slot at each repetition (1400, 1300) and stay on a tie (1300 free, 0, the
// current Tx among the free slots); every repetition is keyed past the watchdog limit 2 and WD counts 4, 3, 2, 1; a spot 60 s
// or 590 s old keeps Tx at 1500 and WD counts from 8; slot_check names the repetition and hearing.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_022_the_slot_check_at_every_repetition() {
    type Set = fn(&crate::pskr::Feed);
    let table: [(&str, Set, bool); 7] = [
        ("no spot", |_| {}, false),
        ("60 s", |feed| feed.inject(&heard_spot(60)), true),
        ("590 s", |feed| feed.inject(&heard_spot(590)), true),
        ("601 s", |feed| feed.inject(&heard_spot(601)), false),
        (
            "40 m",
            |feed| {
                let t = crate::contact_http_tests::now_ms() / 1000 - 60;
                feed.inject(&spot_of("HB9BLA", "K1ABC", 7_075_500, "40m", t));
            },
            false,
        ),
        (
            "Use off",
            |feed| {
                feed.inject(&heard_spot(60));
                feed.switch_use(false);
            },
            false,
        ),
        (
            "feed off",
            |feed| {
                feed.inject(&heard_spot(60));
                feed.switch(false);
            },
            false,
        ),
    ];
    for (name, set, heard) in table {
        let t = slot_check(set).await;
        let (f, e) = (&t.f, t.e);
        let x = if heard { 8 } else { 4 };
        assert_eq!(wd(f).await, json!(x), "{name}");
        let moves = [1400, 1300, 1300];
        for k in 1..=3 {
            transmit_own_period(f, rep(e, k - 1) + 15_000).await;
            slot_rows(f, e, k);
            publish(f, rep(e, k), &[]);
            let s = f.read("contact").await;
            let hz = if heard { 1500 } else { moves[k as usize - 1] };
            assert_eq!(
                (
                    s["settings"]["tx_hz"].clone(),
                    s["settings"]["rx_hz"].clone()
                ),
                (json!(hz), json!(hz)),
                "{name}, repetition {k}"
            );
            assert_eq!(s["transmit"]["arm_state"], "armed", "{name}");
            assert_eq!(s["watchdog"]["tx_expired"], false, "{name}");
            assert_eq!(wd(f).await, json!(x - k), "{name}, repetition {k}");
            assert_eq!(
                run_of(f).await["slot_check"],
                json!({"repetitions":k,"hears_us":heard,"hz":hz}),
                "{name}"
            );
        }
        assert_eq!(f.keys(), 6, "{name}: every repetition keyed and released");
    }
}

// Proves: TC-039-022. A target that has answered keeps its slot for the whole exchange: after the
// partner's report at the 2nd repetition Tx never moves again.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_022_an_answer_keeps_the_slot() {
    let t = slot_check(|_| {}).await;
    let (f, e) = (&t.f, t.e);
    slot_rows(f, e, 1);
    publish(f, rep(e, 1), &[]);
    assert_eq!(frequencies(f).await.1, json!(1400));
    slot_rows(f, e, 2);
    publish(f, rep(e, 2), &[("HB9BLA K1ABC -09", 1800.0, Some(-9.0))]);
    for k in 3..=5 {
        slot_rows(f, e, 2);
        publish(f, rep(e, k), &[]);
        assert_eq!(frequencies(f).await.1, json!(1400), "repetition {k}");
    }
}

// Proves: TC-039-022. A refused move changes nothing and is checked again at the next repetition.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_022_a_refused_move_is_checked_again() {
    let t = slot_check(|_| {}).await;
    let (f, e) = (&t.f, t.e);
    let state = f.state.clone();
    let (id, boot) = (f.id.clone(), f.boot.clone());
    // The operator's command lands between the decision and the move: the move is stale.
    *f.state
        .recording
        .contact
        .get()
        .unwrap()
        .automation
        .before_slot_move
        .lock()
        .unwrap() = Some(Box::new(move || {
        let station = state.recording.contact.get().unwrap();
        let body = json!({"v":1,"profile_id":id,"boot_id":boot,"command_id":profile::new_uuid().unwrap(),
                "contact_revision":station.facts().0,"action":"set_hold_tx","enabled":true});
        station
            .operate_as(&state, body, true, authorization::Principal::Browser)
            .unwrap();
    }));
    slot_rows(f, e, 1);
    publish(f, rep(e, 1), &[]);
    assert_eq!(frequencies(f).await.1, json!(1500), "refused");
    assert_eq!(contact(f).await.2, json!("armed"));
    publish(f, rep(e, 2), &[]);
    assert_eq!(frequencies(f).await.1, json!(1400), "checked again");
}

// Proves: TC-039-033, TC-039-022. Unattended (no client for 60 s): the stop at N is back at once,
// and K1ABC silent with a spot of my call is left at 4 repetitions, not 8; then the run stops
// no_client.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_033_unattended_x_is_never_doubled() {
    let mut t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let e = t.e;
    t.feed.inject(&heard_spot(60));
    drop(t.client.take());
    let f = &t.f;
    f.tick();
    at_skew(f, 60);
    assert_eq!(quiet_run(f).0, "contact_active");
    f.tick();
    assert_eq!(
        f.browser("GET", "/contact", None).await.json["watchdog"]["tx_remaining_calls"],
        6,
        "the stop at N is back"
    );
    for k in 1..=3 {
        publish(f, rep(e, k), &[]);
        assert_eq!(quiet_contact(f).await.2, json!("armed"), "{k}");
    }
    publish(f, rep(e, 4), &[]);
    assert_eq!(quiet_contact(f).await.2, json!("disarmed"));
    f.tick();
    assert_eq!(quiet_run(f), ("stopped".into(), json!("no_client")));
    assert_eq!(f.keys(), 0);
}

// Proves: TC-039-048. The run snapshot's hearing and his end: heard {t, -12} with a spot of my call,
// unknown with Use off; his decoded frequency of my Tx parity (odd) at the quietest slot sends Tx to
// the next quietest with his_end yes, one of the other parity excludes nothing, his frequencies
// everywhere leave the quietest with his_end no.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_048_the_run_shows_the_hearing_and_his_end() {
    let t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    assert_eq!(
        run_of(f).await["hearing"],
        json!({"state":"unknown","spot_utc_s":null,"snr_db":null})
    );
    let now = crate::contact_http_tests::now_ms() / 1000;
    t.feed
        .inject(&spot_of("HB9BLA", "K1ABC", 14_075_500, "20m", now - 60));
    f.tick();
    assert_eq!(
        run_of(f).await["hearing"],
        json!({"state":"heard","spot_utc_s":now - 60,"snr_db":-12})
    );
    t.feed.switch_use(false);
    f.tick();
    assert_eq!(run_of(f).await["hearing"]["state"], "unknown");
    // Use off is also no his end: the slot check (not heard) has the power alone. My even period
    // busy (comb_row, floor 20, busy 40) except 1300..1350 at 20 (rise -0.65, free: value 0) and
    // 1650..1700 at 22 (22 - 20.65 = 1.35, value 1); every other slot holds busy bins (1290 three
    // of 17, 3 dB; 1660 three, 5 dB). My odd period reads 0 (my Tx parity, not judged, #66).
    let rows = |f: &Mcp, e: i64| {
        wf_row(f, e - 45_000, 0, &[], false);
        comb_row(
            f,
            e - 30_000,
            20,
            40,
            &[(bins(1300, 1350), 20), (bins(1650, 1700), 22)],
            false,
        );
    };
    rows(f, e);
    publish(f, rep(e, 1), &[]);
    assert_eq!(
        run_of(f).await["tx_slot"],
        json!({"hz":1300,"power_db":0,"his_end":"unknown"})
    );
    // A run not heard: his decoded frequencies of my Tx parity decide.
    let t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    let odd = |s: i64| if s.div_euclid(15) % 2 == 1 { s } else { s - 15 };
    // 1320 Hz of my Tx parity excludes 1300; 1650 Hz of the other parity excludes nothing.
    t.feed.inject(&spot_of(
        "DL1XYZ",
        "K1ABC",
        14_075_320,
        "20m",
        odd(now) - 30,
    ));
    t.feed
        .inject(&spot_of("G4ABC", "K1ABC", 14_075_650, "20m", odd(now) - 15));
    rows(f, e);
    publish(f, rep(e, 1), &[]);
    assert_eq!(
        run_of(f).await["tx_slot"],
        json!({"hz":1650,"power_db":1,"his_end":"yes"})
    );
    // His frequencies of my Tx parity everywhere: his end ignored.
    // 27 offsets 90 Hz apart (the feed keeps at most 32): every candidate within 45 Hz of one.
    for hz in (300..=2650).step_by(90) {
        t.feed.inject(&spot_of(
            "W1AW",
            "K1ABC",
            14_074_000 + hz,
            "20m",
            odd(now) - 60,
        ));
    }
    publish(f, rep(e, 2), &[]);
    assert_eq!(
        run_of(f).await["tx_slot"],
        json!({"hz":1300,"power_db":0,"his_end":"no"})
    );
}

// Proves: TC-039-022, TC-039-044 (c). WD in a contest stay: 3 at the 1st repetition with the spot
// (2x = 4), null (WD:∞) once K1ABC in situation 1 stays at the 2nd, and a number again (1, the
// next repetition leaves) once the spot is older than 600 s.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_022_wd_is_infinite_in_a_contest_stay_and_a_number_after_the_spot() {
    let t = contest_calling(|_| {}).await;
    let (f, e) = (&t.f, t.e);
    t.feed.inject(&heard_spot(596));
    publish(f, rep(e, 1), &[K1ABC_WW]);
    assert_eq!(wd(f).await, json!(3));
    publish(f, rep(e, 2), &[K1ABC_WW]);
    assert_eq!(contact(f).await.2, json!("armed"), "it stays");
    assert_eq!(wd(f).await, Value::Null, "WD:∞");
    tokio::time::sleep(Duration::from_secs(6)).await;
    assert_eq!(wd(f).await, json!(1));
    assert_eq!(run_of(f).await["hearing"]["state"], "unknown");
    publish(f, rep(e, 3), &[K1ABC_WW]);
    assert_eq!(contact(f).await.2, json!("disarmed"));
}

// Proves: TC-039-045. A caller is answered from the CQ's slot: the CQ on 900 (the quiet slot of my
// Rx parity, cq_quiet_rows), a caller at 1200 Hz keeps Tx and Rx on 900; a caller at 920 Hz,
// within 50 Hz of the slot, moves Tx and Rx to the nearest candidate away from it: 820 (my 50 Hz
// signal 50 Hz below its 920..970). Hold Tx explicitly off (#39 holdtx; with it on: TC-039-049
// (h)).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_045_a_caller_is_answered_from_the_cqs_slot() {
    for (hz, expected) in [(1200.0, 900), (920.0, 820)] {
        let t = casual(true).await;
        let (f, e) = (&t.f, t.e);
        hold_off(f).await;
        cq_quiet_rows(f, e);
        publish(f, e, &[]);
        publish(f, rep(e, 1), &[]);
        assert_eq!(run_of(f).await["state"], "calling_cq");
        assert_eq!(frequencies(f).await.1, json!(900), "the CQ's slot");
        publish(f, rep(e, 2), &[("HB9BLA DL1XYZ JO62", hz, Some(-10.0))]);
        assert_eq!(contact(f).await.0, json!("DL1XYZ"));
        let s = frequencies(f).await;
        assert_eq!(
            (s.0, s.1),
            (json!(expected), json!(expected)),
            "caller at {hz}"
        );
        assert_eq!(s.2["hz"], json!(expected));
    }
}

// Proves: TC-039-042. With Auto off a selection only marks: a pounce armed on K1ABC keeps running
// and armed when the browser selects "Test calls"; Auto on then ends it.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_042_a_selection_with_auto_off_leaves_a_pounce_running() {
    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    assert_eq!(pounce(&f, "K1ABC", 5).await.status, StatusCode::ACCEPTED);
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-5.0))]);
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
    save(&f, config(Some("Test calls"))).await;
    f.tick();
    assert_eq!(
        f.browser("GET", "/strategy", None).await.json["auto"],
        false
    );
    assert_eq!(run_state(&f).await, ("contact_active".into(), Value::Null));
    assert_eq!(f.read("automation").await["run"]["pounce"]["call"], "K1ABC");
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
    // Auto on: the operator wins over the pounce.
    assert_eq!(auto(&f, true, None).await.status, StatusCode::OK);
    f.tick();
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (run["state"].clone(), run["pounce"].clone()),
        (json!("waiting"), Value::Null)
    );
}

// #39 holdtx (TC-039-049, TC-039-050). Oracle: the operator's rule of 2026-11-07, hand-worked in
// each test: with Hold Tx on a run keeps Tx and Rx is on the station; Tx alone moves at the slot
// check of a target that does not hear us, or 50 Hz clear of a station within 50 Hz of it; a CQ
// goes out on the held Tx. Quietness is a slot's largest rise above the passband floor in my Rx
// periods (#66).

/// The station clock past `end_ms`, so that a waterfall period ending there counts.
fn ended(f: &Mcp, end_ms: i64) {
    let now = f.bench.now_utc_ms();
    if now < end_ms {
        f.bench.offset.fetch_add(end_ms - now, Ordering::SeqCst);
    }
}
/// A strategy run with Auto on, on 20 m in `mode` ("Test calls", repetitions 4, quiet_minutes 10),
/// Hold Tx on as a fresh station has it, Tx at `tx` (else 1500); `first` published in the even
/// period e selects the target; the feed follows it.
async fn held_run(
    mode: &'static str,
    tx: Option<u32>,
    first: &[(&str, f64, Option<f64>)],
) -> Leaving {
    held_run_with(mode, tx, |_, _| {}, first).await
}
/// `held_run` with `rows` written to the waterfall before the selection in e.
async fn held_run_with(
    mode: &'static str,
    tx: Option<u32>,
    rows: impl FnOnce(&Mcp, i64),
    first: &[(&str, f64, Option<f64>)],
) -> Leaving {
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job(mode);
    let e = at_even(&f);
    let client = f.state.recording.clients.session();
    assert_eq!(
        f.read("contact").await["settings"]["hold_tx"],
        true,
        "Hold Tx on by default"
    );
    if let Some(hz) = tx {
        set_tx(&f, hz).await;
    }
    rows(&f, e);
    let feed = attach_feed(&f);
    let mut c = config(Some("Test calls"));
    c["strategies"][0]["repetitions"] = json!(4);
    c["strategies"][0]["quiet_minutes"] = json!(10);
    select(&f, c).await;
    publish(&f, e, first);
    f.tick();
    Leaving {
        f,
        e,
        feed,
        client: Some(client),
    }
}
/// (Rx, Tx) of the contact snapshot.
async fn rx_tx(f: &Mcp) -> (Value, Value) {
    let s = f.read("contact").await["settings"].clone();
    (s["rx_hz"].clone(), s["tx_hz"].clone())
}

// Proves: TC-039-049 (a), (b). Hold Tx on: selecting K1ABC (CQ at 1800) leaves Tx on 1500 and puts
// Rx on 1800, tx_slot names the held 1500 (no power yet); at the unanswered repetitions with no
// spot Tx alone takes the quietest slot, 1400 then 1300 (slot_rows, each a free slot of value 0),
// and Rx stays 1800.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_049_hold_tx_on_keeps_tx_and_moves_it_alone_when_he_does_not_hear_us() {
    let t = held_run("ft8", None, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    assert_eq!(contact(f).await.2, json!("armed"));
    assert_eq!(
        frequencies(f).await,
        (
            json!(1800),
            json!(1500),
            json!({"hz":1500,"power_db":null,"his_end":"unknown"})
        ),
        "(a) Tx held, Rx on K1ABC"
    );
    wf_row(f, e - 15_000, 0, &[], false);
    for (k, hz) in [(1, 1400), (2, 1300)] {
        transmit_own_period(f, rep(e, k - 1) + 15_000).await;
        slot_rows(f, e, k);
        publish(f, rep(e, k), &[]);
        assert_eq!(
            frequencies(f).await,
            (
                json!(1800),
                json!(hz),
                json!({"hz":hz,"power_db":0,"his_end":"unknown"})
            ),
            "(b) repetition {k}: Tx alone"
        );
        assert_eq!(
            run_of(f).await["slot_check"],
            json!({"repetitions":k,"hears_us":false,"hz":hz})
        );
        assert_eq!(contact(f).await.2, json!("armed"));
    }
}

// Proves: TC-039-049 (c). The slot check keeps 50 Hz from my Rx as well: K1ABC calls CQ again at
// 1600 (his signal moved, Rx stays 1800). The even period busy (comb_row, floor 20, busy 40)
// except 1760..1810 at 20 and 1300..1350 at 21 (both value 0, free). 1760 is 50 Hz clear of
// K1ABC's 1600..1650 but not of my Rx signal 1800..1850 (1760 + 50 + 50 > 1800), so it is
// excluded; candidates clear of both lie at or below 1500, at 1700 and from 1900: the quietest of
// them is 1300 (every other slot holds busy bins).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_049_the_slot_check_never_comes_within_50_hz_of_rx() {
    let t = held_run("ft8", None, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    wf_row(f, e - 15_000, 0, &[], false);
    comb_row(
        f,
        e,
        20,
        40,
        &[(bins(1760, 1810), 20), (bins(1300, 1350), 21)],
        false,
    );
    ended(f, e + 15_000);
    publish(f, rep(e, 1), &[("CQ K1ABC FN42", 1600.0, Some(-10.0))]);
    assert_eq!(rx_tx(f).await, (json!(1800), json!(1300)));
    assert_eq!(
        run_of(f).await["tx_slot"],
        json!({"hz":1300,"power_db":0,"his_end":"unknown"})
    );
}

// Proves: TC-039-049 (d), (e). A spot of my call at K1ABC 60 s old: Tx stays 1500 at the
// repetition, hears_us true. His report after the 1st repetition (Tx 1400): Tx never moves again,
// also with rows that would move it, Rx stays 1800.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_049_a_target_that_hears_us_or_has_answered_keeps_tx() {
    let t = held_run("ft8", None, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    t.feed.inject(&heard_spot(60));
    wf_row(f, e - 15_000, 0, &[], false);
    slot_rows(f, e, 1);
    publish(f, rep(e, 1), &[]);
    assert_eq!(rx_tx(f).await, (json!(1800), json!(1500)), "(d)");
    assert_eq!(
        run_of(f).await["slot_check"],
        json!({"repetitions":1,"hears_us":true,"hz":1500})
    );

    let t = held_run("ft8", None, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    wf_row(f, e - 15_000, 0, &[], false);
    transmit_own_period(f, e + 15_000).await;
    slot_rows(f, e, 1);
    publish(f, rep(e, 1), &[]);
    assert_eq!(rx_tx(f).await, (json!(1800), json!(1400)));
    transmit_own_period(f, rep(e, 1) + 15_000).await;
    slot_rows(f, e, 2);
    publish(f, rep(e, 2), &[("HB9BLA K1ABC -09", 1800.0, Some(-9.0))]);
    assert_eq!(contact(f).await.1, json!("roger_report"));
    for k in 3..=5 {
        transmit_own_period(f, rep(e, k - 1) + 15_000).await;
        // 1300 quieter than the slot Tx is on.
        wf_row(
            f,
            rep(e, k) - 30_000,
            40,
            &[(1300, 1350, 0), (1400, 1450, 60)],
            false,
        );
        ended(f, rep(e, k) - 15_000);
        publish(f, rep(e, k), &[]);
        assert_eq!(contact(f).await.2, json!("armed"), "(e) {k}");
        assert_eq!(rx_tx(f).await, (json!(1800), json!(1400)), "(e) {k}");
    }
}

// Proves: TC-039-049 (f). A station within 50 Hz of the held Tx 1500: Tx goes to the nearest slot
// 50 Hz clear of its signal, the lower on a tie, no power used; Rx on the station. At 1520
// (1520..1570): below needs f + 50 + 50 <= 1520, so 1420 (80 Hz away); above f >= 1620 (120 Hz):
// 1420. A caller at 1530: 1430 (70 Hz) against 1630 (130 Hz): 1430. No power is used (D4): a far
// quiet slot is in the waterfall (my even period busy, comb_row floor 20 busy 40, except 1000..1050
// at the floor, value 0), and Tx still takes the nearest clear slot, power_db 19 (1420, bins
// 485..501, and 1430, bins 489..505, are all busy: 40 - 20.65).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_049_a_station_within_50_hz_moves_tx_50_hz_clear() {
    let rows = |f: &Mcp, e: i64| {
        comb_row(f, e - 30_000, 20, 40, &[(bins(1000, 1050), 20)], false);
        wf_row(f, e - 15_000, 0, &[], false);
    };
    for (first, rx, tx) in [
        (("CQ K1ABC FN42", 1520.0, Some(-10.0)), 1520, 1420),
        (("HB9BLA DL1XYZ JO62", 1530.0, Some(-10.0)), 1530, 1430),
    ] {
        let t = held_run_with("ft8", None, rows, &[first]).await;
        let f = &t.f;
        assert_eq!(contact(f).await.2, json!("armed"), "{rx}");
        assert_eq!(
            frequencies(f).await,
            (
                json!(rx),
                json!(tx),
                json!({"hz":tx,"power_db":19,"his_end":"unknown"})
            ),
            "station at {rx}"
        );
    }
}

// Proves: TC-039-049 (g). FT4, the held Tx 2700 outside the Tx range (300..2610), a station at
// 1000: the selection keeps Tx 2700 (D7), Rx 1000. At the unanswered repetition with no spot 2700
// is no candidate (round 3 Q6): my odd period reads 0, the even one a flat floor of 40, so every
// candidate ties at a rise of 40; were 2700 a candidate the tie would keep it, but it is not, so Tx
// alone goes to the tied candidate nearest 2700, the top of the range, 2610, and Rx stays 1000.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_049_a_held_tx_outside_the_range_is_kept_and_moves_in_at_the_slot_check() {
    let t = held_run("ft4", Some(2700), &[("CQ K1ABC FN42", 1000.0, Some(-10.0))]).await;
    let (f, e) = (&t.f, t.e);
    assert_eq!(contact(f).await.2, json!("armed"));
    assert_eq!(
        frequencies(f).await,
        (
            json!(1000),
            json!(2700),
            json!({"hz":2700,"power_db":null,"his_end":"unknown"})
        ),
        "kept at the selection"
    );
    wf_row(f, e - 7_500, 0, &[], false);
    wf_row(f, e, 40, &[], false);
    ended(f, e + 7_500);
    publish(f, e + 15_000, &[]);
    assert_eq!(rx_tx(f).await, (json!(1000), json!(2610)));
    assert_eq!(
        run_of(f).await["slot_check"],
        json!({"repetitions":1,"hears_us":false,"hz":2610})
    );
}

/// The held CQ's table: both parities a floor of 20, my odd periods 60 at 900..950. Held, the CQ
/// stays on 900 and names its value in my Rx parity (even), 20 - 20.65 clamped, 0 (#66).
fn held_cq_rows(f: &Mcp, e: i64) {
    for k in 0..4 {
        wf_row(f, rep(e, k) - 120_000, 20, &[], false);
        wf_row(f, rep(e, k) - 105_000, 20, &[(900, 950, 60)], false);
    }
}

// Proves: TC-039-049 (h). "Casual 20 m" with Hold Tx on and Tx 900: after two empty publications
// the CQ is keyed on 900 with no slot decision (tx_slot names 900 with its value in my Rx parity,
// 0), Rx unchanged. A caller at 1200 is answered from 900, Rx 1200 (tx_slot 900, 0); a caller at
// 920 (920..970) moves Tx to 820, the nearest slot 50 Hz clear of it (820 + 50 + 50 = 920; above,
// 1020 is 120 Hz away), Rx 920, 0.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_049_the_cq_goes_out_on_the_held_tx_and_its_callers_keep_it() {
    for (hz, expected) in [(1200.0, 900), (920.0, 820)] {
        let t = casual(true).await;
        let (f, e) = (&t.f, t.e);
        set_tx(f, 900).await;
        let rx = rx_tx(f).await.0;
        held_cq_rows(f, e);
        publish(f, e, &[]);
        publish(f, rep(e, 1), &[]);
        assert_eq!(run_of(f).await["state"], "calling_cq");
        assert_eq!(contact(f).await.2, json!("armed"));
        assert_eq!(
            frequencies(f).await,
            (
                rx,
                json!(900),
                json!({"hz":900,"power_db":0,"his_end":"unknown"})
            ),
            "the CQ on the held Tx"
        );
        publish(f, rep(e, 2), &[("HB9BLA DL1XYZ JO62", hz, Some(-10.0))]);
        assert_eq!(contact(f).await.0, json!("DL1XYZ"));
        assert_eq!(
            frequencies(f).await,
            (
                json!(hz as u32),
                json!(expected),
                json!({"hz":expected,"power_db":0,"his_end":"unknown"})
            ),
            "caller at {hz}"
        );
    }
}

// Proves: TC-039-049 (i). Hold Tx switched off during the contact: the next repetition moves Tx
// and Rx together onto the slot (1300, as TC-039-049 (b) computes it).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_049_hold_tx_switched_off_mid_contact_moves_rx_with_tx() {
    let t = held_run("ft8", None, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    wf_row(f, e - 15_000, 0, &[], false);
    transmit_own_period(f, e + 15_000).await;
    slot_rows(f, e, 1);
    publish(f, rep(e, 1), &[]);
    assert_eq!(rx_tx(f).await, (json!(1800), json!(1400)));
    hold_off(f).await;
    transmit_own_period(f, rep(e, 1) + 15_000).await;
    slot_rows(f, e, 2);
    publish(f, rep(e, 2), &[]);
    assert_eq!(contact(f).await.2, json!("armed"));
    assert_eq!(rx_tx(f).await, (json!(1300), json!(1300)));
}

// Proves: TC-039-049 (j). Contest S&P (repetitions 4) as (a) and (b): K1ABC selected at 1800, Tx
// held 1500; repetitions 1 and 2 move Tx alone to 1400 and 1300, Rx stays 1800.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_049_contest_sp_holds_tx_as_a_strategy_run() {
    let t = contest_calling(|c| c["contest"]["repetitions"] = json!(4)).await;
    let (f, e) = (&t.f, t.e);
    assert_eq!(rx_tx(f).await, (json!(1800), json!(1500)), "(a)");
    wf_row(f, e - 15_000, 0, &[], false);
    for (k, hz) in [(1, 1400), (2, 1300)] {
        transmit_own_period(f, rep(e, k - 1) + 15_000).await;
        slot_rows(f, e, k);
        publish(f, rep(e, k), &[K1ABC_WW]);
        assert_eq!(rx_tx(f).await, (json!(1800), json!(hz)), "(b) {k}");
        assert_eq!(contact(f).await.2, json!("armed"));
    }
}

/// A contest Run with Auto on (WW Digi, 20 m, the period in force) from the held Tx 900, the held
/// CQ's table in the waterfall.
async fn contest_run_held() -> Leaving {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    held_cq_rows(&f, e);
    let client = f.state.recording.clients.session();
    f.state.recording.fixture_band("20m");
    import_adi(&f, &logged_before("W1DUP", "EM12", e));
    browser_ok(&f, "set_activity", json!({"activity":"ww_digi"})).await;
    set_tx(&f, 900).await;
    let feed = attach_feed(&f);
    select(&f, contest_config(e, "run", -1)).await;
    f.tick();
    Leaving {
        f,
        e,
        feed,
        client: Some(client),
    }
}

// Proves: TC-039-049 (j). Contest Run as (h): its CQ on the held 900 with no slot decision
// (tx_slot 900, value 0 in my Rx parity); K2NEW calling at 1200 is answered from 900, Rx 1200; at
// 920 Tx moves to 820, Rx 920.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_049_contest_run_calls_cq_on_the_held_tx() {
    for (hz, expected) in [(1200.0, 900), (920.0, 820)] {
        let t = contest_run_held().await;
        let (f, e) = (&t.f, t.e);
        assert_eq!(run_of(f).await["state"], "calling_cq");
        assert_eq!(
            frequencies(f).await.1,
            json!(900),
            "the Run's CQ on the held Tx"
        );
        assert_eq!(
            run_of(f).await["tx_slot"],
            json!({"hz":900,"power_db":0,"his_end":"unknown"})
        );
        publish(f, e, &[("HB9BLA K2NEW FN31", hz, Some(-8.0))]);
        assert_eq!(contact(f).await.0, json!("K2NEW"));
        assert_eq!(contact(f).await.2, json!("armed"));
        assert_eq!(
            rx_tx(f).await,
            (json!(hz as u32), json!(expected)),
            "caller at {hz}"
        );
    }
}

// Proves: TC-039-049 (k). A pounce on K1ABC with Hold Tx on: Tx stays 1500, Rx on K1ABC 1800, and
// it never moves (a pounce has no slot check), also with rows whose quietest slot is 1400.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_049_a_pounce_keeps_the_held_tx() {
    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    assert_eq!(pounce(&f, "K1ABC", 5).await.status, StatusCode::ACCEPTED);
    publish(&f, e, &[("CQ K1ABC FN42", 1800.0, Some(-5.0))]);
    assert_eq!(contact(&f).await.0, json!("K1ABC"));
    assert_eq!(
        frequencies(&f).await,
        (
            json!(1800),
            json!(1500),
            json!({"hz":1500,"power_db":null,"his_end":"unknown"})
        )
    );
    wf_row(&f, e - 15_000, 0, &[], false);
    for k in 1..=2 {
        transmit_own_period(&f, rep(e, k - 1) + 15_000).await;
        slot_rows(&f, e, k);
        publish(&f, rep(e, k), &[]);
        assert_eq!(contact(&f).await.2, json!("armed"), "{k}");
        assert_eq!(rx_tx(&f).await, (json!(1800), json!(1500)), "{k}");
    }
}

/// A detailed waterfall row of the period starting at `start` with `level(hz)` in each bin,
/// rounded to whole dB as the receive's levels are.
fn wf_levels(f: &Mcp, start: i64, level: impl Fn(f64) -> f64, tx: bool) {
    let levels: Vec<u8> = (0..1024)
        .map(|bin| level(f64::from(bin) * crate::freeslot::BIN_HZ).round() as u8)
        .collect();
    f.state.recording.fixture_detail_row(start, &levels, tx);
}
/// The receive filter's roll-off of the 2026-11-07 reproduction: 30 dB, falling linearly from
/// 2400 Hz to 15 dB at 2700 Hz.
fn roll_off(hz: f64) -> f64 {
    if hz < 2400.0 {
        30.0
    } else {
        (30.0 - 15.0 * (hz - 2400.0) / 300.0).max(15.0)
    }
}
/// The roll-off with AA3B 12 dB above it at 2621..2711 Hz (an FT4 signal, 90 Hz wide).
fn with_aa3b(hz: f64) -> f64 {
    roll_off(hz)
        + if (2621.0..2711.0).contains(&hz) {
            12.0
        } else {
            0.0
        }
}
/// A strategy run with Hold Tx explicitly off (the slot sets Rx and Tx, so it is read off the
/// selection), Tx at `tx`; `rows` writes the waterfall before the even period e, in which `first`
/// selects the target.
async fn rise_run(
    mode: &'static str,
    tx: u32,
    rows: impl FnOnce(&Mcp, i64),
    first: &[(&str, f64, Option<f64>)],
) -> Leaving {
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job(mode);
    let e = at_even(&f);
    let client = f.state.recording.clients.session();
    hold_off(&f).await;
    set_tx(&f, tx).await;
    rows(&f, e);
    let feed = attach_feed(&f);
    select(&f, config(Some("Test calls"))).await;
    publish(&f, e, first);
    Leaving {
        f,
        e,
        feed,
        client: Some(client),
    }
}
const KC8ZPI_CQ: (&str, f64, Option<f64>) = ("CQ KC8ZPI EM79", 513.0, Some(-12.0));
/// The FT4 period `index` periods of 7.5 s from e: even indices are my Rx parity (as e), odd mine.
fn ft4(e: i64, index: i64) -> i64 {
    e + 7_500 * index
}

/// The reference vector of TC-039-050 (a): server/tests/vectors/freeslot/roll_off_ft4.json, the
/// independent numpy fit and choice of roll_off_ft4.py next to it (its source and tolerance in it).
fn roll_off_vector() -> Value {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/vectors/freeslot/roll_off_ft4.json");
    let bytes = std::fs::read(&path).unwrap_or_else(|e| {
        panic!(
            "no reference vector {} ({e}): run roll_off_ft4.py there",
            path.display()
        )
    });
    serde_json::from_slice(&bytes).unwrap()
}
/// A station decoded at each of `hz` in the period starting at `period`, published as a record
/// of that period without a tick (a report between two other stations: never a candidate).
fn decoded_in(f: &Mcp, period: i64, hz: &[f64]) {
    let records = hz
        .iter()
        .map(|hz| crate::contact_http_tests::record("G4AAA W1XYZ -10", *hz, Some(-10.0)))
        .collect();
    f.state
        .recording
        .fixture_publish_period(&crate::contact_http_tests::period_text(period), records);
}
/// The open ranges of the station's latest build (#82), as [lo, hi) pairs.
async fn open_ranges(f: &Mcp) -> Vec<(u64, u64)> {
    free_tx_slots(f).await["open"]
        .as_array()
        .expect("open")
        .iter()
        .map(|r| (r[0].as_u64().unwrap(), r[1].as_u64().unwrap()))
        .collect()
}
/// Whether my FT8 signal [hz, hz + 50) lies inside one open range of the latest build.
async fn in_open(f: &Mcp, hz: u64) -> bool {
    open_ranges(f)
        .await
        .iter()
        .any(|(lo, hi)| *lo <= hz && hz + 50 <= *hi)
}
const K1ABC_2400: (&str, f64, Option<f64>) = ("CQ K1ABC FN42", 2400.0, Some(-5.0));

/// `with_aa3b` with an undecoded FT4 station 18 dB above it at 1500.5..1590.5 Hz (bins 513..542),
/// on the current Tx (level and position as roll_off_ft4.py's: every deciding candidate 0.1 dB from
/// a half dB, and the same choice under the parent's rule).
fn with_station(hz: f64) -> f64 {
    with_aa3b(hz)
        + if (1500.5..1590.5).contains(&hz) {
            18.0
        } else {
            0.0
        }
}

// Proves: CL-039-09; TC-039-050 (a), (k). The 2026-11-07 reproduction, FT4: 30 dB flat to 2400 Hz,
// falling to 15 dB at 2700 Hz (a sharp knee the fourth-order floor cannot follow: the roll-off
// slots read about 2 dB below it), AA3B 12 dB above it at 2621..2711 Hz, not decoded, in my 4
// counted Rx periods (my Tx-parity periods without him); the selection of KC8ZPI (513 Hz) from Tx
// 1500, twice. Oracle: the reference vector, an independent numpy fit of each run's floor and the
// choice it implies (roll_off_ft4.py), whose tables are the test's; and the rule by hand: at or
// under the floor a slot is free, 0 (#66 "At or under floor = free"), so the roll-off slots are no
// quieter than the free mid-band. Tx 1500 on the flat floor: kept, power_db 0. Tx 1500 on a station
// 18 dB above the floor at 1500.5..1590.5: to the free slot nearest it, the vector's (a slot holding
// only a few of the station's bins may still read under 0.5, free), power_db 0. Never a slot in
// 2400..2610 (raw level alone would choose 2530 at 21 dB, the floor rule without the clamp 2530
// at -2). A regression guard: green on the parent, red without the clamp.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_050_the_roll_off_is_compared_above_the_passband_floor() {
    type Table = fn(f64) -> f64;
    let v = roll_off_vector();
    let runs: [(&str, Table, Option<u64>); 2] = [
        ("flat", with_aa3b, Some(1500)),
        ("station", with_station, None),
    ];
    for (i, (name, level, kept)) in runs.into_iter().enumerate() {
        let run = &v["runs"][i];
        assert_eq!(run["name"], json!(name));
        let levels: Vec<Value> = (0..1024)
            .map(|bin| json!(level(f64::from(bin) * crate::freeslot::BIN_HZ).round() as u8))
            .collect();
        assert_eq!(
            run["levels_db"],
            json!(levels),
            "{name}: the vector's table"
        );
        let choice = &run["choice"];
        assert_eq!(
            (&choice["mode"], &choice["current_hz"], &choice["called_hz"]),
            (&json!("ft4"), &json!(1500), &json!(513)),
            "{name}"
        );
        let expected = choice["hz"].as_u64().unwrap();
        assert_eq!(choice["power_db"], json!(0), "{name}: a free slot");
        match kept {
            Some(hz) => assert_eq!(expected, hz, "{name}: the current Tx kept"),
            None => assert_ne!(expected, 1500, "{name}: off the station"),
        }
        let rows = move |f: &Mcp, e: i64| {
            for j in (1..=4).rev() {
                wf_levels(f, ft4(e, -2 * j), level, false);
                wf_levels(f, ft4(e, -2 * j + 1), roll_off, false);
            }
        };
        let t = rise_run("ft4", 1500, rows, &[KC8ZPI_CQ]).await;
        let f = &t.f;
        assert_eq!(contact(f).await.0, json!("KC8ZPI"), "{name}");
        let s = frequencies(f).await;
        assert_eq!(
            s,
            (
                json!(expected),
                json!(expected),
                json!({"hz":expected,"power_db":0,"his_end":"unknown"})
            ),
            "{name}"
        );
        let hz = s.1.as_u64().unwrap();
        assert!(!(2400..=2610).contains(&hz), "{name}: never the roll-off");
    }
}

// Proves: CL-039-09; TC-039-050 (b), (k). FT8, a flat floor of 30 (floor 30.65) in my 4 counted Rx
// periods, the current Tx 1500 on a slot 5 dB above it (1500..1550, bins 512..529, at 35), every
// other slot on the floor. Its value is 35 - 30.65 = 4.35, 4; a floor slot's rise -0.65, free: 0.
// The selection of K1ABC (2400) with Hold Tx off leaves 1500 for the nearest floor slot: 1450
// (bins 495..511) and 1550 (bins 530..546), both 50 Hz away, the lower; tx_slot {1450, 0}, and
// 1450 lies in an open range of the station's build (#82: it overlaps no decode). With Hold Tx on
// Tx stays on 1500 and tx_slot names its value 4. Red on the parent: every rise 0 over its own
// usual level, Tx kept.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_050_a_steady_station_on_the_current_tx_is_a_rise_above_the_floor() {
    let rows = |f: &Mcp, e: i64| {
        for j in (1..=4).rev() {
            wf_row(f, e - 30_000 * j, 30, &[(1500, 1550, 35)], false);
        }
    };
    let t = rise_run("ft8", 1500, rows, &[K1ABC_2400]).await;
    assert_eq!(
        frequencies(&t.f).await,
        (
            json!(1450),
            json!(1450),
            json!({"hz":1450,"power_db":0,"his_end":"unknown"})
        )
    );
    assert!(in_open(&t.f, 1450).await, "{:?}", open_ranges(&t.f).await);
    let t = held_run_with("ft8", None, rows, &[K1ABC_2400]).await;
    assert_eq!(
        frequencies(&t.f).await,
        (
            json!(2400),
            json!(1500),
            json!({"hz":1500,"power_db":4,"his_end":"unknown"})
        )
    );
}

// Proves: CL-039-09, CL-065-01; TC-039-050 (c), (k). The busiest period counts. My 4 counted Rx
// periods busy (comb_row, floor 30, busy 40: every slot off the bands holds at least 9 busy bins of
// 17, so reads at least 35.3, a value of at least 5). Slot A, the current Tx 1500 (bins 512..529),
// on the floor in 3 periods and 6 dB above it in the oldest: its largest rise 36 - 30.65 = 5.35, 5.
// Slot B 1950 (bins 666..682) 3 dB above the floor in all 4: 33 - 30.65 = 2.35, 2; the slots
// overlapping it in part hold busy bins and read more (1940: 3 busy and 14 of B, 34.2). So B wins
// with 2 against 5 (the mean, 0.85 against 2.35, would keep A). No slot is at 0, so the station's
// build has no open range (#82). Red on the parent: every rise over its own usual level is 0 but
// A's.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_050_the_busiest_counted_period_counts() {
    let rows = |f: &Mcp, e: i64| {
        for j in (1..=4).rev() {
            let a = if j == 4 { 36 } else { 30 };
            comb_row(
                f,
                e - 30_000 * j,
                30,
                40,
                &[(bins(1500, 1550), a), (bins(1950, 2000), 33)],
                false,
            );
        }
    };
    let t = rise_run("ft8", 1500, rows, &[K1ABC_2400]).await;
    let f = &t.f;
    assert_eq!(
        frequencies(f).await,
        (
            json!(1950),
            json!(1950),
            json!({"hz":1950,"power_db":2,"his_end":"unknown"})
        )
    );
    assert_eq!(open_ranges(f).await, Vec::<(u64, u64)>::new());
}

// Proves: CL-039-09, CL-065-01; TC-039-050 (d), (k). The floor follows each period: my counted Rx
// periods flat 30 in the two older and 32 in the two later. A floor slot reads -0.65 in each (30
// against 30.65, 32 against 32.65), so its value is 0, not raised by the floor change; Tx 1500
// kept, tx_slot {1500, 0}, and 1500 lies in an open range of the station's build (#82). Red on the
// parent: its rise over the usual level is 31 - 30, 1.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_050_a_floor_change_does_not_raise_a_free_slot() {
    let rows = |f: &Mcp, e: i64| {
        for j in (1..=4).rev() {
            wf_row(f, e - 30_000 * j, if j > 2 { 30 } else { 32 }, &[], false);
        }
    };
    let t = rise_run("ft8", 1500, rows, &[K1ABC_2400]).await;
    let f = &t.f;
    assert_eq!(
        frequencies(f).await,
        (
            json!(1500),
            json!(1500),
            json!({"hz":1500,"power_db":0,"his_end":"unknown"})
        )
    );
    assert!(in_open(f, 1500).await, "{:?}", open_ranges(f).await);
}

// Proves: CL-039-09; TC-039-050 (e), (k). One counted period is enough to compare: one Rx period, a
// flat 30 with the current Tx's slot 1500..1550 (bins 512..529) at 35 (value 4.35, 4): Tx leaves
// for the nearest free slot. 1460 and 1540 hold 4 of the band's bins, (4 x 35 + 13 x 30) / 17 -
// 30.65 = 0.53, 1 (not free); so 1450 (the lower of 1450 and 1550), value 0. Red on the parent:
// with one period every rise over its own usual level is 0 and Tx stays.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_050_one_counted_period_compares() {
    let rows = |f: &Mcp, e: i64| wf_row(f, e - 30_000, 30, &[(1500, 1550, 35)], false);
    let t = rise_run("ft8", 1500, rows, &[K1ABC_2400]).await;
    assert_eq!(
        frequencies(&t.f).await,
        (
            json!(1450),
            json!(1450),
            json!({"hz":1450,"power_db":0,"his_end":"unknown"})
        )
    );
}

// Proves: CL-039-09; TC-039-050 (f), (j), (k). Periods that do not count, each with the current Tx's
// slot 1500..1550 at 40 on a flat 30 (which would move Tx if counted): an Rx period I transmitted
// in (30 s before e); a 5th older Rx period (150 s before e); my last Rx periods 3 to 4.5 minutes
// old, as after a change of my Tx parity; and no period at all. In each no period counts: Tx 1500
// kept, power_db null. Red on the parent: it counts the old periods (the last 4 of the parity,
// however old).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_050_transmitted_old_and_absent_periods_never_count() {
    let busy = [(1500, 1550, 40)];
    let cases: [(&str, Vec<(i64, bool)>); 4] = [
        ("transmitted", vec![(1, true)]),
        ("5th older", vec![(5, false)]),
        (
            "3 minutes old",
            vec![(9, false), (8, false), (7, false), (6, false)],
        ),
        ("none", vec![]),
    ];
    for (name, periods) in cases {
        let rows = |f: &Mcp, e: i64| {
            for (j, tx) in &periods {
                wf_row(f, e - 30_000 * j, 30, &busy, *tx);
            }
        };
        let t = rise_run("ft8", 1500, rows, &[K1ABC_2400]).await;
        assert_eq!(
            frequencies(&t.f).await,
            (
                json!(1500),
                json!(1500),
                json!({"hz":1500,"power_db":null,"his_end":"unknown"})
            ),
            "{name}"
        );
    }
}

// Proves: CL-039-09; TC-039-050 (g), (k). After a station band change only later periods count: on
// 20 m my Rx period 30 s before e has the current Tx's slot 1500..1550 at 40 on a flat 30; after
// the change to 40 m one Rx period flat 30. The selection two periods later keeps Tx 1500 at 0
// (the 20 m period counted would move it). Red on the parent: its rise over the usual level is 0.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_050_after_a_band_change_only_later_periods_count() {
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    hold_off(&f).await;
    select(&f, config(Some("Test calls"))).await;
    wf_row(&f, e - 30_000, 30, &[(1500, 1550, 40)], false);
    wf_row(&f, e - 15_000, 0, &[], false);
    f.tick();
    f.state.recording.fixture_band("40m");
    f.tick();
    wf_row(&f, rep(e, 1), 30, &[], false);
    wf_row(&f, rep(e, 1) + 15_000, 30, &[], false);
    ended(&f, rep(e, 2));
    publish(&f, rep(e, 2), &[K1ABC_2400]);
    assert_eq!(contact(&f).await.0, json!("K1ABC"));
    assert_eq!(
        frequencies(&f).await,
        (
            json!(1500),
            json!(1500),
            json!({"hz":1500,"power_db":0,"his_end":"unknown"})
        )
    );
    assert_eq!(free_tx_slots(&f).await["periods"], json!(1));
}

// Proves: CL-039-09; TC-039-050 (h), (k). Values compare in whole dB. One Rx period busy (comb_row,
// floor 30, busy 40); the current Tx's slot 1500 (bins 512..529) at 31 with its bin 520 at 32 or
// at 35: (17 x 31 + 32) / 18 - 30.65 = 0.41 or (17 x 31 + 35) / 18 - 30.65 = 0.57; slot X 1950
// (bins 666..682) with 666..671 at 30 and 672..682 at 31: (6 x 30 + 11 x 31) / 17 - 30.65 = -0.003;
// every other slot holds busy bins and reads at least 1.6 (1940, 1490). 0.41 and -0.003 are both 0:
// a tie, Tx 1500 kept, power_db 0; 0.57 is 1: Tx to 1950, power_db 0. Red on the parent: every rise
// over its own usual level is 0 with one period, Tx kept.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_050_values_compare_in_whole_db() {
    for (bump, expected) in [(32, 1500), (35, 1950)] {
        let rows = move |f: &Mcp, e: i64| {
            comb_row(
                f,
                e - 30_000,
                30,
                40,
                &[
                    (520..521, bump),
                    (bins(1500, 1550), 31),
                    (666..672, 30),
                    (bins(1950, 2000), 31),
                ],
                false,
            );
        };
        let t = rise_run("ft8", 1500, rows, &[K1ABC_2400]).await;
        assert_eq!(
            frequencies(&t.f).await,
            (
                json!(expected),
                json!(expected),
                json!({"hz":expected,"power_db":0,"his_end":"unknown"})
            ),
            "bin 520 at {bump}"
        );
    }
}

// Proves: CL-039-09, CL-065-01; TC-039-050 (i), (k). A period counts only when its levels reach bin
// 921 (2698.2 Hz). My Rx periods 90 and 60 s before e flat 30 (1024 bins); the one 30 s before e
// with the current Tx's slot 1500..1550 at 40 and a station decoded at 1500 in it. Its rows of 922
// bins (to bin 921): it counts, 1500 is busy and on the decoded station, Tx to 1450 (|1450 - 1500|
// is not below 50), periods now 3. Its rows of 921 bins (to bin 920): neither its levels nor its
// decode count, Tx stays 1500 at 0, periods now 2. Red on the parent: it counts the short period.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_050_a_period_counts_only_when_its_levels_reach_bin_921() {
    for (bins_len, expected, now) in [(922, 1450, 3), (921, 1500, 2)] {
        let rows = move |f: &Mcp, e: i64| {
            wf_row(f, e - 90_000, 30, &[], false);
            wf_row(f, e - 60_000, 30, &[], false);
            let mut short: Vec<u8> = (0..1024)
                .map(|bin| {
                    let hz = f64::from(bin) * crate::freeslot::BIN_HZ;
                    if (1500.0..1550.0).contains(&hz) {
                        40
                    } else {
                        30
                    }
                })
                .collect();
            short.truncate(bins_len);
            f.state
                .recording
                .fixture_detail_row(e - 30_000, &short, false);
            decoded_in(f, e - 30_000, &[1500.0]);
        };
        let t = rise_run("ft8", 1500, rows, &[K1ABC_2400]).await;
        let f = &t.f;
        assert_eq!(
            frequencies(f).await,
            (
                json!(expected),
                json!(expected),
                json!({"hz":expected,"power_db":0,"his_end":"unknown"})
            ),
            "{bins_len} bins"
        );
        assert_eq!(
            free_tx_slots(f).await["periods"],
            json!(now),
            "{bins_len} bins"
        );
    }
}

// #65 WstxStrategy::FreeTxSlots on the wire (TC-065-002). Oracle: the operator's rules of
// 2026-11-08 (issue #65 Functionality 1-2) worked by hand from the hand-authored waterfall rows
// below, and the model's exact keys (WstxMcp::AutomationWire, WstxStationProtocol).

/// A status WebSocket peer over the served router with the browser's cookie and Origin and one
/// display subscription (RFC 6455 frames written and read here; client frames masked).
struct Peer {
    stream: std::net::TcpStream,
    pending: Vec<u8>,
    inbox: Vec<Value>,
}
impl Peer {
    fn open(address: std::net::SocketAddr, f: &Mcp, subscription: &str) -> Peer {
        use std::io::{Read, Write};
        let mut stream = std::net::TcpStream::connect(address).unwrap();
        stream
            .set_read_timeout(Some(Duration::from_millis(50)))
            .unwrap();
        let request = [
            "GET /ws HTTP/1.1".to_owned(),
            format!("Host: {address}"),
            format!("Origin: {}", f.app.origin),
            "Connection: Upgrade".to_owned(),
            "Upgrade: websocket".to_owned(),
            "Sec-WebSocket-Version: 13".to_owned(),
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==".to_owned(),
            "Sec-WebSocket-Protocol: wstx.v1".to_owned(),
            format!("Cookie: {}", f.cookie()),
            String::new(),
            String::new(),
        ]
        .join("\r\n");
        stream.write_all(request.as_bytes()).unwrap();
        let (mut head, deadline) = (Vec::new(), Instant::now() + Duration::from_secs(5));
        while !head.ends_with(b"\r\n\r\n") {
            assert!(Instant::now() < deadline, "no upgrade");
            let mut byte = [0u8];
            if let Ok(1) = stream.read(&mut byte) {
                head.push(byte[0]);
            }
        }
        assert!(head.starts_with(b"HTTP/1.1 101"), "{head:?}");
        let mut peer = Peer {
            stream,
            pending: Vec::new(),
            inbox: Vec::new(),
        };
        peer.write(
            1,
            json!({"v":1,"type":subscription,"id":1})
                .to_string()
                .as_bytes(),
        );
        // What follows the subscription's reply stays for the next read.
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            assert!(Instant::now() < deadline, "no subscription reply");
            let messages = peer.read(Duration::from_millis(100));
            if let Some(i) = messages
                .iter()
                .position(|m| m["type"] == "spectrum.subscription")
            {
                peer.inbox = messages[i + 1..].to_vec();
                break;
            }
        }
        peer
    }
    fn write(&mut self, opcode: u8, payload: &[u8]) {
        use std::io::Write;
        let mask = [0x37, 0xfa, 0x21, 0x3d];
        let mut frame = vec![0x80 | opcode];
        match payload.len() {
            n @ 0..=125 => frame.push(0x80 | n as u8),
            n => {
                frame.push(0x80 | 126);
                frame.extend((n as u16).to_be_bytes());
            }
        }
        frame.extend(mask);
        frame.extend(payload.iter().enumerate().map(|(i, b)| b ^ mask[i % 4]));
        self.stream.write_all(&frame).unwrap();
    }
    /// The text messages received within `wait` (a ping is answered).
    fn read(&mut self, wait: Duration) -> Vec<Value> {
        use std::io::Read;
        let (deadline, mut out) = (Instant::now() + wait, std::mem::take(&mut self.inbox));
        while Instant::now() < deadline {
            let mut buf = [0u8; 16384];
            if let Ok(n) = self.stream.read(&mut buf) {
                assert!(n > 0, "the station closed the socket");
                self.pending.extend(&buf[..n]);
            }
            while let Some((opcode, payload, used)) = frame(&self.pending) {
                self.pending.drain(..used);
                match opcode {
                    1 => out.push(serde_json::from_slice(&payload).unwrap()),
                    9 => self.write(10, &payload),
                    _ => {}
                }
            }
        }
        out
    }
    /// The next free_tx_slots.state message within 5 s (what follows it stays for the next read);
    /// none of the messages read is an automation.state (automation is never used, #82).
    fn next_free_tx_slots(&mut self) -> Option<Value> {
        let deadline = Instant::now() + Duration::from_secs(5);
        while Instant::now() < deadline {
            let messages = tokio::task::block_in_place(|| self.read(Duration::from_millis(100)));
            assert!(
                messages.iter().all(|m| m["type"] != "automation.state"),
                "{messages:?}"
            );
            if let Some(i) = messages
                .iter()
                .position(|m| m["type"] == "free_tx_slots.state")
            {
                self.inbox = messages[i + 1..].to_vec();
                return Some(messages[i].clone());
            }
        }
        None
    }
    /// The free_tx_slots.state messages received within 2.5 s (two contact ticks and more).
    fn free_tx_slots(&mut self) -> Vec<Value> {
        let messages = tokio::task::block_in_place(|| self.read(Duration::from_millis(2500)));
        messages
            .into_iter()
            .filter(|m| m["type"] == "free_tx_slots.state")
            .collect()
    }
}
/// One complete server frame at the start of `b`: (opcode, payload, its length in `b`).
fn frame(b: &[u8]) -> Option<(u8, Vec<u8>, usize)> {
    let (len, at) = match *b.get(1)? & 0x7f {
        126 => (usize::from(u16::from_be_bytes([*b.get(2)?, *b.get(3)?])), 4),
        127 => (
            usize::try_from(u64::from_be_bytes(b.get(2..10)?.try_into().ok()?)).ok()?,
            10,
        ),
        n => (usize::from(n), 2),
    };
    let payload = b.get(at..at + len)?.to_vec();
    Some((b[0] & 0x0f, payload, at + len))
}
/// GET /automation free_tx_slots, checked to be the MCP automation view's.
async fn free_tx_slots(f: &Mcp) -> Value {
    let get = f.browser("GET", "/automation", None).await.json;
    assert!(
        get.as_object().unwrap().contains_key("free_tx_slots"),
        "{get}"
    );
    assert_eq!(
        f.read("automation").await["free_tx_slots"],
        get["free_tx_slots"],
        "MCP view"
    );
    get["free_tx_slots"].clone()
}

// #82 WstxStrategy::FreeTxSlots: the station's open slots with or without a run (TC-082-002,
// TC-082-003). Oracle: CL-065-01's parity rule and build times (the operator's round 1 Q3 and round
// 2 Q1 answers), its open rule worked by hand from the hand-authored rows below, and the model's
// exact keys (WstxMcp::AutomationWire, WstxStationProtocol::PushedStationState).

/// The station clock stands still at `at`; then one station step (the build runs in it).
fn step_at(f: &Mcp, at: i64) {
    f.bench.frozen.store(at, Ordering::SeqCst);
    f.tick();
}
/// The served router of `f` on a local port, with its server task.
async fn serve(f: &Mcp) -> (std::net::SocketAddr, tokio::task::JoinHandle<()>) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let app = f.app.clone();
    let server = tokio::spawn(async move {
        axum::serve(listener, crate::router(app)).await.unwrap();
    });
    (address, server)
}
/// The listening rows before the even period e: my even periods e - 60 and e - 30 s flat 30 with
/// an undecoded station 12 dB up over 1000..1050 Hz (bins 342..358), the odd e - 45 and e - 15 s
/// flat 30 with one over 2000..2050 Hz (bins 683..699), and the even period e itself flat 30 with
/// one over 1500..1550 Hz (bins 512..529). A slot holding k raised bins of its n (17 or 18) reads
/// 12k / n - 0.65 in that period: closed from k = 2 (0.76, 1), open at k = 0. So 1000..1050 closes
/// 960..1040 (960 holds 3, 1040 4; 950 and 1050 none), 2000..2050 closes 1960..2040 and
/// 1500..1550 closes 1460..1540.
fn listening_rows(f: &Mcp, e: i64) {
    for back in [60_000, 30_000] {
        wf_row(f, e - back, 30, &[(1000, 1050, 42)], false);
        wf_row(f, e - back + 15_000, 30, &[(2000, 2050, 42)], false);
    }
    wf_row(f, e, 30, &[(1500, 1550, 42)], false);
}
/// The build of GET /automation free_tx_slots (with the MCP view's), its keys exactly #82's.
async fn build_of(f: &Mcp) -> Value {
    let v = free_tx_slots(f).await;
    let mut keys: Vec<&String> = v.as_object().expect("a value").keys().collect();
    keys.sort();
    assert_eq!(
        keys,
        ["at_utc_ms", "mode", "open", "periods", "qso", "rx_parity"],
        "{v}"
    );
    v
}
fn listening(at: i64, rx: &str, periods: u64, open: Value) -> Value {
    json!({"at_utc_ms":at,"mode":"ft8","rx_parity":rx,"qso":false,"periods":periods,"open":open})
}

// Proves: CL-065-01; TC-082-002 (a), (d). Listening on 20 m FT8 with no run, then with a strategy
// run waiting (Test calls, nothing to call), on `listening_rows`, read right after the period
// starts e, e + 15, e + 30 and e + 45 s: rx_parity even, odd, even, odd (the parity of the period
// in progress, the Rx parity for transmitting in the next one), qso false, at_utc_ms the period
// start. At e: my even e - 30 and e - 60 s count (2), e itself in progress does not: open
// [[300, 1000], [1050, 2700]] (1000 closed, 1500 open). At e + 15 s: the odd e - 15 and e - 45 s
// (2): [[300, 2000], [2050, 2700]] (1000 open). At e + 30 s: e, e - 30 and e - 60 s (3), e's station
// now counted: [[300, 1000], [1050, 1500], [1550, 2700]]. At e + 45 s as at e + 15 s. The waiting
// run gives the same values, with no run_id. Red on the parent: no value without a run.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_082_002_listening_alternates_the_parity_every_period_with_or_without_a_waiting_run() {
    for waiting in [false, true] {
        let f = station(true).await;
        f.state.recording.fixture_band("20m");
        f.state.recording.fixture_live_job("ft8");
        let e = at_even(&f);
        let _client = f.state.recording.clients.session();
        listening_rows(&f, e);
        if waiting {
            select(&f, config(Some("Test calls"))).await;
            assert_eq!(run_state(&f).await.0, "waiting");
        }
        let even = json!([[300, 1000], [1050, 2700]]);
        let odd = json!([[300, 2000], [2050, 2700]]);
        let counted = json!([[300, 1000], [1050, 1500], [1550, 2700]]);
        for (at, expected) in [
            (e, listening(e, "even", 2, even)),
            (e + 15_000, listening(e + 15_000, "odd", 2, odd.clone())),
            (e + 30_000, listening(e + 30_000, "even", 3, counted)),
            (e + 45_000, listening(e + 45_000, "odd", 2, odd)),
        ] {
            step_at(&f, at);
            assert_eq!(build_of(&f).await, expected, "waiting {waiting}");
        }
        if waiting {
            assert_eq!(run_state(&f).await.0, "waiting");
        }
    }
}

/// The station clock runs again from where it stood still (the offset carries the frozen time).
fn unfreeze(f: &Mcp) {
    let at = f.bench.frozen.swap(0, Ordering::SeqCst);
    if at != 0 {
        f.bench
            .offset
            .fetch_add(at - f.bench.now_utc_ms(), Ordering::SeqCst);
    }
}

// Proves: CL-065-01; TC-082-002 (b). My own CQ, Tx even, no contact: flat rows before e, the odd
// period e + 15 s with a station 12 dB up over 2000..2050 Hz (closing 1960..2040, as
// `listening_rows`' band) and the odd e + 45 s with one over 2400..2450 Hz (bins 820..836,
// closing 2360..2440: 2360 holds 3 of its bins, 2440 4, 2350 and 2450 none). Enable Tx on at
// e + 16 s (the odd period, not mine): at once a build with qso true and rx_parity odd (e - 15 and
// e - 45 s count, 2: [[300, 2700]]). Then the period starts e + 30 s (my transmission), e + 45 s,
// e + 60 s (my transmission) and e + 75 s: every build qso true and rx_parity odd; the open ranges
// change only at the even starts, when an odd period has ended: at e + 30 s 3 periods,
// [[300, 2000], [2050, 2700]], the same at e + 45 s; at e + 60 s 4 periods, [[300, 2000],
// [2050, 2400], [2450, 2700]], the same at e + 75 s. Enable Tx off at e + 76 s: at once qso false
// (rx_parity odd, the period in progress). Red on the parent: no value without a run.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_082_002_my_own_cq_holds_its_rx_parity_over_its_transmissions() {
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    for back in [60_000, 45_000, 30_000, 15_000] {
        wf_row(&f, e - back, 30, &[], false);
    }
    wf_row(&f, e + 15_000, 30, &[(2000, 2050, 42)], false);
    wf_row(&f, e + 45_000, 30, &[(2400, 2450, 42)], false);
    browser_ok(&f, "set_parity", json!({"parity":"even"})).await;
    f.bench.frozen.store(e + 16_000, Ordering::SeqCst);
    let safety = f.read("contact").await["transmit"]["safety_revision"].clone();
    browser_ok(
        &f,
        "enable_tx",
        json!({"enabled":true,"safety_revision":safety}),
    )
    .await;
    step_at(&f, e + 16_000);
    assert_eq!(contact(&f).await.2, json!("armed"));
    assert_eq!(
        build_of(&f).await,
        json!({"at_utc_ms":e + 16_000,"mode":"ft8","rx_parity":"odd","qso":true,"periods":2,
            "open":[[300, 2700]]}),
        "Enable Tx on: at once"
    );
    let after_15 = json!([[300, 2000], [2050, 2700]]);
    let after_45 = json!([[300, 2000], [2050, 2400], [2450, 2700]]);
    for (start, own, periods, open) in [
        (e + 30_000, true, 3, &after_15),
        (e + 45_000, false, 3, &after_15),
        (e + 60_000, true, 4, &after_45),
        (e + 75_000, false, 4, &after_45),
    ] {
        if own {
            unfreeze(&f);
            transmit_own_period(&f, start).await;
            assert_eq!(contact(&f).await.2, json!("armed"), "{start}");
        } else {
            step_at(&f, start);
        }
        let v = build_of(&f).await;
        let at = v["at_utc_ms"].as_i64().unwrap();
        assert!(
            (start..start + 15_000).contains(&at),
            "{start}: built at {at}"
        );
        assert_eq!(
            (&v["qso"], &v["rx_parity"], &v["periods"], &v["open"]),
            (&json!(true), &json!("odd"), &json!(periods), open),
            "{start}"
        );
    }
    f.bench.frozen.store(e + 76_000, Ordering::SeqCst);
    browser_ok(
        &f,
        "enable_tx",
        json!({"enabled":false,"safety_revision":null}),
    )
    .await;
    step_at(&f, e + 76_000);
    let v = build_of(&f).await;
    assert_eq!(
        (&v["at_utc_ms"], &v["qso"], &v["rx_parity"]),
        (&json!(e + 76_000), &json!(false), &json!("odd")),
        "Enable Tx off: at once"
    );
}

// Proves: CL-065-01; TC-082-002 (c), (f). (c) A manual contact: K1ABC's CQ decoded at 900 Hz in the odd period e - 15 s; the
// operator double-clicks it at e + 61 s, in the even period e + 60 s, my Tx parity even (replying,
// Enable Tx off: nothing keyed). Listening just before, rx_parity even; at once qso true and
// rx_parity odd (the contact's Rx parity: e + 45, e + 15, e - 15 and e - 45 s count, 4), and at
// the period starts after it odd: e + 75 and e + 90 s. The caller's slot is closed: |f - 900| below
// 50 closes 860..940. The open ranges change only at builds at even starts: a station over
// 2400..2450 Hz (bins 820..836) in the odd period e + 75 s, closing 2360..2440 (2360 holds 3 of its
// bins, 2440 4; 2350 and 2450 none), is not in the build at e + 75 s, nor at e + 89 s (no build
// within a period), and is from e + 90 s on. (f) A station decoded at 1200 Hz only in the odd
// period e + 105 s, which is flat in the waterfall (no rise closes a slot): the build at the even
// start e + 120 s (e + 105, 75, 45 and 15 s count, 4; K1ABC's e - 15 s no longer) has 1200 open,
// [[300, 2400], [2450, 2700]]; the publication of e + 105 s's decodes builds at once (e + 120.5 s),
// qso true and rx_parity odd as before, 1160..1240 closed: [[300, 1200], [1250, 2400],
// [2450, 2700]]. Red on the parent: no value without a run; on the build without "Rebuild on
// decodes" (f) keeps the period-start value.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_082_002_a_manual_qso_holds_its_rx_parity_and_its_decodes_build_at_once() {
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    for back in [60_000, 30_000] {
        wf_row(&f, e - back, 30, &[], false);
        wf_row(&f, e - back + 15_000, 30, &[], false);
    }
    publish(&f, e - 15_000, &[("CQ K1ABC FN42", 900.0, Some(-5.0))]);
    let caller = json!([[300, 900], [950, 2700]]);
    step_at(&f, e + 15_000);
    assert_eq!(
        build_of(&f).await,
        listening(e + 15_000, "odd", 2, caller.clone())
    );

    // (c) a manual contact with K1ABC (decoded in the odd e - 15 s).
    for back in [0, 30_000] {
        wf_row(&f, e + back, 30, &[], false);
        wf_row(&f, e + back + 15_000, 30, &[], false);
    }
    step_at(&f, e + 61_000);
    let v = build_of(&f).await;
    assert_eq!(
        (&v["rx_parity"], &v["qso"]),
        (&json!("even"), &json!(false))
    );
    browser_ok(
        &f,
        "select_row",
        json!({"row":live_row(&f, "CQ K1ABC FN42"),"replace":true,"directive_confirmed":true}),
    )
    .await;
    step_at(&f, e + 61_000);
    assert_eq!(contact(&f).await.1, json!("replying"));
    assert_eq!(
        build_of(&f).await,
        json!({"at_utc_ms":e + 61_000,"mode":"ft8","rx_parity":"odd","qso":true,"periods":4,
            "open":caller}),
        "the QSO: at once, its Rx parity"
    );
    step_at(&f, e + 75_000);
    let v = build_of(&f).await;
    assert_eq!(
        (&v["at_utc_ms"], &v["rx_parity"], &v["open"]),
        (&json!(e + 75_000), &json!("odd"), &caller)
    );
    wf_row(&f, e + 75_000, 30, &[(2400, 2450, 42)], false);
    step_at(&f, e + 89_000);
    assert_eq!(
        build_of(&f).await["at_utc_ms"],
        json!(e + 75_000),
        "no build within a period"
    );
    step_at(&f, e + 90_000);
    let v = build_of(&f).await;
    assert_eq!(
        (&v["at_utc_ms"], &v["rx_parity"], &v["qso"], &v["periods"]),
        (&json!(e + 90_000), &json!("odd"), &json!(true), &json!(4))
    );
    assert_eq!(v["open"], json!([[300, 900], [950, 2400], [2450, 2700]]));

    // (f) Rebuild on decodes: the odd period e + 105 s flat (a station there below the level that
    // closes a slot by its rise), its decodes not yet published at the even start e + 120 s.
    wf_row(&f, e + 90_000, 30, &[], false);
    wf_row(&f, e + 105_000, 30, &[], false);
    step_at(&f, e + 120_000);
    let start = build_of(&f).await;
    assert_eq!(
        (
            &start["at_utc_ms"],
            &start["rx_parity"],
            &start["qso"],
            &start["periods"]
        ),
        (&json!(e + 120_000), &json!("odd"), &json!(true), &json!(4))
    );
    assert_eq!(
        start["open"],
        json!([[300, 2400], [2450, 2700]]),
        "e + 105, 75, 45 and 15 s count; K1ABC's e - 15 s no longer; 1200 open"
    );
    // Its decodes published: at once a build, the slots overlapping 1200 Hz (1160..1240) closed.
    decoded_in(&f, e + 105_000, &[1200.0]);
    step_at(&f, e + 120_500);
    let v = build_of(&f).await;
    assert_eq!(
        (&v["at_utc_ms"], &v["rx_parity"], &v["qso"], &v["periods"]),
        (&json!(e + 120_500), &json!("odd"), &json!(true), &json!(4)),
        "the publication builds at once"
    );
    assert_eq!(v["open"], json!([[300, 1200], [1250, 2400], [2450, 2700]]));
}

// Proves: CL-065-01; TC-082-002 (e). Listening on flat rows (my even e - 60 and e - 30 s): at e + 1 s
// 2 periods count. A station band change (20 m to 40 m) at e + 2 s builds at once: only later
// periods count, periods 0 and open []. The live receive stops: null (GET and MCP). A new live job
// starts: a value at once from its first period (periods 0, open []); its odd period e + 15 s
// received, at e + 45 s it counts: periods 1, open [[300, 2700]]. Red on the parent: null without a
// run.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_082_002_a_band_change_and_a_new_live_job_count_anew_no_receive_is_null() {
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    for back in [60_000, 30_000] {
        wf_row(&f, e - back, 30, &[], false);
    }
    step_at(&f, e + 1_000);
    assert_eq!(
        build_of(&f).await,
        listening(e + 1_000, "even", 2, json!([[300, 2700]]))
    );
    f.state.recording.fixture_band("40m");
    step_at(&f, e + 2_000);
    assert_eq!(
        build_of(&f).await,
        listening(e + 2_000, "even", 0, json!([])),
        "after the band change"
    );
    f.state.recording.fixture_stop_live_job();
    step_at(&f, e + 3_000);
    assert_eq!(free_tx_slots(&f).await, Value::Null, "no live receive");
    f.state.recording.fixture_live_job("ft8");
    step_at(&f, e + 4_000);
    assert_eq!(
        build_of(&f).await,
        listening(e + 4_000, "even", 0, json!([])),
        "a new live job"
    );
    wf_row(&f, e + 15_000, 30, &[], false);
    step_at(&f, e + 45_000);
    assert_eq!(
        build_of(&f).await,
        listening(e + 45_000, "odd", 1, json!([[300, 2700]]))
    );
}

// Proves: CL-065-01; TC-082-003, TC-082-002 (a) in FT4, TC-065-002 (#82: replaced by TC-082-003).
// Automation never used (no configuration, no run), Detailed, Thin
// and Off peers on the served router, flat rows. FT8: a build at each of the 4 period starts e,
// e + 15, e + 30 and e + 45 s, and one at Enable Tx on (e + 50 s, Tx even: the odd period is not
// mine) and one at Enable Tx off (e + 55 s): each Detailed and Thin peer gets one free_tx_slots.state
// per build, data {profile_id, boot_id, free_tx_slots} with the GET value of that build (exact keys
// {at_utc_ms, mode, rx_parity, qso, periods, open}, equal to the MCP view's), none to Off. A fourth
// peer subscribing Thin gets exactly one, the current value. FT4: a new live job (mode ft4) at
// e + 60 s builds at once, then at e + 67.5, e + 75 and e + 82.5 s: 4 in 30 s, rx_parity even, odd,
// even, odd (TC-082-002 (a) in FT4). The live receive
// stops: one event with free_tx_slots null, GET null, no further event. No automation.state to any
// peer, and none of run_id, slots, rise_db, level_db, floor_db or listening in an event. The 48-range
// value with two UUIDs and a 13-digit at_utc_ms is at most 1024 bytes. Red on the parent: no event
// and null without a run.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_082_003_free_tx_slots_on_the_socket_and_in_the_snapshot_without_a_run() {
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    for back in [60_000, 45_000, 30_000, 15_000] {
        wf_row(&f, e - back, 30, &[], false);
    }
    let (address, server) = serve(&f).await;
    let mut peers: Vec<Peer> = tokio::task::block_in_place(|| {
        ["spectrum.detail", "spectrum.thin", "spectrum.off"]
            .iter()
            .map(|s| Peer::open(address, &f, s))
            .collect()
    });
    assert_eq!(
        free_tx_slots(&f).await,
        Value::Null,
        "before the first build"
    );
    let event = |v: &Value| {
        json!({"v":1,"type":"free_tx_slots.state",
            "data":{"profile_id":f.id,"boot_id":f.boot,"free_tx_slots":v}})
    };
    let mut sent = Vec::new();
    let mut each = async |peers: &mut Vec<Peer>, label: &str, null: bool| {
        let v = if null {
            free_tx_slots(&f).await
        } else {
            build_of(&f).await
        };
        for (i, peer) in peers.iter_mut().enumerate() {
            if i == 2 {
                // The Off peer, read (and its pings answered) at every build: never one.
                let off = tokio::task::block_in_place(|| peer.read(Duration::from_millis(50)));
                assert!(
                    off.iter()
                        .all(|m| m["type"] != "free_tx_slots.state"
                            && m["type"] != "automation.state"),
                    "Off: {label}: {off:?}"
                );
                continue;
            }
            let got = peer.next_free_tx_slots();
            assert_eq!(got.as_ref(), Some(&event(&v)), "peer {i}: {label}");
            sent.push(got.unwrap());
        }
        v
    };
    browser_ok(&f, "set_parity", json!({"parity":"even"})).await;
    for (k, rx) in [(0, "even"), (1, "odd"), (2, "even"), (3, "odd")] {
        step_at(&f, e + 15_000 * k);
        let v = each(&mut peers, &format!("FT8 build {k}"), false).await;
        assert_eq!(
            (&v["at_utc_ms"], &v["rx_parity"], &v["qso"], &v["mode"]),
            (
                &json!(e + 15_000 * k),
                &json!(rx),
                &json!(false),
                &json!("ft8")
            )
        );
    }
    f.bench.frozen.store(e + 50_000, Ordering::SeqCst);
    let safety = f.read("contact").await["transmit"]["safety_revision"].clone();
    browser_ok(
        &f,
        "enable_tx",
        json!({"enabled":true,"safety_revision":safety}),
    )
    .await;
    step_at(&f, e + 50_000);
    let v = each(&mut peers, "QSO start", false).await;
    assert_eq!(v["qso"], true);
    f.bench.frozen.store(e + 55_000, Ordering::SeqCst);
    browser_ok(
        &f,
        "enable_tx",
        json!({"enabled":false,"safety_revision":null}),
    )
    .await;
    step_at(&f, e + 55_000);
    let current = each(&mut peers, "QSO end", false).await;
    assert_eq!(current["qso"], false);
    let mut late = tokio::task::block_in_place(|| Peer::open(address, &f, "spectrum.thin"));
    assert_eq!(
        late.free_tx_slots(),
        [event(&current)],
        "a peer subscribing Thin gets the current value once"
    );
    peers.push(late);

    f.state.recording.fixture_live_job("ft4");
    // FT4 periods of 7.5 s: e + 60 s is even (e a multiple of 30 s), the parity alternates.
    for (k, (at, rx)) in [
        (e + 60_000, "even"),
        (e + 67_500, "odd"),
        (e + 75_000, "even"),
        (e + 82_500, "odd"),
    ]
    .into_iter()
    .enumerate()
    {
        step_at(&f, at);
        let v = each(&mut peers, &format!("FT4 build {k}"), false).await;
        assert_eq!(
            (&v["at_utc_ms"], &v["mode"], &v["rx_parity"]),
            (&json!(at), &json!("ft4"), &json!(rx))
        );
    }
    f.state.recording.fixture_stop_live_job();
    step_at(&f, e + 85_000);
    assert_eq!(each(&mut peers, "receive stopped", true).await, Value::Null);
    step_at(&f, e + 90_000);
    for (i, peer) in peers.iter_mut().enumerate() {
        assert_eq!(
            peer.free_tx_slots(),
            Vec::<Value>::new(),
            "peer {i}: no further event"
        );
    }
    let off = tokio::task::block_in_place(|| peers[2].read(Duration::from_millis(500)));
    assert!(
        off.iter()
            .all(|m| m["type"] != "free_tx_slots.state" && m["type"] != "automation.state"),
        "{off:?}"
    );
    assert_eq!(sent.len(), 2 * 6 + 3 * 5, "one per build and peer");
    for m in &sent {
        let text = m.to_string();
        for word in [
            "run_id",
            "\"slots\"",
            "rise_db",
            "level_db",
            "floor_db",
            "listening",
        ] {
            assert!(!text.contains(word), "{word} in {text}");
        }
    }
    let r = &f.state.recording;
    let worst: Vec<(u32, u32)> = (300..=2650).step_by(50).map(|f| (f, f + 50)).collect();
    let value = crate::freeslot::value(
        9_999_999_999_999,
        wstx_rust::decoder::Mode::Ft8,
        wstx_rust::transmit::Parity::Even,
        true,
        4,
        &worst,
    );
    let longest = crate::automation::free_tx_slots_event(r, &value);
    assert!(longest.len() <= 1024, "{} bytes: {longest}", longest.len());
    server.abort();
}

// #66 quiet slots across the passband (TC-066-001, TC-066-002). Oracle: the operator's rules of
// 2026-11-08 (issue #66 Functionality 1-8), hand-computed in each test from the waterfall rows and
// the decodes written here.

/// The decodes of the HB9BLA capture of 2026-11-08 10:28:58 UTC (10 m FT8, the run's CQ decision,
/// D:/wstx-tmp/live-20261108c/slots-102901.json): per period its start relative to 10:28:30 and
/// the audio frequencies decoded in it; my Rx parity even (10:27:30, 10:28:00, 10:28:30), my Tx
/// parity odd (10:28:15, 10:28:45).
const CAPTURE: [(i64, &[f64]); 5] = [
    (
        -60_000,
        &[
            451.5, 544.0, 575.3, 604.0, 660.8, 896.5, 1102.8, 1198.5, 1363.9, 1398.9, 1738.9,
            1835.3, 2012.1, 2181.1,
        ],
    ),
    (
        -30_000,
        &[
            451.5, 544.1, 575.1, 604.0, 660.8, 896.8, 1102.7, 1198.6, 1363.8, 1399.1, 1738.9,
            1833.7, 2061.6, 2181.0,
        ],
    ),
    (
        -15_000,
        &[
            754.1, 765.4, 887.8, 916.1, 1034.3, 1378.4, 1799.2, 1977.1, 2365.0, 2508.8,
        ],
    ),
    (
        0,
        &[
            450.7, 543.0, 573.6, 659.6, 895.4, 1101.5, 1197.5, 1362.9, 1398.2, 1737.9, 1832.8,
            2011.2, 2180.1,
        ],
    ),
    (
        15_000,
        &[753.3, 764.8, 1033.6, 1377.6, 1754.1, 1976.1, 2364.5],
    ),
];
/// RK3AW, decoded in my even periods only, whose signal was in both odd periods too (the capture's
/// 1180 Hz slot read 50 dB against a usual 48).
const RK3AW_HZ: f64 = 1198.5;
/// A decoded report between two other stations at each of `hz`: never a candidate.
fn reports(hz: &[f64]) -> Vec<(&'static str, f64, Option<f64>)> {
    hz.iter()
        .map(|hz| ("G4AAA W1XYZ -10", *hz, Some(-10.0)))
        .collect()
}

// Proves: CL-039-09, CL-065-01; TC-066-001. The 10:28:58 capture (HB9BLA 2026-11-08, 10 m FT8): a
// run's CQ decision ("Casual 20 m"), my Tx parity odd and Rx parity even, Tx 1930, Rx 906, the
// station clock 13.965 s into 10:28:45. Counted: my even periods 10:27:30, 10:28:00 and 10:28:30
// (periods now 3), each a flat floor of 30 (32 in 10:28:30), every station decoded in it a band
// [hz, hz + 50) 12 dB above the floor; my odd periods alike, RK3AW's band in both. Hand computation:
// the even decodes leave the candidates 300..400, 720..800, 1010..1050, 1250..1310, 1450..1680,
// 1890..1960, 2120..2130 and 2240..2650 (with Hold Tx on 810..1000 is also within 50 Hz of Rx
// 906); each lies on the floor in every even period, rise -0.65, so free: 0 (#66 "At or under
// floor = free"), and the latest period counts (level 32, floor 32.65). #82: the open slots are
// those decode-free grid points with no clearance of Rx (D1), the same with Hold Tx on and off: a
// decode d closes (d - 50, d + 50), so the even clusters 450.7..451.5, 543.0..660.8, 895.4..896.8,
// 1101.5..1198.6, 1362.9..1399.1, 1737.9..1835.3, 2011.2..2061.6 and 2180.1..2181.1 leave open
// 300..400, 720..840, 950..1050, 1250..1310, 1450..1680, 1890..1960, 2120..2130 and 2240..2650
// (edges: 400 is 50.7 Hz below 450.7, 840 55.4 below 895.4, 950 53.2 above 896.8, 1310 52.9 below
// 1362.9, 2130 50.1 below 2180.1), each signal [f, f + 50) joined into [300, 450), [720, 890),
// [950, 1100), [1250, 1360), [1450, 1730), [1890, 2010), [2120, 2180), [2240, 2700): none
// overlaps a station decoded in my even periods; DL5XU (1976) and A61DD (765), decoded only in my
// odd periods, close nothing; qso true (the run's CQ is armed), rx_parity even, periods 3.
// Hold Tx on: the CQ on the held 1930, Rx 906, tx_slot {1930, 0}. Hold Tx off: the CQ's slot 1930
// (the current Tx among the quietest), Rx = Tx. Red on the parent: no open ranges (its list ranked
// five slots by the rise over each slot's own usual level).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_066_001_the_capture_lists_free_slots_off_the_busy_region() {
    for hold in [true, false] {
        let t = casual(true).await;
        let (f, e) = (&t.f, t.e);
        if !hold {
            hold_off(f).await;
        }
        browser_ok(f, "set_frequency", json!({"rx_hz":906,"tx_hz":1930})).await;
        for (offset, decodes) in CAPTURE {
            let start = e + offset;
            let floor = if offset >= 0 { 32.0 } else { 30.0 };
            let mut bands = decodes.to_vec();
            if offset == -15_000 || offset == 15_000 {
                bands.push(RK3AW_HZ);
            }
            let level = |hz: f64| {
                if bands.iter().any(|d| hz >= *d && hz < d + 50.0) {
                    floor + 12.0
                } else {
                    floor
                }
            };
            wf_levels(f, start, level, false);
            if offset < 0 {
                decoded_in(f, start, decodes);
            }
        }
        f.bench
            .offset
            .fetch_add(e + 28_965 - f.bench.now_utc_ms(), Ordering::SeqCst);
        publish(f, e, &reports(CAPTURE[3].1));
        publish(f, e + 15_000, &reports(CAPTURE[4].1));
        assert_eq!(run_of(f).await["state"], "calling_cq", "Hold Tx {hold}");
        let rx = if hold { 906 } else { 1930 };
        assert_eq!(
            frequencies(f).await,
            (
                json!(rx),
                json!(1930),
                json!({"hz":1930,"power_db":0,"his_end":"unknown"})
            ),
            "Hold Tx {hold}"
        );
        let v = free_tx_slots(f).await;
        assert_eq!(
            (&v["rx_parity"], &v["qso"], &v["periods"]),
            (&json!("even"), &json!(true), &json!(3)),
            "Hold Tx {hold}"
        );
        assert_eq!(
            v["open"],
            json!([
                [300, 450],
                [720, 890],
                [950, 1100],
                [1250, 1360],
                [1450, 1730],
                [1890, 2010],
                [2120, 2180],
                [2240, 2700]
            ]),
            "Hold Tx {hold}"
        );
    }
}

// Proves: CL-039-09, CL-065-01; TC-066-002 (a), (j). The 07:29 reproduction (HB9BLA 2026-11-08,
// 20 m): Tx 1550, my Rx parity even; 4 counted periods of each parity, a flat floor of 30 in the
// two older and 32 in the two later; a station decoded at 659.5 Hz at 38 dB in all 4 even periods,
// stations decoded at 659.7 and 691.8 Hz at 38 dB in all 4 odd periods. The selection of K1ABC
// (2400, Hold Tx off): 1550 is free, 0 (rise -0.65), like every free slot (610..700 is on the
// decoded station), so Tx stays on 1550, tx_slot {1550, 0}. #82: the station's open slots close
// 610..700 (|f - 659.5| below 50) and nothing for the odd stations: [300, 650), [710, 2700). Red on
// the parent: it moves Tx to 680 (rise 0 on the station against 1 on the free slots), as live.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_066_002_the_0729_case_keeps_tx_off_the_station() {
    let rows = |f: &Mcp, e: i64| {
        for j in (1..=4).rev() {
            let floor = if j > 2 { 30.0 } else { 32.0 };
            let on = |stations: &'static [f64]| {
                move |hz: f64| {
                    if stations.iter().any(|d| hz >= *d && hz < d + 50.0) {
                        38.0
                    } else {
                        floor
                    }
                }
            };
            let even = e - 30_000 * j;
            wf_levels(f, even, on(&[659.5]), false);
            decoded_in(f, even, &[659.5]);
            wf_levels(f, even + 15_000, on(&[659.7, 691.8]), false);
            decoded_in(f, even + 15_000, &[659.7, 691.8]);
        }
    };
    let t = rise_run("ft8", 1550, rows, &[K1ABC_2400]).await;
    let f = &t.f;
    assert_eq!(contact(f).await.0, json!("K1ABC"));
    assert_eq!(
        frequencies(f).await,
        (
            json!(1550),
            json!(1550),
            json!({"hz":1550,"power_db":0,"his_end":"unknown"})
        )
    );
    assert_eq!(open_ranges(f).await, [(300, 650), (710, 2700)]);
}

// Proves: CL-039-09; TC-039-049 (f); TC-066-002 (g). Hold Tx on, the selection of K1ABC at 1520,
// within 50 Hz of the held Tx 1500 (D4): the nearest candidates 50 Hz clear of his signal (and of
// Rx on him) are 1420 (80 Hz) below and 1620 (120 Hz) above. A station decoded at 1400 in my last
// Rx period (flat 20) overlaps 1360..1440, so below only 1350 and lower are left (150 Hz) and Tx
// goes to 1620, Rx on 1520, tx_slot {1620, 0}. With stations decoded every 40 Hz every candidate is
// overlapped, all come back and Tx goes to 1420. Red on the parent: decodes leave nothing out, Tx
// to 1420.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_066_002_the_hold_tx_50_hz_move_skips_a_decoded_station() {
    let everywhere: Vec<f64> = (280..=2700).step_by(40).map(f64::from).collect();
    for (decodes, tx) in [(vec![1400.0], 1620), (everywhere, 1420)] {
        let rows = move |f: &Mcp, e: i64| {
            wf_row(f, e - 30_000, 20, &[], false);
            decoded_in(f, e - 30_000, &decodes);
        };
        let t = held_run_with("ft8", None, rows, &[("CQ K1ABC FN42", 1520.0, Some(-10.0))]).await;
        assert_eq!(
            frequencies(&t.f).await,
            (
                json!(1520),
                json!(tx),
                json!({"hz":tx,"power_db":0,"his_end":"unknown"})
            ),
            "Tx to {tx}"
        );
    }
}

// Proves: CL-039-22; TC-039-045; TC-066-002 (h). Hold Tx off, "Casual 20 m", Tx 900, my 4 Rx periods
// flat 20 and a station decoded at 800 Hz in the last of them: the CQ stays on 900 (|900 - 800| is
// 100 Hz; every free slot 0), tx_slot {900, 0}. A caller at 920 is within 50 Hz of the CQ's slot:
// the nearest candidate 50 Hz clear of his 920..970 below is 820, on the decoded station (20 Hz),
// and below it the first free one is 750 (150 Hz); above, 1020 (120 Hz): Tx and Rx to 1020, not
// 820. Red on the parent: decodes leave nothing out, Tx to 820.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_066_002_the_cqs_caller_move_skips_a_decoded_station() {
    let t = casual(true).await;
    let (f, e) = (&t.f, t.e);
    hold_off(f).await;
    set_tx(f, 900).await;
    for j in (1..=4).rev() {
        wf_row(f, e - 30_000 * j, 20, &[], false);
    }
    decoded_in(f, e - 30_000, &[800.0]);
    publish(f, e, &[]);
    publish(f, rep(e, 1), &[]);
    assert_eq!(run_of(f).await["state"], "calling_cq");
    assert_eq!(
        frequencies(f).await,
        (
            json!(900),
            json!(900),
            json!({"hz":900,"power_db":0,"his_end":"unknown"})
        )
    );
    publish(f, rep(e, 2), &[("HB9BLA DL1XYZ JO62", 920.0, Some(-10.0))]);
    assert_eq!(contact(f).await.0, json!("DL1XYZ"));
    assert_eq!(
        frequencies(f).await,
        (
            json!(1020),
            json!(1020),
            json!({"hz":1020,"power_db":0,"his_end":"unknown"})
        )
    );
}

// Proves: CL-039-09; TC-066-002. The TC-066-003 defect (HB9BLA 2026-11-08 18:02-18:13 UTC): after
// the run's first transmission every decision counted 0 Rx periods. A strategy run with Hold Tx on
// (as live) selects K1ABC (CQ in the even period e at 1800 Hz) and calls him in my odd periods
// e + 15 s and e + 45 s; the hardware double keys PTT at each period start. The detailed waterfall
// comes from the actual live worker, fed with silent blocks from e - 30 s, observing the transmit
// owner at each block as live. Timing (the worker's spectrum): a detailed row of 2400 frames
// completes with its 5th 4096-point transform, 4816 frames (0.4 s) after its middle, so the last 2
// rows of my Rx period before each Tx period (first frames 0.4 and 0.2 s before it) complete on
// the air and carry the tx mark (#61), as the live Tx runs of 77 rows. Those periods are received
// (I transmitted in the period after them), so they count (CL-039-09 "periods I transmitted in
// never counted"): the station's build counts 1 period at the selection (e - 30 s, #82 periods),
// 2 at the slot check of the 1st repetition (+ e), 3 at the 2nd (+ e + 30 s). My Tx periods are never kept
// in the per-period power, the received ones are (e - 30, e - 15, e and e + 30 s). Red on the
// parent: it drops each Rx period with a marked row, 1 at every slot check, as live.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_066_002_received_periods_count_after_my_transmissions() {
    use std::time::{Duration, Instant};
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    let (_, job, generation) = f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    let mut capture = f.state.recording.fixture_capture(e - 30_000);
    capture.until(e);
    let mut c = config(Some("Test calls"));
    c["strategies"][0]["repetitions"] = json!(4);
    select(&f, c).await;
    publish(&f, e, &[K1ABC_CQ]);
    assert_eq!(contact(&f).await.0, json!("K1ABC"));
    let periods = |now: i64| json!(now);
    assert_eq!(free_tx_slots(&f).await["periods"], periods(1), "selection");
    let service = &f.state.recording.transmit.get().unwrap().service;
    for k in 1..=2 {
        let (rx, own) = (rep(e, k - 1), rep(e, k - 1) + 15_000);
        // My Rx period received up to my Tx period, then PTT keyed at its start.
        capture.until(own);
        crate::automation_tests::assert_bound(&f, own);
        f.bench
            .offset
            .fetch_add(own - 30 - f.bench.now_utc_ms(), Ordering::SeqCst);
        let deadline = Instant::now() + Duration::from_secs(5);
        while !service.view().transmitting {
            assert!(Instant::now() < deadline, "{:?}", service.view());
            f.tick();
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
        let on_air: Vec<(i64, bool)> = capture
            .until(own + 13_000)
            .into_iter()
            .filter(|(t, _)| (rx..own).contains(t))
            .collect();
        assert_eq!(
            on_air,
            [(own - 400, true), (own - 200, true)],
            "repetition {k}: the Rx period's rows completed on the air"
        );
        f.bench.offset.fetch_add(13_000, Ordering::SeqCst);
        let deadline = Instant::now() + Duration::from_secs(5);
        while service.view().transmitting {
            assert!(Instant::now() < deadline, "{:?}", service.view());
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
        f.tick();
        // The next Rx period received up to its decode 13 s in; K1ABC silent: the slot check.
        capture.until(rep(e, k) + 13_000);
        ended(&f, rep(e, k) + 13_000);
        publish(&f, rep(e, k), &[]);
        assert_eq!(
            run_of(&f).await["slot_check"]["repetitions"],
            json!(k),
            "repetition {k}"
        );
        assert_eq!(
            free_tx_slots(&f).await["periods"],
            periods(k + 1),
            "repetition {k}"
        );
    }
    // The other half of the rule: my Tx periods e + 15 s and e + 45 s (every row marked) are not
    // kept; the received ones are, the odd e - 15 s as well; e + 60 s is still in progress.
    let kept: Vec<i64> = f
        .state
        .recording
        .waterfall
        .lock()
        .unwrap()
        .periods((&job, generation), f.bench.now_utc_ms())
        .iter()
        .map(|p| p.start_ms - e)
        .collect();
    assert_eq!(kept, [-30_000, -15_000, 0, 30_000], "periods kept, from e");
}
