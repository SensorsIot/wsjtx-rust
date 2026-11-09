#![forbid(unsafe_code)]
// #97 strategy redesign (WstxStrategy D19, CL-097-01..07): TC-097-001..008 and TC-097-010 at cost 2.
// The expected values, refusal paths, tables and orders are written here from the model
// (WstxStrategy::Strategy, BuiltinStrategies, StrategyConfiguration, Candidate, CountryList,
// UsStateFilter, CqTargetList, CallerOfMyCall, ValueOrder, TxMoveRule, FreeTxSlot) and from the
// cited cty.dat lines (Fed. Rep. of Germany 669, Japan 1223, United States 1251); never evaluator
// output.
use super::*;

const EMPTY: &str = r#"{"include":[],"exclude":[]}"#;
fn empty() -> Value {
    serde_json::from_str(EMPTY).unwrap()
}
/// A class contest strategy of ww_digi with the contest built-in's values.
fn contest_json(name: &str) -> Value {
    json!({"name":name,"class":"contest","bands":null,
        "filters":{"countries":empty(),"states":empty(),"cq_targets":empty()},
        "order":[],"contest":"ww_digi","callers_first":true,
        "leave":{"mode":"contest","tx_changes":2},
        "tx_move_every":{"heard":0,"not_heard":2,"no_reports":2},"busy_pause":false,
        "cq_when_idle":true,"retry_minutes":10})
}
fn configuration(strategies: Value) -> Value {
    json!({"continent":null,"active":null,"strategies":strategies,"ignore_calls":[],
        "session_ignore_minutes":30})
}
/// The bundled country table (a PUT checks country names against it).
fn table() -> crate::dxcc::Table {
    crate::dxcc::Table::default()
}

// Proves: TC-097-001
#[test]
fn tc_097_001_schema_4_every_key_at_its_bounds_and_one_refusal_per_field() {
    // Strategy 0, class strategy, every key at its bounds with the stated entry shape.
    let bands: Vec<&str> = vec![
        "2190m", "630m", "560m", "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m",
        "10m", "8m", "6m", "5m", "4m", "2m", "1.25m", "70cm", "33cm", "23cm", "13cm", "9cm", "6cm",
        "3cm", "1.25cm", "6mm", "4mm", "2.5mm", "2mm", "1mm",
    ];
    assert_eq!(bands.len(), 32);
    let entry = |i: usize| json!({"kind":"prefix","value":format!("A{:02}", i % 100),"bands":null});
    let mut include: Vec<Value> = (0..64).map(entry).collect();
    include[0] = json!({"kind":"prefix","value":"VK9ABCDEFGHIJ","bands":null});
    include[1] = json!({"kind":"prefix","value":"VK9","bands":bands});
    let exclude: Vec<Value> = (0..64).map(entry).collect();
    let words = |c: char| -> Vec<String> { (0..32).map(|i| format!("{c}{:07}", i)).collect() };
    let order = [
        "most_wanted",
        "new_dxcc",
        "new_dxcc_band",
        "new_dxcc_band_mode",
        "new_call",
        "new_call_band",
        "new_grid",
        "new_grid_band",
        "new_cq_zone",
        "new_itu_zone",
        "new_continent",
        "new_prefix",
        "snr_bucket",
        "snr",
        "distance",
        "hears_us",
    ];
    let s0 = json!({"name":"Max","class":"strategy","bands":bands,
        "filters":{"new":["dxcc","call","grid","cq_zone","itu_zone","continent","prefix"],
            "new_per":"band_mode","new_means":"not_confirmed",
            "region":{"kind":"selected","continents":["AF","AN","AS","EU","NA","OC","SA"]},
            "min_snr_db":-50,"worked_since":{"kind":"from_to","from":"1930-01-01","to":"2099-12-31"},
            "treat_73_as_cq":false,
            "countries":{"include":include,"exclude":exclude},
            "states":{"include":US_STATES.to_vec(),"exclude":[]},
            "cq_targets":{"include":words('P'),"exclude":words('Q')}},
        "order":order,"contest":null,"callers_first":false,
        "leave":{"mode":"calls","calls":20,"calls_heard":40},
        "tx_move_every":{"heard":20,"not_heard":0,"no_reports":20},"busy_pause":false,
        "cq_when_idle":true,"retry_minutes":120});
    let full = configuration(json!([s0, contest_json("WW fast")]));
    let body = json!({"v":1,"profile_id":profile::new_uuid().unwrap(),
        "boot_id":profile::new_uuid().unwrap(),"expected_revision":0,"configuration":full});
    assert!(
        serde_json::to_vec(&body).unwrap().len() < BODY_MAX,
        "the maximum shape fits the 32768-byte body"
    );
    let ok = parse_config(&full, Some(&table())).expect("every key at its bounds");
    assert_eq!(ok.json(), full, "read back key for key");
    // The lower bounds of the other leave modes and the numbers.
    for (leave, retry) in [
        (json!({"mode":"calls","calls":1,"calls_heard":1}), 1),
        (json!({"mode":"until_logged","gone_minutes":1}), 1),
        (json!({"mode":"until_logged","gone_minutes":60}), 120),
        (json!({"mode":"contest","tx_changes":1}), 1),
        (json!({"mode":"contest","tx_changes":20}), 120),
    ] {
        let mut s = strategy_json("A");
        s["leave"] = leave.clone();
        s["retry_minutes"] = json!(retry);
        s["tx_move_every"] = json!({"heard":0,"not_heard":0,"no_reports":0});
        let c = configuration(json!([s]));
        assert_eq!(parse_config(&c, None).map(|c| c.json()), Ok(c), "{leave}");
    }
    // One refusal per field, each naming exactly its path; strategy 0 of class strategy,
    // strategy 1 of class contest.
    // 33 bands: the 32 above and 2190m again is caught by the length first.
    let thirty_three: Vec<&str> = bands.iter().copied().chain(["submm"]).collect();
    let refuse = |edit: &dyn Fn(&mut Value), field: &str| {
        let mut c = configuration(json!([strategy_json("A"), contest_json("WW fast")]));
        edit(&mut c);
        assert_eq!(
            parse_config(&c, Some(&table())),
            Err(field.to_owned()),
            "{field}"
        );
    };
    let f0 = |k: &str| format!("strategies[0].{k}");
    let set0 = |path: &[&str], v: Value| {
        let path: Vec<String> = path.iter().map(|s| (*s).to_owned()).collect();
        move |c: &mut Value| {
            let mut node = &mut c["strategies"][0];
            for k in &path {
                node = &mut node[k.as_str()];
            }
            *node = v.clone();
        }
    };
    refuse(&set0(&["bands"], json!(["11m"])), &f0("bands[0]"));
    refuse(&set0(&["bands"], json!(["20m", "20m"])), &f0("bands[1]"));
    refuse(&set0(&["bands"], json!(thirty_three)), &f0("bands"));
    refuse(&set0(&["filters", "new"], json!([])), &f0("filters.new"));
    refuse(
        &set0(&["filters", "new"], json!(["dxcc", "dxcc"])),
        &f0("filters.new[1]"),
    );
    refuse(
        &set0(&["filters", "new_per"], json!("slot")),
        &f0("filters.new_per"),
    );
    let country = |e: Value| json!({"include":[e],"exclude":[]});
    refuse(
        &set0(
            &["filters", "countries"],
            country(json!({"kind":"call","value":"VK9","bands":null})),
        ),
        &f0("filters.countries.include[0].kind"),
    );
    refuse(
        &set0(
            &["filters", "countries"],
            country(json!({"kind":"prefix","value":"VK-9","bands":null})),
        ),
        &f0("filters.countries.include[0].value"),
    );
    refuse(
        &set0(
            &["filters", "countries"],
            country(json!({"kind":"prefix","value":"VK9ABCDEFGHIJK","bands":null})),
        ),
        &f0("filters.countries.include[0].value"),
    );
    refuse(
        &set0(
            &["filters", "countries"],
            country(json!({"kind":"prefix","value":"VK9","bands":thirty_three})),
        ),
        &f0("filters.countries.include[0].bands"),
    );
    refuse(
        &set0(
            &["filters", "countries"],
            country(json!({"kind":"country","value":"Atlantis","bands":null})),
        ),
        &f0("filters.countries.include[0].value"),
    );
    let sixty_five: Vec<Value> = (0..65).map(entry).collect();
    refuse(
        &set0(
            &["filters", "countries"],
            json!({"include":sixty_five,"exclude":[]}),
        ),
        &f0("filters.countries.include"),
    );
    for state in ["XX", "PR"] {
        refuse(
            &set0(
                &["filters", "states"],
                json!({"include":[state],"exclude":[]}),
            ),
            &f0("filters.states.include[0]"),
        );
    }
    let fifty_two: Vec<&str> = US_STATES.iter().copied().chain(["CA"]).collect();
    refuse(
        &set0(
            &["filters", "states"],
            json!({"include":fifty_two,"exclude":[]}),
        ),
        &f0("filters.states.include"),
    );
    for word in ["POTASOTAX", "PO-TA"] {
        refuse(
            &set0(
                &["filters", "cq_targets"],
                json!({"include":[word],"exclude":[]}),
            ),
            &f0("filters.cq_targets.include[0]"),
        );
    }
    let thirty_three_words: Vec<String> = (0..33).map(|i| format!("W{i}")).collect();
    refuse(
        &set0(
            &["filters", "cq_targets"],
            json!({"include":thirty_three_words,"exclude":[]}),
        ),
        &f0("filters.cq_targets.include"),
    );
    refuse(&set0(&["order"], json!(["snr", "snr"])), &f0("order[1]"));
    let seventeen: Vec<&str> = order.iter().copied().chain(["snr"]).collect();
    refuse(&set0(&["order"], json!(seventeen)), &f0("order"));
    for (leave, field) in [
        (
            json!({"mode":"calls","calls":0,"calls_heard":4}),
            "leave.calls",
        ),
        (
            json!({"mode":"calls","calls":21,"calls_heard":40}),
            "leave.calls",
        ),
        (
            json!({"mode":"calls","calls":4,"calls_heard":3}),
            "leave.calls_heard",
        ),
        (
            json!({"mode":"calls","calls":4,"calls_heard":41}),
            "leave.calls_heard",
        ),
        (
            json!({"mode":"until_logged","gone_minutes":0}),
            "leave.gone_minutes",
        ),
        (
            json!({"mode":"until_logged","gone_minutes":61}),
            "leave.gone_minutes",
        ),
        (json!({"mode":"contest","tx_changes":0}), "leave.tx_changes"),
        (
            json!({"mode":"contest","tx_changes":21}),
            "leave.tx_changes",
        ),
        (json!({"mode":"never"}), "leave.mode"),
    ] {
        refuse(&set0(&["leave"], leave), &f0(field));
    }
    refuse(
        &set0(&["tx_move_every", "heard"], json!(-1)),
        &f0("tx_move_every.heard"),
    );
    refuse(
        &set0(&["tx_move_every", "heard"], json!(21)),
        &f0("tx_move_every.heard"),
    );
    refuse(
        &set0(&["tx_move_every"], json!({"heard":0,"not_heard":1})),
        &f0("tx_move_every"),
    );
    refuse(&set0(&["retry_minutes"], json!(0)), &f0("retry_minutes"));
    refuse(&set0(&["retry_minutes"], json!(121)), &f0("retry_minutes"));
    // The contest strategy (strategies[1]).
    let set1 = |path: &[&str], v: Value| {
        let path: Vec<String> = path.iter().map(|s| (*s).to_owned()).collect();
        move |c: &mut Value| {
            let mut node = &mut c["strategies"][1];
            for k in &path {
                node = &mut node[k.as_str()];
            }
            *node = v.clone();
        }
    };
    refuse(
        &set1(&["order"], json!(["most_wanted"])),
        "strategies[1].order",
    );
    refuse(
        &set1(&["filters", "new"], json!(["dxcc"])),
        "strategies[1].filters",
    );
    refuse(&set1(&["contest"], Value::Null), "strategies[1].contest");
    refuse(
        &set1(&["contest"], json!("unknown")),
        "strategies[1].contest",
    );
    // A class strategy naming a contest; the classes of schema 3 and none.
    refuse(&set0(&["contest"], json!("ww_digi")), &f0("contest"));
    for class in ["award", "casual"] {
        refuse(&set0(&["class"], json!(class)), &f0("class"));
    }
    for name in ["DXCC all", "casual"] {
        refuse(&set0(&["name"], json!(name)), &f0("name"));
    }
    // Each schema 3 key and builtin: refused like any extra key.
    for key in [
        "goals",
        "needed",
        "value",
        "window",
        "repetitions",
        "quiet_minutes",
        "cq_when_no_target",
        "builtin",
    ] {
        refuse(
            &|c: &mut Value| c["strategies"][0][key] = json!(1),
            "strategies[0]",
        );
    }
}

// Proves: TC-097-001
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_001_a_put_is_read_back_and_an_oversized_body_is_refused() {
    let f = station(true).await;
    let c = configuration(json!([strategy_json("Mine"), contest_json("WW fast")]));
    let r = put(&f, json!(0), c.clone()).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);
    assert_eq!(
        (r.json["revision"].clone(), r.json["configuration"].clone()),
        (json!(1), c)
    );
    let mut big = configuration(json!([strategy_json("Mine")]));
    big["strategies"][0]["name"] = json!("x".repeat(40_000));
    let r = put(&f, json!(1), big).await;
    assert_eq!(r.status.as_u16(), 413, "{}", r.json);
    let mut bad = configuration(json!([strategy_json("Mine")]));
    bad["strategies"][0]["filters"]["countries"]["include"] =
        json!([{"kind":"country","value":"Atlantis","bands":null}]);
    let r = put(&f, json!(1), bad).await;
    assert_eq!(
        (r.status.as_u16(), r.json["error"]["field"].clone()),
        (
            400,
            json!("strategies[0].filters.countries.include[0].value")
        ),
        "a country name the table does not hold"
    );
    let saved: Value =
        serde_json::from_slice(&std::fs::read(f.dir.join(FILE_NAME)).unwrap()).unwrap();
    assert_eq!(saved["revision"], 1, "nothing stored by a refusal");
    std::fs::remove_file(f.dir.join(FILE_NAME)).unwrap();
}

/// The schema 4 "Mine" of TC-097-002, written from the upgrade table by hand.
fn mine_v4() -> Value {
    json!({"name":"Mine","class":"strategy","bands":null,
        "filters":{"new":["dxcc","call"],"new_per":"band","new_means":"not_confirmed",
            "region":{"kind":"dx"},"min_snr_db":null,"worked_since":{"kind":"today"},
            "treat_73_as_cq":false,"countries":empty(),"states":empty(),"cq_targets":empty()},
        "order":["new_dxcc_band_mode","snr"],"contest":null,"callers_first":true,
        "leave":{"mode":"calls","calls":5,"calls_heard":10},
        "tx_move_every":{"heard":0,"not_heard":1,"no_reports":2},"busy_pause":true,
        "cq_when_idle":true,"retry_minutes":15})
}
fn schema_3(name: &str, goals: Value) -> Value {
    json!({"name":name,"class":"award","goals":goals,"needed":"not_worked",
        "region":{"kind":"all"},"min_snr_db":null,"value":["most_wanted"],"callers_first":true,
        "cq_when_no_target":false,"repetitions":4,"quiet_minutes":10,"treat_73_as_cq":true,
        "window":{"kind":"all"}})
}

// Proves: TC-097-002
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_002_a_schema_3_file_upgrades_key_by_key_and_renames_built_in_names() {
    let f = station(true).await;
    let write = |schema: u64, strategies: Value| {
        std::fs::write(
            f.dir.join(FILE_NAME),
            serde_json::to_vec(
                &json!({"schema_version":schema,"profile_id":f.id,"revision":7,
                "configuration":configuration(strategies)}),
            )
            .unwrap(),
        )
        .unwrap();
    };
    let mine = json!({"name":"Mine","class":"award","goals":["dxcc_band","new_call"],
        "needed":"not_confirmed","region":{"kind":"dx"},"min_snr_db":null,
        "value":["new_dxcc_slot","snr"],"callers_first":true,"cq_when_no_target":true,
        "repetitions":5,"quiet_minutes":15,"treat_73_as_cq":false,"window":{"kind":"today"}});
    write(
        3,
        json!([
            mine,
            schema_3("Grid", json!(["grid"])),
            schema_3("DXCC all", json!(["dxcc"])),
            schema_3("dxcc all copy", json!(["dxcc"])),
            schema_3("Casual", json!(["new_call_band"]))
        ]),
    );
    let g = f.browser("GET", "/strategy", None).await.json;
    assert_eq!(g["revision"], 7);
    let list = g["configuration"]["strategies"].clone();
    assert_eq!(list[0], mine_v4(), "Mine key by key");
    assert_eq!(
        (
            list[1]["filters"]["new"].clone(),
            list[1]["filters"]["new_per"].clone()
        ),
        (json!(["grid"]), json!("ever"))
    );
    assert_eq!(
        list.as_array()
            .unwrap()
            .iter()
            .map(|s| s["name"].clone())
            .collect::<Vec<_>>(),
        [
            "Mine",
            "Grid",
            "DXCC all copy 2",
            "dxcc all copy",
            "Casual copy"
        ]
        .map(|n| json!(n))
    );
    assert_eq!(
        g["configuration_note"],
        json!([{"from":"DXCC all","to":"DXCC all copy 2"},{"from":"Casual","to":"Casual copy"}])
    );
    // The next PUT writes schema 4 at revision 8 and the note is gone.
    let p = put(&f, json!(7), g["configuration"].clone()).await;
    assert_eq!(p.status, StatusCode::OK, "{}", p.json);
    assert_eq!(p.json["configuration_note"], json!([]));
    let saved: Value =
        serde_json::from_slice(&std::fs::read(f.dir.join(FILE_NAME)).unwrap()).unwrap();
    assert_eq!(
        (saved["schema_version"].clone(), saved["revision"].clone()),
        (json!(4), json!(8))
    );
    // A schema 3 strategy otherwise malformed: the file is malformed.
    let mut broken = schema_3("Bad", json!(["dxcc"]));
    broken["value"] = json!(["rarest"]);
    write(3, json!([broken]));
    let s = Owner::default().snapshot(&f.state);
    assert_eq!(
        (s["configuration"].clone(), s["configuration_error"].clone()),
        (Value::Null, json!("invalid_configuration"))
    );
    std::fs::remove_file(f.dir.join(FILE_NAME)).unwrap();
    // Property: each mapped goal is the (what, per) of its goal, so it gives the verdicts
    // TC-039-030 expects of the goal (tc_039_030_each_goal_in_both_needed_settings runs them).
    for (goal, what, per) in [
        ("dxcc", NewWhat::Dxcc, NewPer::Ever),
        ("dxcc_band", NewWhat::Dxcc, NewPer::Band),
        ("dxcc_slot", NewWhat::Dxcc, NewPer::BandMode),
        ("waz", NewWhat::CqZone, NewPer::Ever),
        ("wpx", NewWhat::Prefix, NewPer::Ever),
        ("grid", NewWhat::Grid, NewPer::Ever),
        ("new_call", NewWhat::Call, NewPer::Ever),
        ("new_call_band", NewWhat::Call, NewPer::Band),
    ] {
        let c = configuration(json!([v4(schema_3("G", json!([goal])))]));
        let parsed = parse_config(&c, None).unwrap();
        assert_eq!(
            (
                parsed.strategies[0].new.clone(),
                parsed.strategies[0].new_per
            ),
            (vec![what], per),
            "{goal}"
        );
    }
}

/// The operator's table on #97 (BuiltinStrategies), written here.
fn builtin_table() -> Vec<Value> {
    let base =
        |name: &str, new: &str, per: &str, means: &str, order: Value, leave: Value, cq: bool| {
            json!({"name":name,"class":"strategy","bands":null,
            "filters":{"new":[new],"new_per":per,"new_means":means,"region":{"kind":"all"},
                "min_snr_db":null,"worked_since":{"kind":"all"},"treat_73_as_cq":true,
                "countries":empty(),"states":empty(),"cq_targets":empty()},
            "order":order,"contest":null,"callers_first":true,"leave":leave,
            "tx_move_every":{"heard":0,"not_heard":1,"no_reports":2},"busy_pause":true,
            "cq_when_idle":cq,"retry_minutes":10})
        };
    let gone = json!({"mode":"until_logged","gone_minutes":10});
    let calls = json!({"mode":"calls","calls":4,"calls_heard":8});
    let mw = json!(["most_wanted", "snr"]);
    let casual = json!(["snr_bucket", "distance"]);
    let mut pota = base(
        "POTA/SOTA",
        "call",
        "band",
        "not_worked",
        casual.clone(),
        calls.clone(),
        false,
    );
    pota["filters"]["worked_since"] = json!({"kind":"today"});
    pota["filters"]["cq_targets"] = json!({"include":["POTA","SOTA"],"exclude":[]});
    vec![
        base(
            "DXCC all",
            "dxcc",
            "band_mode",
            "not_confirmed",
            mw.clone(),
            gone.clone(),
            false,
        ),
        base(
            "New DXCC on band",
            "dxcc",
            "band",
            "not_confirmed",
            mw.clone(),
            gone.clone(),
            false,
        ),
        base("New DXCC", "dxcc", "ever", "not_confirmed", mw, gone, false),
        base("Casual", "call", "band", "not_worked", casual, calls, true),
        pota,
    ]
}

// Proves: TC-097-003
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_003_the_five_built_ins_the_contest_built_ins_and_active() {
    let f = station(true).await;
    let g = f.browser("GET", "/strategy", None).await.json;
    let listed = g["builtin_strategies"].as_array().unwrap().clone();
    let mut expected = builtin_table();
    for p in crate::contest::all_profiles() {
        let mut c = contest_json(p.name);
        c["contest"] = json!(p.id);
        expected.push(c);
    }
    for e in &mut expected {
        e["builtin"] = json!(true);
    }
    assert_eq!(listed, expected, "five built-ins, then one per contest");
    assert_eq!(g["configuration"]["strategies"], json!([]));
    let with = |active: &str| {
        let mut c = configuration(json!([]));
        c["active"] = json!(active);
        c
    };
    let r = put(&f, json!(0), with("DXCC all")).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);
    for name in ["casual", "New calls"] {
        let r = put(&f, json!(1), with(name)).await;
        assert_eq!(
            (r.status.as_u16(), r.json["error"]["field"].clone()),
            (400, json!("active")),
            "{name}"
        );
    }
    let r = put(&f, json!(1), with("WW Digi")).await;
    assert_eq!(
        (r.status.as_u16(), r.json["error"]["field"].clone()),
        (400, json!("contest")),
        "a contest built-in only with its contest"
    );
    let mut ww = with("WW Digi");
    ww["contest"] =
        json!({"profile":"ww_digi","start":"2026-08-29T12:00Z","end":"2026-08-30T12:00Z"});
    let r = put(&f, json!(1), ww).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);
    // A station restart: active None and Auto off (DXCC all is first in the list, not selected).
    let s = Owner::default().snapshot(&f.state);
    assert_eq!(
        (s["configuration"]["active"].clone(), s["auto"].clone()),
        (Value::Null, json!(false))
    );
    std::fs::remove_file(f.dir.join(FILE_NAME)).unwrap();
}

/// HB9BLA (EU) on 20m FT8 with an empty log.
fn on(band: Option<&str>) -> Station {
    Station {
        band: band.map(str::to_owned),
        ..me()
    }
}

// Proves: TC-097-004
#[test]
fn tc_097_004_off_the_strategy_bands_nothing_is_ranked() {
    let s = Strategy {
        bands: Some(vec!["20m".into(), "40m".into()]),
        ..award(&[Goal::NewCall])
    };
    let records = rows(&[
        ("CQ K1ABC FN42", Some(-5.0)),
        ("HB9BLA W1AW FN31", Some(-3.0)),
    ]);
    assert_eq!(called(&s, &records, &on(Some("20m"))), ["W1AW", "K1ABC"]);
    for (band, why) in [
        (Some("15m"), "band not in the strategy"),
        (None, "band unknown"),
    ] {
        let v = evaluate(&s, &records, &on(band));
        assert!(
            v.iter().all(|v| v.rank.is_none() && v.why == why),
            "{band:?}"
        );
    }
    let all = Strategy {
        bands: None,
        ..s.clone()
    };
    assert_eq!(
        called(&all, &records, &on(Some("15m"))).len(),
        2,
        "null: every band"
    );
}

/// The hand log of TC-097-005 on 40m FT8: DL1ABC 40m FT8 (not confirmed), F1ABC 40m FT4
/// (confirmed), JA1XYZ 20m FT8 (confirmed).
fn new_log() -> Arc<Worked> {
    worked(&[
        ("DL1ABC", Some("40m"), Some("FT8"), Some("JO62"), false),
        ("F1ABC", Some("40m"), Some("FT4"), Some("JN18"), true),
        ("JA1XYZ", Some("20m"), Some("FT8"), Some("PM95"), true),
    ])
}
fn new_rows() -> Vec<Value> {
    rows(&[
        ("CQ DL2XYZ JO50", Some(-1.0)),
        ("CQ F5ABC JN05", Some(-2.0)),
        ("CQ JA2ABC PM85", Some(-3.0)),
        ("CQ DL1ABC JO62", Some(-4.0)),
        ("CQ F1ABC JN18", Some(-5.0)),
    ])
}
/// The new senders of one what, per and means, in row order.
fn new_of(what: NewWhat, per: NewPer, needed: Needed, st: &Station) -> Vec<String> {
    let s = Strategy {
        new: vec![what],
        new_per: per,
        needed,
        ..award(&[Goal::NewCall])
    };
    let got = called(&s, &new_rows(), st);
    ["DL2XYZ", "F5ABC", "JA2ABC", "DL1ABC", "F1ABC"]
        .into_iter()
        .filter(|c| got.iter().any(|g| g == c))
        .map(str::to_owned)
        .collect()
}

// Proves: TC-097-005
#[test]
fn tc_097_005_what_must_be_new_per_and_means_by_hand() {
    use Needed::*;
    use NewPer::*;
    use NewWhat::*;
    let st = Station {
        worked: Some(new_log()),
        ..me()
    };
    // Germany (DL), France (F) EU zone 14 ITU 27/28, Japan AS zone 25 ITU 45.
    for (what, per, needed, expected) in [
        (Dxcc, Ever, NotWorked, vec![]),
        (Dxcc, Band, NotWorked, vec!["JA2ABC"]),
        (Dxcc, BandMode, NotWorked, vec!["F5ABC", "JA2ABC", "F1ABC"]),
        (Dxcc, Ever, NotConfirmed, vec!["DL2XYZ", "DL1ABC"]),
        (Call, Ever, NotWorked, vec!["DL2XYZ", "F5ABC", "JA2ABC"]),
        (Call, Band, NotWorked, vec!["DL2XYZ", "F5ABC", "JA2ABC"]),
        (
            Call,
            BandMode,
            NotWorked,
            vec!["DL2XYZ", "F5ABC", "JA2ABC", "F1ABC"],
        ),
        (CqZone, Ever, NotWorked, vec![]),
        (CqZone, Band, NotWorked, vec!["JA2ABC"]),
        (Continent, Ever, NotWorked, vec![]),
        (Continent, Band, NotWorked, vec!["JA2ABC"]),
        (Continent, Ever, NotConfirmed, vec![]),
        (ItuZone, Band, NotWorked, vec!["JA2ABC"]),
        (Prefix, Ever, NotWorked, vec!["DL2XYZ", "F5ABC", "JA2ABC"]),
        (Grid, Ever, NotWorked, vec!["DL2XYZ", "F5ABC", "JA2ABC"]),
        (Grid, Band, NotWorked, vec!["DL2XYZ", "F5ABC", "JA2ABC"]),
    ] {
        assert_eq!(
            new_of(what, per, needed, &st),
            expected,
            "{what:?} {per:?} {needed:?}"
        );
    }
    // The reason names the new whats and the per.
    let s = Strategy {
        new: vec![Dxcc, Call],
        new_per: BandMode,
        ..award(&[Goal::NewCall])
    };
    let v = evaluate(&s, &new_rows(), &st);
    let f5 = v.iter().find(|v| v.facts.from == "F5ABC").unwrap();
    assert_eq!(f5.why, "new: dxcc, call on 40m FT8");
    // Either what counts: DL2XYZ is a new call although Germany is worked on 40m FT8.
    assert!(called(&s, &new_rows(), &st).contains(&"DL2XYZ".to_owned()));
    // The station band unknown: nothing new per band or band and mode.
    let unknown = Station {
        band: None,
        worked: Some(new_log()),
        ..me()
    };
    assert_eq!(
        new_of(Call, Band, NotWorked, &unknown),
        Vec::<String>::new()
    );
    assert_eq!(
        new_of(Dxcc, BandMode, NotWorked, &unknown),
        Vec::<String>::new()
    );
    // Treat 73 as CQ: an RR73 to another station counts as calling only when on.
    let rr73 = rows(&[("W1AW K2NEW RR73", Some(0.0))]);
    let on = Strategy {
        new: vec![Call],
        treat_73_as_cq: true,
        ..award(&[Goal::NewCall])
    };
    let off = Strategy {
        treat_73_as_cq: false,
        ..on.clone()
    };
    assert_eq!(called(&on, &rr73, &st), ["K2NEW"]);
    assert_eq!(evaluate(&off, &rr73, &st)[0].why, "not a CQ");
}

/// A dated worked set of a window (the station step's set of that window).
fn dated_state(
    log: &[(&str, &str, u32, Option<&str>, bool)],
    window: Option<(u32, u32)>,
) -> Arc<Worked> {
    let logged: Vec<Logged> = log
        .iter()
        .map(|(call, band, date, state, confirmed)| Logged {
            call: (*call).into(),
            grid: None,
            band: Some((*band).into()),
            mode: Some("FT8".into()),
            confirmed: *confirmed,
            date: Some(*date),
            state: state.map(Into::into),
        })
        .collect();
    Arc::new(Worked::from_log_window(
        &crate::dxcc::Table::default(),
        &logged,
        window,
    ))
}
fn country(kind: &str, value: &str, bands: Value) -> CountryEntry {
    CountryEntry {
        country: kind == "country",
        value: value.into(),
        bands: bands
            .as_array()
            .map(|b| b.iter().map(|x| x.as_str().unwrap().to_owned()).collect()),
    }
}

// Proves: TC-097-006
#[test]
fn tc_097_006_country_state_and_cq_target_lists() {
    let st = Station {
        band: Some("20m".into()),
        worked: Some(dated_state(
            &[
                ("W6ABC", "40m", 20_260_101, Some("CA"), true),
                ("W6ABC", "40m", 20_260_301, Some("NV"), false),
            ],
            None,
        )),
        ..me()
    };
    let records = rows(&[
        ("CQ POTA K1ABC FN42", Some(-1.0)), // 0
        ("CQ SOTA W7XYZ DN31", Some(-2.0)), // 1
        ("CQ DX JA1XYZ PM95", Some(-3.0)),  // 2
        ("CQ EU DL1XYZ JO62", Some(-4.0)),  // 3
        ("CQ W6ABC CM87", Some(-5.0)),      // 4
        ("CQ VE3ABC FN03", Some(-6.0)),     // 5
        ("CQ K9NOR EN52", Some(-7.0)),      // 6
        ("CQ VK9LA QF98", Some(-8.0)),      // 7
    ]);
    // New call per band: W6ABC (logged on 40m) is new on 20m.
    let with = |edit: &dyn Fn(&mut Strategy)| {
        let mut s = award(&[Goal::NewCallBand]);
        s.treat_73_as_cq = true;
        edit(&mut s);
        let mut got = called(&s, &records, &st);
        got.sort();
        got
    };
    let sorted = |l: &[&str]| {
        let mut v: Vec<String> = l.iter().map(|s| s.to_string()).collect();
        v.sort();
        v
    };
    // Prefix by the start of the call; country by the entity (cty.dat 4018-4021: Lord Howe
    // Island holds =VK9LA).
    assert_eq!(
        with(&|s| s.countries.include = vec![country("prefix", "VK9", Value::Null)]),
        sorted(&["VK9LA"])
    );
    assert_eq!(
        with(&|s| s.countries.include = vec![country("country", "lord howe island", Value::Null)]),
        sorted(&["VK9LA"])
    );
    // Per band: the DL entry counts only on 40m.
    assert_eq!(
        with(&|s| s.countries.include = vec![country("prefix", "DL", json!(["40m"]))]),
        sorted(&[])
    );
    let on40 = Station {
        band: Some("40m".into()),
        ..st.clone()
    };
    let mut dl = award(&[Goal::NewCall]);
    dl.countries.include = vec![country("prefix", "DL", json!(["40m"]))];
    assert_eq!(called(&dl, &records, &on40), ["DL1XYZ"]);
    // Exclude wins over include (W7XYZ's CQ SOTA is greyed for a strategy without SOTA).
    assert_eq!(
        with(&|s| s.countries.include = vec![country("prefix", "W", Value::Null)]),
        sorted(&["W6ABC"])
    );
    assert_eq!(
        with(&|s| {
            s.countries.include = vec![country("prefix", "W", Value::Null)];
            s.countries.exclude = vec![country("prefix", "W6", Value::Null)];
        }),
        sorted(&[])
    );
    assert!(
        !with(&|s| s.countries.exclude = vec![country("country", "United States", Value::Null)])
            .iter()
            .any(|c| ["K1ABC", "W6ABC", "W7XYZ", "K9NOR"].contains(&c.as_str())),
    );
    // States: W6ABC is CA (the confirmed record before the newer unconfirmed NV); K1RU sends MA
    // in its exchange; K9NOR (no record) and VE3ABC (not a US entity) are unknown.
    assert_eq!(
        with(&|s| s.states.include = vec!["CA".into()]),
        sorted(&["W6ABC"])
    );
    assert_eq!(with(&|s| s.states.include = vec!["NV".into()]), sorted(&[]));
    let excluded = with(&|s| s.states.exclude = vec!["CA".into()]);
    assert!(!excluded.contains(&"W6ABC".to_owned()));
    assert!(excluded.contains(&"K9NOR".to_owned()) && excluded.contains(&"VE3ABC".to_owned()));
    let mut ru = record("W9XYZ K1RU 579 MA", 1500.0, Some(0.0));
    ru["fields"]["type"] = json!("rtty");
    ru["fields"]["exchange"] = json!({"kind":"state","value":"MA"});
    ru["sequence"] = json!(8);
    let mut cq = record("CQ K1RU FN42", 1600.0, Some(0.0));
    cq["sequence"] = json!(9);
    let ma = Strategy {
        states: Lists {
            include: vec!["MA".into()],
            exclude: Vec::new(),
        },
        ..award(&[Goal::NewCall])
    };
    assert_eq!(
        called(&ma, &[ru, cq], &st),
        ["K1RU"],
        "MA from the exchange"
    );
    // CQ targets: include POTA ranks only CQ POTA, not grey although DirectedCqRule greys it.
    let pota = Strategy {
        cq_targets: Lists {
            include: vec!["POTA".into()],
            exclude: Vec::new(),
        },
        ..award(&[Goal::NewCallBand])
    };
    let v = evaluate(&pota, &records, &st);
    let k1 = v.iter().find(|v| v.facts.from == "K1ABC").unwrap();
    assert_eq!((k1.rank, k1.grey), (Some(0), false));
    assert_eq!(called(&pota, &records, &st), ["K1ABC"]);
    let w6 = v.iter().find(|v| v.facts.from == "W6ABC").unwrap();
    assert_eq!(w6.why, "CQ target");
    let plain = award(&[Goal::NewCall]);
    let grey = evaluate(&plain, &records, &st);
    assert!(grey.iter().find(|v| v.facts.from == "K1ABC").unwrap().grey);
    // Exclude DX fails CQ DX only.
    let no_dx = with(&|s| s.cq_targets.exclude = vec!["DX".into()]);
    assert!(!no_dx.contains(&"JA1XYZ".to_owned()) && no_dx.contains(&"W6ABC".to_owned()));
    // POTA/SOTA: K1ABC worked on 20m yesterday is new today; W7XYZ worked today is not.
    let today = utc_date();
    let builtin = builtins().iter().find(|b| b.name == "POTA/SOTA").unwrap();
    let st_today = Station {
        band: Some("20m".into()),
        worked: Some(dated_state(
            &[
                ("K1ABC", "20m", today - 1, None, false),
                ("W7XYZ", "20m", today, None, false),
            ],
            Some((today, today)),
        )),
        ..me()
    };
    let v = evaluate(builtin, &records, &st_today);
    assert_eq!(called(builtin, &records, &st_today), ["K1ABC"]);
    let w7 = v.iter().find(|v| v.facts.from == "W7XYZ").unwrap();
    assert_eq!(w7.why, "not new");
}

// Proves: TC-097-006
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_006_the_pota_sota_run_selects_and_arms_cq_pota() {
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    select(&f, config(Some("POTA/SOTA"))).await;
    publish(
        &f,
        e,
        &[
            ("CQ JA JA1XYZ PM95", 1200.0, Some(5.0)),
            ("CQ POTA K1ABC FN42", 1500.0, Some(-5.0)),
        ],
    );
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed")),
        "the run's own select_row of CQ POTA passes; CQ JA stays refused"
    );
}

// Proves: TC-097-007
#[test]
fn tc_097_007_callers_of_my_call_pass_the_filters() {
    let st = Station {
        band: Some("20m".into()),
        worked: Some(worked(&[(
            "W1AW",
            Some("20m"),
            Some("FT8"),
            Some("FN31"),
            false,
        )])),
        ..me()
    };
    let casual = builtins()
        .iter()
        .find(|b| b.name == "Casual")
        .unwrap()
        .clone();
    let records = rows(&[
        ("HB9BLA W1AW FN31", Some(5.0)),   // 0 worked on 20m
        ("HB9BLA N1NEW FN31", Some(-9.0)), // 1 new
        ("CQ K1ABC FN42", Some(-1.0)),     // 2 new
    ]);
    let v = evaluate(&casual, &records, &st);
    let w1 = v.iter().find(|v| v.facts.from == "W1AW").unwrap();
    assert_eq!(
        (w1.rank, w1.why.as_str()),
        (None, "calls my call · not new")
    );
    assert_eq!(
        called(&casual, &records, &st),
        ["N1NEW", "K1ABC"],
        "callers first"
    );
    let off = Strategy {
        callers_first: false,
        order: vec![Criterion::Snr],
        ..casual.clone()
    };
    assert_eq!(
        called(&off, &records, &st),
        ["K1ABC", "N1NEW"],
        "ranked by SNR"
    );
    // A caller failing region dx, min SNR, a country exclude, a state include names its line.
    for (edit, why) in [
        (
            Box::new(|s: &mut Strategy| s.region = Region::Dx) as Box<dyn Fn(&mut Strategy)>,
            "calls my call · region",
        ),
        (
            Box::new(|s: &mut Strategy| s.min_snr_db = Some(-5)),
            "calls my call · below min SNR",
        ),
        (
            Box::new(|s: &mut Strategy| {
                s.countries.exclude = vec![country("prefix", "N1", Value::Null)]
            }),
            "calls my call · country list",
        ),
        (
            Box::new(|s: &mut Strategy| s.states.include = vec!["CA".into()]),
            "calls my call · state list",
        ),
    ] {
        let mut s = casual.clone();
        edit(&mut s);
        let st_na = Station {
            my_continent: Some("NA".into()),
            ..st.clone()
        };
        let v = evaluate(&s, &records, &st_na);
        let n1 = v.iter().find(|v| v.facts.from == "N1NEW").unwrap();
        assert_eq!((n1.rank, n1.why.as_str()), (None, why));
    }
}

// Proves: TC-097-008
#[test]
fn tc_097_008_snr_bucket_hears_us_and_the_new_criteria() {
    let st = me();
    let records = rows(&[
        ("CQ K1AAA FN42", Some(-11.0)), // last bucket
        ("CQ K1BBB FN42", Some(0.0)),   // middle
        ("CQ K1CCC FN42", None),        // unknown
        ("CQ K1DDD FN42", Some(1.0)),   // first
        ("CQ K1EEE FN42", Some(-10.0)), // middle
    ]);
    let s = |order: Vec<Criterion>| Strategy {
        order,
        ..award(&[Goal::NewCall])
    };
    assert_eq!(
        called(&s(vec![Criterion::SnrBucket]), &records, &st),
        ["K1DDD", "K1BBB", "K1EEE", "K1AAA", "K1CCC"],
        "+1, then 0 and -10 (SNR inside), -11, unknown"
    );
    // Hears us first: with PskrUse on (a heard set) JA1XYZ and VK2ABC first; off it ties.
    let r2 = rows(&[
        ("CQ DL1XYZ JO62", Some(5.0)),
        ("CQ JA1XYZ PM95", Some(-15.0)),
        ("CQ VK2ABC QF56", Some(-20.0)),
    ]);
    let heard = Station {
        hears: Some(vec!["JA1XYZ".into(), "VK2ABC".into()]),
        ..me()
    };
    assert_eq!(
        called(&s(vec![Criterion::HearsUs]), &r2, &heard),
        ["JA1XYZ", "VK2ABC", "DL1XYZ"]
    );
    assert_eq!(
        called(&s(vec![Criterion::HearsUs]), &r2, &me()),
        ["DL1XYZ", "JA1XYZ", "VK2ABC"]
    );
    // New continent: AS and OC new (EU worked), SNR inside.
    let eu = Station {
        worked: Some(worked(&[("DL2AAA", Some("40m"), Some("FT8"), None, false)])),
        ..me()
    };
    assert_eq!(
        called(&s(vec![Criterion::NewContinent]), &r2, &eu),
        ["JA1XYZ", "VK2ABC", "DL1XYZ"]
    );
    // Decode order never changes an order.
    let mut reversed = records.clone();
    reversed.reverse();
    for (i, r) in reversed.iter_mut().enumerate() {
        r["sequence"] = json!(i);
    }
    assert_eq!(
        called(&s(vec![Criterion::SnrBucket]), &reversed, &st),
        ["K1DDD", "K1BBB", "K1EEE", "K1AAA", "K1CCC"]
    );
}

// Proves: TC-097-010
#[test]
fn tc_097_010_auto_slot_from_500_hz_upper_edge_ties_and_the_move_rule() {
    use crate::freeslot::{moved, quietest_clear};
    use wstx_rust::decoder::Mode;
    // Free (0 dB) only at the listed slots, 10 dB everywhere else.
    let free =
        |list: &'static [u32]| move |f: u32| Some(if list.contains(&f) { 0.0 } else { 10.0 });
    let slot = |current: u32, list: &'static [u32]| {
        quietest_clear(Mode::Ft8, current, &[], &[], None, &free(list)).hz
    };
    assert_eq!(slot(1500, &[400, 480, 520]), 520, "never below 500 Hz");
    assert_eq!(
        slot(2000, &[1700, 2420]),
        1700,
        "the upper edge loses the tie"
    );
    let quieter = |f: u32| {
        Some(match f {
            2420 => 0.0,
            1700 => 1.0,
            _ => 10.0,
        })
    };
    assert_eq!(
        quietest_clear(Mode::Ft8, 2000, &[], &[], None, &quieter).hz,
        2420,
        "the upper edge wins when strictly quieter"
    );
    assert_eq!(
        slot(2400, &[2350, 2360]),
        2350,
        "2350 (to 2400 Hz) before the nearer 2360 (to 2410 Hz)"
    );
    // A move never keeps the current slot (nor overlaps it).
    let m = moved(Mode::Ft8, 1500, &[], &[], None, &free(&[1500, 1540, 1600])).unwrap();
    assert_eq!(m.hz, 1600, "1500 and 1540 overlap the current Tx");
    // Never within 50 Hz of his frequency of my Tx parity: no fallback.
    // The only free slot 1600 lies within 50 Hz of his 1610: the next quietest, nearest the
    // current Tx without overlapping it, the lower on a tie (1450 before 1550).
    assert_eq!(
        moved(Mode::Ft8, 1500, &[], &[], Some(&[1610]), &free(&[1600])).map(|m| m.hz),
        Some(1450)
    );
    let only_near_him: Vec<u32> = (500..=2650).step_by(10).collect();
    let all_near = |_f: u32| Some(0.0);
    let his: Vec<u32> = only_near_him.clone();
    assert_eq!(
        moved(Mode::Ft8, 1500, &[], &[], Some(&his), &all_near),
        None,
        "every candidate near his frequencies: Tx stays"
    );
    // A held Tx at 400 is no candidate: a move goes into 500..2650.
    let m = moved(Mode::Ft8, 400, &[], &[], None, &free(&[])).unwrap();
    assert!((500..=2650).contains(&m.hz), "{}", m.hz);
}

// Proves: TC-097-017
#[test]
fn tc_097_017_the_split_clearance_table() {
    use crate::freeslot::split_clear;
    use wstx_rust::decoder::Mode;
    for (d, clear) in [
        (0, false),
        (50, false),
        (51, false),
        (99, false),
        (100, true),
    ] {
        assert_eq!(split_clear(Mode::Ft8, 1500 + d, 1500), clear, "FT8 {d}");
    }
    for (d, clear) in [(139, false), (140, true)] {
        assert_eq!(split_clear(Mode::Ft4, 1500 + d, 1500), clear, "FT4 {d}");
    }
}

const KE1J_CQ: (&str, f64, Option<f64>) = ("CQ KE1J FN42", 1800.0, Some(-10.0));
const KE1J_BUSY: (&str, f64, Option<f64>) = ("W9XYZ KE1J -07", 1200.0, Some(-7.0));
/// TC-097-011 setup: an attended run of "Test calls" with leave {calls 4, calls_heard 8},
/// busy_pause `on`, Hold Tx on, Tx watchdog 3 set by the browser, calling KE1J (CQ at 1800 Hz)
/// from Tx 1500.
async fn calling_busy_ke1j(on: bool) -> Leaving {
    let t = leaving(|c| c["strategies"][0]["busy_pause"] = json!(on), &[KE1J_CQ]).await;
    browser_watchdog(&t.f, 3).await;
    assert_eq!(
        contact(&t.f).await,
        (json!("KE1J"), json!("replying"), json!("armed"))
    );
    assert_eq!(frequencies(&t.f).await.1, json!(1500));
    t
}
fn leave_of(remaining: u64, busy: bool, paused: u64) -> Value {
    json!({"mode":"calls","remaining":remaining,"busy":busy,"paused":paused,"staying":false})
}

// Proves: TC-097-011 (a), (c), (e) (CL-097-06, hand-worked from WstxStrategy::BusyPause). KE1J's
// report to W9XYZ for two of his periods: leave.busy true, paused 1 and 2, remaining stays 4; his
// RR73 ends it and the next call counts (remaining 3), his CQ the next (2). (c) three publications
// without his decode after the report stay paused (busy holds). (e) his report to my call resets
// every count. Red on the parent: the busy calls count (remaining 3, 2).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_011_a_busy_target_pauses_the_runs_count() {
    let t = calling_busy_ke1j(true).await;
    let (f, e) = (&t.f, t.e);
    publish(f, rep(e, 1), &[KE1J_BUSY]);
    assert_eq!(run_of(f).await["leave"], leave_of(4, true, 1));
    publish(f, rep(e, 2), &[KE1J_BUSY]);
    assert_eq!(run_of(f).await["leave"], leave_of(4, true, 2));
    publish(f, rep(e, 3), &[("W9XYZ KE1J RR73", 1200.0, Some(-7.0))]);
    assert_eq!(run_of(f).await["leave"], leave_of(3, false, 2));
    publish(f, rep(e, 4), &[KE1J_CQ]);
    assert_eq!(run_of(f).await["leave"], leave_of(2, false, 2));
    assert_eq!(contact(f).await.2, json!("armed"));
    // (c) busy holds without his decode; (e) progress resets every count.
    let t = calling_busy_ke1j(true).await;
    let (f, e) = (&t.f, t.e);
    publish(f, rep(e, 1), &[KE1J_BUSY]);
    publish(f, rep(e, 2), &[]);
    publish(f, rep(e, 3), &[]);
    assert_eq!(run_of(f).await["leave"], leave_of(4, true, 3), "(c)");
    publish(f, rep(e, 4), &[("HB9BLA KE1J -10", 1800.0, Some(-10.0))]);
    let leave = run_of(f).await["leave"].clone();
    assert_eq!(
        (&leave["busy"], &leave["paused"], &leave["remaining"]),
        (&json!(false), &json!(0), &json!(4)),
        "(e) {leave}"
    );
}

// Proves: TC-097-011 (d), (b) (CL-097-06). (d) Tx watchdog 3: KE1J busy for 5 publications, 3
// paused calls, the 4th and 5th count (remaining 3, 2). (b) his R-report to W9XYZ at 1510 Hz moves
// Tx to 1410 (the nearest candidate 100 Hz from 1510, FT8), Rx stays 1800, Enable Tx stays on.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_011_d_at_most_n_paused_calls_and_the_split_move() {
    let t = calling_busy_ke1j(true).await;
    let (f, e) = (&t.f, t.e);
    let mut seen = Vec::new();
    for k in 1..=5 {
        publish(f, rep(e, k), &[KE1J_BUSY]);
        let leave = run_of(f).await["leave"].clone();
        seen.push((leave["paused"].clone(), leave["remaining"].clone()));
    }
    assert_eq!(
        seen,
        [
            (json!(1), json!(4)),
            (json!(2), json!(4)),
            (json!(3), json!(4)),
            (json!(3), json!(3)),
            (json!(3), json!(2))
        ]
    );
    let t = calling_busy_ke1j(true).await;
    let (f, e) = (&t.f, t.e);
    publish(f, rep(e, 1), &[("W9XYZ KE1J R-09", 1510.0, Some(-7.0))]);
    let (rx, tx, _) = frequencies(f).await;
    assert_eq!((rx, tx), (json!(1800), json!(1410)), "(b)");
    assert_eq!(contact(f).await.2, json!("armed"));
}

// Proves: TC-097-011 (f) (CL-097-06, busy_pause off). The busy calls count and KE1J is left at the
// 4th; his R-report to W9XYZ at 1510 Hz disarms as partnerWorksOther does (within 50 Hz of Tx).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_011_f_busy_pause_off_counts_and_keeps_the_wsjtx_stop() {
    let t = calling_busy_ke1j(false).await;
    let (f, e) = (&t.f, t.e);
    for k in 1..=3 {
        publish(f, rep(e, k), &[KE1J_BUSY]);
        assert_eq!(run_of(f).await["leave"], leave_of(4 - k as u64, false, 0));
    }
    publish(f, rep(e, 4), &[KE1J_BUSY]);
    assert_eq!(
        run_of(f).await["left"],
        json!({"call":"KE1J","reason":"repetitions"})
    );
    let t = calling_busy_ke1j(false).await;
    let (f, e) = (&t.f, t.e);
    publish(f, rep(e, 1), &[("W9XYZ KE1J R-09", 1510.0, Some(-7.0))]);
    assert_eq!(contact(f).await.2, json!("disarmed"));
    assert_eq!(frequencies(f).await.1, json!(1500), "no split move");
}

// Proves: TC-097-011 (h) (CL-097-06, hand-worked from WstxContact::BusyPartner). KE1J's grid to
// W9XYZ starts busy (leave.busy true, paused 1, remaining stays 4); his 73 to W9XYZ ends it and
// that publication's call counts (busy false, remaining 3). Red on the parent: a grid to another
// call is no busy start (the call counts, remaining 3, busy false).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_011_h_a_grid_to_another_starts_busy_and_his_73_ends_it() {
    let t = calling_busy_ke1j(true).await;
    let (f, e) = (&t.f, t.e);
    publish(f, rep(e, 1), &[("W9XYZ KE1J FN42", 1200.0, Some(-7.0))]);
    assert_eq!(run_of(f).await["leave"], leave_of(4, true, 1), "the grid");
    publish(f, rep(e, 2), &[("W9XYZ KE1J 73", 1200.0, Some(-7.0))]);
    assert_eq!(run_of(f).await["leave"], leave_of(3, false, 1), "the 73");
    assert_eq!(contact(f).await.2, json!("armed"));
}

// Proves: TC-097-011 (i) (CL-097-06, hand-worked from WstxContact::BusyPartner and the #97
// coordinator default for a free text). KE1J's report to W9XYZ starts busy (paused 1); his report
// to K2ABC keeps it (busy_with K2ABC, paused 2, remaining stays 4) and Tx stays 1500 (no TxMoveRule
// move while busy, although tx_move_every no_reports 1 moves at every counted call); his free text
// "TNX QSO" in his period at 1205 Hz (within 10 Hz of his last decode at 1200) ends it and that
// publication's call counts (remaining 3). Red on the parent: the free text does not end busy
// (busy true, paused 3, remaining 4).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_011_i_busy_holds_across_a_further_station_and_ends_with_his_free_text() {
    let t = calling_busy_ke1j(true).await;
    let (f, e) = (&t.f, t.e);
    publish(f, rep(e, 1), &[KE1J_BUSY]);
    assert_eq!(run_of(f).await["leave"], leave_of(4, true, 1));
    assert_eq!(frequencies(f).await.1, json!(1500));
    publish(f, rep(e, 2), &[("K2ABC KE1J -05", 1200.0, Some(-7.0))]);
    assert_eq!(run_of(f).await["leave"], leave_of(4, true, 2), "K2ABC");
    assert_eq!(
        f.read("contact").await["watchdog"]["busy_with"],
        json!("K2ABC")
    );
    assert_eq!(frequencies(f).await.1, json!(1500), "no move while busy");
    publish(f, rep(e, 3), &[("TNX QSO", 1205.0, Some(-7.0))]);
    assert_eq!(run_of(f).await["leave"], leave_of(3, false, 2), "free text");
    assert_eq!(contact(f).await.2, json!("armed"));
    assert_ne!(
        frequencies(f).await.1,
        json!(1500),
        "the counted call moves"
    );
}
