#![forbid(unsafe_code)]
//! WstxUdp: the WSJT-X-compatible UDP interface with multiple targets (#40). The station
//! step sends Heartbeat, Status, Decode and Clear to each enabled target; SaveContact sends
//! QSO Logged and Logged ADIF. Send-only (operator 2026-11-06): the station reacts to the
//! browser and MCP, never to a UDP command; a target's Heartbeat only negotiates the header
//! schema. Routes: GET /udp (UdpSnapshot), PUT /udp (configuration).
use crate::*;
use axum::extract::RawQuery;
use recording_http::authorize;
use selection_http::empty;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, UdpSocket};
use wstx_rust::network_message as nm;
use wstx_rust::transmit::service::ArmState;

#[cfg(test)]
#[path = "udp_tests.rs"]
mod tests;

pub const TARGETS_MAX: usize = 16;
pub const BODY_MAX: usize = 8192;
pub const FILE_NAME: &str = "udp.json";
pub const INSTANCE_DEFAULT: &str = "WSTX-Rust";
const HEARTBEAT: Duration = Duration::from_secs(15);
const DATAGRAMS_PER_STEP: usize = 64;
/// Winsock WSAEMSGSIZE: a received datagram was larger than the buffer.
const WSAEMSGSIZE: i32 = 10040;
const FILE_BYTES_MAX: u64 = 65_536;
const MAX_SAFE: u64 = 9_007_199_254_740_991;
/// OutboundMessage names in enum order (bit i of a target's selection).
pub const MESSAGES: [&str; 7] = [
    "heartbeat",
    "status",
    "decode",
    "clear",
    "qso_logged",
    "close",
    "logged_adif",
];
const HEARTBEAT_BIT: u8 = 1;
const STATUS_BIT: u8 = 2;
const DECODE_BIT: u8 = 4;
const CLEAR_BIT: u8 = 8;
const QSO_LOGGED_BIT: u8 = 16;
const CLOSE_BIT: u8 = 32;
const LOGGED_ADIF_BIT: u8 = 64;

/// WstxUdp::UdpTarget.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Target {
    pub address: SocketAddr,
    pub enabled: bool,
    /// multicast_ttl: the IPv4 TTL or the IPv6 hop limit of a multicast target.
    pub ttl: u32,
    pub interface: Option<Interface>,
    pub messages: u8,
}
/// multicast_interface: an IPv4 address for an IPv4 target, an interface index for an
/// IPv6 target (WstxUdp D6).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Interface {
    V4(Ipv4Addr),
    Index(u32),
}
impl Interface {
    fn text(&self) -> String {
        match self {
            Interface::V4(ip) => ip.to_string(),
            Interface::Index(i) => i.to_string(),
        }
    }
}
/// An IPv6 interface index: decimal digits without sign or leading zero, 1..=u32::MAX.
fn interface_index(s: &str) -> Option<u32> {
    let digits = !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit()) && !s.starts_with('0');
    digits.then(|| s.parse().ok()).flatten()
}
/// The scope of an IPv6 multicast group (RFC 4291 2.7): its fourth nibble.
fn multicast_scope(ip: &Ipv6Addr) -> u16 {
    ip.segments()[0] & 0x000f
}
impl Target {
    fn json(&self) -> Value {
        let messages: Vec<&str> = MESSAGES
            .iter()
            .enumerate()
            .filter(|(i, _)| self.messages & (1 << i) != 0)
            .map(|(_, m)| *m)
            .collect();
        json!({"address":self.address.to_string(),"enabled":self.enabled,"multicast_ttl":self.ttl,
            "multicast_interface":self.interface.map(|i|i.text()),"messages":messages})
    }
    /// The socket settings: a change reopens the socket.
    fn socket_key(&self) -> (SocketAddr, bool, u32, Option<Interface>) {
        (self.address, self.enabled, self.ttl, self.interface)
    }
}
/// WstxUdp::UdpConfiguration (without its revision).
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Config {
    pub instance: String,
    pub targets: Vec<Target>,
}
impl Config {
    pub(crate) fn default_list() -> Self {
        Self {
            instance: INSTANCE_DEFAULT.into(),
            targets: vec![Target {
                address: SocketAddr::from((Ipv4Addr::LOCALHOST, 2237)),
                enabled: true,
                ttl: 1,
                interface: None,
                messages: 127,
            }],
        }
    }
    fn json(&self) -> Value {
        json!({"instance_name":self.instance,"targets":self.targets.iter().map(Target::json).collect::<Vec<_>>()})
    }
}

fn exact<'a>(
    v: &'a Value,
    keys: &[&'static str],
    field: &str,
) -> Result<&'a serde_json::Map<String, Value>, String> {
    let o = v.as_object().ok_or_else(|| field.to_owned())?;
    if o.len() != keys.len() || !keys.iter().all(|k| o.contains_key(*k)) {
        return Err(field.to_owned());
    }
    Ok(o)
}
fn target(v: &Value, i: usize) -> Result<Target, String> {
    let f = |k: &str| format!("targets[{i}].{k}");
    exact(
        v,
        &[
            "address",
            "enabled",
            "multicast_ttl",
            "multicast_interface",
            "messages",
        ],
        &format!("targets[{i}]"),
    )?;
    let address: SocketAddr = v["address"]
        .as_str()
        .and_then(|a| a.parse().ok())
        .ok_or_else(|| f("address"))?;
    // An IPv6 multicast group of reserved scope 0 or 15 has no defined reach.
    let refused = match address.ip() {
        IpAddr::V4(ip) => ip.is_unspecified() || ip.is_broadcast(),
        IpAddr::V6(ip) => {
            ip.is_unspecified() || (ip.is_multicast() && matches!(multicast_scope(&ip), 0 | 15))
        }
    };
    if refused || address.port() == 0 {
        return Err(f("address"));
    }
    let enabled = v["enabled"].as_bool().ok_or_else(|| f("enabled"))?;
    let ttl = v["multicast_ttl"]
        .as_u64()
        .filter(|t| (1..=255).contains(t))
        .ok_or_else(|| f("multicast_ttl"))? as u32;
    // An IPv6 group names an interface index; every other address keeps the IPv4 form
    // (a unicast target ignores it), so a saved udp.json of #40 still loads.
    let interface = match (&v["multicast_interface"], address.ip()) {
        (Value::Null, _) => None,
        (Value::String(s), IpAddr::V6(ip)) if ip.is_multicast() => Some(Interface::Index(
            interface_index(s).ok_or_else(|| f("multicast_interface"))?,
        )),
        (Value::String(s), _) => Some(Interface::V4(
            s.parse::<Ipv4Addr>()
                .map_err(|_| f("multicast_interface"))?,
        )),
        _ => return Err(f("multicast_interface")),
    };
    // An interface-local or link-local group exists only on one interface: name it.
    if let IpAddr::V6(ip) = address.ip()
        && ip.is_multicast()
        && matches!(multicast_scope(&ip), 1 | 2)
        && interface.is_none()
    {
        return Err(f("multicast_interface"));
    }
    let mut messages = 0u8;
    for m in v["messages"].as_array().ok_or_else(|| f("messages"))? {
        let bit = m
            .as_str()
            .and_then(|m| MESSAGES.iter().position(|n| *n == m))
            .ok_or_else(|| f("messages"))?;
        if messages & (1 << bit) != 0 {
            return Err(f("messages"));
        }
        messages |= 1 << bit;
    }
    Ok(Target {
        address,
        enabled,
        ttl,
        interface,
        messages,
    })
}
/// Exact UdpConfiguration parsing; the error is the refused field.
pub(crate) fn parse_config(v: &Value) -> Result<Config, String> {
    exact(v, &["instance_name", "targets"], "configuration")?;
    let instance = v["instance_name"]
        .as_str()
        .filter(|s| {
            !s.is_empty() && s.len() <= 64 && !s.chars().any(char::is_control) && s.trim() == *s
        })
        .ok_or("instance_name")?
        .to_owned();
    let list = v["targets"].as_array().ok_or("targets")?;
    if list.len() > TARGETS_MAX {
        return Err("targets".into());
    }
    let mut targets: Vec<Target> = Vec::new();
    for (i, t) in list.iter().enumerate() {
        let t = target(t, i)?;
        if targets.iter().any(|o| o.address == t.address) {
            return Err(format!("targets[{i}].address"));
        }
        targets.push(t);
    }
    Ok(Config { instance, targets })
}

/// Volatile per-target state (WstxUdp::TargetStatus) and its socket.
#[derive(Default)]
struct Runtime {
    socket: Option<UdpSocket>,
    schema: u32,
    last_send: Option<i64>,
    error: Option<&'static str>,
    last_status: Option<Vec<u8>>,
    /// The decoder's windows-begun count when the last Status was sent.
    status_windows: u64,
    /// The last pulse (Heartbeat and Status resend), monotonic.
    pulse_at: Option<Instant>,
    /// A pulse fell due: the next Status goes out even when unchanged.
    status_due: bool,
}
type Identity = (String, String, u64);
#[derive(Default)]
struct Inner {
    revision: u64,
    config: Option<Config>,
    error: Option<&'static str>,
    runtimes: Vec<Runtime>,
    /// The live job whose decodes were sent and its next unsent sequence.
    cursor: Option<(Identity, u64)>,
    /// A Decode of the cursor's job was produced (a later change sends Clear).
    decoded: bool,
}
/// The UDP interface of one station.
pub(crate) struct Owner {
    inner: Mutex<Inner>,
    /// WSTX_UDP=off: no socket is opened (isolated tests of the executable).
    disabled: bool,
}

fn wall_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as i64)
}
/// The station's UTC (the #9 owner's clock when present).
fn now_ms(r: &recording::Recording) -> i64 {
    r.transmit
        .get()
        .map_or_else(wall_ms, |t| t.service.with(|c| c.hardware().now_utc_ms()))
}
fn open_socket(t: &Target) -> Option<UdpSocket> {
    let bind: SocketAddr = match t.address.ip() {
        IpAddr::V4(ip) if ip.is_loopback() => (Ipv4Addr::LOCALHOST, 0).into(),
        IpAddr::V4(_) => (Ipv4Addr::UNSPECIFIED, 0).into(),
        IpAddr::V6(ip) if ip.is_loopback() => (Ipv6Addr::LOCALHOST, 0).into(),
        IpAddr::V6(_) => (Ipv6Addr::UNSPECIFIED, 0).into(),
    };
    let socket = socket2::Socket::new(
        socket2::Domain::for_address(bind),
        socket2::Type::DGRAM,
        Some(socket2::Protocol::UDP),
    )
    .ok()?;
    match t.address.ip() {
        IpAddr::V4(group) if group.is_multicast() => {
            socket.set_multicast_ttl_v4(t.ttl).ok()?;
            socket.set_multicast_loop_v4(true).ok()?;
            if let Some(Interface::V4(interface)) = t.interface {
                socket.set_multicast_if_v4(&interface).ok()?;
            }
        }
        IpAddr::V6(group) if group.is_multicast() => {
            socket.set_multicast_hops_v6(t.ttl).ok()?;
            socket.set_multicast_loop_v6(true).ok()?;
            if let Some(Interface::Index(index)) = t.interface {
                socket.set_multicast_if_v6(index).ok()?;
            }
        }
        _ => {}
    }
    socket.bind(&bind.into()).ok()?;
    socket.set_nonblocking(true).ok()?;
    Some(socket.into())
}
fn activate(t: &Target, disabled: bool) -> Runtime {
    let mut rt = Runtime {
        schema: nm::SCHEMA_OUT,
        ..Runtime::default()
    };
    if t.enabled && !disabled {
        rt.socket = open_socket(t);
        if rt.socket.is_none() {
            rt.error = Some("socket_unavailable");
        }
    }
    rt
}
fn send(rt: &mut Runtime, to: SocketAddr, bytes: &[u8], now: i64) {
    let Some(socket) = &rt.socket else {
        return;
    };
    match socket.send_to(bytes, to) {
        Ok(_) => {
            rt.last_send = Some(now);
            if rt.error == Some("send_failed") {
                rt.error = None;
            }
        }
        Err(_) => rt.error = Some("send_failed"),
    }
}

/// Decoder text in the WSJT-X form (WstxUdp D4): "R -09" becomes "R-09".
pub(crate) fn wsjtx_text(record: &Value) -> Option<String> {
    let text = record["text"].as_str()?;
    let f = &record["fields"];
    if f["type"] == "standard"
        && f["ack"] == true
        && f["exchange"]["kind"] == "report"
        && let Some(report) = f["exchange"]["value"].as_i64()
        && let Some(stem) = text.strip_suffix(&format!(" R {report:+03}"))
    {
        return Some(format!("{stem} R{report:+03}"));
    }
    Some(text.to_owned())
}
/// The Decode fields of a published live record (WstxUdp::OutboundRules), if it has them.
pub(crate) fn decode_of(record: &Value, mode: &str) -> Option<nm::Decode> {
    if record["status"] != "decoded" {
        return None;
    }
    let period = record["period_start_utc"]
        .as_str()
        .and_then(contact::parse_utc)?;
    let frequency = record["frequency_hz"].as_f64().filter(|f| f.is_finite())?;
    let snr = record["snr_db"]
        .as_f64()
        .filter(|s| s.is_finite())
        .map_or(0, |s| s.round().clamp(-1000.0, 1000.0) as i32);
    Some(nm::Decode {
        time_ms: nm::ms_of_day(period),
        snr,
        delta_time: record["dt_seconds"].as_f64().unwrap_or(0.0) as f32,
        delta_frequency: frequency.round().clamp(0.0, 1.0e6) as u32,
        mode: if mode == "ft4" { "+" } else { "~" }.into(),
        message: wsjtx_text(record)?,
        low_confidence: false,
        off_air: false,
    })
}
/// Days since 1970-01-01 of a proleptic Gregorian date (Hinnant's days_from_civil).
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}
/// Unix ms of an ADIF date YYYYMMDD and time HHMM or HHMMSS (validated by the log).
pub(crate) fn adif_ms(date: Option<&str>, time: Option<&str>) -> i64 {
    let n = |s: &str, a: usize, b: usize| s.get(a..b).and_then(|t| t.parse::<i64>().ok());
    let (Some(date), Some(time)) = (date, time) else {
        return 0;
    };
    let (Some(y), Some(m), Some(d), Some(h), Some(min)) = (
        n(date, 0, 4),
        n(date, 4, 6),
        n(date, 6, 8),
        n(time, 0, 2),
        n(time, 2, 4),
    ) else {
        return 0;
    };
    let s = n(time, 4, 6).unwrap_or(0);
    (days_from_civil(y, m, d) * 86_400 + h * 3600 + min * 60 + s) * 1000
}
/// ADIF freq (MHz with six decimals) in Hz; 0 when absent.
fn freq_hz(freq: Option<&str>) -> u64 {
    let Some((whole, fraction)) = freq.and_then(|f| f.split_once('.')) else {
        return 0;
    };
    let padded = format!("{fraction:0<6}");
    let (Ok(w), Some(Ok(f))) = (
        whole.parse::<u64>(),
        padded.get(..6).map(|f| f.parse::<u64>()),
    ) else {
        return 0;
    };
    w.checked_mul(1_000_000)
        .and_then(|w| w.checked_add(f))
        .unwrap_or(0)
}
pub(crate) fn logged_of(record: &logbook::Record) -> nm::Logged {
    let g = |k: &str| record.get(k).unwrap_or("").to_owned();
    let mode = match (record.get("mode"), record.get("submode")) {
        (Some("MFSK"), Some(sub)) => sub.to_owned(),
        (mode, _) => mode.unwrap_or("").to_owned(),
    };
    nm::Logged {
        time_off: nm::DateTime::from_unix_ms(adif_ms(
            record.get("qso_date_off"),
            record.get("time_off"),
        )),
        dx_call: g("call"),
        dx_grid: g("gridsquare"),
        tx_frequency_hz: freq_hz(record.get("freq")),
        mode,
        report_sent: g("rst_sent"),
        report_received: g("rst_rcvd"),
        tx_power: g("tx_pwr"),
        comments: g("comment"),
        name: String::new(),
        time_on: nm::DateTime::from_unix_ms(adif_ms(record.get("qso_date"), record.get("time_on"))),
        operator_call: String::new(),
        my_call: g("station_callsign"),
        my_grid: g("my_gridsquare"),
    }
}
pub(crate) fn adif_text(record: &logbook::Record) -> String {
    format!(
        "\n<adif_ver:5>3.1.8\n<programid:9>WSTX-Rust\n<EOH>\n{} <EOR>",
        record.adi_fields()
    )
}
pub(crate) fn status_of(state: &ProfileState, r: &recording::Recording) -> nm::Status {
    let (call, grid, name) = {
        let store = state.store.lock().unwrap_or_else(|p| p.into_inner());
        let d = &store.document;
        (
            d.callsign.trim().to_ascii_uppercase(),
            contact_http::station_locator(&d.locator).unwrap_or_default(),
            d.display_name.clone(),
        )
    };
    let view = r.transmit.get().map(|t| t.service.view());
    let facts = r.contact.get().map(|c| c.status_facts());
    let mode = if r.operating_mode() == "ft4" {
        "FT4"
    } else {
        "FT8"
    };
    nm::Status {
        dial_hz: contact_http::confirmed_dial(r).unwrap_or(0),
        mode: mode.into(),
        dx_call: facts
            .as_ref()
            .and_then(|f| f.dx_call.clone())
            .unwrap_or_default(),
        report: facts
            .as_ref()
            .map_or(String::new(), |f| contact::render_report(f.report)),
        tx_mode: mode.into(),
        tx_enabled: view
            .as_ref()
            .is_some_and(|v| v.arm_state == ArmState::Armed),
        transmitting: view.as_ref().is_some_and(|v| v.transmitting),
        decoding: r.decoder_activity().0,
        rx_df: facts.as_ref().map_or(0, |f| f.rx_hz),
        tx_df: facts.as_ref().map_or(0, |f| f.tx_hz),
        de_call: call,
        de_grid: grid,
        dx_grid: facts
            .as_ref()
            .and_then(|f| f.dx_grid.clone())
            .unwrap_or_default(),
        tx_watchdog: view.as_ref().is_some_and(|v| v.tx_expired),
        sub_mode: String::new(),
        fast_mode: false,
        special_operation: facts.as_ref().map_or(0, |f| f.activity.special_operation()),
        frequency_tolerance: u32::MAX,
        tr_period: if mode == "FT4" { 7 } else { 15 },
        configuration_name: name,
        tx_message: facts.and_then(|f| f.next_message).unwrap_or_default(),
    }
}
impl Owner {
    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|p| p.into_inner())
    }
    /// Loads udp.json of the selected profile (missing: the default list) and opens the
    /// sockets of its enabled targets.
    pub(crate) fn open(state: &ProfileState, disabled: bool) -> Arc<Self> {
        let mut inner = Inner::default();
        let read = {
            let store = state.store.lock().unwrap_or_else(|p| p.into_inner());
            store.read_document_file(FILE_NAME, FILE_BYTES_MAX)
        };
        match read {
            Ok(None) => inner.config = Some(Config::default_list()),
            Ok(Some(bytes)) => {
                let loaded = serde_json::from_slice::<Value>(&bytes).ok().and_then(|v| {
                    let ok = v.as_object().is_some_and(|o| o.len() == 5)
                        && v["schema_version"] == 1
                        && v["profile_id"] == state.recording.profile.as_str()
                        && v["revision"].as_u64().is_some_and(|n| n <= MAX_SAFE);
                    // A file saved before send-only names accept_commands on each target: it
                    // keeps loading, and the next save drops the key.
                    let mut targets = v["targets"].clone();
                    for t in targets.as_array_mut().into_iter().flatten() {
                        if let Some(t) = t.as_object_mut() {
                            t.remove("accept_commands");
                        }
                    }
                    let config = json!({"instance_name":v["instance_name"],"targets":targets});
                    ok.then(|| parse_config(&config).ok())
                        .flatten()
                        .map(|c| (v["revision"].as_u64().unwrap_or(0), c))
                });
                match loaded {
                    Some((revision, config)) => {
                        inner.revision = revision;
                        inner.config = Some(config);
                    }
                    None => inner.error = Some("invalid_configuration"),
                }
            }
            Err(_) => inner.error = Some("invalid_configuration"),
        }
        if let Some(c) = &inner.config {
            inner.runtimes = c.targets.iter().map(|t| activate(t, disabled)).collect();
        }
        Arc::new(Self {
            inner: Mutex::new(inner),
            disabled,
        })
    }
    /// UdpSnapshot.
    pub(crate) fn snapshot(&self, r: &recording::Recording) -> Value {
        let inner = self.lock();
        let status: Vec<Value> = inner
            .config
            .iter()
            .flat_map(|c| c.targets.iter().zip(&inner.runtimes))
            .map(|(t, rt)| {
                json!({"address":t.address.to_string(),"active":rt.socket.is_some(),"schema":rt.schema,
                    "last_send_utc_ms":rt.last_send,"error":rt.error})
            })
            .collect();
        json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"revision":inner.revision,
            "configuration":inner.config.as_ref().map(Config::json),"configuration_error":inner.error,
            "status":status})
    }
    /// PUT /udp after the route checks: validation, revision, atomic save, then the
    /// running sockets follow the saved configuration.
    pub(crate) fn put(&self, state: &ProfileState, body: Value) -> Result<Value, Refusal> {
        let r = &state.recording;
        let keys = [
            "v",
            "profile_id",
            "boot_id",
            "expected_revision",
            "configuration",
        ];
        let o = body.as_object().ok_or(("invalid_request", None))?;
        if let Some(k) = keys.iter().find(|k| !o.contains_key(**k)) {
            return Err(("invalid_request", Some((*k).into())));
        }
        if o.len() != keys.len() {
            return Err(("invalid_request", None));
        }
        if body["v"].as_u64() != Some(1) {
            return Err(if body["v"].is_u64() {
                ("unsupported_version", Some("v".into()))
            } else {
                ("invalid_request", Some("v".into()))
            });
        }
        for k in ["profile_id", "boot_id"] {
            if !body[k].as_str().is_some_and(profile::valid_uuid) {
                return Err(("invalid_request", Some(k.into())));
            }
        }
        let expected = body["expected_revision"]
            .as_u64()
            .filter(|n| *n <= MAX_SAFE)
            .ok_or(("invalid_request", Some("expected_revision".into())))?;
        let config =
            parse_config(&body["configuration"]).map_err(|f| ("invalid_request", Some(f)))?;
        if body["profile_id"] != r.profile.as_str() {
            return Err(("wrong_profile", Some("profile_id".into())));
        }
        if body["boot_id"] != r.boot.as_str() {
            return Err(("state_conflict", Some("boot_id".into())));
        }
        let mut inner = self.lock();
        if expected != inner.revision {
            return Err(("stale_revision", Some("expected_revision".into())));
        }
        if inner.revision >= MAX_SAFE {
            return Err(("counter_exhausted", None));
        }
        let revision = inner.revision + 1;
        let document = json!({"schema_version":1,"profile_id":r.profile,"revision":revision,
            "instance_name":config.instance,"targets":config.json()["targets"]});
        {
            let mut store = state
                .store
                .lock()
                .map_err(|_| ("storage_unavailable", None))?;
            store
                .write_document_file(FILE_NAME, &document)
                .map_err(|_| ("storage_unavailable", None))?;
        }
        inner.revision = revision;
        inner.error = None;
        self.reconcile(&mut inner, config, now_ms(r));
        drop(inner);
        Ok(self.snapshot(r))
    }
    /// Close to a removed, disabled or changed target; activation of a new or changed one;
    /// an unchanged target keeps its socket, schema and status.
    fn reconcile(&self, inner: &mut Inner, next: Config, now: i64) {
        let old = inner.config.take();
        let mut old_runtimes: Vec<Option<Runtime>> = std::mem::take(&mut inner.runtimes)
            .into_iter()
            .map(Some)
            .collect();
        let mut runtimes = Vec::new();
        for t in &next.targets {
            let kept = old.as_ref().and_then(|o| {
                (o.instance == next.instance)
                    .then(|| {
                        o.targets
                            .iter()
                            .position(|ot| ot.socket_key() == t.socket_key())
                    })
                    .flatten()
            });
            match kept.and_then(|i| old_runtimes[i].take()) {
                Some(rt) => runtimes.push(rt),
                None => runtimes.push(activate(t, self.disabled)),
            }
        }
        if let Some(o) = &old {
            for (t, rt) in o.targets.iter().zip(old_runtimes.iter_mut()) {
                if let Some(rt) = rt.as_mut().filter(|rt| rt.socket.is_some())
                    && t.messages & CLOSE_BIT != 0
                {
                    let bytes = nm::close(rt.schema, &o.instance);
                    send(rt, t.address, &bytes, now);
                }
            }
        }
        inner.runtimes = runtimes;
        inner.config = Some(next);
    }
    /// One station step (main.rs timer, every 50 ms): schema negotiation, Heartbeat,
    /// Decode/Clear and Status.
    pub(crate) fn step(&self, state: &ProfileState) {
        let r = &state.recording;
        let mut inner = self.lock();
        // The decode cursor advances even without an open socket, so a target enabled
        // later never receives earlier decodes as new ones.
        let active = inner.runtimes.iter().any(|rt| rt.socket.is_some());
        let now = now_ms(r);
        if active {
            negotiate(&mut inner);
        }
        let inner = &mut *inner;
        // An invalid configuration has no targets; its cursor still advances, so a later
        // valid PUT never sends the retained decodes as new ones.
        let config = inner.config.clone().unwrap_or(Config {
            instance: String::new(),
            targets: Vec::new(),
        });
        let id = config.instance.as_str();
        let version = env!("CARGO_PKG_VERSION");
        // The pulse (MessageClient heartbeat_timer_, NetworkMessage::pulse 15 s): Heartbeat,
        // and the Status resent unchanged so a tool started later learns the state (#40).
        for (t, rt) in config.targets.iter().zip(inner.runtimes.iter_mut()) {
            if rt.socket.is_some() && rt.pulse_at.is_none_or(|at| at.elapsed() >= HEARTBEAT) {
                rt.pulse_at = Some(Instant::now());
                rt.status_due = true;
                if t.messages & HEARTBEAT_BIT != 0 {
                    let bytes = nm::heartbeat(rt.schema, id, version, "");
                    send(rt, t.address, &bytes, now);
                }
            }
        }
        // Decode and Clear of the current live job.
        let cursor = inner.cursor.clone();
        let live = r.live_records_after(
            cursor.as_ref().map(|c| &c.0),
            cursor.as_ref().map_or(0, |c| c.1),
        );
        let changed = match (&live, &cursor) {
            (Some((identity, _, _)), Some((previous, _))) => identity != previous,
            (None, Some(_)) => true,
            _ => false,
        };
        if changed {
            if inner.decoded {
                for (t, rt) in config.targets.iter().zip(inner.runtimes.iter_mut()) {
                    if t.messages & CLEAR_BIT != 0 {
                        let bytes = nm::clear(rt.schema, id);
                        send(rt, t.address, &bytes, now);
                    }
                }
            }
            inner.decoded = false;
            inner.cursor = None;
        }
        if let Some((identity, mode, records)) = live {
            let mut next = inner
                .cursor
                .as_ref()
                .filter(|c| c.0 == identity)
                .map_or(0, |c| c.1);
            for record in &records {
                let Some(sequence) = record["sequence"].as_u64() else {
                    continue;
                };
                if sequence < next {
                    continue;
                }
                next = sequence + 1;
                let Some(decode) = decode_of(record, mode) else {
                    continue;
                };
                inner.decoded = true;
                for (t, rt) in config.targets.iter().zip(inner.runtimes.iter_mut()) {
                    if t.messages & DECODE_BIT != 0 {
                        let bytes = nm::decode(rt.schema, id, true, &decode);
                        send(rt, t.address, &bytes, now);
                    }
                }
            }
            inner.cursor = Some((identity, next));
        }
        if !active {
            return;
        }
        // Status: at activation, on change, on each decoder window (a window begun and ended
        // between two steps still sends one) and with each pulse.
        let windows = r.decoder_activity().1;
        let status = status_of(state, r);
        for (t, rt) in config.targets.iter().zip(inner.runtimes.iter_mut()) {
            if rt.socket.is_none() {
                continue;
            }
            if t.messages & STATUS_BIT != 0 {
                let bytes = nm::status(rt.schema, id, &status);
                if rt.status_due
                    || rt.status_windows != windows
                    || rt.last_status.as_ref() != Some(&bytes)
                {
                    send(rt, t.address, &bytes, now);
                    rt.last_status = Some(bytes);
                    rt.status_windows = windows;
                }
            }
            rt.status_due = false;
        }
    }
    /// QSO Logged then Logged ADIF of a newly saved contact (SaveContact outcome saved).
    pub(crate) fn logged(&self, state: &ProfileState, record: &logbook::Record) {
        let mut inner = self.lock();
        let Some(config) = inner.config.clone() else {
            return;
        };
        let now = now_ms(&state.recording);
        let logged = logged_of(record);
        let adif = adif_text(record);
        for (t, rt) in config.targets.iter().zip(inner.runtimes.iter_mut()) {
            if t.messages & QSO_LOGGED_BIT != 0 {
                let bytes = nm::qso_logged(rt.schema, &config.instance, &logged);
                send(rt, t.address, &bytes, now);
            }
            if t.messages & LOGGED_ADIF_BIT != 0 {
                let bytes = nm::logged_adif(rt.schema, &config.instance, &adif);
                send(rt, t.address, &bytes, now);
            }
        }
    }
}
/// The one thing read from a target: its Heartbeat raises that target's header schema
/// (MessageClient negotiation, never lowered). Everything else is read and dropped, so a tool's
/// command has no effect and a pending ICMP error of an earlier send does not stay behind.
fn negotiate(inner: &mut Inner) {
    let Some(config) = &inner.config else {
        return;
    };
    for (t, rt) in config.targets.iter().zip(inner.runtimes.iter_mut()) {
        let Some(socket) = &rt.socket else {
            continue;
        };
        let mut buffer = [0u8; nm::INBOUND_BYTES_MAX + 1];
        for _ in 0..DATAGRAMS_PER_STEP {
            match socket.recv_from(&mut buffer) {
                Ok((n, from)) => {
                    if from == t.address
                        && let Some(h) = nm::heartbeat_of(&buffer[..n])
                        && h.id == config.instance
                    {
                        rt.schema = rt.schema.max(h.schema);
                    }
                }
                // Windows reports an earlier send's ICMP port unreachable here, and a
                // datagram larger than the buffer as WSAEMSGSIZE.
                Err(e)
                    if e.kind() == std::io::ErrorKind::ConnectionReset
                        || e.raw_os_error() == Some(WSAEMSGSIZE) => {}
                Err(_) => break,
            }
        }
    }
}

/// The station step of the UDP interface (main.rs timer).
pub(crate) fn station_tick(state: &ProfileState) {
    if let Some(owner) = state.recording.udp.get() {
        owner.step(state);
    }
}
/// SaveContact hook: a newly saved record goes to the targets.
pub(crate) fn logged(state: &ProfileState, record: &logbook::Record) {
    if let Some(owner) = state.recording.udp.get() {
        owner.logged(state, record);
    }
}

type Refusal = (&'static str, Option<String>);
fn refusal(code: &str, field: Option<&str>) -> Response {
    let status = match code {
        "unauthorized" => StatusCode::UNAUTHORIZED,
        "forbidden_origin" | "wrong_profile" => StatusCode::FORBIDDEN,
        "not_found" => StatusCode::NOT_FOUND,
        "request_too_large" => StatusCode::PAYLOAD_TOO_LARGE,
        "unsupported_media_type" => StatusCode::UNSUPPORTED_MEDIA_TYPE,
        "invalid_request" | "unsupported_version" => StatusCode::BAD_REQUEST,
        "storage_unavailable" => StatusCode::SERVICE_UNAVAILABLE,
        _ => StatusCode::CONFLICT,
    };
    profile_error(status, code, field)
}
pub async fn snapshot(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, false).await {
        Ok(r) => r,
        Err(e) => return refusal(e, None),
    };
    if let Err(e) = empty(query, body) {
        return refusal(e, None);
    }
    match r.udp.get() {
        Some(owner) => Json(owner.snapshot(&r)).into_response(),
        None => refusal("not_found", None),
    }
}
pub async fn put(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, true).await {
        Ok(r) => r,
        Err(e) => return refusal(e, None),
    };
    if query.is_some() {
        return refusal("invalid_request", None);
    }
    if !json_media_type(&headers) || headers.contains_key(header::CONTENT_ENCODING) {
        return refusal("unsupported_media_type", None);
    }
    let bytes = match body {
        Ok(b) if b.len() <= BODY_MAX => b,
        _ => return refusal("request_too_large", None),
    };
    let Ok(body) = serde_json::from_slice::<Value>(&bytes) else {
        return refusal("invalid_request", None);
    };
    let (Some(owner), Some(state)) = (r.udp.get().cloned(), app.profile.clone()) else {
        return refusal("not_found", None);
    };
    match tokio::task::spawn_blocking(move || owner.put(&state, body)).await {
        Ok(Ok(snapshot)) => Json(snapshot).into_response(),
        Ok(Err((code, field))) => refusal(code, field.as_deref()),
        Err(_) => refusal("storage_unavailable", None),
    }
}
