#![forbid(unsafe_code)]
//! WstxStrategy::HearingFeed (#39): the read-only PSK Reporter MQTT subscriber and the
//! bounded "heard by target" / "frequencies the target decodes" model. Its own thread does
//! all network waiting; the station only reads a short-held mutex, and no connection means
//! unknown, never an error for the operator. It sends the MQTT handshake, the two
//! subscriptions and keep-alive pings, nothing else.
use crate::*;
use axum::extract::RawQuery;
use recording_http::{authorize, error, parse, syntax};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::fs;
use std::io::{ErrorKind, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::path::Path;
use std::sync::Condvar;

#[cfg(test)]
#[path = "pskr_tests.rs"]
mod tests;

const FILE: &str = "pskr.json";
const FILE_LIMIT: u64 = 1024;
const HOST: &str = "mqtt.pskreporter.info";
/// The broker's TLS listener; its chain validates against ISRG_ROOTS (checked 2026-11-06).
const TLS_PORT: u16 = 1884;
/// Trust anchors of the broker's Let's Encrypt chain: the self-signed ISRG Root X1 and X2.
/// Compiled in, because webpki-roots is outside deny.toml and the Windows store only holds
/// a root once something asked for it. A broker on another CA shows an error in Settings.
const ISRG_ROOTS: &[u8] = include_bytes!("pskr_isrg_roots.pem");
/// How long a spot still counts, for "hears us" and for the frequencies the target decodes.
/// Reporters upload in batches up to about 5 minutes late, so a spot can only be expected
/// within that delay plus one more upload; an older one no longer describes this path.
pub(crate) const HEARD_WINDOW_S: i64 = 600;
/// One entry per (receiver, band, mode) that heard my call.
const HEARD_MAX: usize = 256;
/// Spots received by the current target.
const DECODED_MAX: usize = 128;
/// The preferred frequencies handed to the slot choice, newest first.
const PREFERRED_MAX: usize = 32;
/// An MQTT packet larger than any spot is a protocol error; this bounds the read buffer.
const PACKET_MAX: usize = 4096;
/// A longer field in a spot is not a spot.
const FIELD_MAX: usize = 16;
/// Settings need the age in minutes; a feed of spots stays inside the Thin link budget.
const SPOT_EVENT_S: i64 = 30;

/// The waits of a session. A test shortens them; the station uses `BROKER`.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Timing {
    /// How long a read waits before the thread looks at the settings again.
    pub poll: Duration,
    /// Connect, TLS handshake and CONNACK, each.
    pub handshake: Duration,
    /// A PINGREQ after this much silence on my side.
    pub ping: Duration,
    /// MQTT keep-alive announced in CONNECT.
    pub keep_alive_s: u16,
    /// The link is dead after this much silence from the broker.
    pub silence: Duration,
    pub backoff_first: Duration,
    pub backoff_max: Duration,
    /// A session this long was healthy: the next failure starts the backoff over.
    pub stable: Duration,
}
impl Timing {
    pub(crate) const BROKER: Timing = Timing {
        poll: Duration::from_millis(250),
        handshake: Duration::from_secs(10),
        ping: Duration::from_secs(45),
        keep_alive_s: 60,
        silence: Duration::from_secs(90),
        backoff_first: Duration::from_secs(5),
        backoff_max: Duration::from_secs(300),
        stable: Duration::from_secs(60),
    };
}

/// Doubling reconnect delay. Every session end takes one, so toggling the setting or a
/// broker that accepts and drops at once cannot make the station hammer a third party.
#[derive(Debug)]
pub(crate) struct Backoff {
    next: Duration,
    first: Duration,
    max: Duration,
}
impl Backoff {
    pub(crate) fn new(timing: &Timing) -> Self {
        Self {
            next: timing.backoff_first,
            first: timing.backoff_first,
            max: timing.backoff_max,
        }
    }
    pub(crate) fn step(&mut self) -> Duration {
        let delay = self.next;
        self.next = (self.next * 2).min(self.max);
        delay
    }
    pub(crate) fn reset(&mut self) {
        self.next = self.first;
    }
}

/// A call usable as one topic segment. Decoded calls reach this, so it must never let an
/// MQTT wildcard or separator through; a call with `/` is skipped, the feed stays unknown
/// for it (the broker documents no form for such a call in a topic).
fn segment(call: &str) -> Option<&str> {
    (!call.is_empty()
        && call.len() <= FIELD_MAX
        && call
            .bytes()
            .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit()))
    .then_some(call)
}
pub(crate) fn sender_filter(call: &str) -> Option<String> {
    segment(call).map(|c| format!("pskr/filter/v2/+/+/{c}/+/#"))
}
pub(crate) fn receiver_filter(call: &str) -> Option<String> {
    segment(call).map(|c| format!("pskr/filter/v2/+/+/+/{c}/#"))
}
/// The MQTT 3.1.1 client id every server must accept: alphanumeric and at most 23 bytes,
/// with the callsign so that the broker's operator can identify the station.
pub(crate) fn client_id(call: &str, boot: &str) -> String {
    let call: String = call
        .chars()
        .filter(char::is_ascii_alphanumeric)
        .take(13)
        .collect();
    let tail: String = boot
        .chars()
        .filter(char::is_ascii_alphanumeric)
        .take(4)
        .collect();
    format!("wstx{call}{tail}")
}

/// One accepted spot (`f`, `md`, `b`, `sc`, `rc` and the transmission time of the payload).
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Spot {
    pub sender: String,
    pub receiver: String,
    pub mode: String,
    pub band: String,
    pub hz: u64,
    pub utc_s: i64,
}
#[derive(Deserialize)]
struct WireSpot {
    f: u64,
    md: String,
    t: i64,
    t_tx: Option<i64>,
    sc: String,
    rc: String,
    b: String,
}
pub(crate) fn parse_spot(payload: &[u8]) -> Option<Spot> {
    let wire: WireSpot = serde_json::from_slice(payload).ok()?;
    let field = |s: &str| (!s.is_empty() && s.len() <= FIELD_MAX).then(|| s.to_ascii_uppercase());
    Some(Spot {
        sender: field(&wire.sc)?,
        receiver: field(&wire.rc)?,
        mode: field(&wire.md)?,
        band: field(&wire.b)?.to_ascii_lowercase(),
        hz: wire.f,
        utc_s: wire.t_tx.unwrap_or(wire.t),
    })
}

/// The model: who heard my call, and what the current target decodes. Pure; its memory is
/// bounded by HEARD_MAX and DECODED_MAX whatever the broker sends.
#[derive(Debug, Default)]
pub(crate) struct Hearing {
    heard: Vec<Spot>,
    decoded: VecDeque<Spot>,
}
impl Hearing {
    pub(crate) fn record(&mut self, my: &str, target: Option<&str>, mut spot: Spot, now_s: i64) {
        if now_s - spot.utc_s > HEARD_WINDOW_S {
            return;
        }
        // A reporter's clock ahead of ours must not stretch the window.
        spot.utc_s = spot.utc_s.min(now_s);
        if spot.sender == my {
            let same = self.heard.iter_mut().find(|h| {
                h.receiver == spot.receiver && h.band == spot.band && h.mode == spot.mode
            });
            match same {
                Some(h) => h.utc_s = h.utc_s.max(spot.utc_s),
                None => {
                    if self.heard.len() >= HEARD_MAX {
                        self.heard.retain(|h| now_s - h.utc_s <= HEARD_WINDOW_S);
                    }
                    if self.heard.len() >= HEARD_MAX
                        && let Some(oldest) =
                            (0..self.heard.len()).min_by_key(|i| self.heard[*i].utc_s)
                    {
                        self.heard.swap_remove(oldest);
                    }
                    self.heard.push(spot);
                }
            }
        } else if target == Some(spot.receiver.as_str()) {
            if self.decoded.len() >= DECODED_MAX {
                self.decoded.pop_front();
            }
            self.decoded.push_back(spot);
        }
    }
    /// A spot of my call received by `target` on this band and mode, not older than the window.
    pub(crate) fn hears_us(&self, target: &str, mode: &str, band: &str, now_s: i64) -> bool {
        self.heard.iter().any(|h| {
            h.receiver == target
                && h.mode == mode
                && h.band == band
                && now_s - h.utc_s <= HEARD_WINDOW_S
        })
    }
    /// Audio offsets (spot frequency minus my dial) of what the current target decoded on
    /// this mode and band, newest first and distinct, inside `range`. A spot for another
    /// band or mode says nothing about this one.
    pub(crate) fn decoded_offsets(
        &self,
        mode: &str,
        band: &str,
        dial_hz: u64,
        range: (u32, u32),
        now_s: i64,
    ) -> Vec<u32> {
        let mut out: Vec<u32> = Vec::new();
        for s in self.decoded.iter().rev() {
            if s.mode != mode || s.band != band || now_s - s.utc_s > HEARD_WINDOW_S {
                continue;
            }
            let offset =
                s.hz.checked_sub(dial_hz)
                    .and_then(|o| u32::try_from(o).ok());
            if let Some(o) = offset.filter(|o| (range.0..=range.1).contains(o))
                && !out.contains(&o)
            {
                out.push(o);
                if out.len() == PREFERRED_MAX {
                    break;
                }
            }
        }
        out
    }
    fn clear_decoded(&mut self) {
        self.decoded.clear();
    }
}

// --- MQTT 3.1.1, the subscribe-only subset; every packet is written from its section in
// the OASIS specification and QoS is always 0, so no state other than the packet id.
fn remaining_length(mut n: usize, out: &mut Vec<u8>) {
    loop {
        let byte = (n % 128) as u8;
        n /= 128;
        out.push(if n > 0 { byte | 0x80 } else { byte });
        if n == 0 {
            return;
        }
    }
}
fn packet(first: u8, body: &[u8]) -> Vec<u8> {
    let mut out = vec![first];
    remaining_length(body.len(), &mut out);
    out.extend_from_slice(body);
    out
}
fn text(body: &mut Vec<u8>, s: &str) {
    let bytes = s.as_bytes();
    let n = u16::try_from(bytes.len()).expect("ids and filters are built short");
    body.extend_from_slice(&n.to_be_bytes());
    body.extend_from_slice(bytes);
}
pub(crate) fn connect_packet(client: &str, keep_alive_s: u16) -> Vec<u8> {
    let mut body = Vec::new();
    text(&mut body, "MQTT");
    body.push(4); // protocol level 3.1.1
    body.push(0x02); // clean session, no will, no user name, no password
    body.extend_from_slice(&keep_alive_s.to_be_bytes());
    text(&mut body, client);
    packet(0x10, &body)
}
pub(crate) fn subscribe_packet(id: u16, filter: &str) -> Vec<u8> {
    let mut body = id.to_be_bytes().to_vec();
    text(&mut body, filter);
    body.push(0); // QoS 0
    packet(0x82, &body)
}
pub(crate) fn unsubscribe_packet(id: u16, filter: &str) -> Vec<u8> {
    let mut body = id.to_be_bytes().to_vec();
    text(&mut body, filter);
    packet(0xa2, &body)
}
const PINGREQ: [u8; 2] = [0xc0, 0];
const DISCONNECT: [u8; 2] = [0xe0, 0];

#[derive(Debug, PartialEq, Eq)]
pub(crate) enum Packet {
    ConnAck(u8),
    Publish(Vec<u8>),
    SubAck(bool),
    UnsubAck,
    PingResp,
}
/// Takes one complete packet off the front of `buffer`. None: more bytes are needed.
pub(crate) fn next_packet(buffer: &mut Vec<u8>) -> Result<Option<Packet>, &'static str> {
    let (mut length, mut header) = (0usize, 1usize);
    loop {
        let Some(&byte) = buffer.get(header) else {
            return Ok(None);
        };
        length += usize::from(byte & 0x7f) << (7 * (header - 1));
        header += 1;
        if byte & 0x80 == 0 {
            break;
        }
        if header > 4 {
            return Err("protocol_error");
        }
    }
    if length > PACKET_MAX {
        return Err("protocol_error");
    }
    if buffer.len() < header + length {
        return Ok(None);
    }
    let first = buffer[0];
    let body: Vec<u8> = buffer.drain(..header + length).skip(header).collect();
    let parsed = match first >> 4 {
        2 if body.len() == 2 => Packet::ConnAck(body[1]),
        // QoS 0 subscriptions never get a higher QoS, and the topic is not trusted: the
        // payload's own sc and rc decide.
        3 if first & 0x06 == 0 && body.len() >= 2 => {
            let topic = usize::from(u16::from_be_bytes([body[0], body[1]]));
            let payload = body.get(2 + topic..).ok_or("protocol_error")?;
            Packet::Publish(payload.to_vec())
        }
        9 if body.len() >= 3 => Packet::SubAck(body[2..].iter().all(|code| *code <= 2)),
        11 if body.len() == 2 => Packet::UnsubAck,
        13 if body.is_empty() => Packet::PingResp,
        _ => return Err("protocol_error"),
    };
    Ok(Some(parsed))
}

/// What a session reads and writes: the TLS stream, or plain TCP to a local test peer.
/// Its read returns WouldBlock or TimedOut after `Timing::poll`.
pub(crate) trait Transport: Read + Write + Send {}
impl<T: Read + Write + Send> Transport for T {}
pub(crate) type Connector = Box<dyn Fn(&Timing) -> Result<Box<dyn Transport>, &'static str> + Send>;

fn tcp(host: &str, port: u16, timing: &Timing) -> Result<TcpStream, &'static str> {
    let addresses = (host, port)
        .to_socket_addrs()
        .map_err(|_| "resolve_failed")?;
    let mut stream = None;
    for address in addresses {
        if let Ok(connected) = TcpStream::connect_timeout(&address, timing.handshake) {
            stream = Some(connected);
            break;
        }
    }
    let stream = stream.ok_or("connect_failed")?;
    stream.set_nodelay(true).map_err(|_| "connect_failed")?;
    stream
        .set_read_timeout(Some(timing.poll))
        .and_then(|()| stream.set_write_timeout(Some(timing.handshake)))
        .map_err(|_| "connect_failed")?;
    Ok(stream)
}
fn root_store(roots: &[u8]) -> Result<rustls::RootCertStore, &'static str> {
    use rustls::pki_types::{CertificateDer, pem::PemObject};
    let mut store = rustls::RootCertStore::empty();
    for root in CertificateDer::pem_slice_iter(roots) {
        let root = root.map_err(|_| "tls_failed")?;
        store.add(root).map_err(|_| "tls_failed")?;
    }
    Ok(store)
}
/// A TLS client trusting only `roots`, with the name checked. The handshake finishes here
/// so that a certificate failure is named as such.
pub(crate) fn tls_connect(
    host: &'static str,
    port: u16,
    roots: &[u8],
    timing: &Timing,
) -> Result<Box<dyn Transport>, &'static str> {
    let mut stream = tcp(host, port, timing)?;
    let config = rustls::ClientConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .map_err(|_| "tls_failed")?
    .with_root_certificates(root_store(roots)?)
    .with_no_client_auth();
    let name = rustls::pki_types::ServerName::try_from(host).map_err(|_| "tls_failed")?;
    let mut connection =
        rustls::ClientConnection::new(Arc::new(config), name).map_err(|_| "tls_failed")?;
    stream
        .set_read_timeout(Some(timing.handshake))
        .map_err(|_| "tls_failed")?;
    while connection.is_handshaking() {
        connection
            .complete_io(&mut stream)
            .map_err(|_| "tls_failed")?;
    }
    stream
        .set_read_timeout(Some(timing.poll))
        .map_err(|_| "tls_failed")?;
    Ok(Box::new(rustls::StreamOwned::new(connection, stream)))
}
/// The connector of the running station. WSTX_PSKR=off opens no connection, so isolated
/// tests of the executable never reach the broker; WSTX_PSKR=tcp:<loopback>:<port> speaks
/// plain MQTT to a local test peer, and nothing else can replace the broker.
pub(crate) fn station_connector(setting: Option<&str>) -> Option<Connector> {
    match setting {
        None => Some(Box::new(|timing: &Timing| {
            tls_connect(HOST, TLS_PORT, ISRG_ROOTS, timing)
        })),
        Some(value) => {
            let address: SocketAddr = value.strip_prefix("tcp:")?.parse().ok()?;
            address.ip().is_loopback().then(|| -> Connector {
                Box::new(move |timing: &Timing| {
                    let host = address.ip().to_string();
                    let stream = tcp(&host, address.port(), timing)?;
                    Ok(Box::new(stream) as Box<dyn Transport>)
                })
            })
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Link {
    Off,
    Connecting,
    Connected,
    Error,
}
struct Inner {
    enabled: bool,
    storage_error: Option<&'static str>,
    my_call: Option<String>,
    target: Option<String>,
    link: Link,
    error: Option<&'static str>,
    last_spot_s: Option<i64>,
    /// When the last spot moved the revision (SPOT_EVENT_S).
    spot_event_s: i64,
    revision: u64,
    hearing: Hearing,
    stopping: bool,
}
struct Shared {
    inner: Mutex<Inner>,
    wake: Condvar,
}
fn utc_s() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}
impl Shared {
    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }
    fn set_link(&self, link: Link, failure: Option<&'static str>) {
        let mut i = self.lock();
        let error = match link {
            Link::Connected | Link::Off => None,
            Link::Connecting => i.error,
            Link::Error => failure,
        };
        if i.link != link || i.error != error {
            i.link = link;
            i.error = error;
            i.revision += 1;
        }
    }
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Record {
    schema_version: u8,
    profile_id: String,
    enabled: bool,
}
/// The station's one feed; dropping it ends its thread.
pub(crate) struct Feed {
    shared: Arc<Shared>,
    directory: PathBuf,
    profile: String,
    boot: String,
    /// Test seam: the dial when the fixture has no CAT actor.
    #[cfg(test)]
    pub(crate) dial: Mutex<Option<u64>>,
}
impl Drop for Feed {
    fn drop(&mut self) {
        self.shared.lock().stopping = true;
        self.shared.wake.notify_all();
    }
}
impl Feed {
    /// The saved setting, on by default (operator decision 2026-11-04, #39). Without a
    /// connector no thread starts: the setting still works, the link stays off.
    pub(crate) fn start(
        directory: &Path,
        profile: &str,
        boot: &str,
        connector: Option<Connector>,
        timing: Timing,
    ) -> Arc<Self> {
        let path = directory.join(FILE);
        let (enabled, storage_error) = match fs::metadata(&path) {
            Err(e) if e.kind() == ErrorKind::NotFound => (true, None),
            Err(_) => (true, Some("storage_unavailable")),
            Ok(_) => match recording::bounded_json::<Record>(&path, FILE_LIMIT) {
                Ok(r) if r.schema_version == 1 && r.profile_id == profile => (r.enabled, None),
                _ => (true, Some("invalid_pskr")),
            },
        };
        let shared = Arc::new(Shared {
            inner: Mutex::new(Inner {
                enabled,
                storage_error,
                my_call: None,
                target: None,
                link: Link::Off,
                error: None,
                last_spot_s: None,
                spot_event_s: 0,
                revision: 0,
                hearing: Hearing::default(),
                stopping: false,
            }),
            wake: Condvar::new(),
        });
        if let Some(connector) = connector {
            let (worker_shared, tail) = (shared.clone(), boot.to_owned());
            // No thread means an always-off feed: nothing depends on this one.
            let _ = std::thread::Builder::new()
                .name("pskr".into())
                .spawn(move || worker(&worker_shared, &connector, timing, &tail));
        }
        Arc::new(Self {
            shared,
            directory: directory.to_path_buf(),
            profile: profile.to_owned(),
            boot: boot.to_owned(),
            #[cfg(test)]
            dial: Mutex::new(None),
        })
    }
    /// Test seam: a payload as the session accepts it.
    #[cfg(test)]
    pub(crate) fn inject(&self, payload: &str) {
        let my_call = self.shared.lock().my_call.clone().unwrap();
        accept(&self.shared, &my_call, payload.as_bytes());
    }
    #[cfg(test)]
    pub(crate) fn switch(&self, enabled: bool) {
        let (profile, boot) = (self.profile.clone(), self.boot.clone());
        self.set_enabled(&profile, &boot, enabled).unwrap();
    }
    /// My call and the current target, from the station step. Changing the target replaces
    /// its subscription and forgets what the previous target decoded.
    pub(crate) fn observe(&self, my_call: Option<&str>, target: Option<&str>) {
        let mut i = self.shared.lock();
        if i.my_call.as_deref() != my_call {
            i.my_call = my_call.map(str::to_owned);
            i.hearing = Hearing::default();
            self.shared.wake.notify_all();
        }
        if i.target.as_deref() != target {
            i.target = target.map(str::to_owned);
            i.hearing.clear_decoded();
        }
    }
    pub(crate) fn revision(&self) -> u64 {
        self.shared.lock().revision
    }
    /// Known to hear us; false means not known, also with the feed off or unreachable.
    pub(crate) fn hears_us(&self, target: &str, mode: &str, band: &str) -> bool {
        self.shared
            .lock()
            .hearing
            .hears_us(target, mode, band, utc_s())
    }
    pub(crate) fn decoded_offsets(
        &self,
        mode: &str,
        band: &str,
        dial_hz: u64,
        range: (u32, u32),
    ) -> Vec<u32> {
        self.shared
            .lock()
            .hearing
            .decoded_offsets(mode, band, dial_hz, range, utc_s())
    }
    pub(crate) fn view(&self) -> Value {
        let i = self.shared.lock();
        let state = match i.link {
            Link::Off => "off",
            Link::Connecting => "connecting",
            Link::Connected => "connected",
            Link::Error => "error",
        };
        json!({"v":1,"profile_id":self.profile,"boot_id":self.boot,"enabled":i.enabled,
            "state":state,"error":i.error,"last_spot_utc_s":i.last_spot_s,
            "storage_error":i.storage_error})
    }
    /// The `pskr.state` event of the current state.
    pub(crate) fn event(&self) -> (u64, String) {
        let revision = self.revision();
        let text = json!({"v":1,"type":"pskr.state","data":self.view()}).to_string();
        (revision, text)
    }
    fn set_enabled(&self, profile: &str, boot: &str, enabled: bool) -> Result<Value, &'static str> {
        if profile != self.profile {
            return Err("wrong_profile");
        }
        if boot != self.boot {
            return Err("state_conflict");
        }
        let record = Record {
            schema_version: 1,
            profile_id: self.profile.clone(),
            enabled,
        };
        let saved = profile::atomic_json(&self.directory, FILE, &record);
        {
            let mut i = self.shared.lock();
            i.storage_error = saved.is_err().then_some("storage_unavailable");
            i.revision += 1;
            if saved.is_ok() && i.enabled != enabled {
                i.enabled = enabled;
                // Off is unknown: nothing the feed said before may still decide.
                i.hearing = Hearing::default();
                i.last_spot_s = None;
                if !enabled {
                    i.link = Link::Off;
                    i.error = None;
                }
            }
        }
        self.shared.wake.notify_all();
        saved.map_err(|_| "storage_unavailable")?;
        Ok(self.view())
    }
}

/// Waits for the setting and the backoff, runs one session, and takes the next delay.
fn worker(shared: &Shared, connector: &Connector, timing: Timing, boot: &str) {
    let mut backoff = Backoff::new(&timing);
    let mut not_before = Instant::now();
    loop {
        let call = {
            let mut i = shared.lock();
            loop {
                if i.stopping {
                    return;
                }
                let due = not_before.saturating_duration_since(Instant::now());
                if i.enabled
                    && due.is_zero()
                    && let Some(call) = i.my_call.clone()
                {
                    break call;
                }
                // A notify ends the wait early; no change of a setting skips the backoff.
                let wait = if i.enabled && !due.is_zero() {
                    due
                } else {
                    Duration::from_secs(3600)
                };
                i = shared
                    .wake
                    .wait_timeout(i, wait)
                    .unwrap_or_else(|e| e.into_inner())
                    .0;
            }
        };
        shared.set_link(Link::Connecting, None);
        let started = Instant::now();
        let end = connector(&timing).and_then(|mut stream| {
            let client = client_id(&call, boot);
            session(shared, stream.as_mut(), &client, &call, &timing)
        });
        if started.elapsed() >= timing.stable {
            backoff.reset();
        }
        not_before = Instant::now() + backoff.step();
        match end {
            Ok(()) => {
                let enabled = shared.lock().enabled;
                shared.set_link(if enabled { Link::Connecting } else { Link::Off }, None);
            }
            Err(code) => {
                let enabled = shared.lock().enabled;
                shared.set_link(if enabled { Link::Error } else { Link::Off }, Some(code));
            }
        }
    }
}

fn send(stream: &mut dyn Transport, bytes: &[u8]) -> Result<(), &'static str> {
    stream
        .write_all(bytes)
        .and_then(|()| stream.flush())
        .map_err(|_| "connection_lost")
}
/// Reads what arrived within one poll into `buffer`; Ok(false) when nothing did.
fn fill(stream: &mut dyn Transport, buffer: &mut Vec<u8>) -> Result<bool, &'static str> {
    let mut chunk = [0u8; 1024];
    match stream.read(&mut chunk) {
        Ok(0) => Err("connection_closed"),
        Ok(n) => {
            buffer.extend_from_slice(&chunk[..n]);
            Ok(true)
        }
        Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => Ok(false),
        Err(_) => Err("connection_lost"),
    }
}
struct PacketIds(u16);
impl PacketIds {
    fn next(&mut self) -> u16 {
        self.0 = self.0.checked_add(1).unwrap_or(1);
        self.0
    }
}
/// One connection. Ok: ended on purpose (setting off, my call changed, feed dropped).
fn session(
    shared: &Shared,
    stream: &mut dyn Transport,
    client: &str,
    my_call: &str,
    timing: &Timing,
) -> Result<(), &'static str> {
    let mut buffer = Vec::new();
    send(stream, &connect_packet(client, timing.keep_alive_s))?;
    let asked = Instant::now();
    loop {
        match next_packet(&mut buffer)? {
            Some(Packet::ConnAck(0)) => break,
            Some(Packet::ConnAck(_)) => return Err("connection_refused"),
            Some(_) => return Err("protocol_error"),
            None => {}
        }
        if asked.elapsed() >= timing.handshake {
            return Err("connection_timeout");
        }
        fill(stream, &mut buffer)?;
    }
    shared.set_link(Link::Connected, None);
    let mut ids = PacketIds(0);
    if let Some(filter) = sender_filter(my_call) {
        send(stream, &subscribe_packet(ids.next(), &filter))?;
    }
    let mut target_filter: Option<String> = None;
    let (mut sent, mut heard) = (Instant::now(), Instant::now());
    loop {
        let (stop, wanted) = {
            let i = shared.lock();
            (
                i.stopping || !i.enabled || i.my_call.as_deref() != Some(my_call),
                i.target.as_deref().and_then(receiver_filter),
            )
        };
        if stop {
            let _ = send(stream, &DISCONNECT);
            return Ok(());
        }
        if wanted != target_filter {
            if let Some(old) = &target_filter {
                send(stream, &unsubscribe_packet(ids.next(), old))?;
            }
            if let Some(new) = &wanted {
                send(stream, &subscribe_packet(ids.next(), new))?;
            }
            target_filter = wanted;
            sent = Instant::now();
        }
        if sent.elapsed() >= timing.ping {
            send(stream, &PINGREQ)?;
            sent = Instant::now();
        }
        while let Some(packet) = next_packet(&mut buffer)? {
            heard = Instant::now();
            match packet {
                Packet::Publish(payload) => accept(shared, my_call, &payload),
                Packet::SubAck(false) => return Err("subscribe_refused"),
                Packet::SubAck(true) | Packet::UnsubAck | Packet::PingResp => {}
                Packet::ConnAck(_) => return Err("protocol_error"),
            }
        }
        if heard.elapsed() >= timing.silence {
            return Err("connection_timeout");
        }
        fill(stream, &mut buffer)?;
    }
}
/// The payload decides what a spot is: a spot neither from my call nor to the current
/// target is dropped whatever topic it came on.
fn accept(shared: &Shared, my_call: &str, payload: &[u8]) {
    let Some(spot) = parse_spot(payload) else {
        return;
    };
    let now = utc_s();
    let mut i = shared.lock();
    if spot.sender != my_call && i.target.as_deref() != Some(spot.receiver.as_str()) {
        return;
    }
    let time = spot.utc_s.min(now);
    let target = i.target.clone();
    i.hearing.record(my_call, target.as_deref(), spot, now);
    if i.last_spot_s.is_none_or(|last| last < time) {
        let first = i.last_spot_s.is_none();
        i.last_spot_s = Some(time);
        if first || now - i.spot_event_s >= SPOT_EVENT_S {
            i.spot_event_s = now;
            i.revision += 1;
        }
    }
}

/// What the feed knows of `target` on the station's band and `mode`: known to hear us, and
/// the audio offsets it decodes inside the free slot range. Unknown is (false, none): the
/// feed off or absent, the band or dial unknown, no target.
pub(crate) fn hearing_of(
    r: &recording::Recording,
    target: Option<&str>,
    mode: decoder::Mode,
) -> (bool, Vec<u32>) {
    let (Some(feed), Some(target), Some(band)) = (r.pskr.get(), target, strategy::station_band(r))
    else {
        return (false, Vec::new());
    };
    let name = match mode {
        decoder::Mode::Ft8 => "FT8",
        decoder::Mode::Ft4 => "FT4",
    };
    #[cfg(test)]
    let dial = (*feed.dial.lock().unwrap()).or_else(|| contact_http::confirmed_dial(r));
    #[cfg(not(test))]
    let dial = contact_http::confirmed_dial(r);
    let offsets = dial.map_or_else(Vec::new, |dial| {
        feed.decoded_offsets(name, band, dial, freeslot::band(mode))
    });
    (feed.hears_us(target, name, band), offsets)
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Edit {
    v: u64,
    profile_id: String,
    boot_id: String,
    enabled: bool,
}
fn feed_of(r: &recording::Recording) -> Result<Arc<Feed>, &'static str> {
    r.pskr.get().cloned().ok_or("not_found")
}
/// GET /pskr: the one snapshot a browser reads on (re)connect; pskr.state pushes the rest.
pub async fn snapshot(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, false).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    if let Err(e) = selection_http::empty(query, body) {
        return error(e);
    }
    match feed_of(&r) {
        Ok(feed) => Json(feed.view()).into_response(),
        Err(e) => error(e),
    }
}
/// POST /pskr: the Settings switch.
pub async fn update(
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
    let b: Edit = match parse(&headers, body) {
        Ok(b) => b,
        Err(e) => return error(e),
    };
    if let Err(e) = syntax(b.v, &b.profile_id, &b.boot_id, 0) {
        return error(e);
    }
    let feed = match feed_of(&r) {
        Ok(feed) => feed,
        Err(e) => return error(e),
    };
    match tokio::task::spawn_blocking(move || {
        feed.set_enabled(&b.profile_id, &b.boot_id, b.enabled)
    })
    .await
    {
        Ok(Ok(v)) => Json(v).into_response(),
        Ok(Err(e)) => error(e),
        Err(_) => error("storage_unavailable"),
    }
}
