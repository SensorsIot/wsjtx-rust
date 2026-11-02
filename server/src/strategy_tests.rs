#![forbid(unsafe_code)]
// Proves: CL-039-01, CL-039-02, CL-039-03, CL-039-05, CL-039-06; TC-039-001..005 (each
// test names its case below). Hand-authored records and strategies; the expected ranks,
// grey marks, orders, stop reasons and requests are the WstxStrategy tables written in
// these tests (geography from the locator square centres), not evaluator output.
// Integration cases use the actual station router, contact engine and #9 transmit owner
// on the recording hardware double (virtual UTC; no audio, PTT or radio).
use super::*;
use crate::automation_tests::{at_even, publish, run_state, transmit_own_period};
use crate::contact_http_tests::record;
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

pub(crate) fn strategy_json(name: &str, role: &str) -> Value {
    json!({"name":name,"rules":[{"conditions":[{"kind":"message","negate":false,"value":"cq"},
        {"kind":"continent","negate":false,"values":["NA"]}]},{"conditions":[{"kind":"message","negate":false,"value":"cq"}]}],
        "sort":"strongest","treat_73_as_cq":true,"apply_to_callers":false,"skip_after":2,"auto_role":role,"switch_after":2})
}
fn config(active: Option<&str>, role: &str) -> Value {
    json!({"continent":null,"active":active,"highlight":true,"strategies":[strategy_json("NA first",role)]})
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
            json!({"continent":null,"active":null,"highlight":false,"strategies":[]}),
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

// Proves: TC-039-005
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_005_automation_never_resets_the_tx_watchdog() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    browser_watchdog(&f, 1).await;
    save(&f, config(Some("NA first"), "cq")).await;
    assert_eq!(auto(&f).await.status, StatusCode::ACCEPTED);
    f.tick();
    assert_eq!(contact(&f).await.1, json!("calling"));
    // Own CQ transmissions (a new text is keyed) never restart the watchdog.
    transmit_own_period(&f, e + 15_000).await;
    publish(
        &f,
        e + 30_000,
        &[("HB9BLA K1ABC FN42", 1500.0, Some(-10.0))],
    );
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("report"), json!("armed"))
    );
    transmit_own_period(&f, e + 45_000).await;
    // 61 s after the start (the last operator action) the watchdog ends it, mid-QSO.
    let service = &f.state.recording.transmit.get().unwrap().service;
    let started = e + 1000;
    f.bench
        .offset
        .fetch_add(started + 61_000 - f.bench.now_utc_ms(), Ordering::SeqCst);
    let deadline = Instant::now() + Duration::from_secs(5);
    while service.view().arm_state == wstx_rust::transmit::service::ArmState::Armed {
        assert!(Instant::now() < deadline);
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    f.tick();
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("tx_watchdog"))
    );
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["watchdog"]["tx_expired"].clone(),
            c["transmit"]["last_disarm_cause"].clone()
        ),
        (json!(true), json!("tx_watchdog"))
    );
    // A new run after the expiry may not arm: the operator's watchdog time is spent
    // only when no operator action follows; the Auto start itself is one, so it arms.
    let revision = f.read("contact").await["contact_revision"]
        .as_u64()
        .unwrap();
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
fn tc_039_005_core_watchdog_counts_from_the_operator_mark() {
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
    core.set_watchdogs(2, 90).unwrap();
    bench.offset.fetch_add(90_000, Ordering::SeqCst);
    core.arm_automatic(revision).unwrap();
    assert_eq!(
        core.view().tx_remaining_minutes,
        1,
        "counted from the mark 90 s ago"
    );
    bench.offset.fetch_add(31_000, Ordering::SeqCst);
    assert!(core.watchdog_spent());
    core.disarm(wstx_rust::transmit::service::DisarmCause::Operator);
    core.arm(revision).unwrap();
    assert_eq!(
        core.view().tx_remaining_minutes,
        2,
        "an operator arm restarts it"
    );
    assert_eq!(core.view().arm_state, ArmState::Armed);
}

// Proves: TC-039-005
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_005_auto_never_arms_after_the_operator_watchdog_time() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    browser_watchdog(&f, 1).await;
    save(&f, config(Some("NA first"), "call")).await;
    assert_eq!(auto(&f).await.status, StatusCode::ACCEPTED);
    // 61 s after the start (no candidate meanwhile) a matching CQ arrives.
    f.bench.offset.fetch_add(61_000, Ordering::SeqCst);
    publish(&f, e + 60_000, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("tx_watchdog"))
    );
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["transmit"]["arm_state"].clone(),
            c["contact"]["dx_call"].clone()
        ),
        (json!("disarmed"), Value::Null),
        "{c}"
    );
    assert_eq!(f.keys(), 0);
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
/// A browser (human) action that sets the Tx watchdog to `minutes`.
async fn browser_watchdog(f: &Mcp, minutes: u64) {
    let c = f.browser("GET", "/contact", None).await.json;
    let body = f.command(
        c["contact_revision"].as_u64().unwrap(),
        "set_watchdogs",
        json!({"tx_minutes":minutes,"tune_seconds":90}),
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
    let advance = |ms: i64| {
        f.bench.offset.fetch_add(ms, Ordering::SeqCst);
    };
    // No browser action since boot: an MCP Enable Tx is refused.
    let v = mcp_contact(&f, "enable_tx", json!({"enabled":true,"safety_revision":3})).await;
    assert_eq!(
        (v["status"].clone(), v["result"]["error"]["code"].clone()),
        (json!(409), json!("tx_watchdog")),
        "{v}"
    );
    assert!(!armed());
    // (1) An MCP run start 40 s after the browser action does not extend the watchdog.
    browser_watchdog(&f, 1).await;
    advance(40_000);
    let auto = |action: &str, extra: Value| {
        let mut b = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),"action":action});
        b.as_object_mut()
            .unwrap()
            .extend(extra.as_object().unwrap().clone());
        json!({ "command": b })
    };
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
    advance(21_000);
    publish(&f, e + 60_000, &[("CQ K1ABC FN42", 1500.0, Some(-1.0))]);
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("tx_watchdog")),
        "the MCP start is no operator action"
    );
    assert!(!armed());
    // (2) Repeated MCP commands do not extend it: 61 s after the browser action an MCP
    // Enable Tx is refused although MCP commands came at 20, 40 and 55 s.
    let _ = mcp_contact(&f, "cancel", json!({})).await;
    browser_watchdog(&f, 1).await;
    for step in [20_000, 20_000, 15_000] {
        advance(step);
        let v = mcp_contact(&f, "set_frequency", json!({"rx_hz":1200,"tx_hz":null})).await;
        assert_eq!(v["status"], 202, "{v}");
        assert!(!spent(), "still within the minute");
    }
    advance(6_000);
    assert!(spent());
    let v = mcp_contact(&f, "enable_tx", json!({"enabled":true,"safety_revision":3})).await;
    assert_eq!(v["result"]["error"]["code"], "tx_watchdog", "{v}");
    assert!(!armed());
    // An MCP client may not lengthen the spent watchdog (only the browser sets it).
    let v = mcp_contact(
        &f,
        "set_watchdogs",
        json!({"tx_minutes":99,"tune_seconds":90}),
    )
    .await;
    assert_eq!(v["result"]["error"]["code"], "operator_required", "{v}");
    assert!(spent());
    let v = mcp_contact(&f, "enable_tx", json!({"enabled":true,"safety_revision":3})).await;
    assert_eq!(v["result"]["error"]["code"], "tx_watchdog", "{v}");
    assert!(!armed());
    // (3) A browser action resets it: MCP may arm again; a later browser action extends it.
    browser_watchdog(&f, 1).await;
    let v = mcp_contact(&f, "enable_tx", json!({"enabled":true,"safety_revision":3})).await;
    assert_eq!(v["status"], 202, "{v}");
    assert!(armed());
    let v = mcp_contact(
        &f,
        "enable_tx",
        json!({"enabled":false,"safety_revision":null}),
    )
    .await;
    assert_eq!(v["status"], 202, "{v}");
    advance(50_000);
    browser_watchdog(&f, 1).await;
    advance(11_000);
    assert!(
        !spent(),
        "61 s after the first but 11 s after the last browser action"
    );
    advance(50_000);
    assert!(spent());
}
