//! The stored recording of a profile: its WAV form, its samples and its import.

use super::*;

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
    if bytes > FILE_BYTES {
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
        if chunks > IMPORT_MAX_RIFF_CHUNKS {
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
                unsupported = word(0) != 1 || word(2) != 1 || dword(4) != RATE_HZ || word(14) != 16;
                if !unsupported && (word(12) != 2 || dword(8) != RATE_HZ * 2) {
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
    if frames > IMPORT_MAX_FRAMES {
        return Err("recording_limit");
    }
    Ok(Wave {
        offset,
        frames,
        bytes,
    })
}
impl SourceFile {
    pub fn open(path: &Path, source: Arc<SourceDescriptor>) -> Result<Self> {
        let mut file = File::open(path).map_err(|_| "recording_unavailable")?;
        let wave = validate(&mut file).map_err(|_| "recording_unavailable")?;
        if source.schema_version != 1
            || source.rate_hz != RATE_HZ
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
impl ReplaySource for SourceFile {
    fn next(&mut self) -> Result<Option<SampleBlock>> {
        SourceFile::next(self)
    }
}
impl ReplaySources for WavFiles {
    fn open(&self, path: &Path, source: Arc<SourceDescriptor>) -> Result<Box<dyn ReplaySource>> {
        Ok(Box::new(SourceFile::open(path, source)?))
    }
}
impl Recording {
    pub(super) fn cleanup(&self, pending: Option<&str>) -> Result<()> {
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
        for entry in io(self.files.list(&self.dir))? {
            let entry = io(entry)?;
            let name = entry.name.to_string_lossy();
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
            if entry.is_file {
                io(self.files.remove(&self.dir.join(&entry.name)))?;
            } else {
                return Err("storage_unavailable");
            }
        }
        Ok(())
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
    pub(super) fn finish_cleanup(&self, id: String) {
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
                let limit = if i.state == "reserved" {
                    RESERVATION_MS
                } else {
                    UPLOAD_IDLE_MS
                };
                if matches!(i.state, "reserved" | "receiving")
                    && (i.touched.elapsed() >= Duration::from_millis(limit)
                        || i.started.elapsed() >= Duration::from_millis(UPLOAD_TOTAL_MS))
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
        let mut file = io(self
            .files
            .create(&path, profile::Open::Append { create: start == 0 }))?;
        io(file.write(body))?;
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
        io(file.flush())?;
        drop(file);
        let wave = validate(&mut io(File::open(&path))?)?;
        let metadata = Metadata {
            schema_version: 1,
            recording_id: id.to_owned(),
            file_bytes: wave.bytes,
            frames: wave.frames,
            rate_hz: RATE_HZ,
        };
        write_json(&*self.files, &self.path(id, "json"), &metadata)?;
        write_json(
            &*self.files,
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
        io(self.files.replace(
            &self.dir.join("manifest.tmp"),
            &self.dir.join("current.json"),
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
}
