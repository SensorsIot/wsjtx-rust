//! WstxTransmit::TransmitWire and the station hardware of the transmit owner: PTT via
//! the CL-022 lifecycle's single CI-V actor (explicit transmit path, never from the
//! lifecycle itself), audio via the profile's exact output device.
use crate::*;
use axum::extract::RawQuery;
use recording_http::{authorize, parse};
use selection_http::{empty, error};
use std::collections::VecDeque;
use wstx_rust::radio_control::actor::Actor;
use wstx_rust::transmit::ClockState;
use wstx_rust::transmit::air::StationClock;
use wstx_rust::transmit::clock::Measurement;
use wstx_rust::transmit::service::{
    self as tx, AudioError, AudioPoll, Capability, Context, HaltState, Hardware, Outcome, Program,
    PttError, Service, View,
};

/// Station facts published by the CL-022 tick (store -> authorization -> recording).
#[derive(Default)]
pub(crate) struct Inputs {
    /// control.mode cat, control.ptt cat and an exact audio.output_device.
    configured: bool,
    output_device: Option<String>,
    /// The current CL-022 safety revision while the automatic CAT gate is eligible.
    safety_revision: Option<u64>,
    actor: Option<Arc<Actor>>,
}
type Stopper = Arc<dyn Fn() + Send + Sync>;
pub(crate) struct StationHardware {
    inputs: Arc<Mutex<Inputs>>,
    #[cfg(windows)]
    output: Option<wstx_rust::playback::Output>,
    slot: Arc<Mutex<Option<Stopper>>>,
    abort: Arc<std::sync::atomic::AtomicBool>,
    origin: Instant,
    clock: Arc<StationClock>,
}
impl Hardware for StationHardware {
    fn attach_abort(&mut self, abort: Arc<std::sync::atomic::AtomicBool>) {
        self.abort = abort;
    }
    fn monotonic_ms(&self) -> i64 {
        self.origin.elapsed().as_millis() as i64
    }
    fn now_utc_ms(&self) -> i64 {
        // #43: station UTC is the system clock plus the clock-from-the-air correction
        // (0 on the NTP basis); the system clock itself is never set.
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0)
            + self.clock.correction_ms()
    }
    fn clock(&self) -> ClockState {
        // WstxTransmit::TransmitClock and AirClock: only reads the latest SNTP
        // measurement and air estimate, combined by the profile's clock source.
        self.clock.state()
    }
    fn clock_measurement(&self) -> Option<Measurement> {
        self.clock.ntp().latest()
    }
    fn context(&self) -> Context {
        let i = self.inputs.lock().unwrap_or_else(|p| p.into_inner());
        let snapshot = i.actor.as_ref().and_then(|a| a.snapshot().ok());
        let ready = snapshot
            .as_ref()
            .is_some_and(|s| s.state == wstx_rust::radio_control::State::Ready);
        // Only a fresh confirmed 1C 00 readback of a ready connection counts.
        let radio_transmitting = snapshot
            .as_ref()
            .filter(|s| {
                s.state == wstx_rust::radio_control::State::Ready && s.facts.rx_tx.confirmed
            })
            .and_then(|s| s.facts.rx_tx.value);
        if !i.configured {
            return Context {
                capability: Capability::Unsupported,
                safety_revision: None,
                radio_transmitting,
            };
        }
        Context {
            capability: if ready && i.safety_revision.is_some() {
                Capability::Available
            } else {
                Capability::Unavailable
            },
            safety_revision: i.safety_revision,
            radio_transmitting,
        }
    }
    fn ptt(&mut self, on: bool) -> Result<(), PttError> {
        let actor = self
            .inputs
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .actor
            .clone()
            .ok_or(PttError::Unavailable)?;
        if on {
            tx::actor_ptt_abortable(&actor, Duration::from_secs(1), &self.abort)
        } else {
            tx::actor_ptt(&actor, false, Duration::from_secs(1))
        }
    }
    #[cfg(windows)]
    fn open_audio(&mut self) -> Result<(), AudioError> {
        self.stop_audio();
        let id = self
            .inputs
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .output_device
            .clone()
            .ok_or(AudioError::Unavailable)?;
        let output = wstx_rust::playback::Output::open_abortable(&id, &self.abort)
            .map_err(|_| AudioError::Unavailable)?;
        *self.slot.lock().unwrap_or_else(|p| p.into_inner()) = Some(output.stopper());
        self.output = Some(output);
        Ok(())
    }
    #[cfg(not(windows))]
    fn open_audio(&mut self) -> Result<(), AudioError> {
        Err(AudioError::Unavailable)
    }
    #[cfg(windows)]
    fn play(&mut self, program: Program) -> Result<(), AudioError> {
        use wstx_rust::playback::Source;
        let output = self.output.as_ref().ok_or(AudioError::Unavailable)?;
        let source = match program {
            Program::Waveform { samples, skip } => Source::Samples { samples, skip },
            Program::Tone { hz } => Source::Tone { hz },
        };
        output
            .play(source, tx::PLAYBACK_SCALE)
            .map_err(|_| AudioError::DeviceLost)
    }
    #[cfg(not(windows))]
    fn play(&mut self, _: Program) -> Result<(), AudioError> {
        Err(AudioError::Unavailable)
    }
    fn poll_audio(&mut self) -> AudioPoll {
        #[cfg(windows)]
        {
            use wstx_rust::playback::OutputState;
            match self.output.as_ref().map(|o| o.state()) {
                Some(OutputState::Playing) => AudioPoll::Playing,
                Some(OutputState::Finished) => AudioPoll::Finished,
                Some(OutputState::Failed(_)) => AudioPoll::Failed(AudioError::DeviceLost),
                _ => AudioPoll::Idle,
            }
        }
        #[cfg(not(windows))]
        AudioPoll::Idle
    }
    fn stop_audio(&mut self) {
        *self.slot.lock().unwrap_or_else(|p| p.into_inner()) = None;
        #[cfg(windows)]
        if let Some(mut output) = self.output.take() {
            output.stop();
        }
    }
    fn audio_stopper(&self) -> Stopper {
        let slot = self.slot.clone();
        Arc::new(move || {
            if let Some(stop) = slot.lock().unwrap_or_else(|p| p.into_inner()).as_ref() {
                stop();
            }
        })
    }
}

pub(crate) struct Station {
    inputs: Arc<Mutex<Inputs>>,
    /// The station clock (#43); None for injected test hardware.
    clock: Option<Arc<StationClock>>,
    slot: Arc<Mutex<Option<Stopper>>>,
    pub(crate) service: Service<Box<dyn Hardware>>,
    receipts: Mutex<VecDeque<(String, Value, Value)>>,
}
impl Station {
    /// `clock` is the process's station clock (tests pass one whose SNTP monitor never
    /// measures).
    pub(crate) fn start(clock: Arc<StationClock>) -> std::io::Result<Arc<Self>> {
        let inputs = Arc::new(Mutex::new(Inputs::default()));
        let slot = Arc::new(Mutex::new(None));
        let hardware = StationHardware {
            inputs: inputs.clone(),
            #[cfg(windows)]
            output: None,
            slot: slot.clone(),
            abort: Arc::new(std::sync::atomic::AtomicBool::new(false)),
            origin: Instant::now(),
            clock: clock.clone(),
        };
        Ok(Arc::new(Self {
            inputs,
            clock: Some(clock),
            slot,
            service: Service::start(Box::new(hardware) as Box<dyn Hardware>)?,
            receipts: Mutex::new(VecDeque::new()),
        }))
    }
    /// Shares the station's call hash table with the transmit owner (CL-024-01).
    pub(crate) fn attach_hashes(&self, hashes: Arc<Mutex<wstx_rust::decoder::HashTable>>) {
        self.service.with(|c| c.attach_hashes(hashes));
    }
    /// The call hash table the transmit owner feeds, if attached.
    #[cfg(test)]
    pub(crate) fn hash_table(&self) -> Option<Arc<Mutex<wstx_rust::decoder::HashTable>>> {
        self.service.with(|c| c.hash_table().cloned())
    }
    /// Test seam: the same station with injected hardware (virtual devices, no radio).
    #[cfg(test)]
    pub(crate) fn start_with(hardware: Box<dyn Hardware>) -> std::io::Result<Arc<Self>> {
        Ok(Arc::new(Self {
            inputs: Arc::new(Mutex::new(Inputs::default())),
            clock: None,
            slot: Arc::new(Mutex::new(None)),
            service: Service::start(hardware)?,
            receipts: Mutex::new(VecDeque::new()),
        }))
    }
    /// WstxTransmit::ExitRelease for process exit and panics: stop output and, only if
    /// the CI-V switch may be keyed, send one off-only release bounded to 500 ms. Uses
    /// try_lock only, so a panicking holder cannot deadlock it.
    pub(crate) fn emergency_release(&self) {
        if let Ok(slot) = self.slot.try_lock()
            && let Some(stop) = slot.as_ref()
        {
            stop();
        }
        let actor = self.inputs.try_lock().ok().and_then(|i| i.actor.clone());
        if let Some(actor) = actor
            && actor.ptt_indeterminate()
        {
            let _ = actor.ptt(false, Instant::now() + Duration::from_millis(500));
        }
    }
    /// Called by the CL-022 tick with the current profile, gate and actor.
    pub(crate) fn update(
        &self,
        document: &profile::Document,
        gate: &crate::cat_lifecycle::Gate,
        actor: Option<Arc<Actor>>,
    ) {
        let c = &document.control;
        if let Some(clock) = &self.clock {
            // #43: the station's own decodes never count for the clock from the air.
            clock.set_own_call(&document.callsign);
        }
        let mut i = self.inputs.lock().unwrap_or_else(|p| p.into_inner());
        i.configured = c.mode == "cat" && c.ptt == "cat" && document.audio.output_device.is_some();
        i.output_device = document.audio.output_device.clone();
        i.safety_revision = match gate {
            crate::cat_lifecycle::Gate::Eligible { key, .. } => Some(key.safety_revision),
            _ => None,
        };
        i.actor = actor;
    }
}

fn name<T: std::fmt::Debug>(value: T) -> String {
    // CamelCase variant names map to the wire's snake_case.
    let text = format!("{value:?}");
    let mut out = String::new();
    for (i, c) in text.chars().enumerate() {
        if c.is_ascii_uppercase() {
            if i > 0 {
                out.push('_');
            }
            out.push(c.to_ascii_lowercase());
        } else {
            out.push(c);
        }
    }
    out
}
fn outcome(o: &Outcome) -> Value {
    json!({"outcome_sequence":o.outcome_sequence,"request_sequence":o.request_sequence,"kind":name(o.kind),
        "refusal":o.refusal.map(name),"failure":o.failure.map(name),"audio_start_utc_ms":o.audio_start_utc_ms})
}
fn measurement(m: &Measurement) -> Value {
    json!({"server":m.server,"offset_ms":m.offset_ms,"round_trip_ms":m.round_trip_ms,
        "age_ms":u64::try_from(m.taken.elapsed().as_millis()).unwrap_or(u64::MAX)})
}
pub(crate) fn view_json(r: &recording::Recording, v: &View) -> Value {
    let halt = match v.halt_state {
        HaltState::Idle => "idle",
        HaltState::Pending => "pending",
        HaltState::Stopped => "stopped",
    };
    let recent = v
        .outcomes
        .iter()
        .rev()
        .take(8)
        .rev()
        .map(outcome)
        .collect::<Vec<_>>();
    json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,
        "transmit":{"capability":name(v.capability),"arm_state":name(v.arm_state),"last_disarm_cause":name(v.last_disarm_cause),
            "tune":v.tune,"pending_sequence":v.pending_sequence,"last_text":v.last_text,"last_period_utc":v.last_period_utc_ms,
            "halt_state":halt,"refusal":v.refusal.map(name)},
        "ptt":name(v.ptt),"transmitting":v.transmitting,"clock":name(v.clock),
        "clock_measurement":v.clock_measurement.as_ref().map(measurement),
        "clock_source":r.clock.get().map_or("ntp",|c|c.station.source().name()),
        "clock_warning":r.clock.get().is_some_and(|c|c.station.view().warning).then_some("ntp_air_disagree"),
        "watchdog":{"tx_calls":v.tx_calls,"tx_remaining_calls":v.tx_remaining_calls,"tx_expired":v.tx_expired,
            "tune_seconds":v.tune_seconds,"tune_remaining_seconds":v.tune_remaining_seconds},
        "outcomes":recent,"startup_release":name(v.startup_release)})
}
fn station(r: &recording::Recording) -> Result<Arc<Station>, &'static str> {
    r.transmit.get().cloned().ok_or("not_found")
}
pub async fn snapshot(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, false).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    if let Err(e) = empty(query, body) {
        return error(e);
    }
    let s = match station(&r) {
        Ok(s) => s,
        Err(e) => return error(e),
    };
    let view = tokio::task::spawn_blocking(move || s.service.view()).await;
    match view {
        Ok(v) => Json(view_json(&r, &v)).into_response(),
        Err(_) => error("storage_unavailable"),
    }
}
fn keys(body: &Value, extra: &[&str]) -> Result<(), &'static str> {
    let object = body.as_object().ok_or("invalid_request")?;
    let base = ["v", "profile_id", "boot_id", "command_id"];
    if object.len() != base.len() + extra.len()
        || !base.iter().chain(extra).all(|k| object.contains_key(*k))
    {
        return Err("invalid_request");
    }
    Ok(())
}
fn envelope(
    body: &Value,
    r: &recording::Recording,
    boot_checked: bool,
) -> Result<String, &'static str> {
    let text = |k: &str| body.get(k).and_then(Value::as_str);
    let (Some(v), Some(profile_id), Some(boot_id), Some(command_id)) = (
        body.get("v").and_then(Value::as_u64),
        text("profile_id"),
        text("boot_id"),
        text("command_id"),
    ) else {
        return Err("invalid_request");
    };
    if !profile::valid_uuid(profile_id)
        || !profile::valid_uuid(boot_id)
        || !profile::valid_uuid(command_id)
    {
        return Err("invalid_request");
    }
    if v != 1 {
        return Err("unsupported_version");
    }
    if profile_id != r.profile {
        return Err("wrong_profile");
    }
    if boot_checked && boot_id != r.boot {
        return Err("state_conflict");
    }
    Ok(command_id.to_owned())
}
/// HaltTransmit: always admitted for the selected profile (no boot/revision check).
pub async fn halt(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, true).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    if query.is_some() {
        return error("invalid_request");
    }
    let body: Value = match parse(&headers, body) {
        Ok(v) => v,
        Err(e) => return error(e),
    };
    if let Err(e) = keys(&body, &[]) {
        return error(e);
    }
    let command = match envelope(&body, &r, false) {
        Ok(c) => c,
        Err(e) => return error(e),
    };
    let s = match station(&r) {
        Ok(s) => s,
        Err(e) => return error(e),
    };
    let id = command.clone();
    let state = tokio::task::spawn_blocking(move || s.service.halt(&id))
        .await
        .unwrap_or(HaltState::Pending);
    let state = match state {
        HaltState::Idle => "idle",
        HaltState::Pending => "pending",
        HaltState::Stopped => "stopped",
    };
    (
        StatusCode::ACCEPTED,
        Json(json!({"v":1,"command_id":command,"halt_state":state})),
    )
        .into_response()
}
type Run = Box<dyn FnOnce(&mut tx::Core<Box<dyn Hardware>>) -> Value + Send>;
fn safe(value: Option<&Value>) -> Option<u64> {
    value.and_then(Value::as_u64).filter(|n| *n <= tx::MAX_SAFE)
}
/// Exact action parameters -> a closure on the core; None for invalid parameters.
fn command(body: &Value, granted: bool) -> Result<Run, &'static str> {
    let action = body
        .get("action")
        .and_then(Value::as_str)
        .ok_or("invalid_request")?;
    let refusal = |r: Result<(), tx::TransmitRefusal>| json!({"accepted":r.is_ok(),"refusal":r.err().map(name)});
    Ok(match action {
        "arm" => {
            keys(body, &["action", "safety_revision"])?;
            let revision = safe(body.get("safety_revision"))
                .filter(|n| *n >= 1)
                .ok_or("invalid_request")?;
            Box::new(move |c| {
                if !granted {
                    return refusal(Err(tx::TransmitRefusal::NotAuthorized));
                }
                refusal(c.arm(revision))
            })
        }
        "disarm" => {
            keys(body, &["action"])?;
            Box::new(move |c| {
                c.disarm(tx::DisarmCause::Operator);
                refusal(Ok(()))
            })
        }
        "set_watchdogs" => {
            keys(body, &["action", "tx_calls", "tune_seconds"])?;
            let tx_calls = safe(body.get("tx_calls")).ok_or("invalid_request")?;
            let tune_seconds = safe(body.get("tune_seconds")).ok_or("invalid_request")?;
            if !(1..=99).contains(&tx_calls) || !(1..=300).contains(&tune_seconds) {
                return Err("out_of_range");
            }
            Box::new(move |c| {
                let _ = c.set_watchdogs(tx_calls as u32, tune_seconds as u32);
                c.activity();
                refusal(Ok(()))
            })
        }
        "tune" => {
            let enabled = body
                .get("enabled")
                .and_then(Value::as_bool)
                .ok_or("invalid_request")?;
            if enabled {
                keys(body, &["action", "enabled", "tx_offset_hz"])?;
            } else {
                keys(body, &["action", "enabled"])?;
            }
            let hz = if enabled {
                safe(body.get("tx_offset_hz")).ok_or("invalid_request")?
            } else {
                0
            };
            Box::new(move |c| {
                if enabled && !granted {
                    return refusal(Err(tx::TransmitRefusal::NotAuthorized));
                }
                refusal(c.set_tune(enabled, hz.min(u64::from(u32::MAX)) as u32))
            })
        }
        "request" => {
            keys(
                body,
                &[
                    "action",
                    "request_sequence",
                    "mode",
                    "period_start_utc_ms",
                    "message_text",
                    "tx_offset_hz",
                ],
            )?;
            let sequence = safe(body.get("request_sequence")).ok_or("invalid_request")?;
            let mode = match body.get("mode").and_then(Value::as_str) {
                Some("ft8") => decoder::Mode::Ft8,
                Some("ft4") => decoder::Mode::Ft4,
                _ => return Err("invalid_request"),
            };
            let period = safe(body.get("period_start_utc_ms")).ok_or("invalid_request")?;
            let text = body
                .get("message_text")
                .and_then(Value::as_str)
                .ok_or("invalid_request")?;
            if text.chars().count() > 64 {
                return Err("invalid_request");
            }
            let hz = safe(body.get("tx_offset_hz")).ok_or("invalid_request")?;
            let request = tx::Request {
                contact_id: None,
                request_sequence: sequence,
                mode,
                period_start_utc_ms: period as i64,
                message_text: text.to_owned(),
                tx_offset_hz: hz.min(u64::from(u32::MAX)) as u32,
            };
            Box::new(move |c| {
                c.activity();
                outcome(&c.submit(request))
            })
        }
        _ => return Err("invalid_request"),
    })
}
/// POST /transmit/command: arm, disarm, request, tune, set_watchdogs. Retained
/// command_id with the identical body returns the same result without effect.
pub async fn execute(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, true).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    if query.is_some() {
        return error("invalid_request");
    }
    let body: Value = match parse(&headers, body) {
        Ok(v) => v,
        Err(e) => return error(e),
    };
    let command_id = match envelope(&body, &r, true) {
        Ok(c) => c,
        Err(e) => return error(e),
    };
    // Transmit authority needs a current CL-022 grant (selected HTTPS profile).
    let granted = matches!(
        authorization_http::operating_access_async(&headers, &app).await,
        Ok(Some(_))
    );
    let s = match station(&r) {
        Ok(s) => s,
        Err(e) => return error(e),
    };
    if let Some((_, prior, result)) = s
        .receipts
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .iter()
        .find(|(id, _, _)| *id == command_id)
    {
        return if *prior == body {
            Json(result.clone()).into_response()
        } else {
            error("state_conflict")
        };
    }
    let run = match command(&body, granted) {
        Ok(f) => f,
        Err(e) => return error(e),
    };
    let station = s.clone();
    let result = match tokio::task::spawn_blocking(move || station.service.with(run)).await {
        Ok(v) => v,
        Err(_) => return error("storage_unavailable"),
    };
    let reply = json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"command_id":command_id,"result":result});
    let mut receipts = s.receipts.lock().unwrap_or_else(|p| p.into_inner());
    if receipts.len() == 16 {
        receipts.pop_front();
    }
    receipts.push_back((command_id, body, reply.clone()));
    Json(reply).into_response()
}
