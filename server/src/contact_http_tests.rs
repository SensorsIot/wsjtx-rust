#![forbid(unsafe_code)]
// Proves: CL-010-01, CL-010-03, CL-010-06, CL-010-11, CL-010-14, CL-010-15; TC-007-001,
// TC-007-003, TC-007-004, TC-010-008, TC-010-009. The actual router with the contact
// engine, the actual #9 transmit owner thread on recording hardware doubles (no audio,
// PTT or radio) and hand-authored decoded rows packed with the real codec.
use super::*;
use axum::body::Body;
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU64, Ordering};
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
    /// Every Tx level handed to the hardware (#44 CL-044-12).
    pub(crate) levels: Arc<Mutex<Vec<i32>>>,
    /// Safety edits since the start: the safety revision is 3 plus this (#81 TC-081-005 (g)).
    pub(crate) safety_edits: Arc<AtomicU64>,
    /// When nonzero, the transmit owner's thread reads its UTC at most this value while the
    /// test thread reads the moved clock: a jump the engine sees first (#87).
    pub(crate) owner_hold: Arc<AtomicI64>,
}
impl Hardware for Bench {
    fn set_level_db(&mut self, level_db: i32) {
        self.levels.lock().unwrap().push(level_db);
    }
    fn now_utc_ms(&self) -> i64 {
        let frozen = self.frozen.load(Ordering::SeqCst);
        if frozen != 0 {
            return frozen;
        }
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as i64
            + self.offset.load(Ordering::SeqCst);
        let hold = self.owner_hold.load(Ordering::SeqCst);
        if hold != 0 && std::thread::current().name() == Some("transmit") {
            return now.min(hold);
        }
        now
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
            safety_revision: Some(3 + self.safety_edits.load(Ordering::SeqCst)),
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
    let (dir, _) = profile_directory(origin, transmit, "JN47AA");
    start_station(dir, origin, transmit)
}
/// A newly created disposable profile directory of HB9BLA at `locator` (profile.json
/// only), with its profile id; nothing is started on it.
pub(crate) fn profile_directory(
    origin: &str,
    transmit: bool,
    locator: &str,
) -> (std::path::PathBuf, String) {
    let dir = std::env::temp_dir().join(format!("wstx-contact-{}", profile::new_uuid().unwrap()));
    std::fs::create_dir(&dir).unwrap();
    let id = profile::new_uuid().unwrap();
    let bind = origin.trim_start_matches("http://");
    let doc = json!({"schema_version":1,"profile_id":id,"revision":0,"display_name":"Contact fixture",
        "callsign":"HB9BLA","locator":locator,"endpoint":{"bind":bind,"origin":null},"connection_type":"standard",
        "audio":{"input_device":null,"output_device":null},"control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}});
    // A transmit-capable fixture is configured for CAT PTT, as a real one would be (the
    // CAT lifecycle does not run in these tests; the transmit owner uses the double).
    let mut doc = doc;
    if transmit {
        doc["audio"]["output_device"] = json!("fixture-output-device");
        doc["control"] = json!({"mode":"cat","endpoint":"icom7300://COM250","ptt":"cat"});
    }
    std::fs::write(dir.join("profile.json"), serde_json::to_vec(&doc).unwrap()).unwrap();
    (dir, id)
}
/// A station start on the profile directory `dir`: a new station owner with a new boot id
/// (the store, the recording, the transmit owner on a new bench, the contact station).
pub(crate) fn start_station(dir: std::path::PathBuf, origin: &str, transmit: bool) -> Fixture {
    let boot = profile::new_uuid().unwrap();
    let (store, _) = profile::Store::open(&dir).unwrap();
    let id = store.document.profile_id.clone();
    let recording = recording::Recording::open(&dir, id.clone(), boot.clone());
    let bench = Bench::default();
    bench.unsupported.store(!transmit, Ordering::SeqCst);
    let _ = recording
        .transmit
        .set(transmit_http::Station::start_with(Box::new(bench.clone())).unwrap());
    let _ = recording.contact.set(contact_http::Station::start(&store));
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
    /// Ends this station (its store and locks are released) and starts a new one on the
    /// same profile directory.
    pub(crate) fn restart(mut self) -> Fixture {
        let dir = std::mem::take(&mut self.dir);
        let origin = self.origin.clone();
        let transmit = !self.bench.unsupported.load(Ordering::SeqCst);
        drop(self);
        start_station(dir, &origin, transmit)
    }
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
        // A restarted station handed its directory to its successor.
        if self.dir.as_os_str().is_empty() {
            return;
        }
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

// Proves: TC-007-004, TC-010-010, TC-050-006, TC-111-007, TC-097-017 (d).
// (TC-111-007: the snapshot's keys, the longest cause and its 4096 byte bound.)
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
            "last_arm_cause",
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
            "exchange",
            "serial",
            "auto_seq",
            "call_first",
            "tx1_skip",
            "tx_calls",
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
            "tx_remaining_calls",
            "tx_expired",
            "tune_remaining_seconds",
            "busy_with",
            "paused_calls"
        ])
    );
    assert_eq!(
        (&v["watchdog"]["busy_with"], &v["watchdog"]["paused_calls"]),
        (&Value::Null, &json!(0))
    );
    assert_eq!(v["contact"], Value::Null);
    assert_eq!(v["log"], Value::Null, "#41: no review; nothing logged yet");
    assert_eq!(
        v["settings"],
        json!({"auto_seq":true,"call_first":true,"tx1_skip":false,"tx_calls":6,"tune_seconds":90,"rx_hz":1500,"tx_hz":1500,"hold_tx":true,"parity":"odd","report":-15,"activity":"none","exchange":null,"serial":1})
    );
    assert_eq!(v["transmit"]["capability"], "available");
    assert_eq!(v["transmit"]["arm_state"], "disarmed");
    // TC-111-007 (#111 L3): off with cause startup and no start yet at a station start.
    assert_eq!(
        (
            &v["transmit"]["last_disarm_cause"],
            &v["transmit"]["last_arm_cause"]
        ),
        (&json!("startup"), &Value::Null)
    );
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
    // 16 maximal dialogue entries, #37; #97 a 13-character busy_with and paused_calls 99) fits;
    // one byte over the cap is refused, never truncated.
    let long = "A".repeat(37);
    let entry =
        json!({"dir":"tx","text":long,"snr":-50,"period_utc_ms":MAX_SAFE_TEST,"count":u32::MAX});
    let dialogue = vec![entry; crate::contact::DIALOGUE_MAX];
    let max = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"contact_revision":MAX_SAFE_TEST,"snapshot_sequence":MAX_SAFE_TEST,
        "monotonic_ms":MAX_SAFE_TEST,"utc_ms":MAX_SAFE_TEST,
        "transmit":{"capability":"unavailable","arm_state":"disarmed","last_disarm_cause":"partner_works_other","last_arm_cause":"operator","tune":false,
            "pending_sequence":MAX_SAFE_TEST,"last_text":long,"last_period_utc":MAX_SAFE_TEST,"halt_state":"pending","safety_revision":MAX_SAFE_TEST,"refusal":"clock_not_synchronized"},
        "settings":{"auto_seq":true,"call_first":false,"tx1_skip":false,"tx_calls":99,"tune_seconds":300,"rx_hz":3000,"tx_hz":2950,"hold_tx":false,"parity":"even","report":-50,"activity":"field_day","exchange":"32F WWA","serial":u32::MAX},
        "contact":{"id":f.id,"origin":"manual_entry","dx_call":"PJ4/PA3XYZABC","dx_grid":"JN47AA","report_sent":"-50","report_rcvd":"-50",
            "exchange_sent":"32F WWA","exchange_rcvd":"32F WWA","state":"roger_report","next_slot":"tx3","tx4":"rr73","messages":[long,long,long,long,long,long],
            "start_utc":"2026-10-31T23:59:59Z","end_utc":"2026-10-31T23:59:59Z","saved":false,"suggested_slot":"tx5",
            "last_rcvd":{"text":long,"snr":-50,"period_utc_ms":MAX_SAFE_TEST,"count":u32::MAX},
            "dialogue":dialogue},
        "log":{"contact_id":f.id,"call":"PJ4/PA3XYZABC","outcome":"unsaved","error":"storage_unavailable"},
        "watchdog":{"tx_remaining_calls":99,"tx_expired":true,"tune_remaining_seconds":300,
            "busy_with":"PJ4/PA3XYZABC","paused_calls":99}});
    let size = contact_http::admit(&max).unwrap().len();
    assert!(size <= contact_http::SNAPSHOT_BYTES_MAX, "{size}");
    let mut over = max.clone();
    over["contact"]["dx_grid"] = json!("X".repeat(contact_http::SNAPSHOT_BYTES_MAX - size + 7));
    assert_eq!(contact_http::admit(&over), Err("snapshot_limit"));
    // Event payloads stay within 192 bytes.
    let r = &f.state.recording;
    // station.tick with its exact keys is at least 220 bytes at maximum values (two
    // UUIDs, a 13-digit utc_ms); the model's StationTickEvent bound is 224 (#10 NOTES).
    let tick = contact_http::tick_event(r).0;
    let worst = tick
        .replace("\"rx_level_db\":null", "\"rx_level_db\":90")
        .replace("false", "true ");
    assert!(worst.len() <= 224, "{worst}");
}
const MAX_SAFE_TEST: u64 = 9_007_199_254_740_991;

// Proves: TC-097-017 (d) (CL-097-06, WstxOperatingChain::BusyPartner "Shown"). The operator selects CQ
// KE1J; KE1J's report to W9XYZ (packed with the real codec) is published: GET /contact's watchdog
// carries busy_with "W9XYZ" and paused_calls 0 (no paused send yet); his RR73 to W9XYZ clears it.
// Red on the parent: no busy_with key.
#[tokio::test]
async fn tc_097_017_d_get_contact_carries_the_busy_partner() {
    let f = fixture("http://127.0.0.1:18001", true);
    let r = &f.state.recording;
    let (source, job, generation) = r.fixture_live_job("ft8");
    let even = now_ms().div_euclid(30_000) * 30_000;
    let seq = r.fixture_publish_period(
        &period_text(even),
        vec![record("CQ KE1J FN42", 1800.0, Some(-7.0))],
    );
    f.tick();
    let row = json!({"source_id":source,"job_id":job,"generation":generation,"sequence":seq[0]});
    let (s, v) = f
        .send("select_row", json!({"row":row,"replace":false}))
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    r.fixture_publish_period(
        &period_text(even),
        vec![record("W9XYZ KE1J -07", 1200.0, Some(-7.0))],
    );
    f.tick();
    let snap = f.snapshot().await;
    assert_eq!(
        (
            &snap["watchdog"]["busy_with"],
            &snap["watchdog"]["paused_calls"]
        ),
        (&json!("W9XYZ"), &json!(0)),
        "{}",
        snap["watchdog"]
    );
    r.fixture_publish_period(
        &period_text(even),
        vec![record("W9XYZ KE1J RR73", 1200.0, Some(-7.0))],
    );
    f.tick();
    assert_eq!(f.snapshot().await["watchdog"]["busy_with"], Value::Null);
}

// Proves: TC-007-004.
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
        ("abort", json!({})),
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
        (f.body(current, "set_watchdogs", json!({"tx_calls":0,"tune_seconds":90})), "out_of_range", None),
        (f.body(current, "set_watchdogs", json!({"tx_calls":6,"tune_seconds":301})), "out_of_range", None),
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

// Proves: TC-007-001, TC-007-003, TC-050-006.
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
            "exchange_sent",
            "exchange_rcvd",
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
        (Some(1235), Some(1500), Some("odd"))
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
    // Halt (priority #9 route) first, then cancel.
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

// Proves: TC-007-004.
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
        exchange_sent: None,
        exchange_rcvd: None,
        activity: crate::contact::Activity::None,
        band: None,
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
        busy_with: None,
        his_last: None,
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
            "stx":null,"stx_string":null,"srx":null,"contest_id":null,"srx_string":null,"class":null,"arrl_sect":null,"state":null,"unknown_field_count":0})
    );
    assert_eq!(
        crate::logbook::validate_record(&record, "HB9BLA", "JN47"),
        Ok(())
    );
}

// Proves: TC-010-009.
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

// Proves: CL-010-15; TC-007-005 (#10 pushed transmit state, unit subset). The
// transmit.state revision follows the GET /transmit read view only: unchanged while the
// view is unchanged (no time-driven step), one step per change, age_ms ignored; the event
// has exactly its keys within 192 bytes.
#[tokio::test]
async fn transmit_state_revision_follows_the_read_view_only() {
    let f = fixture("http://127.0.0.1:18077", true);
    let r = &f.state.recording;
    // The service's first tick settles the startup release, a real change of the view.
    let service = &r.transmit.get().unwrap().service;
    let started = std::time::Instant::now();
    while transmit_http::view_json(r, &service.view())["startup_release"] == "pending" {
        assert!(
            started.elapsed() < Duration::from_secs(10),
            "startup release"
        );
        std::thread::sleep(Duration::from_millis(5));
    }
    let first = transmit_http::state_revision(r).unwrap();
    std::thread::sleep(Duration::from_millis(1100));
    assert_eq!(transmit_http::state_revision(r), Some(first), "time alone");
    let body = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),
        "action":"set_watchdogs","tx_calls":7,"tune_seconds":90});
    let (status, reply, _, _) = f.call("POST", "/transmit/command", Some(body)).await;
    assert_eq!(status, StatusCode::OK, "{reply}");
    let changed = transmit_http::state_revision(r).unwrap();
    assert_eq!(changed, first + 1, "one step per change");
    assert_eq!(transmit_http::state_revision(r), Some(changed));
    let view = json!({"ptt":"released","clock_measurement":{"server":"a","offset_ms":3,"round_trip_ms":9,"age_ms":10}});
    let mut older = view.clone();
    older["clock_measurement"]["age_ms"] = json!(99_000);
    assert_eq!(
        transmit_http::view_digest(view.clone()),
        transmit_http::view_digest(older)
    );
    let mut keyed = view.clone();
    keyed["ptt"] = json!("keyed");
    assert_ne!(
        transmit_http::view_digest(view),
        transmit_http::view_digest(keyed)
    );
    // The first event holds the whole pushed view; each later one only what changed.
    let first_view = transmit_http::pushed_view(r).unwrap();
    assert!(first_view.get("outcomes").is_none() && first_view.get("profile_id").is_none());
    let whole = transmit_http::changed_fields(&Value::Null, &first_view);
    assert_eq!(Value::Object(whole.clone()), first_view);
    // TC-111-007 (#111 L3): the event carries last_arm_cause and stays within 1024 bytes
    // with the longest causes of each direction.
    assert_eq!(
        first_view["transmit"].get("last_arm_cause"),
        Some(&Value::Null)
    );
    let mut longest = first_view.clone();
    longest["transmit"]["last_disarm_cause"] = json!("partner_works_other");
    longest["transmit"]["last_arm_cause"] = json!("operator");
    let longest = transmit_http::state_event(
        r,
        MAX_SAFE_TEST,
        transmit_http::changed_fields(&Value::Null, &longest),
    );
    assert!(longest.len() <= 1024, "{longest}");
    let event = transmit_http::state_event(r, MAX_SAFE_TEST, whole);
    assert!(event.len() <= 1024, "{event}");
    let event: Value = serde_json::from_str(&event).unwrap();
    assert_eq!(event["data"]["transmit_revision"], json!(MAX_SAFE_TEST));
    assert_eq!(event["data"]["profile_id"], json!(f.id));
    assert_eq!(event["data"]["boot_id"], json!(f.boot));
    assert!(transmit_http::changed_fields(&first_view, &first_view).is_empty());
    let mut later = first_view.clone();
    later["watchdog"]["tx_calls"] = json!(3);
    later["transmit"]["tune"] = json!(true);
    later["ptt"] = json!("keyed");
    assert_eq!(
        Value::Object(transmit_http::changed_fields(&first_view, &later)),
        json!({"watchdog":{"tx_calls":3},"transmit":{"tune":true},"ptt":"keyed"})
    );
    // The measurement's age alone is no change; a new measurement goes whole.
    let mut measured = first_view.clone();
    measured["clock_measurement"] =
        json!({"server":"a","offset_ms":1,"round_trip_ms":2,"age_ms":10});
    let mut older = measured.clone();
    older["clock_measurement"]["age_ms"] = json!(5000);
    assert!(transmit_http::changed_fields(&measured, &older).is_empty());
    assert_eq!(
        Value::Object(transmit_http::changed_fields(&first_view, &measured)),
        json!({"clock_measurement":{"server":"a","offset_ms":1,"round_trip_ms":2,"age_ms":10}})
    );
    let mut counting = first_view.clone();
    counting["watchdog"]["tune_remaining_seconds"] = json!(44);
    assert!(transmit_http::countdown_only(
        &transmit_http::changed_fields(&first_view, &counting)
    ));
    assert!(!transmit_http::countdown_only(
        &transmit_http::changed_fields(&first_view, &later)
    ));
}

// Proves: CL-010-15; TC-007-005 (#10 contact.state carries the changed fields).
#[test]
fn contact_state_carries_only_what_the_peer_lacks() {
    let row = |n: u32| json!({"dir":"rx","text":format!("HB9BLA K1ABC R-{n:02} padding padding padding padding"),"snr":-7,"period_utc_ms":n,"count":1});
    let view = |contact: Value, hold: bool| {
        json!({"v":1,"profile_id":"p","boot_id":"b","contact_revision":1,"snapshot_sequence":1,"monotonic_ms":1,"utc_ms":1,
            "transmit":{"capability":"unsupported","tune":false},"settings":{"hold_tx":hold,"rx_hz":1500},
            "contact":contact,"log":null,"watchdog":{"tx_expired":false,"tune_remaining_seconds":0}})
    };
    // A peer holding nothing gets every field, null too.
    let first = view(Value::Null, false);
    let (changed, holds) = contact_http::state_changes(&Value::Null, &first);
    assert_eq!(
        Value::Object(changed),
        json!({"transmit":first["transmit"],"settings":first["settings"],"contact":null,"log":null,"watchdog":first["watchdog"]})
    );
    assert_eq!(holds, first);
    assert!(contact_http::state_changes(&first, &first).0.is_empty());
    // Only the changed member, and not the time fields.
    let mut held = view(Value::Null, true);
    held["utc_ms"] = json!(99);
    let (changed, _) = contact_http::state_changes(&first, &held);
    assert_eq!(Value::Object(changed), json!({"settings":{"hold_tx":true}}));
    // A contact goes whole; the same contact's next row goes alone, from its index.
    let one = view(
        json!({"id":"c","state":"calling","dialogue":[row(1)]}),
        true,
    );
    let (changed, sent) = contact_http::state_changes(&held, &one);
    assert_eq!(changed["contact"]["id"], json!("c"));
    assert_eq!(changed["contact"]["dialogue_from"], json!(0));
    assert_eq!(changed["contact"]["dialogue"], json!([row(1)]));
    let two = view(
        json!({"id":"c","state":"rogers","dialogue":[row(1),row(2)]}),
        true,
    );
    let (changed, _) = contact_http::state_changes(&sent, &two);
    assert_eq!(
        Value::Object(changed),
        json!({"contact":{"state":"rogers","dialogue_from":1,"dialogue":[row(2)]}})
    );
    // A changed last row (a repeat's count) sends the dialogue again from its start.
    let mut repeat = two.clone();
    repeat["contact"]["dialogue"][1]["count"] = json!(2);
    let (changed, _) = contact_http::state_changes(&two, &repeat);
    assert_eq!(changed["contact"]["dialogue_from"], json!(0));
    assert_eq!(changed["contact"]["dialogue"].as_array().unwrap().len(), 2);
    // Over the frame budget the rest of the rows follow, none lost and none sent twice.
    let rows: Vec<Value> = (0..60).map(row).collect();
    let long = view(json!({"id":"c","state":"rogers","dialogue":rows}), true);
    let (mut holds, mut received, mut frames) = (held.clone(), Vec::new(), 0);
    while holds["contact"] != long["contact"] {
        let (changed, next) = contact_http::state_changes(&holds, &long);
        let event = contact_http::state_event(&long, changed.clone());
        assert!(event.len() <= 2048, "{}", event.len());
        assert_eq!(changed["contact"]["dialogue_from"], json!(received.len()));
        received.extend(changed["contact"]["dialogue"].as_array().unwrap().clone());
        holds = next;
        frames += 1;
        assert!(frames < 10);
    }
    assert!(frames > 1);
    assert_eq!(json!(received), long["contact"]["dialogue"]);
    // The whole first event of a socket fits as well, with real ids, a log and a long dialogue.
    let id = "12345678-1234-4234-8234-123456789012";
    let mut reload = view(
        json!({"id":id,"origin":"manual","dx_call":"K1ABC/P","dx_grid":"FN42","report_sent":"-07","report_rcvd":"R-09",
        "exchange_sent":null,"exchange_rcvd":null,"state":"rogers","next_slot":"tx4","tx4":"rr73",
        "messages":{"tx1":"K1ABC/P HB9BLA JN37","tx2":"K1ABC/P HB9BLA -07","tx3":"K1ABC/P HB9BLA R-07","tx4":"K1ABC/P HB9BLA RR73","tx5":"K1ABC/P HB9BLA 73","tx6":"CQ HB9BLA JN37"},
        "start_utc":"2026-11-06T10:00:00Z","end_utc":null,"saved":false,"suggested_slot":null,
        "last_rcvd":{"text":"HB9BLA K1ABC/P R-09","snr":-9,"period_utc_ms":1793962997000i64,"count":1},
        "dialogue":(0..16).map(row).collect::<Vec<_>>()}),
        true,
    );
    reload["profile_id"] = json!(id);
    reload["boot_id"] = json!(id);
    reload["contact_revision"] = json!(9007199254740991i64);
    reload["snapshot_sequence"] = json!(9007199254740991i64);
    reload["monotonic_ms"] = json!(9007199254740991i64);
    reload["utc_ms"] = json!(1793962997000i64);
    reload["log"] =
        json!({"contact_id":id,"call":"K1ABC/P","outcome":"unsaved","error":"storage_unavailable"});
    reload["transmit"] = json!({"capability":"available","arm_state":"disarmed","last_disarm_cause":"tx_watchdog_expired","tune":false,"pending_sequence":null,"last_text":"K1ABC/P HB9BLA R-07","last_period_utc":1793962997000i64,"halt_state":"idle","safety_revision":7,"refusal":"tune_active"});
    reload["settings"] = json!({"auto_seq":true,"call_first":true,"tx1_skip":false,"tx_calls":6,"tune_seconds":90,"rx_hz":1500,"tx_hz":1500,"hold_tx":false,"parity":"odd","report":-15,"activity":"none","exchange":null,"serial":1});
    reload["watchdog"] =
        json!({"tx_remaining_calls":6,"tx_expired":false,"tune_remaining_seconds":0});
    let (mut holds, mut received, mut frames) = (Value::Null, 0, 0);
    while holds["contact"] != reload["contact"] {
        let (changed, next) = contact_http::state_changes(&holds, &reload);
        let event = contact_http::state_event(&reload, changed.clone());
        assert!(event.len() <= 2048, "frame {frames}: {} bytes", event.len());
        received += changed["contact"]["dialogue"].as_array().unwrap().len();
        holds = next;
        frames += 1;
        assert!(frames < 10);
    }
    assert_eq!(received, 16);
}
// Proves: CL-010-15; TC-007-005. Below Detailed a running Tune countdown alone goes at most every 5 s.
#[test]
fn pushed_state_paces_a_countdown_by_display_profile() {
    use std::time::Duration;
    let of = |v: Value| v.as_object().cloned().unwrap();
    let countdown = of(json!({"watchdog":{"tune_remaining_seconds":44}}));
    let other = of(json!({"watchdog":{"tx_calls":3}}));
    assert!(transmit_http::due(
        "detail",
        &countdown,
        Duration::from_secs(1)
    ));
    for profile in ["thin", "off"] {
        assert!(!transmit_http::due(
            profile,
            &countdown,
            Duration::from_millis(4900)
        ));
        assert!(transmit_http::due(
            profile,
            &countdown,
            Duration::from_secs(5)
        ));
        assert!(transmit_http::due(
            profile,
            &other,
            Duration::from_millis(1)
        ));
    }
}

/// TC-007-001/003/004, TC-010-008/009, TC-050-004 in the real browser: launches
/// tests/contact.test.cjs against this router with a request-recording peer.
/// Mandatory release execution is registered as the contact-browser suite.
/// The two TC-050-004 tests each wait for several real-clock FT8 periods, so each runs
/// against its own station and browser, concurrently with the other tests (harness#28);
/// together the three runs cover every test of the file once.
#[cfg(not(debug_assertions))]
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn contact_browser_operating_flow() {
    let (rest, switch_mid_qso, switch_from_cq) = tokio::join!(
        contact_browser_station(&["--test-skip-pattern=^TC-050-004 "]),
        contact_browser_station(&["--test-name-pattern=^TC-050-004 mid-QSO: "]),
        contact_browser_station(&["--test-name-pattern=^TC-050-004 from-CQ: "]),
    );
    let runs = [
        ("other tests", rest),
        ("TC-050-004 mid-QSO", switch_mid_qso),
        ("TC-050-004 from-CQ", switch_from_cq),
    ];
    // Every run's output first, so that one failure does not hide the others.
    for (label, outcome) in &runs {
        println!("{label}:\n{}", String::from_utf8_lossy(&outcome.stdout));
    }
    for (label, outcome) in runs {
        let stdout = String::from_utf8_lossy(&outcome.stdout);
        assert!(
            outcome.status.success(),
            "{label}:\n{stdout}\n{}",
            String::from_utf8_lossy(&outcome.stderr)
        );
        // A filter that matched nothing would pass vacuously.
        assert!(
            stdout.contains("\u{2139} pass ") && !stdout.contains("\u{2139} pass 0"),
            "{label}: no test selected\n{stdout}"
        );
    }
}

/// One isolated station (router, contact step and control peer) running
/// tests/contact.test.cjs with the given node test filter.
#[cfg(not(debug_assertions))]
async fn contact_browser_station(filter: &[&str]) -> std::process::Output {
    let filter: Vec<String> = filter.iter().map(|f| f.to_string()).collect();
    let listener = crate::test_ports::browser_listener();
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
                let _ = tokio::task::spawn_blocking(move || {
                    contact_http::station_tick(&state);
                })
                .await;
            }
        })
    };
    // Test-only control peer: publishes hand-authored periods on request.
    let control = crate::test_ports::browser_listener();
    let control_origin = format!("http://{}", control.local_addr().unwrap());
    let publisher = f.clone();
    let tuner = f.clone();
    let bander = f.clone();
    let control_app = Router::new()
        .route(
            "/band",
            post(move |Json(body): Json<Value>| {
                let f = bander.clone();
                async move {
                    let (band, hz) = match body["band"].as_str().unwrap() {
                        "20m" => ("20m", 14_074_000),
                        _ => ("40m", 7_074_000),
                    };
                    f.state.recording.fixture_manual_band(band, hz);
                    Json(json!({"band":band}))
                }
            }),
        )
        .route(
            "/tune",
            post(move |Json(body): Json<Value>| {
                let f = tuner.clone();
                async move {
                    let station = f.state.recording.transmit.get().unwrap();
                    let enabled = body["enabled"].as_bool().unwrap();
                    let result = station.service.with(|c| {
                        if !enabled {
                            let stopped = c.set_tune(false, 0);
                            c.disarm(wstx_rust::transmit::service::DisarmCause::Operator);
                            return stopped;
                        }
                        let revision = c.hardware().context().safety_revision.unwrap_or(1);
                        c.arm(revision)?;
                        c.set_tune(true, 1500)
                    });
                    Json(json!({"accepted":result.is_ok(),"refusal":format!("{result:?}")}))
                }
            }),
        )
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
            .args(["--test", "--test-concurrency=1"])
            .args(&filter)
            .arg("tests/contact.test.cjs")
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
    outcome
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
// (WstxQsoTransmit::StationOperatingMode) and a mode selection is refused busy while #9
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
// Proves: CL-111-03; TC-111-001 (b) (the cause mode_changed on the wire).
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
            // #111 CL-111-03, TC-111-001 (b): the wire names the mode change.
            Some("mode_changed")
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
// Proves: TC-050-006.
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
            {"dir":"rx","text":"HB9BLA IW9FRA +10","snr":15,"period_utc_ms":p(2),"count":2},
            {"dir":"tx","text":"IW9FRA HB9BLA R+10","snr":null,"period_utc_ms":p(3),"count":2},
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
    // "eu_vhf" until #99 (TC-099-002).
    let (s, v) = f
        .send("set_activity", json!({"activity":"q65_pileup"}))
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

// Proves: CL-099-02; TC-099-002 (e), (g). set_activity eu_vhf over POST /contact/command: no
// exchange, the refusals with their fields from the profile, the settings read back with the
// serial and UDP Status special operation 2.
#[tokio::test]
async fn eu_vhf_reads_back_refuses_with_its_fields_and_reaches_udp_status() {
    let f = fixture("http://127.0.0.1:18001", true);
    let (s, v) = f
        .send("set_activity", json!({"activity":"eu_vhf","exchange":"MA"}))
        .await;
    assert_eq!(
        (s, code(&v)),
        (
            StatusCode::BAD_REQUEST,
            ("invalid_request", Some("exchange"))
        )
    );
    let profile = |callsign: &str, locator: &str| {
        let mut store = f.state.store.lock().unwrap();
        store.document.callsign = callsign.into();
        store.document.locator = locator.into();
    };
    for (callsign, locator, refused) in [
        ("HB9BLA", "JN47", ("profile_incomplete", Some("locator"))),
        ("VP2E/HB9BLAX", "JN47AA", ("invalid_call", Some("callsign"))),
    ] {
        profile(callsign, locator);
        let (_, v) = f.send("set_activity", json!({"activity":"eu_vhf"})).await;
        assert_eq!(code(&v), refused, "{callsign} {locator}");
        assert_eq!(f.snapshot().await["settings"]["activity"], "none");
    }
    profile("HB9BLA", "JN47AA");
    let (s, v) = f.send("set_activity", json!({"activity":"eu_vhf"})).await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    let settings = &f.snapshot().await["settings"];
    assert_eq!(
        (
            &settings["activity"],
            &settings["exchange"],
            &settings["serial"]
        ),
        (&json!("eu_vhf"), &Value::Null, &json!(1))
    );
    assert_eq!(
        crate::udp::status_of(&f.state, &f.state.recording).special_operation,
        2
    );
    let (s, v) = f
        .send(
            "enter_dx",
            json!({"dx_call":"K1ABC","dx_grid":null,"replace":false}),
        )
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    let contact = &f.snapshot().await["contact"];
    // The default report -15: n = 21 / 6 = 3.
    assert_eq!(contact["messages"][1], "<K1ABC> <HB9BLA> 530001 JN47AA");
    assert_eq!(
        (&contact["exchange_sent"], &contact["exchange_rcvd"]),
        (&Value::Null, &Value::Null)
    );
    // The locator cut after the choice: the next regeneration names the field.
    profile("HB9BLA", "JN47");
    let (_, v) = f.send("set_report", json!({"report":-10})).await;
    assert_eq!(code(&v), ("profile_incomplete", Some("locator")));
}

// Proves: CL-024-03; TC-024-008 (d), (e). set_activity field_day/rtty with the exchange
// over POST /contact/command: normalized read-back, the serial, refusals and UDP Status 3/4.
#[tokio::test]
async fn contest_activity_with_its_exchange_reads_back_and_reaches_udp_status() {
    let f = fixture("http://127.0.0.1:18001", true);
    for body in [
        json!({"activity":"field_day"}),
        json!({"activity":"field_day","exchange":"33A EMA"}),
        json!({"activity":"rtty","exchange":"DXX"}),
        json!({"activity":"ww_digi","exchange":"MA"}),
        json!({"activity":"rtty","exchange":7}),
        json!({"activity":"field_day","exchange":"1\u{e9} EMA"}),
    ] {
        let (s, v) = f.send("set_activity", body.clone()).await;
        assert_eq!(
            (s, code(&v)),
            (
                StatusCode::BAD_REQUEST,
                ("invalid_request", Some("exchange"))
            ),
            "{body}"
        );
    }
    for (name, exchange, shown, udp) in [
        ("field_day", "1a  ema", "1A EMA", 3u8),
        ("rtty", "dx", "DX", 4),
    ] {
        let (s, v) = f
            .send("set_activity", json!({"activity":name,"exchange":exchange}))
            .await;
        assert_eq!(s, StatusCode::ACCEPTED, "{v}");
        let settings = &f.snapshot().await["settings"];
        assert_eq!(
            (
                &settings["activity"],
                &settings["exchange"],
                &settings["serial"]
            ),
            (&json!(name), &json!(shown), &json!(1))
        );
        assert_eq!(
            crate::udp::status_of(&f.state, &f.state.recording).special_operation,
            udp,
            "{name}"
        );
    }
    let (s, _) = f.send("set_activity", json!({"activity":"none"})).await;
    assert_eq!(s, StatusCode::ACCEPTED);
    assert_eq!(f.snapshot().await["settings"]["exchange"], Value::Null);
}

// Proves: CL-024-04; TC-024-012 (#24 S4b). set_activity hound over POST /contact/command:
// read-back with Tx parity odd and Hold Tx, no exchange, UDP Status 7; the row reader keeps a
// 0.1 DXpedition record as its fields, not as a standard message.
#[tokio::test]
async fn hound_reads_back_reaches_udp_status_and_the_row_reader_keeps_0_1_fields() {
    let f = fixture("http://127.0.0.1:18001", true);
    let (s, v) = f
        .send("set_activity", json!({"activity":"hound","exchange":"MA"}))
        .await;
    assert_eq!(
        (s, code(&v)),
        (
            StatusCode::BAD_REQUEST,
            ("invalid_request", Some("exchange"))
        )
    );
    let (s, v) = f.send("set_activity", json!({"activity":"hound"})).await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    let settings = &f.snapshot().await["settings"];
    assert_eq!(
        (
            &settings["activity"],
            &settings["parity"],
            &settings["hold_tx"],
            &settings["exchange"]
        ),
        (&json!("hound"), &json!("odd"), &json!(true), &Value::Null)
    );
    assert_eq!(
        crate::udp::status_of(&f.state, &f.state.recording).special_operation,
        7
    );
    let mut table = wstx_rust::decoder::HashTable::new();
    table.set_my_call(Some("HB9BLA"));
    table.set_dx_call(Some("KH7Z"));
    let payload = table.resolve(&wstx_rust::decoder::unpack(
        &crate::contact_tests::dxpedition_bits("HB9BLA", "K1ABC", "KH7Z", -8),
    ));
    let mut record = serde_json::to_value(wstx_rust::decoder::Decode {
        payload,
        start_frame: 0,
        frequency_hz: 450.0,
        snr_db: Some(-5.0),
        a_priori: None,
    })
    .unwrap();
    record["sequence"] = json!(1);
    record["status"] = json!("decoded");
    let row = contact_http::row_of(&record, &("s".into(), "j".into(), 1), "ft8").unwrap();
    assert_eq!(row.text, "HB9BLA RR73; K1ABC <KH7Z> -08");
    assert_eq!(row.standard, None);
    assert_eq!(
        row.dxpedition.as_deref(),
        Some(&contact::Dxpedition {
            rr73_to: contact::Call::Sign("HB9BLA".into()),
            report_to: contact::Call::Sign("K1ABC".into()),
            fox: contact::Call::Hashed("KH7Z".into()),
            report: -8,
        })
    );
}

// Proves: FR-003, CL-007-03 (#56 slice 5 APrioriContext). The live decode context follows
// the profile callsign and the current contact: MyCall alone before a contact, then DxCall,
// the WSJT-X QSO progress of the contact state and the Rx/Tx offsets. CQ-only (lapcqonly)
// holds until Enable Tx is on, clears while it is on and returns 300 s after it went off.
#[tokio::test]
async fn a_priori_context_follows_profile_and_contact() {
    use decoder::QsoProgress;
    let f = fixture("http://127.0.0.1:18017", true);
    let r = &f.state.recording;
    let (source, job, generation) = r.fixture_live_job("ft8");
    f.tick();
    let calls = |text: &str| wstx_rust::transmit::pack(text).unwrap().bits;
    let ap = f.contact().a_priori();
    assert_eq!(
        ap.my_call.map(|b| b.to_vec()),
        Some(calls("HB9BLA KA1ABC RRR")[..29].to_vec())
    );
    assert_eq!(
        (ap.dx_call, ap.progress, ap.cq_only),
        (None, QsoProgress::Calling, true)
    );
    let p0 = now_ms().div_euclid(30_000) * 30_000 - 300_000;
    let cq = r.fixture_publish_period(
        &period_text(p0),
        vec![record("CQ K1ABC FN42", 1234.0, Some(-5.0))],
    )[0];
    f.tick();
    let row = json!({"source_id":source,"job_id":job,"generation":generation,"sequence":cq});
    let (s, v) = f
        .send("select_row", json!({"row":row,"replace":false}))
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    f.tick();
    let snap = f.snapshot().await;
    let ap = f.contact().a_priori();
    let bits = calls("HB9BLA K1ABC RRR");
    assert_eq!(ap.my_call.map(|b| b.to_vec()), Some(bits[..29].to_vec()));
    assert_eq!(ap.dx_call.map(|b| b.to_vec()), Some(bits[29..58].to_vec()));
    assert_eq!(ap.progress, QsoProgress::Replying);
    assert_eq!(ap.rx_hz, snap["settings"]["rx_hz"].as_f64().unwrap());
    assert_eq!(ap.tx_hz, snap["settings"]["tx_hz"].as_f64().unwrap());
    assert!(ap.cq_only, "Enable Tx was never on");
    r.fixture_publish_period(
        &period_text(p0 + 30_000),
        vec![record("HB9BLA K1ABC -10", 1234.0, Some(-5.0))],
    );
    f.tick();
    assert_eq!(f.contact().a_priori().progress, QsoProgress::RogerReport);
    // Enable Tx on: the station is operating, every type of the state runs.
    f.contact().grant.store(true, Ordering::SeqCst);
    let safety = f.snapshot().await["transmit"]["safety_revision"].clone();
    let (s, v) = f
        .send(
            "enable_tx",
            json!({"enabled":true,"safety_revision":safety}),
        )
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    f.tick();
    assert!(!f.contact().a_priori().cq_only, "Enable Tx on");
    let (s, v) = f
        .send("enable_tx", json!({"enabled":false,"safety_revision":null}))
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    // The 300 s count from the last step that was still transmitting, tuning or armed: a
    // transmission already keyed when Enable Tx went off runs to its end on the real clock,
    // so step on the real clock until the transmitter is idle before moving the time. The
    // PTT is keyed a few ms before the audio starts, so "not transmitting" alone is not idle.
    let deadline = Instant::now() + Duration::from_secs(30);
    loop {
        f.tick();
        let (_, t, _, _) = f.call("GET", "/transmit", None).await;
        if t["transmitting"] == false
            && t["ptt"] == "released"
            && t["transmit"]["pending_sequence"].is_null()
            && t["transmit"]["tune"] == false
            && t["transmit"]["arm_state"] == "disarmed"
        {
            break;
        }
        assert!(Instant::now() < deadline, "transmitter never idle: {t}");
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    f.bench.offset.store(299_000, Ordering::SeqCst);
    f.tick();
    assert!(
        !f.contact().a_priori().cq_only,
        "299 s after Enable Tx went off"
    );
    f.bench.offset.store(301_000, Ordering::SeqCst);
    f.tick();
    assert!(
        f.contact().a_priori().cq_only,
        "301 s after Enable Tx went off"
    );
}

// ---------------------------------------------------------------- #110 QsoSettingsFile
const QSO_FILE: &str = "qso-settings.json";
/// (auto_seq, call_first) as GET /contact `settings` shows them.
async fn seq_and_first(f: &Fixture) -> (Value, Value) {
    let s = f.snapshot().await["settings"].clone();
    (s["auto_seq"].clone(), s["call_first"].clone())
}
async fn set_ok(f: &Fixture, action: &str, enabled: bool) {
    let (s, v) = f.send(action, json!({"enabled":enabled})).await;
    assert_eq!(s, StatusCode::ACCEPTED, "{action} {enabled}: {v}");
}
/// The file as it lies in the profile directory: at most 256 bytes of one JSON value.
fn qso_file(f: &Fixture) -> Value {
    let bytes = std::fs::read(f.dir.join(QSO_FILE)).unwrap();
    assert!(bytes.len() <= 256, "{} bytes", bytes.len());
    serde_json::from_slice(&bytes).unwrap()
}
async fn profile_revision(f: &Fixture) -> Value {
    let (s, v, _, _) = f.call("GET", "/profile", None).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert!(v["revision"].is_u64(), "{v}");
    v["revision"].clone()
}

// Proves: CL-110-01; TC-110-001 (a)-(g). Expected values are CL-110-01 points 1, 2, 3, 5
// and 6 as the issue states them; a station start is a new station owner (new boot id) on
// the same disposable profile directory.
#[tokio::test]
async fn tc_110_001_auto_seq_and_call_first_are_saved_across_a_station_start() {
    let origin = "http://127.0.0.1:18110";
    let (dir, id) = profile_directory(origin, true, "JN37");
    let f = start_station(dir, origin, true);
    // (a) A newly created profile, nothing saved: both on.
    assert!(!f.dir.join(QSO_FILE).exists());
    assert_eq!(seq_and_first(&f).await, (json!(true), json!(true)));
    let revision = profile_revision(&f).await;
    // (b) Call 1st off is accepted and holds after a station start; Auto Seq stays on.
    let at = f.snapshot().await["contact_revision"].as_u64().unwrap();
    let body = f.body(at, "set_call_first", json!({"enabled":false}));
    let (s, receipt, _, _) = f.call("POST", "/contact/command", Some(body.clone())).await;
    assert_eq!(s, StatusCode::ACCEPTED, "{receipt}");
    // Guard of existing behaviour: the same body again is 200 with the same receipt.
    let (s, again, _, _) = f.call("POST", "/contact/command", Some(body)).await;
    assert_eq!((s, &again), (StatusCode::OK, &receipt));
    let first_boot = f.boot.clone();
    let f = f.restart();
    assert_ne!(f.boot, first_boot, "a new station owner");
    assert_eq!(seq_and_first(&f).await, (json!(true), json!(false)), "(b)");
    // (c) Then Auto Seq off: both off after the next start.
    set_ok(&f, "set_auto_seq", false).await;
    let f = f.restart();
    assert_eq!(seq_and_first(&f).await, (json!(false), json!(false)), "(c)");
    // (g) Another, newly created profile has none of it.
    let other = fixture("http://127.0.0.1:18111", true);
    assert_ne!(other.id, id);
    assert_eq!(
        seq_and_first(&other).await,
        (json!(true), json!(true)),
        "(g)"
    );
    assert!(!other.dir.join(QSO_FILE).exists());
    drop(other);
    // (d) Both on again: on because on was saved, not because nothing is there.
    set_ok(&f, "set_auto_seq", true).await;
    set_ok(&f, "set_call_first", true).await;
    let f = f.restart();
    assert_eq!(seq_and_first(&f).await, (json!(true), json!(true)), "(d)");
    assert_eq!(
        qso_file(&f),
        json!({"schema_version":1,"profile_id":id,"auto_seq":true,"call_first":true})
    );
    // (f) Saving never advanced the profile revision.
    assert_eq!(profile_revision(&f).await, revision, "(f)");
    // (e) Two changes without a start between them: the second save keeps the first.
    set_ok(&f, "set_call_first", false).await;
    set_ok(&f, "set_auto_seq", false).await;
    let f = f.restart();
    assert_eq!(seq_and_first(&f).await, (json!(false), json!(false)), "(e)");
    assert_eq!(f.id, id);
}

// Proves: CL-110-01; TC-110-002 (a)-(j). Every file is written by hand into the profile
// directory before the station start; the expected values are the QsoSettingsFile format
// of the issue (exactly {schema_version: 1, profile_id, auto_seq, call_first}, at most
// 256 bytes; anything else: both on, and the next accepted change replaces the file).
#[tokio::test]
async fn tc_110_002_missing_hand_written_and_unusable_files() {
    let origin = "http://127.0.0.1:18112";
    fn padded(text: String, bytes: usize) -> String {
        let spaces = " ".repeat(bytes - text.len());
        format!("{text}{spaces}")
    }
    fn object(id: &str, rest: &str) -> String {
        format!(r#"{{"schema_version":1,"profile_id":"{id}",{rest}}}"#)
    }
    fn positive(id: &str) -> String {
        object(id, r#""auto_seq":false,"call_first":true"#)
    }
    let other_id = profile::new_uuid().unwrap();
    type Case = (&'static str, Box<dyn Fn(&str) -> String>, (bool, bool));
    let on = (true, true);
    let cases: Vec<Case> = vec![
        ("(a) hand-written", Box::new(positive), (false, true)),
        (
            "(b) 256 bytes",
            Box::new(|id| padded(positive(id), 256)),
            (false, true),
        ),
        (
            "(c) 257 bytes",
            Box::new(|id| padded(positive(id), 257)),
            on,
        ),
        ("(d) empty", Box::new(|_| String::new()), on),
        (
            "(e) truncated",
            Box::new(|id| format!(r#"{{"schema_version":1,"profile_id":"{id}","auto_seq":fal"#)),
            on,
        ),
        (
            "(f) schema_version 2",
            Box::new(|id| {
                format!(
                    r#"{{"schema_version":2,"profile_id":"{id}","auto_seq":false,"call_first":false}}"#
                )
            }),
            on,
        ),
        (
            "(g) another profile's id",
            Box::new(move |_| object(&other_id, r#""auto_seq":false,"call_first":false"#)),
            on,
        ),
        (
            "(h) extra key",
            Box::new(|id| object(id, r#""auto_seq":false,"call_first":false,"tx1_skip":true"#)),
            on,
        ),
        (
            "(h) missing key",
            Box::new(|id| object(id, r#""auto_seq":false"#)),
            on,
        ),
        (
            "(i) a string",
            Box::new(|id| object(id, r#""auto_seq":"false","call_first":false"#)),
            on,
        ),
        (
            "(i) a number",
            Box::new(|id| object(id, r#""auto_seq":false,"call_first":0"#)),
            on,
        ),
    ];
    assert_eq!(cases.len(), 11);
    for (name, content, expected) in cases {
        let (dir, id) = profile_directory(origin, true, "JN37");
        let text = content(&id);
        match name {
            "(b) 256 bytes" => assert_eq!(text.len(), 256),
            "(c) 257 bytes" => assert_eq!(text.len(), 257),
            _ => {}
        }
        std::fs::write(dir.join(QSO_FILE), &text).unwrap();
        // The station start succeeds and GET /contact answers 200 (asserted in snapshot).
        let f = start_station(dir, origin, true);
        assert_eq!(
            seq_and_first(&f).await,
            (json!(expected.0), json!(expected.1)),
            "{name}"
        );
        if matches!(name, "(a) hand-written" | "(b) 256 bytes") {
            continue;
        }
        // (j) The next accepted change replaces the unusable file with a valid one.
        set_ok(&f, "set_call_first", false).await;
        let valid = json!({"schema_version":1,"profile_id":id,"auto_seq":true,"call_first":false});
        assert_eq!(qso_file(&f), valid, "{name}");
        let f = f.restart();
        assert_eq!(
            seq_and_first(&f).await,
            (json!(true), json!(false)),
            "{name}"
        );
    }
}

/// Every entry of the profile directory with its bytes (a directory by name only).
fn directory_content(dir: &std::path::Path) -> Vec<(String, Option<Vec<u8>>)> {
    let mut entries: Vec<_> = std::fs::read_dir(dir)
        .unwrap()
        .map(|e| {
            let e = e.unwrap();
            let name = e.file_name().to_string_lossy().into_owned();
            (name, std::fs::read(e.path()).ok())
        })
        .collect();
    entries.sort();
    entries
}

// Proves: CL-110-01; TC-110-003 (a)-(c). The fault is the profile store's test seam at the
// replace of the file (profile::tests::with_fault "replace"); the command runs through
// Station::operate, the browser's validation and execution, on the test's own thread, which
// is where the seam acts. Expected values are CL-110-01 point 4.
#[tokio::test]
async fn tc_110_003_a_failed_save_refuses_the_change_and_changes_nothing() {
    let f = fixture("http://127.0.0.1:18113", true);
    // Saved state: Call 1st on.
    set_ok(&f, "set_call_first", true).await;
    assert_eq!(qso_file(&f)["call_first"], true);
    let before = f.snapshot().await;
    let revision = before["contact_revision"].as_u64().unwrap();
    let on_disk = directory_content(&f.dir);
    // (a) The replace fails: refused storage_unavailable, field null, nothing changed.
    let body = f.body(revision, "set_call_first", json!({"enabled":false}));
    let refused =
        profile::tests::with_fault("replace", || f.contact().operate(&f.state, body, false));
    assert_eq!(refused, Err(("storage_unavailable", None)));
    let after = f.snapshot().await;
    assert_eq!(after["settings"], before["settings"]);
    assert_eq!(after["settings"]["call_first"], true);
    assert_eq!(after["contact_revision"], before["contact_revision"]);
    assert_eq!(
        directory_content(&f.dir),
        on_disk,
        "the directory is as it was"
    );
    // (c) Guard of existing behaviour: a setting that is not saved does not need storage.
    let body = f.body(revision, "set_hold_tx", json!({"enabled":false}));
    let accepted =
        profile::tests::with_fault("replace", || f.contact().operate(&f.state, body, false));
    assert_eq!(accepted.map(|(status, _)| status), Ok(StatusCode::ACCEPTED));
    assert_eq!(directory_content(&f.dir), on_disk);
    // (b) Storage is back: the same action with a new command_id is saved.
    set_ok(&f, "set_call_first", false).await;
    assert_eq!(seq_and_first(&f).await, (json!(true), json!(false)));
    let f = f.restart();
    assert_eq!(seq_and_first(&f).await, (json!(true), json!(false)));
}

// Proves: CL-111-01, CL-111-02, CL-111-03, CL-111-06.
// Proves: TC-111-002, TC-111-003, TC-111-007, TC-111-009, TC-111-010.
// TC-111-002: snapshot reload and repeated command_id. TC-111-003: each start is one
// ContactCommand with its safety revision. TC-111-007: the causes on the wire. TC-111-009: the
// station's band reaches the engine. TC-111-010 (b) on the wire. The station: router, contact
// engine and transmit owner on the recording double. Expected values are the tables of
// CL-111-02 and CL-111-03.
#[tokio::test]
async fn tc_111_starts_are_single_commands_and_a_band_change_stops_the_station() {
    let f = fixture("http://127.0.0.1:18001", true);
    let r = &f.state.recording;
    r.fixture_band("20m");
    let (source, job, generation) = r.fixture_live_job("ft8");
    let even = now_ms().div_euclid(30_000) * 30_000;
    let seq = r.fixture_publish_period(
        &period_text(even),
        vec![record("CQ K1ABC FN42", 1234.6, Some(-12.4))],
    );
    f.tick();
    f.contact().grant.store(true, Ordering::SeqCst);
    let row = json!({"source_id":source,"job_id":job,"generation":generation,"sequence":seq[0]});
    let shown = f.snapshot().await["transmit"]["safety_revision"].clone();
    assert_eq!(shown, json!(3));
    let state = |v: &Value| {
        (
            v["transmit"]["arm_state"].as_str().map(str::to_owned),
            v["transmit"]["last_disarm_cause"]
                .as_str()
                .map(str::to_owned),
            v["transmit"]["last_arm_cause"].as_str().map(str::to_owned),
        )
    };
    let off_at_start = (Some("disarmed".into()), Some("startup".into()), None);
    // Every start carries the safety revision shown to its sender: without it the request is
    // invalid, with another one it is stale and nothing is prepared.
    let starts = [
        ("reply", json!({"row":row})),
        ("call_cq", json!({})),
        (
            "call_dx",
            json!({"dx_call":"K1ABC","dx_grid":null,"replace":false}),
        ),
        ("send_next", json!({"slot":"tx2"})),
        ("reset_repetitions", json!({})),
    ];
    for (action, extra) in &starts {
        let (s, v) = f.send(action, extra.clone()).await;
        assert_eq!(
            (s, code(&v)),
            (
                StatusCode::BAD_REQUEST,
                ("invalid_request", Some("safety_revision"))
            ),
            "{action}"
        );
    }
    for (action, extra) in &starts[..3] {
        for stale in [json!(2), Value::Null] {
            let mut extra = extra.clone();
            extra["safety_revision"] = stale;
            let (s, v) = f.send(action, extra).await;
            assert_eq!(
                (s, code(&v)),
                (
                    StatusCode::CONFLICT,
                    ("stale_revision", Some("safety_revision"))
                ),
                "{action}"
            );
        }
    }
    let snap = f.snapshot().await;
    assert_eq!(snap["contact"], Value::Null, "nothing is prepared");
    assert_eq!(state(&snap), off_at_start);
    // TC-111-002: a selection, its repeated command_id and a reloaded snapshot never start.
    let revision = snap["contact_revision"].as_u64().unwrap();
    let select = f.body(revision, "select_row", json!({"row":row,"replace":false}));
    let (s, receipt, _, _) = f
        .call("POST", "/contact/command", Some(select.clone()))
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{receipt}");
    let (s, again, _, _) = f.call("POST", "/contact/command", Some(select)).await;
    assert_eq!((s, &again), (StatusCode::OK, &receipt));
    for _ in 0..5 {
        f.tick();
        let snap = f.snapshot().await;
        assert_eq!(state(&snap), off_at_start, "a reload changes nothing");
        assert_eq!(snap["transmit"]["pending_sequence"], Value::Null);
    }
    let (_, t, _, _) = f.call("GET", "/transmit", None).await;
    assert_eq!(t["outcomes"], json!([]), "no TransmitRequest");
    // Tune on needs the shown revision too (CL-111-06); Tune off needs none.
    let (s, v) = f.send("tune", json!({"enabled":true})).await;
    assert_eq!(
        (s, code(&v)),
        (
            StatusCode::CONFLICT,
            ("stale_revision", Some("safety_revision"))
        )
    );
    let (s, v) = f.send("tune", json!({"enabled":false})).await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    // Reply: one command prepares the row's QSO and switches on, cause operator.
    let revision = f.snapshot().await["contact_revision"].as_u64().unwrap();
    let reply = f.body(
        revision,
        "reply",
        json!({"row":row,"safety_revision":shown}),
    );
    let (s, receipt, _, _) = f
        .call("POST", "/contact/command", Some(reply.clone()))
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{receipt}");
    let snap = f.snapshot().await;
    assert_eq!(
        state(&snap),
        (
            Some("armed".into()),
            Some("startup".into()),
            Some("operator".into())
        )
    );
    assert_eq!(
        (
            snap["contact"]["dx_call"].as_str(),
            snap["contact"]["state"].as_str()
        ),
        (Some("K1ABC"), Some("replying"))
    );
    assert!(snap["transmit"]["pending_sequence"].is_u64(), "planned");
    let contact = snap["contact"]["id"].clone();
    // Its repeated command_id replays the receipt: still exactly one request.
    let (s, again, _, _) = f.call("POST", "/contact/command", Some(reply)).await;
    assert_eq!((s, &again), (StatusCode::OK, &receipt));
    let (_, t, _, _) = f.call("GET", "/transmit", None).await;
    let accepted = t["outcomes"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|o| o["kind"] == "accepted")
        .count();
    assert_eq!(accepted, 1, "{t}");
    // Send next and Reset act on the QSO and leave the state on.
    let (s, v) = f
        .send("send_next", json!({"slot":"tx2","safety_revision":shown}))
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    let (s, v) = f
        .send("reset_repetitions", json!({"safety_revision":shown}))
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    let snap = f.snapshot().await;
    assert_eq!(snap["contact"]["next_slot"], "tx2");
    assert_eq!(snap["contact"]["id"], contact);
    assert_eq!(snap["transmit"]["arm_state"], "armed");
    // CQ and Call during the QSO: contact_active; Call with replace starts the other partner.
    let (s, v) = f.send("call_cq", json!({"safety_revision":shown})).await;
    assert_eq!((s, code(&v).0), (StatusCode::CONFLICT, "contact_active"));
    let call = |replace: bool| json!({"dx_call":"DL1XYZ","dx_grid":"JO62","replace":replace,"safety_revision":shown});
    let (s, v) = f.send("call_dx", call(false)).await;
    assert_eq!((s, code(&v).0), (StatusCode::CONFLICT, "contact_active"));
    let (s, v) = f.send("call_dx", call(true)).await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    let snap = f.snapshot().await;
    assert_eq!(snap["contact"]["dx_call"], "DL1XYZ");
    assert_ne!(snap["contact"]["id"], contact);
    assert_eq!(snap["transmit"]["arm_state"], "armed");
    // TC-111-009: the station band changes (20 m to 40 m): off, band_changed, cancelled.
    r.fixture_band("40m");
    f.tick();
    let snap = f.snapshot().await;
    assert_eq!(
        state(&snap),
        (
            Some("disarmed".into()),
            Some("band_changed".into()),
            Some("operator".into())
        )
    );
    assert_eq!(
        (
            snap["contact"]["state"].as_str(),
            &snap["contact"]["dx_call"]
        ),
        (Some("cancelled"), &Value::Null)
    );
    assert_eq!(snap["transmit"]["pending_sequence"], Value::Null);
    // The CQ start calls CQ on the new band.
    f.tick();
    let (s, v) = f.send("call_cq", json!({"safety_revision":shown})).await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    let snap = f.snapshot().await;
    assert_eq!(snap["contact"]["state"], "calling");
    assert_eq!(snap["transmit"]["arm_state"], "armed");
}

// ------------------------------------------------------------------ #85
// Never the same station twice in a row in the log (CL-085-01 to -03). The actual router,
// station step, log and UDP owner with a loopback target; the #9 transmit owner on the
// recording double on a virtual UTC. Expected outcomes are the hand-written rule table of
// CL-085-01 (refused: no record, nothing at the target, `same_station_again`), never output.

/// A loopback UDP target that selects QSO Logged and Logged ADIF, installed before the owner
/// opens (no default target is activated).
fn udp_target_85(f: &Fixture) -> std::net::UdpSocket {
    let peer = std::net::UdpSocket::bind("127.0.0.1:0").unwrap();
    peer.set_read_timeout(Some(std::time::Duration::from_millis(150)))
        .unwrap();
    let doc = json!({"schema_version":1,"profile_id":f.id,"revision":0,"targets":[{
        "address":peer.local_addr().unwrap().to_string(),"enabled":true,"multicast_ttl":1,
        "multicast_interface":null,"messages":["qso_logged","logged_adif"]}]});
    std::fs::write(
        f.dir.join(crate::udp::FILE_NAME),
        serde_json::to_vec(&doc).unwrap(),
    )
    .unwrap();
    let owner = crate::udp::Owner::open(&f.state, false, &f.dir.join("udp-instance"));
    assert!(f.state.recording.udp.set(owner.clone()).is_ok());
    owner.step(&f.state);
    datagrams_85(&peer);
    peer
}
/// The message types (QDataStream u32 at bytes 8..12) the target received since the last call.
fn datagrams_85(peer: &std::net::UdpSocket) -> Vec<u32> {
    let mut kinds = Vec::new();
    let mut b = [0u8; 8192];
    while let Ok((n, _)) = peer.recv_from(&mut b) {
        assert!(n >= 12);
        kinds.push(u32::from_be_bytes([b[8], b[9], b[10], b[11]]));
    }
    kinds
}
fn calls_85(f: &Fixture) -> Vec<String> {
    f.state.logbook.history(&f.id, 0, 50).unwrap()["records"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["call"].as_str().unwrap().to_owned())
        .collect()
}
fn log_file_85(f: &Fixture) -> Option<Vec<u8>> {
    std::fs::read(f.dir.join(crate::logbook::FILE_NAME)).ok()
}
/// FT8 on a virtual UTC: the partner's messages are published 13 s into his (even) period,
/// my transmissions (odd) are recorded from the transmit owner's view.
struct Air85<'a> {
    f: &'a Fixture,
    p0: i64,
    t: i64,
    job: (String, String, u64),
    sent: Vec<(i64, String)>,
}
impl<'a> Air85<'a> {
    fn new(f: &'a Fixture) -> Self {
        let job = f.state.recording.fixture_live_job("ft8");
        f.contact().grant.store(true, Ordering::SeqCst);
        // An even FT8 period (a multiple of 30 s).
        let p0 = now_ms().div_euclid(30_000) * 30_000 + 60_000;
        let mut air = Self {
            f,
            p0,
            t: p0 - 1_000,
            job,
            sent: Vec::new(),
        };
        air.to(p0);
        air
    }
    fn p(&self, n: i64) -> i64 {
        self.p0 + n * 15_000
    }
    fn to(&mut self, until: i64) {
        let service = &self.f.state.recording.transmit.get().unwrap().service;
        while self.t < until {
            self.t += 100;
            self.f.bench.frozen.store(self.t, Ordering::SeqCst);
            service.with(|c| c.tick());
            self.f.tick();
            let v = service.view();
            if let (Some(p), Some(text)) = (v.last_period_utc_ms, v.last_text.clone())
                && self.sent.last().is_none_or(|(q, x)| *q != p || *x != text)
            {
                self.sent.push((p, text));
            }
        }
    }
    /// The partner's `text` in period `n`; returns its row.
    fn hear(&mut self, n: i64, text: &str) -> Value {
        self.to(self.p(n) + 13_000);
        let seq = self.f.state.recording.fixture_publish_period(
            &period_text(self.p(n)),
            vec![record(text, 1500.0, Some(-9.0))],
        )[0];
        self.f.tick();
        let (source, job, generation) = &self.job;
        json!({"source_id":source,"job_id":job,"generation":generation,"sequence":seq})
    }
    fn sent_in(&self, n: i64) -> Vec<&str> {
        self.sent
            .iter()
            .filter(|(p, _)| *p == self.p(n))
            .map(|(_, t)| t.as_str())
            .collect()
    }
    /// My transmissions from period `n` on.
    fn sent_from(&self, n: i64) -> Vec<(i64, &str)> {
        self.sent
            .iter()
            .filter(|(p, _)| *p >= self.p(n))
            .map(|(p, t)| ((p - self.p0) / 15_000, t.as_str()))
            .collect()
    }
}
/// Reply (#111): one command selects the row and starts, with the safety revision shown.
async fn reply_85(f: &Fixture, row: &Value) {
    let (s, v) = f
        .send("reply", json!({"row":row,"safety_revision":3}))
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "reply: {v}");
}
/// A whole QSO with `call` from his CQ in period `n` to my 73 in n+5; returns the period
/// after it.
async fn qso_from_cq_85(air: &mut Air85<'_>, n: i64, call: &str) -> i64 {
    let cq = air.hear(n, &format!("CQ {call} FN42"));
    reply_85(air.f, &cq).await;
    air.hear(n + 2, &format!("HB9BLA {call} -09"));
    air.hear(n + 4, &format!("HB9BLA {call} RR73"));
    air.to(air.p(n + 6));
    assert_eq!(
        air.sent_from(n),
        [
            (n + 1, format!("{call} HB9BLA JN47").as_str()),
            (n + 3, format!("{call} HB9BLA R-09").as_str()),
            (n + 5, format!("{call} HB9BLA 73").as_str()),
        ],
        "the exchange with {call}"
    );
    let snap = air.f.snapshot().await;
    assert_eq!(snap["contact"]["state"], "completed", "{snap}");
    assert_eq!(snap["transmit"]["arm_state"], "disarmed", "{snap}");
    n + 6
}

// Proves: CL-085-01, CL-085-02; TC-085-001 (a), (b), (c), (d); TC-085-002 (a), (g)
// Proves: TC-085-005 (b). On the air with K1ABC: the first QSO is logged (one record, one QSO Logged and
// one Logged ADIF); his repeated RR73 answered again, a whole second exchange from his CQ and a
// QSO after my CQ answered with his grid (Call 1st) complete as usual and add nothing; after a
// QSO with W1AW, K1ABC is logged again. CL-040-01 (one pair per saved record) is the guard.
#[tokio::test]
async fn tc_085_001_the_same_station_in_a_row_is_not_logged() {
    let f = fixture("http://127.0.0.1:18085", true);
    let target = udp_target_85(&f);
    let mut air = Air85::new(&f);
    // (g) An empty log: the first QSO is logged (guard).
    let n = qso_from_cq_85(&mut air, 0, "K1ABC").await;
    assert_eq!(calls_85(&f), ["K1ABC"]);
    assert_eq!(datagrams_85(&target), [5, 12], "QSO Logged, Logged ADIF");
    let first = f.snapshot().await;
    assert_eq!(first["contact"]["saved"], true);
    let file = log_file_85(&f);

    // (a) His RR73 again: Reply sends one 73; the contact completes, transmission off; nothing
    // is written or sent, and the contact is not saved.
    let rr73 = air.hear(n, "HB9BLA K1ABC RR73");
    reply_85(&f, &rr73).await;
    let snap = f.snapshot().await;
    assert_eq!(
        (
            snap["contact"]["state"].as_str(),
            snap["contact"]["next_slot"].as_str()
        ),
        (Some("signoff"), Some("tx5"))
    );
    assert_ne!(
        snap["contact"]["id"], first["contact"]["id"],
        "a new contact"
    );
    air.to(air.p(n + 2));
    assert_eq!(air.sent_from(n), [(n + 1, "K1ABC HB9BLA 73")], "one 73");
    let (status, snap, _, bytes) = f.call("GET", "/contact", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(snap["contact"]["state"], "completed");
    assert_eq!(snap["transmit"]["arm_state"], "disarmed");
    assert_eq!(snap["contact"]["saved"], false);
    assert_eq!(log_file_85(&f), file, "contacts.adi is byte-identical");
    assert!(datagrams_85(&target).is_empty(), "nothing at the target");
    // TC-085-005 (b): the log member names the refused contact; the snapshot stays bounded.
    assert_eq!(
        snap["log"],
        json!({"contact_id":snap["contact"]["id"],"call":"K1ABC","outcome":"unsaved",
            "error":"same_station_again"})
    );
    assert!(bytes <= 4096, "{bytes} bytes");
    let n = n + 2;

    // (b), (d) A complete second exchange from his CQ: the third QSO in a row, still one record.
    let n = qso_from_cq_85(&mut air, n, "K1ABC").await;
    assert_eq!(calls_85(&f), ["K1ABC"]);
    assert_eq!(log_file_85(&f), file);
    assert!(datagrams_85(&target).is_empty());
    assert_eq!(f.snapshot().await["log"]["error"], "same_station_again");

    // TC-085-002 (a) K1ABC, W1AW, K1ABC: each is logged.
    let n = qso_from_cq_85(&mut air, n, "W1AW").await;
    let n = qso_from_cq_85(&mut air, n, "K1ABC").await;
    assert_eq!(calls_85(&f), ["K1ABC", "W1AW", "K1ABC"]);
    assert_eq!(datagrams_85(&target), [5, 12, 5, 12]);
    let snap = f.snapshot().await;
    assert_eq!(
        snap["log"],
        json!({"contact_id":snap["contact"]["id"],"call":"K1ABC","outcome":"saved","error":null})
    );
    let file = log_file_85(&f);

    // (c) My CQ answered by K1ABC with his grid (Call 1st); it completes on his 73: no record.
    let (s, v) = f.send("set_call_first", json!({"enabled":true})).await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    let (s, v) = f.send("call_cq", json!({"safety_revision":3})).await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");
    air.hear(n + 2, "HB9BLA K1ABC FN42");
    air.hear(n + 4, "HB9BLA K1ABC R-05");
    air.hear(n + 6, "HB9BLA K1ABC 73");
    air.to(air.p(n + 7));
    assert_eq!(
        air.sent_from(n),
        [
            (n + 1, "CQ HB9BLA JN47"),
            (n + 3, "K1ABC HB9BLA -09"),
            (n + 5, "K1ABC HB9BLA RRR"),
        ]
    );
    let snap = f.snapshot().await;
    assert_eq!(snap["contact"]["state"], "completed", "{snap}");
    assert_eq!(snap["log"]["error"], "same_station_again");
    assert_eq!(log_file_85(&f), file);
    assert!(datagrams_85(&target).is_empty());
    assert!(air.sent_in(n + 7).is_empty());
}

/// 2026-11-01T12:34:30Z, an even FT8 period.
const P85: i64 = 1_793_536_470_000;
fn operate_85(f: &Fixture, action: &str, extra: Value) {
    let (revision, _, _) = f.contact().facts();
    let body = f.body(revision, action, extra);
    f.contact()
        .operate(&f.state, body, false)
        .unwrap_or_else(|e| panic!("{action}: {e:?}"));
}
/// The partner's `text` in the FT8 period at `period`, then one station step 14 s into it.
fn partner_85(f: &Fixture, period: i64, text: &str) {
    f.state
        .recording
        .fixture_publish_period(&period_text(period), vec![record(text, 1500.0, Some(-9.0))]);
    f.bench.frozen.store(period + 14_000, Ordering::SeqCst);
    f.tick();
}
/// A QSO with `call` entered at `at` and completed in rogers by his R-09 and 73 (no
/// transmission is needed for the log).
fn entered_qso_85(f: &Fixture, at: i64, call: &str) {
    f.bench.frozen.store(at, Ordering::SeqCst);
    operate_85(
        f,
        "enter_dx",
        json!({"dx_call":call,"dx_grid":null,"replace":true}),
    );
    partner_85(f, at + 30_000, &format!("HB9BLA {call} R-09"));
    partner_85(f, at + 60_000, &format!("HB9BLA {call} 73"));
    assert_eq!(
        f.contact().facts().1.unwrap().state,
        "completed",
        "{call} completed: {}",
        String::from_utf8(f.contact().snapshot(&f.state).unwrap()).unwrap()
    );
}
fn log_view_85(f: &Fixture) -> Value {
    let bytes = f.contact().snapshot(&f.state).unwrap();
    serde_json::from_slice::<Value>(&bytes).unwrap()["log"].clone()
}
fn refused_85(f: &Fixture, call: &str) -> Value {
    json!({"contact_id":f.contact().facts().1.unwrap().id,"call":call,"outcome":"unsaved",
        "error":"same_station_again"})
}

// Proves: CL-085-01, CL-085-02; TC-085-001 (e), (f); TC-085-002 (h), (i); TC-085-003 (a), (b),
// (e). Log QSO of a running second QSO with the station logged last closes it and writes
// nothing; a cancelled or an invalid (log_invalid_field) first QSO leaves the next one with that
// station logged; a pending first record is the newest QSO; the stored log is read again after a
// restart; SaveContact stores what it is given (L5).
#[tokio::test(flavor = "multi_thread")]
async fn tc_085_001_log_qso_pending_records_and_restart() {
    let f = fixture("http://127.0.0.1:18086", false);
    f.state.recording.fixture_live_job("ft8");
    let target = udp_target_85(&f);
    // (h) A cancelled QSO with K1ABC logs nothing.
    f.bench.frozen.store(P85 - 10_000, Ordering::SeqCst);
    operate_85(
        &f,
        "enter_dx",
        json!({"dx_call":"K1ABC","dx_grid":null,"replace":true}),
    );
    operate_85(&f, "cancel", json!({}));
    // (i) A QSO with K1ABC closed by Log QSO while the profile has no callsign is refused
    // log_invalid_field and writes nothing either.
    f.bench.frozen.store(P85, Ordering::SeqCst);
    operate_85(
        &f,
        "enter_dx",
        json!({"dx_call":"K1ABC","dx_grid":null,"replace":true}),
    );
    partner_85(&f, P85 + 30_000, "HB9BLA K1ABC R-09");
    f.state.store.lock().unwrap().document.callsign = String::new();
    operate_85(&f, "open_log", json!({}));
    f.state.store.lock().unwrap().document.callsign = "HB9BLA".into();
    assert_eq!(log_view_85(&f)["error"], "log_invalid_field");
    assert!(calls_85(&f).is_empty());
    // Then a valid QSO with K1ABC is logged.
    entered_qso_85(&f, P85 + 90_000, "K1ABC");
    assert_eq!(calls_85(&f), ["K1ABC"]);
    assert_eq!(datagrams_85(&target), [5, 12]);
    let file = log_file_85(&f);
    // (f) Log QSO again on the logged contact changes nothing (guard).
    operate_85(&f, "open_log", json!({}));
    f.tick();
    assert_eq!(log_file_85(&f), file);
    assert!(datagrams_85(&target).is_empty());

    // (e) Log QSO during a running second QSO with K1ABC: closed (completed, Tx6), no record.
    f.bench.frozen.store(P85 + 180_000, Ordering::SeqCst);
    operate_85(
        &f,
        "enter_dx",
        json!({"dx_call":"K1ABC","dx_grid":null,"replace":true}),
    );
    partner_85(&f, P85 + 210_000, "HB9BLA K1ABC R-05");
    assert_eq!(f.contact().facts().1.unwrap().state, "rogers");
    operate_85(&f, "open_log", json!({}));
    f.tick();
    let snap: Value = serde_json::from_slice(&f.contact().snapshot(&f.state).unwrap()).unwrap();
    assert_eq!(
        (
            snap["contact"]["state"].as_str(),
            snap["contact"]["next_slot"].as_str(),
            snap["transmit"]["arm_state"].as_str()
        ),
        (Some("completed"), Some("tx6"), Some("disarmed"))
    );
    assert_eq!(snap["log"], refused_85(&f, "K1ABC"));
    assert_eq!(log_file_85(&f), file);
    assert!(datagrams_85(&target).is_empty());

    // TC-085-003 (b) The first record of W1AW is pending after a failed write; a second QSO
    // with W1AW completes meanwhile and is refused. The retry stores one record, one pair.
    f.state.logbook.inject_fault(Some("write"));
    entered_qso_85(&f, P85 + 300_000, "W1AW");
    assert_eq!(log_view_85(&f)["error"], "storage_unavailable");
    entered_qso_85(&f, P85 + 390_000, "W1AW");
    assert_eq!(log_view_85(&f), refused_85(&f, "W1AW"));
    f.state.logbook.inject_fault(None);
    f.contact().retry_logs_now();
    f.tick();
    assert_eq!(calls_85(&f), ["K1ABC", "W1AW"]);
    assert_eq!(datagrams_85(&target), [5, 12]);

    // TC-085-003 (a) K1ABC logged, the station restarted: the next K1ABC is not logged.
    entered_qso_85(&f, P85 + 480_000, "K1ABC");
    assert_eq!(calls_85(&f), ["K1ABC", "W1AW", "K1ABC"]);
    let file = log_file_85(&f);
    let f = f.restart();
    f.state.recording.fixture_live_job("ft8");
    entered_qso_85(&f, P85 + 600_000, "K1ABC");
    assert_eq!(log_view_85(&f), refused_85(&f, "K1ABC"));
    assert_eq!(log_file_85(&f), file, "the file is unchanged");

    // TC-085-003 (e) SaveContact of a K1ABC record right after it: stored as today (guard).
    let body = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),
        "record":{"contact_id":profile::new_uuid().unwrap(),"call":"K1ABC","gridsquare":null,"mode":"FT8",
        "submode":null,"rst_sent":"-12","rst_rcvd":"-09","qso_date":"20261101","time_on":"124500",
        "qso_date_off":"20261101","time_off":"124600","band":null,"freq":null,
        "station_callsign":"HB9BLA","my_gridsquare":"JN47AA","tx_pwr":null,"comment":null}});
    let (s, v, _, _) = f.call("POST", "/contacts", Some(body)).await;
    assert_eq!(s, StatusCode::CREATED, "{v}");
    assert_eq!(calls_85(&f), ["K1ABC", "W1AW", "K1ABC", "K1ABC"]);
}

/// Makes the built-in contest strategy `name` of the contest `id` the active strategy (class
/// contest), with its contest selected for 2026-11-01.
fn contest_strategy_85(f: &Fixture, name: &str, id: &str) {
    let owner = &f.contact().strategy;
    let mut configuration = owner.config(&f.state).unwrap().json();
    configuration["active"] = json!(name);
    configuration["contest"] =
        json!({"profile":id,"start":"2026-11-01T00:00Z","end":"2026-11-02T00:00Z"});
    let body = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,
        "expected_revision":owner.revision(),"configuration":configuration});
    owner.put(&f.state, body).unwrap();
}
fn snap_85(f: &Fixture) -> Value {
    serde_json::from_slice(&f.contact().snapshot(&f.state).unwrap()).unwrap()
}
/// A QSO with `call` (grid `grid`) entered at `at` and closed by Log QSO.
fn log_qso_85(f: &Fixture, at: i64, call: &str, grid: Option<&str>) {
    f.bench.frozen.store(at, Ordering::SeqCst);
    operate_85(
        f,
        "enter_dx",
        json!({"dx_call":call,"dx_grid":grid,"replace":true}),
    );
    operate_85(f, "open_log", json!({}));
    f.tick();
    assert_eq!(f.contact().facts().1.unwrap().state, "completed");
}

// Proves: CL-085-03, CL-085-02, CL-085-01; TC-085-004 (a)-(e). Under a contest (the active
// strategy is of class contest) the serial counts only when the log accepts the contact: a
// second QSO in a row with K1ABC (a dupe under the contest's rule) keeps the serial and the next
// station is sent the same one; under band_grid a rover from a new grid is logged and counts; a
// record refused log_invalid_field is accepted for the answer and counts (L6).
#[tokio::test(flavor = "multi_thread")]
async fn tc_085_004_the_contest_serial_counts_only_on_accepted() {
    let f = fixture("http://127.0.0.1:18089", false);
    f.state.recording.fixture_live_job("ft8");
    contest_strategy_85(&f, "ARRL Digi", "arrl_digi");
    operate_85(
        &f,
        "set_activity",
        json!({"activity":"rtty","exchange":"DX"}),
    );
    let serial = |f: &Fixture| snap_85(f)["settings"]["serial"].as_u64().unwrap();
    assert_eq!(serial(&f), 1);
    // (a) K1ABC logged with 0001; a second QSO with K1ABC sends 0002 and completes: no record,
    // the serial stays 2, and the next station is sent 0002.
    let rtty = |at: i64, call: &str| {
        f.bench.frozen.store(at, Ordering::SeqCst);
        operate_85(
            &f,
            "enter_dx",
            json!({"dx_call":call,"dx_grid":null,"replace":true}),
        );
        // The serial my Tx2 sends (its last word; the RST follows the report).
        let tx2 = snap_85(&f)["contact"]["messages"][1].clone();
        let sent = tx2.as_str().unwrap().rsplit(' ').next().unwrap().to_owned();
        partner_85(&f, at + 30_000, &format!("HB9BLA {call} R 579 MA"));
        partner_85(&f, at + 60_000, &format!("HB9BLA {call} 73"));
        assert_eq!(f.contact().facts().1.unwrap().state, "completed", "{call}");
        sent
    };
    assert_eq!(rtty(P85, "K1ABC"), "0001");
    assert_eq!(calls_85(&f), ["K1ABC"]);
    assert_eq!(serial(&f), 2);
    assert_eq!(rtty(P85 + 90_000, "K1ABC"), "0002");
    assert_eq!(snap_85(&f)["log"], refused_85(&f, "K1ABC"));
    assert_eq!(calls_85(&f), ["K1ABC"]);
    assert_eq!(serial(&f), 2, "not counted on refused");
    f.bench.frozen.store(P85 + 180_000, Ordering::SeqCst);
    operate_85(
        &f,
        "enter_dx",
        json!({"dx_call":"W1AW","dx_grid":null,"replace":true}),
    );
    let tx2 = snap_85(&f)["contact"]["messages"][1].clone();
    assert!(
        tx2.as_str().unwrap().starts_with("W1AW HB9BLA ")
            && tx2.as_str().unwrap().ends_with(" 0002"),
        "the next station is sent the same serial: {tx2}"
    );
    // (b) The same with the second QSO closed by Log QSO.
    log_qso_85(&f, P85 + 210_000, "K1ABC", None);
    assert_eq!(snap_85(&f)["log"], refused_85(&f, "K1ABC"));
    assert_eq!(serial(&f), 2);
    // (c) K1ABC, W1AW, K1ABC: three records, three counts (guard).
    log_qso_85(&f, P85 + 240_000, "W1AW", None);
    log_qso_85(&f, P85 + 270_000, "K1ABC", None);
    assert_eq!(calls_85(&f), ["K1ABC", "W1AW", "K1ABC"]);
    assert_eq!(serial(&f), 4);
    // (e) A record refused log_invalid_field (no profile callsign): accepted, the serial counts.
    f.bench.frozen.store(P85 + 300_000, Ordering::SeqCst);
    operate_85(
        &f,
        "enter_dx",
        json!({"dx_call":"DL1ABC","dx_grid":null,"replace":true}),
    );
    f.state.store.lock().unwrap().document.callsign = String::new();
    operate_85(&f, "open_log", json!({}));
    f.state.store.lock().unwrap().document.callsign = "HB9BLA".into();
    assert_eq!(snap_85(&f)["log"]["error"], "log_invalid_field");
    assert_eq!(serial(&f), 5);

    // (d) na_vhf under ARRL June VHF (band_grid): K1ABC/R from FN42 logged; from FN42 again
    // directly after it not logged; from FN43 directly after the first logged, serial counted.
    contest_strategy_85(&f, "ARRL June VHF", "arrl_vhf_jun");
    operate_85(
        &f,
        "set_activity",
        json!({"activity":"na_vhf","exchange":null}),
    );
    log_qso_85(&f, P85 + 330_000, "K1ABC/R", Some("FN42"));
    assert_eq!(snap_85(&f)["log"]["outcome"], "saved");
    let n = serial(&f);
    log_qso_85(&f, P85 + 360_000, "K1ABC/R", Some("FN42"));
    assert_eq!(snap_85(&f)["log"], refused_85(&f, "K1ABC/R"));
    assert_eq!(serial(&f), n);
    log_qso_85(&f, P85 + 390_000, "K1ABC/R", Some("FN43"));
    assert_eq!(snap_85(&f)["log"]["outcome"], "saved");
    assert_eq!(serial(&f), n + 1);
    assert_eq!(
        calls_85(&f),
        ["K1ABC", "W1AW", "K1ABC", "K1ABC/R", "K1ABC/R"]
    );
}

// Proves: CL-085-01; TC-085-001 (g). With Auto on, after a QSO made by hand with K1ABC, the
// strategy run answers K1ABC calling me and the QSO completes: no record, and Auto goes on. The
// HTTPS station of the MCP fixture (the run needs the grant) on the virtual UTC.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_085_001_g_auto_answers_the_station_logged_last_and_nothing_is_logged() {
    use crate::automation_tests::{publish, run_state};
    let f = crate::mcp_tests::station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let station = f.state.recording.contact.get().unwrap().clone();
    let service = &f.state.recording.transmit.get().unwrap().service;
    let e = now_ms().div_euclid(30_000) * 30_000 + 120_000;
    let mut t = e - 10_000;
    let mut to = |until: i64| {
        while t < until {
            t += 100;
            f.bench.frozen.store(t, Ordering::SeqCst);
            service.with(|c| c.tick());
            f.tick();
        }
    };
    to(e - 10_000);
    // The QSO by hand: K1ABC entered, his R-09 and 73 complete it; it is logged.
    let command = f.command(
        station.facts().0,
        "enter_dx",
        json!({"dx_call":"K1ABC","dx_grid":null,"replace":true}),
    );
    let r = f.browser("POST", "/contact/command", Some(command)).await;
    assert_eq!(r.status, StatusCode::ACCEPTED, "{}", r.json);
    to(e + 14_000);
    publish(&f, e, &[("HB9BLA K1ABC R-09", 1500.0, Some(-9.0))]);
    to(e + 44_000);
    publish(&f, e + 30_000, &[("HB9BLA K1ABC 73", 1500.0, Some(-9.0))]);
    assert_eq!(station.facts().1.unwrap().state, "completed");
    let calls = |f: &crate::mcp_tests::Mcp| -> Vec<String> {
        f.state.logbook.history(&f.id, 0, 10).unwrap()["records"]
            .as_array()
            .unwrap()
            .iter()
            .map(|r| r["call"].as_str().unwrap().to_owned())
            .collect()
    };
    assert_eq!(calls(&f), ["K1ABC"]);
    // Auto on with a strategy that answers every caller: a new call worked in a past window
    // only, so the QSO by hand does not make K1ABC worked for it.
    let mut s = crate::strategy::tests::strategy_json("Answer callers");
    s["filters"]["worked_since"] = json!({"kind":"from_to","from":"2020-01-01","to":"2020-01-02"});
    let configuration = json!({"continent":null,"active":"Answer callers","strategies":[s],
        "ignore_calls":[],"session_ignore_minutes":30});
    let revision = f.browser("GET", "/strategy", None).await.json["revision"].clone();
    let r = f
        .browser(
            "PUT",
            "/strategy",
            Some(json!({"v":1,"profile_id":f.id,"boot_id":f.boot,
            "expected_revision":revision,"configuration":configuration})),
        )
        .await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);
    let r = crate::strategy::tests::auto(&f, true, None).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);
    // K1ABC calls me with a report: Auto answers him; his RR73 is answered with 73.
    to(e + 74_000);
    publish(&f, e + 60_000, &[("HB9BLA K1ABC -10", 1500.0, Some(-10.0))]);
    let c = f.read("contact").await;
    assert_eq!(
        (
            c["contact"]["dx_call"].as_str(),
            c["transmit"]["arm_state"].as_str()
        ),
        (Some("K1ABC"), Some("armed")),
        "{c}"
    );
    let second = c["contact"]["id"].clone();
    to(e + 104_000);
    publish(
        &f,
        e + 90_000,
        &[("HB9BLA K1ABC RR73", 1500.0, Some(-10.0))],
    );
    to(e + 130_000);
    let c = f.read("contact").await;
    assert_eq!(c["contact"]["id"], second);
    assert_eq!(c["contact"]["state"], "completed", "{c}");
    assert_eq!(
        c["log"],
        json!({"contact_id":second,"call":"K1ABC","outcome":"unsaved","error":"same_station_again"})
    );
    assert_eq!(calls(&f), ["K1ABC"], "no record");
    assert_ne!(run_state(&f).await.0, "stopped", "Auto goes on");
    assert!(station.strategy.auto(&f.state), "Auto is still on");
}

fn open_gate_85(
    publish: &mut dyn FnMut() -> std::io::Result<()>,
) -> Result<std::io::Result<()>, crate::authorization::Error> {
    Ok(publish())
}

// Proves: CL-085-01; TC-085-002 (j); TC-085-003 (c), (d). The newest record of a log prepared by
// hand (another program's K1ABC on 40 m in FT8, the confirmed CAT dial of the radio double being
// 7.074 MHz) makes the next QSO with K1ABC not logged; an ADIF import appending DL1ABC makes the
// next one logged (L5). A second profile reads only its own log.
#[tokio::test(flavor = "multi_thread")]
async fn tc_085_003_the_newest_record_whatever_wrote_it() {
    let origin = "http://127.0.0.1:18087";
    let (dir, _) = profile_directory(origin, false, "JN47AA");
    std::fs::write(
        dir.join(crate::logbook::FILE_NAME),
        "Log4OM\n<eoh>\n<call:5>K1ABC <qso_date:8>20261101 <time_on:6>120000 <band:3>40m \
         <freq:8>7.075000 <mode:3>FT8 <app_wstxrust_contact_id:36>33333333-3333-4333-8333-333333333333 <eor>\n",
    )
    .unwrap();
    let f = start_station(dir, origin, false);
    f.state.recording.fixture_live_job("ft8");
    let r = &f.state.recording;
    let (actor, _) = crate::radio_http_tests::actor(r.profile.clone(), r.boot.clone(), 0, false);
    r.fixture_radio(actor.clone());
    let deadline = Instant::now() + std::time::Duration::from_secs(3);
    while contact_http::confirmed_dial(r).is_none() && Instant::now() < deadline {
        std::thread::sleep(std::time::Duration::from_millis(5));
    }
    assert_eq!(contact_http::confirmed_dial(r), Some(7_074_000));
    let file = log_file_85(&f);
    // (c) Not logged; the file is unchanged.
    entered_qso_85(&f, P85, "K1ABC");
    assert_eq!(log_view_85(&f), refused_85(&f, "K1ABC"));
    assert_eq!(log_file_85(&f), file);
    // (d) An ADIF import appends DL1ABC: the next K1ABC is logged.
    let adi = b"WSJT-X\n<eoh>\n<call:6>DL1ABC <qso_date:8>20261101 <time_on:6>121000 <band:3>40m \
        <freq:8>7.075000 <mode:3>FT8 <eor>\n";
    let sha: String = ring::digest::digest(&ring::digest::SHA256, adi)
        .as_ref()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    let id = profile::new_uuid().unwrap();
    f.state
        .logbook
        .reserve(&id, adi.len() as u64, &sha, Instant::now())
        .unwrap();
    f.state
        .logbook
        .chunk(&id, 0, adi.len() as u64, adi, Instant::now(), &open_gate_85)
        .unwrap();
    assert_eq!(calls_85(&f), ["K1ABC", "DL1ABC"]);
    entered_qso_85(&f, P85 + 120_000, "K1ABC");
    assert_eq!(calls_85(&f), ["K1ABC", "DL1ABC", "K1ABC"]);
    let stored = f.state.logbook.history(&f.id, 2, 1).unwrap();
    assert_eq!(stored["records"][0]["band"], "40m", "{stored}");
    actor.request_close();

    // (j) A second profile with its own (empty) log logs K1ABC.
    let g = fixture("http://127.0.0.1:18088", false);
    g.state.recording.fixture_live_job("ft8");
    entered_qso_85(&g, P85, "K1ABC");
    assert_eq!(calls_85(&g), ["K1ABC"]);
    assert_eq!(calls_85(&f), ["K1ABC", "DL1ABC", "K1ABC"]);
}
