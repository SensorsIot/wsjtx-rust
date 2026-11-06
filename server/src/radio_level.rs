#![forbid(unsafe_code)]
//! #44 CL-044-12/13 the Tx audio level: a digital attenuation of our Tx audio, stored per
//! radio profile in its own file (a level change never advances the profile revision,
//! which would reconnect CAT). "Set level" is the default way to set it: it runs Tune,
//! steps the level up until the radio's ALC first rises, backs off one step, stores it
//! and stops Tune. A manual level exists only for a radio that reports no ALC over CI-V.
//! Meters are read under the transmit hold (`Actor::read_meters`); the state is pushed to
//! the WebSocket peers as `radio.tx_level` on change (no polling).
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
    revision: u64,
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
    #[cfg(test)]
    pub(crate) fn result(&self) -> Option<&'static str> {
        self.lock().result
    }
    #[cfg(test)]
    pub(crate) fn assistant_running(&self) -> bool {
        self.lock().assistant
    }
    #[cfg(test)]
    pub(crate) fn alc(&self) -> Alc {
        self.lock().alc
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
pub(crate) fn startup(state: &ProfileState) {
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
            let meters = actor.read_meters(Instant::now() + METER_READ);
            owner.tx_level.lock().reading = false;
            if let Ok(meters) = meters {
                owner.tx_level.record(meters);
            }
        });
    if spawned.is_err() {
        recording.tx_level.lock().reading = false;
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
        let meters = match actor.read_meters(Instant::now() + METER_READ) {
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
            }
            Step::Done(value, result) => break (Some(value), result),
            Step::Stop(result) => break (None, result),
        }
    };
    let level = stored.unwrap_or(prior);
    station.service.with(|c| {
        let _ = c.set_tune(false, 0);
        c.set_tx_level(level);
        if armed_here && c.view().arm_state == ArmState::Armed {
            c.disarm(DisarmCause::Operator);
        }
    });
    let result = match stored.map(|value| store_level(state, value)) {
        Some(Err(e)) => e,
        _ => result,
    };
    recording.tx_level.update(|i| {
        i.assistant = false;
        i.result = Some(result);
        i.level_db = level;
        i.stored |= stored.is_some();
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
    let alc = match i.alc {
        Alc::Unknown => "unknown",
        Alc::Available => "available",
        Alc::Unavailable => "unavailable",
    };
    let data = json!({"profile_id":recording.profile,"boot_id":recording.boot,
        "managed":i.managed,"level_db":i.level_db,"stored":i.stored,"alc":alc,
        "assistant":i.assistant,"result":i.result,"meters":meters,"power_limit_pct":i.power_limit});
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
