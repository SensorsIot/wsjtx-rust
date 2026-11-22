#![forbid(unsafe_code)]
// GET /clock on the actual router (exact keys of CL-043-01, no source setting, POST /clock an
// unknown route, a clock.json ignored and left in place), GET /transmit carrying the same
// warning, capture_warning, clock_revision, the actual station transmit owner admitting and
// timing transmit by the station clock, and clock.state pushed over the actual status
// WebSocket to every profile. Expected values come from the model's rule and texts.
use super::*;
use crate::contact_http::tests::{DrivenClock, RoundSource};
use crate::listener::*;
use axum::body::Body;
use std::time::{Duration, SystemTime};
use tower::ServiceExt;
use wstx_rust::transmit::clock::{Measurement, Monitor, WindowsTime};

struct Station {
    router: Router,
    dir: std::path::PathBuf,
    id: String,
    recording: Arc<recording::Recording>,
    /// The station's clocks.
    time: Arc<DrivenClock>,
    /// What the Windows Time reader reports.
    windows_time: Arc<Mutex<WindowsTime>>,
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
/// The actual router of a profile in `dir` (a clock.json as left there), as main wires it.
fn station(dir: std::path::PathBuf, ntp: Arc<Monitor>) -> Station {
    let id = profile::new_uuid().unwrap();
    let boot = profile::new_uuid().unwrap();
    let doc = json!({"schema_version":1,"profile_id":id,"revision":0,"display_name":"Clock",
        "callsign":"HB9BLA","locator":"JN47AA","endpoint":{"bind":"127.0.0.1:18001","origin":null},"connection_type":"standard",
        "audio":{"input_device":null,"output_device":null},"control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}});
    std::fs::write(dir.join("profile.json"), serde_json::to_vec(&doc).unwrap()).unwrap();
    let (store, _) = profile::Store::open(&dir, std::sync::Arc::new(crate::profile::Disk)).unwrap();
    let time = DrivenClock::new();
    let recording = recording::Recording::open(
        &dir,
        id.clone(),
        boot.clone(),
        std::sync::Arc::new(crate::profile::Disk),
        time.clone(),
        std::sync::Arc::new(crate::recording::Threads),
        std::sync::Arc::new(crate::recording::WavFiles),
    );
    let windows_time = Arc::new(Mutex::new(WindowsTime::Running));
    let reader = windows_time.clone();
    let clock =
        clock_http::Clock::new(ntp, time.clone(), Box::new(move || *reader.lock().unwrap()));
    let _ = recording.clock.set(clock.clone());
    let shared = transmit_http::Shared::default();
    let hardware = transmit_http::StationHardware::new(clock.station.clone(), &shared);
    let _ = recording.transmit.set(
        transmit_http::Station::start(clock.station.clone(), shared, Box::new(hardware)).unwrap(),
    );
    let app = App {
        origin: "http://127.0.0.1:18001".to_string(),
        profile: Some(Arc::new(ProfileState {
            store: Mutex::new(store),
            authorization: Mutex::new(None),
            boot,
            recording: recording.clone(),
            logbook: Arc::new(crate::logbook::Logbook::open(
                &dir,
                std::sync::Arc::new(crate::profile::Disk),
            )),
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
        recording,
        time,
        windows_time,
    }
}
async fn call(s: &Station, method: &str, path: &str, body: Option<Value>) -> (StatusCode, Bytes) {
    let request = axum::http::Request::builder().method(method).uri(path);
    let request = match body {
        Some(b) => request
            .header(header::ORIGIN, "http://127.0.0.1:18001")
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(serde_json::to_vec(&b).unwrap())),
        None => request.body(Body::empty()),
    }
    .unwrap();
    let response = s.router.clone().oneshot(request).await.unwrap();
    let status = response.status();
    (
        status,
        axum::body::to_bytes(response.into_body(), 65536)
            .await
            .unwrap(),
    )
}
async fn get(s: &Station, path: &str) -> Value {
    let (status, bytes) = call(s, "GET", path, None).await;
    assert_eq!(status, StatusCode::OK, "{path}");
    serde_json::from_slice(&bytes).unwrap()
}
fn keys(v: &Value) -> Vec<&str> {
    let mut k: Vec<&str> = v.as_object().unwrap().keys().map(String::as_str).collect();
    k.sort();
    k
}
fn station_clock(s: &Station) -> Arc<wstx_rust::transmit::air::StationClock> {
    s.recording.clock.get().unwrap().station.clone()
}
/// `periods` FT8 windows of `stations` distinct stations at raw DT `dt`, each heard with the
/// station's clocks driven to its time; they return to offset zero after.
fn heard(s: &Station, stations: usize, dt: i64, periods: std::ops::Range<i64>) {
    let clock = station_clock(s);
    clock.set_own_call("HB9BLA");
    let at = |ms: i64| s.time.set_offset(Duration::from_millis(ms as u64));
    for k in periods {
        let t = k * 15_000 + 13_800;
        at(t);
        for i in 0..stations {
            clock.observe(&format!("K{i}ABC"), dt, Some(-4.0));
        }
        at(t + 200);
        clock.period_done(15_000);
    }
    at(0);
}
fn measured(offset_ms: i64) -> Measurement {
    Measurement {
        server: "ch.pool.ntp.org".into(),
        offset_ms,
        round_trip_ms: 20,
        taken: Instant::now(),
        system: SystemTime::now(),
    }
}
const VIEW_KEYS: [&str; 10] = [
    "air",
    "boot_id",
    "capture_warning",
    "clock_revision",
    "correction_ms",
    "ntp",
    "profile_id",
    "state",
    "v",
    "warning",
];

// The view of CL-043-01 with and without a stored clock.json (unchanged),
// GET /transmit without clock_source, twelve stations at +1555 ms over two periods, POST
// /clock an unknown route.
// Proves: TC-043-003
// Timing: clock
#[tokio::test]
async fn clock_view_wire_with_and_without_a_43_file() {
    for file in [false, true] {
        let dir = directory();
        let text = br#"{"schema_version":1,"profile_id":"00000000-0000-4000-8000-0000000000c1","source":"ntp"}"#;
        if file {
            std::fs::write(dir.join("clock.json"), text).unwrap();
        }
        let s = station(dir, RoundSource::idle());
        let view = get(&s, "/clock").await;
        assert_eq!(keys(&view), VIEW_KEYS);
        assert_eq!(keys(&view["ntp"]), ["measurement", "state", "windows_time"]);
        assert_eq!(keys(&view["air"]), ["estimate"]);
        assert_eq!(
            (
                &view["state"],
                &view["correction_ms"],
                &view["warning"],
                &view["air"]["estimate"]
            ),
            (
                &json!("synchronized"),
                &json!(0),
                &Value::Null,
                &Value::Null
            )
        );
        let transmit = get(&s, "/transmit").await;
        assert!(transmit.get("clock_source").is_none());
        assert_eq!(
            (&transmit["clock"], &transmit["clock_warning"]),
            (&json!("synchronized"), &Value::Null)
        );
        // Twelve at +1555: estimate median +1555, all plus: -1000 (unsynchronized: 1555 >
        // 1000); the second window's votes are 1555 - 1000 = 555: -1555, synchronized.
        heard(&s, 12, 1555, 0..1);
        let view = get(&s, "/clock").await;
        let e = &view["air"]["estimate"];
        assert_eq!(
            keys(e),
            ["age_ms", "median_dt_ms", "minus", "plus", "stations"]
        );
        assert_eq!(
            (&e["median_dt_ms"], &e["stations"], &e["plus"], &e["minus"]),
            (&json!(1555), &json!(12), &json!(12), &json!(0))
        );
        assert_eq!(
            (&view["state"], &view["correction_ms"]),
            (&json!("unsynchronized"), &json!(-1000))
        );
        heard(&s, 12, 1555, 1..2);
        let view = get(&s, "/clock").await;
        assert_eq!(view["air"]["estimate"]["median_dt_ms"], json!(555));
        assert_eq!(
            (&view["state"], &view["correction_ms"]),
            (&json!("synchronized"), &json!(-1555))
        );
        let (status, _) = call(
            &s,
            "POST",
            "/clock",
            Some(json!({"v":1,"profile_id":s.id,"source":"ntp"})),
        )
        .await;
        assert_eq!(status, StatusCode::NOT_FOUND, "an unknown route");
        if file {
            assert_eq!(std::fs::read(s.dir.join("clock.json")).unwrap(), text);
        } else {
            assert!(!s.dir.join("clock.json").exists(), "never written");
        }
    }
}

// No clock source setting: clock.json missing, {source ntp}, {source
// air} and malformed give the same view (twelve stations 2 s fast: -2000 after two periods,
// synchronized); each file byte for byte unchanged; POST /clock answered as an unknown route.
// Proves: TC-092-001
#[tokio::test]
async fn no_clock_source_setting() {
    let unknown = {
        let s = station(directory(), RoundSource::idle());
        call(&s, "POST", "/no-such-route", Some(json!({"v":1}))).await
    };
    let mut views = vec![];
    for text in [
        None,
        Some(
            r#"{"schema_version":1,"profile_id":"00000000-0000-4000-8000-0000000000c1","source":"ntp"}"#,
        ),
        Some(
            r#"{"schema_version":1,"profile_id":"00000000-0000-4000-8000-0000000000c1","source":"air"}"#,
        ),
        Some("{"),
    ] {
        let dir = directory();
        if let Some(text) = text {
            std::fs::write(dir.join("clock.json"), text).unwrap();
        }
        let s = station(dir, RoundSource::idle());
        heard(&s, 12, 2000, 0..2);
        let mut view = get(&s, "/clock").await;
        assert_eq!(keys(&view), VIEW_KEYS);
        let transmit = get(&s, "/transmit").await;
        assert!(transmit.get("clock_source").is_none());
        assert_eq!(transmit["clock_warning"], view["warning"]);
        let post = call(
            &s,
            "POST",
            "/clock",
            Some(json!({"v":1,"profile_id":s.id,"boot_id":view["boot_id"],"source":"ntp"})),
        )
        .await;
        assert_eq!(post, unknown, "the router's answer for an unknown route");
        if let Some(text) = text {
            assert_eq!(
                std::fs::read(s.dir.join("clock.json")).unwrap(),
                text.as_bytes()
            );
        }
        for identity in ["profile_id", "boot_id"] {
            view[identity] = Value::Null;
        }
        view["air"]["estimate"]["age_ms"] = Value::Null;
        views.push(view);
    }
    assert_eq!(
        (&views[0]["state"], &views[0]["correction_ms"]),
        (&json!("synchronized"), &json!(-2000))
    );
    assert!(views.iter().all(|v| *v == views[0]), "{views:?}");
}

// GET /clock and GET /transmit after each step: the same warning, the
// Windows Time service state, capture_warning, and clock_revision increasing at each change
// of a clock.state field and only then.
// Proves: TC-007-011, TC-092-003
#[tokio::test]
async fn warnings_windows_time_capture_and_revision() {
    let (ntp, rounds) = RoundSource::start();
    let s = station(directory(), ntp);
    let revision = |v: &Value| v["clock_revision"].as_u64().unwrap();
    let first = get(&s, "/clock").await;
    assert_eq!(
        revision(&get(&s, "/clock").await),
        revision(&first),
        "nothing changed"
    );
    let mut last = revision(&first);
    // Each step: (expected warning, capture_warning, whether a clock.state field changed).
    let mut step = async |expected: Option<&str>, capture: Option<&str>, changed: bool| {
        let view = get(&s, "/clock").await;
        let transmit = get(&s, "/transmit").await;
        assert_eq!(view["warning"], json!(expected));
        assert_eq!(transmit["clock_warning"], view["warning"]);
        assert!(transmit.get("clock_source").is_none());
        assert_eq!(view["capture_warning"], json!(capture));
        assert_eq!(revision(&view), last + u64::from(changed), "{view}");
        last = revision(&view);
    };
    rounds.give(false, Some(measured(12)));
    step(None, None, false).await;
    rounds.give(false, Some(measured(40)));
    step(None, None, false).await;
    rounds.give(false, Some(measured(501)));
    step(Some("pc_clock_off"), None, true).await;
    rounds.give(false, Some(measured(525)));
    step(Some("pc_clock_off"), None, true).await;
    rounds.give(false, Some(measured(500)));
    step(None, None, true).await;
    rounds.give(true, None);
    step(None, None, false).await;
    // The Windows Time service as the reader reports it.
    for (reader, name) in [
        (WindowsTime::Running, "running"),
        (WindowsTime::Stopped, "stopped"),
        (WindowsTime::Disabled, "disabled"),
        (WindowsTime::Unknown, "unknown"),
    ] {
        *s.windows_time.lock().unwrap() = reader;
        assert_eq!(get(&s, "/clock").await["ntp"]["windows_time"], name);
    }
    // capture_warning with live receive: before the first epoch null; a correlated clock at
    // 1000.0 and -1000.0 ppm null, 1000.1 drift_high; a rate not yet known null; an
    // uncorrelated epoch; receive stopped (1500 ppm) null.
    let r = &s.recording;
    r.fixture_live_job("ft8");
    step(None, None, false).await;
    r.fixture_capture_clock(Some(true), Some(Some(1000.0)));
    step(None, None, false).await;
    r.fixture_capture_clock(Some(true), Some(Some(-1000.0)));
    step(None, None, false).await;
    r.fixture_capture_clock(Some(true), Some(Some(1000.1)));
    step(None, Some("drift_high"), true).await;
    r.fixture_capture_clock(Some(true), Some(None));
    step(None, None, true).await;
    r.fixture_capture_clock(Some(false), None);
    step(None, Some("uncorrelated"), true).await;
    r.fixture_capture_clock(Some(true), Some(Some(1500.0)));
    step(None, Some("drift_high"), true).await;
    r.fixture_stop_live_job();
    step(None, None, true).await;
    // stations_off with SNTP synchronized: four at +501 -> -501.
    heard(&s, 4, 501, 0..1);
    step(Some("stations_off"), None, true).await;
}

// The actual transmit owner plans with the station clock: synchronized with two stations (no
// evidence, correction 0), six at +2000: -1000 (unsynchronized: median 2000) then -2000,
// synchronized, and its UTC 2000 ms behind the system clock.
// Proves: TC-043-003
#[test]
fn transmit_owner_admits_and_times_by_the_air_clock() {
    let s = station(directory(), RoundSource::idle());
    let transmit = s.recording.transmit.get().unwrap().clone();
    let utc = || transmit.service.with(|c| c.hardware().now_utc_ms());
    let wall = || {
        SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as i64
    };
    use wstx_rust::transmit::ClockState::{Synchronized, Unsynchronized};
    assert_eq!(transmit.service.view().clock, Synchronized, "never unknown");
    heard(&s, 2, 2000, 0..1);
    assert_eq!(transmit.service.view().clock, Synchronized, "two stations");
    assert!((utc() - wall()).abs() <= 10);
    heard(&s, 6, 2000, 1..2);
    assert_eq!(
        transmit.service.view().clock,
        Unsynchronized,
        "median +2000"
    );
    heard(&s, 6, 2000, 2..3);
    assert_eq!(transmit.service.view().clock, Synchronized);
    let shifted = utc() - wall();
    assert!(
        (-2010..=-1990).contains(&shifted),
        "station UTC {shifted} ms from the system clock"
    );
}

/// The clock.state frames each peer received at or after `since`, with their receipt instants
/// (over a held transport: the instants the station handed them over).
fn handed_writes(
    peers: &[crate::liveness_tests::Peer],
    since: tokio::time::Instant,
) -> Vec<Vec<(tokio::time::Instant, Value)>> {
    peers
        .iter()
        .map(|p| p.received_since("clock.state", since))
        .collect()
}

// clock.state over the actual status WebSocket of a receive-only and a
// transmit-configured profile, to a Detailed and a Thin peer: one event after subscribing
// with exactly the keys of CL-043-01 within 512 bytes; none while nothing changes or for an
// SNTP move within 500 ms; one for +525 and for +530, handed to each socket within 1 s; quick
// changes coalesced, handed to each socket at least eventDelayMs apart; drift_high and back;
// clock_revision equal to GET /clock's. The peers run over held transports on the paused runtime
// clock: timing on each peer's receipt instants, count, order and content at receipt.
// Proves: TC-092-009
#[tokio::test(start_paused = true)]
async fn clock_state_is_pushed_to_every_profile() {
    use crate::liveness_tests::{Held, Peer};
    for transmit in [false, true] {
        let f = crate::mcp_tests::station(transmit).await;
        let (ntp, rounds) = RoundSource::start();
        rounds.give(false, Some(measured(12)));
        let _ = f.state.recording.clock.set(clock_http::Clock::new(
            ntp,
            f.clock.clone(),
            Box::new(|| WindowsTime::Running),
        ));
        f.state.recording.fixture_live_job("ft8");
        f.state
            .recording
            .fixture_capture_clock(Some(true), Some(Some(12.0)));
        let (listener, accepted) = tokio::sync::mpsc::unbounded_channel();
        let server = tokio::spawn(
            axum::serve(Held(accepted), crate::listener::router(f.app.clone())).into_future(),
        );
        let cookie = format!("Cookie: {}\r\n", f.cookie());
        let mut peers = Vec::new();
        for (id, subscription) in ["spectrum.detail", "spectrum.thin"].iter().enumerate() {
            let peer = Peer::open_with(&listener, &f.app.origin, &cookie, true).await;
            peer.send(json!({"v":1,"type":subscription,"id":id + 1}))
                .await;
            peers.push(peer);
        }
        let sockets = peers.len();
        // Clock events received by each peer within `wait` of the runtime clock.
        async fn events(peers: &mut [Peer], wait: Duration) -> Vec<Vec<Value>> {
            tokio::time::sleep(wait).await;
            peers
                .iter_mut()
                .map(|p| {
                    let mut got = vec![];
                    while let Ok(m) = p.texts.try_recv() {
                        if m["type"] == "clock.state" {
                            got.push(m);
                        }
                    }
                    got
                })
                .collect()
        }
        let current = async || f.browser("GET", "/clock", None).await.json;
        let first = events(&mut peers, Duration::from_millis(1500)).await;
        let view = current().await;
        for got in &first {
            assert_eq!(got.len(), 1, "one event after subscribing: {got:?}");
            let event = &got[0];
            assert!(event.to_string().len() <= 512, "{event}");
            assert_eq!(keys(event), ["data", "type", "v"]);
            assert_eq!(
                keys(&event["data"]),
                ["boot_id", "clock", "clock_revision", "profile_id"]
            );
            assert_eq!(
                keys(&event["data"]["clock"]),
                [
                    "capture_warning",
                    "correction_ms",
                    "ntp_offset_ms",
                    "state",
                    "warning"
                ]
            );
            assert_eq!(
                event["data"]["clock"],
                json!({"state":"synchronized","correction_ms":0,"warning":null,"ntp_offset_ms":null,"capture_warning":null})
            );
            assert_eq!(event["data"]["clock_revision"], view["clock_revision"]);
            assert_eq!(
                (&event["data"]["profile_id"], &event["data"]["boot_id"]),
                (&json!(f.id), &json!(f.boot))
            );
        }
        // Nothing changes for 10 s, then SNTP +12 -> +40 (synchronized): no event.
        assert!(
            events(&mut peers, Duration::from_secs(10))
                .await
                .iter()
                .all(Vec::is_empty)
        );
        rounds.give(false, Some(measured(40)));
        assert!(
            events(&mut peers, Duration::from_millis(1500))
                .await
                .iter()
                .all(Vec::is_empty)
        );
        // +525 and then +530: one event each, handed to each socket within 1 s.
        for offset in [525, 530] {
            let set = tokio::time::Instant::now();
            rounds.give(false, Some(measured(offset)));
            let got = events(&mut peers, Duration::from_millis(1500)).await;
            let view = current().await;
            for got in &got {
                assert_eq!(got.len(), 1, "{offset}: {got:?}");
                let event = &got[0];
                assert_eq!(event["data"]["clock"]["warning"], "pc_clock_off");
                assert_eq!(event["data"]["clock"]["ntp_offset_ms"], offset);
                assert_eq!(event["data"]["clock_revision"], view["clock_revision"]);
            }
            let handed = handed_writes(&peers, set);
            assert_eq!(handed.len(), sockets, "{offset}: {handed:?}");
            for writes in &handed {
                assert_eq!(writes.len(), 1, "{offset}: {writes:?}");
                let (at, event) = &writes[0];
                assert_eq!(event["data"]["clock"]["ntp_offset_ms"], offset);
                assert!(
                    at.duration_since(set) <= Duration::from_millis(1000),
                    "{offset}: {:?}",
                    at.duration_since(set)
                );
            }
        }
        // Three changes within 300 ms: coalesced, the last delivered, handed to each socket at
        // least eventDelayMs apart. The first is handed over at its 250 ms tick, before the other
        // two arrive (at +260 and +290), so that the next write is the paced one.
        let set = tokio::time::Instant::now();
        let mut got = vec![vec![]; 2];
        for (offset, wait) in [(540, 260), (550, 30), (560, 2500)] {
            rounds.give(false, Some(measured(offset)));
            let more = events(&mut peers, Duration::from_millis(wait)).await;
            for (all, more) in got.iter_mut().zip(more) {
                all.extend(more);
            }
        }
        let view = current().await;
        for got in &got {
            assert!(!got.is_empty() && got.len() <= 2, "{got:?}");
            let last = got.last().unwrap();
            assert_eq!(last["data"]["clock"]["ntp_offset_ms"], 560);
            assert_eq!(last["data"]["clock_revision"], view["clock_revision"]);
        }
        let handed = handed_writes(&peers, set);
        assert_eq!(handed.len(), sockets, "{handed:?}");
        for writes in &handed {
            assert!(!writes.is_empty(), "{handed:?}");
            for w in writes.windows(2) {
                let gap = w[1].0.duration_since(w[0].0);
                assert!(
                    gap >= Duration::from_millis(crate::listener::socket_protocol::EVENT_DELAY_MS),
                    "{gap:?}: {writes:?}"
                );
            }
        }
        // Capture drift 1500 ppm: drift_high; then everything restored: null.
        f.state
            .recording
            .fixture_capture_clock(Some(true), Some(Some(1500.0)));
        let got = events(&mut peers, Duration::from_millis(1500)).await;
        for got in &got {
            assert_eq!(
                got.last().unwrap()["data"]["clock"]["capture_warning"],
                "drift_high"
            );
        }
        f.state
            .recording
            .fixture_capture_clock(Some(true), Some(Some(12.0)));
        rounds.give(false, Some(measured(12)));
        let got = events(&mut peers, Duration::from_millis(1500)).await;
        let view = current().await;
        for got in &got {
            let last = got.last().unwrap();
            assert_eq!(
                last["data"]["clock"],
                json!({"state":"synchronized","correction_ms":0,"warning":null,"ntp_offset_ms":null,"capture_warning":null})
            );
            assert_eq!(last["data"]["clock_revision"], view["clock_revision"]);
        }
        server.abort();
    }
}

// GET /clock's view and the clock.state event read on four threads while SNTP records 501,
// 502, …: a higher clock_revision never carries a lower offset, and each offset has at most
// one revision.
// Proves: TC-092-009
#[test]
fn a_revision_never_carries_older_clock_values() {
    use std::sync::atomic::{AtomicBool, Ordering::SeqCst};
    let (ntp, rounds) = RoundSource::start();
    rounds.give(false, Some(measured(501)));
    let s = station(directory(), ntp);
    let (r, c) = (&*s.recording, s.recording.clock.get().unwrap());
    let done = AtomicBool::new(false);
    let mut seen: Vec<(u64, i64)> = std::thread::scope(|scope| {
        let readers: Vec<_> = (0..4)
            .map(|i| {
                let done = &done;
                scope.spawn(move || {
                    let mut seen = vec![];
                    while !done.load(SeqCst) {
                        seen.push(if i % 2 == 0 {
                            let v = view(r, c);
                            assert_eq!(v["warning"], "pc_clock_off");
                            let offset = &v["ntp"]["measurement"]["offset_ms"];
                            (
                                v["clock_revision"].as_u64().unwrap(),
                                offset.as_i64().unwrap(),
                            )
                        } else {
                            let (revision, text) = state_event(r).unwrap();
                            let e: Value = serde_json::from_str(&text).unwrap();
                            let offset = &e["data"]["clock"]["ntp_offset_ms"];
                            (revision, offset.as_i64().unwrap())
                        });
                    }
                    seen
                })
            })
            .collect();
        for offset in 502..20_000 {
            rounds.give(false, Some(measured(offset)));
            std::thread::yield_now();
        }
        done.store(true, SeqCst);
        readers
            .into_iter()
            .flat_map(|h| h.join().unwrap())
            .collect()
    });
    seen.sort_unstable();
    seen.dedup();
    assert!(seen.len() > 1, "{seen:?}");
    for w in seen.windows(2) {
        assert!(
            w[0].0 < w[1].0 && w[0].1 < w[1].1,
            "revision and offset out of step: {w:?}"
        );
    }
}

// GET /clock's view read on three threads while an asked round's measurement (+40) reaches
// 600 s: in each view ntp.state is unknown exactly when warning is ntp_unreachable, and
// exactly when ntp.measurement.age_ms is beyond 600000.
// Proves: TC-043-003
#[test]
fn get_clock_shows_one_age() {
    let (ntp, rounds) = RoundSource::start();
    let s = station(directory(), ntp);
    let (r, c) = (&*s.recording, s.recording.clock.get().unwrap());
    let mut stale = 0;
    for _ in 0..200 {
        let (now, system) = (Instant::now(), SystemTime::now());
        let age = Duration::from_millis(599_998);
        rounds.give(
            true,
            Some(Measurement {
                taken: now - age,
                system: system - age,
                ..measured(40)
            }),
        );
        let until = now + Duration::from_millis(4);
        let views: Vec<Value> = std::thread::scope(|scope| {
            let readers: Vec<_> = (0..3)
                .map(|_| {
                    scope.spawn(move || {
                        let mut views = vec![view(r, c)];
                        while Instant::now() < until {
                            views.push(view(r, c));
                        }
                        views
                    })
                })
                .collect();
            readers
                .into_iter()
                .flat_map(|h| h.join().unwrap())
                .collect()
        });
        for v in &views {
            let unknown = v["ntp"]["state"] == "unknown";
            let age_ms = v["ntp"]["measurement"]["age_ms"].as_u64().unwrap();
            assert_eq!(unknown, v["warning"] == "ntp_unreachable", "{v}");
            assert_eq!(unknown, age_ms > 600_000, "{v}");
            stale += usize::from(unknown);
        }
    }
    assert!(stale > 0, "the boundary was crossed");
}
