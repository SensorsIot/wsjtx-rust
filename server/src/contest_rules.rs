#![forbid(unsafe_code)]
//! WstxContest (#98): the contest file. Every contest is one record of one validated JSON
//! file (ContestFile, ContestEncoding, ContestProfile): its schedule with time zones
//! (ScheduleRule), its modes, exchange, dupe dimensions, points and score as small
//! expressions (ContestExpression), multipliers, window, cap, automation clause and entry
//! parameters. Nothing here evaluates a log (contest.rs does).
use crate::contact::{civil, parse_utc};
use serde_json::{Map, Value, json};
use std::collections::BTreeMap;
use std::sync::{Arc, OnceLock};

/// ContestFile::bytesMax.
pub(crate) const BYTES_MAX: usize = 1_048_576;
/// The bundled file, embedded in the station.
pub(crate) const BUNDLED: &str = include_str!("../data/contests.json");
pub(crate) const SILENT_TEXT: &str = "The rules do not address automatic operation.";

/// The ADIF bands a record may name (ProfileTable: HF6, 60m, 30m, 17m, 12m and VHF).
pub(crate) const BANDS: &[&str] = &[
    "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m", "5m", "4m", "2m",
    "1.25m", "70cm", "33cm", "23cm", "13cm", "9cm", "6cm", "3cm", "1.25cm", "6mm", "4mm", "2.5mm",
    "2mm", "1mm", "submm",
];
/// ModeRule names.
const MODE_NAMES: &[&str] = &[
    "FT8", "FT4", "RTTY", "PSK31", "PSK63", "CW", "SSB", "AM", "FM",
];
const ACTIVITIES: &[&str] = &[
    "none",
    "na_vhf",
    "ww_digi",
    "arrl_digi",
    "field_day",
    "rtty",
    "eu_vhf",
];
const FIELDS: &[&str] = &[
    "grid4",
    "grid6",
    "report",
    "rst",
    "serial",
    "fd_class",
    "section",
    "state_province",
    "canton",
    "province",
    "member_flag",
    "county",
];
const PARAM_NAMES: &[&str] = &[
    "section",
    "hours",
    "days",
    "rover",
    "member",
    "power",
    "category",
    "canton",
    "province",
    "fd_class",
    "single_band",
];
const RESTRICTIONS: &[&str] = &[
    "single_signal",
    "no_multistream",
    "no_alternating_cq",
    "standard_messages_only",
    "self_spot_forbidden",
    "self_spot_limited",
    "self_spot_allowed",
];

// ------------------------------------------------------------------ the parts
/// The mode class of a logged or station mode (phone, CW, digital).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub(crate) enum ModeClass {
    Phone,
    Cw,
    Digital,
}
impl ModeClass {
    pub(crate) fn of(mode: &str) -> Self {
        match mode.to_ascii_uppercase().as_str() {
            "CW" => ModeClass::Cw,
            "SSB" | "USB" | "LSB" | "AM" | "FM" | "DIGITALVOICE" => ModeClass::Phone,
            _ => ModeClass::Digital,
        }
    }
    pub(crate) fn name(self) -> &'static str {
        match self {
            ModeClass::Phone => "phone",
            ModeClass::Cw => "cw",
            ModeClass::Digital => "digital",
        }
    }
}
/// WstxContest::AutomationClause.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Clause {
    Forbidden,
    Silent,
    Permitted,
}
impl Clause {
    pub(crate) fn name(self) -> &'static str {
        match self {
            Clause::Forbidden => "forbidden",
            Clause::Silent => "silent",
            Clause::Permitted => "permitted",
        }
    }
    fn parse(s: &str) -> Option<Self> {
        match s {
            "forbidden" => Some(Clause::Forbidden),
            "silent" => Some(Clause::Silent),
            "permitted" => Some(Clause::Permitted),
            _ => None,
        }
    }
}
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct LogFormat {
    pub format: String,
    pub contest: Option<String>,
    pub confirmed: bool,
}
/// n of a day rule: a number, the last, or every.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Nth {
    N(usize),
    Last,
    Every,
}
/// ScheduleRule day rules.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum DayRule {
    FullWeekend {
        n: Nth,
        month: u32,
    },
    /// weekday 0 Sunday .. 6 Saturday; months None: all.
    Weekday {
        weekday: i64,
        n: Nth,
        months: Option<Vec<u32>>,
    },
    Date {
        month: u32,
        day: u32,
    },
    Dates(Vec<(i64, u32, u32)>),
    Asked,
}
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Round {
    pub day: DayRule,
    /// Minutes from 00:00 local of the anchor day.
    pub start_min: i64,
    pub end_min: i64,
    pub bands: Option<Vec<String>>,
    pub label: Option<String>,
}
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum Limit {
    Number(f64),
    Param(String),
}
/// ScoredWindow.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Window {
    pub limit: Limit,
    pub utc_day: bool,
    pub best: bool,
    pub min_off_minutes: i64,
}
/// SeriesRule (shown, not computed).
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Series {
    pub best: u64,
    pub of: u64,
    pub per: String,
    pub normalise: String,
    pub annual: Option<String>,
}
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Schedule {
    pub tz: Zone,
    pub tz_name: String,
    pub rounds: Vec<Round>,
    pub text: String,
    pub series: Option<Series>,
    pub window: Option<Window>,
}
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum Count {
    List(Vec<String>),
    Digital,
    DigitalNoRtty,
    Any,
}
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum AsOne {
    All,
    Groups(Vec<Vec<String>>),
}
/// ModeRule.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Modes {
    pub count: Count,
    pub as_one: AsOne,
}
impl Modes {
    /// The counted mode name of a contact (MODE or SUBMODE, case-insensitive), None when the
    /// record does not count it. For a class the name is the SUBMODE, else the MODE.
    pub(crate) fn counted(&self, mode: &str, submode: Option<&str>) -> Option<String> {
        let mode = mode.to_ascii_uppercase();
        let sub = submode.map(str::to_ascii_uppercase).filter(|s| !s.is_empty());
        match &self.count {
            Count::List(names) => names
                .iter()
                .find(|n| **n == mode || sub.as_deref() == Some(n.as_str()))
                .cloned(),
            Count::Any => Some(sub.unwrap_or(mode)),
            Count::Digital => {
                (ModeClass::of(&mode) == ModeClass::Digital).then(|| sub.unwrap_or(mode))
            }
            Count::DigitalNoRtty => (ModeClass::of(&mode) == ModeClass::Digital
                && mode != "RTTY"
                && sub.as_deref() != Some("RTTY"))
            .then(|| sub.unwrap_or(mode)),
        }
    }
    /// The station's own mode (FT8 or FT4).
    pub(crate) fn counts_station(&self, mode: &str) -> bool {
        let m = mode.to_ascii_uppercase();
        match m.as_str() {
            "FT4" => self.counted("MFSK", Some("FT4")).is_some(),
            _ => self.counted(&m, None).is_some(),
        }
    }
    /// The dupe dimension mode_group of a counted name.
    pub(crate) fn group(&self, name: &str) -> String {
        match &self.as_one {
            AsOne::All => "all".into(),
            AsOne::Groups(groups) => groups
                .iter()
                .position(|g| g.iter().any(|n| n == name))
                .map_or_else(|| name.to_owned(), |i| format!("#{i}")),
        }
    }
    /// The mode classes the record can count (for a class table without else).
    fn classes(&self) -> Vec<ModeClass> {
        match &self.count {
            Count::List(names) => names.iter().map(|n| ModeClass::of(n)).collect(),
            Count::Digital | Count::DigitalNoRtty => vec![ModeClass::Digital],
            Count::Any => vec![ModeClass::Phone, ModeClass::Cw, ModeClass::Digital],
        }
    }
}
/// ExchangeRule.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Exchange {
    pub activity: String,
    pub cq: Option<String>,
    pub sent: Vec<String>,
    pub rcvd: Vec<String>,
    pub unsendable_for: Option<Expr>,
}
/// DupeRule dimensions.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Dim {
    Band,
    Mode,
    ModeGroup,
    ModeClass,
    Round,
    UtcDay,
    TheirGrid4,
    MyGrid4,
}
impl Dim {
    fn parse(s: &str) -> Option<Self> {
        Some(match s {
            "band" => Dim::Band,
            "mode" => Dim::Mode,
            "mode_group" => Dim::ModeGroup,
            "mode_class" => Dim::ModeClass,
            "round" => Dim::Round,
            "utc_day" => Dim::UtcDay,
            "their_grid4" => Dim::TheirGrid4,
            "my_grid4" => Dim::MyGrid4,
            _ => return None,
        })
    }
    pub(crate) fn name(self) -> &'static str {
        match self {
            Dim::Band => "band",
            Dim::Mode => "mode",
            Dim::ModeGroup => "mode_group",
            Dim::ModeClass => "mode_class",
            Dim::Round => "round",
            Dim::UtcDay => "utc_day",
            Dim::TheirGrid4 => "their_grid4",
            Dim::MyGrid4 => "my_grid4",
        }
    }
    pub(crate) fn grid(self) -> bool {
        matches!(self, Dim::TheirGrid4 | Dim::MyGrid4)
    }
}
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Dupe {
    pub per: Vec<Dim>,
    pub best: bool,
}
/// MultiplierRule kinds.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum MultKind {
    Dxcc,
    Wpx,
    Continent,
    CqZone,
    ItuZone,
    GridField,
    Grid4,
    MyGrid4,
    CallArea(String),
    Exchange(String),
    Call,
}
impl MultKind {
    fn name(&self) -> String {
        match self {
            MultKind::Dxcc => "dxcc".into(),
            MultKind::Wpx => "wpx".into(),
            MultKind::Continent => "continent".into(),
            MultKind::CqZone => "cq_zone".into(),
            MultKind::ItuZone => "itu_zone".into(),
            MultKind::GridField => "grid_field".into(),
            MultKind::Grid4 => "grid4".into(),
            MultKind::MyGrid4 => "my_grid4".into(),
            MultKind::CallArea(n) => format!("call_area:{n}"),
            MultKind::Exchange(f) => format!("exchange:{f}"),
            MultKind::Call => "call".into(),
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Per {
    Contest,
    Band,
    BandMode,
    Round,
    BandRound,
}
impl Per {
    fn parse(s: &str) -> Option<Self> {
        Some(match s {
            "contest" => Per::Contest,
            "band" => Per::Band,
            "band_mode" => Per::BandMode,
            "round" => Per::Round,
            "band_round" => Per::BandRound,
            _ => return None,
        })
    }
    fn name(self) -> &'static str {
        match self {
            Per::Contest => "contest",
            Per::Band => "band",
            Per::BandMode => "band_mode",
            Per::Round => "round",
            Per::BandRound => "band_round",
        }
    }
}
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Multiplier {
    pub name: String,
    pub kind: MultKind,
    pub per: Per,
    pub only: Option<Expr>,
    pub all_bands: bool,
}
/// PointsRule points_cap.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Cap {
    pub when: Expr,
    pub n: u64,
    pub d: u64,
}
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Automation {
    pub clause: Clause,
    pub text: String,
    pub reference: Option<String>,
    pub by_section: Vec<(String, Clause, String)>,
}
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum Choices {
    Bool,
    Words(Vec<String>),
    Numbers(Vec<i64>),
}
/// An entry parameter's value.
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub(crate) enum PValue {
    Bool(bool),
    Word(String),
    Number(i64),
}
impl PValue {
    pub(crate) fn json(&self) -> Value {
        match self {
            PValue::Bool(b) => json!(b),
            PValue::Word(w) => json!(w),
            PValue::Number(n) => json!(n),
        }
    }
}
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Param {
    pub name: String,
    pub choices: Choices,
    pub default: PValue,
}
impl Param {
    /// One of its choices from JSON, else None.
    pub(crate) fn value(&self, v: &Value) -> Option<PValue> {
        match &self.choices {
            Choices::Bool => v.as_bool().map(PValue::Bool),
            Choices::Words(w) => v
                .as_str()
                .filter(|s| w.iter().any(|c| c == s))
                .map(|s| PValue::Word(s.to_owned())),
            Choices::Numbers(n) => v.as_i64().filter(|x| n.contains(x)).map(PValue::Number),
        }
    }
    fn choices_json(&self) -> Value {
        match &self.choices {
            Choices::Bool => json!("bool"),
            Choices::Words(w) => json!(w),
            Choices::Numbers(n) => json!(n),
        }
    }
    pub(crate) fn json(&self) -> Value {
        json!({"name":self.name,"choices":self.choices_json(),"default":self.default.json()})
    }
}
/// EntryRule.
#[derive(Clone, Debug, PartialEq, Default)]
pub(crate) struct Entry {
    pub eligible: Option<Expr>,
    pub workable: Option<Expr>,
    pub params: Vec<Param>,
}
/// WstxContest::ContestProfile: one record, rule facts only.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Profile {
    pub id: String,
    pub name: String,
    pub organiser: String,
    pub source: String,
    pub checked: String,
    pub log: LogFormat,
    pub schedule: Schedule,
    pub bands: Vec<String>,
    pub modes: Modes,
    pub exchange: Exchange,
    pub dupe: Dupe,
    pub points: Expr,
    pub points_cap: Option<Cap>,
    pub multipliers: Vec<Multiplier>,
    pub score: Expr,
    pub extras: Vec<String>,
    pub automation: Automation,
    pub restrictions: Vec<String>,
    pub entry: Entry,
    pub members: Option<String>,
    pub notes: Vec<String>,
    pub unconfirmed: Vec<String>,
}
/// WstxContest::ContestFile parsed.
#[derive(Clone, Debug, PartialEq, Default)]
pub(crate) struct File {
    pub contests: Vec<Arc<Profile>>,
    pub sets: BTreeMap<String, Vec<String>>,
    pub call_areas: BTreeMap<String, BTreeMap<String, String>>,
    pub call_lists: BTreeMap<String, Vec<String>>,
}
/// A refusal: the JSON path of the first fault and a reason.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Fault {
    pub path: String,
    pub reason: String,
}
fn fault(path: impl Into<String>, reason: impl Into<String>) -> Fault {
    Fault {
        path: path.into(),
        reason: reason.into(),
    }
}
type R<T> = Result<T, Fault>;

/// The bundled file, parsed once (its test fails when it does not validate).
pub(crate) fn bundled() -> Arc<File> {
    static FILE: OnceLock<Arc<File>> = OnceLock::new();
    FILE.get_or_init(|| {
        Arc::new(
            File::parse(BUNDLED.as_bytes(), &crate::dxcc::Table::default())
                .expect("the bundled contest file validates"),
        )
    })
    .clone()
}

impl File {
    pub(crate) fn profile(&self, id: &str) -> Option<&Arc<Profile>> {
        self.contests.iter().find(|p| p.id == id)
    }
    /// The SARL-style area of a call: the longest prefix that starts it, else "*".
    pub(crate) fn call_area(&self, table: &str, call: &str) -> Option<String> {
        let t = self.call_areas.get(table)?;
        let call = call.to_ascii_uppercase();
        t.iter()
            .filter(|(p, _)| p.as_str() != "*" && call.starts_with(p.as_str()))
            .max_by_key(|(p, _)| p.len())
            .map(|(_, a)| a.clone())
            .or_else(|| t.get("*").cloned())
    }
    /// ContestFile validation, complete before anything changes.
    pub(crate) fn parse(bytes: &[u8], cty: &crate::dxcc::Table) -> R<File> {
        if bytes.len() > BYTES_MAX {
            return Err(fault("", format!("larger than {BYTES_MAX} bytes")));
        }
        let text = std::str::from_utf8(bytes).map_err(|_| fault("", "not UTF-8"))?;
        let v: Value = serde_json::from_str(text).map_err(|_| fault("", "not JSON"))?;
        let o = obj(
            &v,
            "",
            &["format", "contests"],
            &["sets", "call_areas", "call_lists"],
        )?;
        if v["format"] != json!(1) {
            return Err(fault("format", "must be 1"));
        }
        let mut file = File::default();
        if let Some(sets) = o.get("sets") {
            let m = sets.as_object().ok_or(fault("sets", "an object"))?;
            for (name, members) in m {
                let p = format!("sets.{name}");
                if !upper_name(name, 12) {
                    return Err(fault(p, "a name of 1..12 letters A-Z or _"));
                }
                let list = members.as_array().ok_or(fault(&p, "a list"))?;
                let mut out = Vec::new();
                for (i, m) in list.iter().enumerate() {
                    let mp = format!("{p}[{i}]");
                    let s = m.as_str().ok_or(fault(&mp, "a prefix"))?;
                    if !cty.cty.has_primary(s) {
                        return Err(fault(mp, "not the primary prefix of a cty.dat entity"));
                    }
                    out.push(s.to_owned());
                }
                file.sets.insert(name.clone(), out);
            }
        }
        if let Some(areas) = o.get("call_areas") {
            let m = areas.as_object().ok_or(fault("call_areas", "an object"))?;
            for (name, table) in m {
                let p = format!("call_areas.{name}");
                if !upper_name(name, 12) {
                    return Err(fault(p, "a name of 1..12 letters A-Z or _"));
                }
                let t = table.as_object().ok_or(fault(&p, "an object"))?;
                let mut out = BTreeMap::new();
                for (prefix, area) in t {
                    let ap = format!("{p}.{prefix}");
                    if prefix != "*"
                        && !(1..=8).contains(&prefix.len())
                        && prefix.bytes().all(|b| b.is_ascii_uppercase() || b.is_ascii_digit())
                    {
                        return Err(fault(ap, "a call prefix or *"));
                    }
                    let a = area
                        .as_str()
                        .filter(|a| printable(a, 1, 16))
                        .ok_or(fault(&ap, "an area of 1..16 characters"))?;
                    out.insert(prefix.clone(), a.to_owned());
                }
                file.call_areas.insert(name.clone(), out);
            }
        }
        if let Some(lists) = o.get("call_lists") {
            let m = lists.as_object().ok_or(fault("call_lists", "an object"))?;
            for (name, calls) in m {
                let p = format!("call_lists.{name}");
                if !upper_name(name, 12) {
                    return Err(fault(p, "a name of 1..12 letters A-Z or _"));
                }
                let list = calls.as_array().ok_or(fault(&p, "a list"))?;
                let mut out = Vec::new();
                for (i, c) in list.iter().enumerate() {
                    let s = c
                        .as_str()
                        .filter(|s| {
                            (1..=13).contains(&s.len())
                                && s.bytes().all(|b| {
                                    b.is_ascii_uppercase() || b.is_ascii_digit() || b == b'/'
                                })
                        })
                        .ok_or(fault(format!("{p}[{i}]"), "a call"))?;
                    out.push(s.to_owned());
                }
                file.call_lists.insert(name.clone(), out);
            }
        }
        let list = o
            .get("contests")
            .and_then(Value::as_array)
            .ok_or(fault("contests", "a list"))?;
        if list.is_empty() {
            return Err(fault("contests", "at least one contest"));
        }
        for (i, c) in list.iter().enumerate() {
            let p = profile(c, &format!("contests[{i}]"), &file)?;
            if file.contests.iter().any(|o| o.id == p.id) {
                return Err(fault(format!("contests[{i}].id"), "an id twice"));
            }
            file.contests.push(Arc::new(p));
        }
        let _ = o;
        Ok(file)
    }
}
fn upper_name(s: &str, max: usize) -> bool {
    (1..=max).contains(&s.len()) && s.bytes().all(|b| b.is_ascii_uppercase() || b == b'_')
}
fn printable(s: &str, min: usize, max: usize) -> bool {
    (min..=max).contains(&s.len()) && s.bytes().all(|b| (0x20..0x7f).contains(&b))
}

// ------------------------------------------------------------------ JSON reading
struct Obj<'a> {
    o: &'a Map<String, Value>,
}
impl<'a> Obj<'a> {
    fn get(&self, k: &str) -> Option<&'a Value> {
        self.o.get(k)
    }
}
fn join(path: &str, key: &str) -> String {
    if path.is_empty() {
        key.to_owned()
    } else {
        format!("{path}.{key}")
    }
}
/// An object with exactly these required and optional keys.
fn obj<'a>(v: &'a Value, path: &str, required: &[&str], optional: &[&str]) -> R<Obj<'a>> {
    let o = v.as_object().ok_or(fault(path, "an object"))?;
    for k in o.keys() {
        if !required.contains(&k.as_str()) && !optional.contains(&k.as_str()) {
            return Err(fault(join(path, k), "an unknown key"));
        }
    }
    for k in required {
        if !o.contains_key(*k) {
            return Err(fault(join(path, k), "a required key is missing"));
        }
    }
    Ok(Obj { o })
}
fn text(v: &Value, path: &str, min: usize, max: usize) -> R<String> {
    v.as_str()
        .filter(|s| printable(s, min, max))
        .map(str::to_owned)
        .ok_or(fault(
            path,
            format!("{min}..{max} printable ASCII characters"),
        ))
}
fn texts(v: Option<&Value>, path: &str) -> R<Vec<String>> {
    let Some(v) = v else { return Ok(Vec::new()) };
    let list = v.as_array().ok_or(fault(path, "a list"))?;
    list.iter()
        .enumerate()
        .map(|(i, s)| text(s, &format!("{path}[{i}]"), 1, 200))
        .collect()
}
fn words(v: &Value, path: &str, allowed: &[&str]) -> R<Vec<String>> {
    let list = v.as_array().ok_or(fault(path, "a list"))?;
    let mut out: Vec<String> = Vec::new();
    for (i, s) in list.iter().enumerate() {
        let p = format!("{path}[{i}]");
        let s = s
            .as_str()
            .filter(|s| allowed.contains(s))
            .ok_or(fault(&p, "an unknown value"))?;
        if out.iter().any(|o| o == s) {
            return Err(fault(p, "a value twice"));
        }
        out.push(s.to_owned());
    }
    Ok(out)
}
fn real_date(s: &str) -> Option<(i64, u32, u32)> {
    let b = s.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' {
        return None;
    }
    let ms = parse_utc(&format!("{s}T00:00:00Z"))?;
    let (y, m, d, ..) = civil(ms);
    (format!("{y:04}-{m:02}-{d:02}") == s).then_some((y, m, d))
}
fn profile(v: &Value, path: &str, file: &File) -> R<Profile> {
    let o = obj(
        v,
        path,
        &[
            "id", "name", "organiser", "source", "checked", "log", "schedule", "bands", "exchange",
            "dupe", "points", "score",
        ],
        &[
            "modes",
            "points_cap",
            "multipliers",
            "extras",
            "automation",
            "restrictions",
            "entry",
            "members",
            "notes",
            "unconfirmed",
        ],
    )?;
    let p = |k: &str| join(path, k);
    let id = v["id"]
        .as_str()
        .filter(|s| {
            (1..=32).contains(&s.len())
                && s.bytes()
                    .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_')
        })
        .ok_or(fault(p("id"), "1..32 characters a-z, 0-9 or _"))?
        .to_owned();
    let name = text(&v["name"], &p("name"), 1, 40)?;
    let organiser = text(&v["organiser"], &p("organiser"), 1, 60)?;
    let source = text(&v["source"], &p("source"), 1, 300)?;
    if !(source.starts_with("https://") || source.starts_with("http://"))
        || source.contains(' ')
        || source.len() <= 8
    {
        return Err(fault(p("source"), "an http or https URL"));
    }
    let checked = v["checked"]
        .as_str()
        .filter(|s| real_date(s).is_some())
        .ok_or(fault(p("checked"), "a real date YYYY-MM-DD"))?
        .to_owned();
    let lp = p("log");
    obj(&v["log"], &lp, &["format", "contest", "confirmed"], &[])?;
    let log = LogFormat {
        format: v["log"]["format"]
            .as_str()
            .filter(|f| ["cabrillo", "edi", "adif", "email"].contains(f))
            .ok_or(fault(join(&lp, "format"), "cabrillo, edi, adif or email"))?
            .to_owned(),
        contest: match &v["log"]["contest"] {
            Value::Null => None,
            c => Some(text(c, &join(&lp, "contest"), 1, 40)?),
        },
        confirmed: v["log"]["confirmed"]
            .as_bool()
            .ok_or(fault(join(&lp, "confirmed"), "true or false"))?,
    };
    let bands = words(&v["bands"], &p("bands"), BANDS)?;
    if bands.is_empty() {
        return Err(fault(p("bands"), "at least one band"));
    }
    let modes = match o.get("modes") {
        None => Modes {
            count: Count::List(vec!["FT8".into(), "FT4".into()]),
            as_one: AsOne::Groups(vec![vec!["FT8".into(), "FT4".into()]]),
        },
        Some(m) => modes(m, &p("modes"))?,
    };
    // Entry first: expressions read its params.
    let entry_params = match o.get("entry") {
        None => Vec::new(),
        Some(e) => {
            obj(
                e,
                &p("entry"),
                &[],
                &["eligible", "workable", "params"],
            )?;
            match e.get("params") {
                None => Vec::new(),
                Some(list) => params(list, &join(&p("entry"), "params"))?,
            }
        }
    };
    let schedule = schedule(&v["schedule"], &p("schedule"), &entry_params)?;
    let mut reach: Vec<String> = bands.clone();
    for r in &schedule.rounds {
        for b in r.bands.iter().flatten() {
            if !reach.contains(b) {
                reach.push(b.clone());
            }
        }
    }
    let members = match o.get("members") {
        None | Some(Value::Null) => None,
        Some(m) => Some(
            m.as_str()
                .filter(|m| file.call_lists.contains_key(*m))
                .ok_or(fault(p("members"), "the name of a call list"))?
                .to_owned(),
        ),
    };
    let env = Env {
        file,
        params: &entry_params,
        bands: &reach,
        classes: modes.classes(),
        mults: Vec::new(),
    };
    let ep = p("exchange");
    obj(
        &v["exchange"],
        &ep,
        &["activity"],
        &["cq", "sent", "rcvd", "unsendable_for"],
    )?;
    let activity = v["exchange"]["activity"]
        .as_str()
        .filter(|a| ACTIVITIES.contains(a))
        .ok_or(fault(join(&ep, "activity"), "an unknown activity"))?
        .to_owned();
    let cq = match v["exchange"].get("cq") {
        None => default_cq(&activity).map(str::to_owned),
        Some(c) => Some(
            c.as_str()
                .filter(|w| {
                    ((1..=4).contains(&w.len()) && w.bytes().all(|b| b.is_ascii_uppercase()))
                        || (w.len() == 3 && w.bytes().all(|b| b.is_ascii_digit()))
                })
                .ok_or(fault(
                    join(&ep, "cq"),
                    "1..4 letters A-Z or three digits",
                ))?
                .to_owned(),
        ),
    };
    let (sent_default, rcvd_default) = default_exchange(&activity);
    let sent = match v["exchange"].get("sent") {
        None => sent_default,
        Some(s) => words(s, &join(&ep, "sent"), FIELDS)?,
    };
    let rcvd = match v["exchange"].get("rcvd") {
        None => rcvd_default,
        Some(s) => words(s, &join(&ep, "rcvd"), FIELDS)?,
    };
    let unsendable_for = match v["exchange"].get("unsendable_for") {
        None => None,
        Some(e) => Some(Expr::parse_in(
            e,
            &join(&ep, "unsendable_for"),
            Ctx::Eligible,
            &env,
        )?),
    };
    let dp = p("dupe");
    obj(&v["dupe"], &dp, &["per"], &["keep"])?;
    let per_list = words(
        &v["dupe"]["per"],
        &join(&dp, "per"),
        &[
            "band",
            "mode",
            "mode_group",
            "mode_class",
            "round",
            "utc_day",
            "their_grid4",
            "my_grid4",
        ],
    )?;
    let dupe = Dupe {
        per: per_list.iter().filter_map(|d| Dim::parse(d)).collect(),
        best: match v["dupe"].get("keep") {
            None => false,
            Some(k) => match k.as_str() {
                Some("first") => false,
                Some("best") => true,
                _ => return Err(fault(join(&dp, "keep"), "first or best")),
            },
        },
    };
    let points = Expr::parse_in(&v["points"], &p("points"), Ctx::Points, &env)?;
    let points_cap = match o.get("points_cap") {
        None => None,
        Some(c) => {
            let cp = p("points_cap");
            obj(c, &cp, &["when", "share"], &[])?;
            let when = Expr::parse_in(&c["when"], &join(&cp, "when"), Ctx::Condition, &env)?;
            let share = c["share"]
                .as_array()
                .filter(|a| a.len() == 2)
                .and_then(|a| Some((a[0].as_u64()?, a[1].as_u64()?)))
                .filter(|(n, d)| *n >= 1 && n < d)
                .ok_or(fault(
                    join(&cp, "share"),
                    "[n, d] whole numbers with 1 <= n < d",
                ))?;
            Some(Cap {
                when,
                n: share.0,
                d: share.1,
            })
        }
    };
    let mut multipliers: Vec<Multiplier> = Vec::new();
    if let Some(list) = o.get("multipliers") {
        let arr = list.as_array().ok_or(fault(p("multipliers"), "a list"))?;
        for (i, m) in arr.iter().enumerate() {
            let mp = format!("{}[{i}]", p("multipliers"));
            obj(m, &mp, &["name", "kind", "per"], &["only", "requires"])?;
            let name = m["name"]
                .as_str()
                .filter(|n| {
                    (1..=16).contains(&n.len())
                        && n.bytes().all(|b| b.is_ascii_lowercase() || b == b'_')
                })
                .ok_or(fault(join(&mp, "name"), "1..16 characters a-z or _"))?
                .to_owned();
            if multipliers.iter().any(|o| o.name == name) {
                return Err(fault(join(&mp, "name"), "a name twice"));
            }
            let kind = mult_kind(&m["kind"], &join(&mp, "kind"), file)?;
            let per = m["per"]
                .as_str()
                .and_then(Per::parse)
                .ok_or(fault(join(&mp, "per"), "an unknown scope"))?;
            let only = match m.get("only") {
                None => None,
                Some(e) => Some(Expr::parse_in(e, &join(&mp, "only"), Ctx::Only, &env)?),
            };
            let all_bands = match m.get("requires") {
                None => false,
                Some(r) if r == "all_bands" => true,
                Some(_) => return Err(fault(join(&mp, "requires"), "all_bands")),
            };
            multipliers.push(Multiplier {
                name,
                kind,
                per,
                only,
                all_bands,
            });
        }
    }
    let score_env = Env {
        mults: multipliers.iter().map(|m| m.name.clone()).collect(),
        ..env.clone()
    };
    let score = Expr::parse_in(&v["score"], &p("score"), Ctx::Score, &score_env)?;
    if let Some(w) = &schedule.window
        && w.best
        && !(score.text.trim() == "points" || score.text.trim() == "qsos")
    {
        return Err(fault(
            join(&p("schedule"), "window.scored"),
            "best needs an additive score (points or qsos)",
        ));
    }
    let extras = texts(o.get("extras"), &p("extras"))?;
    let automation = match o.get("automation") {
        None => Automation {
            clause: Clause::Silent,
            text: SILENT_TEXT.into(),
            reference: None,
            by_section: Vec::new(),
        },
        Some(a) => automation(a, &p("automation"), &entry_params)?,
    };
    let mut restrictions: Vec<String> = Vec::new();
    if let Some(list) = o.get("restrictions") {
        let arr = list.as_array().ok_or(fault(p("restrictions"), "a list"))?;
        for (i, r) in arr.iter().enumerate() {
            let rp = format!("{}[{i}]", p("restrictions"));
            let s = r.as_str().ok_or(fault(&rp, "a restriction"))?;
            let ok = RESTRICTIONS.contains(&s)
                || s.strip_prefix("min_band_stay:").is_some_and(|n| {
                    !n.is_empty()
                        && n.len() <= 4
                        && n.bytes().all(|b| b.is_ascii_digit())
                        && n != "0"
                });
            if !ok || restrictions.iter().any(|o| o == s) {
                return Err(fault(rp, "an unknown restriction"));
            }
            restrictions.push(s.to_owned());
        }
    }
    let entry = match o.get("entry") {
        None => Entry::default(),
        Some(e) => {
            let ep = p("entry");
            Entry {
                eligible: match e.get("eligible") {
                    None => None,
                    Some(x) => Some(Expr::parse_in(
                        x,
                        &join(&ep, "eligible"),
                        Ctx::Eligible,
                        &env,
                    )?),
                },
                workable: match e.get("workable") {
                    None => None,
                    Some(x) => Some(Expr::parse_in(
                        x,
                        &join(&ep, "workable"),
                        Ctx::Workable,
                        &env,
                    )?),
                },
                params: entry_params.clone(),
            }
        }
    };
    let notes = texts(o.get("notes"), &p("notes"))?;
    let unconfirmed = texts(o.get("unconfirmed"), &p("unconfirmed"))?;
    for (i, u) in unconfirmed.iter().enumerate() {
        let head = u.split(':').next().unwrap_or("");
        if head.is_empty()
            || !head
                .bytes()
                .all(|b| b.is_ascii_lowercase() || b == b'_' || b == b'.' || b.is_ascii_uppercase())
        {
            return Err(fault(
                format!("{}[{i}]", p("unconfirmed")),
                "a field path, optionally followed by \": words\"",
            ));
        }
    }
    Ok(Profile {
        id,
        name,
        organiser,
        source,
        checked,
        log,
        schedule,
        bands,
        modes,
        exchange: Exchange {
            activity,
            cq,
            sent,
            rcvd,
            unsendable_for,
        },
        dupe,
        points,
        points_cap,
        multipliers,
        score,
        extras,
        automation,
        restrictions,
        entry,
        members,
        notes,
        unconfirmed,
    })
}
/// ExchangeRule: the activity's CQ word by default.
pub(crate) fn default_cq(activity: &str) -> Option<&'static str> {
    match activity {
        "na_vhf" | "arrl_digi" | "eu_vhf" => Some("TEST"),
        "ww_digi" => Some("WW"),
        "field_day" => Some("FD"),
        "rtty" => Some("RU"),
        _ => None,
    }
}
fn default_exchange(activity: &str) -> (Vec<String>, Vec<String>) {
    let v = |l: &[&str]| l.iter().map(|s| (*s).to_owned()).collect::<Vec<_>>();
    match activity {
        "na_vhf" | "ww_digi" | "arrl_digi" => (v(&["grid4"]), v(&["grid4"])),
        "field_day" => (v(&["fd_class", "section"]), v(&["fd_class", "section"])),
        "rtty" => (v(&["rst", "serial"]), v(&["rst", "serial"])),
        "eu_vhf" => (
            v(&["report", "serial", "grid6"]),
            v(&["report", "serial", "grid6"]),
        ),
        _ => (v(&["report"]), v(&["report", "grid4"])),
    }
}
fn modes(v: &Value, path: &str) -> R<Modes> {
    obj(v, path, &[], &["count", "as_one"])?;
    let count = match v.get("count") {
        None => Count::List(vec!["FT8".into(), "FT4".into()]),
        Some(Value::String(s)) => match s.as_str() {
            "digital" => Count::Digital,
            "digital_no_rtty" => Count::DigitalNoRtty,
            "any" => Count::Any,
            _ => return Err(fault(join(path, "count"), "a mode list or a class")),
        },
        Some(list) => {
            let l = words(list, &join(path, "count"), MODE_NAMES)?;
            if l.is_empty() {
                return Err(fault(join(path, "count"), "at least one mode"));
            }
            Count::List(l)
        }
    };
    let as_one = match v.get("as_one") {
        None => AsOne::Groups(vec![vec!["FT8".into(), "FT4".into()]]),
        Some(Value::String(s)) if s == "all" => AsOne::All,
        Some(Value::Array(groups)) => {
            let mut out = Vec::new();
            for (i, g) in groups.iter().enumerate() {
                out.push(words(g, &format!("{}[{i}]", join(path, "as_one")), MODE_NAMES)?);
            }
            AsOne::Groups(out)
        }
        Some(_) => return Err(fault(join(path, "as_one"), "all or a list of mode lists")),
    };
    Ok(Modes { count, as_one })
}
fn mult_kind(v: &Value, path: &str, file: &File) -> R<MultKind> {
    let s = v.as_str().ok_or(fault(path, "a multiplier kind"))?;
    Ok(match s {
        "dxcc" => MultKind::Dxcc,
        "wpx" => MultKind::Wpx,
        "continent" => MultKind::Continent,
        "cq_zone" => MultKind::CqZone,
        "itu_zone" => MultKind::ItuZone,
        "grid_field" => MultKind::GridField,
        "grid4" => MultKind::Grid4,
        "my_grid4" => MultKind::MyGrid4,
        "call" => MultKind::Call,
        _ => {
            if let Some(n) = s.strip_prefix("call_area:") {
                if !file.call_areas.contains_key(n) {
                    return Err(fault(path, "no call area table of that name"));
                }
                MultKind::CallArea(n.to_owned())
            } else if let Some(f) = s.strip_prefix("exchange:") {
                if !FIELDS.contains(&f) {
                    return Err(fault(path, "an unknown exchange field"));
                }
                MultKind::Exchange(f.to_owned())
            } else {
                return Err(fault(path, "an unknown multiplier kind"));
            }
        }
    })
}
fn params(v: &Value, path: &str) -> R<Vec<Param>> {
    let list = v.as_array().ok_or(fault(path, "a list"))?;
    let mut out: Vec<Param> = Vec::new();
    for (i, item) in list.iter().enumerate() {
        let pp = format!("{path}[{i}]");
        obj(item, &pp, &["name", "choices", "default"], &[])?;
        let name = item["name"]
            .as_str()
            .filter(|n| PARAM_NAMES.contains(n))
            .ok_or(fault(join(&pp, "name"), "an unknown parameter name"))?
            .to_owned();
        if out.iter().any(|o| o.name == name) {
            return Err(fault(join(&pp, "name"), "a name twice"));
        }
        let cp = join(&pp, "choices");
        let choices = match &item["choices"] {
            Value::String(s) if s == "bool" => Choices::Bool,
            Value::Array(a) if (1..=8).contains(&a.len()) => {
                if a.iter().all(|x| x.is_i64() || x.is_u64()) {
                    let n: Vec<i64> = a.iter().filter_map(Value::as_i64).collect();
                    let mut d = n.clone();
                    d.sort_unstable();
                    d.dedup();
                    if d.len() != n.len() || n.len() != a.len() {
                        return Err(fault(cp, "distinct whole numbers"));
                    }
                    Choices::Numbers(n)
                } else {
                    let w: Vec<String> = a
                        .iter()
                        .map(|x| {
                            x.as_str()
                                .filter(|s| {
                                    (1..=16).contains(&s.len())
                                        && s.bytes().all(|b| {
                                            b.is_ascii_alphanumeric() || b == b'_' || b == b'-'
                                        })
                                })
                                .map(str::to_owned)
                        })
                        .collect::<Option<_>>()
                        .ok_or(fault(&cp, "words of 1..16 characters"))?;
                    let mut d = w.clone();
                    d.sort();
                    d.dedup();
                    if d.len() != w.len() {
                        return Err(fault(cp, "distinct words"));
                    }
                    Choices::Words(w)
                }
            }
            _ => return Err(fault(cp, "\"bool\" or a list of 1..8 words or numbers")),
        };
        let mut param = Param {
            name,
            choices,
            default: PValue::Bool(false),
        };
        param.default = param
            .value(&item["default"])
            .ok_or(fault(join(&pp, "default"), "not one of its choices"))?;
        out.push(param);
    }
    Ok(out)
}
fn automation(v: &Value, path: &str, params: &[Param]) -> R<Automation> {
    let o = obj(v, path, &["clause", "text"], &["ref", "by_section"])?;
    let clause = v["clause"]
        .as_str()
        .and_then(Clause::parse)
        .ok_or(fault(join(path, "clause"), "forbidden, silent or permitted"))?;
    let text_ = text(&v["text"], &join(path, "text"), 1, 400)?;
    let reference = match o.get("ref") {
        None | Some(Value::Null) => None,
        Some(r) => Some(text(r, &join(path, "ref"), 1, 20)?),
    };
    let mut by_section = Vec::new();
    if let Some(b) = o.get("by_section") {
        let bp = join(path, "by_section");
        let m = b.as_object().ok_or(fault(&bp, "an object"))?;
        let section = params.iter().find(|p| p.name == "section");
        for (value, e) in m {
            let ep = join(&bp, value);
            let known = section.is_some_and(|p| p.value(&json!(value)).is_some());
            if !known {
                return Err(fault(ep, "not a value of the entry parameter section"));
            }
            obj(e, &ep, &["clause", "text"], &[])?;
            let c = e["clause"]
                .as_str()
                .and_then(Clause::parse)
                .ok_or(fault(join(&ep, "clause"), "forbidden, silent or permitted"))?;
            by_section.push((value.clone(), c, text(&e["text"], &join(&ep, "text"), 1, 400)?));
        }
    }
    Ok(Automation {
        clause,
        text: text_,
        reference,
        by_section,
    })
}
fn time_of(v: &Value, path: &str) -> R<i64> {
    let s = v.as_str().ok_or(fault(path, "\"Nd HH:MM\""))?;
    let bad = || fault(path, "\"Nd HH:MM\"");
    let (d, hm) = s.split_once("d ").ok_or_else(bad)?;
    let days: i64 = d
        .parse()
        .ok()
        .filter(|_| !d.is_empty() && d.len() <= 3)
        .ok_or_else(bad)?;
    let (h, m) = hm.split_once(':').ok_or_else(bad)?;
    if h.len() != 2 || m.len() != 2 {
        return Err(bad());
    }
    let h: i64 = h.parse().ok().filter(|h| (0..24).contains(h)).ok_or_else(bad)?;
    let m: i64 = m.parse().ok().filter(|m| (0..60).contains(m)).ok_or_else(bad)?;
    Ok(days * 1440 + h * 60 + m)
}
fn weekday_of(s: &str) -> Option<i64> {
    ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        .iter()
        .position(|w| *w == s)
        .map(|i| i as i64)
}
fn nth(v: &Value, allow_every: bool) -> Option<Nth> {
    match v {
        Value::String(s) if s == "last" => Some(Nth::Last),
        Value::String(s) if s == "every" && allow_every => Some(Nth::Every),
        n => n
            .as_u64()
            .filter(|n| (1..=5).contains(n))
            .map(|n| Nth::N(n as usize)),
    }
}
fn month(v: &Value) -> Option<u32> {
    v.as_u64().filter(|m| (1..=12).contains(m)).map(|m| m as u32)
}
fn day_rule(v: &Value, path: &str) -> R<DayRule> {
    let o = v.as_object().ok_or(fault(path, "a day rule"))?;
    if o.contains_key("full_weekend") {
        obj(v, path, &["full_weekend", "month"], &[])?;
        return Ok(DayRule::FullWeekend {
            n: nth(&v["full_weekend"], false)
                .ok_or(fault(join(path, "full_weekend"), "1..5 or last"))?,
            month: month(&v["month"]).ok_or(fault(join(path, "month"), "1..12"))?,
        });
    }
    if o.contains_key("weekday") {
        obj(v, path, &["weekday", "n", "months"], &[])?;
        let months = match &v["months"] {
            Value::String(s) if s == "all" => None,
            Value::Array(a) if !a.is_empty() => Some(
                a.iter()
                    .map(month)
                    .collect::<Option<Vec<_>>>()
                    .ok_or(fault(join(path, "months"), "\"all\" or months 1..12"))?,
            ),
            _ => return Err(fault(join(path, "months"), "\"all\" or months 1..12")),
        };
        return Ok(DayRule::Weekday {
            weekday: v["weekday"]
                .as_str()
                .and_then(weekday_of)
                .ok_or(fault(join(path, "weekday"), "MON..SUN"))?,
            n: nth(&v["n"], true).ok_or(fault(join(path, "n"), "1..5, last or every"))?,
            months,
        });
    }
    if o.contains_key("date") {
        obj(v, path, &["date"], &[])?;
        let s = v["date"].as_str().unwrap_or("");
        let ok = s.len() == 5
            && s.as_bytes()[2] == b'-'
            && real_date(&format!("2028-{s}")).is_some();
        if !ok {
            return Err(fault(join(path, "date"), "MM-DD"));
        }
        return Ok(DayRule::Date {
            month: s[..2].parse().unwrap_or(1),
            day: s[3..].parse().unwrap_or(1),
        });
    }
    if o.contains_key("dates") {
        obj(v, path, &["dates"], &[])?;
        let a = v["dates"]
            .as_array()
            .filter(|a| !a.is_empty())
            .ok_or(fault(join(path, "dates"), "a list of dates"))?;
        let mut out = Vec::new();
        for (i, d) in a.iter().enumerate() {
            out.push(
                d.as_str()
                    .and_then(real_date)
                    .ok_or(fault(format!("{}[{i}]", join(path, "dates")), "YYYY-MM-DD"))?,
            );
        }
        return Ok(DayRule::Dates(out));
    }
    if o.contains_key("asked") {
        obj(v, path, &["asked"], &[])?;
        if v["asked"] != json!(true) {
            return Err(fault(join(path, "asked"), "true"));
        }
        return Ok(DayRule::Asked);
    }
    Err(fault(path, "an unknown day rule"))
}
fn schedule(v: &Value, path: &str, params: &[Param]) -> R<Schedule> {
    let o = obj(v, path, &["rounds", "text"], &["tz", "series", "window"])?;
    let tz_name = match o.get("tz") {
        None => "UTC".to_owned(),
        Some(t) => t.as_str().unwrap_or("").to_owned(),
    };
    let tz = Zone::named(&tz_name).ok_or(fault(join(path, "tz"), "UTC or a known IANA zone"))?;
    let rp = join(path, "rounds");
    let list = v["rounds"]
        .as_array()
        .filter(|a| !a.is_empty())
        .ok_or(fault(&rp, "at least one round"))?;
    let mut rounds = Vec::new();
    for (i, r) in list.iter().enumerate() {
        let p = format!("{rp}[{i}]");
        obj(r, &p, &["day", "time"], &["bands", "label"])?;
        let day = day_rule(&r["day"], &join(&p, "day"))?;
        let t = r["time"]
            .as_array()
            .filter(|t| t.len() == 2)
            .ok_or(fault(join(&p, "time"), "[start, end]"))?;
        let start_min = time_of(&t[0], &format!("{}[0]", join(&p, "time")))?;
        let end_min = time_of(&t[1], &format!("{}[1]", join(&p, "time")))?;
        if end_min <= start_min {
            return Err(fault(join(&p, "time"), "the end must lie after the start"));
        }
        let bands = match r.get("bands") {
            None => None,
            Some(b) => Some(words(b, &join(&p, "bands"), BANDS)?),
        };
        let label = match r.get("label") {
            None => None,
            Some(l) => Some(text(l, &join(&p, "label"), 1, 40)?),
        };
        rounds.push(Round {
            day,
            start_min,
            end_min,
            bands,
            label,
        });
    }
    let series = match o.get("series") {
        None => None,
        Some(s) => {
            let sp = join(path, "series");
            obj(s, &sp, &["best", "of", "per", "normalise"], &["annual"])?;
            let n = |k: &str| {
                s[k].as_u64()
                    .filter(|n| (1..=366).contains(n))
                    .ok_or(fault(join(&sp, k), "a whole number"))
            };
            let pick = |k: &str, allowed: &[&str]| {
                s[k].as_str()
                    .filter(|x| allowed.contains(x))
                    .map(str::to_owned)
                    .ok_or(fault(join(&sp, k), "an unknown value"))
            };
            Some(Series {
                best: n("best")?,
                of: n("of")?,
                per: pick("per", &["band", "contest"])?,
                normalise: pick("normalise", &["none", "winner_1000", "rank"])?,
                annual: match s.get("annual") {
                    None => None,
                    Some(_) => Some(pick("annual", &["sum", "sum_times_rounds"])?),
                },
            })
        }
    };
    let window = match o.get("window") {
        None => None,
        Some(w) => {
            let wp = join(path, "window");
            obj(w, &wp, &["limit", "scored"], &["unit", "min_off_minutes"])?;
            let limit = match &w["limit"] {
                Value::Object(_) => {
                    obj(&w["limit"], &join(&wp, "limit"), &["param"], &[])?;
                    let name = w["limit"]["param"].as_str().unwrap_or("");
                    let ok = params
                        .iter()
                        .any(|p| p.name == name && matches!(p.choices, Choices::Numbers(_)));
                    if !ok {
                        return Err(fault(
                            join(&wp, "limit.param"),
                            "an entry parameter with numbers",
                        ));
                    }
                    Limit::Param(name.to_owned())
                }
                n => Limit::Number(
                    n.as_f64()
                        .filter(|x| *x > 0.0 && *x <= 744.0)
                        .ok_or(fault(join(&wp, "limit"), "a number or {param}"))?,
                ),
            };
            let utc_day = match w.get("unit") {
                None => false,
                Some(u) if u == "hour" => false,
                Some(u) if u == "utc_day" => true,
                Some(_) => return Err(fault(join(&wp, "unit"), "hour or utc_day")),
            };
            let best = match w["scored"].as_str() {
                Some("first") => false,
                Some("best") => true,
                _ => return Err(fault(join(&wp, "scored"), "first or best")),
            };
            let min_off_minutes = match w.get("min_off_minutes") {
                None => 0,
                Some(m) => m
                    .as_i64()
                    .filter(|m| (0..=1440).contains(m))
                    .ok_or(fault(join(&wp, "min_off_minutes"), "0..1440"))?,
            };
            Some(Window {
                limit,
                utc_day,
                best,
                min_off_minutes,
            })
        }
    };
    Ok(Schedule {
        tz,
        tz_name,
        rounds,
        text: text(&v["text"], &join(path, "text"), 1, 200)?,
        series,
        window,
    })
}

// ------------------------------------------------------------------ time zones
/// A time zone: UTC, a fixed offset, or a standard offset with one of the daylight-saving
/// rules in force (EU, US, south-eastern Australia, New Zealand). Offsets in minutes east.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Zone {
    Fixed(i64),
    Eu(i64),
    Us(i64),
    Au(i64),
    Nz,
}
const DAY_MS: i64 = 86_400_000;
const HOUR_MS: i64 = 3_600_000;
impl Zone {
    /// The zones the station knows (the IANA names in use by contests).
    pub(crate) fn named(name: &str) -> Option<Zone> {
        Some(match name {
            "UTC" => Zone::Fixed(0),
            "Europe/London" | "Europe/Dublin" | "Europe/Lisbon" | "Atlantic/Canary" => Zone::Eu(0),
            "Europe/Paris" | "Europe/Berlin" | "Europe/Zurich" | "Europe/Vienna" | "Europe/Rome"
            | "Europe/Madrid" | "Europe/Amsterdam" | "Europe/Brussels" | "Europe/Oslo"
            | "Europe/Stockholm" | "Europe/Copenhagen" | "Europe/Prague" | "Europe/Warsaw"
            | "Europe/Budapest" | "Europe/Belgrade" | "Europe/Ljubljana" | "Europe/Zagreb"
            | "Europe/Bratislava" | "Europe/Luxembourg" | "Europe/Monaco" | "Europe/Malta"
            | "Europe/Vaduz" | "Europe/Andorra" | "Europe/San_Marino" | "Europe/Tirane"
            | "Europe/Sarajevo" | "Europe/Skopje" | "Europe/Podgorica" | "Europe/Gibraltar" => {
                Zone::Eu(60)
            }
            "Europe/Helsinki" | "Europe/Athens" | "Europe/Bucharest" | "Europe/Sofia"
            | "Europe/Riga" | "Europe/Tallinn" | "Europe/Vilnius" | "Europe/Kyiv"
            | "Europe/Kiev" | "Europe/Chisinau" | "Asia/Nicosia" => Zone::Eu(120),
            "America/New_York" | "America/Toronto" => Zone::Us(-300),
            "America/Chicago" | "America/Winnipeg" => Zone::Us(-360),
            "America/Denver" | "America/Edmonton" => Zone::Us(-420),
            "America/Los_Angeles" | "America/Vancouver" => Zone::Us(-480),
            "America/Anchorage" => Zone::Us(-540),
            "America/Halifax" => Zone::Us(-240),
            "America/Phoenix" => Zone::Fixed(-420),
            "Pacific/Honolulu" => Zone::Fixed(-600),
            "America/Sao_Paulo" => Zone::Fixed(-180),
            "Africa/Johannesburg" => Zone::Fixed(120),
            "Africa/Nairobi" => Zone::Fixed(180),
            "Africa/Lagos" => Zone::Fixed(60),
            "Asia/Kolkata" => Zone::Fixed(330),
            "Asia/Jakarta" => Zone::Fixed(420),
            "Asia/Shanghai" | "Asia/Singapore" | "Asia/Hong_Kong" | "Australia/Perth" => {
                Zone::Fixed(480)
            }
            "Asia/Tokyo" | "Asia/Seoul" => Zone::Fixed(540),
            "Australia/Brisbane" => Zone::Fixed(600),
            "Australia/Sydney" | "Australia/Melbourne" | "Australia/Hobart"
            | "Australia/Canberra" => Zone::Au(600),
            "Pacific/Auckland" => Zone::Nz,
            _ => return None,
        })
    }
    fn standard(self) -> i64 {
        match self {
            Zone::Fixed(o) | Zone::Eu(o) | Zone::Us(o) | Zone::Au(o) => o,
            Zone::Nz => 720,
        }
    }
    /// Daylight saving in force at this UTC instant.
    fn dst(self, utc_ms: i64) -> bool {
        let (year, ..) = civil(utc_ms);
        let std = self.standard() * 60_000;
        match self {
            Zone::Fixed(_) => false,
            Zone::Eu(_) => {
                let start = last_weekday(year, 3, 0) + HOUR_MS;
                let end = last_weekday(year, 10, 0) + HOUR_MS;
                utc_ms >= start && utc_ms < end
            }
            Zone::Us(_) => {
                let start = nth_weekday(year, 3, 0, 2) + 2 * HOUR_MS - std;
                let end = nth_weekday(year, 11, 0, 1) + 2 * HOUR_MS - std - HOUR_MS;
                utc_ms >= start && utc_ms < end
            }
            Zone::Au(_) => {
                let end = nth_weekday(year, 4, 0, 1) + 3 * HOUR_MS - std - HOUR_MS;
                let start = nth_weekday(year, 10, 0, 1) + 2 * HOUR_MS - std;
                utc_ms < end || utc_ms >= start
            }
            Zone::Nz => {
                let end = nth_weekday(year, 4, 0, 1) + 3 * HOUR_MS - std - HOUR_MS;
                let start = last_weekday(year, 9, 0) + 2 * HOUR_MS - std;
                utc_ms < end || utc_ms >= start
            }
        }
    }
    /// The UTC instant of a local wall-clock time (as ms of a UTC-labelled calendar).
    pub(crate) fn to_utc(self, local_ms: i64) -> i64 {
        let u = local_ms - self.standard() * 60_000;
        if self.dst(u - HOUR_MS) { u - HOUR_MS } else { u }
    }
}
/// 00:00 of each day of a month that is this weekday (0 Sunday), as UTC-labelled ms.
fn weekdays(year: i64, month: u32, weekday: i64) -> Vec<i64> {
    (1..=31)
        .filter_map(|day| parse_utc(&format!("{year:04}-{month:02}-{day:02}T00:00:00Z")))
        .filter(|ms| civil(*ms).1 == month && (ms / DAY_MS + 4).rem_euclid(7) == weekday)
        .collect()
}
fn nth_weekday(year: i64, month: u32, weekday: i64, n: usize) -> i64 {
    weekdays(year, month, weekday)[n - 1]
}
fn last_weekday(year: i64, month: u32, weekday: i64) -> i64 {
    *weekdays(year, month, weekday).last().unwrap_or(&0)
}
/// The Saturdays whose Sunday is in the same month ('full weekend', #63).
fn full_weekends(year: i64, month: u32) -> Vec<i64> {
    let mut list = weekdays(year, month, 6);
    list.retain(|ms| civil(ms + DAY_MS).1 == month);
    list
}
fn pick(list: Vec<i64>, n: Nth) -> Vec<i64> {
    match n {
        Nth::Every => list,
        Nth::Last => list.last().copied().into_iter().collect(),
        Nth::N(i) => list.get(i - 1).copied().into_iter().collect(),
    }
}
/// One occurrence of a contest.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Occurrence {
    pub start_ms: i64,
    pub end_ms: i64,
    pub band: Option<String>,
    pub round: usize,
}
impl Round {
    /// The local anchor days of this round in a month.
    fn days(&self, year: i64, m: u32) -> Vec<i64> {
        match &self.day {
            DayRule::FullWeekend { n, month } if *month == m => pick(full_weekends(year, m), *n),
            DayRule::Weekday { weekday, n, months }
                if months.as_ref().is_none_or(|l| l.contains(&m)) =>
            {
                pick(weekdays(year, m, *weekday), *n)
            }
            DayRule::Date { month, day } if *month == m => {
                parse_utc(&format!("{year:04}-{m:02}-{day:02}T00:00:00Z"))
                    .into_iter()
                    .collect()
            }
            DayRule::Dates(list) => list
                .iter()
                .filter(|(y, mo, _)| *y == year && *mo == m)
                .filter_map(|(y, mo, d)| parse_utc(&format!("{y:04}-{mo:02}-{d:02}T00:00:00Z")))
                .collect(),
            _ => Vec::new(),
        }
    }
}
impl Schedule {
    /// The occurrences of every round whose anchor day lies in months [first, last]
    /// (counted as year*12 + month-1).
    fn occurrences(&self, first: i64, last: i64) -> Vec<Occurrence> {
        let mut out = Vec::new();
        for m in first..=last {
            let (y, mo) = (m.div_euclid(12), m.rem_euclid(12) as u32 + 1);
            for (i, r) in self.rounds.iter().enumerate() {
                for day in r.days(y, mo) {
                    out.push(Occurrence {
                        start_ms: self.tz.to_utc(day + r.start_min * 60_000),
                        end_ms: self.tz.to_utc(day + r.end_min * 60_000),
                        band: r
                            .bands
                            .as_ref()
                            .filter(|b| b.len() == 1)
                            .map(|b| b[0].clone()),
                        round: i,
                    });
                }
            }
        }
        out
    }
    /// ScheduleRule: the current or next occurrence, the earliest that has not ended; None
    /// when every round is asked or every listed date has passed.
    pub(crate) fn next(&self, now_ms: i64) -> Option<Occurrence> {
        let (year, month, ..) = civil(now_ms);
        let first = year * 12 + i64::from(month) - 1;
        let mut list = self.occurrences(first - 2, first + 13);
        // Explicit dates further ahead than the scan.
        for (i, r) in self.rounds.iter().enumerate() {
            if let DayRule::Dates(dates) = &r.day {
                for (y, m, _) in dates {
                    let at = y * 12 + i64::from(*m) - 1;
                    if at > first + 13 {
                        list.extend(
                            self.occurrences(at, at)
                                .into_iter()
                                .filter(|o| o.round == i),
                        );
                    }
                }
            }
        }
        list.into_iter()
            .filter(|o| o.end_ms > now_ms)
            .min_by_key(|o| (o.start_ms, o.round))
    }
    /// The round whose occurrence holds this instant (dupe and multiplier scope round).
    pub(crate) fn round_at(&self, ms: i64) -> Option<usize> {
        let (year, month, ..) = civil(ms);
        let at = year * 12 + i64::from(month) - 1;
        self.occurrences(at - 2, at + 1)
            .into_iter()
            .find(|o| o.start_ms <= ms && ms < o.end_ms)
            .map(|o| o.round)
    }
}

// ------------------------------------------------------------------ expressions
/// ContestExpression contexts.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Ctx {
    Points,
    Condition,
    Only,
    Eligible,
    Workable,
    Score,
}
/// What an expression may read while it is checked.
#[derive(Clone)]
struct Env<'a> {
    file: &'a File,
    params: &'a [Param],
    bands: &'a [String],
    classes: Vec<ModeClass>,
    mults: Vec<String>,
}
#[derive(Clone, Copy, Debug, PartialEq)]
enum Truth {
    SameGrid4,
    SameGrid6,
    GridKnown,
    SameDxcc,
    SameContinent,
    TheirMember,
    MyMember,
}
#[derive(Clone, Copy, Debug, PartialEq)]
enum Func {
    Floor,
    Ceil,
    Max,
    Min,
}
#[derive(Clone, Debug, PartialEq)]
enum Node {
    Num(f64),
    Word(String),
    Km { six: bool, radius: f64 },
    Truth(Truth),
    TheirIn(String),
    MyIn(String),
    TheirCont(String),
    MyCont(String),
    Param(String),
    Qsos,
    Points,
    Mults,
    M(String),
    Fn(Func, Vec<Node>),
    Table {
        band: bool,
        entries: Vec<(String, Node)>,
        other: Option<Box<Node>>,
    },
    Bin(u8, Box<Node>, Box<Node>),
    Cmp(&'static str, Box<Node>, Box<Node>),
    Not(Box<Node>),
    And(Box<Node>, Box<Node>),
    Or(Box<Node>, Box<Node>),
    If(Box<Node>, Box<Node>, Box<Node>),
}
/// A parsed expression with its text.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Expr {
    pub text: String,
    node: Node,
}
const EARTH_KM: f64 = 6371.0;
/// IARU R1: a factor of 111.2 km per degree.
const IARU_RADIUS_KM: f64 = 111.2 * 180.0 / std::f64::consts::PI;
struct Parser<'a> {
    s: &'a [u8],
    i: usize,
}
const KEYWORDS: &[&str] = &["if", "then", "else", "and", "or", "not"];
impl Parser<'_> {
    fn ws(&mut self) {
        while self.i < self.s.len() && self.s[self.i].is_ascii_whitespace() {
            self.i += 1;
        }
    }
    fn peek(&mut self) -> Option<u8> {
        self.ws();
        self.s.get(self.i).copied()
    }
    fn eat(&mut self, c: u8) -> bool {
        if self.peek() == Some(c) {
            self.i += 1;
            true
        } else {
            false
        }
    }
    fn expect(&mut self, c: u8) -> Result<(), String> {
        if self.eat(c) {
            Ok(())
        } else {
            Err(format!("'{}' expected at {}", c as char, self.i))
        }
    }
    /// The next identifier without consuming it.
    fn word_at(&mut self) -> Option<String> {
        self.ws();
        let start = self.i;
        let mut j = start;
        while j < self.s.len() && (self.s[j].is_ascii_alphanumeric() || self.s[j] == b'_') {
            j += 1;
        }
        (j > start && self.s[start].is_ascii_alphabetic() || j > start && self.s[start] == b'_')
            .then(|| String::from_utf8_lossy(&self.s[start..j]).into_owned())
    }
    fn keyword(&mut self, k: &str) -> bool {
        if self.word_at().as_deref() == Some(k) {
            self.ws();
            self.i += k.len();
            true
        } else {
            false
        }
    }
    fn ident(&mut self) -> Option<String> {
        let w = self.word_at()?;
        self.ws();
        self.i += w.len();
        Some(w)
    }
    fn expr(&mut self) -> Result<Node, String> {
        if self.keyword("if") {
            let c = self.or()?;
            if !self.keyword("then") {
                return Err("then expected".into());
            }
            let a = self.expr()?;
            if !self.keyword("else") {
                return Err("else expected".into());
            }
            let b = self.expr()?;
            return Ok(Node::If(Box::new(c), Box::new(a), Box::new(b)));
        }
        self.or()
    }
    fn or(&mut self) -> Result<Node, String> {
        let mut a = self.and()?;
        while self.keyword("or") {
            let b = self.and()?;
            a = Node::Or(Box::new(a), Box::new(b));
        }
        Ok(a)
    }
    fn and(&mut self) -> Result<Node, String> {
        let mut a = self.not()?;
        while self.keyword("and") {
            let b = self.not()?;
            a = Node::And(Box::new(a), Box::new(b));
        }
        Ok(a)
    }
    fn not(&mut self) -> Result<Node, String> {
        if self.keyword("not") {
            return Ok(Node::Not(Box::new(self.not()?)));
        }
        self.cmp()
    }
    fn cmp(&mut self) -> Result<Node, String> {
        let a = self.sum()?;
        self.ws();
        let rest = &self.s[self.i..];
        let op = ["<=", ">=", "!=", "=", "<", ">"]
            .into_iter()
            .find(|o| rest.starts_with(o.as_bytes()));
        match op {
            Some(o) => {
                self.i += o.len();
                let b = self.sum()?;
                Ok(Node::Cmp(o, Box::new(a), Box::new(b)))
            }
            None => Ok(a),
        }
    }
    fn sum(&mut self) -> Result<Node, String> {
        let mut a = self.term()?;
        loop {
            let op = match self.peek() {
                Some(c @ (b'+' | b'-')) => c,
                _ => return Ok(a),
            };
            self.i += 1;
            let b = self.term()?;
            a = Node::Bin(op, Box::new(a), Box::new(b));
        }
    }
    fn term(&mut self) -> Result<Node, String> {
        let mut a = self.factor()?;
        loop {
            let op = match self.peek() {
                Some(c @ (b'*' | b'/')) => c,
                _ => return Ok(a),
            };
            self.i += 1;
            let b = self.factor()?;
            a = Node::Bin(op, Box::new(a), Box::new(b));
        }
    }
    fn number(&mut self) -> Result<f64, String> {
        self.ws();
        let start = self.i;
        while self.i < self.s.len() && (self.s[self.i].is_ascii_digit() || self.s[self.i] == b'.')
        {
            self.i += 1;
        }
        std::str::from_utf8(&self.s[start..self.i])
            .ok()
            .and_then(|t| t.parse::<f64>().ok())
            .ok_or_else(|| format!("a number expected at {start}"))
    }
    fn arg_name(&mut self) -> Result<String, String> {
        self.expect(b'(')?;
        self.ws();
        let start = self.i;
        while self.i < self.s.len()
            && (self.s[self.i].is_ascii_alphanumeric() || self.s[self.i] == b'_')
        {
            self.i += 1;
        }
        let name = String::from_utf8_lossy(&self.s[start..self.i]).into_owned();
        self.expect(b')')?;
        if name.is_empty() {
            return Err("a name expected".into());
        }
        Ok(name)
    }
    fn factor(&mut self) -> Result<Node, String> {
        match self.peek() {
            None => return Err("an expression expected".into()),
            Some(b'(') => {
                self.i += 1;
                let e = self.expr()?;
                self.expect(b')')?;
                return Ok(e);
            }
            Some(b'"') => {
                self.i += 1;
                let start = self.i;
                while self.i < self.s.len() && self.s[self.i] != b'"' {
                    self.i += 1;
                }
                let w = String::from_utf8_lossy(&self.s[start..self.i]).into_owned();
                self.expect(b'"')?;
                return Ok(Node::Word(w));
            }
            Some(c) if c.is_ascii_digit() || c == b'.' => return Ok(Node::Num(self.number()?)),
            _ => {}
        }
        let Some(name) = self.ident() else {
            return Err(format!("unexpected character at {}", self.i));
        };
        if KEYWORDS.contains(&name.as_str()) {
            return Err(format!(
                "'{name}' here: an if inside a sum needs parentheses"
            ));
        }
        let call = self.peek() == Some(b'(');
        Ok(match name.as_str() {
            "km" => {
                self.expect(b'(')?;
                let six = match self.ident().as_deref() {
                    Some("grid4") => false,
                    Some("grid6") => true,
                    _ => return Err("km(grid4 or grid6, earth)".into()),
                };
                let radius = if self.eat(b',') {
                    if self.keyword("iaru") {
                        IARU_RADIUS_KM
                    } else {
                        let r = self.number()?;
                        if r != 6371.0 && r != 6378.16 {
                            return Err("earth: 6371, 6378.16 or iaru".into());
                        }
                        r
                    }
                } else {
                    EARTH_KM
                };
                self.expect(b')')?;
                Node::Km { six, radius }
            }
            "floor" | "ceil" | "max" | "min" => {
                let f = match name.as_str() {
                    "floor" => Func::Floor,
                    "ceil" => Func::Ceil,
                    "max" => Func::Max,
                    _ => Func::Min,
                };
                self.expect(b'(')?;
                let mut args = vec![self.expr()?];
                while self.eat(b',') {
                    args.push(self.expr()?);
                }
                self.expect(b')')?;
                let want = if matches!(f, Func::Max | Func::Min) {
                    2
                } else {
                    1
                };
                if args.len() != want {
                    return Err(format!("{name} takes {want} argument(s)"));
                }
                Node::Fn(f, args)
            }
            "band" | "class" if self.peek() == Some(b'{') => {
                self.i += 1;
                let mut entries = Vec::new();
                let mut other = None;
                loop {
                    self.ws();
                    let start = self.i;
                    while self.i < self.s.len() && self.s[self.i] != b':' && self.s[self.i] != b'}'
                    {
                        self.i += 1;
                    }
                    let key = String::from_utf8_lossy(&self.s[start..self.i])
                        .trim()
                        .to_owned();
                    self.expect(b':')?;
                    let value = self.expr()?;
                    if key == "else" {
                        other = Some(Box::new(value));
                    } else {
                        entries.push((key, value));
                    }
                    if self.eat(b'}') {
                        break;
                    }
                    self.expect(b',')?;
                }
                Node::Table {
                    band: name == "band",
                    entries,
                    other,
                }
            }
            "their_in" => Node::TheirIn(self.arg_name()?),
            "my_in" => Node::MyIn(self.arg_name()?),
            "their_cont" => Node::TheirCont(self.arg_name()?),
            "my_cont" => Node::MyCont(self.arg_name()?),
            "param" => Node::Param(self.arg_name()?),
            "same_grid4" => Node::Truth(Truth::SameGrid4),
            "same_grid6" => Node::Truth(Truth::SameGrid6),
            "grid_known" => Node::Truth(Truth::GridKnown),
            "same_dxcc" => Node::Truth(Truth::SameDxcc),
            "same_continent" => Node::Truth(Truth::SameContinent),
            "their_member" => Node::Truth(Truth::TheirMember),
            "my_member" => Node::Truth(Truth::MyMember),
            "qsos" => Node::Qsos,
            "points" => Node::Points,
            "mults" => Node::Mults,
            "m" if self.peek() == Some(b'.') => {
                self.i += 1;
                let n = self.ident().ok_or("m.NAME expected")?;
                Node::M(n)
            }
            _ if call => return Err(format!("unknown function {name}")),
            _ => return Err(format!("unknown variable {name}")),
        })
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Ty {
    Num,
    Bool,
    Word,
}
impl Expr {
    /// Parses and checks an expression string of a context (refusing what it may not use).
    fn parse_in(v: &Value, path: &str, ctx: Ctx, env: &Env) -> R<Expr> {
        let text = v
            .as_str()
            .filter(|s| printable(s, 1, 400))
            .ok_or(fault(path, "an expression string"))?;
        let mut p = Parser {
            s: text.as_bytes(),
            i: 0,
        };
        let node = p.expr().map_err(|e| fault(path, e))?;
        if p.peek().is_some() {
            return Err(fault(path, format!("unexpected text at {}", p.i)));
        }
        let ty = check(&node, ctx, env).map_err(|e| fault(path, e))?;
        let want = match ctx {
            Ctx::Points | Ctx::Score => Ty::Num,
            _ => Ty::Bool,
        };
        if ty != want {
            return Err(fault(
                path,
                if want == Ty::Num {
                    "a number is needed, not a condition"
                } else {
                    "a condition is needed"
                },
            ));
        }
        Ok(Expr {
            text: text.to_owned(),
            node,
        })
    }
    /// A parse of a text in a context for the tests and the hand oracle (no params, no sets).
    #[cfg(test)]
    pub(crate) fn test(text: &str, ctx: Ctx, file: &File, params: &[Param]) -> R<Expr> {
        let bands: Vec<String> = BANDS.iter().map(|b| (*b).to_owned()).collect();
        let env = Env {
            file,
            params,
            bands: &bands,
            classes: vec![ModeClass::Phone, ModeClass::Cw, ModeClass::Digital],
            mults: vec!["grids".into(), "squares".into(), "areas".into(), "triples".into()],
        };
        Expr::parse_in(&json!(text), "x", ctx, &env)
    }
}
/// Which variables a context may read.
fn allowed(node: &Node, ctx: Ctx) -> bool {
    use Node as N;
    let qso = matches!(ctx, Ctx::Points | Ctx::Condition | Ctx::Only);
    match node {
        N::Km { .. } | N::Table { .. } => qso,
        N::Truth(Truth::SameGrid4 | Truth::SameGrid6 | Truth::GridKnown) => qso,
        N::Truth(Truth::SameDxcc | Truth::SameContinent | Truth::TheirMember)
        | N::TheirIn(_)
        | N::TheirCont(_) => qso || ctx == Ctx::Workable,
        N::Truth(Truth::MyMember) | N::MyIn(_) | N::MyCont(_) | N::Param(_) => ctx != Ctx::Score,
        N::Qsos | N::Points | N::Mults | N::M(_) => ctx == Ctx::Score,
        N::If(..) | N::Cmp(..) | N::Not(_) | N::And(..) | N::Or(..) | N::Word(_) => {
            ctx != Ctx::Score
        }
        _ => true,
    }
}
fn check(node: &Node, ctx: Ctx, env: &Env) -> Result<Ty, String> {
    use Node as N;
    if !allowed(node, ctx) {
        return Err(format!("{} may not be used here", describe(node)));
    }
    let num = |n: &Node| -> Result<(), String> {
        match check(n, ctx, env)? {
            Ty::Num => Ok(()),
            _ => Err("a number is needed, not a condition".into()),
        }
    };
    let truth = |n: &Node| -> Result<(), String> {
        match check(n, ctx, env)? {
            Ty::Bool => Ok(()),
            _ => Err("a condition is needed".into()),
        }
    };
    Ok(match node {
        N::Num(_) | N::Km { .. } | N::Qsos | N::Points | N::Mults => Ty::Num,
        N::Word(_) => Ty::Word,
        N::M(name) => {
            if !env.mults.contains(name) {
                return Err(format!("no multiplier set named {name}"));
            }
            Ty::Num
        }
        N::Truth(_) => Ty::Bool,
        N::TheirIn(s) | N::MyIn(s) => {
            if !env.file.sets.contains_key(s) {
                return Err(format!("no set named {s}"));
            }
            Ty::Bool
        }
        N::TheirCont(c) | N::MyCont(c) => {
            if !crate::dxcc::CONTINENTS.contains(&c.as_str()) {
                return Err(format!("{c} is no continent"));
            }
            Ty::Bool
        }
        N::Param(name) => match env.params.iter().find(|p| p.name == *name) {
            None => return Err(format!("no entry parameter {name}")),
            Some(p) => match p.choices {
                Choices::Bool => Ty::Bool,
                Choices::Numbers(_) => Ty::Num,
                Choices::Words(_) => Ty::Word,
            },
        },
        N::Fn(_, args) => {
            for a in args {
                num(a)?;
            }
            Ty::Num
        }
        N::Table {
            band,
            entries,
            other,
        } => {
            for (k, v) in entries {
                let known = if *band {
                    BANDS.contains(&k.as_str())
                } else {
                    ["phone", "cw", "digital"].contains(&k.as_str())
                };
                if !known {
                    return Err(format!("unknown table key {k}"));
                }
                num(v)?;
            }
            match other {
                Some(o) => num(o)?,
                None => {
                    let missing = if *band {
                        env.bands
                            .iter()
                            .find(|b| !entries.iter().any(|(k, _)| k == *b))
                            .cloned()
                    } else {
                        env.classes
                            .iter()
                            .find(|c| !entries.iter().any(|(k, _)| k == c.name()))
                            .map(|c| c.name().to_owned())
                    };
                    if let Some(m) = missing {
                        return Err(format!("the table has no else and misses {m}"));
                    }
                }
            }
            Ty::Num
        }
        N::Bin(_, a, b) => {
            num(a)?;
            num(b)?;
            Ty::Num
        }
        N::Cmp(op, a, b) => {
            let (ta, tb) = (check(a, ctx, env)?, check(b, ctx, env)?);
            match (ta, tb) {
                (Ty::Num, Ty::Num) => {}
                (Ty::Word, Ty::Word) if matches!(*op, "=" | "!=") => {
                    if let (N::Param(p), N::Word(w)) | (N::Word(w), N::Param(p)) =
                        (a.as_ref(), b.as_ref())
                    {
                        let ok = env.params.iter().any(|x| {
                            x.name == *p && matches!(&x.choices, Choices::Words(l) if l.contains(w))
                        });
                        if !ok {
                            return Err(format!("\"{w}\" is no choice of {p}"));
                        }
                    }
                }
                _ => return Err("a comparison of two numbers or a param and a word".into()),
            }
            Ty::Bool
        }
        N::Not(a) => {
            truth(a)?;
            Ty::Bool
        }
        N::And(a, b) | N::Or(a, b) => {
            truth(a)?;
            truth(b)?;
            Ty::Bool
        }
        N::If(c, a, b) => {
            truth(c)?;
            let (ta, tb) = (check(a, ctx, env)?, check(b, ctx, env)?);
            if ta != tb || ta == Ty::Word {
                return Err("both branches must be numbers or both conditions".into());
            }
            ta
        }
    })
}
fn describe(node: &Node) -> String {
    use Node as N;
    match node {
        N::Km { .. } => "km".into(),
        N::Table { band: true, .. } => "band{}".into(),
        N::Table { band: false, .. } => "class{}".into(),
        N::Truth(t) => format!("{t:?}").to_ascii_lowercase(),
        N::TheirIn(_) => "their_in".into(),
        N::MyIn(_) => "my_in".into(),
        N::TheirCont(_) => "their_cont".into(),
        N::MyCont(_) => "my_cont".into(),
        N::Param(_) => "param".into(),
        N::Qsos => "qsos".into(),
        N::Points => "points".into(),
        N::Mults => "mults".into(),
        N::M(n) => format!("m.{n}"),
        _ => "a condition".into(),
    }
}

/// What an expression reads of one QSO, of my station and of the totals.
#[derive(Clone, Debug, Default)]
pub(crate) struct Vars<'a> {
    pub band: &'a str,
    pub class: Option<ModeClass>,
    /// Locators up to 6 characters.
    pub my_grid: Option<&'a str>,
    pub their_grid: Option<&'a str>,
    /// For the value only: the sender's entity centre when no locator is known.
    pub their_centre: Option<(f64, f64)>,
    pub my_prefix: Option<&'a str>,
    pub my_cont: Option<&'a str>,
    pub their_prefix: Option<&'a str>,
    pub their_cont: Option<&'a str>,
    pub their_member: bool,
    pub params: Option<&'a BTreeMap<String, PValue>>,
    pub sets: Option<&'a BTreeMap<String, Vec<String>>>,
    pub qsos: f64,
    pub points: f64,
    pub sets_sizes: Option<&'a BTreeMap<String, f64>>,
}
#[derive(Clone, Debug, PartialEq)]
enum Val {
    Num(f64),
    Bool(bool),
    Word(String),
}
/// Kilometres between the centres of two locators cut to 4 or 6 characters.
pub(crate) fn kilometres(a: &str, b: &str, six: bool, radius: f64) -> Option<f64> {
    let n = if six { 6 } else { 4 };
    let a = crate::strategy::maidenhead(a.get(..n)?)?;
    let b = crate::strategy::maidenhead(b.get(..n)?)?;
    Some(arc(a, b, radius))
}
fn arc(a: (f64, f64), b: (f64, f64), radius: f64) -> f64 {
    let r = std::f64::consts::PI / 180.0;
    let (la1, la2, dl) = (a.0 * r, b.0 * r, (b.1 - a.1) * r);
    let h = ((la2 - la1) / 2.0).sin().powi(2) + la1.cos() * la2.cos() * (dl / 2.0).sin().powi(2);
    2.0 * radius * h.sqrt().min(1.0).asin()
}
fn same(a: Option<&str>, b: Option<&str>, n: usize) -> bool {
    match (a.and_then(|a| a.get(..n)), b.and_then(|b| b.get(..n))) {
        (Some(a), Some(b)) => a.eq_ignore_ascii_case(b),
        _ => false,
    }
}
impl Expr {
    /// The number of an expression (None: a value it needs is missing, e.g. a locator).
    pub(crate) fn number(&self, v: &Vars) -> Option<f64> {
        match eval(&self.node, v)? {
            Val::Num(n) => Some(n),
            _ => None,
        }
    }
    /// The truth of a condition (a missing value is false).
    pub(crate) fn holds(&self, v: &Vars) -> bool {
        matches!(eval(&self.node, v), Some(Val::Bool(true)))
    }
}
fn eval(node: &Node, v: &Vars) -> Option<Val> {
    use Node as N;
    let num = |n: &Node| match eval(n, v)? {
        Val::Num(x) => Some(x),
        _ => None,
    };
    let truth = |n: &Node| match eval(n, v) {
        Some(Val::Bool(b)) => Some(b),
        _ => None,
    };
    let in_set = |set: &str, prefix: Option<&str>| {
        prefix.is_some_and(|p| {
            v.sets
                .and_then(|s| s.get(set))
                .is_some_and(|l| l.iter().any(|x| x == p))
        })
    };
    let param = |name: &str| v.params.and_then(|p| p.get(name)).cloned();
    Some(match node {
        N::Num(x) => Val::Num(*x),
        N::Word(w) => Val::Word(w.clone()),
        N::Km { six, radius } => {
            let my = v.my_grid?;
            Val::Num(match v.their_grid {
                Some(t) => kilometres(my, t, *six, *radius)?,
                None => {
                    let n = if *six { 6 } else { 4 };
                    let me = crate::strategy::maidenhead(my.get(..n)?)?;
                    arc(me, v.their_centre?, *radius)
                }
            })
        }
        N::Truth(t) => Val::Bool(match t {
            Truth::SameGrid4 => same(v.my_grid, v.their_grid, 4),
            Truth::SameGrid6 => same(v.my_grid, v.their_grid, 6),
            Truth::GridKnown => v.their_grid.is_some_and(|g| g.len() >= 4),
            Truth::SameDxcc => v.my_prefix.is_some() && v.my_prefix == v.their_prefix,
            Truth::SameContinent => v.my_cont.is_some() && v.my_cont == v.their_cont,
            Truth::TheirMember => v.their_member,
            Truth::MyMember => param("member") == Some(PValue::Bool(true)),
        }),
        N::TheirIn(s) => Val::Bool(in_set(s, v.their_prefix)),
        N::MyIn(s) => Val::Bool(in_set(s, v.my_prefix)),
        N::TheirCont(c) => Val::Bool(v.their_cont == Some(c.as_str())),
        N::MyCont(c) => Val::Bool(v.my_cont == Some(c.as_str())),
        N::Param(name) => match param(name)? {
            PValue::Bool(b) => Val::Bool(b),
            PValue::Number(n) => Val::Num(n as f64),
            PValue::Word(w) => Val::Word(w),
        },
        N::Qsos => Val::Num(v.qsos),
        N::Points => Val::Num(v.points),
        N::Mults => Val::Num(v.sets_sizes.map_or(0.0, |s| s.values().sum())),
        N::M(name) => Val::Num(v.sets_sizes.and_then(|s| s.get(name)).copied().unwrap_or(0.0)),
        N::Fn(f, args) => {
            let a = num(&args[0])?;
            Val::Num(match f {
                Func::Floor => a.floor(),
                Func::Ceil => a.ceil(),
                Func::Max => a.max(num(&args[1])?),
                Func::Min => a.min(num(&args[1])?),
            })
        }
        N::Table {
            band,
            entries,
            other,
        } => {
            let key = if *band {
                v.band.to_owned()
            } else {
                v.class?.name().to_owned()
            };
            match entries.iter().find(|(k, _)| *k == key) {
                Some((_, e)) => Val::Num(num(e)?),
                None => Val::Num(num(other.as_deref()?)?),
            }
        }
        N::Bin(op, a, b) => {
            let (a, b) = (num(a)?, num(b)?);
            Val::Num(match op {
                b'+' => a + b,
                b'-' => a - b,
                b'*' => a * b,
                // x/0 is 0.
                _ => {
                    if b == 0.0 {
                        0.0
                    } else {
                        a / b
                    }
                }
            })
        }
        N::Cmp(op, a, b) => {
            let (a, b) = (eval(a, v)?, eval(b, v)?);
            Val::Bool(match (a, b) {
                (Val::Num(a), Val::Num(b)) => match *op {
                    "=" => a == b,
                    "!=" => a != b,
                    "<" => a < b,
                    "<=" => a <= b,
                    ">" => a > b,
                    _ => a >= b,
                },
                (Val::Word(a), Val::Word(b)) => (*op == "=") == (a == b),
                _ => return None,
            })
        }
        N::Not(a) => Val::Bool(!truth(a).unwrap_or(false)),
        N::And(a, b) => Val::Bool(truth(a).unwrap_or(false) && truth(b).unwrap_or(false)),
        N::Or(a, b) => Val::Bool(truth(a).unwrap_or(false) || truth(b).unwrap_or(false)),
        N::If(c, a, b) => {
            if truth(c).unwrap_or(false) {
                eval(a, v)?
            } else {
                eval(b, v)?
            }
        }
    })
}

// ------------------------------------------------------------------ the wire and the prompt
impl Profile {
    /// The clause and text in force for the selected section (AutomationClause).
    pub(crate) fn clause_for(&self, entry: &BTreeMap<String, PValue>) -> (Clause, &str) {
        let a = &self.automation;
        if let Some(PValue::Word(section)) = entry.get("section")
            && let Some((_, c, t)) = a.by_section.iter().find(|(v, _, _)| v == section)
        {
            return (*c, t.as_str());
        }
        (a.clause, a.text.as_str())
    }
    /// The entry values with every absent param at its default.
    pub(crate) fn entry_defaults(&self) -> BTreeMap<String, PValue> {
        self.entry
            .params
            .iter()
            .map(|p| (p.name.clone(), p.default.clone()))
            .collect()
    }
    /// The window's limit (hours or days) under these entry values.
    pub(crate) fn window_limit(&self, entry: &BTreeMap<String, PValue>) -> Option<f64> {
        let w = self.schedule.window.as_ref()?;
        Some(match &w.limit {
            Limit::Number(n) => *n,
            Limit::Param(p) => match entry.get(p) {
                Some(PValue::Number(n)) => *n as f64,
                _ => return None,
            },
        })
    }
    /// The station can be set to the record's activity (eu_vhf: not before #99).
    pub(crate) fn station_activity(&self) -> Option<crate::contact::Activity> {
        crate::contact::Activity::parse(&self.exchange.activity)
    }
    fn modes_words(&self) -> String {
        match &self.modes.count {
            Count::List(l) => l.join(", "),
            Count::Digital => "Any digital mode".into(),
            Count::DigitalNoRtty => "Any digital mode except RTTY".into(),
            Count::Any => "Any mode".into(),
        }
    }
    fn series_words(&self) -> Option<String> {
        let s = self.schedule.series.as_ref()?;
        let mut t = format!(
            "Best {} of {} rounds per {}",
            s.best,
            s.of,
            if s.per == "band" { "band" } else { "contest" }
        );
        match s.normalise.as_str() {
            "winner_1000" => t.push_str(", the winner scores 1000"),
            "rank" => t.push_str(", scored by rank"),
            _ => {}
        }
        if s.annual.as_deref() == Some("sum_times_rounds") {
            t.push_str(", annual sum times the rounds entered");
        }
        t.push_str(" (not computed)");
        Some(t)
    }
    fn window_words(&self) -> Option<String> {
        let w = self.schedule.window.as_ref()?;
        let limit = match &w.limit {
            Limit::Number(n) => format!("{n}"),
            Limit::Param(p) => format!("the entry's {p}"),
        };
        let unit = if w.utc_day { "UTC days" } else { "hours" };
        Some(if w.best {
            format!("The best {limit} {unit} score")
        } else if w.min_off_minutes > 0 {
            format!(
                "The first {limit} {unit} of operating time score (off times of at least {} minutes)",
                w.min_off_minutes
            )
        } else {
            format!("The first {limit} {unit} of operating time score")
        })
    }
    /// The wire form of GET /strategy/contests (ContestHttp) at `now_ms` for my station.
    pub(crate) fn json(&self, now_ms: i64, me: &MyStation, file: &File) -> Value {
        let defaults = self.entry_defaults();
        let mine = |e: &Expr| {
            e.holds(&Vars {
                my_prefix: me.prefix.as_deref(),
                my_cont: me.continent.as_deref(),
                params: Some(&defaults),
                sets: Some(&file.sets),
                ..Vars::default()
            })
        };
        let eligible = self.entry.eligible.as_ref().map(mine);
        let unsendable = self.exchange.unsendable_for.as_ref().is_some_and(mine);
        let mut notes = self.notes.clone();
        if let Some(m) = &self.members
            && file.call_lists.get(m).is_none_or(Vec::is_empty)
        {
            notes.push("member points not counted".into());
        }
        json!({"id":self.id,"name":self.name,"organiser":self.organiser,"source":self.source,
            "checked":self.checked,"cabrillo":self.log.contest,
            "cabrillo_confirmed":self.log.confirmed,"log_format":self.log.format,
            "activity":self.exchange.activity,"cq":self.exchange.cq,"bands":self.bands,
            "modes":self.modes_words(),
            "dupes":self.dupe.per.iter().map(|d| d.name()).collect::<Vec<_>>(),
            "points":self.points.text,
            "multipliers":self.multipliers.iter().map(|m| json!({"name":m.name,
                "kind":m.kind.name(),"per":m.per.name()})).collect::<Vec<_>>(),
            "score":self.score.text,"extras":self.extras,
            "automation":self.automation.clause.name(),"automation_text":self.automation.text,
            "by_section":self.automation.by_section.iter().map(|(v,c,t)|
                (v.clone(), json!({"clause":c.name(),"text":t}))).collect::<Map<String,Value>>(),
            "schedule":self.schedule.text,"series":self.series_words(),
            "window":self.window_words(),
            "params":self.entry.params.iter().map(Param::json).collect::<Vec<_>>(),
            "eligible":eligible,
            "exchange_sendable":!unsendable && self.station_activity().is_some(),
            "notes":notes,"unconfirmed":self.unconfirmed,
            "period":self.schedule.next(now_ms).map(|o| json!({
                "start":crate::contest::utc_text(o.start_ms),
                "end":crate::contest::utc_text(o.end_ms),"band":o.band}))})
    }
}
/// My station as the prompt's notes read it.
#[derive(Clone, Debug, Default)]
pub(crate) struct MyStation {
    pub prefix: Option<String>,
    pub continent: Option<String>,
}
