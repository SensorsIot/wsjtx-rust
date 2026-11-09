//! CR #10 persistent contact log (WstxContact::LogRecord, SaveContact, UpdateLogbook,
//! ExportAdi, ContactHistory, WorkedBeforeQuery, AdiLimits). The selected profile's
//! `contacts.adi` is ADIF 3.1.8 ADI, always written as a complete new file in the
//! profile directory, flushed and atomically replaced. The in-memory view changes only
//! after a successful replace. Field order and spelling follow WSJT-X
//! logbook/AdifQso.cpp so WSJT-X and other logging programs can import the file.
use serde_json::{Value, json};
use std::{
    collections::{HashMap, VecDeque},
    fs::{self, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

#[cfg(test)]
#[path = "logbook_tests.rs"]
pub(crate) mod tests;

pub const IMPORT_BYTES_MAX: u64 = 67_108_864;
pub const IMPORT_RECORDS_MAX: usize = 100_000;
pub const FIELD_CHARACTERS_MAX: usize = 1024;
pub const FIELD_NAME_CHARACTERS_MAX: usize = 64;
pub const IMPORT_CHUNK_BYTES_MAX: usize = 16_384;
pub const HISTORY_PAGE_RECORDS_MAX: usize = 10;
pub const HISTORY_PAGE_BYTES_MAX: usize = 16_384;
pub const FILE_NAME: &str = "contacts.adi";
const ID_FIELD: &str = "app_wstxrust_contact_id";
/// #10 UpdateLogbook source marker of a record added from another logger's export.
const SOURCE_FIELD: &str = "app_wstxrust_source";
/// #10 consolidation window: a record this close to a stored one is already present.
const CONSOLIDATION_SECONDS: i64 = 120;
/// #10 at most this many skip/drop reason groups are listed in the update summary.
const REASON_GROUPS: usize = 16;
const RECEIPTS: usize = 16;
const IMPORT_IDLE: Duration = Duration::from_secs(60);

/// Supported LogRecord fields in WSJT-X to_adif order (contact id follows them).
pub const FIELDS: [&str; 31] = [
    "call",
    "gridsquare",
    "mode",
    "submode",
    "rst_sent",
    "rst_rcvd",
    "qso_date",
    "time_on",
    "qso_date_off",
    "time_off",
    "band",
    "freq",
    "station_callsign",
    "my_gridsquare",
    "tx_pwr",
    "comment",
    // Contest exchanges in AdifQso::to_adif order (#24 S2b, LogRecord).
    "stx",
    "stx_string",
    "srx",
    "contest_id",
    "srx_string",
    "class",
    "arrl_sect",
    "state",
    // QSO confirmation (#10, operator 2026-11-04, ADIF 3.1 QSL Rcvd / QSL Via): kept by
    // UpdateLogbook and only ever upgraded to a confirmation, never removed.
    "lotw_qsl_rcvd",
    "lotw_qslrdate",
    "qsl_rcvd",
    "qslrdate",
    "qsl_rcvd_via",
    "eqsl_qsl_rcvd",
    "eqsl_qslrdate",
];
const CALL: usize = 0;
const GRID: usize = 1;
const MODE: usize = 2;
const SUBMODE: usize = 3;
const QSO_DATE: usize = 6;
const TIME_ON: usize = 7;
const QSO_DATE_OFF: usize = 8;
const TIME_OFF: usize = 9;
const BAND: usize = 10;
const FREQ: usize = 11;
/// #97 the ADIF STATE (WstxStrategy::UsStateOf).
const STATE: usize = 23;
/// The contest fields are FIELDS[CONTEST..CONFIRMATION].
const CONTEST: usize = 16;
/// The confirmation fields are FIELDS[CONFIRMATION..]; the LogRecord fields before them.
const CONFIRMATION: usize = 24;
/// #10 confirmation channels (LoTW, paper QSL, eQSL): received status, received date and
/// received via indexes.
const CHANNELS: [(usize, usize, Option<usize>); 3] =
    [(24, 25, None), (26, 27, Some(28)), (29, 30, None)];

/// ADIF 3.1.8 band enumeration with inclusive limits in Hz.
/// #97 a band name of the ADIF band enumeration, in lower case (WstxStrategy::StrategyBands).
pub fn is_band(name: &str) -> bool {
    BANDS.iter().any(|(b, _, _)| *b == name)
}
const BANDS: [(&str, u64, u64); 33] = [
    ("2190m", 135_700, 137_800),
    ("630m", 472_000, 479_000),
    ("560m", 501_000, 504_000),
    ("160m", 1_800_000, 2_000_000),
    ("80m", 3_500_000, 4_000_000),
    ("60m", 5_060_000, 5_450_000),
    ("40m", 7_000_000, 7_300_000),
    ("30m", 10_100_000, 10_150_000),
    ("20m", 14_000_000, 14_350_000),
    ("17m", 18_068_000, 18_168_000),
    ("15m", 21_000_000, 21_450_000),
    ("12m", 24_890_000, 24_990_000),
    ("10m", 28_000_000, 29_700_000),
    ("8m", 40_000_000, 45_000_000),
    ("6m", 50_000_000, 54_000_000),
    ("5m", 54_000_001, 69_900_000),
    ("4m", 70_000_000, 71_000_000),
    ("2m", 144_000_000, 148_000_000),
    ("1.25m", 222_000_000, 225_000_000),
    ("70cm", 420_000_000, 450_000_000),
    ("33cm", 902_000_000, 928_000_000),
    ("23cm", 1_240_000_000, 1_300_000_000),
    ("13cm", 2_300_000_000, 2_450_000_000),
    ("9cm", 3_300_000_000, 3_500_000_000),
    ("6cm", 5_650_000_000, 5_925_000_000),
    ("3cm", 10_000_000_000, 10_500_000_000),
    ("1.25cm", 24_000_000_000, 24_250_000_000),
    ("6mm", 47_000_000_000, 47_200_000_000),
    ("4mm", 75_500_000_000, 81_000_000_000),
    ("2.5mm", 119_980_000_000, 123_000_000_000),
    ("2mm", 134_000_000_000, 149_000_000_000),
    ("1mm", 241_000_000_000, 250_000_000_000),
    ("submm", 300_000_000_000, 7_500_000_000_000),
];

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Unknown {
    pub name: String,
    pub kind: Option<String>,
    pub value: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct Record {
    pub contact_id: String,
    pub values: [Option<String>; 31],
    /// APP_WSTXRUST_SOURCE: the program a record added by UpdateLogbook came from.
    pub source: Option<String>,
    pub unknown: Vec<Unknown>,
}
impl Record {
    pub fn get(&self, name: &str) -> Option<&str> {
        let index = FIELDS.iter().position(|f| *f == name)?;
        self.values[index].as_deref()
    }
    /// Sets a supported field (a name outside FIELDS is a programming error).
    pub fn set(&mut self, name: &str, value: String) {
        let index = FIELDS
            .iter()
            .position(|f| *f == name)
            .expect("supported field");
        self.values[index] = Some(value);
    }
    /// #10 QSO confirmation: LOTW_QSL_RCVD, QSL_RCVD or EQSL_QSL_RCVD is Y or V
    /// (ADIF 3.1 QSL Rcvd: Y yes, V verified; N, R, I and absent are not confirmed).
    pub fn confirmed(&self) -> bool {
        CHANNELS
            .iter()
            .any(|(status, _, _)| self.values[*status].as_deref().is_some_and(confirmation))
    }
    /// #10 UpdateLogbook upgrade: each channel that `other` confirms and this record does
    /// not takes `other`'s status and, where `other` has them, its date and via. Nothing
    /// else changes and a confirmation is never removed. Whether anything changed.
    fn upgrade_confirmation(&mut self, other: &Record) -> bool {
        let mut changed = false;
        for (status, date, via) in CHANNELS {
            if !self.upgrades(other, status) {
                continue;
            }
            self.values[status] = other.values[status].clone();
            for i in std::iter::once(date).chain(via) {
                if other.values[i].is_some() {
                    self.values[i] = other.values[i].clone();
                }
            }
            changed = true;
        }
        changed
    }
    /// Whether `other` confirms the channel of this status index and this record does not.
    fn upgrades(&self, other: &Record, status: usize) -> bool {
        other.values[status].as_deref().is_some_and(confirmation)
            && !self.values[status].as_deref().is_some_and(confirmation)
    }
    /// Whether upgrade_confirmation with `other` would change this record.
    fn upgradable_by(&self, other: &Record) -> bool {
        CHANNELS
            .iter()
            .any(|(status, _, _)| self.upgrades(other, *status))
    }
    fn effective_mode(&self) -> String {
        let mode = self.values[MODE]
            .as_deref()
            .unwrap_or("")
            .to_ascii_uppercase();
        match &self.values[SUBMODE] {
            Some(submode) if mode == "MFSK" => submode.to_ascii_uppercase(),
            _ => mode,
        }
    }
    fn effective_band(&self) -> Option<String> {
        self.values[BAND]
            .as_ref()
            .map(|b| b.to_ascii_lowercase())
            .or_else(|| self.values[FREQ].as_deref().and_then(band_of_mhz))
    }
    /// Seconds of QSO_DATE + TIME_ON on a day count (UTC), for the consolidation window.
    fn start_seconds(&self) -> Option<i64> {
        let date = self.values[QSO_DATE].as_deref()?;
        let time = self.values[TIME_ON].as_deref()?;
        let number = |s: &str| s.parse::<i64>().ok();
        let (y, m, d) = (
            number(&date[..4])?,
            number(&date[4..6])?,
            number(&date[6..8])?,
        );
        // Days from civil (Howard Hinnant), proleptic Gregorian.
        let y = if m <= 2 { y - 1 } else { y };
        let era = y.div_euclid(400);
        let yoe = y - era * 400;
        let doy = (153 * (m + if m > 2 { -3 } else { 9 }) + 2) / 5 + d - 1;
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        let days = era * 146_097 + doe - 719_468;
        let seconds = if time.len() == 6 {
            number(&time[4..6])?
        } else {
            0
        };
        Some(days * 86_400 + number(&time[..2])? * 3600 + number(&time[2..4])? * 60 + seconds)
    }
    /// #10 consolidation key: call, effective band and effective mode.
    fn consolidation_key(&self) -> (String, String, String) {
        (
            self.values[CALL]
                .as_deref()
                .unwrap_or("")
                .to_ascii_uppercase(),
            self.effective_band().unwrap_or_default(),
            self.effective_mode(),
        )
    }
    pub fn history_json(&self, index: usize) -> Value {
        let mut object = serde_json::Map::new();
        object.insert("index".into(), json!(index));
        object.insert("contact_id".into(), json!(self.contact_id));
        // ContactHistory shows the LogRecord fields, not the confirmation fields (#10).
        for (name, value) in FIELDS.iter().zip(&self.values).take(CONFIRMATION) {
            object.insert((*name).into(), json!(value));
        }
        object.insert("unknown_field_count".into(), json!(self.unknown.len()));
        Value::Object(object)
    }
    /// One ADI record line: supported fields, the contact id, then unknown fields
    /// verbatim (name, optional type indicator and value), ended by ` <eor>`.
    pub fn to_adi(&self) -> String {
        let mut line = self.adi_fields();
        line.push_str(" <eor>\n");
        line
    }
    /// The ADI fields of `to_adi` without the end-of-record marker.
    pub fn adi_fields(&self) -> String {
        let mut line = String::new();
        let mut field = |name: &str, kind: Option<&str>, value: &str| {
            if !line.is_empty() {
                line.push(' ');
            }
            line.push('<');
            line.push_str(name);
            line.push(':');
            // ADIF LEN counts characters, not UTF-8 bytes.
            line.push_str(&value.chars().count().to_string());
            if let Some(kind) = kind {
                line.push(':');
                line.push_str(kind);
            }
            line.push('>');
            line.push_str(value);
        };
        for (name, value) in FIELDS.iter().zip(&self.values) {
            if let Some(value) = value {
                field(name, None, value);
            }
        }
        field(ID_FIELD, None, &self.contact_id);
        if let Some(source) = &self.source {
            field(SOURCE_FIELD, None, source);
        }
        for unknown in &self.unknown {
            field(&unknown.name, unknown.kind.as_deref(), &unknown.value);
        }
        line
    }
}

// ------------------------------------------------------------------ values
pub fn band_of_hz(hz: u64) -> Option<&'static str> {
    BANDS
        .iter()
        .find(|(_, low, high)| (*low..=*high).contains(&hz))
        .map(|(name, _, _)| *name)
}
fn band_of_mhz(freq: &str) -> Option<String> {
    let (whole, fraction) = freq.split_once('.').unwrap_or((freq, ""));
    let whole: u64 = if whole.is_empty() {
        0
    } else {
        whole.parse().ok()?
    };
    let mut digits: String = fraction.chars().take(6).collect();
    while digits.len() < 6 {
        digits.push('0');
    }
    let hz = whole
        .checked_mul(1_000_000)?
        .checked_add(digits.parse().ok()?)?;
    band_of_hz(hz).map(str::to_owned)
}
pub fn valid_band(band: &str) -> bool {
    BANDS
        .iter()
        .any(|(name, _, _)| name.eq_ignore_ascii_case(band))
}
fn positive_decimal(value: &str) -> bool {
    let (whole, fraction) = match value.split_once('.') {
        Some((_, "")) => return false,
        Some(parts) => parts,
        None => (value, ""),
    };
    let digits = |s: &str| s.bytes().all(|b| b.is_ascii_digit());
    !value.is_empty()
        && digits(whole)
        && digits(fraction)
        && value.bytes().any(|b| (b'1'..=b'9').contains(&b))
}
/// Canonical decimal for comparison only: "14.074" equals "14.074000".
fn decimal_key(value: &str) -> String {
    let (whole, fraction) = value.split_once('.').unwrap_or((value, ""));
    let whole = whole.trim_start_matches('0');
    let fraction = fraction.trim_end_matches('0');
    format!("{whole}.{fraction}")
}
pub fn valid_date(value: &str) -> bool {
    let b = value.as_bytes();
    if b.len() != 8 || !b.iter().all(u8::is_ascii_digit) {
        return false;
    }
    let year: u32 = value[..4].parse().unwrap_or(0);
    let month: u32 = value[4..6].parse().unwrap_or(0);
    let day: u32 = value[6..].parse().unwrap_or(0);
    let leap = year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400));
    let days = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if leap => 29,
        2 => 28,
        _ => return false,
    };
    year >= 1930 && (1..=days).contains(&day)
}
pub fn valid_time(value: &str, seconds_required: bool) -> bool {
    let b = value.as_bytes();
    if !(b.len() == 6 || (b.len() == 4 && !seconds_required)) || !b.iter().all(u8::is_ascii_digit) {
        return false;
    }
    let part = |i: usize| (b[i] - b'0') * 10 + (b[i + 1] - b'0');
    part(0) < 24 && part(2) < 60 && (b.len() == 4 || part(4) < 60)
}
pub fn valid_grid(value: &str, lengths: &[usize]) -> bool {
    lengths.contains(&value.len())
        && value.bytes().enumerate().all(|(i, b)| {
            let upper = b.to_ascii_uppercase();
            match i {
                0 | 1 => (b'A'..=b'R').contains(&upper),
                4 | 5 => (b'A'..=b'X').contains(&upper),
                _ => b.is_ascii_digit(),
            }
        })
}
fn call_like(value: &str, maximum: usize) -> bool {
    (1..=maximum).contains(&value.len())
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'/')
}
fn token(value: &str) -> bool {
    (1..=32).contains(&value.len())
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-')
}
fn printable(value: &str) -> bool {
    value.bytes().all(|b| (0x20..=0x7e).contains(&b))
}
/// ADIF 3.1 QSL Rcvd value that is a confirmation (Y or V, case-insensitive).
fn confirmation(value: &str) -> bool {
    value.eq_ignore_ascii_case("Y") || value.eq_ignore_ascii_case("V")
}
/// Report rendering of WstxContact::ReportRange, "%+2.2d" in -50..+49, or an RTTY
/// Roundup 5n9 RST (#24 S2b, LogRecord).
pub fn valid_report(value: &str) -> bool {
    let b = value.as_bytes();
    if b.len() == 3 && b[0] == b'5' && (b'2'..=b'9').contains(&b[1]) && b[2] == b'9' {
        return true;
    }
    b.len() == 3
        && (b[0] == b'+' || b[0] == b'-')
        && b[1..].iter().all(u8::is_ascii_digit)
        && value.parse::<i32>().is_ok_and(|n| (-50..=49).contains(&n))
}

/// #24 contest field domain of LogRecord (STX/SRX 1-4 digits, the others at most 32
/// printable characters without '<' and '>'), shared by SaveContact and UpdateLogbook.
fn valid_contest_value(name: &str, value: &str) -> bool {
    match name {
        "stx" | "srx" => {
            (1..=4).contains(&value.len()) && value.bytes().all(|b| b.is_ascii_digit())
        }
        _ => (1..=32).contains(&value.len()) && printable(value) && !value.contains(['<', '>']),
    }
}

/// Import-domain validation of one supported field (AdiError invalidValue otherwise).
fn valid_import_value(index: usize, value: &str) -> bool {
    match FIELDS[index] {
        "call" | "station_callsign" => call_like(value, 32),
        "gridsquare" | "my_gridsquare" => valid_grid(value, &[2, 4, 6, 8]),
        "mode" | "submode" => token(value),
        "rst_sent" | "rst_rcvd" => value.len() <= 16,
        "qso_date" | "qso_date_off" => valid_date(value),
        "time_on" | "time_off" => valid_time(value, false),
        "band" => valid_band(value),
        "freq" | "tx_pwr" => positive_decimal(value),
        // ADIF 3.1 QSL Rcvd enumeration, Date and QSL Via enumeration (case-insensitive).
        "lotw_qsl_rcvd" | "qsl_rcvd" | "eqsl_qsl_rcvd" => ["Y", "N", "R", "I", "V"]
            .iter()
            .any(|e| e.eq_ignore_ascii_case(value)),
        "lotw_qslrdate" | "qslrdate" | "eqsl_qslrdate" => valid_date(value),
        "qsl_rcvd_via" => ["B", "D", "E", "M"]
            .iter()
            .any(|e| e.eq_ignore_ascii_case(value)),
        _ => true,
    }
}

// ------------------------------------------------------------------ ADI parsing
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Fault {
    pub code: &'static str,
    pub record: Option<usize>,
    pub field: Option<String>,
}
impl Fault {
    fn new(code: &'static str, record: Option<usize>, field: Option<&str>) -> Self {
        Self {
            code,
            record,
            field: field.map(str::to_owned),
        }
    }
    pub fn json(&self) -> Value {
        json!({"code":self.code,"record":self.record,"field":self.field})
    }
}
pub struct Limits {
    pub records: usize,
}
/// One ADI field: name, optional type indicator and value, or the fault of that value
/// alone (field_too_long, unsupported_character), which the caller judges per record.
type RawField = (String, Option<String>, Result<String, &'static str>);
#[derive(Debug)]
pub struct Parsed {
    /// Header PROGRAMID when it is a 1..32 character token (UpdateLogbook source marker).
    pub program: Option<String>,
    pub records: Vec<Vec<RawField>>,
}
fn control(c: char) -> bool {
    c.is_control() && !matches!(c, '\t' | '\r' | '\n')
}
/// Byte index `n` characters after `start`, if the text holds that many.
fn advance(text: &str, start: usize, n: usize) -> Option<usize> {
    let rest = &text[start..];
    if rest.as_bytes().get(..n)?.is_ascii() {
        return Some(start + n);
    }
    match rest.char_indices().nth(n) {
        Some((i, _)) => Some(start + i),
        None => (rest.chars().count() == n).then_some(text.len()),
    }
}
/// ADIF ADI (UTF-8, a leading byte order mark ignored). Header present when the first
/// character is not '<', ended by <EOH>. Tags <NAME:LEN[:TYPE]> are case-insensitive and
/// LEN is exact in characters; text between fields of a record must be white space so
/// that an inexact LEN is detected (lengthMismatch) instead of silently truncating a value.
/// Structural faults refuse the file; a value's own fault stays with its field.
pub fn parse(bytes: &[u8], limits: &Limits) -> Result<Parsed, Fault> {
    let text =
        std::str::from_utf8(bytes).map_err(|_| Fault::new("unsupported_character", None, None))?;
    let text = text.strip_prefix('\u{feff}').unwrap_or(text);
    let b = text.as_bytes();
    let mut records = Vec::new();
    let mut program = None;
    let mut current: Vec<RawField> = Vec::new();
    let mut in_header = b.first().is_some_and(|c| *c != b'<');
    let mut position = 0;
    let at = |records: &Vec<Vec<RawField>>| Some(records.len());
    loop {
        let next = b[position..].iter().position(|c| *c == b'<');
        let end = next.map_or(b.len(), |n| position + n);
        let between = &text[position..end];
        if between.chars().any(control) {
            return Err(Fault::new("unsupported_character", at(&records), None));
        }
        // Text after a value means its LEN is not exact (Log4OM writes CNTY like
        // "<CNTY:10>NY,ORLEANS // Orleans"): that field is faulted, never truncated.
        if !in_header
            && !between.bytes().all(|c| c.is_ascii_whitespace())
            && let Some(last) = current.last_mut()
        {
            last.2 = Err("length_mismatch");
        }
        let Some(_) = next else {
            if in_header || !current.is_empty() {
                return Err(Fault::new("malformed", at(&records), None));
            }
            return Ok(Parsed { program, records });
        };
        let open = end;
        let Some(close) = b[open + 1..].iter().position(|c| *c == b'>') else {
            return Err(Fault::new("malformed", at(&records), None));
        };
        let close = open + 1 + close;
        let tag = &text[open + 1..close];
        if tag.bytes().any(|c| !(0x20..=0x7e).contains(&c)) {
            return Err(Fault::new(
                if tag.chars().any(control) {
                    "unsupported_character"
                } else {
                    "malformed"
                },
                at(&records),
                None,
            ));
        }
        let mut parts = tag.split(':');
        let name = parts.next().unwrap_or("");
        if name.len() > FIELD_NAME_CHARACTERS_MAX {
            return Err(Fault::new("field_too_long", at(&records), None));
        }
        if name.is_empty()
            || name
                .bytes()
                .any(|c| matches!(c, b',' | b':' | b'<' | b'>' | b'{' | b'}' | b' '))
        {
            return Err(Fault::new("malformed", at(&records), None));
        }
        let lname = name.to_ascii_lowercase();
        let Some(length) = parts.next() else {
            match lname.as_str() {
                "eoh" if in_header => in_header = false,
                "eor" if !in_header && !current.is_empty() => {
                    if records.len() == limits.records {
                        return Err(Fault::new("too_many_records", Some(records.len()), None));
                    }
                    records.push(std::mem::take(&mut current));
                }
                _ => return Err(Fault::new("malformed", at(&records), Some(&lname))),
            }
            position = close + 1;
            continue;
        };
        let kind = parts.next();
        if parts.next().is_some()
            || length.is_empty()
            || length.len() > 10
            || !length.bytes().all(|c| c.is_ascii_digit())
            || kind.is_some_and(|k| k.len() != 1 || !k.bytes().all(|c| c.is_ascii_alphabetic()))
        {
            return Err(Fault::new("malformed", at(&records), Some(&lname)));
        }
        let length: usize = length
            .parse()
            .map_err(|_| Fault::new("malformed", at(&records), Some(&lname)))?;
        let start = close + 1;
        let Some(stop) = advance(text, start, length) else {
            return Err(Fault::new("length_mismatch", at(&records), Some(&lname)));
        };
        let value = &text[start..stop];
        let value = if length > FIELD_CHARACTERS_MAX {
            Err("field_too_long")
        } else if value.chars().any(control) {
            Err("unsupported_character")
        } else {
            Ok(value.to_owned())
        };
        if !in_header {
            current.push((name.to_owned(), kind.map(str::to_owned), value));
        } else if lname == "programid" {
            program = value.ok().filter(|v| token(v));
        }
        position = stop;
    }
}
/// The stored-log reading of one parsed record: any fault refuses it. The contact id stays
/// empty when the record has none.
fn interpret(index: usize, raw: Vec<RawField>) -> Result<Record, Fault> {
    let mut record = Record::default();
    let mut seen_id = false;
    for (name, kind, value) in raw {
        let lname = name.to_ascii_lowercase();
        let value = value.map_err(|code| Fault::new(code, Some(index), Some(&lname)))?;
        let supported = FIELDS.iter().position(|f| *f == lname);
        if supported.is_none() && lname != ID_FIELD && lname != SOURCE_FIELD {
            record.unknown.push(Unknown { name, kind, value });
            continue;
        }
        if !printable(&value) {
            return Err(Fault::new(
                "unsupported_character",
                Some(index),
                Some(&lname),
            ));
        }
        if let Some(i) = supported {
            // A confirmation field that a log written before #10 kept verbatim (the former
            // ImportAdi) and that is invalid or repeated stays an unknown field, so such a
            // log stays readable.
            if i >= CONFIRMATION
                && (record.values[i].is_some()
                    || !value.is_empty() && !valid_import_value(i, &value))
            {
                record.unknown.push(Unknown { name, kind, value });
                continue;
            }
            if record.values[i].is_some() {
                return Err(Fault::new("malformed", Some(index), Some(&lname)));
            }
            if !value.is_empty() {
                if !valid_import_value(i, &value) {
                    return Err(Fault::new("invalid_value", Some(index), Some(&lname)));
                }
                record.values[i] = Some(value);
            }
        } else if lname == SOURCE_FIELD {
            if record.source.is_some() {
                return Err(Fault::new("malformed", Some(index), Some(&lname)));
            }
            if !token(&value) {
                return Err(Fault::new("invalid_value", Some(index), Some(&lname)));
            }
            record.source = Some(value);
        } else {
            if seen_id {
                return Err(Fault::new("malformed", Some(index), Some(&lname)));
            }
            seen_id = true;
            if !value.is_empty() {
                let id = value.to_ascii_lowercase();
                if !crate::profile::valid_uuid(&id) {
                    return Err(Fault::new("invalid_value", Some(index), Some(&lname)));
                }
                record.contact_id = id;
            }
        }
    }
    for required in [CALL, QSO_DATE, TIME_ON, MODE] {
        if record.values[required].is_none() {
            return Err(Fault::new(
                "missing_required_field",
                Some(index),
                Some(FIELDS[required]),
            ));
        }
    }
    Ok(record)
}
pub fn parse_records(bytes: &[u8], limits: &Limits) -> Result<Vec<Record>, Fault> {
    parse(bytes, limits)?
        .records
        .into_iter()
        .enumerate()
        .map(|(i, raw)| interpret(i, raw))
        .collect()
}
/// A fault that keeps a record out of an update, or a field out of its record.
type FieldFault = (&'static str, String);
/// #10 UpdateLogbook reading of one record: only the kept fields (FIELDS, contact id,
/// source); every other field is not stored. A missing or invalid required field, or a
/// kept field given twice, skips the record; an invalid optional field is dropped.
fn interpret_update(raw: Vec<RawField>) -> Result<(Record, Vec<FieldFault>), FieldFault> {
    let mut record = Record::default();
    let mut dropped = Vec::new();
    let mut seen = Vec::new();
    for (name, _, value) in raw {
        let lname = name.to_ascii_lowercase();
        let supported = FIELDS.iter().position(|f| *f == lname);
        if supported.is_none() && lname != ID_FIELD && lname != SOURCE_FIELD {
            continue;
        }
        if seen.contains(&lname) {
            return Err(("malformed", lname));
        }
        seen.push(lname.clone());
        let required = supported.is_some_and(|i| [CALL, QSO_DATE, TIME_ON, MODE].contains(&i));
        let checked = value.and_then(|v| {
            if !printable(&v) {
                Err("unsupported_character")
            } else if v.is_empty() {
                Ok(None)
            } else if match supported {
                // UpdateLogbook keeps only contest values SaveContact would accept (#10,
                // 2026-11-04); the stored-log reading stays as before.
                Some(i) => {
                    valid_import_value(i, &v)
                        && (!(CONTEST..CONFIRMATION).contains(&i)
                            || valid_contest_value(FIELDS[i], &v))
                }
                None if lname == SOURCE_FIELD => token(&v),
                None => crate::profile::valid_uuid(&v.to_ascii_lowercase()),
            } {
                Ok(Some(v))
            } else {
                Err("invalid_value")
            }
        });
        match (checked, supported) {
            (Ok(None), _) => {}
            (Ok(Some(v)), Some(i)) => record.values[i] = Some(v),
            (Ok(Some(v)), None) if lname == SOURCE_FIELD => record.source = Some(v),
            (Ok(Some(v)), None) => record.contact_id = v.to_ascii_lowercase(),
            (Err(code), _) if required => return Err((code, lname)),
            (Err(code), _) => dropped.push((code, lname)),
        }
    }
    for required in [CALL, QSO_DATE, TIME_ON, MODE] {
        if record.values[required].is_none() {
            return Err(("missing_required_field", FIELDS[required].to_owned()));
        }
    }
    Ok((record, dropped))
}

/// First differing LogRecord field of two records with the same contact id (the
/// confirmation fields are not compared: only UpdateLogbook sets them).
fn first_difference(a: &Record, b: &Record) -> Option<&'static str> {
    for (i, name) in FIELDS.iter().enumerate().take(CONFIRMATION) {
        let (x, y) = match (a.values[i].as_deref(), b.values[i].as_deref()) {
            (None, None) => continue,
            (Some(x), Some(y)) => (x, y),
            _ => return Some(name),
        };
        let same = match *name {
            "call" | "gridsquare" | "mode" | "submode" | "band" | "station_callsign"
            | "my_gridsquare" => x.eq_ignore_ascii_case(y),
            "time_on" | "time_off" if x.len() == 4 || y.len() == 4 => x[..4] == y[..4],
            "freq" | "tx_pwr" => decimal_key(x) == decimal_key(y),
            _ => x == y,
        };
        if !same {
            return Some(name);
        }
    }
    None
}

// ------------------------------------------------------------------ store
#[derive(Debug, PartialEq, Eq)]
pub enum SaveOutcome {
    Saved,
    AlreadySaved,
    Conflict,
}
/// WstxContact::DirectLog outcome: one record per contact id, a changed one replaced.
#[derive(Debug, PartialEq, Eq)]
pub enum LogOutcome {
    Saved,
    AlreadySaved,
    Replaced,
}
#[derive(Debug, PartialEq, Eq)]
pub enum StoreError {
    Unavailable,
    Unauthorized(crate::authorization::Error),
}
/// Publication gate: runs the replace under the caller's authority (the HTTPS durable
/// grant rechecked under the authorization lock) and returns its I/O result.
pub type Gate<'a> = &'a dyn Fn(
    &mut dyn FnMut() -> std::io::Result<()>,
) -> Result<std::io::Result<()>, crate::authorization::Error>;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ImportState {
    Receiving,
    Completed,
    Failed,
}
/// One group of UpdateLogbook skip or drop reasons: code, field, count, first record.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Group {
    pub code: &'static str,
    pub field: Option<String>,
    pub count: usize,
    pub record: usize,
}
/// #10 UpdateLogbook summary: added, already present, skipped (with reasons) and the
/// optional fields dropped from added or present records.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Summary {
    pub added: usize,
    pub present: usize,
    /// #10 present records whose confirmation this update upgraded.
    pub confirmed: usize,
    pub skipped: usize,
    pub reasons: Vec<Group>,
    pub dropped: Vec<Group>,
}
fn group(groups: &mut Vec<Group>, code: &'static str, field: Option<String>, record: usize) {
    if let Some(g) = groups
        .iter_mut()
        .find(|g| g.code == code && g.field == field)
    {
        g.count += 1;
    } else if groups.len() < REASON_GROUPS {
        groups.push(Group {
            code,
            field,
            count: 1,
            record,
        });
    }
}
fn groups_json(groups: &[Group]) -> Value {
    groups
        .iter()
        .map(|g| json!({"code":g.code,"field":g.field,"count":g.count,"record":g.record}))
        .collect()
}
struct Import {
    id: String,
    total: u64,
    sha256: String,
    bytes: Vec<u8>,
    received: u64,
    state: ImportState,
    summary: Summary,
    error: Option<Fault>,
    touched: Instant,
}
impl Import {
    fn view(&self) -> Value {
        let s = &self.summary;
        json!({"v":1,"id":self.id,"state":match self.state {
            ImportState::Receiving=>"receiving",ImportState::Completed=>"completed",ImportState::Failed=>"failed"},
            "received_bytes":self.received,"total_bytes":self.total,
            "added":s.added,"present":s.present,"confirmed":s.confirmed,"skipped":s.skipped,
            "reasons":groups_json(&s.reasons),"dropped":groups_json(&s.dropped),
            "error":self.error.as_ref().map(Fault::json)})
    }
}
pub struct Receipt {
    pub command_id: String,
    pub body: Value,
    pub status: u16,
    pub response: Value,
}
struct Inner {
    available: bool,
    /// Shared with a running ExportAdi stream, which keeps its snapshot without the lock;
    /// a change replaces the whole vector.
    records: Arc<Vec<Record>>,
    ids: HashMap<String, usize>,
    created: String,
    import: Option<Import>,
    receipts: VecDeque<Receipt>,
    /// Counts every change of `records` (#55 worked-set cache key).
    revision: u64,
    #[cfg(test)]
    fault: Option<&'static str>,
}
/// (records revision, country table, worked set of that log and table).
/// #10 worked-before index of the log: (effective band, effective mode) per call and
/// per 4-character grid square, so a query looks up the asked calls, not every record.
#[derive(Default)]
struct WorkedIndex {
    calls: HashMap<String, Vec<(String, String)>>,
    grids: HashMap<String, Vec<(String, String)>>,
}
impl WorkedIndex {
    fn of(records: &[Record]) -> Self {
        let mut index = Self::default();
        for record in records {
            let (call, band, mode) = record.consolidation_key();
            if let Some(grid) = record.values[GRID].as_deref().and_then(square) {
                index
                    .grids
                    .entry(grid)
                    .or_default()
                    .push((band.clone(), mode.clone()));
            }
            index.calls.entry(call).or_default().push((band, mode));
        }
        index
    }
    fn status(entries: Option<&Vec<(String, String)>>, band: &str, mode: &str) -> &'static str {
        match entries {
            None => "not_worked",
            // A record without band is never "this band" (as before the index).
            Some(e)
                if e.iter()
                    .any(|(b, m)| !b.is_empty() && b == band && m == mode) =>
            {
                "worked_this_band_and_mode"
            }
            Some(_) => "worked_other_band_or_mode",
        }
    }
}
fn square(grid: &str) -> Option<String> {
    grid.get(..4).map(str::to_ascii_uppercase)
}
/// The most windows of worked sets kept (WstxStrategy::WorkedWindow).
const WORKED_WINDOWS: usize = 4;
/// (log revision, country table, (first date, last date), worked set).
type WindowCache = (
    u64,
    std::sync::Arc<crate::dxcc::Cty>,
    (u32, u32),
    std::sync::Arc<crate::dxcc::Worked>,
);
/// What the worked sets read of the records.
fn logged(records: &[Record]) -> Vec<crate::dxcc::Logged> {
    records
        .iter()
        .map(|r| crate::dxcc::Logged {
            call: r.values[CALL].clone().unwrap_or_default(),
            grid: r.values[GRID].clone(),
            band: r.effective_band(),
            mode: Some(r.effective_mode()).filter(|m| !m.is_empty()),
            confirmed: r.confirmed(),
            date: r.values[QSO_DATE].as_deref().and_then(|d| d.parse().ok()),
            state: r.values[STATE].clone(),
        })
        .collect()
}
type WorkedCache = (
    u64,
    std::sync::Arc<crate::dxcc::Cty>,
    std::sync::Arc<crate::dxcc::Worked>,
);
pub struct Logbook {
    directory: PathBuf,
    inner: Mutex<Inner>,
    /// #55 the country table of this profile (WSJT-X keeps AD1CCty in WorkedBefore).
    dxcc: Mutex<DxccState>,
    /// #55 the worked set of the log for (records revision, country table), rebuilt only
    /// when either changes: /receive/results reads it on every page.
    /// The table is held (not its address), so a later table can never match it.
    worked_set: Mutex<Option<WorkedCache>>,
    worked_windows: Mutex<Vec<WindowCache>>,
    /// #39 the keys a background build is running for (WstxStrategy::WorkedWindow).
    worked_building: Mutex<Vec<Option<(u32, u32)>>>,
    /// #10 the worked-before index for the records revision it was built from.
    worked_index: Mutex<Option<(u64, std::sync::Arc<WorkedIndex>)>>,
}
struct DxccState {
    table: crate::dxcc::Table,
    /// The uploaded cty.dat exists but could not be read or parsed: the bundled
    /// table is used and the file is left untouched.
    unreadable: bool,
}
/// Why a cty.dat replacement was refused.
#[derive(Debug)]
pub enum DxccError {
    /// The text is no cty.dat (the 1-based line that failed).
    Invalid(usize),
    Store(StoreError),
}
fn load_dxcc(path: &Path) -> DxccState {
    let bundled = |unreadable| DxccState {
        table: crate::dxcc::Table::default(),
        unreadable,
    };
    match fs::read(path) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => bundled(false),
        read => match read
            .ok()
            .and_then(|b| String::from_utf8(b).ok())
            .and_then(|t| crate::dxcc::Cty::parse(&t).ok())
        {
            Some(cty) => DxccState {
                table: crate::dxcc::Table::uploaded(cty),
                unreadable: false,
            },
            None => bundled(true),
        },
    }
}
fn gated_io(gate: Gate, action: &mut dyn FnMut() -> std::io::Result<()>) -> Result<(), StoreError> {
    match gate(action) {
        Ok(Ok(())) => Ok(()),
        Ok(Err(_)) => Err(StoreError::Unavailable),
        Err(e) => Err(StoreError::Unauthorized(e)),
    }
}
fn utc_timestamp() -> String {
    let seconds = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());
    let days = (seconds / 86_400) as i64;
    let rest = seconds % 86_400;
    // Civil-from-days (Howard Hinnant), proleptic Gregorian UTC.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!(
        "{year:04}{month:02}{day:02} {:02}{:02}{:02}",
        rest / 3600,
        rest % 3600 / 60,
        rest % 60
    )
}
fn header(created: &str) -> String {
    let version = env!("CARGO_PKG_VERSION");
    format!(
        "ADIF Export\n<adif_ver:5>3.1.8\n<created_timestamp:{}>{created}\n<programid:8>WSTXRUST\n<programversion:{}>{version}\n<eoh>\n",
        created.len(),
        version.len()
    )
}
/// Records per chunk of an ExportAdi stream (about 30 KiB of a typical log).
pub const EXPORT_CHUNK_RECORDS: usize = 128;
/// ExportAdi as a stream: the header with the first chunk, then EXPORT_CHUNK_RECORDS
/// records per chunk, each formatted only when the connection takes it, so a large log is
/// never held as one document (WstxContact::ExportAdi).
pub struct AdiExport {
    header: Option<String>,
    records: Arc<Vec<Record>>,
    next: usize,
}
impl futures_core::Stream for AdiExport {
    type Item = Result<String, std::convert::Infallible>;
    fn poll_next(
        mut self: std::pin::Pin<&mut Self>,
        _: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Option<Self::Item>> {
        let this = &mut *self;
        let mut chunk = this.header.take().unwrap_or_default();
        let end = (this.next + EXPORT_CHUNK_RECORDS).min(this.records.len());
        for record in &this.records[this.next..end] {
            chunk.push_str(&record.to_adi());
        }
        this.next = end;
        std::task::Poll::Ready((!chunk.is_empty()).then_some(Ok(chunk)))
    }
}
fn document(created: &str, records: &[Record]) -> Vec<u8> {
    let mut text = header(created);
    for record in records {
        text.push_str(&record.to_adi());
    }
    text.into_bytes()
}
fn sha256_hex(bytes: &[u8]) -> String {
    ring::digest::digest(&ring::digest::SHA256, bytes)
        .as_ref()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

impl Logbook {
    /// Loads `<profile dir>/contacts.adi`. A missing file is an empty log; an unreadable
    /// or invalid file leaves the log unavailable and is never overwritten.
    pub fn open(directory: &Path) -> Self {
        let path = directory.join(FILE_NAME);
        let (available, records, created) = match fs::read(&path) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                (true, Vec::new(), utc_timestamp())
            }
            Err(_) => (false, Vec::new(), String::new()),
            Ok(bytes) => match parse_records(
                &bytes,
                &Limits {
                    records: usize::MAX,
                },
            ) {
                Ok(records)
                    if records
                        .iter()
                        .all(|r| crate::profile::valid_uuid(&r.contact_id)) =>
                {
                    (true, records, utc_timestamp())
                }
                _ => (false, Vec::new(), String::new()),
            },
        };
        let ids = records
            .iter()
            .enumerate()
            .map(|(i, r)| (r.contact_id.clone(), i))
            .collect::<HashMap<_, _>>();
        let available = available && ids.len() == records.len();
        Self {
            directory: directory.to_owned(),
            inner: Mutex::new(Inner {
                available,
                records: Arc::new(records),
                ids,
                created,
                import: None,
                receipts: VecDeque::new(),
                revision: 0,
                #[cfg(test)]
                fault: None,
            }),
            dxcc: Mutex::new(load_dxcc(&directory.join(crate::dxcc::FILE_NAME))),
            worked_set: Mutex::new(None),
            worked_windows: Mutex::new(Vec::new()),
            worked_building: Mutex::new(Vec::new()),
            worked_index: Mutex::new(None),
        }
    }
    fn lock(&self) -> Result<std::sync::MutexGuard<'_, Inner>, StoreError> {
        let inner = self.inner.lock().map_err(|_| StoreError::Unavailable)?;
        if inner.available {
            Ok(inner)
        } else {
            Err(StoreError::Unavailable)
        }
    }
    #[cfg(test)]
    pub fn inject_fault(&self, stage: Option<&'static str>) {
        self.inner.lock().unwrap().fault = stage;
    }
    /// Writes the complete next file beside the log, flushes it and replaces
    /// contacts.adi through the gate. A failure removes the temporary file and leaves
    /// both the file and the in-memory log unchanged.
    fn publish(&self, inner: &Inner, next: &[Record], gate: Gate) -> Result<(), StoreError> {
        let temporary = self.directory.join(format!(
            ".contacts-{}.tmp",
            crate::profile::new_uuid().map_err(|_| StoreError::Unavailable)?
        ));
        #[cfg(test)]
        let fault = inner.fault;
        #[cfg(not(test))]
        let _ = inner;
        let checkpoint = |_stage: &str| -> std::io::Result<()> {
            #[cfg(test)]
            if fault == Some(_stage) {
                return Err(std::io::Error::other("injected storage failure"));
            }
            Ok(())
        };
        let written = (|| {
            let mut file = OpenOptions::new()
                .create_new(true)
                .write(true)
                .open(&temporary)?;
            checkpoint("write")?;
            file.write_all(&document(&inner.created, next))?;
            checkpoint("flush")?;
            file.sync_all()
        })();
        let result = match written {
            Err(_) => Err(StoreError::Unavailable),
            Ok(()) => {
                let target = self.directory.join(FILE_NAME);
                let mut replace = || {
                    checkpoint("replace")?;
                    fs::rename(&temporary, &target)
                };
                match gate(&mut replace) {
                    Ok(Ok(())) => Ok(()),
                    Ok(Err(_)) => Err(StoreError::Unavailable),
                    Err(error) => Err(StoreError::Unauthorized(error)),
                }
            }
        };
        if result.is_err() {
            let _ = fs::remove_file(&temporary);
        }
        result
    }
    fn append(&self, inner: &mut Inner, new: Vec<Record>, gate: Gate) -> Result<(), StoreError> {
        self.update(inner, HashMap::new(), new, gate)
    }
    /// Replaces the stored records at the given indexes and appends `new`, in one publish.
    fn update(
        &self,
        inner: &mut Inner,
        changed: HashMap<usize, Record>,
        new: Vec<Record>,
        gate: Gate,
    ) -> Result<(), StoreError> {
        let mut next = Vec::clone(&inner.records);
        for (index, record) in changed {
            next[index] = record;
        }
        next.extend(new);
        self.publish(inner, &next, gate)?;
        inner.ids = next
            .iter()
            .enumerate()
            .map(|(i, r)| (r.contact_id.clone(), i))
            .collect();
        inner.records = Arc::new(next);
        inner.revision += 1;
        Ok(())
    }
    /// SaveContact: exactly once per contact id. Identical resave is AlreadySaved;
    /// different fields after a save are Conflict; nothing is written for either.
    pub fn save(&self, record: Record, gate: Gate) -> Result<SaveOutcome, StoreError> {
        let mut inner = self.lock()?;
        if let Some(&index) = inner.ids.get(&record.contact_id) {
            let stored = &inner.records[index];
            return Ok(
                if first_difference(stored, &record).is_none() && stored.unknown.is_empty() {
                    SaveOutcome::AlreadySaved
                } else {
                    SaveOutcome::Conflict
                },
            );
        }
        self.append(&mut inner, vec![record], gate)?;
        Ok(SaveOutcome::Saved)
    }
    /// DirectLog: appends a new contact id; an identical stored record is AlreadySaved;
    /// different fields replace the stored record in place (its index and any preserved
    /// unknown fields are kept). Nothing changes in memory unless the replace succeeds.
    pub fn put(&self, record: Record, gate: Gate) -> Result<LogOutcome, StoreError> {
        let mut inner = self.lock()?;
        let Some(&index) = inner.ids.get(&record.contact_id) else {
            self.append(&mut inner, vec![record], gate)?;
            return Ok(LogOutcome::Saved);
        };
        if first_difference(&inner.records[index], &record).is_none() {
            return Ok(LogOutcome::AlreadySaved);
        }
        let mut next = Vec::clone(&inner.records);
        let mut replaced = Record {
            unknown: next[index].unknown.clone(),
            source: next[index].source.clone(),
            ..record
        };
        // #10 a confirmation is never removed: the stored confirmation fields stay.
        replaced.values[CONFIRMATION..].clone_from_slice(&next[index].values[CONFIRMATION..]);
        next[index] = replaced;
        self.publish(&inner, &next, gate)?;
        inner.records = Arc::new(next);
        inner.revision += 1;
        Ok(LogOutcome::Replaced)
    }
    pub fn receipt(&self, command_id: &str) -> Result<Option<(Value, u16, Value)>, StoreError> {
        let inner = self.lock()?;
        Ok(inner
            .receipts
            .iter()
            .find(|r| r.command_id == command_id)
            .map(|r| (r.body.clone(), r.status, r.response.clone())))
    }
    pub fn retain_receipt(&self, receipt: Receipt) {
        if let Ok(mut inner) = self.lock() {
            if inner.receipts.len() == RECEIPTS {
                inner.receipts.pop_front();
            }
            inner.receipts.push_back(receipt);
        }
    }
    /// Whether a record with this contact id is durably stored (review outcome).
    pub fn saved(&self, contact_id: &str) -> bool {
        self.lock()
            .is_ok_and(|inner| inner.ids.contains_key(contact_id))
    }
    pub fn total(&self) -> Result<usize, StoreError> {
        Ok(self.lock()?.records.len())
    }
    /// ContactHistory page in storage order; at most `limit` records and at most
    /// HISTORY_PAGE_BYTES_MAX encoded bytes (fewer records when needed, at least one).
    pub fn history(
        &self,
        profile_id: &str,
        cursor: usize,
        limit: usize,
    ) -> Result<Value, StoreError> {
        let inner = self.lock()?;
        let total = inner.records.len();
        let mut records = Vec::new();
        let page = |records: &Vec<Value>| {
            let next = cursor + records.len();
            json!({"v":1,"profile_id":profile_id,"total":total,"cursor":cursor,"next":next,"more":next<total,"records":records})
        };
        for (index, record) in inner.records.iter().enumerate().skip(cursor).take(limit) {
            records.push(record.history_json(index));
            if records.len() > 1 && page(&records).to_string().len() > HISTORY_PAGE_BYTES_MAX {
                records.pop();
                break;
            }
        }
        Ok(page(&records))
    }
    /// ExportAdi: a snapshot of the log at the request, streamed without the lock.
    pub fn export(&self) -> Result<AdiExport, StoreError> {
        let inner = self.lock()?;
        Ok(AdiExport {
            header: Some(header(&utc_timestamp())),
            records: inner.records.clone(),
            next: 0,
        })
    }
    /// The worked-before index of the current log, rebuilt only when the log changed.
    fn index(&self, inner: &Inner) -> std::sync::Arc<WorkedIndex> {
        let mut cache = self.worked_index.lock().unwrap_or_else(|p| p.into_inner());
        match &*cache {
            Some((revision, index)) if *revision == inner.revision => index.clone(),
            _ => {
                let index = std::sync::Arc::new(WorkedIndex::of(&inner.records));
                *cache = Some((inner.revision, index.clone()));
                index
            }
        }
    }
    /// WorkedBeforeQuery over the stored log (including contacts saved this session and
    /// records added by UpdateLogbook).
    pub fn worked(
        &self,
        calls: &[String],
        band: &str,
        mode: &str,
    ) -> Result<Vec<&'static str>, StoreError> {
        let index = self.index(&*self.lock()?);
        let (band, mode) = (band.to_ascii_lowercase(), mode.to_ascii_uppercase());
        Ok(calls
            .iter()
            .map(|c| WorkedIndex::status(index.calls.get(&c.to_ascii_uppercase()), &band, &mode))
            .collect())
    }

    /// #55 WorkedBefore of the stored log against the current country table (cached).
    pub fn worked_set(&self) -> Result<std::sync::Arc<crate::dxcc::Worked>, StoreError> {
        let (table, _) = self.dxcc();
        let (revision, logged) = {
            let inner = self.lock()?;
            if let Some((r, t, w)) = &*self.worked_set.lock().unwrap_or_else(|p| p.into_inner())
                && *r == inner.revision
                && std::sync::Arc::ptr_eq(t, &table.cty)
            {
                return Ok(w.clone());
            }
            (inner.revision, logged(&inner.records))
        };
        let worked = std::sync::Arc::new(crate::dxcc::Worked::from_log(&table, &logged));
        *self.worked_set.lock().unwrap_or_else(|p| p.into_inner()) =
            Some((revision, table.cty.clone(), worked.clone()));
        Ok(worked)
    }
    /// #39 WstxStrategy::WorkedWindow: WorkedBefore of the records dated first..=last
    /// (YYYYMMDD), cached per log revision, country table and window, at most
    /// WORKED_WINDOWS of them.
    pub fn worked_window(
        &self,
        first: u32,
        last: u32,
    ) -> Result<std::sync::Arc<crate::dxcc::Worked>, StoreError> {
        let (table, _) = self.dxcc();
        let (revision, logged) = {
            let inner = self.lock()?;
            let cache = self
                .worked_windows
                .lock()
                .unwrap_or_else(|p| p.into_inner());
            if let Some(hit) = cache.iter().find(|c| {
                c.0 == inner.revision
                    && std::sync::Arc::ptr_eq(&c.1, &table.cty)
                    && c.2 == (first, last)
            }) {
                return Ok(hit.3.clone());
            }
            (inner.revision, logged(&inner.records))
        };
        let worked = std::sync::Arc::new(crate::dxcc::Worked::from_log_window(
            &table,
            &logged,
            Some((first, last)),
        ));
        let mut cache = self
            .worked_windows
            .lock()
            .unwrap_or_else(|p| p.into_inner());
        cache.retain(|c| c.2 != (first, last));
        if cache.len() >= WORKED_WINDOWS {
            cache.remove(0);
        }
        cache.push((revision, table.cty.clone(), (first, last), worked.clone()));
        Ok(worked)
    }
    /// #39 WstxStrategy::WorkedWindow for the station step: the last built set of this window
    /// (all time: None) at once, without building (a rebuild of the operator's log takes about
    /// 100 ms, two station steps). A set that is missing or behind the log or the country
    /// table is built on its own thread for a later step; None until the first is ready.
    pub fn worked_latest(
        self: &std::sync::Arc<Self>,
        window: Option<(u32, u32)>,
    ) -> Option<std::sync::Arc<crate::dxcc::Worked>> {
        let (table, _) = self.dxcc();
        let last = match window {
            None => self
                .worked_set
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .clone(),
            Some(key) => self
                .worked_windows
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .iter()
                .find(|c| c.2 == key)
                .map(|c| (c.0, c.1.clone(), c.3.clone())),
        };
        // A busy log (a save, an import) keeps the last set: the step never waits for it.
        let revision = match self.inner.try_lock() {
            Ok(inner) => Some(inner.revision),
            Err(_) => None,
        };
        let current = revision.is_none_or(|revision| {
            last.as_ref()
                .is_some_and(|(r, t, _)| *r == revision && std::sync::Arc::ptr_eq(t, &table.cty))
        });
        if !current {
            let mut building = self
                .worked_building
                .lock()
                .unwrap_or_else(|p| p.into_inner());
            if !building.contains(&window) {
                building.push(window);
                let log = self.clone();
                std::thread::spawn(move || {
                    let _ = match window {
                        None => log.worked_set(),
                        Some((first, last)) => log.worked_window(first, last),
                    };
                    log.worked_building
                        .lock()
                        .unwrap_or_else(|p| p.into_inner())
                        .retain(|k| *k != window);
                });
            }
        }
        last.map(|(_, _, w)| w)
    }
    /// The log revision now; None while the log is busy (the station step never waits).
    pub fn revision_now(&self) -> Option<u64> {
        self.inner.try_lock().ok().map(|inner| inner.revision)
    }
    /// #63 WstxContest::ContestLog: the log revision and the contacts that started in [start,
    /// end) (Unix ms).
    pub fn contest_qsos(
        &self,
        start_ms: i64,
        end_ms: i64,
    ) -> Result<(u64, Vec<crate::contest::Qso>), StoreError> {
        let inner = self.lock()?;
        let list = inner
            .records
            .iter()
            .filter_map(|r| {
                let ms = r.start_seconds()? * 1000;
                (ms >= start_ms && ms < end_ms).then(|| crate::contest::Qso {
                    call: r.values[CALL].as_deref().unwrap_or("").to_ascii_uppercase(),
                    grid: r.values[GRID].clone(),
                    band: r.effective_band(),
                    mode: r.effective_mode(),
                    ms,
                })
            })
            .collect();
        Ok((inner.revision, list))
    }
    /// #55 the country table in use and whether an uploaded file was unreadable.
    pub fn dxcc(&self) -> (crate::dxcc::Table, bool) {
        let d = self.dxcc.lock().unwrap_or_else(|p| p.into_inner());
        (d.table.clone(), d.unreadable)
    }
    /// #55 replaces the profile's cty.dat with `text` (validated first), or with None
    /// removes the upload so the bundled table applies. The file is written beside the
    /// log, flushed and renamed through the gate; the table changes only after that.
    pub fn replace_dxcc(&self, text: Option<&str>, gate: Gate) -> Result<(), DxccError> {
        let parsed = text
            .map(crate::dxcc::Cty::parse)
            .transpose()
            .map_err(DxccError::Invalid)?;
        let mut state = self.dxcc.lock().unwrap_or_else(|p| p.into_inner());
        let target = self.directory.join(crate::dxcc::FILE_NAME);
        match text {
            Some(t) => {
                let temporary = self.directory.join(format!(
                    ".cty-{}.tmp",
                    crate::profile::new_uuid()
                        .map_err(|_| DxccError::Store(StoreError::Unavailable))?
                ));
                let written = (|| {
                    let mut file = OpenOptions::new()
                        .create_new(true)
                        .write(true)
                        .open(&temporary)?;
                    file.write_all(t.as_bytes())?;
                    file.sync_all()
                })();
                let result = written
                    .map_err(|_| StoreError::Unavailable)
                    .and_then(|()| gated_io(gate, &mut || fs::rename(&temporary, &target)));
                if result.is_err() {
                    let _ = fs::remove_file(&temporary);
                }
                result
            }
            None => gated_io(gate, &mut || match fs::remove_file(&target) {
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
                other => other,
            }),
        }
        .map_err(DxccError::Store)?;
        *state = DxccState {
            table: parsed.map_or_else(crate::dxcc::Table::default, crate::dxcc::Table::uploaded),
            unreadable: false,
        };
        Ok(())
    }

    // -------------------------------------------------------------- imports
    /// Reserve (or retry) one import. Same id with identical total/sha256 returns the
    /// existing resource without a second effect; different values are state_conflict.
    pub fn reserve(
        &self,
        id: &str,
        total: u64,
        sha256: &str,
        now: Instant,
    ) -> Result<(bool, Value), &'static str> {
        let mut inner = self.lock().map_err(|_| "storage_unavailable")?;
        if let Some(import) = &inner.import {
            if import.id == id {
                return if import.total == total && import.sha256 == sha256 {
                    Ok((false, import.view()))
                } else {
                    Err("state_conflict")
                };
            }
            if import.state == ImportState::Receiving
                && now.duration_since(import.touched) < IMPORT_IDLE
            {
                return Err("busy");
            }
        }
        let import = Import {
            id: id.to_owned(),
            total,
            sha256: sha256.to_owned(),
            bytes: Vec::new(),
            received: 0,
            state: ImportState::Receiving,
            summary: Summary::default(),
            error: None,
            touched: now,
        };
        let view = import.view();
        inner.import = Some(import);
        Ok((true, view))
    }
    pub fn import_view(&self, id: &str) -> Result<Value, &'static str> {
        let inner = self.lock().map_err(|_| "storage_unavailable")?;
        inner
            .import
            .as_ref()
            .filter(|i| i.id == id)
            .map(Import::view)
            .ok_or("not_found")
    }
    /// One in-order chunk. The last chunk checks sha256, validates the whole file and
    /// publishes all new records in one atomic replace, or none at all.
    pub fn chunk(
        &self,
        id: &str,
        start: u64,
        total: u64,
        bytes: &[u8],
        now: Instant,
        gate: Gate,
    ) -> Result<Value, &'static str> {
        let mut inner = self.lock().map_err(|_| "storage_unavailable")?;
        let import = inner
            .import
            .as_mut()
            .filter(|i| i.id == id)
            .ok_or("not_found")?;
        if import.state != ImportState::Receiving {
            return Err("state_conflict");
        }
        if total != import.total || start != import.received {
            return Err("state_conflict");
        }
        if start + bytes.len() as u64 > import.total {
            return Err("invalid_request");
        }
        import.bytes.extend_from_slice(bytes);
        import.received = import.bytes.len() as u64;
        import.touched = now;
        if import.received < import.total {
            return Ok(import.view());
        }
        let mut import = inner.import.take().ok_or("not_found")?;
        let result = if sha256_hex(&import.bytes) != import.sha256 {
            Err(Fault::new("integrity_mismatch", None, None))
        } else {
            self.consolidate(&inner, &import.bytes)
        };
        let outcome = match result {
            Err(fault) => {
                import.state = ImportState::Failed;
                import.error = Some(fault);
                Err("import_failed")
            }
            Ok((new, changed, summary)) => {
                import.summary = summary;
                let appended = if new.is_empty() && changed.is_empty() {
                    Ok(())
                } else {
                    self.update(&mut inner, changed, new, gate)
                };
                match appended {
                    Ok(()) => {
                        import.state = ImportState::Completed;
                        Ok(())
                    }
                    Err(e) => {
                        import.state = ImportState::Failed;
                        import.summary.added = 0;
                        import.summary.confirmed = 0;
                        Err(match e {
                            StoreError::Unauthorized(_) => "unauthorized",
                            StoreError::Unavailable => "storage_unavailable",
                        })
                    }
                }
            }
        };
        import.bytes = Vec::new();
        let view = import.view();
        inner.import = Some(import);
        outcome.map(|()| view)
    }
    /// #10 UpdateLogbook before publication: the structural parse (any fault refuses the
    /// file), then each record skipped, already present or added. A record is present
    /// when its contact id is stored or added earlier from this file, or when a stored
    /// or earlier added record has the same consolidation key and a start at most
    /// CONSOLIDATION_SECONDS away; that record wins, and only its confirmation is
    /// upgraded (Record::upgrade_confirmation). Returns the records to add, the stored
    /// records (by index) whose confirmation changed, and the summary.
    fn consolidate(&self, inner: &Inner, bytes: &[u8]) -> Result<Consolidated, Fault> {
        let parsed = parse(
            bytes,
            &Limits {
                records: IMPORT_RECORDS_MAX,
            },
        )?;
        let source = parsed.program.unwrap_or_else(|| "ADIF".to_owned());
        let mut ids: HashMap<String, Target> = inner
            .ids
            .iter()
            .map(|(id, i)| (id.clone(), Target::Stored(*i)))
            .collect();
        let mut starts: HashMap<(String, String, String), Vec<(i64, Target)>> = HashMap::new();
        for (i, record) in inner.records.iter().enumerate() {
            if let Some(start) = record.start_seconds() {
                starts
                    .entry(record.consolidation_key())
                    .or_default()
                    .push((start, Target::Stored(i)));
            }
        }
        let (mut new, mut summary) = (Vec::<Record>::new(), Summary::default());
        let mut changed: HashMap<usize, Record> = HashMap::new();
        for (index, raw) in parsed.records.into_iter().enumerate() {
            let (mut record, dropped) = match interpret_update(raw) {
                Ok(read) => read,
                Err((code, field)) => {
                    summary.skipped += 1;
                    group(&mut summary.reasons, code, Some(field), index);
                    continue;
                }
            };
            for (code, field) in dropped {
                group(&mut summary.dropped, code, Some(field), index);
            }
            let key = record.consolidation_key();
            let start = record.start_seconds();
            let near = |s: &&(i64, Target)| {
                start.is_some_and(|t| (s.0 - t).abs() <= CONSOLIDATION_SECONDS)
            };
            let present = ids.get(&record.contact_id).copied().or_else(|| {
                starts
                    .get(&key)
                    .and_then(|s| s.iter().find(near))
                    .map(|s| s.1)
            });
            if let Some(target) = present {
                summary.present += 1;
                let upgraded = match target {
                    Target::Added(i) => new[i].upgrade_confirmation(&record),
                    // A stored record is copied only when its confirmation changes.
                    Target::Stored(i) => {
                        let current = changed.get(&i).unwrap_or(&inner.records[i]);
                        current.upgradable_by(&record) && {
                            let mut next = current.clone();
                            next.upgrade_confirmation(&record);
                            changed.insert(i, next);
                            true
                        }
                    }
                };
                summary.confirmed += usize::from(upgraded);
                continue;
            }
            if record.contact_id.is_empty() {
                record.contact_id = crate::profile::new_uuid()
                    .map_err(|_| Fault::new("malformed", Some(index), None))?;
            }
            record.source.get_or_insert_with(|| source.clone());
            let target = Target::Added(new.len());
            ids.insert(record.contact_id.clone(), target);
            if let Some(start) = start {
                starts.entry(key).or_default().push((start, target));
            }
            new.push(record);
        }
        summary.added = new.len();
        Ok((new, changed, summary))
    }
}

/// #10 the record a consolidated update record is present as: a stored one (its index) or
/// one added earlier from the same file (its index among the added).
#[derive(Clone, Copy)]
enum Target {
    Stored(usize),
    Added(usize),
}
/// UpdateLogbook result before publication: records to add, stored records whose
/// confirmation changed (by index), summary.
type Consolidated = (Vec<Record>, HashMap<usize, Record>, Summary);

/// Save-domain validation of a record to store (log_invalid_field with the key).
pub fn validate_record(record: &Record, callsign: &str, locator: &str) -> Result<(), &'static str> {
    let v = |i: usize| record.values[i].as_deref();
    if !crate::profile::valid_uuid(&record.contact_id) {
        return Err("record.contact_id");
    }
    let call = v(CALL).unwrap_or("");
    if !(3..=13).contains(&call.len())
        || !call
            .bytes()
            .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit() || b == b'/')
        || !call.bytes().any(|b| b.is_ascii_digit())
    {
        return Err("record.call");
    }
    if v(GRID).is_some_and(|g| !valid_grid(g, &[4, 6])) {
        return Err("record.gridsquare");
    }
    match (v(MODE), v(SUBMODE)) {
        (Some("FT8"), None) | (Some("MFSK"), Some("FT4")) => {}
        (Some("FT8" | "MFSK"), _) => return Err("record.submode"),
        _ => return Err("record.mode"),
    }
    for (i, key) in [(4, "record.rst_sent"), (5, "record.rst_rcvd")] {
        if v(i).is_some_and(|r| !valid_report(r)) {
            return Err(key);
        }
    }
    for (i, key) in [
        (QSO_DATE, "record.qso_date"),
        (QSO_DATE_OFF, "record.qso_date_off"),
    ] {
        if !v(i).is_some_and(valid_date) {
            return Err(key);
        }
    }
    for (i, key) in [(TIME_ON, "record.time_on"), (TIME_OFF, "record.time_off")] {
        if !v(i).is_some_and(|t| valid_time(t, true)) {
            return Err(key);
        }
    }
    let on = format!("{}{}", v(QSO_DATE).unwrap_or(""), v(TIME_ON).unwrap_or(""));
    let off = format!(
        "{}{}",
        v(QSO_DATE_OFF).unwrap_or(""),
        v(TIME_OFF).unwrap_or("")
    );
    if off < on {
        return Err("record.time_off");
    }
    if v(BAND).is_some_and(|b| !BANDS.iter().any(|(name, _, _)| *name == b)) {
        return Err("record.band");
    }
    if let Some(freq) = v(FREQ) {
        let six = freq
            .split_once('.')
            .is_some_and(|(w, f)| !w.is_empty() && f.len() == 6);
        if !six || !positive_decimal(freq) {
            return Err("record.freq");
        }
        if v(BAND).is_some_and(|b| band_of_mhz(freq).as_deref() != Some(b)) {
            return Err("record.freq");
        }
    }
    if callsign.is_empty() || v(12) != Some(callsign) {
        return Err("record.station_callsign");
    }
    let expected = (!locator.is_empty()).then_some(locator);
    if v(13) != expected {
        return Err("record.my_gridsquare");
    }
    if v(14).is_some_and(|p| p.len() > 16 || !positive_decimal(p)) {
        return Err("record.tx_pwr");
    }
    if v(15).is_some_and(|c| {
        c.is_empty() || c.len() > FIELD_CHARACTERS_MAX || !printable(c) || c.contains(['<', '>'])
    }) {
        return Err("record.comment");
    }
    // Contest exchange fields (#24 S2b, LogRecord): STX/SRX 1-4 digits, the others at
    // most 32 printable characters without '<' and '>'.
    for (i, name) in FIELDS.iter().enumerate().take(CONFIRMATION).skip(CONTEST) {
        let Some(value) = v(i) else { continue };
        if !valid_contest_value(name, value) {
            return Err(match *name {
                "stx" => "record.stx",
                "stx_string" => "record.stx_string",
                "srx" => "record.srx",
                "contest_id" => "record.contest_id",
                "srx_string" => "record.srx_string",
                "class" => "record.class",
                "arrl_sect" => "record.arrl_sect",
                _ => "record.state",
            });
        }
    }
    Ok(())
}
