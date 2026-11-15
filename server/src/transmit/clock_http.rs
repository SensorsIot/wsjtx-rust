//! #43/#92 CL-043-01: the station clock view of Settings > General > Clock, read on demand
//! (GET /clock) rather than on the thin status link, and the pushed clock.state event for
//! every profile. There is no source setting: clock.json (#43) is neither read nor written,
//! and POST /clock no longer exists.
use crate::*;
use axum::extract::RawQuery;
use recording_http::{authorize, error};
use wstx_rust::transmit::ClockState;
use wstx_rust::transmit::air::{StationClock, Warning};

#[cfg(test)]
#[path = "clock_http_tests.rs"]
mod tests;

/// The clock.state event is at most this long (CL-043-01).
pub(crate) const EVENT_LIMIT: usize = 512;

/// The station clock of the selected profile and the station-wide clock_revision.
pub(crate) struct Clock {
    pub(crate) station: Arc<StationClock>,
    /// The clock.state fields last seen and their revision.
    revision: Mutex<(Value, u64)>,
}
impl Clock {
    pub(crate) fn new(ntp: Arc<wstx_rust::transmit::clock::Monitor>) -> Arc<Self> {
        Arc::new(Self {
            station: StationClock::new(ntp),
            revision: Mutex::new((Value::Null, 0)),
        })
    }
}
fn state(s: ClockState) -> &'static str {
    match s {
        ClockState::Synchronized => "synchronized",
        ClockState::Unsynchronized => "unsynchronized",
        ClockState::Unknown => "unknown",
    }
}
/// The clock fields of clock.state and their clock_revision, which increases at each change
/// any reader observes (GET /clock and every peer's push read the same counter).
fn fields(r: &recording::Recording, c: &Clock, v: &wstx_rust::transmit::air::View) -> (Value, u64) {
    let pc_clock_off = v.warning == Some(Warning::PcClockOff);
    let fields = json!({"state":state(v.state),"correction_ms":v.correction_ms,
        "warning":v.warning.map(Warning::name),
        "ntp_offset_ms":v.ntp.as_ref().filter(|_|pc_clock_off).map(|m|m.offset_ms),
        "capture_warning":r.capture_warning()});
    let mut seen = c.revision.lock().unwrap_or_else(|p| p.into_inner());
    if seen.0 != fields {
        *seen = (fields.clone(), seen.1 + 1);
    }
    (fields, seen.1)
}
/// GET /clock: exactly the view of CL-043-01.
pub(crate) fn view(r: &recording::Recording, c: &Clock) -> Value {
    let v = c.station.view();
    let (fields, revision) = self::fields(r, c, &v);
    let measurement = v.ntp.as_ref().map(|m| {
        json!({"server":m.server,"offset_ms":m.offset_ms,"round_trip_ms":m.round_trip_ms,
            "age_ms":u64::try_from(m.taken.elapsed().as_millis()).unwrap_or(u64::MAX)})
    });
    let estimate = v.air.map(|(e, age)| {
        json!({"median_dt_ms":e.median_dt_ms,"stations":e.stations,"plus":e.plus,"minus":e.minus,"age_ms":age.max(0)})
    });
    json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"state":fields["state"],
        "correction_ms":v.correction_ms,
        "ntp":{"state":state(v.ntp_state),"measurement":measurement,"windows_time":c.station.windows_time().name()},
        "air":{"estimate":estimate},
        "warning":fields["warning"],"capture_warning":fields["capture_warning"],"clock_revision":revision})
}
/// The clock.state event and its clock_revision; None without a station clock.
pub(crate) fn state_event(r: &recording::Recording) -> Option<(u64, String)> {
    let c = r.clock.get()?;
    let v = c.station.view();
    let (clock, revision) = fields(r, c, &v);
    let text = json!({"v":1,"type":"clock.state","data":{"profile_id":r.profile,"boot_id":r.boot,
        "clock_revision":revision,"clock":clock}})
    .to_string();
    (text.len() <= EVENT_LIMIT).then_some((revision, text))
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
    let c = match clock(&r) {
        Ok(c) => c,
        Err(e) => return error(e),
    };
    // The Windows Time query is a blocking service-manager call.
    match tokio::task::spawn_blocking(move || view(&r, &c)).await {
        Ok(v) => Json(v).into_response(),
        Err(_) => error("storage_unavailable"),
    }
}
