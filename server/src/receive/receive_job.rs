//! The jobs of receive: start, admission, the records of a live job, epochs and the end of a job.

use super::*;

pub(super) fn audio_error(error: source::SourceError) -> &'static str {
    match error {
        source::SourceError::Unavailable => "audio_unavailable",
        source::SourceError::UnsupportedFormat => "unsupported_audio",
        source::SourceError::FailedClose => "audio_close_failed",
        source::SourceError::CounterExhausted => "counter_exhausted",
        source::SourceError::Cancelled => "cancelled",
        _ => "audio_failed",
    }
}
pub(super) fn window_error(error: receive::WindowError) -> &'static str {
    match error {
        receive::WindowError::CounterExhausted => "counter_exhausted",
        receive::WindowError::DecodeLimit => "decode_limit",
        _ => "audio_failed",
    }
}
impl Recording {
    /// The live decoding job's identity (source, job, generation) and mode.
    pub(crate) fn live_identity(&self) -> Option<(String, String, u64, &'static str)> {
        let s = self.state.lock().unwrap();
        let j = s.job.as_ref().filter(|j| j.kind == "live")?;
        let l = s.live.as_ref()?;
        let source = l.source.as_ref()?.source_id.clone();
        matches!(l.mode, "ft8" | "ft4").then(|| (source, j.id.clone(), j.generation, l.mode))
    }
    /// Retained result records of the current live job with sequence >= `after` (all
    /// retained ones when `identity` is not the current job).
    pub(crate) fn live_records_after(
        &self,
        identity: Option<&(String, String, u64)>,
        after: u64,
    ) -> Option<LiveRecords> {
        let (source, job, generation, mode) = self.live_identity()?;
        let current = (source, job, generation);
        let from = if identity == Some(&current) { after } else { 0 };
        let s = self.state.lock().unwrap();
        let l = s.live.as_ref()?;
        let skip = from.saturating_sub(l.first_sequence) as usize;
        let records = l
            .records
            .iter()
            .skip(skip)
            .map(|(r, _)| r.clone())
            .collect();
        Some((current, mode, records))
    }
    /// One retained live result record by its full identity.
    pub(crate) fn live_record(
        &self,
        source: &str,
        job: &str,
        generation: u64,
        sequence: u64,
    ) -> Option<(Value, &'static str)> {
        let (s_id, j_id, g, mode) = self.live_identity()?;
        if s_id != source || j_id != job || g != generation {
            return None;
        }
        let s = self.state.lock().unwrap();
        let l = s.live.as_ref()?;
        if sequence < l.first_sequence {
            return None;
        }
        l.records
            .get((sequence - l.first_sequence) as usize)
            .map(|(r, _)| (r.clone(), mode))
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
        let started = self.receive_start_selected(
            profile,
            boot,
            generation,
            device.clone(),
            mode,
            StartGuard::Profile(revision),
        )?;
        let band = self.state.lock().unwrap().operating.nominal.band;
        self.remember_receive(mode, band, &device);
        Ok(started)
    }
    pub(super) fn receive_start_selected(
        self: &Arc<Self>,
        profile: &str,
        boot: &str,
        generation: u64,
        device: String,
        mode: &'static str,
        guard: StartGuard,
    ) -> Result<Value> {
        self.reap_receive();
        // FR-023: a native profile receives from its own confirmed DAX stream through the
        // same live source, converter and receive owner as an audio device.
        if let Some(session) = self.flex.get() {
            if !session.ready() {
                return Err("radio_unavailable");
            }
            let input = session.clone().input().map_err(audio_error)?;
            return self
                .receive_start_checked(profile, boot, generation, device, mode, input, guard);
        }
        let inputs = self.inputs.get().ok_or("audio_unavailable")?;
        let input = inputs.open(&device).map_err(audio_error)?;
        self.receive_start_checked(profile, boot, generation, device, mode, input, guard)
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
            if matches!(mode, "ft4" | "ft8") {
                s.operating_mode = mode;
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
                capture_drift: None,
                clock_correction: 0,
                publication_error: None,
                level: (0.0, 0, None, None),
                loss_epochs: 0,
                last_loss: None,
            });
        }
        self.sync_transmit_mode();
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
        let worker = self.spawner.spawn(Some("station-receive"), Box::new(run))?;
        self.state.lock().unwrap().live_worker = Some(worker);
        Ok(())
    }
    pub(super) fn reap_receive(&self) {
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
        self.files.id().map_err(|_| "storage_unavailable")
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
            s.detail_recent.clear();
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
        self.forget_receive();
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
    pub(super) fn publish_decode(
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
            || !(decoder::DECODE_BAND_LOW_HZ..=decoder::DECODE_BAND_HIGH_HZ)
                .contains(&decode.frequency_hz)
            || decode
                .snr_db
                .is_some_and(|v| !v.is_finite() || !(-SNR_LIMIT_DB..=SNR_LIMIT_DB).contains(&v))
        {
            l.publication_error = Some("decode_limit");
            return Err(decoder::DecodeError::DecodeLimit);
        }
        // HashResolution: fill hashed calls in from the calls heard and sent so far, then
        // learn this record's calls.
        let resolved;
        let decode = {
            let mut hashes = self.hashes.lock().unwrap_or_else(|p| p.into_inner());
            let payload = hashes.resolve(&decode.payload);
            hashes.learn(&payload);
            if payload == decode.payload {
                decode
            } else {
                resolved = decoder::Decode {
                    payload,
                    ..decode.clone()
                };
                &resolved
            }
        };
        let mut value =
            serde_json::to_value(decode).map_err(|_| decoder::DecodeError::DecodeLimit)?;
        let drift = l.capture_drift.map_or(0, |(d, _)| d);
        let timing = relative_decode_timing(
            l.timing.as_ref(),
            l.mode,
            decode.start_frame,
            drift + l.clock_correction,
        );
        // The air estimate takes DT against the uncorrected system clock, so the
        // correction it leads to never feeds back into it.
        if let (Some(clock), Some(from), Some((_, raw))) = (
            self.clock.get(),
            decode.payload.fields.as_ref().and_then(air::sender),
            relative_decode_timing(l.timing.as_ref(), l.mode, decode.start_frame, drift),
        ) {
            clock
                .station
                .observe(from, (raw * 1000.0).round() as i64, decode.snr_db);
        }
        value["period_start_utc"] = json!(timing.as_ref().map(|(period, _)| period));
        value["dt_seconds"] = json!(timing.map(|(_, dt)| dt));
        value
            .as_object_mut()
            .ok_or(decoder::DecodeError::DecodeLimit)?
            .insert("sequence".into(), json!(l.next_sequence));
        let size = serde_json::to_vec(&value)
            .map_err(|_| decoder::DecodeError::DecodeLimit)?
            .len();
        if size > RECORD_MAX_BYTES {
            return Err(decoder::DecodeError::DecodeLimit);
        }
        while l.records.len() >= KEPT_RECORDS || l.record_bytes + size > KEPT_MI_B * 1024 * 1024 {
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
impl LiveWorker {
    pub(super) fn new(
        owner: Arc<Recording>,
        job: Job,
        input: Box<dyn LiveInput>,
        mode: &str,
    ) -> Self {
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
            clock: ClockTracker::default(),
            air: 0,
        }
    }
    pub(super) fn current(&self) -> bool {
        !self.job.cancel.load(Ordering::Acquire)
    }
    pub(super) fn run(mut self, mut result: Result<()>) {
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
    pub(super) fn epoch(&mut self, p: source::EpochProposal) -> Result<()> {
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
        s.detail_recent.clear();
        s.latest_decode = None;
        s.decode_counter = 0;
        let l = s.live.as_mut().ok_or("state_conflict")?;
        l.clear_context();
        // Count rotations only: an initial epoch replaces nothing, whatever its trigger.
        if self.epoch_seen && p.reason == "capture_loss" {
            l.loss_epochs = l.loss_epochs.saturating_add(1).min(source::MAX_COUNTER);
            l.last_loss = Some(p.trigger);
            eprintln!(
                "receive: unknown-loss source epoch {} trigger={} native_frame={} job={}",
                l.loss_epochs, p.trigger, p.first_device_frame, self.job.id
            );
        }
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
        s.detail_recent.clear();
        let l = s.live.as_mut().ok_or("state_conflict")?;
        l.source = Some(descriptor.clone());
        l.timing = Some(timing.clone());
        drop(s);
        let mode = self.mode.unwrap_or(decoder::Mode::Ft8);
        self.air = self.owner.clock_correction();
        let schedule = window_schedule(&timing, mode, self.air).unwrap_or_default();
        self.clock = ClockTracker::default();
        self.window = Some(
            receive::WindowBuffer::new(mode, descriptor)
                .map_err(window_error)?
                .with_schedule(&schedule),
        );
        self.spectrum.reset(0);
        self.reset = true;
        self.epoch_seen = true;
        Ok(())
    }
}
impl Recording {
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
            s.detail_recent.clear();
            s.job = Some(job.clone());
        }
        let this = self.clone();
        let worker_job = job.clone();
        drop(
            self.spawner
                .spawn(None, Box::new(move || this.run(worker_job, meta)))
                .expect("failed to spawn thread"),
        );
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
        s.detail_recent.clear();
        Ok(value)
    }
    fn run(&self, job: Job, meta: Metadata) {
        let result = self.process(&job, &meta);
        self.release(job, meta, result);
    }
    pub(super) fn release(&self, job: Job, meta: Metadata, result: Result<()>) {
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
}
