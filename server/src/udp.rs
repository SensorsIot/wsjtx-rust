#![forbid(unsafe_code)]
//! WstxUdp: the WSJT-X-compatible UDP interface with multiple targets. The station step
//! sends Heartbeat, Status, Decode and Clear to each enabled target; DirectLog and
//! SaveContact send QSO Logged and Logged ADIF; the exit guard sends Close. Send-only: the
//! station reacts to the browser and MCP, never to a UDP command; a target's Heartbeat only
//! negotiates the header schema. Every datagram carries the server's instance name
//! (CL-112-01). Routes: GET /udp (UdpSnapshot), PUT /udp (configuration).
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
/// CL-112-01 the base form of the instance name without a radio.
pub const INSTANCE_BASE: &str = "WSTX-Rust";
/// The model of a CAT control: every CAT endpoint is icom7300:// or a plain COMn of one
/// (WstxRadioIO), the IC-7300 of the radio model table.
const CAT_MODEL: &str = "IC-7300";
/// A clash beyond this many live servers takes the base form (bounded by the processes
/// that run).
const INSTANCE_NUMBER_MAX: u32 = 99;
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
/// WstxUdp::UdpConfiguration (without its revision): the target list.
#[derive(Clone, Debug, Default, PartialEq)]
pub(crate) struct Config {
    pub targets: Vec<Target>,
}
impl Config {
    pub(crate) fn default_list() -> Self {
        Self {
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
        json!({"targets":self.targets.iter().map(Target::json).collect::<Vec<_>>()})
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
    exact(v, &["targets"], "configuration")?;
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
    Ok(Config { targets })
}

/// CL-112-01 the base form of the instance name of a CAT or no-radio profile.
pub(crate) fn base_name(document: &profile::Document) -> String {
    let c = &document.control;
    let cat = c.mode == "cat"
        && c.endpoint
            .as_deref()
            .is_some_and(|e| wstx_rust::radio_control::Configuration::parse(e).is_ok());
    if cat {
        format!("{INSTANCE_BASE} - {CAT_MODEL}")
    } else {
        INSTANCE_BASE.into()
    }
}
/// CL-112-01 the base form of a native Flex profile once its session is ready with the
/// radio's model and the slice letter.
fn flex_name(session: &wstx_rust::flex::Session) -> Option<String> {
    let s = session.snapshot();
    if s.state != wstx_rust::flex::State::Ready {
        return None;
    }
    let model = s.radio.and_then(|r| r.model)?;
    let letter = s.slice.and_then(|l| l.letter)?;
    Some(format!("{INSTANCE_BASE} - {model} {letter}"))
}
/// The lock file of an instance name: its letters, digits and '-', others as '_'.
fn lock_file(name: &str) -> String {
    let stem: String = name
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect();
    format!("{stem}.lock")
}
/// CL-112-01: the first of the base form, then "base 2", "base 3", ... whose lock no live
/// server holds; the lock stays in `held` for the life of the process. Without a usable
/// lock folder the base form, unchecked.
fn claim(root: &std::path::Path, base: &str, held: &Mutex<Option<std::fs::File>>) -> String {
    if std::fs::create_dir_all(root).is_err() {
        return base.into();
    }
    for n in 1..=INSTANCE_NUMBER_MAX {
        let name = if n == 1 {
            base.to_owned()
        } else {
            format!("{base} {n}")
        };
        let Ok(file) = std::fs::OpenOptions::new()
            .create(true)
            .truncate(false)
            .write(true)
            .open(root.join(lock_file(&name)))
        else {
            return base.into();
        };
        match file.try_lock() {
            Ok(()) => {
                *held.lock().unwrap_or_else(|p| p.into_inner()) = Some(file);
                return name;
            }
            Err(std::fs::TryLockError::WouldBlock) => {}
            Err(_) => return base.into(),
        }
    }
    base.into()
}
/// CL-112-03 the delta time of a Decode: dt rounded to one decimal as Band Activity shows it
/// (decimal rounding of the exact value, a tie away from zero), as single precision.
pub(crate) fn delta_time(dt: Option<f64>) -> f32 {
    let Some(dt) = dt.filter(|d| d.is_finite()) else {
        return 0.0;
    };
    let t = dt.abs();
    let q = t * 4.0;
    // An exact tie at x.x5 is t = m / 4 with m odd: exactly representable, rounded away.
    let text = if q.fract() == 0.0 && q < 1e15 && (q as u64) % 2 == 1 {
        let tenths = (t * 10.0).ceil() as u64;
        format!("{}.{}", tenths / 10, tenths % 10)
    } else {
        format!("{t:.1}")
    };
    let value: f32 = text.parse().unwrap_or(0.0);
    if dt < 0.0 && value != 0.0 {
        -value
    } else {
        value
    }
}
/// CL-112-05 Exchange sent and received of QSO Logged, rebuilt from the stored record by its
/// activity (WSJT-X mainwindow_qso.cpp captureLogQso, logqso.cpp xsent/xrcvd).
pub(crate) fn exchanges_of(record: &logbook::Record) -> (String, String) {
    let g = |k: &str| record.get(k);
    let left = |v: Option<&str>| v.map_or(String::new(), |s| s.chars().take(4).collect());
    let join = |a: Option<&str>, b: Option<&str>| match (a, b) {
        (Some(a), Some(b)) => format!("{a} {b}"),
        _ => String::new(),
    };
    // EuVhfExchange "5nSSSS GRID6" from RST (RS), STX/SRX and the 6-character grid.
    let eu = |rs: Option<&str>, serial: Option<&str>, grid: Option<&str>| match (rs, serial, grid) {
        (Some(rs), Some(serial), Some(grid)) if grid.len() >= 6 => {
            format!("{rs}{serial} {}", &grid[..6])
        }
        _ => String::new(),
    };
    match record.activity.as_deref() {
        Some("na_vhf" | "ww_digi" | "arrl_digi") => {
            (left(g("my_gridsquare")), left(g("gridsquare")))
        }
        Some("field_day" | "rtty") => (
            g("stx_string").map_or_else(|| join(g("rst_sent"), g("stx")), str::to_owned),
            g("srx_string").map_or_else(
                || join(g("rst_rcvd"), g("srx").or(g("state"))),
                str::to_owned,
            ),
        ),
        Some("eu_vhf") => (
            eu(g("rst_sent"), g("stx"), g("my_gridsquare")),
            eu(g("rst_rcvd"), g("srx"), g("gridsquare")),
        ),
        _ => (String::new(), String::new()),
    }
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
    /// CL-112-01 the instance name; None until a native Flex session is first ready.
    name: Option<String>,
    /// The last operating selection band seen (CL-112-04: a change sends Clear).
    band: Option<&'static str>,
}
/// The UDP interface of one station.
pub(crate) struct Owner {
    inner: Mutex<Inner>,
    /// WSTX_UDP=off: no socket is opened and no name is claimed (isolated tests).
    disabled: bool,
    /// The folder of the instance-name locks.
    lock_root: std::path::PathBuf,
    /// The lock of the claimed instance name, held while the owner (the process) lives.
    held: Mutex<Option<std::fs::File>>,
    /// Test seam: the next udp.json writes fail.
    #[cfg(test)]
    pub(crate) fail_write: std::sync::atomic::AtomicBool,
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
        delta_time: delta_time(record["dt_seconds"].as_f64()),
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
    let (exchange_sent, exchange_received) = exchanges_of(record);
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
        exchange_sent,
        exchange_received,
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
        // CL-112-02 WSJT-X m_operatingFrequency: the radio's dial, else the chosen band's.
        dial_hz: contact_http::confirmed_dial(r)
            .or_else(|| r.operating_nominal_hz())
            .unwrap_or(0),
        mode: mode.into(),
        dx_call: facts
            .as_ref()
            .and_then(|f| f.dx_call.clone())
            .unwrap_or_default(),
        // CL-112-02 WSJT-X QString::number: "-9", "3", "0".
        report: facts
            .as_ref()
            .map_or(String::new(), |f| f.report.to_string()),
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
    /// Loads udp.json of the selected profile (missing: the default list), fixes the
    /// instance name of a CAT or no-radio profile in `lock_root` (CL-112-01; a native Flex
    /// profile fixes it at its first ready session) and opens the sockets of the enabled
    /// targets. Called after radio discovery (CL-044-15), before the server serves.
    pub(crate) fn open(
        state: &ProfileState,
        disabled: bool,
        lock_root: &std::path::Path,
    ) -> Arc<Self> {
        let mut inner = Inner::default();
        let (read, base) = {
            let store = state.store.lock().unwrap_or_else(|p| p.into_inner());
            (
                store.read_document_file(FILE_NAME, FILE_BYTES_MAX),
                base_name(&store.document),
            )
        };
        let owner = Self {
            inner: Mutex::new(Inner::default()),
            disabled,
            lock_root: lock_root.to_owned(),
            held: Mutex::new(None),
            #[cfg(test)]
            fail_write: std::sync::atomic::AtomicBool::new(false),
        };
        if state.recording.flex.get().is_none() {
            inner.name = Some(owner.claim(&base));
        }
        match read {
            Ok(None) => inner.config = Some(Config::default_list()),
            Ok(Some(bytes)) => {
                let loaded = serde_json::from_slice::<Value>(&bytes)
                    .ok()
                    .and_then(|mut v| {
                        // A file saved while the name was a setting names instance_name: it
                        // keeps loading, and the next save drops the key.
                        if let Some(o) = v.as_object_mut() {
                            o.remove("instance_name");
                        }
                        let ok = v.as_object().is_some_and(|o| o.len() == 4)
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
                        let config = json!({"targets":targets});
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
        *owner.lock() = inner;
        Arc::new(owner)
    }
    /// The instance name of `base` (WSTX_UDP=off: the base form, nothing claimed).
    fn claim(&self, base: &str) -> String {
        if self.disabled {
            base.into()
        } else {
            claim(&self.lock_root, base, &self.held)
        }
    }
    /// A native Flex profile fixes its name when its session is first ready (CL-112-01).
    fn name_flex(&self, inner: &mut Inner, r: &recording::Recording) {
        if inner.name.is_none()
            && let Some(base) = r.flex.get().and_then(|s| flex_name(s))
        {
            inner.name = Some(self.claim(&base));
        }
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
        json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"instance_name":inner.name,
            "revision":inner.revision,"configuration":inner.config.as_ref().map(Config::json),
            "configuration_error":inner.error,"status":status})
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
            "targets":config.json()["targets"]});
        {
            let mut store = state
                .store
                .lock()
                .map_err(|_| ("storage_unavailable", None))?;
            #[cfg(test)]
            if self.fail_write.load(std::sync::atomic::Ordering::SeqCst) {
                return Err(("storage_unavailable", None));
            }
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
                o.targets
                    .iter()
                    .position(|ot| ot.socket_key() == t.socket_key())
            });
            match kept.and_then(|i| old_runtimes[i].take()) {
                Some(rt) => runtimes.push(rt),
                None => runtimes.push(activate(t, self.disabled)),
            }
        }
        if let (Some(o), Some(id)) = (&old, &inner.name) {
            for (t, rt) in o.targets.iter().zip(old_runtimes.iter_mut()) {
                if let Some(rt) = rt.as_mut().filter(|rt| rt.socket.is_some())
                    && t.messages & CLOSE_BIT != 0
                {
                    let bytes = nm::close(rt.schema, id);
                    send(rt, t.address, &bytes, now);
                }
            }
        }
        inner.runtimes = runtimes;
        inner.config = Some(next);
    }
    /// One station step (main.rs timer, every 50 ms): schema negotiation, Heartbeat,
    /// Decode, Clear and Status.
    pub(crate) fn step(&self, state: &ProfileState) {
        let r = &state.recording;
        let mut inner = self.lock();
        self.name_flex(&mut inner, r);
        // Without a name (a Flex session never ready) nothing is sent. The decode cursor
        // advances even without an open socket, so a target enabled later never receives
        // earlier decodes as new ones.
        let named = inner.name.clone();
        let active = named.is_some() && inner.runtimes.iter().any(|rt| rt.socket.is_some());
        let now = now_ms(r);
        if active {
            negotiate(&mut inner);
        }
        let inner = &mut *inner;
        // An invalid configuration has no targets; its cursor still advances, so a later
        // valid PUT never sends the retained decodes as new ones.
        let config = match (&named, &inner.config) {
            (Some(_), Some(c)) => c.clone(),
            _ => Config::default(),
        };
        let id = named.as_deref().unwrap_or("");
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
        // CL-112-04 Clear when the operating selection's band changes to another band (as
        // WSJT-X band_activity_cleared, whether or not a Decode was sent since).
        if let Some(band) = r.operating_band() {
            if inner.band.is_some_and(|previous| previous != band) {
                for (t, rt) in config.targets.iter().zip(inner.runtimes.iter_mut()) {
                    if t.messages & CLEAR_BIT != 0 {
                        let bytes = nm::clear(rt.schema, id);
                        send(rt, t.address, &bytes, now);
                    }
                }
            }
            inner.band = Some(band);
        }
        // Decode of the current live job (a played recording is no live job).
        let cursor = inner.cursor.clone();
        let live = r.live_records_after(
            cursor.as_ref().map(|c| &c.0),
            cursor.as_ref().map_or(0, |c| c.1),
        );
        if live.is_none() {
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
                // A record without a period start gives no Decode, and the cursor passes it.
                let Some(decode) = decode_of(record, mode) else {
                    continue;
                };
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
    /// QSO Logged then Logged ADIF of a newly stored contact (DirectLog or SaveContact
    /// outcome saved).
    pub(crate) fn logged(&self, state: &ProfileState, record: &logbook::Record) {
        let mut inner = self.lock();
        let (Some(config), Some(id)) = (inner.config.clone(), inner.name.clone()) else {
            return;
        };
        let now = now_ms(&state.recording);
        let logged = logged_of(record);
        let adif = adif_text(record);
        for (t, rt) in config.targets.iter().zip(inner.runtimes.iter_mut()) {
            if t.messages & QSO_LOGGED_BIT != 0 {
                let bytes = nm::qso_logged(rt.schema, &id, &logged);
                send(rt, t.address, &bytes, now);
            }
            if t.messages & LOGGED_ADIF_BIT != 0 {
                let bytes = nm::logged_adif(rt.schema, &id, &adif);
                send(rt, t.address, &bytes, now);
            }
        }
    }
    /// CL-112-06 one Close under the instance name to each active target that selects
    /// close: one non-blocking send each, no wait.
    pub(crate) fn close_all(&self) {
        let mut inner = self.lock();
        let (Some(config), Some(id)) = (inner.config.clone(), inner.name.clone()) else {
            return;
        };
        let now = wall_ms();
        for (t, rt) in config.targets.iter().zip(inner.runtimes.iter_mut()) {
            if rt.socket.is_some() && t.messages & CLOSE_BIT != 0 {
                let bytes = nm::close(rt.schema, &id);
                send(rt, t.address, &bytes, now);
            }
        }
    }
}
/// CL-112-06 the exit guard (Ctrl+C, Ctrl+Break, console close, logoff, shutdown): the
/// transmit release (WstxTransmit::ExitRelease) first, then Close to the UDP targets.
pub(crate) fn exit(recording: &recording::Recording, release: impl FnOnce()) {
    release();
    if let Some(owner) = recording.udp.get() {
        owner.close_all();
    }
}
/// The one thing read from a target: its Heartbeat raises that target's header schema
/// (MessageClient negotiation, never lowered). Everything else is read and dropped, so a tool's
/// command has no effect and a pending ICMP error of an earlier send does not stay behind.
fn negotiate(inner: &mut Inner) {
    let (Some(config), Some(name)) = (&inner.config, &inner.name) else {
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
                        && h.id == *name
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
