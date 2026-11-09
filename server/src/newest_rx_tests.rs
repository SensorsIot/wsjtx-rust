// #89 WstxStrategy::FreeTxSlot Due and Waiting for the newest period, StrategyRun Decision timing
// (TC-089-002, TC-089-003, TC-089-004; TC-089-001 (c) at the station). Oracle: the operator's rules
// of 2026-11-09 ("Count once decoded"; "decision always fastest when needed info is available"):
// my newest Rx period counts once its complete publication is published, also while in progress;
// a contest Run's CQ decided in waiting without a fresh publication waits for that publication, at
// the latest until the period in progress ends. Every slot below is a hand computation written
// above its test, on flat rows of 30 dB (floor 30.65, every slot -0.65, free, value 0) unless a
// band is named: a candidate f is closed by a station decoded at d in a counted period when
// |f - d| is below 50 Hz, and of equal values the current Tx is kept, else the nearer, then the
// lower. The actual station router, contact engine and #9 transmit owner on the recording
// hardware double (virtual UTC; no audio, PTT or radio).
use super::*;

/// A report between two other stations (never a candidate, never a caller of mine).
fn other_at(hz: f64) -> (&'static str, f64, Option<f64>) {
    ("G4AAA W1XYZ -10", hz, Some(-10.0))
}
const HA7NB: (&str, f64, Option<f64>) = ("CQ HA7NB JN97", 1001.0, Some(-12.0));
const M7HNI: (&str, f64, Option<f64>) = ("G4AAA M7HNI -10", 2340.0, Some(-8.0));

/// TC-089-002 (the 12:24:29 reproduction, #66 comment 6740465378): a station on 20 m FT8, Hold Tx
/// off, Tx 2340; my odd periods P - 120 .. P - 30 s and P = e + 15 s received flat 30 (one row
/// each); a station decoded at 2290 only in P - 120 s; `start` starts the run (a strategy run or a
/// pounce on HA7NB); then the clock at P + 14.1 s and P's complete publication: HA7NB's CQ at
/// 1001 Hz and M7HNI decoded at 2340 Hz.
async fn newest_p(start: impl AsyncFnOnce(&Mcp)) -> (Mcp, crate::automation::ClientSession) {
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let client = f.state.recording.clients.session();
    hold_off(&f).await;
    set_tx(&f, 2340).await;
    let p = e + 15_000;
    for back in [120_000, 90_000, 60_000, 30_000] {
        wf_row(&f, p - back, 30, &[], false);
    }
    decoded_in(&f, p - 120_000, &[2290.0]);
    wf_row(&f, p, 30, &[], false);
    start(&f).await;
    ended(&f, p + 14_100);
    publish(&f, p, &[HA7NB, M7HNI]);
    (f, client)
}

// Proves: CL-039-09; TC-089-002 (Hold Tx off selection, pounce, the 5th older period). The
// selection of HA7NB on P's complete publication at P + 14.1 s (P in progress) counts P: the
// candidates clear of HA7NB (1001, the called station, also decoded in P) and of M7HNI decoded at
// 2340 in P (2300..2380 closed), all at value 0; the current Tx 2340 is closed, the nearest free
// slots 2290 and 2390 are both 50 Hz away: the lower, 2290; Rx = Tx = 2290, tx_slot {2290, 0,
// unknown}, not 2340. The station decoded at 2290 only in P - 120 s (the 5th older odd period once
// P counts) closes nothing, else 2390. A pounce on HA7NB chooses the same. Red on the parent: P not
// counted, Tx stays on 2340 (with M7HNI on it).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_089_002_a_selection_on_the_newest_publication_counts_its_stations() {
    let expected = (
        json!(2290),
        json!(2290),
        json!({"hz":2290,"power_db":0,"his_end":"unknown"}),
    );
    let (f, _client) = newest_p(async |f: &Mcp| select(f, config(Some("Test calls"))).await).await;
    assert_eq!(contact(&f).await.0, json!("HA7NB"), "the strategy run");
    assert_eq!(frequencies(&f).await, expected, "the strategy run");
    let (f, _client) = newest_p(async |f: &Mcp| {
        assert_eq!(pounce(f, "HA7NB", 5).await.status, StatusCode::ACCEPTED);
    })
    .await;
    assert_eq!(contact(&f).await.0, json!("HA7NB"), "the pounce");
    assert_eq!(frequencies(&f).await, expected, "the pounce");
}

// Proves: CL-039-09; TC-089-002 (Hold Tx on slot check). Hold Tx on (as a fresh station), Tx 1500:
// K1ABC (CQ at 1800 in the even e) selected, Rx 1800, Tx stays 1500; my even periods e - 90 ..
// e - 30 s flat 30. K1ABC silent: at rep 1 (e + 30 s) a station decoded on my Tx 1500 only in that
// period, its row flat 30, published complete at e + 44.1 s (in progress). The slot check counts it:
// 1460..1540 closed, Tx alone to the nearest free slot clear of the station and of Rx (1800): 1450
// and 1550 both 50 Hz away, the lower 1450; Rx stays 1800. Red on the parent: rep 1 not counted, Tx
// stays 1500.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_089_002_a_held_slot_check_counts_the_newest_period() {
    let rows = |f: &Mcp, e: i64| {
        for back in [90_000, 60_000, 30_000] {
            wf_row(f, e - back, 30, &[], false);
        }
    };
    let t = held_run_with("ft8", None, rows, &[K1ABC_CQ]).await;
    let (f, e) = (&t.f, t.e);
    assert_eq!(contact(f).await.0, json!("K1ABC"));
    assert_eq!(rx_tx(f).await, (json!(1800), json!(1500)));
    transmit_own_period(f, e + 15_000).await;
    wf_row(f, rep(e, 1), 30, &[], false);
    ended(f, rep(e, 1) + 14_100);
    publish(f, rep(e, 1), &[other_at(1500.0)]);
    assert_eq!(rx_tx(f).await, (json!(1800), json!(1450)));
    assert_eq!(
        run_of(f).await["slot_check"],
        json!({"repetitions":1,"hears_us":false,"hz":1450})
    );
}

// Proves: CL-065-01; TC-089-003 (a). In a QSO (my own CQ, Tx even, so my Rx parity odd), my periods
// e - 60 .. e - 15 s flat 30 and the odd P = e + 15 s flat 30 (its row so far). Enable Tx on at
// e + 16 s: a build counting e - 15 and e - 45 s (2), [[300, 2700]]. P's complete publication at
// P + 14.1 s with a station decoded at 1200 Hz in P: one build at once, at_utc_ms P + 14.1 s, P
// counted (3), 1160..1240 closed: [[300, 1200], [1250, 2700]]. Red on the parent: no build at P's
// publication, the e + 16 s value with 1200 open until the next period start.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_089_003_the_marks_count_the_publication_of_the_period_in_progress_in_a_qso() {
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    for back in [60_000, 45_000, 30_000, 15_000] {
        wf_row(&f, e - back, 30, &[], false);
    }
    let p = e + 15_000;
    wf_row(&f, p, 30, &[], false);
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
    assert_eq!(
        build_of(&f).await,
        json!({"at_utc_ms":e + 16_000,"mode":"ft8","rx_parity":"odd","qso":true,"periods":2,
            "open":[[300, 2700]]})
    );
    decoded_in(&f, p, &[1200.0]);
    step_at(&f, p + 14_100);
    assert_eq!(
        build_of(&f).await,
        json!({"at_utc_ms":p + 14_100,"mode":"ft8","rx_parity":"odd","qso":true,"periods":3,
            "open":[[300, 1200], [1250, 2700]]}),
        "P's publication: at once, P counted"
    );
}

// Proves: CL-065-01, CL-039-09; TC-089-003 (b), (c), (d); TC-089-001 (c). Listening with no run, my
// periods e - 60 .. e - 15 s and the odd P = e + 15 s flat 30. At P's start the build judges odd:
// e - 15 and e - 45 s (2), [[300, 2700]]. (c) A partial publication of P with a station at 1200 Hz
// at P + 13 s makes P not due: no build (at_utc_ms stays P). (d) A complete publication of the
// even e (the other parity, ended) with a station at 1800 Hz: the judged odd periods unchanged, no
// build. (b) P's complete publication at P + 14.1 s with the station at 1200: a build at once,
// rx_parity odd, P counted (3), [[300, 1200], [1250, 2700]]. At the next period start e + 30 s the
// parity flips as before: even, e - 30 and e - 60 s (2), the odd decode closes nothing:
// [[300, 2700]]. Red on the parent: no build at P's publication.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_089_003_listening_counts_the_period_in_progress_once_completely_published() {
    let f = station(true).await;
    f.state.recording.fixture_band("20m");
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    let _client = f.state.recording.clients.session();
    for back in [60_000, 45_000, 30_000, 15_000] {
        wf_row(&f, e - back, 30, &[], false);
    }
    let p = e + 15_000;
    wf_row(&f, p, 30, &[], false);
    step_at(&f, p);
    let start = listening(p, "odd", 2, json!([[300, 2700]]));
    assert_eq!(build_of(&f).await, start);
    f.state.recording.fixture_publish_partial(
        &period_text(p),
        vec![record("G4AAA W1XYZ -10", 1200.0, Some(-10.0))],
    );
    step_at(&f, p + 13_000);
    assert_eq!(build_of(&f).await, start, "(c) a partial publication");
    decoded_in(&f, e, &[1800.0]);
    step_at(&f, p + 13_500);
    assert_eq!(build_of(&f).await, start, "(d) the other parity");
    decoded_in(&f, p, &[1200.0]);
    step_at(&f, p + 14_100);
    assert_eq!(
        build_of(&f).await,
        listening(p + 14_100, "odd", 3, json!([[300, 1200], [1250, 2700]])),
        "(b) P's complete publication"
    );
    step_at(&f, e + 30_000);
    assert_eq!(
        build_of(&f).await,
        listening(e + 30_000, "even", 2, json!([[300, 2700]])),
        "(b) the next period start"
    );
}

/// TC-089-004: a contest Run (WW Digi on 20 m, the period in force, W1DUP a dupe), Hold Tx `hold`,
/// Tx 1500, CQ Tx odd (my Rx parity even); my even periods e - 90 .. e - 30 s flat 30 and P = e
/// flat 30 (or with 1500..1550 at 42: `loud`), one row each; `before` runs before Auto on (it sets
/// the clock); Auto on, then one station step.
async fn run_cq(hold: bool, loud: bool, before: impl FnOnce(&Mcp, i64)) -> Leaving {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    for back in [90_000, 60_000, 30_000] {
        wf_row(&f, e - back, 30, &[], false);
    }
    let band: &[(u32, u32, u8)] = if loud { &[(1500, 1550, 42)] } else { &[] };
    wf_row(&f, e, 30, band, false);
    let client = f.state.recording.clients.session();
    if !hold {
        hold_off(&f).await;
    }
    f.state.recording.fixture_band("20m");
    import_adi(&f, &logged_before("W1DUP", "EM12", e));
    browser_ok(&f, "set_activity", json!({"activity":"ww_digi"})).await;
    let feed = attach_feed(&f);
    before(&f, e);
    select(&f, contest_config(e, "run", -1)).await;
    f.tick();
    Leaving {
        f,
        e,
        feed,
        client: Some(client),
    }
}
/// The run waits: no decision (tx_slot null), no enable_tx (disarmed), Tx where it was.
async fn waits(f: &Mcp, tx: u64, name: &str) {
    let run = run_of(f).await;
    assert_eq!(
        (&run["state"], &run["tx_slot"]),
        (&json!("waiting"), &Value::Null),
        "{name}"
    );
    assert_eq!(contact(f).await.2, json!("disarmed"), "{name}");
    assert_eq!(rx_tx(f).await.1, json!(tx), "{name}");
}
/// The run's CQ decided on `hz` (Hold Tx off: Rx = Tx, value 0) and armed.
async fn calls_from(f: &Mcp, hz: u64, name: &str) {
    assert_eq!(run_of(f).await["state"], "calling_cq", "{name}");
    assert_eq!(contact(f).await.2, json!("armed"), "{name}");
    assert_eq!(
        frequencies(f).await,
        (
            json!(hz),
            json!(hz),
            json!({"hz":hz,"power_db":0,"his_end":"unknown"})
        ),
        "{name}"
    );
}

// Proves: CL-039-09, CL-039-05; TC-089-004 (a), (b), (e). (a) Auto on at P + 5 s, P = e my newest
// Rx period, in progress and unpublished: no decision and no enable_tx at P + 8 and P + 14 s; P's
// complete publication at P + 14.1 s with a station decoded at 1500 (the current Tx) in P: in that
// station step the CQ's slot with P counted, 1460..1540 closed, the nearest free 1450 (the lower of
// 1450 and 1550), enable_tx, the CQ keyed at the next period start P + 15 s. (b) No publication of
// P, its row loud at 1500..1550 (42 over 30: slot 1500 rise 11.35, value 11; 1460 and 1540 hold 4
// of the 18 band bins, (4 x 42 + 13 x 30) / 17 - 30.65 = 2.17, 2; 1450 and 1550 none, 0): waiting at
// P + 14.9 s, decided at P + 15.0 s with P counted by its levels: 1450. (e) Auto on at P + 20 s
// (the odd period in progress) with P's complete publication already there: decided and armed at
// once, 1450. Red on the parent: (a) and (b) the CQ at P + 5 s from 1500 (P not counted).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_089_004_a_run_cq_waits_for_the_newest_rx_period() {
    let t = run_cq(false, false, |f, e| ended(f, e + 5_000)).await;
    let (f, e) = (&t.f, t.e);
    waits(f, 1500, "(a) at P + 5 s").await;
    for at in [8_000, 14_000] {
        ended(f, e + at);
        f.tick();
        waits(f, 1500, "(a)").await;
    }
    ended(f, e + 14_100);
    publish(f, e, &[other_at(1500.0)]);
    calls_from(f, 1450, "(a) on P's publication").await;
    // Keyed at P + 15 s: the transmission bound to that period runs to its end.
    transmit_own_period(f, e + 15_000).await;

    let t = run_cq(false, true, |f, e| ended(f, e + 5_000)).await;
    let (f, e) = (&t.f, t.e);
    waits(f, 1500, "(b) at P + 5 s").await;
    ended(f, e + 14_900);
    f.tick();
    waits(f, 1500, "(b) at P + 14.9 s").await;
    ended(f, e + 15_000);
    f.tick();
    calls_from(f, 1450, "(b) at P + 15.0 s").await;

    let t = run_cq(false, false, |f, e| {
        ended(f, e + 14_100);
        publish(f, e, &[other_at(1500.0)]);
        ended(f, e + 20_000);
    })
    .await;
    calls_from(&t.f, 1450, "(e) already published").await;
}

// Proves: CL-039-05; TC-089-004 (c), (d), (f). (c) Hold Tx on: the CQ takes no decision (on the held
// Tx 1500, D16) and does not wait: armed at P + 5 s. (d) Auto off, and separately Halt, at P + 8 s
// during the wait: stopped, and at P's publication no decision and no enable_tx. (f) Auto on again
// at P + 8 s during the wait: still waiting, and on P's publication one decision, 1450 as (a). Red on
// the parent: (d) and (f) the CQ at P + 5 s.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_089_004_hold_tx_stop_and_a_second_auto_on() {
    let t = run_cq(true, false, |f, e| ended(f, e + 5_000)).await;
    let f = &t.f;
    assert_eq!(run_of(f).await["state"], "calling_cq", "(c)");
    assert_eq!(contact(f).await.2, json!("armed"), "(c)");
    assert_eq!(rx_tx(f).await.1, json!(1500), "(c) the held Tx");

    for halted in [false, true] {
        let t = run_cq(false, false, |f, e| ended(f, e + 5_000)).await;
        let (f, e) = (&t.f, t.e);
        waits(f, 1500, "(d)").await;
        ended(f, e + 8_000);
        let reason = if halted {
            halt(f).await;
            "halted"
        } else {
            assert_eq!(auto(f, false, None).await.status, StatusCode::OK);
            f.tick();
            "stopped"
        };
        ended(f, e + 14_100);
        publish(f, e, &[other_at(1500.0)]);
        f.tick();
        assert_eq!(run_state(f).await, ("stopped".into(), json!(reason)), "(d)");
        let run = run_of(f).await;
        assert_eq!(run["tx_slot"], Value::Null, "(d) {reason}");
        assert_eq!(contact(f).await.2, json!("disarmed"), "(d) {reason}");
        assert_eq!(rx_tx(f).await.1, json!(1500), "(d) {reason}");
    }

    let t = run_cq(false, false, |f, e| ended(f, e + 5_000)).await;
    let (f, e) = (&t.f, t.e);
    waits(f, 1500, "(f)").await;
    ended(f, e + 8_000);
    assert_eq!(auto(f, true, Some(true)).await.status, StatusCode::OK);
    f.tick();
    waits(f, 1500, "(f) Auto on again").await;
    ended(f, e + 14_100);
    publish(f, e, &[other_at(1500.0)]);
    calls_from(f, 1450, "(f) one decision on P's publication").await;
}

// Proves: CL-039-09, CL-039-05; TC-089-004 (g). Hold Tx off; K1ABC's CQ decoded at 1800 Hz in the
// even e - 30 s (published before Auto on). Auto on at P + 1 s (P = e): waiting. The operator
// double-clicks K1ABC at P + 2 s: the run is manual (Rx = Tx = 1800 for his contact). Esc at P + 5 s
// gives him up: the run back to waiting, and no set_frequency and no enable_tx of the run until P's
// complete publication at P + 14.1 s with a station decoded on the current Tx 1800 in P; then the
// CQ's slot with P counted: 1760..1840 closed (also by K1ABC in e - 30 s), the nearest free 1750
// (the lower of 1750 and 1850). Red on the parent: the CQ at P + 5 s.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_089_004_after_esc_on_a_manual_contact_the_cq_waits() {
    let t = run_cq(false, false, |f, e| {
        publish(f, e - 30_000, &[("CQ K1ABC FN42", 1800.0, Some(-5.0))]);
    })
    .await;
    let (f, e) = (&t.f, t.e);
    waits(f, 1500, "Auto on at P + 1 s").await;
    ended(f, e + 2_000);
    browser_ok(
        f,
        "select_row",
        json!({"row":live_row(f, "CQ K1ABC FN42"),"replace":true,"directive_confirmed":true}),
    )
    .await;
    f.tick();
    assert_eq!(run_of(f).await["state"], "manual");
    let tx = rx_tx(f).await.1.as_u64().unwrap();
    assert_eq!(tx, 1800, "the contact's Tx");
    ended(f, e + 5_000);
    browser_ok(f, "abort", json!({})).await;
    f.tick();
    f.tick();
    f.tick();
    let run = run_of(f).await;
    assert_eq!(
        (&run["state"], &run["tx_slot"]),
        (&json!("waiting"), &Value::Null),
        "after Esc at P + 5 s"
    );
    assert_ne!(contact(f).await.1, json!("calling"), "after Esc");
    ended(f, e + 14_000);
    f.tick();
    assert_eq!(run_of(f).await["state"], "waiting", "at P + 14 s");
    assert_eq!(rx_tx(f).await.1, json!(tx), "no set_frequency");
    ended(f, e + 14_100);
    publish(f, e, &[other_at(1800.0)]);
    calls_from(f, 1750, "on P's publication").await;
}

// Proves: CL-039-05; TC-089-004 (g), the completed manual contact. Hold Tx off; K1ABC's RR73 to my
// call decoded at 1800 Hz in the even e - 30 s (published before Auto on). Auto on at e + 1 s:
// waiting. The operator double-clicks it at e + 2 s (Rx 1800, Tx stays 1500 for a caller) and
// enables Tx: the run is manual; my 73 goes
// out in my odd period e + 15 s and completes the contact at its end (about e + 28 s; a manual
// contact completes at the end of my own transmission, just before my next Rx period, so not at
// P + 5 s). The run is back to waiting with the newest period of its Rx parity, e, unpublished: no
// decision and no enable_tx of the run at e + 29.9 s; at e + 30 s, the end of the period in
// progress, it decides with what is due (e, e - 30, e - 60 and e - 90 s, all flat; K1ABC at 1800 in
// e - 30 s closes 1760..1840): the current Tx 1500 is free and kept, Rx = Tx = 1500, tx_slot {1500,
// 0}. Red on the parent: the CQ at the contact's end.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_089_004_after_a_completed_manual_contact_the_cq_waits() {
    const RR73: (&str, f64, Option<f64>) = ("HB9BLA K1ABC RR73", 1800.0, Some(-5.0));
    let t = run_cq(false, false, |f, e| publish(f, e - 30_000, &[RR73])).await;
    let (f, e) = (&t.f, t.e);
    waits(f, 1500, "Auto on at e + 1 s").await;
    ended(f, e + 2_000);
    browser_ok(
        f,
        "select_row",
        json!({"row":live_row(f, RR73.0),"replace":true,"directive_confirmed":true}),
    )
    .await;
    let safety = f.read("contact").await["transmit"]["safety_revision"].clone();
    browser_ok(
        f,
        "enable_tx",
        json!({"enabled":true,"safety_revision":safety}),
    )
    .await;
    f.tick();
    assert_eq!(run_of(f).await["state"], "manual");
    assert_eq!(
        rx_tx(f).await,
        (json!(1800), json!(1500)),
        "a caller: Tx stays"
    );
    transmit_own_period(f, e + 15_000).await;
    f.tick();
    assert_eq!(contact(f).await.1, json!("completed"));
    ended(f, e + 29_900);
    f.tick();
    let run = run_of(f).await;
    assert_eq!(
        (&run["state"], &run["tx_slot"]),
        (&json!("waiting"), &Value::Null),
        "at e + 29.9 s"
    );
    assert_eq!(contact(f).await.1, json!("completed"), "no CQ yet");
    ended(f, e + 30_000);
    f.tick();
    calls_from(f, 1500, "at e + 30 s").await;
}
