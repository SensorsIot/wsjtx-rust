#![forbid(unsafe_code)]
//! WstxStrategy (#39): named operating strategies, the directed-CQ rule and their one
//! evaluator. The browser's Highlight view and the station's Auto runs
//! (WstxMcp::OperatingAutomation with a strategy) both use these verdicts; the browser
//! never evaluates a strategy itself. Routes: GET /strategy (StrategySnapshot), PUT
//! /strategy (configuration), POST /strategy/evaluate (verdicts of retained live rows).
use crate::*;
use axum::extract::RawQuery;
use recording_http::authorize;
use selection_http::empty;
use std::collections::HashMap;

#[cfg(test)]
#[path = "strategy_tests.rs"]
mod tests;

pub const FILE_NAME: &str = "strategy.json";
pub const BODY_MAX: usize = 32_768;
pub const STRATEGIES_MAX: usize = 16;
pub const RULES_MAX: usize = 8;
pub const CONDITIONS_MAX: usize = 12;
pub const LIST_MAX: usize = 32;
pub const EVALUATE_MAX: u64 = 2048;
const FILE_BYTES_MAX: u64 = 262_144;
const MAX_SAFE: u64 = 9_007_199_254_740_991;
pub use crate::dxcc::CONTINENTS;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Message {
    Cq,
    DirectedCq,
    ToMe,
    Signoff,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Scope {
    Ever,
    Band,
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Range {
    pub min: Option<f64>,
    pub max: Option<f64>,
}
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum Cond {
    Message(Message),
    NewCall(Scope),
    NewGrid(Scope),
    Continent(Vec<String>),
    Distance(Range),
    Azimuth(Range),
    Snr(Range),
    Dt(Range),
    Audio(Range),
    Call(Vec<String>),
    CqTarget(Vec<String>),
    Band(Vec<String>),
    /// #42 WstxStrategy::NewEntity.
    NewEntity(crate::dxcc::Category, Scope),
}
use crate::dxcc::Category;
/// The wire kinds of the #42 entity New conditions.
const ENTITY_KINDS: [(&str, Category, &str); 4] = [
    ("new_dxcc", Category::Dxcc, "DXCC"),
    ("new_continent", Category::Continent, "continent"),
    ("new_cq_zone", Category::CqZone, "CQ zone"),
    ("new_itu_zone", Category::ItuZone, "ITU zone"),
];
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Condition {
    pub cond: Cond,
    pub negate: bool,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Sort {
    Strongest,
    Weakest,
    Furthest,
    Newest,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Role {
    Call,
    Cq,
    Alternate,
}
/// WstxStrategy::Strategy.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Strategy {
    pub name: String,
    pub rules: Vec<Vec<Condition>>,
    pub sort: Sort,
    pub treat_73_as_cq: bool,
    pub apply_to_callers: bool,
    pub skip_after: u64,
    pub role: Role,
    pub switch_after: u64,
}
/// WstxStrategy::StrategyConfiguration.
#[derive(Clone, Debug, PartialEq, Default)]
pub(crate) struct Config {
    pub continent: Option<String>,
    pub active: Option<String>,
    pub highlight: bool,
    pub strategies: Vec<Strategy>,
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
fn list(
    v: &Value,
    field: &str,
    item: impl Fn(&Value, &str) -> Result<String, Field>,
) -> Result<Vec<String>, Field> {
    let a = v.as_array().ok_or(bad(field))?;
    if a.is_empty() || a.len() > LIST_MAX {
        return Err(bad(field));
    }
    let mut out: Vec<String> = Vec::new();
    for (i, x) in a.iter().enumerate() {
        let x = item(x, &format!("{field}[{i}]"))?;
        if out.contains(&x) {
            return Err(bad(format!("{field}[{i}]")));
        }
        out.push(x);
    }
    Ok(out)
}
fn bounded(v: &Value, field: &str, lo: u64, hi: u64) -> Result<u64, Field> {
    v.as_u64()
        .filter(|n| (lo..=hi).contains(n))
        .ok_or(bad(field))
}
fn range(v: &Value, field: &str, lo: f64, hi: f64, wraps: bool) -> Result<Range, Field> {
    let num = |k: &str| match &v[k] {
        Value::Null => Ok(None),
        n => n
            .as_f64()
            .filter(|n| *n >= lo && *n <= hi)
            .map(Some)
            .ok_or(bad(format!("{field}.{k}"))),
    };
    let (min, max) = (num("min")?, num("max")?);
    if min.is_none() && max.is_none() {
        return Err(bad(format!("{field}.min")));
    }
    if !wraps && min.zip(max).is_some_and(|(a, b)| a > b) {
        return Err(bad(format!("{field}.max")));
    }
    Ok(Range { min, max })
}
fn condition(v: &Value, field: &str) -> Result<Condition, Field> {
    let kind = v["kind"].as_str().ok_or(bad(format!("{field}.kind")))?;
    let negate = v["negate"]
        .as_bool()
        .ok_or(bad(format!("{field}.negate")))?;
    let keys: &[&str] = match kind {
        "message" | "new_call" | "new_grid" | "new_dxcc" | "new_continent" | "new_cq_zone"
        | "new_itu_zone" => &["kind", "negate", "value"],
        "continent" | "call" | "cq_target" | "band" => &["kind", "negate", "values"],
        "distance_km" | "azimuth_deg" | "snr_db" | "dt_s" | "audio_hz" => {
            &["kind", "negate", "min", "max"]
        }
        _ => return Err(bad(format!("{field}.kind"))),
    };
    exact(v, keys, field)?;
    let value = format!("{field}.value");
    let values = format!("{field}.values");
    let scope = |v: &Value| match v.as_str() {
        Some("ever") => Ok(Scope::Ever),
        Some("band") => Ok(Scope::Band),
        _ => Err(bad(value.clone())),
    };
    let cond = match kind {
        "message" => Cond::Message(match v["value"].as_str() {
            Some("cq") => Message::Cq,
            Some("directed_cq") => Message::DirectedCq,
            Some("to_me") => Message::ToMe,
            Some("signoff") => Message::Signoff,
            _ => return Err(bad(value)),
        }),
        "new_call" => Cond::NewCall(scope(&v["value"])?),
        "new_grid" => Cond::NewGrid(scope(&v["value"])?),
        "new_dxcc" | "new_continent" | "new_cq_zone" | "new_itu_zone" => {
            let category = ENTITY_KINDS
                .iter()
                .find(|k| k.0 == kind)
                .map(|k| k.1)
                .ok_or(bad(format!("{field}.kind")))?;
            Cond::NewEntity(category, scope(&v["value"])?)
        }
        "continent" => Cond::Continent(list(&v["values"], &values, |x, f| {
            x.as_str()
                .filter(|c| CONTINENTS.contains(c))
                .map(str::to_owned)
                .ok_or(bad(f))
        })?),
        "call" => Cond::Call(list(&v["values"], &values, |x, f| word(x, f, 13, b"/"))?),
        "cq_target" => Cond::CqTarget(list(&v["values"], &values, |x, f| word(x, f, 4, b""))?),
        "band" => Cond::Band(list(&v["values"], &values, |x, f| {
            x.as_str()
                .filter(|b| logbook::valid_band(b))
                .map(str::to_ascii_lowercase)
                .ok_or(bad(f))
        })?),
        "distance_km" => Cond::Distance(range(v, field, 0.0, 20_038.0, false)?),
        "azimuth_deg" => Cond::Azimuth(range(v, field, 0.0, 360.0, true)?),
        "snr_db" => Cond::Snr(range(v, field, -50.0, 49.0, false)?),
        "dt_s" => Cond::Dt(range(v, field, -7.5, 7.5, false)?),
        _ => Cond::Audio(range(v, field, 0.0, 3500.0, false)?),
    };
    Ok(Condition { cond, negate })
}
fn strategy(v: &Value, field: &str) -> Result<Strategy, Field> {
    exact(
        v,
        &[
            "name",
            "rules",
            "sort",
            "treat_73_as_cq",
            "apply_to_callers",
            "skip_after",
            "auto_role",
            "switch_after",
        ],
        field,
    )?;
    let name = v["name"]
        .as_str()
        .filter(|n| {
            (1..=32).contains(&n.len())
                && n.trim() == *n
                && n.bytes().all(|b| (0x20..0x7f).contains(&b))
        })
        .ok_or(bad(format!("{field}.name")))?
        .to_owned();
    let rules = v["rules"]
        .as_array()
        .filter(|r| (1..=RULES_MAX).contains(&r.len()))
        .ok_or(bad(format!("{field}.rules")))?;
    let mut parsed = Vec::new();
    for (i, rule) in rules.iter().enumerate() {
        let rf = format!("{field}.rules[{i}]");
        exact(rule, &["conditions"], &rf)?;
        let list = rule["conditions"]
            .as_array()
            .filter(|c| c.len() <= CONDITIONS_MAX)
            .ok_or(bad(format!("{rf}.conditions")))?;
        let mut conditions = Vec::new();
        for (j, c) in list.iter().enumerate() {
            conditions.push(condition(c, &format!("{rf}.conditions[{j}]"))?);
        }
        parsed.push(conditions);
    }
    let flag = |k: &str| v[k].as_bool().ok_or(bad(format!("{field}.{k}")));
    Ok(Strategy {
        name,
        rules: parsed,
        sort: match v["sort"].as_str() {
            Some("strongest") => Sort::Strongest,
            Some("weakest") => Sort::Weakest,
            Some("furthest") => Sort::Furthest,
            Some("newest") => Sort::Newest,
            _ => return Err(bad(format!("{field}.sort"))),
        },
        treat_73_as_cq: flag("treat_73_as_cq")?,
        apply_to_callers: flag("apply_to_callers")?,
        skip_after: bounded(&v["skip_after"], &format!("{field}.skip_after"), 1, 20)?,
        role: match v["auto_role"].as_str() {
            Some("call") => Role::Call,
            Some("cq") => Role::Cq,
            Some("alternate") => Role::Alternate,
            _ => return Err(bad(format!("{field}.auto_role"))),
        },
        switch_after: bounded(&v["switch_after"], &format!("{field}.switch_after"), 1, 20)?,
    })
}
/// Exact StrategyConfiguration parsing (field names a refused value).
pub(crate) fn parse_config(v: &Value) -> Result<Config, Field> {
    exact(
        v,
        &["continent", "active", "highlight", "strategies"],
        "configuration",
    )?;
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
        let s = strategy(s, &format!("strategies[{i}]"))?;
        if strategies
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
                .filter(|a| strategies.iter().any(|s| s.name == *a))
                .ok_or(bad("active"))?
                .to_owned(),
        ),
    };
    let highlight = v["highlight"].as_bool().ok_or(bad("highlight"))?;
    Ok(Config {
        continent,
        active,
        highlight,
        strategies,
    })
}
fn range_json(r: &Range) -> (Value, Value) {
    (json!(r.min), json!(r.max))
}
impl Condition {
    fn json(&self) -> Value {
        let (kind, rest) = match &self.cond {
            Cond::Message(m) => (
                "message",
                json!({"value":match m {Message::Cq=>"cq",Message::DirectedCq=>"directed_cq",Message::ToMe=>"to_me",Message::Signoff=>"signoff"}}),
            ),
            Cond::NewCall(s) | Cond::NewGrid(s) => (
                if matches!(self.cond, Cond::NewCall(_)) {
                    "new_call"
                } else {
                    "new_grid"
                },
                json!({"value":if *s==Scope::Ever {"ever"} else {"band"}}),
            ),
            Cond::NewEntity(c, s) => (
                ENTITY_KINDS
                    .iter()
                    .find(|k| k.1 == *c)
                    .map_or("new_dxcc", |k| k.0),
                json!({"value":if *s==Scope::Ever {"ever"} else {"band"}}),
            ),
            Cond::Continent(l) => ("continent", json!({ "values": l })),
            Cond::Call(l) => ("call", json!({ "values": l })),
            Cond::CqTarget(l) => ("cq_target", json!({ "values": l })),
            Cond::Band(l) => ("band", json!({ "values": l })),
            Cond::Distance(r) | Cond::Azimuth(r) | Cond::Snr(r) | Cond::Dt(r) | Cond::Audio(r) => {
                let kind = match self.cond {
                    Cond::Distance(_) => "distance_km",
                    Cond::Azimuth(_) => "azimuth_deg",
                    Cond::Snr(_) => "snr_db",
                    Cond::Dt(_) => "dt_s",
                    _ => "audio_hz",
                };
                let (min, max) = range_json(r);
                (kind, json!({"min":min,"max":max}))
            }
        };
        let mut v = json!({"kind":kind,"negate":self.negate});
        if let (Some(o), Some(r)) = (v.as_object_mut(), rest.as_object()) {
            o.extend(r.clone());
        }
        v
    }
    /// A short operator label ("not new call (ever)", "SNR -10..", ...).
    fn label(&self) -> String {
        let span = |r: &Range, unit: &str| {
            format!(
                "{}..{}{unit}",
                r.min.map_or(String::new(), |n| n.to_string()),
                r.max.map_or(String::new(), |n| n.to_string())
            )
        };
        let text = match &self.cond {
            Cond::Message(m) => format!(
                "message {}",
                match m {
                    Message::Cq => "CQ",
                    Message::DirectedCq => "directed CQ",
                    Message::ToMe => "to me",
                    Message::Signoff => "RR73/73",
                }
            ),
            Cond::NewCall(s) => format!(
                "new call{}",
                if *s == Scope::Band { " on band" } else { "" }
            ),
            Cond::NewGrid(s) => format!(
                "new grid{}",
                if *s == Scope::Band { " on band" } else { "" }
            ),
            Cond::NewEntity(c, s) => format!(
                "new {}{}",
                ENTITY_KINDS
                    .iter()
                    .find(|k| k.1 == *c)
                    .map_or("DXCC", |k| k.2),
                if *s == Scope::Band { " on band" } else { "" }
            ),
            Cond::Continent(l) => format!("continent {}", l.join("/")),
            Cond::Call(l) => format!("call {}", l.join("/")),
            Cond::CqTarget(l) => format!("CQ target {}", l.join("/")),
            Cond::Band(l) => format!("band {}", l.join("/")),
            Cond::Distance(r) => format!("distance {}", span(r, " km")),
            Cond::Azimuth(r) => format!("azimuth {}", span(r, " deg")),
            Cond::Snr(r) => format!("SNR {}", span(r, " dB")),
            Cond::Dt(r) => format!("DT {}", span(r, " s")),
            Cond::Audio(r) => format!("audio {}", span(r, " Hz")),
        };
        if self.negate {
            format!("not {text}")
        } else {
            text
        }
    }
}
impl Strategy {
    pub(crate) fn json(&self) -> Value {
        json!({"name":self.name,
            "rules":self.rules.iter().map(|r| json!({"conditions":r.iter().map(Condition::json).collect::<Vec<_>>()})).collect::<Vec<_>>(),
            "sort":match self.sort {Sort::Strongest=>"strongest",Sort::Weakest=>"weakest",Sort::Furthest=>"furthest",Sort::Newest=>"newest"},
            "treat_73_as_cq":self.treat_73_as_cq,"apply_to_callers":self.apply_to_callers,"skip_after":self.skip_after,
            "auto_role":match self.role {Role::Call=>"call",Role::Cq=>"cq",Role::Alternate=>"alternate"},
            "switch_after":self.switch_after})
    }
}
impl Config {
    pub(crate) fn json(&self) -> Value {
        json!({"continent":self.continent,"active":self.active,"highlight":self.highlight,
            "strategies":self.strategies.iter().map(Strategy::json).collect::<Vec<_>>()})
    }
    pub(crate) fn active_strategy(&self) -> Option<&Strategy> {
        let name = self.active.as_deref()?;
        self.strategies.iter().find(|s| s.name == name)
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
/// Great-circle distance in whole km (R 6371 km) and initial bearing in degrees.
pub(crate) fn distance_bearing(from: &str, to: &str) -> Option<(f64, f64)> {
    Some(great_circle(maidenhead(from)?, maidenhead(to)?))
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
    pub dt: Option<f64>,
    pub hz: f64,
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
        dt: record["dt_seconds"].as_f64(),
        hz: record["frequency_hz"].as_f64().unwrap_or(0.0),
    })
}
/// Station facts of one evaluation: my call, grid and continent, the band, the country
/// table (#55) and the worked status of the calls and grids in question (from the
/// internal log).
#[derive(Clone, Debug, Default)]
pub(crate) struct Station {
    pub my_call: String,
    pub my_grid: Option<String>,
    pub my_continent: Option<String>,
    pub band: Option<String>,
    /// call -> (worked ever, worked on this band and mode)
    pub calls: HashMap<String, (bool, bool)>,
    pub grids: HashMap<String, (bool, bool)>,
    pub dxcc: crate::dxcc::Table,
    /// #42 the operating mode (upper case) and the log's cached worked set (None: the
    /// log is unreadable) for NewEntity.
    pub mode: String,
    pub worked: Option<std::sync::Arc<crate::dxcc::Worked>>,
}
/// WstxStrategy::DirectedCqRule: is a CQ with this target addressed to my station?
/// A continent target only to that continent; DX only from another, known continent
/// than mine; any other target (TEST, POTA, a number, a country) is not continent-
/// directed and is left to the strategy's cq_target conditions.
pub(crate) fn addressed_to_me(target: &str, mine: Option<&str>, sender: Option<&str>) -> bool {
    if CONTINENTS.contains(&target) {
        return mine == Some(target);
    }
    if target == "DX" {
        return mine.zip(sender).is_some_and(|(m, s)| m != s);
    }
    true
}
fn within(r: &Range, x: Option<f64>, wraps: bool) -> bool {
    let Some(x) = x else { return false };
    match (r.min, r.max) {
        (Some(a), Some(b)) if wraps && a > b => x >= a || x <= b,
        (a, b) => a.is_none_or(|a| x >= a) && b.is_none_or(|b| x <= b),
    }
}
impl Station {
    fn worked_call(&self, call: &str) -> (bool, bool) {
        self.calls.get(call).copied().unwrap_or_default()
    }
    fn holds(&self, c: &Cond, f: &Facts, treat_73_as_cq: bool) -> bool {
        let geo = f
            .grid
            .as_deref()
            .zip(self.my_grid.as_deref())
            .and_then(|(g, m)| distance_bearing(m, g));
        match c {
            Cond::Message(Message::Cq) => self.cq_like(f, treat_73_as_cq),
            Cond::Message(Message::DirectedCq) => f.cq && f.target.is_some(),
            Cond::Message(Message::ToMe) => f.to_call.as_deref() == Some(self.my_call.as_str()),
            Cond::Message(Message::Signoff) => f.signoff,
            Cond::NewCall(s) => {
                let (ever, band) = self.worked_call(&f.from);
                if *s == Scope::Ever { !ever } else { !band }
            }
            Cond::NewGrid(s) => f.grid.as_deref().is_some_and(|g| {
                let (ever, band) = self
                    .grids
                    .get(&g[..4].to_ascii_uppercase())
                    .copied()
                    .unwrap_or_default();
                if *s == Scope::Ever { !ever } else { !band }
            }),
            Cond::Continent(l) => self
                .dxcc
                .continent(&f.from)
                .is_some_and(|c| l.iter().any(|x| x == c)),
            Cond::Distance(r) => within(r, geo.map(|g| g.0), false),
            Cond::Azimuth(r) => within(r, geo.map(|g| g.1), true),
            Cond::Snr(r) => within(r, f.snr, false),
            Cond::Dt(r) => within(r, f.dt, false),
            Cond::Audio(r) => within(r, Some(f.hz), false),
            Cond::Call(l) => l.iter().any(|p| f.from.starts_with(p.as_str())),
            Cond::CqTarget(l) => f.cq && f.target.as_ref().is_some_and(|t| l.contains(t)),
            Cond::Band(l) => self.band.as_ref().is_some_and(|b| l.contains(b)),
            Cond::NewEntity(c, s) => {
                let (Some(w), Some(r)) = (&self.worked, self.dxcc.lookup(&f.from)) else {
                    return false;
                };
                match s {
                    Scope::Ever => w.entity_new(*c, &r, None),
                    Scope::Band => self
                        .band
                        .as_deref()
                        .is_some_and(|b| w.entity_new(*c, &r, Some((b, &self.mode)))),
                }
            }
        }
    }
    /// A CQ, or with treat_73_as_cq an RR73/73 that ends someone else's QSO.
    pub(crate) fn cq_like(&self, f: &Facts, treat_73_as_cq: bool) -> bool {
        f.cq || (treat_73_as_cq
            && f.signoff
            && f.to_call.as_deref().is_some_and(|t| t != self.my_call))
    }
    /// The hard directed-CQ rule: a directed CQ not addressed to me is greyed and never
    /// matches (Highlight) nor is answered (Auto).
    pub(crate) fn greyed(&self, f: &Facts) -> bool {
        f.target.as_deref().is_some_and(|t| {
            !addressed_to_me(
                t,
                self.my_continent.as_deref(),
                self.dxcc.continent(&f.from),
            )
        })
    }
}
/// WstxStrategy::Verdict of one record.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Verdict {
    pub facts: Facts,
    pub rank: Option<usize>,
    pub grey: bool,
    pub why: String,
    pub km: Option<f64>,
}
impl Verdict {
    pub(crate) fn json(&self, explain: bool) -> Value {
        let mut v = json!({"sequence":self.facts.sequence,"rank":self.rank,"grey":self.grey});
        if explain {
            v["why"] = json!(self.why);
        }
        v
    }
}
/// WstxStrategy::Evaluate: one verdict per decoded standard record with a resolved
/// sender (other records have none). rank = index of the first rule whose conditions
/// all hold (each negated as configured); a greyed directed CQ has no rank.
pub(crate) fn evaluate(s: &Strategy, records: &[Value], st: &Station) -> Vec<Verdict> {
    let mut out = Vec::new();
    for record in records {
        let Some(f) = facts(record) else { continue };
        let km = f
            .grid
            .as_deref()
            .zip(st.my_grid.as_deref())
            .and_then(|(g, m)| distance_bearing(m, g))
            .map(|g| g.0);
        if st.greyed(&f) {
            let target = f.target.clone().unwrap_or_default();
            out.push(Verdict {
                why: format!(
                    "CQ {target} is not addressed to my continent ({})",
                    st.my_continent.as_deref().unwrap_or("unknown")
                ),
                facts: f,
                rank: None,
                grey: true,
                km,
            });
            continue;
        }
        let mut rank = None;
        let mut failed = Vec::new();
        for (i, rule) in s.rules.iter().enumerate() {
            match rule
                .iter()
                .find(|c| st.holds(&c.cond, &f, s.treat_73_as_cq) == c.negate)
            {
                None => {
                    rank = Some(i);
                    break;
                }
                Some(c) => failed.push(format!("rule {}: {}", i + 1, c.label())),
            }
        }
        out.push(Verdict {
            why: match rank {
                Some(i) => format!("matches rule {}", i + 1),
                None => format!("no match ({})", failed.join("; ")),
            },
            facts: f,
            rank,
            grey: false,
            km,
        });
    }
    out
}
/// Matches first by rank, then by the strategy's sort, then by sequence.
pub(crate) fn order(list: &mut [Verdict], sort: Sort) {
    let key = |v: &Verdict| match sort {
        Sort::Strongest => v.facts.snr.map_or(f64::INFINITY, |s| -s),
        Sort::Weakest => v.facts.snr.unwrap_or(f64::INFINITY),
        Sort::Furthest => v.km.map_or(f64::INFINITY, |k| -k),
        Sort::Newest => -(v.facts.sequence as f64),
    };
    list.sort_by(|a, b| {
        a.rank
            .unwrap_or(usize::MAX)
            .cmp(&b.rank.unwrap_or(usize::MAX))
            .then(key(a).total_cmp(&key(b)))
            .then(a.facts.sequence.cmp(&b.facts.sequence))
    });
}
/// Auto answers a CQ with a target that DirectedCqRule leaves open (TEST, POTA, a
/// country or a number) only when the matched rule asks for that target with a
/// non-negated cq_target condition: a country-directed CQ is never answered by default.
pub(crate) fn auto_target_ok(s: &Strategy, v: &Verdict) -> bool {
    let Some(target) = v.facts.target.as_deref() else {
        return true;
    };
    if CONTINENTS.contains(&target) || target == "DX" {
        return true; // DirectedCqRule already decided (not greyed here).
    }
    v.rank.and_then(|r| s.rules.get(r)).is_some_and(|rule| {
        rule.iter().any(|c| {
            !c.negate && matches!(&c.cond, Cond::CqTarget(l) if l.iter().any(|t| t == target))
        })
    })
}
/// The callsign guard before Auto answers (WSJT-Z): at least 3 characters with a digit
/// and a letter, not a rover (/R).
pub(crate) fn sane_call(call: &str) -> bool {
    call.len() >= 3
        && call.bytes().any(|b| b.is_ascii_digit())
        && call.bytes().any(|b| b.is_ascii_uppercase())
        && !call.ends_with("/R")
}
/// The station's continent: the configured one, else the cty.dat continent of my call.
pub(crate) fn my_continent(
    config: &Config,
    call: Option<&str>,
    dxcc: &crate::dxcc::Table,
) -> Option<String> {
    config
        .continent
        .clone()
        .or_else(|| call.and_then(|c| dxcc.continent(c)).map(str::to_owned))
}
/// Builds the evaluation facts for these records from the profile, the station band and
/// the internal log.
/// The station band: the CAT dial band, else the operating selection band.
pub(crate) fn station_band(r: &recording::Recording) -> Option<&'static str> {
    contact_http::confirmed_dial(r)
        .and_then(logbook::band_of_hz)
        .or(r.operating_band())
}
pub(crate) fn station(state: &ProfileState, config: &Config, records: &[Value]) -> Station {
    let r = &state.recording;
    let (call, locator) = contact_http::profile_facts(state);
    let band = station_band(r).map(str::to_owned);
    let mode = r.operating_mode().to_ascii_uppercase();
    let facts: Vec<Facts> = records.iter().filter_map(facts).collect();
    let mut calls: Vec<String> = facts.iter().map(|f| f.from.clone()).collect();
    calls.sort();
    calls.dedup();
    let mut grids: Vec<String> = facts
        .iter()
        .filter_map(|f| f.grid.as_ref().map(|g| g[..4].to_ascii_uppercase()))
        .collect();
    grids.sort();
    grids.dedup();
    let b = band.clone().unwrap_or_default();
    let status = |list: &[String], worked: Vec<&'static str>| {
        list.iter()
            .cloned()
            .zip(worked)
            .map(|(k, w)| (k, (w != "not_worked", w == "worked_this_band_and_mode")))
            .collect::<HashMap<_, _>>()
    };
    let (dxcc, _) = state.logbook.dxcc();
    Station {
        my_continent: my_continent(config, call.as_deref(), &dxcc),
        my_call: call.unwrap_or_default(),
        my_grid: locator,
        band,
        calls: status(
            &calls,
            state.logbook.worked(&calls, &b, &mode).unwrap_or_default(),
        ),
        grids: status(
            &grids,
            state
                .logbook
                .worked_grids(&grids, &b, &mode)
                .unwrap_or_default(),
        ),
        dxcc,
        // The log's cached set (#55), rebuilt only after a log or country table change.
        worked: state.logbook.worked_set().ok(),
        mode,
    }
}

// ------------------------------------------------------------------ owner
#[derive(Default)]
struct Inner {
    loaded: bool,
    revision: u64,
    config: Option<Config>,
    error: Option<&'static str>,
}
/// The strategy store of one station (strategy.json beside profile.json), read on first
/// use; one leaf lock.
#[derive(Default)]
pub(crate) struct Owner {
    inner: Mutex<Inner>,
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
                            && v["schema_version"] == 1
                            && v["profile_id"] == state.recording.profile.as_str()
                            && v["revision"].as_u64().is_some_and(|n| n <= MAX_SAFE);
                        ok.then(|| parse_config(&v["configuration"]).ok())
                            .flatten()
                            .map(|c| (v["revision"].as_u64().unwrap_or(0), c))
                    });
                    match loaded {
                        Some((revision, config)) => {
                            inner.revision = revision;
                            inner.config = Some(config);
                        }
                        None => inner.error = Some("invalid_configuration"),
                    }
                }
                Err(_) => inner.error = Some("invalid_configuration"),
            }
        }
        inner
    }
    /// The saved configuration (None while the file is unreadable).
    pub(crate) fn config(&self, state: &ProfileState) -> Option<Config> {
        self.lock(state).config.clone()
    }
    /// StrategySnapshot.
    pub(crate) fn snapshot(&self, state: &ProfileState) -> Value {
        let r = &state.recording;
        let (call, _) = contact_http::profile_facts(state);
        let (dxcc, _) = state.logbook.dxcc();
        let inner = self.lock(state);
        let mine = inner
            .config
            .as_ref()
            .and_then(|c| my_continent(c, call.as_deref(), &dxcc));
        json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"revision":inner.revision,
            "configuration":inner.config.as_ref().map(Config::json),
            "configuration_error":inner.error,"my_continent":mine,
            "derived_continent":call.as_deref().and_then(|c| dxcc.continent(c))})
    }
    /// PUT /strategy after the route checks. `running` names the strategy an active
    /// Auto run uses: it cannot be removed or switched while the run lasts.
    pub(crate) fn put(
        &self,
        state: &ProfileState,
        body: Value,
        running: bool,
    ) -> Result<Value, Refusal> {
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
        let config =
            parse_config(&body["configuration"]).map_err(|f| ("invalid_request", Some(f)))?;
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
        if running && config.active != before {
            return Err(("state_conflict", Some("active".into())));
        }
        if inner.revision >= MAX_SAFE {
            return Err(("counter_exhausted", None));
        }
        let revision = inner.revision + 1;
        let document = json!({"schema_version":1,"profile_id":r.profile,"revision":revision,
            "configuration":config.json()});
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
        inner.config = Some(config);
        drop(inner);
        Ok(self.snapshot(state))
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
            s => Some(strategy(s, "strategy").map_err(|f| ("invalid_request", Some(f)))?),
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
        let chosen = match draft {
            Some(s) => s,
            None => config
                .active_strategy()
                .cloned()
                .ok_or(("not_configured", Some("strategy".into())))?,
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
        let st = station(state, &config, &records);
        // In display order: matches by rank and the strategy's sort, then the rest.
        let mut list = evaluate(&chosen, &records, &st);
        order(&mut list, chosen.sort);
        let verdicts: Vec<Value> = list
            .iter()
            .filter(|v| explain || v.rank.is_some() || v.grey)
            .map(|v| v.json(explain))
            .collect();
        Ok(
            json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"strategy":chosen.name,
            "my_continent":st.my_continent,"sort":chosen.json()["sort"],"verdicts":verdicts}),
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
    match tokio::task::spawn_blocking(move || station.strategy.snapshot(&state)).await {
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
    let reply = tokio::task::spawn_blocking(move || {
        // Read before the strategy lock: the automation lock is never taken under it.
        let running = station.automation.strategy_run_active();
        station.strategy.put(&state, body, running)
    })
    .await;
    match reply {
        Ok(Ok(snapshot)) => Json(snapshot).into_response(),
        Ok(Err((code, field))) => refusal(code, field.as_deref()),
        Err(_) => refusal("storage_unavailable", None),
    }
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
