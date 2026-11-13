use crate::*;
use axum::extract::RawQuery;
use recording_http::{authorize, error, parse, syntax};
use serde::Deserialize;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Start {
    v: u64,
    profile_id: String,
    boot_id: String,
    generation: u64,
    profile_revision: u64,
    mode: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct StartupEdit {
    v: u64,
    profile_id: String,
    boot_id: String,
    monitor_off_at_startup: bool,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct DiagnosticsEdit {
    v: u64,
    profile_id: String,
    boot_id: String,
    window_dump: bool,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Stop {
    v: u64,
    profile_id: String,
    boot_id: String,
    generation: u64,
    job_id: String,
}

fn empty(body: Result<Bytes, BytesRejection>) -> Result<(), &'static str> {
    match body {
        Ok(b) if b.is_empty() => Ok(()),
        Ok(_) => Err("invalid_request"),
        Err(_) => Err("request_too_large"),
    }
}

/// The data of receive.state (WstxStationLink::PushedStationState): the identity and what a
/// browser holding it would otherwise read GET /receive for. It leaves out what frames carry.
pub(crate) fn receive_state_data(s: &Value) -> Value {
    let (j, c) = (&s["job"], &s["clock"]);
    json!({"profile_id":s["profile_id"],"boot_id":s["boot_id"],"generation":s["generation"],
        "source_id":s["source"]["id"],"job_id":j["id"],"state":j["state"],
        "audio":s["audio"],
        "clock":{"correlated":c["correlated"],"utc_anchor":c["utc_anchor"],"canonical_anchor_frame":c["canonical_anchor_frame"],"uncertainty_ns":c["uncertainty_ns"]},
        "job":{"error":j["error"],"first_sequence":j["first_sequence"],"next_sequence":j["next_sequence"],
            "available_count":j["available_count"],"last_overrun":j["last_overrun"],"latest_decode":j["latest_decode"]}})
}

/// The receive.state this peer gets after `sent` (#10): the first one of a socket and one of a new
/// receive identity hold every field; a later one the identity and only the audio, clock and job
/// fields that changed (job by its keys).
pub(crate) fn receive_state_delta(sent: &Value, now: &Value) -> Value {
    const IDENTITY: [&str; 6] = [
        "profile_id",
        "boot_id",
        "generation",
        "source_id",
        "job_id",
        "state",
    ];
    if sent.is_null() || IDENTITY[..5].iter().any(|k| sent[*k] != now[*k]) {
        return now.clone();
    }
    let mut delta = serde_json::Map::new();
    for key in IDENTITY {
        delta.insert(key.into(), now[key].clone());
    }
    for key in ["audio", "clock"] {
        if sent[key] != now[key] {
            delta.insert(key.into(), now[key].clone());
        }
    }
    let job: serde_json::Map<String, Value> = now["job"]
        .as_object()
        .into_iter()
        .flatten()
        .filter(|(k, v)| sent["job"][k.as_str()] != **v)
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect();
    if !job.is_empty() {
        delta.insert("job".into(), Value::Object(job));
    }
    Value::Object(delta)
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
    if query.is_some() {
        return error("invalid_request");
    }
    if let Err(e) = empty(body) {
        return error(e);
    }
    Json(r.receive_snapshot()).into_response()
}
/// #47 CL-007-05: the measured capture-clock drift, on demand (same rules as GET /receive).
pub async fn clock(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
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
    Json(r.receive_clock()).into_response()
}
/// #45 CL-045-01: the persisted startup choice, Monitor-off setting and resume outcome.
pub async fn startup(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
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
    Json(r.startup_view()).into_response()
}
/// #45 CL-045-01: sets "Monitor off at startup"; it takes effect at the next start.
pub async fn startup_update(
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
    let b: StartupEdit = match parse(&headers, body) {
        Ok(b) => b,
        Err(e) => return error(e),
    };
    if let Err(e) = syntax(b.v, &b.profile_id, &b.boot_id, 0) {
        return error(e);
    }
    match tokio::task::spawn_blocking(move || {
        r.set_monitor_off(&b.profile_id, &b.boot_id, b.monitor_off_at_startup)
    })
    .await
    {
        Ok(Ok(v)) => Json(v).into_response(),
        Ok(Err(e)) => error(e),
        Err(_) => error("storage_unavailable"),
    }
}
/// #52 CL-052-01: the latest windows' sample and capture counters and the dump setting.
pub async fn diagnostics(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
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
    Json(r.diagnostics_view()).into_response()
}
/// #52 CL-052-01: turns the FT8 prompt-window dump on or off; it acts from the next window.
pub async fn diagnostics_update(
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
    let b: DiagnosticsEdit = match parse(&headers, body) {
        Ok(b) => b,
        Err(e) => return error(e),
    };
    if let Err(e) = syntax(b.v, &b.profile_id, &b.boot_id, 0) {
        return error(e);
    }
    match tokio::task::spawn_blocking(move || {
        r.set_window_dump(&b.profile_id, &b.boot_id, b.window_dump)
    })
    .await
    {
        Ok(Ok(v)) => Json(v).into_response(),
        Ok(Err(e)) => error(e),
        Err(_) => error("storage_unavailable"),
    }
}
pub async fn devices(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
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
    #[cfg(windows)]
    let devices = match tokio::task::spawn_blocking(audio::enumerate_inputs).await {
        Ok(Ok(devices)) => devices,
        _ => return error("audio_unavailable"),
    };
    #[cfg(not(windows))]
    let devices: Vec<Value> = Vec::new();
    #[cfg(windows)]
    let devices: Vec<_> = devices
        .into_iter()
        .map(|d| json!({"id":d.id,"name":d.name}))
        .collect();
    if devices.len() > 64
        || devices.iter().any(|d| {
            d["id"]
                .as_str()
                .is_none_or(|s| s.is_empty() || s.len() > 256)
                || d["name"]
                    .as_str()
                    .is_none_or(|s| s.is_empty() || s.len() > 256)
        })
    {
        return error("device_limit");
    }
    let value = json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"devices":devices});
    if !serde_json::to_vec(&value).is_ok_and(|b| b.len() <= 16384) {
        return error("device_limit");
    }
    Json(value).into_response()
}
pub async fn start(
    State(app): State<App>,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, true).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    let b: Start = match parse(&headers, body) {
        Ok(b) => b,
        Err(e) => return error(e),
    };
    if let Err(e) = syntax(b.v, &b.profile_id, &b.boot_id, b.generation) {
        return error(e);
    }
    if b.profile_revision > profile::MAX_REVISION {
        return error("invalid_request");
    }
    let mode = match b.mode.as_str() {
        "spectrum" => "spectrum",
        "ft4" => "ft4",
        "ft8" => "ft8",
        _ => return error("invalid_request"),
    };
    let profile = app.profile.unwrap();
    let station = profile.clone();
    let reply = match tokio::task::spawn_blocking(move || {
        r.receive_context(&b.profile_id, &b.boot_id, b.generation)?;
        let store = profile.store.lock().unwrap();
        if store.document.revision != b.profile_revision {
            return Err("state_conflict");
        }
        let device = profile::receive_device(&store.document).ok_or("audio_unconfigured")?;
        drop(store);
        r.receive_start(
            &b.profile_id,
            &b.boot_id,
            b.generation,
            b.profile_revision,
            device,
            mode,
        )
    })
    .await
    {
        Ok(Ok(v)) => (StatusCode::ACCEPTED, Json(v)).into_response(),
        Ok(Err(e)) => return error(e),
        Err(_) => return error("audio_unavailable"),
    };
    contact_step(station).await;
    reply
}
/// WstxQsoTransmit::ModeChange: one synchronous station contact step before a receive or
/// selection mutation is answered, so a mode change is applied to the contact at once.
pub(crate) async fn contact_step(state: Arc<ProfileState>) {
    let _ = tokio::task::spawn_blocking(move || crate::contact_http::station_tick(&state)).await;
}
pub async fn stop(
    State(app): State<App>,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, true).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    let b: Stop = match parse(&headers, body) {
        Ok(b) => b,
        Err(e) => return error(e),
    };
    if let Err(e) = syntax(b.v, &b.profile_id, &b.boot_id, b.generation) {
        return error(e);
    }
    if !profile::valid_uuid(&b.job_id) {
        return error("invalid_request");
    }
    // Stop also clears the persisted startup choice (#45): file I/O off the runtime.
    let stopped = tokio::task::spawn_blocking(move || {
        r.receive_stop(&b.profile_id, &b.boot_id, b.generation, &b.job_id)
    })
    .await
    .unwrap_or(Err("storage_unavailable"));
    match stopped {
        Ok(v) => {
            if let Some(state) = app.profile.clone() {
                contact_step(state).await;
            }
            (StatusCode::ACCEPTED, Json(v)).into_response()
        }
        Err(e) => error(e),
    }
}
fn number(value: &str) -> Result<u64, &'static str> {
    if value.is_empty()
        || (value.len() > 1 && value.starts_with('0'))
        || !value.bytes().all(|b| b.is_ascii_digit())
    {
        return Err("invalid_request");
    }
    value
        .parse::<u64>()
        .ok()
        .filter(|n| *n <= profile::MAX_REVISION)
        .ok_or("invalid_request")
}
pub async fn results(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, false).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    if let Err(e) = empty(body) {
        return error(e);
    }
    let parsed = (|| {
        let mut values = std::collections::BTreeMap::new();
        for pair in query.as_deref().ok_or("invalid_request")?.split('&') {
            let (key, value) = pair.split_once('=').ok_or("invalid_request")?;
            if !matches!(
                key,
                "source_id" | "job_id" | "generation" | "cursor" | "limit"
            ) || values.insert(key, value).is_some()
            {
                return Err("invalid_request");
            }
        }
        let source = *values.get("source_id").ok_or("invalid_request")?;
        let job = *values.get("job_id").ok_or("invalid_request")?;
        if !profile::valid_uuid(source) || !profile::valid_uuid(job) {
            return Err("invalid_request");
        }
        let generation = number(values.get("generation").ok_or("invalid_request")?)?;
        let cursor = number(values.get("cursor").ok_or("invalid_request")?)?;
        let limit = values
            .get("limit")
            .map(|v| number(v))
            .transpose()?
            .unwrap_or(16);
        if !(1..=16).contains(&limit) {
            return Err("invalid_request");
        }
        r.receive_results(source, job, generation, cursor, limit as usize)
    })();
    match parsed {
        Ok(v) if v["error"]["code"] == "cursor_expired" => {
            (StatusCode::GONE, Json(v)).into_response()
        }
        Ok(mut v) => {
            // #55 DecodedEntity: the entity and new-* flags of each decoded sender.
            if let Some(state) = app.profile.clone() {
                let annotated = tokio::task::spawn_blocking(move || {
                    if let Some(records) = v["records"].as_array_mut() {
                        crate::dxcc::annotate(&state, records);
                    }
                    v
                });
                match annotated.await {
                    Ok(annotated) => v = annotated,
                    Err(_) => return error("storage_unavailable"),
                }
            }
            Json(v).into_response()
        }
        Err(e) => error(e),
    }
}
