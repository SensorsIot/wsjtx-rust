#![forbid(unsafe_code)]
#[cfg(test)]
mod auth_tests;
mod authorization;
mod authorization_http;
mod automation;
#[cfg(test)]
mod automation_tests;
mod cat_lifecycle;
#[cfg(test)]
mod cat_lifecycle_tests;
mod clock_http;
mod contact;
mod contact_http;
#[cfg(test)]
mod contact_http_tests;
#[cfg(test)]
mod contact_tests;
mod dxcc;
mod flex_http;
mod freeslot;
mod http_compression;
#[cfg(test)]
mod http_compression_tests;
mod logbook;
mod logbook_http;
mod mcp;
#[cfg(test)]
mod mcp_tests;
mod profile;
#[cfg(test)]
mod protocol_tests;
mod pskr;
mod radio_agc;
mod radio_http;
#[cfg(test)]
mod radio_http_tests;
mod radio_level;
mod radio_setup;
#[cfg(test)]
mod radio_setup_tests;
mod receive;
mod receive_http;
#[cfg(test)]
mod receive_http_tests;
mod recording;
mod recording_http;
mod selection;
mod selection_http;
#[cfg(all(test, not(debug_assertions)))]
mod selection_http_tests;
use wstx_rust::{audio, decoder, source};
mod contest;
mod most_wanted;
mod spectrum;
mod strategy;
#[cfg(test)]
mod test_ports;
mod transmit_http;
#[cfg(test)]
mod transmit_http_tests;
mod udp;
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
    authorization: Mutex<Option<authorization_http::Service>>,
    boot: String,
    recording: Arc<recording::Recording>,
    logbook: Arc<logbook::Logbook>,
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
        [command, directory, antenna, address @ ..]
            if command == "--create-native-flex-profile" && address.len() <= 1 =>
        {
            let directory = PathBuf::from(directory);
            let address = match address.first().map(|a| a.to_str()) {
                Some(None) => {
                    return Err(startup_error("invalid_runtime_configuration", &directory).into());
                }
                other => other.flatten().map(str::to_owned),
            };
            let Some(antenna) = antenna.to_str() else {
                return Err(startup_error("invalid_runtime_configuration", &directory).into());
            };
            let (target, antenna) = (directory.clone(), antenna.to_owned());
            tokio::task::spawn_blocking(move || {
                profile::Store::create_native(&target, &antenna, address.as_deref())
            })
                .await?
                .map_err(|code| startup_error(code, &directory))?;
            return Ok(());
        }
        _ => return Err("invalid_runtime_configuration: expected --profile <directory>, --create-profile <directory> or --create-native-flex-profile <directory> <rx antenna> [<radio address:port>]".into()),
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
            let authority_origin = origin.clone();
            let (store, authorization) = tokio::task::spawn_blocking(move || {
                let mut store = store; // CL-044-05: migrate friendly-name device entries before any owner reads them.
                #[cfg(windows)]
                if radio_setup::needs_migration(&store.document) {
                    match radio_setup::native_endpoints() {
                        Ok(endpoints) => {
                            for line in radio_setup::migrate_devices(&mut store, &endpoints) {
                                eprintln!("{line}");
                            }
                        }
                        Err(_) => {
                            eprintln!("profile: device migration skipped (audio_unavailable)")
                        }
                    }
                }

                authorization_http::Service::initialize(&mut store, &authority_origin)
                    .map(|authority| (store, authority))
            })
            .await?
            .map_err(|_| error("resource_unavailable", ""))?;
            let boot = profile::new_uuid().map_err(|_| error("resource_unavailable", ""))?;
            let base = selected.clone().ok_or("profile directory absent")?;
            let id = store.document.profile_id.clone();
            let recording_boot = boot.clone();
            let recording = tokio::task::spawn_blocking(move || {
                recording::Recording::open(&base, id, recording_boot)
            })
            .await?;
            recording.initialize_profile_revision(store.document.revision);
            // WstxTransmit slice B: one transmit owner per station, disarmed at startup.
            // WstxTransmit::TransmitClock: the station measures its UTC offset by SNTP
            // on its own thread, at start and every minute. WSTX_SNTP_SERVERS replaces
            // the server order (comma-separated; empty: never measure, clock unknown).
            let mut sntp = wstx_rust::transmit::clock::Sntp::station();
            if let Ok(list) = env::var("WSTX_SNTP_SERVERS") {
                sntp.servers = wstx_rust::transmit::clock::server_list(&list);
            }
            let clock = wstx_rust::transmit::clock::Monitor::start(
                Box::new(sntp),
                wstx_rust::transmit::clock::INTERVAL,
            )
            .map_err(|_| error("resource_unavailable", ""))?;
            // #43: the profile's clock source (clock.json) combines SNTP with the clock
            // from the air into the station clock of receive and transmit.
            let clock_base = selected.clone().ok_or("profile directory absent")?;
            let clock_profile = recording.profile.clone();
            let clock = tokio::task::spawn_blocking(move || {
                clock_http::Clock::load(&clock_base, &clock_profile, clock)
            })
            .await?;
            let _ = recording.clock.set(clock.clone());
            let transmit = transmit_http::Station::start(clock.station.clone())
                .map_err(|_| error("resource_unavailable", ""))?;
            // Process exit and panics stop output and release a keyed CI-V switch once.
            let guard = transmit.clone();
            #[cfg(windows)]
            wstx_rust::playback::install_exit_guard(Box::new(move || guard.emergency_release()));
            #[cfg(not(windows))]
            let _ = guard;
            let hooked = transmit.clone();
            let previous = std::panic::take_hook();
            std::panic::set_hook(Box::new(move |info| {
                hooked.emergency_release();
                previous(info);
            }));
            let _ = recording.transmit.set(transmit);
            recording.start_hashes(&store.document.callsign);
            recording.sync_transmit_mode();
            // WstxContact: one contact engine per station, consuming the transmit owner.
            let _ = recording.contact.set(contact_http::Station::start());
            // FR-023: a native profile starts its own direct radio session; a standard
            // profile never opens a native socket.
            if let Some(native) = &store.document.native {
                let mut config = wstx_rust::flex::Config::default();
                if let Ok(value) = env::var("WSTX_FLEX_DISCOVERY") {
                    config.discovery = value
                        .parse()
                        .map_err(|_| error("invalid_runtime_configuration", ""))?;
                }
                if let Ok(value) = env::var("WSTX_FLEX_REGISTER_PORT") {
                    let port = value
                        .parse()
                        .map_err(|_| error("invalid_runtime_configuration", ""))?;
                    config.register_ports = [port, port];
                }
                let session = wstx_rust::flex::Session::start(native.intent(), config)
                    .map_err(|_| error("resource_unavailable", ""))?;
                let _ = recording.flex.set(session);
            }
            let log_base = selected.clone().ok_or("profile directory absent")?;
            let logbook = Arc::new(
                tokio::task::spawn_blocking(move || logbook::Logbook::open(&log_base)).await?,
            );
            let watched = recording.clone();
            tokio::spawn(async move {
                let mut timer = interval(Duration::from_millis(50));
                loop {
                    timer.tick().await;
                    watched.tick();
                }
            });
            let state = Arc::new(ProfileState {
                store: Mutex::new(store),
                authorization: Mutex::new(authorization),
                boot,
                recording,
                logbook,
            });
            // CL-044-07: the saved audio endpoints' names, before the first /receive.
            let named = state.clone();
            tokio::task::spawn_blocking(move || {
                // CL-044-15: the next free radio, before the CAT lifecycle first ticks.
                if !env::var("WSTX_RADIO_DISCOVERY").is_ok_and(|v| v == "off")
                    && let Some(line) = radio_setup::discover_on_start(&named)
                {
                    eprintln!("{line}");
                }
                radio_setup::startup_names(&named);
                // CL-044-12: the stored Tx level, before anything can transmit.
                radio_level::startup(&named);
            })
            .await?;
            // WstxContact: the station-wide contact step, whether or not a browser is connected.
            let contacts = state.clone();
            tokio::spawn(async move {
                let mut timer = interval(Duration::from_millis(50));
                timer.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
                loop {
                    timer.tick().await;
                    let current = contacts.clone();
                    let _ =
                        tokio::task::spawn_blocking(move || contact_http::station_tick(&current))
                            .await;
                }
            });
            // WstxUdp: the station's UDP interface and its step. WSTX_UDP=off opens no
            // socket (isolated tests of the executable never reach port 2237).
            let disabled = env::var("WSTX_UDP").is_ok_and(|v| v == "off");
            let opened = state.clone();
            let owner =
                tokio::task::spawn_blocking(move || udp::Owner::open(&opened, disabled)).await?;
            let _ = state.recording.udp.set(owner);
            // WstxStrategy::HearingFeed: read-only; its thread waits on the network, nothing
            // else does. WSTX_PSKR=off opens no connection (isolated tests of the executable).
            let feed_base = selected.clone().ok_or("profile directory absent")?;
            let feed_setting = env::var("WSTX_PSKR").ok();
            let feed = pskr::Feed::start(
                &feed_base,
                &state.recording.profile,
                &state.recording.boot,
                pskr::station_connector(feed_setting.as_deref()),
                pskr::Timing::BROKER,
            );
            let _ = state.recording.pskr.set(feed);
            let interface = state.clone();
            tokio::spawn(async move {
                let mut timer = interval(Duration::from_millis(50));
                timer.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
                loop {
                    timer.tick().await;
                    let current = interface.clone();
                    let _ = tokio::task::spawn_blocking(move || udp::station_tick(&current)).await;
                }
            });
            // CL-022-03/04: one station-wide timer and at most one tick in flight; it
            // runs whether or not any browser is connected.
            let lifecycle = state.clone();
            tokio::spawn(async move {
                let mut timer = interval(Duration::from_millis(50));
                timer.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
                loop {
                    timer.tick().await;
                    let current = lifecycle.clone();
                    let _ = tokio::task::spawn_blocking(move || {
                        authorization_http::cat_tick(&current, Instant::now())
                    })
                    .await;
                }
            });
            // #45 CL-045-02: resume the last started receive unless Monitor off at
            // startup; a band resume waits (bounded) for the CAT lifecycle above.
            let (device, cat) = {
                let store = state.store.lock().unwrap();
                (
                    profile::receive_device(&store.document),
                    store.document.control.mode == "cat",
                )
            };
            if state
                .recording
                .resume_receive(device, cat, recording::startup::CAT_WAIT)
                .is_err()
            {
                eprintln!("receive: startup resume could not start");
            }
            Some(state)
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
    let app = router(state);
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
fn router(state: App) -> Router {
    Router::new()
        .route("/", get(index))
        .route("/authorization.js", get(|| async { ([(header::CONTENT_TYPE, "text/javascript; charset=utf-8")], include_str!("../../client/authorization.js")) }))
        .route("/app.js", get(|| async { ([(header::CONTENT_TYPE, "text/javascript; charset=utf-8")], include_str!("../../client/app.js")) }))
        .route("/recording.js", get(|| async { ([(header::CONTENT_TYPE, "text/javascript; charset=utf-8")], include_str!("../../client/recording.js")) }))
        .route("/recording.css", get(|| async { ([(header::CONTENT_TYPE, "text/css; charset=utf-8")], include_str!("../../client/recording.css")) }))
        .route("/contact.js", get(|| async { ([(header::CONTENT_TYPE, "text/javascript; charset=utf-8")], include_str!("../../client/contact.js")) }))
        .route("/logbook.js", get(|| async { ([(header::CONTENT_TYPE, "text/javascript; charset=utf-8")], include_str!("../../client/logbook.js")) }))
        .route("/style.css", get(|| async { ([(header::CONTENT_TYPE, "text/css; charset=utf-8")], include_str!("../../client/style.css")) }))
        .route("/session", post(session).layer(axum::extract::DefaultBodyLimit::max(1024)))
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
        .route("/receive/start", post(receive_http::start).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/receive/stop", post(receive_http::stop).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/receive/results", get(receive_http::results))
        .route("/receive/clock", get(receive_http::clock))
        .route("/clock", get(clock_http::snapshot).post(clock_http::update).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/receive/startup", get(receive_http::startup).post(receive_http::startup_update).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/receive/diagnostics", get(receive_http::diagnostics).post(receive_http::diagnostics_update).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/receive/selection", get(selection_http::snapshot))
        .route("/receive/select", post(selection_http::select).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/native-flex", get(flex_http::snapshot))
        .route("/radio", get(radio_http::snapshot))
        .route("/radio/connect", post(radio_http::connect).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/radio/disconnect", post(radio_http::disconnect).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/radio/operation", post(radio_http::execute).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/radio/detect", post(radio_setup::detect_route).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/radio/settings/apply", post(radio_setup::apply_route).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/radio/tx-level", post(radio_level::route).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/radio/settings/undo", post(radio_setup::undo_route).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/transmit", get(transmit_http::snapshot))
        .route("/transmit/command", post(transmit_http::execute).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/transmit/halt", post(transmit_http::halt).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/recording/imports", post(recording_http::reserve).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/recording/imports/{id}", get(recording_http::import).put(recording_http::import).delete(recording_http::import).layer(axum::extract::DefaultBodyLimit::max(2048)))
        .route("/recording/replay", post(recording_http::replay).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/recording/jobs/{id}", axum::routing::delete(recording_http::cancel_job))
        .route("/contacts", get(logbook_http::history).post(logbook_http::save).layer(axum::extract::DefaultBodyLimit::max(logbook_http::SAVE_BODY_MAX)))
        .route("/contacts/export.adi", get(logbook_http::export))
        .route("/contacts/imports", post(logbook_http::reserve).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/contacts/imports/{id}", get(logbook_http::import).put(logbook_http::import).layer(axum::extract::DefaultBodyLimit::max(logbook::IMPORT_CHUNK_BYTES_MAX)))
        .route("/contact", get(contact_http::snapshot))
        .route("/contact/command", post(contact_http::command).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/dxcc", get(logbook_http::dxcc).put(logbook_http::dxcc_put).layer(axum::extract::DefaultBodyLimit::max(logbook_http::DXCC_BODY_MAX)))
        .route("/automation", get(automation::snapshot))
        .route("/automation/command", post(automation::command).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/strategy", get(strategy::snapshot).put(strategy::put).layer(axum::extract::DefaultBodyLimit::max(strategy::BODY_MAX)))
        .route("/strategy/evaluate", post(strategy::evaluate_route).layer(axum::extract::DefaultBodyLimit::max(strategy::BODY_MAX)))
        .route("/strategy/ignore", post(strategy::ignore_route).layer(axum::extract::DefaultBodyLimit::max(strategy::BODY_MAX)))
        .route("/strategy/auto", post(strategy::auto_route).layer(axum::extract::DefaultBodyLimit::max(strategy::BODY_MAX)))
        .route("/strategy/most-wanted/download", post(strategy::most_wanted_download_route).layer(axum::extract::DefaultBodyLimit::max(strategy::BODY_MAX)))
        .route("/strategy/alerts", get(strategy::alerts_route))
        .route("/strategy/contests", get(strategy::contests_route))
        .route("/strategy/alerts/clear", post(strategy::clear_alerts_route).layer(axum::extract::DefaultBodyLimit::max(strategy::BODY_MAX)))
        .route("/pskr", get(pskr::snapshot).post(pskr::update).layer(axum::extract::DefaultBodyLimit::max(1024)))
        .route("/pskr/use", post(pskr::update_use).layer(axum::extract::DefaultBodyLimit::max(1024)))
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
        .with_state(state)
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
// #33: the running station reports the commit its release build was made from, so a
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
    ([("x-wstx-source-commit", commit)], Html(include_str!("../../client/index.html").replace(
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
    match tokio::task::spawn_blocking(move || match state.store.lock() {
        Ok(store) => {
            let Ok(owner) = state.authorization.lock() else {
                return authorization_http::mapped(authorization::Error::PersistenceFailed);
            };
            if let Err(error) =
                authorization_http::configuration_access(&headers, &app, owner.as_ref())
            {
                return authorization_http::mapped(error);
            }
            Json(representation(&state, &store.document, &app.origin)).into_response()
        }
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
    match tokio::task::spawn_blocking(move || {
        let Ok(mut store) = state.store.lock() else {
            return profile_error(StatusCode::SERVICE_UNAVAILABLE, "storage_unavailable", None);
        };
        let Ok(mut authorization) = state.authorization.lock() else {
            return authorization_http::mapped(authorization::Error::PersistenceFailed);
        };
        // Validated under the held authorization lock: no separate dispatch recheck needed.
        if let Err(error) =
            authorization_http::configuration_access(&headers, &app, authorization.as_ref())
        {
            return authorization_http::mapped(error);
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
        let mut edit: profile::Edit = match serde_path_to_error::deserialize(&mut deserializer) {
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
                    "settings.radio",
                    "settings.radio.agc",
                    "settings.radio.power_limit_pct",
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
        edit.settings.complete_radio(store.document.radio);
        if let Err(field) = edit.settings.validate().and_then(|()| {
            if store.document.native.is_some() {
                edit.settings.validate_native()
            } else {
                Ok(())
            }
        }) {
            return profile_error(StatusCode::BAD_REQUEST, "invalid_settings", Some(field));
        } // CL-044-05: a saved audio device is a WASAPI endpoint ID, never a friendly name.
        if let Err(field) = edit.settings.audio.validate_endpoints() {
            return profile_error(
                StatusCode::BAD_REQUEST,
                "audio_device_not_endpoint",
                Some(field),
            );
        }

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
        if let Some(service) = authorization.as_mut()
            && service.authority.reconcile_control(&mut store).is_err()
        {
            return profile_error(StatusCode::SERVICE_UNAVAILABLE, "storage_unavailable", None);
        }
        drop(authorization);
        state.recording.profile_changed(store.document.revision);
        state.recording.set_my_call(Some(&store.document.callsign));
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

async fn session(
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

async fn upgrade(State(app): State<App>, headers: HeaderMap, ws: WebSocketUpgrade) -> Response {
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
        .max_message_size(1024)
        .max_frame_size(1024)
        .write_buffer_size(0)
        .max_write_buffer_size(4096)
        .on_upgrade(move |socket| async move {
            let _permit = permit;
            // #39 an authenticated client is here (WstxStrategy::StrategyRun).
            let _client = app.profile.as_ref().map(|p| p.recording.clients.session());
            connection(socket, app.profile, authority).await
        })
}

/// WstxStationProtocol::ClientBuild (#51): the identity of the embedded browser client, the
/// first 16 hex digits of the SHA-256 over every served client file in route order. The page
/// carries the build it was served with; station.status carries the station's.
fn client_build() -> &'static str {
    static BUILD: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    BUILD.get_or_init(|| {
        let mut digest = ring::digest::Context::new(&ring::digest::SHA256);
        for asset in [
            include_str!("../../client/index.html"),
            include_str!("../../client/authorization.js"),
            include_str!("../../client/app.js"),
            include_str!("../../client/recording.js"),
            include_str!("../../client/recording.css"),
            include_str!("../../client/contact.js"),
            include_str!("../../client/logbook.js"),
            include_str!("../../client/style.css"),
        ] {
            digest.update(asset.as_bytes());
        }
        digest.finish().as_ref()[..8]
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect()
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
            json!({"v":1,"type":"station.status","id":id,"data":{"version":env!("CARGO_PKG_VERSION"),"radio":"unconfigured","build":client_build()}})
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

// A late interval tick must not keep the old grid and send the next frame early.
fn arm_detail(
    tick: &mut tokio::time::Interval,
    accepted: tokio::time::Instant,
    behind: bool,
) -> tokio::time::Instant {
    // #54: a subscriber behind the station catches up at 170 ms per row (under 10 KiB/s).
    let next = accepted + Duration::from_millis(if behind { 170 } else { 200 });
    tick.reset_at(next);
    next
}
/// #54: the next live Thin pacing anchor is the previous one plus the period, so 100 ms ticks do
/// not drift against the 1 row/s source. A send more than half a period late restarts the grid
/// at the send, so two sends are always at least half a period (1 s live) apart.
fn next_thin_anchor(previous: Instant, period: Duration, now: Instant) -> Instant {
    let next = previous + period;
    if now.saturating_duration_since(next) > period / 2 {
        now
    } else {
        next
    }
}
/// #54: the oldest retained Detailed row after the one this socket sent last (rows of
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

struct ConnectionAuthority {
    state: Arc<ProfileState>,
    access: authorization::Access,
}
impl ConnectionAuthority {
    // Test-only synchronous observation; production uses current_async below.
    #[cfg(test)]
    fn current(&self) -> bool {
        self.state
            .authorization
            .lock()
            .ok()
            .and_then(|owner| {
                owner
                    .as_ref()
                    .map(|s| s.authority.current_grant(&self.access).is_ok())
            })
            .unwrap_or(false)
    }
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
    mut socket: WebSocket,
    profile: Option<Arc<ProfileState>>,
    authority: Option<ConnectionAuthority>,
) {
    let recording = profile.as_ref().map(|p| p.recording.clone());
    let mut heartbeat = interval(Duration::from_secs(5));
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
    // #57 CL-057-01: a Detailed peer is told of each new or grown decode view at once; Thin
    // and Off keep the 2 s receive tick that their link budget is measured with.
    let mut publication = recording.as_ref().map(|r| r.publication.subscribe());
    // WstxContact::ContactStateEvent / StationTickEvent pacing (optional writes).
    let mut contact_tick = interval(Duration::from_secs(1));
    contact_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut contact_seen: Option<(u64, Option<u64>)> = None;
    // What this peer holds of the contact snapshot, and when it was last sent.
    let mut contact_sent = Value::Null;
    let mut contact_sent_at = Instant::now();
    // WstxTransmit::TransmitWire transmit.state (pushed state, coalesced like contact.state).
    let mut transmit_seen: Option<u64> = None;
    // What this peer holds: the fields it was last sent, and when.
    let mut transmit_sent = Value::Null;
    let mut transmit_sent_at = Instant::now();
    // WstxMcp::AutomationStateEvent: only after a change since boot (no event while unused).
    let mut automation_seen: Option<(u64, u64)> = Some((0, 0));
    // #65 free_tx_slots.state: the decision this Detailed or Thin peer holds (None: none, also
    // while Off, so that a peer coming from Off gets the current value once).
    let mut free_tx_slots_seen: Option<u64> = None;
    // #39 WstxStrategy::StrategyHttp strategy.state: only after a change since this peer subscribed.
    let mut strategy_seen: Option<u64> = None;
    // #42 WstxStrategy::Alert alert.state: only after a change since this peer subscribed.
    let mut alert_seen: Option<u64> = None;
    // #44 CL-044-11 radio.agc: the managed AGC and its last read-back, once known, then
    // after each change (the first event is this peer's snapshot).
    let mut agc_seen: u64 = 0;
    // #39 WstxStrategy::HearingFeed pskr.state: after a change since this peer subscribed
    // (the first event follows its GET /pskr snapshot).
    let mut pskr_seen: u64 = 0;
    // #44 CL-044-13 radio.tx_level: after each change of the level, assistant or meters.
    let mut tx_level_seen: u64 = 0;
    // FR-023 radio.native: this peer's snapshot, then each change of the native session.
    let mut native_seen: u64 = 0;
    // Pushed recording.state: its comparison key (without received_bytes), the last data and when.
    let mut recording_tick = interval(Duration::from_secs(1));
    recording_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut recording_seen: Option<(Value, Value, Instant)> = None;
    let mut profile_seen: Option<u64> = None;
    // WstxOperatingReceive::SelectionStateEvent: what this peer holds, and when it was last sent.
    let mut selection_sent = Value::Null;
    let mut selection_sent_at = Instant::now();
    let mut last_station_tick: Option<Instant> = None;
    let mut tick_transmitting: Option<bool> = None;
    // Events pace by the peer's display subscription; a peer that never chose one
    // (a bare status observer) receives none.
    let mut subscribed = false;
    let reason = loop {
        let auth_ready = if let Some(context) = &authority {
            match context.current_async().await {
                Ok(true) => true,
                Ok(false) => break "authority",
                Err(_) => false,
            }
        } else {
            true
        };
        tokio::select! {
            biased;
            _ = tokio::time::sleep_until((optional_since.unwrap_or_else(Instant::now)+Duration::from_secs(2)).into()), if optional_since.is_some()=>break "optional flush stalled 2 s",
            _ = heartbeat.tick() => {
                if last_pong.elapsed() > Duration::from_secs(15) { break "no pong for 15 s"; }
                if !send_control(&mut socket, Message::Text(json!({"v":1,"type":"heartbeat"}).to_string().into()),optional_since).await { break "heartbeat write"; }
                optional_since=None;
                if !send(&mut socket,Message::Ping(Vec::new().into())).await {break "ping write";}
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
                    if !send_control(&mut socket,Message::Text(json!({"v":1,"type":"receive.state","data":event}).to_string().into()),optional_since).await {break "receive.state write";}
                    optional_since=None;receive_seen=key;receive_sent=data;
                }
            }
            _ = contact_tick.tick(), if subscribed && recording.as_ref().is_some_and(|r| r.contact.get().is_some()) => {
                if !auth_ready { continue; }
                if optional_since.is_some() {
                    match optional_flush(&mut socket) { Ok(true)=>optional_since=None, Ok(false)=>continue, Err(_)=>break "optional write error" }
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
                                Err(_)=>break "optional write error",
                            }
                        }
                    }
                }
                if let Some(revision)=transmit_http::state_revision(r) && transmit_seen!=Some(revision) {
                    let now=transmit_http::pushed_view(r).unwrap_or(Value::Null);
                    let changed=transmit_http::changed_fields(&transmit_sent,&now);
                    if changed.is_empty() {transmit_seen=Some(revision);}
                    else if transmit_http::due(display_profile,&changed,transmit_sent_at.elapsed()) {
                        match optional_write(&mut socket,Message::Text(transmit_http::state_event(r,revision,changed).into())) {
                            Ok(None)=>{},
                            Ok(Some(flushed))=>{transmit_seen=Some(revision);transmit_sent=now;transmit_sent_at=Instant::now();if !flushed {optional_since=Some(Instant::now());continue;}},
                            Err(_)=>break "optional write error",
                        }
                    }
                }
                let automation=r.contact.get().map(|c|c.automation.revisions());
                if automation.is_some() && automation!=automation_seen {
                    match optional_write(&mut socket,Message::Text(automation::state_event(r,automation.unwrap_or_default()).into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{automation_seen=automation;if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break "optional write error",
                    }
                }
                if display_profile!="off" && let Some((decision,text))=r.contact.get().and_then(|c|c.automation.free_tx_slots_event(r)) && free_tx_slots_seen!=Some(decision) {
                    match optional_write(&mut socket,Message::Text(text.into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{free_tx_slots_seen=Some(decision);if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break "optional write error",
                    }
                }
                let strategy=r.contact.get().map_or(0,|c|c.strategy.revision());
                if strategy_seen.is_none() { strategy_seen=Some(strategy); }
                if strategy_seen!=Some(strategy) {
                    match optional_write(&mut socket,Message::Text(strategy::state_event(r,strategy).into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{strategy_seen=Some(strategy);if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break "optional write error",
                    }
                }
                let alert=r.contact.get().map_or(0,|c|c.strategy.alert_revision());
                if alert_seen.is_none() { alert_seen=Some(alert); }
                if alert_seen!=Some(alert) {
                    match optional_write(&mut socket,Message::Text(strategy::alert_event(r,alert).into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{alert_seen=Some(alert);if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break "optional write error",
                    }
                }
                if r.agc.revision()!=agc_seen {
                    let (revision,text)=radio_agc::event(r);
                    match optional_write(&mut socket,Message::Text(text.into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{agc_seen=revision;if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break "optional write error",
                    }
                }
                if let Some(feed)=r.pskr.get() && feed.revision()!=pskr_seen {
                    let (revision,text)=feed.event();
                    match optional_write(&mut socket,Message::Text(text.into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{pskr_seen=revision;if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break "optional write error",
                    }
                }
                if r.tx_level.revision()!=tx_level_seen {
                    let (revision,text)=radio_level::event(r);
                    match optional_write(&mut socket,Message::Text(text.into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{tx_level_seen=revision;if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break "optional write error",
                    }
                }
                if let Some(session)=r.flex.get() && session.revision()!=native_seen {
                    let (revision,text)=flex_http::event(r,session);
                    match optional_write(&mut socket,Message::Text(text.into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{native_seen=revision;if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break "optional write error",
                    }
                }
                let (text,transmitting)=contact_http::tick_event(r);
                // Detailed 1 per second; Thin and Off 1 per 5 s; plus transmit start/stop.
                let every=Duration::from_millis(if display_profile=="detail" {950} else {4950});
                if last_station_tick.is_none_or(|t|t.elapsed()>=every) || tick_transmitting.is_some_and(|t|t!=transmitting) {
                    match optional_write(&mut socket,Message::Text(text.into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{last_station_tick=Some(Instant::now());tick_transmitting=Some(transmitting);if !flushed {optional_since=Some(Instant::now());}},
                        Err(_)=>break "optional write error",
                    }
                }
            }
            _ = recording_tick.tick(), if subscribed && recording.is_some() => {
                if !auth_ready { continue; }
                if optional_since.is_some() {
                    match optional_flush(&mut socket) { Ok(true)=>optional_since=None, Ok(false)=>continue, Err(_)=>break "optional write error" }
                }
                let (revision,text)=recording.as_ref().unwrap().profile_state_event();
                if profile_seen!=Some(revision) {
                    match optional_write(&mut socket,Message::Text(text.into())) {
                        Ok(None)=>{},
                        Ok(Some(flushed))=>{profile_seen=Some(revision);if !flushed {optional_since=Some(Instant::now());continue;}},
                        Err(_)=>break "optional write error",
                    }
                }
                if let Some(now)=profile.as_ref().and_then(|p|selection_http::pushed_view(p)) {
                    let changed=selection_http::state_changes(&selection_sent,&now);
                    if !changed.is_empty() && selection_http::state_due(display_profile,&changed,&selection_sent,&now,selection_sent_at.elapsed()) {
                        let (text,holds)=selection_http::state_event(&selection_sent,&now,changed);
                        match optional_write(&mut socket,Message::Text(text.into())) {
                            Ok(None)=>{},
                            Ok(Some(flushed))=>{selection_sent=holds;selection_sent_at=Instant::now();if !flushed {optional_since=Some(Instant::now());continue;}},
                            Err(_)=>break "optional write error",
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
                        Err(_)=>break "optional write error",
                    }
                }
            }
            incoming = socket.recv() => match incoming {
                Some(Ok(Message::Text(text))) => {
                    if let Some(context) = &authority {
                        match context.current_async().await { Ok(true) => (), Ok(false) => break "authority", Err(_) => continue }
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
                    if !send_control(&mut socket, Message::Text(value.to_string().into()),optional_since).await { break "reply write"; }
                    optional_since=None;
                }
                Some(Ok(Message::Pong(_))) => last_pong = Instant::now(),
                Some(Ok(Message::Binary(_))) => { let _ = send_control(&mut socket, Message::Close(Some(CloseFrame { code: 1003, reason: "text required".into() })),optional_since).await; break "binary frame"; }
                Some(Ok(Message::Ping(_))) => {},
                _ => break "peer closed or receive error",
            },
            _ = async { if display_profile=="detail" {detail_tick.tick().await} else {display.tick().await} }, if display_profile != "off" => {
                if optional_since.is_some() {
                    match optional_flush(&mut socket) { Ok(true)=>optional_since=None, Ok(false)=>continue, Err(_)=>break "optional write error" }
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
                            Err(_)=>break "optional write error",
                        }
                    }
                }
            }
        }
    };
    #[cfg(test)]
    SOCKET_CLOSES
        .lock()
        .unwrap()
        .push(json!({"utc_ms":std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0,|d|d.as_millis() as u64),"reason":reason}));
    let _ = reason;
}
/// Why each socket of this test process ended, recorded per run by TC-007-005.
#[cfg(test)]
pub(crate) static SOCKET_CLOSES: Mutex<Vec<Value>> = Mutex::new(Vec::new());
