#![forbid(unsafe_code)]
//! #44 CL-044-12/13 the Tx audio level: a digital attenuation of our Tx audio, stored per
//! radio profile in its own file (a level change never advances the profile revision,
//! which would reconnect CAT). "Set level" is the default way to set it: it runs Tune,
//! steps the level up until the radio's ALC first rises, backs off one step, stores it
//! and stops Tune. A manual level exists only for a radio that reports no ALC over CI-V.
//! Meters are read under the transmit hold (`Actor::read_meters`); the state is pushed to
//! the WebSocket peers as `radio.tx_level` on change (no polling). In normal operation
//! (CL-044-14) one burst in the middle of each transmission corrects the level by at most
//! one step for the next transmission and reports persistent trouble in the error field.
use crate::recording::Recording;
use crate::*;
use axum::extract::RawQuery;
use recording_http::{authorize, parse};
use selection_http::error;
use transmit_http::{envelope, keys, name};
use wstx_rust::radio_control::setup::Meters;
use wstx_rust::transmit::service::{ArmState, DisarmCause, LEVEL_MAX_DB, LEVEL_MIN_DB};

pub(crate) const LEVEL_FILE: &str = "tx-level.json";
const LEVEL_FILE_MAX: u64 = 256;
/// Where the assistant starts: well below any ALC on a radio with a sane USB MOD level.
pub(crate) const ASSISTANT_START_DB: i32 = -30;
/// Tune level settle time before each meter read of the assistant.
#[cfg(not(test))]
const SETTLE: Duration = Duration::from_millis(400);
#[cfg(test)]
const SETTLE: Duration = Duration::from_millis(5);
/// Bound of one meter read (all its frames).
const METER_READ: Duration = Duration::from_millis(400);
/// Meter display while Tune runs outside the assistant.
const TUNE_READ_EVERY: Duration = Duration::from_secs(1);
/// IC-7300 SWR meter (15 12): 0120 is SWR 3.0 (Full Manual section 19). A clear fault.
pub(crate) const SWR_FAULT_RAW: u16 = 120;

/// 15 11 Po: 0000 = 0 %, 0143 = 50 %, 0213 = 100 % (IC-7300 Full Manual section 19).
pub(crate) fn po_percent(raw: u16) -> u32 {
    let raw = u32::from(raw);
    if raw <= 143 {
        raw * 50 / 143
    } else {
        50 + (raw - 143) * 50 / 70
    }
}
/// 15 12 SWR, ten times the ratio: 0000 = 1.0, 0048 = 1.5, 0080 = 2.0, 0120 = 3.0.
pub(crate) fn swr_x10(raw: u16) -> u32 {
    let raw = u32::from(raw);
    match raw {
        0..=48 => 10 + raw * 5 / 48,
        49..=80 => 15 + (raw - 48) * 5 / 32,
        _ => 20 + (raw - 80) / 4,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Step {
    Up(i32),
    /// The level to store, and the assistant's result.
    Done(i32, &'static str),
    Stop(&'static str),
}
/// One assistant decision from the meters read at `level`.
pub(crate) fn assistant_step(level: i32, meters: &Meters, limit: Option<u8>) -> Step {
    let Some(alc) = meters.alc else {
        return Step::Stop("no_alc");
    };
    if meters.swr.is_some_and(|s| s >= SWR_FAULT_RAW) {
        return Step::Stop("high_swr");
    }
    let over = limit
        .zip(meters.po)
        .is_some_and(|(l, p)| po_percent(p) > u32::from(l));
    if alc > 0 || over {
        Step::Done((level - 1).max(LEVEL_MIN_DB), "stored")
    } else if level >= LEVEL_MAX_DB {
        Step::Done(LEVEL_MAX_DB, "max_without_alc")
    } else {
        Step::Up(level + 1)
    }
}

/// CL-044-14 ALC above this lowers the level. Onset reads 4-7 and ALC moves about 6 per dB
/// (live 2026-11-06), so the level one step above Set level's stop stays inside it.
pub(crate) const ALC_LIMIT_RAW: u16 = 10;
/// CL-044-14 ALC at or above this counts for the warning: half the ALC zone (0120 is its
/// top). Lowering from the limit up to here is routine and shows no entry.
pub(crate) const ALC_HIGH_RAW: u16 = 60;
/// CL-044-14 SWR 2.0: a warning when it persists; SWR_FAULT_RAW stops transmitting.
pub(crate) const SWR_HIGH_RAW: u16 = 80;
/// CL-044-14 consecutive transmissions before an entry appears in the error field.
pub(crate) const PERSISTENT: u8 = 3;
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct Counts {
    alc_high: u8,
    po_low: u8,
    swr_high: u8,
    /// The last reading stepped the level up.
    raised: bool,
    /// A level lowered right after its step up: no step up reaches it again, so a reading
    /// of 0 one step below a reading above the limit settles, while any other lowering
    /// keeps following the drive. Until a stored Set level, a changed profile power or a
    /// restart.
    ceiling: Option<i32>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Verdict {
    pub level_db: i32,
    pub fault: bool,
    pub warnings: Vec<&'static str>,
}
/// One transmission's judgement: at most one level step, never above the profile power.
/// Po is judged against the profile power only; without one it is neither low nor over.
pub(crate) fn monitor_step(
    level: i32,
    meters: &Meters,
    limit: Option<u8>,
    counts: &mut Counts,
) -> Verdict {
    let po = limit
        .zip(meters.po)
        .map(|(l, p)| (po_percent(p), u32::from(l)));
    let alc_high = meters.alc.is_some_and(|a| a >= ALC_HIGH_RAW);
    let over = po.is_some_and(|(p, l)| p > l);
    let low = po.is_some_and(|(p, l)| p * 5 < l * 4);
    let very_low = po.is_some_and(|(p, l)| p * 2 < l);
    let swr_high = meters.swr.is_some_and(|s| s >= SWR_HIGH_RAW);
    let count = |n: &mut u8, on: bool| *n = if on { n.saturating_add(1) } else { 0 };
    count(&mut counts.alc_high, alc_high);
    count(&mut counts.po_low, very_low);
    count(&mut counts.swr_high, swr_high);
    let raised = std::mem::take(&mut counts.raised);
    let level_db = if meters.alc.is_some_and(|a| a > ALC_LIMIT_RAW) || over {
        if raised {
            counts.ceiling = Some(level);
        }
        (level - 1).max(LEVEL_MIN_DB)
    } else if meters.alc == Some(0) && low && counts.ceiling.is_none_or(|c| level + 1 < c) {
        counts.raised = true;
        (level + 1).min(LEVEL_MAX_DB)
    } else {
        level
    };
    let mut warnings = Vec::new();
    for (entry, n) in [
        ("alc_high", counts.alc_high),
        ("po_low", counts.po_low),
        ("swr_high", counts.swr_high),
    ] {
        if n >= PERSISTENT {
            warnings.push(entry);
        }
    }
    Verdict {
        level_db,
        fault: meters.swr.is_some_and(|s| s >= SWR_FAULT_RAW),
        warnings,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub(crate) enum Alc {
    #[default]
    Unknown,
    Available,
    Unavailable,
}
#[derive(Default)]
struct Inner {
    managed: bool,
    power_limit: Option<u8>,
    level_db: i32,
    /// A level was stored for this profile (assistant or manual).
    stored: bool,
    alc: Alc,
    assistant: bool,
    result: Option<&'static str>,
    meters: Option<Meters>,
    reading: bool,
    read_at: Option<Instant>,
    counts: Counts,
    /// CL-044-15 shown beside Detect radio; kept here to share this one pushed event.
    keying_confirmed: bool,
    warnings: Vec<&'static str>,
    /// SWR stopped transmitting; held until a later reading or Set level shows it clear.
    swr_fault: bool,
    revision: u64,
    /// Test seam only (#87): a fixture's bound of one meter read instead of METER_READ.
    #[cfg(test)]
    read_bound: Option<Duration>,
}
#[derive(Default)]
pub(crate) struct Owner {
    inner: Mutex<Inner>,
}
impl Owner {
    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|p| p.into_inner())
    }
    pub(crate) fn revision(&self) -> u64 {
        self.lock().revision
    }
    pub(crate) fn level_db(&self) -> i32 {
        self.lock().level_db
    }
    /// The bound of one meter read (CL-044-12: 400 ms); in tests the fixture's override.
    fn read_bound(&self) -> Duration {
        #[cfg(test)]
        if let Some(bound) = self.lock().read_bound {
            return bound;
        }
        METER_READ
    }
    /// Test seam only (#87): every meter read of this owner takes `bound` instead.
    #[cfg(test)]
    pub(crate) fn set_read_bound(&self, bound: Duration) {
        self.lock().read_bound = Some(bound);
    }
    #[cfg(test)]
    pub(crate) fn result(&self) -> Option<&'static str> {
        self.lock().result
    }
    #[cfg(test)]
    pub(crate) fn assistant_running(&self) -> bool {
        self.lock().assistant
    }
    #[cfg(test)]
    pub(crate) fn warnings(&self) -> Vec<&'static str> {
        self.lock().warnings.clone()
    }
    #[cfg(test)]
    pub(crate) fn swr_fault(&self) -> bool {
        self.lock().swr_fault
    }
    #[cfg(test)]
    pub(crate) fn alc(&self) -> Alc {
        self.lock().alc
    }
    pub(crate) fn set_keying_confirmed(&self) {
        self.update(|i| i.keying_confirmed = true);
    }
    fn update(&self, change: impl FnOnce(&mut Inner)) {
        let mut i = self.lock();
        change(&mut i);
        i.revision += 1;
    }
    /// A meter read: the ALC is unavailable exactly when the radio refused its read (FA).
    pub(crate) fn record(&self, meters: Meters) {
        let alc = if meters.alc.is_some() {
            Alc::Available
        } else {
            Alc::Unavailable
        };
        let mut i = self.lock();
        if i.meters != Some(meters) || i.alc != alc {
            i.meters = Some(meters);
            i.alc = alc;
            i.revision += 1;
        }
    }
}

#[derive(serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct Record {
    schema_version: u8,
    level_db: i32,
}
fn store_level(state: &ProfileState, level_db: i32) -> Result<(), &'static str> {
    state
        .store
        .lock()
        .map_err(|_| "storage_unavailable")?
        .write_document_file(
            LEVEL_FILE,
            &Record {
                schema_version: 1,
                level_db,
            },
        )
        .map_err(|_| "storage_unavailable")
}
/// The stored level at startup; a missing or invalid file leaves the unattenuated default.
/// Also connects the transmit step's mid-transmission call to the meter read.
pub(crate) fn startup(state: &Arc<ProfileState>) {
    if let Some(t) = state.recording.transmit.get() {
        let weak = Arc::downgrade(state);
        t.set_meter_sink(Arc::new(move || {
            if let Some(state) = weak.upgrade() {
                let _ = on_meter_due(&state);
            }
        }));
    }
    if radio_setup::keying_confirmed(state) {
        state.recording.tx_level.set_keying_confirmed();
    }
    let record = state.store.lock().ok().and_then(|s| {
        let bytes = s.read_document_file(LEVEL_FILE, LEVEL_FILE_MAX).ok()??;
        serde_json::from_slice::<Record>(&bytes).ok()
    });
    let Some(record) = record
        .filter(|r| r.schema_version == 1 && (LEVEL_MIN_DB..=LEVEL_MAX_DB).contains(&r.level_db))
    else {
        return;
    };
    let recording = &state.recording;
    recording.tx_level.update(|i| {
        i.level_db = record.level_db;
        i.stored = true;
    });
    if let Some(t) = recording.transmit.get() {
        t.service.with(|c| c.set_tx_level(record.level_db));
    }
}

/// One tick under the CAT lifecycle: the profile's radio settings, and the meter display
/// while Tune runs outside the assistant. The read runs on its own thread; this tick
/// never waits for the transmit owner.
pub(crate) fn tick(recording: &Arc<Recording>, radio: Option<profile::Radio>, now: Instant) {
    let (managed, limit) = (radio.is_some(), radio.and_then(|r| r.power_limit_pct));
    {
        let mut i = recording.tx_level.lock();
        if i.managed != managed || i.power_limit != limit {
            i.managed = managed;
            if i.power_limit != limit {
                i.counts.ceiling = None;
            }
            i.power_limit = limit;
            i.revision += 1;
        }
        if !managed || i.assistant || i.reading {
            return;
        }
        if i.read_at
            .is_some_and(|t| now.duration_since(t) < TUNE_READ_EVERY)
        {
            return;
        }
    }
    let tune = recording
        .transmit
        .get()
        .and_then(|t| t.service.try_with(|c| c.tune_on()))
        .unwrap_or(false);
    let Some(actor) = recording.radio_actor().filter(|_| tune) else {
        return;
    };
    {
        let mut i = recording.tx_level.lock();
        i.reading = true;
        i.read_at = Some(now);
    }
    let owner = recording.clone();
    let spawned = std::thread::Builder::new()
        .name("tx-meters".into())
        .spawn(move || {
            let meters = actor.read_meters(Instant::now() + owner.tx_level.read_bound());
            owner.tx_level.lock().reading = false;
            if let Ok(meters) = meters {
                owner.tx_level.record(meters);
            }
        });
    if spawned.is_err() {
        recording.tx_level.lock().reading = false;
    }
}

/// CL-044-14 the transmit step's call in the middle of a transmission. It returns at once
/// and the burst runs on its own thread, so the transmit step, its audio and its release
/// never wait for the radio. Nothing is read while Set level runs.
pub(crate) fn on_meter_due(state: &Arc<ProfileState>) -> Option<std::thread::JoinHandle<()>> {
    let recording = &state.recording;
    if recording.tx_level.lock().assistant {
        return None;
    }
    let actor = recording.radio_actor()?;
    let running = state.clone();
    std::thread::Builder::new()
        .name("tx-monitor".into())
        .spawn(move || {
            let bound = running.recording.tx_level.read_bound();
            if let Ok(meters) = actor.read_meters(Instant::now() + bound) {
                monitor(&running, &meters);
            }
        })
        .ok()
}
/// One transmission's reading: a level change waits for the next transmission (the
/// transmit owner keeps the running one's level); a clear fault stops transmitting.
fn monitor(state: &Arc<ProfileState>, meters: &Meters) {
    let recording = &state.recording;
    let Some(station) = recording.transmit.get() else {
        return;
    };
    recording.tx_level.record(*meters);
    let verdict = {
        let mut i = recording.tx_level.lock();
        // Set level started during the burst: the level is its own.
        if i.assistant {
            return;
        }
        let mut counts = i.counts;
        let verdict = monitor_step(i.level_db, meters, i.power_limit, &mut counts);
        i.counts = counts;
        verdict
    };
    if verdict.fault {
        // A fresh command id: a repeated one would answer from the receipt, not stop.
        let command = profile::new_uuid().unwrap_or_else(|_| recording.boot.clone());
        // First: no automation may arm in the moment after the halt.
        station.service.with(|c| c.require_operator());
        station.service.halt(&command);
    }
    // CL-044-12: a level counts only once it is on disk; a failed store leaves the prior one.
    let level = verdict.level_db;
    let changed = level != recording.tx_level.level_db() && store_level(state, level).is_ok();
    if changed {
        station.service.with(|c| c.set_tx_level(level));
    }
    let mut i = recording.tx_level.lock();
    // A reading without SWR says nothing about the fault.
    let swr_fault = verdict.fault || (i.swr_fault && meters.swr.is_none());
    if changed || i.warnings != verdict.warnings || i.swr_fault != swr_fault {
        if changed {
            i.level_db = level;
            i.stored = true;
        }
        i.warnings = verdict.warnings;
        i.swr_fault = swr_fault;
        i.revision += 1;
    }
}

/// Starts "Set level": arms when needed, Tune at the start level, and the stepping thread.
pub(crate) fn start_assistant(state: &Arc<ProfileState>, hz: u32) -> Result<(), String> {
    let recording = &state.recording;
    let station = recording.transmit.get().ok_or("not_found")?.clone();
    {
        let mut i = recording.tx_level.lock();
        if i.assistant {
            return Err("busy".into());
        }
        i.assistant = true;
        i.result = None;
        i.revision += 1;
    }
    let prior = recording.tx_level.level_db();
    let halts = station.service.halt_requests();
    let begun = station.service.with(|c| {
        let view = c.view();
        if view.tune || view.transmitting || view.pending_sequence.is_some() {
            return Err("busy".to_owned());
        }
        let armed_here = view.arm_state != ArmState::Armed;
        if armed_here {
            let revision = c
                .hardware()
                .context()
                .safety_revision
                .ok_or("radio_unavailable")?;
            c.arm(revision).map_err(name)?;
        }
        c.set_tx_level(ASSISTANT_START_DB);
        if let Err(refusal) = c.set_tune(true, hz) {
            c.set_tx_level(prior);
            if armed_here {
                c.disarm(DisarmCause::Operator);
            }
            return Err(name(refusal));
        }
        Ok(armed_here)
    });
    let armed_here = match begun {
        Ok(armed_here) => armed_here,
        Err(refusal) => {
            recording.tx_level.update(|i| i.assistant = false);
            return Err(refusal);
        }
    };
    let running = state.clone();
    let thread_station = station.clone();
    let spawned = std::thread::Builder::new()
        .name("tx-level".into())
        .spawn(move || assistant(&running, &thread_station, prior, armed_here, halts));
    if spawned.is_err() {
        station.service.with(|c| {
            let _ = c.set_tune(false, 0);
            c.set_tx_level(prior);
            if armed_here {
                c.disarm(DisarmCause::Operator);
            }
        });
        recording.tx_level.update(|i| i.assistant = false);
        return Err("busy".into());
    }
    Ok(())
}
/// The stepping thread. HALT, the Tune limit or any lost Tune aborts without storing.
fn assistant(
    state: &Arc<ProfileState>,
    station: &Arc<transmit_http::Station>,
    prior: i32,
    armed_here: bool,
    halts: u64,
) {
    let recording = &state.recording;
    let limit = recording.tx_level.lock().power_limit;
    let lost = || station.service.halt_requests() != halts || !station.service.view().tune;
    let mut level = ASSISTANT_START_DB;
    recording.tx_level.update(|i| i.level_db = level);
    let (stored, result) = loop {
        let settled = Instant::now() + SETTLE;
        while Instant::now() < settled && !lost() {
            std::thread::sleep(Duration::from_millis(5));
        }
        if lost() {
            break (None, "aborted");
        }
        let Some(actor) = recording.radio_actor() else {
            break (None, "radio_unavailable");
        };
        let meters = match actor.read_meters(Instant::now() + recording.tx_level.read_bound()) {
            Ok(meters) => meters,
            // A read cancelled by the release of a HALT is an abort, not a radio error.
            Err(_) if lost() => break (None, "aborted"),
            Err(e) => break (None, selection::radio_error(e)),
        };
        recording.tx_level.record(meters);
        if lost() {
            break (None, "aborted");
        }
        match assistant_step(level, &meters, limit) {
            Step::Up(next) => {
                level = next;
                station.service.with(|c| c.set_tx_level(level));
                recording.tx_level.update(|i| i.level_db = level);
            }
            Step::Done(value, result) => break (Some(value), result),
            Step::Stop(result) => break (None, result),
        }
    };
    station.service.with(|c| {
        let _ = c.set_tune(false, 0);
        c.set_tx_level(prior);
        if armed_here && c.view().arm_state == ArmState::Armed {
            c.disarm(DisarmCause::Operator);
        }
    });
    // CL-044-12: a level counts only once it is on disk; every failure leaves the prior one.
    let (kept, result) = match stored.map(|value| (value, store_level(state, value))) {
        Some((value, Ok(_))) => {
            station.service.with(|c| c.set_tx_level(value));
            (Some(value), result)
        }
        Some((_, Err(e))) => (None, e),
        None => (None, result),
    };
    recording.tx_level.update(|i| {
        i.assistant = false;
        i.result = Some(result);
        i.level_db = kept.unwrap_or(prior);
        i.stored |= kept.is_some();
        if kept.is_some() {
            i.swr_fault = false;
            i.counts.ceiling = None;
        }
    });
}
/// The manual level, offered only for a radio that reports no ALC over CI-V; also live
/// while Tune runs.
pub(crate) fn set_manual(state: &ProfileState, level_db: i32) -> Result<(), &'static str> {
    if !(LEVEL_MIN_DB..=LEVEL_MAX_DB).contains(&level_db) {
        return Err("invalid_request");
    }
    let recording = &state.recording;
    let station = recording.transmit.get().ok_or("not_found")?;
    {
        let i = recording.tx_level.lock();
        if i.assistant {
            return Err("busy");
        }
        if i.alc != Alc::Unavailable {
            return Err("alc_available");
        }
    }
    store_level(state, level_db)?;
    station.service.with(|c| c.set_tx_level(level_db));
    recording.tx_level.update(|i| {
        i.level_db = level_db;
        i.stored = true;
        i.result = None;
    });
    Ok(())
}

/// The `radio.tx_level` event of the current state.
pub(crate) fn event(recording: &Recording) -> (u64, String) {
    let i = recording.tx_level.lock();
    let meters = i
        .meters
        .map(|m| json!({"alc":m.alc,"po_pct":m.po.map(po_percent),"swr_x10":m.swr.map(swr_x10)}));
    let mut warnings = i.warnings.clone();
    if i.swr_fault {
        warnings.push("swr_fault");
    }
    let alc = match i.alc {
        Alc::Unknown => "unknown",
        Alc::Available => "available",
        Alc::Unavailable => "unavailable",
    };
    let data = json!({"profile_id":recording.profile,"boot_id":recording.boot,
        "managed":i.managed,"level_db":i.level_db,"stored":i.stored,"alc":alc,
        "assistant":i.assistant,"result":i.result,"meters":meters,"power_limit_pct":i.power_limit,
        "warnings":warnings,"keying_confirmed":i.keying_confirmed});
    (
        i.revision,
        json!({"v":1,"type":"radio.tx_level","data":data}).to_string(),
    )
}

/// POST /radio/tx-level: action `set_level` (the assistant, tx_offset_hz) or `manual`
/// (level_db, only without CI-V ALC). The outcome arrives as the radio.tx_level push.
pub async fn route(
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
    let command = match envelope(&body, &r, true) {
        Ok(c) => c,
        Err(e) => return error(e),
    };
    let integer = |k: &str| body.get(k).and_then(Value::as_i64);
    let action = match body.get("action").and_then(Value::as_str) {
        Some("set_level") => keys(&body, &["action", "tx_offset_hz"]).and_then(|()| {
            integer("tx_offset_hz")
                .and_then(|hz| u32::try_from(hz).ok())
                .map(Err)
                .ok_or("invalid_request")
        }),
        Some("manual") => keys(&body, &["action", "level_db"]).and_then(|()| {
            integer("level_db")
                .and_then(|db| i32::try_from(db).ok())
                .map(Ok)
                .ok_or("invalid_request")
        }),
        _ => Err("invalid_request"),
    };
    let action = match action {
        Ok(a) => a,
        Err(e) => return error(e),
    };
    // Transmit authority needs a current CL-022 grant, as Tune does.
    if !matches!(
        authorization_http::operating_access_async(&headers, &app).await,
        Ok(Some(_))
    ) {
        return error("unauthorized");
    }
    let Some(state) = app.profile.clone() else {
        return error("not_found");
    };
    let done = tokio::task::spawn_blocking(move || match action {
        Err(hz) => start_assistant(&state, hz),
        Ok(db) => set_manual(&state, db).map_err(str::to_owned),
    })
    .await;
    let refusal = match done {
        Ok(Ok(())) => None,
        Ok(Err(refusal)) => Some(refusal),
        Err(_) => Some("storage_unavailable".to_owned()),
    };
    if let Some(code @ ("invalid_request" | "not_found" | "storage_unavailable")) =
        refusal.as_deref()
    {
        return error(code);
    }
    Json(
        json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"command_id":command,
        "accepted":refusal.is_none(),"refusal":refusal}),
    )
    .into_response()
}

#[cfg(test)]
#[path = "radio_level_tests.rs"]
mod tests;
