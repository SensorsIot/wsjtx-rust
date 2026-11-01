use super::*;
use crate::receive_http_tests::Input;
use axum::http::StatusCode;

const PROFILE: &str = "00000000-0000-4000-8000-000000000001";

struct Dir(PathBuf);
impl Dir {
    fn new() -> Self {
        let path =
            std::env::temp_dir().join(format!("wstx-startup-{}", profile::new_uuid().unwrap()));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
    fn open(&self) -> Arc<Recording> {
        Recording::open(&self.0, PROFILE.into(), profile::new_uuid().unwrap())
    }
    fn file(&self) -> Value {
        serde_json::from_slice(&fs::read(self.0.join(FILE)).unwrap()).unwrap()
    }
    fn write(&self, value: &Value) {
        fs::write(self.0.join(FILE), serde_json::to_vec(value).unwrap()).unwrap();
    }
}
impl Drop for Dir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn inject(r: &Recording) {
    r.resources.lock().unwrap().live_input = Some(Box::new(Input::queued().0));
}
fn resume(r: &Arc<Recording>, cat: bool, wait: Duration) -> Value {
    r.resume_receive(Some("profile-input".into()), cat, wait)
        .unwrap()
        .join()
        .unwrap();
    r.startup_view()
}
fn stored(off: bool, mode: &str, band: Option<&str>) -> Value {
    json!({"schema_version":1,"profile_id":PROFILE,"monitor_off_at_startup":off,
        "last_receive":{"mode":mode,"band":band,"input_device":"stored-input"}})
}
fn stop(r: &Recording) {
    let v = r.receive_snapshot();
    r.receive_stop(
        &r.profile,
        &r.boot,
        v["generation"].as_u64().unwrap(),
        v["job"]["id"].as_str().unwrap(),
    )
    .unwrap();
}

// Proves: CL-045-01; TC-045-001. Start (direct and band selection) persists mode, band and audio
// input next to profile.json; Monitor-off persists; operator Stop clears the choice.
#[test]
fn startup_choice_round_trips_and_stop_clears() {
    let dir = Dir::new();
    let r = dir.open();
    assert!(!dir.0.join(FILE).exists());
    inject(&r);
    r.receive_start(&r.profile, &r.boot, 0, 0, "first-input".into(), "ft8")
        .unwrap();
    assert_eq!(
        dir.file(),
        json!({"schema_version":1,"profile_id":PROFILE,"monitor_off_at_startup":false,
            "last_receive":{"mode":"ft8","band":null,"input_device":"first-input"}})
    );
    inject(&r);
    let s = r.state.lock().unwrap();
    let intent = selection::Intent {
        command_id: profile::new_uuid().unwrap(),
        profile_id: r.profile.clone(),
        boot_id: r.boot.clone(),
        profile_revision: s.operating.profile_revision,
        generation: s.generation,
        revision: s.operating.revision,
        action: "band",
        mode: Some("ft4"),
        band: Some("40m".into()),
    };
    drop(s);
    r.selection_begin(intent, Some("band-input".into()), false)
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(2);
    while r.selection_snapshot(false).unwrap()["operation"]["result"] == "pending" {
        assert!(Instant::now() < deadline);
        std::thread::sleep(Duration::from_millis(1));
    }
    assert_eq!(
        dir.file()["last_receive"],
        json!({"mode":"ft4","band":"40m","input_device":"band-input"})
    );
    r.set_monitor_off(&r.profile, &r.boot, true).unwrap();
    let reopened = dir.open();
    let view = reopened.startup_view();
    assert_eq!(view["monitor_off_at_startup"], true);
    assert_eq!(
        view["last_receive"],
        json!({"mode":"ft4","band":"40m","input_device":"band-input"})
    );
    assert_eq!(view["storage_error"], Value::Null);
    stop(&r);
    assert_eq!(
        dir.file(),
        json!({"schema_version":1,"profile_id":PROFILE,"monitor_off_at_startup":true,
            "last_receive":null})
    );
    assert_eq!(dir.open().startup_view()["last_receive"], Value::Null);
}

// Proves: CL-045-01; TC-045-001. A foreign, malformed, oversize or out-of-domain file resumes
// nothing, reads as the defaults and is reported, never trusted.
#[test]
fn startup_file_invalid_or_foreign_is_ignored() {
    let mut extra = stored(true, "ft8", Some("20m"));
    extra["unexpected"] = json!(1);
    let mut foreign = stored(true, "ft8", Some("20m"));
    foreign["profile_id"] = json!("00000000-0000-4000-8000-000000000002");
    let mut schema = stored(true, "ft8", Some("20m"));
    schema["schema_version"] = json!(2);
    let mut device = stored(true, "ft8", Some("20m"));
    device["last_receive"]["input_device"] = json!("");
    let mut oversize = serde_json::to_vec(&stored(true, "ft8", Some("20m"))).unwrap();
    oversize.extend(std::iter::repeat_n(b' ', 1024));
    let cases: Vec<Vec<u8>> = vec![
        serde_json::to_vec(&foreign).unwrap(),
        serde_json::to_vec(&stored(true, "jt65", None)).unwrap(),
        serde_json::to_vec(&stored(true, "ft8", Some("2m"))).unwrap(),
        serde_json::to_vec(&extra).unwrap(),
        serde_json::to_vec(&schema).unwrap(),
        serde_json::to_vec(&device).unwrap(),
        oversize,
        b"{".to_vec(),
    ];
    for bytes in cases {
        let dir = Dir::new();
        fs::write(dir.0.join(FILE), &bytes).unwrap();
        let r = dir.open();
        inject(&r);
        let view = resume(&r, false, Duration::ZERO);
        assert_eq!(view["storage_error"], "invalid_startup");
        assert_eq!(view["monitor_off_at_startup"], false);
        assert_eq!(view["last_receive"], Value::Null);
        assert_eq!(view["resume"]["state"], "idle");
        assert_eq!(r.receive_snapshot()["job"], Value::Null);
    }
}

// Proves: CL-045-02; TC-045-001. The stored FT4 20 m choice restarts as the band button would:
// FT4 receive on the profile's audio input, nominal dial 14 080 000 Hz (canonical
// FT4 20 m preferred frequency), with no operator request.
#[test]
fn startup_resume_starts_stored_band_and_mode() {
    let dir = Dir::new();
    dir.write(&stored(false, "ft4", Some("20m")));
    let r = dir.open();
    inject(&r);
    let view = resume(&r, false, Duration::ZERO);
    assert_eq!(view["resume"], json!({"state":"started","error":null}));
    let selection = r.selection_snapshot(false).unwrap();
    assert_eq!(selection["selection"]["band"], "20m");
    assert_eq!(selection["selection"]["mode"], "ft4");
    assert_eq!(selection["selection"]["nominal_hz"], 14080000);
    let receive = r.receive_snapshot();
    assert_eq!(receive["job"]["mode"], "ft4");
    assert_eq!(receive["job"]["state"], "running");
    assert_eq!(receive["audio"]["device_id"], "profile-input");
}

// Proves: CL-045-02; TC-045-001. Monitor off at startup, a stopped receive (nothing stored) and an
// operator start that came first each leave the resume without effect.
#[test]
fn startup_resume_off_or_stopped_stays_off() {
    let dir = Dir::new();
    dir.write(&stored(true, "ft8", Some("20m")));
    let r = dir.open();
    inject(&r);
    assert_eq!(resume(&r, false, Duration::ZERO)["resume"]["state"], "off");
    assert_eq!(r.receive_snapshot()["job"], Value::Null);
    assert_eq!(r.receive_snapshot()["generation"], 0);

    let dir = Dir::new();
    let r = dir.open();
    inject(&r);
    r.receive_start(&r.profile, &r.boot, 0, 0, "first-input".into(), "ft8")
        .unwrap();
    stop(&r);
    let restarted = dir.open();
    inject(&restarted);
    assert_eq!(
        resume(&restarted, false, Duration::ZERO)["resume"]["state"],
        "idle"
    );
    assert_eq!(restarted.receive_snapshot()["job"], Value::Null);

    let dir = Dir::new();
    dir.write(&stored(false, "ft4", Some("20m")));
    let r = dir.open();
    inject(&r);
    let operator = r
        .receive_start(&r.profile, &r.boot, 0, 0, "operator-input".into(), "ft8")
        .unwrap();
    inject(&r);
    assert_eq!(
        resume(&r, false, Duration::ZERO)["resume"]["state"],
        "skipped"
    );
    let receive = r.receive_snapshot();
    assert_eq!(receive["job"]["id"], operator["job"]["id"]);
    assert_eq!(receive["job"]["mode"], "ft8");
}

// Proves: CL-045-02; TC-045-001. Transient refusals while CAT comes up (radio not yet
// ready, the actor's poll holding its lease, a connection change between preflights)
// are retried within the wait: the resume still selects the stored band.
#[test]
fn startup_resume_retries_transient_selection_refusals() {
    let dir = Dir::new();
    dir.write(&stored(false, "ft8", Some("40m")));
    let r = dir.open();
    r.resources.lock().unwrap().resume_refusals =
        ["radio_unavailable", "busy", "state_conflict"].into();
    inject(&r);
    let view = resume(&r, false, Duration::from_secs(5));
    assert_eq!(view["resume"], json!({"state":"started","error":null}));
    assert!(r.resources.lock().unwrap().resume_refusals.is_empty());
    let selection = r.selection_snapshot(false).unwrap();
    assert_eq!(selection["selection"]["band"], "40m");
    assert_eq!(selection["selection"]["nominal_hz"], 7074000);
    assert_eq!(r.receive_snapshot()["job"]["state"], "running");
}

// Proves: CL-045-02; TC-045-001. Configured CAT that never becomes ready within the wait still
// resumes receive on the stored mode (untuned), and keeps the stored band.
#[test]
fn startup_resume_cat_unavailable_falls_back_to_plain_receive() {
    let dir = Dir::new();
    dir.write(&stored(false, "ft8", Some("40m")));
    let r = dir.open();
    inject(&r);
    let view = resume(&r, true, Duration::from_millis(300));
    assert_eq!(
        view["resume"],
        json!({"state":"started_untuned","error":null})
    );
    let receive = r.receive_snapshot();
    assert_eq!(receive["job"]["mode"], "ft8");
    assert_eq!(receive["job"]["state"], "running");
    assert_eq!(
        r.selection_snapshot(false).unwrap()["selection"]["band"],
        Value::Null
    );
    assert_eq!(dir.file()["last_receive"]["band"], "40m");
}

// Proves: CL-045-01; TC-045-001. GET/POST /receive/startup through the station router, with the
// station's refusal codes and no change on a refused request.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn startup_http_view_and_monitor_off_update() {
    let f = crate::contact_http_tests::fixture("http://127.0.0.1:18451", false);
    let (status, view, _, _) = f.call("GET", "/receive/startup", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(view["monitor_off_at_startup"], false);
    assert_eq!(view["last_receive"], Value::Null);
    assert_eq!(view["profile_id"], f.id);
    let body =
        |off: bool| json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"monitor_off_at_startup":off});
    let (status, view, _, _) = f.call("POST", "/receive/startup", Some(body(true))).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(view["monitor_off_at_startup"], true);
    let file: Value = serde_json::from_slice(&fs::read(f.dir.join(FILE)).unwrap()).unwrap();
    assert_eq!(file["monitor_off_at_startup"], true);
    let mut wrong = body(false);
    wrong["profile_id"] = json!(profile::new_uuid().unwrap());
    let mut stale = body(false);
    stale["boot_id"] = json!(profile::new_uuid().unwrap());
    let mut extra = body(false);
    extra["band"] = json!("20m");
    let mut version = body(false);
    version["v"] = json!(2);
    let mut text = body(false);
    text["monitor_off_at_startup"] = json!("false");
    for (b, code, status) in [
        (wrong, "wrong_profile", StatusCode::FORBIDDEN),
        (stale, "state_conflict", StatusCode::CONFLICT),
        (extra, "invalid_request", StatusCode::BAD_REQUEST),
        (version, "unsupported_version", StatusCode::BAD_REQUEST),
        (text, "invalid_request", StatusCode::BAD_REQUEST),
    ] {
        let (got, v, _, _) = f.call("POST", "/receive/startup", Some(b)).await;
        assert_eq!((got, v["error"]["code"].as_str()), (status, Some(code)));
    }
    let (got, v, _, _) = f
        .raw(
            "POST",
            "/receive/startup",
            Some("http://evil.example"),
            Some(serde_json::to_vec(&body(false)).unwrap()),
            &[],
        )
        .await;
    assert_eq!(
        (got, v["error"]["code"].as_str()),
        (StatusCode::FORBIDDEN, Some("forbidden_origin"))
    );
    let (got, _, _, _) = f.call("GET", "/receive/startup?x=1", None).await;
    assert_eq!(got, StatusCode::BAD_REQUEST);
    let (_, view, _, _) = f.call("GET", "/receive/startup", None).await;
    assert_eq!(view["monitor_off_at_startup"], true);
    let _ = fs::remove_dir_all(&f.dir);
}

// Proves: CL-045-03; TC-045-001. A resume on a transmit-capable station (CAT PTT configured) leaves
// the transmit owner disarmed and never exchanges PTT.
#[test]
fn startup_resume_never_arms_or_keys() {
    // The manual band path (a selection) and the configured-CAT fallback path.
    for (port, cat, state) in [(18452, false, "started"), (18453, true, "started_untuned")] {
        let f = crate::contact_http_tests::fixture(&format!("http://127.0.0.1:{port}"), true);
        let r = f.state.recording.clone();
        let t = r.transmit.get().unwrap().clone();
        let observed = || {
            let v = crate::transmit_http::view_json(&r, &t.service.view());
            json!([v["transmit"], v["ptt"], v["transmitting"], v["outcomes"]])
        };
        let before = observed();
        assert_ne!(before[0]["arm_state"], "armed");
        r.remember_receive("ft8", Some("20m"), "stored-input");
        inject(&r);
        assert_eq!(
            resume(&r, cat, Duration::from_millis(100))["resume"]["state"],
            state
        );
        assert_eq!(r.receive_snapshot()["job"]["state"], "running");
        std::thread::sleep(Duration::from_millis(200));
        assert_eq!(observed(), before);
        assert!(f.bench.keys.lock().unwrap().is_empty());
        stop(&r);
        let _ = fs::remove_dir_all(&f.dir);
    }
}
