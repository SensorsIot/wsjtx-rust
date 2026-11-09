//! WstxTransmit::TransmitClock: the station measures its own UTC offset by SNTP
//! (RFC 4330 client, RFC 5905 packet) instead of relying on Windows reporting that a
//! time service disciplines the clock (a third-party tool that steps the clock is
//! never reported as discipline). Measurements run on their own thread; the transmit
//! owner only reads the latest one.
use super::ClockState;
use std::io;
use std::net::{SocketAddr, ToSocketAddrs, UdpSocket};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, Weak};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// #92 situation 1: the Windows Time service state, read without administrator rights
/// for the remedy of pc_clock_off; the station never starts or configures it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WindowsTime {
    Running,
    Stopped,
    Disabled,
    /// The query failed (or no Windows).
    Unknown,
}
impl WindowsTime {
    pub fn name(self) -> &'static str {
        match self {
            Self::Running => "running",
            Self::Stopped => "stopped",
            Self::Disabled => "disabled",
            Self::Unknown => "unknown",
        }
    }
}
/// Reads the Windows Time (W32Time) service state now: running; else disabled when its
/// start type is disabled; else stopped; unknown when a query fails.
pub fn windows_time() -> WindowsTime {
    #[cfg(windows)]
    {
        super::windows_time::query()
    }
    #[cfg(not(windows))]
    {
        WindowsTime::Unknown
    }
}

/// Servers in the operator's order; the next is tried when one does not answer.
pub const SERVERS: [&str; 3] = ["ch.pool.ntp.org", "time.windows.com", "pool.ntp.org"];
/// Largest |offset| that is still synchronized.
pub const MAX_OFFSET_MS: i64 = 500;
/// A measurement older than this no longer counts: the state is unknown.
pub const MAX_AGE: Duration = Duration::from_secs(600);
/// Largest difference between system and monotonic time elapsed since a measurement
/// that still counts as no clock step (free-running drift over `MAX_AGE` stays below it).
pub const MAX_STEP_MS: i64 = 100;
/// Time between measurements.
pub const INTERVAL: Duration = Duration::from_secs(60);
/// How long one server may take to answer.
pub const SERVER_TIMEOUT: Duration = Duration::from_millis(1500);
/// Seconds from 1900-01-01 (NTP era 0) to 1970-01-01.
const NTP_UNIX_SECONDS: u64 = 2_208_988_800;

/// One answered SNTP exchange.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Measurement {
    /// The server name as configured.
    pub server: String,
    /// Server time minus station system time.
    pub offset_ms: i64,
    pub round_trip_ms: i64,
    /// Monotonic instant at which the reply arrived.
    pub taken: Instant,
    /// Station system clock at that instant as the offset describes it (send time plus
    /// monotonic elapsed time), so a later step, also one during the exchange, is detected.
    pub system: SystemTime,
}

fn unix_ms(t: SystemTime) -> i128 {
    match t.duration_since(UNIX_EPOCH) {
        Ok(d) => d.as_millis() as i128,
        Err(e) => -(e.duration().as_millis() as i128),
    }
}
/// System time minus monotonic time elapsed since `m`: nonzero when the system clock
/// was stepped (or slewed) after the measurement.
fn step_ms(m: &Measurement, now: Instant, system_now: SystemTime) -> i128 {
    unix_ms(system_now)
        - unix_ms(m.system)
        - now.saturating_duration_since(m.taken).as_millis() as i128
}
/// The rule of TransmitClock at monotonic `now` and system time `system_now`:
/// synchronized when the latest measurement is at most `MAX_AGE` old, the system clock
/// has not stepped by more than `MAX_STEP_MS` since, and |offset| <= `MAX_OFFSET_MS`;
/// unsynchronized when it is that recent and unstepped but outside; otherwise unknown
/// (the next measurement decides).
pub fn state(latest: Option<&Measurement>, now: Instant, system_now: SystemTime) -> ClockState {
    match latest {
        Some(m)
            if now.saturating_duration_since(m.taken) <= MAX_AGE
                && step_ms(m, now, system_now).abs() <= i128::from(MAX_STEP_MS) =>
        {
            if m.offset_ms.abs() <= MAX_OFFSET_MS {
                ClockState::Synchronized
            } else {
                ClockState::Unsynchronized
            }
        }
        _ => ClockState::Unknown,
    }
}

/// NTP 32.32 fixed-point timestamp of `t` (seconds wrap per NTP era).
pub fn ntp_timestamp(t: SystemTime) -> u64 {
    let since = t.duration_since(UNIX_EPOCH).unwrap_or_default();
    let seconds = (since.as_secs() + NTP_UNIX_SECONDS) & 0xffff_ffff;
    let fraction = (u64::from(since.subsec_nanos()) << 32) / 1_000_000_000;
    (seconds << 32) | fraction
}

/// A client request (LI 0, version 4, mode 3) carrying `transmit` as its transmit timestamp.
pub fn request(transmit: u64) -> [u8; 48] {
    let mut packet = [0u8; 48];
    packet[0] = 0x23;
    packet[40..48].copy_from_slice(&transmit.to_be_bytes());
    packet
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ReplyError {
    /// Shorter than the 48-byte header.
    Short,
    /// Leap indicator 3: the server's clock is not synchronized.
    Alarm,
    /// Not a server reply (mode 4).
    Mode,
    /// Stratum outside 1..=15 (0 is a kiss-of-death).
    Stratum,
    /// Transmit timestamp zero.
    ZeroTransmit,
    /// The originate timestamp does not echo our request.
    OriginMismatch,
}

fn timestamp(reply: &[u8], at: usize) -> u64 {
    u64::from_be_bytes(reply[at..at + 8].try_into().expect("8 bytes"))
}
/// a - b in 32.32 fixed point; wrapping, so an era boundary between them is harmless.
fn difference(a: u64, b: u64) -> i128 {
    i128::from(a.wrapping_sub(b) as i64)
}
fn fixed_to_ms(fixed: i128) -> i64 {
    ((fixed * 1000 + (1 << 31)) >> 32) as i64
}

/// Validates `reply` to a request sent at `t1` and received at `t4` (both NTP
/// timestamps of the station clock) and returns (offset ms, round trip ms):
/// offset = ((T2-T1)+(T3-T4))/2, round trip = (T4-T1)-(T3-T2), never negative.
pub fn offset(reply: &[u8], t1: u64, t4: u64) -> Result<(i64, i64), ReplyError> {
    if reply.len() < 48 {
        return Err(ReplyError::Short);
    }
    if reply[0] >> 6 == 3 {
        return Err(ReplyError::Alarm);
    }
    if reply[0] & 7 != 4 {
        return Err(ReplyError::Mode);
    }
    if !(1..=15).contains(&reply[1]) {
        return Err(ReplyError::Stratum);
    }
    let (origin, t2, t3) = (
        timestamp(reply, 24),
        timestamp(reply, 32),
        timestamp(reply, 40),
    );
    if t3 == 0 {
        return Err(ReplyError::ZeroTransmit);
    }
    if origin != t1 {
        return Err(ReplyError::OriginMismatch);
    }
    let offset = (difference(t2, t1) + difference(t3, t4)) / 2;
    let round_trip = difference(t4, t1) - difference(t3, t2);
    Ok((fixed_to_ms(offset), fixed_to_ms(round_trip).max(0)))
}

fn address(server: &str) -> io::Result<SocketAddr> {
    let target = if server.contains(':') {
        server.to_string()
    } else {
        format!("{server}:123")
    };
    let mut addresses = target.to_socket_addrs()?.collect::<Vec<_>>();
    addresses.sort_by_key(|a| !a.is_ipv4());
    addresses
        .into_iter()
        .next()
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no address"))
}

/// One answered exchange: the offset and round trip refer to the station clock at
/// `sent_system`, read at monotonic `sent`; the reply arrived at monotonic `received`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Exchange {
    pub offset_ms: i64,
    pub round_trip_ms: i64,
    pub sent_system: SystemTime,
    pub sent: Instant,
    pub received: Instant,
}

/// One SNTP exchange with `server` (a host name, port 123 by default, or host:port),
/// bounded by `timeout` after name resolution. `now` is the station clock under
/// measurement; the receive time is the send time plus monotonic elapsed time, so a
/// clock step during the exchange cannot distort it. Invalid datagrams are ignored
/// until the deadline.
pub fn query(
    server: &str,
    timeout: Duration,
    now: &dyn Fn() -> SystemTime,
) -> io::Result<Exchange> {
    let target = address(server)?;
    let local: SocketAddr = if target.is_ipv4() {
        "0.0.0.0:0".parse().expect("address")
    } else {
        "[::]:0".parse().expect("address")
    };
    let socket = UdpSocket::bind(local)?;
    socket.connect(target)?;
    let sent_system = now();
    let t1 = ntp_timestamp(sent_system);
    let sent = Instant::now();
    socket.send(&request(t1))?;
    let deadline = sent + timeout;
    let mut buffer = [0u8; 512];
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Err(io::Error::new(io::ErrorKind::TimedOut, "no valid reply"));
        }
        socket.set_read_timeout(Some(left))?;
        let n = match socket.recv(&mut buffer) {
            Ok(n) => n,
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::WouldBlock
                        | io::ErrorKind::TimedOut
                        | io::ErrorKind::ConnectionReset
                ) =>
            {
                // Windows reports an ICMP port-unreachable as a reset; keep waiting.
                if e.kind() == io::ErrorKind::ConnectionReset {
                    std::thread::sleep(left.min(Duration::from_millis(10)));
                }
                continue;
            }
            Err(e) => return Err(e),
        };
        let received = Instant::now();
        let elapsed = received - sent;
        let t4 = t1.wrapping_add(
            ((elapsed.as_nanos() << 32) / 1_000_000_000).min(u128::from(u64::MAX)) as u64,
        );
        if let Ok((offset_ms, round_trip_ms)) = offset(&buffer[..n], t1, t4) {
            return Ok(Exchange {
                offset_ms,
                round_trip_ms,
                sent_system,
                sent,
                received,
            });
        }
    }
}

/// A source of clock measurements (SNTP on the station, fakes in tests).
pub trait Source: Send {
    fn measure(&mut self) -> Option<Measurement>;
    /// Whether a round asks any server (false for an empty server list), for the
    /// warning ntp_unreachable (#92).
    fn asks(&self) -> bool {
        true
    }
}

/// SNTP over `servers` in order: the first that answers validly is the measurement.
pub struct Sntp {
    pub servers: Vec<String>,
    pub timeout: Duration,
    pub now: fn() -> SystemTime,
}
impl Sntp {
    /// The station's servers and timeout on the system clock.
    pub fn station() -> Self {
        Self {
            servers: SERVERS.iter().map(|s| s.to_string()).collect(),
            timeout: SERVER_TIMEOUT,
            now: SystemTime::now,
        }
    }
}
/// The servers of a WSTX_SNTP_SERVERS value: comma-separated, blanks dropped.
pub fn server_list(list: &str) -> Vec<String> {
    list.split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(String::from)
        .collect()
}
impl Source for Sntp {
    fn asks(&self) -> bool {
        !self.servers.is_empty()
    }
    fn measure(&mut self) -> Option<Measurement> {
        self.servers.iter().find_map(|server| {
            let e = query(server, self.timeout, &self.now).ok()?;
            // The system time the offset describes, carried to the reply on the
            // monotonic clock: a step during the exchange then shows as a step.
            Some(Measurement {
                server: server.clone(),
                offset_ms: e.offset_ms,
                round_trip_ms: e.round_trip_ms,
                taken: e.received,
                system: e.sent_system + (e.received - e.sent),
            })
        })
    }
}

/// The latest measurement, shared between the measuring thread and its readers.
#[derive(Default)]
pub struct Monitor {
    latest: Mutex<Option<Measurement>>,
    /// Whether any completed round since start asked a server (#92 ntp_unreachable).
    asked: AtomicBool,
}
impl Monitor {
    /// A monitor that never measures by itself (state unknown until `record`).
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }
    /// One completed round: `asked` whether it asked any server, `measurement` its valid
    /// answer (none keeps the previous measurement, which then ages out).
    pub fn round(&self, asked: bool, measurement: Option<Measurement>) {
        if asked {
            self.asked.store(true, Ordering::Release);
        }
        if let Some(m) = measurement {
            *self.latest.lock().unwrap_or_else(|p| p.into_inner()) = Some(m);
        }
    }
    /// Whether any round since start asked a server.
    pub fn asked(&self) -> bool {
        self.asked.load(Ordering::Acquire)
    }
    /// Measures with `source` now and then every `interval` on a dedicated thread,
    /// which ends after the monitor is dropped.
    pub fn start(mut source: Box<dyn Source>, interval: Duration) -> io::Result<Arc<Self>> {
        let monitor = Self::new();
        let weak: Weak<Self> = Arc::downgrade(&monitor);
        std::thread::Builder::new()
            .name("wstx-sntp".into())
            .spawn(move || {
                loop {
                    let asked = source.asks();
                    let measurement = source.measure();
                    match weak.upgrade() {
                        Some(monitor) => monitor.round(asked, measurement),
                        None => return,
                    }
                    std::thread::sleep(interval);
                }
            })?;
        Ok(monitor)
    }
    /// Records a measurement without marking a round (test seam): keeps the previous
    /// measurement (which then ages out) when none was taken.
    pub fn record(&self, measurement: Option<Measurement>) {
        self.round(false, measurement);
    }
    pub fn latest(&self) -> Option<Measurement> {
        self.latest
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .clone()
    }
    pub fn state(&self) -> ClockState {
        state(self.latest().as_ref(), Instant::now(), SystemTime::now())
    }
}
