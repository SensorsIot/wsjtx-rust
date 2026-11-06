#![forbid(unsafe_code)]
// Proves: CL-039-01, CL-039-02, CL-039-03, CL-039-05, CL-039-06, CL-039-09, CL-039-10, CL-042-01, CL-042-02,
// CL-042-03, CL-042-04; TC-039-001..005, TC-039-010, TC-039-030, TC-039-031, TC-042-001, TC-042-002,
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
        calls_per_station: 3,
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

// Proves: TC-039-030, TC-042-001. Entity columns of cty.dat: DL Fed. Rep. of Germany (CQ 14), F
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
    // In value order: Australia new ever; Japan and the U.S. new on this band, by SNR.
    assert_eq!(called(&both, &goal_rows(), &st), vec![G4, G3, G5]);
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
        all(&["JA2ABC", "DL2XYZ", "K1ABC", "XX1ABC"])
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
    let list = crate::most_wanted::List::parse(r#"{"1":"150"}"#, "2026-11-06", "upload");
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
        vec!["JA2ABC", "VK2ABC", "DL2XYZ", "F5ABC", "G4XYZ"],
        "DXCC new first (ever, band, band and mode), then SNR"
    );
    // ADIF 230 Germany, 150 Australia: on the list first, by rank; the others as before.
    let listed = Station {
        worked: Some(log),
        most_wanted: crate::most_wanted::List::parse(
            r#"{"1":"230","2":"150","3":"999"}"#,
            "d",
            "upload",
        )
        .map(Arc::new),
        ..me()
    };
    assert_eq!(
        called(&s, &records, &listed),
        vec!["DL2XYZ", "VK2ABC", "JA2ABC", "F5ABC", "G4XYZ"]
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
        "min_snr_db":null,"calls_per_station":2,"treat_73_as_cq":true,"window":{"kind":"all"}})
}
fn config(active: Option<&str>) -> Value {
    json!({"continent":null,"active":active,"strategies":[strategy_json("New calls")],
        "ignore_calls":[],"session_ignore_minutes":30})
}

// Proves: TC-039-001, TC-039-030
#[test]
fn tc_039_001_configuration_is_exact() {
    let mut full = config(Some("New calls"));
    full["strategies"] = json!([{"name":"New calls","class":"award",
        "goals":["dxcc","dxcc_band","dxcc_slot","waz","wpx","grid","new_call"],
        "needed":"not_confirmed","region":{"kind":"selected","continents":["AF","AS"]},
        "min_snr_db":-15,"calls_per_station":20,"treat_73_as_cq":false,
        "window":{"kind":"from_to","from":"2024-02-29","to":"2026-11-06"}},
        {"name":"B","class":"award","goals":["grid"],"needed":"not_worked","region":{"kind":"dx"},
        "min_snr_db":null,"calls_per_station":1,"treat_73_as_cq":true,"window":{"kind":"today"}}]);
    let ok = parse_config(&full).unwrap();
    assert_eq!(ok.json(), full, "round trip");
    let parsed = ok.active_strategy().unwrap();
    assert_eq!(parsed.window, Window::FromTo(20_240_229, 20_261_106));
    assert_eq!(parsed.needed, Needed::NotConfirmed);
    let set = |path: &[&str], v: Value| {
        let mut c = config(Some("New calls"));
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
            &["strategies", "0", "calls_per_station"][..],
            json!(0),
            s0("calls_per_station"),
        ),
        (
            &["strategies", "0", "calls_per_station"][..],
            json!(21),
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
    write(3, 3, config(None));
    assert_eq!(read().2, json!("invalid_configuration"));
    // A current file, even with an active name, reads active None after a restart.
    write(2, 9, config(Some("New calls")));
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
        json!({"schema_version":2,"profile_id":f.id,"revision":1,"configuration":config(None)})
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
    let selected = put(&f, revision, config(Some("New calls"))).await;
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

// ------------------------------------------------------------------ strategy runs
/// The browser's selection: a save with the strategy active, which starts the run.
async fn select(f: &Mcp, configuration: Value) {
    save(f, configuration).await;
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
    // Selecting starts it: no other request; the run waits and no CQ is armed.
    select(&f, config(Some("New calls"))).await;
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
    // Proves: CL-039-08; TC-039-009: the strategy's pick moves Rx, Tx stays on its slot.
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
    // calls_per_station 2: two partner periods without an answer: on to the best other
    // candidate of the next publication; DL1XYZ is stronger but passed over, no stop.
    publish(&f, e + 30_000, &[]);
    publish(&f, e + 60_000, &[]);
    assert_eq!(contact(&f).await.2, json!("disarmed"));
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (
            run["state"].clone(),
            run["rested"].clone(),
            run["reason"].clone()
        ),
        (json!("waiting"), json!("DL1XYZ"), Value::Null)
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
        (json!("K1ABC"), json!("K1ABC HB9BLA JN47"), json!("armed"))
    );
    assert_eq!(
        (
            c["settings"]["tx_hz"].clone(),
            c["settings"]["rx_hz"].clone()
        ),
        (tx, json!(1700)),
        "after a 73 Tx stays on its free slot"
    );
    // It comes back: K1ABC given its calls, DL1XYZ again; then K1ABC alone is called again.
    publish(&f, e + 120_000, &[]);
    publish(&f, e + 150_000, &[]);
    publish(&f, e + 180_000, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    assert_eq!(
        contact(&f).await.0,
        json!("K1ABC"),
        "the one it left, when alone"
    );
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
    select(&f, config(Some("New calls"))).await;
    let _client = f.state.recording.clients.session();
    // No time_limit (a policy deadline would be the start); only the grant binds it.
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
async fn tc_039_004_halt_sets_none_esc_and_a_cancel_do_not_and_a_new_selection_restarts() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("New calls"))).await;
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    assert_eq!(contact(&f).await.2, json!("armed"));
    // An operator's cancel keeps the strategy and the run.
    browser_ok(&f, "cancel", json!({})).await;
    f.tick();
    f.tick();
    assert_eq!(active_of(&f).await, json!("New calls"));
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
    assert_eq!(active_of(&f).await, json!("New calls"), "Esc is no HALT");
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
    // HALT: run stopped halted, active None, a new revision the browser is told of.
    let before = f.browser("GET", "/strategy", None).await.json["revision"].clone();
    halt(&f).await;
    assert_eq!(run_state(&f).await, ("stopped".into(), json!("halted")));
    let s = f.browser("GET", "/strategy", None).await.json;
    assert_eq!(s["configuration"]["active"], Value::Null);
    assert_eq!(s["revision"], json!(before.as_u64().unwrap() + 1));
    let station_owner = f.state.recording.contact.get().unwrap();
    assert_eq!(
        json!(station_owner.strategy.revision()),
        s["revision"],
        "strategy.state"
    );
    // A HALT with a strategy selected but no run (a refused start) sets None as well.
    let revision = s["revision"].clone();
    let r = f.state.recording.contact.get().unwrap().strategy.put(
        &f.state,
        json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"expected_revision":revision,
                "configuration":config(Some("New calls"))}),
    );
    assert!(r.is_ok());
    assert_eq!(active_of(&f).await, json!("New calls"));
    halt(&f).await;
    assert_eq!(active_of(&f).await, Value::Null);
    // A new selection starts it again and it answers (a HALT is answered by the selection).
    select(&f, config(Some("New calls"))).await;
    f.tick();
    assert_eq!(
        active_of(&f).await,
        json!("New calls"),
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
    select(&f, config(Some("New calls"))).await;
    f.tick();
    assert_eq!(run_state(&f).await, ("waiting".into(), json!("no_receive")));
    assert_eq!(active_of(&f).await, json!("New calls"));
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
    assert_eq!(active_of(&f).await, json!("New calls"));
    publish(&f, e + 30_000, &[("CQ DL1XYZ JO62", 1200.0, Some(-1.0))]);
    assert_eq!(contact(&f).await.0, json!("DL1XYZ"), "on the new identity");
    // Auto Seq off: it finishes nothing new; the reason is shown while it waits.
    save(&f, config(None)).await;
    browser_ok(&f, "cancel", json!({})).await;
    browser_ok(&f, "set_auto_seq", json!({"enabled":false})).await;
    select(&f, config(Some("New calls"))).await;
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
    select(&f, config(Some("New calls"))).await;
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
    store_only(&f, config(Some("New calls")));
    station_owner
        .automation
        .selected(station_owner, &f.state, None);
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
            json!("New calls")
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
    let mut c = config(Some("New calls"));
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
    select(&f, config(Some("New calls"))).await;
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

// Proves: TC-039-004. Review finding 2: the station left after calls_per_station answers me: it
// is a caller, always answered first, not passed over.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_a_station_left_after_its_calls_is_answered_when_it_calls_me() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("New calls"))).await;
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-10.0))]);
    publish(&f, e + 30_000, &[]);
    publish(&f, e + 60_000, &[]);
    assert_eq!(f.read("automation").await["run"]["rested"], json!("K1ABC"));
    publish(
        &f,
        e + 90_000,
        &[
            ("HB9BLA K1ABC -10", 1500.0, Some(-10.0)),
            ("CQ DL1XYZ JO62", 1200.0, Some(9.0)),
        ],
    );
    let c = contact(&f).await;
    assert_eq!(c.0, json!("K1ABC"), "the caller, not the stronger CQ");
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
    select(&f, config(Some("New calls"))).await;
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
    select(&f, config(Some("New calls"))).await;
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
        json!("New calls"),
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
    select(&f, config(Some("New calls"))).await;
    assert_eq!(quiet_run(&f), ("waiting".into(), Value::Null));
    publish(&f, e + 180_000, &[("CQ DL1XYZ JO62", 1200.0, Some(9.0))]);
    assert_eq!(quiet_contact(&f).await.0, json!("DL1XYZ"));
    assert_eq!(f.keys(), 2, "key on and off of the one own period above");
}

// Proves: TC-039-033: the status WebSocket itself is what counts: an actual upgrade over the
// served router with the browser's cookie holds a run past 60 s, its close lets the 60 s run.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_033_a_real_status_websocket_keeps_a_strategy_and_its_close_ends_that() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    at_even(&f);
    select(&f, config(Some("New calls"))).await;
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

// Proves: TC-039-033
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_033_waiting_stops_at_60_s_and_a_client_or_reload_keeps_it() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("New calls"))).await;
    at_skew(&f, 60);
    assert_eq!(quiet_run(&f), ("stopped".into(), json!("no_client")));
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    assert_eq!(quiet_contact(&f).await.0, Value::Null, "nothing selected");
    // A status session keeps it, however long; after it the 60 s count from its end. A reload
    // inside them (a new session) keeps it too.
    at_skew(&f, 0);
    save(&f, config(None)).await;
    select(&f, config(Some("New calls"))).await;
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
    select(&f, config(Some("New calls"))).await;
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
    select(&f, config(Some("New calls"))).await;
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
    select(&f, config(Some("New calls"))).await;
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
async fn tc_039_031_most_wanted_upload_download_status_and_mcp_refusal() {
    let f = station(true).await;
    let post = async |path: &str, extra: Value| {
        let mut b = json!({"v":1,"profile_id":f.id,"boot_id":f.boot});
        b.as_object_mut()
            .unwrap()
            .extend(extra.as_object().unwrap().clone());
        f.browser("POST", path, Some(b)).await
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
    // A refused list changes nothing.
    let r = post("/strategy/most-wanted", json!({"text":"{\"1\":\"x\"}"})).await;
    assert_eq!(
        (
            r.status.as_u16(),
            r.json["error"]["code"].clone(),
            r.json["error"]["field"].clone()
        ),
        (400, json!("invalid_most_wanted"), json!("text"))
    );
    let r = post("/strategy/most-wanted", json!({"text":5})).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
    let r = post("/strategy/most-wanted", json!({"text":null,"x":1})).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
    // Upload: status with the unknown number counted; a new owner reads the file.
    let today = utc_date();
    let today = format!(
        "{:04}-{:02}-{:02}",
        today / 10000,
        today / 100 % 100,
        today % 100
    );
    let r = post(
        "/strategy/most-wanted",
        json!({"text":"{\"1\":\"150\",\"2\":\"9999\"}"}),
    )
    .await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);
    assert_eq!(
        r.json["most_wanted"],
        json!({"date":today,"source":"upload","entries":2,"unmapped":1})
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
    // Download now: a failed fetch and a refused body change nothing; a good one replaces.
    let owner = f.state.recording.contact.get().unwrap();
    *owner.strategy.fetch.lock().unwrap() = Some(Err("offline".into()));
    let d = post("/strategy/most-wanted/download", json!({})).await;
    assert_eq!(
        (d.status.as_u16(), d.json["error"]["code"].clone()),
        (502, json!("download_failed"))
    );
    *owner.strategy.fetch.lock().unwrap() = Some(Ok("<html>".into()));
    let d = post("/strategy/most-wanted/download", json!({})).await;
    assert_eq!(d.status.as_u16(), 502);
    assert_eq!(
        f.browser("GET", "/strategy", None).await.json["most_wanted"]["source"],
        json!("upload")
    );
    *owner.strategy.fetch.lock().unwrap() = Some(Ok("{\"1\":\"339\"}".into()));
    let d = post("/strategy/most-wanted/download", json!({})).await;
    assert_eq!(d.status, StatusCode::OK, "{}", d.json);
    assert_eq!(
        d.json["most_wanted"],
        json!({"date":today,"source":"download","entries":1,"unmapped":0})
    );
    let file: Value =
        serde_json::from_slice(&std::fs::read(f.dir.join(crate::most_wanted::FILE_NAME)).unwrap())
            .unwrap();
    assert_eq!(
        file,
        json!({"schema_version":1,"profile_id":f.id,"date":today,"source":"download","list":{"1":"339"}})
    );
    // The MCP principal may not change it.
    let internal = crate::mcp_tests::internal_transport(&f, &f.mcp);
    let m = crate::mcp_tests::with_cookie(
        &f,
        "POST",
        "/strategy/most-wanted",
        &internal,
        Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"text":null})),
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
    // Removal.
    let d = post("/strategy/most-wanted", json!({"text":null})).await;
    assert_eq!(
        (d.status.as_u16(), d.json["most_wanted"].clone()),
        (200, Value::Null)
    );
    assert!(!f.dir.join(crate::most_wanted::FILE_NAME).exists());
}

/// A station that is neither calling nor calling me, on `hz`.
fn busy(hz: f64) -> (&'static str, f64, Option<f64>) {
    ("W2XX W3YY -05", hz, Some(-5.0))
}
/// (Rx, Tx, the run's slot status).
async fn frequencies(f: &Mcp) -> (Value, Value, Value) {
    let settings = f.read("contact").await["settings"].clone();
    let slot = f.read("automation").await["run"]["tx_slot"].clone();
    (settings["rx_hz"].clone(), settings["tx_hz"].clone(), slot)
}

// Proves: CL-039-09; TC-039-010. My Tx parity after answering an even station is odd. Slots
// worked out by hand: an FT8 signal at f forbids the slots strictly between f-100 and f+100.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_010_a_strategy_takes_a_free_slot_keeps_it_and_changes_it_only_when_busy() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("New calls"))).await;
    // The 5th period back (would force 1720 Hz) and the other parity (too) do not count.
    publish(&f, e - 135_000, &[busy(1320.0)]);
    publish(&f, e - 105_000, &[busy(2000.0)]);
    publish(&f, e - 75_000, &[busy(1480.0)]);
    publish(&f, e - 60_000, &[busy(1290.0)]);
    publish(&f, e - 45_000, &[busy(1620.0)]);
    publish(&f, e - 15_000, &[busy(2100.0)]);
    // 1480 and 1620 forbid 1380 < slot < 1720: my Tx 1500 goes to 1380, Rx to the station.
    publish(&f, e, &[("CQ K1ABC FN42", 2400.0, Some(-5.0))]);
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
    assert_eq!(
        frequencies(&f).await,
        (json!(2400), json!(1380), json!({"hz":1380,"free":true}))
    );
    // The whole QSO stays there.
    publish(&f, e + 30_000, &[("HB9BLA K1ABC -10", 2400.0, Some(-10.0))]);
    assert_eq!(contact(&f).await.1, json!("roger_report"));
    assert_eq!(frequencies(&f).await.1, json!(1380));
    publish(
        &f,
        e + 60_000,
        &[("HB9BLA K1ABC RR73", 2400.0, Some(-10.0))],
    );
    assert_eq!(contact(&f).await.1, json!("signoff"));
    transmit_own_period(&f, e + 15_000).await;
    assert_eq!(contact(&f).await.1, json!("completed"));
    assert_eq!(frequencies(&f).await.1, json!(1380));
    f.tick();
    // The next call: last 4 odd periods 2650, 2100, 1620, 1480 leave 1380 free; it stays.
    publish(&f, e + 75_000, &[busy(2650.0)]);
    publish(&f, e + 90_000, &[("CQ DL1XYZ JO62", 900.0, Some(-5.0))]);
    assert_eq!(contact(&f).await.0, json!("DL1XYZ"));
    assert_eq!(
        frequencies(&f).await,
        (json!(900), json!(1380), json!({"hz":1380,"free":true}))
    );
    // calls_per_station 2 gives DL1XYZ up. The slot then becomes busy: the last 4 odd periods
    // 1400, 2650, 2100, 1620 and the station on 1000 forbid 900..1100, 1300..1500,
    // 1520..1720, 2000..2200, 2550..2750: 1300 is the nearest to 1380.
    publish(&f, e + 120_000, &[]);
    publish(&f, e + 150_000, &[]);
    publish(&f, e + 165_000, &[busy(1400.0)]);
    publish(&f, e + 180_000, &[("CQ G4ABC IO91", 1000.0, Some(-5.0))]);
    assert_eq!(contact(&f).await.0, json!("G4ABC"));
    assert_eq!(
        frequencies(&f).await,
        (json!(1000), json!(1300), json!({"hz":1300,"free":true}))
    );
}

// Proves: CL-039-09; TC-039-010.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_010_never_on_the_called_station_also_with_hold_tx_off() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("New calls"))).await;
    // A station on my Tx: 1400 and 1600 tie, the lower.
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-5.0))]);
    assert_eq!(
        frequencies(&f).await,
        (json!(1500), json!(1400), json!({"hz":1400,"free":true}))
    );
    // calls_per_station 2 gives K1ABC up. Hold Tx off: the selection moves Tx, the run takes it back.
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
        (json!(1700), json!(1400), json!({"hz":1400,"free":true}))
    );
    assert_eq!(f.keys(), 0);
}

// Proves: CL-039-09; TC-039-010. Signals every 190 Hz leave no FT8 slot in 300..2650.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_010_a_full_band_keeps_the_tx_still_calls_and_says_so() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("New calls"))).await;
    let full: Vec<_> = (0..13).map(|i| busy(f64::from(300 + 190 * i))).collect();
    publish(&f, e - 15_000, &full);
    publish(&f, e, &[("CQ K1ABC FN42", 2400.0, Some(-5.0))]);
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
    assert_eq!(
        frequencies(&f).await,
        (json!(2400), json!(1500), json!({"hz":1500,"free":false}))
    );
    assert_eq!(f.keys(), 0);
}

// Proves: CL-039-09; TC-039-010. A full band and a station on my Tx: no free slot, and the call
// still does not go out on the station: 1400 and 1600 tie for 1500, the lower.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_010_a_full_band_still_never_calls_on_the_called_station() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("New calls"))).await;
    let full: Vec<_> = (0..13).map(|i| busy(f64::from(300 + 190 * i))).collect();
    publish(&f, e - 15_000, &full);
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-5.0))]);
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
    assert_eq!(
        frequencies(&f).await,
        (json!(1500), json!(1400), json!({"hz":1400,"free":false}))
    );
}

// Proves: CL-039-09; TC-039-010. 4 periods fill the band; the 3 most recent leave a gap: 1350
// and 1500 forbid 1250..1600, 1600 is nearest 1500 (1250 is 250 away).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_010_a_band_filled_over_four_periods_looks_at_fewer() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("New calls"))).await;
    let full: Vec<_> = (0..13).map(|i| busy(f64::from(300 + 190 * i))).collect();
    publish(&f, e - 105_000, &full);
    publish(&f, e - 75_000, &[busy(1350.0)]);
    publish(&f, e - 45_000, &[busy(2000.0)]);
    publish(&f, e - 15_000, &[busy(1500.0)]);
    publish(&f, e, &[("CQ K1ABC FN42", 900.0, Some(-5.0))]);
    assert_eq!(
        frequencies(&f).await,
        (json!(900), json!(1600), json!({"hz":1600,"free":true}))
    );
}

// Proves: CL-039-09; TC-039-010. A retune on the radio keeps the live job: the signals of the old
// band say nothing about this one, and those of the new band do.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_010_signals_of_the_previous_band_do_not_count() {
    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("New calls"))).await;
    publish(&f, e - 15_000, &[busy(1500.0)]);
    f.state.recording.fixture_band("20m");
    publish(&f, e, &[("CQ K1ABC FN42", 2400.0, Some(-5.0))]);
    assert_eq!(contact(&f).await.0, json!("K1ABC"));
    assert_eq!(
        frequencies(&f).await,
        (json!(2400), json!(1500), json!({"hz":1500,"free":true}))
    );
    // calls_per_station 2 gives K1ABC up; a signal on this band counts: 1400 and 1600 tie.
    publish(&f, e + 30_000, &[]);
    publish(&f, e + 60_000, &[]);
    publish(&f, e + 75_000, &[busy(1500.0)]);
    publish(&f, e + 90_000, &[("CQ DL1XYZ JO62", 2200.0, Some(-5.0))]);
    assert_eq!(contact(&f).await.0, json!("DL1XYZ"));
    assert_eq!(
        frequencies(&f).await,
        (json!(2200), json!(1400), json!({"hz":1400,"free":true}))
    );
}

// Proves: CL-039-09; TC-039-010. A strategy run outlives its live job: after a retune (the slot
// reads from a sequence of that job) and a receive restart, the new job counts from its first record.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_010_a_new_live_job_counts_from_its_first_record() {
    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("New calls"))).await;
    publish(&f, e - 15_000, &[busy(600.0)]);
    f.state.recording.fixture_band("20m");
    publish(
        &f,
        e,
        &[
            busy(700.0),
            busy(800.0),
            busy(900.0),
            busy(1000.0),
            busy(1100.0),
            busy(2000.0),
        ],
    );
    f.state.recording.fixture_live_job("ft8");
    f.tick();
    // Odd, the new job's sequence 0: on my Tx. 1400 and 1600 tie for 1500, the lower.
    publish(&f, e + 15_000, &[busy(1500.0)]);
    publish(&f, e + 30_000, &[("CQ K1ABC FN42", 2400.0, Some(-5.0))]);
    assert_eq!(
        frequencies(&f).await,
        (json!(2400), json!(1400), json!({"hz":1400,"free":true}))
    );
}

// Proves: CL-039-05, CL-039-09; TC-039-010. Between the run's select_row and its Tx
// move the operator replaces the contact: the set_frequency is refused stale and the operator's
// contact stands.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_010_a_double_click_racing_the_slot_move_stays_the_operators() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("New calls"))).await;
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

// Proves: CL-039-09; TC-039-010. A pounce answers as a strategy run does.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_010_a_pounce_never_calls_on_the_called_station() {
    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    assert_eq!(pounce(&f, "K1ABC", 5).await.status, StatusCode::ACCEPTED);
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-5.0))]);
    assert_eq!(contact(&f).await.0, json!("K1ABC"));
    assert_eq!(
        frequencies(&f).await,
        (json!(1500), json!(1400), json!({"hz":1400,"free":true}))
    );
}

// Proves: CL-039-09; TC-039-010. A caller is a called station like any other: answered from a free
// slot, which holds for the exchange; a caller on my slot is answered from the slot beside it.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_010_a_caller_is_answered_from_a_free_slot_and_stays_there() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    select(&f, config(Some("New calls"))).await;
    publish(&f, e - 15_000, &[busy(1500.0)]);
    // My parity after answering an even caller is odd: this even period does not count.
    publish(&f, e, &[busy(1350.0)]);
    publish(
        &f,
        e + 30_000,
        &[("HB9BLA K1ABC FN42", 2000.0, Some(-10.0))],
    );
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("report"), json!("armed"))
    );
    assert_eq!(
        frequencies(&f).await,
        (json!(2000), json!(1400), json!({"hz":1400,"free":true}))
    );
    // No new decision during the exchange, also with a signal on the slot now.
    publish(&f, e + 45_000, &[("W2XX W3YY -05", 1400.0, Some(-5.0))]);
    assert_eq!(frequencies(&f).await.1, json!(1400));
    browser_ok(&f, "cancel", json!({})).await;
    f.tick();
    f.tick();
    // A caller on my slot: never on the called station (1400 ± 100), the nearest is 1300.
    publish(
        &f,
        e + 60_000,
        &[("HB9BLA DL1XYZ JO62", 1400.0, Some(-10.0))],
    );
    assert_eq!(contact(&f).await.0, json!("DL1XYZ"));
    assert_eq!(
        frequencies(&f).await,
        (json!(1400), json!(1300), json!({"hz":1300,"free":true}))
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
    select(&f, config(Some("New calls"))).await;
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
        json!("New calls")
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
    select(&f, config(Some("New calls"))).await;
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
        json!("New calls")
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
    select(&f, config(Some("New calls"))).await;
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
    select(&f, config(Some("New calls"))).await;
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
    select(&f, config(Some("New calls"))).await;
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
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    browser_watchdog(&f, 2).await;
    let mut c = config(Some("New calls"));
    c["strategies"][0]["calls_per_station"] = json!(20);
    select(&f, c.clone()).await;
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
    assert_eq!(active_of(&f).await, json!("New calls"), "it stays selected");
    // A new selection from the browser is an operator action: it arms again.
    browser_ok(&f, "cancel", json!({})).await;
    save(&f, config(None)).await;
    select(&f, c).await;
    publish(&f, e + 90_000, &[("CQ DL1XYZ JO62", 1200.0, Some(-1.0))]);
    assert_eq!(contact(&f).await.2, json!("armed"));
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
    let mut c = config(Some("New calls"));
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
    let mut c = config(Some("New calls"));
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
    let mut c = config(Some("New calls"));
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
    select(&f, config(Some("New calls"))).await;
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
    transmit_own_period(&f, e + 75_000).await;
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
            tx,
            json!(1700)
        ),
        "after a 73 Tx stays on its free slot"
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
    select(&f, config(Some("New calls"))).await;
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
    select(&f, config(Some("New calls"))).await;
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
    select(&f, config(Some("New calls"))).await;
    f.tick();
    assert_eq!(run_state(&f).await, ("waiting".into(), json!("activity")));
}

// ------------------------------------------------------------------ #42 Alert
/// The strategy "Alerts": rule 1 (call prefix K, no alert), rule 2 (any CQ, alert).
fn alerts_strategy() -> Value {
    json!({"name":"Alerts","class":"award","goals":["new_call"],"needed":"not_worked","region":{"kind":"all"},
        "min_snr_db":null,"calls_per_station":2,"treat_73_as_cq":false,"window":{"kind":"all"}})
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
