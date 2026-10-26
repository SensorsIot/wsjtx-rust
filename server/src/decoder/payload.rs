use serde::{Deserialize, Serialize};
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Call {
    pub kind: String,
    pub text: Option<String>,
    pub hash_bits: Option<u8>,
    pub hash_value: Option<u32>,
}
impl Call {
    fn named(text: String, token: bool) -> Self {
        Self {
            kind: if token { "token" } else { "call" }.into(),
            text: Some(text),
            hash_bits: None,
            hash_value: None,
        }
    }
    fn hashed(bits: u8, n: u32) -> Self {
        Self {
            kind: "hash".into(),
            text: None,
            hash_bits: Some(bits),
            hash_value: Some(n),
        }
    }
    fn display(&self) -> &str {
        self.text.as_deref().unwrap_or("<...>")
    }
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "snake_case")]
pub enum Exchange {
    Grid(String),
    Blank(()),
    Roger(String),
    Report(i32),
    State(String),
    Serial(u32),
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Fields {
    FreeText {
        value: String,
    },
    Telemetry {
        value: String,
    },
    Standard {
        to: Call,
        from: Call,
        ack: bool,
        exchange: Exchange,
    },
    Dxpedition {
        first: Call,
        second: Call,
        hashed: Call,
        report: i32,
    },
    FieldDay {
        to: Call,
        from: Call,
        ack: bool,
        transmitters: u32,
        #[serde(rename = "class")]
        class_name: String,
        section: String,
    },
    Rtty {
        tu: bool,
        to: Call,
        from: Call,
        ack: bool,
        report: u32,
        exchange: Exchange,
    },
    Nonstandard {
        full_call: Call,
        hashed_call: Call,
        hash_second: bool,
        cq: bool,
        roger: String,
    },
    Vhf {
        to: Call,
        from: Call,
        ack: bool,
        report: u32,
        serial: u32,
        grid: String,
    },
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PayloadStatus {
    Decoded,
    Unsupported,
    InvalidPayload,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Payload {
    pub status: PayloadStatus,
    pub payload77: String,
    pub i3: u8,
    pub n3: Option<u8>,
    pub text: Option<String>,
    pub fields: Option<Fields>,
}
struct Bits<'a>(&'a [u8; 77]);
impl Bits<'_> {
    fn get(&self, s: usize, n: usize) -> u128 {
        self.0[s..s + n].iter().fold(0, |a, &b| a * 2 + b as u128)
    }
}
fn radix(mut n: u128, alphabets: &[&[u8]]) -> Option<String> {
    let mut out = vec![0; alphabets.len()];
    for (i, a) in alphabets.iter().enumerate().rev() {
        out[i] = a[(n % a.len() as u128) as usize];
        n /= a.len() as u128;
    }
    if n != 0 {
        None
    } else {
        Some(String::from_utf8(out).ok()?)
    }
}
fn c28(n: u32) -> Option<Call> {
    if n < 3 {
        return Some(Call::named(["DE", "QRZ", "CQ"][n as usize].into(), true));
    }
    if n <= 1002 {
        return Some(Call::named(format!("CQ {:03}", n - 3), true));
    }
    if n < 2063592 {
        let s = radix(
            (n - 1003) as u128,
            &[&b" ABCDEFGHIJKLMNOPQRSTUVWXYZ"[..]; 4],
        )?;
        let s = s.trim_start();
        if s.is_empty() || s.contains(' ') {
            return None;
        }
        return Some(Call::named(format!("CQ {s}"), true));
    }
    if n < 6257896 {
        return Some(Call::hashed(22, n - 2063592));
    }
    let s = radix(
        (n - 6257896) as u128,
        &[
            b" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ",
            b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ",
            b"0123456789",
            b" ABCDEFGHIJKLMNOPQRSTUVWXYZ",
            b" ABCDEFGHIJKLMNOPQRSTUVWXYZ",
            b" ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        ],
    )?;
    let bytes = s.as_bytes();
    if !bytes[..2].iter().any(u8::is_ascii_alphabetic) {
        return None;
    }
    let suffix = s[3..].trim_end();
    if suffix.is_empty() || suffix.contains(' ') {
        return None;
    }
    Some(Call::named(s.trim().into(), false))
}
fn grid(mut n: u32, six: bool) -> Option<String> {
    let rad: &[u32] = if six {
        &[18, 18, 10, 10, 24, 24]
    } else {
        &[18, 18, 10, 10]
    };
    let mut out = vec![0; rad.len()];
    for i in (0..rad.len()).rev() {
        out[i] = (n % rad[i]) as u8 + if i == 2 || i == 3 { b'0' } else { b'A' };
        n /= rad[i];
    }
    if n > 0 {
        None
    } else {
        String::from_utf8(out).ok()
    }
}
fn lists(text: &str, index: u32) -> Option<String> {
    let a: Vec<String> = serde_json::from_str(text).ok()?;
    a.get(index.checked_sub(1)? as usize).cloned()
}
fn suffix(c: &mut Call, on: bool, s: &str) -> Option<()> {
    if on {
        if c.kind != "call" {
            return None;
        }
        c.text.as_mut()?.push_str(s);
    }
    Some(())
}
fn decode(b: &Bits<'_>, i3: u8, n3: u8) -> Option<(String, Fields)> {
    let g = |s, n| b.get(s, n) as u32;
    let ackword = |a: bool| if a { " R" } else { "" };
    match (i3, n3) {
        (0, 0) => {
            let s = radix(
                b.get(0, 71),
                &[&b" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ+-./?"[..]; 13],
            )?;
            let s = s.trim_end().to_string();
            if s.trim().is_empty() {
                return None;
            }
            Some((s.clone(), Fields::FreeText { value: s }))
        }
        (0, 5) => {
            let s = format!("{:018X}", b.get(0, 71));
            Some((s.clone(), Fields::Telemetry { value: s }))
        }
        (0, 1) => {
            let first = c28(g(0, 28))?;
            let second = c28(g(28, 28))?;
            let hashed = Call::hashed(10, g(56, 10));
            let report = 2 * g(66, 5) as i32 - 30;
            Some((
                format!(
                    "{} RR73; {} <...> {report:+03}",
                    first.display(),
                    second.display()
                ),
                Fields::Dxpedition {
                    first,
                    second,
                    hashed,
                    report,
                },
            ))
        }
        (0, 3 | 4) => {
            let to = c28(g(0, 28))?;
            let from = c28(g(28, 28))?;
            let ack = g(56, 1) != 0;
            let transmitters = g(57, 4) + 1 + if n3 == 4 { 16 } else { 0 };
            let cl = g(61, 3);
            if cl > 5 {
                return None;
            }
            let class_name = ((b'A' + cl as u8) as char).to_string();
            let section = lists(
                include_str!("../../../fixtures/decoder/protocol-data/arrl_rac_sections.json"),
                g(64, 7),
            )?;
            Some((
                format!(
                    "{} {}{} {transmitters}{class_name} {section}",
                    to.display(),
                    from.display(),
                    ackword(ack)
                ),
                Fields::FieldDay {
                    to,
                    from,
                    ack,
                    transmitters,
                    class_name,
                    section,
                },
            ))
        }
        (1 | 2, _) => {
            let mut to = c28(g(0, 28))?;
            let mut from = c28(g(29, 28))?;
            suffix(&mut to, g(28, 1) != 0, if i3 == 1 { "/R" } else { "/P" })?;
            suffix(&mut from, g(57, 1) != 0, if i3 == 1 { "/R" } else { "/P" })?;
            let ack = g(58, 1) != 0;
            let raw = g(59, 15);
            let (s, exchange) = match raw {
                0..=32399 => {
                    let s = grid(raw, false)?;
                    (s.clone(), Exchange::Grid(s))
                }
                32401 => (String::new(), Exchange::Blank(())),
                32402..=32404 => {
                    let s = ["RRR", "RR73", "73"][(raw - 32402) as usize].to_string();
                    (s.clone(), Exchange::Roger(s))
                }
                32405..=32505 => {
                    let r = raw as i32 - if raw <= 32485 { 32435 } else { 32536 };
                    (format!("{r:+03}"), Exchange::Report(r))
                }
                _ => return None,
            };
            let text = if s.is_empty() {
                format!("{} {}{}", to.display(), from.display(), ackword(ack))
            } else {
                format!("{} {}{} {s}", to.display(), from.display(), ackword(ack))
            };
            Some((
                text,
                Fields::Standard {
                    to,
                    from,
                    ack,
                    exchange,
                },
            ))
        }
        (3, _) => {
            let tu = g(0, 1) != 0;
            let to = c28(g(1, 28))?;
            let from = c28(g(29, 28))?;
            let ack = g(57, 1) != 0;
            let report = 529 + g(58, 3) * 10;
            let raw = g(61, 13);
            let (s, exchange) = if raw < 8000 {
                (format!("{raw:04}"), Exchange::Serial(raw))
            } else {
                let s = lists(
                    include_str!("../../../fixtures/decoder/protocol-data/states_provinces.json"),
                    raw.checked_sub(8000)?,
                )?;
                (s.clone(), Exchange::State(s))
            };
            Some((
                format!(
                    "{}{} {}{} {report} {s}",
                    if tu { "TU; " } else { "" },
                    to.display(),
                    from.display(),
                    ackword(ack)
                ),
                Fields::Rtty {
                    tu,
                    to,
                    from,
                    ack,
                    report,
                    exchange,
                },
            ))
        }
        (4, _) => {
            let hashed_call = Call::hashed(12, g(0, 12));
            let s = radix(
                b.get(12, 58),
                &[&b" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ/"[..]; 11],
            )?;
            let s = s.trim();
            if s.is_empty() || s.contains(' ') {
                return None;
            }
            let full_call = Call::named(s.into(), false);
            let hash_second = g(70, 1) != 0;
            let roger = ["", "RRR", "RR73", "73"][g(71, 2) as usize].to_string();
            let cq = g(73, 1) != 0;
            let text = if cq {
                format!("CQ {}", full_call.display())
            } else {
                format!(
                    "{} {}{}",
                    if hash_second {
                        full_call.display()
                    } else {
                        "<...>"
                    },
                    if hash_second {
                        "<...>"
                    } else {
                        full_call.display()
                    },
                    if roger.is_empty() {
                        String::new()
                    } else {
                        format!(" {roger}")
                    }
                )
            };
            Some((
                text,
                Fields::Nonstandard {
                    full_call,
                    hashed_call,
                    hash_second,
                    cq,
                    roger,
                },
            ))
        }
        (5, _) => {
            let to = Call::hashed(12, g(0, 12));
            let from = Call::hashed(22, g(12, 22));
            let ack = g(34, 1) != 0;
            let report = 52 + g(35, 3);
            let serial = g(38, 11);
            let grid = grid(g(49, 25), true)?;
            Some((
                format!("<...> <...>{} {report}{serial:04} {grid}", ackword(ack)),
                Fields::Vhf {
                    to,
                    from,
                    ack,
                    report,
                    serial,
                    grid,
                },
            ))
        }
        _ => None,
    }
}
pub fn unpack(bits: &[u8; 77]) -> Payload {
    let b = Bits(bits);
    let i3 = b.get(74, 3) as u8;
    let n3 = if i3 == 0 {
        Some(b.get(71, 3) as u8)
    } else {
        None
    };
    let mut p = Payload {
        status: PayloadStatus::InvalidPayload,
        payload77: bits
            .iter()
            .map(|&x| if x == 0 { '0' } else { '1' })
            .collect(),
        i3,
        n3,
        text: None,
        fields: None,
    };
    if bits.iter().any(|&x| x > 1) {
        return p;
    }
    if i3 >= 6 || i3 == 0 && matches!(n3, Some(2 | 6 | 7)) {
        p.status = PayloadStatus::Unsupported;
        return p;
    }
    if let Some((text, fields)) = decode(&b, i3, n3.unwrap_or(0)) {
        p.status = PayloadStatus::Decoded;
        p.text = Some(text);
        p.fields = Some(fields);
    }
    p
}
