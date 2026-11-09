#![forbid(unsafe_code)]
// TC-007-005 thin-link and local presentation:
// the actual router with the contact engine, the logbook and the #9 transmit owner on the
// recording hardware double (no audio, PTT or radio), served over actual rustls TLS behind
// the tests/support.cjs 32 kbit/s, 300 ms RTT link simulator, with two authenticated
// browsers. Decoded rows are hand-authored and published through a test-only control peer
// (not on the counted link); the bounds are those of TC-007-005, asserted in
// tests/contact-thin.test.cjs.
use super::*;
use crate::contact_http_tests::{Bench, now_ms, period_text, record_exchange};
use std::io::{BufRead, BufReader, Read, Write};
use std::process::{Command, Stdio};

// Proves: CL-010-06, CL-010-08, CL-010-15, CL-065-01; TC-007-005. Runs both browsers through every
// TC-007-005 phase on the counted link and fails unless both complete them; #82: the live receive
// with no automation run makes the station push its open slots every period in the Thin and Off
// windows (asserted in tests/contact-thin.test.cjs).
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn contact_thin_link_two_clients() {
    rustls::crypto::ring::default_provider()
        .install_default()
        .ok();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_path_buf();
    let generated = Command::new("node")
        .args(["--eval","require('selfsigned').generate([{name:'commonName',value:'localhost'}],{days:1,keySize:2048,extensions:[{name:'subjectAltName',altNames:[{type:2,value:'localhost'}]}]}).then(c=>process.stdout.write(JSON.stringify({cert:c.cert,key:c.private})))"])
        .current_dir(&root)
        .output()
        .unwrap();
    assert!(
        generated.status.success(),
        "certificate fixture generator failed"
    );
    let cert: Value = serde_json::from_slice(&generated.stdout).unwrap();
    let token = profile::new_uuid().unwrap().replace('-', "");
    let id = profile::new_uuid().unwrap();
    let boot = profile::new_uuid().unwrap();
    let dir = std::env::temp_dir().join(format!(
        "wstx-contact-thin-{}",
        profile::new_uuid().unwrap()
    ));
    std::fs::create_dir(&dir).unwrap();

    // The station state exists before the control peer, which the child needs at start.
    let slot: Arc<Mutex<Option<Arc<ProfileState>>>> = Arc::new(Mutex::new(None));
    let control = crate::test_ports::browser_listener();
    let control_origin = format!("http://{}", control.local_addr().unwrap());
    let publisher = slot.clone();
    // Revision churn faster than 1/s, off the counted link: `count` Hold Tx toggles every
    // `interval_ms` through the browser's ContactCommand path (contact.state coalescing).
    let churner = slot.clone();
    let control_app = Router::new().route(
        "/socket-closes",
        get(|| async { Json(json!(crate::SOCKET_CLOSES.lock().unwrap().clone())) }),
    ).route(
        "/churn",
        post(move |Json(body): Json<Value>| {
            let slot = churner.clone();
            async move {
                let state = slot.lock().unwrap().clone().unwrap();
                let contact = state.recording.contact.get().unwrap().clone();
                let before = contact.revision();
                for n in 0..body["count"].as_u64().unwrap() {
                    let command = json!({"v":1,"profile_id":state.recording.profile,"boot_id":state.recording.boot,
                        "command_id":profile::new_uuid().unwrap(),"contact_revision":contact.revision(),
                        "action":"set_hold_tx","enabled":n % 2 == 0});
                    let (state, contact) = (state.clone(), contact.clone());
                    let done = tokio::task::spawn_blocking(move || contact.operate(&state, command, true).is_ok())
                        .await
                        .unwrap();
                    assert!(done, "Hold Tx churn command refused");
                    tokio::time::sleep(Duration::from_millis(body["interval_ms"].as_u64().unwrap())).await;
                }
                Json(json!({"before":before,"after":contact.revision()}))
            }
        }),
    ).route(
        "/publish",
        post(move |Json(body): Json<Value>| {
            let slot = publisher.clone();
            async move {
                let state = slot.lock().unwrap().clone().unwrap();
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
                            None,
                        )
                    })
                    .collect();
                let sequences = state
                    .recording
                    .fixture_publish_period(&period_text(period), records);
                Json(json!({"sequences":sequences,"now_ms":now_ms()}))
            }
        }),
    );
    let control_service = tokio::spawn(async move {
        axum::serve(control, control_app).await.unwrap();
    });

    let mut child = Command::new("node")
        .arg("tests/contact-thin.test.cjs")
        .current_dir(&root)
        .env("WSTX_THIN_CONTACT_FIXTURE", "1")
        .env("WSTX_THIN_CONTACT_TOKEN", &token)
        .env("WSTX_THIN_CONTACT_CONTROL", &control_origin)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let stdout = child.stdout.take().unwrap();
    let announced = tokio::task::spawn_blocking(move || {
        let mut reader = BufReader::new(stdout);
        let mut prefix = String::new();
        loop {
            let mut line = String::new();
            assert!(
                reader.read_line(&mut line).unwrap() > 0,
                "child did not announce the link: {prefix}"
            );
            prefix.push_str(&line);
            if let Some((_, tail)) = line.split_once("WSTX_THIN_CONTACT_PROXY ") {
                let port = tail.trim().parse::<u16>().unwrap();
                return (reader, prefix, port);
            }
        }
    });
    let (mut reader, mut output, port) = tokio::time::timeout(Duration::from_secs(30), announced)
        .await
        .expect("link announcement deadline")
        .unwrap();
    let origin = format!("https://localhost:{port}");
    // Transmit-capable (CAT PTT) like the contact fixture; the transmit owner uses the double.
    let document = json!({"schema_version":1,"profile_id":id,"revision":0,"display_name":"Thin contact fixture",
        "callsign":"HB9BLA","locator":"JN47AA","endpoint":{"bind":format!("127.0.0.2:{port}"),"origin":origin},
        "connection_type":"standard","audio":{"input_device":null,"output_device":"fixture-output-device"},
        "control":{"mode":"cat","endpoint":"icom7300://COM250","ptt":"cat"}});
    std::fs::write(
        dir.join("profile.json"),
        serde_json::to_vec(&document).unwrap(),
    )
    .unwrap();
    let (mut store, _) = profile::Store::open(&dir).unwrap();
    // Selected HTTPS profile: browsers enroll real CL-022-01 grants through the token form.
    let authorization =
        crate::authorization_http::Service::initialize(&mut store, &origin).unwrap();
    let recording = recording::Recording::open(&dir, id.clone(), boot.clone());
    recording.initialize_profile_revision(0);
    let bench = Bench::default();
    let _ = recording
        .transmit
        .set(transmit_http::Station::start_with(Box::new(bench.clone())).unwrap());
    let _ = recording.contact.set(contact_http::Station::start());
    let state = Arc::new(ProfileState {
        store: Mutex::new(store),
        authorization: Mutex::new(authorization),
        boot,
        recording,
        logbook: Arc::new(crate::logbook::Logbook::open(&dir)),
    });
    let _ = state.recording.fixture_live_job("ft8");
    state.recording.fixture_manual_band("20m", 14_074_000);
    *slot.lock().unwrap() = Some(state.clone());
    let app = App {
        origin: origin.clone(),
        profile: Some(state.clone()),
        profile_id: Some(id),
        token: Some(token),
        connections: Arc::new(Semaphore::new(16)),
        login_attempts: Arc::new(Mutex::new((Instant::now(), 0))),
    };
    let config = axum_server::tls_rustls::RustlsConfig::from_pem(
        cert["cert"].as_str().unwrap().as_bytes().to_vec(),
        cert["key"].as_str().unwrap().as_bytes().to_vec(),
    )
    .await
    .unwrap();
    let listener =
        std::net::TcpListener::bind((std::net::Ipv4Addr::new(127, 0, 0, 2), port)).unwrap();
    listener.set_nonblocking(true).unwrap();
    let server = axum_server::from_tcp_rustls(listener, config).unwrap();
    let service = tokio::spawn(async move {
        server.serve(router(app).into_make_service()).await.unwrap();
    });
    // The station-wide contact step, as main() runs it.
    let ticker = {
        let state = state.clone();
        tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_millis(50)).await;
                let state = state.clone();
                let _ =
                    tokio::task::spawn_blocking(move || contact_http::station_tick(&state)).await;
            }
        })
    };
    // The running waterfall of the live job: one Thin row per second; a Thin peer gets one per 2 s.
    let waterfall = {
        let state = state.clone();
        tokio::spawn(async move {
            for sequence in 0.. {
                state.recording.fixture_thin_row(sequence);
                tokio::time::sleep(Duration::from_secs(1)).await;
            }
        })
    };
    child.stdin.as_mut().unwrap().write_all(b"READY\n").unwrap();
    drop(child.stdin.take());
    let outcome = tokio::task::spawn_blocking(move || {
        let deadline = Instant::now() + Duration::from_secs(780);
        let timed_out = loop {
            if child.try_wait().unwrap().is_some() {
                break false;
            }
            if Instant::now() >= deadline {
                let _ = child.kill();
                break true;
            }
            std::thread::sleep(Duration::from_millis(50));
        };
        let result = child.wait_with_output().unwrap();
        reader.read_to_string(&mut output).unwrap();
        (result, output, timed_out)
    })
    .await
    .unwrap();
    ticker.abort();
    waterfall.abort();
    service.abort();
    control_service.abort();
    let keys = bench.keys.lock().unwrap().len();
    println!(
        "{}\n{}\nPTT exchanges on the double: {keys}",
        outcome.1,
        String::from_utf8_lossy(&outcome.0.stderr)
    );
    let _ = std::fs::remove_dir_all(&dir);
    assert!(!outcome.2, "browser child deadline");
    assert!(outcome.0.status.success(), "browser child failed");
    assert!(
        outcome.1.contains("WSTX_THIN_CONTACT_COMPLETED 2"),
        "both browsers must complete every TC-007-005 phase"
    );
    assert!(
        bench.keys.lock().unwrap().iter().any(|k| k.1),
        "the contact actually keyed the transmit double"
    );
}
