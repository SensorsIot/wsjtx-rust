#![forbid(unsafe_code)]
//! FR-023 per-station native session (WstxArchitecture::NativeFlexBoundary). One
//! station process is one GUI-class API client; the radio's client-scoped resource
//! ownership is the arbitration authority between stations. This session only ever
//! changes the one slice and stream it created and confirmed under its own current
//! client handle; transient indices, handles and stream IDs are never persisted, and
//! neither is a radio identity: discovery finds whichever radio is available (#22).
use super::wire::{self, Line, Status};
use crate::audio::{
    AudioState, AudioStatus, CaptureDiagnostics, DATA_DISCONTINUITY, Encoding, LiveSource,
    NativeFormat, PacketQueue, TIMESTAMP_ERROR,
};
use crate::source::{SampleSource, SourceDescriptor, SourceError, SourcePoll, SourceTiming};
use std::{
    collections::HashMap,
    io::{ErrorKind, Read, Write},
    net::{IpAddr, SocketAddr, TcpStream, UdpSocket},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, Ordering},
        mpsc::{Receiver, SyncSender, TryRecvError, sync_channel},
    },
    thread::JoinHandle,
    time::{Duration, Instant},
};

/// Persisted intent of one native profile. No runtime handle belongs here.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Intent {
    pub client_id: String,
    pub rx_antenna: String,
    /// Where to connect when discovery cannot reach the radio (a routed path): a locator,
    /// not an identity. Without it, discovery finds the next available radio.
    pub radio_address: Option<SocketAddr>,
}
impl Intent {
    pub fn valid(&self) -> bool {
        let antenna = self.rx_antenna.as_bytes();
        (1..=16).contains(&antenna.len())
            && antenna
                .iter()
                .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit() || *b == b'_')
            && self.client_id.len() == 36
            && self
                .client_id
                .bytes()
                .all(|b| b.is_ascii_hexdigit() || b == b'-')
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Config {
    /// Where discovery announcements are received (default 0.0.0.0:4992).
    pub discovery: SocketAddr,
    /// The radio's UDP ports the keep-alive of a routed path goes to.
    pub register_ports: [u16; 2],
}
impl Default for Config {
    fn default() -> Self {
        Self {
            discovery: SocketAddr::from(([0, 0, 0, 0], wire::DISCOVERY_PORT)),
            register_ports: wire::REGISTER_PORTS,
        }
    }
}

const STEP: Duration = Duration::from_secs(5);
const DISCOVERY_WAIT: Duration = Duration::from_secs(3);
const BACKOFF_MAX_MS: u64 = 4000;
const MAX_TRACKED: usize = 64;
/// A real path reorders about one packet in 300 by one or two places and truly loses far fewer
/// (2026-11-06); 5 packets (27 ms) of waiting tells the two apart.
const REORDER_DEPTH: u8 = 5;
const REGISTER_EVERY: Duration = Duration::from_secs(5);
const UNKNOWN_GAP_100NS: u64 = 2_000_000;
const DAX_RATE: u32 = 24_000;
/// 10 ms at 48 kHz.
const GROUP_FRAMES: usize = 480;
/// Reply codes the pinned API documents for missing receiver/license/resources.
const CAPACITY_CODES: [u32; 3] = [0x5000_0001, 0x5000_0003, 0x5000_001D];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    Unauthorized,
    Discovering,
    Connecting,
    Ready,
    Unavailable,
    Conflict,
    Stopped,
}
impl State {
    pub fn name(self) -> &'static str {
        match self {
            Self::Unauthorized => "unauthorized",
            Self::Discovering => "discovering",
            Self::Connecting => "connecting",
            Self::Ready => "ready",
            Self::Unavailable => "unavailable",
            Self::Conflict => "conflict",
            Self::Stopped => "stopped",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    Unauthorized,
    DiscoveryUnavailable,
    RadioNotFound,
    IncompatibleApi,
    CapacityClients,
    CapacitySlices,
    CapacityDax,
    ClientIdentityInUse,
    OwnershipAmbiguous,
    SliceOwnership,
    DaxChannelConflict,
    AntennaUnavailable,
    RadioRefused,
    TransportLost,
    ProtocolError,
    Timeout,
    ResourceLost,
    InvalidRequest,
    NotReady,
    Busy,
    Cancelled,
    Stopped,
}
impl Error {
    pub fn code(self) -> &'static str {
        match self {
            Self::Unauthorized => "unauthorized",
            Self::DiscoveryUnavailable => "discovery_unavailable",
            Self::RadioNotFound => "radio_not_found",
            Self::IncompatibleApi => "incompatible_api",
            Self::CapacityClients => "capacity_clients",
            Self::CapacitySlices => "capacity_slices",
            Self::CapacityDax => "capacity_dax",
            Self::ClientIdentityInUse => "client_identity_in_use",
            Self::OwnershipAmbiguous => "ownership_ambiguous",
            Self::SliceOwnership => "slice_ownership",
            Self::DaxChannelConflict => "dax_channel_conflict",
            Self::AntennaUnavailable => "antenna_unavailable",
            Self::RadioRefused => "radio_refused",
            Self::TransportLost => "transport_lost",
            Self::ProtocolError => "protocol_error",
            Self::Timeout => "timeout",
            Self::ResourceLost => "resource_lost",
            Self::InvalidRequest => "invalid_request",
            Self::NotReady => "radio_unavailable",
            Self::Busy => "busy",
            Self::Cancelled => "cancelled",
            Self::Stopped => "stopped",
        }
    }
    /// The closed error set of a failed band selection (OperatingReceive S2).
    pub fn selection_code(self) -> &'static str {
        match self {
            Self::Timeout => "radio_timeout",
            Self::RadioRefused => "radio_rejected",
            Self::Cancelled => "cancelled",
            _ => "radio_unavailable",
        }
    }
    fn state(self) -> State {
        match self {
            Self::ClientIdentityInUse
            | Self::OwnershipAmbiguous
            | Self::SliceOwnership
            | Self::DaxChannelConflict => State::Conflict,
            _ => State::Unavailable,
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct RadioFacts {
    /// Shown, never saved or compared: the profile holds no radio identity (#22).
    pub serial: String,
    pub model: Option<String>,
    pub firmware: Option<String>,
    pub protocol: Option<String>,
    pub address: String,
}
#[derive(Clone, Debug, Default, PartialEq)]
pub struct SliceFacts {
    pub index: u32,
    pub letter: Option<String>,
    pub frequency_hz: Option<u64>,
    pub mode: Option<String>,
    pub rx_antenna: Option<String>,
    pub dax_channel: Option<u8>,
    pub stream_id: Option<u32>,
    /// When this session last saw a status for the slice.
    pub observed_at: Option<Instant>,
}
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Counters {
    pub accepted: u64,
    pub foreign: u64,
    pub invalid: u64,
    pub lost: u64,
    /// Arrived after its turn was given up (and counted lost), or twice; dropped.
    pub late: u64,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Snapshot {
    pub state: State,
    pub error: Option<Error>,
    /// Last nonzero radio reply code behind a refusal, for diagnosis only.
    pub radio_code: Option<u32>,
    /// Counts reached sessions; a new number means every older handle is void.
    pub session: u64,
    pub radio: Option<RadioFacts>,
    pub slice: Option<SliceFacts>,
    pub counters: Counters,
    /// Peak |channel 0| of the last accepted own packet (route diagnosis).
    pub last_peak: Option<f32>,
    /// The last own packet's VITA timestamp kind and this host's clock minus that timestamp:
    /// a measurement of whether the radio's time could serve, not used for timing.
    pub vita_tsi: Option<u8>,
    pub vita_offset_ms: Option<i64>,
    /// Spacing of own packets against their duration, as read by this session (its read
    /// loop waits up to 10 ms, which sets the floor): smoothed and largest.
    pub jitter_mean_ms: Option<f64>,
    pub jitter_max_ms: Option<f64>,
    pub retry_after_ms: Option<u64>,
}

struct Sink {
    attachment: u64,
    queue: Arc<PacketQueue>,
    next_frame: u64,
    /// The receive job outlives a lost session: the next session's first packet marks
    /// the gap, which opens a new source epoch.
    session_lost: bool,
    last_arrival: Option<u64>,
    /// DAX packets are grouped to the packet rate of an audio device, because the shared
    /// queue holds 64 packets: 128-frame packets would fill it in 170 ms.
    pending: Vec<u8>,
    pending_frames: usize,
    /// (first frame, its time, flags) of the group.
    pending_first: (u64, u64, u32),
}
impl Sink {
    fn flush(&mut self) {
        if self.pending_frames > 0 {
            let (frame, time, flags) = self.pending_first;
            // A full queue records its own loss; the frame counter still advances.
            let _ = self
                .queue
                .push(&self.pending, self.pending_frames, frame, time, flags);
            self.pending.clear();
            self.pending_frames = 0;
        }
    }
}
struct Shared {
    snapshot: Mutex<Snapshot>,
    sink: Mutex<Option<Sink>>,
    attachments: Mutex<u64>,
    shutdown: AtomicBool,
    /// A current browser grant exists (CL-022-03): nothing reaches a radio without one.
    allowed: AtomicBool,
    /// The last frequency the radio confirmed for the selection (0: none yet). A new
    /// session's new slice goes back there, because the selection still names it.
    tuned_hz: AtomicU64,
    /// Counts changes of what is pushed to the client; packet counters are not pushed.
    revision: AtomicU64,
}
impl Shared {
    fn update(&self, change: impl FnOnce(&mut Snapshot)) {
        if let Ok(mut s) = self.snapshot.lock() {
            let before = Pushed::of(&s);
            change(&mut s);
            if Pushed::of(&s) != before {
                self.revision.fetch_add(1, Ordering::AcqRel);
            }
        }
    }
    fn update_vita(&self, tsi: u8, offset: Option<i64>, spacing_error_ms: Option<f64>) {
        if let Ok(mut s) = self.snapshot.lock() {
            s.vita_tsi = Some(tsi);
            s.vita_offset_ms = offset;
            if let Some(error) = spacing_error_ms.map(f64::abs) {
                let mean = s.jitter_mean_ms.unwrap_or(error);
                s.jitter_mean_ms = Some(mean + (error - mean) / 16.0);
                s.jitter_max_ms = Some(s.jitter_max_ms.unwrap_or(0.0).max(error));
            }
        }
    }
    /// Packet rate: the counters and the peak only, never a pushed change.
    fn count(&self, change: impl FnOnce(&mut Counters, &mut Option<f32>)) {
        if let Ok(mut s) = self.snapshot.lock() {
            let s = &mut *s;
            change(&mut s.counters, &mut s.last_peak);
        }
    }
    fn session_lost(&self) {
        if let Ok(mut sink) = self.sink.lock()
            && let Some(sink) = sink.as_mut()
        {
            sink.session_lost = true;
        }
    }
    fn allowed(&self) -> bool {
        self.allowed.load(Ordering::Acquire)
    }
    fn stopping(&self) -> bool {
        self.shutdown.load(Ordering::Acquire)
    }
    fn fail_sink(&self) {
        if let Ok(mut sink) = self.sink.lock()
            && let Some(sink) = sink.take()
        {
            sink.queue.fail(SourceError::Unavailable);
        }
    }
}

/// A session became ready: a new session number, and the packet counters, the peak, the VITA
/// time and the jitter start over, since GET /native-flex reports them per session.
fn become_ready(s: &mut Snapshot, slice: Option<SliceFacts>) {
    s.state = State::Ready;
    s.error = None;
    s.session += 1;
    s.slice = slice;
    s.counters = Counters::default();
    s.last_peak = None;
    s.vita_tsi = None;
    s.vita_offset_ms = None;
    s.jitter_mean_ms = None;
    s.jitter_max_ms = None;
}

struct TuneRequest {
    frequency_hz: u64,
    deadline: Instant,
    cancelled: Arc<AtomicBool>,
    reply: SyncSender<Result<u64, Error>>,
}

#[derive(PartialEq)]
struct Pushed {
    state: State,
    error: Option<Error>,
    radio_code: Option<u32>,
    session: u64,
    radio: Option<RadioFacts>,
    slice: Option<SliceFacts>,
    retry_after_ms: Option<u64>,
}
impl Pushed {
    fn of(s: &Snapshot) -> Self {
        Self {
            state: s.state,
            error: s.error,
            radio_code: s.radio_code,
            session: s.session,
            radio: s.radio.clone(),
            // When a status arrived is not a change of what it says.
            slice: s.slice.clone().map(|slice| SliceFacts {
                observed_at: None,
                ..slice
            }),
            retry_after_ms: s.retry_after_ms,
        }
    }
}

pub struct Session {
    shared: Arc<Shared>,
    tunes: SyncSender<TuneRequest>,
    thread: Mutex<Option<JoinHandle<()>>>,
}
impl Session {
    pub fn start(intent: Intent, config: Config) -> std::io::Result<Arc<Self>> {
        if !intent.valid() {
            return Err(std::io::Error::other("invalid native intent"));
        }
        let shared = Arc::new(Shared {
            snapshot: Mutex::new(Snapshot {
                state: State::Unauthorized,
                error: None,
                radio_code: None,
                session: 0,
                radio: None,
                slice: None,
                counters: Counters::default(),
                last_peak: None,
                vita_tsi: None,
                vita_offset_ms: None,
                jitter_mean_ms: None,
                jitter_max_ms: None,
                retry_after_ms: None,
            }),
            sink: Mutex::new(None),
            attachments: Mutex::new(0),
            shutdown: AtomicBool::new(false),
            allowed: AtomicBool::new(false),
            tuned_hz: AtomicU64::new(0),
            revision: AtomicU64::new(1),
        });
        let (tunes, requests) = sync_channel(1);
        let worker = shared.clone();
        let thread = std::thread::Builder::new()
            .name("native-flex".into())
            .spawn(move || run(&worker, &intent, config, &requests))?;
        Ok(Arc::new(Self {
            shared,
            tunes,
            thread: Mutex::new(Some(thread)),
        }))
    }
    /// A session without a radio thread whose snapshot the caller sets: the double for tests
    /// of the station's parts that read the session (it never reaches a radio).
    #[doc(hidden)]
    pub fn double() -> Arc<Self> {
        let (tunes, _) = sync_channel(1);
        Arc::new(Self {
            shared: Arc::new(Shared {
                snapshot: Mutex::new(Snapshot {
                    state: State::Unauthorized,
                    error: None,
                    radio_code: None,
                    session: 0,
                    radio: None,
                    slice: None,
                    counters: Counters::default(),
                    last_peak: None,
                    vita_tsi: None,
                    vita_offset_ms: None,
                    jitter_mean_ms: None,
                    jitter_max_ms: None,
                    retry_after_ms: None,
                }),
                sink: Mutex::new(None),
                attachments: Mutex::new(0),
                shutdown: AtomicBool::new(false),
                allowed: AtomicBool::new(false),
                tuned_hz: AtomicU64::new(0),
                revision: AtomicU64::new(1),
            }),
            tunes,
            thread: Mutex::new(None),
        })
    }
    /// Sets the snapshot of a `double`.
    #[doc(hidden)]
    pub fn double_set(&self, change: impl FnOnce(&mut Snapshot)) {
        self.shared.update(change);
    }
    pub fn snapshot(&self) -> Snapshot {
        self.shared
            .snapshot
            .lock()
            .map(|s| s.clone())
            .unwrap_or_else(|p| p.into_inner().clone())
    }
    pub fn ready(&self) -> bool {
        self.snapshot().state == State::Ready
    }
    /// Whether the profile holds a current grant; the session opens or closes accordingly.
    pub fn set_allowed(&self, allowed: bool) {
        self.shared.allowed.store(allowed, Ordering::Release);
    }
    /// The revision of the pushed state; it starts at 1, so a peer's first event is its
    /// snapshot.
    pub fn revision(&self) -> u64 {
        self.shared.revision.load(Ordering::Acquire)
    }
    /// Tunes this station's own slice and returns the frequency the radio confirmed.
    pub fn tune(
        &self,
        frequency_hz: u64,
        deadline: Instant,
        cancelled: &Arc<AtomicBool>,
    ) -> Result<u64, Error> {
        if !(30_000..=74_800_000).contains(&frequency_hz) {
            return Err(Error::InvalidRequest);
        }
        if !self.ready() {
            return Err(Error::NotReady);
        }
        let (reply, answer) = sync_channel(1);
        self.tunes
            .try_send(TuneRequest {
                frequency_hz,
                deadline,
                cancelled: cancelled.clone(),
                reply,
            })
            .map_err(|_| Error::Busy)?;
        // The session answers every admitted request, at the latest at its deadline.
        answer
            .recv_timeout(deadline.saturating_duration_since(Instant::now()) + STEP)
            .unwrap_or(Err(Error::Timeout))
    }
    fn attach(&self, queue: Arc<PacketQueue>) -> Result<u64, Error> {
        let mut sink = self.shared.sink.lock().map_err(|_| Error::NotReady)?;
        if !self.ready() {
            return Err(Error::NotReady);
        }
        if sink.is_some() {
            return Err(Error::Busy);
        }
        let mut counter = self
            .shared
            .attachments
            .lock()
            .map_err(|_| Error::NotReady)?;
        *counter += 1;
        *sink = Some(Sink {
            attachment: *counter,
            queue,
            next_frame: 0,
            session_lost: false,
            last_arrival: None,
            pending: Vec::new(),
            pending_frames: 0,
            pending_first: (0, 0, 0),
        });
        Ok(*counter)
    }
    fn detach(&self, attachment: u64) {
        if let Ok(mut sink) = self.shared.sink.lock()
            && sink.as_ref().is_some_and(|s| s.attachment == attachment)
        {
            *sink = None;
        }
    }
    pub fn stop(&self) {
        self.shared.shutdown.store(true, Ordering::Release);
        let thread = self.thread.lock().ok().and_then(|mut t| t.take());
        if let Some(thread) = thread {
            let _ = thread.join();
        }
    }
}
impl Drop for Session {
    fn drop(&mut self) {
        self.stop();
    }
}

fn run(shared: &Shared, intent: &Intent, config: Config, tunes: &Receiver<TuneRequest>) {
    let mut backoff = 1000;
    while !shared.stopping() {
        if !shared.allowed() {
            shared.update(|s| {
                s.state = State::Unauthorized;
                s.error = None;
                s.slice = None;
                s.retry_after_ms = None;
            });
            std::thread::sleep(Duration::from_millis(100));
            continue;
        }
        let mut reached = false;
        let result = attempt(shared, intent, config, tunes, &mut reached);
        shared.session_lost();
        if shared.stopping() {
            break;
        }
        let error = match result {
            Ok(()) => break,
            Err(Error::Unauthorized) => continue,
            Err(error) => error,
        };
        if reached {
            backoff = 1000;
        }
        shared.update(|s| {
            s.state = error.state();
            s.error = Some(error);
            s.slice = None;
            s.retry_after_ms = Some(backoff);
        });
        let until = Instant::now() + Duration::from_millis(backoff);
        while Instant::now() < until && !shared.stopping() {
            if let Ok(request) = tunes.try_recv() {
                let _ = request.reply.try_send(Err(Error::NotReady));
            }
            std::thread::sleep(Duration::from_millis(20));
        }
        backoff = (backoff * 2).min(BACKOFF_MAX_MS);
    }
    shared.fail_sink();
    shared.update(|s| {
        s.state = State::Stopped;
        s.slice = None;
        s.retry_after_ms = None;
    });
}

/// Several station processes listen for the same announcements on UDP 4992, so the
/// port is bound with address reuse. Discovery only listens; it sends nothing.
fn bind_shared(address: SocketAddr) -> std::io::Result<UdpSocket> {
    use socket2::{Domain, Protocol, Socket, Type};
    let socket = Socket::new(
        Domain::for_address(address),
        Type::DGRAM,
        Some(Protocol::UDP),
    )?;
    socket.set_reuse_address(true)?;
    socket.bind(&address.into())?;
    Ok(socket.into())
}

/// The own receive port. A generous buffer rides out a scheduling stall without packet loss.
fn bind_audio() -> std::io::Result<UdpSocket> {
    use socket2::{Domain, Protocol, Socket, Type};
    let socket = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    let _ = socket.set_recv_buffer_size(1 << 20);
    socket.bind(&SocketAddr::from(([0, 0, 0, 0], 0)).into())?;
    socket.set_nonblocking(true)?;
    Ok(socket.into())
}

/// The first announced radio with a free GUI client: the next available one (#22).
fn discover(shared: &Shared, config: Config) -> Result<(wire::Discovery, IpAddr), Error> {
    let socket = bind_shared(config.discovery).map_err(|_| Error::DiscoveryUnavailable)?;
    socket
        .set_read_timeout(Some(Duration::from_millis(100)))
        .map_err(|_| Error::DiscoveryUnavailable)?;
    let deadline = Instant::now() + DISCOVERY_WAIT;
    let mut buffer = vec![0; wire::MAX_DATAGRAM + 1];
    let mut full = false;
    while Instant::now() < deadline {
        if shared.stopping() {
            return Err(Error::Stopped);
        }
        let Ok((size, from)) = socket.recv_from(&mut buffer) else {
            continue;
        };
        let Ok(found) = wire::parse_discovery(&buffer[..size]) else {
            continue;
        };
        // A radio announcing no free client slot is a capacity fact: no connection is made.
        if found.available_clients == Some(0) {
            full = true;
            continue;
        }
        let address = found.ip.map(IpAddr::V4).unwrap_or(from.ip());
        return Ok((found, address));
    }
    Err(if full {
        Error::CapacityClients
    } else {
        Error::RadioNotFound
    })
}

fn attempt(
    shared: &Shared,
    intent: &Intent,
    config: Config,
    tunes: &Receiver<TuneRequest>,
    reached: &mut bool,
) -> Result<(), Error> {
    shared.update(|s| {
        s.state = State::Discovering;
        s.error = None;
        s.radio_code = None;
        s.retry_after_ms = None;
    });
    // A configured address skips discovery: nothing listens on the LAN then.
    let (found, target) = match intent.radio_address {
        Some(target) => (wire::Discovery::default(), target),
        None => {
            let (found, address) = discover(shared, config)?;
            let port = found.port.unwrap_or(wire::CONTROL_PORT);
            (found, SocketAddr::new(address, port))
        }
    };
    let address = target.ip();
    if !shared.allowed() {
        return Err(Error::Unauthorized);
    }
    let mut radio = RadioFacts {
        serial: found.serial.clone(),
        model: found.model.clone(),
        firmware: found.firmware.clone(),
        protocol: None,
        address: address.to_string(),
    };
    shared.update(|s| {
        s.state = State::Connecting;
        s.radio = Some(radio.clone());
    });
    let tcp = TcpStream::connect_timeout(&target, STEP).map_err(|_| Error::TransportLost)?;
    tcp.set_read_timeout(Some(Duration::from_millis(10)))
        .map_err(|_| Error::TransportLost)?;
    let _ = tcp.set_nodelay(true);
    let mut conn = Conn::new(shared, tcp, address);
    let deadline = Instant::now() + STEP;
    while conn.version.is_none() || conn.own.is_none() {
        if Instant::now() >= deadline {
            return Err(Error::Timeout);
        }
        conn.pump()?;
        // Refuse an unadmitted API before sending any command.
        if conn.version.is_some_and(|v| v != wire::SUPPORTED_PROTOCOL) {
            radio.protocol = conn.version.map(|v| v.to_string());
            shared.update(|s| s.radio = Some(radio.clone()));
            return Err(Error::IncompatibleApi);
        }
    }
    radio.protocol = conn.version.map(|v| v.to_string());
    // No announcement was heard on a routed path: the radio states its own facts.
    if intent.radio_address.is_some()
        && let Ok((0, reply)) = conn.request("info")
    {
        let info = wire::parse_info(&reply);
        radio.serial = info.serial;
        radio.model = info.model;
        radio.firmware = info.firmware;
    }
    shared.update(|s| s.radio = Some(radio.clone()));
    conn.expect_ok("sub client all")?;
    // Replies come in order, so the next reply also proves the client list has arrived,
    // whichever way round the radio sends a subscription's reply and its statuses.
    conn.expect_ok("client start_persistence off")?;
    let own = conn.own.ok_or(Error::ProtocolError)?;
    // The saved client identity already connected elsewhere is occupied, never taken over:
    // registering a duplicate identity could disconnect that other session.
    if conn.view.clients.iter().any(|(handle, c)| {
        *handle != own
            && c.client_id
                .as_deref()
                .is_some_and(|id| id.eq_ignore_ascii_case(&intent.client_id))
    }) {
        return Err(Error::ClientIdentityInUse);
    }
    conn.expect_ok(&format!("client gui {}", intent.client_id))?;
    conn.expect_ok("sub slice all")?;
    conn.expect_ok("sub dax all")?;
    // A fresh handle owns nothing. Anything already attributed to it cannot be
    // proven to be this station's resource, so it is reported and left untouched.
    if conn
        .view
        .slices
        .values()
        .any(|s| s.in_use && s.client_handle == Some(own))
    {
        return Err(Error::OwnershipAmbiguous);
    }
    let udp = bind_audio().map_err(|_| Error::TransportLost)?;
    let port = udp.local_addr().map_err(|_| Error::TransportLost)?.port();
    conn.udp = Some(udp);
    // The radio takes the address from this connection, so a NAT rewriting it stays right;
    // only the port is ever told.
    conn.expect_ok(&format!("client udpport {port}"))?;
    if intent.radio_address.is_some() {
        conn.register = Some((
            config.register_ports.map(|p| SocketAddr::new(address, p)),
            format!("client udp_register handle=0x{own:08X}"),
        ));
        conn.register_keepalive();
    }

    let (code, message) = conn.request(&format!(
        "slice create rxant={} mode=DIGU",
        intent.rx_antenna
    ))?;
    if code != 0 {
        conn.refused(code);
        return Err(if CAPACITY_CODES.contains(&code) {
            Error::CapacitySlices
        } else {
            Error::RadioRefused
        });
    }
    let index: u32 = message
        .split(' ')
        .next()
        .and_then(|s| s.parse().ok())
        .filter(|i| (*i as usize) < MAX_TRACKED)
        .ok_or(Error::ProtocolError)?;
    let slice = conn.wait(Instant::now() + STEP, |v| {
        v.slices
            .get(&index)
            .filter(|s| s.in_use && s.client_handle.is_some())
            .cloned()
    })?;
    if slice.client_handle != Some(own) {
        return Err(Error::SliceOwnership);
    }
    conn.slice = Some(index);
    if slice.rx_antenna.as_deref() != Some(intent.rx_antenna.as_str()) {
        conn.release_own_slice();
        return Err(Error::AntennaUnavailable);
    }
    // DAX channels are chosen free across every visible slice, whatever its owner.
    let used: Vec<u8> = conn.view.slices.values().filter_map(|s| s.dax).collect();
    let Some(channel) = (1..=8u8).find(|c| !used.contains(c)) else {
        conn.release_own_slice();
        return Err(Error::CapacityDax);
    };
    // Read first: a slice already on the channel gets no write.
    if slice.dax != Some(channel) {
        conn.expect_ok(&format!("slice set {index} dax={channel}"))?;
        conn.wait(Instant::now() + STEP, |v| {
            v.slices
                .get(&index)
                .filter(|s| s.dax == Some(channel))
                .map(|_| ())
        })?;
    }
    let (code, message) =
        conn.request(&format!("stream create type=dax_rx dax_channel={channel}"))?;
    if code != 0 {
        conn.refused(code);
        conn.release_own_slice();
        return Err(Error::RadioRefused);
    }
    let hint = wire::parse_hex(message.trim());
    let stream = conn.wait(Instant::now() + STEP, |v| {
        v.streams
            .iter()
            .find(|(_, s)| {
                s.kind == "dax_rx" && s.dax_channel == Some(channel) && s.client_handle == Some(own)
            })
            .map(|(id, _)| *id)
    })?;
    if hint.is_some_and(|h| h != stream) {
        return Err(Error::ProtocolError);
    }
    conn.stream = Some(stream);
    let tuned = shared.tuned_hz.load(Ordering::Acquire);
    if tuned != 0 {
        conn.apply_frequency(index, tuned, Instant::now() + STEP)?;
    }
    *reached = true;
    let facts = conn.slice_facts();
    shared.update(|s| become_ready(s, facts));
    loop {
        if shared.stopping() {
            return Ok(());
        }
        if !shared.allowed() {
            return Err(Error::Unauthorized);
        }
        conn.pump()?;
        conn.register_keepalive();
        conn.check_own()?;
        let facts = conn.slice_facts();
        shared.update(|s| {
            if s.slice != facts {
                s.slice = facts;
            }
        });
        match tunes.try_recv() {
            Ok(request) => {
                let result = serve_tune(&mut conn, &request, |result| {
                    let _ = request.reply.try_send(result);
                });
                if matches!(
                    result,
                    Err(Error::TransportLost | Error::ProtocolError | Error::ResourceLost)
                ) {
                    return result.map(|_| ());
                }
            }
            Err(TryRecvError::Empty) => {}
            Err(TryRecvError::Disconnected) => return Ok(()),
        }
    }
}

/// One tune of the ready loop. The slice as the radio now reports it is published before the
/// caller hears the result, so no reader sees a confirmed selection beside the slice's earlier
/// frequency; after a failed tune the snapshot likewise shows what the radio reports.
fn serve_tune(
    conn: &mut Conn<'_>,
    request: &TuneRequest,
    reply: impl FnOnce(Result<u64, Error>),
) -> Result<u64, Error> {
    let result = conn.tune(request);
    let facts = conn.slice_facts();
    conn.shared.update(|s| {
        if s.slice != facts {
            s.slice = facts;
        }
    });
    reply(result);
    result
}

/// Puts packets back in the order of their 4-bit count. One ahead of its turn waits; a turn is
/// given up only when `REORDER_DEPTH` packets wait behind it. The count tells a jump forward from
/// a late packet only by which half it falls in: 8 or more lost in a row read as late, and the
/// timeline then falls short by up to 16 packets (85 ms) with no epoch.
struct Reorder<T> {
    /// The turn due now.
    next: Option<u8>,
    /// One past the newest count seen; turns from `next` up to here are waited for.
    end: u8,
    held: Vec<(u8, T)>,
}
impl<T> Reorder<T> {
    fn new() -> Self {
        Self {
            next: None,
            end: 0,
            held: Vec::new(),
        }
    }
    /// Hands on what is due, each packet with the number of turns given up before it. False: the
    /// packet came after its turn or twice, and is dropped. After a stall the count may have
    /// wrapped, so what waits goes on first and the count starts over.
    fn accept(
        &mut self,
        count: u8,
        packet: T,
        stalled: bool,
        mut hand_on: impl FnMut(T, u64),
    ) -> bool {
        if stalled {
            self.release(1, &mut hand_on);
            self.next = None;
        }
        let due = *self.next.get_or_insert_with(|| {
            self.end = count;
            count
        });
        let awaited = (count.wrapping_sub(due) & 15) < (self.end.wrapping_sub(due) & 15);
        let passed = !awaited && (count.wrapping_sub(self.end) & 15) >= 8;
        if passed || self.held.iter().any(|(c, _)| *c == count) {
            return false;
        }
        if !awaited {
            self.end = count.wrapping_add(1) & 15;
        }
        self.held.push((count, packet));
        self.release(usize::from(REORDER_DEPTH), &mut hand_on);
        true
    }
    fn release(&mut self, depth: usize, hand_on: &mut impl FnMut(T, u64)) {
        let mut missed = 0;
        while let Some(due) = self.next {
            if let Some(at) = self.held.iter().position(|(c, _)| *c == due) {
                hand_on(self.held.swap_remove(at).1, missed);
                missed = 0;
            } else if self.held.len() >= depth {
                missed += 1;
            } else {
                return;
            }
            self.next = Some(due.wrapping_add(1) & 15);
        }
    }
}

#[derive(Clone, Debug, Default)]
struct ClientView {
    client_id: Option<String>,
}
#[derive(Clone, Debug, Default)]
struct SliceView {
    in_use: bool,
    client_handle: Option<u32>,
    frequency_hz: Option<u64>,
    mode: Option<String>,
    rx_antenna: Option<String>,
    dax: Option<u8>,
    letter: Option<String>,
    observed_at: Option<Instant>,
}
#[derive(Clone, Debug, Default)]
struct StreamView {
    kind: String,
    dax_channel: Option<u8>,
    client_handle: Option<u32>,
}
#[derive(Default)]
struct View {
    clients: HashMap<u32, ClientView>,
    slices: HashMap<u32, SliceView>,
    streams: HashMap<u32, StreamView>,
}

/// `14.074000` MHz to exact hertz; at most six fractional digits are significant.
pub fn megahertz(text: &str) -> Option<u64> {
    let (whole, fraction) = text.split_once('.').unwrap_or((text, ""));
    if whole.is_empty()
        || whole.len() > 5
        || !whole.bytes().all(|b| b.is_ascii_digit())
        || fraction.len() > 9
        || !fraction.bytes().all(|b| b.is_ascii_digit())
    {
        return None;
    }
    let mut micro = fraction.chars().take(6).collect::<String>();
    while micro.len() < 6 {
        micro.push('0');
    }
    Some(whole.parse::<u64>().ok()? * 1_000_000 + micro.parse::<u64>().ok()?)
}
pub fn megahertz_text(hz: u64) -> String {
    format!("{}.{:06}", hz / 1_000_000, hz % 1_000_000)
}

impl View {
    fn apply(&mut self, status: &Status) {
        let bounded = |len: usize| len < MAX_TRACKED;
        let small = |v: &str| (!v.is_empty() && v.len() <= 32).then(|| v.to_owned());
        match status.object.as_str() {
            "client" => {
                let Some(handle) = wire::parse_hex(&status.id) else {
                    return;
                };
                if status.has_word("disconnected") {
                    self.clients.remove(&handle);
                } else if self.clients.contains_key(&handle) || bounded(self.clients.len()) {
                    let entry = self.clients.entry(handle).or_default();
                    if let Some(id) = status
                        .get("client_id")
                        .and_then(|v| (v.len() <= 64).then(|| v.to_owned()))
                    {
                        entry.client_id = Some(id);
                    }
                }
            }
            "slice" => {
                let Some(index) = status
                    .id
                    .parse::<u32>()
                    .ok()
                    .filter(|i| (*i as usize) < MAX_TRACKED)
                else {
                    return;
                };
                let entry = self.slices.entry(index).or_default();
                entry.observed_at = Some(Instant::now());
                for (key, value) in &status.pairs {
                    match key.as_str() {
                        "in_use" => entry.in_use = value == "1",
                        "client_handle" => entry.client_handle = wire::parse_hex(value),
                        "RF_frequency" => entry.frequency_hz = megahertz(value),
                        "mode" => entry.mode = small(value.as_str()),
                        "rxant" => entry.rx_antenna = small(value.as_str()),
                        "dax" => entry.dax = value.parse().ok().filter(|c| (1..=8).contains(c)),
                        "index_letter" => entry.letter = small(value.as_str()),
                        _ => {}
                    }
                }
                if status.has_word("removed") {
                    entry.in_use = false;
                }
                if !entry.in_use {
                    self.slices.remove(&index);
                }
            }
            "stream" => {
                let Some(id) = wire::parse_hex(&status.id) else {
                    return;
                };
                if status.has_word("removed") {
                    self.streams.remove(&id);
                } else if self.streams.contains_key(&id) || bounded(self.streams.len()) {
                    let entry = self.streams.entry(id).or_default();
                    if let Some(kind) = status.get("type").and_then(small) {
                        entry.kind = kind;
                    }
                    if let Some(channel) = status.get("dax_channel") {
                        entry.dax_channel = channel.parse().ok();
                    }
                    if let Some(handle) = status.get("client_handle") {
                        entry.client_handle = wire::parse_hex(handle);
                    }
                }
            }
            _ => {}
        }
    }
}

struct Conn<'a> {
    shared: &'a Shared,
    tcp: TcpStream,
    radio: IpAddr,
    lines: wire::LineBuffer,
    sequence: u32,
    pending: Option<u32>,
    reply: Option<(u32, String)>,
    version: Option<wire::ProtocolVersion>,
    own: Option<u32>,
    view: View,
    udp: Option<UdpSocket>,
    /// A routed path: the datagram that opens and keeps open the way back for the stream.
    register: Option<([SocketAddr; 2], String)>,
    last_register: Option<Instant>,
    slice: Option<u32>,
    stream: Option<u32>,
    order: Reorder<(Vec<f32>, Option<u64>)>,
    last_seen: Option<u64>,
    buffer: Vec<u8>,
}
impl<'a> Conn<'a> {
    fn new(shared: &'a Shared, tcp: TcpStream, radio: IpAddr) -> Self {
        Self {
            shared,
            tcp,
            radio,
            lines: wire::LineBuffer::default(),
            sequence: 0,
            pending: None,
            reply: None,
            version: None,
            own: None,
            view: View::default(),
            udp: None,
            register: None,
            last_register: None,
            slice: None,
            stream: None,
            order: Reorder::new(),
            last_seen: None,
            buffer: vec![0; wire::MAX_DATAGRAM + 1],
        }
    }
    /// From the stream's own port, well inside a router's UDP tracking timeout.
    fn register_keepalive(&mut self) {
        let (Some(udp), Some((targets, text))) = (self.udp.as_ref(), self.register.as_ref()) else {
            return;
        };
        if self
            .last_register
            .is_some_and(|at| at.elapsed() < REGISTER_EVERY)
        {
            return;
        }
        self.last_register = Some(Instant::now());
        for target in targets {
            let _ = udp.send_to(text.as_bytes(), target);
        }
    }
    fn pump(&mut self) -> Result<(), Error> {
        let mut chunk = [0u8; 4096];
        match self.tcp.read(&mut chunk) {
            Ok(0) => return Err(Error::TransportLost),
            Ok(n) => {
                let mut lines = Vec::new();
                self.lines
                    .push(&chunk[..n], &mut lines)
                    .map_err(|_| Error::ProtocolError)?;
                for line in lines {
                    self.line(&line);
                }
            }
            Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {}
            Err(_) => return Err(Error::TransportLost),
        }
        self.datagrams();
        Ok(())
    }
    fn line(&mut self, text: &str) {
        match wire::parse_line(text) {
            Ok(Line::Version(v)) => self.version = Some(v),
            Ok(Line::Handle(h)) => self.own = Some(h),
            Ok(Line::Reply {
                sequence,
                code,
                message,
            }) => {
                // Only the one outstanding command can be answered; others are stale.
                if self.pending == Some(sequence) {
                    self.pending = None;
                    self.reply = Some((code, message));
                }
            }
            Ok(Line::Status { status, .. }) => self.view.apply(&status),
            Ok(Line::Message { .. }) => {}
            Err(_) => self.shared.update(|s| s.counters.invalid += 1),
        }
    }
    fn datagrams(&mut self) {
        let Some(udp) = self.udp.as_ref() else {
            return;
        };
        for _ in 0..64 {
            let (size, from) = match udp.recv_from(&mut self.buffer) {
                Ok(v) => v,
                Err(_) => return,
            };
            let packet = &self.buffer[..size];
            if from.ip() != self.radio {
                self.shared.update(|s| s.counters.foreign += 1);
                continue;
            }
            let Ok(vita) = wire::parse_vita(packet) else {
                self.shared.update(|s| s.counters.invalid += 1);
                continue;
            };
            if self.stream.is_none() || vita.stream_id != self.stream {
                // Another client's stream, an old session's stream or a non-audio packet.
                self.shared.update(|s| s.counters.foreign += 1);
                continue;
            }
            let count = vita.packet_count;
            let Ok(samples) = wire::dax_samples(&vita) else {
                self.shared.update(|s| s.counters.invalid += 1);
                continue;
            };
            // The 4-bit count only reveals some losses; it never proves continuity.
            let now_ms = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_or(0, |d| d.as_millis() as i128);
            let (tsi, offset) = (vita.tsi, vita_offset_ms(&vita, now_ms));
            let arrival = arrival_100ns();
            let frames = samples.len() as u64 / 2;
            let spacing = self.last_seen.zip(arrival).map(|(last, now)| {
                (now as f64 - last as f64) / 10_000.0 - frames as f64 * 1000.0 / DAX_RATE as f64
            });
            let stalled = self
                .last_seen
                .zip(arrival)
                .is_some_and(|(last, now)| now.saturating_sub(last) > UNKNOWN_GAP_100NS);
            self.last_seen = arrival.or(self.last_seen);
            self.shared.update_vita(tsi, offset, spacing);
            let shared = self.shared;
            let taken = self.order.accept(
                count,
                (samples, arrival),
                stalled,
                |(samples, arrival), missed| Self::deliver(shared, &samples, missed, arrival),
            );
            if !taken {
                shared.count(|counters, _| counters.late += 1);
            }
        }
    }
    fn deliver(shared: &Shared, samples: &[f32], missed: u64, arrival: Option<u64>) {
        // The radio's 24 kHz reach the shared 48 kHz converter with each frame held twice;
        // its 6 kHz low-pass removes the images.
        let frames = samples.len();
        let peak = samples
            .iter()
            .step_by(2)
            .map(|v| v.abs())
            .fold(0.0_f32, f32::max);
        if let Ok(mut sink) = shared.sink.lock()
            && let Some(sink) = sink.as_mut()
        {
            let duration = frames as u64 * 10_000_000 / u64::from(NativeInput::FORMAT.rate);
            // The packet's first frame arrived one packet duration before its last one. A
            // rejected clock bracket continues the last arrival instead of breaking the epoch.
            let arrival = arrival.or(sink.last_arrival.map(|last| last + duration));
            // The 4-bit count can wrap, so only a short gap has a known size.
            let unknown = sink
                .last_arrival
                .zip(arrival)
                .is_some_and(|(last, now)| now.saturating_sub(last) > UNKNOWN_GAP_100NS);
            sink.last_arrival = arrival;
            let gap = std::mem::take(&mut sink.session_lost) || unknown;
            let flags = if gap { DATA_DISCONTINUITY } else { 0 }
                | if arrival.is_none() {
                    TIMESTAMP_ERROR
                } else {
                    0
                };
            if flags != 0 {
                sink.flush();
            }
            // Known missing packets keep the timeline and the analysis window: they become
            // silence, since a jump of the position would discard the window being collected.
            // An unknown gap (flags) opens a new epoch instead, and its count may have wrapped.
            let silence = if flags == 0 {
                missed as usize * frames
            } else {
                0
            };
            if silence > 0 {
                if sink.pending_frames == 0 {
                    sink.pending_first = (
                        sink.next_frame,
                        arrival.map_or(0, |a| a.saturating_sub(duration * (missed + 1))),
                        0,
                    );
                }
                let bytes = silence * 2 * 4;
                sink.pending.resize(sink.pending.len() + bytes, 0);
                sink.pending_frames += silence;
                sink.next_frame = sink.next_frame.saturating_add(silence as u64);
            }
            if sink.pending_frames == 0 {
                sink.pending_first = (
                    sink.next_frame,
                    arrival.map_or(0, |a| a.saturating_sub(duration)),
                    flags,
                );
            }
            for frame in samples.as_chunks::<2>().0 {
                for _ in 0..2 {
                    sink.pending
                        .extend(frame.iter().flat_map(|v| v.to_le_bytes()));
                }
            }
            sink.pending_frames += frames;
            sink.next_frame = sink.next_frame.saturating_add(frames as u64);
            if sink.pending_frames >= GROUP_FRAMES {
                sink.flush();
            }
        }
        shared.count(|counters, last_peak| {
            counters.accepted += 1;
            counters.lost += missed;
            *last_peak = Some(peak);
        });
    }
    fn request(&mut self, text: &str) -> Result<(u32, String), Error> {
        self.sequence = self
            .sequence
            .checked_add(1)
            .filter(|n| *n <= i32::MAX as u32)
            .ok_or(Error::ProtocolError)?;
        let line = wire::command(self.sequence, text).map_err(|_| Error::InvalidRequest)?;
        self.pending = Some(self.sequence);
        self.reply = None;
        self.tcp
            .write_all(line.as_bytes())
            .map_err(|_| Error::TransportLost)?;
        let deadline = Instant::now() + STEP;
        loop {
            if let Some(reply) = self.reply.take() {
                return Ok(reply);
            }
            if Instant::now() >= deadline {
                return Err(Error::Timeout);
            }
            if self.shared.stopping() {
                return Err(Error::Stopped);
            }
            self.pump()?;
        }
    }
    fn refused(&self, code: u32) {
        self.shared.update(|s| s.radio_code = Some(code));
    }
    fn expect_ok(&mut self, text: &str) -> Result<(), Error> {
        let (code, _) = self.request(text)?;
        if code != 0 {
            self.refused(code);
            return Err(Error::RadioRefused);
        }
        Ok(())
    }
    fn wait<T>(
        &mut self,
        deadline: Instant,
        mut ready: impl FnMut(&View) -> Option<T>,
    ) -> Result<T, Error> {
        loop {
            if let Some(value) = ready(&self.view) {
                return Ok(value);
            }
            if Instant::now() >= deadline {
                return Err(Error::Timeout);
            }
            if self.shared.stopping() {
                return Err(Error::Stopped);
            }
            self.pump()?;
        }
    }
    /// Removes only the slice this session created and still confirms as its own.
    fn release_own_slice(&mut self) {
        if let (Some(index), Some(own)) = (self.slice.take(), self.own)
            && self
                .view
                .slices
                .get(&index)
                .is_some_and(|s| s.client_handle == Some(own))
        {
            let _ = self.request(&format!("slice remove {index}"));
        }
    }
    fn check_own(&self) -> Result<(), Error> {
        let own = self.own;
        let slice = self.slice.and_then(|i| self.view.slices.get(&i));
        let stream = self.stream.and_then(|i| self.view.streams.get(&i));
        if slice.is_none_or(|s| s.client_handle != own)
            || stream.is_none_or(|s| s.client_handle != own)
        {
            return Err(Error::ResourceLost);
        }
        // Two stations choosing together can pick one channel. The lower slice keeps it;
        // the other session closes and chooses again.
        if let (Some(index), Some(channel)) = (self.slice, slice.and_then(|s| s.dax))
            && self
                .view
                .slices
                .iter()
                .any(|(other, s)| *other < index && s.dax == Some(channel))
        {
            return Err(Error::DaxChannelConflict);
        }
        Ok(())
    }
    fn slice_facts(&self) -> Option<SliceFacts> {
        let index = self.slice?;
        let s = self.view.slices.get(&index)?;
        Some(SliceFacts {
            index,
            letter: s.letter.clone(),
            frequency_hz: s.frequency_hz,
            mode: s.mode.clone(),
            rx_antenna: s.rx_antenna.clone(),
            dax_channel: s.dax,
            stream_id: self.stream,
            observed_at: s.observed_at,
        })
    }
    fn tune(&mut self, request: &TuneRequest) -> Result<u64, Error> {
        let index = self.slice.ok_or(Error::NotReady)?;
        if request.cancelled.load(Ordering::Acquire) {
            return Err(Error::Cancelled);
        }
        let deadline = request.deadline.min(Instant::now() + STEP);
        let observed = self.apply_frequency(index, request.frequency_hz, deadline);
        if request.cancelled.load(Ordering::Acquire) {
            return Err(Error::Cancelled);
        }
        if observed.is_ok() {
            self.shared
                .tuned_hz
                .store(request.frequency_hz, Ordering::Release);
        }
        observed
    }
    /// Read first: each setting is written only when the slice's status differs, and
    /// success needs the radio's own status for this slice, not only the reply. A FLEX-6600
    /// replies to a tune and reports nothing (2026-11-06, firmware 4.3.16), so after a write the
    /// read-back is asked for: subscribing again returns the slice's full status.
    fn apply_frequency(
        &mut self,
        index: u32,
        wanted: u64,
        deadline: Instant,
    ) -> Result<u64, Error> {
        let current = self.view.slices.get(&index).cloned().unwrap_or_default();
        if current.mode.as_deref() != Some("DIGU") {
            self.expect_ok(&format!("slice set {index} mode=DIGU"))?;
        }
        if current.frequency_hz != Some(wanted) {
            self.expect_ok(&format!("slice tune {index} {}", megahertz_text(wanted)))?;
        }
        if current.frequency_hz != Some(wanted) || current.mode.as_deref() != Some("DIGU") {
            self.expect_ok("sub slice all")?;
        }
        self.wait(deadline, |v| {
            v.slices
                .get(&index)
                .filter(|s| s.frequency_hz == Some(wanted) && s.mode.as_deref() == Some("DIGU"))
                .and_then(|s| s.frequency_hz)
        })
    }
}

fn vita_offset_ms(packet: &wire::Vita<'_>, now_ms: i128) -> Option<i64> {
    let seconds = i128::from(packet.integer_time?);
    // TSF 2 is real time in picoseconds; anything else adds no sub-second fact.
    let fraction = packet
        .fractional_time
        .filter(|_| packet.tsf == 2)
        .map_or(0, |ps| i128::from(ps) / 1_000_000_000);
    i64::try_from(now_ms - seconds * 1000 - fraction).ok()
}

/// This host's arrival time of a packet on the capture timeline (QPC, 100 ns).
fn arrival_100ns() -> Option<u64> {
    #[cfg(windows)]
    return crate::audio::system_clock().map(|c| c.qpc_100ns);
    #[cfg(not(windows))]
    None
}

/// The station's live receive input over its own native DAX stream. The samples go
/// through the shared native queue, converter and epoch latch of `crate::audio`.
pub struct NativeInput {
    session: Arc<Session>,
    queue: Arc<PacketQueue>,
    source: LiveSource,
    attachment: Option<u64>,
    status: AudioStatus,
}
impl NativeInput {
    pub const FORMAT: NativeFormat = NativeFormat {
        rate: 48_000,
        channels: 2,
        encoding: Encoding::Float32,
    };
    pub fn new(session: Arc<Session>) -> Result<Self, SourceError> {
        let queue = PacketQueue::new(Self::FORMAT)?;
        let source = LiveSource::new(queue.clone(), Self::FORMAT)?;
        Ok(Self {
            session,
            queue,
            source,
            attachment: None,
            status: AudioStatus {
                state: AudioState::Closed,
                error: None,
                retry_after_ms: None,
            },
        })
    }
    pub fn start(&mut self) -> Result<(), SourceError> {
        match self.session.attach(self.queue.clone()) {
            Ok(attachment) => {
                self.attachment = Some(attachment);
                self.status.state = AudioState::Running;
                self.status.error = None;
                Ok(())
            }
            Err(_) => {
                self.status.state = AudioState::Unavailable;
                self.status.error = Some(SourceError::Unavailable);
                Err(SourceError::Unavailable)
            }
        }
    }
    pub fn request_stop(&mut self) {
        if let Some(attachment) = self.attachment.take() {
            self.session.detach(attachment);
        }
        self.source.stop();
        self.status.state = AudioState::Closed;
    }
    /// While the session is down the job keeps running and shows the input unavailable.
    pub fn status(&self) -> AudioStatus {
        if self.status.state != AudioState::Running || self.session.ready() {
            return self.status;
        }
        AudioStatus {
            state: AudioState::Unavailable,
            error: Some(SourceError::Unavailable),
            retry_after_ms: self.session.snapshot().retry_after_ms,
        }
    }
    /// The latest (canonical frame, UTC FILETIME), for the same drift tracking as a device.
    pub fn clock_utc(&self) -> Option<(u64, u64)> {
        let (frame, qpc) = self.source.clock_sample()?;
        #[cfg(windows)]
        return Some((frame, crate::audio::system_clock()?.utc_at(qpc)?));
        #[cfg(not(windows))]
        {
            let _ = (frame, qpc);
            None
        }
    }
    pub fn marked_frames(&self, from: u64, to: u64) -> (u64, u64) {
        self.source.marked_frames(from, to)
    }
    pub fn capture_diagnostics(&self) -> CaptureDiagnostics {
        self.source.capture_diagnostics()
    }
}
impl Drop for NativeInput {
    fn drop(&mut self) {
        if let Some(attachment) = self.attachment.take() {
            self.session.detach(attachment);
        }
    }
}
impl SampleSource for NativeInput {
    fn descriptor(&self) -> Option<Arc<SourceDescriptor>> {
        self.source.descriptor()
    }
    fn poll(&mut self) -> SourcePoll {
        let event = self.source.poll();
        if let SourcePoll::Failed(error) = &event
            && self.status.state == AudioState::Running
        {
            self.status.state = AudioState::Unavailable;
            self.status.error = Some(*error);
        }
        event
    }
    fn acknowledge_epoch(
        &mut self,
        proposal_counter: u64,
        descriptor: Arc<SourceDescriptor>,
        timing: SourceTiming,
    ) -> Result<(), SourceError> {
        self.source
            .acknowledge_epoch(proposal_counter, descriptor, timing)
    }
}

#[cfg(test)]
#[path = "session_tests.rs"]
mod tests;
