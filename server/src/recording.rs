pub use crate::source::{SampleBlock, SourceDescriptor};
use crate::{audio, decoder, receive, source};
use crate::{profile, selection, spectrum};
use base64::{Engine, engine::general_purpose::STANDARD};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use source::{SampleSource, SourcePoll};
use std::collections::VecDeque;
use std::{
    fs::{self, File},
    io::{Read, Seek, SeekFrom, Write},
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};
#[cfg(test)]
#[path = "recording_tests.rs"]
mod tests;

fn checkpoint(stage: &'static str) -> Result<()> {
    #[cfg(test)]
    tests::checkpoint(stage)?;
    #[cfg(not(test))]
    let _ = stage;
    Ok(())
}

pub const FILE_LIMIT: u64 = 3_145_728;
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
fn read<const N: usize>(file: &mut File) -> Result<[u8; N]> {
    let mut bytes = [0; N];
    file.read_exact(&mut bytes).map_err(|error| {
        if error.kind() == std::io::ErrorKind::UnexpectedEof {
            "invalid_recording"
        } else {
            "storage_unavailable"
        }
    })?;
    Ok(bytes)
}
pub fn validate(file: &mut File) -> Result<Wave> {
    let bytes = file.metadata().map_err(|_| "storage_unavailable")?.len();
    if bytes > FILE_LIMIT {
        return Err("recording_limit");
    }
    file.rewind().map_err(|_| "storage_unavailable")?;
    let header = read::<12>(file)?;
    if &header[..4] != b"RIFF" || &header[8..] != b"WAVE" {
        return Err("invalid_recording");
    }
    if u64::from(u32::from_le_bytes(
        header[4..8].try_into().map_err(|_| "invalid_recording")?,
    )) + 8
        != bytes
    {
        return Err("invalid_recording");
    }
    let mut position = 12u64;
    let mut format = false;
    let mut data = None;
    let mut chunks = 0;
    let mut unsupported = false;
    while position < bytes {
        if bytes - position < 8 {
            return Err("invalid_recording");
        }
        let chunk = read::<8>(file)?;
        chunks += 1;
        if chunks > 64 {
            return Err("recording_limit");
        }
        let size = u64::from(u32::from_le_bytes(
            chunk[4..].try_into().map_err(|_| "invalid_recording")?,
        ));
        position += 8;
        let end = position
            .checked_add(size)
            .and_then(|v| v.checked_add(size % 2))
            .filter(|v| *v <= bytes)
            .ok_or("invalid_recording")?;
        match &chunk[..4] {
            b"fmt " => {
                if format || data.is_some() {
                    return Err("invalid_recording");
                }
                format = true;
                if size != 16 && size != 18 {
                    return Err("unsupported_audio");
                }
                let f = read::<16>(file)?;
                let word = |n| u16::from_le_bytes([f[n], f[n + 1]]);
                let dword = |n| u32::from_le_bytes([f[n], f[n + 1], f[n + 2], f[n + 3]]);
                unsupported = word(0) != 1 || word(2) != 1 || dword(4) != 12000 || word(14) != 16;
                if !unsupported && (word(12) != 2 || dword(8) != 24000) {
                    return Err("invalid_recording");
                }
                if size == 18 && read::<2>(file)? != [0, 0] {
                    return Err("invalid_recording");
                }
            }
            b"data" => {
                if !format || data.is_some() || size == 0 || size % 2 != 0 {
                    return Err("invalid_recording");
                }
                data = Some((position, size / 2));
            }
            _ => {}
        }
        file.seek(SeekFrom::Start(end))
            .map_err(|_| "storage_unavailable")?;
        position = end;
    }
    let (offset, frames) = data.ok_or("invalid_recording")?;
    if unsupported {
        return Err("unsupported_audio");
    }
    if frames > 1_440_000 {
        return Err("recording_limit");
    }
    Ok(Wave {
        offset,
        frames,
        bytes,
    })
}
pub struct SourceFile {
    file: File,
    source: Arc<SourceDescriptor>,
    position: u64,
    frames: u64,
}
impl SourceFile {
    pub fn open(path: &Path, source: Arc<SourceDescriptor>) -> Result<Self> {
        let mut file = File::open(path).map_err(|_| "recording_unavailable")?;
        let wave = validate(&mut file).map_err(|_| "recording_unavailable")?;
        if source.schema_version != 1
            || source.rate_hz != 12000
            || source.channel != "mono_real"
            || source.total_frames != Some(wave.frames)
            || source.utc_anchor.is_some()
        {
            return Err("recording_unavailable");
        }
        file.seek(SeekFrom::Start(wave.offset))
            .map_err(|_| "recording_unavailable")?;
        Ok(Self {
            file,
            source,
            position: 0,
            frames: wave.frames,
        })
    }
    pub fn next(&mut self) -> Result<Option<SampleBlock>> {
        if self.position == self.frames {
            return Ok(None);
        }
        let count = usize::try_from((self.frames - self.position).min(4096))
            .map_err(|_| "recording_unavailable")?;
        let mut raw = vec![0; count * 2];
        self.file
            .read_exact(&mut raw)
            .map_err(|_| "recording_unavailable")?;
        let samples: Arc<[f32]> = raw
            .as_chunks::<2>()
            .0
            .iter()
            .map(|b| f32::from(i16::from_le_bytes([b[0], b[1]])) / 32768.0)
            .collect();
        let first_frame = self.position;
        self.position += count as u64;
        Ok(Some(SampleBlock {
            source: self.source.clone(),
            first_frame,
            samples,
            discontinuity: false,
            end_of_stream: self.position == self.frames,
            timing: None,
        }))
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
    live: Option<LiveState>,
    latest_decode: Option<LatestDecode>,
    decode_counter: u64,
    operating: selection::Operating,
    live_worker: Option<std::thread::JoinHandle<()>>,
    live_owner_released: bool,
}
pub struct Recording {
    pub state: Mutex<State>,
    dir: PathBuf,
    pub profile: String,
    pub boot: String,
    /// The one CL-022-03/04 automatic CAT policy of this station.
    cat: Mutex<crate::cat_lifecycle::Lifecycle>,
    #[cfg(test)]
    cat_transport: Mutex<Option<CatTransport>>,
    #[cfg(test)]
    resources: Mutex<Resources>,
}
/// Fixture seam replacing only the physical serial open, never the actor/executor.
#[cfg(test)]
pub(crate) type CatTransport = Arc<
    dyn Fn(
            &wstx_rust::radio_control::Configuration,
            Instant,
            &AtomicBool,
        ) -> wstx_rust::radio_control::Result<
            Box<dyn wstx_rust::radio_control::executor::Transport>,
        > + Send
        + Sync,
>;

#[derive(Clone, Serialize)]
struct LatestDecode {
    id: u64,
    first_sequence: u64,
    next_sequence: u64,
    period_start_utc: Option<String>,
    complete: bool,
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
    publication_error: Option<&'static str>,
}
impl LiveState {
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
        self.publication_error = None;
    }
}

/// Native resource ownership stays with the existing receive worker. Tests supply the
/// actual queue/converter here; there is no production fixture endpoint.
pub(crate) trait LiveInput: SampleSource + Send {
    fn start(&mut self) -> std::result::Result<(), source::SourceError>;
    fn request_stop(&mut self);
    fn status(&self) -> audio::AudioStatus;
}
#[derive(Clone, Copy)]
enum StartGuard {
    Profile(u64),
    Selection(u64),
    #[cfg(test)]
    Fixture,
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
}

fn audio_error(error: source::SourceError) -> &'static str {
    match error {
        source::SourceError::Unavailable => "audio_unavailable",
        source::SourceError::UnsupportedFormat => "unsupported_audio",
        source::SourceError::FailedClose => "audio_close_failed",
        source::SourceError::CounterExhausted => "counter_exhausted",
        source::SourceError::Cancelled => "cancelled",
        _ => "audio_failed",
    }
}
fn window_error(error: receive::WindowError) -> &'static str {
    match error {
        receive::WindowError::CounterExhausted => "counter_exhausted",
        receive::WindowError::DecodeLimit => "decode_limit",
        _ => "audio_failed",
    }
}

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
            json!({"state":state,"device_id":l.device_id,"device_name":null,
                "error":l.audio.error.map(audio_error),"retry_after_ms":l.audio.retry_after_ms})
        }).unwrap_or_else(|| json!({"state":"closed","device_id":null,"device_name":null,"error":null,"retry_after_ms":null}));
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
    #[allow(
        clippy::too_many_arguments,
        reason = "Exact profile, boot, receive generation and saved revision are separate wire authorities"
    )]
    pub fn receive_start(
        self: &Arc<Self>,
        profile: &str,
        boot: &str,
        generation: u64,
        revision: u64,
        device: String,
        mode: &'static str,
    ) -> Result<Value> {
        self.receive_start_selected(
            profile,
            boot,
            generation,
            device,
            mode,
            StartGuard::Profile(revision),
        )
    }
    fn receive_start_selected(
        self: &Arc<Self>,
        profile: &str,
        boot: &str,
        generation: u64,
        device: String,
        mode: &'static str,
        guard: StartGuard,
    ) -> Result<Value> {
        self.reap_receive();
        #[cfg(test)]
        {
            let input = {
                let mut resources = self.resources.lock().unwrap();
                resources
                    .live_input
                    .take()
                    .or_else(|| resources.live_inputs.pop_front())
            };
            if let Some(input) = input {
                return self
                    .receive_start_checked(profile, boot, generation, device, mode, input, guard);
            }
        }
        #[cfg(windows)]
        let input = audio::AudioController::new(device.clone()).map_err(audio_error)?;
        #[cfg(not(windows))]
        {
            let _ = (profile, boot, generation, device, mode);
            return Err("audio_unavailable");
        }
        #[cfg(windows)]
        self.receive_start_checked(
            profile,
            boot,
            generation,
            device,
            mode,
            Box::new(input),
            guard,
        )
    }
    #[cfg(all(test, not(debug_assertions)))]
    pub(crate) fn fixture_input(&self, input: Box<dyn LiveInput>) {
        self.resources.lock().unwrap().live_input = Some(input);
    }
    #[cfg(all(test, not(debug_assertions)))]
    pub(crate) fn fixture_inputs(&self, inputs: Vec<Box<dyn LiveInput>>) {
        self.resources.lock().unwrap().live_inputs = inputs.into();
    }
    #[cfg(all(test, not(debug_assertions)))]
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
    #[cfg(test)]
    pub(crate) fn receive_start_input(
        self: &Arc<Self>,
        profile: &str,
        boot: &str,
        generation: u64,
        device: String,
        mode: &'static str,
        input: Box<dyn LiveInput>,
    ) -> Result<Value> {
        self.receive_start_checked(
            profile,
            boot,
            generation,
            device,
            mode,
            input,
            StartGuard::Fixture,
        )
    }
    #[allow(
        clippy::too_many_arguments,
        reason = "Existing strict receive context plus optional internal transition token"
    )]
    fn receive_start_checked(
        self: &Arc<Self>,
        profile: &str,
        boot: &str,
        generation: u64,
        device: String,
        mode: &'static str,
        mut input: Box<dyn LiveInput>,
        guard: StartGuard,
    ) -> Result<Value> {
        self.reap_receive();
        let job;
        {
            let mut s = self.state.lock().unwrap();
            if profile != self.profile {
                return Err("wrong_profile");
            }
            if boot != self.boot || generation != s.generation {
                return Err("state_conflict");
            }
            if let StartGuard::Profile(revision) = guard
                && revision != s.operating.profile_revision
            {
                return Err("state_conflict");
            }
            let token = match guard {
                StartGuard::Selection(token) => Some(token),
                _ => None,
            };
            let id = profile::new_uuid().map_err(|_| "storage_unavailable")?;
            let generation = Self::admit_for(&mut s, token)?;
            s.live_owner_released = false;
            job = Job {
                id,
                source_id: None,
                generation,
                kind: "live",
                state: "running",
                processed_frames: 0,
                error: None,
                cancel: Arc::new(AtomicBool::new(false)),
            };
            s.job = Some(job.clone());
            if let Some(token) = token
                && let Some(operation) = s
                    .operating
                    .operation
                    .as_mut()
                    .filter(|o| o.revision == token)
            {
                operation.new_job_id = Some(job.id.clone());
                operation.new_generation = Some(job.generation);
                operation.new_worker_cancel = Some(job.cancel.clone());
            }
            if s.operating.nominal.band.is_none() && matches!(mode, "ft4" | "ft8") {
                s.operating.nominal.mode = mode;
            }
            s.latest_decode = None;
            s.decode_counter = 0;
            s.live = Some(LiveState {
                mode,
                audio: audio::AudioStatus {
                    state: audio::AudioState::Opening,
                    error: None,
                    retry_after_ms: None,
                },
                device_id: device,
                source: None,
                timing: None,
                next_frame: 0,
                records: VecDeque::new(),
                record_bytes: 0,
                first_sequence: 0,
                next_sequence: 0,
                search_limited: false,
                last_overrun: None,
                publication_error: None,
            });
        }
        let this = self.clone();
        let worker_job = job.clone();
        if self
            .spawn_receive(move || {
                let started = input.start().map_err(audio_error);
                LiveWorker::new(this, worker_job, input, mode).run(started);
            })
            .is_err()
        {
            let mut s = self.state.lock().unwrap();
            if let Some(j) = s
                .job
                .as_mut()
                .filter(|j| j.id == job.id && j.generation == job.generation)
            {
                j.state = "failed";
                j.error = Some("audio_unavailable");
            }
            if let Some(l) = s.live.as_mut() {
                l.audio = audio::AudioStatus {
                    state: audio::AudioState::Closed,
                    error: Some(source::SourceError::Unavailable),
                    retry_after_ms: None,
                };
            }
            s.live_owner_released = true;
            return Err("audio_unavailable");
        }
        Ok(self.receive_snapshot())
    }
    fn spawn_receive(&self, run: impl FnOnce() + Send + 'static) -> std::io::Result<()> {
        #[cfg(test)]
        if std::mem::take(&mut self.resources.lock().unwrap().fail_live_spawn) {
            return Err(std::io::Error::other("injected receive spawn failure"));
        }
        let worker = std::thread::Builder::new()
            .name("station-receive".into())
            .spawn(run)?;
        self.state.lock().unwrap().live_worker = Some(worker);
        Ok(())
    }
    fn reap_receive(&self) {
        let worker = {
            let mut s = self.state.lock().unwrap();
            if s.live_worker.as_ref().is_some_and(|worker| {
                worker.is_finished()
                    || s.job
                        .as_ref()
                        .is_some_and(|job| job.kind == "live" && terminal(job.state))
            }) {
                s.live_worker.take()
            } else {
                None
            }
        };
        if let Some(worker) = worker {
            // Native input and all modem/window storage left scope before thread exit.
            // Join outside the station mutex; until then admission remains blocked.
            let _ = worker.join();
            self.state.lock().unwrap().live_owner_released = true;
        }
    }
    fn live_source_uuid(&self) -> Result<String> {
        #[cfg(test)]
        if std::mem::take(&mut self.resources.lock().unwrap().fail_source_uuid) {
            return Err("storage_unavailable");
        }
        profile::new_uuid().map_err(|_| "storage_unavailable")
    }
    pub fn receive_stop(
        &self,
        profile: &str,
        boot: &str,
        generation: u64,
        id: &str,
    ) -> Result<Value> {
        {
            let mut s = self.state.lock().unwrap();
            if profile != self.profile {
                return Err("wrong_profile");
            }
            if boot != self.boot || generation != s.generation {
                return Err("state_conflict");
            }
            if s.live.is_none() {
                return Err("not_found");
            }
            let j = s.job.as_mut().filter(|j| j.id == id).ok_or("not_found")?;
            if !terminal(j.state) {
                j.cancel.store(true, Ordering::Release);
                j.state = "cancelling";
            }
            let stopped_cancel = j.cancel.clone();
            s.frame = None;
            s.detail_frame = None;
            if let Some(operation) = s.operating.operation.as_mut()
                && (operation.old_job_id.as_deref() == Some(id)
                    || operation.new_job_id.as_deref() == Some(id)
                    || operation
                        .new_worker_cancel
                        .as_ref()
                        .is_some_and(|cancel| Arc::ptr_eq(cancel, &stopped_cancel)))
            {
                operation.cancelled.store(true, Ordering::Release);
                operation.monitor_wanted = false;
                operation.phase = "cancelled";
                operation.result = "cancelled";
            }
        }
        Ok(self.receive_snapshot())
    }
    pub fn receive_results(
        &self,
        source: &str,
        job: &str,
        generation: u64,
        cursor: u64,
        limit: usize,
    ) -> Result<Value> {
        let s = self.state.lock().unwrap();
        let j = s
            .job
            .as_ref()
            .filter(|j| {
                j.id == job && j.generation == generation && j.source_id.as_deref() == Some(source)
            })
            .ok_or("not_found")?;
        let l = s.live.as_ref().ok_or("not_found")?;
        if l.source.as_ref().is_none_or(|s| s.source_id != source) {
            return Err("not_found");
        }
        if l.mode == "spectrum" {
            return Err("invalid_request");
        }
        if cursor < l.first_sequence {
            return Ok(
                json!({"v":1,"error":{"code":"cursor_expired","message":"Result history expired"},"first_sequence":l.first_sequence,"next_sequence":l.next_sequence}),
            );
        }
        if cursor > l.next_sequence {
            return Err("invalid_request");
        }
        let mut records = Vec::new();
        let mut next = cursor;
        for (record, _) in l
            .records
            .iter()
            .skip((cursor - l.first_sequence) as usize)
            .take(limit)
        {
            records.push(record.clone());
            next += 1;
        }
        let page = |records: &Vec<Value>, next| {
            json!({"v":1,"profile_id":self.profile,"boot_id":self.boot,
            "source_id":source,"job_id":job,"generation":generation,"mode":l.mode,"state":j.state,
            "error":j.error,"search_limited":l.search_limited,"first_sequence":l.first_sequence,
            "next_sequence":l.next_sequence,"available_count":l.records.len(),"next":next,
            "more":next<l.next_sequence,"records":records,"latest_decode":s.latest_decode})
        };
        while serde_json::to_vec(&page(&records, next))
            .map_err(|_| "decode_limit")?
            .len()
            > 16384
        {
            records.pop();
            next -= 1;
        }
        Ok(page(&records, next))
    }
    fn publish_latest_decode(
        &self,
        context: &Job,
        interval: (u64, u64),
        first: u64,
        complete: bool,
    ) -> Result<()> {
        let mut s = self.state.lock().unwrap();
        if context.cancel.load(Ordering::Acquire)
            || !s.job.as_ref().is_some_and(|j| {
                j.id == context.id
                    && j.generation == context.generation
                    && j.source_id == context.source_id
                    && j.state == "running"
            })
        {
            return Ok(());
        }
        let l = s.live.as_ref().ok_or("state_conflict")?;
        let period = if let Some(timing) = l.timing.as_ref().filter(|t| t.correlated) {
            let Some((period, nominal, support)) = period_parameters(l.mode) else {
                return Ok(());
            };
            let (Some(begin), Some(end)) = (
                source_ticks(timing, interval.0),
                source_ticks(timing, interval.1),
            ) else {
                return Ok(());
            };
            let slot = (end - nominal - support).div_euclid(period) * period;
            if slot + nominal < begin {
                return Ok(());
            }
            Some(
                utc_from_filetime(u64::try_from(slot).map_err(|_| "decode_limit")?)
                    .ok_or("decode_limit")?,
            )
        } else {
            None
        };
        if let (Some(previous), Some(next)) = (
            s.latest_decode
                .as_ref()
                .and_then(|v| v.period_start_utc.as_ref()),
            period.as_ref(),
        ) && next < previous
        {
            return Ok(());
        }
        let (first_sequence, next_sequence) = if let Some(period) = period.as_ref() {
            let mut matching = l
                .records
                .iter()
                .filter(|(r, _)| r["period_start_utc"].as_str() == Some(period));
            if let Some((record, _)) = matching.next() {
                let first = record["sequence"].as_u64().ok_or("decode_limit")?;
                let last = matching
                    .next_back()
                    .map(|(r, _)| r["sequence"].as_u64().unwrap())
                    .unwrap_or(first);
                (first, last + 1)
            } else {
                (l.next_sequence, l.next_sequence)
            }
        } else {
            (first.max(l.first_sequence), l.next_sequence)
        };
        let id = s
            .decode_counter
            .checked_add(1)
            .filter(|id| *id <= source::MAX_COUNTER)
            .ok_or("counter_exhausted")?;
        s.decode_counter = id;
        s.latest_decode = Some(LatestDecode {
            id,
            first_sequence,
            next_sequence,
            period_start_utc: period,
            complete,
        });
        Ok(())
    }
    fn publish_decode(
        &self,
        context: &Job,
        decode: &decoder::Decode,
    ) -> std::result::Result<(), decoder::DecodeError> {
        let mut s = self.state.lock().unwrap();
        if context.cancel.load(Ordering::Acquire)
            || !s.job.as_ref().is_some_and(|j| {
                j.id == context.id
                    && j.generation == context.generation
                    && j.source_id == context.source_id
                    && j.state == "running"
            })
        {
            return Err(decoder::DecodeError::Cancelled);
        }
        let l = s.live.as_mut().ok_or(decoder::DecodeError::Cancelled)?;
        if l.source.as_ref().map(|s| &s.source_id) != context.source_id.as_ref() {
            return Err(decoder::DecodeError::Cancelled);
        }
        if l.publication_error.is_some() {
            return Err(decoder::DecodeError::DecodeLimit);
        }
        if l.next_sequence == source::MAX_COUNTER {
            l.publication_error = Some("counter_exhausted");
            return Err(decoder::DecodeError::DecodeLimit);
        }
        if decode.start_frame >= l.next_frame
            || !decode.frequency_hz.is_finite()
            || !(200.0..=3500.0).contains(&decode.frequency_hz)
            || decode
                .snr_db
                .is_some_and(|v| !v.is_finite() || !(-60.0..=60.0).contains(&v))
        {
            l.publication_error = Some("decode_limit");
            return Err(decoder::DecodeError::DecodeLimit);
        }
        let mut value =
            serde_json::to_value(decode).map_err(|_| decoder::DecodeError::DecodeLimit)?;
        let timing = relative_decode_timing(l.timing.as_ref(), l.mode, decode.start_frame);
        value["period_start_utc"] = json!(timing.as_ref().map(|(period, _)| period));
        value["dt_seconds"] = json!(timing.map(|(_, dt)| dt));
        value
            .as_object_mut()
            .ok_or(decoder::DecodeError::DecodeLimit)?
            .insert("sequence".into(), json!(l.next_sequence));
        let size = serde_json::to_vec(&value)
            .map_err(|_| decoder::DecodeError::DecodeLimit)?
            .len();
        if size > 2048 {
            return Err(decoder::DecodeError::DecodeLimit);
        }
        while l.records.len() >= 2048 || l.record_bytes + size > 2 * 1024 * 1024 {
            let (_, bytes) = l
                .records
                .pop_front()
                .ok_or(decoder::DecodeError::DecodeLimit)?;
            l.record_bytes -= bytes;
            l.first_sequence += 1;
        }
        l.records.push_back((value, size));
        l.record_bytes += size;
        l.next_sequence += 1;
        Ok(())
    }
}

impl Recording {
    pub(crate) fn initialize_profile_revision(&self, revision: u64) {
        self.state.lock().unwrap().operating.profile_revision = revision;
    }
    pub(crate) fn profile_changed(&self, revision: u64) {
        let mut s = self.state.lock().unwrap();
        if s.operating.profile_revision == revision {
            return;
        }
        s.operating.profile_revision = revision;
        if s.operating.revision < profile::MAX_REVISION {
            s.operating.revision += 1;
        }
        if let Some(operation) = s.operating.operation.as_mut() {
            operation.cancelled.store(true, Ordering::Release);
            operation.monitor_wanted = false;
            if operation.result == "pending" {
                operation.phase = "failed";
                operation.result = "failed";
                operation.error = Some("state_conflict");
            }
        }
    }
    pub(crate) fn radio_actor(&self) -> Option<Arc<wstx_rust::radio_control::actor::Actor>> {
        self.state.lock().unwrap().operating.radio.actor.clone()
    }
    fn radio_reserve(
        &self,
        revision: u64,
    ) -> Result<(u64, Option<Arc<wstx_rust::radio_control::actor::Actor>>)> {
        self.refresh_radio_cache();
        let (generation, old) = {
            let mut s = self.state.lock().unwrap();
            if s.operating.profile_revision != revision {
                return Err("state_conflict");
            }
            if s.operating.active() || s.operating.radio.connecting {
                return Err("busy");
            }
            if s.operating.radio.actor.is_some()
                && s.operating
                    .radio
                    .cached
                    .as_ref()
                    .is_none_or(|a| a.state != wstx_rust::radio_control::State::Closed)
            {
                return Err("busy");
            }
            if s.operating.radio.generation == profile::MAX_REVISION {
                return Err("counter_exhausted");
            }
            let radio = &mut s.operating.radio;
            let old = radio.actor.take();
            radio.generation += 1;
            radio.connecting = true;
            radio.cached = None;
            radio.error = None;
            (radio.generation, old)
        };
        Ok((generation, old))
    }
    pub(crate) fn radio_connect(
        self: &Arc<Self>,
        configuration: wstx_rust::radio_control::Configuration,
        revision: u64,
    ) -> Result<Value> {
        use wstx_rust::radio_control::Authority;
        let (generation, old) = self.radio_reserve(revision)?;
        // Final Arc destruction invokes Actor::Drop and therefore belongs outside state locks.
        drop(old);
        let authority = Authority {
            profile_id: self.profile.clone(),
            boot_id: self.boot.clone(),
            profile_revision: revision,
            resource_id: format!("COM{}", configuration.port),
            connection_generation: generation,
        };
        let started = self.radio_begin(configuration, authority);
        let actor = match started {
            Ok(actor) => Arc::new(actor),
            Err(e) => {
                let mut s = self.state.lock().unwrap();
                if s.operating.radio.generation == generation {
                    s.operating.radio.connecting = false;
                    s.operating.radio.error = Some(selection::radio_error(e));
                }
                return Err(selection::radio_error(e));
            }
        };
        self.radio_install(generation, revision, actor)
    }
    fn radio_begin(
        &self,
        configuration: wstx_rust::radio_control::Configuration,
        authority: wstx_rust::radio_control::Authority,
    ) -> std::result::Result<wstx_rust::radio_control::actor::Actor, wstx_rust::radio_control::Error>
    {
        use wstx_rust::radio_control::{actor::Actor, catalogue::Catalogue};
        #[cfg(test)]
        if let Some(open) = self.cat_transport.lock().unwrap().clone() {
            let native = configuration.clone();
            return Catalogue::builtin().and_then(|catalogue| {
                Actor::begin(
                    configuration,
                    authority,
                    catalogue,
                    move |deadline, cancel| open(&native, deadline, cancel),
                )
            });
        }
        #[cfg(windows)]
        {
            let lock_root = std::env::var_os("LOCALAPPDATA")
                .map(PathBuf::from)
                .unwrap_or_else(std::env::temp_dir)
                .join("WstxRust")
                .join("radio-ownership");
            let native = configuration.clone();
            Catalogue::builtin().and_then(|catalogue| {
                Actor::begin(
                    configuration,
                    authority,
                    catalogue,
                    move |deadline, cancel| {
                        wstx_rust::radio_control::windows::SerialTransport::open(
                            &native, &lock_root, deadline, cancel,
                        )
                    },
                )
            })
        }
        #[cfg(not(windows))]
        {
            let _ = (configuration, authority);
            Err(wstx_rust::radio_control::Error::Unavailable)
        }
    }
    #[cfg(test)]
    pub(crate) fn fixture_cat_transport(&self, open: CatTransport) {
        *self.cat_transport.lock().unwrap() = Some(open);
    }
    /// One tick of the automatic read-only lifecycle. The caller holds the profile
    /// store and authority locks (lock order store -> authorization -> recording), so a
    /// committed revocation or configuration edit is observed before any new attempt.
    pub(crate) fn cat_maintain(self: &Arc<Self>, gate: &crate::cat_lifecycle::Gate, now: Instant) {
        use crate::cat_lifecycle::{Action, Gate, Observed};
        use wstx_rust::radio_control::{Error, State as Cat};
        let (actor, generation) = {
            let s = self.state.lock().unwrap();
            (
                s.operating.radio.actor.clone(),
                s.operating.radio.generation,
            )
        };
        let observed = match actor.as_ref().map(|a| a.snapshot()) {
            None => Observed::Absent,
            Some(Err(_)) => Observed::Closing,
            Some(Ok(v)) => match (v.state, v.last_error) {
                (_, Some(Error::FailedClose)) => Observed::FailedClose,
                (Cat::Connecting, _) => Observed::Connecting,
                (Cat::Ready, _) => Observed::Ready,
                (Cat::Unavailable, e) => Observed::FailedReleased(e.unwrap_or(Error::Unavailable)),
                (Cat::Closing, _) => Observed::Closing,
                (Cat::Closed, _) => Observed::Closed,
            },
        };
        let action = self.cat.lock().unwrap().step(gate, observed, now);
        match action {
            Action::None => {}
            Action::Close => {
                let _ = self.radio_disconnect(generation);
            }
            Action::Attempt => {
                let Gate::Eligible { key, configuration } = gate else {
                    return;
                };
                // The released previous actor is removed only if it is still current;
                // its final drop happens outside the state lock.
                let old = {
                    let mut s = self.state.lock().unwrap();
                    let radio = &mut s.operating.radio;
                    match (&radio.actor, &actor) {
                        (Some(a), Some(b)) if Arc::ptr_eq(a, b) => radio.actor.take(),
                        _ => None,
                    }
                };
                drop(old);
                drop(actor);
                if let Err("busy" | "state_conflict") =
                    self.radio_connect(configuration.clone(), key.profile_revision)
                {
                    self.cat.lock().unwrap().deferred(now);
                }
            }
        }
        self.refresh_radio_cache();
    }
    /// Current automatic CAT condition for the additive authorization status.
    pub(crate) fn cat_status(&self) -> (&'static str, Option<&'static str>, Option<u64>) {
        self.cat.lock().unwrap().status()
    }
    fn radio_install(
        &self,
        generation: u64,
        revision: u64,
        actor: Arc<wstx_rust::radio_control::actor::Actor>,
    ) -> Result<Value> {
        let installed = {
            let mut s = self.state.lock().unwrap();
            if s.operating.radio.generation == generation
                && s.operating.radio.connecting
                && s.operating.profile_revision == revision
            {
                s.operating.radio.actor = Some(actor.clone());
                s.operating.radio.connecting = false;
                true
            } else {
                // A profile edit ends only this still-owned reservation. A later
                // generation or explicit Disconnect must remain authoritative.
                if s.operating.radio.generation == generation && s.operating.radio.connecting {
                    s.operating.radio.connecting = false;
                    s.operating.radio.error = Some("state_conflict");
                }
                false
            }
        };
        if !installed {
            actor.request_close();
            return Err("state_conflict");
        }
        Ok(self.radio_view())
    }
    pub(crate) fn radio_disconnect(&self, generation: u64) -> Result<Value> {
        let actor = {
            let mut s = self.state.lock().unwrap();
            if generation != s.operating.radio.generation {
                return Err("state_conflict");
            }
            s.operating.radio.connecting = false;
            if s.operating.radio.actor.is_none() {
                s.operating.radio.error = None;
            }
            if let Some(o) = s
                .operating
                .operation
                .as_mut()
                .filter(|o| o.result == "pending")
            {
                o.cancelled.store(true, Ordering::Release);
                o.monitor_wanted = false;
                o.result = "failed";
                o.phase = "failed";
                o.error = Some("radio_unavailable");
            }
            s.operating.radio.actor.clone()
        };
        if let Some(actor) = actor {
            actor.request_close();
        }
        Ok(self.radio_view())
    }
    pub(crate) fn radio_execute(
        &self,
        generation: u64,
        operation: wstx_rust::radio_control::Operation,
    ) -> Result<Value> {
        let (actor, revision, at) = {
            let s = self.state.lock().unwrap();
            if s.operating.active() {
                return Err("busy");
            }
            if generation != s.operating.radio.generation {
                return Err("state_conflict");
            }
            (
                s.operating.radio.actor.clone().ok_or("radio_unavailable")?,
                s.operating.profile_revision,
                s.operating.boot_at,
            )
        };
        let snapshot = actor.snapshot().map_err(selection::radio_error)?;
        if snapshot.authority.profile_revision != revision {
            return Err("state_conflict");
        }
        let name = operation.key();
        let observation = actor
            .execute(wstx_rust::radio_control::Request {
                authority: snapshot.authority,
                request_id: profile::new_uuid().map_err(|_| "storage_unavailable")?,
                operation,
                deadline: Instant::now() + Duration::from_secs(5),
                cancelled: Arc::new(AtomicBool::new(false)),
            })
            .map_err(selection::radio_error)?;
        self.refresh_radio_cache();
        if self.state.lock().unwrap().operating.radio.generation != generation {
            return Err("state_conflict");
        }
        Ok(
            json!({"v":1,"profile_id":self.profile,"boot_id":self.boot,"connection_generation":generation,"operation":name,"observation":selection::observation(&observation,at)}),
        )
    }
    pub(crate) fn refresh_radio_cache(&self) {
        let (actor, generation) = {
            let s = self.state.lock().unwrap();
            (
                s.operating.radio.actor.clone(),
                s.operating.radio.generation,
            )
        };
        // Actor snapshot/drop must happen outside the Recording lock.
        let observed = actor.as_ref().and_then(|a| a.snapshot().ok());
        self.commit_radio_cache(actor, generation, observed);
    }
    fn commit_radio_cache(
        &self,
        actor: Option<Arc<wstx_rust::radio_control::actor::Actor>>,
        generation: u64,
        observed: Option<wstx_rust::radio_control::Snapshot>,
    ) {
        let mut s = self.state.lock().unwrap();
        let same = match (&actor, &s.operating.radio.actor) {
            (Some(a), Some(b)) => Arc::ptr_eq(a, b),
            (None, None) => true,
            _ => false,
        };
        if same && let Some(observed) = observed {
            let radio = &mut s.operating.radio;
            if generation == radio.generation
                && observed.authority.connection_generation == generation
                && radio
                    .cached
                    .as_ref()
                    .is_none_or(|old| observed.publication() >= old.publication())
            {
                radio.cached = Some(observed);
            }
        }
    }
    pub(crate) fn radio_view(&self) -> Value {
        self.refresh_radio_cache();
        let s = self.state.lock().unwrap();
        let o = &s.operating;
        let r = &o.radio;
        let bound = selection::bound_snapshot(r.cached.as_ref(), o.profile_revision);
        let snapshot = bound.as_ref();
        json!({"v":1,"profile_id":self.profile,"boot_id":self.boot,"connection_generation":r.generation,
            "state":snapshot.map(|v|selection::state_name(v.state)).unwrap_or(if r.connecting {"connecting"}else if r.error.is_some(){"unavailable"}else{"closed"}),
            "error":snapshot.and_then(|v|v.last_error.map(selection::radio_error)).or(r.error),
            "device_id":snapshot.map(|v|v.authority.resource_id.as_str()),"effective_baud":snapshot.and_then(|v|v.effective_baud),
            "observation":snapshot.and_then(|v|v.observation.observed_at.map(|_|selection::observation(&v.observation,o.boot_at)))})
    }
    pub(crate) fn selection_snapshot(&self, cat: bool) -> Result<Value> {
        self.reap_receive();
        self.refresh_radio_cache();
        let mut s = self.state.lock().unwrap();
        let owner_released = s.live_owner_released;
        let receive = self.live_view(&s);
        let generation = s.generation;
        let o = &mut s.operating;
        let r = &o.radio;
        let bands: Vec<_> = selection::BANDS
            .iter()
            .filter(|b| selection::frequency(o.nominal.mode, b).is_some())
            .collect();
        let bound = selection::bound_snapshot(r.cached.as_ref(), o.profile_revision);
        let radio = json!({"connection_generation":r.generation,
            "state":bound.as_ref().map(|v|selection::state_name(v.state)).unwrap_or(if r.connecting{"connecting"}else if r.error.is_some(){"unavailable"}else{"closed"}),
            "error":bound.as_ref().and_then(|v|v.last_error.map(selection::radio_error)).or(r.error),
            "observations":selection::facts(bound.as_ref(),o.boot_at)});
        let mut value = json!({"v":1,"profile_id":self.profile,"boot_id":self.boot,"profile_revision":o.profile_revision,
            "generation":generation,"operating_revision":o.revision,"control":if cat{"cat"}else{"manual"},
            "selection":o.nominal,"available_bands":bands,"operation":o.operation,"cancellation":o.cancellation,
            "receive":{"job_id":receive["job"]["id"],"mode":receive["job"]["mode"],"state":receive["job"]["state"],"audio_state":receive["audio"]["state"],"owner_released":owner_released},"radio":radio});
        if o.last_material.as_ref() != Some(&value) {
            if o.snapshot_sequence == profile::MAX_REVISION {
                return Err("counter_exhausted");
            }
            o.snapshot_sequence += 1;
            o.last_material = Some(value.clone());
        }
        value["snapshot_sequence"] = json!(o.snapshot_sequence);
        value["monotonic_ms"] = json!(
            o.boot_at
                .elapsed()
                .as_millis()
                .min(u128::from(profile::MAX_REVISION)) as u64
        );
        if serde_json::to_vec(&value)
            .map_err(|_| "snapshot_limit")?
            .len()
            > 3072
        {
            return Err("snapshot_limit");
        }
        Ok(value)
    }
    fn selection_receipt(&self, command: &str, revision: u64, phase: &str) -> Value {
        json!({"v":1,"profile_id":self.profile,"boot_id":self.boot,"command_id":command,"operating_revision":revision,"accepted":true,"phase":phase})
    }
    fn selection_preflight(
        &self,
        s: &State,
        intent: &selection::Intent,
        cat: bool,
    ) -> Result<selection::Requested> {
        if intent.profile_id != self.profile {
            return Err("wrong_profile");
        }
        if intent.boot_id != self.boot
            || intent.generation != s.generation
            || intent.profile_revision != s.operating.profile_revision
            || intent.revision != s.operating.revision
        {
            return Err("state_conflict");
        }
        if s.operating.active()
            || s.import
                .as_ref()
                .is_some_and(|i| !terminal(i.state) || i.worker)
            || s.job
                .as_ref()
                .is_some_and(|j| j.kind != "live" && !terminal(j.state))
        {
            return Err("busy");
        }
        let mode = intent.mode.unwrap_or(s.operating.nominal.mode);
        let bound_radio =
            selection::bound_snapshot(s.operating.radio.cached.as_ref(), intent.profile_revision)
                .filter(|snapshot| {
                    snapshot.authority.profile_id == self.profile
                        && snapshot.authority.boot_id == self.boot
                        && snapshot.authority.connection_generation == s.operating.radio.generation
                });
        let selected_band = intent
            .band
            .as_deref()
            .or(s.operating.nominal.band)
            .or_else(|| {
                bound_radio
                    .as_ref()
                    .filter(|v| v.state == wstx_rust::radio_control::State::Ready)
                    .and_then(|v| v.facts.frequency.confirmed.then_some(&v.facts.frequency))
                    .and_then(|f| f.value)
                    .and_then(selection::band_for)
            })
            .ok_or("select_band_first")?;
        let band = selection::BANDS
            .iter()
            .copied()
            .find(|b| *b == selected_band)
            .ok_or("selection_unavailable")?;
        let nominal_hz = selection::frequency(mode, band).ok_or("selection_unavailable")?;
        if cat {
            let snapshot = bound_radio.as_ref().ok_or("radio_unavailable")?;
            if snapshot.state != wstx_rust::radio_control::State::Ready
                || snapshot.authority.profile_revision != intent.profile_revision
            {
                return Err("radio_unavailable");
            }
        }
        if s.operating.revision == profile::MAX_REVISION {
            return Err("counter_exhausted");
        }
        Ok(selection::Requested {
            mode,
            band,
            nominal_hz,
        })
    }
    pub(crate) fn selection_begin(
        self: &Arc<Self>,
        intent: selection::Intent,
        device: Option<String>,
        cat: bool,
    ) -> Result<Value> {
        self.reap_receive();
        self.refresh_radio_cache();
        let requested = {
            let s = self.state.lock().unwrap();
            self.selection_preflight(&s, &intent, cat)?
        };
        let actor = if cat {
            Some(
                self.radio_actor()
                    .ok_or("radio_unavailable")?
                    .reserve_transition()
                    .map_err(selection::radio_error)?,
            )
        } else {
            None
        };
        let connection = actor
            .as_ref()
            .map(|a| a.snapshot().map(|s| s.authority.connection_generation))
            .transpose()
            .map_err(selection::radio_error)?;
        self.refresh_radio_cache();
        let operation;
        {
            let mut s = self.state.lock().unwrap();
            if self.selection_preflight(&s, &intent, cat)? != requested
                || connection.is_some_and(|g| g != s.operating.radio.generation)
            {
                return Err("state_conflict");
            }
            let old_job = s.job.as_ref().filter(|j| j.kind == "live");
            let old_job_id = old_job.map(|j| j.id.clone());
            let monitor_before = old_job.is_some_and(|j| !terminal(j.state));
            let revision = s.operating.next_revision()?;
            operation = selection::Operation {
                command_id: intent.command_id,
                base_revision: intent.revision,
                revision,
                action: intent.action,
                requested,
                phase: "releasing",
                result: "pending",
                error: None,
                monitor_before,
                monitor_wanted: true,
                old_job_id,
                new_job_id: None,
                new_generation: None,
                old_generation: intent.generation,
                new_worker_cancel: None,
                cancelled: Arc::new(AtomicBool::new(false)),
            };
            // Invalidation and cancellation are committed before the admission receipt.
            if let Some(job) = s
                .job
                .as_mut()
                .filter(|j| j.kind == "live" && !terminal(j.state))
            {
                job.cancel.store(true, Ordering::Release);
                job.state = "cancelling";
            }
            s.frame = None;
            s.detail_frame = None;
            s.operating.operation = Some(operation.clone());
        }
        let receipt =
            self.selection_receipt(&operation.command_id, operation.revision, "releasing");
        let this = self.clone();
        let failed_operation = operation.clone();
        if std::thread::Builder::new()
            .name("station-selection".into())
            .spawn(move || this.selection_run(operation, device, actor))
            .is_err()
        {
            self.selection_failed(&failed_operation, "audio_unavailable", "failed");
        }
        Ok(receipt)
    }
    fn selection_current(s: &State, op: &selection::Operation) -> bool {
        s.operating.revision == op.revision
            && s.operating
                .operation
                .as_ref()
                .is_some_and(|o| o.command_id == op.command_id && o.result == "pending")
            && !op.cancelled.load(Ordering::Acquire)
    }
    fn selection_failed(
        &self,
        op: &selection::Operation,
        error: &'static str,
        phase: &'static str,
    ) {
        let mut s = self.state.lock().unwrap();
        if Self::selection_current(&s, op)
            && let Some(o) = s.operating.operation.as_mut()
        {
            o.phase = phase;
            o.result = "failed";
            o.error = Some(error);
            o.monitor_wanted = false;
        }
    }
    fn selection_run(
        self: Arc<Self>,
        op: selection::Operation,
        device: Option<String>,
        actor: Option<wstx_rust::radio_control::actor::TransitionLease>,
    ) {
        let deadline = Instant::now() + Duration::from_millis(250);
        loop {
            self.reap_receive();
            let s = self.state.lock().unwrap();
            if !Self::selection_current(&s, &op) {
                return;
            }
            if s.live_owner_released {
                break;
            }
            drop(s);
            if Instant::now() >= deadline {
                self.selection_failed(&op, "release_failed", "release_blocked");
                return;
            }
            std::thread::sleep(Duration::from_millis(1));
        }
        {
            let mut s = self.state.lock().unwrap();
            if !Self::selection_current(&s, &op) {
                return;
            }
            s.operating.operation.as_mut().unwrap().phase = "applying";
        }
        let cat_applied = actor.is_some();
        if let Some(actor) = actor.as_ref() {
            use wstx_rust::radio_control::{Operation, Request, Sideband};
            let result = (|| {
                let snapshot = actor.snapshot()?;
                let make = |operation| Request {
                    authority: snapshot.authority.clone(),
                    request_id: op.command_id.clone(),
                    operation,
                    deadline: Instant::now() + Duration::from_secs(5),
                    cancelled: op.cancelled.clone(),
                };
                let observed = actor.execute(make(Operation::ReadRxTx))?;
                if observed.transmitting != Some(false) {
                    return Err(wstx_rust::radio_control::Error::Unavailable);
                }
                actor.execute(make(Operation::ReceiveSetup {
                    frequency_hz: op.requested.nominal_hz,
                    mode: Sideband::Usb,
                    filter: 1,
                    data: true,
                    data_filter: 1,
                }))?;
                Ok::<_, wstx_rust::radio_control::Error>(())
            })();
            self.refresh_radio_cache();
            if let Err(error) = result {
                self.selection_failed(&op, selection::radio_error(error), "failed");
                return;
            }
        }
        let generation = {
            let mut s = self.state.lock().unwrap();
            if !Self::selection_current(&s, &op) {
                return;
            }
            s.operating.nominal = selection::Nominal {
                mode: op.requested.mode,
                band: Some(op.requested.band),
                nominal_hz: Some(op.requested.nominal_hz),
                origin: if cat_applied {
                    "cat_readback"
                } else {
                    "manual"
                },
                confirmed_command_id: Some(op.command_id.clone()),
            };
            s.operating.operation.as_mut().unwrap().phase = "restarting";
            s.generation
        };
        let Some(device) = device else {
            self.selection_failed(&op, "audio_unconfigured", "failed");
            return;
        };
        if let Err(error) = self.receive_start_selected(
            &self.profile,
            &self.boot,
            generation,
            device,
            op.requested.mode,
            StartGuard::Selection(op.revision),
        ) {
            self.selection_failed(&op, error, "failed");
            return;
        }
        let mut s = self.state.lock().unwrap();
        if Self::selection_current(&s, &op)
            && let Some(o) = s.operating.operation.as_mut()
        {
            o.phase = "applied";
            o.result = "success";
        }
    }
    pub(crate) fn selection_cancel(
        &self,
        profile: &str,
        boot: &str,
        command: String,
        target: String,
        revision: u64,
    ) -> Result<(Value, bool)> {
        let mut s = self.state.lock().unwrap();
        if profile != self.profile {
            return Err("wrong_profile");
        }
        if boot != self.boot {
            return Err("state_conflict");
        }
        if let Some(cancel) = s
            .operating
            .cancellation
            .as_ref()
            .filter(|c| c.command_id == command)
        {
            if cancel.target_command_id != target || cancel.expected_revision != revision {
                return Err("state_conflict");
            }
            return Ok((
                self.selection_receipt(&command, cancel.revision, "cancelled"),
                true,
            ));
        }
        let op = s
            .operating
            .operation
            .as_ref()
            .filter(|o| o.command_id == target)
            .cloned();
        let result = if let Some(op) = op {
            if s.operating.revision != op.revision
                || (revision != op.base_revision && revision != op.revision)
            {
                return Err("operation_superseded");
            }
            if s.operating.revision == profile::MAX_REVISION {
                return Err("counter_exhausted");
            }
            op.cancelled.store(true, Ordering::Release);
            // Unknown-loss epochs rotate the same worker's public tuple, but keep
            // this existing private cancellation Arc. A fresh Start has a new Arc.
            // Never reinterpret an old public Stop tuple as authority over a new job.
            if let Some(job) = s.job.as_mut().filter(|j| {
                j.kind == "live"
                    && ((op.new_job_id.as_deref() == Some(&j.id)
                        && op.new_generation == Some(j.generation))
                        || (op.old_job_id.as_deref() == Some(&j.id)
                            && op.old_generation == j.generation)
                        || op
                            .new_worker_cancel
                            .as_ref()
                            .is_some_and(|cancel| Arc::ptr_eq(cancel, &j.cancel)))
            }) && !terminal(job.state)
            {
                job.cancel.store(true, Ordering::Release);
                job.state = "cancelling";
            }
            let already = op.result == "cancelled";
            let current = s.operating.operation.as_mut().unwrap();
            current.monitor_wanted = false;
            current.phase = "cancelled";
            current.result = "cancelled";
            s.frame = None;
            s.detail_frame = None;
            if already {
                "already_cancelled"
            } else {
                "cancelled"
            }
        } else {
            if revision != s.operating.revision || s.operating.active() {
                return Err("operation_superseded");
            }
            "fenced"
        };
        let next = s.operating.next_revision()?;
        s.operating.cancellation = Some(selection::Cancellation {
            command_id: command.clone(),
            target_command_id: target,
            revision: next,
            result,
            expected_revision: revision,
        });
        Ok((self.selection_receipt(&command, next, "cancelled"), false))
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
}
impl LiveWorker {
    fn new(owner: Arc<Recording>, job: Job, input: Box<dyn LiveInput>, mode: &str) -> Self {
        let mode = match mode {
            "ft8" => Some(decoder::Mode::Ft8),
            "ft4" => Some(decoder::Mode::Ft4),
            _ => None,
        };
        Self {
            owner,
            job,
            input,
            mode,
            window: None,
            modem: mode.map(decoder::DecodeState::new_live),
            reset: false,
            epoch_seen: false,
            spectrum: LiveSpectrum::new(),
        }
    }
    fn current(&self) -> bool {
        !self.job.cancel.load(Ordering::Acquire)
    }
    fn run(mut self, mut result: Result<()>) {
        while result.is_ok() && self.current() {
            match self.step() {
                Ok(Some(window)) => result = self.analyze(window),
                Ok(None) => std::thread::sleep(Duration::from_millis(2)),
                Err(error) => result = Err(error),
            }
        }
        self.input.request_stop();
        loop {
            let _ = self.input.poll();
            let status = self.input.status();
            {
                let mut s = self.owner.state.lock().unwrap();
                if let Some(l) = s.live.as_mut() {
                    l.audio = status;
                }
            }
            if status.state == audio::AudioState::Closed {
                break;
            }
            // FailedClose retains the native owner and receiver admission until release.
            if status.error == Some(source::SourceError::FailedClose) {
                result = Err("audio_close_failed");
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        // Closed acknowledges the device, then all receive-owned processing and
        // wrapper resources must leave scope before another worker is admitted.
        let Self {
            owner,
            job,
            input,
            window,
            modem,
            spectrum,
            ..
        } = self;
        drop((input, window, modem, spectrum));
        let mut s = owner.state.lock().unwrap();
        if let Some(j) = s
            .job
            .as_mut()
            .filter(|j| j.id == job.id && j.generation == job.generation)
        {
            if job.cancel.load(Ordering::Acquire) {
                j.state = "cancelled";
                j.error = None;
            } else {
                j.state = "failed";
                j.error = result.err();
            }
        }
    }
    fn epoch(&mut self, p: source::EpochProposal) -> Result<()> {
        self.window = None;
        self.modem = None;
        self.spectrum.reset(0);
        self.reset = true;
        let mut s = self.owner.state.lock().unwrap();
        if !self.current() {
            return Err("cancelled");
        }
        self.job.source_id = None;
        if let Some(j) = s.job.as_mut() {
            j.source_id = None;
        }
        s.frame = None;
        s.detail_frame = None;
        s.latest_decode = None;
        s.decode_counter = 0;
        s.live.as_mut().ok_or("state_conflict")?.clear_context();
        let replacement = if self.epoch_seen {
            let generation = s
                .generation
                .checked_add(1)
                .filter(|g| *g <= source::MAX_COUNTER)
                .ok_or("generation_exhausted")?;
            Some((
                profile::new_uuid().map_err(|_| "storage_unavailable")?,
                generation,
            ))
        } else {
            None
        };
        let source_id = self.owner.live_source_uuid()?;
        let mut descriptor = Arc::new(SourceDescriptor {
            schema_version: 1,
            profile_id: self.owner.profile.clone(),
            boot_id: self.owner.boot.clone(),
            source_id,
            rate_hz: 12000,
            channel: "mono_real",
            total_frames: None,
            utc_anchor: None,
        });
        let mut timing = source::SourceTiming {
            source_id: descriptor.source_id.clone(),
            segment: 0,
            native_rate: p.native_rate,
            native_anchor_frame: p.first_device_frame as f64 + p.converter_delay_native_frames,
            canonical_anchor_frame: 0,
            converter_delay_native_frames: p.converter_delay_native_frames,
            qpc_anchor_100ns: p.packet_qpc_100ns,
            system_utc_anchor: None,
            uncertainty_ns: None,
            correlated: false,
            external_accuracy: source::ExternalAccuracy::Unknown,
        };
        #[cfg(windows)]
        if let (Some(packet), Some(clock)) = (p.packet_qpc_100ns, audio::system_clock()) {
            let delay =
                (p.converter_delay_native_frames * 10_000_000.0 / f64::from(p.native_rate)).round();
            if delay.is_finite()
                && delay >= 0.0
                && let Some(center) = packet.checked_add(delay as u64)
                && let Some(utc) = clock.utc_at(center).and_then(utc_from_filetime)
            {
                timing.qpc_anchor_100ns = Some(center);
                timing.system_utc_anchor = Some(utc.clone());
                timing.uncertainty_ns = Some(clock.uncertainty_ns);
                timing.correlated = true;
                Arc::get_mut(&mut descriptor).unwrap().utc_anchor = Some(utc);
            }
        }
        if let Some((id, generation)) = replacement {
            self.job.id = id;
            self.job.generation = generation;
            self.job.processed_frames = 0;
            s.generation = generation;
        }
        s.job = Some(self.job.clone());
        // ACK is a synchronous provider memory operation. Keeping the owner lock
        // through it prevents a pre-ACK source from appearing in any snapshot.
        self.input
            .acknowledge_epoch(p.proposal_counter, descriptor.clone(), timing.clone())
            .map_err(audio_error)?;
        self.job.source_id = Some(descriptor.source_id.clone());
        s.job = Some(self.job.clone());
        s.frame = None;
        s.detail_frame = None;
        let l = s.live.as_mut().ok_or("state_conflict")?;
        l.source = Some(descriptor.clone());
        l.timing = Some(timing.clone());
        drop(s);
        self.window = Some(
            receive::WindowBuffer::new(self.mode.unwrap_or(decoder::Mode::Ft8), descriptor)
                .map_err(window_error)?,
        );
        self.spectrum.reset(0);
        self.reset = true;
        self.epoch_seen = true;
        Ok(())
    }
    fn step(&mut self) -> Result<Option<receive::AnalysisWindow>> {
        let event = self.input.poll();
        {
            let mut s = self.owner.state.lock().unwrap();
            if let Some(l) = s.live.as_mut() {
                l.audio = self.input.status();
            }
        }
        match event {
            SourcePoll::EpochChanged(p) => {
                self.epoch(p)?;
                Ok(None)
            }
            SourcePoll::Block(block) => {
                let outcome = self
                    .window
                    .as_mut()
                    .map(|w| w.push(&block))
                    .transpose()
                    .map_err(window_error)?;
                let frames = self.spectrum.push(&block)?;
                let mut s = self.owner.state.lock().unwrap();
                if !self.current() {
                    return Err("cancelled");
                }
                let j = s
                    .job
                    .as_mut()
                    .filter(|j| j.id == self.job.id && j.generation == self.job.generation)
                    .ok_or("state_conflict")?;
                j.processed_frames = outcome
                    .as_ref()
                    .map(|o| o.captured_next_frame)
                    .unwrap_or(block.first_frame + block.samples.len() as u64);
                let next = j.processed_frames;
                let gap_reset = outcome.as_ref().is_some_and(|o| o.reset_decoder);
                if gap_reset {
                    s.latest_decode = None;
                }
                let l = s.live.as_mut().ok_or("state_conflict")?;
                l.next_frame = next;
                self.reset |= outcome.as_ref().is_some_and(|o| o.reset_decoder);
                if self.reset {
                    self.modem = None;
                }
                for SpectrumRow {
                    first,
                    end,
                    levels,
                    detailed,
                } in frames.into_iter().flatten()
                {
                    let sequence = first / if detailed { 2400 } else { 12000 };
                    let kind = if detailed {
                        "spectrum.detail.frame"
                    } else {
                        "spectrum.frame"
                    };
                    let frame = json!({"v":1,"type":kind,"data":{"boot_id":self.owner.boot,
                        "source_id":self.job.source_id,"job_id":self.job.id,"generation":self.job.generation,
                        "sequence":sequence,"first_frame":first,"end_frame":end,"levels_b64":STANDARD.encode(&levels)}});
                    if detailed {
                        s.detail_frame = Some(frame);
                    } else {
                        let mut frame = frame;
                        frame["data"].as_object_mut().unwrap().remove("levels_b64");
                        frame["data"]["levels"] = json!(levels);
                        s.frame = Some(frame);
                    }
                }
                Ok(if self.mode.is_some() {
                    outcome.and_then(|o| o.window)
                } else {
                    None
                })
            }
            SourcePoll::Failed(source::SourceError::Unavailable) => {
                self.window = None;
                self.modem = None;
                self.reset = true;
                let mut s = self.owner.state.lock().unwrap();
                if !self.current() {
                    return Err("cancelled");
                }
                if self.job.source_id.is_some() {
                    let generation = s
                        .generation
                        .checked_add(1)
                        .filter(|g| *g <= source::MAX_COUNTER)
                        .ok_or("generation_exhausted")?;
                    self.job.id = profile::new_uuid().map_err(|_| "storage_unavailable")?;
                    self.job.generation = generation;
                    self.job.source_id = None;
                    self.job.processed_frames = 0;
                    s.generation = generation;
                    s.job = Some(self.job.clone());
                    self.epoch_seen = false;
                }
                s.frame = None;
                s.detail_frame = None;
                s.latest_decode = None;
                s.decode_counter = 0;
                if let Some(l) = s.live.as_mut() {
                    l.clear_context();
                }
                Ok(None)
            }
            SourcePoll::Failed(e) => Err(audio_error(e)),
            SourcePoll::End => Err("audio_unavailable"),
            SourcePoll::Pending => Ok(None),
        }
    }
    fn analyze(&mut self, mut window: receive::AnalysisWindow) -> Result<()> {
        use std::{
            future::Future,
            task::{Context, Poll, Waker},
        };
        loop {
            let mode = self.mode.ok_or("state_conflict")?;
            let mut state = if self.reset {
                self.modem = None;
                decoder::DecodeState::new_live(mode)
            } else {
                self.modem.take().ok_or("state_conflict")?
            };
            self.reset = false;
            let decoder = decoder::Decoder::new();
            let cancel = self.job.cancel.clone();
            let job = self.job.clone();
            let owner = self.owner.clone();
            let cancelled = || cancel.load(Ordering::Acquire);
            let mut publish = |decoded: &decoder::Decode| owner.publish_decode(&job, decoded);
            let interval = (window.origin, window.origin + window.samples.len() as u64);
            let first_sequence = self
                .owner
                .state
                .lock()
                .unwrap()
                .live
                .as_ref()
                .map(|l| l.next_sequence)
                .ok_or("state_conflict")?;
            let mut complete = false;
            let mut future = Box::pin(decoder.decode_window_into_async(
                window.samples,
                window.origin,
                &mut state,
                &cancelled,
                &mut publish,
            ));
            let mut context = Context::from_waker(Waker::noop());
            let mut replacement = None;
            let result = loop {
                if !self.current() {
                    break Err("cancelled");
                }
                match future.as_mut().poll(&mut context) {
                    Poll::Ready(result) => {
                        break match result {
                            Ok(()) => {
                                complete = true;
                                Ok(())
                            }
                            Err(decoder::DecodeError::Cancelled) => Err("cancelled"),
                            Err(decoder::DecodeError::SearchLimited) => {
                                if let Some(l) = self.owner.state.lock().unwrap().live.as_mut() {
                                    l.search_limited = true;
                                }
                                Err("decode_limit")
                            }
                            Err(_) => Err(self
                                .owner
                                .state
                                .lock()
                                .unwrap()
                                .live
                                .as_ref()
                                .and_then(|l| l.publication_error)
                                .unwrap_or("decode_limit")),
                        };
                    }
                    Poll::Pending => {}
                }
                // Drain the real capture queue between cooperative numerical yields.
                for _ in 0..128 {
                    match self.step() {
                        Ok(Some(next)) => {
                            replacement = Some(next);
                            break;
                        }
                        Ok(None) => {}
                        Err(error) => {
                            drop(future);
                            return Err(error);
                        }
                    }
                    if self.reset {
                        break;
                    }
                }
                if replacement.is_some() || self.reset {
                    if replacement.is_some()
                        && let Some(l) = self.owner.state.lock().unwrap().live.as_mut()
                    {
                        l.last_overrun = Some(interval);
                    }
                    break Ok(());
                }
            };
            drop(future);
            self.modem = if self.reset { None } else { Some(state) };
            result?;
            if !self.reset {
                self.owner
                    .publish_latest_decode(&job, interval, first_sequence, complete)?;
            }
            if let Some(next) = replacement {
                window = next;
            } else {
                return Ok(());
            }
        }
    }
}

fn period_parameters(mode: &str) -> Option<(i128, i128, i128)> {
    match mode {
        "ft8" => Some((150_000_000, 5_000_000, 126_400_000)),
        "ft4" => Some((75_000_000, 4_520_000, 50_400_000)),
        _ => None,
    }
}
fn source_ticks(timing: &source::SourceTiming, frame: u64) -> Option<i128> {
    if !timing.correlated {
        return None;
    }
    let anchor = i128::from(filetime_from_utc(timing.system_utc_anchor.as_deref()?)?);
    Some(
        anchor
            + (i128::from(frame) - i128::from(timing.canonical_anchor_frame)) * 10_000_000 / 12000,
    )
}
fn relative_decode_timing(
    timing: Option<&source::SourceTiming>,
    mode: &str,
    frame: u64,
) -> Option<(String, f64)> {
    let observed = source_ticks(timing?, frame)?;
    let (period, nominal, _) = period_parameters(mode)?;
    let slot = (observed - nominal + period / 2).div_euclid(period) * period;
    Some((
        utc_from_filetime(u64::try_from(slot).ok()?)?,
        (observed - slot - nominal) as f64 / 10_000_000.0,
    ))
}
fn filetime_from_utc(text: &str) -> Option<u64> {
    let b = text.as_bytes();
    if b.len() < 20
        || b.get(4) != Some(&b'-')
        || b.get(7) != Some(&b'-')
        || b.get(10) != Some(&b'T')
        || b.get(13) != Some(&b':')
        || b.get(16) != Some(&b':')
        || b.last() != Some(&b'Z')
    {
        return None;
    }
    let number = |a: usize, z: usize| -> Option<u64> {
        let part = b.get(a..z)?;
        if !part.iter().all(u8::is_ascii_digit) {
            return None;
        }
        std::str::from_utf8(part).ok()?.parse().ok()
    };
    let (year, month, day, hour, minute, second) = (
        number(0, 4)?,
        number(5, 7)?,
        number(8, 10)?,
        number(11, 13)?,
        number(14, 16)?,
        number(17, 19)?,
    );
    if !(1970..=9999).contains(&year)
        || !(1..=12).contains(&month)
        || hour > 23
        || minute > 59
        || second > 59
    {
        return None;
    }
    let leap = |y: u64| y.is_multiple_of(4) && (!y.is_multiple_of(100) || y.is_multiple_of(400));
    let months = [
        31,
        if leap(year) { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ];
    if day == 0 || day > months[(month - 1) as usize] {
        return None;
    }
    let mut days = 0;
    for y in 1970..year {
        days += if leap(y) { 366 } else { 365 };
    }
    days += months[..(month - 1) as usize].iter().sum::<u64>() + day - 1;
    let fraction = if b.len() == 20 {
        0
    } else {
        if b.get(19) != Some(&b'.') || !(22..=28).contains(&b.len()) {
            return None;
        }
        let digits = b.len() - 21;
        number(20, b.len() - 1)? * 10_u64.pow((7 - digits) as u32)
    };
    (11_644_473_600 + days * 86400 + hour * 3600 + minute * 60 + second)
        .checked_mul(10_000_000)?
        .checked_add(fraction)
}

fn utc_from_filetime(ticks: u64) -> Option<String> {
    let seconds = ticks.checked_div(10_000_000)?.checked_sub(11_644_473_600)?;
    let mut days = seconds / 86400;
    let mut year = 1970u64;
    let leap = |year: u64| {
        year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400))
    };
    while year <= 9999 {
        let count = if leap(year) { 366 } else { 365 };
        if days < count {
            break;
        }
        days -= count;
        year += 1;
    }
    if year > 9999 {
        return None;
    }
    let months = [
        31,
        if leap(year) { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ];
    let mut month = 1;
    for count in months {
        if days < count {
            break;
        }
        days -= count;
        month += 1;
    }
    let time = seconds % 86400;
    Some(format!(
        "{year:04}-{month:02}-{:02}T{:02}:{:02}:{:02}.{:07}Z",
        days + 1,
        time / 3600,
        time % 3600 / 60,
        time % 60,
        ticks % 10_000_000
    ))
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
impl LiveSpectrum {
    fn new() -> Self {
        Self {
            samples: VecDeque::with_capacity(8192),
            first: 0,
            next: 0,
            thin_start: 0,
            detail_start: 0,
            thin: spectrum::Spectrum::new(false),
            detail: spectrum::Spectrum::detailed(false),
            peak: [0.; 128],
            powers: [0.; 1024],
            count: 0,
        }
    }
    fn reset(&mut self, first: u64) {
        self.samples.clear();
        self.first = first;
        self.next = first;
        self.thin_start = first.div_ceil(12000) * 12000;
        self.detail_start = first.div_ceil(2400) * 2400;
        self.peak.fill(0.);
        self.powers.fill(0.);
        self.count = 0;
    }
    fn push(&mut self, block: &SampleBlock) -> Result<[Option<SpectrumRow>; 2]> {
        if block.discontinuity {
            self.reset(block.first_frame);
        }
        if block.first_frame != self.next || block.samples.iter().any(|s| !s.is_finite()) {
            return Err("audio_failed");
        }
        self.next = self
            .next
            .checked_add(block.samples.len() as u64)
            .filter(|n| *n <= source::MAX_COUNTER)
            .ok_or("counter_exhausted")?;
        self.samples.extend(block.samples.iter().copied());
        let mut frames = [None, None];
        while self.thin_start + 2048 <= self.next {
            let offset = (self.thin_start - self.first) as usize;
            let x: Vec<_> = self
                .samples
                .iter()
                .skip(offset)
                .take(2048)
                .copied()
                .collect();
            for (peak, power) in self.peak.iter_mut().zip(self.thin.amplitudes(&x)?) {
                *peak = peak.max(power);
            }
            let first = self.thin_start / 12000 * 12000;
            self.thin_start += spectrum::HOP;
            if self.thin_start >= first + 12000 {
                frames[0] = Some(SpectrumRow {
                    first,
                    end: first + 12000,
                    levels: self.peak.into_iter().map(spectrum::quantize).collect(),
                    detailed: false,
                });
                self.peak.fill(0.);
            }
        }
        while self.detail_start + 4096 <= self.next {
            let offset = (self.detail_start - self.first) as usize;
            let x: Vec<_> = self
                .samples
                .iter()
                .skip(offset)
                .take(4096)
                .copied()
                .collect();
            for (power, a) in self
                .powers
                .iter_mut()
                .zip(self.detail.native_amplitudes(&x)?)
            {
                *power += a * a;
            }
            self.count += 1;
            let first = self.detail_start / 2400 * 2400;
            self.detail_start += 480;
            if self.detail_start >= first + 2400 {
                let levels = self
                    .powers
                    .iter()
                    .map(|p| spectrum::quantize((p / self.count as f32).sqrt()))
                    .collect();
                frames[1] = Some(SpectrumRow {
                    first,
                    end: first + 2400,
                    levels,
                    detailed: true,
                });
                self.powers.fill(0.);
                self.count = 0;
            }
        }
        let retain = self.thin_start.min(self.detail_start);
        while self.first < retain && !self.samples.is_empty() {
            self.samples.pop_front();
            self.first += 1;
        }
        if self.samples.len() > 8192 {
            return Err("decode_limit");
        }
        Ok(frames)
    }
}
#[cfg(test)]
#[derive(Default)]
struct Resources {
    active_workers: usize,
    peak_workers: usize,
    peak_blocks: usize,
    cross_deadline: bool,
    deadline_crossings: usize,
    live_input: Option<Box<dyn LiveInput>>,
    live_inputs: VecDeque<Box<dyn LiveInput>>,
    fail_live_spawn: bool,
    fail_source_uuid: bool,
}
fn io<T>(value: std::io::Result<T>) -> Result<T> {
    value.map_err(|_| "storage_unavailable")
}
fn write_json(path: &Path, value: &impl Serialize) -> Result<()> {
    let bytes = serde_json::to_vec(value).map_err(|_| "storage_unavailable")?;
    let mut f = io(File::create(path))?;
    io(f.write_all(&bytes))?;
    io(f.sync_all())
}
fn bounded_json<T: serde::de::DeserializeOwned>(path: &Path, cap: u64) -> Result<T> {
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
    pub fn open(base: &Path, profile: String, boot: String) -> Arc<Self> {
        let dir = base.join("recordings");
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
            live: None,
            latest_decode: None,
            decode_counter: 0,
            operating: selection::Operating::new(),
            live_worker: None,
            live_owner_released: true,
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
                #[cfg(test)]
                cat_transport: Mutex::new(None),
                #[cfg(test)]
                resources: Mutex::new(Resources::default()),
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
                    || meta.rate_hz != 12000
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
            #[cfg(test)]
            cat_transport: Mutex::new(None),
            #[cfg(test)]
            resources: Mutex::new(Resources::default()),
        });
        if this.cleanup(None).is_err() {
            this.state.lock().unwrap().storage_error = Some("storage_unavailable");
        }
        this
    }
    fn path(&self, id: &str, extension: &str) -> PathBuf {
        self.dir.join(format!("{id}.{extension}"))
    }
    fn cleanup(&self, pending: Option<&str>) -> Result<()> {
        checkpoint("cleanup")?;
        let (committed, unknown_commit, rejected) = {
            let s = self.state.lock().unwrap();
            (
                s.committed_id.clone(),
                s.unknown_commit,
                s.import
                    .as_ref()
                    .filter(|i| matches!(i.state, "cancelling" | "failed"))
                    .map(|i| i.id.clone()),
            )
        };
        // An unreadable manifest provides no authority to delete a possible committed original.
        for entry in io(fs::read_dir(&self.dir))? {
            let entry = io(entry)?;
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if name == "current.json"
                || (unknown_commit
                    && name.rsplit_once('.').is_some_and(|(id, ext)| {
                        profile::valid_uuid(id)
                            && matches!(ext, "wav" | "json")
                            && rejected.as_deref() != Some(id)
                    }))
                || committed
                    .as_ref()
                    .is_some_and(|id| name == format!("{id}.wav") || name == format!("{id}.json"))
                || pending
                    .is_some_and(|id| name == format!("{id}.wav") || name == format!("{id}.json"))
            {
                continue;
            }
            if entry
                .file_type()
                .map_err(|_| "storage_unavailable")?
                .is_file()
            {
                io(fs::remove_file(entry.path()))?;
            } else {
                return Err("storage_unavailable");
            }
        }
        Ok(())
    }
    pub fn snapshot(&self) -> Value {
        let s = self.state.lock().unwrap();
        let recording = s.recording.as_ref().map(|m| json!({"id":m.recording_id,"rate_hz":12000,"frames":m.frames,"file_bytes":m.file_bytes,"utc_anchor":null}));
        let import = s.import.as_ref().filter(|i| !terminal(i.state)).map(|i| {
            let mut v = serde_json::to_value(i).unwrap();
            v.as_object_mut().unwrap().remove("recording_id");
            v
        });
        json!({"v":1,"profile_id":self.profile,"boot_id":self.boot,"generation":s.generation,"recording":recording,"source_error":s.source_error,"storage_error":s.storage_error,"import":import,"job":s.job})
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
        s.live = None;
        Ok(s.generation)
    }
    pub fn reserve(self: &Arc<Self>, profile: &str, boot: &str, generation: u64) -> Result<Value> {
        self.reap_receive();
        let mut s = self.state.lock().unwrap();
        if profile != self.profile {
            return Err("wrong_profile");
        }
        if boot != self.boot || generation != s.generation {
            return Err("state_conflict");
        }
        let id = profile::new_uuid().map_err(|_| "storage_unavailable")?;
        let generation = Self::admit(&mut s)?;
        s.import = Some(Import {
            id: id.clone(),
            state: "reserved",
            received_bytes: 0,
            total_bytes: None,
            error: None,
            recording_id: None,
            started: Instant::now(),
            touched: Instant::now(),
            worker: false,
            cleanup_started: None,
        });
        Ok(json!({"v":1,"id":id,"generation":generation,"state":"reserved"}))
    }
    pub fn import_view(&self, id: &str) -> Result<Value> {
        let s = self.state.lock().unwrap();
        let i = s
            .import
            .as_ref()
            .filter(|i| i.id == id)
            .ok_or("not_found")?;
        let mut v = serde_json::to_value(i).unwrap();
        v["v"] = json!(1);
        Ok(v)
    }
    pub fn cancel_import(self: &Arc<Self>, id: &str) -> Result<Value> {
        let cleanup;
        {
            let mut s = self.state.lock().unwrap();
            let i = s
                .import
                .as_mut()
                .filter(|i| i.id == id)
                .ok_or("not_found")?;
            if i.state == "committing" {
                return Err("invalid_state");
            }
            cleanup = !terminal(i.state) && i.state != "reserved" && !i.worker;
            if !terminal(i.state) {
                i.state = if i.state == "reserved" {
                    "cancelled"
                } else {
                    "cancelling"
                };
                i.cleanup_started = Some(Instant::now());
                i.error = Some("cancelled");
            }
            if cleanup {
                i.worker = true;
            }
        }
        if cleanup {
            let this = self.clone();
            let id = id.to_owned();
            std::thread::spawn(move || this.finish_cleanup(id));
        }
        self.import_view(id)
    }
    fn finish_cleanup(&self, id: String) {
        let outcome = self.cleanup(None);
        let mut s = self.state.lock().unwrap();
        if let Some(i) = s.import.as_mut().filter(|i| i.id == id) {
            if outcome.is_ok() {
                i.worker = false;
                i.state = if i.error == Some("cancelled") {
                    "cancelled"
                } else {
                    "failed"
                };
            } else {
                i.state = "failed";
                i.error = Some("storage_unavailable");
                s.storage_error = Some("storage_unavailable");
            }
        }
        if outcome.is_ok() {
            s.storage_error = None;
        }
    }
    pub fn tick(self: &Arc<Self>) {
        self.reap_receive();
        let expired = {
            let mut s = self.state.lock().unwrap();
            if let Some(i) = s.import.as_mut() {
                let limit = if i.state == "reserved" { 30 } else { 15 };
                if matches!(i.state, "reserved" | "receiving")
                    && (i.touched.elapsed() >= Duration::from_secs(limit)
                        || i.started.elapsed() >= Duration::from_secs(1800))
                {
                    i.state = "cancelling";
                    i.cleanup_started = Some(Instant::now());
                    i.error = Some("upload_timeout");
                    if !i.worker {
                        i.worker = true;
                        Some(i.id.clone())
                    } else {
                        None
                    }
                } else {
                    None
                }
            } else {
                None
            }
        };
        {
            let mut s = self.state.lock().unwrap();
            if let Some(i) = s.import.as_mut()
                && i.state == "cancelling"
                && i.cleanup_started
                    .is_some_and(|time| time.elapsed() >= Duration::from_secs(5))
            {
                i.state = "failed";
                i.error = Some("storage_unavailable");
                s.storage_error = Some("storage_unavailable");
            }
        }
        if let Some(id) = expired {
            let this = self.clone();
            std::thread::spawn(move || this.finish_cleanup(id));
        }
    }
    pub fn begin_chunk(self: &Arc<Self>, id: &str, start: u64, total: u64) -> Result<()> {
        {
            let mut s = self.state.lock().unwrap();
            let i = s
                .import
                .as_mut()
                .filter(|i| i.id == id)
                .ok_or("not_found")?;
            if i.error == Some("upload_timeout") {
                return Err("upload_timeout");
            }
            if i.error == Some("cancelled") {
                return Err("cancelled");
            }
            if i.worker || i.received_bytes != start || i.total_bytes.is_some_and(|n| n != total) {
                return Err("state_conflict");
            }
            if !matches!(i.state, "reserved" | "receiving") {
                return Err("invalid_state");
            }
            i.worker = true;
            i.state = "receiving";
            i.total_bytes = Some(total);
            i.touched = Instant::now();
        }
        Ok(())
    }
    pub fn chunk(&self, id: &str, start: u64, total: u64, body: Vec<u8>) -> Result<Value> {
        let result = self.write_chunk(id, start, total, &body);
        if let Err(code) = result {
            {
                let mut s = self.state.lock().unwrap();
                let i = s.import.as_mut().unwrap();
                i.state = "cancelling";
                i.cleanup_started = Some(Instant::now());
                i.error = Some(code);
            }
            self.finish_cleanup(id.to_owned());
            return Err(code);
        }
        result
    }
    fn write_chunk(&self, id: &str, start: u64, total: u64, body: &[u8]) -> Result<Value> {
        let path = self.path(id, "wav");
        let mut file = io(fs::OpenOptions::new()
            .create(start == 0)
            .append(true)
            .open(&path))?;
        io(file.write_all(body))?;
        checkpoint("append")?;
        let received = start + body.len() as u64;
        {
            let mut s = self.state.lock().unwrap();
            let i = s.import.as_mut().unwrap();
            if i.state != "receiving" {
                return Err(i.error.unwrap_or("cancelled"));
            }
            i.received_bytes = received;
            if received < total {
                i.worker = false;
                return Ok(json!({"v":1,"id":id,"state":"receiving","received_bytes":received}));
            }
            i.state = "validating";
        }
        checkpoint("original_flush")?;
        io(file.sync_all())?;
        drop(file);
        let wave = validate(&mut io(File::open(&path))?)?;
        let metadata = Metadata {
            schema_version: 1,
            recording_id: id.to_owned(),
            file_bytes: wave.bytes,
            frames: wave.frames,
            rate_hz: 12000,
        };
        checkpoint("metadata")?;
        write_json(&self.path(id, "json"), &metadata)?;
        checkpoint("manifest")?;
        write_json(
            &self.dir.join("manifest.tmp"),
            &Manifest {
                schema_version: 1,
                recording_id: id.to_owned(),
            },
        )?;
        {
            let mut s = self.state.lock().unwrap();
            let i = s.import.as_mut().unwrap();
            if i.state != "validating" {
                return Err(i.error.unwrap_or("cancelled"));
            }
            i.state = "committing";
        }
        checkpoint("replace")?;
        io(fs::rename(
            self.dir.join("manifest.tmp"),
            self.dir.join("current.json"),
        ))?;
        let generation;
        {
            let mut s = self.state.lock().unwrap();
            s.recording = Some(metadata);
            s.committed_id = Some(id.to_owned());
            s.unknown_commit = false;
            s.source_error = None;
            s.import.as_mut().unwrap().recording_id = Some(id.to_owned());
            generation = s.generation;
        }
        checkpoint("after_replace")?;
        // Keep the slot occupied until obsolete files are really removed.
        self.cleanup(None)?;
        {
            let mut s = self.state.lock().unwrap();
            let i = s.import.as_mut().unwrap();
            i.state = "completed";
            i.recording_id = Some(id.to_owned());
            i.worker = false;
        }
        Ok(json!({"v":1,"id":id,"state":"completed","recording_id":id,"generation":generation}))
    }
    pub fn replay(
        self: &Arc<Self>,
        profile: &str,
        boot: &str,
        generation: u64,
        source: &str,
    ) -> Result<Value> {
        self.reap_receive();
        let job;
        let meta;
        {
            let mut s = self.state.lock().unwrap();
            if profile != self.profile {
                return Err("wrong_profile");
            }
            if boot != self.boot || generation != s.generation {
                return Err("state_conflict");
            }
            if s.source_error.is_some() {
                return Err("recording_unavailable");
            }
            meta = s.recording.clone().ok_or("no_recording")?;
            if meta.recording_id != source {
                return Err("not_found");
            }
            let id = profile::new_uuid().map_err(|_| "storage_unavailable")?;
            let generation = Self::admit(&mut s)?;
            job = Job {
                id,
                source_id: Some(source.to_owned()),
                generation,
                kind: "spectrum",
                state: "running",
                processed_frames: 0,
                error: None,
                cancel: Arc::new(AtomicBool::new(false)),
            };
            s.frame = None;
            s.detail_frame = None;
            s.job = Some(job.clone());
        }
        let this = self.clone();
        let worker_job = job.clone();
        std::thread::spawn(move || this.run(worker_job, meta));
        Ok(json!({"v":1,"id":job.id,"generation":job.generation,"state":"running"}))
    }
    pub fn cancel_job(&self, id: &str) -> Result<Value> {
        let mut s = self.state.lock().unwrap();
        let j = s.job.as_mut().filter(|j| j.id == id).ok_or("not_found")?;
        if j.state == "running" {
            j.cancel.store(true, Ordering::Release);
            j.state = "cancelling";
        }
        let value = json!({"v":1,"id":id,"generation":j.generation,"state":j.state});
        s.frame = None;
        s.detail_frame = None;
        Ok(value)
    }
    fn run(&self, job: Job, meta: Metadata) {
        #[cfg(test)]
        {
            let mut r = self.resources.lock().unwrap();
            r.active_workers += 1;
            r.peak_workers = r.peak_workers.max(r.active_workers);
            assert_eq!(r.active_workers, 1);
        }
        let result = self.process(&job, &meta);
        #[cfg(test)]
        {
            self.resources.lock().unwrap().active_workers -= 1;
        }
        self.release(job, meta, result);
    }
    fn release(&self, job: Job, meta: Metadata, result: Result<()>) {
        // process has returned and dropped its file, sample blocks and FFT storage before terminal publication.
        let mut s = self.state.lock().unwrap();
        if let Some(j) = s
            .job
            .as_mut()
            .filter(|j| j.id == job.id && j.generation == job.generation)
        {
            if job.cancel.load(Ordering::Acquire) {
                j.state = "cancelled";
                j.error = None;
            } else if let Err(code) = result {
                j.state = "failed";
                j.error = Some(code);
                if code == "recording_unavailable" {
                    s.source_error = Some(code);
                    s.recording = None;
                }
            } else {
                j.state = "completed";
                j.processed_frames = meta.frames;
            }
        }
    }
    fn process(&self, job: &Job, meta: &Metadata) -> Result<()> {
        let source = Arc::new(SourceDescriptor {
            schema_version: 1,
            profile_id: self.profile.clone(),
            boot_id: self.boot.clone(),
            source_id: meta.recording_id.clone(),
            rate_hz: 12000,
            channel: "mono_real",
            total_frames: Some(meta.frames),
            utc_anchor: None,
        });
        let mut input = SourceFile::open(&self.path(&meta.recording_id, "wav"), source)?;
        let mut block = input.next()?.ok_or("recording_unavailable")?;
        #[cfg(test)]
        self.observe_blocks(&[&block]);
        if Some(&block.source.source_id) != job.source_id.as_ref()
            || block.discontinuity
            || block.end_of_stream != (block.samples.len() as u64 == meta.frames)
        {
            return Err("recording_unavailable");
        }
        let mut thin = spectrum::Spectrum::new(false);
        let mut detail = spectrum::Spectrum::detailed(false);
        let mut history: VecDeque<f32> = block.samples.iter().copied().collect();
        let mut history_first = 0u64;
        let (mut thin_start, mut detail_start) = (0u64, 0u64);
        let mut thin_peak = [0f32; 128];
        let mut thin_sequence = 0;
        let began = Instant::now();
        for sequence in 0..meta.frames.div_ceil(2400) {
            let row_end = ((sequence + 1) * 2400).min(meta.frames);
            let mut powers = [0f32; 1024];
            let mut count = 0;
            while thin_start.min(detail_start) < row_end {
                if job.cancel.load(Ordering::Acquire) {
                    return Err("cancelled");
                }
                let start = thin_start.min(detail_start);
                while history_first < start && !history.is_empty() {
                    history.pop_front();
                    history_first += 1;
                }
                let needed =
                    (start + if start == detail_start { 4096 } else { 2048 }).min(meta.frames);
                while history_first + (history.len() as u64) < needed {
                    let next = input.next()?.ok_or("recording_unavailable")?;
                    #[cfg(test)]
                    self.observe_blocks(&[&block, &next]);
                    if next.first_frame != history_first + history.len() as u64 {
                        return Err("recording_unavailable");
                    }
                    block = next;
                    if history.len() + block.samples.len() > 8192 {
                        return Err("recording_unavailable");
                    }
                    history.extend(block.samples.iter().copied());
                }
                if start == thin_start {
                    let x: Vec<f32> = history.iter().take(2048).copied().collect();
                    for (peak, a) in thin_peak.iter_mut().zip(thin.amplitudes(&x)?) {
                        *peak = peak.max(a);
                    }
                    thin_start += spectrum::HOP;
                }
                if start == detail_start {
                    let x: Vec<f32> = history.iter().take(4096).copied().collect();
                    for (power, a) in powers.iter_mut().zip(detail.native_amplitudes(&x)?) {
                        *power += a * a;
                    }
                    count += 1;
                    detail_start += 480;
                }
            }
            let due = Duration::from_secs_f64(row_end as f64 / spectrum::RATE as f64);
            loop {
                #[cfg(test)]
                let elapsed = began.elapsed();
                #[cfg(test)]
                {
                    let cross = {
                        let mut r = self.resources.lock().unwrap();
                        let cross = r.cross_deadline;
                        r.cross_deadline = false;
                        if cross {
                            r.deadline_crossings += 1;
                        }
                        cross
                    };
                    if cross {
                        std::thread::sleep(due.saturating_sub(elapsed) + Duration::from_millis(1));
                    }
                }
                let remaining = due.saturating_sub(began.elapsed());
                if remaining.is_zero() {
                    break;
                }
                if job.cancel.load(Ordering::Acquire) {
                    return Err("cancelled");
                }
                std::thread::sleep(remaining.min(Duration::from_millis(20)));
            }
            let levels: Vec<u8> = powers
                .into_iter()
                .map(|p| spectrum::quantize((p / count as f32).sqrt()))
                .collect();
            let mut s = self.state.lock().unwrap();
            if job.cancel.load(Ordering::Acquire) {
                return Err("cancelled");
            }
            if s.job.as_ref().is_some_and(|j| {
                j.id == job.id && j.generation == job.generation && j.state == "running"
            }) {
                s.job.as_mut().unwrap().processed_frames = row_end;
                s.detail_frame = Some(
                    json!({"v":1,"type":"spectrum.detail.frame","data":{"boot_id":self.boot,"source_id":job.source_id,"job_id":job.id,"generation":job.generation,"sequence":sequence,"first_frame":sequence*2400,"end_frame":row_end,"levels_b64":STANDARD.encode(levels)}}),
                );
                if row_end.is_multiple_of(12000) || row_end == meta.frames {
                    let levels: Vec<u8> = thin_peak.into_iter().map(spectrum::quantize).collect();
                    s.frame = Some(
                        json!({"v":1,"type":"spectrum.frame","data":{"boot_id":self.boot,"source_id":job.source_id,"job_id":job.id,"generation":job.generation,"sequence":thin_sequence,"first_frame":thin_sequence*12000,"end_frame":row_end,"levels":levels}}),
                    );
                    thin_peak.fill(0.0);
                    thin_sequence += 1;
                }
            }
        }
        Ok(())
    }
    #[cfg(test)]
    fn observe_blocks(&self, blocks: &[&SampleBlock]) {
        assert!(blocks.len() <= 2);
        for block in blocks {
            assert!(block.samples.len() <= 4096);
            assert_eq!(
                Arc::strong_count(&block.samples),
                1,
                "spectrum must release every previous immutable sample allocation"
            );
        }
        let mut r = self.resources.lock().unwrap();
        r.peak_blocks = r.peak_blocks.max(blocks.len());
    }
}
pub fn terminal(state: &str) -> bool {
    matches!(state, "completed" | "cancelled" | "failed")
}
