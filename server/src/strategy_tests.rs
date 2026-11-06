#![forbid(unsafe_code)]
// Proves: CL-039-01, CL-039-02, CL-039-03, CL-039-05, CL-039-06, CL-042-01, CL-042-02, CL-042-03,
// CL-042-04; TC-039-001..005, TC-042-001, TC-042-002, TC-042-004, TC-042-006 (each test names its
// case below). Hand-authored records and strategies; the expected ranks,
// grey marks, orders, stop reasons and requests are the WstxStrategy tables written in
// these tests (geography from the locator square centres), not evaluator output.
// Integration cases use the actual station router, contact engine and #9 transmit owner
// on the recording hardware double (virtual UTC; no audio, PTT or radio).
use super::*;
use crate::automation_tests::{at_even, not_keyed_in, publish, run_state, transmit_own_period};
use crate::contact_http_tests::{period_text, record};
use crate::mcp_tests::{Mcp, station};
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
        my_grid: Some("JN47AA".into()),
        my_continent: Some("EU".into()),
        band: Some("40m".into()),
        ..Station::default()
    }
}
fn cond(v: Value) -> Condition {
    condition(&v, "c").unwrap()
}
fn strat(rules: Vec<Vec<Value>>, sort: Sort, treat_73: bool) -> Strategy {
    Strategy {
        name: "T".into(),
        rules: rules
            .into_iter()
            .map(|r| r.into_iter().map(cond).collect())
            .collect(),
        sort,
        treat_73_as_cq: treat_73,
        apply_to_callers: false,
        skip_after: 3,
        role: Role::Call,
        switch_after: 2,
        alerts: Vec::new(),
    }
}
fn cq() -> Value {
    json!({"kind":"message","negate":false,"value":"cq"})
}
fn ranks(s: &Strategy, records: &[Value], st: &Station) -> Vec<(u64, Option<usize>, bool)> {
    evaluate(s, records, st)
        .into_iter()
        .map(|v| (v.facts.sequence, v.rank, v.grey))
        .collect()
}
fn sorted(s: &Strategy, records: &[Value], st: &Station) -> Vec<u64> {
    let mut v: Vec<Verdict> = evaluate(s, records, st)
        .into_iter()
        .filter(|v| v.rank.is_some())
        .collect();
    order(&mut v, s.sort);
    v.into_iter().map(|v| v.facts.sequence).collect()
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
fn tc_039_002_continent_distance_and_directed_cq_rule() {
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
    // JN47AA (47.0208, 8.0417) to FN42 (42.5, -71.0): hand haversine, R 6371 km.
    assert_eq!(
        distance_bearing("JN47AA", "FN42").map(|d| d.0),
        Some(5989.0)
    );
    for (target, mine, sender, expected) in [
        ("EU", Some("EU"), None, true),
        ("NA", Some("EU"), Some("NA"), false),
        ("EU", None, Some("EU"), false),
        ("DX", Some("EU"), Some("EU"), false),
        ("DX", Some("EU"), Some("AS"), true),
        ("DX", Some("EU"), None, false),
        ("TEST", Some("EU"), Some("NA"), true),
        ("POTA", None, None, true),
    ] {
        assert_eq!(
            addressed_to_me(target, mine, sender),
            expected,
            "CQ {target} mine {mine:?} sender {sender:?}"
        );
    }
}

// Proves: TC-039-002
#[test]
fn tc_039_002_rules_rank_grey_and_order() {
    let records = table();
    let st = me();
    // Rule 1: CQ from North America; rule 2: any CQ.
    let na = json!({"kind":"continent","negate":false,"values":["NA"]});
    let s = strat(
        vec![vec![cq(), na.clone()], vec![cq()]],
        Sort::Strongest,
        false,
    );
    assert_eq!(
        ranks(&s, &records, &st),
        [
            (0, Some(0), false),
            (1, Some(1), false),
            (2, None, true),
            (3, Some(1), false),
            (4, None, true),
            (5, Some(1), false),
            (6, None, false),
            (7, None, false),
            (8, Some(0), false),
        ]
    );
    assert_eq!(sorted(&s, &records, &st), [8, 0, 1, 3, 5], "strongest");
    let weak = Strategy {
        sort: Sort::Weakest,
        ..s.clone()
    };
    assert_eq!(sorted(&weak, &records, &st), [0, 8, 5, 3, 1]);
    let newest = Strategy {
        sort: Sort::Newest,
        ..s.clone()
    };
    assert_eq!(sorted(&newest, &records, &st), [8, 0, 5, 3, 1]);
    // Berlin JO62 705 km, London IO91 823 km, Tokyo PM95 9618 km from JN47AA.
    let far = Strategy {
        sort: Sort::Furthest,
        ..s.clone()
    };
    assert_eq!(sorted(&far, &records, &st)[2..], [5, 3, 1]);
    // Treat 73 as CQ: K1ABC's RR73 counts as calling; without a grid its continent is
    // still known from cty.dat (#55), so it matches rule 1.
    let s73 = strat(vec![vec![cq(), na], vec![cq()]], Sort::Strongest, true);
    assert_eq!(ranks(&s73, &records, &st)[6], (6, Some(0), false));
    assert!(
        st.cq_like(&facts(&records[6]).unwrap(), true)
            && !st.cq_like(&facts(&records[7]).unwrap(), true),
        "a message to me is never 73-as-CQ"
    );
    // The hard rule holds whatever the rules say: an empty rule matches all but greyed.
    let any = strat(vec![vec![]], Sort::Strongest, false);
    assert_eq!(
        ranks(&any, &records, &st)
            .iter()
            .filter(|r| r.1.is_none())
            .map(|r| r.0)
            .collect::<Vec<_>>(),
        [2, 4]
    );
    // My continent unknown: every continent-directed CQ and CQ DX is greyed.
    let lost = Station {
        my_continent: None,
        ..me()
    };
    assert_eq!(
        ranks(&any, &records, &lost)
            .iter()
            .filter(|r| r.2)
            .map(|r| r.0)
            .collect::<Vec<_>>(),
        [2, 3, 4, 5]
    );
}

// Proves: TC-039-002
#[test]
fn tc_039_002_each_condition_and_its_negation() {
    let records = table();
    let mut st = me();
    st.calls.insert("K1ABC".into(), (true, false));
    st.calls.insert("DL1XYZ".into(), (true, true));
    st.grids.insert("JO62".into(), (true, true));
    let matching = |c: Value| -> Vec<u64> {
        let s = strat(vec![vec![cq(), c]], Sort::Newest, false);
        let mut m: Vec<u64> = ranks(&s, &records, &st)
            .into_iter()
            .filter(|r| r.1.is_some())
            .map(|r| r.0)
            .collect();
        m.sort();
        m
    };
    let all_cq = [0, 1, 3, 5, 8];
    let negated = |mut c: Value| {
        c["negate"] = json!(true);
        c
    };
    for (c, expected) in [
        (
            json!({"kind":"new_call","negate":false,"value":"ever"}),
            vec![3, 5, 8],
        ),
        (
            json!({"kind":"new_call","negate":false,"value":"band"}),
            vec![0, 3, 5, 8],
        ),
        (
            json!({"kind":"new_grid","negate":false,"value":"ever"}),
            vec![0, 3, 5, 8],
        ),
        (
            json!({"kind":"continent","negate":false,"values":["EU","AS"]}),
            vec![1, 3, 5],
        ),
        (
            json!({"kind":"distance_km","negate":false,"min":5000,"max":null}),
            vec![0, 5, 8],
        ),
        (
            json!({"kind":"azimuth_deg","negate":false,"min":250,"max":320}),
            vec![0, 3, 8],
        ),
        (
            json!({"kind":"snr_db","negate":false,"min":-10,"max":-2}),
            vec![1, 3, 8],
        ),
        (
            json!({"kind":"dt_s","negate":false,"min":0,"max":0.2}),
            all_cq.to_vec(),
        ),
        (
            json!({"kind":"audio_hz","negate":false,"min":1050,"max":1350}),
            vec![1, 3],
        ),
        (
            json!({"kind":"call","negate":false,"values":["K","JA1"]}),
            vec![0, 5],
        ),
        (
            json!({"kind":"cq_target","negate":false,"values":["TEST","DX"]}),
            vec![5, 8],
        ),
        (
            json!({"kind":"band","negate":false,"values":["40m"]}),
            all_cq.to_vec(),
        ),
        (
            json!({"kind":"band","negate":false,"values":["20m"]}),
            vec![],
        ),
        (
            json!({"kind":"message","negate":false,"value":"directed_cq"}),
            vec![3, 5, 8],
        ),
    ] {
        assert_eq!(matching(c.clone()), expected, "{c}");
        let complement: Vec<u64> = all_cq
            .iter()
            .copied()
            .filter(|s| !expected.contains(s))
            .collect();
        assert_eq!(matching(negated(c.clone())), complement, "not {c}");
    }
    let to_me = strat(
        vec![
            vec![json!({"kind":"message","negate":false,"value":"to_me"})]
                .into_iter()
                .collect(),
        ],
        Sort::Newest,
        false,
    );
    assert_eq!(ranks(&to_me, &records, &st)[7], (7, Some(0), false));
    let signoff = strat(
        vec![vec![
            json!({"kind":"message","negate":false,"value":"signoff"}),
        ]],
        Sort::Newest,
        false,
    );
    assert_eq!(ranks(&signoff, &records, &st)[6], (6, Some(0), false));
    // The explanation names the first failing condition of each rule.
    let s = strat(
        vec![vec![
            cq(),
            json!({"kind":"snr_db","negate":false,"min":0,"max":null}),
        ]],
        Sort::Newest,
        false,
    );
    let v = evaluate(&s, &records, &st);
    assert_eq!(v[0].why, "no match (rule 1: SNR 0.. dB)");
    assert_eq!(v[2].why, "CQ NA is not addressed to my continent (EU)");
    // Auto: a CQ TEST is answered only when the matched rule asks for TEST.
    let plain = strat(vec![vec![cq()]], Sort::Newest, false);
    let asks = strat(
        vec![vec![
            cq(),
            json!({"kind":"cq_target","negate":false,"values":["TEST"]}),
        ]],
        Sort::Newest,
        false,
    );
    let row = |s: &Strategy, n: u64| {
        evaluate(s, &records, &st)
            .into_iter()
            .find(|v| v.facts.sequence == n)
            .unwrap()
    };
    assert!(!auto_target_ok(&plain, &row(&plain, 8)) && auto_target_ok(&asks, &row(&asks, 8)));
    assert!(
        auto_target_ok(&plain, &row(&plain, 3)),
        "CQ EU for my continent stays answerable"
    );
    assert!(sane_call("K1ABC") && !sane_call("K1") && !sane_call("ABCDE") && !sane_call("W1AW/R"));
}

// Proves: TC-042-001
#[test]
fn tc_042_001_new_dxcc_continent_and_zones_ever_and_on_this_band_and_mode() {
    use crate::dxcc::{Logged, Worked};
    // The hand log (entity columns of the cited cty.dat lines): DL1ABC 40m FT8 (Fed.
    // Rep. of Germany, EU, CQ 14, ITU 28, line 669), JA1XYZ 20m FT8 (Japan, AS, 25, 45,
    // line 1223), F1ABC 40m FT4 (France, EU, 14, 27, line 797), K2ABC without a band
    // (United States, NA, 5, 8, line 1251), Q1ABC 40m FT8 (no entity).
    let log = |call: &str, band: Option<&str>, mode: &str| Logged {
        call: call.into(),
        grid: None,
        band: band.map(Into::into),
        mode: Some(mode.into()),
        confirmed: false,
    };
    let mut st = me();
    st.mode = "FT8".into();
    st.worked = Some(std::sync::Arc::new(Worked::from_log(
        &st.dxcc,
        &[
            log("DL1ABC", Some("40m"), "FT8"),
            log("JA1XYZ", Some("20m"), "FT8"),
            log("F1ABC", Some("40m"), "FT4"),
            log("K2ABC", None, "FT8"),
            log("Q1ABC", Some("40m"), "FT8"),
        ],
    )));
    // Rows: 0 Germany, 1 France, 2 Japan, 3 Australia (OC, 30, 59, line 3977),
    // 4 United States, 5 XX1ABC (no entity: no cty.dat prefix starts it).
    let records = rows(&[
        ("CQ DL2XYZ JO62", Some(-5.0)),
        ("CQ F5ABC JN18", Some(-5.0)),
        ("CQ JA2ABC PM84", Some(-5.0)),
        ("CQ VK2ABC QF56", Some(-5.0)),
        ("CQ K1ABC FN42", Some(-5.0)),
        ("CQ XX1ABC FN42", Some(-5.0)),
    ]);
    let all: Vec<u64> = (0..6).collect();
    let matching = |st: &Station, c: &Value| -> Vec<u64> {
        let s = strat(vec![vec![cq(), c.clone()]], Sort::Newest, false);
        let mut m: Vec<u64> = ranks(&s, &records, st)
            .into_iter()
            .filter(|r| r.1.is_some())
            .map(|r| r.0)
            .collect();
        m.sort();
        m
    };
    let c =
        |kind: &str, value: &str, negate: bool| json!({"kind":kind,"negate":negate,"value":value});
    for (kind, ever, band) in [
        ("new_dxcc", vec![3], vec![1, 2, 3, 4]),
        ("new_continent", vec![3], vec![2, 3, 4]),
        ("new_cq_zone", vec![3], vec![2, 3, 4]),
        ("new_itu_zone", vec![3], vec![1, 2, 3, 4]),
    ] {
        for (scope, expected) in [("ever", &ever), ("band", &band)] {
            // The wire form round-trips exactly.
            assert_eq!(cond(c(kind, scope, false)).json(), c(kind, scope, false));
            assert_eq!(
                matching(&st, &c(kind, scope, false)),
                *expected,
                "{kind} {scope}"
            );
            let complement: Vec<u64> = all
                .iter()
                .copied()
                .filter(|s| !expected.contains(s))
                .collect();
            assert_eq!(
                matching(&st, &c(kind, scope, true)),
                complement,
                "not {kind} {scope}"
            );
        }
        // Exact keys and values.
        assert_eq!(
            condition(&c(kind, "any", false), "c").unwrap_err(),
            "c.value",
            "{kind}"
        );
        assert_eq!(
            condition(&json!({"kind":kind,"negate":false,"values":["ever"]}), "c").unwrap_err(),
            "c"
        );
        assert_eq!(
            condition(&json!({"kind":kind,"negate":false}), "c").unwrap_err(),
            "c"
        );
        // Station band unknown: the band form never holds; ever is unchanged.
        let lost = Station {
            band: None,
            ..st.clone()
        };
        assert_eq!(
            matching(&lost, &c(kind, "band", false)),
            Vec::<u64>::new(),
            "{kind}"
        );
        assert_eq!(matching(&lost, &c(kind, "ever", false)), ever, "{kind}");
        // Log unreadable: no claim of new.
        let unread = Station {
            worked: None,
            ..st.clone()
        };
        for scope in ["ever", "band"] {
            assert_eq!(
                matching(&unread, &c(kind, scope, false)),
                Vec::<u64>::new(),
                "{kind}"
            );
        }
    }
    let s = strat(
        vec![vec![cq(), c("new_dxcc", "band", false)]],
        Sort::Newest,
        false,
    );
    assert_eq!(
        evaluate(&s, &records, &st)[0].why,
        "no match (rule 1: new DXCC on band)"
    );
    let s = strat(
        vec![vec![c("new_itu_zone", "ever", true)]],
        Sort::Newest,
        false,
    );
    assert_eq!(
        evaluate(&s, &records, &st)[3].why,
        "no match (rule 1: not new ITU zone)"
    );
}

pub(crate) fn strategy_json(name: &str, role: &str) -> Value {
    json!({"name":name,"rules":[{"conditions":[{"kind":"message","negate":false,"value":"cq"},
        {"kind":"continent","negate":false,"values":["NA"]}]},{"conditions":[{"kind":"message","negate":false,"value":"cq"}]}],
        "sort":"strongest","treat_73_as_cq":true,"apply_to_callers":false,"skip_after":2,"auto_role":role,"switch_after":2})
}
fn config(active: Option<&str>, role: &str) -> Value {
    json!({"continent":null,"active":active,"highlight":true,"strategies":[strategy_json("NA first",role)],
        "ignore_calls":[],"session_ignore_minutes":30})
}

// Proves: TC-039-001
#[test]
fn tc_039_001_configuration_is_exact() {
    let ok = parse_config(&config(Some("NA first"), "alternate")).unwrap();
    assert_eq!(
        ok.json(),
        config(Some("NA first"), "alternate"),
        "round trip"
    );
    assert_eq!(ok.active_strategy().unwrap().role, Role::Alternate);
    let set = |path: &[&str], v: Value| {
        let mut c = config(Some("NA first"), "call");
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
    for (path, value, field) in [
        (&["continent"][..], json!("XX"), "continent"),
        (&["active"][..], json!("missing"), "active"),
        (&["highlight"][..], json!(1), "highlight"),
        (
            &["strategies", "0", "name"][..],
            json!(" padded"),
            "strategies[0].name",
        ),
        (
            &["strategies", "0", "name"][..],
            json!(""),
            "strategies[0].name",
        ),
        (
            &["strategies", "0", "rules"][..],
            json!([]),
            "strategies[0].rules",
        ),
        (
            &["strategies", "0", "sort"][..],
            json!("rarest"),
            "strategies[0].sort",
        ),
        (
            &["strategies", "0", "skip_after"][..],
            json!(0),
            "strategies[0].skip_after",
        ),
        (
            &["strategies", "0", "switch_after"][..],
            json!(21),
            "strategies[0].switch_after",
        ),
        (
            &["strategies", "0", "auto_role"][..],
            json!("pounce"),
            "strategies[0].auto_role",
        ),
        (
            &["strategies", "0", "treat_73_as_cq"][..],
            json!("yes"),
            "strategies[0].treat_73_as_cq",
        ),
        (
            &["strategies", "0", "rules", "0", "conditions", "0", "kind"][..],
            json!("dxcc"),
            "strategies[0].rules[0].conditions[0].kind",
        ),
        (
            &["strategies", "0", "rules", "0", "conditions", "0", "value"][..],
            json!("any"),
            "strategies[0].rules[0].conditions[0].value",
        ),
        (
            &["strategies", "0", "rules", "0", "conditions", "1", "values"][..],
            json!(["NA", "NA"]),
            "strategies[0].rules[0].conditions[1].values[1]",
        ),
        (
            &["strategies", "0", "rules", "0", "conditions", "1", "values"][..],
            json!([]),
            "strategies[0].rules[0].conditions[1].values",
        ),
    ] {
        assert_eq!(
            set(path, value.clone()),
            Err(field.to_owned()),
            "{path:?}={value}"
        );
    }
    let mut c = config(None, "call");
    c["strategies"] = json!([strategy_json("A", "call"), strategy_json("a", "cq")]);
    assert_eq!(
        parse_config(&c),
        Err("strategies[1].name".into()),
        "names unique ignoring case"
    );
    let mut c = config(None, "call");
    c["strategies"][0]["rules"][0]["conditions"] =
        json!([{"kind":"snr_db","negate":false,"min":0,"max":-5}]);
    assert_eq!(
        parse_config(&c),
        Err("strategies[0].rules[0].conditions[0].max".into())
    );
    c["strategies"][0]["rules"][0]["conditions"] =
        json!([{"kind":"snr_db","negate":false,"min":null,"max":null}]);
    assert_eq!(
        parse_config(&c),
        Err("strategies[0].rules[0].conditions[0].min".into())
    );
    c["strategies"][0]["rules"][0]["conditions"] =
        json!([{"kind":"azimuth_deg","negate":false,"min":300,"max":60}]);
    assert!(
        parse_config(&c).is_ok(),
        "an azimuth range may wrap through north"
    );
    c["strategies"][0]["rules"][0]["conditions"] =
        json!([{"kind":"snr_db","negate":false,"min":0,"max":null,"extra":1}]);
    assert_eq!(
        parse_config(&c),
        Err("strategies[0].rules[0].conditions[0]".into())
    );
    let mut c = config(None, "call");
    c["strategies"] = json!(
        (0..17)
            .map(|i| strategy_json(&format!("S{i}"), "call"))
            .collect::<Vec<_>>()
    );
    assert_eq!(parse_config(&c), Err("strategies".into()));
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
            json!({"continent":null,"active":null,"highlight":false,"strategies":[],
                "ignore_calls":[],"session_ignore_minutes":30}),
            json!("EU")
        ),
        "default: no strategy; continent derived from JN47AA"
    );
    let p = put(&f, json!(0), config(Some("NA first"), "call")).await;
    assert_eq!(p.status, StatusCode::OK, "{}", p.json);
    assert_eq!(p.json["revision"], 1);
    let saved: Value =
        serde_json::from_slice(&std::fs::read(f.dir.join(FILE_NAME)).unwrap()).unwrap();
    assert_eq!(
        saved,
        json!({"schema_version":1,"profile_id":f.id,"revision":1,"configuration":config(Some("NA first"),"call")})
    );
    // A fresh owner (next boot) reads the same file.
    let reopened = Owner::default();
    assert_eq!(
        reopened.snapshot(&f.state)["configuration"],
        config(Some("NA first"), "call")
    );
    let mut other = config(Some("NA first"), "call");
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
    let v = f
        .browser("POST", "/strategy/evaluate", Some(body(Value::Null, false)))
        .await;
    assert_eq!(v.status, StatusCode::OK, "{}", v.json);
    assert_eq!(
        v.json["verdicts"],
        json!([{"sequence":0,"rank":0,"grey":false},{"sequence":3,"rank":1,"grey":false},{"sequence":1,"rank":null,"grey":true}]),
        "display order: rank, then sort, then the rest"
    );
    let mut draft = strategy_json("Draft", "call");
    draft["rules"] = json!([{"conditions":[{"kind":"message","negate":false,"value":"to_me"}]}]);
    let v = f
        .browser("POST", "/strategy/evaluate", Some(body(draft, true)))
        .await;
    assert_eq!(v.json["strategy"], "Draft");
    assert_eq!(
        v.json["verdicts"][0],
        json!({"sequence":2,"rank":0,"grey":false,"why":"matches rule 1"})
    );
    assert_eq!(
        v.json["verdicts"][1]["why"],
        "no match (rule 1: message to me)"
    );
    assert_eq!(
        v.json["verdicts"].as_array().unwrap().len(),
        4,
        "explain lists every decoded row"
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

// ------------------------------------------------------------------ Auto runs
/// Configure and start a strategy run from the browser (cookie grant), as the Auto
/// button does.
async fn auto(f: &Mcp) -> crate::mcp_tests::Reply {
    let a = f.browser("GET", "/automation", None).await.json;
    let cfg = json!({"modes":["ft8"],"ranking":"first_seen","min_snr_db":null,"allowed_calls":[],"blocked_calls":[],
        "max_contacts":100,"max_unanswered_periods":20,"completion_action":"next_candidate","max_run_minutes":480,"strategy":true});
    let c = f.browser("POST", "/automation/command", Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,
        "command_id":profile::new_uuid().unwrap(),"action":"configure","expected_policy_revision":a["policy_revision"],"configuration":cfg}))).await;
    assert_eq!(c.status, StatusCode::ACCEPTED, "{}", c.json);
    let a = f.browser("GET", "/automation", None).await.json;
    let safety = f.read("contact").await["transmit"]["safety_revision"].clone();
    f.browser("POST", "/automation/command", Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,
        "command_id":profile::new_uuid().unwrap(),"action":"start","expected_policy_revision":a["policy_revision"],
        "expected_run_revision":a["run_revision"],"mode":"ft8","safety_revision":safety}))).await
}
async fn save(f: &Mcp, configuration: Value) {
    let revision = f.browser("GET", "/strategy", None).await.json["revision"].clone();
    let r = put(f, revision, configuration).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);
}
async fn contact(f: &Mcp) -> (Value, Value, Value) {
    let c = f.read("contact").await;
    (
        c["contact"]["dx_call"].clone(),
        c["contact"]["state"].clone(),
        c["transmit"]["arm_state"].clone(),
    )
}

// Proves: TC-039-004
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_auto_call_follows_the_strategy_and_the_directed_cq_rule() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let none = auto(&f).await;
    assert_eq!(
        (
            none.json["error"]["code"].clone(),
            none.json["error"]["field"].clone()
        ),
        (json!("not_configured"), json!("strategy")),
        "Auto never runs unfiltered"
    );
    save(&f, config(Some("NA first"), "call")).await;
    let started = auto(&f).await;
    assert_eq!(started.status, StatusCode::ACCEPTED, "{}", started.json);
    // The active strategy cannot be switched away while Auto runs.
    let r = put(
        &f,
        f.browser("GET", "/strategy", None).await.json["revision"].clone(),
        config(None, "call"),
    )
    .await;
    assert_eq!(
        (r.status.as_u16(), r.json["error"]["field"].clone()),
        (409, json!("active"))
    );
    // CQ NA (not for EU) is never answered even though strongest; NA beats EU (rule 1).
    publish(
        &f,
        e,
        &[
            ("CQ NA W1AW FN31", 900.0, Some(5.0)),
            // Country- and number-directed: never answered unless a rule asks for them.
            ("CQ JA JA1XYZ PM95", 600.0, Some(9.0)),
            ("CQ 290 N1MM FN31", 700.0, Some(8.0)),
            ("CQ DL1XYZ JO62", 1200.0, Some(0.0)),
            ("CQ K1ABC FN42", 1500.0, Some(-15.0)),
        ],
    );
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (
            run["state"].clone(),
            run["role"].clone(),
            run["last_decision"]["candidates"].clone()
        ),
        (json!("contact_active"), json!("call"), json!(2))
    );
    // skip_after 2: two partner periods without an answer give K1ABC up; the run goes on.
    publish(&f, e + 30_000, &[]);
    publish(&f, e + 60_000, &[]);
    assert_eq!(contact(&f).await.2, json!("disarmed"));
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (
            run["state"].clone(),
            run["skipped"].clone(),
            run["reason"].clone()
        ),
        (json!("waiting"), json!(["K1ABC"]), Value::Null)
    );
    // Treat 73 as CQ: K1ABC is skipped; DL1XYZ's RR73 is answered, keeping my Tx frequency.
    let tx = f.read("contact").await["settings"]["tx_hz"].clone();
    publish(
        &f,
        e + 90_000,
        &[
            ("CQ K1ABC FN42", 1500.0, Some(-1.0)),
            ("W1AW DL1XYZ RR73", 1700.0, Some(-9.0)),
        ],
    );
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["contact"]["dx_call"].clone(),
            c["contact"]["messages"][0].clone(),
            c["transmit"]["arm_state"].clone()
        ),
        (json!("DL1XYZ"), json!("DL1XYZ HB9BLA JN47"), json!("armed"))
    );
    assert_eq!(
        (
            c["settings"]["tx_hz"].clone(),
            c["settings"]["rx_hz"].clone()
        ),
        (tx, json!(1700)),
        "Hold Tx after a 73"
    );
    // HALT ends the run.
    let halt = f.browser("POST", "/transmit/halt", Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap()}))).await;
    assert_eq!(halt.status, StatusCode::ACCEPTED);
    f.tick();
    assert_eq!(run_state(&f).await, ("stopped".into(), json!("halted")));
    assert_eq!(f.keys(), 0);
}

// Proves: TC-039-004
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_004_auto_cq_answers_a_caller_and_alternates_after_n_tries() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    save(&f, config(Some("NA first"), "alternate")).await;
    assert_eq!(auto(&f).await.status, StatusCode::ACCEPTED);
    // Alternate starts as Auto Call: two publications without a candidate switch to CQ.
    publish(&f, e, &[("CQ NA W1AW FN31", 900.0, Some(5.0))]);
    publish(&f, e + 15_000, &[]);
    f.tick();
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["contact"]["state"].clone(),
            c["transmit"]["arm_state"].clone(),
            c["contact"]["messages"][5].clone()
        ),
        (json!("calling"), json!("armed"), json!("CQ HB9BLA JN47"))
    );
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (run["state"].clone(), run["role"].clone()),
        (json!("calling_cq"), json!("cq"))
    );
    // A caller in the partner (even) period is answered; its RR73 tailender is not.
    publish(
        &f,
        e + 30_000,
        &[
            ("HB9BLA OH1AA RR73", 800.0, Some(9.0)),
            ("HB9BLA K1ABC FN42", 1500.0, Some(-10.0)),
        ],
    );
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("report"), json!("armed"))
    );
    publish(
        &f,
        e + 60_000,
        &[("HB9BLA K1ABC R-05", 1500.0, Some(-10.0))],
    );
    assert_eq!(contact(&f).await.1, json!("rogers"));
    publish(&f, e + 90_000, &[("HB9BLA K1ABC 73", 1500.0, Some(-10.0))]);
    let c = contact(&f).await;
    assert_eq!(c.1, json!("completed"), "{c:?}");
    // After the QSO the CQ role calls CQ again.
    f.tick();
    f.tick();
    assert_eq!(contact(&f).await.1, json!("calling"));
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (run["state"].clone(), run["completed_contacts"].clone()),
        (json!("calling_cq"), json!(1))
    );
    // Two partner periods without a caller switch back to Auto Call (CQ ended, disarmed).
    publish(&f, e + 120_000, &[]);
    publish(&f, e + 150_000, &[]);
    let run = f.read("automation").await["run"].clone();
    assert_eq!(
        (run["state"].clone(), run["role"].clone()),
        (json!("waiting"), json!("call"))
    );
    assert_eq!(contact(&f).await.2, json!("disarmed"));
    assert_eq!(f.keys(), 0);
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
    save(&f, config(Some("NA first"), "cq")).await;
    assert_eq!(auto(&f).await.status, StatusCode::ACCEPTED);
    f.tick();
    assert_eq!(contact(&f).await.1, json!("calling"));
    let halt = f.read("contact").await["transmit"]["halt_state"].clone();
    // The own CQ is Rep 1; the run's reply to the caller is a different message; the
    // report and its repeat are Rep 1 and 2; the next is never keyed.
    transmit_own_period(&f, e + 15_000).await;
    assert_eq!(f.read("contact").await["watchdog"]["tx_remaining_calls"], 1);
    publish(
        &f,
        e + 30_000,
        &[("HB9BLA K1ABC FN42", 1500.0, Some(-10.0))],
    );
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("report"), json!("armed"))
    );
    assert_eq!(f.read("contact").await["watchdog"]["tx_remaining_calls"], 2);
    transmit_own_period(&f, e + 45_000).await;
    transmit_own_period(&f, e + 75_000).await;
    let keys = f.keys();
    not_keyed_in(&f, e + 105_000).await;
    assert_eq!(f.keys(), keys, "never keyed after the limit");
    f.tick();
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("tx_watchdog"))
    );
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["watchdog"]["tx_expired"].clone(),
            c["transmit"]["last_disarm_cause"].clone(),
            c["transmit"]["halt_state"].clone(),
        ),
        (json!(true), json!("tx_watchdog"), halt),
        "stopped without a halt"
    );
    // A new browser Auto start is an operator action: it arms again.
    let revision = c["contact_revision"].as_u64().unwrap();
    f.tool(
        "wstx_contact_command",
        json!({"command":f.command(revision, "cancel", json!({}))}),
    )
    .await;
    assert_eq!(auto(&f).await.status, StatusCode::ACCEPTED);
    f.tick();
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
    let mut c = config(Some("NA first"), "call");
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
    let s = strat(vec![vec![cq()]], Sort::Strongest, false);
    let mut st = me();
    assert_eq!(
        ranks(&s, &records, &st),
        vec![
            (0, Some(0), false),
            (1, Some(0), false),
            (2, None, true),
            (3, None, false)
        ]
    );
    st.ignored.insert("K1ABC".into(), Tier::Permanent);
    st.ignored.insert("W1AW".into(), Tier::Session);
    let v = evaluate(&s, &records, &st);
    assert_eq!(
        v.iter()
            .map(|v| (v.facts.sequence, v.rank, v.grey, v.ignored))
            .collect::<Vec<_>>(),
        vec![
            (0, None, false, true),
            (1, Some(0), false, false),
            (2, None, false, true),
            (3, None, false, false)
        ]
    );
    assert_eq!(v[0].why, "K1ABC is ignored (permanent list)");
    assert_eq!(v[2].why, "W1AW is ignored (session list)");
    // An empty rule holds for every message, still not for an ignored sender.
    let all = strat(vec![vec![]], Sort::Strongest, false);
    assert_eq!(sorted(&all, &records, &st), vec![1, 3]);
    // Exact calls, not prefixes.
    let mut prefix = me();
    prefix.ignored.insert("K1".into(), Tier::Permanent);
    assert_eq!(ranks(&s, &records, &prefix)[0], (0, Some(0), false));
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
    let legacy = json!({"continent":null,"active":"NA first","highlight":true,
        "strategies":[strategy_json("NA first","call")]});
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
    let mut c = config(Some("NA first"), "call");
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
        json!([{"sequence":0,"rank":0,"grey":false,"why":"matches rule 1"},
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
            (json!(1), json!("matches rule 1")),
            (json!(0), json!("matches rule 1")),
            (json!(2), json!("DL1XYZ is ignored (permanent list)"))
        ],
        "W1AW is no longer ignored on 20m; the permanent list stays"
    );
    assert_eq!(f.keys(), 0, "ignore lists never key");
}

// Proves: TC-042-002
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_042_002_auto_call_never_selects_an_ignored_station() {
    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let mut c = config(Some("NA first"), "call");
    c["ignore_calls"] = json!(["K1ABC"]);
    save(&f, c).await;
    assert_eq!(
        ignore(&f, json!("W1AW"), json!(true)).await.status,
        StatusCode::OK
    );
    assert_eq!(auto(&f).await.status, StatusCode::ACCEPTED);
    // K1ABC (permanent) and W1AW (session) would both rank first (NA, rule 1).
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
async fn tc_042_002_auto_cq_never_answers_an_ignored_caller() {
    let f = station(true).await;
    f.state.recording.fixture_band("40m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    // apply_to_callers is off: Auto CQ answers every caller, but not an ignored one.
    save(&f, config(Some("NA first"), "alternate")).await;
    assert_eq!(auto(&f).await.status, StatusCode::ACCEPTED);
    publish(&f, e, &[("CQ NA W1AW FN31", 900.0, Some(5.0))]);
    publish(&f, e + 15_000, &[]);
    f.tick();
    assert_eq!(
        f.read("automation").await["run"]["state"],
        json!("calling_cq")
    );
    assert_eq!(
        ignore(&f, json!("K1ABC"), json!(true)).await.status,
        StatusCode::OK
    );
    publish(
        &f,
        e + 30_000,
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
        Err(("invalid_request", Some("pounce")))
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
    // K1ABC ends its QSO with W1AW: answered, my Tx frequency held.
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
        "Hold Tx after a 73"
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
    assert_eq!(code(&auto(&f).await), (json!("not_ready"), json!("call")));
    f.state.store.lock().unwrap().document.callsign = "HB9BLA".into();
    assert_eq!(
        code(&auto(&f).await),
        (json!("not_configured"), json!("strategy"))
    );
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
    let r = auto(&f).await;
    assert_eq!(
        (
            r.json["error"]["code"].clone(),
            r.json["error"]["field"].clone()
        ),
        (json!("not_ready"), json!("activity"))
    );
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
    let r = auto(&f).await;
    assert_eq!(
        (
            r.json["error"]["code"].clone(),
            r.json["error"]["field"].clone()
        ),
        (json!("not_ready"), json!("activity"))
    );
}

// ------------------------------------------------------------------ #42 Alert
/// The strategy "Alerts": rule 1 (call prefix K, no alert), rule 2 (any CQ, alert).
fn alerts_strategy() -> Value {
    json!({"name":"Alerts","rules":[{"conditions":[{"kind":"call","negate":false,"values":["K"]}]},
        {"conditions":[{"kind":"message","negate":false,"value":"cq"}],"alert":true}],
        "sort":"strongest","treat_73_as_cq":false,"apply_to_callers":false,"skip_after":2,"auto_role":"call","switch_after":2})
}

// Proves: TC-042-006 (WstxStrategy::Strategy rule key alert, WstxStrategy::Alert; the
// expected alert rules are written here from the contract, not evaluator output).
#[test]
fn tc_042_006_alert_rule_key_is_exact_and_names_the_first_alert_rule() {
    let mut c = config(Some("NA first"), "call");
    c["strategies"][0]["rules"][1]["alert"] = json!(true);
    let ok = parse_config(&c).unwrap();
    assert_eq!(ok.json(), c, "alert true reads back on its rule");
    assert_eq!(ok.strategies[0].alerts, vec![1]);
    let mut off = config(Some("NA first"), "call");
    off["strategies"][0]["rules"][0]["alert"] = json!(false);
    assert_eq!(
        parse_config(&off).unwrap().json(),
        config(Some("NA first"), "call"),
        "alert false reads back without the key"
    );
    let mut bad = config(Some("NA first"), "call");
    bad["strategies"][0]["rules"][0]["alert"] = json!("yes");
    assert_eq!(
        parse_config(&bad),
        Err("strategies[0].rules[0].alert".to_owned())
    );
    let mut extra = config(Some("NA first"), "call");
    extra["strategies"][0]["rules"][0]["sound"] = json!(true);
    assert_eq!(
        parse_config(&extra),
        Err("strategies[0].rules[0]".to_owned())
    );
    // Rule 1 (call K, no alert) and rule 2 (CQ, alert): K1ABC ranks by rule 1 and alerts
    // by rule 2; DL1XYZ ranks and alerts by rule 2; the CQ NA (greyed), the ignored
    // G4ABC and the message to me never alert.
    let s = Strategy {
        alerts: vec![1],
        ..strat(
            vec![
                vec![json!({"kind":"call","negate":false,"values":["K"]})],
                vec![cq()],
            ],
            Sort::Newest,
            false,
        )
    };
    let records = rows(&[
        ("CQ K1ABC FN42", Some(-12.0)),
        ("CQ DL1XYZ JO62", Some(-3.0)),
        ("CQ NA W1AW FN31", Some(-5.0)),
        ("CQ G4ABC IO91", Some(-8.0)),
        ("HB9BLA VK2ABC QF56", Some(-20.0)),
    ]);
    let mut st = me();
    st.ignored.insert("G4ABC".into(), Tier::Session);
    assert_eq!(
        evaluate(&s, &records, &st)
            .iter()
            .map(|v| (v.facts.sequence, v.rank, v.alert))
            .collect::<Vec<_>>(),
        vec![
            (0, Some(0), Some(1)),
            (1, Some(1), Some(1)),
            (2, None, None),
            (3, None, None),
            (4, None, None),
        ]
    );
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
    // Before any rule is marked alert: the cursor passes JA1XYZ, which never alerts later.
    publish(&f, e, &[("CQ JA1XYZ PM95", 1100.0, Some(-15.0))]);
    let mut c = config(Some("Alerts"), "call");
    c["strategies"] = json!([alerts_strategy()]);
    save(&f, c).await;
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
            {"id":1,"utc":utc,"call":"K1ABC","message":"CQ K1ABC FN42","rule":"Alerts rule 2",
                "band":"40m","mode":"ft8","snr_db":-12.0,"dxcc":"United States"},
            {"id":2,"utc":utc,"call":"DL1XYZ","message":"CQ DL1XYZ JO62","rule":"Alerts rule 2",
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
