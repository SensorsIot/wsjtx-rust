//! CR #10 persistent contact log (WstxContact::LogRecord, SaveContact, ImportAdi,
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
    sync::Mutex,
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
pub const WORKED_CALLS_MAX: usize = 64;
pub const FILE_NAME: &str = "contacts.adi";
const ID_FIELD: &str = "app_wstxrust_contact_id";
const RECEIPTS: usize = 16;
const IMPORT_IDLE: Duration = Duration::from_secs(60);

/// Supported LogRecord fields in WSJT-X to_adif order (contact id follows them).
pub const FIELDS: [&str; 16] = [
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

/// ADIF 3.1.8 band enumeration with inclusive limits in Hz.
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
    pub values: [Option<String>; 16],
    pub unknown: Vec<Unknown>,
}
impl Record {
    pub fn get(&self, name: &str) -> Option<&str> {
        let index = FIELDS.iter().position(|f| *f == name)?;
        self.values[index].as_deref()
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
    fn natural_key(&self) -> (String, String, String, String, String, String) {
        let value = |i: usize| self.values[i].clone().unwrap_or_default();
        (
            value(CALL).to_ascii_uppercase(),
            value(QSO_DATE),
            value(TIME_ON).chars().take(4).collect(),
            self.effective_band().unwrap_or_default(),
            value(MODE).to_ascii_uppercase(),
            value(SUBMODE).to_ascii_uppercase(),
        )
    }
    pub fn history_json(&self, index: usize) -> Value {
        let mut object = serde_json::Map::new();
        object.insert("index".into(), json!(index));
        object.insert("contact_id".into(), json!(self.contact_id));
        for (name, value) in FIELDS.iter().zip(&self.values) {
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
            line.push_str(&value.len().to_string());
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
/// Report rendering of WstxContact::ReportRange, "%+2.2d" in -50..+49.
pub fn valid_report(value: &str) -> bool {
    let b = value.as_bytes();
    b.len() == 3
        && (b[0] == b'+' || b[0] == b'-')
        && b[1..].iter().all(u8::is_ascii_digit)
        && value.parse::<i32>().is_ok_and(|n| (-50..=49).contains(&n))
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
type RawField = (String, Option<String>, String);
fn text_byte(b: u8) -> bool {
    (0x20..=0x7e).contains(&b) || matches!(b, b'\t' | b'\r' | b'\n')
}
/// ADIF 3.1.8 ADI only. Header present when the first character is not '<', ended by
/// <EOH>. Tags <NAME:LEN[:TYPE]> are case-insensitive and LEN is exact; text between
/// fields of a record must be white space so that an inexact LEN is detected
/// (lengthMismatch) instead of silently truncating a value.
pub fn parse(bytes: &[u8], limits: &Limits) -> Result<Vec<Vec<RawField>>, Fault> {
    let mut records = Vec::new();
    let mut current: Vec<RawField> = Vec::new();
    let mut in_header = bytes.first().is_some_and(|b| *b != b'<');
    let mut position = 0;
    let at = |records: &Vec<Vec<RawField>>| Some(records.len());
    loop {
        let next = bytes[position..].iter().position(|b| *b == b'<');
        let end = next.map_or(bytes.len(), |n| position + n);
        let text = &bytes[position..end];
        if text.iter().any(|b| !text_byte(*b)) {
            return Err(Fault::new("unsupported_character", at(&records), None));
        }
        if !in_header && !current.is_empty() && !text.iter().all(u8::is_ascii_whitespace) {
            let field = current.last().map(|f| f.0.to_ascii_lowercase());
            return Err(Fault::new(
                "length_mismatch",
                at(&records),
                field.as_deref(),
            ));
        }
        let Some(_) = next else {
            if in_header || !current.is_empty() {
                return Err(Fault::new("malformed", at(&records), None));
            }
            return Ok(records);
        };
        let open = end;
        let Some(close) = bytes[open + 1..].iter().position(|b| *b == b'>') else {
            return Err(Fault::new("malformed", at(&records), None));
        };
        let close = open + 1 + close;
        let tag = &bytes[open + 1..close];
        if tag.iter().any(|b| !(0x20..=0x7e).contains(b)) {
            return Err(Fault::new(
                if tag.iter().all(|b| text_byte(*b)) {
                    "malformed"
                } else {
                    "unsupported_character"
                },
                at(&records),
                None,
            ));
        }
        let tag =
            std::str::from_utf8(tag).map_err(|_| Fault::new("malformed", at(&records), None))?;
        let mut parts = tag.split(':');
        let name = parts.next().unwrap_or("");
        if name.len() > FIELD_NAME_CHARACTERS_MAX {
            return Err(Fault::new("field_too_long", at(&records), None));
        }
        if name.is_empty()
            || name
                .bytes()
                .any(|b| matches!(b, b',' | b':' | b'<' | b'>' | b'{' | b'}' | b' '))
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
            || !length.bytes().all(|b| b.is_ascii_digit())
            || kind.is_some_and(|k| k.len() != 1 || !k.bytes().all(|b| b.is_ascii_alphabetic()))
        {
            return Err(Fault::new("malformed", at(&records), Some(&lname)));
        }
        let length: usize = length
            .parse()
            .map_err(|_| Fault::new("malformed", at(&records), Some(&lname)))?;
        if length > FIELD_CHARACTERS_MAX {
            return Err(Fault::new("field_too_long", at(&records), Some(&lname)));
        }
        let start = close + 1;
        let Some(stop) = start.checked_add(length).filter(|s| *s <= bytes.len()) else {
            return Err(Fault::new("length_mismatch", at(&records), Some(&lname)));
        };
        let value = &bytes[start..stop];
        if !value.iter().all(|b| text_byte(*b)) {
            return Err(Fault::new(
                "unsupported_character",
                at(&records),
                Some(&lname),
            ));
        }
        if !in_header {
            current.push((
                name.to_owned(),
                kind.map(str::to_owned),
                String::from_utf8_lossy(value).into_owned(),
            ));
        }
        position = stop;
    }
}
/// Interpret one parsed record; the contact id stays empty when the file has none.
fn interpret(index: usize, raw: Vec<RawField>) -> Result<Record, Fault> {
    let mut record = Record::default();
    let mut seen_id = false;
    for (name, kind, value) in raw {
        let lname = name.to_ascii_lowercase();
        let supported = FIELDS.iter().position(|f| *f == lname);
        if supported.is_none() && lname != ID_FIELD {
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
            if record.values[i].is_some() {
                return Err(Fault::new("malformed", Some(index), Some(&lname)));
            }
            if !value.is_empty() {
                if !valid_import_value(i, &value) {
                    return Err(Fault::new("invalid_value", Some(index), Some(&lname)));
                }
                record.values[i] = Some(value);
            }
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
        .into_iter()
        .enumerate()
        .map(|(i, raw)| interpret(i, raw))
        .collect()
}

/// First differing supported field. With `natural` (an import record without contact
/// id matched by natural key), a value absent on either side carries no information.
fn first_difference(a: &Record, b: &Record, natural: bool) -> Option<&'static str> {
    for (i, name) in FIELDS.iter().enumerate() {
        let (x, y) = (a.values[i].as_deref(), b.values[i].as_deref());
        let (x, y) = match (x, y) {
            (None, None) => continue,
            (Some(_), None) | (None, Some(_)) if natural => continue,
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
struct Import {
    id: String,
    total: u64,
    sha256: String,
    bytes: Vec<u8>,
    received: u64,
    state: ImportState,
    counts: (usize, usize, usize),
    error: Option<Fault>,
    touched: Instant,
}
impl Import {
    fn view(&self) -> Value {
        json!({"v":1,"id":self.id,"state":match self.state {
            ImportState::Receiving=>"receiving",ImportState::Completed=>"completed",ImportState::Failed=>"failed"},
            "received_bytes":self.received,"total_bytes":self.total,
            "new":self.counts.0,"duplicate":self.counts.1,"conflict":self.counts.2,
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
    records: Vec<Record>,
    ids: HashMap<String, usize>,
    created: String,
    import: Option<Import>,
    receipts: VecDeque<Receipt>,
    /// Counts every change of `records` (#55 worked-set cache key).
    revision: u64,
    #[cfg(test)]
    fault: Option<&'static str>,
}
pub struct Logbook {
    directory: PathBuf,
    inner: Mutex<Inner>,
    /// #55 the country table of this profile (WSJT-X keeps AD1CCty in WorkedBefore).
    dxcc: Mutex<DxccState>,
    /// #55 the worked set of the log for (records revision, country table), rebuilt only
    /// when either changes: /receive/results reads it on every page.
    worked_set: Mutex<Option<(u64, usize, std::sync::Arc<crate::dxcc::Worked>)>>,
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
                records,
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
        let mut next = inner.records.clone();
        next.extend(new);
        self.publish(inner, &next, gate)?;
        inner.ids = next
            .iter()
            .enumerate()
            .map(|(i, r)| (r.contact_id.clone(), i))
            .collect();
        inner.records = next;
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
                if first_difference(stored, &record, false).is_none() && stored.unknown.is_empty() {
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
        if first_difference(&inner.records[index], &record, false).is_none() {
            return Ok(LogOutcome::AlreadySaved);
        }
        let mut next = inner.records.clone();
        next[index] = Record {
            unknown: next[index].unknown.clone(),
            ..record
        };
        self.publish(&inner, &next, gate)?;
        inner.records = next;
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
    pub fn export(&self) -> Result<Vec<u8>, StoreError> {
        let inner = self.lock()?;
        Ok(document(&utc_timestamp(), &inner.records))
    }
    /// WorkedBeforeQuery over the stored log (including contacts saved this session).
    pub fn worked(
        &self,
        calls: &[String],
        band: &str,
        mode: &str,
    ) -> Result<Vec<&'static str>, StoreError> {
        let inner = self.lock()?;
        let wanted: HashMap<String, usize> = calls
            .iter()
            .enumerate()
            .map(|(i, c)| (c.to_ascii_uppercase(), i))
            .collect();
        let mut status = vec![0u8; calls.len()];
        let (band, mode) = (band.to_ascii_lowercase(), mode.to_ascii_uppercase());
        for record in &inner.records {
            let call = record.values[CALL]
                .as_deref()
                .unwrap_or("")
                .to_ascii_uppercase();
            if !wanted.contains_key(&call) {
                continue;
            }
            let here = record.effective_band().as_deref() == Some(band.as_str())
                && record.effective_mode() == mode;
            for (i, c) in calls.iter().enumerate() {
                if c.eq_ignore_ascii_case(&call) {
                    status[i] = status[i].max(if here { 2 } else { 1 });
                }
            }
        }
        Ok(status
            .into_iter()
            .map(|s| match s {
                2 => "worked_this_band_and_mode",
                1 => "worked_other_band_or_mode",
                _ => "not_worked",
            })
            .collect())
    }

    /// #55 the (call, band) of every logged contact, for the entity worked status.
    /// #55 WorkedBefore of the stored log against the current country table (cached).
    pub fn worked_set(&self) -> Result<std::sync::Arc<crate::dxcc::Worked>, StoreError> {
        let (table, _) = self.dxcc();
        let key_table = std::sync::Arc::as_ptr(&table.cty) as usize;
        let (revision, logged) = {
            let inner = self.lock()?;
            if let Some((r, t, w)) = &*self.worked_set.lock().unwrap_or_else(|p| p.into_inner())
                && (*r, *t) == (inner.revision, key_table)
            {
                return Ok(w.clone());
            }
            let logged: Vec<crate::dxcc::Logged> = inner
                .records
                .iter()
                .map(|r| crate::dxcc::Logged {
                    call: r.values[CALL].clone().unwrap_or_default(),
                    grid: r.values[GRID].clone(),
                    band: r.effective_band(),
                })
                .collect();
            (inner.revision, logged)
        };
        let worked = std::sync::Arc::new(crate::dxcc::Worked::from_log(&table, &logged));
        *self.worked_set.lock().unwrap_or_else(|p| p.into_inner()) =
            Some((revision, key_table, worked.clone()));
        Ok(worked)
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

    /// #39 WstxStrategy new_grid: the same query over the 4-character grid square
    /// (GRIDSQUARE), case-insensitive.
    pub fn worked_grids(
        &self,
        grids: &[String],
        band: &str,
        mode: &str,
    ) -> Result<Vec<&'static str>, StoreError> {
        let inner = self.lock()?;
        let square = |g: &str| g.get(..4).map(str::to_ascii_uppercase);
        let mut status = vec![0u8; grids.len()];
        let (band, mode) = (band.to_ascii_lowercase(), mode.to_ascii_uppercase());
        for record in &inner.records {
            let Some(grid) = record.values[GRID].as_deref().and_then(square) else {
                continue;
            };
            let here = record.effective_band().as_deref() == Some(band.as_str())
                && record.effective_mode() == mode;
            for (i, g) in grids.iter().enumerate() {
                if square(g).as_deref() == Some(grid.as_str()) {
                    status[i] = status[i].max(if here { 2 } else { 1 });
                }
            }
        }
        Ok(status
            .into_iter()
            .map(|s| match s {
                2 => "worked_this_band_and_mode",
                1 => "worked_other_band_or_mode",
                _ => "not_worked",
            })
            .collect())
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
            counts: (0, 0, 0),
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
            Err((Fault::new("integrity_mismatch", None, None), (0, 0, 0)))
        } else {
            self.classify(&inner, &import.bytes)
        };
        let outcome = match result {
            Err((fault, counts)) => {
                import.state = ImportState::Failed;
                import.counts = counts;
                import.error = Some(fault);
                Err("import_failed")
            }
            Ok((new, counts)) => {
                import.counts = counts;
                match self.append(&mut inner, new, gate) {
                    Ok(()) => {
                        import.state = ImportState::Completed;
                        Ok(())
                    }
                    Err(StoreError::Unauthorized(_)) => {
                        import.state = ImportState::Failed;
                        Err("unauthorized")
                    }
                    Err(StoreError::Unavailable) => {
                        import.state = ImportState::Failed;
                        Err("storage_unavailable")
                    }
                }
            }
        };
        import.bytes = Vec::new();
        let view = import.view();
        inner.import = Some(import);
        outcome.map(|()| view)
    }
    /// Validation before publication: parse, then classify every record as new,
    /// duplicate or conflict against stored records and earlier records of the file.
    #[allow(clippy::type_complexity)]
    fn classify(
        &self,
        inner: &Inner,
        bytes: &[u8],
    ) -> Result<(Vec<Record>, (usize, usize, usize)), (Fault, (usize, usize, usize))> {
        let records = parse_records(
            bytes,
            &Limits {
                records: IMPORT_RECORDS_MAX,
            },
        )
        .map_err(|fault| (fault, (0, 0, 0)))?;
        let mut by_id: HashMap<String, Record> = HashMap::new();
        let mut by_key: HashMap<_, Record> = HashMap::new();
        for record in &inner.records {
            by_id
                .entry(record.contact_id.clone())
                .or_insert_with(|| record.clone());
            by_key
                .entry(record.natural_key())
                .or_insert_with(|| record.clone());
        }
        let (mut new, mut duplicate, mut conflict) = (Vec::new(), 0, 0);
        let mut first_conflict = None;
        for (index, mut record) in records.into_iter().enumerate() {
            let natural = record.contact_id.is_empty();
            let existing = if natural {
                by_key.get(&record.natural_key())
            } else {
                by_id.get(&record.contact_id)
            };
            match existing.map(|stored| first_difference(stored, &record, natural)) {
                Some(None) => duplicate += 1,
                Some(Some(field)) => {
                    conflict += 1;
                    first_conflict.get_or_insert(Fault::new(
                        "identity_conflict",
                        Some(index),
                        Some(field),
                    ));
                }
                None => {
                    if natural {
                        record.contact_id = crate::profile::new_uuid()
                            .map_err(|_| (Fault::new("malformed", Some(index), None), (0, 0, 0)))?;
                    }
                    by_id.insert(record.contact_id.clone(), record.clone());
                    by_key
                        .entry(record.natural_key())
                        .or_insert_with(|| record.clone());
                    new.push(record);
                }
            }
        }
        let counts = (new.len(), duplicate, conflict);
        match first_conflict {
            Some(fault) => Err((fault, counts)),
            None => Ok((new, counts)),
        }
    }
}

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
    Ok(())
}
