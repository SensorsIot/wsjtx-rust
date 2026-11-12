#![forbid(unsafe_code)]
//! WstxStrategy (#39): the award strategies, the directed-CQ rule and their one evaluator.
//! Band Activity's marks and value order and the station's strategy runs
//! (WstxMcp::OperatingAutomation with a strategy) both use these verdicts; the browser
//! never evaluates a strategy itself. Routes: GET /strategy (StrategySnapshot), PUT
//! /strategy (configuration; a changed selection ends a run and, while Auto is on, starts
//! the new one), POST /strategy/auto (WstxStrategy::AutoToggle), POST /strategy/evaluate (verdicts of retained live rows), #42 GET /strategy/alerts and POST
//! /strategy/alerts/clear (WstxStrategy::Alert), POST /strategy/most-wanted/download
//! (WstxStrategy::MostWantedList), GET /strategy/contests (WstxContest::ContestHttp).
use crate::*;
use axum::extract::RawQuery;
use recording_http::authorize;
use selection_http::empty;
use std::collections::HashMap;
use std::time::{Duration, Instant};

#[cfg(test)]
#[path = "strategy_tests.rs"]
pub(crate) mod tests;

pub const FILE_NAME: &str = "strategy.json";
pub const BODY_MAX: usize = 32_768;
pub const STRATEGIES_MAX: usize = 16;
pub const EVALUATE_MAX: u64 = 2048;
/// #42 WstxStrategy::IgnoreLists bounds.
pub const IGNORE_CALLS_MAX: usize = 100;
pub const SESSION_IGNORE_MAX: usize = 64;
pub const SESSION_IGNORE_MINUTES: u64 = 30;
/// #42 WstxStrategy::Alert bounds: the history length and the dedupe window.
pub const ALERT_HISTORY_MAX: usize = 100;
pub const ALERT_DEDUPE_MS: i64 = 10 * 60_000;
const FILE_BYTES_MAX: u64 = 262_144;
const MAX_SAFE: u64 = 9_007_199_254_740_991;
use crate::contact::Activity;
pub use crate::dxcc::CONTINENTS;
use crate::dxcc::{Category, Standing, Worked};

/// WstxStrategy::StrategyClass (#97 D19), wire names "strategy" and "contest".
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Class {
    Strategy,
    Contest,
}
impl Class {
    fn name(self) -> &'static str {
        match self {
            Class::Strategy => "strategy",
            Class::Contest => "contest",
        }
    }
}
/// WstxStrategy::NewWhat, in wire order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum NewWhat {
    Dxcc,
    Call,
    Grid,
    CqZone,
    ItuZone,
    Continent,
    Prefix,
}
const WHATS: [(&str, NewWhat); 7] = [
    ("dxcc", NewWhat::Dxcc),
    ("call", NewWhat::Call),
    ("grid", NewWhat::Grid),
    ("cq_zone", NewWhat::CqZone),
    ("itu_zone", NewWhat::ItuZone),
    ("continent", NewWhat::Continent),
    ("prefix", NewWhat::Prefix),
];
impl NewWhat {
    fn name(self) -> &'static str {
        WHATS.iter().find(|g| g.1 == self).map_or("", |g| g.0)
    }
}
/// WstxStrategy::NewPer, least specific first.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum NewPer {
    Ever,
    Band,
    BandMode,
}
const PERS: [(&str, NewPer); 3] = [
    ("ever", NewPer::Ever),
    ("band", NewPer::Band),
    ("band_mode", NewPer::BandMode),
];
impl NewPer {
    fn name(self) -> &'static str {
        PERS.iter().find(|g| g.1 == self).map_or("", |g| g.0)
    }
}
/// WstxStrategy::ValueCriterion, the criteria of ValueOrder, wire names exactly.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Criterion {
    MostWanted,
    NewDxcc,
    NewDxccBand,
    NewDxccBandMode,
    NewCall,
    NewCallBand,
    NewGrid,
    NewGridBand,
    NewCqZone,
    NewItuZone,
    NewContinent,
    NewPrefix,
    SnrBucket,
    Snr,
    Distance,
    HearsUs,
}
const CRITERIA: [(&str, Criterion); 16] = [
    ("most_wanted", Criterion::MostWanted),
    ("new_dxcc", Criterion::NewDxcc),
    ("new_dxcc_band", Criterion::NewDxccBand),
    ("new_dxcc_band_mode", Criterion::NewDxccBandMode),
    ("new_call", Criterion::NewCall),
    ("new_call_band", Criterion::NewCallBand),
    ("new_grid", Criterion::NewGrid),
    ("new_grid_band", Criterion::NewGridBand),
    ("new_cq_zone", Criterion::NewCqZone),
    ("new_itu_zone", Criterion::NewItuZone),
    ("new_continent", Criterion::NewContinent),
    ("new_prefix", Criterion::NewPrefix),
    ("snr_bucket", Criterion::SnrBucket),
    ("snr", Criterion::Snr),
    ("distance", Criterion::Distance),
    ("hears_us", Criterion::HearsUs),
];
/// Strategy orderCriteriaMax.
pub const ORDER_MAX: usize = 16;
impl Criterion {
    fn name(self) -> &'static str {
        CRITERIA.iter().find(|c| c.1 == self).map_or("", |c| c.0)
    }
    /// The NewNeeded of a "new" criterion (ValueOrder).
    fn new_of(self) -> Option<(NewWhat, NewPer)> {
        Some(match self {
            Criterion::NewDxcc => (NewWhat::Dxcc, NewPer::Ever),
            Criterion::NewDxccBand => (NewWhat::Dxcc, NewPer::Band),
            Criterion::NewDxccBandMode => (NewWhat::Dxcc, NewPer::BandMode),
            Criterion::NewCall => (NewWhat::Call, NewPer::Ever),
            Criterion::NewCallBand => (NewWhat::Call, NewPer::Band),
            Criterion::NewGrid => (NewWhat::Grid, NewPer::Ever),
            Criterion::NewGridBand => (NewWhat::Grid, NewPer::Band),
            Criterion::NewCqZone => (NewWhat::CqZone, NewPer::Ever),
            Criterion::NewItuZone => (NewWhat::ItuZone, NewPer::Ever),
            Criterion::NewContinent => (NewWhat::Continent, NewPer::Ever),
            Criterion::NewPrefix => (NewWhat::Prefix, NewPer::Ever),
            _ => return None,
        })
    }
}
/// WstxStrategy::LeaveRule, the strategy's leave (#97 decision 5).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Leave {
    /// After `calls` calls without an answer, `heard` while he hears us.
    Calls { calls: u64, heard: u64 },
    /// Until logged; gone after `gone_minutes` without his decode.
    UntilLogged { gone_minutes: u64 },
    /// Contest style: stay while heard and most valuable, else leave after `tx_changes`.
    Contest { tx_changes: u64 },
}
impl Leave {
    fn json(self) -> Value {
        match self {
            Leave::Calls { calls, heard } => {
                json!({"mode":"calls","calls":calls,"calls_heard":heard})
            }
            Leave::UntilLogged { gone_minutes } => {
                json!({"mode":"until_logged","gone_minutes":gone_minutes})
            }
            Leave::Contest { tx_changes } => json!({"mode":"contest","tx_changes":tx_changes}),
        }
    }
    /// The LeaveMode's wire name.
    pub(crate) fn mode(self) -> &'static str {
        match self {
            Leave::Calls { .. } => "calls",
            Leave::UntilLogged { .. } => "until_logged",
            Leave::Contest { .. } => "contest",
        }
    }
}
/// WstxStrategy::TxMoveRule: k per PskCase (0 stay, 1 every call, n every n-th call).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct TxMoveEvery {
    pub heard: u64,
    pub not_heard: u64,
    pub no_reports: u64,
}
/// One entry of WstxStrategy::CountryList.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct CountryEntry {
    /// kind "country" (an entity name) or "prefix".
    pub country: bool,
    pub value: String,
    /// None: every band.
    pub bands: Option<Vec<String>>,
}
/// An include and an exclude list (CountryList, UsStateFilter, CqTargetList).
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Lists<T> {
    pub include: Vec<T>,
    pub exclude: Vec<T>,
}
impl<T> Default for Lists<T> {
    fn default() -> Self {
        Self {
            include: Vec::new(),
            exclude: Vec::new(),
        }
    }
}
/// WstxStrategy::Strategy bounds of the lists and bands.
pub const COUNTRIES_MAX: usize = 64;
pub const CQ_TARGETS_MAX: usize = 32;
pub const BANDS_MAX: usize = 32;
/// WstxStrategy::UsStateFilter: the 50 US states and DC.
pub const US_STATES: [&str; 51] = [
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI", "ID", "IL", "IN", "IA",
    "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM",
    "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA",
    "WV", "WI", "WY",
];
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Needed {
    NotWorked,
    NotConfirmed,
}
impl Needed {
    fn holds(self, s: Standing) -> bool {
        match self {
            Needed::NotWorked => !s.worked,
            Needed::NotConfirmed => s.needed(),
        }
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum Region {
    All,
    Dx,
    Selected(Vec<String>),
}
/// WstxStrategy::WorkedWindow; dates are YYYYMMDD.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Window {
    All,
    Today,
    FromTo(u32, u32),
}
/// WstxStrategy::Strategy (#97 D19, schema 4): the nine decisions of one strategy. A contest
/// strategy (class contest) uses only the three lists of its filters; the other filter fields
/// keep their base values and are never read for it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Strategy {
    pub name: String,
    pub class: Class,
    /// 1 Band (StrategyBands): None for every band.
    pub bands: Option<Vec<String>>,
    /// 2 Filters (Candidate).
    pub new: Vec<NewWhat>,
    pub new_per: NewPer,
    pub needed: Needed,
    pub region: Region,
    pub min_snr_db: Option<i64>,
    pub window: Window,
    pub treat_73_as_cq: bool,
    pub countries: Lists<CountryEntry>,
    pub states: Lists<String>,
    pub cq_targets: Lists<String>,
    /// 3 Order (ValueOrder): 0..16 unique criteria; [] for a contest.
    pub order: Vec<Criterion>,
    /// The contest id of a contest strategy (WstxContest::ProfileTable).
    pub contest: Option<&'static str>,
    /// 4 Calling stations are answered (off: a caller of my call has no rank, CL-097-03).
    pub callers_first: bool,
    /// 5 Leaving a station.
    pub leave: Leave,
    /// 6 Tx frequency.
    pub tx_move_every: TxMoveEvery,
    /// 7 Busy pause.
    pub busy_pause: bool,
    /// 8 CQ when idle (CqWhenNoTarget).
    pub cq_when_idle: bool,
    /// 8 The CQ wait (CL-097-08): fresh complete publications with nothing callable, 1..20.
    pub cq_wait_periods: u64,
    /// 9 Retry pause (QuietTime) in minutes, 1..120.
    pub retry_minutes: u64,
}
impl Strategy {
    /// The values every built-in shares (BuiltinStrategies "All five"), with new [dxcc] per band
    /// and mode, not confirmed, order [] and leave {calls 4, calls_heard 8}.
    pub(crate) fn base(name: &str) -> Self {
        Self {
            name: name.to_owned(),
            class: Class::Strategy,
            bands: None,
            new: vec![NewWhat::Dxcc],
            new_per: NewPer::BandMode,
            needed: Needed::NotConfirmed,
            region: Region::All,
            min_snr_db: None,
            window: Window::All,
            treat_73_as_cq: true,
            countries: Lists::default(),
            states: Lists::default(),
            cq_targets: Lists::default(),
            order: Vec::new(),
            contest: None,
            callers_first: true,
            leave: Leave::Calls { calls: 4, heard: 8 },
            tx_move_every: TxMoveEvery {
                heard: 0,
                not_heard: 1,
                no_reports: 2,
            },
            busy_pause: true,
            cq_when_idle: false,
            cq_wait_periods: CQ_WAIT_DEFAULT,
            retry_minutes: 10,
        }
    }
    /// The contest profile of a contest strategy.
    pub(crate) fn profile(&self) -> Option<&'static crate::contest::Profile> {
        self.contest.and_then(crate::contest::profile)
    }
}
/// WstxStrategy::BuiltinStrategies: the five built-ins of class strategy, in this order.
pub(crate) fn builtins() -> &'static [Strategy] {
    static TABLE: std::sync::OnceLock<Vec<Strategy>> = std::sync::OnceLock::new();
    TABLE.get_or_init(|| {
        let dxcc = |name: &str, per: NewPer| Strategy {
            new_per: per,
            order: vec![Criterion::MostWanted, Criterion::Snr],
            leave: Leave::UntilLogged { gone_minutes: 10 },
            ..Strategy::base(name)
        };
        let casual = |name: &str| Strategy {
            new: vec![NewWhat::Call],
            new_per: NewPer::Band,
            needed: Needed::NotWorked,
            order: vec![Criterion::SnrBucket, Criterion::Distance],
            cq_when_idle: true,
            ..Strategy::base(name)
        };
        vec![
            dxcc("DXCC all", NewPer::BandMode),
            dxcc("New DXCC on band", NewPer::Band),
            dxcc("New DXCC", NewPer::Ever),
            casual("Casual"),
            Strategy {
                window: Window::Today,
                cq_targets: Lists {
                    include: vec!["POTA".into(), "SOTA".into()],
                    exclude: Vec::new(),
                },
                cq_when_idle: false,
                ..casual("POTA/SOTA")
            },
        ]
    })
}
/// WstxStrategy::BuiltinStrategies: one read-only contest built-in per contest of the table,
/// with the contest defaults.
pub(crate) fn contest_builtins() -> &'static [Strategy] {
    static TABLE: std::sync::OnceLock<Vec<Strategy>> = std::sync::OnceLock::new();
    TABLE.get_or_init(|| {
        crate::contest::all_profiles()
            .iter()
            .map(|p| Strategy {
                class: Class::Contest,
                contest: Some(p.id),
                leave: Leave::Contest { tx_changes: 2 },
                tx_move_every: TxMoveEvery {
                    heard: 0,
                    not_heard: 2,
                    no_reports: 2,
                },
                busy_pause: false,
                cq_when_idle: true,
                ..Strategy::base(p.name)
            })
            .collect()
    })
}
fn is_builtin(name: &str) -> bool {
    builtins()
        .iter()
        .chain(contest_builtins())
        .any(|b| b.name.eq_ignore_ascii_case(name))
}
/// WstxStrategy::StrategyConfiguration.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Config {
    pub continent: Option<String>,
    pub active: Option<String>,
    pub strategies: Vec<Strategy>,
    /// #42 the permanent ignore list (exact calls) and the session list expiry.
    pub ignore_calls: Vec<String>,
    pub session_ignore_minutes: u64,
    /// #63 the contest in force (memory only, never with an active award strategy).
    pub contest: Option<crate::contest::Selection>,
}
impl Default for Config {
    fn default() -> Self {
        Self {
            continent: None,
            active: None,
            strategies: Vec::new(),
            ignore_calls: Vec::new(),
            session_ignore_minutes: SESSION_IGNORE_MINUTES,
            contest: None,
        }
    }
}

type Field = String;
fn bad(field: impl Into<String>) -> Field {
    field.into()
}
fn exact(v: &Value, keys: &[&str], field: &str) -> Result<(), Field> {
    let o = v.as_object().ok_or(bad(field))?;
    if o.len() != keys.len() || !keys.iter().all(|k| o.contains_key(*k)) {
        return Err(bad(field));
    }
    Ok(())
}
fn word(v: &Value, field: &str, max: usize, extra: &[u8]) -> Result<String, Field> {
    v.as_str()
        .filter(|s| {
            (1..=max).contains(&s.len())
                && s.bytes()
                    .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit() || extra.contains(&b))
        })
        .map(str::to_owned)
        .ok_or(bad(field))
}
fn bounded(v: &Value, field: &str, lo: u64, hi: u64) -> Result<u64, Field> {
    v.as_u64()
        .filter(|n| (lo..=hi).contains(n))
        .ok_or(bad(field))
}
/// A real calendar date "YYYY-MM-DD" in 1930..=2099 as YYYYMMDD.
fn date(v: &Value, field: &str) -> Result<u32, Field> {
    let text = v.as_str().ok_or(bad(field))?;
    let b = text.as_bytes();
    let digits = b.len() == 10
        && b[4] == b'-'
        && b[7] == b'-'
        && b.iter()
            .enumerate()
            .all(|(i, c)| i == 4 || i == 7 || c.is_ascii_digit());
    if !digits {
        return Err(bad(field));
    }
    let compact = format!("{}{}{}", &text[..4], &text[5..7], &text[8..]);
    let year: u32 = text[..4].parse().map_err(|_| bad(field))?;
    if !logbook::valid_date(&compact) || !(1930..=2099).contains(&year) {
        return Err(bad(field));
    }
    compact.parse().map_err(|_| bad(field))
}
fn date_text(d: u32) -> String {
    format!("{:04}-{:02}-{:02}", d / 10000, d / 100 % 100, d % 100)
}
/// CL-097-08: the CQ wait of every built-in, and of a schema 4 file written without the key.
pub(crate) const CQ_WAIT_DEFAULT: u64 = 2;
/// The exact keys of WstxStrategy::Strategy (schema 4), in the order of the decisions.
const STRATEGY_KEYS: [&str; 13] = [
    "name",
    "class",
    "bands",
    "filters",
    "order",
    "contest",
    "callers_first",
    "leave",
    "tx_move_every",
    "busy_pause",
    "cq_when_idle",
    "cq_wait_periods",
    "retry_minutes",
];
/// The exact filter keys of class strategy; class contest has only the three lists.
const FILTER_KEYS: [&str; 10] = [
    "new",
    "new_per",
    "new_means",
    "region",
    "min_snr_db",
    "worked_since",
    "treat_73_as_cq",
    "countries",
    "states",
    "cq_targets",
];
const LIST_KEYS: [&str; 3] = ["countries", "states", "cq_targets"];
/// StrategyBands: null, or 1..32 unique ADIF band names in lower case.
fn bands_of(v: &Value, field: &str) -> Result<Option<Vec<String>>, Field> {
    if v.is_null() {
        return Ok(None);
    }
    let list = v
        .as_array()
        .filter(|a| (1..=BANDS_MAX).contains(&a.len()))
        .ok_or(bad(field))?;
    let mut out: Vec<String> = Vec::new();
    for (i, b) in list.iter().enumerate() {
        let b = b
            .as_str()
            .filter(|b| logbook::is_band(b) && !out.iter().any(|o| o == b))
            .ok_or(bad(format!("{field}[{i}]")))?;
        out.push(b.to_owned());
    }
    Ok(Some(out))
}
/// An include and an exclude list, each 0..max entries read by `item` (unique when asked).
fn lists_of<T: PartialEq>(
    v: &Value,
    field: &str,
    max: usize,
    unique: bool,
    item: impl Fn(&Value, &str) -> Result<T, Field>,
) -> Result<Lists<T>, Field> {
    exact(v, &["include", "exclude"], field)?;
    let one = |k: &str| -> Result<Vec<T>, Field> {
        let lf = format!("{field}.{k}");
        let a = v[k].as_array().filter(|a| a.len() <= max).ok_or(bad(&lf))?;
        let mut out: Vec<T> = Vec::new();
        for (i, x) in a.iter().enumerate() {
            let fi = format!("{lf}[{i}]");
            let t = item(x, &fi)?;
            if unique && out.contains(&t) {
                return Err(fi);
            }
            out.push(t);
        }
        Ok(out)
    };
    Ok(Lists {
        include: one("include")?,
        exclude: one("exclude")?,
    })
}
/// CountryList entries; a country name must be in `table` when one is given (a PUT), a file's
/// entry is read as it is.
fn countries_of(
    v: &Value,
    field: &str,
    table: Option<&crate::dxcc::Table>,
) -> Result<Lists<CountryEntry>, Field> {
    lists_of(v, field, COUNTRIES_MAX, false, |e, f| {
        exact(e, &["kind", "value", "bands"], f)?;
        let country = match e["kind"].as_str() {
            Some("prefix") => false,
            Some("country") => true,
            _ => return Err(format!("{f}.kind")),
        };
        let vf = format!("{f}.value");
        let value = if country {
            let name = e["value"]
                .as_str()
                .filter(|n| (1..=64).contains(&n.len()))
                .ok_or(bad(&vf))?;
            match table {
                Some(t) => t
                    .cty
                    .entity_names()
                    .find(|n| n.eq_ignore_ascii_case(name))
                    .map(str::to_owned)
                    .ok_or(bad(&vf))?,
                None => name.to_owned(),
            }
        } else {
            word(&e["value"], &vf, 13, b"/")?
        };
        Ok(CountryEntry {
            country,
            value,
            bands: bands_of(&e["bands"], &format!("{f}.bands"))?,
        })
    })
}
fn strategy(v: &Value, field: &str, table: Option<&crate::dxcc::Table>) -> Result<Strategy, Field> {
    let f = |k: &str| format!("{field}.{k}");
    // CL-097-08: a strategy without its CQ wait is refused at that key.
    if v.is_object() && v.get("cq_wait_periods").is_none() {
        return Err(f("cq_wait_periods"));
    }
    exact(v, &STRATEGY_KEYS, field)?;
    let name = v["name"]
        .as_str()
        .filter(|n| {
            (1..=32).contains(&n.len())
                && n.trim() == *n
                && n.bytes().all(|b| (0x20..0x7f).contains(&b))
        })
        .ok_or(bad(f("name")))?
        .to_owned();
    let class = match v["class"].as_str() {
        Some("strategy") => Class::Strategy,
        Some("contest") => Class::Contest,
        _ => return Err(f("class")),
    };
    let bands = bands_of(&v["bands"], &f("bands"))?;
    let ff = f("filters");
    let fv = &v["filters"];
    exact(
        fv,
        if class == Class::Strategy {
            &FILTER_KEYS[..]
        } else {
            &LIST_KEYS[..]
        },
        &ff,
    )?;
    let countries = countries_of(&fv["countries"], &format!("{ff}.countries"), table)?;
    let states = lists_of(
        &fv["states"],
        &format!("{ff}.states"),
        US_STATES.len(),
        true,
        |s, f| {
            s.as_str()
                .filter(|s| US_STATES.contains(s))
                .map(str::to_owned)
                .ok_or(bad(f))
        },
    )?;
    let cq_targets = lists_of(
        &fv["cq_targets"],
        &format!("{ff}.cq_targets"),
        CQ_TARGETS_MAX,
        true,
        |s, f| word(s, f, 8, b""),
    )?;
    let order_field = f("order");
    let list = v["order"]
        .as_array()
        .filter(|c| c.len() <= ORDER_MAX && (class == Class::Strategy || c.is_empty()))
        .ok_or(bad(&order_field))?;
    let mut order = Vec::new();
    for (i, c) in list.iter().enumerate() {
        let criterion = CRITERIA
            .iter()
            .find(|k| c.as_str() == Some(k.0))
            .map(|k| k.1)
            .filter(|k| !order.contains(k))
            .ok_or(bad(format!("{order_field}[{i}]")))?;
        order.push(criterion);
    }
    let contest = match (class, &v["contest"]) {
        (Class::Strategy, Value::Null) => None,
        (Class::Contest, c) => Some(
            c.as_str()
                .and_then(crate::contest::profile)
                .ok_or(bad(f("contest")))?
                .id,
        ),
        _ => return Err(f("contest")),
    };
    let flag = |k: &str| v[k].as_bool().ok_or(bad(f(k)));
    let lf = f("leave");
    let lv = &v["leave"];
    let leave = match lv["mode"].as_str() {
        Some("calls") => {
            exact(lv, &["mode", "calls", "calls_heard"], &lf)?;
            let calls = bounded(&lv["calls"], &format!("{lf}.calls"), 1, 20)?;
            Leave::Calls {
                calls,
                heard: bounded(&lv["calls_heard"], &format!("{lf}.calls_heard"), calls, 40)?,
            }
        }
        Some("until_logged") => {
            exact(lv, &["mode", "gone_minutes"], &lf)?;
            Leave::UntilLogged {
                gone_minutes: bounded(&lv["gone_minutes"], &format!("{lf}.gone_minutes"), 1, 60)?,
            }
        }
        Some("contest") => {
            exact(lv, &["mode", "tx_changes"], &lf)?;
            Leave::Contest {
                tx_changes: bounded(&lv["tx_changes"], &format!("{lf}.tx_changes"), 1, 20)?,
            }
        }
        _ => return Err(format!("{lf}.mode")),
    };
    let tf = f("tx_move_every");
    let tv = &v["tx_move_every"];
    exact(tv, &["heard", "not_heard", "no_reports"], &tf)?;
    let k = |key: &str| bounded(&tv[key], &format!("{tf}.{key}"), 0, 20);
    let tx_move_every = TxMoveEvery {
        heard: k("heard")?,
        not_heard: k("not_heard")?,
        no_reports: k("no_reports")?,
    };
    let mut s = Strategy {
        name,
        class,
        bands,
        countries,
        states,
        cq_targets,
        order,
        contest,
        callers_first: flag("callers_first")?,
        leave,
        tx_move_every,
        busy_pause: flag("busy_pause")?,
        cq_when_idle: flag("cq_when_idle")?,
        cq_wait_periods: bounded(&v["cq_wait_periods"], &f("cq_wait_periods"), 1, 20)?,
        retry_minutes: bounded(&v["retry_minutes"], &f("retry_minutes"), 1, 120)?,
        ..Strategy::base("")
    };
    if class == Class::Contest {
        return Ok(s);
    }
    let list = fv["new"]
        .as_array()
        .filter(|g| (1..=WHATS.len()).contains(&g.len()))
        .ok_or(bad(format!("{ff}.new")))?;
    s.new.clear();
    for (i, g) in list.iter().enumerate() {
        let what = WHATS
            .iter()
            .find(|k| g.as_str() == Some(k.0))
            .map(|k| k.1)
            .filter(|k| !s.new.contains(k))
            .ok_or(bad(format!("{ff}.new[{i}]")))?;
        s.new.push(what);
    }
    s.new_per = PERS
        .iter()
        .find(|k| fv["new_per"].as_str() == Some(k.0))
        .map(|k| k.1)
        .ok_or(bad(format!("{ff}.new_per")))?;
    s.needed = match fv["new_means"].as_str() {
        Some("not_worked") => Needed::NotWorked,
        Some("not_confirmed") => Needed::NotConfirmed,
        _ => return Err(format!("{ff}.new_means")),
    };
    let (region, min_snr_db, window) = region_snr_window(fv, &ff)?;
    s.region = region;
    s.min_snr_db = min_snr_db;
    s.window = window;
    s.treat_73_as_cq = fv["treat_73_as_cq"]
        .as_bool()
        .ok_or(bad(format!("{ff}.treat_73_as_cq")))?;
    Ok(s)
}
/// The region, min_snr_db and worked_since filter lines (field paths under `field`).
fn region_snr_window(v: &Value, field: &str) -> Result<(Region, Option<i64>, Window), Field> {
    let f = |k: &str| format!("{field}.{k}");
    let region_field = f("region");
    let region = match v["region"]["kind"].as_str() {
        Some("all") => {
            exact(&v["region"], &["kind"], &region_field)?;
            Region::All
        }
        Some("dx") => {
            exact(&v["region"], &["kind"], &region_field)?;
            Region::Dx
        }
        Some("selected") => {
            exact(&v["region"], &["kind", "continents"], &region_field)?;
            let list = v["region"]["continents"]
                .as_array()
                .filter(|c| (1..=CONTINENTS.len()).contains(&c.len()))
                .ok_or(bad(format!("{region_field}.continents")))?;
            let mut out: Vec<String> = Vec::new();
            for (i, c) in list.iter().enumerate() {
                let c = c
                    .as_str()
                    .filter(|c| CONTINENTS.contains(c) && !out.iter().any(|o| o == c))
                    .ok_or(bad(format!("{region_field}.continents[{i}]")))?;
                out.push(c.to_owned());
            }
            Region::Selected(out)
        }
        _ => return Err(format!("{region_field}.kind")),
    };
    let min_snr_db = match &v["min_snr_db"] {
        Value::Null => None,
        n => Some(
            n.as_i64()
                .filter(|n| (-50..=49).contains(n))
                .ok_or(bad(f("min_snr_db")))?,
        ),
    };
    let window_field = f("worked_since");
    let wv = &v["worked_since"];
    let window = match wv["kind"].as_str() {
        Some("all") => {
            exact(wv, &["kind"], &window_field)?;
            Window::All
        }
        Some("today") => {
            exact(wv, &["kind"], &window_field)?;
            Window::Today
        }
        Some("from_to") => {
            exact(wv, &["kind", "from", "to"], &window_field)?;
            let from = date(&wv["from"], &format!("{window_field}.from"))?;
            let to = date(&wv["to"], &format!("{window_field}.to"))?;
            if from > to {
                return Err(format!("{window_field}.to"));
            }
            Window::FromTo(from, to)
        }
        _ => return Err(format!("{window_field}.kind")),
    };
    Ok((region, min_snr_db, window))
}
/// Exact StrategyConfiguration parsing (field names a refused value). `table`: the country
/// table a PUT checks country names against (None: a file, read as it is).
pub(crate) fn parse_config(v: &Value, table: Option<&crate::dxcc::Table>) -> Result<Config, Field> {
    // #63 contest is optional: a browser or a file without it selects no contest.
    let keys: &[&str] = if v.get("contest").is_some() {
        &[
            "continent",
            "active",
            "strategies",
            "ignore_calls",
            "session_ignore_minutes",
            "contest",
        ]
    } else {
        &[
            "continent",
            "active",
            "strategies",
            "ignore_calls",
            "session_ignore_minutes",
        ]
    };
    exact(v, keys, "configuration")?;
    let continent = match &v["continent"] {
        Value::Null => None,
        c => Some(
            c.as_str()
                .filter(|c| CONTINENTS.contains(c))
                .ok_or(bad("continent"))?
                .to_owned(),
        ),
    };
    let list = v["strategies"]
        .as_array()
        .filter(|s| s.len() <= STRATEGIES_MAX)
        .ok_or(bad("strategies"))?;
    let mut strategies: Vec<Strategy> = Vec::new();
    for (i, s) in list.iter().enumerate() {
        let s = strategy(s, &format!("strategies[{i}]"), table)?;
        if is_builtin(&s.name)
            || strategies
                .iter()
                .any(|o| o.name.eq_ignore_ascii_case(&s.name))
        {
            return Err(bad(format!("strategies[{i}].name")));
        }
        strategies.push(s);
    }
    let active = match &v["active"] {
        Value::Null => None,
        a => Some(
            a.as_str()
                .filter(|a| {
                    strategies
                        .iter()
                        .chain(builtins())
                        .chain(contest_builtins())
                        .any(|s| s.name == *a)
                })
                .ok_or(bad("active"))?
                .to_owned(),
        ),
    };
    let calls = v["ignore_calls"]
        .as_array()
        .filter(|a| a.len() <= IGNORE_CALLS_MAX)
        .ok_or(bad("ignore_calls"))?;
    let mut ignore_calls: Vec<String> = Vec::new();
    for (i, c) in calls.iter().enumerate() {
        let field = format!("ignore_calls[{i}]");
        let c = word(c, &field, 13, b"/")?;
        if ignore_calls.contains(&c) {
            return Err(bad(field));
        }
        ignore_calls.push(c);
    }
    // WstxContest::ContestSelection (#97): a contest goes with active naming a contest strategy
    // of its profile, and a contest strategy only with its contest.
    let contest = match v.get("contest") {
        None | Some(Value::Null) => None,
        Some(c) => Some(crate::contest::parse_selection(c, "contest")?),
    };
    let active_contest = active.as_deref().and_then(|a| {
        strategies
            .iter()
            .chain(builtins())
            .chain(contest_builtins())
            .find(|s| s.name == a)
            .and_then(|s| s.contest)
    });
    if contest.map(|c| c.profile.id) != active_contest {
        return Err(bad("contest"));
    }
    Ok(Config {
        contest,
        continent,
        active,
        strategies,
        ignore_calls,
        session_ignore_minutes: bounded(
            &v["session_ignore_minutes"],
            "session_ignore_minutes",
            1,
            720,
        )?,
    })
}
/// A file of schema_version 1 (rules, sort, auto role, highlight): strategies dropped,
/// active None, continent and the ignore keys kept. One written before #42 has neither
/// ignore key (exactly one of them stays malformed, parse_config refuses it).
fn upgrade(old: &Value) -> Value {
    let (calls, minutes) = (old.get("ignore_calls"), old.get("session_ignore_minutes"));
    let mut v = json!({"continent":old["continent"],"active":null,"strategies":[]});
    match (calls, minutes) {
        (None, None) => {
            v["ignore_calls"] = json!([]);
            v["session_ignore_minutes"] = json!(SESSION_IGNORE_MINUTES);
        }
        (calls, minutes) => {
            if let Some(c) = calls {
                v["ignore_calls"] = c.clone();
            }
            if let Some(m) = minutes {
                v["session_ignore_minutes"] = m.clone();
            }
        }
    }
    v
}
/// A file of schema_version 2 (before strategydef): each strategy's calls_per_station (1..20)
/// is dropped and the strategydef defaults are added. A strategy without calls_per_station,
/// with a bad one or with a key of schema 3 already is malformed (None).
fn upgrade_2(configuration: &Value) -> Option<Value> {
    let mut v = configuration.clone();
    if let Some(list) = v.get_mut("strategies").and_then(Value::as_array_mut) {
        for s in list {
            let o = s.as_object_mut()?;
            let old = o.remove("calls_per_station")?;
            if !old.as_u64().is_some_and(|n| (1..=20).contains(&n)) {
                return None;
            }
            for (k, default) in [
                ("value", json!(["most_wanted"])),
                ("callers_first", json!(true)),
                ("cq_when_no_target", json!(false)),
                ("repetitions", json!(4)),
                ("quiet_minutes", json!(10)),
            ] {
                if o.insert(k.to_owned(), default).is_some() {
                    return None;
                }
            }
        }
    }
    Some(v)
}
/// The exact keys of a schema 3 strategy (read only by the upgrade).
const SCHEMA_3_KEYS: [&str; 13] = [
    "name",
    "class",
    "goals",
    "needed",
    "region",
    "min_snr_db",
    "value",
    "callers_first",
    "cq_when_no_target",
    "repetitions",
    "quiet_minutes",
    "treat_73_as_cq",
    "window",
];
/// The schema 3 goals as (what, per) (StrategyConfiguration upgrade table).
fn goal_of(goal: &str) -> Option<(NewWhat, NewPer)> {
    Some(match goal {
        "dxcc" => (NewWhat::Dxcc, NewPer::Ever),
        "dxcc_band" => (NewWhat::Dxcc, NewPer::Band),
        "dxcc_slot" => (NewWhat::Dxcc, NewPer::BandMode),
        "waz" => (NewWhat::CqZone, NewPer::Ever),
        "wpx" => (NewWhat::Prefix, NewPer::Ever),
        "grid" => (NewWhat::Grid, NewPer::Ever),
        "new_call" => (NewWhat::Call, NewPer::Ever),
        "new_call_band" => (NewWhat::Call, NewPer::Band),
        _ => return None,
    })
}
/// #97 one schema 3 strategy mapped key by key to schema 4 (StrategyConfiguration); None when it
/// is not a schema 3 strategy (the file is then malformed). The values are checked by
/// parse_config afterwards.
pub(crate) fn upgrade_3_strategy(s: &Value) -> Option<Value> {
    let o = s.as_object()?;
    if o.len() != SCHEMA_3_KEYS.len() || !SCHEMA_3_KEYS.iter().all(|k| o.contains_key(*k)) {
        return None;
    }
    if s["class"] != "award" {
        return None;
    }
    let goals = s["goals"].as_array().filter(|g| !g.is_empty())?;
    let mut whats: Vec<NewWhat> = Vec::new();
    let mut per = NewPer::Ever;
    for g in goals {
        let (what, p) = goal_of(g.as_str()?)?;
        if !whats.contains(&what) {
            whats.push(what);
        }
        per = per.max(p);
    }
    let order: Vec<Value> = s["value"]
        .as_array()?
        .iter()
        .map(|c| {
            if c == "new_dxcc_slot" {
                json!("new_dxcc_band_mode")
            } else {
                c.clone()
            }
        })
        .collect();
    let repetitions = s["repetitions"].as_u64()?;
    let empty = json!({"include":[],"exclude":[]});
    Some(json!({"name":s["name"],"class":"strategy","bands":null,
        "filters":{"new":whats.iter().map(|w| w.name()).collect::<Vec<_>>(),
            "new_per":per.name(),"new_means":s["needed"],"region":s["region"],
            "min_snr_db":s["min_snr_db"],"worked_since":s["window"],
            "treat_73_as_cq":s["treat_73_as_cq"],"countries":empty,"states":empty,
            "cq_targets":empty},
        "order":order,"contest":null,"callers_first":s["callers_first"],
        "leave":{"mode":"calls","calls":repetitions,"calls_heard":repetitions.saturating_mul(2)},
        "tx_move_every":{"heard":0,"not_heard":1,"no_reports":2},"busy_pause":true,
        "cq_when_idle":s["cq_when_no_target"],"cq_wait_periods":CQ_WAIT_DEFAULT,
        "retry_minutes":s["quiet_minutes"]}))
}
/// A schema 4 file: a strategy written without cq_wait_periods reads with the default
/// (StrategyConfiguration); a PUT always carries the key.
fn with_cq_wait(configuration: &Value) -> Value {
    let mut v = configuration.clone();
    if let Some(list) = v.get_mut("strategies").and_then(Value::as_array_mut) {
        for s in list {
            if let Some(o) = s.as_object_mut() {
                o.entry("cq_wait_periods").or_insert(json!(CQ_WAIT_DEFAULT));
            }
        }
    }
    v
}
/// A schema 3 configuration with every strategy mapped to schema 4.
fn upgrade_3(configuration: &Value) -> Option<Value> {
    let mut v = configuration.clone();
    if let Some(list) = v.get_mut("strategies").and_then(Value::as_array_mut) {
        for s in list.iter_mut() {
            *s = upgrade_3_strategy(s)?;
        }
    }
    Some(v)
}
/// StrategyConfiguration names: a saved strategy whose name equals a built-in's ignoring case
/// reads renamed "<name> copy", else "<name> copy 2", ..., the first free name of at most 32
/// characters (the name cut so that the suffix fits). Returns the renames (from, to).
fn rename_builtin_names(configuration: &mut Value) -> Vec<(String, String)> {
    let mut renames = Vec::new();
    let Some(list) = configuration["strategies"].as_array_mut() else {
        return renames;
    };
    let mut taken: Vec<String> = list
        .iter()
        .filter_map(|s| s["name"].as_str().map(str::to_ascii_lowercase))
        .collect();
    for s in list.iter_mut() {
        let Some(name) = s["name"].as_str().map(str::to_owned) else {
            continue;
        };
        if !is_builtin(&name) {
            continue;
        }
        let free = |n: &str| !is_builtin(n) && !taken.contains(&n.to_ascii_lowercase());
        let renamed = (1..)
            .map(|i| {
                let suffix = if i == 1 {
                    " copy".to_owned()
                } else {
                    format!(" copy {i}")
                };
                let keep = 32usize.saturating_sub(suffix.len()).min(name.len());
                format!("{}{suffix}", name[..keep].trim_end())
            })
            .find(|n| free(n))
            .unwrap_or_default();
        taken.push(renamed.to_ascii_lowercase());
        s["name"] = json!(renamed);
        renames.push((name, renamed));
    }
    renames
}
fn lists_json<T>(l: &Lists<T>, item: impl Fn(&T) -> Value) -> Value {
    json!({"include":l.include.iter().map(&item).collect::<Vec<_>>(),
        "exclude":l.exclude.iter().map(&item).collect::<Vec<_>>()})
}
impl Strategy {
    pub(crate) fn json(&self) -> Value {
        let countries = lists_json(
            &self.countries,
            |e| json!({"kind":if e.country {"country"} else {"prefix"},"value":e.value,"bands":e.bands}),
        );
        let states = lists_json(&self.states, |s| json!(s));
        let cq_targets = lists_json(&self.cq_targets, |s| json!(s));
        let filters = match self.class {
            Class::Contest => {
                json!({"countries":countries,"states":states,"cq_targets":cq_targets})
            }
            Class::Strategy => json!({
                "new":self.new.iter().map(|g| g.name()).collect::<Vec<_>>(),
                "new_per":self.new_per.name(),
                "new_means":match self.needed {Needed::NotWorked=>"not_worked",Needed::NotConfirmed=>"not_confirmed"},
                "region":match &self.region {
                    Region::All=>json!({"kind":"all"}),
                    Region::Dx=>json!({"kind":"dx"}),
                    Region::Selected(c)=>json!({"kind":"selected","continents":c}),
                },
                "min_snr_db":self.min_snr_db,
                "worked_since":match self.window {
                    Window::All=>json!({"kind":"all"}),
                    Window::Today=>json!({"kind":"today"}),
                    Window::FromTo(a,b)=>json!({"kind":"from_to","from":date_text(a),"to":date_text(b)}),
                },
                "treat_73_as_cq":self.treat_73_as_cq,
                "countries":countries,"states":states,"cq_targets":cq_targets}),
        };
        let t = self.tx_move_every;
        json!({"name":self.name,"class":self.class.name(),"bands":self.bands,"filters":filters,
            "order":self.order.iter().map(|c| c.name()).collect::<Vec<_>>(),
            "contest":self.contest,"callers_first":self.callers_first,"leave":self.leave.json(),
            "tx_move_every":{"heard":t.heard,"not_heard":t.not_heard,"no_reports":t.no_reports},
            "busy_pause":self.busy_pause,"cq_when_idle":self.cq_when_idle,
            "cq_wait_periods":self.cq_wait_periods,"retry_minutes":self.retry_minutes})
    }
}
impl Config {
    pub(crate) fn json(&self) -> Value {
        let mut v = json!({"continent":self.continent,"active":self.active,
            "strategies":self.strategies.iter().map(Strategy::json).collect::<Vec<_>>(),
            "ignore_calls":self.ignore_calls,"session_ignore_minutes":self.session_ignore_minutes});
        if let Some(c) = &self.contest {
            v["contest"] = c.json();
        }
        v
    }
    /// The contest in force (WstxContest::ContestSelection): with Auto on it runs
    /// (WstxContest::ContestRun), with Auto off it only marks.
    pub(crate) fn automatic_contest(&self) -> Option<crate::contest::Selection> {
        self.contest
    }
    /// A contest whose WstxContest::AutomationClause is forbidden: Auto on needs the confirmation.
    pub(crate) fn forbidden_contest(&self) -> bool {
        self.contest
            .is_some_and(|c| c.profile.automation == crate::contest::AutomationClause::Forbidden)
    }
    /// A selection: an active strategy or a contest (WstxStrategy::AutoToggle).
    pub(crate) fn selected(&self) -> bool {
        self.active.is_some() || self.contest.is_some()
    }
    /// What a run follows: the active strategy (#97: a contest strategy with its contest; the
    /// contest evaluates, the strategy's decisions bound the run).
    pub(crate) fn run_strategy(&self) -> Option<Strategy> {
        self.active_strategy().cloned()
    }
    /// The active strategy: a saved one, a built-in or a contest built-in.
    pub(crate) fn active_strategy(&self) -> Option<&Strategy> {
        let name = self.active.as_deref()?;
        self.strategies
            .iter()
            .chain(builtins())
            .chain(contest_builtins())
            .find(|s| s.name == name)
    }
}

// ------------------------------------------------------------------ geography
/// The centre of a 4- or 6-character Maidenhead locator (lat, lon), as the browser's
/// distance and theme code compute it.
pub(crate) fn maidenhead(grid: &str) -> Option<(f64, f64)> {
    let g = grid.to_ascii_uppercase();
    let b = g.as_bytes();
    let ok = (b.len() == 4 || b.len() == 6)
        && (b'A'..=b'R').contains(&b[0])
        && (b'A'..=b'R').contains(&b[1])
        && b[2].is_ascii_digit()
        && b[3].is_ascii_digit()
        && (b.len() == 4 || ((b'A'..=b'X').contains(&b[4]) && (b'A'..=b'X').contains(&b[5])));
    if !ok {
        return None;
    }
    let sub = b.len() == 6;
    let n = |i: usize| f64::from(b[i] - b'A');
    let d = |i: usize| f64::from(b[i] - b'0');
    let lon = n(0) * 20.0 - 180.0
        + d(2) * 2.0
        + if sub {
            n(4) * (2.0 / 24.0) + 1.0 / 24.0
        } else {
            1.0
        };
    let lat = n(1) * 10.0 - 90.0
        + d(3)
        + if sub {
            n(5) * (1.0 / 24.0) + 1.0 / 48.0
        } else {
            0.5
        };
    Some((lat, lon))
}
/// Whole km and degrees between two (lat, lon) points.
pub(crate) fn great_circle(a: (f64, f64), b: (f64, f64)) -> (f64, f64) {
    let r = std::f64::consts::PI / 180.0;
    let (la1, la2, dl) = (a.0 * r, b.0 * r, (b.1 - a.1) * r);
    let h = ((la2 - la1) / 2.0).sin().powi(2) + la1.cos() * la2.cos() * (dl / 2.0).sin().powi(2);
    let km = (12_742.0 * h.sqrt().min(1.0).asin()).round();
    let y = dl.sin() * la2.cos();
    let x = la1.cos() * la2.sin() - la1.sin() * la2.cos() * dl.cos();
    let az = (y.atan2(x) / r + 360.0) % 360.0;
    (km, az.round())
}
/// The great-circle distance in km between two (lat, lon) points, unrounded (haversine on a
/// sphere of 6371 km, as great_circle).
fn haversine_km(a: (f64, f64), b: (f64, f64)) -> f64 {
    let r = std::f64::consts::PI / 180.0;
    let (la1, la2, dl) = (a.0 * r, b.0 * r, (b.1 - a.1) * r);
    let h = ((la2 - la1) / 2.0).sin().powi(2) + la1.cos() * la2.cos() * (dl / 2.0).sin().powi(2);
    12_742.0 * h.sqrt().min(1.0).asin()
}
/// WstxStrategy::StationDistance: whole km (truncated) from the centre of the profile locator
/// to the centre of the 4-character grid in the message, else to the sender's cty.dat entity
/// centre (the entity distance of DecodedEntity). None without a profile locator, or without
/// grid and entity.
pub(crate) fn station_distance(st: &Station, f: &Facts) -> Option<u64> {
    let me = st.my_locator.as_deref().and_then(maidenhead)?;
    let theirs = f
        .grid
        .as_deref()
        .and_then(|g| g.get(..4))
        .and_then(maidenhead)
        .or_else(|| st.dxcc.lookup(&f.from).map(|e| (e.lat, e.lon)))?;
    Some(haversine_km(me, theirs).floor() as u64)
}

// ------------------------------------------------------------------ evaluation
/// What the evaluator reads of one decoded standard record.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Facts {
    pub sequence: u64,
    pub from: String,
    pub to_call: Option<String>,
    pub cq: bool,
    pub target: Option<String>,
    pub signoff: bool,
    pub grid: Option<String>,
    pub snr: Option<f64>,
    /// The audio frequency (Hz), for an exact tie of ValueOrder.
    pub hz: Option<f64>,
}
pub(crate) fn facts(record: &Value) -> Option<Facts> {
    let f = &record["fields"];
    if record["status"] != "decoded" || f["type"] != "standard" || f["from"]["kind"] != "call" {
        return None;
    }
    let to = f["to"]["text"].as_str().unwrap_or("");
    let token = f["to"]["kind"] == "token";
    let cq = token && (to == "CQ" || to.starts_with("CQ "));
    let ex = &f["exchange"];
    Some(Facts {
        sequence: record["sequence"].as_u64()?,
        from: f["from"]["text"].as_str()?.to_owned(),
        to_call: (f["to"]["kind"] == "call").then(|| to.to_owned()),
        cq,
        target: cq
            .then(|| to.strip_prefix("CQ ").map(str::to_owned))
            .flatten(),
        signoff: ex["kind"] == "roger" && matches!(ex["value"].as_str(), Some("RR73" | "73")),
        grid: (ex["kind"] == "grid")
            .then(|| ex["value"].as_str().map(str::to_owned))
            .flatten()
            .filter(|g| maidenhead(g).is_some()),
        snr: record["snr_db"].as_f64(),
        hz: record["frequency_hz"].as_f64(),
    })
}
/// Station facts of one evaluation: my call and continent, the band, the mode, the country
/// table (#55), the worked set of the strategy's window (None: the log is unreadable), the
/// ignore lists (#42) and the Most Wanted list.
#[derive(Clone, Debug, Default)]
pub(crate) struct Station {
    pub my_call: String,
    pub my_continent: Option<String>,
    pub band: Option<String>,
    pub dxcc: crate::dxcc::Table,
    pub mode: String,
    pub worked: Option<std::sync::Arc<Worked>>,
    pub ignored: HashMap<String, Tier>,
    pub most_wanted: Option<std::sync::Arc<crate::most_wanted::List>>,
    /// #63 the station's activity, for the DirectedCqRule.
    pub activity: Activity,
    /// #63 the profile locator, for a contest's distance points.
    pub my_locator: Option<String>,
    /// #97 ValueOrder hears_us: the stations with a spot of my call at most 600 s old on this
    /// band and mode; None with PskrUse off or no feed (the criterion ties).
    pub hears: Option<Vec<String>>,
}
/// The list an ignored call is on (the session list wins when on both).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Tier {
    Session,
    Permanent,
}
impl Tier {
    pub(crate) fn name(self) -> &'static str {
        match self {
            Tier::Session => "session",
            Tier::Permanent => "permanent",
        }
    }
}
#[derive(Clone, Debug)]
struct SessionEntry {
    call: String,
    band: Option<String>,
    until: Instant,
}
/// #42 WstxStrategy::IgnoreLists session list: station memory only, at most 64 entries in
/// the order added, each ending at its expiry; any change of the observed station band
/// empties it.
#[derive(Clone, Debug, Default)]
pub(crate) struct Session {
    entries: Vec<SessionEntry>,
    /// The station band seen last (None: nothing observed yet).
    seen: Option<Option<String>>,
}
impl Session {
    /// Adds (or renews and moves last) a call for `minutes` from `now`.
    pub(crate) fn add(&mut self, call: &str, band: Option<&str>, minutes: u64, now: Instant) {
        self.entries.retain(|e| e.call != call);
        if self.entries.len() >= SESSION_IGNORE_MAX {
            self.entries.remove(0);
        }
        self.entries.push(SessionEntry {
            call: call.to_owned(),
            band: band.map(str::to_owned),
            until: now + Duration::from_secs(minutes * 60),
        });
    }
    pub(crate) fn remove(&mut self, call: &str) {
        self.entries.retain(|e| e.call != call);
    }
    /// The station band now: a change from the band seen last empties the list.
    pub(crate) fn observe_band(&mut self, band: Option<&str>) {
        let band = band.map(str::to_owned);
        if self.seen.as_ref().is_some_and(|seen| *seen != band) {
            self.entries.clear();
        }
        self.seen = Some(band);
    }
    /// The live entries (ended ones dropped): call, band, whole seconds left (rounded up).
    pub(crate) fn entries(&mut self, now: Instant) -> Vec<(String, Option<String>, u64)> {
        self.entries.retain(|e| e.until > now);
        self.entries
            .iter()
            .map(|e| {
                let left = e.until - now;
                let secs = left.as_secs() + u64::from(left.subsec_nanos() > 0);
                (e.call.clone(), e.band.clone(), secs)
            })
            .collect()
    }
}
/// WstxStrategy::DirectedCqRule, the one directive rule of strategies and the operator:
/// a plain CQ, CQ <my continent> or CQ DX from another known continent. Every other
/// directive excludes me.
pub(crate) fn answerable(target: Option<&str>, mine: Option<&str>, sender: Option<&str>) -> bool {
    match target {
        None => true,
        Some("DX") => mine.zip(sender).is_some_and(|(m, s)| m != s),
        Some(t) => mine == Some(t),
    }
}
/// #63 the rule in a contest activity: the activity's own CQ word (CQ TEST, WW, FD, RU) is also
/// answerable, without a warning.
pub(crate) fn answerable_in(
    activity: Activity,
    target: Option<&str>,
    mine: Option<&str>,
    sender: Option<&str>,
) -> bool {
    (target.is_some() && target == activity.cq()) || answerable(target, mine, sender)
}
/// The DirectedCqRule text of a CQ that is not answerable.
fn not_for_me(target: &str, mine: Option<&str>) -> String {
    format!("CQ {target} — not for {}", mine.unwrap_or("this station"))
}
/// The DirectedCqRule verdict of an operator's selection of this record: the warning text
/// when it is a CQ that is not answerable in this activity (the caller holds the contact lock).
pub(crate) fn selection_warning(
    state: &ProfileState,
    record: &Value,
    activity: Activity,
) -> Option<String> {
    let f = facts(record)?;
    let (call, locator) = contact_http::profile_facts(state);
    let (dxcc, _) = state.logbook.dxcc();
    let config = state
        .recording
        .contact
        .get()?
        .strategy
        .config(state)
        .unwrap_or_default();
    let mine = my_continent(&config, call.as_deref(), locator.as_deref(), &dxcc);
    (!answerable_in(
        activity,
        f.target.as_deref(),
        mine.as_deref(),
        dxcc.continent(&f.from),
    ))
    .then(|| not_for_me(f.target.as_deref().unwrap_or(""), mine.as_deref()))
}
/// #97 CqTargetList: the strategy run's own select_row of this record passes the directed-CQ
/// check when it is a CQ whose directive word is on the active strategy's include list (the
/// caller holds the contact lock; the strategy lock is a leaf).
pub(crate) fn run_admits(state: &ProfileState, record: &Value) -> bool {
    let Some(f) = facts(record) else {
        return false;
    };
    state
        .recording
        .contact
        .get()
        .and_then(|s| s.strategy.config(state))
        .and_then(|c| c.active_strategy().cloned())
        .is_some_and(|s| f.cq && included_target(&s, f.target.as_deref()))
}
impl Station {
    /// A CQ, or with treat_73_as_cq an RR73/73 that ends someone else's QSO.
    pub(crate) fn cq_like(&self, f: &Facts, treat_73_as_cq: bool) -> bool {
        f.cq || (treat_73_as_cq
            && f.signoff
            && f.to_call.as_deref().is_some_and(|t| t != self.my_call))
    }
    /// A CQ that is not answerable is greyed and is never a candidate nor answered by a run.
    pub(crate) fn greyed(&self, f: &Facts) -> bool {
        !answerable_in(
            self.activity,
            f.target.as_deref(),
            self.my_continent.as_deref(),
            self.dxcc.continent(&f.from),
        )
    }
    /// The DirectedCqRule text of a greyed record.
    pub(crate) fn directive_text(&self, f: &Facts) -> String {
        not_for_me(
            f.target.as_deref().unwrap_or(""),
            self.my_continent.as_deref(),
        )
    }
    /// WstxStrategy::CallerOfMyCall, before the ignore check.
    pub(crate) fn calls_me(&self, f: &Facts) -> bool {
        f.to_call.as_deref() == Some(self.my_call.as_str()) && !f.signoff
    }
    fn region_holds(&self, s: &Strategy, f: &Facts) -> bool {
        let theirs = self.dxcc.continent(&f.from);
        match &s.region {
            Region::All => true,
            Region::Dx => self
                .my_continent
                .as_deref()
                .zip(theirs)
                .is_some_and(|(m, t)| m != t),
            Region::Selected(list) => theirs.is_some_and(|t| list.iter().any(|c| c == t)),
        }
    }
    /// WstxStrategy::NewNeeded: whether `what` is new for the sender per `per`, with the
    /// strategy's new_means and the worked set of its window. False without the log, without
    /// an entity (the entity whats) and without a known band (per band and band_mode).
    pub(crate) fn new_needed(&self, s: &Strategy, what: NewWhat, per: NewPer, f: &Facts) -> bool {
        let Some(w) = &self.worked else { return false };
        let (band, mode) = match per {
            NewPer::Ever => (None, None),
            NewPer::Band => (self.band.as_deref(), None),
            NewPer::BandMode => (self.band.as_deref(), Some(self.mode.as_str())),
        };
        if per != NewPer::Ever && band.is_none() {
            return false;
        }
        let entity = |c: Category| {
            self.dxcc
                .lookup(&f.from)
                .is_some_and(|r| s.needed.holds(w.entity_standing(c, &r, band, mode)))
        };
        match what {
            NewWhat::Dxcc => entity(Category::Dxcc),
            NewWhat::CqZone => entity(Category::CqZone),
            NewWhat::ItuZone => entity(Category::ItuZone),
            NewWhat::Continent => entity(Category::Continent),
            NewWhat::Call => s.needed.holds(w.call_scoped(&f.from, band, mode)),
            NewWhat::Prefix => s.needed.holds(w.wpx_scoped(&f.from, band, mode)),
            // D13: no grid in the message, or a logged QSO without one: unknown, never new.
            NewWhat::Grid => {
                !w.gridless(&f.from)
                    && f.grid
                        .as_deref()
                        .is_some_and(|g| s.needed.holds(w.grid_scoped(g, band, mode)))
            }
        }
    }
    /// WstxStrategy::StrategyBands: why every verdict is unranked off the strategy's bands.
    fn off_band(&self, s: &Strategy) -> Option<&'static str> {
        let bands = s.bands.as_ref()?;
        match self.band.as_deref() {
            None => Some("band unknown"),
            Some(b) if !bands.iter().any(|x| x == b) => Some("band not in the strategy"),
            Some(_) => None,
        }
    }
    /// WstxStrategy::UsStateOf: the message's exchange first, then the log.
    fn us_state(&self, f: &Facts, from_messages: &HashMap<String, String>) -> Option<String> {
        let entity = self.dxcc.lookup(&f.from)?;
        if !crate::dxcc::US_ENTITIES.contains(&entity.name.as_str()) {
            return None;
        }
        from_messages
            .get(&f.from)
            .cloned()
            .or_else(|| self.worked.as_ref()?.state_of(&f.from).map(str::to_owned))
            .filter(|s| US_STATES.contains(&s.as_str()))
    }
    /// The three lists of a strategy (CountryList, UsStateFilter and, for a CQ, CqTargetList):
    /// the failing line's why, or None.
    fn lists_fail(
        &self,
        s: &Strategy,
        f: &Facts,
        states: &HashMap<String, String>,
        caller: bool,
    ) -> Option<&'static str> {
        let entity = self.dxcc.lookup(&f.from);
        let band = self.band.as_deref();
        let matches = |e: &CountryEntry| {
            e.bands
                .as_ref()
                .is_none_or(|b| band.is_some_and(|band| b.iter().any(|x| x == band)))
                && if e.country {
                    entity
                        .as_ref()
                        .is_some_and(|r| r.name.eq_ignore_ascii_case(&e.value))
                } else {
                    f.from.starts_with(&e.value)
                }
        };
        let c = &s.countries;
        if c.exclude.iter().any(matches)
            || (!c.include.is_empty() && !c.include.iter().any(matches))
        {
            return Some("country list");
        }
        if !s.states.include.is_empty() || !s.states.exclude.is_empty() {
            let state = self.us_state(f, states);
            let listed = |l: &[String]| state.as_ref().is_some_and(|st| l.contains(st));
            if listed(&s.states.exclude)
                || (!s.states.include.is_empty() && !listed(&s.states.include))
            {
                return Some("state list");
            }
        }
        if !caller {
            let word = f.target.as_ref().filter(|_| f.cq);
            let listed = |l: &[String]| word.is_some_and(|w| l.contains(w));
            if listed(&s.cq_targets.exclude)
                || (!s.cq_targets.include.is_empty() && !listed(&s.cq_targets.include))
            {
                return Some("CQ target");
            }
        }
        None
    }
    /// The Most Wanted rank of the sender's entity (None: not listed or no list).
    fn most_wanted_rank(&self, f: &Facts) -> Option<u32> {
        self.most_wanted
            .as_ref()
            .and_then(|l| self.dxcc.lookup(&f.from).and_then(|r| l.rank(&r.name)))
    }
    /// One criterion as a key, smaller first: (0 better group, 1 worse or unknown; the value
    /// inside the group).
    fn criterion_key(&self, s: &Strategy, c: Criterion, f: &Facts) -> (u8, f64) {
        let known = |v: Option<f64>| v.map_or((1, 0.0), |v| (0, -v));
        if let Some((what, per)) = c.new_of() {
            return (u8::from(!self.new_needed(s, what, per, f)), 0.0);
        }
        match c {
            Criterion::MostWanted => self
                .most_wanted_rank(f)
                .map_or((1, 0.0), |rank| (0, f64::from(rank))),
            Criterion::Distance => known(station_distance(self, f).map(|km| km as f64)),
            Criterion::Snr => known(f.snr),
            // Above 0 dB, -10..0 dB, below -10 dB, unknown; equal inside a bucket.
            Criterion::SnrBucket => (
                match f.snr {
                    Some(snr) if snr > 0.0 => 0,
                    Some(snr) if snr >= -10.0 => 1,
                    Some(_) => 2,
                    None => 3,
                },
                0.0,
            ),
            Criterion::HearsUs => (
                u8::from(self.hears.as_ref().is_some_and(|h| !h.contains(&f.from))),
                0.0,
            ),
            _ => (0, 0.0),
        }
    }
}
/// The exact tie of ValueOrder (and ContestValueOrder): the lower audio frequency (unknown
/// last), then the call in character order. Decode order is never a ranking.
pub(crate) fn exact_tie(a: &Facts, b: &Facts) -> std::cmp::Ordering {
    let hz = |f: &Facts| f.hz.unwrap_or(f64::INFINITY);
    hz(a).total_cmp(&hz(b)).then_with(|| a.from.cmp(&b.from))
}
/// What a ranked record is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Kind {
    Caller,
    Candidate,
}
/// WstxStrategy::Verdict of one record.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Verdict {
    pub facts: Facts,
    pub rank: Option<usize>,
    pub grey: bool,
    pub why: String,
    pub kind: Option<Kind>,
    /// #63 what a contest adds (WstxContest::ContestVerdict).
    pub contest: Option<crate::contest::ContestValue>,
}
impl Verdict {
    pub(crate) fn json(&self, explain: bool) -> Value {
        let mut v = json!({"sequence":self.facts.sequence,"rank":self.rank,"grey":self.grey});
        if explain {
            v["why"] = json!(self.why);
        }
        if let Some(c) = self.contest {
            v["dupe"] = json!(c.dupe);
            v["new_multiplier"] = json!(c.new_multiplier);
            v["points"] = json!(c.points);
        }
        v
    }
}
/// #97 CqTargetList: the directive word of this CQ is on the strategy's include list, so it is
/// answerable for the strategy (not grey, and its run's own select_row passes).
pub(crate) fn included_target(s: &Strategy, target: Option<&str>) -> bool {
    target.is_some_and(|t| s.cq_targets.include.iter().any(|w| w == t))
}
/// #97 UsStateOf (1): the US states the RTTY Roundup exchanges of these records carry, per
/// sender.
fn message_states(records: &[Value]) -> HashMap<String, String> {
    records
        .iter()
        .filter(|r| r["status"] == "decoded" && r["fields"]["type"] == "rtty")
        .filter(|r| r["fields"]["exchange"]["kind"] == "state")
        .filter_map(|r| {
            Some((
                r["fields"]["from"]["text"].as_str()?.to_owned(),
                r["fields"]["exchange"]["value"].as_str()?.to_owned(),
            ))
        })
        .collect()
}
/// CL-097-03: why a caller of my call has no rank while Calling stations are answered is off.
const NOT_ANSWERED: &str = "not answered";
/// One record's classification before the ranks: the kind or the reason there is none.
fn classify(
    s: &Strategy,
    f: &Facts,
    st: &Station,
    states: &HashMap<String, String>,
) -> (Option<Kind>, bool, String) {
    if let Some(tier) = st.ignored.get(&f.from) {
        return (
            None,
            false,
            format!("{} is ignored ({} list)", f.from, tier.name()),
        );
    }
    if st.greyed(f) && !included_target(s, f.target.as_deref()) {
        let text = not_for_me(
            f.target.as_deref().unwrap_or(""),
            st.my_continent.as_deref(),
        );
        return (None, true, text);
    }
    if f.from == st.my_call {
        return (None, false, "my own message".to_owned());
    }
    if let Some(why) = st.off_band(s) {
        return (None, false, why.to_owned());
    }
    // #97 CallerOfMyCall: a caller must pass the filters too (every line but "a CQ" and the CQ
    // target line).
    let caller = st.calls_me(f);
    let fail = |why: &str| {
        let why = if caller {
            format!("calls my call · {why}")
        } else {
            why.to_owned()
        };
        (None, false, why)
    };
    if !caller {
        if !sane_call(&f.from) {
            return (None, false, "callsign guard".to_owned());
        }
        if !st.cq_like(f, s.treat_73_as_cq) {
            return (None, false, "not a CQ".to_owned());
        }
    }
    if !st.region_holds(s, f) {
        return fail("region");
    }
    if s.min_snr_db
        .is_some_and(|m| f.snr.is_none_or(|snr| snr < m as f64))
    {
        return fail("below min SNR");
    }
    let new: Vec<&str> = s
        .new
        .iter()
        .filter(|w| st.new_needed(s, **w, s.new_per, f))
        .map(|w| w.name())
        .collect();
    if new.is_empty() {
        return fail("not new");
    }
    if let Some(why) = st.lists_fail(s, f, states, caller) {
        return fail(why);
    }
    if caller {
        // CL-097-03: with Calling stations are answered off a caller gets no rank.
        if !s.callers_first {
            return fail(NOT_ANSWERED);
        }
        return (Some(Kind::Caller), false, "calls my call".to_owned());
    }
    let on = match (s.new_per, st.band.as_deref()) {
        (NewPer::Band, Some(b)) => format!(" on {b}"),
        (NewPer::BandMode, Some(b)) => format!(" on {b} {}", st.mode),
        _ => String::new(),
    };
    (
        Some(Kind::Candidate),
        false,
        format!("new: {}{on}", new.join(", ")),
    )
}
/// WstxStrategy::ValueOrder of a ranked record, smaller first: with callers_first the callers
/// before the candidates; then the strategy's criteria in its order; then always the hidden
/// SNR (stronger first, unknown last). The exact tie follows (exact_tie).
fn value_key(s: &Strategy, v: &Verdict, st: &Station) -> Vec<(u8, f64)> {
    let group = u8::from(s.callers_first && v.kind != Some(Kind::Caller));
    let mut key = vec![(group, 0.0)];
    key.extend(s.order.iter().map(|c| st.criterion_key(s, *c, &v.facts)));
    key.push(st.criterion_key(s, Criterion::Snr, &v.facts));
    key
}
fn key_cmp(a: &[(u8, f64)], b: &[(u8, f64)]) -> std::cmp::Ordering {
    a.iter()
        .zip(b)
        .map(|(x, y)| x.0.cmp(&y.0).then(x.1.total_cmp(&y.1)))
        .find(|o| o.is_ne())
        .unwrap_or(std::cmp::Ordering::Equal)
}
/// WstxStrategy::Verdict: one per decoded standard record with a resolved sender, in display
/// order: rank (the position in ValueOrder) ascending, then the records without a rank in
/// their order.
pub(crate) fn evaluate(s: &Strategy, records: &[Value], st: &Station) -> Vec<Verdict> {
    let states = message_states(records);
    let mut list: Vec<Verdict> = records
        .iter()
        .filter_map(facts)
        .map(|f| {
            let (kind, grey, why) = classify(s, &f, st, &states);
            Verdict {
                facts: f,
                rank: None,
                grey,
                why,
                kind,
                contest: None,
            }
        })
        .collect();
    let (mut ranked, rest): (Vec<Verdict>, Vec<Verdict>) =
        list.drain(..).partition(|v| v.kind.is_some());
    let mut keyed: Vec<(Vec<(u8, f64)>, Verdict)> = ranked
        .drain(..)
        .map(|v| (value_key(s, &v, st), v))
        .collect();
    keyed.sort_by(|(a, va), (b, vb)| key_cmp(a, b).then_with(|| exact_tie(&va.facts, &vb.facts)));
    let ranked_by_list = s.order.contains(&Criterion::MostWanted);
    let mut out = Vec::with_capacity(keyed.len() + rest.len());
    for (i, (_, mut v)) in keyed.into_iter().enumerate() {
        v.rank = Some(i);
        if let Some(rank) = st.most_wanted_rank(&v.facts).filter(|_| ranked_by_list) {
            v.why = format!("{} · Most Wanted #{rank}", v.why);
        }
        out.push(v);
    }
    out.extend(rest);
    out
}
/// #97 a contest strategy's verdicts: the contest's (WstxContest::ContestVerdict, the contest's
/// rules first), then the strategy's bands and its country, US state and CQ target lists on top,
/// ranked by ContestValueOrder with the strategy's callers_first.
pub(crate) fn evaluate_contest(
    s: &Strategy,
    selection: &crate::contest::Selection,
    records: &[Value],
    st: &Station,
    log: Option<&crate::contest::Log>,
) -> Vec<Verdict> {
    let states = message_states(records);
    let off_band = st.off_band(s);
    let (mut ranked, mut rest): (Vec<Verdict>, Vec<Verdict>) =
        crate::contest::evaluate(selection, records, st, log)
            .into_iter()
            .map(|mut v| {
                if v.kind.is_some() {
                    let caller = v.kind == Some(Kind::Caller);
                    // CL-097-03: with Calling stations are answered off a caller gets no rank.
                    let fail = off_band
                        .or_else(|| st.lists_fail(s, &v.facts, &states, caller))
                        .or((caller && !s.callers_first).then_some(NOT_ANSWERED));
                    if let Some(why) = fail {
                        v.kind = None;
                        v.why = if caller && off_band.is_none() {
                            format!("calls my call · {why}")
                        } else {
                            why.to_owned()
                        };
                    }
                }
                v.rank = None;
                v
            })
            .partition(|v| v.kind.is_some());
    ranked.sort_by(|a, b| crate::contest::order_by(a, b, s.callers_first));
    for (i, v) in ranked.iter_mut().enumerate() {
        v.rank = Some(i);
    }
    rest.sort_by_key(|v| v.facts.sequence);
    ranked.extend(rest);
    ranked
}
/// The callsign guard before a run answers a candidate (WSJT-Z): at least 3 characters with a digit
/// and a letter, not a rover (/R).
pub(crate) fn sane_call(call: &str) -> bool {
    call.len() >= 3
        && call.bytes().any(|b| b.is_ascii_digit())
        && call.bytes().any(|b| b.is_ascii_uppercase())
        && !call.ends_with("/R")
}
/// WstxStrategy::MyContinent: the configured one, else the cty.dat continent of my call,
/// else that of the entity nearest to my locator.
pub(crate) fn my_continent(
    config: &Config,
    call: Option<&str>,
    locator: Option<&str>,
    dxcc: &crate::dxcc::Table,
) -> Option<String> {
    config
        .continent
        .clone()
        .or_else(|| call.and_then(|c| dxcc.continent(c)).map(str::to_owned))
        .or_else(|| {
            locator
                .and_then(maidenhead)
                .and_then(|p| dxcc.nearest_continent(p))
                .map(str::to_owned)
        })
}
/// The station band: the CAT dial band, else the operating selection band.
pub(crate) fn station_band(r: &recording::Recording) -> Option<&'static str> {
    contact_http::confirmed_dial(r)
        .and_then(logbook::band_of_hz)
        .or(r.operating_band())
}
/// The current UTC date as YYYYMMDD.
pub(crate) fn utc_date() -> u32 {
    let ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as i64);
    let (year, month, day, ..) = crate::contact::civil(ms);
    year as u32 * 10000 + month * 100 + day
}
/// The dates of a window (None: all time).
fn window_dates(window: Window) -> Option<(u32, u32)> {
    match window {
        Window::All => None,
        Window::Today => {
            let today = utc_date();
            Some((today, today))
        }
        Window::FromTo(first, last) => Some((first, last)),
    }
}
/// WstxStrategy::WorkedWindow for the station step: never builds on it.
pub(crate) fn worked_of(state: &ProfileState, window: Window) -> Option<std::sync::Arc<Worked>> {
    state.logbook.worked_latest(window_dates(window))
}
/// The same on a blocking thread (selection, evaluation route): waits until it is current.
fn worked_build(state: &ProfileState, window: Window) {
    let _ = match window_dates(window) {
        None => state.logbook.worked_set(),
        Some((first, last)) => state.logbook.worked_window(first, last),
    };
}
/// Builds the evaluation facts from the profile, the station band, the log in this window and
/// the list already read (never reads a file: the station step calls it).
pub(crate) fn station(state: &ProfileState, config: &Config, window: Window) -> Station {
    let r = &state.recording;
    let (call, locator) = contact_http::profile_facts(state);
    let band = station_band(r).map(str::to_owned);
    let mode = r.operating_mode().to_ascii_uppercase();
    let (dxcc, _) = state.logbook.dxcc();
    let mut ignored: HashMap<String, Tier> = config
        .ignore_calls
        .iter()
        .map(|c| (c.clone(), Tier::Permanent))
        .collect();
    let mut most_wanted = None;
    let mut activity = Activity::None;
    if let Some(s) = r.contact.get() {
        activity = s.status_facts().activity;
        for (c, _, _) in s.strategy.session_entries(Instant::now()) {
            ignored.insert(c, Tier::Session);
        }
        most_wanted = s.strategy.most_wanted_read();
    }
    let worked = worked_of(state, window);
    Station {
        ignored,
        my_continent: my_continent(config, call.as_deref(), locator.as_deref(), &dxcc),
        my_call: call.unwrap_or_default(),
        band,
        dxcc,
        worked,
        mode,
        most_wanted,
        activity,
        my_locator: locator,
        hears: pskr::heard_calls(r),
    }
}
/// (log revision, profile, start, end, my locator) of a built ContestLog.
type ContestKey = (u64, &'static str, i64, i64, Option<String>);
type ContestCache = Mutex<Option<(ContestKey, Arc<crate::contest::Log>)>>;
/// #63 WstxContest::ContestLog of a selection from the stored log, kept for the station step;
/// None when it is unreadable. On a blocking thread (routes, the build of a later step).
fn contest_log(
    log: &logbook::Logbook,
    cache: &ContestCache,
    s: &crate::contest::Selection,
    my_locator: Option<&str>,
) -> Option<Arc<crate::contest::Log>> {
    let (revision, list) = log.contest_qsos(s.start_ms, s.end_ms).ok()?;
    let key = (
        revision,
        s.profile.id,
        s.start_ms,
        s.end_ms,
        my_locator.map(str::to_owned),
    );
    let mut held = cache.lock().unwrap_or_else(|p| p.into_inner());
    if let Some((k, built)) = held.as_ref()
        && *k == key
    {
        return Some(built.clone());
    }
    let built = Arc::new(crate::contest::Log::of(s, my_locator, &list));
    *held = Some((key, built.clone()));
    Some(built)
}

// ------------------------------------------------------------------ alerts
/// #42 WstxStrategy::Alert: the station's alert history (memory only) with its live-job
/// cursor and the dedupe memory (kept apart from the history: Clear keeps it).
#[derive(Default)]
struct AlertLog {
    /// (live job identity, next sequence to read).
    cursor: Option<((String, String, u64), u64)>,
    entries: std::collections::VecDeque<Value>,
    next_id: u64,
    revision: u64,
    /// (call, station band) -> period start (ms) of its last alert.
    last: HashMap<(String, Option<String>), i64>,
}
impl AlertLog {
    /// Records an alert unless the same call and band alerted less than 10 minutes
    /// before this period start.
    fn record(&mut self, call: &str, band: Option<&str>, period_ms: i64, mut alert: Value) {
        let key = (call.to_owned(), band.map(str::to_owned));
        if self
            .last
            .get(&key)
            .is_some_and(|at| period_ms - at < ALERT_DEDUPE_MS && period_ms >= *at)
        {
            return;
        }
        self.last
            .retain(|_, at| period_ms - *at < ALERT_DEDUPE_MS && *at <= period_ms);
        self.last.insert(key, period_ms);
        self.next_id += 1;
        alert["id"] = json!(self.next_id);
        if self.entries.len() >= ALERT_HISTORY_MAX {
            self.entries.pop_front();
        }
        self.entries.push_back(alert);
        self.revision += 1;
    }
}

// ------------------------------------------------------------------ owner
#[derive(Default)]
struct Inner {
    loaded: bool,
    revision: u64,
    config: Option<Config>,
    error: Option<&'static str>,
    /// WstxStrategy::AutoToggle: station memory only, off at start.
    auto: bool,
    /// #97 configuration_note: the renames of the upgrade (from, to) until the next PUT.
    notes: Vec<(String, String)>,
}
/// The strategy store of one station (strategy.json beside profile.json), read on first
/// use; one leaf lock.
#[derive(Default)]
pub(crate) struct Owner {
    inner: Mutex<Inner>,
    /// #42 the session ignore list; a leaf lock, never held with `inner`.
    session: Mutex<Session>,
    /// #42 the alert history; taken before `inner` and `session`, never under them.
    alerts: Mutex<AlertLog>,
    /// Its revision, read without the lock by the alert.state event.
    alert_revision: std::sync::atomic::AtomicU64,
    /// The store revision, read without the lock by the strategy.state event.
    revision_seen: std::sync::atomic::AtomicU64,
    /// #63 the ContestLog last built, for the station step, which never builds it.
    contest_log: Arc<ContestCache>,
    contest_building: Arc<std::sync::atomic::AtomicBool>,
    /// The HaltTransmit count an Auto on has seen (a change turns Auto off).
    halts_seen: std::sync::atomic::AtomicU64,
    /// Counts each Auto on, so that the station step never turns off an Auto that was switched
    /// on after it looked at the run (auto_step).
    auto_epoch: std::sync::atomic::AtomicU64,
    /// WstxStrategy::MostWantedList: a leaf lock over the parsed list; the file is read
    /// off the station step (`most_wanted_load`), the step only clones the Arc.
    most_wanted: Mutex<MostWantedState>,
    /// Test seam: the reply of the next Download now in place of the HTTP fetch.
    pub(crate) fetch: Mutex<Option<Result<String, String>>>,
}
#[derive(Default)]
struct MostWantedState {
    loaded: bool,
    list: Option<std::sync::Arc<crate::most_wanted::List>>,
    unreadable: bool,
}
pub(crate) type Refusal = (&'static str, Option<String>);
impl Owner {
    fn lock(&self, state: &ProfileState) -> std::sync::MutexGuard<'_, Inner> {
        let mut inner = self.inner.lock().unwrap_or_else(|p| p.into_inner());
        if !inner.loaded {
            inner.loaded = true;
            let read = {
                let store = state.store.lock().unwrap_or_else(|p| p.into_inner());
                store.read_document_file(FILE_NAME, FILE_BYTES_MAX)
            };
            match read {
                Ok(None) => inner.config = Some(Config::default()),
                Ok(Some(bytes)) => {
                    let loaded = serde_json::from_slice::<Value>(&bytes).ok().and_then(|v| {
                        let ok = v.as_object().is_some_and(|o| o.len() == 4)
                            && v["profile_id"] == state.recording.profile.as_str()
                            && v["revision"].as_u64().is_some_and(|n| n <= MAX_SAFE);
                        let mut configuration = match v["schema_version"].as_u64() {
                            Some(1) => upgrade_3(&upgrade(&v["configuration"]))?,
                            Some(2) => upgrade_3(&upgrade_2(&v["configuration"])?)?,
                            Some(3) => upgrade_3(&v["configuration"])?,
                            Some(4) => with_cq_wait(&v["configuration"]),
                            _ => return None,
                        };
                        // #97: a saved name colliding with a built-in reads renamed, never
                        // dropped (every schema).
                        let notes = rename_builtin_names(&mut configuration);
                        ok.then(|| parse_config(&configuration, None).ok())
                            .flatten()
                            .map(|mut c| {
                                // active never survives a restart (WstxStrategy D2), nor
                                // does a contest (WstxContest::ContestSelection).
                                c.active = None;
                                c.contest = None;
                                (v["revision"].as_u64().unwrap_or(0), c, notes)
                            })
                    });
                    match loaded {
                        Some((revision, config, notes)) => {
                            inner.revision = revision;
                            inner.config = Some(config);
                            inner.notes = notes;
                            self.revision_seen
                                .store(revision, std::sync::atomic::Ordering::Release);
                        }
                        None => inner.error = Some("invalid_configuration"),
                    }
                }
                Err(_) => inner.error = Some("invalid_configuration"),
            }
        }
        inner
    }
    /// #63 WstxContest::ContestLog on a blocking thread: waits until it is current.
    pub(crate) fn contest_log_now(
        &self,
        state: &ProfileState,
        s: &crate::contest::Selection,
        my_locator: Option<&str>,
    ) -> Option<Arc<crate::contest::Log>> {
        contest_log(&state.logbook, &self.contest_log, s, my_locator)
    }
    /// #63 WstxContest::ContestLog for the station step: the last built one of this contest at
    /// once; one behind the log is built on its own thread for a later step.
    pub(crate) fn contest_log_latest(
        &self,
        state: &ProfileState,
        s: &crate::contest::Selection,
        my_locator: Option<&str>,
    ) -> Option<Arc<crate::contest::Log>> {
        use std::sync::atomic::Ordering;
        let same = |k: &ContestKey| {
            (k.1, k.2, k.3, k.4.as_deref()) == (s.profile.id, s.start_ms, s.end_ms, my_locator)
        };
        let (behind, last) = {
            let held = self.contest_log.lock().unwrap_or_else(|p| p.into_inner());
            match held.as_ref().filter(|(k, _)| same(k)) {
                // A busy log keeps the last one: the step never waits for it.
                Some((k, built)) => (
                    state.logbook.revision_now().is_some_and(|r| r != k.0),
                    Some(built.clone()),
                ),
                None => (true, None),
            }
        };
        if behind && !self.contest_building.swap(true, Ordering::AcqRel) {
            let (log, cache, building) = (
                state.logbook.clone(),
                self.contest_log.clone(),
                self.contest_building.clone(),
            );
            let (selection, locator) = (*s, my_locator.map(str::to_owned));
            std::thread::spawn(move || {
                contest_log(&log, &cache, &selection, locator.as_deref());
                building.store(false, Ordering::Release);
            });
        }
        last
    }
    /// Test seam: how many QSOs the ContestLog last built holds, starting no build.
    #[cfg(test)]
    pub(crate) fn contest_log_built_qsos(&self) -> Option<u64> {
        self.contest_log
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .as_ref()
            .map(|(_, l)| l.qsos)
    }
    /// The saved configuration (None while the file is unreadable).
    pub(crate) fn config(&self, state: &ProfileState) -> Option<Config> {
        self.lock(state).config.clone()
    }
    fn session(&self) -> std::sync::MutexGuard<'_, Session> {
        self.session.lock().unwrap_or_else(|p| p.into_inner())
    }
    /// The live session ignore list (call, band, seconds left).
    pub(crate) fn session_entries(&self, now: Instant) -> Vec<(String, Option<String>, u64)> {
        self.session().entries(now)
    }
    /// The station step's band observation: a band change empties the session list.
    pub(crate) fn observe_band(&self, band: Option<&str>) {
        self.session().observe_band(band);
    }
    fn alerts(&self) -> std::sync::MutexGuard<'_, AlertLog> {
        self.alerts.lock().unwrap_or_else(|p| p.into_inner())
    }
    /// The alert history revision (alert.state).
    pub(crate) fn alert_revision(&self) -> u64 {
        self.alert_revision
            .load(std::sync::atomic::Ordering::Acquire)
    }
    /// The store revision (strategy.state).
    pub(crate) fn revision(&self) -> u64 {
        self.revision_seen
            .load(std::sync::atomic::Ordering::Acquire)
    }
    /// The list already read, for the station step (no file access).
    pub(crate) fn most_wanted_read(&self) -> Option<std::sync::Arc<crate::most_wanted::List>> {
        self.most_wanted
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .list
            .clone()
    }
    /// Reads most_wanted.json once, on a blocking thread (routes; never the station step).
    pub(crate) fn most_wanted_load(&self, state: &ProfileState) {
        if self
            .most_wanted
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .loaded
        {
            return;
        }
        let read = {
            let store = state.store.lock().unwrap_or_else(|p| p.into_inner());
            store.read_document_file(
                crate::most_wanted::FILE_NAME,
                crate::most_wanted::FILE_BYTES_MAX,
            )
        };
        let parsed = match read {
            Ok(None) => Ok(None),
            Ok(Some(bytes)) => serde_json::from_slice::<Value>(&bytes)
                .ok()
                .filter(|v| {
                    v["schema_version"] == 1 && v["profile_id"] == state.recording.profile.as_str()
                })
                .and_then(|v| crate::most_wanted::List::from_value(&v["list"], v["date"].as_str()?))
                .map(Some)
                .ok_or(()),
            Err(_) => Err(()),
        };
        let mut most = self.most_wanted.lock().unwrap_or_else(|p| p.into_inner());
        if !most.loaded {
            most.loaded = true;
            most.unreadable = parsed.is_err();
            most.list = parsed.ok().flatten().map(std::sync::Arc::new);
        }
    }
    /// Stores the list; the state changes only after the file.
    fn most_wanted_store(
        &self,
        state: &ProfileState,
        list: crate::most_wanted::List,
    ) -> Result<(), Refusal> {
        let r = &state.recording;
        {
            let mut store = state
                .store
                .lock()
                .map_err(|_| ("storage_unavailable", None))?;
            store
                .write_document_file(
                    crate::most_wanted::FILE_NAME,
                    &json!({"schema_version":1,"profile_id":r.profile,"date":list.date,
                        "list":list.list_json()}),
                )
                .map_err(|_| ("storage_unavailable", None))?;
        }
        let mut most = self.most_wanted.lock().unwrap_or_else(|p| p.into_inner());
        most.loaded = true;
        most.unreadable = false;
        most.list = Some(std::sync::Arc::new(list));
        Ok(())
    }
    /// The exact envelope of the small station commands: {v, profile_id, boot_id} plus `more`.
    fn envelope_shape(body: &Value, more: &[&str]) -> Result<(), Refusal> {
        let o = body.as_object().ok_or(("invalid_request", None))?;
        let keys = ["v", "profile_id", "boot_id"];
        if let Some(k) = keys.iter().chain(more).find(|k| !o.contains_key(**k)) {
            return Err(("invalid_request", Some((*k).into())));
        }
        if o.len() != keys.len() + more.len() {
            return Err(("invalid_request", None));
        }
        if body["v"].as_u64() != Some(1) {
            return Err(if body["v"].is_u64() {
                ("unsupported_version", Some("v".into()))
            } else {
                ("invalid_request", Some("v".into()))
            });
        }
        for k in ["profile_id", "boot_id"] {
            if !body[k].as_str().is_some_and(profile::valid_uuid) {
                return Err(("invalid_request", Some(k.into())));
            }
        }
        Ok(())
    }
    fn envelope_context(state: &ProfileState, body: &Value) -> Result<(), Refusal> {
        let r = &state.recording;
        if body["profile_id"] != r.profile.as_str() {
            return Err(("wrong_profile", Some("profile_id".into())));
        }
        if body["boot_id"] != r.boot.as_str() {
            return Err(("state_conflict", Some("boot_id".into())));
        }
        Ok(())
    }
    /// POST /strategy/most-wanted/download after the route checks: one fetch, on the operator's
    /// click; a failure keeps the list and names the reason (Refusal field).
    pub(crate) fn most_wanted_download(
        &self,
        state: &ProfileState,
        body: Value,
    ) -> Result<Value, Refusal> {
        Self::envelope_shape(&body, &[])?;
        Self::envelope_context(state, &body)?;
        let text = self
            .fetch
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .take()
            .unwrap_or_else(crate::most_wanted::fetch)
            .map_err(|reason| ("download_failed", Some(reason)))?;
        let list = crate::most_wanted::List::parse(&text, &date_text(utc_date())).ok_or((
            "download_failed",
            Some("the reply is not a Most Wanted list".to_owned()),
        ))?;
        self.most_wanted_store(state, list)?;
        Ok(self.snapshot(state))
    }
    /// A HaltTransmit from any source since the last step turns Auto off (WstxStrategy::
    /// StrategyRun); the selection stays, so the marks stay (a contest keeps its operation).
    /// Pushed by strategy.state.
    pub(crate) fn halt_step(&self, state: &ProfileState) {
        use std::sync::atomic::Ordering;
        let Some(halts) = state
            .recording
            .transmit
            .get()
            .map(|t| t.service.halt_requests())
        else {
            return;
        };
        if self.halts_seen.swap(halts, Ordering::AcqRel) == halts {
            return;
        }
        let mut inner = self.lock(state);
        self.switch_auto(&mut inner, false);
    }
    /// Sets Auto; a change increments the revision (strategy.state). True when it changed.
    fn switch_auto(&self, inner: &mut Inner, on: bool) -> bool {
        if inner.auto == on || inner.revision >= MAX_SAFE {
            return false;
        }
        inner.auto = on;
        inner.revision += 1;
        self.revision_seen
            .store(inner.revision, std::sync::atomic::Ordering::Release);
        true
    }
    /// WstxStrategy::AutoToggle: whether Auto is on.
    pub(crate) fn auto(&self, state: &ProfileState) -> bool {
        self.lock(state).auto
    }
    /// The count of Auto on switches (read before the run state, for auto_step).
    pub(crate) fn auto_epoch(&self) -> u64 {
        self.auto_epoch.load(std::sync::atomic::Ordering::Acquire)
    }
    /// Turns Auto on after its run started: a HaltTransmit before it has been answered.
    pub(crate) fn auto_on(&self, state: &ProfileState) {
        use std::sync::atomic::Ordering;
        if let Some(t) = state.recording.transmit.get() {
            self.halts_seen
                .store(t.service.halt_requests(), Ordering::Release);
        }
        let mut inner = self.lock(state);
        self.auto_epoch.fetch_add(1, Ordering::AcqRel);
        self.switch_auto(&mut inner, true);
    }
    /// Turns Auto off (Auto off, a refused start, None); true when it was on.
    pub(crate) fn auto_off(&self, state: &ProfileState) -> bool {
        let mut inner = self.lock(state);
        self.switch_auto(&mut inner, false)
    }
    /// The station step after the automation step: every run end turns Auto off (the stop
    /// reason stays in the run snapshot). `epoch` is auto_epoch read before `running`.
    pub(crate) fn auto_step(&self, state: &ProfileState, epoch: u64, running: bool) {
        if running {
            return;
        }
        let mut inner = self.lock(state);
        if inner.auto && self.auto_epoch() == epoch {
            self.switch_auto(&mut inner, false);
        }
    }
    /// #42 WstxStrategy::Alert, once per station step: reads the live records past the
    /// cursor once each and records an alert for each new candidate of the active strategy.
    /// Never transmits or changes a contact or run.
    pub(crate) fn alert_step(&self, state: &ProfileState) {
        let r = &state.recording;
        let mut log = self.alerts();
        let cursor = log.cursor.clone();
        let Some((identity, mode, records)) = r.live_records_after(
            cursor.as_ref().map(|c| &c.0),
            cursor.as_ref().map_or(0, |c| c.1),
        ) else {
            return;
        };
        let same = cursor.as_ref().is_some_and(|c| c.0 == identity);
        let next = records
            .last()
            .and_then(|v| v["sequence"].as_u64())
            .map_or(if same { cursor.map_or(0, |c| c.1) } else { 0 }, |s| s + 1);
        log.cursor = Some((identity, next));
        if records.is_empty() {
            return;
        }
        let Some(config) = self.config(state) else {
            return;
        };
        let Some(chosen) = config.active_strategy() else {
            return;
        };
        let st = station(state, &config, chosen.window);
        let before = log.revision;
        // In the order decoded, not by value.
        let mut list = evaluate(chosen, &records, &st);
        list.sort_by_key(|v| v.facts.sequence);
        for v in list {
            if v.kind != Some(Kind::Candidate) {
                continue;
            }
            let Some(record) = records
                .iter()
                .find(|x| x["sequence"].as_u64() == Some(v.facts.sequence))
            else {
                continue;
            };
            let utc = record["period_start_utc"].as_str().unwrap_or("");
            let period_ms = crate::contact::parse_utc(utc).unwrap_or_else(|| {
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map_or(0, |d| d.as_millis() as i64)
            });
            let alert = json!({"id":0,"utc":utc,"call":v.facts.from,"message":record["text"],
                "rule":chosen.name,"band":st.band,"mode":mode,
                "snr_db":record["snr_db"],
                "dxcc":st.dxcc.lookup(&v.facts.from).map(|e| e.name)});
            log.record(&v.facts.from, st.band.as_deref(), period_ms, alert);
        }
        if log.revision != before {
            self.alert_revision
                .store(log.revision, std::sync::atomic::Ordering::Release);
        }
    }
    /// GET /strategy/alerts.
    pub(crate) fn alerts_snapshot(&self, state: &ProfileState) -> Value {
        let r = &state.recording;
        let log = self.alerts();
        json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"revision":log.revision,
            "alerts":log.entries})
    }
    /// POST /strategy/alerts/clear after the route checks: empties the history (the
    /// dedupe memory stays).
    pub(crate) fn clear_alerts(&self, state: &ProfileState, body: Value) -> Result<Value, Refusal> {
        let r = &state.recording;
        let keys = ["v", "profile_id", "boot_id"];
        let o = body.as_object().ok_or(("invalid_request", None))?;
        if let Some(k) = keys.iter().find(|k| !o.contains_key(**k)) {
            return Err(("invalid_request", Some((*k).into())));
        }
        if o.len() != keys.len() {
            return Err(("invalid_request", None));
        }
        if body["v"].as_u64() != Some(1) {
            return Err(if body["v"].is_u64() {
                ("unsupported_version", Some("v".into()))
            } else {
                ("invalid_request", Some("v".into()))
            });
        }
        for k in ["profile_id", "boot_id"] {
            if !body[k].as_str().is_some_and(profile::valid_uuid) {
                return Err(("invalid_request", Some(k.into())));
            }
        }
        if body["profile_id"] != r.profile.as_str() {
            return Err(("wrong_profile", Some("profile_id".into())));
        }
        if body["boot_id"] != r.boot.as_str() {
            return Err(("state_conflict", Some("boot_id".into())));
        }
        {
            let mut log = self.alerts();
            log.entries.clear();
            log.revision += 1;
            self.alert_revision
                .store(log.revision, std::sync::atomic::Ordering::Release);
        }
        Ok(self.alerts_snapshot(state))
    }
    /// StrategySnapshot.
    pub(crate) fn snapshot(&self, state: &ProfileState) -> Value {
        let r = &state.recording;
        let (call, locator) = contact_http::profile_facts(state);
        let (dxcc, _) = state.logbook.dxcc();
        let session: Vec<Value> = self
            .session_entries(Instant::now())
            .into_iter()
            .map(|(call, band, left)| json!({"call":call,"band":band,"remaining_s":left}))
            .collect();
        let (status, unreadable) = {
            let most = self.most_wanted.lock().unwrap_or_else(|p| p.into_inner());
            (most.list.as_ref().map(|l| l.status()), most.unreadable)
        };
        // Read before the strategy lock: the automation lock comes first.
        let refusal = r
            .contact
            .get()
            .and_then(|s| s.automation.strategy_refusal());
        let inner = self.lock(state);
        let mine = inner
            .config
            .as_ref()
            .and_then(|c| my_continent(c, call.as_deref(), locator.as_deref(), &dxcc));
        json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"revision":inner.revision,
            "configuration":inner.config.as_ref().map(Config::json),
            "configuration_error":inner.error,"my_continent":mine,
            "auto":inner.auto,"strategy_refusal":refusal,
            "derived_continent":call.as_deref().and_then(|c| dxcc.continent(c)),
            "session_ignore":session,"most_wanted":status,
            "builtin_strategies":builtins().iter().chain(contest_builtins()).map(|b| {
                let mut v = b.json();
                v["builtin"] = json!(true);
                v
            }).collect::<Vec<_>>(),
            "configuration_note":inner.notes.iter()
                .map(|(from, to)| json!({"from":from,"to":to})).collect::<Vec<_>>(),
            "most_wanted_unreadable":unreadable,
            "most_wanted_attribution":crate::most_wanted::ATTRIBUTION})
    }
    /// POST /strategy/ignore after the route checks: adds a call to (or removes it from)
    /// the session list; no revision changes.
    pub(crate) fn ignore(&self, state: &ProfileState, body: Value) -> Result<Value, Refusal> {
        let r = &state.recording;
        Self::envelope_shape(&body, &["call", "ignore"])?;
        let call =
            word(&body["call"], "call", 13, b"/").map_err(|f| ("invalid_request", Some(f)))?;
        let on = body["ignore"]
            .as_bool()
            .ok_or(("invalid_request", Some("ignore".into())))?;
        Self::envelope_context(state, &body)?;
        let minutes = self
            .config(state)
            .map_or(SESSION_IGNORE_MINUTES, |c| c.session_ignore_minutes);
        let band = station_band(r);
        {
            let mut session = self.session();
            session.observe_band(band);
            if on {
                session.add(&call, band, minutes, Instant::now());
            } else {
                session.remove(&call);
            }
        }
        Ok(self.snapshot(state))
    }
    /// POST /strategy/auto {v, profile_id, boot_id, auto, automation_confirmed?} after the
    /// route checks (WstxStrategy::AutoToggle): the requested value. auto true needs a
    /// selection (409 not_configured strategy) and, for a contest whose AutomationClause is
    /// forbidden, automation_confirmed true (400 invalid_request automation_confirmed).
    pub(crate) fn auto_request(&self, state: &ProfileState, body: &Value) -> Result<bool, Refusal> {
        let o = body.as_object().ok_or(("invalid_request", None))?;
        let confirmed = o.contains_key("automation_confirmed");
        let more: &[&str] = if confirmed {
            &["auto", "automation_confirmed"]
        } else {
            &["auto"]
        };
        Self::envelope_shape(body, more)?;
        let on = body["auto"]
            .as_bool()
            .ok_or(("invalid_request", Some("auto".into())))?;
        let confirmation = match o.get("automation_confirmed") {
            None => false,
            Some(c) => c
                .as_bool()
                .ok_or(("invalid_request", Some("automation_confirmed".to_owned())))?,
        };
        Self::envelope_context(state, body)?;
        if !on {
            return Ok(false);
        }
        let config = self
            .config(state)
            .filter(Config::selected)
            .ok_or(("not_configured", Some("strategy".into())))?;
        // WstxContest::AutomationClause: a warning the operator must confirm, never a block.
        if config.forbidden_contest() && !confirmation {
            return Err(("invalid_request", Some("automation_confirmed".into())));
        }
        Ok(true)
    }
    /// PUT /strategy after the route checks: the snapshot and whether active changed (the
    /// route then ends the run and, while Auto is on, starts the new one,
    /// WstxStrategy::StrategyRun).
    pub(crate) fn put(&self, state: &ProfileState, body: Value) -> Result<(Value, bool), Refusal> {
        let r = &state.recording;
        let keys = [
            "v",
            "profile_id",
            "boot_id",
            "expected_revision",
            "configuration",
        ];
        let o = body.as_object().ok_or(("invalid_request", None))?;
        if let Some(k) = keys.iter().find(|k| !o.contains_key(**k)) {
            return Err(("invalid_request", Some((*k).into())));
        }
        if o.len() != keys.len() {
            return Err(("invalid_request", None));
        }
        if body["v"].as_u64() != Some(1) {
            return Err(if body["v"].is_u64() {
                ("unsupported_version", Some("v".into()))
            } else {
                ("invalid_request", Some("v".into()))
            });
        }
        for k in ["profile_id", "boot_id"] {
            if !body[k].as_str().is_some_and(profile::valid_uuid) {
                return Err(("invalid_request", Some(k.into())));
            }
        }
        let expected = body["expected_revision"]
            .as_u64()
            .filter(|n| *n <= MAX_SAFE)
            .ok_or(("invalid_request", Some("expected_revision".into())))?;
        let (table, _) = state.logbook.dxcc();
        let config = parse_config(&body["configuration"], Some(&table))
            .map_err(|f| ("invalid_request", Some(f)))?;
        if body["profile_id"] != r.profile.as_str() {
            return Err(("wrong_profile", Some("profile_id".into())));
        }
        if body["boot_id"] != r.boot.as_str() {
            return Err(("state_conflict", Some("boot_id".into())));
        }
        let mut inner = self.lock(state);
        if expected != inner.revision {
            return Err(("stale_revision", Some("expected_revision".into())));
        }
        let before = inner.config.as_ref().and_then(|c| c.active.clone());
        let contest_before = inner.config.as_ref().and_then(|c| c.contest);
        let changed = config.active != before || config.contest != contest_before;
        if inner.revision >= MAX_SAFE {
            return Err(("counter_exhausted", None));
        }
        let revision = inner.revision + 1;
        // active is never read back: the file holds none (WstxStrategy D2).
        let mut stored = config.json();
        stored["active"] = Value::Null;
        if let Some(o) = stored.as_object_mut() {
            o.remove("contest");
        }
        let document = json!({"schema_version":4,"profile_id":r.profile,"revision":revision,
            "configuration":stored});
        {
            let mut store = state
                .store
                .lock()
                .map_err(|_| ("storage_unavailable", None))?;
            store
                .write_document_file(FILE_NAME, &document)
                .map_err(|_| ("storage_unavailable", None))?;
        }
        inner.revision = revision;
        inner.error = None;
        inner.notes.clear();
        // WstxStrategy::AutoToggle: selecting None turns Auto off (in this revision).
        if !config.selected() {
            inner.auto = false;
        }
        inner.config = Some(config);
        self.revision_seen
            .store(revision, std::sync::atomic::Ordering::Release);
        drop(inner);
        // A selection is a new start: a Halt before it has been answered.
        if changed && let Some(t) = r.transmit.get() {
            self.halts_seen.store(
                t.service.halt_requests(),
                std::sync::atomic::Ordering::Release,
            );
        }
        Ok((self.snapshot(state), changed))
    }
    /// POST /strategy/evaluate after the route checks.
    pub(crate) fn evaluate(&self, state: &ProfileState, body: Value) -> Result<Value, Refusal> {
        let r = &state.recording;
        let keys = [
            "v",
            "profile_id",
            "boot_id",
            "source_id",
            "job_id",
            "generation",
            "first_sequence",
            "next_sequence",
            "strategy",
            "explain",
        ];
        let o = body.as_object().ok_or(("invalid_request", None))?;
        if let Some(k) = keys.iter().find(|k| !o.contains_key(**k)) {
            return Err(("invalid_request", Some((*k).into())));
        }
        if o.len() != keys.len() {
            return Err(("invalid_request", None));
        }
        if body["v"].as_u64() != Some(1) {
            return Err(if body["v"].is_u64() {
                ("unsupported_version", Some("v".into()))
            } else {
                ("invalid_request", Some("v".into()))
            });
        }
        for k in ["profile_id", "boot_id", "source_id", "job_id"] {
            if !body[k].as_str().is_some_and(profile::valid_uuid) {
                return Err(("invalid_request", Some(k.into())));
            }
        }
        let safe = |k: &str| {
            body[k]
                .as_u64()
                .filter(|n| *n <= MAX_SAFE)
                .ok_or(("invalid_request", Some(k.to_owned())))
        };
        let (generation, first, next) = (
            safe("generation")?,
            safe("first_sequence")?,
            safe("next_sequence")?,
        );
        if next < first || next - first > EVALUATE_MAX {
            return Err(("invalid_request", Some("next_sequence".into())));
        }
        let explain = body["explain"]
            .as_bool()
            .ok_or(("invalid_request", Some("explain".into())))?;
        let draft = match &body["strategy"] {
            Value::Null => None,
            s => {
                let (table, _) = state.logbook.dxcc();
                Some(
                    strategy(s, "strategy", Some(&table))
                        .map_err(|f| ("invalid_request", Some(f)))?,
                )
            }
        };
        if body["profile_id"] != r.profile.as_str() {
            return Err(("wrong_profile", Some("profile_id".into())));
        }
        if body["boot_id"] != r.boot.as_str() {
            return Err(("state_conflict", Some("boot_id".into())));
        }
        let config = self
            .config(state)
            .ok_or(("not_configured", Some("configuration".into())))?;
        self.most_wanted_load(state);
        // WstxContest::ContestVerdict: a draft is a preview (a contest draft over the contest in
        // force, or its contest's period from now); else the active strategy.
        let chosen = match draft {
            Some(s) => s,
            None => config
                .active_strategy()
                .cloned()
                .ok_or(("not_configured", Some("strategy".into())))?,
        };
        let contest = match (chosen.class, chosen.profile()) {
            (Class::Contest, Some(p)) => {
                Some(config.contest.filter(|c| c.profile.id == p.id).unwrap_or(
                    crate::contest::Selection {
                        profile: p,
                        start_ms: 0,
                        end_ms: i64::MAX,
                    },
                ))
            }
            _ => None,
        };
        let identity = (
            body["source_id"].as_str().unwrap_or("").to_owned(),
            body["job_id"].as_str().unwrap_or("").to_owned(),
            generation,
        );
        let records: Vec<Value> = match r.live_records_after(Some(&identity), first) {
            Some((current, _, records)) if current == identity => records
                .into_iter()
                .filter(|v| {
                    v["sequence"]
                        .as_u64()
                        .is_some_and(|s| s >= first && s < next)
                })
                .collect(),
            _ => return Err(("stale_request", Some("job_id".into()))),
        };
        if let Some(selection) = contest {
            let st = station(state, &config, Window::All);
            let log = self.contest_log_now(state, &selection, st.my_locator.as_deref());
            let verdicts: Vec<Value> =
                evaluate_contest(&chosen, &selection, &records, &st, log.as_deref())
                    .iter()
                    .filter(|v| {
                        explain || v.rank.is_some() || v.grey || v.contest.is_some_and(|c| c.dupe)
                    })
                    .map(|v| v.json(explain))
                    .collect();
            return Ok(
                json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"strategy":selection.profile.name,
                "my_continent":st.my_continent,"verdicts":verdicts,
                "contest":log.as_ref().map(|l| l.summary(&selection))}),
            );
        };
        worked_build(state, chosen.window);
        let st = station(state, &config, chosen.window);
        // In display order: by rank, then the rest.
        let verdicts: Vec<Value> = evaluate(&chosen, &records, &st)
            .iter()
            .filter(|v| explain || v.rank.is_some() || v.grey)
            .map(|v| v.json(explain))
            .collect();
        Ok(
            json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"strategy":chosen.name,
            "my_continent":st.my_continent,"verdicts":verdicts}),
        )
    }
}

fn refusal(code: &str, field: Option<&str>) -> Response {
    let status = match code {
        "unauthorized" => StatusCode::UNAUTHORIZED,
        "forbidden_origin" | "wrong_profile" => StatusCode::FORBIDDEN,
        "not_found" => StatusCode::NOT_FOUND,
        "request_too_large" => StatusCode::PAYLOAD_TOO_LARGE,
        "unsupported_media_type" => StatusCode::UNSUPPORTED_MEDIA_TYPE,
        "invalid_request" | "unsupported_version" => StatusCode::BAD_REQUEST,
        "storage_unavailable" => StatusCode::SERVICE_UNAVAILABLE,
        _ => StatusCode::CONFLICT,
    };
    profile_error(status, code, field)
}
fn station_of(r: &recording::Recording) -> Option<Arc<contact_http::Station>> {
    r.contact.get().cloned()
}
pub async fn snapshot(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, false).await {
        Ok(r) => r,
        Err(e) => return refusal(e, None),
    };
    if let Err(e) = empty(query, body) {
        return refusal(e, None);
    }
    let (Some(station), Some(state)) = (station_of(&r), app.profile.clone()) else {
        return refusal("not_found", None);
    };
    match tokio::task::spawn_blocking(move || {
        station.strategy.most_wanted_load(&state);
        station.strategy.snapshot(&state)
    })
    .await
    {
        Ok(v) => Json(v).into_response(),
        Err(_) => refusal("storage_unavailable", None),
    }
}
async fn body_of(
    app: &App,
    headers: &HeaderMap,
    query: Option<String>,
    body: Result<Bytes, BytesRejection>,
) -> Result<(Arc<contact_http::Station>, Arc<ProfileState>, Value), Box<Response>> {
    let r = authorize(app, headers, true)
        .await
        .map_err(|e| Box::new(refusal(e, None)))?;
    if query.is_some() {
        return Err(Box::new(refusal("invalid_request", None)));
    }
    if !json_media_type(headers) || headers.contains_key(header::CONTENT_ENCODING) {
        return Err(Box::new(refusal("unsupported_media_type", None)));
    }
    let bytes = match body {
        Ok(b) if b.len() <= BODY_MAX => b,
        _ => return Err(Box::new(refusal("request_too_large", None))),
    };
    let body: Value =
        serde_json::from_slice(&bytes).map_err(|_| Box::new(refusal("invalid_request", None)))?;
    match (station_of(&r), app.profile.clone()) {
        (Some(s), Some(p)) => Ok((s, p, body)),
        _ => Err(Box::new(refusal("not_found", None))),
    }
}
/// WstxStrategy::StrategyRun start and end, on a blocking thread with no strategy lock held:
/// ends any run and, when `start` and a selection exist, starts the selection's run through
/// the same internal path as AutomationCommand start (the request's grant; a browser's
/// selection or Auto on ends a Tx watchdog stop, WatchdogFromOperator). A start that is
/// refused turns Auto off (strategy_refusal names why). True when a run started.
fn start_selection(
    station: &contact_http::Station,
    state: &ProfileState,
    access: Option<(authorization::Access, String)>,
    start: bool,
) -> bool {
    let config = station.strategy.config(state);
    let start = start && config.as_ref().is_some_and(Config::selected);
    if start {
        station.strategy.most_wanted_load(state);
        if let Some(s) = config.as_ref().and_then(Config::active_strategy) {
            worked_build(state, s.window);
        }
        // #63 the run's first step finds the contest's log.
        if let Some(c) = config.as_ref().and_then(Config::automatic_contest) {
            let (_, locator) = contact_http::profile_facts(state);
            station
                .strategy
                .contest_log_now(state, &c, locator.as_deref());
        }
    }
    // Taken after the strategy lock is free: the automation lock comes first.
    let started = station.automation.selected(station, state, access, start);
    if started {
        station.strategy.auto_on(state);
    } else {
        station.strategy.auto_off(state);
    }
    started
}
pub async fn put(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let (station, state, body) = match body_of(&app, &headers, query, body).await {
        Ok(v) => v,
        Err(e) => return *e,
    };
    // WstxStrategy::StrategyRun: the request's grant starts the run (the boundary guard has
    // refused an MCP principal: this request is the browser's, #58).
    let access = authorization_http::operating_access_async(&headers, &app)
        .await
        .ok()
        .flatten()
        .zip(authorization_http::transport_token(&headers, &app));
    let reply = tokio::task::spawn_blocking(move || {
        let (snapshot, changed) = station.strategy.put(&state, body)?;
        if !changed {
            return Ok::<Value, Refusal>(snapshot);
        }
        // A changed selection ends any run; while Auto is on the new one starts, except a
        // contest whose clause is forbidden: Auto goes off, the confirmation goes only with
        // Auto on (WstxStrategy::AutoToggle).
        let forbidden = station
            .strategy
            .config(&state)
            .is_some_and(|c| c.forbidden_contest());
        let auto = station.strategy.auto(&state) && !forbidden;
        start_selection(&station, &state, access, auto);
        Ok::<Value, Refusal>(station.strategy.snapshot(&state))
    })
    .await;
    match reply {
        Ok(Ok(snapshot)) => Json(snapshot).into_response(),
        Ok(Err((code, field))) => refusal(code, field.as_deref()),
        Err(_) => refusal("storage_unavailable", None),
    }
}
/// POST /strategy/auto (WstxStrategy::AutoToggle): the browser only (the boundary guard has
/// refused an MCP principal, #58). Auto on ends any running pounce or MCP run and starts the
/// selection's run; Auto off ends the run at once. Returns the GET /strategy snapshot.
pub async fn auto_route(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let (station, state, body) = match body_of(&app, &headers, query, body).await {
        Ok(v) => v,
        Err(e) => return *e,
    };
    let access = authorization_http::operating_access_async(&headers, &app)
        .await
        .ok()
        .flatten()
        .zip(authorization_http::transport_token(&headers, &app));
    let reply = tokio::task::spawn_blocking(move || {
        let on = station.strategy.auto_request(&state, &body)?;
        if on {
            // Already on with its run going: nothing to start again.
            if !(station.strategy.auto(&state) && station.automation.strategy_running()) {
                start_selection(&station, &state, access, true);
            }
        } else {
            station.strategy.auto_off(&state);
            station.automation.end_strategy_run(&station, &state);
        }
        Ok::<Value, Refusal>(station.strategy.snapshot(&state))
    })
    .await;
    match reply {
        Ok(Ok(snapshot)) => Json(snapshot).into_response(),
        Ok(Err((code, field))) => refusal(code, field.as_deref()),
        Err(_) => refusal("storage_unavailable", None),
    }
}
pub async fn ignore_route(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let (station, state, body) = match body_of(&app, &headers, query, body).await {
        Ok(v) => v,
        Err(e) => return *e,
    };
    match tokio::task::spawn_blocking(move || station.strategy.ignore(&state, body)).await {
        Ok(Ok(v)) => Json(v).into_response(),
        Ok(Err((code, field))) => refusal(code, field.as_deref()),
        Err(_) => refusal("storage_unavailable", None),
    }
}
pub async fn alerts_route(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, false).await {
        Ok(r) => r,
        Err(e) => return refusal(e, None),
    };
    if let Err(e) = empty(query, body) {
        return refusal(e, None);
    }
    let (Some(station), Some(state)) = (station_of(&r), app.profile.clone()) else {
        return refusal("not_found", None);
    };
    Json(station.strategy.alerts_snapshot(&state)).into_response()
}
pub async fn clear_alerts_route(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let (station, state, body) = match body_of(&app, &headers, query, body).await {
        Ok(v) => v,
        Err(e) => return *e,
    };
    match station.strategy.clear_alerts(&state, body) {
        Ok(v) => Json(v).into_response(),
        Err((code, field)) => refusal(code, field.as_deref()),
    }
}
/// GET /strategy/contests (WstxContest::ContestHttp): the profiles with their current or
/// next period, read at (re)connect and when the period prompt opens.
pub async fn contests_route(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, false).await {
        Ok(r) => r,
        Err(e) => return refusal(e, None),
    };
    if let Err(e) = empty(query, body) {
        return refusal(e, None);
    }
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as i64);
    Json(json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,
        "profiles":crate::contest::profiles_json(now)}))
    .into_response()
}
/// POST /strategy/most-wanted/download.
pub async fn most_wanted_download_route(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let (station, state, body) = match body_of(&app, &headers, query, body).await {
        Ok(v) => v,
        Err(e) => return *e,
    };
    match tokio::task::spawn_blocking(move || station.strategy.most_wanted_download(&state, body))
        .await
    {
        Ok(Ok(v)) => Json(v).into_response(),
        Ok(Err(("download_failed", reason))) => (
            StatusCode::BAD_GATEWAY,
            Json(json!({"error":{"code":"download_failed","reason":reason}})),
        )
            .into_response(),
        Ok(Err((code, field))) => refusal(code, field.as_deref()),
        Err(_) => refusal("storage_unavailable", None),
    }
}
/// strategy.state: announces a new store revision (a save, a selection, an Auto change, a
/// HALT's or a run end's Auto off); the browser then reads GET /strategy.
pub(crate) fn state_event(r: &recording::Recording, revision: u64) -> String {
    json!({"v":1,"type":"strategy.state","data":{"profile_id":r.profile,"boot_id":r.boot,
        "strategy_revision":revision}})
    .to_string()
}
/// alert.state: announces a new alert or a clear; the browser then reads GET
/// /strategy/alerts.
pub(crate) fn alert_event(r: &recording::Recording, revision: u64) -> String {
    json!({"v":1,"type":"alert.state","data":{"profile_id":r.profile,"boot_id":r.boot,
        "alert_revision":revision}})
    .to_string()
}
pub async fn evaluate_route(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let (station, state, body) = match body_of(&app, &headers, query, body).await {
        Ok(v) => v,
        Err(e) => return *e,
    };
    match tokio::task::spawn_blocking(move || station.strategy.evaluate(&state, body)).await {
        Ok(Ok(v)) => Json(v).into_response(),
        Ok(Err((code, field))) => refusal(code, field.as_deref()),
        Err(_) => refusal("storage_unavailable", None),
    }
}
