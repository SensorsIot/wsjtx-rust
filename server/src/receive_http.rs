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
pub async fn snapshot(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, false) {
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
pub async fn devices(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, false) {
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
    let r = match authorize(&app, &headers, true) {
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
    match tokio::task::spawn_blocking(move || {
        r.receive_context(&b.profile_id, &b.boot_id, b.generation)?;
        let store = profile.store.lock().unwrap();
        if store.document.revision != b.profile_revision {
            return Err("state_conflict");
        }
        let device = store
            .document
            .audio
            .input_device
            .clone()
            .ok_or("audio_unconfigured")?;
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
        Ok(Err(e)) => error(e),
        Err(_) => error("audio_unavailable"),
    }
}
pub async fn stop(
    State(app): State<App>,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, true) {
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
    match r.receive_stop(&b.profile_id, &b.boot_id, b.generation, &b.job_id) {
        Ok(v) => (StatusCode::ACCEPTED, Json(v)).into_response(),
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
    let r = match authorize(&app, &headers, false) {
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
        Ok(v) => Json(v).into_response(),
        Err(e) => error(e),
    }
}
