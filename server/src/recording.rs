use crate::{profile, spectrum};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
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
#[derive(Clone, Serialize)]
pub struct SourceDescriptor {
    pub schema_version: u8,
    pub profile_id: String,
    pub boot_id: String,
    pub source_id: String,
    pub rate_hz: u32,
    pub channel: &'static str,
    pub total_frames: Option<u64>,
    pub utc_anchor: Option<String>,
}
pub struct SampleBlock {
    pub source: Arc<SourceDescriptor>,
    pub first_frame: u64,
    pub samples: Arc<[f32]>,
    pub discontinuity: bool,
    pub end_of_stream: bool,
}
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
    pub source_id: String,
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
}
pub struct Recording {
    pub state: Mutex<State>,
    dir: PathBuf,
    pub profile: String,
    pub boot: String,
    #[cfg(test)]
    resources: Mutex<Resources>,
}
#[cfg(test)]
#[derive(Default)]
struct Resources {
    active_workers: usize,
    peak_workers: usize,
    peak_blocks: usize,
    cross_deadline: bool,
    deadline_crossings: usize,
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
        }
        let this = Arc::new(Self {
            state: Mutex::new(state),
            dir,
            profile,
            boot,
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
        Ok(s.generation)
    }
    pub fn reserve(self: &Arc<Self>, profile: &str, boot: &str, generation: u64) -> Result<Value> {
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
                source_id: source.to_owned(),
                generation,
                kind: "spectrum",
                state: "running",
                processed_frames: 0,
                error: None,
                cancel: Arc::new(AtomicBool::new(false)),
            };
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
        if block.source.source_id != job.source_id
            || block.discontinuity
            || block.end_of_stream != (block.samples.len() as u64 == meta.frames)
        {
            return Err("recording_unavailable");
        }
        let mut fft = spectrum::Spectrum::new(false);
        let mut window = [0.0; spectrum::SIZE];
        let mut start = 0;
        let mut sequence = 0;
        let began = Instant::now();
        while start < meta.frames {
            let mut peak = [0f32; 128];
            let row_end = ((sequence + 1) * spectrum::RATE).min(meta.frames);
            while start < row_end {
                if job.cancel.load(Ordering::Acquire) {
                    return Err("cancelled");
                }
                for (n, value) in window.iter_mut().enumerate() {
                    let position = start + n as u64;
                    if position >= meta.frames {
                        *value = 0.0;
                        continue;
                    }
                    // The next FFT window overlaps the current one; retain only its 2048-sample working history.
                    if position < block.first_frame {
                        continue;
                    }
                    while position >= block.first_frame + block.samples.len() as u64 {
                        let next = input.next()?.ok_or("recording_unavailable")?;
                        #[cfg(test)]
                        self.observe_blocks(&[&block, &next]);
                        block = next;
                    }
                    *value = block.samples[(position - block.first_frame) as usize];
                }
                let amplitudes = fft.amplitudes(&window)?;
                for (p, a) in peak.iter_mut().zip(amplitudes) {
                    *p = p.max(a);
                }
                // Move overlapping samples before reading forward into the next block.
                window.copy_within(spectrum::HOP as usize.., 0);
                start += spectrum::HOP;
            }
            let due = Duration::from_secs_f64(row_end as f64 / 12000.0);
            loop {
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
                let remaining = due.saturating_sub(elapsed);
                if remaining.is_zero() {
                    break;
                }
                if job.cancel.load(Ordering::Acquire) {
                    return Err("cancelled");
                }
                std::thread::sleep(remaining.min(Duration::from_millis(20)));
            }
            let levels: Vec<u8> = peak.into_iter().map(spectrum::quantize).collect();
            let mut s = self.state.lock().unwrap();
            if job.cancel.load(Ordering::Acquire) {
                return Err("cancelled");
            }
            if s.job.as_ref().is_some_and(|j| {
                j.id == job.id && j.generation == job.generation && j.state == "running"
            }) {
                s.job.as_mut().unwrap().processed_frames = row_end;
                s.frame = Some(
                    json!({"v":1,"type":"spectrum.frame","data":{"boot_id":self.boot,"source_id":job.source_id,"job_id":job.id,"generation":job.generation,"sequence":sequence,"first_frame":sequence*12000,"end_frame":row_end,"levels":levels}}),
                );
            }
            sequence += 1;
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
