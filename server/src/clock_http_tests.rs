#![forbid(unsafe_code)]
// Proves: CL-043-01, CL-043-03, CL-009-05; TC-043-003. The saved clock source and
// GET/POST /clock on the actual router, GET /transmit carrying the source, and the
// actual station transmit owner admitting and timing transmit by the station clock.
use super::*;
use axum::body::Body;
use tower::ServiceExt;
use wstx_rust::transmit::clock::Monitor;

struct Station {
    router: Router,
    dir: std::path::PathBuf,
    id: String,
    boot: String,
    origin: String,
    recording: Arc<recording::Recording>,
}
impl Drop for Station {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}
fn directory() -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("wstx-clock-{}", profile::new_uuid().unwrap()));
    std::fs::create_dir(&dir).unwrap();
    dir
}
/// The actual router of a profile in `dir` (clock.json as left there), as main wires it.
fn station(dir: std::path::PathBuf) -> Station {
    let id = profile::new_uuid().unwrap();
    let boot = profile::new_uuid().unwrap();
    let doc = json!({"schema_version":1,"profile_id":id,"revision":0,"display_name":"Clock",
        "callsign":"HB9BLA","locator":"JN47AA","endpoint":{"bind":"127.0.0.1:18001","origin":null},"connection_type":"standard",
        "audio":{"input_device":null,"output_device":null},"control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}});
    std::fs::write(dir.join("profile.json"), serde_json::to_vec(&doc).unwrap()).unwrap();
    let (store, _) = profile::Store::open(&dir).unwrap();
    let recording = recording::Recording::open(&dir, id.clone(), boot.clone());
    let clock = clock_http::Clock::load(&dir, &id, Monitor::new());
    let _ = recording.clock.set(clock.clone());
    let _ = recording
        .transmit
        .set(transmit_http::Station::start(clock.station.clone()).unwrap());
    let origin = "http://127.0.0.1:18001".to_string();
    let app = App {
        origin: origin.clone(),
        profile: Some(Arc::new(ProfileState {
            store: Mutex::new(store),
            authorization: Mutex::new(None),
            boot: boot.clone(),
            recording: recording.clone(),
            logbook: Arc::new(crate::logbook::Logbook::open(&dir)),
        })),
        profile_id: Some(id.clone()),
        token: None,
        connections: Arc::new(Semaphore::new(16)),
        login_attempts: Arc::new(Mutex::new((Instant::now(), 0))),
    };
    Station {
        router: router(app),
        dir,
        id,
        boot,
        origin,
        recording,
    }
}
async fn call(
    s: &Station,
    method: &str,
    path: &str,
    origin: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut request = axum::http::Request::builder().method(method).uri(path);
    if let Some(origin) = origin {
        request = request.header(header::ORIGIN, origin);
    }
    let request = match body {
        Some(b) => request
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(serde_json::to_vec(&b).unwrap())),
        None => request.body(Body::empty()),
    }
    .unwrap();
    let response = s.router.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), 65536)
        .await
        .unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}
fn keys(v: &Value) -> Vec<&str> {
    let mut k: Vec<&str> = v.as_object().unwrap().keys().map(String::as_str).collect();
    k.sort();
    k
}

// Proves: TC-043-003.
#[test]
fn saved_source_reads_as_ntp_unless_valid() {
    let id = "00000000-0000-4000-8000-0000000000c1";
    let source = |text: Option<&str>| {
        let dir = directory();
        if let Some(text) = text {
            std::fs::write(dir.join(clock_http::FILE), text).unwrap();
        }
        let c = clock_http::Clock::load(&dir, id, Monitor::new());
        let _ = std::fs::remove_dir_all(&dir);
        let error = *c.storage_error.lock().unwrap();
        (c.station.source().name(), error)
    };
    assert_eq!(source(None), ("ntp", None), "missing: the default");
    let good = |s: &str| format!(r#"{{"schema_version":1,"profile_id":"{id}","source":"{s}"}}"#);
    assert_eq!(source(Some(&good("air"))), ("air", None));
    assert_eq!(source(Some(&good("both"))), ("both", None));
    for bad in [
        good("gps"),
        good("AIR"),
        r#"{"schema_version":1,"profile_id":"00000000-0000-4000-8000-0000000000c2","source":"air"}"#.into(),
        format!(r#"{{"schema_version":2,"profile_id":"{id}","source":"air"}}"#),
        format!(r#"{{"schema_version":1,"profile_id":"{id}","source":"air","extra":1}}"#),
        format!(r#"{{"schema_version":1,"profile_id":"{id}","source":"air"}}{}"#, " ".repeat(1024)),
        "{".into(),
    ] {
        assert_eq!(source(Some(&bad)), ("ntp", Some("invalid_clock")), "{bad}");
    }
}

// Proves: TC-043-003.
#[tokio::test]
async fn clock_wire_saves_the_source_and_reports_both_measurements() {
    let s = station(directory());
    let (status, view) = call(&s, "GET", "/clock", None, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        keys(&view),
        [
            "air",
            "basis",
            "boot_id",
            "correction_ms",
            "disagreement_ms",
            "ntp",
            "profile_id",
            "source",
            "state",
            "storage_error",
            "v",
            "warning"
        ]
    );
    assert_eq!(keys(&view["ntp"]), ["measurement", "state"]);
    assert_eq!(keys(&view["air"]), ["applied_ms", "estimate", "state"]);
    assert_eq!(
        (
            &view["source"],
            &view["state"],
            &view["basis"],
            &view["correction_ms"]
        ),
        (&json!("ntp"), &json!("unknown"), &json!("ntp"), &json!(0))
    );
    assert_eq!(view["air"]["estimate"], Value::Null);
    let edit = |source: &str| json!({"v":1,"profile_id":s.id,"boot_id":s.boot,"source":source});
    let origin = Some(s.origin.as_str());
    let (status, view) = call(&s, "POST", "/clock", origin, Some(edit("air"))).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        (&view["source"], &view["basis"]),
        (&json!("air"), &json!("air"))
    );
    let file: Value =
        serde_json::from_slice(&std::fs::read(s.dir.join(clock_http::FILE)).unwrap()).unwrap();
    assert_eq!(
        file,
        json!({"schema_version":1,"profile_id":s.id,"source":"air"})
    );
    let (_, transmit) = call(&s, "GET", "/transmit", None, None).await;
    assert_eq!(
        (
            &transmit["clock_source"],
            &transmit["clock_warning"],
            &transmit["clock"]
        ),
        (&json!("air"), &Value::Null, &json!("unknown"))
    );
    // The air estimate after twelve stations were heard in two windows.
    let clock = s.recording.clock.get().unwrap().station.clone();
    for _ in 0..2 {
        for i in 0..12 {
            clock.observe(&format!("K{i}ABC"), 1500 + i * 10, Some(-4.0));
        }
        clock.period_done();
    }
    let (_, view) = call(&s, "GET", "/clock", None, None).await;
    let e = &view["air"]["estimate"];
    assert_eq!(
        keys(e),
        ["age_ms", "confidence_pct", "heard", "offset_ms", "stations"]
    );
    assert_eq!(
        (
            &e["offset_ms"],
            &e["stations"],
            &e["heard"],
            &e["confidence_pct"]
        ),
        (&json!(-1555), &json!(12), &json!(12), &json!(100))
    );
    assert_eq!(
        (
            &view["state"],
            &view["correction_ms"],
            &view["air"]["applied_ms"]
        ),
        (&json!("synchronized"), &json!(-1555), &json!(-1555))
    );
    // Refusals change nothing.
    for (body, origin, query, status, code) in [
        (
            json!({"v":1,"profile_id":"00000000-0000-4000-8000-0000000000c2","boot_id":s.boot,"source":"ntp"}),
            origin,
            "",
            StatusCode::FORBIDDEN,
            "wrong_profile",
        ),
        (
            json!({"v":1,"profile_id":s.id,"boot_id":"00000000-0000-4000-8000-0000000000c3","source":"ntp"}),
            origin,
            "",
            StatusCode::CONFLICT,
            "state_conflict",
        ),
        (
            json!({"v":2,"profile_id":s.id,"boot_id":s.boot,"source":"ntp"}),
            origin,
            "",
            StatusCode::BAD_REQUEST,
            "unsupported_version",
        ),
        (
            json!({"v":1,"profile_id":s.id,"boot_id":s.boot,"source":"gps"}),
            origin,
            "",
            StatusCode::BAD_REQUEST,
            "invalid_request",
        ),
        (
            json!({"v":1,"profile_id":s.id,"boot_id":s.boot,"source":"ntp","x":1}),
            origin,
            "",
            StatusCode::BAD_REQUEST,
            "invalid_request",
        ),
        (
            json!({"v":1,"profile_id":s.id,"boot_id":s.boot}),
            origin,
            "",
            StatusCode::BAD_REQUEST,
            "invalid_request",
        ),
        (
            edit("ntp"),
            Some("https://elsewhere.example"),
            "",
            StatusCode::FORBIDDEN,
            "forbidden_origin",
        ),
        (
            edit("ntp"),
            None,
            "",
            StatusCode::FORBIDDEN,
            "forbidden_origin",
        ),
        (
            edit("ntp"),
            origin,
            "?x=1",
            StatusCode::BAD_REQUEST,
            "invalid_request",
        ),
    ] {
        let (got, reply) = call(
            &s,
            "POST",
            &format!("/clock{query}"),
            origin,
            Some(body.clone()),
        )
        .await;
        assert_eq!(
            (got, reply["error"]["code"].as_str()),
            (status, Some(code)),
            "{body}"
        );
    }
    let (status, _) = call(&s, "GET", "/clock?x=1", None, None).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(clock.source().name(), "air");
    // A restart reads the saved source.
    let reopened = clock_http::Clock::load(&s.dir, &s.id, Monitor::new());
    assert_eq!(reopened.station.source().name(), "air");
}

// The actual transmit owner plans with the station clock: refused while too few stations
// are heard, admitted once the air estimate is confident, and its UTC carries the correction.
// Proves: TC-043-003.
#[test]
fn transmit_owner_admits_and_times_by_the_air_clock() {
    let s = station(directory());
    let clock = s.recording.clock.get().unwrap().station.clone();
    clock.set_source(wstx_rust::transmit::air::Source::Air);
    let transmit = s.recording.transmit.get().unwrap().clone();
    let utc = || transmit.service.with(|c| c.hardware().now_utc_ms());
    let wall = || {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as i64
    };
    let quiet = transmit.service.view();
    assert_eq!(quiet.clock, wstx_rust::transmit::ClockState::Unknown);
    for i in 0..2 {
        clock.observe(&format!("K{i}ABC"), 2000, Some(0.0));
    }
    clock.period_done();
    assert_eq!(
        transmit.service.view().clock,
        wstx_rust::transmit::ClockState::Unknown,
        "two stations"
    );
    for _ in 0..2 {
        for i in 0..6 {
            clock.observe(&format!("K{i}ABC"), 2000, Some(0.0));
        }
        clock.period_done();
    }
    assert_eq!(
        transmit.service.view().clock,
        wstx_rust::transmit::ClockState::Synchronized
    );
    let shifted = utc() - wall();
    assert!(
        (-2010..=-1990).contains(&shifted),
        "station UTC {shifted} ms from the system clock"
    );
    // NTP source: the same estimate neither corrects nor admits.
    clock.set_source(wstx_rust::transmit::air::Source::Ntp);
    assert_eq!(
        transmit.service.view().clock,
        wstx_rust::transmit::ClockState::Unknown
    );
    assert!((utc() - wall()).abs() <= 10);
}
