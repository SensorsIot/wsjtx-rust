#![forbid(unsafe_code)]
use super::*;
#[path = "../../fixtures/radio/native_ft8_fixture.rs"]
#[cfg(not(debug_assertions))]
mod native_fixture;
#[cfg(not(debug_assertions))]
use native_fixture::{NATIVE_FRAMES, NativeFt8Fixture, TRAILING_SILENT_FRAMES};
use source::{SampleSource, SourceDescriptor, SourceError, SourcePoll, SourceTiming};

/// Injects only independently verified native packets. Conversion, epoch ACK,
/// windowing, numerical decoding, manager, HTTP and browser are production code.
pub(crate) struct Input {
    #[cfg(not(debug_assertions))]
    fixture: Option<NativeFt8Fixture>,
    #[cfg(not(debug_assertions))]
    queue: Arc<audio::PacketQueue>,
    source: audio::LiveSource,
    #[cfg(not(debug_assertions))]
    first: usize,
    running: bool,
    release_gate: Option<(
        Arc<std::sync::atomic::AtomicBool>,
        Arc<std::sync::atomic::AtomicBool>,
    )>,
}
impl Input {
    pub(crate) fn block_release(
        &mut self,
    ) -> (
        Arc<std::sync::atomic::AtomicBool>,
        Arc<std::sync::atomic::AtomicBool>,
    ) {
        let gate = (
            Arc::new(std::sync::atomic::AtomicBool::new(false)),
            Arc::new(std::sync::atomic::AtomicBool::new(false)),
        );
        self.release_gate = Some(gate.clone());
        gate
    }
    #[cfg(not(debug_assertions))]
    fn new(fixture: NativeFt8Fixture) -> Self {
        let mut input = Self::queued().0;
        input.fixture = Some(fixture);
        input
    }
    pub(crate) fn queued() -> (Self, Arc<audio::PacketQueue>) {
        let format = audio::NativeFormat {
            rate: 48000,
            channels: 2,
            encoding: audio::Encoding::Float32,
        };
        let queue = audio::PacketQueue::new(format).unwrap();
        let input = Self {
            #[cfg(not(debug_assertions))]
            fixture: None,
            source: audio::LiveSource::new(queue.clone(), format).unwrap(),
            #[cfg(not(debug_assertions))]
            queue: queue.clone(),
            #[cfg(not(debug_assertions))]
            first: 0,
            running: false,
            release_gate: None,
        };
        (input, queue)
    }
}
impl Drop for Input {
    fn drop(&mut self) {
        if let Some((entered, released)) = &self.release_gate {
            entered.store(true, std::sync::atomic::Ordering::Release);
            while !released.load(std::sync::atomic::Ordering::Acquire) {
                std::thread::sleep(Duration::from_millis(1));
            }
        }
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
        let result = self.source.poll();
        #[cfg(not(debug_assertions))]
        {
            if !self.running || !matches!(result, SourcePoll::Pending) || self.fixture.is_none() {
                return result;
            }
            // One mode period: the latest-period UI must not be asked to retain an older
            // fixture station after a second, deliberately empty FT4 period.
            let frames = if self.fixture.as_ref().unwrap().expected["mode"] == "ft4" {
                NATIVE_FRAMES / 2
            } else {
                NATIVE_FRAMES
            };
            if self.first < frames {
                let count = 8192.min(frames - self.first);
                let packet = self
                    .fixture
                    .as_ref()
                    .unwrap()
                    .native_stereo(self.first, count);
                // The fixture has no independent QPC-to-UTC clock; zero is not a clock anchor.
                let flags = if self.first == 0 {
                    audio::TIMESTAMP_ERROR
                } else {
                    0
                };
                assert!(self.queue.push(&packet, count, self.first as u64, 0, flags));
                self.first += count;
                return self.source.poll();
            }
            if self.first == frames {
                assert!(self.queue.push(
                    &[],
                    TRAILING_SILENT_FRAMES,
                    self.first as u64,
                    0,
                    audio::SILENT
                ));
                self.first += TRAILING_SILENT_FRAMES;
                return self.source.poll();
            }
        }
        result
    }
}
impl recording::LiveInput for Input {
    fn start(&mut self) -> Result<(), SourceError> {
        self.running = true;
        Ok(())
    }
    fn request_stop(&mut self) {
        self.running = false;
        self.source.stop();
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

// Proves: CL-008-02/03/05; CL-010-05/07/08; TC-009-004.
// Cost2: isolated real HTTP server + Chromium on development PC; no hardware.
// Mandatory release execution is registered as live-station-browser.
#[cfg(not(debug_assertions))]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn live_native_fixture_reaches_real_manager_http_and_browser_callsign() {
    live_native_browser_mode("ft8").await;
}

// Proves: CL-008-02/03/05; CL-010-05/07/08; TC-009-004.
// Same actual native provider, decoder, owner, HTTP and browser path in FT4 mode.
#[cfg(not(debug_assertions))]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn live_native_ft4_fixture_reaches_real_manager_http_and_browser_callsign() {
    live_native_browser_mode("ft4").await;
}

#[cfg(not(debug_assertions))]
async fn live_native_browser_mode(mode: &str) {
    let fixture = if mode == "ft8" {
        NativeFt8Fixture::load()
    } else {
        NativeFt8Fixture::load_mode(mode)
    };
    let expected = fixture.expected.clone();
    let dir = std::env::temp_dir().join(format!(
        "wstx-live-browser-{}",
        profile::new_uuid().unwrap()
    ));
    std::fs::create_dir(&dir).unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let origin = format!("http://{address}");
    let profile_id = profile::new_uuid().unwrap();
    let boot = profile::new_uuid().unwrap();
    let doc = json!({"schema_version":1,"profile_id":profile_id,"revision":0,"display_name":format!("Actual native {} fixture", mode.to_uppercase()),
        "callsign":"HB9BLA","locator":"JN47AA","endpoint":{"bind":address.to_string(),"origin":null},"connection_type":"standard",
        "audio":{"input_device":"explicit-test-native-input","output_device":null},"control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}});
    std::fs::write(dir.join("profile.json"), serde_json::to_vec(&doc).unwrap()).unwrap();
    let (store, _) = profile::Store::open(&dir).unwrap();
    let recording = recording::Recording::open(&dir, profile_id.clone(), boot.clone());
    recording.fixture_input(Box::new(Input::new(fixture)));
    let app = App {
        origin: origin.clone(),
        profile: Some(Arc::new(ProfileState {
            store: Mutex::new(store),
            authorization: Mutex::new(None),
            boot,
            recording: recording.clone(),
        })),
        profile_id: Some(profile_id),
        token: None,
        connections: Arc::new(Semaphore::new(16)),
        login_attempts: Arc::new(Mutex::new((Instant::now(), 0))),
    };
    let service = tokio::spawn(async move {
        axum::serve(listener, router(app)).await.unwrap();
    });
    let outcome = tokio::task::spawn_blocking(move || {
        std::process::Command::new("node")
            .args(["--test", "tests/receive-integration.test.cjs"])
            .current_dir(
                std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                    .parent()
                    .unwrap(),
            )
            .env("WSTX_RECEIVE_FIXTURE_ORIGIN", origin)
            .env("WSTX_RECEIVE_FIXTURE_EXPECTED", expected.to_string())
            .output()
            .unwrap()
    })
    .await
    .unwrap();
    let snapshot = recording.receive_snapshot();
    if let Some(id) = snapshot["job"]["id"].as_str() {
        let _ = recording.receive_stop(
            &recording.profile,
            &recording.boot,
            snapshot["generation"].as_u64().unwrap(),
            id,
        );
    }
    let deadline = Instant::now() + Duration::from_secs(5);
    while recording.receive_snapshot()["audio"]["state"] != "closed" && Instant::now() < deadline {
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    assert_eq!(recording.receive_snapshot()["audio"]["state"], "closed");
    service.abort();
    let _ = service.await;
    drop(recording);
    std::fs::remove_dir_all(dir).unwrap();
    assert!(
        outcome.status.success(),
        "{}\n{}",
        String::from_utf8_lossy(&outcome.stdout),
        String::from_utf8_lossy(&outcome.stderr)
    );
    println!("{}", String::from_utf8_lossy(&outcome.stdout));
}
