#![forbid(unsafe_code)]
// Proves: CL-012-02, CL-012-03, CL-012-04; TC-020-003 (and TC-020-002 for the
// configuration barrier). Hand-authored candidate tables and contact scenarios; the
// expected selections, states and stop reasons are the WstxMcp::CandidateSelection and
// OperatingAutomation tables written below, not automation output. Integration cases use
// the actual station router, contact engine and #9 transmit owner on the recording
// hardware double (virtual UTC; no audio, PTT or radio) through the MCP test client.
use super::*;
use crate::automation::{Config, Ranking, candidates, parse_config};
use crate::contact_http_tests::{now_ms, period_text, record};
use crate::mcp_tests::{Mcp, station};
use std::sync::atomic::Ordering;
use wstx_rust::transmit::service::Hardware;

pub(crate) fn config_json() -> Value {
    json!({"modes":["ft8"],"ranking":"strongest_snr","min_snr_db":null,"allowed_calls":[],"blocked_calls":[],
        "max_contacts":2,"max_unanswered_periods":5,"completion_action":"next_candidate"})
}
fn rows(list: &[(u64, &str, f64, Option<f64>)]) -> Vec<Value> {
    list.iter()
        .map(|(sequence, text, hz, snr)| {
            let mut r = record(text, *hz, *snr);
            r["sequence"] = json!(sequence);
            r
        })
        .collect()
}
fn order(records: &[Value], config: &Config, worked: &[&str]) -> Vec<String> {
    let worked: Vec<String> = worked.iter().map(|w| w.to_string()).collect();
    candidates(records, config, "HB9BLA", &worked)
        .into_iter()
        .map(|c| c.call)
        .collect()
}

// Proves: TC-020-003.
#[test]
fn tc_020_003_candidate_selection_table() {
    let records = rows(&[
        (0, "CQ K1ABC FN42", 1500.0, Some(-12.0)),
        (1, "CQ W1AW FN31", 900.0, Some(-3.0)),
        (2, "CQ DL1XYZ JO62", 2100.0, None),
        (3, "HB9BLA K1ABC -05", 800.0, Some(5.0)),
        (4, "CQ HB9BLA JN47", 700.0, Some(9.0)),
        (5, "CQ W1AW FN31", 950.0, Some(-1.0)),
        (6, "CQ AA1AA FN42", 900.0, Some(-3.0)),
    ]);
    let base = parse_config(&config_json()).unwrap().unwrap();
    let with = |f: &dyn Fn(&mut Config)| {
        let mut c = base.clone();
        f(&mut c);
        c
    };
    // Not CQ (3), my own call (4) and a repeated call (5: W1AW keeps sequence 1) never compete.
    let first = with(&|c| c.ranking = Ranking::FirstSeen);
    assert_eq!(
        order(&records, &first, &[]),
        ["K1ABC", "W1AW", "DL1XYZ", "AA1AA"]
    );
    // Strongest: unknown SNR excluded; -3/-3 tie broken by call (AA1AA < W1AW).
    assert_eq!(order(&records, &base, &[]), ["AA1AA", "W1AW", "K1ABC"]);
    let low = with(&|c| c.ranking = Ranking::LowestFrequency);
    assert_eq!(
        order(&records, &low, &[]),
        ["AA1AA", "W1AW", "K1ABC", "DL1XYZ"]
    );
    let min = with(&|c| {
        c.ranking = Ranking::FirstSeen;
        c.min_snr_db = Some(-5)
    });
    assert_eq!(
        order(&records, &min, &[]),
        ["W1AW", "AA1AA"],
        "below -5 dB and unknown SNR excluded"
    );
    let at = with(&|c| {
        c.ranking = Ranking::FirstSeen;
        c.min_snr_db = Some(-3)
    });
    assert_eq!(
        order(&records, &at, &[]),
        ["W1AW", "AA1AA"],
        "exactly the minimum is eligible"
    );
    let allowed = with(&|c| {
        c.ranking = Ranking::FirstSeen;
        c.allowed = vec!["K1ABC".into(), "DL1XYZ".into()]
    });
    assert_eq!(order(&records, &allowed, &[]), ["K1ABC", "DL1XYZ"]);
    let blocked = with(&|c| {
        c.ranking = Ranking::FirstSeen;
        c.blocked = vec!["W1AW".into()]
    });
    assert_eq!(order(&records, &blocked, &[]), ["K1ABC", "DL1XYZ", "AA1AA"]);
    assert_eq!(
        order(&records, &first, &["K1ABC"]),
        ["W1AW", "DL1XYZ", "AA1AA"],
        "worked in this run"
    );
    assert!(
        order(
            &rows(&[(0, "HB9BLA W1AW -05", 1000.0, Some(1.0))]),
            &base,
            &[]
        )
        .is_empty()
    );
}

// Proves: TC-020-002, TC-020-003.
#[test]
fn tc_020_003_configuration_is_exact_and_has_no_default_policy() {
    assert_eq!(parse_config(&Value::Null), Ok(None), "null: unconfigured");
    let ok = parse_config(&config_json()).unwrap().unwrap();
    assert_eq!(
        (
            ok.ranking,
            ok.max_contacts,
            ok.max_unanswered,
            ok.next_candidate
        ),
        (Ranking::StrongestSnr, 2, 5, true)
    );
    assert_eq!(
        ok.max_run_minutes, 120,
        "only the run duration bound has a default (D7)"
    );
    let calls16: Vec<String> = (0..16).map(|i| format!("K{i}AAA")).collect();
    let mut edge = config_json();
    edge["allowed_calls"] = json!(calls16);
    edge["min_snr_db"] = json!(-50);
    edge["max_contacts"] = json!(100);
    edge["max_unanswered_periods"] = json!(20);
    edge["modes"] = json!(["ft4", "ft8"]);
    edge["max_run_minutes"] = json!(480);
    assert!(parse_config(&edge).is_ok(), "upper bounds admitted");
    let mut low = config_json();
    low["max_run_minutes"] = json!(1);
    assert_eq!(parse_config(&low).unwrap().unwrap().max_run_minutes, 1);
    let calls17: Vec<String> = (0..17).map(|i| format!("K{i}AAA")).collect();
    for (key, value, field) in [
        ("modes", json!([]), "modes"),
        ("modes", json!(["ft8", "ft8"]), "modes"),
        ("modes", json!(["jt65"]), "modes"),
        ("ranking", json!("random"), "ranking"),
        ("min_snr_db", json!(-51), "min_snr_db"),
        ("min_snr_db", json!(50), "min_snr_db"),
        ("min_snr_db", json!(1.5), "min_snr_db"),
        ("allowed_calls", json!(calls17), "allowed_calls"),
        ("allowed_calls", json!(["k1abc"]), "allowed_calls"),
        ("allowed_calls", json!(["K1"]), "allowed_calls"),
        ("blocked_calls", json!(["W1AW", "W1AW"]), "blocked_calls"),
        ("max_contacts", json!(0), "max_contacts"),
        ("max_contacts", json!(101), "max_contacts"),
        ("max_unanswered_periods", json!(0), "max_unanswered_periods"),
        (
            "max_unanswered_periods",
            json!(21),
            "max_unanswered_periods",
        ),
        ("completion_action", json!("loop"), "completion_action"),
        ("max_run_minutes", json!(0), "max_run_minutes"),
        ("max_run_minutes", json!(481), "max_run_minutes"),
        ("max_run_minutes", json!("120"), "max_run_minutes"),
    ] {
        let mut c = config_json();
        c[key] = value.clone();
        assert_eq!(
            parse_config(&c),
            Err(("invalid_request", Some(field))),
            "{key}={value}"
        );
    }
    let mut both = config_json();
    both["allowed_calls"] = json!(["W1AW"]);
    both["blocked_calls"] = json!(["W1AW"]);
    assert_eq!(
        parse_config(&both),
        Err(("invalid_request", Some("blocked_calls")))
    );
    let mut missing = config_json();
    missing.as_object_mut().unwrap().remove("completion_action");
    assert_eq!(
        parse_config(&missing),
        Err(("invalid_request", Some("configuration"))),
        "every key required"
    );
    let mut extra = config_json();
    extra["arm"] = json!(true);
    assert_eq!(
        parse_config(&extra),
        Err(("invalid_request", Some("configuration")))
    );
}

/// Bench UTC set to 1 s after an even FT8 period E (a partner period); own periods are odd.
pub(crate) fn at_even(f: &Mcp) -> i64 {
    let e = (now_ms().div_euclid(30_000) + 4) * 30_000;
    f.bench.offset.store(e + 1000 - now_ms(), Ordering::SeqCst);
    e
}
/// The next even period after the bench's current UTC, the bench set 1 s after it.
fn next_even(f: &Mcp) -> i64 {
    let e = (f.bench.now_utc_ms().div_euclid(30_000) + 1) * 30_000;
    f.bench
        .offset
        .fetch_add(e + 1000 - f.bench.now_utc_ms(), Ordering::SeqCst);
    e
}
pub(crate) fn publish(f: &Mcp, period: i64, list: &[(&str, f64, Option<f64>)]) {
    let records = list
        .iter()
        .map(|(t, hz, snr)| record(t, *hz, *snr))
        .collect();
    f.state
        .recording
        .fixture_publish_period(&period_text(period), records);
    f.tick();
}
pub(crate) async fn automation(f: &Mcp, action: &str, extra: Value) -> Value {
    // #39: an MCP run arms only within the Tx watchdog time of the operator's last
    // browser action; these MCP cases start with the operator present.
    if action == "start" {
        f.operator_present().await;
    }
    let mut b = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),"action":action});
    b.as_object_mut()
        .unwrap()
        .extend(extra.as_object().unwrap().clone());
    f.tool("wstx_automation_command", json!({"command":b}))
        .await
}
/// Configure, then start with the revisions and safety revision read through MCP.
pub(crate) async fn run(f: &Mcp, config: Value, mode: &str) -> (Value, Value) {
    let a = f.read("automation").await;
    let c = automation(
        f,
        "configure",
        json!({"expected_policy_revision":a["policy_revision"],"configuration":config}),
    )
    .await;
    assert_eq!(c["status"], 202, "{c}");
    let a = f.read("automation").await;
    let safety = f.read("contact").await["transmit"]["safety_revision"].clone();
    let start = json!({"expected_policy_revision":a["policy_revision"],"expected_run_revision":a["run_revision"],"mode":mode,"safety_revision":safety});
    let s = automation(f, "start", start.clone()).await;
    assert_eq!(s["status"], 202, "{s}");
    (s, start)
}
/// The operator cancels the contact a stopped run left prepared (a new run needs none).
async fn cancel(f: &Mcp) {
    let revision = f.read("contact").await["contact_revision"]
        .as_u64()
        .unwrap();
    let v = f
        .tool(
            "wstx_contact_command",
            json!({"command":f.command(revision, "cancel", json!({}))}),
        )
        .await;
    assert_eq!(v["status"], 202, "{v}");
}
pub(crate) async fn run_state(f: &Mcp) -> (String, Value) {
    let r = f.read("automation").await["run"].clone();
    (
        r["state"].as_str().unwrap_or("").to_owned(),
        r["reason"].clone(),
    )
}
/// One own (odd) transmission of the pending request in period `own`, run to completion.
pub(crate) async fn not_keyed_in(f: &Mcp, own: i64) {
    let service = &f.state.recording.transmit.get().unwrap().service;
    // A request still pending at the limit is stopped at once, at this instant (#87: a tick
    // after the jump would race the transmit service's late start); a run's change it
    // reads at a tick (such as its attendance) applies from the next one.
    f.tick();
    // Without a pending request the Tx watchdog stops 1.2 s into the due period.
    f.bench
        .offset
        .fetch_add(own + 1_300 - f.bench.now_utc_ms(), Ordering::SeqCst);
    let deadline = Instant::now() + Duration::from_secs(5);
    while service.view().arm_state == wstx_rust::transmit::service::ArmState::Armed {
        assert!(Instant::now() < deadline, "{:?}", service.view());
        f.tick();
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    assert!(!service.view().transmitting);
    f.tick();
}
/// The own period a pending request is bound to, by the contact engine's submission rule
/// (contact.rs `submit`): the next period of the contact's parity at or after
/// max(now + LEAD_MS, the last started period + one period). None without a pending request.
fn bound_period(f: &Mcp) -> Option<i64> {
    let view = f.state.recording.transmit.get().unwrap().service.view();
    view.pending_sequence?;
    let mode = crate::contact_http::mode_of(f.state.recording.operating_mode());
    let parity = f.state.recording.contact.get()?.status_facts().parity;
    let lead = f.bench.now_utc_ms() + crate::contact::LEAD_MS;
    let floor = view
        .last_period_utc_ms
        .map_or(lead, |p| lead.max(p + crate::contact::period_ms(mode)));
    Some(wstx_rust::transmit::next_period(mode, floor, parity))
}
/// Fails at once when a pending request is bound to another period than `own`: a clock
/// moved past that period would race the transmit service's StalePeriod refusal (#87).
pub(crate) fn assert_bound(f: &Mcp, own: i64) {
    if let Some(bound) = bound_period(f) {
        assert_eq!(
            own, bound,
            "own period {own}: the pending request is bound to period {bound}"
        );
    }
}
/// Moves the bench UTC forward to `to` (never back: the clock may already be past it).
fn advance_to(f: &Mcp, to: i64) {
    f.bench
        .offset
        .fetch_add((to - f.bench.now_utc_ms()).max(0), Ordering::SeqCst);
}
/// One own transmission of the pending request in period `own`, run to completion. The
/// bench clock moves only to the request's own period, so the transmit service never
/// meets a period the clock has passed (#87): `own` must be the period the pending
/// request is bound to. Each step waits on the transmit owner's event; the 5 s deadline
/// is a hang guard only.
pub(crate) async fn transmit_own_period(f: &Mcp, own: i64) {
    assert_bound(f, own);
    let service = &f.state.recording.transmit.get().unwrap().service;
    let mode = crate::contact_http::mode_of(f.state.recording.operating_mode());
    let audio_start = wstx_rust::transmit::plan_start(
        mode,
        own,
        wstx_rust::transmit::ClockState::Synchronized,
        own,
        48_000,
    )
    .unwrap()
    .audio_start_ms;
    let deadline = Instant::now() + Duration::from_secs(5);
    let wait = async |done: &dyn Fn(&wstx_rust::transmit::service::View) -> bool, tick: bool| {
        loop {
            let view = service.view();
            if done(&view) {
                break;
            }
            assert!(Instant::now() < deadline, "{view:?}");
            if tick {
                f.tick();
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    };
    f.bench
        .offset
        .fetch_add(own - 30 - f.bench.now_utc_ms(), Ordering::SeqCst);
    wait(
        &|v| v.ptt == wstx_rust::transmit::service::PttState::Keyed,
        true,
    )
    .await;
    advance_to(f, audio_start);
    wait(&|v| v.transmitting, true).await;
    // Past the end of the longest (FT8) waveform.
    advance_to(f, audio_start + 13_000);
    wait(
        &|v| !v.transmitting && v.ptt == wstx_rust::transmit::service::PttState::Released,
        false,
    )
    .await;
    f.tick();
}

// Proves: TC-020-003.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_020_003_automation_selects_progresses_completes_and_takes_the_next_candidate() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    // Before start nothing is selected or armed, whatever is decoded.
    publish(&f, e - 30_000, &[("CQ K1ABC FN42", 1500.0, Some(-12.0))]);
    assert_eq!(f.read("contact").await["contact"], Value::Null);
    let (receipt, _) = run(&f, config_json(), "ft8").await;
    assert_eq!(receipt["result"]["state"], "waiting");
    assert_eq!(
        f.read("contact").await["contact"],
        Value::Null,
        "a publication before start is never used"
    );
    // Strongest SNR: W1AW -3 over K1ABC -12 and DL1XYZ (unknown SNR).
    publish(
        &f,
        e,
        &[
            ("CQ K1ABC FN42", 1500.0, Some(-12.0)),
            ("CQ W1AW FN31", 900.0, Some(-3.0)),
            ("CQ DL1XYZ JO62", 2100.0, None),
        ],
    );
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["contact"]["dx_call"].clone(),
            c["contact"]["state"].clone()
        ),
        (json!("W1AW"), json!("replying")),
        "{c}"
    );
    assert_eq!(c["contact"]["messages"][0], "W1AW HB9BLA JN47");
    assert_eq!(
        (
            c["settings"]["parity"].clone(),
            c["settings"]["rx_hz"].clone()
        ),
        (json!("odd"), json!(900))
    );
    assert_eq!(c["transmit"]["arm_state"], "armed");
    let a = f.read("automation").await["run"].clone();
    assert_eq!(
        (a["state"].clone(), a["selected"]["call"].clone()),
        (json!("contact_active"), json!("W1AW"))
    );
    assert_eq!(a["last_decision"]["candidates"], 2);
    // The contact engine progresses the contact (WstxContact::AutoSequence), not automation.
    publish(&f, e + 30_000, &[("HB9BLA W1AW -05", 905.0, Some(-6.0))]);
    assert_eq!(f.read("contact").await["contact"]["state"], "roger_report");
    publish(&f, e + 60_000, &[("HB9BLA W1AW RR73", 905.0, Some(-6.0))]);
    assert_eq!(f.read("contact").await["contact"]["state"], "signoff");
    assert_eq!(
        f.read("contact").await["contact"]["messages"][4],
        "W1AW HB9BLA 73"
    );
    transmit_own_period(&f, e + 15_000).await;
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["contact"]["state"].clone(),
            c["transmit"]["arm_state"].clone()
        ),
        (json!("completed"), json!("disarmed")),
        "{c}"
    );
    assert_eq!(
        f.state
            .recording
            .transmit
            .get()
            .unwrap()
            .service
            .view()
            .last_text
            .as_deref(),
        Some("W1AW HB9BLA 73")
    );
    let a = f.read("automation").await["run"].clone();
    assert_eq!(
        (a["state"].clone(), a["completed_contacts"].clone()),
        (json!("waiting"), json!(1))
    );
    // Next candidate: W1AW is worked in this run; K1ABC is next even though weaker.
    let e2 = e + 90_000;
    publish(
        &f,
        e2,
        &[
            ("CQ W1AW FN31", 900.0, Some(-1.0)),
            ("CQ K1ABC FN42", 1500.0, Some(-12.0)),
        ],
    );
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["contact"]["dx_call"].clone(),
            c["transmit"]["arm_state"].clone()
        ),
        (json!("K1ABC"), json!("armed")),
        "{c}"
    );
    // Explicit stop: future dispatch ends and the run's contact is disarmed (no Halt).
    let run_id = f.read("automation").await["run"]["id"].clone();
    let halts = f
        .state
        .recording
        .transmit
        .get()
        .unwrap()
        .service
        .halt_requests();
    let s = automation(&f, "stop", json!({"run_id":run_id})).await;
    assert_eq!(
        (s["status"].clone(), s["result"]["state"].clone()),
        (json!(202), json!("stopped"))
    );
    assert_eq!(run_state(&f).await, ("stopped".into(), json!("stopped")));
    assert_eq!(f.read("contact").await["transmit"]["arm_state"], "disarmed");
    assert_eq!(
        f.state
            .recording
            .transmit
            .get()
            .unwrap()
            .service
            .halt_requests(),
        halts,
        "stop is not a halt"
    );
    publish(&f, e2 + 30_000, &[("CQ G4ABC IO91", 1000.0, Some(0.0))]);
    assert_eq!(
        f.read("contact").await["contact"]["dx_call"],
        "K1ABC",
        "no selection after stop"
    );
    let again = automation(&f, "stop", json!({"run_id":run_id})).await;
    assert_eq!(again["result"]["error"]["code"], "stale_request");
}

// Proves: TC-020-003.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_020_003_halt_retry_and_conflicts_never_replay_a_transmit_action() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let mut cfg = config_json();
    cfg["completion_action"] = json!("stop");
    let (receipt, start) = run(&f, cfg.clone(), "ft8").await;
    // A second run or a configuration change while running is a conflict.
    let a = f.read("automation").await;
    let second = automation(&f, "start", json!({"expected_policy_revision":a["policy_revision"],"expected_run_revision":a["run_revision"],"mode":"ft8","safety_revision":3})).await;
    assert_eq!(
        (
            second["status"].clone(),
            second["result"]["error"]["code"].clone()
        ),
        (json!(409), json!("state_conflict"))
    );
    let cfg_change = automation(
        &f,
        "configure",
        json!({"expected_policy_revision":a["policy_revision"],"configuration":null}),
    )
    .await;
    assert_eq!(cfg_change["result"]["error"]["code"], "state_conflict");
    publish(&f, e, &[("CQ W1AW FN31", 900.0, Some(-3.0))]);
    assert_eq!(f.read("contact").await["transmit"]["arm_state"], "armed");
    let contact_revision = f.read("contact").await["contact_revision"].clone();
    // Halt from the MCP client ends the run in every state.
    let halt =
        json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap()});
    assert_eq!(
        f.tool("wstx_transmit_halt", json!({"halt":halt})).await["status"],
        202
    );
    f.tick();
    assert_eq!(run_state(&f).await, ("stopped".into(), json!("halted")));
    // Retrying the original start (same command_id and body) returns its receipt only.
    let mut body = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":receipt["result"]["command_id"],"action":"start"});
    body.as_object_mut()
        .unwrap()
        .extend(start.as_object().unwrap().clone());
    let retry = f
        .tool("wstx_automation_command", json!({"command":body}))
        .await;
    assert_eq!(
        (retry["status"].clone(), retry["result"].clone()),
        (json!(200), receipt["result"].clone())
    );
    let stale = automation(&f, "start", start.clone()).await;
    assert_eq!(
        (
            stale["result"]["error"]["code"].clone(),
            stale["result"]["error"]["field"].clone()
        ),
        (json!("stale_revision"), json!("expected_run_revision"))
    );
    publish(
        &f,
        e + 30_000,
        &[
            ("CQ K1ABC FN42", 1500.0, Some(-1.0)),
            ("HB9BLA W1AW -05", 905.0, Some(-6.0)),
        ],
    );
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["contact"]["dx_call"].clone(),
            c["transmit"]["arm_state"].clone()
        ),
        (json!("W1AW"), json!("disarmed")),
        "{c}"
    );
    assert!(c["contact_revision"].as_u64() >= contact_revision.as_u64());
    assert_eq!(
        f.read("automation").await["run"]["selected"]["call"],
        "W1AW",
        "no new selection after halt"
    );
    // A run never starts over a contact in progress; the operator cancels it first.
    let a = f.read("automation").await;
    let busy = automation(&f, "start", json!({"expected_policy_revision":a["policy_revision"],"expected_run_revision":a["run_revision"],"mode":"ft8","safety_revision":3})).await;
    assert_eq!(
        (
            busy["result"]["error"]["code"].clone(),
            busy["result"]["error"]["field"].clone()
        ),
        (json!("state_conflict"), json!("contact"))
    );
    cancel(&f).await;
    // A browser Halt (the same priority route) ends a waiting run before any selection.
    let a = f.read("automation").await;
    let fresh = automation(&f, "start", json!({"expected_policy_revision":a["policy_revision"],"expected_run_revision":a["run_revision"],"mode":"ft8","safety_revision":3})).await;
    assert_eq!(fresh["status"], 202, "{fresh}");
    let r = f.browser("POST", "/transmit/halt", Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap()}))).await;
    assert_eq!(r.status, StatusCode::ACCEPTED);
    publish(&f, e + 60_000, &[("CQ G4ABC IO91", 1000.0, Some(0.0))]);
    assert_eq!(run_state(&f).await, ("stopped".into(), json!("halted")));
    assert_eq!(
        f.read("contact").await["contact"]["state"],
        "cancelled",
        "nothing selected after the halt"
    );
}

// Proves: TC-020-003.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_020_003_no_answer_context_change_and_lost_authority_stop_and_disarm() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let mut cfg = config_json();
    cfg["max_unanswered_periods"] = json!(2);
    cfg["ranking"] = json!("first_seen");
    run(&f, cfg.clone(), "ft8").await;
    publish(
        &f,
        e,
        &[
            ("CQ W1AW FN31", 900.0, Some(-3.0)),
            ("CQ K1ABC FN42", 1500.0, Some(9.0)),
        ],
    );
    assert_eq!(
        f.read("contact").await["contact"]["dx_call"],
        "W1AW",
        "first seen"
    );
    // Only the partner's (even) periods can answer: the own odd period is not counted.
    publish(&f, e + 15_000, &[("CQ G4ABC IO91", 1000.0, Some(0.0))]);
    let a = f.read("automation").await["run"].clone();
    assert_eq!(
        (a["state"].clone(), a["unanswered_periods"].clone()),
        (json!("contact_active"), json!(0))
    );
    publish(&f, e + 30_000, &[("HB9BLA K1ABC -05", 1000.0, Some(0.0))]);
    let a = f.read("automation").await["run"].clone();
    assert_eq!(
        (a["state"].clone(), a["unanswered_periods"].clone()),
        (json!("contact_active"), json!(1))
    );
    publish(&f, e + 45_000, &[("CQ G4ABC IO91", 1000.0, Some(0.0))]);
    assert_eq!(
        run_state(&f).await.0,
        "contact_active",
        "own period again not counted"
    );
    publish(&f, e + 60_000, &[("CQ G4ABC IO91", 1000.0, Some(0.0))]);
    assert_eq!(run_state(&f).await, ("stopped".into(), json!("no_answer")));
    assert_eq!(f.read("contact").await["transmit"]["arm_state"], "disarmed");
    // A new live job (receive context) ends a running contact and disarms it.
    cancel(&f).await;
    let a = f.read("automation").await;
    let s = automation(&f, "start", json!({"expected_policy_revision":a["policy_revision"],"expected_run_revision":a["run_revision"],"mode":"ft8","safety_revision":3})).await;
    assert_eq!(s["status"], 202, "{s}");
    publish(&f, e + 90_000, &[("CQ K1ABC FN42", 1500.0, Some(9.0))]);
    assert_eq!(f.read("contact").await["transmit"]["arm_state"], "armed");
    f.state.recording.fixture_live_job("ft8");
    f.tick();
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("context_changed"))
    );
    assert_eq!(f.read("contact").await["transmit"]["arm_state"], "disarmed");
    // Revoking the starting MCP client in Settings ends the run at the next step and the
    // MCP credential is gone (#58: revocation is immediate).
    cancel(&f).await;
    let a = f.read("automation").await;
    let s = automation(&f, "start", json!({"expected_policy_revision":a["policy_revision"],"expected_run_revision":a["run_revision"],"mode":"ft8","safety_revision":3})).await;
    assert_eq!(s["status"], 202, "{s}");
    let clients = f
        .browser("GET", "/authorization/v1/mcp-clients", None)
        .await;
    let id = clients.json["clients"][0]["client_id"].as_str().unwrap();
    assert_eq!(f.revoke_mcp_client(id).await.status, StatusCode::OK);
    publish(&f, e + 120_000, &[("CQ G4ABC IO91", 1000.0, Some(0.0))]);
    let snapshot = f
        .state
        .recording
        .contact
        .get()
        .unwrap()
        .automation
        .snapshot(&f.state.recording);
    assert_eq!(
        (
            snapshot["run"]["state"].clone(),
            snapshot["run"]["reason"].clone()
        ),
        (json!("stopped"), json!("authority_lost"))
    );
    assert_eq!(
        snapshot["run"]["selected"],
        Value::Null,
        "nothing selected without authority"
    );
    let r = f.modern("tools/list", json!({})).await;
    assert_eq!(r.status, StatusCode::UNAUTHORIZED);
}

// Proves: TC-020-003.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_020_003_ft4_uses_the_same_policy_and_mode_mismatch_is_not_ready() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft4");
    let mut cfg = config_json();
    cfg["modes"] = json!(["ft4"]);
    let a = f.read("automation").await;
    let c = automation(
        &f,
        "configure",
        json!({"expected_policy_revision":a["policy_revision"],"configuration":cfg.clone()}),
    )
    .await;
    assert_eq!(c["status"], 202);
    let a = f.read("automation").await;
    let ft8 = automation(&f, "start", json!({"expected_policy_revision":a["policy_revision"],"expected_run_revision":a["run_revision"],"mode":"ft8","safety_revision":3})).await;
    assert_eq!(
        (
            ft8["result"]["error"]["code"].clone(),
            ft8["result"]["error"]["field"].clone()
        ),
        (json!("not_ready"), json!("mode"))
    );
    let s = automation(&f, "start", json!({"expected_policy_revision":a["policy_revision"],"expected_run_revision":a["run_revision"],"mode":"ft4","safety_revision":3})).await;
    assert_eq!(s["status"], 202, "{s}");
    let p = (now_ms().div_euclid(15_000) + 2) * 15_000;
    publish(
        &f,
        p,
        &[
            ("CQ K1ABC FN42", 1500.0, Some(-12.0)),
            ("CQ W1AW FN31", 900.0, Some(-3.0)),
        ],
    );
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["contact"]["dx_call"].clone(),
            c["contact"]["tx4"].clone(),
            c["transmit"]["arm_state"].clone()
        ),
        (json!("W1AW"), json!("rr73"), json!("armed")),
        "{c}"
    );
}

/// One complete responder contact with `call` from its CQ at even period `e`.
async fn complete_contact(f: &Mcp, e: i64, call: &str) {
    publish(f, e, &[(&format!("CQ {call} FN31"), 900.0, Some(-3.0))]);
    assert_eq!(f.read("contact").await["contact"]["dx_call"], call);
    publish(
        f,
        e + 30_000,
        &[(&format!("HB9BLA {call} -05"), 905.0, Some(-6.0))],
    );
    publish(
        f,
        e + 60_000,
        &[(&format!("HB9BLA {call} RR73"), 905.0, Some(-6.0))],
    );
    assert_eq!(f.read("contact").await["contact"]["state"], "signoff");
    transmit_own_period(f, e + 15_000).await;
    assert_eq!(f.read("contact").await["contact"]["state"], "completed");
}
async fn start_again(f: &Mcp) -> Value {
    let a = f.read("automation").await;
    let s = automation(
        f,
        "start",
        json!({"expected_policy_revision":a["policy_revision"],
        "expected_run_revision":a["run_revision"],"mode":"ft8","safety_revision":3}),
    )
    .await;
    assert_eq!(s["status"], 202, "{s}");
    s
}
async fn reconfigure(f: &Mcp, cfg: Value) {
    let a = f.read("automation").await;
    let c = automation(
        f,
        "configure",
        json!({"expected_policy_revision":a["policy_revision"],"configuration":cfg}),
    )
    .await;
    assert_eq!(c["status"], 202, "{c}");
}
fn halts(f: &Mcp) -> u64 {
    f.state
        .recording
        .transmit
        .get()
        .unwrap()
        .service
        .halt_requests()
}
fn owner(f: &Mcp) -> Arc<contact_http::Station> {
    f.state.recording.contact.get().unwrap().clone()
}
fn skew(f: &Mcp, d: Duration) {
    *owner(f).automation.skew.lock().unwrap() = d;
}

// Proves: CL-039-09; TC-039-010, TC-039-049 (l). A plain MCP policy run decides no slot, with Hold
// Tx on (the default) as before #39 holdtx.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_039_010_a_plain_policy_run_keeps_its_tx_on_the_called_station() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    assert_eq!(f.read("contact").await["settings"]["hold_tx"], true);
    run(&f, config_json(), "ft8").await;
    publish(&f, e, &[("CQ K1ABC FN42", 1500.0, Some(-12.0))]);
    let c = f.read("contact").await;
    assert_eq!(c["contact"]["dx_call"], "K1ABC");
    assert_eq!(c["settings"]["tx_hz"], 1500);
    assert_eq!(
        f.read("automation").await["run"]["tx_slot"],
        Value::Null,
        "no slot decision"
    );
}

// Proves: TC-020-003.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_020_003_contact_limit_and_completion_stop_the_run() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let mut cfg = config_json();
    cfg["max_contacts"] = json!(1);
    let e = at_even(&f);
    run(&f, cfg.clone(), "ft8").await;
    complete_contact(&f, e, "W1AW").await;
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("limit_reached"))
    );
    assert_eq!(f.read("automation").await["run"]["completed_contacts"], 1);
    // completion_action stop ends the run after one contact even below the limit.
    cfg["max_contacts"] = json!(5);
    cfg["completion_action"] = json!("stop");
    reconfigure(&f, cfg).await;
    start_again(&f).await;
    let e2 = next_even(&f);
    complete_contact(&f, e2, "K1ABC").await;
    assert_eq!(run_state(&f).await, ("stopped".into(), json!("completed")));
    publish(&f, e2 + 90_000, &[("CQ G4ABC IO91", 1000.0, Some(0.0))]);
    let c = f.read("contact").await;
    assert_eq!(
        c["contact"]["dx_call"], "K1ABC",
        "no selection after completion"
    );
    assert_eq!(c["transmit"]["arm_state"], "disarmed");
}

// Proves: TC-020-003.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_020_003_a_halt_racing_the_arming_halts_and_never_keys() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    run(&f, config_json(), "ft8").await;
    let before = halts(&f);
    let recording = f.state.recording.clone();
    *owner(&f).automation.before_enable.lock().unwrap() = Some(Box::new(move || {
        recording
            .transmit
            .get()
            .unwrap()
            .service
            .halt("00000000-0000-4000-8000-0000000000aa");
    }));
    publish(&f, e, &[("CQ W1AW FN31", 900.0, Some(-3.0))]);
    assert_eq!(run_state(&f).await, ("stopped".into(), json!("halted")));
    let c = f.read("contact").await;
    assert_eq!(c["transmit"]["arm_state"], "disarmed", "{c}");
    assert_eq!(
        halts(&f),
        before + 2,
        "the operator's Halt and the automation's own Halt"
    );
    assert!(
        f.bench.keys.lock().unwrap().iter().all(|(_, on)| !on),
        "never keyed"
    );
    publish(&f, e + 30_000, &[("CQ K1ABC FN42", 1500.0, Some(0.0))]);
    assert_eq!(f.read("contact").await["transmit"]["arm_state"], "disarmed");
}

// Proves: TC-020-003.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_020_003_the_run_ends_with_its_transport_and_its_duration() {
    let mut f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    at_even(&f);
    let mut cfg = config_json();
    cfg["max_run_minutes"] = json!(1);
    run(&f, cfg.clone(), "ft8").await;
    skew(&f, Duration::from_secs(59));
    f.tick();
    assert_eq!(run_state(&f).await.0, "waiting", "inside the duration");
    skew(&f, Duration::from_secs(61));
    f.tick();
    assert_eq!(run_state(&f).await, ("stopped".into(), json!("time_limit")));
    skew(&f, Duration::ZERO);
    // A newer proof of the browser's grant is another credential (#58): the MCP
    // client's run keeps its own transport and waits on; the client's revocation ends
    // it (TC-020-003 d).
    cfg["max_run_minutes"] = json!(480);
    reconfigure(&f, cfg).await;
    let started = start_again(&f).await;
    f.renew().await;
    f.tick();
    assert_eq!(run_state(&f).await.0, "waiting");
    let stop = automation(&f, "stop", json!({"run_id":started["result"]["run_id"]})).await;
    assert_eq!(stop["status"], 202, "{stop}");
    // The starting transport's 8 h deadline ends a waiting run (checked before duration).
    start_again(&f).await;
    skew(&f, Duration::from_secs(8 * 3600 - 60));
    f.tick();
    assert_eq!(run_state(&f).await.0, "waiting");
    skew(&f, Duration::from_secs(8 * 3600 + 1));
    f.tick();
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("authority_lost"))
    );
    skew(&f, Duration::ZERO);
}

/// One accepted ContactCommand from the MCP client (the operator's own action).
async fn operator(f: &Mcp, action: &str, extra: Value) {
    let revision = f.read("contact").await["contact_revision"]
        .as_u64()
        .unwrap();
    let v = f
        .tool(
            "wstx_contact_command",
            json!({"command":f.command(revision, action, extra)}),
        )
        .await;
    assert_eq!(v["status"], 202, "{action}: {v}");
}

// Proves: TC-020-003.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_020_003_operator_actions_end_the_run_and_are_never_taken_over() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    // An operator CQ while the run waits: the run stops and leaves the CQ alone.
    run(&f, config_json(), "ft8").await;
    operator(&f, "enable_tx", json!({"enabled":true,"safety_revision":3})).await;
    f.tick();
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("contact_changed"))
    );
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["contact"]["state"].clone(),
            c["transmit"]["arm_state"].clone()
        ),
        (json!("calling"), json!("armed"))
    );
    publish(&f, e, &[("CQ W1AW FN31", 900.0, Some(-3.0))]);
    assert_eq!(
        f.read("contact").await["contact"]["state"],
        "calling",
        "never taken over"
    );
    operator(
        &f,
        "enable_tx",
        json!({"enabled":false,"safety_revision":null}),
    )
    .await;
    operator(&f, "cancel", json!({})).await;
    // An operator contact prepared while the run waits is not adopted either.
    start_again(&f).await;
    operator(
        &f,
        "enter_dx",
        json!({"dx_call":"W1AW","dx_grid":null,"replace":false}),
    )
    .await;
    publish(&f, e + 30_000, &[("CQ W1AW FN31", 900.0, Some(-3.0))]);
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("contact_changed"))
    );
    assert_eq!(f.read("contact").await["contact"]["origin"], "manual_entry");
    operator(&f, "cancel", json!({})).await;
    // Operator cancel of the run's contact.
    start_again(&f).await;
    publish(&f, e + 60_000, &[("CQ K1ABC FN42", 1500.0, Some(-3.0))]);
    assert_eq!(run_state(&f).await.0, "contact_active");
    operator(&f, "cancel", json!({})).await;
    f.tick();
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("contact_changed"))
    );
    // Operator Enable Tx off: transmit_stopped (no Halt).
    let before = halts(&f);
    start_again(&f).await;
    publish(&f, e + 90_000, &[("CQ G4ABC IO91", 1000.0, Some(-3.0))]);
    assert_eq!(run_state(&f).await.0, "contact_active");
    operator(
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
    assert_eq!(halts(&f), before);
    operator(&f, "cancel", json!({})).await;
    // Operator replaces the run's contact: contact_changed, and the run disarms.
    start_again(&f).await;
    publish(&f, e + 120_000, &[("CQ DL1XYZ JO62", 1200.0, Some(-3.0))]);
    assert_eq!(f.read("contact").await["transmit"]["arm_state"], "armed");
    operator(
        &f,
        "enter_dx",
        json!({"dx_call":"DL1ABC","dx_grid":"JO62","replace":true}),
    )
    .await;
    f.tick();
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("contact_changed"))
    );
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["contact"]["dx_call"].clone(),
            c["transmit"]["arm_state"].clone()
        ),
        (json!("DL1ABC"), json!("disarmed"))
    );
}

// Proves: TC-020-003.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_020_003_refused_selection_or_arming_stops_without_a_contact_left_behind() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    // A start with another than the current safety revision is refused.
    reconfigure(&f, config_json()).await;
    let a = f.read("automation").await;
    let stale = automation(
        &f,
        "start",
        json!({"expected_policy_revision":a["policy_revision"],
        "expected_run_revision":a["run_revision"],"mode":"ft8","safety_revision":4}),
    )
    .await;
    assert_eq!(
        (
            stale["result"]["error"]["code"].clone(),
            stale["result"]["error"]["field"].clone()
        ),
        (json!("stale_revision"), json!("safety_revision"))
    );
    // select_row refused (profile callsign gone): provider_error, nothing prepared.
    start_again(&f).await;
    let callsign = std::mem::take(&mut f.state.store.lock().unwrap().document.callsign);
    publish(&f, e, &[("CQ W1AW FN31", 900.0, Some(-3.0))]);
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("provider_error"))
    );
    assert_eq!(f.read("contact").await["contact"], Value::Null);
    f.state.store.lock().unwrap().document.callsign = callsign;
    // enable_tx refused (transmit became unsupported): the selected contact is cancelled.
    start_again(&f).await;
    f.bench.unsupported.store(true, Ordering::SeqCst);
    publish(&f, e + 30_000, &[("CQ K1ABC FN42", 1500.0, Some(-3.0))]);
    assert_eq!(
        run_state(&f).await,
        ("stopped".into(), json!("transmit_refused"))
    );
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["contact"]["dx_call"].clone(),
            c["contact"]["state"].clone(),
            c["transmit"]["arm_state"].clone()
        ),
        (Value::Null, json!("cancelled"), json!("disarmed")),
        "{c}"
    );
    assert!(f.bench.keys.lock().unwrap().is_empty());
}
