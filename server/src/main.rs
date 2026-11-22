#![forbid(unsafe_code)]
#[cfg(test)]
mod auth_tests;
#[path = "supervisor/authorization.rs"]
mod authorization;
#[path = "supervisor/authorization_http.rs"]
mod authorization_http;
#[path = "operating/auto/automation.rs"]
mod automation;
#[path = "radioControl/cat_lifecycle.rs"]
mod cat_lifecycle;
#[cfg(test)]
#[path = "radioControl/cat_lifecycle_tests.rs"]
mod cat_lifecycle_tests;
#[path = "clock/clock_http.rs"]
mod clock_http;
#[path = "operating/qso/contact.rs"]
mod contact;
#[path = "operating/qso/contact_http.rs"]
mod contact_http;
#[path = "log/dxcc.rs"]
mod dxcc;
#[path = "flexAdapter/flex_http.rs"]
mod flex_http;
#[path = "operating/qso/freeslot.rs"]
mod freeslot;
#[path = "web/content_coding.rs"]
mod http_compression;
#[cfg(test)]
#[path = "web/content_coding_tests.rs"]
mod http_compression_tests;
#[path = "web/link_log.rs"]
mod link_log;
#[cfg(test)]
#[path = "web/link_log_tests.rs"]
mod link_log_tests;
#[path = "web/listener.rs"]
mod listener;
#[cfg(test)]
#[path = "web/liveness_tests.rs"]
mod liveness_tests;
#[path = "log/logbook.rs"]
mod logbook;
#[path = "log/logbook_http.rs"]
mod logbook_http;
#[path = "mcp/endpoint.rs"]
mod mcp;
#[cfg(test)]
#[path = "mcp/endpoint_tests.rs"]
mod mcp_tests;
mod profile;
#[path = "spots/pskr.rs"]
mod pskr;
#[path = "radioControl/radio_agc.rs"]
mod radio_agc;
#[path = "radioControl/radio_http.rs"]
mod radio_http;
#[cfg(test)]
#[path = "radioControl/radio_http_tests.rs"]
mod radio_http_tests;
#[path = "transmit/radio_level.rs"]
mod radio_level;
#[path = "radioControl/radio_setup.rs"]
mod radio_setup;
#[cfg(test)]
#[path = "radioControl/radio_setup_tests.rs"]
mod radio_setup_tests;
#[path = "receive/receive.rs"]
mod receive;
#[path = "receive/receive_http.rs"]
mod receive_http;
#[cfg(test)]
#[path = "receive/receive_http_tests.rs"]
mod receive_http_tests;
#[path = "receive/recording.rs"]
mod recording;
mod recording_http;
#[path = "supervisor/selection.rs"]
mod selection;
#[path = "supervisor/selection_http.rs"]
mod selection_http;
#[cfg(all(test, not(debug_assertions)))]
#[path = "supervisor/selection_http_tests.rs"]
mod selection_http_tests;
#[cfg(test)]
#[path = "web/socket_bounds_tests.rs"]
mod socket_bounds_tests;
use wstx_rust::{audio, decoder, source};
#[path = "operating/contest.rs"]
mod contest;
#[path = "operating/ranking/most_wanted.rs"]
mod most_wanted;
#[path = "receive/spectrum.rs"]
mod spectrum;
#[path = "operating/strategy.rs"]
mod strategy;
#[path = "transmit/transmit_http.rs"]
mod transmit_http;
#[path = "udp/udp.rs"]
mod udp;
use axum::{Json, body::Bytes};
use axum::{
    Router,
    extract::{
        State, WebSocketUpgrade,
        rejection::BytesRejection,
        ws::{CloseFrame, Message},
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
    // The station's one file port: the disk.
    let files: Arc<dyn profile::Files> = Arc::new(profile::Disk);
    let args: Vec<_> = env::args_os().skip(1).collect();
    let selected = match args.as_slice() {
        [] => None,
        [command, directory] if command == "--create-profile" || command == "--profile" => {
            let directory = PathBuf::from(directory);
            if command == "--create-profile" {
                let (target, files) = (directory.clone(), files.clone());
                tokio::task::spawn_blocking(move || profile::Store::create(&target, files)).await?
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
            let (target, antenna, files) = (directory.clone(), antenna.to_owned(), files.clone());
            tokio::task::spawn_blocking(move || {
                profile::Store::create_native(&target, &antenna, address.as_deref(), files)
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
        let (path, files) = (path.clone(), files.clone());
        Some(
            tokio::task::spawn_blocking(move || profile::Store::open(&path, files))
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
            // The station's clocks, one for every part that reads or waits on time.
            let station_clock: Arc<dyn wstx_rust::transmit::clock::Clock> =
                Arc::new(wstx_rust::transmit::clock::SystemClock);
            let (recording_boot, recording_files, recording_clock) =
                (boot.clone(), files.clone(), station_clock.clone());
            let recording = tokio::task::spawn_blocking(move || {
                recording::Recording::open(
                    &base,
                    id,
                    recording_boot,
                    recording_files,
                    recording_clock,
                    Arc::new(recording::Threads),
                    Arc::new(recording::WavFiles),
                )
            })
            .await?;
            // The live inputs receive opens: the WASAPI capture of the selected device.
            #[cfg(windows)]
            let _ = recording
                .inputs
                .set(std::sync::Arc::new(recording::AudioInputs {
                    capture: std::sync::Arc::new(audio::Wasapi),
                }));
            // The ports and audio endpoints radio detection reads.
            #[cfg(windows)]
            let _ = recording
                .radio_setup
                .hardware
                .set(std::sync::Arc::new(radio_setup::Native));
            // The station's CAT serial line, leased under its radio-ownership folder.
            #[cfg(windows)]
            let _ = recording.cat_opener.set(std::sync::Arc::new(
                wstx_rust::radio_control::windows::SerialOpener {
                    lock_root: env::var_os("LOCALAPPDATA")
                        .map(std::path::PathBuf::from)
                        .unwrap_or_else(env::temp_dir)
                        .join("WstxRust")
                        .join("radio-ownership"),
                },
            ));
            recording.initialize_profile_revision(store.document.revision);
            // WstxTransmitPart::TransmitService: one transmit owner per station, disarmed at
            // startup. WstxStationClock::TimeServerCheck: the station measures its UTC offset
            // by SNTP on its own thread, at start and every minute. WSTX_SNTP_SERVERS replaces
            // the server order (comma-separated; empty: never measure, no NTP warning).
            let mut sntp = wstx_rust::transmit::clock::Sntp::station();
            if let Ok(list) = env::var("WSTX_SNTP_SERVERS") {
                sntp.servers = wstx_rust::transmit::clock::server_list(&list);
            }
            let clock = wstx_rust::transmit::clock::Monitor::start(
                Box::new(sntp),
                wstx_rust::transmit::clock::INTERVAL,
            )
            .map_err(|_| error("resource_unavailable", ""))?;
            // The station clock of receive and transmit: the system clock plus
            // the correction from the air; SNTP only measures for warnings (no source
            // setting; a clock.json in the station folder is ignored and left in place).
            let clock = clock_http::Clock::new(
                clock,
                station_clock.clone(),
                Box::new(wstx_rust::transmit::clock::windows_time),
            );
            let _ = recording.clock.set(clock.clone());
            // The transmit adapter: PTT through the CAT actor, audio to the output device.
            let shared = transmit_http::Shared::default();
            let hardware = transmit_http::StationHardware::new(clock.station.clone(), &shared);
            let transmit =
                transmit_http::Station::start(clock.station.clone(), shared, Box::new(hardware))
                    .map_err(|_| error("resource_unavailable", ""))?;
            // Process exit and panics stop output and release a keyed CI-V switch once; the
            // exit then sends Close to the UDP targets (CL-112-06).
            let guard = transmit.clone();
            let exiting = recording.clone();
            #[cfg(windows)]
            wstx_rust::playback::install_exit_guard(Box::new(move || {
                udp::exit(&exiting, || guard.emergency_release())
            }));
            #[cfg(not(windows))]
            let _ = (guard, exiting);
            let hooked = transmit.clone();
            let previous = std::panic::take_hook();
            std::panic::set_hook(Box::new(move |info| {
                hooked.emergency_release();
                previous(info);
            }));
            let _ = recording.transmit.set(transmit);
            recording.start_hashes(&store.document.callsign);
            recording.sync_transmit_mode();
            // WstxQsoPart::QsoService: one contact engine per station, consuming the transmit
            // owner.
            let contact = contact_http::Station::start(&store, station_clock);
            // WstxClubLog::MostWantedQuery: Download now asks Club Log.
            contact
                .strategy
                .set_list_source(Box::new(most_wanted::ClubLog));
            let _ = recording.contact.set(contact);
            // FR-023: a native profile starts its own direct radio session; a standard
            // profile never opens a native socket.
            if let Some(native) = &store.document.native {
                let mut config = wstx_rust::flex::Config::default();
                if let Some(address) = native.discovery() {
                    config.discovery = address;
                }
                if let Some(port) = native.register_port {
                    config.register_ports = [port, port];
                }
                let session = wstx_rust::flex::Session::start(native.intent(), config)
                    .map_err(|_| error("resource_unavailable", ""))?;
                let _ = recording.flex.set(session);
            }
            let log_base = selected.clone().ok_or("profile directory absent")?;
            let log_files = files.clone();
            let logbook = Arc::new(
                tokio::task::spawn_blocking(move || logbook::Logbook::open(&log_base, log_files))
                    .await?,
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
                if let Some(line) = radio_setup::discover_on_start(&named) {
                    eprintln!("{line}");
                }
                radio_setup::startup_names(&named);
                // CL-044-12: the stored Tx level, before anything can transmit.
                radio_level::startup(&named);
            })
            .await?;
            // WstxQsoPart::QsoService: the station-wide contact step, whether or not a browser is
            // connected.
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
            // WstxUdp: the station's UDP interface and its step. The name is fixed here,
            // after radio discovery.
            let opened = state.clone();
            let instance_locks = env::var_os("LOCALAPPDATA")
                .map(PathBuf::from)
                .unwrap_or_else(env::temp_dir)
                .join("WstxRust")
                .join("udp-instance");
            let owner = tokio::task::spawn_blocking(move || {
                udp::Owner::open(&opened, &instance_locks, Arc::new(udp::SystemSockets))
            })
            .await?;
            let _ = state.recording.udp.set(owner);
            // WstxHearingFeed::HearingFeed: read-only; its thread waits on the network, nothing
            // else does.
            let feed_base = selected.clone().ok_or("profile directory absent")?;
            let feed = pskr::Feed::start(
                &feed_base,
                &state.recording.profile,
                &state.recording.boot,
                pskr::broker_connector(),
                pskr::FeedSession::BROKER,
                files.clone(),
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
            // CL-045-02: resume the last started receive unless Monitor off at
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
    // WstxListener::LinkTrafficLog: a station with a profile directory counts the
    // bytes of every accepted connection and writes them per period; without one, no log.
    let log = profile.as_ref().map(|state| {
        let log = link_log::Log::new(Box::new(link_log::StationClock(state.recording.clone())));
        link_log::spawn_writer(log.clone(), state.clone());
        log
    });
    let state = App {
        origin: origin.clone(),
        profile,
        profile_id,
        token,
        connections: Arc::new(Semaphore::new(listener::SOCKET_BOUND)),
        login_attempts: Arc::new(Mutex::new((Instant::now(), 0))),
    };
    let app = listener::router(state);
    println!("WSTX address {scheme}://{address}");
    let server = link_log::Server::new(listener, tls, log)
        .map_err(|_| error("resource_unavailable", "Listener unavailable"))?;
    println!("WSTX listening {origin}");
    server.serve(app).await?;
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
fn profile_error(status: StatusCode, code: &str, field: Option<&str>) -> Response {
    (status, Json(json!({"error":{"code":code,"field":field}}))).into_response()
}
fn representation(state: &ProfileState, doc: &profile::ProfileDocument, origin: &str) -> Value {
    profile::representation(doc, &state.boot, origin)
}
async fn get_profile(State(app): State<App>, headers: HeaderMap) -> Response {
    let Some(state) = app.profile.clone() else {
        return StatusCode::NOT_FOUND.into_response();
    };
    if headers.contains_key(header::ORIGIN) && !listener::allowed_origin(&headers, &app) {
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
    if !listener::allowed_origin(&headers, &app) {
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
