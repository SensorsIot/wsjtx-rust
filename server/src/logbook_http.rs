//! WstxContact::ContactWire log routes: POST/GET /contacts, GET /contacts/export.adi,
//! POST /contacts/imports, GET/PUT /contacts/imports/{id} and POST /contact/worked.
//! Validation order follows WstxOperatingReceive S2: route, Origin, TLS/session,
//! size/media/syntax, version/UUIDs/integers, profile, boot, state. Every log mutation
//! publishes its atomic replace only under the authorization lock with the operating
//! grant (HTTPS) or runtime token (plaintext) rechecked.
use crate::logbook::{self, Record, SaveOutcome, StoreError};
use crate::*;
use axum::extract::{Path, RawQuery};
use axum::http::Method;
use serde::Deserialize;
use std::collections::HashMap;

/// SaveContact body cap: a 1024-character comment stays admissible with worst-case
/// two-byte JSON escaping of every character (#10 decision 2026-10-31).
pub const SAVE_BODY_MAX: usize = 8192;

pub fn error(code: &str, field: Option<&str>) -> Response {
    let status = match code {
        "forbidden_origin" | "wrong_profile" => StatusCode::FORBIDDEN,
        "unauthorized" => StatusCode::UNAUTHORIZED,
        "unsupported_media_type" => StatusCode::UNSUPPORTED_MEDIA_TYPE,
        "request_too_large" => StatusCode::PAYLOAD_TOO_LARGE,
        "invalid_request" | "unsupported_version" | "out_of_range" | "log_invalid_field" => {
            StatusCode::BAD_REQUEST
        }
        "not_found" => StatusCode::NOT_FOUND,
        "import_failed" => StatusCode::UNPROCESSABLE_ENTITY,
        "storage_unavailable" => StatusCode::SERVICE_UNAVAILABLE,
        _ => StatusCode::CONFLICT,
    };
    profile_error(status, code, field)
}
/// Boxed refusal response for helpers (keeps their `Result` small).
type Refused = Box<Response>;
fn refuse(code: &str, field: Option<&str>) -> Refused {
    Box::new(error(code, field))
}
fn stored(e: StoreError) -> Response {
    match e {
        StoreError::Unavailable => error("storage_unavailable", None),
        StoreError::Unauthorized(e) => authorization_http::mapped(e),
    }
}
async fn authorize(
    app: &App,
    headers: &HeaderMap,
    mutation: bool,
) -> Result<Arc<ProfileState>, Refused> {
    let Some(state) = app.profile.clone() else {
        return Err(refuse("not_found", None));
    };
    if (mutation || headers.contains_key(header::ORIGIN)) && !allowed_origin(headers, app) {
        return Err(refuse("forbidden_origin", None));
    }
    authorization_http::operating_access_async(headers, app)
        .await
        .map_err(|e| Box::new(authorization_http::mapped(e)))?;
    Ok(state)
}
fn single_media(headers: &HeaderMap, expected: &str) -> bool {
    let mut types = headers.get_all(header::CONTENT_TYPE).iter();
    let first = types.next().and_then(|v| v.to_str().ok()).unwrap_or("");
    types.next().is_none()
        && !headers.contains_key(header::CONTENT_ENCODING)
        && first.eq_ignore_ascii_case(expected)
}
fn json_body(
    headers: &HeaderMap,
    body: Result<Bytes, BytesRejection>,
    cap: usize,
) -> Result<Value, Refused> {
    if headers.get_all(header::CONTENT_TYPE).iter().count() != 1
        || headers.contains_key(header::CONTENT_ENCODING)
        || !json_media_type(headers)
    {
        return Err(refuse("unsupported_media_type", None));
    }
    let bytes = body.map_err(|_| refuse("request_too_large", None))?;
    if bytes.len() > cap {
        return Err(refuse("request_too_large", None));
    }
    serde_json::from_slice(&bytes).map_err(|_| refuse("invalid_request", None))
}
/// Exact keys, v, profile_id and boot_id; returns the object for further keys.
fn envelope<'a>(
    value: &'a Value,
    keys: &[&str],
) -> Result<&'a serde_json::Map<String, Value>, Refused> {
    let object = value
        .as_object()
        .ok_or_else(|| refuse("invalid_request", None))?;
    if object.len() != keys.len() || keys.iter().any(|k| !object.contains_key(*k)) {
        let extra = object.keys().find(|k| !keys.contains(&k.as_str()));
        let missing = keys.iter().find(|k| !object.contains_key(**k));
        return Err(refuse(
            "invalid_request",
            extra.map(String::as_str).or(missing.copied()),
        ));
    }
    for key in ["profile_id", "boot_id"] {
        if !object[key].as_str().is_some_and(profile::valid_uuid) {
            return Err(refuse("invalid_request", Some(key)));
        }
    }
    if !object["v"].is_u64() {
        return Err(refuse("invalid_request", Some("v")));
    }
    if object["v"] != 1 {
        return Err(refuse("unsupported_version", Some("v")));
    }
    Ok(object)
}
fn context(state: &ProfileState, object: &serde_json::Map<String, Value>) -> Result<(), Refused> {
    let profile_id = state
        .store
        .lock()
        .map_err(|_| refuse("storage_unavailable", None))?
        .document
        .profile_id
        .clone();
    if object["profile_id"] != profile_id.as_str() {
        return Err(refuse("wrong_profile", Some("profile_id")));
    }
    if object["boot_id"] != state.boot.as_str() {
        return Err(refuse("state_conflict", Some("boot_id")));
    }
    Ok(())
}
/// The publication gate: the replace runs only while the authorization lock is held
/// and the request's operating authority is still current (revocation wins).
fn gated<T>(
    app: &App,
    headers: &HeaderMap,
    state: &ProfileState,
    action: impl FnOnce(logbook::Gate) -> T,
) -> T {
    let gate = |publish: &mut dyn FnMut() -> std::io::Result<()>| {
        let owner = state
            .authorization
            .lock()
            .map_err(|_| authorization::Error::PersistenceFailed)?;
        authorization_http::configuration_access(headers, app, owner.as_ref())?;
        Ok(publish())
    };
    action(&gate)
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct WireRecord {
    contact_id: String,
    call: String,
    #[serde(deserialize_with = "nullable")]
    gridsquare: Option<String>,
    mode: String,
    #[serde(deserialize_with = "nullable")]
    submode: Option<String>,
    #[serde(deserialize_with = "nullable")]
    rst_sent: Option<String>,
    #[serde(deserialize_with = "nullable")]
    rst_rcvd: Option<String>,
    qso_date: String,
    time_on: String,
    qso_date_off: String,
    time_off: String,
    #[serde(deserialize_with = "nullable")]
    band: Option<String>,
    #[serde(deserialize_with = "nullable")]
    freq: Option<String>,
    station_callsign: String,
    #[serde(deserialize_with = "nullable")]
    my_gridsquare: Option<String>,
    #[serde(deserialize_with = "nullable")]
    tx_pwr: Option<String>,
    #[serde(deserialize_with = "nullable")]
    comment: Option<String>,
    /// Contest exchange field (#24 S2b), optional.
    #[serde(default)]
    stx: Option<String>,
    /// Contest exchange field (#24 S2b), optional.
    #[serde(default)]
    stx_string: Option<String>,
    /// Contest exchange field (#24 S2b), optional.
    #[serde(default)]
    srx: Option<String>,
    /// Contest exchange field (#24 S2b), optional.
    #[serde(default)]
    contest_id: Option<String>,
    /// Contest exchange field (#24 S2b), optional.
    #[serde(default)]
    srx_string: Option<String>,
    /// Contest exchange field (#24 S2b), optional.
    #[serde(default, rename = "class")]
    class_: Option<String>,
    /// Contest exchange field (#24 S2b), optional.
    #[serde(default)]
    arrl_sect: Option<String>,
    /// Contest exchange field (#24 S2b), optional.
    #[serde(default)]
    state: Option<String>,
}
fn nullable<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Option<String>, D::Error> {
    Option::<String>::deserialize(d)
}
impl WireRecord {
    fn record(self) -> Record {
        Record {
            contact_id: self.contact_id,
            values: [
                Some(self.call),
                self.gridsquare,
                Some(self.mode),
                self.submode,
                self.rst_sent,
                self.rst_rcvd,
                Some(self.qso_date),
                Some(self.time_on),
                Some(self.qso_date_off),
                Some(self.time_off),
                self.band,
                self.freq,
                Some(self.station_callsign),
                self.my_gridsquare,
                self.tx_pwr,
                self.comment,
                self.stx,
                self.stx_string,
                self.srx,
                self.contest_id,
                self.srx_string,
                self.class_,
                self.arrl_sect,
                self.state,
                None,
                None,
                None,
                None,
                None,
                None,
                None,
            ],
            source: None,
            unknown: Vec::new(),
        }
    }
}

/// POST /contacts (SaveContact): 201 saved, 200 already_saved, 409 log_conflict,
/// 400 log_invalid_field, 503 storage_unavailable (the review stays unsaved).
pub async fn save(
    State(app): State<App>,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let state = match authorize(&app, &headers, true).await {
        Ok(s) => s,
        Err(r) => return *r,
    };
    let value = match json_body(&headers, body, SAVE_BODY_MAX) {
        Ok(v) => v,
        Err(r) => return *r,
    };
    let object = match envelope(
        &value,
        &["v", "profile_id", "boot_id", "command_id", "record"],
    ) {
        Ok(o) => o.clone(),
        Err(r) => return *r,
    };
    if !object["command_id"]
        .as_str()
        .is_some_and(profile::valid_uuid)
    {
        return error("invalid_request", Some("command_id"));
    }
    let record: WireRecord = match serde_json::from_value(object["record"].clone()) {
        Ok(r) => r,
        Err(_) => return error("invalid_request", Some("record")),
    };
    tokio::task::spawn_blocking(move || {
        if let Err(r) = context(&state, &object) {
            return *r;
        }
        let command_id = object["command_id"].as_str().unwrap_or_default().to_owned();
        let body = Value::Object(object.clone());
        match state.logbook.receipt(&command_id) {
            Err(e) => return stored(e),
            Ok(Some((retained, status, response))) => {
                return if retained == body {
                    (
                        StatusCode::from_u16(status).unwrap_or(StatusCode::OK),
                        Json(response),
                    )
                        .into_response()
                } else {
                    error("state_conflict", Some("command_id"))
                };
            }
            Ok(None) => {}
        }
        let (callsign, locator) = match state.store.lock() {
            Ok(store) => (
                store.document.callsign.clone(),
                crate::contact_http::station_locator(&store.document.locator).unwrap_or_default(),
            ),
            Err(_) => return error("storage_unavailable", None),
        };
        if callsign.is_empty() {
            return error("profile_incomplete", Some("record.station_callsign"));
        }
        let record = record.record();
        if let Err(field) = logbook::validate_record(&record, &callsign, &locator) {
            return error("log_invalid_field", Some(field));
        }
        let id = record.contact_id.clone();
        let sent = record.clone();
        let outcome = gated(&app, &headers, &state, |gate| {
            state.logbook.save(record, gate)
        });
        let (status, response) = match outcome {
            Ok(SaveOutcome::Saved) => {
                // WstxUdp: QSO Logged and Logged ADIF of the newly stored contact.
                crate::udp::logged(&state, &sent);
                (
                    StatusCode::CREATED,
                    json!({"v":1,"contact_id":id,"outcome":"saved"}),
                )
            }
            Ok(SaveOutcome::AlreadySaved) => (
                StatusCode::OK,
                json!({"v":1,"contact_id":id,"outcome":"already_saved"}),
            ),
            Ok(SaveOutcome::Conflict) => return error("log_conflict", Some("record")),
            Err(e) => return stored(e),
        };
        state.logbook.retain_receipt(logbook::Receipt {
            command_id,
            body,
            status: status.as_u16(),
            response: response.clone(),
        });
        (status, Json(response)).into_response()
    })
    .await
    .unwrap_or_else(|_| error("storage_unavailable", None))
}

fn query(raw: Option<String>, allowed: &[&str]) -> Result<HashMap<String, String>, Refused> {
    let mut values = HashMap::new();
    for part in raw
        .as_deref()
        .unwrap_or("")
        .split('&')
        .filter(|p| !p.is_empty())
    {
        let (key, value) = part
            .split_once('=')
            .ok_or_else(|| refuse("invalid_request", None))?;
        if !allowed.contains(&key) {
            return Err(refuse("invalid_request", None));
        }
        if values.insert(key.to_owned(), value.to_owned()).is_some() {
            return Err(refuse(
                "invalid_request",
                Some(allowed.iter().find(|k| **k == key).copied().unwrap_or("")),
            ));
        }
    }
    Ok(values)
}
fn integer(
    values: &HashMap<String, String>,
    key: &'static str,
    default: usize,
) -> Result<usize, Refused> {
    match values.get(key) {
        None => Ok(default),
        Some(v) if !v.is_empty() && v.len() <= 16 && v.bytes().all(|b| b.is_ascii_digit()) => {
            v.parse().map_err(|_| refuse("invalid_request", Some(key)))
        }
        Some(_) => Err(refuse("invalid_request", Some(key))),
    }
}

/// GET /contacts?cursor=&limit= (ContactHistory).
pub async fn history(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(raw): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let state = match authorize(&app, &headers, false).await {
        Ok(s) => s,
        Err(r) => return *r,
    };
    if !matches!(&body, Ok(b) if b.is_empty()) {
        return error("invalid_request", None);
    }
    let values = match query(raw, &["cursor", "limit"]) {
        Ok(v) => v,
        Err(r) => return *r,
    };
    let (cursor, limit) = match (
        integer(&values, "cursor", 0),
        integer(&values, "limit", logbook::HISTORY_PAGE_RECORDS_MAX),
    ) {
        (Ok(c), Ok(l)) => (c, l),
        (Err(r), _) | (_, Err(r)) => return *r,
    };
    if !(1..=logbook::HISTORY_PAGE_RECORDS_MAX).contains(&limit) {
        return error("out_of_range", Some("limit"));
    }
    tokio::task::spawn_blocking(move || {
        let profile_id = match state.store.lock() {
            Ok(store) => store.document.profile_id.clone(),
            Err(_) => return error("storage_unavailable", None),
        };
        match state.logbook.total() {
            Ok(total) if cursor > total => return error("out_of_range", Some("cursor")),
            Err(e) => return stored(e),
            Ok(_) => {}
        }
        match state.logbook.history(&profile_id, cursor, limit) {
            Ok(page) => Json(page).into_response(),
            Err(e) => stored(e),
        }
    })
    .await
    .unwrap_or_else(|_| error("storage_unavailable", None))
}

/// GET /contacts/export.adi (ExportAdi), identity coding, attachment contacts.adi.
pub async fn export(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(raw): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let state = match authorize(&app, &headers, false).await {
        Ok(s) => s,
        Err(r) => return *r,
    };
    if raw.is_some() || !matches!(&body, Ok(b) if b.is_empty()) {
        return error("invalid_request", None);
    }
    // The snapshot is taken off the runtime; the records are formatted chunk by chunk as
    // the connection takes them (chunked transfer, no Content-Length), so a large log is
    // never built in memory at once (WstxContact::ExportAdi).
    match tokio::task::spawn_blocking(move || state.logbook.export()).await {
        Ok(Ok(stream)) => (
            StatusCode::OK,
            [
                (header::CONTENT_TYPE, "application/octet-stream"),
                (
                    header::CONTENT_DISPOSITION,
                    "attachment; filename=\"contacts.adi\"",
                ),
            ],
            axum::body::Body::from_stream(stream),
        )
            .into_response(),
        Ok(Err(e)) => stored(e),
        Err(_) => error("storage_unavailable", None),
    }
}

/// POST /contact/worked (WorkedBeforeQuery), read-only.
pub async fn worked(
    State(app): State<App>,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let state = match authorize(&app, &headers, true).await {
        Ok(s) => s,
        Err(r) => return *r,
    };
    let value = match json_body(&headers, body, 2048) {
        Ok(v) => v,
        Err(r) => return *r,
    };
    let object = match envelope(
        &value,
        &["v", "profile_id", "boot_id", "band", "mode", "calls"],
    ) {
        Ok(o) => o.clone(),
        Err(r) => return *r,
    };
    let Some(band) = object["band"].as_str().filter(|b| logbook::valid_band(b)) else {
        return error("invalid_request", Some("band"));
    };
    let Some(mode) = object["mode"]
        .as_str()
        .filter(|m| matches!(*m, "FT8" | "FT4"))
    else {
        return error("invalid_request", Some("mode"));
    };
    let Some(calls) = object["calls"]
        .as_array()
        .filter(|c| c.len() <= logbook::WORKED_CALLS_MAX)
    else {
        return error("invalid_request", Some("calls"));
    };
    let mut list = Vec::new();
    for call in calls {
        match call.as_str() {
            Some(c)
                if (1..=13).contains(&c.len())
                    && c.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'/') =>
            {
                list.push(c.to_ascii_uppercase())
            }
            _ => return error("invalid_request", Some("calls")),
        }
    }
    let (band, mode) = (band.to_owned(), mode.to_owned());
    tokio::task::spawn_blocking(move || {
        if let Err(r) = context(&state, &object) {
            return *r;
        }
        match state.logbook.worked(&list, &band, &mode) {
            Ok(statuses) => {
                let statuses: Vec<Value> = list
                    .iter()
                    .zip(statuses)
                    .map(|(call, status)| json!({"call":call,"status":status}))
                    .collect();
                Json(json!({"v":1,"band":band,"mode":mode,"statuses":statuses})).into_response()
            }
            Err(e) => stored(e),
        }
    })
    .await
    .unwrap_or_else(|_| error("storage_unavailable", None))
}

/// #55 WstxDxcc::CountryFile view: which cty.dat the station uses.
fn dxcc_view(state: &ProfileState) -> Value {
    let (table, unreadable) = state.logbook.dxcc();
    let r = &state.recording;
    json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,
        "source":if table.uploaded {"uploaded"} else {"bundled"},
        "version":table.cty.version(),"entities":table.cty.entity_count(),
        "upload_unreadable":unreadable})
}
/// GET /dxcc[?call=X], read-only; with a call (1..13 of A-Z 0-9 /) also its compact
/// entity (null: none), for the QSO pane.
pub async fn dxcc(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
) -> Response {
    let state = match authorize(&app, &headers, false).await {
        Ok(s) => s,
        Err(r) => return *r,
    };
    let mut view = dxcc_view(&state);
    if let Some(query) = query {
        let Some(call) = query
            .strip_prefix("call=")
            .filter(|c| (1..=13).contains(&c.len()))
            .filter(|c| c.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'/'))
        else {
            return error("invalid_request", Some("call"));
        };
        let (table, _) = state.logbook.dxcc();
        let me = contact_http::profile_facts(&state)
            .1
            .as_deref()
            .and_then(crate::strategy::maidenhead);
        view["entity"] = json!(table.lookup(call).map(|r| crate::dxcc::compact(&r, me)));
    }
    Json(view).into_response()
}
/// PUT /dxcc {v, profile_id, boot_id, text}: text replaces this profile's cty.dat after
/// it parses; null returns to the bundled file. A refused text changes nothing.
pub async fn dxcc_put(
    State(app): State<App>,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let state = match authorize(&app, &headers, true).await {
        Ok(s) => s,
        Err(r) => return *r,
    };
    let value = match json_body(&headers, body, DXCC_BODY_MAX) {
        Ok(v) => v,
        Err(r) => return *r,
    };
    let object = match envelope(&value, &["v", "profile_id", "boot_id", "text"]) {
        Ok(o) => o.clone(),
        Err(r) => return *r,
    };
    let text = match &object["text"] {
        Value::Null => None,
        Value::String(t) if t.len() <= crate::dxcc::FILE_BYTES_MAX => Some(t.clone()),
        _ => return error("invalid_request", Some("text")),
    };
    tokio::task::spawn_blocking(move || {
        if let Err(r) = context(&state, &object) {
            return *r;
        }
        match gated(&app, &headers, &state, |gate| {
            state.logbook.replace_dxcc(text.as_deref(), gate)
        }) {
            Ok(()) => Json(dxcc_view(&state)).into_response(),
            Err(logbook::DxccError::Invalid(line)) => (
                StatusCode::BAD_REQUEST,
                Json(json!({"error":{"code":"invalid_cty","field":"text","line":line}})),
            )
                .into_response(),
            Err(logbook::DxccError::Store(e)) => stored(e),
        }
    })
    .await
    .unwrap_or_else(|_| error("storage_unavailable", None))
}
/// PUT /dxcc body cap: an uploaded file of FILE_BYTES_MAX with JSON escaping of its line
/// breaks and the envelope.
pub const DXCC_BODY_MAX: usize = 2 * crate::dxcc::FILE_BYTES_MAX;

/// POST /contacts/imports: 201 new reservation, 200 identical retry.
pub async fn reserve(
    State(app): State<App>,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let state = match authorize(&app, &headers, true).await {
        Ok(s) => s,
        Err(r) => return *r,
    };
    let value = match json_body(&headers, body, 1024) {
        Ok(v) => v,
        Err(r) => return *r,
    };
    let object = match envelope(
        &value,
        &[
            "v",
            "profile_id",
            "boot_id",
            "import_id",
            "total_bytes",
            "sha256",
        ],
    ) {
        Ok(o) => o.clone(),
        Err(r) => return *r,
    };
    let Some(id) = object["import_id"]
        .as_str()
        .filter(|i| profile::valid_uuid(i))
        .map(str::to_owned)
    else {
        return error("invalid_request", Some("import_id"));
    };
    let Some(total) = object["total_bytes"]
        .as_u64()
        .filter(|t| *t <= profile::MAX_REVISION)
    else {
        return error("invalid_request", Some("total_bytes"));
    };
    if total == 0 {
        return error("out_of_range", Some("total_bytes"));
    }
    if total > logbook::IMPORT_BYTES_MAX {
        return error("request_too_large", Some("total_bytes"));
    }
    let Some(sha) = object["sha256"]
        .as_str()
        .filter(|s| {
            s.len() == 64
                && s.bytes()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        })
        .map(str::to_owned)
    else {
        return error("invalid_request", Some("sha256"));
    };
    tokio::task::spawn_blocking(move || {
        if let Err(r) = context(&state, &object) {
            return *r;
        }
        match state.logbook.reserve(&id, total, &sha, Instant::now()) {
            Ok((created, view)) => (
                if created {
                    StatusCode::CREATED
                } else {
                    StatusCode::OK
                },
                [(header::LOCATION, format!("/contacts/imports/{id}"))],
                Json(view),
            )
                .into_response(),
            Err(code) => error(code, None),
        }
    })
    .await
    .unwrap_or_else(|_| error("storage_unavailable", None))
}

/// GET or PUT /contacts/imports/{id}. Chunks: application/octet-stream, exact
/// Content-Range, at most 16384 bytes, in order. The completing chunk returns 201.
pub async fn import(
    State(app): State<App>,
    Path(id): Path<String>,
    method: Method,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let state = match authorize(&app, &headers, method != Method::GET).await {
        Ok(s) => s,
        Err(r) => return *r,
    };
    if method == Method::PUT && !single_media(&headers, "application/octet-stream") {
        return error("unsupported_media_type", None);
    }
    let Ok(bytes) = body else {
        return error("request_too_large", None);
    };
    let cap = if method == Method::PUT {
        logbook::IMPORT_CHUNK_BYTES_MAX
    } else {
        0
    };
    if bytes.len() > cap {
        return error(
            if method == Method::PUT {
                "request_too_large"
            } else {
                "invalid_request"
            },
            None,
        );
    }
    if !profile::valid_uuid(&id) {
        return error("invalid_request", None);
    }
    if method == Method::GET {
        return match tokio::task::spawn_blocking(move || state.logbook.import_view(&id)).await {
            Ok(Ok(v)) => Json(v).into_response(),
            Ok(Err(c)) => error(c, None),
            Err(_) => error("storage_unavailable", None),
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
        return error("invalid_request", None);
    };
    if ranges.next().is_some()
        || [start, end, total]
            .iter()
            .any(|s| s.is_empty() || s.len() > 16 || !s.bytes().all(|b| b.is_ascii_digit()))
    {
        return error("invalid_request", None);
    }
    let (Ok(start), Ok(end), Ok(total)) = (
        start.parse::<u64>(),
        end.parse::<u64>(),
        total.parse::<u64>(),
    ) else {
        return error("invalid_request", None);
    };
    if total == 0
        || end >= total
        || end.checked_sub(start).and_then(|n| n.checked_add(1)) != Some(bytes.len() as u64)
        || bytes.is_empty()
    {
        return error("invalid_request", None);
    }
    tokio::task::spawn_blocking(move || {
        let result = gated(&app, &headers, &state, |gate| {
            state
                .logbook
                .chunk(&id, start, total, &bytes, Instant::now(), gate)
        });
        match result {
            Ok(v) => (
                if v["state"] == "completed" {
                    StatusCode::CREATED
                } else {
                    StatusCode::ACCEPTED
                },
                Json(v),
            )
                .into_response(),
            Err("unauthorized") => error("unauthorized", None),
            Err(c) => error(c, None),
        }
    })
    .await
    .unwrap_or_else(|_| error("storage_unavailable", None))
}
