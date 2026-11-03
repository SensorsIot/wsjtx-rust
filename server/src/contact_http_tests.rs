#![forbid(unsafe_code)]
// Proves: CL-010-01, CL-010-03, CL-010-06, CL-010-11, CL-010-14, CL-010-15; TC-007-001,
// TC-007-003, TC-007-004, TC-010-008, TC-010-009. The actual router with the contact
// engine, the actual #9 transmit owner thread on recording hardware doubles (no audio,
// PTT or radio) and hand-authored decoded rows packed with the real codec.
use super::*;
use axum::body::Body;
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use tower::ServiceExt;
use wstx_rust::transmit::service::{
    AudioError, AudioPoll, Capability, Context, Hardware, Program, PttError,
};

/// Wall-clock hardware double: capability fixed, PTT/plays recorded, audio ends after
/// its sample count.
#[derive(Clone, Default)]
pub(crate) struct Bench {
    pub(crate) unsupported: Arc<AtomicBool>,
    /// Every PTT exchange with its UTC time.
    pub(crate) keys: Arc<Mutex<Vec<(i64, bool)>>>,
    playing: Arc<Mutex<Option<(i64, usize)>>>,
    pub(crate) offset: Arc<AtomicI64>,
    /// When nonzero, the station's UTC stands still at this value (offset ignored).
    pub(crate) frozen: Arc<AtomicI64>,
}
impl Hardware for Bench {
    fn now_utc_ms(&self) -> i64 {
        let frozen = self.frozen.load(Ordering::SeqCst);
        if frozen != 0 {
            return frozen;
        }
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as i64
            + self.offset.load(Ordering::SeqCst)
    }
    fn clock(&self) -> wstx_rust::transmit::ClockState {
        wstx_rust::transmit::ClockState::Synchronized
    }
    fn context(&self) -> Context {
        if self.unsupported.load(Ordering::SeqCst) {
            return Context {
                capability: Capability::Unsupported,
                safety_revision: None,
                radio_transmitting: Some(false),
            };
        }
        Context {
            capability: Capability::Available,
            safety_revision: Some(3),
            radio_transmitting: Some(false),
        }
    }
    fn ptt(&mut self, on: bool) -> Result<(), PttError> {
        let at = self.now_utc_ms();
        self.keys.lock().unwrap().push((at, on));
        Ok(())
    }
    fn open_audio(&mut self) -> Result<(), AudioError> {
        Ok(())
    }
    fn play(&mut self, program: Program) -> Result<(), AudioError> {
        let n = match program {
            Program::Waveform { samples, skip } => samples.len() - skip,
            Program::Tone { .. } => usize::MAX / 4,
        };
        *self.playing.lock().unwrap() = Some((self.now_utc_ms(), n));
        Ok(())
    }
    fn poll_audio(&mut self) -> AudioPoll {
        match *self.playing.lock().unwrap() {
            Some((at, n)) if (self.now_utc_ms() - at) * 48 >= n as i64 => AudioPoll::Finished,
            Some(_) => AudioPoll::Playing,
            None => AudioPoll::Idle,
        }
    }
    fn stop_audio(&mut self) {
        *self.playing.lock().unwrap() = None;
    }
    fn audio_stopper(&self) -> Arc<dyn Fn() + Send + Sync> {
        let p = self.playing.clone();
        Arc::new(move || *p.lock().unwrap() = None)
    }
}

/// A decoded result record of `text` with the real 77-bit codec (no decoder run).
pub(crate) fn record(text: &str, hz: f64, snr: Option<f64>) -> Value {
    record_exchange(text, hz, snr, None)
}
/// `record` with the 15 exchange bits (59..74) of a type 1/2 message replaced by `raw`, as
/// another program may pack them (e.g. RR73 as the grid square 32373 instead of 32403).
pub(crate) fn record_exchange(text: &str, hz: f64, snr: Option<f64>, raw: Option<u64>) -> Value {
    let mut bits = wstx_rust::transmit::pack(text).unwrap().bits;
    if let Some(raw) = raw {
        for (i, bit) in bits[59..74].iter_mut().enumerate() {
            *bit = ((raw >> (14 - i)) & 1) as u8;
        }
    }
    let mut v = serde_json::to_value(decoder::unpack(&bits)).unwrap();
    v["start_frame"] = json!(0);
    v["frequency_hz"] = json!(hz);
    v["snr_db"] = json!(snr);
    v["dt_seconds"] = json!(0.1);
    v
}
pub(crate) fn period_text(ms: i64) -> String {
    let t = crate::contact::utc_text(ms);
    format!("{}.0000000Z", &t[..19])
}
pub(crate) fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as i64
}

pub(crate) struct Fixture {
    pub(crate) router: Router,
    pub(crate) state: Arc<ProfileState>,
    pub(crate) origin: String,
    pub(crate) id: String,
    pub(crate) boot: String,
    pub(crate) dir: std::path::PathBuf,
    pub(crate) bench: Bench,
}
pub(crate) fn fixture(origin: &str, transmit: bool) -> Fixture {
    let dir = std::env::temp_dir().join(format!("wstx-contact-{}", profile::new_uuid().unwrap()));
    std::fs::create_dir(&dir).unwrap();
    let id = profile::new_uuid().unwrap();
    let boot = profile::new_uuid().unwrap();
    let bind = origin.trim_start_matches("http://");
    let doc = json!({"schema_version":1,"profile_id":id,"revision":0,"display_name":"Contact fixture",
        "callsign":"HB9BLA","locator":"JN47AA","endpoint":{"bind":bind,"origin":null},"connection_type":"standard",
        "audio":{"input_device":null,"output_device":null},"control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}});
    // A transmit-capable fixture is configured for CAT PTT, as a real one would be (the
    // CAT lifecycle does not run in these tests; the transmit owner uses the double).
    let mut doc = doc;
    if transmit {
        doc["audio"]["output_device"] = json!("fixture-output-device");
        doc["control"] = json!({"mode":"cat","endpoint":"icom7300://COM250","ptt":"cat"});
    }
    std::fs::write(dir.join("profile.json"), serde_json::to_vec(&doc).unwrap()).unwrap();
    let (store, _) = profile::Store::open(&dir).unwrap();
    let recording = recording::Recording::open(&dir, id.clone(), boot.clone());
    let bench = Bench::default();
    bench.unsupported.store(!transmit, Ordering::SeqCst);
    let _ = recording
        .transmit
        .set(transmit_http::Station::start_with(Box::new(bench.clone())).unwrap());
    let _ = recording.contact.set(contact_http::Station::start());
    let state = Arc::new(ProfileState {
        store: Mutex::new(store),
        authorization: Mutex::new(None),
        boot: boot.clone(),
        recording,
        logbook: Arc::new(crate::logbook::Logbook::open(&dir)),
    });
    let app = App {
        origin: origin.to_string(),
        profile: Some(state.clone()),
        profile_id: Some(id.clone()),
        token: None,
        connections: Arc::new(Semaphore::new(16)),
        login_attempts: Arc::new(Mutex::new((Instant::now(), 0))),
    };
    Fixture {
        router: router(app),
        state,
        origin: origin.to_string(),
        id,
        boot,
        dir,
        bench,
    }
}
impl Fixture {
    pub(crate) fn contact(&self) -> Arc<contact_http::Station> {
        self.state.recording.contact.get().unwrap().clone()
    }
    pub(crate) fn tick(&self) {
        contact_http::station_tick(&self.state);
    }
    pub(crate) async fn call(
        &self,
        method: &str,
        path: &str,
        body: Option<Value>,
    ) -> (StatusCode, Value, HeaderMap, usize) {
        self.raw(
            method,
            path,
            Some(&self.origin),
            body.map(|b| serde_json::to_vec(&b).unwrap()),
            &[],
        )
        .await
    }
    pub(crate) async fn raw(
        &self,
        method: &str,
        path: &str,
        origin: Option<&str>,
        body: Option<Vec<u8>>,
        headers: &[(&str, &str)],
    ) -> (StatusCode, Value, HeaderMap, usize) {
        let mut request = axum::http::Request::builder().method(method).uri(path);
        if let Some(origin) = origin {
            request = request.header(header::ORIGIN, origin);
        }
        for (k, v) in headers {
            request = request.header(*k, *v);
        }
        let request = match body {
            Some(b) => {
                if !headers
                    .iter()
                    .any(|(k, _)| k.eq_ignore_ascii_case("content-type"))
                {
                    request = request.header(header::CONTENT_TYPE, "application/json");
                }
                request.body(Body::from(b))
            }
            None => request.body(Body::empty()),
        }
        .unwrap();
        let response = self.router.clone().oneshot(request).await.unwrap();
        let status = response.status();
        let headers = response.headers().clone();
        let bytes = axum::body::to_bytes(response.into_body(), 1 << 20)
            .await
            .unwrap();
        (
            status,
            serde_json::from_slice(&bytes).unwrap_or(Value::Null),
            headers,
            bytes.len(),
        )
    }
    fn body(&self, revision: u64, action: &str, extra: Value) -> Value {
        let mut b = json!({"v":1,"profile_id":self.id,"boot_id":self.boot,"command_id":profile::new_uuid().unwrap(),
            "contact_revision":revision,"action":action});
        for (k, v) in extra.as_object().unwrap() {
            b[k] = v.clone();
        }
        b
    }
    async fn snapshot(&self) -> Value {
        let (status, v, _, _) = self.call("GET", "/contact", None).await;
        assert_eq!(status, StatusCode::OK, "{v}");
        v
    }
    async fn send(&self, action: &str, extra: Value) -> (StatusCode, Value) {
        let revision = self.snapshot().await["contact_revision"].as_u64().unwrap();
        let (s, v, _, _) = self
            .call(
                "POST",
                "/contact/command",
                Some(self.body(revision, action, extra)),
            )
            .await;
        (s, v)
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}
fn keys(v: &Value) -> Vec<String> {
    let mut k: Vec<_> = v.as_object().unwrap().keys().cloned().collect();
    k.sort();
    k
}
fn sorted(list: &[&str]) -> Vec<String> {
    let mut k: Vec<String> = list.iter().map(|s| s.to_string()).collect();
    k.sort();
    k
}
fn code(v: &Value) -> (&str, Option<&str>) {
    (
        v["error"]["code"].as_str().unwrap_or(""),
        v["error"]["field"].as_str(),
    )
}

#[tokio::test]
async fn contact_snapshot_is_exact_identity_coded_and_bounded() {
    let f = fixture("http://127.0.0.1:18001", true);
    let (status, v, headers, bytes) = f
        .raw(
            "GET",
            "/contact",
            None,
            None,
            &[("accept-encoding", "gzip, br")],
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        headers.get(header::CONTENT_ENCODING).is_none(),
        "GET /contact is never content-coded"
    );
    assert!(bytes <= contact_http::SNAPSHOT_BYTES_MAX);
    assert_eq!(
        keys(&v),
        sorted(&[
            "v",
            "profile_id",
            "boot_id",
            "contact_revision",
            "snapshot_sequence",
            "monotonic_ms",
            "utc_ms",
            "transmit",
            "settings",
            "contact",
            "log",
            "watchdog"
        ])
    );
    assert_eq!(
        keys(&v["transmit"]),
        sorted(&[
            "capability",
            "arm_state",
            "last_disarm_cause",
            "tune",
            "pending_sequence",
            "last_text",
            "last_period_utc",
            "halt_state",
            "safety_revision",
            "refusal"
        ])
    );
    assert_eq!(
        keys(&v["settings"]),
        sorted(&[
            "auto_seq",
            "call_first",
            "tx1_skip",
            "tx_minutes",
            "tune_seconds",
            "rx_hz",
            "tx_hz",
            "hold_tx",
            "parity",
            "report",
            "activity"
        ])
    );
    assert_eq!(
        keys(&v["watchdog"]),
        sorted(&[
            "tx_remaining_minutes",
            "tx_expired",
            "tune_remaining_seconds"
        ])
    );
    assert_eq!(v["contact"], Value::Null);
    assert_eq!(v["log"], Value::Null, "#41: no review; nothing logged yet");
    assert_eq!(
        v["settings"],
        json!({"auto_seq":true,"call_first":true,"tx1_skip":false,"tx_minutes":6,"tune_seconds":90,"rx_hz":1500,"tx_hz":1500,"hold_tx":false,"parity":"odd","report":-15,"activity":"none"})
    );
    assert_eq!(v["transmit"]["capability"], "available");
    assert_eq!(v["transmit"]["arm_state"], "disarmed");
    let (status, _, _, _) = f.raw("GET", "/contact?x=1", None, None, &[]).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, v, _, _) = f
        .raw("GET", "/contact", Some("http://evil.example"), None, &[])
        .await;
    assert_eq!(
        (status, code(&v).0),
        (StatusCode::FORBIDDEN, "forbidden_origin")
    );
    // The maximum shape (six 37-character messages, 13-character calls, a log outcome,
    // 16 maximal dialogue entries, #37) fits; one byte over the cap is refused, never
    // truncated.
    let long = "A".repeat(37);
    let entry =
        json!({"dir":"tx","text":long,"snr":-50,"period_utc_ms":MAX_SAFE_TEST,"count":u32::MAX});
    let dialogue = vec![entry; crate::contact::DIALOGUE_MAX];
    let max = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"contact_revision":MAX_SAFE_TEST,"snapshot_sequence":MAX_SAFE_TEST,
        "monotonic_ms":MAX_SAFE_TEST,"utc_ms":MAX_SAFE_TEST,
        "transmit":{"capability":"unavailable","arm_state":"disarmed","last_disarm_cause":"authority_changed","tune":false,
            "pending_sequence":MAX_SAFE_TEST,"last_text":long,"last_period_utc":MAX_SAFE_TEST,"halt_state":"pending","safety_revision":MAX_SAFE_TEST,"refusal":"clock_not_synchronized"},
        "settings":{"auto_seq":true,"call_first":false,"tx1_skip":false,"tx_minutes":99,"tune_seconds":300,"rx_hz":3000,"tx_hz":2950,"hold_tx":false,"parity":"even","report":-50,"activity":"arrl_digi"},
        "contact":{"id":f.id,"origin":"manual_entry","dx_call":"PJ4/PA3XYZABC","dx_grid":"JN47AA","report_sent":"-50","report_rcvd":"-50",
            "state":"roger_report","next_slot":"tx3","tx4":"rr73","messages":[long,long,long,long,long,long],
            "start_utc":"2026-10-31T23:59:59Z","end_utc":"2026-10-31T23:59:59Z","saved":false,"suggested_slot":"tx5",
            "last_rcvd":{"text":long,"snr":-50,"period_utc_ms":MAX_SAFE_TEST,"count":u32::MAX},
            "dialogue":dialogue},
        "log":{"contact_id":f.id,"call":"PJ4/PA3XYZABC","outcome":"unsaved","error":"storage_unavailable"},
        "watchdog":{"tx_remaining_minutes":99,"tx_expired":true,"tune_remaining_seconds":300}});
    let size = contact_http::admit(&max).unwrap().len();
    assert!(size <= contact_http::SNAPSHOT_BYTES_MAX, "{size}");
    let mut over = max.clone();
    over["contact"]["dx_grid"] = json!("X".repeat(contact_http::SNAPSHOT_BYTES_MAX - size + 7));
    assert_eq!(contact_http::admit(&over), Err("snapshot_limit"));
    // Event payloads stay within 192 bytes.
    let r = &f.state.recording;
    assert!(contact_http::state_event(r, MAX_SAFE_TEST).len() <= 192);
    // station.tick with its exact keys is at least 220 bytes at maximum values (two
    // UUIDs, a 13-digit utc_ms); the model's StationTickEvent bound is 224 (#10 NOTES).
    let tick = contact_http::tick_event(r).0;
    let worst = tick
        .replace("\"rx_level_db\":null", "\"rx_level_db\":90")
        .replace("false", "true ");
    assert!(worst.len() <= 224, "{worst}");
}
const MAX_SAFE_TEST: u64 = 9_007_199_254_740_991;

#[tokio::test]
async fn contact_command_wire_is_strict_replays_receipts_and_checks_revisions() {
    let f = fixture("http://127.0.0.1:18001", true);
    let rev = |v: &Value| v["contact_revision"].as_u64().unwrap();
    let r0 = rev(&f.snapshot().await);
    // Accepted: 202 exact receipt.
    let body = f.body(r0, "set_report", json!({"report":-7}));
    let (s, receipt, _, n) = f.call("POST", "/contact/command", Some(body.clone())).await;
    assert_eq!(s, StatusCode::ACCEPTED, "{receipt}");
    assert!(n <= 384);
    assert_eq!(
        keys(&receipt),
        sorted(&[
            "v",
            "profile_id",
            "boot_id",
            "command_id",
            "contact_revision",
            "accepted"
        ])
    );
    assert_eq!(receipt["accepted"], true);
    let r1 = rev(&f.snapshot().await);
    assert!(r1 > r0);
    assert_eq!(f.snapshot().await["settings"]["report"], -7);
    // Identical retained command_id: 200, the same receipt, no effect.
    let (s, again, _, _) = f.call("POST", "/contact/command", Some(body.clone())).await;
    assert_eq!((s, &again), (StatusCode::OK, &receipt));
    assert_eq!(rev(&f.snapshot().await), r1);
    // Same command_id, different body: state_conflict.
    let mut changed = body.clone();
    changed["report"] = json!(-8);
    let (s, v, _, _) = f.call("POST", "/contact/command", Some(changed)).await;
    assert_eq!(
        (s, code(&v)),
        (StatusCode::CONFLICT, ("state_conflict", Some("command_id")))
    );
    // Stale revision refused, except cancel, enable_tx false and tune false.
    let (s, v, _, _) = f
        .call(
            "POST",
            "/contact/command",
            Some(f.body(r0, "set_report", json!({"report":-9}))),
        )
        .await;
    assert_eq!(
        (s, code(&v)),
        (
            StatusCode::CONFLICT,
            ("stale_revision", Some("contact_revision"))
        )
    );
    for (action, extra) in [
        ("cancel", json!({})),
        ("enable_tx", json!({"enabled":false,"safety_revision":null})),
        ("tune", json!({"enabled":false})),
    ] {
        let (s, v, _, _) = f
            .call("POST", "/contact/command", Some(f.body(r0, action, extra)))
            .await;
        assert_eq!(s, StatusCode::ACCEPTED, "{action} {v}");
    }
    let current = rev(&f.snapshot().await);
    let (s, v, _, _) = f
        .call(
            "POST",
            "/contact/command",
            Some(f.body(current + 1, "cancel", json!({}))),
        )
        .await;
    assert_eq!(
        code(&v).0,
        "stale_revision",
        "{s}: a future revision is never admitted"
    );
    // Exact keys, enums, UUIDs, safe integers, version.
    let base = f.body(current, "set_report", json!({"report":-5}));
    let cases: Vec<(Value, &str, Option<&str>)> = vec![
        ({let mut b = base.clone(); b.as_object_mut().unwrap().remove("report"); b}, "invalid_request", Some("report")),
        ({let mut b = base.clone(); b["extra"] = json!(1); b}, "invalid_request", None),
        ({let mut b = base.clone(); b["v"] = json!(2); b}, "unsupported_version", Some("v")),
        ({let mut b = base.clone(); b["command_id"] = json!("not-a-uuid"); b}, "invalid_request", Some("command_id")),
        ({let mut b = base.clone(); b["contact_revision"] = json!(9_007_199_254_740_992u64); b}, "invalid_request", Some("contact_revision")),
        ({let mut b = base.clone(); b["action"] = json!("transmit_now"); b}, "invalid_request", Some("action")),
        ({let mut b = base.clone(); b["profile_id"] = json!(profile::new_uuid().unwrap()); b}, "wrong_profile", Some("profile_id")),
        ({let mut b = base.clone(); b["boot_id"] = json!(profile::new_uuid().unwrap()); b}, "state_conflict", Some("boot_id")),
        (f.body(current, "set_report", json!({"report":50})), "invalid_report", None),
        (f.body(current, "set_frequency", json!({"rx_hz":null,"tx_hz":199})), "out_of_range", None),
        (f.body(current, "set_frequency", json!({"rx_hz":null,"tx_hz":2951})), "out_of_range", None),
        (f.body(current, "set_frequency", json!({"rx_hz":3001,"tx_hz":null})), "out_of_range", None),
        (f.body(current, "set_watchdogs", json!({"tx_minutes":0,"tune_seconds":90})), "out_of_range", None),
        (f.body(current, "set_watchdogs", json!({"tx_minutes":6,"tune_seconds":301})), "out_of_range", None),
        (f.body(current, "choose_next", json!({"slot":"tx7"})), "invalid_request", Some("slot")),
        (f.body(current, "choose_next", json!({"slot":"tx2"})), "no_contact", None),
        (f.body(current, "set_tx4", json!({"form":"r73"})), "invalid_request", Some("form")),
        (f.body(current, "set_parity", json!({"parity":"first"})), "invalid_request", Some("parity")),
        (f.body(current, "enter_dx", json!({"dx_call":"AB1","dx_grid":null,"replace":false})), "invalid_call", None),
        (f.body(current, "enter_dx", json!({"dx_call":"DL1ABC","dx_grid":"SS00","replace":false})), "invalid_grid", None),
        (f.body(current, "select_row", json!({"row":{"source_id":f.id,"job_id":f.id,"generation":1},"replace":false})), "invalid_request", Some("row")),
        (f.body(current, "select_row", json!({"row":{"source_id":f.id,"job_id":f.id,"generation":1,"sequence":0},"replace":false})), "row_unavailable", Some("row")),
        (f.body(current, "redecode", json!({})), "redecode_unavailable", None),
        (f.body(current, "open_log", json!({})), "no_contact", None),
        // #41: the review queue and its discard action are retired.
        (f.body(current, "discard_review", json!({"contact_id":f.id})), "invalid_request", Some("action")),
    ];
    for (body, expected, field) in cases {
        let (s, v, _, _) = f.call("POST", "/contact/command", Some(body.clone())).await;
        assert_eq!(code(&v), (expected, field), "{s} {body}");
        assert_eq!(
            rev(&f.snapshot().await),
            current,
            "a refusal changes nothing: {body}"
        );
    }
    // Barriers: Origin, media type, body size, query.
    let ok = serde_json::to_vec(&f.body(current, "set_hold_tx", json!({"enabled":true}))).unwrap();
    let (s, v, _, _) = f
        .raw("POST", "/contact/command", None, Some(ok.clone()), &[])
        .await;
    assert_eq!((s, code(&v).0), (StatusCode::FORBIDDEN, "forbidden_origin"));
    let (s, _, _, _) = f
        .raw(
            "POST",
            "/contact/command",
            Some(&f.origin),
            Some(ok.clone()),
            &[("content-type", "text/plain")],
        )
        .await;
    assert_eq!(s, StatusCode::UNSUPPORTED_MEDIA_TYPE);
    let (s, _, _, _) = f
        .raw(
            "POST",
            "/contact/command?x=1",
            Some(&f.origin),
            Some(ok.clone()),
            &[],
        )
        .await;
    assert_eq!(s, StatusCode::BAD_REQUEST);
    // 1024 bytes admitted, 1025 refused.
    let mut text = f.body(current, "edit_message", json!({"slot":"tx1","text":""}));
    let size = serde_json::to_vec(&text).unwrap().len();
    text["text"] = json!(" ".repeat(1024 - size));
    let exact = serde_json::to_vec(&text).unwrap();
    assert_eq!(exact.len(), 1024);
    let (s, v, _, _) = f
        .raw(
            "POST",
            "/contact/command",
            Some(&f.origin),
            Some(exact.clone()),
            &[],
        )
        .await;
    assert_ne!(s, StatusCode::PAYLOAD_TOO_LARGE, "{v}");
    let mut over = exact.clone();
    over.insert(over.len() - 2, b' ');
    let (s, _, _, _) = f
        .raw("POST", "/contact/command", Some(&f.origin), Some(over), &[])
        .await;
    assert_eq!(s, StatusCode::PAYLOAD_TOO_LARGE);
    // 16 receipts retained: the 17th oldest command_id is no longer a replay.
    let first = f.body(
        rev(&f.snapshot().await),
        "set_hold_tx",
        json!({"enabled":false}),
    );
    let (s, _, _, _) = f
        .call("POST", "/contact/command", Some(first.clone()))
        .await;
    assert_eq!(s, StatusCode::ACCEPTED);
    for i in 0..16 {
        let (s, v) = f.send("set_report", json!({"report":-(i % 20)})).await;
        assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    }
    let (s, v, _, _) = f.call("POST", "/contact/command", Some(first)).await;
    assert_eq!(
        code(&v).0,
        "stale_revision",
        "{s}: evicted receipt is evaluated again"
    );
    // StatusReply is unchanged by the contact events.
    assert_eq!(
        keys(&reply(r#"{"v":1,"type":"station.get","id":1}"#)["data"]),
        sorted(&["version", "radio", "build"])
    );
}

#[tokio::test]
async fn selected_row_prepares_without_transmit_and_only_an_explicit_enable_arms() {
    let f = fixture("http://127.0.0.1:18001", true);
    let r = &f.state.recording;
    let (source, job, generation) = r.fixture_live_job("ft8");
    let now = now_ms();
    let even = now.div_euclid(30_000) * 30_000;
    let seq = r.fixture_publish_period(
        &period_text(even),
        vec![
            record("CQ K1ABC FN42", 1234.6, Some(-12.4)),
            record("CQ DL1ABC JO62", 800.0, Some(-3.0)),
        ],
    );
    let mut hashed = record("CQ W1AW FN31", 500.0, None);
    hashed["fields"]["from"] = json!({"kind":"hash","text":null,"hash_bits":22,"hash_value":12345});
    let hash_seq = r.fixture_publish_period(&period_text(even), vec![hashed])[0];
    f.tick();
    let row = |sequence: u64| json!({"source_id":source,"job_id":job,"generation":generation,"sequence":sequence});
    let (s, v) = f
        .send("select_row", json!({"row":row(hash_seq),"replace":false}))
        .await;
    assert_eq!(
        (s, code(&v).0),
        (StatusCode::BAD_REQUEST, "row_not_standard")
    );
    let (s, v) = f.send("select_row", json!({"row":{"source_id":source,"job_id":profile::new_uuid().unwrap(),"generation":generation,"sequence":seq[0]},"replace":false})).await;
    assert_eq!(
        (s, code(&v).0),
        (StatusCode::CONFLICT, "row_unavailable"),
        "an old/other job tuple"
    );
    let (s, v) = f
        .send("select_row", json!({"row":row(seq[0]),"replace":false}))
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    let snap = f.snapshot().await;
    let c = &snap["contact"];
    assert_eq!(
        keys(c),
        sorted(&[
            "id",
            "origin",
            "dx_call",
            "dx_grid",
            "report_sent",
            "report_rcvd",
            "state",
            "next_slot",
            "tx4",
            "messages",
            "start_utc",
            "end_utc",
            "saved",
            "suggested_slot",
            "last_rcvd",
            "dialogue"
        ])
    );
    assert_eq!(
        c["dialogue"],
        json!([]),
        "a new contact has no dialogue (#37)"
    );
    assert!(profile::valid_uuid(c["id"].as_str().unwrap()));
    assert_eq!(
        (
            c["dx_call"].as_str(),
            c["dx_grid"].as_str(),
            c["report_sent"].as_str()
        ),
        (Some("K1ABC"), Some("FN42"), None)
    );
    // RST_SENT is the report actually sent: none yet (planned Tx2 text holds -12).
    assert_eq!(
        (c["state"].as_str(), c["next_slot"].as_str()),
        (Some("replying"), Some("tx1"))
    );
    assert_eq!(
        c["messages"],
        json!([
            "K1ABC HB9BLA JN47",
            "K1ABC HB9BLA -12",
            "K1ABC HB9BLA R-12",
            "K1ABC HB9BLA RRR",
            "K1ABC HB9BLA 73",
            "CQ HB9BLA JN47"
        ])
    );
    assert_eq!(
        (
            snap["settings"]["rx_hz"].as_u64(),
            snap["settings"]["tx_hz"].as_u64(),
            snap["settings"]["parity"].as_str()
        ),
        (Some(1235), Some(1235), Some("odd"))
    );
    for _ in 0..5 {
        f.tick();
    }
    let snap = f.snapshot().await;
    assert_eq!(
        snap["transmit"]["arm_state"], "disarmed",
        "selection never arms"
    );
    assert_eq!(
        snap["transmit"]["pending_sequence"],
        Value::Null,
        "no TransmitRequest"
    );
    // A different partner needs the explicit ChangeContact.
    let (s, v) = f
        .send("select_row", json!({"row":row(seq[1]),"replace":false}))
        .await;
    assert_eq!((s, code(&v).0), (StatusCode::CONFLICT, "contact_active"));
    // Plaintext has no CL-022 grant: Enable Tx is transmit_unavailable.
    let (s, v) = f
        .send("enable_tx", json!({"enabled":true,"safety_revision":3}))
        .await;
    assert_eq!(
        (s, code(&v).0),
        (StatusCode::CONFLICT, "transmit_unavailable")
    );
    // With the test-only grant the explicit Enable Tx arms and one request is pending
    // for the next odd period with the Tx1 text.
    f.contact().grant.store(true, Ordering::SeqCst);
    for (wrong, field) in [
        (json!(2), "safety_revision"),
        (Value::Null, "safety_revision"),
    ] {
        let (s, v) = f
            .send("enable_tx", json!({"enabled":true,"safety_revision":wrong}))
            .await;
        assert_eq!(
            (s, code(&v)),
            (StatusCode::CONFLICT, ("stale_revision", Some(field))),
            "Enable Tx needs the current CL-022 safety revision"
        );
    }
    let shown = f.snapshot().await["transmit"]["safety_revision"].clone();
    assert_eq!(
        shown,
        json!(3),
        "the snapshot shows the current safety revision"
    );
    let revision = f.snapshot().await["contact_revision"].as_u64().unwrap();
    let enable = f.body(
        revision,
        "enable_tx",
        json!({"enabled":true,"safety_revision":shown}),
    );
    let (s, receipt, _, _) = f
        .call("POST", "/contact/command", Some(enable.clone()))
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{receipt}");
    let snap = f.snapshot().await;
    assert_eq!(snap["transmit"]["arm_state"], "armed");
    // Accepted TransmitRequest sequences as #9 reports them.
    let accepted = |t: &Value| -> std::collections::BTreeSet<u64> {
        t["outcomes"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|o| o["kind"] == "accepted")
            .map(|o| o["request_sequence"].as_u64().unwrap())
            .collect()
    };
    let (_, t0, _, _) = f.call("GET", "/transmit", None).await;
    assert_eq!(
        accepted(&t0).len(),
        1,
        "Enable Tx submits exactly one request: {t0}"
    );
    // A duplicated browser action (same command_id) replays the receipt, nothing else;
    // further steps add no request unless the first one's audio started (then exactly
    // one new request for the next own period).
    let (s, again, _, _) = f.call("POST", "/contact/command", Some(enable)).await;
    assert_eq!((s, &again), (StatusCode::OK, &receipt));
    for _ in 0..5 {
        f.tick();
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    // The audio may start after the fifth step (real clock); the next request is then
    // queued by a later step, so keep stepping for a bounded time (#10 flake).
    let deadline = Instant::now() + Duration::from_secs(5);
    let (t1, started, new) = loop {
        let (_, t1, _, _) = f.call("GET", "/transmit", None).await;
        let started = !t1["transmit"]["last_text"].is_null();
        let new = accepted(&t1).difference(&accepted(&t0)).count();
        if !started || new > 0 || Instant::now() >= deadline {
            break (t1, started, new);
        }
        f.tick();
        tokio::time::sleep(Duration::from_millis(50)).await;
    };
    assert_eq!(new, usize::from(started), "{t1}");
    // Every key falls inside an own-parity (odd) period's start window.
    for (at, on) in f.bench.keys.lock().unwrap().iter().copied() {
        if on {
            let period = at - at.rem_euclid(15_000);
            assert_eq!(
                wstx_rust::transmit::parity(decoder::Mode::Ft8, period),
                wstx_rust::transmit::Parity::Odd,
                "key at {at} outside an own period"
            );
            assert!(at - period < 11_250, "key at {at} after the start window");
        }
    }
    // Esc: halt (priority #9 route) first, then cancel.
    let (s, v, _, _) = f.call("POST", "/transmit/halt", Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap()}))).await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    let (s, _) = f.send("cancel", json!({})).await;
    assert_eq!(s, StatusCode::ACCEPTED);
    f.tick();
    let snap = f.snapshot().await;
    assert_eq!(
        (
            snap["transmit"]["arm_state"].as_str(),
            snap["contact"]["state"].as_str()
        ),
        (Some("disarmed"), Some("cancelled"))
    );
    assert_eq!(snap["contact"]["dx_call"], Value::Null);
    assert!(
        f.bench.keys.lock().unwrap().last().is_none_or(|k| !k.1),
        "PTT is released after the halt (a key, if any, was in an own period)"
    );
}

#[tokio::test]
async fn receive_only_station_selects_and_logs_and_refuses_every_transmit_action() {
    let f = fixture("http://127.0.0.1:18001", false);
    f.contact().grant.store(true, Ordering::SeqCst);
    let (s, v) = f
        .send(
            "enter_dx",
            json!({"dx_call":"dl1abc","dx_grid":"JO62","replace":false}),
        )
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    let snap = f.snapshot().await;
    assert_eq!(snap["transmit"]["capability"], "unsupported");
    assert_eq!(snap["contact"]["origin"], "manual_entry");
    for (action, extra) in [
        ("enable_tx", json!({"enabled":true,"safety_revision":null})),
        ("tune", json!({"enabled":true})),
    ] {
        let (s, v) = f.send(action, extra).await;
        assert_eq!(
            (s, code(&v).0),
            (StatusCode::CONFLICT, "transmit_unavailable"),
            "{action}"
        );
    }
    // #41: Log QSO logs at once on a receive-only station, without a review form.
    let (s, _) = f.send("open_log", json!({})).await;
    assert_eq!(s, StatusCode::ACCEPTED);
    let snap = f.snapshot().await;
    assert_eq!(snap["log"]["outcome"], "saved", "{snap}");
    assert_eq!(snap["contact"]["saved"], true);
    let page = f.state.logbook.history(&f.id, 0, 10).unwrap();
    let record = &page["records"][0];
    assert_eq!(page["total"], 1);
    assert_eq!(record["contact_id"], snap["contact"]["id"]);
    assert_eq!(
        (
            record["call"].as_str(),
            record["gridsquare"].as_str(),
            record["mode"].as_str(),
            record["station_callsign"].as_str(),
            record["my_gridsquare"].as_str()
        ),
        (
            Some("DL1ABC"),
            Some("JO62"),
            Some("FT8"),
            Some("HB9BLA"),
            Some("JN47AA")
        )
    );
    assert_eq!(
        (record["band"].clone(), record["freq"].clone()),
        (Value::Null, Value::Null),
        "no confirmed dial: band and frequency absent"
    );
    // The logged record is the one SaveContact would store: an identical save is
    // already_saved (one record per contact identity).
    let mut wire = record.clone();
    let wire = wire.as_object_mut().unwrap();
    wire.remove("index");
    wire.remove("unknown_field_count");
    let (s, v, _, _) = f.call("POST", "/contacts", Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),"record":wire}))).await;
    assert_eq!(
        (s, v["outcome"].as_str()),
        (StatusCode::OK, Some("already_saved")),
        "{v}"
    );
}

// Proves: CL-010-04; TC-011-001. #41 DirectLog record of an FT4 contact with a confirmed
// dial. Hand-computed: P = 2026-11-01T12:34:30Z; TIME_ON one FT4 period (7.5 s) before
// the first transmitted Tx3 at P+22.5 s = 12:34:45; TIME_OFF P+45 s = 12:35:15; FREQ
// 14.080000 MHz dial + 1234 Hz = 14.081234 (20m); FT4 is MODE MFSK, SUBMODE FT4.
#[test]
fn direct_log_record_fields_from_the_confirmed_dial() {
    const P: i64 = 1_793_536_470_000;
    let c = crate::contact::Contact {
        id: "11111111-1111-4111-8111-111111111111".into(),
        origin: crate::contact::Origin::DecodedRow,
        mode: decoder::Mode::Ft4,
        dx_call: Some("K1ABC".into()),
        dx_grid: Some("FN42".into()),
        report: -12,
        report_rcvd: Some(-9),
        report_sent: Some(-12),
        state: crate::contact::State::Completed,
        next: crate::contact::Slot::Tx6,
        tx4: crate::contact::Tx4::Rr73,
        messages: Default::default(),
        started_tx1_skipped: false,
        prepared_utc_ms: P,
        first_tx_period: Some(P + 7_500),
        first_tx2_period: None,
        first_tx3_period: Some(P + 22_500),
        last_counted_end: Some(P + 45_000),
        logged_on_completion: true,
        suggested: None,
        last_rcvd: None,
        dialogue: Default::default(),
    };
    let record = contact_http::Station::record_of(
        &c,
        P + 50_000,
        Some(14_080_000),
        1234,
        "HB9BLA",
        Some("JN47"),
    )
    .unwrap();
    assert_eq!(
        record.history_json(0),
        json!({"index":0,"contact_id":c.id,"call":"K1ABC","gridsquare":"FN42","mode":"MFSK","submode":"FT4",
            "rst_sent":"-12","rst_rcvd":"-09","qso_date":"20261101","time_on":"123445",
            "qso_date_off":"20261101","time_off":"123515","band":"20m","freq":"14.081234",
            "station_callsign":"HB9BLA","my_gridsquare":"JN47","tx_pwr":null,"comment":null,
            "unknown_field_count":0})
    );
    assert_eq!(
        crate::logbook::validate_record(&record, "HB9BLA", "JN47"),
        Ok(())
    );
}

#[test]
fn rx_level_is_round_10_log10_mean_square_in_16_bit_units() {
    let sine = |amplitude: f64| -> (f64, u64) {
        let n = 12_000u64;
        let mut sum = 0.0;
        for i in 0..n {
            let s = (amplitude * (2.0 * std::f64::consts::PI * 1000.0 * i as f64 / 12_000.0).sin())
                as f32;
            let v = f64::from(s) * 32768.0;
            sum += v * v;
        }
        (sum, n)
    };
    let (s, n) = sine(1.0);
    assert_eq!(recording::rx_level_db(s, n), 87, "full-scale sine");
    let (s, n) = sine(0.01);
    assert_eq!(recording::rx_level_db(s, n), 47, "-40 dBFS sine");
    assert_eq!(recording::rx_level_db(0.0, 12_000), 0, "silence clamped");
    // Uniform noise of known power: mean(s^2) = A^2/3 with A = 0.1 -> 10log10(32768^2*0.01/3) = 65.5 -> 65 or 66.
    let mut x: u64 = 1;
    let mut sum = 0.0;
    for _ in 0..120_000 {
        x = x
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        let u = ((x >> 11) as f64 / (1u64 << 53) as f64) * 2.0 - 1.0;
        let v = f64::from((0.1 * u) as f32) * 32768.0;
        sum += v * v;
    }
    assert!((65..=66).contains(&recording::rx_level_db(sum, 120_000)));
}

/// TC-007-001/003/004, TC-010-008/009 in the real browser: launches
/// tests/contact.test.cjs against this router with a request-recording peer.
/// Mandatory release execution is registered as the contact-browser suite.
#[cfg(not(debug_assertions))]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn contact_browser_operating_flow() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let origin = format!("http://{address}");
    let f = Arc::new(fixture(&origin, true));
    f.contact().grant.store(true, Ordering::SeqCst);
    let (source, job, generation) = f.state.recording.fixture_live_job("ft8");
    let _ = (&source, &job, generation);
    let router = f.router.clone();
    let service = tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    // The station-wide contact step, as main() runs it.
    let ticker = {
        let f = f.clone();
        tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_millis(50)).await;
                let state = f.state.clone();
                let _ =
                    tokio::task::spawn_blocking(move || contact_http::station_tick(&state)).await;
            }
        })
    };
    // Test-only control peer: publishes hand-authored periods on request.
    let control = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let control_origin = format!("http://{}", control.local_addr().unwrap());
    let publisher = f.clone();
    let control_app = Router::new()
        .route(
            "/publish",
            post(move |Json(body): Json<Value>| {
                let f = publisher.clone();
                async move {
                    let period = body["period_ms"].as_i64().unwrap();
                    let records = body["rows"]
                        .as_array()
                        .unwrap()
                        .iter()
                        .map(|r| {
                            record_exchange(
                                r["text"].as_str().unwrap(),
                                r["hz"].as_f64().unwrap(),
                                r["snr"].as_f64(),
                                r["exchange_raw"].as_u64(),
                            )
                        })
                        .collect();
                    let sequences = f
                        .state
                        .recording
                        .fixture_publish_period(&period_text(period), records);
                    Json(json!({"sequences":sequences,"now_ms":now_ms()}))
                }
            }),
        )
        .route(
            "/keys",
            get({
                let f = f.clone();
                move || {
                    let f = f.clone();
                    async move {
                        let keys: Vec<bool> =
                            f.bench.keys.lock().unwrap().iter().map(|k| k.1).collect();
                        Json(json!(keys))
                    }
                }
            }),
        );
    let control_service = tokio::spawn(async move {
        axum::serve(control, control_app).await.unwrap();
    });
    let outcome = tokio::task::spawn_blocking(move || {
        std::process::Command::new("node")
            .args(["--test", "--test-concurrency=1", "tests/contact.test.cjs"])
            .current_dir(
                std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                    .parent()
                    .unwrap(),
            )
            .env("WSTX_CONTACT_FIXTURE_ORIGIN", origin)
            .env("WSTX_CONTACT_FIXTURE_CONTROL", control_origin)
            .output()
            .unwrap()
    })
    .await
    .unwrap();
    ticker.abort();
    service.abort();
    control_service.abort();
    assert!(
        outcome.status.success(),
        "{}\n{}",
        String::from_utf8_lossy(&outcome.stdout),
        String::from_utf8_lossy(&outcome.stderr)
    );
    println!("{}", String::from_utf8_lossy(&outcome.stdout));
}

// ---------------------------------------------------------------- FT4 (#11 slice B)
fn tick_period(f: &Fixture) -> u64 {
    let (text, _) = contact_http::tick_event(&f.state.recording);
    serde_json::from_str::<Value>(&text).unwrap()["data"]["period_ms"]
        .as_u64()
        .unwrap()
}
async fn select_mode(f: &Fixture, mode: &str) -> (StatusCode, Value) {
    let (_, sel, _, _) = f.call("GET", "/receive/selection", None).await;
    let body = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),
        "profile_revision":sel["profile_revision"],"generation":sel["generation"],
        "operating_revision":sel["operating_revision"],"action":"mode","mode":mode});
    let (s, v, _, _) = f.call("POST", "/receive/select", Some(body)).await;
    (s, v)
}

// Proves: CL-011-02; TC-006-002. The station's operating mode follows the live FT4 job
// (WstxContact::StationOperatingMode) and a mode selection is refused busy while #9
// keys the radio (ModeChange; WSJT-X updateModeControlLock).
#[tokio::test]
async fn ft4_live_job_sets_the_contact_mode_and_tick_period_and_tune_blocks_a_mode_change() {
    let f = fixture("http://127.0.0.1:18011", true);
    let r = &f.state.recording;
    assert_eq!(tick_period(&f), 15_000, "fresh boot: FT8");
    r.fixture_live_job("ft4");
    assert_eq!(tick_period(&f), 7_500);
    let (s, v) = f
        .send(
            "enter_dx",
            json!({"dx_call":"K1ABC","dx_grid":null,"replace":false}),
        )
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    let snap = f.snapshot().await;
    assert_eq!(
        (
            snap["contact"]["tx4"].as_str(),
            snap["contact"]["messages"][3].as_str()
        ),
        (Some("rr73"), Some("K1ABC HB9BLA RR73")),
        "a manual entry in FT4 is an FT4 contact"
    );
    let (s, v) = f.send("set_tx4", json!({"form":"rrr"})).await;
    assert_eq!(
        (s, code(&v)),
        (StatusCode::BAD_REQUEST, ("out_of_range", Some("form")))
    );
    let service = &r.transmit.get().unwrap().service;
    service.with(|c| {
        c.arm(3).unwrap();
        c.set_tune(true, 1500).unwrap();
    });
    let before = f.call("GET", "/receive/selection", None).await.1["operating_revision"].clone();
    let (s, v) = select_mode(&f, "ft8").await;
    assert_eq!((s, code(&v).0), (StatusCode::CONFLICT, "busy"), "{v}");
    let after = f.call("GET", "/receive/selection", None).await.1;
    assert_eq!(after["operating_revision"], before, "nothing changed");
    assert_eq!(after["receive"]["mode"], "ft4");
    service.with(|c| c.set_tune(false, 0).unwrap());
    let (_, v) = select_mode(&f, "ft8").await;
    assert_ne!(code(&v).0, "busy", "{v}");
    r.fixture_live_job("ft8");
    assert_eq!(tick_period(&f), 15_000);
}

// Proves: CL-011-03, CL-011-04; TC-007-008. An FT4 and an FT8 station at once, each
// with its own router, engine, #9 owner and log; then the FT4 station switches mode.
// Station time stands still 3 s before the FT4 station's first own (odd) period at
// even + 7.5 s, so its Tx1 request is still unstarted when the mode switches, however
// slowly the test runs: the switch, not the #9 owner's period start, ends it. (On wall
// time a slow run let that period start first; the owner then refused the request as
// stale_request, last_disarm_cause "refused", before the contact step saw the switch.)
#[tokio::test]
async fn simultaneous_ft4_and_ft8_stations_stay_isolated_and_a_mode_switch_cancels_only_its_own() {
    let f4 = fixture("http://127.0.0.1:18012", true);
    let f8 = fixture("http://127.0.0.1:18013", true);
    let even = now_ms().div_euclid(30_000) * 30_000;
    for f in [&f4, &f8] {
        f.bench.frozen.store(even + 4_500, Ordering::SeqCst);
    }
    let mut rows = Vec::new();
    for (f, mode) in [(&f4, "ft4"), (&f8, "ft8")] {
        let r = &f.state.recording;
        let (source, job, generation) = r.fixture_live_job(mode);
        let seq = r.fixture_publish_period(
            &period_text(even),
            vec![record("CQ K1ABC FN42", 1234.6, Some(-12.4))],
        );
        f.tick();
        let row =
            json!({"source_id":source,"job_id":job,"generation":generation,"sequence":seq[0]});
        let (s, v) = f
            .send("select_row", json!({"row":row,"replace":false}))
            .await;
        assert_eq!(s, StatusCode::ACCEPTED, "{v}");
        let (s, v) = f.send("open_log", json!({})).await;
        assert_eq!(s, StatusCode::ACCEPTED, "{v}");
        rows.push(row);
    }
    // #41: Log QSO stored each station's record in its own contacts.adi.
    let review = |snap: &Value| {
        let f = if snap["profile_id"] == f4.id {
            &f4
        } else {
            &f8
        };
        let page = f.state.logbook.history(&f.id, 0, 10).unwrap();
        assert_eq!(page["total"], 1, "one record per station");
        let record = &page["records"][0];
        assert_eq!(record["contact_id"], snap["contact"]["id"]);
        (
            record["mode"].as_str().map(String::from),
            record["submode"].as_str().map(String::from),
        )
    };
    let logged4 = f4.snapshot().await;
    let s8 = f8.snapshot().await;
    assert_eq!(logged4["contact"]["messages"][3], "K1ABC HB9BLA RR73");
    assert_eq!(s8["contact"]["messages"][3], "K1ABC HB9BLA RRR");
    assert_eq!(review(&logged4), (Some("MFSK".into()), Some("FT4".into())));
    assert_eq!(review(&s8), (Some("FT8".into()), None));
    assert_ne!(logged4["contact"]["id"], s8["contact"]["id"]);
    // #37: Log QSO closed each station's contact.
    assert_eq!(
        (
            logged4["contact"]["state"].as_str(),
            s8["contact"]["state"].as_str()
        ),
        (Some("completed"), Some("completed"))
    );
    // Only the FT4 station arms, on K1ABC selected again (a new contact).
    f4.contact().grant.store(true, Ordering::SeqCst);
    let (s, v) = f4
        .send("select_row", json!({"row":rows[0],"replace":false}))
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    let (s, v) = f4
        .send("enable_tx", json!({"enabled":true,"safety_revision":3}))
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    f8.tick();
    let s4 = f4.snapshot().await;
    assert_eq!(s4["transmit"]["arm_state"], "armed");
    assert_eq!(s4["contact"]["state"], "replying");
    assert_eq!(f8.snapshot().await["transmit"]["arm_state"], "disarmed");
    // The FT4 station switches to FT8: its contact is cancelled and Enable Tx is off;
    // its log record keeps MFSK/FT4. The FT8 station is untouched.
    f4.state.recording.fixture_live_job("ft8");
    f4.tick();
    let s4 = f4.snapshot().await;
    assert_eq!(
        (
            s4["contact"]["state"].as_str(),
            s4["transmit"]["arm_state"].as_str(),
            s4["transmit"]["last_disarm_cause"].as_str()
        ),
        (
            Some("cancelled"),
            Some("disarmed"),
            Some("contact_cancelled")
        )
    );
    assert_eq!(review(&logged4), (Some("MFSK".into()), Some("FT4".into())));
    let s8 = f8.snapshot().await;
    assert_eq!(
        (
            s8["contact"]["state"].as_str(),
            s8["contact"]["dx_call"].as_str()
        ),
        (Some("completed"), Some("K1ABC"))
    );
    assert_eq!(review(&s8), (Some("FT8".into()), None));
}

// Proves: CL-011-02; TC-006-002. The busy barrier also holds while PTT is keyed before
// the audio and while the waveform plays (ModeChange); nothing changes.
#[tokio::test]
async fn a_mode_selection_is_busy_while_ptt_is_keyed_and_while_transmitting() {
    use wstx_rust::transmit::service::{OutcomeKind, PttState, Request};
    let f = fixture("http://127.0.0.1:18014", true);
    let r = &f.state.recording;
    r.fixture_live_job("ft4");
    let service = &r.transmit.get().unwrap().service;
    // Virtual UTC 200 ms before an FT4 period start; audio follows 300 ms after it.
    let now = now_ms();
    let period = (now.div_euclid(7_500) + 2) * 7_500;
    f.bench.offset.store(period - 200 - now, Ordering::SeqCst);
    service.with(|c| {
        c.arm(3).unwrap();
        let o = c.submit(Request {
            contact_id: None,
            request_sequence: 1,
            mode: decoder::Mode::Ft4,
            period_start_utc_ms: period,
            message_text: "CQ HB9BLA JN47".into(),
            tx_offset_hz: 1500,
        });
        assert_eq!(o.kind, OutcomeKind::Accepted);
    });
    let before = f.call("GET", "/receive/selection", None).await.1["operating_revision"].clone();
    let wait = |keyed: bool| async move {
        let deadline = Instant::now() + Duration::from_secs(3);
        loop {
            let v = service.view();
            if (keyed && v.ptt == PttState::Keyed && !v.transmitting) || (!keyed && v.transmitting)
            {
                return;
            }
            assert!(Instant::now() < deadline, "{v:?}");
            tokio::time::sleep(Duration::from_millis(2)).await;
        }
    };
    wait(true).await;
    let (s, v) = select_mode(&f, "ft8").await;
    assert_eq!(
        (s, code(&v).0),
        (StatusCode::CONFLICT, "busy"),
        "PTT keyed: {v}"
    );
    wait(false).await;
    let (s, v) = select_mode(&f, "ft8").await;
    assert_eq!(
        (s, code(&v).0),
        (StatusCode::CONFLICT, "busy"),
        "transmitting: {v}"
    );
    let after = f.call("GET", "/receive/selection", None).await.1;
    assert_eq!(after["operating_revision"], before, "nothing changed");
    assert_eq!(after["receive"]["mode"], "ft4");
    assert_eq!(tick_period(&f), 7_500);
    service.with(|c| c.halt());
}

// Proves: CL-011-02; TC-006-002. StationOperatingMode persists across a receive stop: an
// FT4 contact is kept when FT4 receive (started outside the operating selection) stops.
#[tokio::test]
async fn the_operating_mode_persists_across_a_receive_stop_and_keeps_the_ft4_contact() {
    let f = fixture("http://127.0.0.1:18015", false);
    let r = &f.state.recording;
    let (_, job, generation) = r.fixture_live_job("ft4");
    let (s, v) = f
        .send(
            "enter_dx",
            json!({"dx_call":"K1ABC","dx_grid":null,"replace":false}),
        )
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    let (s, v, _, _) = f
        .call(
            "POST",
            "/receive/stop",
            Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"generation":generation,"job_id":job})),
        )
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    // The receive worker's completion (no worker runs in this fixture).
    r.state.lock().unwrap().job.as_mut().unwrap().state = "cancelled";
    f.tick();
    assert_eq!(tick_period(&f), 7_500, "still FT4 after the stop");
    let snap = f.snapshot().await;
    assert_eq!(
        (
            snap["contact"]["state"].as_str(),
            snap["contact"]["dx_call"].as_str(),
            snap["contact"]["tx4"].as_str()
        ),
        (Some("replying"), Some("K1ABC"), Some("rr73"))
    );
}

// Proves: CL-011-03; TC-007-008. #11 live stall (IW9FRA, 2026-11-02 13:44-13:46 UTC):
// the published FT4 records of the partner (even 7.5 s periods, Î”f 1838 Hz, the real
// codec's fields and period_start_utc form) reach the engine through the station step
// and move the contact Tx1 -> Tx3 -> Tx5 exactly as WSJT-X auto-sequence does.
#[tokio::test]
async fn published_ft4_partner_records_advance_the_contact_to_signoff_after_rr73() {
    let f = fixture("http://127.0.0.1:18016", false);
    let r = &f.state.recording;
    let (source, job, generation) = r.fixture_live_job("ft4");
    // An even FT4 period well in the past (a multiple of 15 s).
    let p0 = now_ms().div_euclid(15_000) * 15_000 - 120_000;
    let cq = r.fixture_publish_period(
        &period_text(p0),
        vec![record("CQ IW9FRA JM68", 1838.0, Some(10.0))],
    )[0];
    f.tick();
    let row = json!({"source_id":source,"job_id":job,"generation":generation,"sequence":cq});
    let (s, v) = f
        .send("select_row", json!({"row":row,"replace":false}))
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    let state = |snap: &Value| {
        (
            snap["contact"]["state"].as_str().map(String::from),
            snap["contact"]["next_slot"].as_str().map(String::from),
        )
    };
    let expect = |a: &str, b: &str| (Some(a.to_string()), Some(b.to_string()));
    assert_eq!(state(&f.snapshot().await), expect("replying", "tx1"));
    assert_eq!(f.snapshot().await["settings"]["parity"], "odd");
    for (n, text, snr, after) in [
        (2, "HB9BLA IW9FRA +10", 10.0, ("roger_report", "tx3")),
        (4, "HB9BLA IW9FRA +10", 15.0, ("roger_report", "tx3")),
        (6, "HB9BLA IW9FRA RR73", 17.0, ("signoff", "tx5")),
        (8, "HB9BLA IW9FRA RR73", 9.0, ("signoff", "tx5")),
    ] {
        r.fixture_publish_period(
            &period_text(p0 + n * 7_500),
            vec![record(text, 1838.0, Some(snr))],
        );
        f.tick();
        let snap = f.snapshot().await;
        assert_eq!(state(&snap), expect(after.0, after.1), "after {text} ({n})");
    }
    let snap = f.snapshot().await;
    assert_eq!(snap["contact"]["report_rcvd"], "+10");
    assert_eq!(snap["contact"]["messages"][4], "IW9FRA HB9BLA 73");
}

// Proves: CL-011-03; TC-007-008. The same IW9FRA replay on a transmit-capable station
// through the actual station step, router and #9 owner on a virtual UTC: each partner
// record is published 7.0 s after its period start (live +6.7..7.3 s), just before my
// odd period; Hold Tx keeps my Tx at 2439 Hz. Expected: Tx1, R+10, R+10, 73, completed,
// logged once (contacts.adi) with Enable Tx off.
#[tokio::test]
async fn armed_ft4_station_answers_the_partners_rr73_with_73_and_logs_once() {
    let f = fixture("http://127.0.0.1:18017", true);
    f.contact().grant.store(true, Ordering::SeqCst);
    let r = &f.state.recording;
    let service = &r.transmit.get().unwrap().service;
    let (source, job, generation) = r.fixture_live_job("ft4");
    let p0 = now_ms().div_euclid(15_000) * 15_000 + 60_000;
    let at = |t: i64| {
        f.bench.frozen.store(t, Ordering::SeqCst);
        service.with(|c| c.tick());
        f.tick();
    };
    at(p0 + 7_000);
    let cq = r.fixture_publish_period(
        &period_text(p0),
        vec![record("CQ IW9FRA JM68", 1838.0, Some(10.0))],
    )[0];
    f.tick();
    for (action, extra) in [
        ("set_hold_tx", json!({"enabled":true})),
        ("set_frequency", json!({"rx_hz":null,"tx_hz":2439})),
        (
            "select_row",
            json!({"row":{"source_id":source,"job_id":job,"generation":generation,"sequence":cq},"replace":false}),
        ),
        ("enable_tx", json!({"enabled":true,"safety_revision":3})),
    ] {
        let (s, v) = f.send(action, extra).await;
        assert_eq!(s, StatusCode::ACCEPTED, "{action}: {v}");
    }
    let mut sent: Vec<(i64, String)> = Vec::new();
    let partner = [
        (2, "HB9BLA IW9FRA +10", 10.0),
        (4, "HB9BLA IW9FRA +10", 15.0),
        (6, "HB9BLA IW9FRA RR73", 17.0),
        (8, "HB9BLA IW9FRA RR73", 9.0),
        (10, "HB9BLA IW9FRA RR73", 16.0),
    ];
    let mut t = p0 + 7_000;
    while t < p0 + 13 * 7_500 {
        t += 50;
        if let Some((_, text, snr)) = partner.iter().find(|(n, ..)| p0 + n * 7_500 + 7_000 == t) {
            let n = (t - 7_000 - p0) / 7_500;
            r.fixture_publish_period(
                &period_text(p0 + n * 7_500),
                vec![record(text, 1838.0, Some(*snr))],
            );
        }
        at(t);
        let v = service.view();
        if let (Some(p), Some(text)) = (v.last_period_utc_ms, v.last_text.clone())
            && sent.last().is_none_or(|(q, x)| *q != p || *x != text)
        {
            sent.push((p, text));
        }
    }
    let sent: Vec<_> = sent
        .into_iter()
        .map(|(p, text)| ((p - p0) / 7_500, text))
        .collect();
    let expected: Vec<(i64, String)> = [
        (1, "IW9FRA HB9BLA JN47"),
        (3, "IW9FRA HB9BLA R+10"),
        (5, "IW9FRA HB9BLA R+10"),
        (7, "IW9FRA HB9BLA 73"),
    ]
    .iter()
    .map(|(n, t)| (*n, t.to_string()))
    .collect();
    assert_eq!(sent, expected);
    let snap = f.snapshot().await;
    assert_eq!(snap["contact"]["state"], "completed", "{snap}");
    assert_eq!(snap["transmit"]["arm_state"], "disarmed");
    assert_eq!(snap["contact"]["saved"], true, "{snap}");
    let log = f.state.logbook.history(&f.id, 0, 10).unwrap();
    assert_eq!(log["records"].as_array().unwrap().len(), 1, "{log}");
    // Proves: CL-050-06; TC-050-006 (#37): the snapshot's QSO dialogue, as exchanged.
    let p = |n: i64| p0 + n * 7_500;
    assert_eq!(
        snap["contact"]["dialogue"],
        json!([
            {"dir":"tx","text":"IW9FRA HB9BLA JN47","snr":null,"period_utc_ms":p(1),"count":1},
            {"dir":"rx","text":"HB9BLA IW9FRA +10","snr":10,"period_utc_ms":p(2),"count":1},
            {"dir":"tx","text":"IW9FRA HB9BLA R+10","snr":null,"period_utc_ms":p(3),"count":1},
            {"dir":"rx","text":"HB9BLA IW9FRA +10","snr":15,"period_utc_ms":p(4),"count":1},
            {"dir":"tx","text":"IW9FRA HB9BLA R+10","snr":null,"period_utc_ms":p(5),"count":1},
            {"dir":"rx","text":"HB9BLA IW9FRA RR73","snr":17,"period_utc_ms":p(6),"count":1},
            {"dir":"tx","text":"IW9FRA HB9BLA 73","snr":null,"period_utc_ms":p(7),"count":1}
        ]),
        "{snap}"
    );
}

// Proves: CL-024-01; TC-024-002 (#24 S1). The station's startup wiring gives the transmit
// owner the Recording's call hash table and sets my call from the profile.
#[test]
fn startup_shares_the_hash_table_with_the_transmit_owner() {
    let f = fixture("http://127.0.0.1:18001", true);
    let r = &f.state.recording;
    assert!(r.transmit.get().unwrap().hash_table().is_none());
    r.start_hashes("hb9bla");
    let shared = r.transmit.get().unwrap().hash_table().unwrap();
    assert!(Arc::ptr_eq(&shared, &r.hashes));
    assert_eq!(r.hashes.lock().unwrap().my_call(), Some("HB9BLA"));
}

// Proves: CL-024-01; TC-024-003 (f). A nonstandard manual entry over POST /contact/command
// gets its compound message set, and the station's contact step hands its DX call to the
// call hash table.
#[tokio::test]
async fn the_contact_step_gives_the_hash_table_the_dx_call() {
    let f = fixture("http://127.0.0.1:18001", true);
    let r = &f.state.recording;
    let (s, v) = f
        .send(
            "enter_dx",
            json!({"dx_call":"PJ4/K1ABC","dx_grid":null,"replace":false}),
        )
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    let snap = f.snapshot().await;
    assert_eq!(snap["contact"]["messages"][0], "<PJ4/K1ABC> HB9BLA JN47");
    r.contact.get().unwrap().tick(&f.state);
    assert_eq!(r.hashes.lock().unwrap().dx_call(), Some("PJ4/K1ABC"));
    let (s, v) = f.send("cancel", json!({})).await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    r.contact.get().unwrap().tick(&f.state);
    assert_eq!(r.hashes.lock().unwrap().dx_call(), None);
}

// Proves: CL-024-02; TC-024-005 (d). set_activity over POST /contact/command: the settings
// read it back, an unknown activity is refused and UDP Status carries WSJT-X's value.
#[tokio::test]
async fn set_activity_reads_back_and_reaches_udp_status() {
    let f = fixture("http://127.0.0.1:18001", true);
    let (s, v) = f
        .send("set_activity", json!({"activity":"field_day"}))
        .await;
    assert_eq!(
        (s, code(&v)),
        (
            StatusCode::BAD_REQUEST,
            ("invalid_request", Some("activity"))
        )
    );
    for (name, udp) in [
        ("ww_digi", 5u8),
        ("arrl_digi", 8),
        ("na_vhf", 1),
        ("none", 0),
    ] {
        let (s, v) = f.send("set_activity", json!({ "activity": name })).await;
        assert_eq!(s, StatusCode::ACCEPTED, "{v}");
        assert_eq!(f.snapshot().await["settings"]["activity"], name);
        assert_eq!(
            crate::udp::status_of(&f.state, &f.state.recording).special_operation,
            udp,
            "{name}"
        );
    }
}
