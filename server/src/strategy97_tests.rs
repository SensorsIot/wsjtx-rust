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

// Proves: TC-097-004 (CL-097-02, the run steps). "Test calls" with bands ["20m", "40m"], Auto on:
// on 15m with CQ K1ABC published the run waits with reason band and arms nothing; after the retune
// to 20m it selects K1ABC from the next publication; the retune to 17m in that contact disarms and
// cancels it at the next step with no retry entry, and the run waits band.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_004_the_run_waits_off_the_strategy_bands() {
    let f = station(true).await;
    f.state.recording.fixture_band("15m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    let mut c = config(Some("Test calls"));
    c["strategies"][0]["bands"] = json!(["20m", "40m"]);
    select(&f, c).await;
    publish(&f, e, &[K1ABC_CQ]);
    assert_eq!(
        (
            run_of(&f).await["state"].clone(),
            run_of(&f).await["reason"].clone()
        ),
        (json!("waiting"), json!("band"))
    );
    assert_eq!(contact(&f).await.2, json!("disarmed"), "nothing armed");
    f.state.recording.fixture_band("20m");
    f.tick();
    publish(&f, rep(e, 1), &[K1ABC_CQ]);
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
    f.state.recording.fixture_band("17m");
    f.tick();
    f.tick();
    assert_eq!(
        contact(&f).await,
        (Value::Null, json!("cancelled"), json!("disarmed"))
    );
    let run = run_of(&f).await;
    assert_eq!(
        (&run["state"], &run["reason"], &run["quiet"]),
        (&json!("waiting"), &json!("band"), &json!([])),
        "no retry entry"
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

// Proves: TC-097-006 (CL-097-02, CqTargetList and DirectedCqRule: the include list admits only the
// run's own select_row). With POTA/SOTA active (Auto off) the operator's double-click of CQ POTA
// K1ABC still gets the directive warning (409 directive_not_answerable) and an MCP select_row of it
// is refused directive_not_answerable; a run of "Test calls" (no POTA on its include list) never
// selects CQ POTA K1ABC.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_006_only_the_runs_own_select_row_passes_the_directive() {
    let pota = ("CQ POTA K1ABC FN42", 1500.0, Some(-5.0));
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    save(&f, config(Some("POTA/SOTA"))).await;
    publish(&f, e, &[pota]);
    let row = live_row(&f, "CQ POTA K1ABC FN42");
    let w = f
        .browser(
            "POST",
            "/contact/command",
            Some(browser_command(&f, "select_row", json!({"row":row,"replace":false})).await),
        )
        .await;
    assert_eq!(
        (w.status, w.json["error"]["code"].clone()),
        (StatusCode::CONFLICT, json!("directive_not_answerable")),
        "the operator's warning"
    );
    let m = mcp_contact(&f, "select_row", json!({"row":row,"replace":false})).await;
    assert_eq!(
        m["result"]["error"]["code"], "directive_not_answerable",
        "{m}"
    );
    assert_eq!(contact(&f).await.0, Value::Null);

    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    select(&f, config(Some("Test calls"))).await;
    publish(&f, e, &[pota]);
    publish(&f, rep(e, 1), &[pota]);
    assert_eq!(contact(&f).await.0, Value::Null, "never selected (grey)");
}

// Proves: TC-097-007 (CL-097-02, the run steps; oracle: the operator's decision 2 on #97). A
// duplicate of Casual (call per band, not worked, callers_first on, min SNR -10 dB): W1AW, worked
// on 20m, calling my call is never answered by the run; N1NEW calling my call is; in a QSO with
// K1ABC his answer -05 decoded at -15 dB (below the minimum) is progress (roger report due, not
// left); the operator's double-click of W1AW's call starts a manual QSO with W1AW.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_007_the_run_answers_only_callers_that_pass_the_filters() {
    let w1aw = ("HB9BLA W1AW FN31", 1200.0, Some(5.0));
    let setup = || async {
        let f = station(true).await;
        f.state.recording.fixture_band("20m");
        f.state.recording.fixture_live_job("ft8");
        let e = at_even(&f);
        let client = f.state.recording.clients.session();
        import_adi(&f, &logged_before("W1AW", "FN31", e));
        let mut c = config(None);
        let mut s = strategy_json("Casual dup");
        s["filters"]["new_per"] = json!("band");
        s["filters"]["min_snr_db"] = json!(-10);
        c["strategies"] = json!([s]);
        c["active"] = json!("Casual dup");
        select(&f, c).await;
        (f, e, client)
    };
    let (f, e, _client) = setup().await;
    publish(&f, e, &[w1aw]);
    assert_eq!(contact(&f).await.0, Value::Null, "W1AW not answered");
    publish(
        &f,
        rep(e, 1),
        &[w1aw, ("HB9BLA N1NEW FN31", 1300.0, Some(-8.0))],
    );
    assert_eq!(contact(&f).await.0, json!("N1NEW"));

    let (f, e, _client) = setup().await;
    publish(&f, e, &[("CQ K1ABC FN42", 1800.0, Some(-5.0))]);
    assert_eq!(contact(&f).await.0, json!("K1ABC"));
    publish(&f, rep(e, 1), &[("HB9BLA K1ABC -05", 1800.0, Some(-15.0))]);
    assert_eq!(
        contact(&f).await,
        (json!("K1ABC"), json!("roger_report"), json!("armed")),
        "progress below the minimum SNR"
    );
    assert_eq!(run_of(&f).await["left"], Value::Null);

    let (f, e, _client) = setup().await;
    publish(&f, e, &[w1aw]);
    let row = live_row(&f, "HB9BLA W1AW FN31");
    let r = f
        .browser(
            "POST",
            "/contact/command",
            Some(browser_command(&f, "select_row", json!({"row":row,"replace":false})).await),
        )
        .await;
    assert_eq!(r.status, StatusCode::ACCEPTED, "{}", r.json);
    f.tick();
    assert_eq!(contact(&f).await.0, json!("W1AW"), "the manual QSO");
    assert_eq!(run_of(&f).await["state"], "manual");
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

/// TC-097-009: the leave mode of "Test calls" (the TC-039-043 setup).
fn until_logged(c: &mut Value) {
    c["strategies"][0]["leave"] = json!({"mode":"until_logged","gone_minutes":10});
}
fn contest_style(heard: u64, no_reports: u64) -> impl FnOnce(&mut Value) {
    move |c: &mut Value| {
        c["strategies"][0]["leave"] = json!({"mode":"contest","tx_changes":2});
        c["strategies"][0]["tx_move_every"] =
            json!({"heard":heard,"not_heard":2,"no_reports":no_reports});
    }
}
fn left_for(call: &str, reason: &str) -> Value {
    json!({"call":call,"reason":reason})
}
/// The Tx offset after each publication of `rows` at the partner periods `from..=to`, and whether
/// the contact is still armed then.
async fn calls(
    f: &Mcp,
    e: i64,
    from: i64,
    to: i64,
    rows: &[(&str, f64, Option<f64>)],
) -> Vec<(Value, bool)> {
    let mut seen = Vec::new();
    for k in from..=to {
        publish(f, rep(e, k), rows);
        seen.push((frequencies(f).await.1, contact(f).await.2 == json!("armed")));
    }
    seen
}

// Proves: TC-097-009 (a) (CL-097-04, hand-worked from WstxStrategy::LeaveRule calls). A spot of my
// call at K1ABC 598 s old: heard, so the leaving is at 8 (remaining 8 - k after the first 4 calls);
// 3 s later the spot is older than 600 s and the 5th call leaves at 4 {K1ABC, repetitions}.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_009_a_the_spot_ageing_past_600_s_brings_the_leaving_back_to_calls() {
    let t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    t.feed.inject(&heard_spot(598));
    for k in 1..=4 {
        publish(f, rep(e, k), &[]);
        assert_eq!(run_of(f).await["leave"]["remaining"], json!(8 - k), "{k}");
    }
    tokio::time::sleep(Duration::from_secs(3)).await;
    publish(f, rep(e, 5), &[]);
    assert_eq!(contact(f).await.2, json!("disarmed"));
    assert_eq!(run_of(f).await["left"], left_for("K1ABC", "repetitions"));
}

// Proves: TC-097-009 (b) (CL-097-04, LeaveRule until_logged, gone_minutes 10). K1ABC calling CQ
// every period for 30 minutes (60 publications) is never left. K1ABC last decoded at t0 (= e), then
// silent: the publication at t0 + 9 min 45 s (my parity) leaves nothing, the one at t0 + 10 min
// (his) leaves {K1ABC, gone}. His answer -05 at t0 + 30 s, then silent: not left at t0 + 10 min
// (9 min 30 s after it), left at t0 + 10 min 30 s.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_009_b_until_logged_leaves_only_when_gone_10_minutes() {
    let t = leaving(until_logged, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    for k in 1..=60 {
        publish(f, rep(e, k), &[K1ABC_CQ]);
    }
    assert_eq!(
        (contact(f).await.2, run_of(f).await["left"].clone()),
        (json!("armed"), Value::Null),
        "never left while decoded"
    );
    assert_eq!(run_of(f).await["leave"]["mode"], "until_logged");

    let t = leaving(until_logged, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    publish(f, rep(e, 1), &[]);
    publish(f, e + 585_000, &[]);
    assert_eq!(contact(f).await.2, json!("armed"), "t0 + 9 min 45 s");
    publish(f, e + 600_000, &[]);
    assert_eq!(contact(f).await.2, json!("disarmed"), "t0 + 10 min");
    assert_eq!(run_of(f).await["left"], left_for("K1ABC", "gone"));

    let t = leaving(until_logged, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    publish(f, rep(e, 1), &[("HB9BLA K1ABC -05", 1800.0, Some(-5.0))]);
    publish(f, rep(e, 20), &[]);
    assert_eq!(
        contact(f).await.2,
        json!("armed"),
        "9 min 30 s after his answer"
    );
    publish(f, rep(e, 21), &[]);
    assert_eq!(run_of(f).await["left"], left_for("K1ABC", "gone"));
}

// Proves: TC-097-009 (c) (CL-097-04, LeaveRule contest {tx_changes 2}, TxMoveRule). Silent with no
// spot (no_reports, k 2): Tx moves after the 2nd and the 4th call, left {tx_changes} at the 6th.
// Calling CQ with a spot and nothing more valuable: stays 20 periods. A more valuable station
// (+5 dB under order [snr]) from the 3rd period: heard 0 never moves, left at the 5th; heard 1
// moves at the 3rd and 4th, left at the 5th. no_reports 0: never moves, left at the 3rd.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_009_c_contest_style_change_points_and_the_stay() {
    let better = ("CQ N1NEW FN31", 1300.0, Some(5.0));
    let t = leaving(contest_style(0, 2), &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    let start = frequencies(f).await.1;
    let seen = calls(f, e, 1, 5, &[]).await;
    let txs: Vec<&Value> = seen.iter().map(|s| &s.0).collect();
    assert!(seen.iter().all(|s| s.1), "armed through the 5th");
    assert_eq!(txs[0], &start, "the 1st: no move");
    assert_ne!(txs[1], &start, "moved after the 2nd");
    assert_eq!(txs[2], txs[1], "the 3rd: no move");
    assert_ne!(txs[3], txs[2], "moved after the 4th");
    assert_eq!(txs[4], txs[3], "the 5th: no move");
    publish(f, rep(e, 6), &[]);
    assert_eq!(run_of(f).await["left"], left_for("K1ABC", "tx_changes"));

    let t = leaving(contest_style(0, 2), &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    t.feed.inject(&heard_spot(60));
    let start = frequencies(f).await.1;
    let seen = calls(f, e, 1, 20, &[K1ABC_CQ]).await;
    assert!(seen.iter().all(|s| s.1 && s.0 == start), "stays 20 periods");
    assert_eq!(run_of(f).await["leave"]["staying"], true);

    for (heard, moves) in [(0, false), (1, true)] {
        let t = leaving(contest_style(heard, 2), &[K1ABC_CQ]).await;
        let (f, e) = (&t.f, t.e);
        t.feed.inject(&heard_spot(60));
        let start = frequencies(f).await.1;
        calls(f, e, 1, 2, &[K1ABC_CQ]).await;
        let seen = calls(f, e, 3, 4, &[K1ABC_CQ, better]).await;
        assert!(seen.iter().all(|s| s.1), "heard {heard}");
        assert_eq!(seen[0].0 != start, moves, "heard {heard}: the 3rd");
        assert_eq!(seen[1].0 != seen[0].0, moves, "heard {heard}: the 4th");
        publish(f, rep(e, 5), &[K1ABC_CQ, better]);
        assert_eq!(
            run_of(f).await["left"],
            left_for("K1ABC", "tx_changes"),
            "heard {heard}: the 5th"
        );
    }

    let t = leaving(contest_style(0, 0), &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    let start = frequencies(f).await.1;
    let seen = calls(f, e, 1, 2, &[]).await;
    assert!(seen.iter().all(|s| s.1 && s.0 == start), "no_reports 0");
    publish(f, rep(e, 3), &[]);
    assert_eq!(run_of(f).await["left"], left_for("K1ABC", "tx_changes"));
}

// Proves: TC-097-009 (d), (e) (CL-097-04, LeaveRule and the retry pause). (d) His answer after the
// 3rd call brings the count back (remaining 4). (e) retry_minutes 10: after the leaving at the 4th,
// K1ABC's call to my call at 5 min is not answered, his CQ at 9 min 59 s not selected, at 10 min
// selected.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_009_d_e_an_answer_resets_and_the_retry_pause() {
    let t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    calls(f, e, 1, 3, &[]).await;
    assert_eq!(run_of(f).await["leave"]["remaining"], json!(1));
    publish(f, rep(e, 4), &[("HB9BLA K1ABC -05", 1800.0, Some(-5.0))]);
    assert_eq!(run_of(f).await["leave"]["remaining"], json!(4), "(d)");

    let t = leaving(|_| {}, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    calls(f, e, 1, 4, &[]).await;
    assert_eq!(run_of(f).await["left"], left_for("K1ABC", "repetitions"));
    at_skew(f, 300);
    publish(f, rep(e, 5), &[("HB9BLA K1ABC FN42", 1800.0, Some(-5.0))]);
    assert_eq!(contact(f).await.0, Value::Null, "not answered at 5 min");
    at_skew(f, 599);
    publish(f, rep(e, 6), &[K1ABC_CQ]);
    assert_eq!(
        contact(f).await.0,
        Value::Null,
        "not selected at 9 min 59 s"
    );
    at_skew(f, 600);
    publish(f, rep(e, 7), &[K1ABC_CQ]);
    assert_eq!(contact(f).await.0, json!("K1ABC"), "selected at 10 min");
}

// Proves: TC-097-009 (f) (CL-097-04: unattended no stay, the stop at N). No client for 60 s, Tx
// watchdog 6, K1ABC calling CQ every period with a spot of my call: until_logged and contest both
// key 6 calls and the Tx watchdog stops the 7th; the run stops no_client (calls: TC-039-033).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_009_f_unattended_until_logged_and_contest_end_at_the_stop_at_n() {
    for (name, edit) in [
        (
            "until_logged",
            Box::new(until_logged) as Box<dyn FnOnce(&mut Value)>,
        ),
        ("contest", Box::new(contest_style(0, 2))),
    ] {
        let mut t = leaving(edit, &[K1ABC_CQ]).await;
        let e = t.e;
        t.feed.inject(&heard_spot(60));
        drop(t.client.take());
        let f = &t.f;
        f.tick();
        at_skew(f, 60);
        assert_eq!(quiet_run(f).0, "contact_active", "{name}");
        transmit_own_period(f, e + 15_000).await;
        for k in 1..=5 {
            publish(f, rep(e, k), &[K1ABC_CQ]);
            transmit_own_period(f, rep(e, k) + 15_000).await;
        }
        publish(f, rep(e, 6), &[K1ABC_CQ]);
        not_keyed_in(f, rep(e, 6) + 15_000).await;
        assert_eq!(quiet_contact(f).await.2, json!("disarmed"), "{name}");
        f.tick();
        assert_eq!(
            quiet_run(f),
            ("stopped".into(), json!("no_client")),
            "{name}"
        );
    }
}

// Proves: TC-097-009 (g) (CL-097-04, the caller exception). In each mode a new caller of my call at
// the 2nd call: left {K1ABC, caller} and N1NEW selected from the same publication.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_009_g_a_caller_is_answered_at_once_in_each_mode() {
    for (name, edit) in [
        (
            "calls",
            Box::new(|_: &mut Value| {}) as Box<dyn FnOnce(&mut Value)>,
        ),
        ("until_logged", Box::new(until_logged)),
        ("contest", Box::new(contest_style(0, 2))),
    ] {
        let t = leaving(edit, &[K1ABC_CQ]).await;
        let (f, e) = (&t.f, t.e);
        publish(f, rep(e, 1), &[]);
        publish(f, rep(e, 2), &[("HB9BLA N1NEW FN31", 1200.0, Some(-8.0))]);
        assert_eq!(contact(f).await.0, json!("N1NEW"), "{name}");
        assert_eq!(
            run_of(f).await["left"],
            left_for("K1ABC", "caller"),
            "{name}"
        );
    }
}

/// A spot of DL1XYZ received by K1ABC `age_s` ago (K1ABC reports, not my call).
fn reports_spot(age_s: i64) -> String {
    spot_of(
        "DL1XYZ",
        "K1ABC",
        14_075_000,
        "20m",
        crate::contact_http_tests::now_ms() / 1000 - age_s,
    )
}
fn moves_of(tx_move_every: Value) -> impl FnOnce(&mut Value) {
    move |c: &mut Value| c["strategies"][0]["tx_move_every"] = tx_move_every
}
/// Whether Tx moved at each of the calls `from..=to` (the run's slot_check.moved).
async fn moved_at(
    f: &Mcp,
    e: i64,
    from: i64,
    to: i64,
    rows: &[(&str, f64, Option<f64>)],
) -> Vec<bool> {
    let mut seen = Vec::new();
    for k in from..=to {
        publish(f, rep(e, k), rows);
        seen.push(run_of(f).await["slot_check"]["moved"] == json!(true));
    }
    seen
}

// Proves: TC-097-010 (CL-097-05, the run steps, hand-worked from WstxStrategy::TxMoveRule and
// HearingFeed "He reports"). The PSK case of slot_check: K1ABC's report of another sender 120 s and
// 599 s old is not_heard; none (the only report 601 s old is outside the window) is no_reports;
// slot_check carries case, hears_us, moved and hz. k per case over 6 calls: {0, 0, 0} never moves;
// {2, 2, 2} not_heard moves at the 2nd, 4th and 6th. The case changing from no_reports (k 1) to heard
// (k 0) after the 1st call: moved at the 1st, never after. His answer after the 2nd call: no move
// after it. A busy-paused call between two calls (k 2, busy_pause on) is not counted toward k: the
// move comes at the 3rd call. Hold Tx on moves Tx alone (Rx stays 1800), off both.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_010_the_run_moves_tx_per_psk_case() {
    for (age, case) in [(120, "not_heard"), (599, "not_heard"), (601, "no_reports")] {
        let t = leaving(|_| {}, &[K1ABC_CQ]).await;
        let (f, e) = (&t.f, t.e);
        t.feed.inject(&reports_spot(age));
        publish(f, rep(e, 1), &[]);
        let s = run_of(f).await["slot_check"].clone();
        assert_eq!(
            (
                &s["case"],
                &s["hears_us"],
                s["moved"].is_boolean(),
                s["hz"].is_u64()
            ),
            (&json!(case), &json!(false), true, true),
            "a report {age} s old: {s}"
        );
    }
    let t = leaving(
        moves_of(json!({"heard":0,"not_heard":0,"no_reports":0})),
        &[K1ABC_CQ],
    )
    .await;
    assert_eq!(moved_at(&t.f, t.e, 1, 3, &[]).await, [false; 3], "k 0");
    let t = leaving(
        moves_of(json!({"heard":2,"not_heard":2,"no_reports":2})),
        &[K1ABC_CQ],
    )
    .await;
    t.feed.inject(&reports_spot(120));
    assert_eq!(
        moved_at(&t.f, t.e, 1, 3, &[]).await,
        [false, true, false],
        "k 2"
    );
    // The case change (no_reports k 1 to heard k 0).
    let t = leaving(
        moves_of(json!({"heard":0,"not_heard":1,"no_reports":1})),
        &[K1ABC_CQ],
    )
    .await;
    let (f, e) = (&t.f, t.e);
    assert_eq!(moved_at(f, e, 1, 1, &[]).await, [true], "no_reports");
    t.feed.inject(&heard_spot(60));
    assert_eq!(moved_at(f, e, 2, 3, &[]).await, [false, false], "heard");
    // No move after his answer.
    let t = leaving(
        moves_of(json!({"heard":1,"not_heard":1,"no_reports":1})),
        &[K1ABC_CQ],
    )
    .await;
    let (f, e) = (&t.f, t.e);
    moved_at(f, e, 1, 2, &[]).await;
    let before = frequencies(f).await.1;
    publish(f, rep(e, 3), &[("HB9BLA K1ABC -05", 1800.0, Some(-5.0))]);
    publish(f, rep(e, 4), &[]);
    assert_eq!(frequencies(f).await.1, before, "no move after the answer");
    // A busy-paused call is not counted toward k.
    let t = leaving(
        |c| {
            c["strategies"][0]["busy_pause"] = json!(true);
            c["strategies"][0]["tx_move_every"] = json!({"heard":2,"not_heard":2,"no_reports":2});
        },
        &[K1ABC_CQ],
    )
    .await;
    let (f, e) = (&t.f, t.e);
    assert_eq!(moved_at(f, e, 1, 1, &[]).await, [false]);
    publish(f, rep(e, 2), &[("W9XYZ K1ABC -07", 1200.0, Some(-7.0))]);
    assert_eq!(run_of(f).await["leave"]["paused"], json!(1));
    let before = frequencies(f).await.1;
    publish(f, rep(e, 3), &[("W9XYZ K1ABC RR73", 1200.0, Some(-7.0))]);
    assert_ne!(frequencies(f).await.1, before, "moved at the 3rd call");
    // Hold Tx on: Tx alone, Rx stays on K1ABC; off: both.
    for (hold, rx_follows) in [(true, false), (false, true)] {
        let t = leaving_from(
            hold,
            moves_of(json!({"heard":1,"not_heard":1,"no_reports":1})),
            &[K1ABC_CQ],
        )
        .await;
        let (f, e) = (&t.f, t.e);
        publish(f, rep(e, 1), &[]);
        let (rx, tx, _) = frequencies(f).await;
        assert_eq!(run_of(f).await["slot_check"]["moved"], true, "hold {hold}");
        assert_eq!(rx == tx, rx_follows, "hold {hold}: rx {rx} tx {tx}");
        if hold {
            assert_eq!(rx, json!(1800));
        }
    }
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

// Proves: TC-097-011 (g) (CL-097-06: "unattended there is no pause"; WstxContact::BusyPartner: the
// split move applies to every contact that pauses, also while it is not pausing). No client for
// 60 s, busy_pause on, Tx watchdog 3: KE1J's R-report to W9XYZ at 1510 Hz moves Tx to 1410 (Rx
// stays 1800, Enable Tx on); the calls while he is busy count (WD 1, 0 after the 2nd and 3rd
// keyed call, no busy_with shown) and the Tx watchdog stops the 4th at N; the run then stops
// no_client. The calls are keyed (transmit_own_period): a run step alone keys nothing, so the stop
// at N is only reached with real sends. No product change: the busy logic of ee0cb13ad already
// holds this (the 50 Hz stop of partnerWorksOther would disarm at once).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_011_g_unattended_the_busy_calls_count_and_tx_still_moves() {
    let mut t = calling_busy_ke1j(true).await;
    let e = t.e;
    drop(t.client.take());
    let f = &t.f;
    f.tick();
    at_skew(f, 60);
    assert_eq!(quiet_run(f).0, "contact_active");
    let busy = ("W9XYZ KE1J R-09", 1510.0, Some(-7.0));
    let watchdog = async || {
        let c = f.browser("GET", "/contact", None).await.json;
        (
            c["watchdog"]["tx_remaining_calls"].clone(),
            c["watchdog"]["busy_with"].clone(),
        )
    };
    transmit_own_period(f, e + 15_000).await;
    assert_eq!(watchdog().await, (json!(2), Value::Null), "the first call");
    publish(f, rep(e, 1), &[busy]);
    let c = f.browser("GET", "/contact", None).await.json;
    assert_eq!(
        (&c["settings"]["rx_hz"], &c["settings"]["tx_hz"]),
        (&json!(1800), &json!(1410)),
        "the split move"
    );
    assert_eq!(quiet_contact(f).await.2, json!("armed"));
    transmit_own_period(f, rep(e, 1) + 15_000).await;
    assert_eq!(watchdog().await, (json!(1), Value::Null), "counted, busy");
    publish(f, rep(e, 2), &[busy]);
    transmit_own_period(f, rep(e, 2) + 15_000).await;
    assert_eq!(watchdog().await, (json!(0), Value::Null), "counted, busy");
    publish(f, rep(e, 3), &[busy]);
    not_keyed_in(f, rep(e, 3) + 15_000).await;
    assert_eq!(quiet_contact(f).await.2, json!("disarmed"), "the stop at N");
    f.tick();
    assert_eq!(quiet_run(f), ("stopped".into(), json!("no_client")));
}

// Proves: TC-097-015 (CL-097-07, hand-worked from WstxContest D11, WstxStrategy::BuiltinStrategies
// and LeaveRule). WW Digi on 20m, the period in force, W1DUP a dupe in the log, Auto on. The
// built-in "WW Digi" (cq_when_idle on): no CQ after one empty publication, the CQ after the second;
// CQ JA1XYZ (new multiplier, farthest), CQ K1ABC and the dupe W1DUP calling my call: JA1XYZ
// selected (first by ContestValueOrder), the CQ ended, W1DUP never answered; a JA caller of my call
// (JA2ABC) answered at once. "WW Digi fast" (leave {contest, 1}, cq_when_idle false, countries
// exclude Japan, tx_move_every no_reports 2): six empty publications call no CQ; JA1XYZ and the JA
// caller have no rank, K1ABC is selected; silent without spots (no_reports, every 2nd call) Tx moves
// after the 2nd call and K1ABC is left {tx_changes} at the 4th. A selection with operation "run" is
// refused at contest.operation, a strategy of class strategy with the contest at contest.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_097_015_the_contest_built_in_and_a_saved_contest_strategy_run() {
    let dupe = ("HB9BLA W1DUP EM12", 900.0, Some(9.0));
    let ja_caller = ("HB9BLA JA2ABC PM85", 1300.0, Some(-12.0));
    let k1abc = ("CQ WW K1ABC FN42", 1800.0, Some(-10.0));
    let ja1xyz = ("CQ WW JA1XYZ PM95", 1100.0, Some(-15.0));
    // The built-in: the CQ only on the second empty publication.
    let t = contest_leaving("sp", |c| c["active"] = json!("WW Digi")).await;
    let (f, e) = (&t.f, t.e);
    publish(f, e - 120_000, &[]);
    assert_ne!(
        run_of(f).await["state"],
        "calling_cq",
        "one empty publication"
    );
    publish(f, e - 105_000, &[]);
    assert_eq!(run_of(f).await["state"], "calling_cq", "the second");
    assert_eq!(contact(f).await.1, json!("calling"));
    publish(f, e, &[k1abc, ja1xyz, dupe]);
    assert_eq!(
        contact(f).await,
        (json!("JA1XYZ"), json!("report"), json!("armed")),
        "JA1XYZ first, the CQ ended, never W1DUP"
    );
    assert_eq!(run_of(f).await["state"], "contact_active");
    publish(f, rep(e, 1), &[ja_caller, dupe]);
    assert_eq!(contact(f).await.0, json!("JA2ABC"), "the JA caller");
    assert_eq!(
        run_of(f).await["left"],
        json!({"call":"JA1XYZ","reason":"caller"})
    );
    // "WW Digi fast".
    let fast = |c: &mut Value| {
        contest_edit(c, |s| {
            s["name"] = json!("WW Digi fast");
            s["leave"] = json!({"mode":"contest","tx_changes":1});
            s["cq_when_idle"] = json!(false);
            s["filters"]["countries"]["exclude"] =
                json!([{"kind":"country","value":"Japan","bands":null}]);
        })
    };
    let t = contest_leaving("sp", fast).await;
    let (f, e) = (&t.f, t.e);
    for k in 0..6 {
        publish(f, e - 180_000 + 15_000 * k, &[]);
        assert_ne!(run_of(f).await["state"], "calling_cq", "no CQ, {k}");
    }
    assert_eq!(contact(f).await.0, Value::Null);
    publish(f, e, &[ja1xyz, ja_caller, k1abc]);
    assert_eq!(
        contact(f).await,
        (json!("K1ABC"), json!("report"), json!("armed")),
        "Japan excluded"
    );
    let tx = || async { frequencies(f).await.1 };
    let start = tx().await;
    publish(f, rep(e, 1), &[]);
    assert_eq!(tx().await, start, "no move at the 1st call");
    publish(f, rep(e, 2), &[]);
    let moved = tx().await;
    assert_ne!(moved, start, "moved after the 2nd call");
    publish(f, rep(e, 3), &[]);
    assert_eq!(
        (tx().await, contact(f).await.2),
        (moved, json!("armed")),
        "the 3rd"
    );
    publish(f, rep(e, 4), &[]);
    assert_eq!(contact(f).await.2, json!("disarmed"));
    assert_eq!(
        run_of(f).await["left"],
        json!({"call":"K1ABC","reason":"tx_changes"})
    );
    // The refusals.
    let g = f.browser("GET", "/strategy", None).await.json;
    let mut c = g["configuration"].clone();
    c["contest"]["operation"] = json!("run");
    let r = put(f, g["revision"].clone(), c).await;
    assert_eq!(
        (r.status.as_u16(), r.json["error"]["field"].clone()),
        (400, json!("contest.operation"))
    );
    let mut c = g["configuration"].clone();
    c["active"] = json!("Test calls");
    let r = put(f, g["revision"].clone(), c).await;
    assert_eq!(
        (r.status.as_u16(), r.json["error"]["field"].clone()),
        (400, json!("contest"))
    );
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
