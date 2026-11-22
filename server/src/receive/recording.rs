use crate::flex_http::NativeSession;
pub use crate::source::{SampleBlock, SourceDescriptor};
use crate::{audio, decoder, receive, source};
use crate::{profile, selection, spectrum};
use base64::{Engine, engine::general_purpose::STANDARD};
use live_receive::*;
use receive_job::*;
use recordings::*;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use source::{SampleSource, SourcePoll};
use std::collections::VecDeque;
use std::{
    fs::{self, File},
    io::{Read, Seek, SeekFrom},
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};
use wstx_rust::transmit::air;
#[path = "receive_diagnostics.rs"]
pub(crate) mod diagnostics;
#[path = "live_receive.rs"]
mod live_receive;
#[path = "../supervisor/operating_selection.rs"]
mod operating_selection;
#[path = "../radioControl/radio_connection.rs"]
mod radio_connection;
#[path = "receive_job.rs"]
mod receive_job;
#[path = "../profile/recording.rs"]
mod recordings;
#[path = "spectrum_rows.rs"]
mod spectrum_rows;
#[path = "../supervisor/receive_startup.rs"]
pub(crate) mod startup;
#[cfg(test)]
#[path = "recording_tests.rs"]
pub(crate) mod tests;

/// WstxRecordingTransfer::RecordingLimits: the one sample rate of a recording, the largest
/// recording file, its most samples and chunks, and the times of an import.
pub const RATE_HZ: u32 = 12000;
pub const FILE_BYTES: u64 = 3_145_728;
const IMPORT_MAX_FRAMES: u64 = 1_440_000;
const IMPORT_MAX_RIFF_CHUNKS: u32 = 64;
const RESERVATION_MS: u64 = 30_000;
const UPLOAD_IDLE_MS: u64 = 15_000;
const UPLOAD_TOTAL_MS: u64 = 1_800_000;
/// WstxReceiveJob::LiveResults: the records kept and their bytes, the largest record and
/// the SNR limit of a record.
const KEPT_RECORDS: usize = 2048;
const KEPT_MI_B: usize = 2;
const RECORD_MAX_BYTES: usize = 2048;
const SNR_LIMIT_DB: f64 = 60.0;
pub type Result<T> = std::result::Result<T, &'static str>;
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Metadata {
    schema_version: u8,
    recording_id: String,
    file_bytes: u64,
    frames: u64,
    rate_hz: u32,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Manifest {
    schema_version: u8,
    recording_id: String,
}
#[derive(Clone, Copy, Debug)]
pub struct Wave {
    pub offset: u64,
    pub frames: u64,
    pub bytes: u64,
}
pub struct SourceFile {
    file: File,
    source: Arc<SourceDescriptor>,
    position: u64,
    frames: u64,
}
/// The replay source port: opens the committed recording a replay reads its blocks from.
pub trait ReplaySources: Send + Sync {
    fn open(&self, path: &Path, source: Arc<SourceDescriptor>) -> Result<Box<dyn ReplaySource>>;
}
/// One opened replay input: the next block of at most 4096 samples, or the end.
pub trait ReplaySource: Send {
    fn next(&mut self) -> Result<Option<SampleBlock>>;
}
/// The real replay source: the recording's WAV file.
pub struct WavFiles;
/// The worker spawner port: the receive and replay workers start through it.
pub trait Spawner: Send + Sync {
    fn spawn(
        &self,
        name: Option<&'static str>,
        run: Box<dyn FnOnce() + Send>,
    ) -> std::io::Result<std::thread::JoinHandle<()>>;
}
/// The real spawner: one operating-system thread per job, named when a name is given.
pub struct Threads;
impl Spawner for Threads {
    fn spawn(
        &self,
        name: Option<&'static str>,
        run: Box<dyn FnOnce() + Send>,
    ) -> std::io::Result<std::thread::JoinHandle<()>> {
        let mut builder = std::thread::Builder::new();
        if let Some(name) = name {
            builder = builder.name(name.into());
        }
        builder.spawn(run)
    }
}
#[derive(Clone, Serialize)]
pub struct Import {
    pub id: String,
    pub state: &'static str,
    pub received_bytes: u64,
    pub total_bytes: Option<u64>,
    pub error: Option<&'static str>,
    pub recording_id: Option<String>,
    #[serde(skip)]
    started: Instant,
    #[serde(skip)]
    touched: Instant,
    #[serde(skip)]
    pub worker: bool,
    #[serde(skip)]
    cleanup_started: Option<Instant>,
}
#[derive(Clone, Serialize)]
pub struct Job {
    pub id: String,
    pub source_id: Option<String>,
    pub generation: u64,
    pub kind: &'static str,
    pub state: &'static str,
    pub processed_frames: u64,
    pub error: Option<&'static str>,
    #[serde(skip)]
    cancel: Arc<AtomicBool>,
}
pub struct State {
    pub generation: u64,
    recording: Option<Metadata>,
    committed_id: Option<String>,
    unknown_commit: bool,
    pub source_error: Option<&'static str>,
    pub storage_error: Option<&'static str>,
    pub import: Option<Import>,
    pub job: Option<Job>,
    pub frame: Option<Value>,
    pub detail_frame: Option<Value>,
    /// The most recent Detailed rows (at most DETAIL_RECENT_ROWS, oldest first), so each
    /// subscriber receives every row in order after a processing stall.
    pub detail_recent: VecDeque<Value>,
    live: Option<LiveState>,
    latest_decode: Option<LatestDecode>,
    decode_counter: u64,
    /// WstxUdp Status decoding: the live decoder is processing an analysis window
    /// now, and the number of windows it began (monotonic for the process).
    decoding: bool,
    decode_windows: u64,
    operating: selection::Operating,
    live_worker: Option<std::thread::JoinHandle<()>>,
    live_owner_released: bool,
    /// WstxOperatingSelection::OperatingModeRule: the mode of the last started ft4/ft8 live job
    /// or admitted mode selection, whichever came last (FT8 at a fresh boot).
    operating_mode: &'static str,
}
pub struct Recording {
    pub state: Mutex<State>,
    dir: PathBuf,
    pub profile: String,
    pub boot: String,
    /// The one CL-022-03/04 automatic CAT policy of this station.
    cat: Mutex<crate::cat_lifecycle::Lifecycle>,
    /// The transmit owner of this station (WstxTransmitPart::TransmitService), started once by
    /// the process.
    pub(crate) transmit: std::sync::OnceLock<Arc<crate::transmit_http::Station>>,
    /// The periods this station transmitted in, observed from the transmit owner.
    pub(crate) tx: Mutex<TxPeriods>,
    /// The contact engine of this station (WstxQsoPart::QsoService), started once by the
    /// process.
    pub(crate) contact: std::sync::OnceLock<Arc<crate::contact_http::Station>>,
    /// FR-023 native session of a native profile, started once by the process.
    pub(crate) flex: std::sync::OnceLock<Arc<dyn NativeSession>>,
    /// Who is connected, for the rule without a client.
    pub(crate) clients: crate::automation::Clients,
    /// WstxHoldTx::SlotLevel: the per-period waterfall power of the live receive.
    pub(crate) waterfall: Mutex<crate::freeslot::Waterfall>,
    /// WstxUdp interface of this station, opened once by the process.
    pub(crate) udp: std::sync::OnceLock<Arc<crate::udp::Owner>>,
    /// The read-only PSK Reporter feed (WstxHearingFeed::HearingFeed), started once by the
    /// process; absent in in-process tests, so none of them can reach the network.
    pub(crate) pskr: std::sync::OnceLock<Arc<crate::pskr::Feed>>,
    /// The station clock and its saved source, started once by the process.
    pub(crate) clock: std::sync::OnceLock<Arc<crate::clock_http::Clock>>,
    /// Radio detection of this station (one at a time).
    pub(crate) radio_setup: crate::radio_setup::Owner,
    /// The station-managed radio AGC (CL-044-10).
    pub(crate) agc: crate::radio_agc::Owner,
    pub(crate) tx_level: crate::radio_level::Owner,
    /// Bumped at each latest_decode publication so Detailed WebSocket peers announce it at
    /// once instead of on the 2 s receive tick (CL-057-01).
    pub(crate) publication: tokio::sync::watch::Sender<u64>,
    /// The station's call hash table (WstxMessagePayload::HashResolution), shared
    /// with the transmit owner; kept for the process lifetime.
    pub(crate) hashes: Arc<Mutex<decoder::HashTable>>,
    /// The persisted receive choice and Monitor-off setting (receive-startup.json).
    startup: Mutex<startup::Startup>,
    /// Per-window receive diagnostics and the dump setting (receive-diagnostics.json).
    diagnostics: Mutex<diagnostics::Diagnostics>,
    /// A failed background window dump, reported in the diagnostics view.
    diagnostics_error: Arc<AtomicBool>,
    /// The file port the recordings are written, listed and removed through.
    files: Arc<dyn profile::Files>,
    /// The station's clocks: replay pacing, the Set level settle and the meter reads.
    pub(crate) time: Arc<dyn wstx_rust::transmit::clock::Clock>,
    /// The CAT line opener the entry point supplies; without one CAT is unavailable.
    pub(crate) cat_opener: std::sync::OnceLock<Arc<dyn wstx_rust::radio_control::executor::Opener>>,
    /// The audio inputs a live start opens, filled by the entry point; without them a live
    /// start other than a native session is audio_unavailable.
    pub(crate) inputs: std::sync::OnceLock<Arc<dyn LiveInputs>>,
    /// The spawner of the receive and replay workers.
    spawner: Arc<dyn Spawner>,
    /// The source a replay reads its recording from.
    replays: Arc<dyn ReplaySources>,
}

/// One analysis window's decode in progress (Recording::begin_window_decode).
pub(crate) struct WindowDecode(Arc<Recording>);
impl Drop for WindowDecode {
    fn drop(&mut self) {
        self.0
            .state
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .decoding = false;
    }
}

#[derive(Clone, Serialize)]
struct LatestDecode {
    id: u64,
    first_sequence: u64,
    next_sequence: u64,
    period_start_utc: Option<String>,
    complete: bool,
    /// CL-061-04: the period is one this station transmitted in; it had no decode
    /// attempt. The key is present only when true.
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    transmitted: bool,
}

/// Tx periods (CL-061-04): the T/R period starts (station UTC ms) in which this
/// station was on the air (PTT keyed, a transmission or Tune), the latest KEPT_PERIODS,
/// and whether it is on the air now. The receive path neither decodes nor measures the Rx
/// level in them; capture keeps running.
const KEPT_PERIODS: usize = 16;
#[derive(Default)]
pub(crate) struct TxPeriods {
    keyed: bool,
    starts: VecDeque<i64>,
}
impl TxPeriods {
    /// One observation of the transmit owner at station UTC `now_ms`.
    pub(crate) fn note(
        &mut self,
        now_ms: i64,
        keyed: bool,
        last_period_start_ms: Option<i64>,
        period_ms: i64,
    ) {
        self.keyed = keyed;
        let current = keyed.then(|| now_ms.div_euclid(period_ms) * period_ms);
        for start in [last_period_start_ms, current].into_iter().flatten() {
            if !self.starts.contains(&start) {
                self.starts.push_back(start);
                if self.starts.len() > KEPT_PERIODS {
                    self.starts.pop_front();
                }
            }
        }
    }
    fn contains(&self, start_ms: i64) -> bool {
        self.starts.contains(&start_ms)
    }
}

struct LiveState {
    mode: &'static str,
    audio: audio::AudioStatus,
    device_id: String,
    source: Option<Arc<SourceDescriptor>>,
    timing: Option<source::SourceTiming>,
    next_frame: u64,
    records: VecDeque<(Value, usize)>,
    record_bytes: usize,
    first_sequence: u64,
    next_sequence: u64,
    search_limited: bool,
    last_overrun: Option<(u64, u64)>,
    /// Measured capture clock minus the epoch anchor's prediction (100 ns) and its rate
    /// in ppm, from ClockTracker; it re-anchors the window schedule and UTC/DT.
    capture_drift: Option<(i128, Option<f64>)>,
    /// The station clock correction (clock from the air, 100 ns) the live worker
    /// applied with the drift: windows, period and DT refer to system UTC plus both.
    clock_correction: i128,
    publication_error: Option<&'static str>,
    /// WstxLiveReceive::RxLevel accumulation (sum of squares in 16-bit
    /// full-scale units, sample count, window start) and the last published value.
    level: (f64, u64, Option<Instant>, Option<i32>),
    /// Unknown-loss epoch rotations of this live receive and the latest trigger code;
    /// they survive the rotations they count and reset only with a new live start.
    loss_epochs: u64,
    last_loss: Option<&'static str>,
}
/// WstxLiveReceive::RxLevel: the highest receive level.
const MAX_DB: f64 = 90.0;
/// rxLevelDb = round(10 log10(mean(s^2))) with s scaled to 32768, clamped to 0..MAX_DB.
pub(crate) fn rx_level_db(sum_squares: f64, count: u64) -> i32 {
    if count == 0 || sum_squares <= 0.0 {
        return 0;
    }
    (10.0 * (sum_squares / count as f64).log10())
        .round()
        .clamp(0.0, MAX_DB) as i32
}
impl LiveState {
    fn accumulate_level(&mut self, samples: &[f32], now: Instant) {
        let (sum, count, since, _) = &mut self.level;
        for s in samples {
            let v = f64::from(*s) * 32768.0;
            *sum += v * v;
        }
        *count += samples.len() as u64;
        let start = *since.get_or_insert(now);
        // At most one value per second (the status interval).
        if now.duration_since(start) >= Duration::from_secs(1) {
            let value = rx_level_db(*sum, *count);
            self.level = (0.0, 0, Some(now), Some(value));
        }
    }
    fn clear_context(&mut self) {
        self.source = None;
        self.timing = None;
        self.next_frame = 0;
        self.records.clear();
        self.record_bytes = 0;
        self.first_sequence = 0;
        self.next_sequence = 0;
        self.search_limited = false;
        self.last_overrun = None;
        self.capture_drift = None;
        self.publication_error = None;
        self.level = (0.0, 0, None, None);
    }
}

/// Native resource ownership stays with the existing receive worker. Tests supply the
/// actual queue/converter here; there is no production fixture endpoint.
pub(crate) trait LiveInput: SampleSource + Send {
    fn start(&mut self) -> std::result::Result<(), source::SourceError>;
    fn request_stop(&mut self);
    fn status(&self) -> audio::AudioStatus;
    /// Latest (canonical frame, UTC FILETIME) of the capture clock, when measurable.
    fn clock_utc(&self) -> Option<(u64, u64)> {
        None
    }
    /// Zero-filled and glitch-flagged canonical frames inside `[from, to)`, when known.
    fn marked_frames(&self, _from: u64, _to: u64) -> Option<(u64, u64)> {
        None
    }
    /// The capture's cumulative loss and glitch counters, when known.
    fn capture_diagnostics(&self) -> Option<audio::CaptureDiagnostics> {
        None
    }
}
impl LiveInput for wstx_rust::flex::NativeInput {
    fn start(&mut self) -> std::result::Result<(), source::SourceError> {
        self.start()
    }
    fn request_stop(&mut self) {
        self.request_stop();
    }
    fn status(&self) -> audio::AudioStatus {
        self.status()
    }
    fn clock_utc(&self) -> Option<(u64, u64)> {
        wstx_rust::flex::NativeInput::clock_utc(self)
    }
    fn marked_frames(&self, from: u64, to: u64) -> Option<(u64, u64)> {
        Some(wstx_rust::flex::NativeInput::marked_frames(self, from, to))
    }
    fn capture_diagnostics(&self) -> Option<audio::CaptureDiagnostics> {
        Some(wstx_rust::flex::NativeInput::capture_diagnostics(self))
    }
}
#[derive(Clone, Copy)]
enum StartGuard {
    Profile(u64),
    Selection(u64),
}
/// The live input port: a live start opens the input of its device through it.
pub(crate) trait LiveInputs: Send + Sync {
    fn open(&self, device: &str) -> std::result::Result<Box<dyn LiveInput>, source::SourceError>;
}
/// The real live inputs: an audio controller over the capture device.
#[cfg(windows)]
pub(crate) struct AudioInputs {
    pub(crate) capture: Arc<dyn audio::CaptureDevice>,
}
#[cfg(windows)]
impl LiveInputs for AudioInputs {
    fn open(&self, device: &str) -> std::result::Result<Box<dyn LiveInput>, source::SourceError> {
        Ok(Box::new(audio::AudioController::new(
            device.to_owned(),
            self.capture.clone(),
        )?))
    }
}
#[cfg(windows)]
impl LiveInput for audio::AudioController {
    fn start(&mut self) -> std::result::Result<(), source::SourceError> {
        self.start()
    }
    fn request_stop(&mut self) {
        self.request_stop();
    }
    fn status(&self) -> audio::AudioStatus {
        self.status()
    }
    fn clock_utc(&self) -> Option<(u64, u64)> {
        audio::AudioController::clock_utc(self)
    }
    fn marked_frames(&self, from: u64, to: u64) -> Option<(u64, u64)> {
        audio::AudioController::marked_frames(self, from, to)
    }
    fn capture_diagnostics(&self) -> Option<audio::CaptureDiagnostics> {
        audio::AudioController::capture_diagnostics(self)
    }
}

/// The current live job identity (source, job, generation), its mode and its retained
/// result records.
pub(crate) type LiveRecords = ((String, String, u64), &'static str, Vec<Value>);
impl Recording {
    fn live_view(&self, s: &State) -> Value {
        let live = s.live.as_ref();
        let audio = live.map(|l| {
            let state = match l.audio.state {
                audio::AudioState::Closed => "closed",
                audio::AudioState::Opening => "opening",
                audio::AudioState::Running => "running",
                audio::AudioState::Closing => "closing",
                audio::AudioState::Unavailable => "unavailable",
            };
            json!({"state":state,"device_id":l.device_id,"device_name":self.radio_setup.name(&l.device_id),
                "error":l.audio.error.map(audio_error),"retry_after_ms":l.audio.retry_after_ms,
                "loss_epochs":l.loss_epochs,"last_loss":l.last_loss})
        }).unwrap_or_else(|| json!({"state":"closed","device_id":null,"device_name":null,"error":null,"retry_after_ms":null,"loss_epochs":0,"last_loss":null}));
        let source = live.and_then(|l| l.source.as_ref().map(|source|
            json!({"id":source.source_id,"kind":"live","sample_rate":12000,"channels":1,
                "next_frame":l.next_frame,"segment":l.timing.as_ref().map(|t|t.segment).unwrap_or(0)})));
        let job = live.and_then(|l| s.job.as_ref().map(|j|
            json!({"id":j.id,"mode":l.mode,"state":j.state,"error":j.error,
                "processed_frames":j.processed_frames,"first_sequence":l.first_sequence,
                "next_sequence":l.next_sequence,"available_count":l.records.len(),
                "last_overrun":l.last_overrun.map(|(first,end)|json!({"first_frame":first,"end_frame":end})),"latest_decode":s.latest_decode})));
        let timing = live.and_then(|l| l.timing.as_ref());
        json!({"v":1,"profile_id":self.profile,"boot_id":self.boot,"generation":s.generation,
            "audio":audio,"source":source,"job":job,"clock":{"basis":"system_utc",
            "correlated":timing.is_some_and(|t|t.correlated),"utc_anchor":timing.and_then(|t|t.system_utc_anchor.as_ref()),
            "canonical_anchor_frame":timing.map(|t|t.canonical_anchor_frame),
            "uncertainty_ns":timing.and_then(|t|t.uncertainty_ns),"external_accuracy":"unknown"}})
    }
    /// GET /receive/clock: the measured capture-clock offset from the epoch anchor's
    /// prediction and its rate, read on demand; kept out of the high-frequency /receive
    /// snapshot so the thin link keeps its budget. Null until measured.
    pub(crate) fn receive_clock(&self) -> Value {
        let s = self.state.lock().unwrap();
        let drift = s.live.as_ref().and_then(|l| l.capture_drift);
        json!({"v":1,"profile_id":self.profile,"boot_id":self.boot,
            "capture_drift_ms":drift.map(|(d,_)|(d as f64/10_000.0).round() as i64),
            "capture_drift_ppm":drift.and_then(|(_,ppm)|ppm).map(|p|(p*10.0).round()/10.0)})
    }
    /// CL-043-03 (2) capture_warning, only while live receive runs: uncorrelated while a
    /// capture epoch exists and its clock is not correlated to UTC (null before the first
    /// epoch, so a receive start or restart is no entry), else drift_high while the known
    /// |capture_drift_ppm| is above 1000, else null.
    pub(crate) fn capture_warning(&self) -> Option<&'static str> {
        let s = self.state.lock().unwrap();
        let running = s
            .job
            .as_ref()
            .is_some_and(|j| j.kind == "live" && !terminal(j.state));
        let l = s.live.as_ref().filter(|_| running)?;
        let timing = l.timing.as_ref()?;
        if !timing.correlated {
            return Some("uncorrelated");
        }
        l.capture_drift
            .and_then(|(_, ppm)| ppm)
            .filter(|ppm| ppm.abs() > CAPTURE_DRIFT_WARN_PPM)
            .map(|_| "drift_high")
    }
    pub fn receive_snapshot(&self) -> Value {
        self.live_view(&self.state.lock().unwrap())
    }
    pub(crate) fn receive_context(&self, profile: &str, boot: &str, generation: u64) -> Result<()> {
        if profile != self.profile {
            return Err("wrong_profile");
        }
        let s = self.state.lock().unwrap();
        if boot != self.boot || generation != s.generation {
            return Err("state_conflict");
        }
        Ok(())
    }
}

impl Recording {
    /// Startup wiring of HashResolution (CL-024-01): my call from the profile and the
    /// table shared with this station's transmit owner, once it is started.
    pub(crate) fn start_hashes(&self, callsign: &str) {
        self.set_my_call(Some(callsign));
        if let Some(transmit) = self.transmit.get() {
            transmit.attach_hashes(self.hashes.clone());
        }
    }
    /// My call for the hash table (the profile callsign; None without one).
    pub(crate) fn set_my_call(&self, call: Option<&str>) {
        self.hashes
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .set_my_call(call);
    }
}

struct LiveWorker {
    owner: Arc<Recording>,
    job: Job,
    input: Box<dyn LiveInput>,
    mode: Option<decoder::Mode>,
    window: Option<receive::WindowBuffer>,
    modem: Option<decoder::DecodeState>,
    reset: bool,
    epoch_seen: bool,
    spectrum: LiveSpectrum,
    clock: ClockTracker,
    /// The station clock correction (100 ns) included in the window schedule.
    air: i128,
}

/// Smoothed capture-clock offset (100 ns) from the epoch anchor's prediction. Packet times
/// carry scheduling jitter of milliseconds; a moving average over about a second removes it,
/// and a jump beyond STEP_TICKS (a system clock step) restarts the average at the new value.
#[derive(Default)]
struct ClockTracker {
    mean: Option<f64>,
    applied: i128,
    first: Option<(u64, f64)>,
}
/// The schedule follows the measured offset once it moved by more than 50 ms.
const RESCHEDULE_TICKS: f64 = 500_000.0;
const STEP_TICKS: f64 = 2_000_000.0;
/// capture_warning drift_high above this |capture drift| (ppm).
const CAPTURE_DRIFT_WARN_PPM: f64 = 1000.0;
impl ClockTracker {
    /// Feeds one (canonical frame, observed UTC) sample. Returns (offset, ppm) whenever the
    /// applied offset changes, so the caller re-anchors exactly then.
    fn observe(
        &mut self,
        timing: &source::SourceTiming,
        frame: u64,
        utc: u64,
    ) -> Option<(i128, Option<f64>)> {
        let offset = (i128::from(utc) - source_ticks(timing, frame)?) as f64;
        let mean = match self.mean {
            Some(mean) if (offset - mean).abs() <= STEP_TICKS => mean + (offset - mean) / 50.0,
            // First sample or a clock step: the rate is measured again from here.
            _ => {
                self.first = None;
                offset
            }
        };
        self.mean = Some(mean);
        let first = *self.first.get_or_insert((frame, mean));
        if (mean - self.applied as f64).abs() <= RESCHEDULE_TICKS {
            return None;
        }
        self.applied = mean.round() as i128;
        let seconds = frame.saturating_sub(first.0) as f64 / 12000.0;
        let ppm = (seconds >= 60.0).then(|| (mean - first.1) / (seconds * 10.0));
        Some((self.applied, ppm))
    }
}

/// 5 s of Detailed rows; a subscriber further behind than this sees a real gap
/// (WstxStationLink::DisplayRows).
pub mod display_rows {
    pub const DETAIL_RECENT_ROWS: usize = 25;
}
fn push_detail(s: &mut State, frame: Value) {
    if s.detail_recent.len() == display_rows::DETAIL_RECENT_ROWS {
        s.detail_recent.pop_front();
    }
    s.detail_recent.push_back(frame.clone());
    s.detail_frame = Some(frame);
}
struct SpectrumRow {
    first: u64,
    end: u64,
    levels: Vec<u8>,
    detailed: bool,
}
struct LiveSpectrum {
    samples: VecDeque<f32>,
    first: u64,
    next: u64,
    thin_start: u64,
    detail_start: u64,
    thin: spectrum::Spectrum,
    detail: spectrum::Spectrum,
    peak: [f32; 128],
    powers: [f32; 1024],
    count: u32,
}
fn io<T>(value: std::io::Result<T>) -> Result<T> {
    value.map_err(|_| "storage_unavailable")
}
fn write_json(files: &dyn profile::Files, path: &Path, value: &impl Serialize) -> Result<()> {
    let bytes = serde_json::to_vec(value).map_err(|_| "storage_unavailable")?;
    let mut f = io(files.create(path, profile::Open::Truncate))?;
    io(f.write(&bytes))?;
    io(f.flush())
}
pub(crate) fn bounded_json<T: serde::de::DeserializeOwned>(path: &Path, cap: u64) -> Result<T> {
    let mut bytes = Vec::new();
    io(File::open(path))?
        .take(cap + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| "storage_unavailable")?;
    if bytes.len() as u64 > cap {
        return Err("recording_unavailable");
    }
    serde_json::from_slice(&bytes).map_err(|_| "recording_unavailable")
}
impl Recording {
    pub fn open(
        base: &Path,
        profile: String,
        boot: String,
        files: Arc<dyn profile::Files>,
        time: Arc<dyn wstx_rust::transmit::clock::Clock>,
        spawner: Arc<dyn Spawner>,
        replays: Arc<dyn ReplaySources>,
    ) -> Arc<Self> {
        let dir = base.join("recordings");
        let startup = Mutex::new(startup::Startup::load(base, &profile, files.clone()));
        let diagnostics = Mutex::new(diagnostics::Diagnostics::load(
            base,
            &profile,
            files.clone(),
        ));
        let mut state = State {
            generation: 0,
            recording: None,
            committed_id: None,
            unknown_commit: false,
            source_error: None,
            storage_error: None,
            import: None,
            job: None,
            frame: None,
            detail_frame: None,
            detail_recent: VecDeque::new(),
            live: None,
            latest_decode: None,
            decode_counter: 0,
            decoding: false,
            decode_windows: 0,
            operating: selection::Operating::new(),
            live_worker: None,
            live_owner_released: true,
            operating_mode: "ft8",
        };
        let confined = fs::create_dir_all(&dir).is_ok()
            && base
                .canonicalize()
                .ok()
                .zip(dir.canonicalize().ok())
                .is_some_and(|(base, actual)| actual == base.join("recordings"));
        if !confined {
            state.storage_error = Some("storage_unavailable");
            return Arc::new(Self {
                state: Mutex::new(state),
                dir,
                profile,
                boot,
                cat: Mutex::new(crate::cat_lifecycle::Lifecycle::new()),
                transmit: std::sync::OnceLock::new(),
                tx: Default::default(),
                contact: std::sync::OnceLock::new(),
                flex: std::sync::OnceLock::new(),
                clients: Default::default(),
                waterfall: Default::default(),
                udp: std::sync::OnceLock::new(),
                pskr: std::sync::OnceLock::new(),
                clock: std::sync::OnceLock::new(),
                radio_setup: Default::default(),
                agc: Default::default(),
                tx_level: Default::default(),
                publication: tokio::sync::watch::Sender::new(0),
                hashes: Default::default(),
                startup,
                diagnostics,
                diagnostics_error: Arc::new(AtomicBool::new(false)),
                files,
                time,
                cat_opener: std::sync::OnceLock::new(),
                inputs: std::sync::OnceLock::new(),
                spawner,
                replays,
            });
        }
        if dir.join("current.json").exists() {
            let loaded = (|| {
                let m: Manifest = bounded_json(&dir.join("current.json"), 256)?;
                if m.schema_version != 1 || !profile::valid_uuid(&m.recording_id) {
                    return Err("recording_unavailable");
                }
                state.committed_id = Some(m.recording_id.clone());
                let meta: Metadata =
                    bounded_json(&dir.join(format!("{}.json", m.recording_id)), 1024)?;
                let wave = validate(&mut io(File::open(
                    dir.join(format!("{}.wav", m.recording_id)),
                ))?)?;
                if meta.schema_version != 1
                    || meta.recording_id != m.recording_id
                    || meta.rate_hz != RATE_HZ
                    || meta.frames != wave.frames
                    || meta.file_bytes != wave.bytes
                {
                    return Err("recording_unavailable");
                }
                Ok(meta)
            })();
            match loaded {
                Ok(meta) => state.recording = Some(meta),
                Err(_) => {
                    state.source_error = Some("recording_unavailable");
                    state.unknown_commit = state.committed_id.is_none();
                }
            }
        } else {
            match fs::read_dir(&dir) {
                Ok(entries) => {
                    for entry in entries {
                        let Ok(entry) = entry else {
                            state.storage_error = Some("storage_unavailable");
                            break;
                        };
                        let name = entry.file_name();
                        let name = name.to_string_lossy();
                        if name.rsplit_once('.').is_some_and(|(id, extension)| {
                            profile::valid_uuid(id) && matches!(extension, "wav" | "json")
                        }) {
                            state.unknown_commit = true;
                            state.source_error = Some("recording_unavailable");
                        }
                    }
                }
                Err(_) => state.storage_error = Some("storage_unavailable"),
            }
        }
        let this = Arc::new(Self {
            state: Mutex::new(state),
            dir,
            profile,
            boot,
            cat: Mutex::new(crate::cat_lifecycle::Lifecycle::new()),
            transmit: std::sync::OnceLock::new(),
            tx: Default::default(),
            contact: std::sync::OnceLock::new(),
            flex: std::sync::OnceLock::new(),
            clients: Default::default(),
            waterfall: Default::default(),
            udp: std::sync::OnceLock::new(),
            pskr: std::sync::OnceLock::new(),
            clock: std::sync::OnceLock::new(),
            radio_setup: Default::default(),
            agc: Default::default(),
            tx_level: Default::default(),
            publication: tokio::sync::watch::Sender::new(0),
            hashes: Default::default(),
            startup,
            diagnostics,
            diagnostics_error: Arc::new(AtomicBool::new(false)),
            files,
            time,
            cat_opener: std::sync::OnceLock::new(),
            inputs: std::sync::OnceLock::new(),
            spawner,
            replays,
        });
        if this.cleanup(None).is_err() {
            this.state.lock().unwrap().storage_error = Some("storage_unavailable");
        }
        this
    }
    fn path(&self, id: &str, extension: &str) -> PathBuf {
        self.dir.join(format!("{id}.{extension}"))
    }
    pub fn snapshot(&self) -> Value {
        let s = self.state.lock().unwrap();
        let recording = s.recording.as_ref().map(|m| json!({"id":m.recording_id,"rate_hz":RATE_HZ,"frames":m.frames,"file_bytes":m.file_bytes,"utc_anchor":null}));
        let import = s.import.as_ref().filter(|i| !terminal(i.state)).map(|i| {
            let mut v = serde_json::to_value(i).unwrap();
            v.as_object_mut().unwrap().remove("recording_id");
            v
        });
        json!({"v":1,"profile_id":self.profile,"boot_id":self.boot,"generation":s.generation,"recording":recording,"source_error":s.source_error,"storage_error":s.storage_error,"import":import,"job":s.job})
    }
    /// WstxProfileAccess::ProfileSnapshot profile.state: the saved revision this station runs.
    pub(crate) fn profile_state_event(&self) -> (u64, String) {
        let revision = self.state.lock().unwrap().operating.profile_revision;
        (
            revision,
            json!({"v":1,"type":"profile.state","data":{"profile_id":self.profile,"boot_id":self.boot,"revision":revision}})
                .to_string(),
        )
    }
    /// The pushed recording.state data (WstxRecordingTransfer::RecordingStatus).
    pub fn state_event_data(&self) -> Value {
        let s = self.snapshot();
        let source = if s["job"]["kind"] == "live" {
            &s["job"]["source_id"]
        } else {
            &s["recording"]["id"]
        };
        let import = if s["import"].is_null() {
            Value::Null
        } else {
            json!({"id":s["import"]["id"],"state":s["import"]["state"],"received_bytes":s["import"]["received_bytes"],"total_bytes":s["import"]["total_bytes"],"error":s["import"]["error"]})
        };
        json!({"generation":s["generation"],"source_id":source,"job_id":s["job"]["id"],"state":s["job"]["state"],"import":import})
    }
    fn admit(s: &mut State) -> Result<u64> {
        Self::admit_for(s, None)
    }
    fn admit_for(s: &mut State, token: Option<u64>) -> Result<u64> {
        if !s.live_owner_released || (s.operating.active() && token != Some(s.operating.revision)) {
            return Err("busy");
        }
        if token.is_some_and(|t| t != s.operating.revision || !s.operating.active()) {
            return Err("state_conflict");
        }
        if s.storage_error.is_some() {
            return Err("storage_unavailable");
        }
        if s.import
            .as_ref()
            .is_some_and(|i| !terminal(i.state) || i.worker)
            || s.job.as_ref().is_some_and(|j| !terminal(j.state))
        {
            return Err("busy");
        }
        if s.generation == profile::MAX_REVISION {
            return Err("generation_exhausted");
        }
        s.generation += 1;
        s.frame = None;
        s.detail_frame = None;
        s.detail_recent.clear();
        s.live = None;
        Ok(s.generation)
    }
}
pub fn terminal(state: &str) -> bool {
    matches!(state, "completed" | "cancelled" | "failed")
}
