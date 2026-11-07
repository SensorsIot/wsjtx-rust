//! FR-023 native session status: the radio.native push and the read-only GET /native-flex
//! snapshot. Runtime slice and stream values are informational only; no request accepts
//! them as authority.
use crate::*;
use axum::extract::RawQuery;
use recording_http::authorize;
use selection_http::{empty, error};
use wstx_rust::flex::{Session, Snapshot, State as SessionState};

fn pushed(profile: &str, boot: &str, s: &Snapshot) -> Value {
    let radio = s.radio.as_ref().map(|r| {
        json!({"serial":r.serial,"model":r.model,"firmware":r.firmware,"protocol":r.protocol,"address":r.address})
    });
    let slice = s.slice.as_ref().map(|l| {
        json!({"index":l.index,"letter":l.letter,"frequency_hz":l.frequency_hz,"mode":l.mode,
            "rx_antenna":l.rx_antenna,"dax_channel":l.dax_channel,"stream_id":l.stream_id})
    });
    json!({"profile_id":profile,"boot_id":boot,"state":s.state.name(),
        "error":s.error.map(|e|e.code()),"radio_code":s.radio_code.map(|c|format!("{c:08X}")),
        "session":s.session,"radio":radio,"slice":slice,
        "retry_after_ms":s.retry_after_ms,"transmit":"unsupported"})
}

/// The radio.native event: one peer's snapshot, then each change of the pushed state.
pub(crate) fn event(recording: &recording::Recording, session: &Session) -> (u64, String) {
    // The revision first: a change racing this read is pushed once more, never lost.
    let revision = session.revision();
    let data = pushed(&recording.profile, &recording.boot, &session.snapshot());
    (
        revision,
        json!({"v":1,"type":"radio.native","data":data}).to_string(),
    )
}

/// The radio object of /receive/selection for a native profile. The fact shape is the CAT
/// one: the slice status is the radio's read-back of the frequency, and only that fact exists.
pub(crate) fn selection_radio(session: &Session, boot_at: Instant) -> Value {
    let s = session.snapshot();
    let ready = s.state == SessionState::Ready;
    let state = match s.state {
        SessionState::Ready => "ready",
        SessionState::Discovering | SessionState::Connecting => "connecting",
        SessionState::Stopped | SessionState::Unauthorized => "closed",
        SessionState::Unavailable | SessionState::Conflict => "unavailable",
    };
    let frequency = s
        .slice
        .as_ref()
        .and_then(|l| l.frequency_hz.zip(l.observed_at))
        .filter(|_| ready);
    let unknown =
        || json!({"value":null,"query_sequence":null,"observed_at_ms":null,"confirmed":false});
    json!({"connection_generation":s.session,"state":state,"error":s.error.map(|e|e.code()),
        "observations":{
            "frequency":frequency.map_or_else(unknown,|(hz,at)|json!({"value":hz,"query_sequence":s.session.max(1),
                "observed_at_ms":at.saturating_duration_since(boot_at).as_millis() as u64,"confirmed":true})),
            "mode":unknown(),"data":unknown(),"rx_tx":unknown(),"split":unknown()}})
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
    // A standard profile has no native backend at all.
    let Some(session) = r.flex.get() else {
        return error("not_found");
    };
    let s = session.snapshot();
    let c = s.counters;
    let mut value = pushed(&r.profile, &r.boot, &s);
    value["v"] = json!(1);
    value["packets"] =
        json!({"accepted":c.accepted,"foreign":c.foreign,"invalid":c.invalid,"lost":c.lost});
    value["last_peak"] = json!(s.last_peak);
    value["vita"] = json!({"tsi":s.vita_tsi,"host_minus_radio_ms":s.vita_offset_ms});
    value["arrival"] = json!({"jitter_mean_ms":s.jitter_mean_ms,"jitter_max_ms":s.jitter_max_ms});
    Json(value).into_response()
}
