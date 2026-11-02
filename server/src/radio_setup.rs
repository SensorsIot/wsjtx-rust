//! #44 automatic radio detection and IC-7300 setup (CL-044-01..05): the station side.
//! Detection is read-only; "Apply recommended radio settings" and its undo are separate
//! operator actions through the station's single CAT owner.
use crate::*;
use axum::extract::RawQuery;
use recording_http::{authorize, error, parse, syntax};
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, Ordering};
use wstx_rust::radio_control::{
    self as cat, SetupCommand, SetupReply,
    executor::Transport,
    setup::{self, AudioEndpoint, Flow, Match, Migration, PortInfo, Setting},
};

pub(crate) const UNDO_FILE: &str = "radio-settings-undo.json";
const UNDO_MAX: u64 = 4096;
const DETECT_BUDGET: Duration = Duration::from_secs(40);
const PORT_BUDGET: Duration = Duration::from_secs(6);
const STEP: Duration = Duration::from_secs(4);

/// The physical world detection reads: ports, audio endpoints, and opening a port
/// under the CAT ownership claim with line-safe settings.
pub(crate) trait Hardware: Send + Sync {
    fn ports(&self) -> Result<Vec<PortInfo>, cat::Error>;
    fn endpoints(&self) -> Result<Vec<AudioEndpoint>, cat::Error>;
    fn open(
        &self,
        port: u16,
        deadline: Instant,
        cancel: &AtomicBool,
    ) -> Result<Box<dyn Transport>, cat::Error>;
}
#[cfg(windows)]
struct Native;
#[cfg(windows)]
impl Hardware for Native {
    fn ports(&self) -> Result<Vec<PortInfo>, cat::Error> {
        cat::windows::enumerate_ports()
    }
    fn endpoints(&self) -> Result<Vec<AudioEndpoint>, cat::Error> {
        native_endpoints()
    }
    fn open(
        &self,
        port: u16,
        deadline: Instant,
        cancel: &AtomicBool,
    ) -> Result<Box<dyn Transport>, cat::Error> {
        // The same per-device ownership claim as the CAT owner (Recording::radio_begin).
        let lock_root = std::env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir)
            .join("WstxRust")
            .join("radio-ownership");
        let configuration = cat::Configuration {
            port,
            baud: cat::Baud::Fixed(9600),
            radio_address: 0x94,
            controller_address: setup::CONTROLLER,
        };
        cat::windows::SerialTransport::open(&configuration, &lock_root, deadline, cancel)
            .map(|t| Box::new(t) as Box<dyn Transport>)
    }
}
#[cfg(windows)]
pub(crate) fn native_endpoints() -> Result<Vec<AudioEndpoint>, cat::Error> {
    let mut all = Vec::new();
    for (flow, list) in [
        (Flow::Capture, audio::enumerate_inputs()),
        (Flow::Render, audio::enumerate_outputs()),
    ] {
        for device in list.map_err(|_| cat::Error::Unavailable)? {
            let topology = cat::windows::device_topology(&format!("SWD\\MMDEVAPI\\{}", device.id))
                .map(|(_, t)| t)
                .unwrap_or_default();
            all.push(AudioEndpoint {
                id: device.id,
                name: device.name,
                flow,
                topology,
            });
        }
    }
    Ok(all)
}

/// Per-station detection state: one detection at a time, and the test seam.
#[derive(Default)]
pub(crate) struct Owner {
    pub(crate) busy: AtomicBool,
    #[cfg(test)]
    pub(crate) hardware: Mutex<Option<Arc<dyn Hardware>>>,
}
impl Owner {
    fn hardware(&self) -> Option<Arc<dyn Hardware>> {
        #[cfg(test)]
        if let Some(h) = self.hardware.lock().unwrap().clone() {
            return Some(h);
        }
        #[cfg(windows)]
        return Some(Arc::new(Native));
        #[cfg(not(windows))]
        None
    }
}
struct Busy<'a>(&'a AtomicBool);
impl Drop for Busy<'_> {
    fn drop(&mut self) {
        self.0.store(false, Ordering::Release);
    }
}

fn hex(v: u8) -> String {
    format!("{v:02X}")
}
fn readings_json(readings: &[(Setting, Option<u16>)]) -> Value {
    Value::Array(
        readings
            .iter()
            .map(|(s, v)| {
                let f = setup::guidance(*s, *v);
                json!({"item":s.item_text(),"name":s.name(),"value":v,"label":v.map(|v|s.label(v)),
                    "recommended":s.recommended(),"severity":f.severity,"message":f.message})
            })
            .collect(),
    )
}
fn audio_json(m: &Match) -> Value {
    match m {
        Match::One(e) => json!({"state":"one","id":e.id,"name":e.name}),
        Match::None => json!({"state":"none","id":null,"name":null}),
        Match::Ambiguous(n) => json!({"state":"ambiguous","id":null,"name":null,"count":n}),
    }
}
/// The station's own CAT owner and its configuration, observed without opening anything.
struct StationCat {
    actor: Arc<cat::actor::Actor>,
    snapshot: cat::Snapshot,
    configuration: Option<cat::Configuration>,
}
fn station_cat(state: &ProfileState) -> Option<StationCat> {
    let configuration = {
        let store = state.store.lock().ok()?;
        let c = &store.document.control;
        (c.mode == "cat")
            .then(|| {
                c.endpoint
                    .as_deref()
                    .and_then(|e| cat::Configuration::parse(e).ok())
            })
            .flatten()
    };
    let actor = state.recording.radio_actor()?;
    let snapshot = actor.snapshot().ok()?;
    (snapshot.state != cat::State::Closed).then_some(StationCat {
        actor,
        snapshot,
        configuration,
    })
}
fn read_all(
    mut read: impl FnMut(Setting) -> Result<Option<u16>, cat::Error>,
) -> (Vec<(Setting, Option<u16>)>, Option<&'static str>) {
    let mut readings = Vec::new();
    for s in setup::SETTINGS {
        match read(s) {
            Ok(v) => readings.push((s, v)),
            Err(e) => return (readings, Some(selection::radio_error(e))),
        }
    }
    (readings, None)
}

/// USB serial bridges of the model table's radios (Silicon Labs CP210x, VID 10C4 PID EA60).
pub(crate) const RADIO_BRIDGES: [(&str, &str); 1] = [("10C4", "EA60")];
fn radio_bridge(port: &PortInfo) -> bool {
    port.vid_pid()
        .is_some_and(|(v, p)| RADIO_BRIDGES.iter().any(|(a, b)| v == *a && p == *b))
}
/// CL-044-01..03: POST /radio/detect. Read-only; never opens the station's CAT port.
pub(crate) fn detect(state: &ProfileState) -> Result<Value, &'static str> {
    let owner = &state.recording.radio_setup;
    if owner
        .busy
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        return Err("busy");
    }
    let _busy = Busy(&owner.busy);
    let hardware = owner.hardware().ok_or("radio_unavailable")?;
    let started = Instant::now();
    let cancel = AtomicBool::new(false);
    let ports = hardware.ports().map_err(selection::radio_error)?;
    let (endpoints, audio_error) = match hardware.endpoints() {
        Ok(e) => (e, None),
        Err(_) => (Vec::new(), Some("audio_unavailable")),
    };
    let station = station_cat(state);
    let mut reports = Vec::new();
    let mut supported = Vec::new();
    let mut settings = Value::Null;
    for port in ports.iter().take(64) {
        let held = station.as_ref().filter(|s| {
            s.configuration
                .as_ref()
                .is_some_and(|c| c.port == port.port)
                || s.snapshot
                    .authority
                    .resource_id
                    .eq_ignore_ascii_case(&port.instance_id)
        });
        let mut radios = Vec::new();
        let port_state;
        if let Some(s) = held {
            // CL-044-01: reported from the running owner, never opened a second time.
            port_state = "station_cat";
            if s.snapshot.state == cat::State::Ready
                && let Some(c) = &s.configuration
            {
                let deadline = Instant::now() + STEP;
                if let Ok(SetupReply::Id(id)) = s.actor.setup(SetupCommand::ReadId, deadline) {
                    radios.push(setup::Identity {
                        baud: s.snapshot.effective_baud.unwrap_or(0),
                        address: c.radio_address,
                        id,
                    });
                    if id == 0x94 {
                        let (readings, error) = read_all(|s2| {
                            match s
                                .actor
                                .setup(SetupCommand::Read(s2), Instant::now() + STEP)?
                            {
                                SetupReply::Value(v) => Ok(v),
                                SetupReply::Id(_) => Err(cat::Error::Protocol),
                            }
                        });
                        settings = json!({"port":port.port,"source":"station_cat","civ_baud":s.snapshot.effective_baud,
                            "items":readings_json(&readings),"error":error});
                    }
                }
            }
        } else if started.elapsed() >= DETECT_BUDGET {
            port_state = "not_probed";
        } else if !radio_bridge(port) {
            // CL-044-01: only known radio USB bridges are opened; others are manual.
            port_state = "not_radio_bridge";
        } else {
            let deadline = Instant::now() + PORT_BUDGET;
            match hardware.open(port.port, deadline, &cancel) {
                Err(cat::Error::ResourceInUse) => port_state = "in_use",
                Err(_) => port_state = "unavailable",
                Ok(mut transport) => {
                    let found =
                        setup::probe(&mut *transport, deadline, &cancel).unwrap_or_default();
                    if let Some(radio) = found.iter().find(|r| r.id == 0x94) {
                        let at = radio.baud;
                        let address = radio.address;
                        // The probe stopped at the answering rate; the menu reads use it.
                        let (readings, error) = read_all(|s2| {
                            setup::probe_setting(
                                &mut *transport,
                                address,
                                s2,
                                Instant::now() + STEP,
                                &cancel,
                            )
                        });
                        if settings.is_null() {
                            settings = json!({"port":port.port,"source":"probe","civ_baud":at,
                                "items":readings_json(&readings),"error":error});
                        }
                    }
                    let _ = transport.close();
                    radios = found;
                    port_state = if radios.is_empty() {
                        "no_reply"
                    } else {
                        "identified"
                    };
                }
            }
        }
        let input = setup::match_audio(port, &endpoints, Flow::Capture);
        let output = setup::match_audio(port, &endpoints, Flow::Render);
        let radio_values: Vec<Value> = radios
            .iter()
            .map(|r| {
                let m = setup::model(r.id);
                if m.is_some_and(|m| m.station_cat) {
                    supported.push((port.port, r.clone(), input.clone(), output.clone()));
                }
                json!({"model":m.map(|m|m.name),"id":hex(r.id),"civ_address":hex(r.address),"baud":r.baud,
                    "station_cat":m.is_some_and(|m|m.station_cat),"unknown_model":m.is_none()})
            })
            .collect();
        let (vid, pid) = port.vid_pid().unzip();
        reports.push(json!({"port":format!("COM{}",port.port),"friendly_name":port.friendly_name,"vid":vid,"pid":pid,
            "instance_id":port.instance_id,"state":port_state,"radios":radio_values,
            "audio":if radios.is_empty(){Value::Null}else{json!({"input":audio_json(&input),"output":audio_json(&output)})}}));
    }
    let proposal = match supported.as_slice() {
        [(port, radio, input, output)] => {
            let pick = |m: &Match| match m {
                Match::One(e) => json!(e.id),
                _ => Value::Null,
            };
            let name = |m: &Match| match m {
                Match::One(e) => json!(e.name),
                _ => Value::Null,
            };
            json!({"port":format!("COM{port}"),"model":"IC-7300","civ_address":hex(radio.address),"baud":radio.baud,
                "control":{"mode":"cat","endpoint":format!("icom7300://COM{port}?baud={}&radio={:02x}&controller=e0",radio.baud,radio.address),"ptt":"cat"},
                "audio":{"input_device":pick(input),"output_device":pick(output),"input_name":name(input),"output_name":name(output)}})
        }
        _ => Value::Null,
    };
    Ok(
        json!({"v":1,"profile_id":state.recording.profile,"boot_id":state.boot,"ports":reports,
        "manual":setup::MANUAL_FAMILIES,"supported_radios":supported.len(),"proposal":proposal,
        "settings":settings,"audio_error":audio_error}),
    )
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub(crate) struct UndoItem {
    pub item: String,
    pub old: u16,
    pub new: u16,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub(crate) struct UndoRecord {
    pub schema_version: u8,
    pub profile_id: String,
    pub civ_address: String,
    pub items: Vec<UndoItem>,
}
fn read_undo(state: &ProfileState) -> Result<Option<UndoRecord>, &'static str> {
    let store = state.store.lock().map_err(|_| "storage_unavailable")?;
    let Some(bytes) = store
        .read_document_file(UNDO_FILE, UNDO_MAX)
        .map_err(|_| "storage_unavailable")?
    else {
        return Ok(None);
    };
    let record: UndoRecord = serde_json::from_slice(&bytes).map_err(|_| "invalid_undo_record")?;
    if record.schema_version != 1
        || record.profile_id != store.document.profile_id
        || record.items.len() > setup::APPLY_ORDER.len()
        || record.items.iter().any(|i| {
            Setting::from_item(&i.item)
                .is_none_or(|s| s.encode(i.old).is_err() || s.encode(i.new).is_err())
        })
    {
        return Err("invalid_undo_record");
    }
    Ok(Some(record))
}
/// Common preconditions of apply and undo (CL-044-04).
fn ready_ic7300(
    state: &ProfileState,
    generation: u64,
) -> Result<(Arc<cat::actor::Actor>, u8), &'static str> {
    let station = station_cat(state).ok_or("radio_unavailable")?;
    if station.snapshot.authority.connection_generation != generation {
        return Err("state_conflict");
    }
    if station.snapshot.state != cat::State::Ready {
        return Err("radio_unavailable");
    }
    let address = station
        .configuration
        .as_ref()
        .map(|c| c.radio_address)
        .ok_or("radio_unavailable")?;
    if let Some(transmit) = state.recording.transmit.get()
        && transmit.service.view().arm_state != wstx_rust::transmit::service::ArmState::Disarmed
    {
        return Err("transmit_armed");
    }
    match station
        .actor
        .setup(SetupCommand::ReadId, Instant::now() + STEP)
        .map_err(selection::radio_error)?
    {
        SetupReply::Id(0x94) => Ok((station.actor, address)),
        _ => Err("unsupported_radio"),
    }
}
fn write_all(
    actor: &cat::actor::Actor,
    writes: &[(Setting, u16)],
) -> (Vec<Value>, Option<(Setting, &'static str)>) {
    let mut done = Vec::new();
    for (setting, value) in writes {
        match actor.setup(SetupCommand::Write(*setting, *value), Instant::now() + STEP) {
            Ok(_) => {
                done.push(json!({"item":setting.item_text(),"name":setting.name(),"value":value}))
            }
            Err(e) => return (done, Some((*setting, selection::radio_error(e)))),
        }
    }
    (done, None)
}
fn outcome(
    state: &ProfileState,
    action: &str,
    done: Vec<Value>,
    failed: Option<(Setting, &'static str)>,
    record: Option<&UndoRecord>,
) -> Value {
    json!({"v":1,"profile_id":state.recording.profile,"boot_id":state.boot,"action":action,
        "result":if failed.is_some(){"failed"}else{"done"},"written":done,
        "failed_item":failed.map(|(s,_)|s.item_text()),"error":failed.map(|(_,e)|e),"undo":record})
}
/// CL-044-04 "Apply recommended radio settings".
pub(crate) fn apply(state: &ProfileState, generation: u64) -> Result<Value, &'static str> {
    let (actor, address) = ready_ic7300(state, generation)?;
    let mut readings = Vec::new();
    for s in setup::APPLY_ORDER {
        match actor
            .setup(SetupCommand::Read(s), Instant::now() + STEP)
            .map_err(selection::radio_error)?
        {
            SetupReply::Value(v) => readings.push((s, v)),
            SetupReply::Id(_) => return Err("radio_unavailable"),
        }
    }
    let plan = setup::plan(&readings);
    let mut record = read_undo(state)?.unwrap_or(UndoRecord {
        schema_version: 1,
        profile_id: state.recording.profile.clone(),
        civ_address: hex(address),
        items: Vec::new(),
    });
    if record.civ_address != hex(address) {
        return Err("undo_pending");
    }
    if plan.is_empty() {
        let existing = Some(&record).filter(|r| !r.items.is_empty());
        return Ok(outcome(state, "apply", Vec::new(), None, existing));
    }
    let recorded: Vec<String> = record.items.iter().map(|i| i.item.clone()).collect();
    for (setting, old, new) in &plan {
        let item = setting.item_text();
        match record.items.iter_mut().find(|i| i.item == item) {
            // The first recorded old value is the operator's own; keep it.
            Some(existing) => existing.new = *new,
            None => record.items.push(UndoItem {
                item,
                old: *old,
                new: *new,
            }),
        }
    }
    // The undo record is durable before the first write.
    state
        .store
        .lock()
        .map_err(|_| "storage_unavailable")?
        .write_document_file(UNDO_FILE, &record)
        .map_err(|_| "storage_unavailable")?;
    let writes: Vec<_> = plan.iter().map(|(s, _, n)| (*s, *n)).collect();
    let (done, failed) = write_all(&actor, &writes);
    if let Some((failed_setting, error)) = failed {
        // An item not reached is unchanged, and so is one the radio refused (FA) or one
        // refused before its frame (busy: TX or lease); only
        // what may have changed stays recorded, so a later undo can restore it all.
        let written: Vec<String> = done
            .iter()
            .filter_map(|v| v["item"].as_str().map(str::to_owned))
            .collect();
        let failed_item = failed_setting.item_text();
        record.items.retain(|i| {
            recorded.contains(&i.item)
                || written.contains(&i.item)
                || (i.item == failed_item && !matches!(error, "radio_rejected" | "busy"))
        });
        let mut store = state.store.lock().map_err(|_| "storage_unavailable")?;
        if record.items.is_empty() {
            store.remove_document_file(UNDO_FILE)
        } else {
            store.write_document_file(UNDO_FILE, &record)
        }
        .map_err(|_| "storage_unavailable")?;
        let kept = Some(&record).filter(|r| !r.items.is_empty());
        return Ok(outcome(state, "apply", done, failed, kept));
    }
    Ok(outcome(state, "apply", done, None, Some(&record)))
}
/// CL-044-04 undo: recorded old values in reverse order; the record goes only on success.
pub(crate) fn undo(state: &ProfileState, generation: u64) -> Result<Value, &'static str> {
    let record = read_undo(state)?.ok_or("nothing_to_undo")?;
    let (actor, address) = ready_ic7300(state, generation)?;
    if record.civ_address != hex(address) {
        return Err("state_conflict");
    }
    let writes: Vec<_> = record
        .items
        .iter()
        .rev()
        .filter_map(|i| Setting::from_item(&i.item).map(|s| (s, i.old)))
        .collect();
    let (done, failed) = write_all(&actor, &writes);
    if failed.is_some() {
        return Ok(outcome(state, "undo", done, failed, Some(&record)));
    }
    state
        .store
        .lock()
        .map_err(|_| "storage_unavailable")?
        .remove_document_file(UNDO_FILE)
        .map_err(|_| "storage_unavailable")?;
    Ok(outcome(state, "undo", done, None, None))
}

/// CL-044-05 startup migration of friendly-name device entries. Returns the log lines.
pub(crate) fn migrate_devices(
    store: &mut profile::Store,
    endpoints: &[AudioEndpoint],
) -> Vec<String> {
    let mut settings = store.document.settings();
    let mut log = Vec::new();
    let mut changed = false;
    for (field, value, flow) in [
        (
            "audio.input_device",
            &mut settings.audio.input_device,
            Flow::Capture,
        ),
        (
            "audio.output_device",
            &mut settings.audio.output_device,
            Flow::Render,
        ),
    ] {
        let Some(current) = value.clone() else {
            continue;
        };
        match setup::migrate(&current, endpoints, flow) {
            Migration::Unchanged => {}
            Migration::Migrated(id) => {
                log.push(format!("profile: {field} migrated to endpoint {id}"));
                *value = Some(id);
                changed = true;
            }
            Migration::NotFound => log.push(format!(
                "profile: {field} is not an endpoint ID (not_found)"
            )),
            Migration::Ambiguous => log.push(format!(
                "profile: {field} is not an endpoint ID (ambiguous)"
            )),
        }
    }
    if changed && store.save(settings).is_err() {
        log.push("profile: device migration could not be saved (storage_unavailable)".into());
    }
    log
}
/// True when a device entry needs the migration enumeration at all.
pub(crate) fn needs_migration(document: &profile::Document) -> bool {
    document.audio.validate_endpoints().is_err()
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Detect {
    v: u64,
    profile_id: String,
    boot_id: String,
    /// CL-044-01: the operator confirms that USB SEND/keying are OFF (or the radio is on
    /// a dummy load) before ports are opened: an open can pulse DTR/RTS before they
    /// are disabled.
    keying_inhibit_confirmed: bool,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Settings {
    v: u64,
    profile_id: String,
    boot_id: String,
    connection_generation: u64,
}
fn context(r: &recording::Recording, profile_id: &str, boot_id: &str) -> Result<(), &'static str> {
    if profile_id != r.profile {
        return Err("wrong_profile");
    }
    if boot_id != r.boot {
        return Err("state_conflict");
    }
    Ok(())
}
pub async fn detect_route(
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
    let b: Detect = match parse(&headers, body) {
        Ok(v) => v,
        Err(e) => return error(e),
    };
    if let Err(e) = syntax(b.v, &b.profile_id, &b.boot_id, 0)
        .and_then(|()| context(&r, &b.profile_id, &b.boot_id))
    {
        return error(e);
    }
    if !b.keying_inhibit_confirmed {
        return error("confirmation_required");
    }
    let Some(state) = app.profile.clone() else {
        return error("not_found");
    };
    match tokio::task::spawn_blocking(move || detect(&state)).await {
        Ok(Ok(v)) => Json(v).into_response(),
        Ok(Err(e)) => error(e),
        Err(_) => error("radio_unavailable"),
    }
}
async fn settings_route(
    app: App,
    headers: HeaderMap,
    query: Option<String>,
    body: Result<Bytes, BytesRejection>,
    action: fn(&ProfileState, u64) -> Result<Value, &'static str>,
) -> Response {
    let r = match authorize(&app, &headers, true).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    if query.is_some() {
        return error("invalid_request");
    }
    let b: Settings = match parse(&headers, body) {
        Ok(v) => v,
        Err(e) => return error(e),
    };
    if let Err(e) = syntax(b.v, &b.profile_id, &b.boot_id, b.connection_generation)
        .and_then(|()| context(&r, &b.profile_id, &b.boot_id))
    {
        return error(e);
    }
    let Some(state) = app.profile.clone() else {
        return error("not_found");
    };
    match tokio::task::spawn_blocking(move || action(&state, b.connection_generation)).await {
        Ok(Ok(v)) => Json(v).into_response(),
        Ok(Err(e)) => error(e),
        Err(_) => error("radio_unavailable"),
    }
}
pub async fn apply_route(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    settings_route(app, headers, query, body, apply).await
}
pub async fn undo_route(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    settings_route(app, headers, query, body, undo).await
}
