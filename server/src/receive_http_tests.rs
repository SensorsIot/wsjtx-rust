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
    if mode == "ft8" {
        recording.fixture_input(Box::new(Input::new(fixture)));
    } else {
        // #37: the browser chooses FT4 with the top-bar band and mode selects; the band
        // selection starts receive (in FT8) first and the mode change restarts it in FT4,
        // so each of the two receive starts opens its own native fixture input.
        recording.fixture_inputs(vec![
            Box::new(Input::new(NativeFt8Fixture::load_mode(mode))),
            Box::new(Input::new(fixture)),
        ]);
    }
    let app = App {
        origin: origin.clone(),
        profile: Some(Arc::new(ProfileState {
            store: Mutex::new(store),
            authorization: Mutex::new(None),
            boot,
            recording: recording.clone(),
            logbook: Arc::new(crate::logbook::Logbook::open(&dir)),
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

/// The hash-pinned busy recording websdr_test7.wav (27 decodes) as real-time native
/// capture whose QPC clock is the system clock: it fills the first UTC FT8 period at least
/// 2 s after Start and again the periods 30 s and 60 s later, with silence around them (#57).
#[cfg(all(windows, not(debug_assertions)))]
struct BusyPeriodInput {
    queue: Arc<audio::PacketQueue>,
    source: audio::LiveSource,
    samples: Vec<f32>,
    period: Arc<std::sync::atomic::AtomicU64>,
    clock: Option<(Instant, audio::ClockCorrelation, i128)>,
    pushed: u64,
    running: bool,
}
#[cfg(all(windows, not(debug_assertions)))]
impl BusyPeriodInput {
    fn load(period: Arc<std::sync::atomic::AtomicU64>) -> Self {
        let manifest: Value =
            serde_json::from_str(include_str!("../../fixtures/decoder/manifest.json")).unwrap();
        let sha = manifest["files"]
            .as_array()
            .unwrap()
            .iter()
            .find(|f| f["path"] == "test/wav/websdr_test7.wav")
            .unwrap()["sha256"]
            .as_str()
            .unwrap()
            .to_owned();
        let file = std::path::PathBuf::from(
            std::env::var_os("WSTX_SAMPLE_DIR").expect("WSTX_SAMPLE_DIR recording cache required"),
        )
        .join("websdr_test7.wav");
        let check = std::process::Command::new("python")
            .args(["-c", "import hashlib,pathlib,sys;assert hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest()==sys.argv[2]"])
            .arg(&file)
            .arg(sha)
            .output()
            .unwrap();
        assert!(check.status.success(), "busy recording hash changed");
        let wav = std::fs::read(&file).unwrap();
        // The pinned file is canonical 44-byte-header PCM16 mono 12 kHz audio.
        assert_eq!((&wav[..4], &wav[36..40]), (&b"RIFF"[..], &b"data"[..]));
        assert_eq!(u32::from_le_bytes(wav[24..28].try_into().unwrap()), 12_000);
        let samples: Vec<f32> = wav[44..]
            .as_chunks::<2>()
            .0
            .iter()
            .map(|b| f32::from(i16::from_le_bytes(*b)) / 32768.0)
            .collect();
        assert_eq!(samples.len(), 180_000);
        let format = audio::NativeFormat {
            rate: 48000,
            channels: 2,
            encoding: audio::Encoding::Float32,
        };
        let queue = audio::PacketQueue::new(format).unwrap();
        Self {
            source: audio::LiveSource::new(queue.clone(), format).unwrap(),
            queue,
            samples,
            period,
            clock: None,
            pushed: 0,
            running: false,
        }
    }
}
#[cfg(all(windows, not(debug_assertions)))]
impl SampleSource for BusyPeriodInput {
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
        if !self.running || !matches!(result, SourcePoll::Pending) {
            return result;
        }
        let (began, clock, offset) = *self.clock.get_or_insert_with(|| {
            let clock = audio::system_clock().unwrap();
            let period =
                (clock.utc_filetime_100ns + 20_000_000).div_ceil(150_000_000) * 150_000_000;
            self.period
                .store(period, std::sync::atomic::Ordering::Release);
            // Native frame at which the recording (and the UTC period) begins.
            let offset = i128::from(period - clock.utc_filetime_100ns) * 48000 / 10_000_000;
            (Instant::now(), clock, offset)
        });
        let due = (began.elapsed().as_nanos() * 48000 / 1_000_000_000) as u64;
        if due <= self.pushed {
            return result;
        }
        let count = (due - self.pushed).min(8192) as usize;
        let mut bytes = Vec::with_capacity(count * 8);
        for n in self.pushed..self.pushed + count as u64 {
            let at = i128::from(n) - offset;
            // Three busy periods, 30 s apart.
            let at = if (0..90 * 48000).contains(&at) {
                at % (30 * 48000)
            } else {
                at
            };
            let value = if at >= 0 {
                self.samples.get((at / 4) as usize).copied().unwrap_or(0.0)
            } else {
                0.0
            };
            bytes.extend_from_slice(&value.to_le_bytes());
            bytes.extend_from_slice(&(-value).to_le_bytes());
        }
        let qpc = clock.qpc_100ns + self.pushed * 10_000_000 / 48000;
        assert!(self.queue.push(&bytes, count, self.pushed, qpc, 0));
        self.pushed += count as u64;
        self.source.poll()
    }
}
#[cfg(all(windows, not(debug_assertions)))]
impl recording::LiveInput for BusyPeriodInput {
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

// Proves: CL-057-01, CL-057-02; TC-057-001, TC-057-002 (#57). Busy FT8 periods through the
// actual live source, window schedule, modem, publication, WebSocket, results API and
// Detailed browser: every row of a published period view is painted within 0.3 s of its
// publication, and within 0.5 s of the prompt window's completion at +13.8 s (best of two).
#[cfg(all(windows, not(debug_assertions)))]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn live_native_busy_period_rows_promptly() {
    let unix_ms = |filetime: u64| (filetime as f64 - 116_444_736_000_000_000.0) / 10_000.0;
    let period = Arc::new(std::sync::atomic::AtomicU64::new(0));
    let input = BusyPeriodInput::load(period.clone());
    let dir = std::env::temp_dir().join(format!("wstx-busy-{}", profile::new_uuid().unwrap()));
    std::fs::create_dir(&dir).unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let origin = format!("http://{address}");
    let profile_id = profile::new_uuid().unwrap();
    let boot = profile::new_uuid().unwrap();
    let doc = json!({"schema_version":1,"profile_id":profile_id,"revision":0,"display_name":"Busy period fixture",
        "callsign":"HB9BLA","locator":"JN47AA","endpoint":{"bind":address.to_string(),"origin":null},"connection_type":"standard",
        "audio":{"input_device":"explicit-test-native-input","output_device":null},"control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}});
    std::fs::write(dir.join("profile.json"), serde_json::to_vec(&doc).unwrap()).unwrap();
    let (store, _) = profile::Store::open(&dir).unwrap();
    let recording = recording::Recording::open(&dir, profile_id.clone(), boot.clone());
    recording.fixture_input(Box::new(input));
    let app = App {
        origin: origin.clone(),
        profile: Some(Arc::new(ProfileState {
            store: Mutex::new(store),
            authorization: Mutex::new(None),
            boot,
            recording: recording.clone(),
            logbook: Arc::new(crate::logbook::Logbook::open(&dir)),
        })),
        profile_id: Some(profile_id),
        token: None,
        connections: Arc::new(Semaphore::new(16)),
        login_attempts: Arc::new(Mutex::new((Instant::now(), 0))),
    };
    let service = tokio::spawn(async move {
        axum::serve(listener, router(app)).await.unwrap();
    });
    // Server-side timeline: every change of the published counter or descriptor.
    let done = Arc::new(std::sync::atomic::AtomicBool::new(false));
    let observer = {
        let (recording, done) = (recording.clone(), done.clone());
        std::thread::spawn(move || {
            let mut timeline: Vec<(f64, Value, Value)> = vec![];
            while !done.load(std::sync::atomic::Ordering::Acquire) {
                let s = recording.receive_snapshot();
                let now = unix_ms(audio::system_clock().unwrap().utc_filetime_100ns);
                let (next, view) = (
                    s["job"]["next_sequence"].clone(),
                    s["job"]["latest_decode"].clone(),
                );
                if timeline
                    .last()
                    .is_none_or(|(_, n, v)| *n != next || *v != view)
                {
                    timeline.push((now, next, view));
                }
                std::thread::sleep(Duration::from_millis(1));
            }
            timeline
        })
    };
    let outcome = tokio::task::spawn_blocking(move || {
        std::process::Command::new("node")
            .args(["--test", "tests/receive-latency.test.cjs"])
            .current_dir(
                std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                    .parent()
                    .unwrap(),
            )
            .env("WSTX_LATENCY_ORIGIN", origin)
            .output()
            .unwrap()
    })
    .await
    .unwrap();
    done.store(true, std::sync::atomic::Ordering::Release);
    let timeline = observer.join().unwrap();
    let snapshot = recording.receive_snapshot();
    let (source, job, generation) = (
        snapshot["source"]["id"].as_str().map(str::to_owned),
        snapshot["job"]["id"].as_str().map(str::to_owned),
        snapshot["generation"].as_u64().unwrap(),
    );
    // The first published views with records are the two busy periods (silence around them),
    // each with its records as published at that moment.
    let mut views: Vec<(f64, Value, Vec<Value>)> = vec![];
    for (t, _, v) in &timeline {
        let fresh = v["next_sequence"].as_u64() > v["first_sequence"].as_u64()
            && views.iter().all(|(_, seen, _)| seen["id"] != v["id"]);
        if let (true, Some(source), Some(job)) = (fresh && views.len() < 2, &source, &job) {
            let mut records = vec![];
            let mut cursor = v["first_sequence"].as_u64().unwrap();
            while cursor < v["next_sequence"].as_u64().unwrap() {
                let page = recording
                    .receive_results(source, job, generation, cursor, 16)
                    .unwrap();
                let page = page["records"].as_array().unwrap();
                records.extend(
                    page.iter()
                        .filter(|r| r["sequence"].as_u64() < v["next_sequence"].as_u64())
                        .cloned(),
                );
                cursor += page.len() as u64;
            }
            views.push((*t, v.clone(), records));
        }
    }
    if let Some(id) = &job {
        let _ = recording.receive_stop(&recording.profile, &recording.boot, generation, id);
    }
    let deadline = Instant::now() + Duration::from_secs(5);
    while recording.receive_snapshot()["audio"]["state"] != "closed" && Instant::now() < deadline {
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    service.abort();
    let _ = service.await;
    drop(recording);
    std::fs::remove_dir_all(dir).unwrap();
    let stdout = String::from_utf8_lossy(&outcome.stdout);
    assert!(
        outcome.status.success(),
        "{stdout}\n{}",
        String::from_utf8_lossy(&outcome.stderr)
    );
    if let Some(line) = stdout
        .lines()
        .find(|l| l.starts_with("WSTX_LATENCY_FAILURE "))
    {
        println!("{line}");
    }
    let browser: Value = serde_json::from_str(
        stdout
            .lines()
            .find_map(|l| l.strip_prefix("WSTX_LATENCY_BROWSER "))
            .expect("browser timeline"),
    )
    .unwrap();
    assert_eq!(
        views.len(),
        2,
        "two published busy-period views: {:?}",
        views.iter().map(|v| &v.1).collect::<Vec<_>>()
    );
    let first = unix_ms(period.load(std::sync::atomic::Ordering::Acquire)) + 13_800.0;
    let events = |key: &str| browser[key].as_array().unwrap().clone();
    let activity = events("activity");
    let mut completion_latencies = vec![];
    for (index, (published, view, records)) in views.iter().enumerate() {
        // Measurement report relative to the window completion (period start + 13.8 s).
        let completed = first + 30_000.0 * index as f64;
        let at = |t: f64| format!("{:+.3}s", (t - completed) / 1000.0);
        let near = |t: f64| t >= completed - 500.0 && t <= completed + 8000.0;
        let expected: Vec<Value> = records.iter().map(|r| r["sequence"].clone()).collect();
        assert!(
            expected.len() >= 25,
            "busy period decodes {}",
            expected.len()
        );
        println!("VIEW {view}");
        for (t, next, v) in timeline.iter().filter(|(t, _, _)| near(*t)) {
            println!("SERVER {} next_sequence={next} latest_decode={v}", at(*t));
        }
        for f in events("frames")
            .iter()
            .filter(|f| near(f["t"].as_f64().unwrap()))
        {
            println!("WS {} receive.state", at(f["t"].as_f64().unwrap()));
        }
        for r in events("requests")
            .iter()
            .filter(|r| near(r["t"].as_f64().unwrap()))
        {
            let t = r["t"].as_f64().unwrap();
            println!(
                "HTTP {} {} {} {}",
                at(t),
                r["phase"],
                r["route"],
                r["query"]
            );
        }
        for a in activity.iter().filter(|a| near(a["t"].as_f64().unwrap())) {
            let rows = a["sequences"].as_array().unwrap().len();
            println!(
                "PAINT {} rows={rows} header={}",
                at(a["t"].as_f64().unwrap()),
                a["header"]
            );
        }
        let painted = activity
            .iter()
            .find(|a| {
                let shown = a["sequences"].as_array().unwrap();
                expected.iter().all(|s| shown.contains(s))
            })
            .expect("every published busy-period row painted");
        // The painted rows are exactly the published decode set.
        let mut shown: Vec<String> = painted["texts"]
            .as_array()
            .unwrap()
            .iter()
            .map(|t| t.as_str().unwrap().to_owned())
            .collect();
        let mut texts: Vec<String> = records
            .iter()
            .map(|r| {
                r["text"].as_str().map_or_else(
                    || format!("Payload {}", r["status"].as_str().unwrap()),
                    str::to_owned,
                )
            })
            .collect();
        println!("DECODES {} {texts:?}", texts.len());
        shown.sort();
        texts.sort();
        assert_eq!(shown, texts);
        let painted = painted["t"].as_f64().unwrap();
        println!(
            "LATENCY view published {} all {} rows painted {} ({:.0} ms after publication)",
            at(*published),
            expected.len(),
            at(painted),
            painted - published
        );
        assert!(
            painted - published <= 300.0,
            "rows painted {:.0} ms after their publication (budget 300 ms)",
            painted - published
        );
        completion_latencies.push(painted - completed);
    }
    println!("COMPLETION all rows painted {completion_latencies:?} ms after window completion");
    let best = completion_latencies
        .iter()
        .copied()
        .fold(f64::INFINITY, f64::min);
    assert!(
        best <= 500.0,
        "rows painted {best:.0} ms after the window completed at best (budget 500 ms)"
    );
}

#[cfg(all(windows, not(debug_assertions)))]
struct StationMetrics {
    child: std::process::Child,
    output: std::io::BufReader<std::process::ChildStdout>,
    sequence: u64,
}
#[cfg(all(windows, not(debug_assertions)))]
impl StationMetrics {
    fn helper() -> std::path::PathBuf {
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .join("tools/windows_process_metrics.py")
    }
    /// The existing metrics helper binds this waiting test process by its creation time.
    fn bind_self() -> Self {
        use std::io::BufRead;
        use std::process::{Command, Stdio};
        let identity = Command::new("python")
            .arg(Self::helper())
            .arg("--parent-identity")
            .output()
            .unwrap();
        assert!(identity.status.success(), "{identity:?}");
        let identity: Value = serde_json::from_slice(&identity.stdout).unwrap();
        assert_eq!(identity["pid"], std::process::id());
        let creation = identity["creation_filetime"].as_u64().unwrap();
        let mut child = Command::new("python")
            .arg(Self::helper())
            .args(["--pid", &std::process::id().to_string()])
            .args(["--creation", &creation.to_string()])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        let mut output = std::io::BufReader::new(child.stdout.take().unwrap());
        let mut line = String::new();
        output.read_line(&mut line).unwrap();
        let bound: Value = serde_json::from_str(&line).unwrap();
        assert_eq!(bound["state"], "bound", "{line}");
        assert_eq!(bound["creation_filetime"], creation);
        Self {
            child,
            output,
            sequence: 0,
        }
    }
    fn request(&mut self, op: &str) -> Value {
        use std::io::{BufRead, Write};
        self.sequence += 1;
        let stdin = self.child.stdin.as_mut().unwrap();
        writeln!(stdin, "{}", json!({"op":op,"id":self.sequence})).unwrap();
        stdin.flush().unwrap();
        let mut line = String::new();
        self.output.read_line(&mut line).unwrap();
        let value: Value = serde_json::from_str(&line).unwrap();
        assert_eq!(value["id"], self.sequence, "{line}");
        value
    }
    fn sample(&mut self) -> Value {
        let value = self.request("sample");
        assert_eq!(value["unit"], "bytes");
        assert_eq!(value["pid"], std::process::id());
        value
    }
}

// Proves: CL-007-04; TC-004-003. Station process private-commit delta <=96MiB over idle and
// receive-owner release <=250ms after Stop, on the actual manager, provider and decoder.
// Exclusive resource window only (station capture paused, no concurrent builds).
#[cfg(all(windows, not(debug_assertions)))]
#[test]
#[ignore = "exclusive resource window: station process delta and owner release"]
fn resource_station_process_delta_and_owner_release() {
    let dir = std::env::temp_dir().join(format!(
        "wstx-station-resource-{}",
        profile::new_uuid().unwrap()
    ));
    std::fs::create_dir(&dir).unwrap();
    let profile_id = profile::new_uuid().unwrap();
    let boot = profile::new_uuid().unwrap();
    let doc = json!({"schema_version":1,"profile_id":profile_id,"revision":0,"display_name":"Station resource fixture",
        "callsign":"HB9BLA","locator":"JN47AA","endpoint":{"bind":"127.0.0.1:0","origin":null},"connection_type":"standard",
        "audio":{"input_device":"explicit-test-native-input","output_device":null},"control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}});
    std::fs::write(dir.join("profile.json"), serde_json::to_vec(&doc).unwrap()).unwrap();
    let recording = recording::Recording::open(&dir, profile_id.clone(), boot.clone());
    let mut metrics = StationMetrics::bind_self();
    let idle = metrics.sample();
    let mut phases = Vec::new();
    // Frames ingested when the decoded phase first published: the complete fixture,
    // including the trailing support that hands its window to the decoder.
    let mut ingested = std::collections::BTreeMap::<&str, u64>::new();
    for (phase, mode) in [
        ("after-decode", "ft8"),
        ("busy-window", "ft8"),
        ("after-decode", "ft4"),
        ("busy-window", "ft4"),
    ] {
        let fixture = NativeFt8Fixture::load_mode(mode);
        let payload = fixture.expected["payload77"].as_str().unwrap().to_owned();
        let generation = recording.receive_snapshot()["generation"].as_u64().unwrap();
        let started = recording
            .receive_start_input(
                &profile_id,
                &boot,
                generation,
                "explicit-test-native-input".into(),
                if mode == "ft8" { "ft8" } else { "ft4" },
                Box::new(Input::new(fixture)),
            )
            .unwrap();
        let job = started["job"]["id"].as_str().unwrap().to_owned();
        let job_generation = started["generation"].as_u64().unwrap();
        let deadline = Instant::now() + Duration::from_secs(60);
        let mut decoded = false;
        loop {
            let snapshot = recording.receive_snapshot();
            assert_eq!(snapshot["job"]["state"], "running", "{snapshot}");
            let processed = snapshot["job"]["processed_frames"].as_u64().unwrap_or(0);
            if phase == "busy-window" && processed >= ingested[mode] {
                // The window is with the decoder; no publication yet means it is in progress.
                assert_eq!(
                    snapshot["job"]["available_count"], 0,
                    "{mode}: decode completed before Stop; busy release not established"
                );
                break;
            }
            if phase == "after-decode"
                && snapshot["job"]["available_count"].as_u64().unwrap_or(0) > 0
            {
                let source = snapshot["source"]["id"].as_str().unwrap();
                let page = recording
                    .receive_results(source, &job, job_generation, 0, 64)
                    .unwrap();
                if page.to_string().contains(&payload) {
                    decoded = true;
                    ingested.insert(mode, processed);
                    break;
                }
            }
            assert!(
                Instant::now() < deadline,
                "{phase} {mode}: no progress {snapshot}"
            );
            std::thread::sleep(Duration::from_millis(1));
        }
        let during = metrics.sample();
        let published = recording.receive_snapshot()["job"]["available_count"].clone();
        let stop = Instant::now();
        recording
            .receive_stop(&profile_id, &boot, job_generation, &job)
            .unwrap();
        while recording.selection_snapshot(false).unwrap()["receive"]["owner_released"] != true {
            assert!(
                stop.elapsed() < Duration::from_secs(5),
                "{phase} {mode}: owner never released"
            );
            std::thread::sleep(Duration::from_micros(200));
        }
        let release = stop.elapsed();
        if phase == "busy-window" {
            let after = recording.receive_snapshot()["job"]["available_count"].clone();
            assert!(
                after.is_null() || after == 0,
                "{mode}: cancelled busy decode published {after}"
            );
        }
        phases.push(json!({"phase":phase,"mode":mode,"decoded_expected":decoded,
            "published_at_stop":published,"release_seconds":release.as_secs_f64(),
            "private_usage_before_stop":during["private_usage"]}));
        assert!(phase != "after-decode" || decoded);
        assert!(
            release <= Duration::from_millis(250),
            "{phase} {mode}: receive owner release {release:?} > 250ms"
        );
    }
    let final_sample = metrics.sample();
    let idle_private = idle["private_usage"].as_u64().unwrap();
    let peak = final_sample["lifetime_peak_commit"].as_u64().unwrap();
    let delta = peak.saturating_sub(idle_private);
    let power = std::process::Command::new("powercfg")
        .arg("/getactivescheme")
        .output()
        .unwrap();
    let os = std::process::Command::new("cmd")
        .args(["/c", "ver"])
        .output()
        .unwrap();
    println!(
        "RESOURCE_STATION {}",
        json!({"idle":idle,"final":final_sample,"lifetime_peak_minus_idle_private_bytes":delta,
            "limit_bytes":96u64*1024*1024,"phases":phases,
            "delta_basis":"lifetime peak commit of the whole test process (manager, provider, decoder, harness) minus idle private usage; conservative upper bound",
            "os_version":String::from_utf8_lossy(&os.stdout),"power_scheme":String::from_utf8_lossy(&power.stdout),
            "processor_identifier":std::env::var("PROCESSOR_IDENTIFIER").unwrap_or_default(),
            "parallelism":std::thread::available_parallelism().unwrap().get(),
            "executable":std::env::current_exe().unwrap()})
    );
    assert_eq!(metrics.request("close")["state"], "closed");
    metrics.child.wait().unwrap();
    drop(recording);
    let _ = std::fs::remove_dir_all(dir);
    assert!(
        delta <= 96 * 1024 * 1024,
        "station process delta {delta} bytes > 96MiB"
    );
}
