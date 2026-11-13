// Proves: CL-081-01; TC-081-001..005 (#81, each test names its case below). A started QSO is finished
// whatever ends the run (WstxStrategy::StartedQso). Oracle: the operator's rule of 2026-11-08 on #81
// ("Auto only starts"; a QSO is started once he has sent a message to my call and our transmission to
// him has started), the standard sequence of WstxContact::QsoAndLogging (Tx1, R-report, 73 after his
// RR73), WstxQsoControl::TxWatchdog (the stop at N) and the FT8 transmission length of 12.64 s
// (79 symbols of 0.16 s). The actual station router, contact engine, logbook and #9 transmit owner on
// the recording hardware double (virtual UTC; no audio, PTT or radio) with the scripted IC-7300 dial
// on 14.074 MHz (the log's band); hand-authored decodes packed with the real codec.
use super::*;
use crate::automation_tests::{automation, run};

/// A station on 20 m FT8: the scripted dial on 14.074 MHz (the band of the log entry), an empty log,
/// a status client present, the Tx watchdog at `limit` set by the browser (None: the default 6).
/// e: the even (partner) period of the bench; the own periods are odd.
struct Station81 {
    f: Mcp,
    e: i64,
    peer: Arc<Mutex<crate::cat_lifecycle_tests::Peer>>,
    _client: crate::automation::ClientSession,
}
async fn station81(limit: Option<u64>) -> Station81 {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let client = f.state.recording.clients.session();
    f.state.recording.fixture_band("20m");
    let peer = dial_20m(&f);
    if let Some(limit) = limit {
        browser_watchdog(&f, limit).await;
    }
    Station81 {
        f,
        e,
        peer,
        _client: client,
    }
}
const K1ABC: (&str, f64, Option<f64>) = ("CQ K1ABC FN42", 1800.0, Some(-10.0));
/// K1ABC's message `text` near his CQ's frequency.
fn his(text: &str) -> (&str, f64, Option<f64>) {
    (text, 1805.0, Some(-8.0))
}
/// The run calls K1ABC (Tx1 keyed in e + 15 s) and his answer HB9BLA K1ABC -05 is decoded in e + 30 s:
/// a started QSO (case d), our R-report due.
async fn answered(f: &Mcp, e: i64) {
    publish(f, e, &[K1ABC]);
    assert_eq!(
        contact(f).await,
        (json!("K1ABC"), json!("replying"), json!("armed"))
    );
    transmit_own_period(f, e + 15_000).await;
    assert_eq!(last_text(f).as_deref(), Some("K1ABC HB9BLA JN47"));
    publish(f, e + 30_000, &[his("HB9BLA K1ABC -05")]);
    assert_eq!(
        contact(f).await,
        (json!("K1ABC"), json!("roger_report"), json!("armed"))
    );
}
/// The QSO goes on from his report: our R-report keyed in e + 45 s, his RR73 (with `beside`) in
/// e + 60 s, our 73 in e + 75 s; then the contact is completed with Enable Tx off and the log holds
/// exactly one entry, K1ABC FN42 on 20 m in FT8, written by the completed contact itself.
async fn finished(f: &Mcp, e: i64, beside: &[(&str, f64, Option<f64>)]) {
    transmit_own_period(f, e + 45_000).await;
    assert_eq!(last_text(f).as_deref(), Some("K1ABC HB9BLA R-10"));
    let mut rows = vec![his("HB9BLA K1ABC RR73")];
    rows.extend_from_slice(beside);
    publish(f, e + 60_000, &rows);
    transmit_own_period(f, e + 75_000).await;
    assert_eq!(last_text(f).as_deref(), Some("K1ABC HB9BLA 73"));
    f.tick();
    assert_eq!(
        contact(f).await,
        (json!("K1ABC"), json!("completed"), json!("disarmed"))
    );
    assert_eq!(logged(f, e), vec![qso("K1ABC", "FN42")]);
}
/// Into the own period `own` until its transmission is on the air, then 2 s into it with one station
/// step; the key-on time.
async fn on_the_air(f: &Mcp, own: i64) -> i64 {
    crate::automation_tests::assert_bound(f, own);
    let service = &f.state.recording.transmit.get().unwrap().service;
    f.bench
        .offset
        .fetch_add(own - 30 - f.bench.now_utc_ms(), Ordering::SeqCst);
    let deadline = Instant::now() + Duration::from_secs(5);
    while !service.view().transmitting {
        assert!(Instant::now() < deadline, "{:?}", service.view());
        f.tick();
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    f.bench.offset.fetch_add(2_000, Ordering::SeqCst);
    f.tick();
    let (at, on) = *f.bench.keys.lock().unwrap().last().unwrap();
    assert!(on);
    at
}
/// The transmission keyed at `on` runs on to its normal end: PTT released 12.64 s (the FT8
/// transmission) or more after the key-on, never at the request that came 2 s into it.
async fn to_its_end(f: &Mcp, on: i64) {
    let service = &f.state.recording.transmit.get().unwrap().service;
    assert!(service.view().transmitting, "still on the air");
    f.bench.offset.fetch_add(11_000, Ordering::SeqCst);
    let deadline = Instant::now() + Duration::from_secs(5);
    while service.view().transmitting {
        assert!(Instant::now() < deadline, "{:?}", service.view());
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    f.tick();
    let (off, keyed) = *f.bench.keys.lock().unwrap().last().unwrap();
    assert!(!keyed);
    assert!(
        off - on >= 12_640,
        "released {} ms after the key-on",
        off - on
    );
}
/// The station steps through the own period `own` in 100 ms steps to 2 s into it and on past its end:
/// nothing is keyed.
async fn silent_through(f: &Mcp, own: i64) {
    let service = &f.state.recording.transmit.get().unwrap().service;
    let keys = f.keys();
    f.bench
        .offset
        .fetch_add(own - 30 - f.bench.now_utc_ms(), Ordering::SeqCst);
    for _ in 0..21 {
        f.tick();
        tokio::time::sleep(Duration::from_millis(5)).await;
        assert!(!service.view().transmitting, "nothing keyed in {own}");
        f.bench.offset.fetch_add(100, Ordering::SeqCst);
    }
    f.bench.offset.fetch_add(11_000, Ordering::SeqCst);
    f.tick();
    assert_eq!(f.keys(), keys, "nothing keyed in {own}");
}
async fn auto_off(f: &Mcp) {
    let r = auto(f, false, None).await;
    assert_eq!(
        (r.status, r.json["auto"].clone()),
        (StatusCode::OK, json!(false)),
        "{}",
        r.json
    );
}
/// The started QSO of TC-081-001 with "New calls" selected and Auto on.
async fn new_calls_answered(limit: Option<u64>) -> Station81 {
    let t = station81(limit).await;
    select(&t.f, config(Some("New calls"))).await;
    answered(&t.f, t.e).await;
    t
}

// Proves: CL-081-01; TC-081-001, the reproduction. Auto off after K1ABC's report: Auto off at once
// (one strategy.state) and the run stopped, reason stopped; Enable Tx stays on, our R-report goes out
// in the next own period and 73 after his RR73; the contact completes with Enable Tx off and logs
// itself once; afterwards nothing is armed, selected or keyed for DL1XYZ's CQ or W1AW's calls. Red
// on the parent: Enable Tx off and the contact cancelled at the Auto off.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_081_001_auto_off_in_a_started_qso_finishes_it_and_logs_it_once() {
    let t = new_calls_answered(None).await;
    let (f, e) = (&t.f, t.e);
    let owner = f.state.recording.contact.get().unwrap();
    let before = owner.strategy.revision();
    auto_off(f).await;
    assert_eq!(owner.strategy.revision(), before + 1, "one strategy.state");
    assert_eq!(
        f.browser("GET", "/strategy", None).await.json["auto"],
        false
    );
    assert_eq!(run_state(f).await, ("stopped".into(), json!("stopped")));
    f.tick();
    assert_eq!(
        contact(f).await,
        (json!("K1ABC"), json!("roger_report"), json!("armed")),
        "Enable Tx stays on"
    );
    finished(f, e, &[]).await;
    let w1aw = ("HB9BLA W1AW FN31", 900.0, Some(-5.0));
    publish(
        f,
        e + 90_000,
        &[("CQ DL1XYZ JO62", 1200.0, Some(-1.0)), w1aw],
    );
    silent_through(f, e + 105_000).await;
    publish(f, e + 120_000, &[w1aw]);
    silent_through(f, e + 135_000).await;
    publish(f, e + 150_000, &[w1aw]);
    silent_through(f, e + 165_000).await;
    assert_eq!(
        contact(f).await,
        (json!("K1ABC"), json!("completed"), json!("disarmed"))
    );
    assert_eq!(run_state(f).await, ("stopped".into(), json!("stopped")));
    assert_eq!(logged(f, e), vec![qso("K1ABC", "FN42")]);
}

/// "Casual 20 m" with Auto on and Hold Tx off calling CQ after two empty publications (e - 30 s and
/// e); the CQ is due in e + 15 s.
async fn casual_cq() -> Station81 {
    let t = station81(None).await;
    let (f, e) = (&t.f, t.e);
    hold_off(f).await;
    select(f, config(Some("Casual 20 m"))).await;
    publish(f, e - 30_000, &[]);
    publish(f, e, &[]);
    assert_eq!(run_of(f).await["state"], "calling_cq");
    assert_eq!(contact(f).await.2, json!("armed"));
    t
}
/// The CQ keyed in e + 15 s, W1AW FN31 calling my call in e + 30 s: the run answers him from the CQ,
/// our report to him armed for e + 45 s.
async fn w1aw_answered(f: &Mcp, e: i64) {
    transmit_own_period(f, e + 15_000).await;
    assert_eq!(last_text(f).as_deref(), Some("CQ HB9BLA JN47"));
    publish(f, e + 30_000, &[("HB9BLA W1AW FN31", 900.0, Some(-10.0))]);
    assert_eq!(
        contact(f).await,
        (json!("W1AW"), json!("report"), json!("armed"))
    );
    assert_eq!(run_of(f).await["state"], "contact_active");
}

// Proves: CL-081-01; TC-081-002 (a). He called us and our reply is on the air: a started QSO. Auto off
// 2 s into the period of our report to W1AW: the report's period ends normally (no abort, no halt),
// then his R-05 is answered with RR73 and the contact completes and logs W1AW once. Red on the parent:
// Enable Tx off and the contact cancelled at the Auto off.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_081_002_a_reply_on_the_air_is_a_started_qso() {
    let t = casual_cq().await;
    let (f, e) = (&t.f, t.e);
    w1aw_answered(f, e).await;
    let halt_state = f.read("contact").await["transmit"]["halt_state"].clone();
    let on = on_the_air(f, e + 45_000).await;
    assert_eq!(last_text(f).as_deref(), Some("W1AW HB9BLA -10"));
    auto_off(f).await;
    assert_eq!(run_state(f).await, ("stopped".into(), json!("stopped")));
    assert_eq!(
        contact(f).await,
        (json!("W1AW"), json!("report"), json!("armed"))
    );
    to_its_end(f, on).await;
    publish(f, e + 60_000, &[("HB9BLA W1AW R-05", 905.0, Some(-8.0))]);
    transmit_own_period(f, e + 75_000).await;
    assert_eq!(last_text(f).as_deref(), Some("W1AW HB9BLA RRR"));
    publish(f, e + 90_000, &[("HB9BLA W1AW RR73", 905.0, Some(-8.0))]);
    transmit_own_period(f, e + 105_000).await;
    assert_eq!(last_text(f).as_deref(), Some("W1AW HB9BLA 73"));
    f.tick();
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["contact"]["state"].clone(),
            c["transmit"]["arm_state"].clone(),
            c["transmit"]["halt_state"].clone()
        ),
        (json!("completed"), json!("disarmed"), halt_state)
    );
    assert_eq!(logged(f, e), vec![qso("W1AW", "FN31")]);
}

// Proves: CL-081-01; TC-081-002 (b), (c), (d), regression guards (green on the parent). (b) He called
// us and our reply is only armed: no started QSO; Auto off disarms and cancels at once, his further
// calls are not answered, nothing is keyed or logged. (c) We called K1ABC's CQ and he has sent nothing
// to my call: Auto off 2 s into our second Tx1 lets it finish its period, then nothing is keyed, the
// contact is cancelled and his late answer is not replied to. (d) The run's CQ on the air finishes its
// period, nothing is keyed after it and no CQ contact is left behind.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_081_002_b_c_d_no_started_qso_ends_at_once_and_its_period_on_the_air_finishes() {
    // (b)
    let t = casual_cq().await;
    let (f, e) = (&t.f, t.e);
    w1aw_answered(f, e).await;
    let keys = f.keys();
    auto_off(f).await;
    f.tick();
    assert_eq!(
        contact(f).await,
        (Value::Null, json!("cancelled"), json!("disarmed"))
    );
    for k in 1..=3 {
        silent_through(f, rep(e, k) + 15_000).await;
        publish(
            f,
            rep(e, k + 1),
            &[("HB9BLA W1AW FN31", 900.0, Some(-10.0))],
        );
    }
    silent_through(f, rep(e, 4) + 15_000).await;
    assert_eq!(f.keys(), keys, "W1AW never gets a transmission");
    assert_eq!(contact(f).await.1, json!("cancelled"));
    assert_eq!(logged(f, e), vec![]);

    // (c)
    let t = station81(None).await;
    let (f, e) = (&t.f, t.e);
    select(f, config(Some("New calls"))).await;
    publish(f, e, &[K1ABC]);
    transmit_own_period(f, e + 15_000).await;
    publish(f, e + 30_000, &[]);
    let on = on_the_air(f, e + 45_000).await;
    assert_eq!(last_text(f).as_deref(), Some("K1ABC HB9BLA JN47"));
    auto_off(f).await;
    to_its_end(f, on).await;
    assert_eq!(
        contact(f).await,
        (Value::Null, json!("cancelled"), json!("disarmed"))
    );
    publish(f, e + 60_000, &[his("HB9BLA K1ABC -05")]);
    silent_through(f, e + 75_000).await;
    assert_eq!(contact(f).await.1, json!("cancelled"));
    assert_eq!(logged(f, e), vec![]);

    // (d)
    let t = casual_cq().await;
    let (f, e) = (&t.f, t.e);
    let on = on_the_air(f, e + 15_000).await;
    assert_eq!(last_text(f).as_deref(), Some("CQ HB9BLA JN47"));
    auto_off(f).await;
    to_its_end(f, on).await;
    silent_through(f, e + 45_000).await;
    assert_eq!(
        contact(f).await,
        (Value::Null, json!("idle"), json!("disarmed")),
        "no CQ contact left behind"
    );
}

// Proves: CL-081-01; TC-081-003 (a), (b), (h). None, another strategy with Auto on and Auto off twice
// let the started QSO finish: (a) the run stopped, Auto off; (b) the old run stopped, Auto on, the new
// run manual until the completion, then waiting, JA1XYZ (CQ during the QSO) selected only from a
// publication after the completion; (h) the second Auto off changes no revision and no contact. Red
// on the parent: each case disarms and cancels K1ABC at the end, nothing logged.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_081_003_none_another_strategy_and_auto_off_twice_finish_the_qso() {
    // (a)
    let t = new_calls_answered(None).await;
    let (f, e) = (&t.f, t.e);
    save(f, config(None)).await;
    assert_eq!(run_state(f).await, ("stopped".into(), json!("stopped")));
    assert_eq!(
        f.browser("GET", "/strategy", None).await.json["auto"],
        false
    );
    f.tick();
    assert_eq!(contact(f).await.2, json!("armed"));
    finished(f, e, &[]).await;

    // (b)
    let t = new_calls_answered(None).await;
    let (f, e) = (&t.f, t.e);
    let old = run_of(f).await["id"].clone();
    save(f, config(Some("Farthest new on band"))).await;
    assert_eq!(f.browser("GET", "/strategy", None).await.json["auto"], true);
    f.tick();
    let run = run_of(f).await;
    assert_ne!(run["id"], old);
    assert_eq!(run["state"], "manual", "the new run waits for the QSO");
    let ja = ("CQ JA1XYZ PM95", 1300.0, Some(-12.0));
    transmit_own_period(f, e + 45_000).await;
    assert_eq!(last_text(f).as_deref(), Some("K1ABC HB9BLA R-10"));
    publish(f, e + 60_000, &[his("HB9BLA K1ABC RR73"), ja]);
    assert_eq!(contact(f).await.0, json!("K1ABC"), "JA1XYZ not selected");
    assert_eq!(run_of(f).await["state"], "manual");
    transmit_own_period(f, e + 75_000).await;
    assert_eq!(last_text(f).as_deref(), Some("K1ABC HB9BLA 73"));
    f.tick();
    assert_eq!(
        contact(f).await,
        (json!("K1ABC"), json!("completed"), json!("disarmed"))
    );
    assert_eq!(logged(f, e), vec![qso("K1ABC", "FN42")]);
    f.tick();
    assert_eq!(run_state(f).await, ("waiting".into(), Value::Null));
    publish(f, e + 90_000, &[ja]);
    assert_eq!(
        contact(f).await,
        (json!("JA1XYZ"), json!("replying"), json!("armed"))
    );

    // (h)
    let t = new_calls_answered(None).await;
    let (f, e) = (&t.f, t.e);
    auto_off(f).await;
    let owner = f.state.recording.contact.get().unwrap();
    let revisions = || {
        (
            owner.strategy.revision(),
            owner.automation.revisions(),
            owner.revision(),
        )
    };
    let before = revisions();
    f.bench.offset.fetch_add(1_000, Ordering::SeqCst);
    auto_off(f).await;
    assert_eq!(revisions(), before, "the second Auto off changes nothing");
    assert_eq!(run_state(f).await, ("stopped".into(), json!("stopped")));
    finished(f, e, &[]).await;
}

/// WW Digi S&P with Auto on and automation_confirmed (the period e - 1 h to e + 1 h): K1ABC's CQ in e
/// called with the exchange (Tx1 is disabled in a contest), keyed in e + 15 s, and his roger with the
/// exchange in e + 30 s: a started QSO, our RRR due.
async fn contest_answered() -> Station81 {
    let t = station81(None).await;
    let (f, e) = (&t.f, t.e);
    browser_ok(f, "set_activity", json!({"activity":"ww_digi"})).await;
    select(f, contest_config(e, "sp", -1)).await;
    f.tick();
    publish(f, e, &[("CQ WW K1ABC FN42", 1800.0, Some(-10.0))]);
    assert_eq!(
        contact(f).await,
        (json!("K1ABC"), json!("report"), json!("armed"))
    );
    transmit_own_period(f, e + 15_000).await;
    assert_eq!(last_text(f).as_deref(), Some("K1ABC HB9BLA JN47"));
    publish(f, e + 30_000, &[his("HB9BLA K1ABC R FN42")]);
    assert_eq!(
        contact(f).await,
        (json!("K1ABC"), json!("rogers"), json!("armed"))
    );
    t
}
/// Our RRR keyed in `own`, his RR73 after it and our 73 complete the contest QSO: one log entry K1ABC
/// FN42 20m FT8.
async fn contest_finished(f: &Mcp, own: i64, e: i64) {
    transmit_own_period(f, own).await;
    assert_eq!(last_text(f).as_deref(), Some("K1ABC HB9BLA RRR"));
    publish(f, own + 15_000, &[his("HB9BLA K1ABC RR73")]);
    transmit_own_period(f, own + 30_000).await;
    assert_eq!(last_text(f).as_deref(), Some("K1ABC HB9BLA 73"));
    f.tick();
    assert_eq!(
        contact(f).await,
        (json!("K1ABC"), json!("completed"), json!("disarmed"))
    );
    assert_eq!(logged(f, e), vec![qso("K1ABC", "FN42")]);
}

// Proves: CL-081-01; TC-081-003 (c), (d). A contest deselected in a started QSO: the run stopped, Auto
// off, the QSO finished. The end of the contest period in a started QSO: the run manual while it
// finishes, then waiting outside_period. Red on the parent: K1ABC disarmed and cancelled at the end.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_081_003_a_contest_deselected_or_its_period_end_finishes_the_qso() {
    // (c)
    let t = contest_answered().await;
    let (f, e) = (&t.f, t.e);
    save(f, config(None)).await;
    assert_eq!(run_state(f).await, ("stopped".into(), json!("stopped")));
    assert_eq!(
        f.browser("GET", "/strategy", None).await.json["auto"],
        false
    );
    f.tick();
    assert_eq!(contact(f).await.2, json!("armed"));
    contest_finished(f, e + 45_000, e).await;

    // (d)
    let t = contest_answered().await;
    let (f, e) = (&t.f, t.e);
    // An hour later (the same period phase): past the period's end.
    let later = e + 3_600_000;
    crate::automation_tests::jump_and_tick(f, later + 1_000 - f.bench.now_utc_ms());
    assert_eq!(run_state(f).await, ("manual".into(), Value::Null));
    assert_eq!(contact(f).await.2, json!("armed"));
    contest_finished(f, later + 15_000, e).await;
    f.tick();
    f.tick();
    assert_eq!(
        run_state(f).await,
        ("waiting".into(), json!("outside_period"))
    );
}

// Proves: CL-081-01; TC-081-003 (e). Auto on ending a pounce in its started QSO: the pounce stopped,
// the strategy run manual until the completion, then waiting. Red on the parent: K1ABC disarmed and
// cancelled at the Auto on.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_081_003_auto_on_ending_a_pounce_finishes_its_qso() {
    let t = station81(None).await;
    let (f, e) = (&t.f, t.e);
    save(f, config(Some("New calls"))).await;
    let p = pounce(f, "K1ABC", 5).await;
    assert_eq!(p.status, StatusCode::ACCEPTED, "{}", p.json);
    answered(f, e).await;
    let pounce_run = run_of(f).await["id"].clone();
    let r = auto(f, true, None).await;
    assert_eq!(r.json["auto"], true, "{}", r.json);
    f.tick();
    let run = run_of(f).await;
    assert_ne!(run["id"], pounce_run);
    assert_eq!(
        (run["state"].clone(), run["pounce"].clone()),
        (json!("manual"), Value::Null)
    );
    finished(f, e, &[]).await;
    f.tick();
    assert_eq!(run_state(f).await, ("waiting".into(), Value::Null));
}

// Proves: CL-081-01; TC-081-003 (f), (g). An MCP policy run's AutomationCommand stop (run stopped
// stopped) and its time limit (max_run_minutes 1, the automation clock moved by the seam; stopped
// time_limit) let its started QSO finish. Red on the parent: K1ABC disarmed at the end.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_081_003_an_mcp_stop_and_the_time_limit_finish_the_qso() {
    // (f)
    let t = station81(None).await;
    let (f, e) = (&t.f, t.e);
    let (receipt, _) = run(f, crate::automation_tests::config_json(), "ft8").await;
    let id = receipt["result"]["run_id"].clone();
    answered(f, e).await;
    let s = automation(f, "stop", json!({"run_id":id})).await;
    assert_eq!(s["status"], 202, "{s}");
    assert_eq!(run_state(f).await, ("stopped".into(), json!("stopped")));
    f.tick();
    assert_eq!(contact(f).await.2, json!("armed"));
    finished(f, e, &[]).await;

    // (g)
    let t = station81(None).await;
    let (f, e) = (&t.f, t.e);
    let mut c = crate::automation_tests::config_json();
    c["max_run_minutes"] = json!(1);
    run(f, c, "ft8").await;
    answered(f, e).await;
    at_skew(f, 61);
    assert_eq!(run_state(f).await, ("stopped".into(), json!("time_limit")));
    assert_eq!(contact(f).await.2, json!("armed"));
    finished(f, e, &[]).await;
}

/// TC-081-004: "Test calls" with repetitions 4 and the Tx watchdog at 2 (the browser's), a spot of my
/// call at K1ABC 60 s old (he hears us: the leave rule would double x to 8), Tx 1500 held (K1ABC at
/// 1800); the feed follows K1ABC.
async fn watched() -> (Station81, Arc<crate::pskr::Feed>) {
    let t = station81(Some(2)).await;
    let (f, e) = (&t.f, t.e);
    let feed = attach_feed(f);
    let mut c = config(Some("Test calls"));
    set_repetitions(&mut c, 4);
    select(f, c).await;
    publish(f, e, &[K1ABC]);
    f.tick();
    feed.inject(&heard_spot(60));
    assert_eq!(feed.target().as_deref(), Some("K1ABC"));
    transmit_own_period(f, e + 15_000).await;
    publish(f, e + 30_000, &[his("HB9BLA K1ABC -05")]);
    assert_eq!(contact(f).await.1, json!("roger_report"));
    (t, feed)
}
/// After the Auto off the run's rules for the QSO have ended: no leaving, no slot check (Tx stays on
/// 1500, slot_check unchanged), no subscription of K1ABC, and tx_remaining_calls is the Tx watchdog's
/// `remaining`.
async fn rules_ended(f: &Mcp, feed: &crate::pskr::Feed, slot_check: &Value, remaining: u64) {
    f.tick();
    let run = run_of(f).await;
    assert_eq!(
        (
            run["state"].clone(),
            run["left"].clone(),
            run["quiet"].clone(),
            run["slot_check"].clone()
        ),
        (json!("stopped"), Value::Null, json!([]), slot_check.clone())
    );
    let c = f.read("contact").await;
    assert_eq!(c["settings"]["tx_hz"], 1500);
    assert_eq!(c["watchdog"]["tx_remaining_calls"], remaining);
    assert_eq!(feed.target(), None, "no subscription of K1ABC");
}

// Proves: CL-081-01; TC-081-004 (a), (b). The finishing QSO is bounded by the Tx watchdog (limit 2),
// not by the run. (a) Auto off after our 1st R-report, his RR73 after our 2nd: the 2nd R-report goes
// out (the limit not passed), then 73, completed, one log entry. (b) He repeats his report: the
// R-report is keyed a 2nd time, never a 3rd; Enable Tx goes off with cause tx_watchdog, no halt,
// nothing logged. Red on the parent: K1ABC disarmed at the Auto off, no 2nd R-report.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_081_004_a_b_the_finishing_qso_keeps_the_tx_watchdog_limit() {
    // (a)
    let (t, feed) = watched().await;
    let (f, e) = (&t.f, t.e);
    transmit_own_period(f, e + 45_000).await;
    assert_eq!(last_text(f).as_deref(), Some("K1ABC HB9BLA R-10"));
    let slot_check = run_of(f).await["slot_check"].clone();
    auto_off(f).await;
    rules_ended(f, &feed, &slot_check, 1).await;
    publish(f, e + 60_000, &[his("HB9BLA K1ABC -05")]);
    let keys = f.keys();
    transmit_own_period(f, e + 75_000).await;
    assert_eq!(f.keys(), keys + 2, "the 2nd R-report");
    assert_eq!(last_text(f).as_deref(), Some("K1ABC HB9BLA R-10"));
    publish(f, e + 90_000, &[his("HB9BLA K1ABC RR73")]);
    transmit_own_period(f, e + 105_000).await;
    assert_eq!(last_text(f).as_deref(), Some("K1ABC HB9BLA 73"));
    f.tick();
    assert_eq!(contact(f).await.1, json!("completed"));
    assert_eq!(logged(f, e), vec![qso("K1ABC", "FN42")]);

    // (b)
    let (t, feed) = watched().await;
    let (f, e) = (&t.f, t.e);
    transmit_own_period(f, e + 45_000).await;
    let slot_check = run_of(f).await["slot_check"].clone();
    let halt_state = f.read("contact").await["transmit"]["halt_state"].clone();
    auto_off(f).await;
    rules_ended(f, &feed, &slot_check, 1).await;
    publish(f, e + 60_000, &[his("HB9BLA K1ABC -05")]);
    transmit_own_period(f, e + 75_000).await;
    assert_eq!(last_text(f).as_deref(), Some("K1ABC HB9BLA R-10"));
    publish(f, e + 90_000, &[his("HB9BLA K1ABC -05")]);
    let keys = f.keys();
    not_keyed_in(f, e + 105_000).await;
    assert_eq!(f.keys(), keys, "never a 3rd R-report");
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["transmit"]["last_disarm_cause"].clone(),
            c["transmit"]["halt_state"].clone()
        ),
        (json!("tx_watchdog"), halt_state)
    );
    assert_eq!(logged(f, e), vec![]);
}

// Proves: CL-081-01; TC-081-004 (c). With Auto on the run's exemption sends the R-report a 3rd time
// (past the limit 2, StrategyWatchdog); after the Auto off it is not sent again: Enable Tx goes off
// with cause tx_watchdog in the next due period. Red on the parent: the cause is the Auto off's
// disarm, not the Tx watchdog.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_081_004_c_a_message_past_the_limit_is_not_sent_again_after_the_auto_off() {
    let (t, feed) = watched().await;
    let (f, e) = (&t.f, t.e);
    for k in 0..3 {
        if k > 0 {
            publish(f, e + 30_000 + 30_000 * k, &[his("HB9BLA K1ABC -05")]);
        }
        transmit_own_period(f, e + 45_000 + 30_000 * k).await;
        assert_eq!(last_text(f).as_deref(), Some("K1ABC HB9BLA R-10"));
    }
    let slot_check = run_of(f).await["slot_check"].clone();
    auto_off(f).await;
    rules_ended(f, &feed, &slot_check, 0).await;
    publish(f, e + 120_000, &[his("HB9BLA K1ABC -05")]);
    let keys = f.keys();
    not_keyed_in(f, e + 135_000).await;
    assert_eq!(f.keys(), keys, "not sent again");
    assert_eq!(
        f.read("contact").await["transmit"]["last_disarm_cause"],
        "tx_watchdog"
    );
    assert_eq!(logged(f, e), vec![]);
}

/// TC-081-005: Auto off in the started QSO and the R-report keyed once after it: the QSO finishing.
async fn finishing() -> Station81 {
    let t = new_calls_answered(None).await;
    let (f, e) = (&t.f, t.e);
    auto_off(f).await;
    transmit_own_period(f, e + 45_000).await;
    assert_eq!(last_text(f).as_deref(), Some("K1ABC HB9BLA R-10"));
    assert_eq!(contact(f).await.2, json!("armed"), "finishing");
    t
}

// Proves: CL-081-01; TC-081-005 (a), (b), (c). What still ends a finishing QSO at once: (a) HALT 2 s
// into our next R-report: the transmission stops and the contact is cancelled (the finishing guard),
// nothing is keyed after it and nothing logged, also after his RR73; (b) Abort
// QSO likewise, the contact cancelled, no halt; (c) a double-click of W1AW calling my call replaces
// K1ABC's contact and calls W1AW; K1ABC is never logged. Red on the parent: the QSO has already ended
// at the Auto off.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_081_005_halt_abort_and_a_double_click_end_a_finishing_qso_at_once() {
    // (a)
    let t = finishing().await;
    let (f, e) = (&t.f, t.e);
    let on = on_the_air(f, e + 75_000).await;
    halt(f).await;
    let service = &f.state.recording.transmit.get().unwrap().service;
    assert!(!service.view().transmitting, "the transmission stopped");
    let (off, keyed) = *f.bench.keys.lock().unwrap().last().unwrap();
    assert!(
        !keyed && off - on < 12_640,
        "stopped {} ms after the key-on",
        off - on
    );
    assert_eq!(
        f.read("contact").await["transmit"]["last_disarm_cause"],
        "halt"
    );
    // StartedQso "Still at once": Enable Tx off and the contact cancelled at the step of the HALT.
    assert_eq!(
        contact(f).await,
        (Value::Null, json!("cancelled"), json!("disarmed"))
    );
    publish(f, e + 90_000, &[his("HB9BLA K1ABC RR73")]);
    silent_through(f, e + 105_000).await;
    assert_eq!(
        contact(f).await,
        (Value::Null, json!("cancelled"), json!("disarmed")),
        "his RR73 changes nothing"
    );
    assert_eq!(logged(f, e), vec![]);

    // (b)
    let t = finishing().await;
    let (f, e) = (&t.f, t.e);
    let halt_state = f.read("contact").await["transmit"]["halt_state"].clone();
    let on = on_the_air(f, e + 75_000).await;
    browser_ok(f, "abort", json!({})).await;
    f.tick();
    let service = &f.state.recording.transmit.get().unwrap().service;
    assert!(!service.view().transmitting, "the transmission stopped now");
    let (off, keyed) = *f.bench.keys.lock().unwrap().last().unwrap();
    assert!(
        !keyed && off - on < 12_640,
        "stopped {} ms after the key-on",
        off - on
    );
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["contact"]["state"].clone(),
            c["transmit"]["arm_state"].clone(),
            c["transmit"]["halt_state"].clone()
        ),
        (json!("cancelled"), json!("disarmed"), halt_state)
    );
    publish(f, e + 90_000, &[his("HB9BLA K1ABC RR73")]);
    silent_through(f, e + 105_000).await;
    assert_eq!(logged(f, e), vec![]);

    // (c)
    let t = finishing().await;
    let (f, e) = (&t.f, t.e);
    publish(f, e + 60_000, &[("HB9BLA W1AW FN31", 900.0, Some(-12.0))]);
    browser_ok(
        f,
        "select_row",
        json!({"row":live_row(f, "HB9BLA W1AW FN31"),"replace":true}),
    )
    .await;
    let safety = f.read("contact").await["transmit"]["safety_revision"].clone();
    browser_ok(
        f,
        "enable_tx",
        json!({"enabled":true,"safety_revision":safety}),
    )
    .await;
    assert_eq!(
        contact(f).await,
        (json!("W1AW"), json!("report"), json!("armed"))
    );
    transmit_own_period(f, e + 75_000).await;
    assert_eq!(last_text(f).as_deref(), Some("W1AW HB9BLA -12"));
    publish(f, e + 90_000, &[his("HB9BLA K1ABC RR73")]);
    f.tick();
    assert_eq!(contact(f).await.0, json!("W1AW"));
    assert_eq!(logged(f, e), vec![]);
}

/// Enable Tx off and the contact cancelled at the next station step, nothing keyed after it and
/// nothing logged.
async fn ended_at_once(t: &Station81) {
    let (f, e) = (&t.f, t.e);
    f.tick();
    assert_eq!(
        contact(f).await,
        (Value::Null, json!("cancelled"), json!("disarmed"))
    );
    publish(f, e + 60_000, &[his("HB9BLA K1ABC RR73")]);
    silent_through(f, e + 75_000).await;
    assert_eq!(logged(f, e), vec![]);
}

// Proves: CL-081-01; TC-081-005 (d), (e), (f). After the run's end the finishing guard still ends the
// QSO at once on (d) the radio's dial to 7.074 MHz, (e) the operating mode to FT4 and (f) the browser
// grant revoked. Red on the parent: the QSO has already ended at the Auto off.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_081_005_band_mode_and_grant_end_a_finishing_qso_at_once() {
    // (d)
    let t = finishing().await;
    retune(&t.f, &t.peer, 7_074_000);
    ended_at_once(&t).await;

    // (e)
    let t = finishing().await;
    t.f.state.recording.fixture_live_job("ft4");
    ended_at_once(&t).await;

    // (f)
    let t = finishing().await;
    {
        let mut store = t.f.state.store.lock().unwrap();
        let mut owner = t.f.state.authorization.lock().unwrap();
        owner
            .as_mut()
            .unwrap()
            .authority
            .revoke(&mut store, &t.f.gid, &profile::new_uuid().unwrap(), false)
            .unwrap();
    }
    ended_at_once(&t).await;
}

// Proves: CL-081-01; TC-081-005 (g). A safety edit after the run's end: Enable Tx off with cause
// authority_changed in the transmit owner, and the finishing guard cancels the contact (the edit
// makes the run's grant no longer current); nothing keyed after it and nothing logged. Red on the
// parent: the QSO has already ended at the Auto off; red without the guard's grant check: the contact
// stays in roger_report.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_081_005_g_a_safety_edit_ends_a_finishing_qso_at_once() {
    // (g) A safety edit: the transmit owner's context takes the new safety revision (the hardware
    // double's seam stands for it) and disarms with cause authority_changed; the saved changed
    // control is reconciled into the authorization (a new scope), so the run's grant is no longer
    // current and the finishing guard cancels the contact.
    let t = finishing().await;
    let f = &t.f;
    f.bench.safety_edits.fetch_add(1, Ordering::SeqCst);
    let service = &f.state.recording.transmit.get().unwrap().service;
    let deadline = Instant::now() + Duration::from_secs(5);
    while service.view().arm_state == wstx_rust::transmit::service::ArmState::Armed {
        assert!(Instant::now() < deadline, "{:?}", service.view());
        f.tick();
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    assert_eq!(
        f.read("contact").await["transmit"]["last_disarm_cause"],
        "authority_changed"
    );
    {
        let mut store = f.state.store.lock().unwrap();
        let mut settings = store.document.settings();
        settings.control = profile::Control {
            mode: "cat".into(),
            endpoint: Some("icom7300://COM251".into()),
            ptt: "cat".into(),
        };
        store.save(settings).unwrap();
        f.state
            .authorization
            .lock()
            .unwrap()
            .as_mut()
            .unwrap()
            .authority
            .reconcile_control(&mut store)
            .unwrap();
    }
    ended_at_once(&t).await;
    assert_eq!(
        f.read("contact").await["transmit"]["last_disarm_cause"],
        "authority_changed"
    );
}

// Proves: CL-081-01; TC-081-005 (h), a regression guard (green on the parent). With Auto on and the run
// still on, the run's own leaving ends a started QSO at once: K1ABC silent after his report for 4
// repetitions (no spot) is left {K1ABC, repetitions} at the 4th, disarmed and cancelled, the run
// waiting.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_081_005_h_the_runs_leaving_ends_a_started_qso_at_once() {
    let t = new_calls_answered(None).await;
    let (f, e) = (&t.f, t.e);
    for k in 2..=4 {
        publish(f, rep(e, k), &[]);
        assert_eq!(contact(f).await.2, json!("armed"), "repetition {}", k - 1);
    }
    publish(f, rep(e, 5), &[]);
    assert_eq!(
        contact(f).await,
        (Value::Null, json!("cancelled"), json!("disarmed"))
    );
    let run = run_of(f).await;
    assert_eq!(
        (run["state"].clone(), run["left"].clone()),
        (
            json!("waiting"),
            json!({"call":"K1ABC","reason":"repetitions"})
        )
    );
}
