#![forbid(unsafe_code)]
//! FR-023 native FlexRadio wire subset: bounded TCP control lines, VITA-49 DAX receive
//! packets and discovery packets. Independently written from the SmartSDR TCP/IP API
//! wiki and the wire facts recorded in WstxFlexSession::NativeFlexWireSubset; no
//! vendor code is translated or linked.

/// Control TCP port and the discovery UDP port of the pinned API (both 4992).
pub const CONTROL_PORT: u16 = 4992;
pub const DISCOVERY_PORT: u16 = 4992;
/// The radio's UDP ports a routed client sends its registration to.
pub const REGISTER_PORTS: [u16; 2] = [4991, 4993];
/// The only admitted API protocol version (`V1.4.0.0`).
pub const SUPPORTED_PROTOCOL: ProtocolVersion = ProtocolVersion {
    major: 1,
    minor: 4,
    a: 0,
    b: 0,
};
/// One incoming line including its LF; one outgoing command including its LF.
pub const MAX_LINE: usize = 4096;
pub const MAX_COMMAND: usize = 1024;
/// Largest accepted UDP datagram.
pub const MAX_DATAGRAM: usize = 16_384;
pub const FLEX_OUI: u32 = 0x00_1C2D;
pub const FLEX_INFORMATION_CLASS: u16 = 0x534C;
/// IEEE float stereo DAX audio at 24 kHz, the one admitted format: what a FLEX-6600 on
/// SmartSDR 4.3.16 sent on 2026-11-06 (type 3, 128 frames per packet, equal channels).
pub const DAX_FLOAT_24K: u16 = 0x03E3;
pub const DISCOVERY_CLASS: u16 = 0xFFFF;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WireError {
    LineTooLong,
    InvalidText,
    Malformed,
    TruncatedPacket,
    InvalidPacketLength,
    NotDaxAudio,
    UnsupportedFormat,
    NonfiniteSample,
    EmptyPayload,
    NotDiscovery,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ProtocolVersion {
    pub major: u8,
    pub minor: u8,
    pub a: u8,
    pub b: u32,
}
impl ProtocolVersion {
    fn parse(text: &str) -> Result<Self, WireError> {
        let mut parts = text.split('.');
        let mut next = || parts.next().ok_or(WireError::Malformed);
        let number = |s: &str| -> Result<u64, WireError> {
            if s.is_empty() || s.len() > 10 || !s.bytes().all(|b| b.is_ascii_digit()) {
                return Err(WireError::Malformed);
            }
            s.parse().map_err(|_| WireError::Malformed)
        };
        let byte = |s: &str| u8::try_from(number(s)?).map_err(|_| WireError::Malformed);
        let version = Self {
            major: byte(next()?)?,
            minor: byte(next()?)?,
            a: byte(next()?)?,
            b: u32::try_from(number(next()?)?).map_err(|_| WireError::Malformed)?,
        };
        if parts.next().is_some() {
            return Err(WireError::Malformed);
        }
        Ok(version)
    }
}
impl std::fmt::Display for ProtocolVersion {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}.{}.{}", self.major, self.minor, self.a, self.b)
    }
}

/// One radio-to-client line.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Line {
    Version(ProtocolVersion),
    Handle(u32),
    Reply {
        sequence: u32,
        code: u32,
        message: String,
    },
    Status {
        handle: u32,
        status: Status,
    },
    Message {
        number: u32,
        text: String,
    },
}

/// `<object> <id> [word...] [key=value...]`, e.g. `slice 0 in_use=1 RF_frequency=14.074000`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Status {
    pub object: String,
    pub id: String,
    pub words: Vec<String>,
    pub pairs: Vec<(String, String)>,
}
impl Status {
    pub fn get(&self, key: &str) -> Option<&str> {
        // A repeated key keeps its last value, as a later field in one update supersedes.
        self.pairs
            .iter()
            .rev()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.as_str())
    }
    pub fn has_word(&self, word: &str) -> bool {
        self.words.iter().any(|w| w == word)
    }
}

fn hex(text: &str) -> Result<u32, WireError> {
    let digits = text
        .strip_prefix("0x")
        .or_else(|| text.strip_prefix("0X"))
        .unwrap_or(text);
    if digits.is_empty() || digits.len() > 8 || !digits.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(WireError::Malformed);
    }
    u32::from_str_radix(digits, 16).map_err(|_| WireError::Malformed)
}
/// A handle or stream identity: hexadecimal with an optional `0x` prefix.
pub fn parse_hex(text: &str) -> Option<u32> {
    hex(text).ok()
}
fn decimal(text: &str) -> Result<u32, WireError> {
    if text.is_empty() || text.len() > 10 || !text.bytes().all(|b| b.is_ascii_digit()) {
        return Err(WireError::Malformed);
    }
    text.parse().map_err(|_| WireError::Malformed)
}

pub fn parse_status(body: &str) -> Result<Status, WireError> {
    let mut words = body.split(' ').filter(|w| !w.is_empty());
    let object = words.next().ok_or(WireError::Malformed)?.to_owned();
    let id = words.next().unwrap_or("").to_owned();
    let mut status = Status {
        object,
        id,
        ..Status::default()
    };
    for word in words {
        match word.split_once('=') {
            Some((key, value)) if !key.is_empty() => {
                status.pairs.push((key.to_owned(), value.to_owned()))
            }
            Some(_) => return Err(WireError::Malformed),
            None => status.words.push(word.to_owned()),
        }
    }
    Ok(status)
}

/// Parses one line without its terminator.
pub fn parse_line(line: &str) -> Result<Line, WireError> {
    let mut chars = line.chars();
    let kind = chars.next().ok_or(WireError::Malformed)?;
    let rest = chars.as_str();
    match kind {
        'V' => Ok(Line::Version(ProtocolVersion::parse(rest)?)),
        'H' => Ok(Line::Handle(hex(rest)?)),
        'R' => {
            let mut fields = rest.splitn(4, '|');
            let sequence = decimal(fields.next().ok_or(WireError::Malformed)?)?;
            let code = hex(fields.next().ok_or(WireError::Malformed)?)?;
            let message = fields.next().ok_or(WireError::Malformed)?.to_owned();
            Ok(Line::Reply {
                sequence,
                code,
                message,
            })
        }
        'S' => {
            let (handle, body) = rest.split_once('|').ok_or(WireError::Malformed)?;
            Ok(Line::Status {
                handle: hex(handle)?,
                status: parse_status(body)?,
            })
        }
        'M' => {
            let (number, text) = rest.split_once('|').ok_or(WireError::Malformed)?;
            Ok(Line::Message {
                number: hex(number)?,
                text: text.to_owned(),
            })
        }
        _ => Err(WireError::Malformed),
    }
}

/// `C<sequence>|<command>\n`. Commands are fixed typed texts; separators are refused.
pub fn command(sequence: u32, text: &str) -> Result<String, WireError> {
    if text.is_empty()
        || !text.bytes().all(|b| (0x20..0x7f).contains(&b) && b != b'|')
        || sequence == 0
        || sequence > i32::MAX as u32
    {
        return Err(WireError::Malformed);
    }
    let line = format!("C{sequence}|{text}\n");
    if line.len() > MAX_COMMAND {
        return Err(WireError::LineTooLong);
    }
    Ok(line)
}

/// Splits a byte stream into bounded lines. A CR immediately before LF is dropped.
#[derive(Default)]
pub struct LineBuffer {
    pending: Vec<u8>,
}
impl LineBuffer {
    pub fn push(&mut self, bytes: &[u8], lines: &mut Vec<String>) -> Result<(), WireError> {
        for &byte in bytes {
            if byte == b'\n' {
                let mut line = std::mem::take(&mut self.pending);
                if line.last() == Some(&b'\r') {
                    line.pop();
                }
                let text = String::from_utf8(line).map_err(|_| WireError::InvalidText)?;
                if text.chars().any(char::is_control) {
                    return Err(WireError::InvalidText);
                }
                lines.push(text);
            } else {
                // The LF itself is counted in MAX_LINE.
                if self.pending.len() + 1 >= MAX_LINE {
                    return Err(WireError::LineTooLong);
                }
                self.pending.push(byte);
            }
        }
        Ok(())
    }
    pub fn partial(&self) -> bool {
        !self.pending.is_empty()
    }
}

/// The parsed VITA-49 preamble of one datagram; the payload excludes any trailer.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Vita<'a> {
    pub packet_type: u8,
    pub class_present: bool,
    pub trailer_present: bool,
    pub tsi: u8,
    pub tsf: u8,
    pub packet_count: u8,
    pub words: u16,
    pub stream_id: Option<u32>,
    pub oui: Option<u32>,
    pub information_class: Option<u16>,
    pub packet_class: Option<u16>,
    pub integer_time: Option<u32>,
    pub fractional_time: Option<u64>,
    pub payload: &'a [u8],
}

pub fn parse_vita(bytes: &[u8]) -> Result<Vita<'_>, WireError> {
    if bytes.len() > MAX_DATAGRAM {
        return Err(WireError::InvalidPacketLength);
    }
    let word = |at: usize| -> Result<u32, WireError> {
        bytes
            .get(at..at + 4)
            .map(|b| u32::from_be_bytes([b[0], b[1], b[2], b[3]]))
            .ok_or(WireError::TruncatedPacket)
    };
    let header = word(0)?;
    let packet_type = (header >> 28) as u8;
    let class_present = header & (1 << 27) != 0;
    let trailer_present = header & (1 << 26) != 0;
    let tsi = ((header >> 22) & 3) as u8;
    let tsf = ((header >> 20) & 3) as u8;
    let packet_count = ((header >> 16) & 15) as u8;
    let words = (header & 0xffff) as u16;
    let mut at = 4;
    let stream_id = if matches!(packet_type, 1 | 3) {
        at += 4;
        Some(word(4)?)
    } else {
        None
    };
    let (mut oui, mut information_class, mut packet_class) = (None, None, None);
    if class_present {
        oui = Some(word(at)? & 0x00ff_ffff);
        let classes = word(at + 4)?;
        information_class = Some((classes >> 16) as u16);
        packet_class = Some(classes as u16);
        at += 8;
    }
    let integer_time = if tsi != 0 {
        at += 4;
        Some(word(at - 4)?)
    } else {
        None
    };
    let fractional_time = if tsf != 0 {
        at += 8;
        Some((u64::from(word(at - 8)?) << 32) | u64::from(word(at - 4)?))
    } else {
        None
    };
    let trailer = if trailer_present { 4 } else { 0 };
    if usize::from(words) * 4 != bytes.len() {
        // The declared size is authoritative; a short or padded datagram is refused.
        return Err(if bytes.len() < at + trailer {
            WireError::TruncatedPacket
        } else {
            WireError::InvalidPacketLength
        });
    }
    if bytes.len() < at + trailer {
        return Err(WireError::TruncatedPacket);
    }
    Ok(Vita {
        packet_type,
        class_present,
        trailer_present,
        tsi,
        tsf,
        packet_count,
        words,
        stream_id,
        oui,
        information_class,
        packet_class,
        integer_time,
        fractional_time,
        payload: &bytes[at..bytes.len() - trailer],
    })
}

/// Decodes one DAX receive packet: 24 kHz stereo frames of big-endian IEEE float32.
/// Returns interleaved samples (channel 0, channel 1, ...).
pub fn dax_samples(packet: &Vita<'_>) -> Result<Vec<f32>, WireError> {
    if packet.packet_type != 3
        || packet.oui != Some(FLEX_OUI)
        || packet.information_class != Some(FLEX_INFORMATION_CLASS)
    {
        return Err(WireError::NotDaxAudio);
    }
    if packet.packet_class != Some(DAX_FLOAT_24K) {
        // 48/96 kHz float and reduced-bandwidth integer DAX use other rules.
        return Err(WireError::UnsupportedFormat);
    }
    if packet.payload.is_empty() {
        return Err(WireError::EmptyPayload);
    }
    if !packet.payload.len().is_multiple_of(8) {
        return Err(WireError::InvalidPacketLength);
    }
    packet
        .payload
        .as_chunks::<4>()
        .0
        .iter()
        .map(|b| {
            let value = f32::from_be_bytes(*b);
            if value.is_finite() {
                Ok(value)
            } else {
                Err(WireError::NonfiniteSample)
            }
        })
        .collect()
}

/// One discovery announcement. Only the fields this backend uses are retained.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Discovery {
    pub serial: String,
    pub model: Option<String>,
    pub firmware: Option<String>,
    pub ip: Option<std::net::Ipv4Addr>,
    pub port: Option<u16>,
    pub available_clients: Option<u32>,
    pub available_slices: Option<u32>,
}

/// Radio facts from the reply to `info`: `model="FLEX-6600",chassis_serial="...",software_ver=...`.
pub fn parse_info(reply: &str) -> Discovery {
    let mut found = Discovery::default();
    for pair in reply.split(',') {
        let Some((key, value)) = pair.split_once('=') else {
            continue;
        };
        let value = value.trim_matches('"');
        let bounded = (!value.is_empty() && value.len() <= 64).then(|| value.to_owned());
        match key {
            "chassis_serial" => found.serial = bounded.unwrap_or_default(),
            "model" => found.model = bounded,
            "software_ver" => found.firmware = bounded,
            _ => {}
        }
    }
    found
}

pub fn parse_discovery(bytes: &[u8]) -> Result<Discovery, WireError> {
    let packet = parse_vita(bytes)?;
    if packet.packet_type != 3
        || packet.oui != Some(FLEX_OUI)
        || packet.packet_class != Some(DISCOVERY_CLASS)
    {
        return Err(WireError::NotDiscovery);
    }
    let end = packet
        .payload
        .iter()
        .position(|b| *b == 0)
        .unwrap_or(packet.payload.len());
    let text = std::str::from_utf8(&packet.payload[..end]).map_err(|_| WireError::InvalidText)?;
    let mut found = Discovery::default();
    for pair in text.split(' ').filter(|w| !w.is_empty()) {
        let Some((key, value)) = pair.split_once('=') else {
            continue;
        };
        let bounded = || (!value.is_empty() && value.len() <= 64).then(|| value.to_owned());
        match key {
            "serial" => found.serial = bounded().ok_or(WireError::Malformed)?,
            "model" => found.model = bounded(),
            "version" => found.firmware = bounded(),
            "ip" => found.ip = value.parse().ok(),
            "port" => found.port = value.parse().ok().filter(|p| *p != 0),
            "available_clients" => found.available_clients = value.parse().ok(),
            "available_slices" => found.available_slices = value.parse().ok(),
            _ => {}
        }
    }
    if found.serial.is_empty() {
        return Err(WireError::Malformed);
    }
    Ok(found)
}

#[cfg(test)]
#[path = "wire_tests.rs"]
mod tests;
