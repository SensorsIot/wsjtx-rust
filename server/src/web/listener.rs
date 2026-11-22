use super::*;
/// The largest bodies web takes, in bytes (WstxStationLink::Limits).
pub(crate) mod limits {
    pub const CONTROL_BYTES: usize = 1024;
    pub const RECORD_BYTES: usize = 8192;
    pub const SETTINGS_BYTES: usize = 32_768;
}
/// The most sockets the station holds open at once; one more is refused with 503
/// (WstxListener::BoundsRule).
pub(crate) const SOCKET_BOUND: usize = 16;
/// The heartbeat of a socket and the pace of its events (WstxStationLink::SocketProtocol).
pub(crate) mod socket_protocol {
    pub const HEARTBEAT_MS: u64 = 5000;
    pub const EVENT_DELAY_MS: u64 = 1000;
}
pub(crate) fn router(state: App) -> Router {
    Router::new()
        .route("/", get(index))
        .route("/authorization.js", get(|| async { ([(header::CONTENT_TYPE, "text/javascript; charset=utf-8")], include_str!("../../../client/src/frontend/authorization.js")) }))
        .route("/app.js", get(|| async { ([(header::CONTENT_TYPE, "text/javascript; charset=utf-8")], include_str!("../../../client/src/frontend/app.js")) }))
        .route("/recording.js", get(|| async { ([(header::CONTENT_TYPE, "text/javascript; charset=utf-8")], include_str!("../../../client/src/frontend/recording.js")) }))
        .route("/recording.css", get(|| async { ([(header::CONTENT_TYPE, "text/css; charset=utf-8")], include_str!("../../../client/src/frontend/recording.css")) }))
        .route("/contact.js", get(|| async { ([(header::CONTENT_TYPE, "text/javascript; charset=utf-8")], include_str!("../../../client/src/frontend/contact.js")) }))
        .route("/logbook.js", get(|| async { ([(header::CONTENT_TYPE, "text/javascript; charset=utf-8")], include_str!("../../../client/src/frontend/logbook.js")) }))
        .route("/style.css", get(|| async { ([(header::CONTENT_TYPE, "text/css; charset=utf-8")], include_str!("../../../client/src/frontend/style.css")) }))
        .route("/session", post(session).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/authorization/v1/bootstrap-scope", post(authorization_http::bootstrap_scope))
        .route("/authorization/v1/enroll", post(authorization_http::enroll))
        .route("/authorization/v1/challenge", post(authorization_http::challenge))
        .route("/authorization/v1/proof", post(authorization_http::proof))
        .route("/authorization/v1/status", post(authorization_http::status))
        .route("/authorization/v1/receipt", post(authorization_http::reconcile_receipt))
        .route("/authorization/v1/revoke", post(authorization_http::revoke))
        .route("/authorization/v1/commission", post(authorization_http::commission))
        .route("/authorization/v1/mcp-clients", get(authorization_http::mcp_clients))
        .route("/authorization/v1/mcp-clients/create", post(authorization_http::mcp_create))
        .route("/authorization/v1/mcp-clients/revoke", post(authorization_http::mcp_revoke))
        .route("/profile", get(get_profile).put(put_profile))
        .route("/recording", get(recording_http::snapshot))
        .route("/audio/devices", get(receive_http::devices))
        .route("/audio/endpoints", get(radio_setup::endpoints_route))
        .route("/receive", get(receive_http::snapshot))
        .route("/receive/start", post(receive_http::start).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/receive/stop", post(receive_http::stop).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/receive/results", get(receive_http::results))
        .route("/receive/clock", get(receive_http::clock))
        // There is no POST /clock; any other method gets the unknown-route answer.
        .route("/clock", get(clock_http::snapshot).fallback(|| async { StatusCode::NOT_FOUND }).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/receive/startup", get(receive_http::startup).post(receive_http::startup_update).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/receive/diagnostics", get(receive_http::diagnostics).post(receive_http::diagnostics_update).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/receive/selection", get(selection_http::snapshot))
        .route("/receive/select", post(selection_http::select).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/native-flex", get(flex_http::snapshot))
        .route("/radio", get(radio_http::snapshot))
        .route("/radio/connect", post(radio_http::connect).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/radio/disconnect", post(radio_http::disconnect).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/radio/operation", post(radio_http::execute).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/radio/detect", post(radio_setup::detect_route).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/radio/settings/apply", post(radio_setup::apply_route).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/radio/tx-level", post(radio_level::route).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/radio/settings/undo", post(radio_setup::undo_route).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/transmit", get(transmit_http::snapshot))
        .route("/transmit/command", post(transmit_http::execute).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/transmit/halt", post(transmit_http::halt).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/recording/imports", post(recording_http::reserve).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/recording/imports/{id}", get(recording_http::import).put(recording_http::import).delete(recording_http::import).layer(axum::extract::DefaultBodyLimit::max(recording_http::RAW_CHUNK_BYTES)))
        .route("/recording/replay", post(recording_http::replay).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/recording/jobs/{id}", axum::routing::delete(recording_http::cancel_job))
        .route("/contacts", get(logbook_http::history).post(logbook_http::save).layer(axum::extract::DefaultBodyLimit::max(logbook_http::SAVE_BODY_MAX)))
        .route("/contacts/export.adi", get(logbook_http::export))
        .route("/contacts/imports", post(logbook_http::reserve).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/contacts/imports/{id}", get(logbook_http::import).put(logbook_http::import).layer(axum::extract::DefaultBodyLimit::max(logbook::IMPORT_CHUNK_BYTES_MAX)))
        .route("/contact", get(contact_http::snapshot))
        .route("/contact/command", post(contact_http::command).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/dxcc", get(logbook_http::dxcc).put(logbook_http::dxcc_put).layer(axum::extract::DefaultBodyLimit::max(logbook_http::DXCC_BODY_MAX)))
        .route("/automation", get(automation::snapshot))
        .route("/automation/command", post(automation::command).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/strategy", get(strategy::snapshot).put(strategy::put).layer(axum::extract::DefaultBodyLimit::max(strategy::BODY_MAX)))
        .route("/strategy/evaluate", post(strategy::evaluate_route).layer(axum::extract::DefaultBodyLimit::max(strategy::BODY_MAX)))
        .route("/strategy/ignore", post(strategy::ignore_route).layer(axum::extract::DefaultBodyLimit::max(strategy::BODY_MAX)))
        .route("/strategy/auto", post(strategy::auto_route).layer(axum::extract::DefaultBodyLimit::max(strategy::BODY_MAX)))
        .route("/strategy/most-wanted/download", post(strategy::most_wanted_download_route).layer(axum::extract::DefaultBodyLimit::max(strategy::BODY_MAX)))
        .route("/strategy/alerts", get(strategy::alerts_route))
        .route("/strategy/contests", get(strategy::contests_route))
        .route("/strategy/alerts/clear", post(strategy::clear_alerts_route).layer(axum::extract::DefaultBodyLimit::max(strategy::BODY_MAX)))
        .route("/pskr", get(pskr::snapshot).post(pskr::update).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/pskr/use", post(pskr::update_use).layer(axum::extract::DefaultBodyLimit::max(limits::CONTROL_BYTES)))
        .route("/udp", get(udp::snapshot).put(udp::put).layer(axum::extract::DefaultBodyLimit::max(udp::BODY_MAX)))
        .route("/mcp", post(mcp::endpoint).get(mcp::not_allowed).delete(mcp::not_allowed).layer(axum::extract::DefaultBodyLimit::max(mcp::BODY_MAX)))
        .route("/ws", get(upgrade))
        .layer(axum::extract::DefaultBodyLimit::max(8192))
        .layer(axum::middleware::from_fn_with_state(state.clone(), mcp::principal_guard))
        .layer(axum::middleware::from_fn(|request, next: axum::middleware::Next| async move {
            let mut response = next.run(request).await;
            let headers = response.headers_mut();
            headers.insert("content-security-policy", "default-src 'self'; connect-src 'self'; script-src 'self'; style-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'".parse().unwrap());
            headers.insert("x-content-type-options", "nosniff".parse().unwrap());
            headers.insert(header::CACHE_CONTROL, "no-store".parse().unwrap());
            response
        }))
        .layer(axum::middleware::from_fn(http_compression::encode))
        // Outermost, so a response is counted as it leaves the router (after content coding).
        .layer(axum::middleware::from_fn(link_log::http))
        .with_state(state)
}
// The running station reports the commit its release build was made from, so a
// post-install probe can ask the service itself instead of trusting the install receipt.
fn source_commit(raw: Option<&'static str>) -> &'static str {
    match raw {
        Some(commit)
            if commit.len() == 40
                && commit
                    .bytes()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) =>
        {
            commit
        }
        _ => "unknown",
    }
}
async fn index(State(app): State<App>) -> impl IntoResponse {
    let commit = source_commit(option_env!("WSTX_SOURCE_COMMIT"));
    ([("x-wstx-source-commit", commit)], Html(include_str!("../../../client/src/frontend/index.html").replace(
        "</head>", if app.profile.is_some() { "<link rel=\"stylesheet\" href=\"/recording.css\"><script src=\"/recording.js\" defer></script></head>" } else { "</head>" }
    ).replace(
        "<script src=\"/app.js\" defer></script>",
        if app.profile.is_some() { "<script src=\"/authorization.js\" defer></script><script src=\"/app.js\" defer></script>" } else { "<script src=\"/app.js\" defer></script>" }
    ).replace(
        "data-profile=\"false\"",
        &format!(
            "data-profile=\"{}\" data-build=\"{}\"",
            app.profile.is_some(),
            client_build()
        ),
    )))
}
pub(crate) fn cookie_name(app: &App) -> String {
    app.profile_id
        .as_ref()
        .map_or_else(|| "wstx_session".into(), |id| format!("wstx_session_{id}"))
}
pub(crate) fn cookie_value(app: &App, token: &str) -> String {
    app.profile_id
        .as_ref()
        .map_or_else(|| token.to_owned(), |id| format!("{id}.{token}"))
}
pub(crate) fn authenticated(headers: &HeaderMap, app: &App) -> bool {
    // Trusted plaintext loopback configuration GET/PUT remains a separate contract.
    // A selected HTTPS profile never inherits the old runtime-token cookie.
    if app.profile_id.is_some() && app.origin.starts_with("https://") {
        return false;
    }
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
pub(crate) fn allowed_origin(headers: &HeaderMap, app: &App) -> bool {
    let mut origins = headers.get_all(header::ORIGIN).iter();
    origins.next().and_then(|v| v.to_str().ok()) == Some(app.origin.as_str())
        && (app.profile_id.is_none() || origins.next().is_none())
}
pub(crate) fn equal_secret(a: &str, b: &str) -> bool {
    bool::from(a.as_bytes().ct_eq(b.as_bytes()))
}

pub(crate) async fn session(
    State(app): State<App>,
    headers: HeaderMap,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    if !allowed_origin(&headers, &app) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let body = match body {
        Ok(bytes) if bytes.len() <= 1024 => bytes,
        _ => return StatusCode::PAYLOAD_TOO_LARGE.into_response(),
    };
    let Ok(body) = std::str::from_utf8(&body) else {
        return StatusCode::BAD_REQUEST.into_response();
    };
    if app.profile.is_some() {
        return authorization_http::bootstrap_session_async(&headers, &app, body).await;
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
        Some(token) if equal_secret(body, token) => (
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

async fn upgrade(
    State(app): State<App>,
    link: Option<axum::Extension<axum::extract::ConnectInfo<link_log::Link>>>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> Response {
    let link = link.and_then(|link| link.0.0.0);
    if !allowed_origin(&headers, &app) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let authority = if let Some(state) = &app.profile {
        match authorization_http::operating_access_async(&headers, &app).await {
            Ok(access) => access.map(|access| ConnectionAuthority {
                state: state.clone(),
                access,
            }),
            Err(error) => return authorization_http::mapped(error),
        }
    } else {
        if !authenticated(&headers, &app) {
            return StatusCode::UNAUTHORIZED.into_response();
        }
        None
    };
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
        .max_message_size(limits::CONTROL_BYTES)
        .max_frame_size(limits::CONTROL_BYTES)
        .write_buffer_size(0)
        .max_write_buffer_size(4096)
        .on_upgrade(move |socket| async move {
            let _permit = permit;
            // An authenticated client is here.
            let _client = app.profile.as_ref().map(|p| p.recording.clients.session());
            connection(link_log::Socket::new(socket, link), app.profile, authority).await
        })
}

/// WstxListener::ClientBuild: the identity of the embedded browser client, the
/// first HEX_DIGITS hex digits of the SHA-256 over every served client file in route order.
/// The page carries the build it was served with; station.status carries the station's.
mod client_build {
    pub const HEX_DIGITS: usize = 16;
}
fn client_build() -> &'static str {
    static BUILD: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    BUILD.get_or_init(|| {
        let mut digest = ring::digest::Context::new(&ring::digest::SHA256);
        for asset in [
            include_str!("../../../client/src/frontend/index.html"),
            include_str!("../../../client/src/frontend/authorization.js"),
            include_str!("../../../client/src/frontend/app.js"),
            include_str!("../../../client/src/frontend/recording.js"),
            include_str!("../../../client/src/frontend/recording.css"),
            include_str!("../../../client/src/frontend/contact.js"),
            include_str!("../../../client/src/frontend/logbook.js"),
            include_str!("../../../client/src/frontend/style.css"),
        ] {
            digest.update(asset.as_bytes());
        }
        digest.finish().as_ref()[..client_build::HEX_DIGITS / 2]
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect()
    })
}
pub(crate) fn reply(text: &str) -> Value {
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
            json!({"v":1,"type":"station.status","id":id,"data":{"version":env!("CARGO_PKG_VERSION"),"radio":"unconfigured","build":client_build()}})
        }
        Some(_) => error(id, "unknown_command"),
        None => error(id, "invalid_request"),
    }
}

async fn send(socket: &mut link_log::Socket, message: Message) -> bool {
    matches!(
        timeout(Duration::from_secs(2), socket.send(message)).await,
        Ok(Ok(()))
    )
}
async fn send_control(
    socket: &mut link_log::Socket,
    message: Message,
    pending: Option<tokio::time::Instant>,
) -> bool {
    if let Some(since) = pending {
        matches!(
            tokio::time::timeout_at(since + Duration::from_secs(2), send(socket, message)).await,
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

// A late interval tick must not keep the old grid and send the next frame early.
fn arm_detail(
    tick: &mut tokio::time::Interval,
    accepted: tokio::time::Instant,
    behind: bool,
) -> tokio::time::Instant {
    // A subscriber behind the station catches up at 170 ms per row (under 10 KiB/s).
    let next = accepted + Duration::from_millis(if behind { 170 } else { 200 });
    tick.reset_at(next);
    next
}
/// The next live Thin pacing anchor is the previous one plus the period, so 100 ms ticks do
/// not drift against the 1 row/s source. A send more than half a period late restarts the grid
/// at the send, so two sends are always at least half a period (1 s live) apart.
fn next_thin_anchor(
    previous: tokio::time::Instant,
    period: Duration,
    now: tokio::time::Instant,
) -> tokio::time::Instant {
    let next = previous + period;
    if now.saturating_duration_since(next) > period / 2 {
        now
    } else {
        next
    }
}
/// The oldest retained Detailed row after the one this socket sent last (rows of
/// another job all count as new), and whether more rows wait behind it.
fn detail_after(
    recent: &std::collections::VecDeque<Value>,
    seen: &Option<(Value, Value)>,
) -> Option<(Value, bool)> {
    let mut pending = recent.iter().filter(|f| match seen {
        Some((job, sequence)) if f["data"]["job_id"] == *job => {
            f["data"]["sequence"].as_u64() > sequence.as_u64()
        }
        _ => true,
    });
    let first = pending.next()?.clone();
    Some((first, pending.next().is_some()))
}

pub(crate) struct ConnectionAuthority {
    pub(crate) state: Arc<ProfileState>,
    pub(crate) access: authorization::Access,
}
impl ConnectionAuthority {
    async fn current_async(&self) -> Result<bool, authorization::Error> {
        let state = self.state.clone();
        let access = self.access.clone();
        tokio::task::spawn_blocking(move || {
            let owner = state
                .authorization
                .lock()
                .map_err(|_| authorization::Error::PersistenceFailed)?;
            let Some(service) = owner.as_ref() else {
                return Ok(false);
            };
            match service.authority.current_grant(&access) {
                Ok(_) => Ok(true),
                Err(authorization::Error::Unauthorized) => Ok(false),
                Err(error) => Err(error),
            }
        })
        .await
        .map_err(|_| authorization::Error::PersistenceFailed)?
    }
}
async fn connection(
    mut socket: link_log::Socket,
    profile: Option<Arc<ProfileState>>,
    authority: Option<ConnectionAuthority>,
) {
    // Every time of this loop is the runtime's clock, so a test can drive it (TC-021-008).
    use tokio::time::Instant;
    let recording = profile.as_ref().map(|p| p.recording.clone());
    let mut heartbeat = interval(Duration::from_millis(socket_protocol::HEARTBEAT_MS));
    heartbeat.tick().await;
    let mut last_pong = Instant::now();
    let mut display = interval(Duration::from_millis(100));
    display.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut detail_tick = interval(Duration::from_millis(200));
    detail_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut next_detail = arm_detail(&mut detail_tick, tokio::time::Instant::now(), false);
    let mut display_profile = "off";
    let mut seen = None;
    let mut last_display = Instant::now() - Duration::from_secs(1);
    let mut optional_since: Option<Instant> = None;
    let mut receive_tick = interval(Duration::from_secs(2));
    receive_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut receive_seen = Value::Null;
    let mut receive_sent = Value::Null;
    // CL-057-01: a Detailed peer is told of each new or grown decode view at once; Thin
    // and Off keep the 2 s receive tick that their link budget is measured with.
    let mut publication = recording.as_ref().map(|r| r.publication.subscribe());
    // WstxQsoControl::QsoState / StationTickEvent pacing (optional writes).
    let mut contact_tick = interval(Duration::from_millis(socket_protocol::EVENT_DELAY_MS));
    contact_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut contact_seen: Option<(u64, Option<u64>)> = None;
    // What this peer holds of the contact snapshot, and when it was last sent.
    let mut contact_sent = Value::Null;
    let mut contact_sent_at = Instant::now();
    // WstxTransmitControl::TransmitStatus transmit.state (pushed state, coalesced like
    // contact.state).
    let mut transmit_seen: Option<u64> = None;
    // What this peer holds: the fields it was last sent, and when.
    let mut transmit_sent = Value::Null;
    let mut transmit_sent_at = Instant::now();
    // WstxAutoControl::AutoActivity: only after a change since boot (no event while unused).
    let mut automation_seen: Option<(u64, u64)> = Some((0, 0));
    // free_tx_slots.state: the build this Detailed or Thin peer holds (None: none, also
    // while Off, so that a peer coming from Off gets the current value once).
    let mut free_tx_slots_seen: Option<u64> = None;
    // WstxStrategies::StrategiesState strategy.state: only after a change since this peer
    // subscribed.
    let mut strategy_seen: Option<u64> = None;
    // WstxRankingControl::Alert alert.state: only after a change since this peer subscribed.
    let mut alert_seen: Option<u64> = None;
    // CL-044-11 radio.agc: the managed AGC and its last read-back, once known, then
    // after each change (the first event is this peer's snapshot).
    let mut agc_seen: u64 = 0;
    // WstxHearingFeed::HearingFeed pskr.state: after a change since this peer subscribed
    // (the first event follows its GET /pskr snapshot).
    let mut pskr_seen: u64 = 0;
    // WstxTransmitControl::TxLevelStatus radio.tx_level: after each change of the level,
    // assistant or meters.
    let mut tx_level_seen: u64 = 0;
    // FR-023 radio.native: this peer's snapshot, then each change of the native session.
    let mut native_seen: u64 = 0;
    // Pushed recording.state: its comparison key (without received_bytes), the last data and when.
    let mut recording_tick = interval(Duration::from_millis(socket_protocol::EVENT_DELAY_MS));
    recording_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut recording_seen: Option<(Value, Value, Instant)> = None;
    let mut profile_seen: Option<u64> = None;
    // CL-043-01 clock.state: every profile, once after subscribing, then at each change of
    // clock_revision, at most one per second per peer and within 1 s (250 ms ticks).
    let mut clock_tick = interval(Duration::from_millis(250));
    clock_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut clock_seen: Option<u64> = None;
    let mut clock_sent_at: Option<Instant> = None;
    // WstxStationCommands::SelectionState: what this peer holds, and when it was last sent.
    let mut selection_sent = Value::Null;
    let mut selection_sent_at = Instant::now();
    let mut last_station_tick: Option<Instant> = None;
    let mut tick_transmitting: Option<bool> = None;
    // Events pace by the peer's display subscription; a peer that never chose one
    // (a bare status observer) receives none.
    let mut subscribed = false;
    loop {
        let auth_ready = if let Some(context) = &authority {
            match context.current_async().await {
                Ok(true) => true,
                Ok(false) => break,
                Err(_) => false,
            }
        } else {
            true
        };
        tokio::select! {
            biased;
            _ = tokio::time::sleep_until(optional_since.unwrap_or_else(Instant::now)+Duration::from_secs(2)), if optional_since.is_some()=>break,
            _ = heartbeat.tick() => {
                if last_pong.elapsed() > Duration::from_secs(15) { break; }
                if !send_control(&mut socket, Message::Text(json!({"v":1,"type":"heartbeat"}).to_string().into()),optional_since).await { break; }
                optional_since=None;
                if !send(&mut socket,Message::Ping(Vec::new().into())).await {break;}
            }
            _ = async {
                tokio::select! {
                    _ = receive_tick.tick() => {},
                    Some(Ok(())) = async { Some(publication.as_mut()?.changed().await) }, if display_profile == "detail" => {},
                }
            }, if recording.is_some() => {
                if !auth_ready { continue; }
                let r=recording.as_ref().unwrap();
                let s=r.receive_snapshot();
                let data=receive_http::receive_state_data(&s);
                let notify=!s["job"].is_null() || !receive_seen["job_id"].is_null();
                // The countdown of an audio retry alone is no change to announce.
                let mut key=data.clone();key["audio"]["retry_after_ms"]=Value::Null;
                if notify && key!=receive_seen {
                    let event=receive_http::receive_state_delta(&receive_sent,&data);
                    if !send_control(&mut socket,Message::Text(json!({"v":1,"type":"receive.state","data":event}).to_string().into()),optional_since).await {break;}
                    optional_since=None;receive_seen=key;receive_sent=data;
                }
            }
            _ = contact_tick.tick(), if subscribed && recording.as_ref().is_some_and(|r| r.contact.get().is_some()) => {
                if !auth_ready { continue; }
                if optional_since.is_some() {
                    match optional_flush(&mut socket) { Ok(true)=>optional_since=None, Ok(false)=>continue, Err(_)=>break }
                }
                let r=recording.as_ref().unwrap();
                // The snapshot holds the transmit view as well; a peer still lacking dialogue rows gets them on the next tick.
                let revision=(r.contact.get().map_or(0,|c|c.revision()),transmit_http::state_revision(r));
                if contact_seen!=Some(revision) {
                    let snapshot=profile.as_ref().zip(r.contact.get()).and_then(|(p,c)|c.snapshot(p).ok()).and_then(|bytes|serde_json::from_slice::<Value>(&bytes).ok());
                    if let Some(snapshot)=snapshot {
                        let (changed,holds)=contact_http::state_changes(&contact_sent,&snapshot);
                        let complete=holds["contact"]==snapshot["contact"];
                        // A new revision or sequence without a changed field still goes: the next command needs the
                        // revision, and a read may have caught a value that is gone again.
                        if changed.is_empty() && contact_sent["contact_revision"]==snapshot["contact_revision"] && contact_sent["snapshot_sequence"]==snapshot["snapshot_sequence"] {contact_seen=Some(revision);}
                        else if transmit_http::due(display_profile,&changed,contact_sent_at.elapsed()) {
                            match optional_write(&mut socket,Message::Text(contact_http::state_event(&snapshot,changed).into())) {
                                Ok(None)=>{},
                                Ok(Some(flushed))=>{if complete {contact_seen=Some(revision);}contact_sent=holds;contact_sent_at=Instant::now();if !flushed {optional_since=Some(Instant::now());continue;}},
                                Err(_)=>break,
                            }
                        }
                    }
                }
                if let Some((revision,now))=transmit_http::state_read(r) && transmit_seen!=Some(revision) {
                    let changed=transmit_http::changed_fields(&transmit_sent,&now);
                    if changed.is_empty() {transmit_seen=Some(revision);}
                    else if transmit_http::due(display_profile,&changed,transmit_sent_at.elapsed()) {
                        match optional_write(&mut socket,Message::Text(transmit_http::state_event(r,revision,changed).into())) {
                            Ok(None)=>{},
                            Ok(Some(flushed))=>{transmit_seen=Some(revision);transmit_sent=now;transmit_sent_at=Instant::now();if !flushed {optional_since=Some(Instant::now());continue;}},
                            Err(_)=>break,
                        }
                    }
                }
                let automation=r.contact.get().map(|c|c.automation.revisions());
                if automation.is_some() && automation!=automation_seen {
                    match optional_write(&mut socket,Message::Text(automation::state_event(r,automation.unwrap_or_default()).into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{automation_seen=automation;if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break,
                    }
                }
                if display_profile!="off" && let Some((build,text,null))=r.contact.get().and_then(|c|c.automation.free_tx_slots_event(r,free_tx_slots_seen)) {
                    // A null goes only to a peer that holds a value (once when it becomes null).
                    if null && free_tx_slots_seen.is_none() { free_tx_slots_seen=Some(build); }
                    else { match optional_write(&mut socket,Message::Text(text.into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{free_tx_slots_seen=Some(build);if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break,
                    } }
                }
                let strategy=r.contact.get().map_or(0,|c|c.strategy.revision());
                if strategy_seen.is_none() { strategy_seen=Some(strategy); }
                if strategy_seen!=Some(strategy) {
                    match optional_write(&mut socket,Message::Text(strategy::state_event(r,strategy).into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{strategy_seen=Some(strategy);if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break,
                    }
                }
                let alert=r.contact.get().map_or(0,|c|c.strategy.alert_revision());
                if alert_seen.is_none() { alert_seen=Some(alert); }
                if alert_seen!=Some(alert) {
                    match optional_write(&mut socket,Message::Text(strategy::alert_event(r,alert).into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{alert_seen=Some(alert);if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break,
                    }
                }
                if r.agc.revision()!=agc_seen {
                    let (revision,text)=radio_agc::event(r);
                    match optional_write(&mut socket,Message::Text(text.into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{agc_seen=revision;if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break,
                    }
                }
                if let Some(feed)=r.pskr.get() && feed.revision()!=pskr_seen {
                    let (revision,text)=feed.event();
                    match optional_write(&mut socket,Message::Text(text.into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{pskr_seen=revision;if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break,
                    }
                }
                if r.tx_level.revision()!=tx_level_seen {
                    let (revision,text)=radio_level::event(r);
                    match optional_write(&mut socket,Message::Text(text.into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{tx_level_seen=revision;if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break,
                    }
                }
                if let Some(session)=r.flex.get() && session.revision()!=native_seen {
                    let (revision,text)=flex_http::event(r,&**session);
                    match optional_write(&mut socket,Message::Text(text.into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{native_seen=revision;if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break,
                    }
                }
                let (text,transmitting)=contact_http::tick_event(r);
                // Detailed 1 per second; Thin and Off 1 per 5 s; plus transmit start/stop.
                let every=Duration::from_millis(if display_profile=="detail" {950} else {4950});
                if last_station_tick.is_none_or(|t|t.elapsed()>=every) || tick_transmitting.is_some_and(|t|t!=transmitting) {
                    match optional_write(&mut socket,Message::Text(text.into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{last_station_tick=Some(Instant::now());tick_transmitting=Some(transmitting);if !flushed {optional_since=Some(Instant::now());}},
                        Err(_)=>break,
                    }
                }
            }
            _ = clock_tick.tick(), if subscribed && recording.as_ref().is_some_and(|r| r.clock.get().is_some()) => {
                if !auth_ready { continue; }
                if optional_since.is_some() {
                    match optional_flush(&mut socket) { Ok(true)=>optional_since=None, Ok(false)=>continue, Err(_)=>break }
                }
                if clock_sent_at.is_some_and(|at| at.elapsed() < Duration::from_millis(socket_protocol::EVENT_DELAY_MS)) { continue; }
                if let Some((revision,text))=clock_http::state_event(recording.as_ref().unwrap()) && clock_seen!=Some(revision) {
                    match optional_write(&mut socket,Message::Text(text.into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{
                            clock_seen=Some(revision);clock_sent_at=Some(Instant::now());if !flushed {optional_since=Some(Instant::now());}},
                        Err(_)=>break,
                    }
                }
            }
            _ = recording_tick.tick(), if subscribed && recording.is_some() => {
                if !auth_ready { continue; }
                if optional_since.is_some() {
                    match optional_flush(&mut socket) { Ok(true)=>optional_since=None, Ok(false)=>continue, Err(_)=>break }
                }
                let (revision,text)=recording.as_ref().unwrap().profile_state_event();
                if profile_seen!=Some(revision) {
                    match optional_write(&mut socket,Message::Text(text.into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{profile_seen=Some(revision);if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break,
                    }
                }
                if let Some(now)=profile.as_ref().and_then(|p|selection_http::pushed_view(p)) {
                    let changed=selection_http::state_changes(&selection_sent,&now);
                    if !changed.is_empty() && selection_http::state_due(display_profile,&changed,&selection_sent,&now,selection_sent_at.elapsed()) {
                        let (text,holds)=selection_http::state_event(&selection_sent,&now,changed);
                        match optional_write(&mut socket,Message::Text(text.into())) {
                            Ok(None)=>{},
                            Ok(Some(flushed))=>{selection_sent=holds;selection_sent_at=Instant::now();if !flushed {optional_since=Some(Instant::now());continue;}},
                            Err(_)=>break,
                        }
                    }
                }
                let data=recording.as_ref().unwrap().state_event_data();
                let mut key=data.clone();
                if let Some(import)=key["import"].as_object_mut() { import.remove("received_bytes"); }
                let due=recording_seen.as_ref().is_none_or(|(k,d,at)|*k!=key||(*d!=data&&at.elapsed()>=Duration::from_secs(5)));
                if due {
                    match optional_write(&mut socket,Message::Text(json!({"v":1,"type":"recording.state","data":data}).to_string().into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{recording_seen=Some((key,data,Instant::now()));if !flushed {optional_since=Some(Instant::now());}},
                        Err(_)=>break,
                    }
                }
            }
            incoming = socket.recv() => match incoming {
                Some(Ok(Message::Text(text))) => {
                    if let Some(context) = &authority {
                        match context.current_async().await { Ok(true) => (), Ok(false) => break, Err(_) => continue }
                    }
                    let mut value = reply(&text);
                    if value["data"]["code"] == "unknown_command" {
                        let request: Value = serde_json::from_str(&text).unwrap_or(Value::Null);
                        let command = request["type"].as_str().unwrap_or("");
                        if matches!(command,"recording.get"|"spectrum.thin"|"spectrum.detail"|"spectrum.off") {
                            if let Some(r) = &recording {
                                if command == "recording.get" {
                                    let s = r.snapshot();
                                    let source=if s["job"]["kind"]=="live" {&s["job"]["source_id"]}else{&s["recording"]["id"]};
                                    value = json!({"v":1,"type":"recording.state","id":request["id"],"data":{"generation":s["generation"],"source_id":source,"job_id":s["job"]["id"],"state":s["job"]["state"]}});
                                } else {
                                    display_profile = if command=="spectrum.detail" {"detail"} else if command=="spectrum.thin" {"thin"} else {"off"};
                                    subscribed = true;
                                    socket.display(display_profile);
                                    if display_profile=="off" { free_tx_slots_seen=None; }
                                    if display_profile=="detail" { next_detail=arm_detail(&mut detail_tick,tokio::time::Instant::now(),false); }
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
                let live=recording.as_ref().is_some_and(|r|r.state.lock().unwrap().job.as_ref().is_some_and(|j|j.kind=="live"));
                if display_profile=="thin" && last_display.elapsed()<Duration::from_secs(if live {2}else{1}) {continue;}
                if display_profile=="detail" && tokio::time::Instant::now()<next_detail {detail_tick.reset_at(next_detail);continue;}
                let (frame,behind) = recording.as_ref().and_then(|r| {let s=r.state.lock().unwrap();if display_profile=="detail" {detail_after(&s.detail_recent,&seen)} else {s.frame.clone().map(|f|(f,false))}}).map_or((None,false),|(f,b)|(Some(f),b));
                if let Some(frame) = frame {
                    let identity = (frame["data"]["job_id"].clone(),frame["data"]["sequence"].clone());
                    if seen.as_ref() != Some(&identity) {
                        let text=frame.to_string();
                        if text.len()>if display_profile=="detail" {2048} else {1024} { continue; }
                        match optional_write(&mut socket,Message::Text(text.into())) {
                            Ok(None)=>{},
                            Ok(Some(flushed))=>{seen=Some(identity);last_display=if live {next_thin_anchor(last_display,Duration::from_secs(2),Instant::now())} else {Instant::now()};if display_profile=="detail" {next_detail=arm_detail(&mut detail_tick,tokio::time::Instant::now(),behind);}
                            if !flushed {optional_since=Some(Instant::now());}},
                            Err(_)=>break,
                        }
                    }
                }
            }
        }
    }
}
#[cfg(test)]
#[path = "listener_tests.rs"]
mod protocol_tests;
