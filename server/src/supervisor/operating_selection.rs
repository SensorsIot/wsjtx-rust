//! The operating selection: band and mode, the readback and the selection commands.

use super::*;

impl Recording {
    /// WstxOperatingSelection::OperatingModeRule: the mode of the last started ft4/ft8 live job
    /// or admitted operating mode selection (persists across a receive stop).
    pub(crate) fn operating_mode(&self) -> &'static str {
        self.state.lock().unwrap().operating_mode
    }
    /// The band of the operating selection (nominal), if any (strategy band facts).
    pub(crate) fn operating_band(&self) -> Option<&'static str> {
        self.state.lock().unwrap().operating.nominal.band
    }
    /// The nominal dial frequency of the operating selection (Hz), if any.
    pub(crate) fn operating_nominal_hz(&self) -> Option<u64> {
        self.state.lock().unwrap().operating.nominal.nominal_hz
    }
    /// Gives the transmit owner the station's operating mode (WstxTransmitControl::StationMode).
    /// Called after every change, never under the station mutex.
    pub(crate) fn sync_transmit_mode(&self) {
        let mode = match self.operating_mode() {
            "ft4" => decoder::Mode::Ft4,
            _ => decoder::Mode::Ft8,
        };
        if let Some(t) = self.transmit.get() {
            t.service.with(|c| c.set_station_mode(Some(mode)));
        }
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
    /// WstxOperatingSelection::ReadbackRule: while the selection band
    /// is unknown, the lifecycle's Ready connection with a confirmed fresh dial that
    /// exactly equals the station operating mode's preferred entry of one band becomes
    /// the selection. Read-only: no CAT bytes, no receive restart, no revision advance,
    /// never replaces a known selection and never infers the mode.
    pub(super) fn adopt_readback_selection(&self, profile_revision: u64) {
        let mut s = self.state.lock().unwrap();
        if s.operating.nominal.band.is_some()
            || s.operating.active()
            || s.operating.profile_revision != profile_revision
        {
            return;
        }
        let mode = s.operating_mode;
        let o = &mut s.operating;
        let dial = selection::bound_snapshot(o.radio.cached.as_ref(), profile_revision)
            .filter(|v| {
                v.state == wstx_rust::radio_control::State::Ready
                    && v.authority.profile_id == self.profile
                    && v.authority.boot_id == self.boot
                    && v.authority.connection_generation == o.radio.generation
            })
            .and_then(|v| {
                v.facts
                    .frequency
                    .confirmed
                    .then_some(v.facts.frequency.value)
            })
            .flatten();
        let Some(dial) = dial else {
            return;
        };
        let mut bands = selection::BANDS
            .into_iter()
            .filter(|b| selection::frequency(mode, b) == Some(dial));
        let (Some(band), None) = (bands.next(), bands.next()) else {
            return;
        };
        o.nominal = selection::Nominal {
            mode,
            band: Some(band),
            nominal_hz: Some(dial),
            origin: "cat_readback",
            confirmed_command_id: None,
        };
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
        let radio = match self.flex.get() {
            Some(session) => crate::flex_http::selection_radio(&**session, o.boot_at),
            None => json!({"connection_generation":r.generation,
                "state":bound.as_ref().map(|v|selection::state_name(v.state)).unwrap_or(if r.connecting{"connecting"}else if r.error.is_some(){"unavailable"}else{"closed"}),
                "error":bound.as_ref().and_then(|v|v.last_error.map(selection::radio_error)).or(r.error),
                "observations":selection::facts(bound.as_ref(),o.boot_at)}),
        };
        let mut value = json!({"v":1,"profile_id":self.profile,"boot_id":self.boot,"profile_revision":o.profile_revision,
            "generation":generation,"operating_revision":o.revision,"control":if self.flex.get().is_some(){"native"}else if cat{"cat"}else{"manual"},
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
    pub(super) fn selection_preflight(
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
        // A band change keeps the station's operating mode (WSJT-X keeps the mode on a
        // band change), so an FT4 contact survives it.
        let mode = intent.mode.unwrap_or(s.operating_mode);
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
        if self.flex.get().is_some_and(|session| !session.ready()) {
            return Err("radio_unavailable");
        }
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
                    .reserve_transition(Instant::now() + selection::LEASE_WAIT)
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
            s.detail_recent.clear();
            // The station's operating mode follows an admitted selection at once, so the
            // transmit owner never keys the old mode on the new dial.
            s.operating_mode = operation.requested.mode;
            s.operating.operation = Some(operation.clone());
        }
        self.sync_transmit_mode();
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
        // FR-023: the native session reads first, tunes only its own slice on a difference
        // and returns once the radio's slice status confirms the frequency.
        let native_applied = if let Some(session) = self.flex.get() {
            if let Err(error) = session.tune(
                op.requested.nominal_hz,
                Instant::now() + Duration::from_secs(5),
                &op.cancelled,
            ) {
                self.selection_failed(&op, error.selection_code(), "failed");
                return;
            }
            true
        } else {
            false
        };
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
                // CL-044-10: the managed AGC on each FT8/FT4 selection.
                if matches!(op.requested.mode, "ft8" | "ft4") {
                    crate::radio_agc::on_selection(
                        &self,
                        actor,
                        snapshot.authority.connection_generation,
                    );
                }
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
                origin: if native_applied {
                    "native_readback"
                } else if cat_applied {
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
            device.clone(),
            op.requested.mode,
            StartGuard::Selection(op.revision),
        ) {
            self.selection_failed(&op, error, "failed");
            return;
        }
        self.remember_receive(op.requested.mode, Some(op.requested.band), &device);
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
            s.detail_recent.clear();
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
