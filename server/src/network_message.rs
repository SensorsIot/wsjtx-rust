#![forbid(unsafe_code)]
//! WstxUdp::UdpWire: the WSJT-X NetworkMessage datagram format (Network/NetworkMessage.hpp),
//! Qt QDataStream big-endian. Pure encoding and parsing; no socket, station or clock.

pub const MAGIC: u32 = 0xADBC_CBDA;
/// Header schema of outbound datagrams before a target's own datagram negotiates 3.
pub const SCHEMA_OUT: u32 = 2;
/// The maximum schema this station reads and advertises in Heartbeat.
pub const SCHEMA_MAX: u32 = 3;
pub const INBOUND_BYTES_MAX: usize = 4096;
/// Qt QDate::toJulianDay of 1970-01-01.
const JULIAN_EPOCH: i64 = 2_440_588;
const DAY_MS: i64 = 86_400_000;

pub mod kind {
    pub const HEARTBEAT: u32 = 0;
    pub const STATUS: u32 = 1;
    pub const DECODE: u32 = 2;
    pub const CLEAR: u32 = 3;
    pub const REPLY: u32 = 4;
    pub const QSO_LOGGED: u32 = 5;
    pub const CLOSE: u32 = 6;
    pub const REPLAY: u32 = 7;
    pub const HALT_TX: u32 = 8;
    pub const FREE_TEXT: u32 = 9;
    pub const LOCATION: u32 = 11;
    pub const LOGGED_ADIF: u32 = 12;
    pub const HIGHLIGHT_CALLSIGN: u32 = 13;
    pub const SWITCH_CONFIGURATION: u32 = 14;
    pub const CONFIGURE: u32 = 15;
}

/// A QDateTime in UTC (timespec 1) from Unix milliseconds.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DateTime {
    pub julian_day: i64,
    pub ms_of_day: u32,
}
impl DateTime {
    pub fn from_unix_ms(ms: i64) -> Self {
        Self {
            julian_day: ms.div_euclid(DAY_MS) + JULIAN_EPOCH,
            ms_of_day: ms_of_day(ms),
        }
    }
}
/// Milliseconds since UTC midnight (QTime) of Unix milliseconds.
pub fn ms_of_day(ms: i64) -> u32 {
    u32::try_from(ms.rem_euclid(DAY_MS)).unwrap_or(0)
}

/// One datagram under construction: header then fields.
pub struct Writer(Vec<u8>);
impl Writer {
    pub fn new(schema: u32, kind: u32, id: &str) -> Self {
        let mut w = Self(Vec::with_capacity(128));
        w.u32(MAGIC).u32(schema).u32(kind).utf8(id);
        w
    }
    pub fn u8(&mut self, v: u8) -> &mut Self {
        self.0.push(v);
        self
    }
    pub fn bool(&mut self, v: bool) -> &mut Self {
        self.u8(u8::from(v))
    }
    pub fn u32(&mut self, v: u32) -> &mut Self {
        self.0.extend_from_slice(&v.to_be_bytes());
        self
    }
    pub fn i32(&mut self, v: i32) -> &mut Self {
        self.0.extend_from_slice(&v.to_be_bytes());
        self
    }
    pub fn u64(&mut self, v: u64) -> &mut Self {
        self.0.extend_from_slice(&v.to_be_bytes());
        self
    }
    /// A C++ float field: QDataStream's default double precision writes the widened value.
    pub fn float(&mut self, v: f32) -> &mut Self {
        self.0.extend_from_slice(&f64::from(v).to_be_bytes());
        self
    }
    pub fn utf8(&mut self, v: &str) -> &mut Self {
        let n = u32::try_from(v.len()).unwrap_or(u32::MAX);
        self.u32(n);
        self.0.extend_from_slice(&v.as_bytes()[..n as usize]);
        self
    }
    pub fn date_time(&mut self, v: DateTime) -> &mut Self {
        self.0.extend_from_slice(&v.julian_day.to_be_bytes());
        self.u32(v.ms_of_day).u8(1)
    }
    pub fn finish(&mut self) -> Vec<u8> {
        std::mem::take(&mut self.0)
    }
}

/// Status (1) fields in wire order.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Status {
    pub dial_hz: u64,
    pub mode: String,
    pub dx_call: String,
    pub report: String,
    pub tx_mode: String,
    pub tx_enabled: bool,
    pub transmitting: bool,
    pub decoding: bool,
    pub rx_df: u32,
    pub tx_df: u32,
    pub de_call: String,
    pub de_grid: String,
    pub dx_grid: String,
    pub tx_watchdog: bool,
    pub sub_mode: String,
    pub fast_mode: bool,
    pub special_operation: u8,
    pub frequency_tolerance: u32,
    pub tr_period: u32,
    pub configuration_name: String,
    pub tx_message: String,
}
/// Decode (2) fields after New.
#[derive(Clone, Debug, PartialEq)]
pub struct Decode {
    pub time_ms: u32,
    pub snr: i32,
    pub delta_time: f32,
    pub delta_frequency: u32,
    pub mode: String,
    pub message: String,
    pub low_confidence: bool,
    pub off_air: bool,
}
/// QSO Logged (5) fields.
#[derive(Clone, Debug, PartialEq)]
pub struct Logged {
    pub time_off: DateTime,
    pub dx_call: String,
    pub dx_grid: String,
    pub tx_frequency_hz: u64,
    pub mode: String,
    pub report_sent: String,
    pub report_received: String,
    pub tx_power: String,
    pub comments: String,
    pub name: String,
    pub time_on: DateTime,
    pub operator_call: String,
    pub my_call: String,
    pub my_grid: String,
}

pub fn heartbeat(schema: u32, id: &str, version: &str, revision: &str) -> Vec<u8> {
    Writer::new(schema, kind::HEARTBEAT, id)
        .u32(SCHEMA_MAX)
        .utf8(version)
        .utf8(revision)
        .finish()
}
pub fn status(schema: u32, id: &str, s: &Status) -> Vec<u8> {
    Writer::new(schema, kind::STATUS, id)
        .u64(s.dial_hz)
        .utf8(&s.mode)
        .utf8(&s.dx_call)
        .utf8(&s.report)
        .utf8(&s.tx_mode)
        .bool(s.tx_enabled)
        .bool(s.transmitting)
        .bool(s.decoding)
        .u32(s.rx_df)
        .u32(s.tx_df)
        .utf8(&s.de_call)
        .utf8(&s.de_grid)
        .utf8(&s.dx_grid)
        .bool(s.tx_watchdog)
        .utf8(&s.sub_mode)
        .bool(s.fast_mode)
        .u8(s.special_operation)
        .u32(s.frequency_tolerance)
        .u32(s.tr_period)
        .utf8(&s.configuration_name)
        .utf8(&s.tx_message)
        .finish()
}
pub fn decode(schema: u32, id: &str, new: bool, d: &Decode) -> Vec<u8> {
    Writer::new(schema, kind::DECODE, id)
        .bool(new)
        .u32(d.time_ms)
        .i32(d.snr)
        .float(d.delta_time)
        .u32(d.delta_frequency)
        .utf8(&d.mode)
        .utf8(&d.message)
        .bool(d.low_confidence)
        .bool(d.off_air)
        .finish()
}
pub fn clear(schema: u32, id: &str) -> Vec<u8> {
    Writer::new(schema, kind::CLEAR, id).finish()
}
pub fn close(schema: u32, id: &str) -> Vec<u8> {
    Writer::new(schema, kind::CLOSE, id).finish()
}
/// QSO Logged with the three MessageClient fields after the documented ones (satellite,
/// satellite mode, Rx frequency) empty.
pub fn qso_logged(schema: u32, id: &str, l: &Logged) -> Vec<u8> {
    Writer::new(schema, kind::QSO_LOGGED, id)
        .date_time(l.time_off)
        .utf8(&l.dx_call)
        .utf8(&l.dx_grid)
        .u64(l.tx_frequency_hz)
        .utf8(&l.mode)
        .utf8(&l.report_sent)
        .utf8(&l.report_received)
        .utf8(&l.tx_power)
        .utf8(&l.comments)
        .utf8(&l.name)
        .date_time(l.time_on)
        .utf8(&l.operator_call)
        .utf8(&l.my_call)
        .utf8(&l.my_grid)
        .utf8("")
        .utf8("")
        .utf8("")
        .utf8("")
        .utf8("")
        .utf8("")
        .finish()
}
pub fn logged_adif(schema: u32, id: &str, adif: &str) -> Vec<u8> {
    Writer::new(schema, kind::LOGGED_ADIF, id)
        .utf8(adif)
        .finish()
}

/// A QColor read from the wire: None is an invalid colour (spec 0) or an unsupported spec.
pub type Color = Option<(u8, u8, u8)>;

#[derive(Clone, Debug, PartialEq)]
pub enum Inbound {
    Heartbeat {
        max_schema: u32,
        version: String,
        revision: String,
    },
    Clear {
        window: u8,
    },
    Reply {
        time_ms: u32,
        snr: i32,
        delta_time: f64,
        delta_frequency: u32,
        mode: String,
        message: String,
        low_confidence: bool,
        modifiers: u8,
    },
    Close,
    Replay,
    HaltTx {
        auto_only: bool,
    },
    FreeText {
        text: String,
        send: bool,
    },
    Location {
        location: String,
    },
    Highlight {
        call: String,
        background: Color,
        foreground: Color,
        last_only: bool,
    },
    SwitchConfiguration,
    Configure,
    /// A type this station does not handle (protocol rule 1: ignored silently).
    Other(u32),
}
#[derive(Clone, Debug, PartialEq)]
pub struct Datagram {
    pub schema: u32,
    pub id: String,
    pub message: Inbound,
}

struct Reader<'a> {
    bytes: &'a [u8],
    at: usize,
}
impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Option<&'a [u8]> {
        let end = self.at.checked_add(n)?;
        let slice = self.bytes.get(self.at..end)?;
        self.at = end;
        Some(slice)
    }
    fn done(&self) -> bool {
        self.at >= self.bytes.len()
    }
    fn u8(&mut self) -> Option<u8> {
        Some(self.take(1)?[0])
    }
    fn bool(&mut self) -> Option<bool> {
        self.u8().map(|b| b != 0)
    }
    fn u16(&mut self) -> Option<u16> {
        Some(u16::from_be_bytes(self.take(2)?.try_into().ok()?))
    }
    fn u32(&mut self) -> Option<u32> {
        Some(u32::from_be_bytes(self.take(4)?.try_into().ok()?))
    }
    fn i32(&mut self) -> Option<i32> {
        Some(i32::from_be_bytes(self.take(4)?.try_into().ok()?))
    }
    fn f64(&mut self) -> Option<f64> {
        Some(f64::from_be_bytes(self.take(8)?.try_into().ok()?))
    }
    /// utf8: 0xFFFFFFFF is the null string (read as empty); invalid UTF-8 is malformed.
    fn utf8(&mut self) -> Option<String> {
        let n = self.u32()?;
        if n == u32::MAX {
            return Some(String::new());
        }
        let bytes = self.take(usize::try_from(n).ok()?)?;
        String::from_utf8(bytes.to_vec()).ok()
    }
    /// QColor (Qt 5): qint8 spec, quint16 alpha, red, green, blue, pad.
    fn color(&mut self) -> Option<Color> {
        let spec = self.u8()?;
        let _alpha = self.u16()?;
        let (r, g, b) = (self.u16()?, self.u16()?, self.u16()?);
        let _pad = self.u16()?;
        Some((spec == 1).then_some(((r >> 8) as u8, (g >> 8) as u8, (b >> 8) as u8)))
    }
}

/// Parses one inbound datagram. None: refused (size, magic, schema other than 2 or 3, a
/// malformed header or a truncated or malformed field of a handled type). Trailing bytes
/// after the known fields are ignored (protocol rule 2).
pub fn parse(bytes: &[u8]) -> Option<Datagram> {
    if bytes.len() > INBOUND_BYTES_MAX {
        return None;
    }
    let mut r = Reader { bytes, at: 0 };
    if r.u32()? != MAGIC {
        return None;
    }
    let schema = r.u32()?;
    if !(SCHEMA_OUT..=SCHEMA_MAX).contains(&schema) {
        return None;
    }
    let kind = r.u32()?;
    let id = r.utf8()?;
    if id.is_empty() {
        return None;
    }
    let message = match kind {
        kind::HEARTBEAT => {
            if r.done() {
                Inbound::Heartbeat {
                    max_schema: 2,
                    version: String::new(),
                    revision: String::new(),
                }
            } else {
                Inbound::Heartbeat {
                    max_schema: r.u32()?,
                    version: r.utf8()?,
                    revision: r.utf8()?,
                }
            }
        }
        kind::CLEAR => {
            let window = if r.done() { 0 } else { r.u8()? };
            if window > 2 {
                return None;
            }
            Inbound::Clear { window }
        }
        kind::REPLY => Inbound::Reply {
            time_ms: r.u32()?,
            snr: r.i32()?,
            delta_time: r.f64()?,
            delta_frequency: r.u32()?,
            mode: r.utf8()?,
            message: r.utf8()?,
            low_confidence: r.bool()?,
            modifiers: if r.done() { 0 } else { r.u8()? },
        },
        kind::CLOSE => Inbound::Close,
        kind::REPLAY => Inbound::Replay,
        // Halt Tx acts even without its Auto Tx Only field (WstxUdp::InboundRules).
        kind::HALT_TX => Inbound::HaltTx {
            auto_only: r.bool().unwrap_or(false),
        },
        kind::FREE_TEXT => Inbound::FreeText {
            text: r.utf8()?,
            send: r.bool()?,
        },
        kind::LOCATION => Inbound::Location {
            location: r.utf8()?,
        },
        kind::HIGHLIGHT_CALLSIGN => Inbound::Highlight {
            call: r.utf8()?,
            background: r.color()?,
            foreground: r.color()?,
            last_only: r.bool()?,
        },
        kind::SWITCH_CONFIGURATION => Inbound::SwitchConfiguration,
        kind::CONFIGURE => Inbound::Configure,
        other => Inbound::Other(other),
    };
    Some(Datagram {
        schema,
        id,
        message,
    })
}
