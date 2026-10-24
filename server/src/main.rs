#![forbid(unsafe_code)]
#[cfg(test)]
mod protocol_tests;
use axum::{
    Router,
    extract::{
        State, WebSocketUpgrade,
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
use subtle::ConstantTimeEq;
use tokio::{
    sync::Semaphore,
    time::{interval, timeout},
};

#[derive(Clone)]
struct App {
    origin: String,
    token: Option<String>,
    connections: Arc<Semaphore>,
    login_attempts: Arc<std::sync::Mutex<(Instant, u8)>>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    rustls::crypto::ring::default_provider()
        .install_default()
        .ok();
    let addr: SocketAddr = env::var("WSTX_BIND")
        .unwrap_or_else(|_| "127.0.0.1:8080".into())
        .parse()?;
    let token = env::var("WSTX_TOKEN").ok();
    let tls = match (
        env::var("WSTX_TLS_CERT").ok(),
        env::var("WSTX_TLS_KEY").ok(),
    ) {
        (Some(cert), Some(key)) => {
            Some(axum_server::tls_rustls::RustlsConfig::from_pem_file(cert, key).await?)
        }
        (None, None) => None,
        _ => return Err("Both WSTX_TLS_CERT and WSTX_TLS_KEY are required".into()),
    };
    if token.as_ref().is_some_and(|s| {
        !(32..=128).contains(&s.len()) || !s.bytes().all(|c| c.is_ascii_alphanumeric())
    }) {
        return Err("WSTX_TOKEN requires 32 through 128 ASCII letters/digits".into());
    }
    if !addr.ip().is_loopback()
        && (tls.is_none() || token.is_none() || env::var("WSTX_ORIGIN").is_err())
    {
        return Err("Remote binding requires TLS, WSTX_TOKEN and WSTX_ORIGIN".into());
    }
    if tls.is_some() && token.is_none() {
        return Err("TLS mode requires WSTX_TOKEN".into());
    }
    if token.is_some() && tls.is_none() {
        return Err("WSTX_TOKEN requires TLS".into());
    }
    let listener = std::net::TcpListener::bind(addr)?;
    listener.set_nonblocking(true)?;
    let address = listener.local_addr()?;
    let scheme = if tls.is_some() { "https" } else { "http" };
    let origin = env::var("WSTX_ORIGIN").unwrap_or_else(|_| format!("{scheme}://{address}"));
    let parsed: axum::http::Uri = origin.parse()?;
    if parsed.scheme_str() != Some(scheme)
        || parsed.authority().is_none()
        || parsed.authority().is_some_and(|a| a.as_str().contains('@'))
        || parsed.path_and_query().is_some_and(|p| p.as_str() != "/")
        || origin.ends_with('/')
        || origin.contains(['\r', '\n', '#'])
    {
        return Err("WSTX_ORIGIN must match the listener scheme, without a trailing slash".into());
    }
    let state = App {
        origin: origin.clone(),
        token,
        connections: Arc::new(Semaphore::new(16)),
        login_attempts: Arc::new(std::sync::Mutex::new((Instant::now(), 0))),
    };
    let app = Router::new()
        .route("/", get(|| async { Html(include_str!("../../client/index.html")) }))
        .route("/app.js", get(|| async { ([(header::CONTENT_TYPE, "text/javascript; charset=utf-8")], include_str!("../../client/app.js")) }))
        .route("/style.css", get(|| async { ([(header::CONTENT_TYPE, "text/css; charset=utf-8")], include_str!("../../client/style.css")) }))
        .route("/session", post(session))
        .route("/ws", get(upgrade))
        .layer(axum::extract::DefaultBodyLimit::max(1024))
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
    println!("WSTX listening {origin}");
    if let Some(tls) = tls {
        axum_server::from_tcp_rustls(listener, tls)?
            .serve(app.into_make_service())
            .await?;
    } else {
        axum::serve(tokio::net::TcpListener::from_std(listener)?, app).await?;
    }
    Ok(())
}

fn allowed_origin(headers: &HeaderMap, app: &App) -> bool {
    headers.get(header::ORIGIN).and_then(|v| v.to_str().ok()) == Some(app.origin.as_str())
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
    match app.token {
        Some(token) if equal_secret(&body, &token) => (
            StatusCode::NO_CONTENT,
            [(
                header::SET_COOKIE,
                format!(
                    "wstx_session={token}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=28800"
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
    if let Some(token) = &app.token {
        let authorized = headers
            .get(header::COOKIE)
            .and_then(|v| v.to_str().ok())
            .is_some_and(|cookie| {
                cookie.split(';').any(|part| {
                    part.trim()
                        .strip_prefix("wstx_session=")
                        .is_some_and(|v| equal_secret(v, token))
                })
            });
        if !authorized {
            return StatusCode::UNAUTHORIZED.into_response();
        }
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
        .max_write_buffer_size(2048)
        .on_upgrade(move |socket| async move {
            let _permit = permit;
            connection(socket).await
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

async fn connection(mut socket: WebSocket) {
    let mut heartbeat = interval(Duration::from_secs(5));
    heartbeat.tick().await;
    let mut last_pong = Instant::now();
    loop {
        tokio::select! {
            _ = heartbeat.tick() => {
                if last_pong.elapsed() > Duration::from_secs(15) { break; }
                if !send(&mut socket, Message::Text(json!({"v":1,"type":"heartbeat"}).to_string().into())).await || !send(&mut socket, Message::Ping(Vec::new().into())).await { break; }
            }
            incoming = socket.recv() => match incoming {
                Some(Ok(Message::Text(text))) => { if !send(&mut socket, Message::Text(reply(&text).to_string().into())).await { break; } }
                Some(Ok(Message::Pong(_))) => last_pong = Instant::now(),
                Some(Ok(Message::Binary(_))) => { let _ = send(&mut socket, Message::Close(Some(CloseFrame { code: 1003, reason: "text required".into() }))).await; break; }
                Some(Ok(Message::Ping(_))) => {},
                _ => break,
            }
        }
    }
}
