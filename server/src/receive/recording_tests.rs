//! Canonical SysML recording/display independent byte/math/state oracles. Cost 2, Windows PC; no hardware.
use super::*;
use crate::contact_http::tests::DrivenClock;
use profile::tests::{Fault, FaultScope, FaultyFiles, Step};

/// A FlexRadio session whose snapshot the test sets; it reaches no radio. It starts as a
/// newly started session does (unauthorized, revision 1, not allowed); tuning answers
/// not ready and its receive input is unavailable.
pub(crate) struct ScriptedSession {
    snapshot: Mutex<wstx_rust::flex::Snapshot>,
    revision: std::sync::atomic::AtomicU64,
    allowed: AtomicBool,
}
impl ScriptedSession {
    pub(crate) fn new() -> Arc<Self> {
        Arc::new(Self {
            snapshot: Mutex::new(wstx_rust::flex::Snapshot {
                state: wstx_rust::flex::State::Unauthorized,
                error: None,
                radio_code: None,
                session: 0,
                radio: None,
                slice: None,
                counters: wstx_rust::flex::session::Counters::default(),
                last_peak: None,
                vita_tsi: None,
                vita_offset_ms: None,
                jitter_mean_ms: None,
                jitter_max_ms: None,
                retry_after_ms: None,
            }),
            revision: std::sync::atomic::AtomicU64::new(1),
            allowed: AtomicBool::new(false),
        })
    }
    /// Changes the snapshot and raises the pushed revision.
    pub(crate) fn set(&self, change: impl FnOnce(&mut wstx_rust::flex::Snapshot)) {
        change(&mut self.snapshot.lock().unwrap());
        self.revision.fetch_add(1, Ordering::AcqRel);
    }
}
impl crate::flex_http::NativeSession for ScriptedSession {
    fn snapshot(&self) -> wstx_rust::flex::Snapshot {
        self.snapshot.lock().unwrap().clone()
    }
    fn ready(&self) -> bool {
        self.snapshot.lock().unwrap().state == wstx_rust::flex::State::Ready
    }
    fn revision(&self) -> u64 {
        self.revision.load(Ordering::Acquire)
    }
    fn set_allowed(&self, allowed: bool) {
        self.allowed.store(allowed, Ordering::Release);
    }
    fn tune(
        &self,
        _: u64,
        _: Instant,
        _: &Arc<AtomicBool>,
    ) -> std::result::Result<u64, wstx_rust::flex::Error> {
        Err(wstx_rust::flex::Error::NotReady)
    }
    fn input(self: Arc<Self>) -> std::result::Result<Box<dyn LiveInput>, source::SourceError> {
        Err(source::SourceError::Unavailable)
    }
}
#[path = "live_receive_tests.rs"]
mod live_receive_tests;
#[path = "../supervisor/operating_selection_tests.rs"]
mod operating_selection_tests;
#[path = "../radioControl/radio_connection_tests.rs"]
mod radio_connection_tests;
#[path = "receive_job_tests.rs"]
mod receive_job_tests;
#[path = "../profile/recording_tests.rs"]
mod recordings_tests;
#[path = "spectrum_rows_tests.rs"]
mod spectrum_rows_tests;
#[path = "recording_tx_tests.rs"]
mod tx;

fn live_ring(r: &Recording) -> (Job, decoder::Decode) {
    let source = Arc::new(SourceDescriptor {
        schema_version: 1,
        profile_id: r.profile.clone(),
        boot_id: r.boot.clone(),
        source_id: profile::new_uuid().unwrap(),
        rate_hz: 12000,
        channel: "mono_real",
        total_frames: None,
        utc_anchor: None,
    });
    let job = Job {
        id: profile::new_uuid().unwrap(),
        source_id: Some(source.source_id.clone()),
        generation: 1,
        kind: "live",
        state: "running",
        processed_frames: 180000,
        error: None,
        cancel: Arc::new(AtomicBool::new(false)),
    };
    let mut s = r.state.lock().unwrap();
    s.generation = 1;
    s.job = Some(job.clone());
    s.live = Some(LiveState {
        mode: "ft8",
        audio: audio::AudioStatus {
            state: audio::AudioState::Running,
            error: None,
            retry_after_ms: None,
        },
        device_id: "isolated-test".into(),
        source: Some(source),
        timing: None,
        next_frame: 180000,
        records: VecDeque::new(),
        record_bytes: 0,
        first_sequence: 0,
        next_sequence: 0,
        search_limited: false,
        last_overrun: None,
        capture_drift: None,
        clock_correction: 0,
        publication_error: None,
        level: (0.0, 0, None, None),
        loss_epochs: 0,
        last_loss: None,
    });
    let decoded = decoder::Decode {
        payload: decoder::unpack(&[0; 77]),
        start_frame: 6000,
        frequency_hz: 1000.0,
        snr_db: None,
        a_priori: None,
    };
    (job, decoded)
}

/// A disposable profile directory and the file fake, live inputs, spawner and replay
/// sources every recording opened on it uses.
struct Fixture(
    PathBuf,
    Arc<FaultyFiles>,
    Arc<QueuedInputs>,
    Arc<CountingSpawner>,
    Arc<WatchedReplays>,
);
use crate::receive_http_tests::QueuedInputs;
impl Fixture {
    /// Queues `input` as the only input and starts receive on it at the current profile
    /// revision.
    fn start(
        &self,
        r: &Arc<Recording>,
        generation: u64,
        device: &str,
        mode: &'static str,
        input: crate::receive_http_tests::Input,
    ) -> Result<Value> {
        self.2.replace(Box::new(input));
        let revision = r.state.lock().unwrap().operating.profile_revision;
        r.receive_start(
            &r.profile,
            &r.boot,
            generation,
            revision,
            device.into(),
            mode,
        )
    }
}

/// The real spawner, counting each worker from its spawn until its job returns; armed, its
/// next spawn fails and runs nothing.
#[derive(Default)]
pub(crate) struct CountingSpawner {
    counts: Arc<(Mutex<(usize, usize)>, std::sync::Condvar)>,
    fail: AtomicBool,
}
/// Ends the count of one worker however its job returns.
struct Counted(Arc<(Mutex<(usize, usize)>, std::sync::Condvar)>);
impl Drop for Counted {
    fn drop(&mut self) {
        self.0.0.lock().unwrap().0 -= 1;
        self.0.1.notify_all();
    }
}
impl CountingSpawner {
    pub(crate) fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }
    /// The next spawn fails with an injected error.
    fn fail_next(&self) {
        self.fail.store(true, Ordering::Release);
    }
    fn active(&self) -> usize {
        self.counts.0.lock().unwrap().0
    }
    fn peak(&self) -> usize {
        self.counts.0.lock().unwrap().1
    }
    /// Waits, at most `within`, until no worker is active.
    fn wait_idle(&self, within: Duration) {
        let counts = self.counts.0.lock().unwrap();
        let _ = self
            .counts
            .1
            .wait_timeout_while(counts, within, |c| c.0 > 0)
            .unwrap();
    }
}
impl Spawner for CountingSpawner {
    fn spawn(
        &self,
        name: Option<&'static str>,
        run: Box<dyn FnOnce() + Send>,
    ) -> std::io::Result<std::thread::JoinHandle<()>> {
        if self.fail.swap(false, Ordering::AcqRel) {
            return Err(std::io::Error::other("injected receive spawn failure"));
        }
        {
            let mut c = self.counts.0.lock().unwrap();
            c.0 += 1;
            c.1 = c.1.max(c.0);
        }
        let counted = Counted(self.counts.clone());
        Threads.spawn(
            name,
            Box::new(move || {
                let _counted = counted;
                run();
            }),
        )
    }
}

/// The real replay sources, checking at each block that a replay holds at most two blocks
/// of at most 4096 samples alive and has released every earlier one.
#[derive(Default)]
pub(crate) struct WatchedReplays {
    peak: Arc<std::sync::atomic::AtomicUsize>,
}
impl WatchedReplays {
    pub(crate) fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }
    /// The most blocks one replay held alive at once.
    fn peak(&self) -> usize {
        self.peak.load(Ordering::Acquire)
    }
}
impl ReplaySources for WatchedReplays {
    fn open(&self, path: &Path, source: Arc<SourceDescriptor>) -> Result<Box<dyn ReplaySource>> {
        Ok(Box::new(Watched {
            inner: WavFiles.open(path, source)?,
            blocks: Vec::new(),
            peak: self.peak.clone(),
        }))
    }
}
struct Watched {
    inner: Box<dyn ReplaySource>,
    blocks: Vec<std::sync::Weak<[f32]>>,
    peak: Arc<std::sync::atomic::AtomicUsize>,
}
impl ReplaySource for Watched {
    fn next(&mut self) -> Result<Option<SampleBlock>> {
        let block = self.inner.next()?;
        self.blocks.retain(|b| b.strong_count() > 0);
        if let Some(block) = &block {
            for earlier in &self.blocks {
                assert_eq!(
                    earlier.strong_count(),
                    1,
                    "spectrum must release every previous immutable sample allocation"
                );
            }
            assert!(block.samples.len() <= 4096);
            self.blocks.push(Arc::downgrade(&block.samples));
            assert!(self.blocks.len() <= 2);
            self.peak.fetch_max(self.blocks.len(), Ordering::AcqRel);
        }
        Ok(block)
    }
}

impl Fixture {
    fn new() -> Self {
        let path =
            std::env::temp_dir().join(format!("wstx-recording-{}", profile::new_uuid().unwrap()));
        fs::create_dir(&path).unwrap();
        Self(
            path,
            FaultyFiles::new(),
            QueuedInputs::new(),
            CountingSpawner::new(),
            WatchedReplays::new(),
        )
    }
    fn recording(&self) -> Arc<Recording> {
        self.recording_on(DrivenClock::new())
    }
    /// The recording on the station clocks `clock`.
    fn recording_on(&self, clock: Arc<DrivenClock>) -> Arc<Recording> {
        let r = Recording::open(
            &self.0,
            "00000000-0000-4000-8000-000000000001".into(),
            profile::new_uuid().unwrap(),
            self.1.clone(),
            clock,
            self.3.clone(),
            self.4.clone(),
        );
        self.2.fill(&r);
        r
    }
    fn wave(&self, bytes: &[u8]) -> File {
        let path = self.0.join("fixture.wav");
        fs::write(&path, bytes).unwrap();
        File::open(path).unwrap()
    }
}

fn selection_intent(
    r: &Recording,
    action: &'static str,
    mode: Option<&'static str>,
    band: Option<&str>,
) -> selection::Intent {
    let s = r.state.lock().unwrap();
    selection::Intent {
        profile_id: r.profile.clone(),
        boot_id: r.boot.clone(),
        command_id: profile::new_uuid().unwrap(),
        profile_revision: s.operating.profile_revision,
        generation: s.generation,
        revision: s.operating.revision,
        action,
        mode,
        band: band.map(str::to_owned),
    }
}
fn selection_wait(r: &Recording) -> Value {
    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        let s = r.selection_snapshot(false).unwrap();
        if s["operation"]["result"] != "pending" {
            return s;
        }
        assert!(
            Instant::now() < deadline,
            "selection fixture terminal deadline"
        );
        std::thread::sleep(Duration::from_millis(1));
    }
}
fn selection_released(r: &Recording) {
    let deadline = Instant::now() + Duration::from_secs(2);
    while r.selection_snapshot(false).unwrap()["receive"]["owner_released"] != true {
        assert!(
            Instant::now() < deadline,
            "receive fixture must actually release"
        );
        std::thread::sleep(Duration::from_millis(1));
    }
}

// The test-only model-value reader
// (harness/project/docs/specifics/local-windows-development.md, "Model values read by tests").
use wstx_test_tools::model_values::{Model, Number};

// The preferred FT8 and FT4 dial frequency of each band in WSJT-X's default
// list of frequencies (WstxOperatingSelection::BandFrequency), copied by hand from
// WSJT-X v3.3.0-beta4 (commit 0f7d5928449ec747c3d1f6da1306f8c94404c3a9),
// models/FrequencyList.cpp (SHA-256
// e556d7ab30462ee8d8b1480f7781a7575101b71d5213c05fa1300344622cc0d4); never generated
// from the implementation's band table. None: WSJT-X lists no FT4 frequency on the band.
const PREFERRED_BAND_ENTRIES: [(&str, u64, Option<u64>); 12] = [
    ("160m", 1_840_000, None),
    ("80m", 3_573_000, Some(3_575_000)),
    ("60m", 5_357_000, Some(5_357_000)),
    ("40m", 7_074_000, Some(7_047_500)),
    ("30m", 10_136_000, Some(10_140_000)),
    ("20m", 14_074_000, Some(14_080_000)),
    ("17m", 18_100_000, Some(18_104_000)),
    ("15m", 21_074_000, Some(21_140_000)),
    ("12m", 24_915_000, Some(24_919_000)),
    ("10m", 28_074_000, Some(28_180_000)),
    ("6m", 50_313_000, Some(50_318_000)),
    ("4m", 70_154_000, None),
];

fn selection_profile_fixture() -> (
    Fixture,
    Arc<Recording>,
    crate::App,
    profile::Settings,
    Arc<AtomicBool>,
) {
    let fixture = Fixture::new();
    let r = Recording::open(
        &fixture.0,
        profile::new_uuid().unwrap(),
        profile::new_uuid().unwrap(),
        std::sync::Arc::new(crate::profile::Disk),
        DrivenClock::new(),
        Arc::new(Threads),
        Arc::new(WavFiles),
    );
    let document = json!({"schema_version":1,"profile_id":r.profile,"revision":0,"display_name":"Before edit","callsign":"HB9BLA","locator":"JN47AA","endpoint":{"bind":"127.0.0.1:18001","origin":null},"connection_type":"standard","audio":{"input_device":null,"output_device":null},"control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}});
    fs::write(
        fixture.0.join("profile.json"),
        serde_json::to_vec(&document).unwrap(),
    )
    .unwrap();
    let (store, _) =
        profile::Store::open(&fixture.0, std::sync::Arc::new(crate::profile::Disk)).unwrap();
    let mut settings = store.document.settings();
    settings.display_name = "After edit".into();
    let cancelled = Arc::new(AtomicBool::new(false));
    {
        let mut s = r.state.lock().unwrap();
        s.operating.revision = 1;
        s.operating.operation = Some(selection::Operation {
            command_id: profile::new_uuid().unwrap(),
            base_revision: 0,
            revision: 1,
            action: "band",
            requested: selection::Requested {
                mode: "ft8",
                band: "40m",
                nominal_hz: 7074000,
            },
            phase: "applying",
            result: "pending",
            error: None,
            monitor_before: false,
            monitor_wanted: true,
            old_job_id: None,
            new_job_id: None,
            new_generation: None,
            old_generation: 0,
            new_worker_cancel: None,
            cancelled: cancelled.clone(),
        });
    }
    let app = crate::App {
        origin: "http://127.0.0.1:18001".into(),
        profile: Some(Arc::new(crate::ProfileState {
            store: Mutex::new(store),
            authorization: Mutex::new(None),
            boot: r.boot.clone(),
            recording: r.clone(),
            logbook: Arc::new(crate::logbook::Logbook::open(
                &fixture.0,
                std::sync::Arc::new(crate::profile::Disk),
            )),
        })),
        profile_id: Some(r.profile.clone()),
        token: None,
        connections: Arc::new(crate::Semaphore::new(16)),
        login_attempts: Arc::new(Mutex::new((Instant::now(), 0))),
    };
    (fixture, r, app, settings, cancelled)
}
fn selection_edit_request(
    app: &crate::App,
    settings: profile::Settings,
) -> (
    crate::HeaderMap,
    std::result::Result<crate::Bytes, crate::BytesRejection>,
) {
    let mut headers = crate::HeaderMap::new();
    headers.insert(crate::header::ORIGIN, app.origin.parse().unwrap());
    headers.insert(
        crate::header::CONTENT_TYPE,
        "application/json".parse().unwrap(),
    );
    let bytes =
        serde_json::to_vec(&json!({"profile_id":app.profile_id,"revision":0,"settings":settings}))
            .unwrap();
    (headers, Ok(crate::Bytes::from(bytes)))
}

impl Drop for Fixture {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}
fn wav(samples: &[i16]) -> Vec<u8> {
    let length = u32::try_from(samples.len() * 2).unwrap();
    let mut b = Vec::from(*b"RIFF");
    b.extend((36 + length).to_le_bytes());
    b.extend(b"WAVEfmt ");
    b.extend(16u32.to_le_bytes());
    b.extend(1u16.to_le_bytes());
    b.extend(1u16.to_le_bytes());
    b.extend(12000u32.to_le_bytes());
    b.extend(24000u32.to_le_bytes());
    b.extend(2u16.to_le_bytes());
    b.extend(16u16.to_le_bytes());
    b.extend(b"data");
    b.extend(length.to_le_bytes());
    for value in samples {
        b.extend(value.to_le_bytes());
    }
    b
}
fn import(r: &Arc<Recording>, bytes: &[u8]) -> Result<String> {
    let generation = r.state.lock().unwrap().generation;
    let v = r.reserve(&r.profile, &r.boot, generation)?;
    let id = v["id"].as_str().unwrap();
    for (n, chunk) in bytes.chunks(2048).enumerate() {
        let offset = (n * 2048) as u64;
        r.begin_chunk(id, offset, bytes.len() as u64)?;
        r.chunk(id, offset, bytes.len() as u64, chunk.to_vec())?;
    }
    Ok(id.to_owned())
}
/// A bound of `WstxRecordingTransfer::RecordingLimits`, read from the model: with its unit
/// (`fileBytes`, `importMaxFrames`, `rateHz`) or as a plain count (`importMaxRiffChunks`).
fn recording_limit(feature: &str) -> usize {
    let name = format!("WstxRecordingTransfer::RecordingLimits::{feature}");
    let model = Model::load();
    let value = if feature == "importMaxRiffChunks" {
        model.number(&name)
    } else {
        model.number_with_unit(&name)
    };
    match value.unwrap_or_else(|e| panic!("model value {e}")) {
        Some(Number::Integer(v)) if v > 0 => v as usize,
        other => panic!("model value {name}: not a positive integer: {other:?}"),
    }
}

fn dft(samples: &[f32], k: usize) -> f64 {
    let mut re = 0.0;
    let mut im = 0.0;
    for (n, &x) in samples.iter().enumerate() {
        let window = (1.0 - (std::f64::consts::TAU * n as f64 / 2048.0).cos()) / 2.0;
        let angle = std::f64::consts::TAU * k as f64 * n as f64 / 2048.0;
        re += f64::from(x) * window * angle.cos();
        im -= f64::from(x) * window * angle.sin();
    }
    re.hypot(im) * (if k == 0 { 1.0 } else { 2.0 }) / 1024.0
}

fn relative_clock(r: &Recording, mode: &'static str, anchor: &str, anchor_frame: u64) {
    let mut s = r.state.lock().unwrap();
    let live = s.live.as_mut().unwrap();
    live.mode = mode;
    live.timing = Some(source::SourceTiming {
        source_id: live.source.as_ref().unwrap().source_id.clone(),
        segment: 0,
        native_rate: 48000,
        native_anchor_frame: 0.0,
        canonical_anchor_frame: anchor_frame,
        converter_delay_native_frames: 0.0,
        qpc_anchor_100ns: Some(0),
        system_utc_anchor: Some(anchor.into()),
        uncertainty_ns: Some(500),
        correlated: true,
        external_accuracy: source::ExternalAccuracy::Unknown,
    });
}

struct DecodeBoundaryInput {
    context: source::SourceContext,
    next: Option<SampleBlock>,
    owner: Arc<Recording>,
    views: Arc<Mutex<Vec<Value>>>,
    /// Distinct decoder_activity values seen while the decode in progress polls.
    activity: Arc<Mutex<Vec<(bool, u64)>>>,
    running: bool,
}
impl SampleSource for DecodeBoundaryInput {
    fn descriptor(&self) -> Option<Arc<SourceDescriptor>> {
        Some(self.context.descriptor.clone())
    }
    fn acknowledge_epoch(
        &mut self,
        _: u64,
        _: Arc<SourceDescriptor>,
        _: source::SourceTiming,
    ) -> std::result::Result<(), source::SourceError> {
        Err(source::SourceError::InvalidContext)
    }
    fn poll(&mut self) -> SourcePoll {
        let view = self.owner.receive_snapshot()["job"]["latest_decode"].clone();
        if !view.is_null() && self.views.lock().unwrap().last() != Some(&view) {
            self.views.lock().unwrap().push(view);
        }
        let activity = self.owner.decoder_activity();
        let mut seen = self.activity.lock().unwrap();
        if seen.last() != Some(&activity) {
            seen.push(activity);
        }
        drop(seen);
        self.next
            .take()
            .map(SourcePoll::Block)
            .unwrap_or(SourcePoll::Pending)
    }
}
impl LiveInput for DecodeBoundaryInput {
    fn start(&mut self) -> std::result::Result<(), source::SourceError> {
        self.running = true;
        Ok(())
    }
    fn request_stop(&mut self) {
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

/// A live input whose capture clock reports a scripted (canonical frame, UTC) sample.
struct ClockInput {
    context: source::SourceContext,
    clock: Arc<Mutex<Option<(u64, u64)>>>,
}
impl SampleSource for ClockInput {
    fn descriptor(&self) -> Option<Arc<SourceDescriptor>> {
        Some(self.context.descriptor.clone())
    }
    fn acknowledge_epoch(
        &mut self,
        _: u64,
        _: Arc<SourceDescriptor>,
        _: source::SourceTiming,
    ) -> std::result::Result<(), source::SourceError> {
        Err(source::SourceError::InvalidContext)
    }
    fn poll(&mut self) -> SourcePoll {
        SourcePoll::Pending
    }
}
impl LiveInput for ClockInput {
    fn start(&mut self) -> std::result::Result<(), source::SourceError> {
        Ok(())
    }
    fn request_stop(&mut self) {}
    fn status(&self) -> audio::AudioStatus {
        audio::AudioStatus {
            state: audio::AudioState::Running,
            error: None,
            retry_after_ms: None,
        }
    }
    fn clock_utc(&self) -> Option<(u64, u64)> {
        *self.clock.lock().unwrap()
    }
}

/// Runs `seconds` of FT8 live capture through the real window buffer and live worker clock
/// tracking. The capture clock runs `ppm` slow against UTC, with packet jitter and a +0.4 s
/// system clock step half way. Returns, per prompt window, the UTC error of its completion
/// against +13.8 s and whether it holds an ordinary DT 0 frame (UTC +0.5..+13.14 s).
fn drifting_prompt_windows(track: bool, seconds: u64, ppm: f64) -> (Vec<(f64, bool)>, Value) {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (job, _) = live_ring(&r);
    relative_clock(&r, "ft8", "2026-11-01T00:00:00.0000000Z", 0);
    let (context, timing) = {
        let s = r.state.lock().unwrap();
        let l = s.live.as_ref().unwrap();
        let timing = l.timing.as_ref().unwrap().clone();
        (
            source::SourceContext {
                descriptor: l.source.as_ref().unwrap().clone(),
                timing: Arc::new(timing.clone()),
            },
            timing,
        )
    };
    let anchor = filetime_from_utc("2026-11-01T00:00:00.0000000Z").unwrap() as f64;
    let total = seconds * 12000;
    // True UTC (100 ns) of canonical frame f.
    let utc = |f: u64| {
        let step = if f > total / 2 { 4_000_000.0 } else { 0.0 };
        anchor + f as f64 * (10_000_000.0 / 12000.0) * (1.0 + ppm * 1e-6) + step
    };
    let clock = Arc::new(Mutex::new(None));
    let input = ClockInput {
        context: context.clone(),
        clock: clock.clone(),
    };
    let mut worker = LiveWorker::new(r.clone(), job, Box::new(input), "ft8");
    let schedule = window_schedule(&timing, decoder::Mode::Ft8, 0).unwrap();
    worker.window = Some(
        receive::WindowBuffer::new(decoder::Mode::Ft8, context.descriptor.clone())
            .unwrap()
            .with_schedule(&schedule),
    );
    let samples: Arc<[f32]> = Arc::from(vec![0.0; 240]);
    let period = 150_000_000.0;
    let mut prompts = vec![];
    let mut first = 0;
    while first < total {
        let block = SampleBlock::live(&context, first, samples.clone(), false).unwrap();
        let outcome = worker.window.as_mut().unwrap().push(&block).unwrap();
        // Deterministic packet jitter of up to +-3 ms.
        let jitter = ((first / 240 * 7919) % 61) as f64 * 1_000.0 - 30_000.0;
        *clock.lock().unwrap() = Some((first, (utc(first) + jitter) as u64));
        if track && let Some(drift) = worker.track_clock(Some(&timing)) {
            r.state.lock().unwrap().live.as_mut().unwrap().capture_drift = Some(drift);
        }
        if let Some(window) = outcome.window.filter(|w| !w.waits) {
            let end = window.origin + window.samples.len() as u64;
            let completed = utc(end) - anchor;
            let slot = ((completed - 138_000_000.0) / period).round() * period;
            let error = (completed - slot - 138_000_000.0) / 10_000_000.0;
            let holds = utc(window.origin) - anchor <= slot + 5_000_000.0
                && completed >= slot + 131_400_000.0;
            prompts.push((error, holds));
        }
        first += 240;
    }
    // The /receive clock object keeps master's exact keys; drift is read on demand.
    let mut keys = r.receive_snapshot()["clock"]
        .as_object()
        .unwrap()
        .keys()
        .cloned()
        .collect::<Vec<_>>();
    keys.sort();
    assert_eq!(
        keys,
        [
            "basis",
            "canonical_anchor_frame",
            "correlated",
            "external_accuracy",
            "uncertainty_ns",
            "utc_anchor"
        ]
    );
    (prompts, r.receive_clock())
}

/// A recording with a live FT8 ring at the fixed anchor whose station clock and recording run
/// on one driven clock at offset zero, as main wires them.
fn air_station() -> (
    Fixture,
    Arc<Recording>,
    Arc<crate::clock_http::Clock>,
    Arc<DrivenClock>,
    Job,
    decoder::Decode,
) {
    let fixture = Fixture::new();
    let time = DrivenClock::new();
    let r = fixture.recording_on(time.clone());
    let clock = crate::clock_http::Clock::new(
        crate::contact_http::tests::RoundSource::idle(),
        time.clone(),
        Box::new(|| wstx_rust::transmit::clock::WindowsTime::Running),
    );
    let _ = r.clock.set(clock.clone());
    let (job, decoded) = live_ring(&r);
    relative_clock(&r, "ft8", "2026-11-01T00:00:00.0000000Z", 0);
    (fixture, r, clock, time, job, decoded)
}

/// A deterministic FT8 period: the independent "cq" vector at 1500 Hz from period +0.5 s
/// over white noise, with 0.25 s of much louder noise at the period start (as a receiver's
/// AGC releasing) and before it, so the SNR depends on where the period starts.
fn ft8_period_audio(frames: usize, period: usize) -> Vec<f32> {
    let vectors: Value = serde_json::from_str(include_str!(
        "../../../fixtures/decoder/independent-vectors/manifest.json"
    ))
    .unwrap();
    let tones = vectors["vectors"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["mode"] == "ft8" && v["id"] == "cq")
        .unwrap()["tones"]
        .as_str()
        .unwrap()
        .bytes()
        .map(|b| b - b'0')
        .collect::<Vec<_>>();
    let wave = decoder::quadratures(decoder::Mode::Ft8, &tones, 1500.).unwrap();
    let mut state = 0x2545_f491_4f6c_dd1du64;
    let mut uniform = || {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        (state >> 11) as f64 / (1u64 << 53) as f64 - 0.5
    };
    (0..frames)
        .map(|i| {
            let noise = (0..4).map(|_| uniform()).sum::<f64>() * 0.02;
            let loud = if i < period + 3000 { 10. } else { 1. };
            let signal = i
                .checked_sub(period + 6000)
                .and_then(|k| wave.get(k))
                .map_or(0., |w| 0.004 * f64::from(w[0]));
            (noise * loud + signal) as f32
        })
        .collect()
}

/// A RIFF WAVE file of these chunks, each padded to an even length.
fn riff(chunks: &[(&[u8; 4], Vec<u8>)]) -> Vec<u8> {
    let mut b = Vec::from(*b"RIFF");
    b.extend([0; 4]);
    b.extend(b"WAVE");
    for (name, body) in chunks {
        b.extend(*name);
        b.extend((body.len() as u32).to_le_bytes());
        b.extend(body);
        if body.len() % 2 == 1 {
            b.push(0);
        }
    }
    let size = (b.len() - 8) as u32;
    b[4..8].copy_from_slice(&size.to_le_bytes());
    b
}

/// A selection of the station that is pending.
fn pending_selection(command: &str, revision: u64) -> selection::Operation {
    selection::Operation {
        command_id: command.into(),
        base_revision: revision.saturating_sub(1),
        revision,
        action: "band",
        requested: selection::Requested {
            mode: "ft8",
            band: "40m",
            nominal_hz: 7074000,
        },
        phase: "releasing",
        result: "pending",
        error: None,
        monitor_before: false,
        monitor_wanted: true,
        old_job_id: None,
        new_job_id: None,
        new_generation: None,
        old_generation: 0,
        new_worker_cancel: None,
        cancelled: Arc::new(AtomicBool::new(false)),
    }
}

impl Recording {
    pub(crate) fn fixture_radio(&self, actor: Arc<wstx_rust::radio_control::actor::Actor>) {
        let snapshot = actor.snapshot().unwrap();
        let mut s = self.state.lock().unwrap();
        assert!(
            s.operating.radio.actor.is_none(),
            "fixture must not replace a live actor under the state lock"
        );
        s.operating.radio.generation = snapshot.authority.connection_generation;
        s.operating.radio.cached = Some(snapshot);
        s.operating.radio.actor = Some(actor);
    }
    /// Test fixture: the operating selection band (no radio command).
    pub(crate) fn fixture_band(&self, band: &'static str) {
        self.state.lock().unwrap().operating.nominal.band = Some(band);
    }
    /// CL-044-07 test seam: the live receive's input endpoint.
    pub(crate) fn fixture_live_device(&self, id: &str) {
        if let Some(live) = self.state.lock().unwrap().live.as_mut() {
            live.device_id = id.into();
        }
    }
    /// Fixture: a complete manual operating selection (band with its nominal frequency, origin
    /// manual) as the browser validates it; no radio command.
    #[cfg(not(debug_assertions))]
    pub(crate) fn fixture_manual_band(&self, band: &'static str, nominal_hz: u64) {
        let mut s = self.state.lock().unwrap();
        s.operating.nominal.band = Some(band);
        s.operating.nominal.nominal_hz = Some(nominal_hz);
        s.operating.nominal.origin = "manual";
    }
    /// Test seam: the live receive's capture epoch (None: none yet; Some(correlated))
    /// and its measured drift (None: not measured; Some(None): rate not yet known).
    pub(crate) fn fixture_capture_clock(&self, epoch: Option<bool>, drift: Option<Option<f64>>) {
        let mut s = self.state.lock().unwrap();
        if let Some(l) = s.live.as_mut() {
            l.timing = epoch.map(|correlated| source::SourceTiming {
                source_id: "fixture-capture".into(),
                segment: 0,
                native_rate: 48_000,
                native_anchor_frame: 0.0,
                canonical_anchor_frame: 0,
                converter_delay_native_frames: 0.0,
                qpc_anchor_100ns: None,
                system_utc_anchor: correlated.then(|| "2026-11-09T12:00:00.0000000Z".into()),
                uncertainty_ns: None,
                correlated,
                external_accuracy: source::ExternalAccuracy::Unknown,
            });
            l.capture_drift = drift.map(|ppm| (0, ppm));
        }
    }
    /// Test seam: an injected running live job whose result records the test publishes
    /// itself (hand-authored rows; no decoder). Returns (source, job, generation).
    pub(crate) fn fixture_live_job(&self, mode: &'static str) -> (String, String, u64) {
        let mut s = self.state.lock().unwrap();
        s.generation += 1;
        let generation = s.generation;
        let id = profile::new_uuid().unwrap();
        let source_id = profile::new_uuid().unwrap();
        s.job = Some(Job {
            id: id.clone(),
            source_id: Some(source_id.clone()),
            generation,
            kind: "live",
            state: "running",
            processed_frames: 0,
            error: None,
            cancel: Arc::new(AtomicBool::new(false)),
        });
        s.latest_decode = None;
        if matches!(mode, "ft4" | "ft8") {
            s.operating_mode = mode;
        }
        s.live = Some(LiveState {
            mode,
            audio: audio::AudioStatus {
                state: audio::AudioState::Running,
                error: None,
                retry_after_ms: None,
            },
            device_id: "fixture-contact-rows".into(),
            source: Some(Arc::new(SourceDescriptor {
                schema_version: 1,
                profile_id: self.profile.clone(),
                boot_id: self.boot.clone(),
                source_id: source_id.clone(),
                rate_hz: 12000,
                channel: "mono_real",
                total_frames: None,
                utc_anchor: None,
            })),
            timing: None,
            next_frame: 0,
            records: VecDeque::new(),
            record_bytes: 0,
            first_sequence: 0,
            next_sequence: 0,
            search_limited: false,
            last_overrun: None,
            capture_drift: None,
            clock_correction: 0,
            publication_error: None,
            level: (0.0, 0, None, Some(47)),
            loss_epochs: 0,
            last_loss: None,
        });
        drop(s);
        self.sync_transmit_mode();
        (source_id, id, generation)
    }
    /// Test seam: the operating selection's band and nominal dial as an origin sets them (no
    /// radio command); a band None clears the selection.
    pub(crate) fn fixture_operating(
        &self,
        band: Option<&'static str>,
        nominal_hz: Option<u64>,
        origin: &'static str,
    ) {
        let mut s = self.state.lock().unwrap();
        s.operating.nominal.band = band;
        s.operating.nominal.nominal_hz = nominal_hz;
        s.operating.nominal.origin = origin;
    }
    /// Test seam: the current job's kind (a played recording is "recording").
    pub(crate) fn fixture_job_kind(&self, kind: &'static str) {
        if let Some(j) = self.state.lock().unwrap().job.as_mut() {
            j.kind = kind;
        }
    }
    /// Test seam: a published live record without a period start (uncorrelated).
    pub(crate) fn fixture_uncorrelated(&self, sequence: u64) {
        let mut s = self.state.lock().unwrap();
        if let Some(l) = s.live.as_mut()
            && let Some((record, _)) = l
                .records
                .iter_mut()
                .find(|(r, _)| r["sequence"] == sequence)
        {
            record["period_start_utc"] = Value::Null;
        }
    }
    /// Test seam: one loss-only source epoch of the live receive (same job and source).
    pub(crate) fn fixture_loss_epoch(&self) {
        if let Some(l) = self.state.lock().unwrap().live.as_mut() {
            l.loss_epochs += 1;
        }
    }
    /// Test seam: the live receive stops (no job, no live state), as after a receive stop.
    pub(crate) fn fixture_stop_live_job(&self) {
        let mut s = self.state.lock().unwrap();
        s.job = None;
        s.live = None;
    }
    /// Test seam: one detailed waterfall row of the live job in the period starting at
    /// `period_start_ms` (FT8 periods), with its levels per native bin, as the receive worker
    /// feeds WstxHoldTx::SlotLevel.
    pub(crate) fn fixture_detail_row(&self, period_start_ms: i64, levels: &[u8], tx: bool) {
        let (job, generation, mode) = {
            let s = self.state.lock().unwrap();
            let j = s.job.as_ref().unwrap();
            (
                j.id.clone(),
                j.generation,
                s.live.as_ref().map_or("ft8", |l| l.mode),
            )
        };
        let period_ms = if mode == "ft4" { 7500 } else { 15000 };
        self.waterfall.lock().unwrap().row(
            (&job, generation),
            period_start_ms,
            period_ms,
            levels,
            tx,
        );
    }
    /// Test seam: publishes one period of fixture records (sequence assigned here) and
    /// its latest-decode descriptor. Returns the assigned sequences.
    pub(crate) fn fixture_publish_period(
        &self,
        period_start_utc: &str,
        records: Vec<Value>,
    ) -> Vec<u64> {
        self.fixture_publish_view(period_start_utc, records, true)
    }
    /// Test seam: `fixture_publish_period` as a partial publication (complete false).
    pub(crate) fn fixture_publish_partial(
        &self,
        period_start_utc: &str,
        records: Vec<Value>,
    ) -> Vec<u64> {
        self.fixture_publish_view(period_start_utc, records, false)
    }
    fn fixture_publish_view(
        &self,
        period_start_utc: &str,
        records: Vec<Value>,
        complete: bool,
    ) -> Vec<u64> {
        let mut s = self.state.lock().unwrap();
        let counter = s.decode_counter + 1;
        let l = s.live.as_mut().unwrap();
        let first = l.next_sequence;
        let mut sequences = Vec::new();
        for mut record in records {
            record["sequence"] = json!(l.next_sequence);
            record["period_start_utc"] = json!(period_start_utc);
            sequences.push(l.next_sequence);
            let size = serde_json::to_vec(&record).unwrap().len();
            l.records.push_back((record, size));
            l.record_bytes += size;
            l.next_sequence += 1;
        }
        let next = l.next_sequence;
        s.decode_counter = counter;
        s.latest_decode = Some(LatestDecode {
            id: counter,
            first_sequence: first,
            next_sequence: next,
            period_start_utc: Some(period_start_utc.into()),
            complete,
            transmitted: false,
        });
        self.publication.send_modify(|n| *n = n.wrapping_add(1));
        sequences
    }
    /// Test seam: the late window of the latest view's period, as publish_view republishes it
    /// (WstxLiveReceive::PeriodViews): `records` appended to that period (sequence assigned here),
    /// the view complete under the same id with next_sequence grown by them (unchanged for none),
    /// and the publication watch signalled. Returns the assigned sequences.
    pub(crate) fn fixture_grow_latest(&self, records: Vec<Value>) -> Vec<u64> {
        let mut s = self.state.lock().unwrap();
        let period = s
            .latest_decode
            .as_ref()
            .and_then(|d| d.period_start_utc.clone())
            .expect("a latest view of a period");
        let l = s.live.as_mut().unwrap();
        let mut sequences = Vec::new();
        for mut record in records {
            record["sequence"] = json!(l.next_sequence);
            record["period_start_utc"] = json!(period);
            sequences.push(l.next_sequence);
            let size = serde_json::to_vec(&record).unwrap().len();
            l.records.push_back((record, size));
            l.record_bytes += size;
            l.next_sequence += 1;
        }
        let next = l.next_sequence;
        let latest = s.latest_decode.as_mut().unwrap();
        latest.next_sequence = next;
        latest.complete = true;
        self.publication.send_modify(|n| *n = n.wrapping_add(1));
        sequences
    }
}
