//! #43 CL-043-01: the profile's clock source (NTP, from the air, both), persisted in
//! clock.json next to profile.json, and the clock view of Settings > General > Clock,
//! read on demand (GET /clock) rather than on the thin status link.
use crate::*;
use axum::extract::RawQuery;
use recording_http::{authorize, error, parse, syntax};
use serde::{Deserialize, Serialize};
use wstx_rust::transmit::ClockState;
use wstx_rust::transmit::air::{Basis, Source, StationClock};

#[cfg(test)]
#[path = "clock_http_tests.rs"]
mod tests;

pub(crate) const FILE: &str = "clock.json";
const FILE_LIMIT: u64 = 1024;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Record {
    schema_version: u8,
    profile_id: String,
    source: String,
}
/// The station clock of the selected profile and where its source is saved.
pub(crate) struct Clock {
    pub(crate) station: Arc<StationClock>,
    directory: PathBuf,
    profile: String,
    storage_error: Mutex<Option<&'static str>>,
}
impl Clock {
    /// Reads the saved source: missing is NTP; foreign, malformed, oversize or unknown
    /// is NTP with storage_error invalid_clock (the next save replaces it).
    pub(crate) fn load(
        directory: &std::path::Path,
        profile: &str,
        ntp: Arc<wstx_rust::transmit::clock::Monitor>,
    ) -> Arc<Self> {
        let path = directory.join(FILE);
        let (source, storage_error) = match std::fs::metadata(&path) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => (Source::Ntp, None),
            Err(_) => (Source::Ntp, Some("storage_unavailable")),
            Ok(_) => match recording::bounded_json::<Record>(&path, FILE_LIMIT) {
                Ok(r) if r.schema_version == 1 && r.profile_id == profile => {
                    match Source::parse(&r.source) {
                        Some(s) => (s, None),
                        None => (Source::Ntp, Some("invalid_clock")),
                    }
                }
                _ => (Source::Ntp, Some("invalid_clock")),
            },
        };
        Arc::new(Self {
            station: StationClock::new(ntp, source),
            directory: directory.to_path_buf(),
            profile: profile.into(),
            storage_error: Mutex::new(storage_error),
        })
    }
    /// Saves and applies `source`; a failed write changes nothing.
    fn set(&self, source: Source) -> std::result::Result<(), &'static str> {
        let record = Record {
            schema_version: 1,
            profile_id: self.profile.clone(),
            source: source.name().into(),
        };
        let mut storage_error = self.storage_error.lock().unwrap();
        match profile::atomic_json(&self.directory, FILE, &record) {
            Ok(()) => {
                *storage_error = None;
                self.station.set_source(source);
                Ok(())
            }
            Err(_) => {
                *storage_error = Some("storage_unavailable");
                Err("storage_unavailable")
            }
        }
    }
}
fn state(s: ClockState) -> &'static str {
    match s {
        ClockState::Synchronized => "synchronized",
        ClockState::Unsynchronized => "unsynchronized",
        ClockState::Unknown => "unknown",
    }
}
pub(crate) fn view(r: &recording::Recording, c: &Clock) -> Value {
    let v = c.station.view();
    let ntp = v.ntp.as_ref().map(|m| {
        json!({"server":m.server,"offset_ms":m.offset_ms,"round_trip_ms":m.round_trip_ms,
            "age_ms":u64::try_from(m.taken.elapsed().as_millis()).unwrap_or(u64::MAX)})
    });
    let air = v.air.map(|(e, age)| {
        json!({"offset_ms":e.offset_ms,"stations":e.stations,"heard":e.heard,
            "confidence_pct":e.confidence_pct,"age_ms":age.max(0)})
    });
    json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"source":v.source.name(),
        "state":state(v.state),"basis":if v.basis==Basis::Air {"air"} else {"ntp"},
        "correction_ms":v.correction_ms,
        "ntp":{"state":state(v.ntp_state),"measurement":ntp},
        "air":{"state":state(v.air_state),"applied_ms":v.air_applied_ms,"estimate":air},
        "disagreement_ms":v.disagreement_ms,"warning":v.warning.then_some("ntp_air_disagree"),
        "storage_error":*c.storage_error.lock().unwrap()})
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Edit {
    v: u64,
    profile_id: String,
    boot_id: String,
    source: String,
}
fn clock(r: &recording::Recording) -> std::result::Result<Arc<Clock>, &'static str> {
    r.clock.get().cloned().ok_or("not_found")
}
fn empty(
    body: std::result::Result<Bytes, BytesRejection>,
) -> std::result::Result<(), &'static str> {
    match body {
        Ok(b) if b.is_empty() => Ok(()),
        Ok(_) => Err("invalid_request"),
        Err(_) => Err("request_too_large"),
    }
}
/// GET /clock: the clock view (operating access, no query, empty body).
pub async fn snapshot(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: std::result::Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, false).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    if query.is_some() {
        return error("invalid_request");
    }
    if let Err(e) = empty(body) {
        return error(e);
    }
    match clock(&r) {
        Ok(c) => Json(view(&r, &c)).into_response(),
        Err(e) => error(e),
    }
}
/// POST /clock {v, profile_id, boot_id, source}: saves the source, effective at once.
pub async fn update(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: std::result::Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, true).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    if query.is_some() {
        return error("invalid_request");
    }
    let b: Edit = match parse(&headers, body) {
        Ok(b) => b,
        Err(e) => return error(e),
    };
    if let Err(e) = syntax(b.v, &b.profile_id, &b.boot_id, 0) {
        return error(e);
    }
    if b.profile_id != r.profile {
        return error("wrong_profile");
    }
    if b.boot_id != r.boot {
        return error("state_conflict");
    }
    let Some(source) = Source::parse(&b.source) else {
        return error("invalid_request");
    };
    let c = match clock(&r) {
        Ok(c) => c,
        Err(e) => return error(e),
    };
    let saved = c.clone();
    match tokio::task::spawn_blocking(move || saved.set(source)).await {
        Ok(Ok(())) => Json(view(&r, &c)).into_response(),
        Ok(Err(e)) => error(e),
        Err(_) => error("storage_unavailable"),
    }
}
