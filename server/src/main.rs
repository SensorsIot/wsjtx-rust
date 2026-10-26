#![forbid(unsafe_code)]
#[cfg(test)]
mod auth_tests;
mod profile;
#[cfg(test)]
mod protocol_tests;
mod recording;
mod recording_http;
mod spectrum;
use axum::{Json, body::Bytes};
use axum::{
    Router,
    extract::{
        State, WebSocketUpgrade,
        rejection::BytesRejection,
        ws::{CloseFrame, Message, WebSocket},
    },
    http::{HeaderMap, StatusCode, header},
    response::{Html, IntoResponse, Response},
    routing::{get, post},
};
use serde_json::{Value, json};
use std::{
    env,
    net::SocketAddr,
    sync::Arc,
    time::{Duration, Instant},
};
use std::{path::PathBuf, sync::Mutex};
use subtle::ConstantTimeEq;
use tokio::{
    sync::Semaphore,
    time::{interval, timeout},
};

struct ProfileState {
    store: Mutex<profile::Store>,
    boot: String,
    recording: Arc<recording::Recording>,
}

#[derive(Clone)]
struct App {
    origin: String,
    profile: Option<Arc<ProfileState>>,
    profile_id: Option<String>,
    token: Option<String>,
    connections: Arc<Semaphore>,
    login_attempts: Arc<std::sync::Mutex<(Instant, u8)>>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    rustls::crypto::ring::default_provider()
        .install_default()
        .ok();
    let args: Vec<_> = env::args_os().skip(1).collect();
    let selected = match args.as_slice() {
        [] => None,
        [command, directory] if command == "--create-profile" || command == "--profile" => {
            let directory = PathBuf::from(directory);
            if command == "--create-profile" {
                let target = directory.clone();
                tokio::task::spawn_blocking(move || profile::Store::create(&target)).await?
                    .map_err(|code| startup_error(code, &directory))?;
                return Ok(());
            }
            Some(directory)
        }
        _ => return Err("invalid_runtime_configuration: expected --profile <directory> or --create-profile <directory>".into()),
    };
    let error = |code: &str, legacy: &str| -> Box<dyn std::error::Error> {
        if let Some(path) = &selected {
            startup_error(code, path).into()
        } else {
            legacy.to_owned().into()
        }
    };
    if selected.is_some()
        && (env::var_os("WSTX_BIND").is_some() || env::var_os("WSTX_ORIGIN").is_some())
    {
        return Err(error("invalid_runtime_configuration", ""));
    }
    let loaded = if let Some(path) = &selected {
        let path = path.clone();
        Some(
            tokio::task::spawn_blocking(move || profile::Store::open(&path))
                .await?
                .map_err(|code| error(code, ""))?,
        )
    } else {
        None
    };
    let addr: SocketAddr = match &loaded {
        Some((_, addr)) => *addr,
        None => env::var("WSTX_BIND")
            .unwrap_or_else(|_| "127.0.0.1:8080".into())
            .parse()?,
    };
    let saved_origin = loaded
        .as_ref()
        .and_then(|(store, _)| store.document.endpoint.origin.clone());
    let configured_origin = if selected.is_some() {
        saved_origin
    } else {
        env::var("WSTX_ORIGIN").ok()
    };
    let token = env::var("WSTX_TOKEN").ok();
    let cert = env::var("WSTX_TLS_CERT").ok();
    let key = env::var("WSTX_TLS_KEY").ok();
    let tls_requested = cert.is_some() && key.is_some();
    if cert.is_some() != key.is_some() {
        return Err(error(
            "invalid_runtime_configuration",
            "Both WSTX_TLS_CERT and WSTX_TLS_KEY are required",
        ));
    }
    if token.as_ref().is_some_and(|s| {
        !(32..=128).contains(&s.len()) || !s.bytes().all(|c| c.is_ascii_alphanumeric())
    }) {
        return Err(error(
            "invalid_runtime_configuration",
            "WSTX_TOKEN requires 32 through 128 ASCII letters/digits",
        ));
    }
    if !addr.ip().is_loopback()
        && (!tls_requested || token.is_none() || configured_origin.is_none())
    {
        return Err(error(
            "invalid_runtime_configuration",
            "Remote binding requires TLS, WSTX_TOKEN and WSTX_ORIGIN",
        ));
    }
    if tls_requested && token.is_none() {
        return Err(error(
            "invalid_runtime_configuration",
            "TLS mode requires WSTX_TOKEN",
        ));
    }
    if token.is_some() && !tls_requested {
        return Err(error(
            "invalid_runtime_configuration",
            "WSTX_TOKEN requires TLS",
        ));
    }
    let scheme = if tls_requested { "https" } else { "http" };
    if let Some(origin) = &configured_origin
        && profile::parse_origin(origin).is_none_or(|uri| uri.scheme_str() != Some(scheme))
    {
        return Err(error(
            "invalid_runtime_configuration",
            "WSTX_ORIGIN must match the listener scheme, without a trailing slash",
        ));
    }
    if let Some((store, _)) = &loaded {
        let effective_origin = configured_origin
            .clone()
            .unwrap_or_else(|| format!("{scheme}://{addr}"));
        store
            .document
            .admit_response_budget(&effective_origin)
            .map_err(|code| error(code, ""))?;
    }
    let tls = match (cert, key) {
        (Some(cert), Some(key)) => Some(
            axum_server::tls_rustls::RustlsConfig::from_pem_file(cert, key)
                .await
                .map_err(|_| error("resource_unavailable", "TLS certificate/key unavailable"))?,
        ),
        _ => None,
    };
    let listener = std::net::TcpListener::bind(addr).map_err(|e| {
        error(
            if e.kind() == std::io::ErrorKind::AddrInUse {
                "endpoint_in_use"
            } else {
                "resource_unavailable"
            },
            "Listener unavailable",
        )
    })?;
    listener
        .set_nonblocking(true)
        .map_err(|_| error("resource_unavailable", "Listener unavailable"))?;
    let address = listener
        .local_addr()
        .map_err(|_| error("resource_unavailable", "Listener unavailable"))?;
    let origin = configured_origin.unwrap_or_else(|| format!("{scheme}://{address}"));
    if let Some((store, _)) = &loaded {
        println!(
            "WSTX profile {} {}",
            store.document.profile_id, store.document.display_name
        );
    }
    let profile_id = loaded
        .as_ref()
        .map(|(store, _)| store.document.profile_id.clone());
    let profile = match loaded {
        Some((store, _)) => {
            let boot = profile::new_uuid().map_err(|_| error("resource_unavailable", ""))?;
            let base = selected.clone().ok_or("profile directory absent")?;
            let id = store.document.profile_id.clone();
            let recording_boot = boot.clone();
            let recording = tokio::task::spawn_blocking(move || {
                recording::Recording::open(&base, id, recording_boot)
            })
            .await?;
            let watched = recording.clone();
            tokio::spawn(async move {
                let mut timer = interval(Duration::from_millis(50));
                loop {
                    timer.tick().await;
                    watched.tick();
                }
            });
            Some(Arc::new(ProfileState {
                store: Mutex::new(store),
                boot,
                recording,
            }))
        }
        None => None,
    };
    let state = App {
        origin: origin.clone(),
        profile,
        profile_id,
        token,
        connections: Arc::new(Semaphore::new(16)),
        login_attempts: Arc::new(Mutex::new((Instant::now(), 0))),
    };
    let app = Router::new()
        .route("/", get(index))
        .route("/app.js", get(|| async { ([(header::CONTENT_TYPE, "text/javascript; charset=utf-8")], include_str!("../../client/app.js")) }))
        .route("/recording.js", get(|| async { ([(header::CONTENT_TYPE, "text/javascript; charset=utf-8")], include_str!("../../client/recording.js")) }))
        .route("/recording.css", get(|| async { ([(header::CONTENT_TYPE, "text/css; charset=utf-8")], include_str!("../../client/recording.css")) }))
        .route("/style.css", get(|| async { ([(header::CONTENT_TYPE, "text/css; charset=utf-8")], include_str!("../../client/style.css")) }))
        .route("/session", post(session).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/profile", get(get_profile).put(put_profile))
        .route("/recording", get(recording_http::snapshot))
        .route("/recording/imports", post(recording_http::reserve).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/recording/imports/{id}", get(recording_http::import).put(recording_http::import).delete(recording_http::import).layer(axum::extract::DefaultBodyLimit::max(2048)))
        .route("/recording/replay", post(recording_http::replay).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/recording/jobs/{id}", axum::routing::delete(recording_http::cancel_job))
        .route("/ws", get(upgrade))
        .layer(axum::extract::DefaultBodyLimit::max(8192))
        .layer(axum::middleware::from_fn(|request, next: axum::middleware::Next| async move {
            let mut response = next.run(request).await;
            let headers = response.headers_mut();
            headers.insert("content-security-policy", "default-src 'self'; connect-src 'self'; script-src 'self'; style-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'".parse().unwrap());
            headers.insert("x-content-type-options", "nosniff".parse().unwrap());
            headers.insert(header::CACHE_CONTROL, "no-store".parse().unwrap());
            response
        }))
        .with_state(state);
    println!("WSTX address {scheme}://{address}");
    if let Some(tls) = tls {
        let server = axum_server::from_tcp_rustls(listener, tls)
            .map_err(|_| error("resource_unavailable", "Listener unavailable"))?;
        println!("WSTX listening {origin}");
        server.serve(app.into_make_service()).await?;
    } else {
        let listener = tokio::net::TcpListener::from_std(listener)
            .map_err(|_| error("resource_unavailable", "Listener unavailable"))?;
        println!("WSTX listening {origin}");
        axum::serve(listener, app).await?;
    }
    Ok(())
}
fn startup_error(code: &str, path: &std::path::Path) -> String {
    let path: String = path
        .to_string_lossy()
        .chars()
        .filter(|c| !c.is_control())
        .take(240)
        .collect();
    format!("{code}: selected profile {path}")
}
async fn index(State(app): State<App>) -> Html<String> {
    Html(include_str!("../../client/index.html").replace(
        "</head>", if app.profile.is_some() { "<link rel=\"stylesheet\" href=\"/recording.css\"><script src=\"/recording.js\" defer></script></head>" } else { "</head>" }
    ).replace(
        "data-profile=\"false\"",
        if app.profile.is_some() {
            "data-profile=\"true\""
        } else {
            "data-profile=\"false\""
        },
    ))
}
fn cookie_name(app: &App) -> String {
    app.profile_id
        .as_ref()
        .map_or_else(|| "wstx_session".into(), |id| format!("wstx_session_{id}"))
}
fn cookie_value(app: &App, token: &str) -> String {
    app.profile_id
        .as_ref()
        .map_or_else(|| token.to_owned(), |id| format!("{id}.{token}"))
}
fn authenticated(headers: &HeaderMap, app: &App) -> bool {
    let Some(token) = &app.token else {
        return true;
    };
    let name = cookie_name(app);
    let expected = cookie_value(app, token);
    if app.profile_id.is_none() {
        return headers
            .get(header::COOKIE)
            .and_then(|h| h.to_str().ok())
            .is_some_and(|h| {
                h.split(';').any(|part| {
                    part.trim()
                        .strip_prefix("wstx_session=")
                        .is_some_and(|value| equal_secret(value, token))
                })
            });
    }
    let mut values = headers
        .get_all(header::COOKIE)
        .iter()
        .filter_map(|h| h.to_str().ok())
        .flat_map(|h| h.split(';'))
        .filter_map(|part| part.trim().split_once('='))
        .filter_map(|(n, value)| (n == name).then_some(value));
    let first = values.next();
    first.is_some_and(|value| equal_secret(value, &expected))
        && (app.profile_id.is_none() || values.next().is_none())
}
fn profile_error(status: StatusCode, code: &str, field: Option<&str>) -> Response {
    (status, Json(json!({"error":{"code":code,"field":field}}))).into_response()
}
fn representation(state: &ProfileState, doc: &profile::Document, origin: &str) -> Value {
    profile::representation(doc, &state.boot, origin)
}
async fn get_profile(State(app): State<App>, headers: HeaderMap) -> Response {
    let Some(state) = app.profile.clone() else {
        return StatusCode::NOT_FOUND.into_response();
    };
    if headers.contains_key(header::ORIGIN) && !allowed_origin(&headers, &app) {
        return profile_error(StatusCode::FORBIDDEN, "forbidden_origin", None);
    }
    if !authenticated(&headers, &app) {
        return profile_error(StatusCode::UNAUTHORIZED, "unauthorized", None);
    }
    match tokio::task::spawn_blocking(move || match state.store.lock() {
        Ok(store) => Json(representation(&state, &store.document, &app.origin)).into_response(),
        Err(_) => profile_error(StatusCode::SERVICE_UNAVAILABLE, "storage_unavailable", None),
    })
    .await
    {
        Ok(response) => response,
        _ => profile_error(StatusCode::SERVICE_UNAVAILABLE, "storage_unavailable", None),
    }
}
fn json_media_type(headers: &HeaderMap) -> bool {
    let content_type = headers
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_ascii_lowercase();
    let parts: Vec<_> = content_type.split(';').map(str::trim).collect();
    parts.first() == Some(&"application/json")
        && parts.len() <= 2
        && !parts.get(1).is_some_and(|s| *s != "charset=utf-8")
}
async fn put_profile(
    State(app): State<App>,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let Some(state) = app.profile.clone() else {
        return StatusCode::NOT_FOUND.into_response();
    };
    if !allowed_origin(&headers, &app) {
        return profile_error(StatusCode::FORBIDDEN, "forbidden_origin", None);
    }
    if !authenticated(&headers, &app) {
        return profile_error(StatusCode::UNAUTHORIZED, "unauthorized", None);
    }
    if !json_media_type(&headers) {
        return profile_error(
            StatusCode::UNSUPPORTED_MEDIA_TYPE,
            "unsupported_media_type",
            None,
        );
    }
    let Ok(body) = body else {
        return profile_error(StatusCode::PAYLOAD_TOO_LARGE, "request_too_large", None);
    };
    let mut deserializer = serde_json::Deserializer::from_slice(&body);
    let edit: profile::Edit = match serde_path_to_error::deserialize(&mut deserializer) {
        Ok(value) => value,
        Err(error) => {
            let path = error.path().to_string();
            let known = [
                "profile_id",
                "revision",
                "settings",
                "settings.display_name",
                "settings.callsign",
                "settings.locator",
                "settings.audio",
                "settings.audio.input_device",
                "settings.audio.output_device",
                "settings.control",
                "settings.control.mode",
                "settings.control.endpoint",
                "settings.control.ptt",
            ];
            return profile_error(
                StatusCode::BAD_REQUEST,
                "invalid_settings",
                known.contains(&path.as_str()).then_some(path.as_str()),
            );
        }
    };
    if deserializer.end().is_err()
        || !profile::valid_uuid(&edit.profile_id)
        || edit.revision > profile::MAX_REVISION
    {
        return profile_error(StatusCode::BAD_REQUEST, "invalid_settings", None);
    }
    if let Err(field) = edit.settings.validate() {
        return profile_error(StatusCode::BAD_REQUEST, "invalid_settings", Some(field));
    }
    match tokio::task::spawn_blocking(move || {
        let Ok(mut store) = state.store.lock() else {
            return profile_error(StatusCode::SERVICE_UNAVAILABLE, "storage_unavailable", None);
        };
        if store.document.profile_id != edit.profile_id {
            return profile_error(StatusCode::FORBIDDEN, "wrong_profile", None);
        }
        if store.document.revision != edit.revision {
            return profile_error(StatusCode::CONFLICT, "revision_conflict", None);
        }
        if store.document.revision == profile::MAX_REVISION {
            return profile_error(StatusCode::CONFLICT, "revision_exhausted", None);
        }
        if store.save(edit.settings).is_err() {
            return profile_error(StatusCode::SERVICE_UNAVAILABLE, "storage_unavailable", None);
        }
        Json(representation(&state, &store.document, &app.origin)).into_response()
    })
    .await
    {
        Ok(response) => response,
        Err(_) => profile_error(StatusCode::SERVICE_UNAVAILABLE, "storage_unavailable", None),
    }
}

fn allowed_origin(headers: &HeaderMap, app: &App) -> bool {
    let mut origins = headers.get_all(header::ORIGIN).iter();
    origins.next().and_then(|v| v.to_str().ok()) == Some(app.origin.as_str())
        && (app.profile_id.is_none() || origins.next().is_none())
}
fn equal_secret(a: &str, b: &str) -> bool {
    bool::from(a.as_bytes().ct_eq(b.as_bytes()))
}

async fn session(State(app): State<App>, headers: HeaderMap, body: String) -> Response {
    if !allowed_origin(&headers, &app) {
        return StatusCode::FORBIDDEN.into_response();
    }
    {
        let Ok(mut attempts) = app.login_attempts.lock() else {
            return StatusCode::SERVICE_UNAVAILABLE.into_response();
        };
        if attempts.0.elapsed() >= Duration::from_secs(60) {
            *attempts = (Instant::now(), 0);
        }
        if attempts.1 >= 10 {
            return StatusCode::TOO_MANY_REQUESTS.into_response();
        }
        attempts.1 += 1;
    }
    match &app.token {
        Some(token) if equal_secret(&body, token) => (
            StatusCode::NO_CONTENT,
            [(
                header::SET_COOKIE,
                format!(
                    "{}={}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=28800",
                    cookie_name(&app),
                    cookie_value(&app, token)
                ),
            )],
        )
            .into_response(),
        _ => StatusCode::UNAUTHORIZED.into_response(),
    }
}

async fn upgrade(State(app): State<App>, headers: HeaderMap, ws: WebSocketUpgrade) -> Response {
    if !allowed_origin(&headers, &app) {
        return StatusCode::FORBIDDEN.into_response();
    }
    if !authenticated(&headers, &app) {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    if headers
        .get(header::SEC_WEBSOCKET_PROTOCOL)
        .and_then(|v| v.to_str().ok())
        != Some("wstx.v1")
    {
        return StatusCode::BAD_REQUEST.into_response();
    }
    let Ok(permit) = app.connections.try_acquire_owned() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };
    ws.protocols(["wstx.v1"])
        .max_message_size(1024)
        .max_frame_size(1024)
        .write_buffer_size(0)
        .max_write_buffer_size(4096)
        .on_upgrade(move |socket| async move {
            let _permit = permit;
            connection(socket, app.profile.map(|p| p.recording.clone())).await
        })
}

fn reply(text: &str) -> Value {
    let error = |id: Value, code: &str| json!({"v":1,"type":"error","id":id,"data":{"code":code}});
    let Ok(value) = serde_json::from_str::<Value>(text) else {
        return error(Value::Null, "invalid_json");
    };
    let valid_id = value
        .get("id")
        .and_then(Value::as_u64)
        .filter(|id| *id <= 9_007_199_254_740_991);
    let id = valid_id.map_or(Value::Null, Value::from);
    let Some(object) = value.as_object() else {
        return error(id, "invalid_request");
    };
    if valid_id.is_none()
        || object.len() != 3
        || !object.contains_key("v")
        || !object.contains_key("type")
        || !value["type"].is_string()
    {
        return error(id, "invalid_request");
    }
    if value["v"].as_u64() != Some(1) {
        return error(id, "unsupported_version");
    }
    match value["type"].as_str() {
        Some("station.get") => {
            json!({"v":1,"type":"station.status","id":id,"data":{"version":env!("CARGO_PKG_VERSION"),"radio":"unconfigured"}})
        }
        Some(_) => error(id, "unknown_command"),
        None => error(id, "invalid_request"),
    }
}

async fn send(socket: &mut WebSocket, message: Message) -> bool {
    matches!(
        timeout(Duration::from_secs(2), socket.send(message)).await,
        Ok(Ok(()))
    )
}
async fn send_control(socket: &mut WebSocket, message: Message, pending: Option<Instant>) -> bool {
    if let Some(since) = pending {
        matches!(
            tokio::time::timeout_at(
                (since + Duration::from_secs(2)).into(),
                send(socket, message)
            )
            .await,
            Ok(true)
        )
    } else {
        send(socket, message).await
    }
}

// Optional writes never wait in the connection loop. Readiness flushes prior buffered
// output. Reserve a full 1024-byte control payload plus both WebSocket headers
// inside the 4096-byte buffer (14 bytes/header is conservative for server frames).
fn optional_write<S: futures_sink::Sink<Message> + Unpin>(
    socket: &mut S,
    message: Message,
) -> Result<Option<bool>, S::Error> {
    use std::{
        pin::Pin,
        task::{Context, Poll, Waker},
    };
    if !matches!(&message,Message::Text(text) if text.len()<=2048 && text.len()+1024+2*14<=4096) {
        return Ok(None);
    }
    let mut cx = Context::from_waker(Waker::noop());
    match Pin::new(&mut *socket).poll_ready(&mut cx) {
        Poll::Pending => return Ok(None),
        Poll::Ready(result) => result?,
    }
    Pin::new(&mut *socket).start_send(message)?;
    match Pin::new(socket).poll_flush(&mut cx) {
        Poll::Ready(result) => {
            result?;
            Ok(Some(true))
        }
        Poll::Pending => Ok(Some(false)),
    }
}
fn optional_flush<S: futures_sink::Sink<Message> + Unpin>(
    socket: &mut S,
) -> Result<bool, S::Error> {
    use std::{
        pin::Pin,
        task::{Context, Poll, Waker},
    };
    match Pin::new(socket).poll_flush(&mut Context::from_waker(Waker::noop())) {
        Poll::Ready(result) => {
            result?;
            Ok(true)
        }
        Poll::Pending => Ok(false),
    }
}

async fn connection(mut socket: WebSocket, recording: Option<Arc<recording::Recording>>) {
    let mut heartbeat = interval(Duration::from_secs(5));
    heartbeat.tick().await;
    let mut last_pong = Instant::now();
    let mut display = interval(Duration::from_millis(100));
    display.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut detail_tick = interval(Duration::from_millis(200));
    detail_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut display_profile = "off";
    let mut seen = None;
    let mut last_display = Instant::now() - Duration::from_secs(1);
    let mut optional_since: Option<Instant> = None;
    loop {
        tokio::select! {
            biased;
            _ = tokio::time::sleep_until((optional_since.unwrap_or_else(Instant::now)+Duration::from_secs(2)).into()), if optional_since.is_some()=>break,
            _ = heartbeat.tick() => {
                if last_pong.elapsed() > Duration::from_secs(15) { break; }
                if !send_control(&mut socket, Message::Text(json!({"v":1,"type":"heartbeat"}).to_string().into()),optional_since).await { break; }
                optional_since=None;
                if !send(&mut socket,Message::Ping(Vec::new().into())).await {break;}
            }
            incoming = socket.recv() => match incoming {
                Some(Ok(Message::Text(text))) => {
                    let mut value = reply(&text);
                    if value["data"]["code"] == "unknown_command" {
                        let request: Value = serde_json::from_str(&text).unwrap_or(Value::Null);
                        let command = request["type"].as_str().unwrap_or("");
                        if matches!(command,"recording.get"|"spectrum.thin"|"spectrum.detail"|"spectrum.off") {
                            if let Some(r) = &recording {
                                if command == "recording.get" {
                                    let s = r.snapshot();
                                    value = json!({"v":1,"type":"recording.state","id":request["id"],"data":{"generation":s["generation"],"source_id":s["recording"]["id"],"job_id":s["job"]["id"],"state":s["job"]["state"]}});
                                } else {
                                    display_profile = if command=="spectrum.detail" {"detail"} else if command=="spectrum.thin" {"thin"} else {"off"};
                                    let state=r.state.lock().unwrap();
                                    let frame=if display_profile=="detail" {&state.detail_frame} else {&state.frame};
                                    seen=frame.as_ref().map(|f|(f["data"]["job_id"].clone(),f["data"]["sequence"].clone()));
                                    value = json!({"v":1,"type":"spectrum.subscription","id":request["id"],"data":{"profile":display_profile}});
                                }
                            } else { value["data"]["code"] = json!("unavailable"); }
                        }
                    }
                    if !send_control(&mut socket, Message::Text(value.to_string().into()),optional_since).await { break; }
                    optional_since=None;
                }
                Some(Ok(Message::Pong(_))) => last_pong = Instant::now(),
                Some(Ok(Message::Binary(_))) => { let _ = send_control(&mut socket, Message::Close(Some(CloseFrame { code: 1003, reason: "text required".into() })),optional_since).await; break; }
                Some(Ok(Message::Ping(_))) => {},
                _ => break,
            },
            _ = async { if display_profile=="detail" {detail_tick.tick().await} else {display.tick().await} }, if display_profile != "off" => {
                if optional_since.is_some() {
                    match optional_flush(&mut socket) { Ok(true)=>optional_since=None, Ok(false)=>continue, Err(_)=>break }
                }
                if display_profile=="thin" && last_display.elapsed()<Duration::from_secs(1) {continue;}
                let frame = recording.as_ref().and_then(|r| {let s=r.state.lock().unwrap();if display_profile=="detail" {s.detail_frame.clone()} else {s.frame.clone()}});
                if let Some(frame) = frame {
                    let identity = (frame["data"]["job_id"].clone(),frame["data"]["sequence"].clone());
                    if seen.as_ref() != Some(&identity) {
                        let text=frame.to_string();
                        if text.len()>if display_profile=="detail" {2048} else {1024} { continue; }
                        match optional_write(&mut socket,Message::Text(text.into())) {
                            Ok(None)=>{},
                            Ok(Some(flushed))=>{seen=Some(identity);last_display=Instant::now();if !flushed {optional_since=Some(Instant::now());}},
                            Err(_)=>break,
                        }
                    }
                }
            }
        }
    }
}
