//! 77-bit FT8 message packing: the inverse of `decoder::unpack` for the supported
//! families, following WSJT-X 3.3.0-beta5 packjt77.f90/packjt77_grammar.f90.
//! See WstxMessageEncode::PackMessage. Every result is unpacked again and must render the
//! normalized input; WSJT-X's truncating free-text fallback is not reproduced.
use crate::decoder::{PayloadStatus, arrl_sections, rtty_exchanges, unpack};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Family {
    /// i3=1
    Standard,
    /// i3=2 (a /P call)
    Portable,
    /// i3=4
    Nonstandard,
    /// i3=0, n3=0
    FreeText,
    /// i3=0, n3=5
    Telemetry,
    /// i3=0, n3=3/4 (ARRL Field Day, #24 S2b)
    FieldDay,
    /// i3=3 (ARRL RTTY / FT Roundup, #24 S2b)
    RttyRoundup,
    /// i3=5 (EU VHF contest, #99)
    EuVhf,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PackError {
    Empty,
    TooLong,
    InvalidText,
    UnsupportedFamily,
    NotExact,
    RoundTripMismatch,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Packed {
    pub bits: [u8; 77],
    pub i3: u8,
    pub n3: Option<u8>,
    pub family: Family,
    /// The normalized message, as the receiver renders it.
    pub text: String,
}

const NTOKENS: u128 = 2_063_592;
const MAX22: u128 = 4_194_304;
const MAXGRID4: u128 = 32_400;
const BASE38: &[u8] = b" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ/";
const TEXT42: &[u8] = b" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ+-./?";
pub fn pack(message: &str) -> Result<Packed, PackError> {
    let text = normalize(message)?;
    let words = text.split(' ').collect::<Vec<_>>();
    let special = matches!(words[0], "CQ" | "DE" | "QRZ");
    if !special {
        // A ';' is DXpedition 0.1 unless it is the one leading "TU;" of RTTY Roundup.
        let tu = words[0] == "TU;" && text.matches(';').count() == 1;
        if text.contains(';') && !tu {
            return Err(PackError::UnsupportedFamily);
        }
        if let Some(bits) = field_day(&words)? {
            return checked(text, Family::FieldDay, bits);
        }
        if words.len() == 1
            && words[0].len() <= 18
            && words[0].bytes().all(|c| c.is_ascii_hexdigit())
        {
            if words[0].len() < 18 {
                return Err(PackError::NotExact);
            }
            let value = u128::from_str_radix(words[0], 16).expect("hexadecimal");
            if value >> 71 == 0 {
                return checked(
                    text,
                    Family::Telemetry,
                    fields(&[(value, 71), (5, 3), (0, 3)]),
                );
            }
        }
    }
    if wspr(&words) {
        return Err(PackError::UnsupportedFamily);
    }
    // A structured candidate that fails the round trip falls through to the next
    // family, as WSJT-X take_candidate does.
    if let Some((family, bits)) = standard(&words)
        && let Ok(packed) = checked(text.clone(), family, bits)
    {
        return Ok(packed);
    }
    if let Some(bits) = rtty(&words)? {
        return checked(text, Family::RttyRoundup, bits);
    }
    if let Some(bits) = nonstandard(&words)
        && let Ok(packed) = checked(text.clone(), Family::Nonstandard, bits)
    {
        return Ok(packed);
    }
    // Type 5 is tried after type 4, as WSJT-X does (#99).
    if let Some(bits) = eu_vhf(&words)
        && let Ok(packed) = checked(text.clone(), Family::EuVhf, bits)
    {
        return Ok(packed);
    }
    if !text.bytes().all(|c| TEXT42.contains(&c)) {
        return Err(PackError::InvalidText);
    }
    if text.len() > 13 {
        return Err(PackError::TooLong);
    }
    let value = format!("{text:>13}")
        .bytes()
        .fold(0u128, |a, c| a * 42 + index(TEXT42, c));
    checked(
        text,
        Family::FreeText,
        fields(&[(value, 71), (0, 3), (0, 3)]),
    )
}

/// Upper case, NUL as blank, blank runs collapsed and trimmed (pack77_normalized_message).
fn normalize(message: &str) -> Result<String, PackError> {
    let mut out = String::new();
    for c in message.chars() {
        let c = if c == '\0' {
            ' '
        } else {
            c.to_ascii_uppercase()
        };
        if c == ' ' {
            if !out.is_empty() && !out.ends_with(' ') {
                out.push(' ');
            }
        } else if c.is_ascii_graphic() {
            out.push(c);
        } else {
            return Err(PackError::InvalidText);
        }
    }
    let out = out.trim_end().to_string();
    match out.len() {
        0 => Err(PackError::Empty),
        38.. => Err(PackError::TooLong),
        _ => Ok(out),
    }
}

/// The bits must unpack to the same tokens; a decoded `<...>` stands for an input
/// `<CALL>` of at most 11 characters (pack77_gate_message_checks).
fn checked(text: String, family: Family, bits: [u8; 77]) -> Result<Packed, PackError> {
    let payload = unpack(&bits);
    let rendered = payload
        .text
        .filter(|_| payload.status == PayloadStatus::Decoded)
        .ok_or(PackError::RoundTripMismatch)?
        .replace(" R -", " R-")
        .replace(" R +", " R+");
    let rendered = rendered.split_whitespace().collect::<Vec<_>>();
    let input = text.split(' ').collect::<Vec<_>>();
    let same = rendered.len() == input.len()
        && input
            .iter()
            .zip(&rendered)
            .all(|(a, b)| a == b || (*b == "<...>" && a.starts_with('<') && a.len() <= 13));
    if !same {
        return Err(PackError::RoundTripMismatch);
    }
    Ok(Packed {
        bits,
        i3: payload.i3,
        n3: payload.n3,
        family,
        text,
    })
}

fn fields(values: &[(u128, usize)]) -> [u8; 77] {
    let mut bits = [0; 77];
    let mut at = 0;
    for &(value, width) in values {
        debug_assert!(value >> width == 0);
        for i in (0..width).rev() {
            bits[at] = ((value >> i) & 1) as u8;
            at += 1;
        }
    }
    assert_eq!(at, 77);
    bits
}
fn index(alphabet: &[u8], c: u8) -> u128 {
    alphabet
        .iter()
        .position(|&a| a == c)
        .expect("checked alphabet") as u128
}
fn digits(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|c| c.is_ascii_digit())
}
fn letters(s: &str) -> bool {
    s.bytes().all(|c| c.is_ascii_uppercase())
}

/// ihashcall (shared with the station's hash table, WstxOfflineDecode::HashResolution).
fn hash(call: &str, m: u32) -> Option<u128> {
    crate::decoder::ihashcall(call, m).map(u128::from)
}
/// `<CALL>` hash token body (pack77_valid_hash_call_token).
fn hash_body(token: &str) -> Option<&str> {
    let body = token.strip_prefix('<')?.strip_suffix('>')?;
    (token.len() <= 13 && body.len() >= 3 && !body.contains(['<', '>'])).then_some(body)
}
/// pack77_c28_standard_shape.
fn standard_shape(t: &str) -> bool {
    let b = t.as_bytes();
    if !(3..=6).contains(&b.len()) || !b.iter().all(u8::is_ascii_alphanumeric) {
        return false;
    }
    let Some(area) = (1..b.len()).rev().find(|&i| b[i].is_ascii_digit()) else {
        return false;
    };
    let prefix = &t[..area];
    (area == 1 || area == 2)
        && prefix.bytes().any(|c| c.is_ascii_uppercase())
        && letters(&t[area + 1..])
        && t.len() - area - 1 <= 3
}
fn standard_call(t: &str) -> bool {
    standard_shape(t) && !t.starts_with('Q')
}
fn cq_modifier(t: &str) -> bool {
    (t.len() == 3 && digits(t)) || ((1..=4).contains(&t.len()) && letters(t))
}
fn c28_call(t: &str) -> u128 {
    let area = (1..t.len())
        .rev()
        .find(|&i| t.as_bytes()[i].is_ascii_digit())
        .unwrap();
    let six = format!(
        "{:<6}",
        if area == 1 {
            format!(" {t}")
        } else {
            t.to_string()
        }
    );
    let c = six.as_bytes();
    let a1 = index(b" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ", c[0]);
    let a2 = index(b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ", c[1]);
    let tail = c[3..]
        .iter()
        .fold(0, |a, &x| a * 27 + index(b" ABCDEFGHIJKLMNOPQRSTUVWXYZ", x));
    ((a1 * 36 + a2) * 10 + u128::from(c[2] - b'0')) * 27u128.pow(3) + tail + NTOKENS + MAX22
}

struct Slot {
    n28: u128,
    suffix: Option<char>,
    hash: bool,
    cq: bool,
}
/// pack77_parse_type12_call plus pack28 for the accepted forms.
fn slot(token: &str, special: bool) -> Option<Slot> {
    let plain = |n28, cq| Slot {
        n28,
        suffix: None,
        hash: false,
        cq,
    };
    if special {
        match token {
            "DE" => return Some(plain(0, false)),
            "QRZ" => return Some(plain(1, false)),
            "CQ" => return Some(plain(2, true)),
            _ => {}
        }
        if let Some(m) = token.strip_prefix("CQ_") {
            if !cq_modifier(m) {
                return None;
            }
            let n = if digits(m) {
                3 + m.parse::<u128>().ok()?
            } else {
                1003 + format!("{m:>4}").bytes().fold(0, |a, c| {
                    a * 27
                        + if c == b' ' {
                            0
                        } else {
                            u128::from(c - b'A' + 1)
                        }
                })
            };
            return Some(plain(n, true));
        }
    }
    if token.starts_with('<') || token.contains('>') {
        let body = hash_body(token)?;
        return Some(Slot {
            n28: NTOKENS + hash(body, 22)?,
            suffix: None,
            hash: true,
            cq: false,
        });
    }
    let (base, suffix) = match token.split_once('/') {
        Some((base, s @ ("R" | "P"))) if !base.is_empty() => (base, s.chars().next()),
        Some(_) => return None,
        None => (token, None),
    };
    standard_call(base).then(|| Slot {
        n28: c28_call(base),
        suffix,
        hash: false,
        cq: false,
    })
}
fn grid4(t: &str) -> Option<u128> {
    let b = t.as_bytes();
    (b.len() == 4
        && (b'A'..=b'R').contains(&b[0])
        && (b'A'..=b'R').contains(&b[1])
        && b[2].is_ascii_digit()
        && b[3].is_ascii_digit())
    .then(|| {
        u128::from(b[0] - b'A') * 1800
            + u128::from(b[1] - b'A') * 100
            + u128::from(b[2] - b'0') * 10
            + u128::from(b[3] - b'0')
    })
}
fn report(t: &str) -> Option<u128> {
    let b = t.as_bytes();
    if b.len() != 3 || !matches!(b[0], b'+' | b'-') || !digits(&t[1..]) {
        return None;
    }
    let snr: i32 = t.parse().ok()?;
    let index = match snr {
        -50..=-31 => snr + 101,
        -30..=50 => snr,
        _ => return None,
    } + 35;
    Some(MAXGRID4 + index as u128)
}
fn roger(t: &str) -> Option<u128> {
    ["RRR", "RR73", "73"]
        .iter()
        .position(|&r| r == t)
        .map(|i| i as u128 + 1)
}

/// Types 1 and 2 (pack77_parse_type12_source).
fn standard(w: &[&str]) -> Option<(Family, [u8; 77])> {
    if !(2..=5).contains(&w.len()) {
        return None;
    }
    let (first, second) = if w[0] == "CQ" && w.len() >= 3 && cq_modifier(w[1]) {
        (format!("CQ_{}", w[1]), 2)
    } else {
        (w[0].to_string(), 1)
    };
    let a = slot(&first, true)?;
    let b = slot(w.get(second)?, false)?;
    // A hashed call never pairs with a slashed call, including a bracketed one.
    let slashed = |t: &str| t.contains('/');
    if (a.cq && b.hash) || (a.hash && slashed(w[second])) || (b.hash && slashed(&first)) {
        return None;
    }
    if a.suffix.is_some() && b.suffix.is_some() && a.suffix != b.suffix {
        return None;
    }
    let tail = &w[second + 1..];
    let (r, exchange) = match tail {
        [] => (0, MAXGRID4 + 1),
        ["R", g] if !a.cq => (1, grid4(g)?),
        [t] => match (roger(t).filter(|_| !a.cq), grid4(t)) {
            (Some(i), _) => (0, MAXGRID4 + i + 1),
            (None, Some(g)) => (0, g),
            _ if a.cq => return None,
            _ => match t.strip_prefix('R') {
                Some(rest) if rest.starts_with(['+', '-']) => (1, report(rest)?),
                _ => (0, report(t)?),
            },
        },
        _ => return None,
    };
    let portable = a.suffix == Some('P') || b.suffix == Some('P');
    let i3 = if portable { 2 } else { 1 };
    let bits = fields(&[
        (a.n28, 28),
        (u128::from(a.suffix.is_some()), 1),
        (b.n28, 28),
        (u128::from(b.suffix.is_some()), 1),
        (r, 1),
        (exchange, 15),
        (i3, 3),
    ]);
    Some((
        if portable {
            Family::Portable
        } else {
            Family::Standard
        },
        bits,
    ))
}

/// Type 4 (pack77_parse_type4_source).
fn nonstandard(w: &[&str]) -> Option<[u8; 77]> {
    let c11 = |t: &str| {
        (1..=11).contains(&t.len()) && t.bytes().all(|c| BASE38.contains(&c)) && !standard_call(t)
    };
    let (hashed, call, flip, cq, tail) = match w {
        ["CQ", call] if hash_body(call).is_none() && call.len() >= 5 && c11(call) => {
            (*call, *call, 0, 1, 0)
        }
        ["CQ", ..] => return None,
        [first, second, rest @ ..] if rest.len() <= 1 => {
            let tail = match rest {
                [t] => roger(t)?,
                _ => 0,
            };
            match (hash_body(first), hash_body(second)) {
                (Some(body), None) if c11(second) => (body, *second, 0, 0, tail),
                (None, Some(body)) if c11(first) => (body, *first, 1, 0, tail),
                _ => return None,
            }
        }
        _ => return None,
    };
    let n58 = format!("{call:>11}")
        .bytes()
        .fold(0, |a, c| a * 38 + index(BASE38, c));
    Some(fields(&[
        (hash(hashed, 12)?, 12),
        (n58, 58),
        (flip, 1),
        (tail, 2),
        (cq, 1),
        (4, 3),
    ]))
}

/// pack77_valid_c28_call_slot without hash tokens, then lower_c28_slot: a standard call
/// is its c28 value; any other slot WSJT-X sends as a 22-bit hash rendered <CALL>, an
/// altered message (notExact); a slot over 11 characters does not fit and is no match.
fn contest_call(t: &str) -> Option<Result<u128, PackError>> {
    let n = t.len();
    if !(3..=13).contains(&n)
        || !t
            .bytes()
            .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == b'/')
    {
        return None;
    }
    if standard_call(t) {
        return Some(Ok(c28_call(t)));
    }
    let slash = t.find('/')?;
    (slash >= 1 && slash < n - 1 && t.matches('/').count() == 1 && n <= 11)
        .then_some(Err(PackError::NotExact))
}
/// Both contest call slots, or no match.
fn contest_calls(a: &str, b: &str) -> Option<Result<(u128, u128), PackError>> {
    let (a, b) = (contest_call(a)?, contest_call(b)?);
    Some(a.and_then(|a| b.map(|b| (a, b))))
}

/// Type 0.3/0.4 ARRL Field Day (pack77_parse_field_day_source, pack77_03_candidate).
fn field_day(w: &[&str]) -> Result<Option<[u8; 77]>, PackError> {
    if !(4..=5).contains(&w.len()) || (w.len() == 5 && w[2] != "R") {
        return Ok(None);
    }
    let Some(section) = arrl_sections().iter().position(|s| s == w[w.len() - 1]) else {
        return Ok(None);
    };
    let exchange = w[w.len() - 2];
    let (count, class) = exchange.split_at(exchange.len().saturating_sub(1));
    let Some(class) = ["A", "B", "C", "D", "E", "F"]
        .iter()
        .position(|&c| c == class)
    else {
        return Ok(None);
    };
    if exchange.len() < 2 || (exchange.len() > 2 && exchange.starts_with('0')) || !digits(count) {
        return Ok(None);
    }
    let Some(count) = count.parse::<u128>().ok().filter(|n| (1..=32).contains(n)) else {
        return Ok(None);
    };
    let Some(calls) = contest_calls(w[0], w[1]) else {
        return Ok(None);
    };
    let (a, b) = calls?;
    let (n3, intx) = if count <= 16 {
        (3, count - 1)
    } else {
        (4, count - 17)
    };
    Ok(Some(fields(&[
        (a, 28),
        (b, 28),
        (u128::from(w.len() == 5), 1),
        (intx, 4),
        (class as u128, 3),
        (section as u128 + 1, 7),
        (n3, 3),
        (0, 3),
    ])))
}

/// Type 3 ARRL RTTY / FT Roundup (pack77_parse_type3_source, pack77_3_candidate).
fn rtty(w: &[&str]) -> Result<Option<[u8; 77]>, PackError> {
    if !(4..=6).contains(&w.len()) {
        return Ok(None);
    }
    let tu = usize::from(w[0] == "TU;");
    let r = usize::from(w.get(2 + tu) == Some(&"R"));
    let report = 2 + tu + r;
    if report + 2 != w.len() {
        return Ok(None);
    }
    let rst = w[report].as_bytes();
    if rst.len() != 3 || rst[0] != b'5' || !(b'2'..=b'9').contains(&rst[1]) || rst[2] != b'9' {
        return Ok(None);
    }
    let exchange = w[report + 1];
    let nexch = if exchange.len() == 4 && digits(exchange) {
        match exchange.parse::<u128>() {
            Ok(n @ 1..=7999) => n,
            _ => return Ok(None),
        }
    } else if let Some(i) = rtty_exchanges().iter().position(|m| m == exchange) {
        8001 + i as u128
    } else {
        return Ok(None);
    };
    let Some(calls) = contest_calls(w[tu], w[1 + tu]) else {
        return Ok(None);
    };
    let (a, b) = calls?;
    Ok(Some(fields(&[
        (tu as u128, 1),
        (a, 28),
        (b, 28),
        (r as u128, 1),
        (u128::from(rst[1] - b'2'), 3),
        (nexch, 13),
        (3, 3),
    ])))
}

/// Type 5 EU VHF contest (pack77_parse_type5_source, pack77_5_candidate,
/// encode_pack77_type5; #99): "<CALL1> <CALL2> [R] 5nSSSS GRID6", both calls hashed
/// (h12, h22), n 2-9, serial 1-2047, GRID6 AA00AA..RR99XX.
fn eu_vhf(w: &[&str]) -> Option<[u8; 77]> {
    let (first, second, r, exchange, grid) = match w {
        [a, b, x, g] => (*a, *b, 0, *x, *g),
        [a, b, "R", x, g] => (*a, *b, 1, *x, *g),
        _ => return None,
    };
    let (first, second) = (hash_body(first)?, hash_body(second)?);
    let e = exchange.as_bytes();
    if e.len() != 6 || !digits(exchange) || e[0] != b'5' || !(b'2'..=b'9').contains(&e[1]) {
        return None;
    }
    let serial = exchange[2..].parse::<u128>().ok()?;
    if !(1..=2047).contains(&serial) {
        return None;
    }
    let g = grid.as_bytes();
    if g.len() != 6 || !g[4..].iter().all(|c| (b'A'..=b'X').contains(c)) {
        return None;
    }
    let grid6 = (grid4(&grid[..4])? * 24 + u128::from(g[4] - b'A')) * 24 + u128::from(g[5] - b'A');
    Some(fields(&[
        (hash(first, 12)?, 12),
        (hash(second, 22)?, 22),
        (r, 1),
        (u128::from(e[1] - b'2'), 3),
        (serial, 11),
        (grid6, 25),
        (5, 3),
    ]))
}

/// The WSPR shapes WSJT-X tries before type 1 (pack77_parse_wspr_source matched_shape).
fn wspr(w: &[&str]) -> bool {
    match w {
        [_, g, dbm] => grid4(g).is_some() && digits(dbm),
        [call, dbm] => call.contains('/') && digits(dbm),
        _ => false,
    }
}
