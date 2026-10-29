#![forbid(unsafe_code)]
use super::*;
#[path = "../../fixtures/radio/native_ft8_fixture.rs"]
mod native_fixture;
use native_fixture::{NATIVE_FRAMES, NativeFt8Fixture, TRAILING_SILENT_FRAMES};
use source::{SampleSource, SourceDescriptor, SourceError, SourcePoll, SourceTiming};
use std::{
    io::{BufRead, BufReader, Read, Write},
    process::{Command, Stdio},
    sync::atomic::{AtomicBool, AtomicU64, Ordering},
};

#[derive(Default)]
struct CaptureCounts {
    started: AtomicU64,
    released: AtomicU64,
    packets: AtomicU64,
    lost: AtomicU64,
}
struct Input {
    source: audio::LiveSource,
    queue: Arc<audio::PacketQueue>,
    fixture: Option<NativeFt8Fixture>,
    producer: Option<std::thread::JoinHandle<()>>,
    stop: Arc<AtomicBool>,
    running: bool,
    counts: Arc<CaptureCounts>,
}
impl Input {
    fn new(mode: &str, counts: Arc<CaptureCounts>) -> (Self, Value) {
        let fixture = if mode == "ft8" {
            NativeFt8Fixture::load()
        } else {
            NativeFt8Fixture::load_mode(mode)
        };
        let expected = fixture.expected.clone();
        let format = audio::NativeFormat {
            rate: 48000,
            channels: 2,
            encoding: audio::Encoding::Float32,
        };
        let queue = audio::PacketQueue::new(format).unwrap();
        (
            Self {
                source: audio::LiveSource::new(queue.clone(), format).unwrap(),
                queue,
                fixture: Some(fixture),
                producer: None,
                stop: Arc::new(AtomicBool::new(false)),
                running: false,
                counts,
            },
            expected,
        )
    }
}
impl SampleSource for Input {
    fn descriptor(&self) -> Option<Arc<SourceDescriptor>> {
        self.source.descriptor()
    }
    fn acknowledge_epoch(
        &mut self,
        counter: u64,
        descriptor: Arc<SourceDescriptor>,
        timing: SourceTiming,
    ) -> Result<(), SourceError> {
        self.source.acknowledge_epoch(counter, descriptor, timing)
    }
    fn poll(&mut self) -> SourcePoll {
        self.source.poll()
    }
}
impl recording::LiveInput for Input {
    fn start(&mut self) -> Result<(), SourceError> {
        let fixture = self.fixture.take().ok_or(SourceError::Unavailable)?;
        let queue = self.queue.clone();
        let stop = self.stop.clone();
        let counts = self.counts.clone();
        self.producer = Some(
            std::thread::Builder::new()
                .name("independent-native-fixture".into())
                .spawn(move || {
                    let period = if fixture.expected["mode"] == "ft4" {
                        NATIVE_FRAMES / 2
                    } else {
                        NATIVE_FRAMES
                    };
                    let began = Instant::now();
                    let mut first = 0usize;
                    while !stop.load(Ordering::Acquire) {
                        // Use the existing fixture's10ms quantum first, then bounded
                        // normal packets. Every byte comes from the fixed waveform.
                        let count = (if first == 0 {
                            TRAILING_SILENT_FRAMES
                        } else {
                            8192
                        })
                        .min(period - first % period);
                        let end = first + count;
                        let due = began + Duration::from_secs_f64(end as f64 / 48000.0);
                        while Instant::now() < due && !stop.load(Ordering::Acquire) {
                            std::thread::sleep(
                                due.saturating_duration_since(Instant::now())
                                    .min(Duration::from_millis(5)),
                            );
                        }
                        if stop.load(Ordering::Acquire) {
                            break;
                        }
                        let packet = fixture.native_stereo(first % period, count);
                        if !queue.push(
                            &packet,
                            count,
                            first as u64,
                            0,
                            if first == 0 {
                                audio::TIMESTAMP_ERROR
                            } else {
                                0
                            },
                        ) {
                            counts.lost.fetch_add(1, Ordering::AcqRel);
                        }
                        counts.packets.fetch_add(1, Ordering::AcqRel);
                        first = end;
                    }
                })
                .map_err(|_| SourceError::Unavailable)?,
        );
        self.running = true;
        self.counts.started.fetch_add(1, Ordering::AcqRel);
        Ok(())
    }
    fn request_stop(&mut self) {
        self.stop.store(true, Ordering::Release);
        if let Some(producer) = self.producer.take() {
            producer.join().unwrap();
            self.counts.released.fetch_add(1, Ordering::AcqRel);
        }
        self.source.stop();
        self.running = false;
    }
    fn status(&self) -> audio::AudioStatus {
        audio::AudioStatus {
            state: if self.running {
                audio::AudioState::Running
            } else {
                audio::AudioState::Closed
            },
            error: None,
            retry_after_ms: None,
        }
    }
}
impl Drop for Input {
    fn drop(&mut self) {
        recording::LiveInput::request_stop(self);
    }
}

// Proves: CL-008-07; TC-009-005 cases1..7. This is a mandatory cost2 release
// fixture, with actual native queue timing, Rust modem, typed actor, TLS and browsers.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn live_native_selection_tls_thin_and_off() {
    rustls::crypto::ring::default_provider()
        .install_default()
        .ok();
    let counts = Arc::new(CaptureCounts::default());
    let mut inputs: Vec<Box<dyn recording::LiveInput>> = Vec::new();
    let mut expected = json!({});
    for mode in ["ft8", "ft4", "ft4", "ft8", "ft8"] {
        let (input, oracle) = Input::new(mode, counts.clone());
        expected[mode] = oracle;
        inputs.push(Box::new(input));
    }
    let dir = std::env::temp_dir().join(format!(
        "wstx-selection-live-{}",
        profile::new_uuid().unwrap()
    ));
    std::fs::create_dir(&dir).unwrap();
    let generated=Command::new("node").args(["--eval","require('selfsigned').generate([{name:'commonName',value:'localhost'}],{days:1,keySize:2048,extensions:[{name:'subjectAltName',altNames:[{type:2,value:'localhost'}]}]}).then(c=>process.stdout.write(JSON.stringify({cert:c.cert,key:c.private})))"]).current_dir(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap()).output().unwrap();
    assert!(
        generated.status.success(),
        "certificate fixture generator failed"
    );
    let cert: Value = serde_json::from_slice(&generated.stdout).unwrap();
    let token = profile::new_uuid().unwrap().replace('-', "");
    let id = profile::new_uuid().unwrap();
    let boot = profile::new_uuid().unwrap();
    let mut child = Command::new("node")
        .arg("tests/radio-selection.test.cjs")
        .current_dir(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .parent()
                .unwrap(),
        )
        .env("WSTX_SELECTION_FIXTURE", "1")
        .env("WSTX_SELECTION_TOKEN", &token)
        .env("WSTX_SELECTION_EXPECTED", expected.to_string())
        .env("WSTX_SELECTION_PROFILE_ID", &id)
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
                "child did not announce proxy"
            );
            prefix.push_str(&line);
            if let Some((_, tail)) = line.split_once("WSTX_SELECTION_PROXY ") {
                let port = tail.trim().parse::<u16>().unwrap();
                return (reader, prefix, port);
            }
        }
    });
    let (mut reader, mut output, port) = tokio::time::timeout(Duration::from_secs(15), announced)
        .await
        .expect("proxy announcement deadline")
        .unwrap();
    let origin = format!("https://localhost:{port}");
    let document = json!({"schema_version":1,"profile_id":id,"revision":0,"display_name":"Actual native selection fixture","callsign":"HB9BLA","locator":"JN47AA","endpoint":{"bind":format!("127.0.0.2:{port}"),"origin":origin},"connection_type":"standard","audio":{"input_device":"independently-verified-native-input","output_device":null},"control":{"mode":"cat","endpoint":"COM3","ptt":"disabled"}});
    std::fs::write(
        dir.join("profile.json"),
        serde_json::to_vec(&document).unwrap(),
    )
    .unwrap();
    let (store, _) = profile::Store::open(&dir).unwrap();
    let recording = recording::Recording::open(&dir, id.clone(), boot.clone());
    recording.initialize_profile_revision(0);
    recording.fixture_inputs(inputs);
    let (actor, rig) = radio_http_tests::actor(id.clone(), boot.clone(), 0, true);
    recording.fixture_radio(actor.clone());
    let app = App {
        origin: origin.clone(),
        profile: Some(Arc::new(ProfileState {
            store: Mutex::new(store),
            authorization: Mutex::new(None),
            boot,
            recording: recording.clone(),
        })),
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
    let watched = recording.clone();
    let ticker = tokio::spawn(async move {
        let mut timer = tokio::time::interval(Duration::from_millis(50));
        loop {
            timer.tick().await;
            watched.tick();
        }
    });
    child.stdin.as_mut().unwrap().write_all(b"READY\n").unwrap();
    drop(child.stdin.take());
    let outcome = tokio::task::spawn_blocking(move || {
        let deadline = Instant::now() + Duration::from_secs(540);
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
    let snapshot = recording.receive_snapshot();
    if let Some(job) = snapshot["job"]["id"].as_str() {
        recording
            .receive_stop(
                &recording.profile,
                &recording.boot,
                snapshot["generation"].as_u64().unwrap(),
                job,
            )
            .unwrap();
    }
    let deadline = Instant::now() + Duration::from_secs(3);
    while recording.selection_snapshot(true).unwrap()["receive"]["owner_released"] != true
        && Instant::now() < deadline
    {
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    let released = recording.selection_snapshot(true).unwrap()["receive"]["owner_released"] == true;
    actor.request_close();
    let deadline = Instant::now() + Duration::from_secs(2);
    while !actor.close_complete() && Instant::now() < deadline {
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    ticker.abort();
    let _ = ticker.await;
    service.abort();
    let _ = service.await;
    let rig = rig.lock().unwrap();
    let setup_ms: Vec<_> = rig
        .setups
        .iter()
        .map(|(first, end)| end.map(|last| last.duration_since(*first).as_secs_f64() * 1000.0))
        .collect();
    let receipt = json!({"native_started":counts.started.load(Ordering::Acquire),"native_released":counts.released.load(Ordering::Acquire),"native_packets":counts.packets.load(Ordering::Acquire),"native_queue_refusals":counts.lost.load(Ordering::Acquire),"setup_ms":setup_ms,"exchanges":rig.exchanges.len(),"released":released,"cat_closed":rig.closed});
    drop(rig);
    std::fs::create_dir_all("test-results/radio-selection").unwrap();
    std::fs::write(
        "test-results/radio-selection/native-receipt.json",
        serde_json::to_vec_pretty(&receipt).unwrap(),
    )
    .unwrap();
    println!(
        "{}\n{}\nNative receipt: {}",
        outcome.1,
        String::from_utf8_lossy(&outcome.0.stderr),
        receipt
    );
    drop(actor);
    drop(recording);
    std::fs::remove_dir_all(dir).unwrap();
    assert!(!outcome.2, "controlled browser child deadline");
    assert!(
        outcome.0.status.success(),
        "controlled browser child failed"
    );
    assert!(
        outcome.1.contains("WSTX_SELECTION_COMPLETED 2 5 2"),
        "both real browser/profile windows and five CQ contexts must actually complete"
    );
    assert_eq!(receipt["native_started"], 5);
    assert_eq!(receipt["native_released"], 5);
    assert_eq!(receipt["setup_ms"].as_array().unwrap().len(), 5);
    assert!(
        receipt["setup_ms"]
            .as_array()
            .unwrap()
            .iter()
            .all(|v| v.as_f64().is_some_and(|ms| ms >= 4230.0 && ms < 5000.0)),
        "actual setup stays within existing5s bound"
    );
    assert!(released);
}

// Proves: CL-022-03; TC-022-007. Confirmation alone has zero native effects.
#[tokio::test]
async fn live_native_selection_commission_has_zero_native_effects() {
    crate::auth_tests::commission_zero_native_io_case().await;
}
