use crate::*;
use axum::{extract::Path, http::Method};
use serde::Deserialize;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Start {
    v: u64,
    profile_id: String,
    boot_id: String,
    generation: u64,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Replay {
    v: u64,
    profile_id: String,
    boot_id: String,
    generation: u64,
    recording_id: String,
}
pub fn error(code: &str) -> Response {
    let status = match code {
        "forbidden_origin" | "wrong_profile" => StatusCode::FORBIDDEN,
        "unauthorized" => StatusCode::UNAUTHORIZED,
        "unsupported_media_type" => StatusCode::UNSUPPORTED_MEDIA_TYPE,
        "request_too_large" => StatusCode::PAYLOAD_TOO_LARGE,
        "invalid_request" | "unsupported_version" => StatusCode::BAD_REQUEST,
        "not_found" => StatusCode::NOT_FOUND,
        "invalid_recording" | "unsupported_audio" | "recording_limit" => {
            StatusCode::UNPROCESSABLE_ENTITY
        }
        "storage_unavailable" => StatusCode::SERVICE_UNAVAILABLE,
        "upload_timeout" => StatusCode::REQUEST_TIMEOUT,
        _ => StatusCode::CONFLICT,
    };
    profile_error(status, code, None)
}
pub(crate) async fn authorize(
    app: &App,
    headers: &HeaderMap,
    mutation: bool,
) -> Result<Arc<recording::Recording>, &'static str> {
    let Some(state) = &app.profile else {
        return Err("not_found");
    };
    if (mutation || headers.contains_key(header::ORIGIN)) && !allowed_origin(headers, app) {
        return Err("forbidden_origin");
    }
    if let Err(error) = authorization_http::operating_access_async(headers, app).await {
        return Err(if error == authorization::Error::Unauthorized {
            "unauthorized"
        } else {
            "storage_unavailable"
        });
    }
    Ok(state.recording.clone())
}
fn media(headers: &HeaderMap, raw: bool) -> bool {
    let mut types = headers.get_all(header::CONTENT_TYPE).iter();
    let text = types
        .next()
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_ascii_lowercase();
    if types.next().is_some() || headers.contains_key(header::CONTENT_ENCODING) {
        return false;
    }
    if raw {
        text == "audio/wav"
    } else {
        json_media_type(headers)
    }
}
fn response(status: StatusCode, value: Value) -> Response {
    (status, Json(value)).into_response()
}
pub async fn snapshot(
    State(app): State<App>,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, false).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    match body {
        Ok(b) if b.is_empty() => Json(r.snapshot()).into_response(),
        Ok(_) => error("invalid_request"),
        Err(_) => error("request_too_large"),
    }
}
pub(crate) fn parse<T: serde::de::DeserializeOwned>(
    headers: &HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Result<T, &'static str> {
    if !media(headers, false) {
        return Err("unsupported_media_type");
    }
    let bytes = body.map_err(|_| "request_too_large")?;
    if bytes.len() > 1024 {
        return Err("request_too_large");
    }
    serde_json::from_slice(&bytes).map_err(|_| "invalid_request")
}
pub(crate) fn syntax(
    v: u64,
    profile: &str,
    boot: &str,
    generation: u64,
) -> Result<(), &'static str> {
    if !profile::valid_uuid(profile)
        || !profile::valid_uuid(boot)
        || generation > profile::MAX_REVISION
    {
        return Err("invalid_request");
    }
    if v != 1 {
        return Err("unsupported_version");
    }
    Ok(())
}
pub async fn reserve(
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
    match r.reserve(&b.profile_id, &b.boot_id, b.generation) {
        Ok(v) => {
            let location = format!("/recording/imports/{}", v["id"].as_str().unwrap());
            (StatusCode::CREATED, [(header::LOCATION, location)], Json(v)).into_response()
        }
        Err(code) => error(code),
    }
}
pub async fn replay(
    State(app): State<App>,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, true).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    let b: Replay = match parse(&headers, body) {
        Ok(b) => b,
        Err(e) => return error(e),
    };
    if !profile::valid_uuid(&b.recording_id) {
        return error("invalid_request");
    }
    if let Err(e) = syntax(b.v, &b.profile_id, &b.boot_id, b.generation) {
        return error(e);
    }
    match r.replay(&b.profile_id, &b.boot_id, b.generation, &b.recording_id) {
        Ok(v) => response(StatusCode::ACCEPTED, v),
        Err(code) => error(code),
    }
}
pub async fn import(
    State(app): State<App>,
    Path(id): Path<String>,
    method: Method,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, method != Method::GET).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    if method == Method::PUT && !media(&headers, true) {
        return error("unsupported_media_type");
    }
    let bytes = match body {
        Ok(b) => b,
        Err(rejection) => {
            if method == Method::PUT
                && rejection.status() != StatusCode::PAYLOAD_TOO_LARGE
                && profile::valid_uuid(&id)
            {
                let _ = r.cancel_import(&id);
            }
            return error("request_too_large");
        }
    };
    if bytes.len() > if method == Method::PUT { 2048 } else { 0 } {
        return error(if method == Method::PUT {
            "request_too_large"
        } else {
            "invalid_request"
        });
    }
    if !profile::valid_uuid(&id) {
        return error("invalid_request");
    }
    if method == Method::GET {
        return match r.import_view(&id) {
            Ok(v) => Json(v).into_response(),
            Err(c) => error(c),
        };
    }
    if method == Method::DELETE {
        return match r.cancel_import(&id) {
            Ok(v) => Json(v).into_response(),
            Err(c) => error(c),
        };
    }
    let mut ranges = headers.get_all(header::CONTENT_RANGE).iter();
    let range = ranges
        .next()
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.strip_prefix("bytes "))
        .and_then(|s| s.split_once('/'))
        .and_then(|(r, total)| r.split_once('-').map(|(start, end)| (start, end, total)));
    let Some((start, end, total)) = range else {
        return error("invalid_request");
    };
    if ranges.next().is_some()
        || [start, end, total]
            .iter()
            .any(|s| s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()))
    {
        return error("invalid_request");
    }
    let (Ok(start), Ok(end), Ok(total)) = (
        start.parse::<u64>(),
        end.parse::<u64>(),
        total.parse::<u64>(),
    ) else {
        return error("invalid_request");
    };
    if total > recording::FILE_LIMIT {
        return error("request_too_large");
    }
    if total == 0
        || end >= total
        || end.checked_sub(start).and_then(|n| n.checked_add(1)) != Some(bytes.len() as u64)
        || bytes.is_empty()
    {
        return error("invalid_request");
    }
    if let Err(c) = r.begin_chunk(&id, start, total) {
        return error(c);
    }
    match tokio::task::spawn_blocking(move || r.chunk(&id, start, total, bytes.to_vec())).await {
        Ok(Ok(v)) => response(
            if v["state"] == "completed" {
                StatusCode::CREATED
            } else {
                StatusCode::ACCEPTED
            },
            v,
        ),
        Ok(Err(c)) => error(c),
        Err(_) => error("storage_unavailable"),
    }
}
pub async fn cancel_job(
    State(app): State<App>,
    Path(id): Path<String>,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, true).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    match body {
        Ok(b) if b.is_empty() => {}
        _ => return error("invalid_request"),
    }
    if !profile::valid_uuid(&id) {
        return error("invalid_request");
    }
    match r.cancel_job(&id) {
        Ok(v) => Json(v).into_response(),
        Err(c) => error(c),
    }
}
