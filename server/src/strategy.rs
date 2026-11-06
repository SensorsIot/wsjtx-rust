#![forbid(unsafe_code)]
//! WstxStrategy (#39): the award strategies, the directed-CQ rule and their one evaluator.
//! Band Activity's marks and value order and the station's strategy runs
//! (WstxMcp::OperatingAutomation with a strategy) both use these verdicts; the browser
//! never evaluates a strategy itself. Routes: GET /strategy (StrategySnapshot), PUT
//! /strategy (configuration; a changed active starts or stops a run), POST
//! /strategy/evaluate (verdicts of retained live rows), #42 GET /strategy/alerts and POST
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

/// WstxStrategy::Goal, in wire order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Goal {
    Dxcc,
    DxccBand,
    DxccSlot,
    Waz,
    Wpx,
    Grid,
    NewCall,
}
const GOALS: [(&str, Goal); 7] = [
    ("dxcc", Goal::Dxcc),
    ("dxcc_band", Goal::DxccBand),
    ("dxcc_slot", Goal::DxccSlot),
    ("waz", Goal::Waz),
    ("wpx", Goal::Wpx),
    ("grid", Goal::Grid),
    ("new_call", Goal::NewCall),
];
impl Goal {
    fn name(self) -> &'static str {
        GOALS.iter().find(|g| g.1 == self).map_or("", |g| g.0)
    }
}
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
/// WstxStrategy::Strategy.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Strategy {
    pub name: String,
    pub goals: Vec<Goal>,
    pub needed: Needed,
    pub region: Region,
    pub min_snr_db: Option<i64>,
    pub calls_per_station: u64,
    pub treat_73_as_cq: bool,
    pub window: Window,
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
}
impl Default for Config {
    fn default() -> Self {
        Self {
            continent: None,
            active: None,
            strategies: Vec::new(),
            ignore_calls: Vec::new(),
            session_ignore_minutes: SESSION_IGNORE_MINUTES,
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
fn strategy(v: &Value, field: &str) -> Result<Strategy, Field> {
    exact(
        v,
        &[
            "name",
            "class",
            "goals",
            "needed",
            "region",
            "min_snr_db",
            "calls_per_station",
            "treat_73_as_cq",
            "window",
        ],
        field,
    )?;
    let f = |k: &str| format!("{field}.{k}");
    let name = v["name"]
        .as_str()
        .filter(|n| {
            (1..=32).contains(&n.len())
                && n.trim() == *n
                && n.bytes().all(|b| (0x20..0x7f).contains(&b))
        })
        .ok_or(bad(f("name")))?
        .to_owned();
    // Only award has behaviour; contest is #63.
    if v["class"] != "award" {
        return Err(f("class"));
    }
    let list = v["goals"]
        .as_array()
        .filter(|g| (1..=GOALS.len()).contains(&g.len()))
        .ok_or(bad(f("goals")))?;
    let mut goals = Vec::new();
    for (i, g) in list.iter().enumerate() {
        let goal = GOALS
            .iter()
            .find(|k| g.as_str() == Some(k.0))
            .map(|k| k.1)
            .filter(|k| !goals.contains(k))
            .ok_or(bad(format!("{field}.goals[{i}]")))?;
        goals.push(goal);
    }
    let needed = match v["needed"].as_str() {
        Some("not_worked") => Needed::NotWorked,
        Some("not_confirmed") => Needed::NotConfirmed,
        _ => return Err(f("needed")),
    };
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
    let window_field = f("window");
    let window = match v["window"]["kind"].as_str() {
        Some("all") => {
            exact(&v["window"], &["kind"], &window_field)?;
            Window::All
        }
        Some("today") => {
            exact(&v["window"], &["kind"], &window_field)?;
            Window::Today
        }
        Some("from_to") => {
            exact(&v["window"], &["kind", "from", "to"], &window_field)?;
            let from = date(&v["window"]["from"], &format!("{window_field}.from"))?;
            let to = date(&v["window"]["to"], &format!("{window_field}.to"))?;
            if from > to {
                return Err(format!("{window_field}.to"));
            }
            Window::FromTo(from, to)
        }
        _ => return Err(format!("{window_field}.kind")),
    };
    Ok(Strategy {
        name,
        goals,
        needed,
        region,
        min_snr_db,
        calls_per_station: bounded(&v["calls_per_station"], &f("calls_per_station"), 1, 20)?,
        treat_73_as_cq: v["treat_73_as_cq"]
            .as_bool()
            .ok_or(bad(f("treat_73_as_cq")))?,
        window,
    })
}
/// Exact StrategyConfiguration parsing (field names a refused value).
pub(crate) fn parse_config(v: &Value) -> Result<Config, Field> {
    exact(
        v,
        &[
            "continent",
            "active",
            "strategies",
            "ignore_calls",
            "session_ignore_minutes",
        ],
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
    Ok(Config {
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
impl Strategy {
    pub(crate) fn json(&self) -> Value {
        json!({"name":self.name,"class":"award",
        "goals":self.goals.iter().map(|g| g.name()).collect::<Vec<_>>(),
        "needed":match self.needed {Needed::NotWorked=>"not_worked",Needed::NotConfirmed=>"not_confirmed"},
        "region":match &self.region {
            Region::All=>json!({"kind":"all"}),
            Region::Dx=>json!({"kind":"dx"}),
            Region::Selected(c)=>json!({"kind":"selected","continents":c}),
        },
        "min_snr_db":self.min_snr_db,"calls_per_station":self.calls_per_station,
        "treat_73_as_cq":self.treat_73_as_cq,
        "window":match self.window {
            Window::All=>json!({"kind":"all"}),
            Window::Today=>json!({"kind":"today"}),
            Window::FromTo(a,b)=>json!({"kind":"from_to","from":date_text(a),"to":date_text(b)}),
        }})
    }
}
impl Config {
    pub(crate) fn json(&self) -> Value {
        json!({"continent":self.continent,"active":self.active,
            "strategies":self.strategies.iter().map(Strategy::json).collect::<Vec<_>>(),
            "ignore_calls":self.ignore_calls,"session_ignore_minutes":self.session_ignore_minutes})
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
}
/// The list an ignored call is on (the session list wins when on both).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Tier {
    Session,
    Permanent,
}
impl Tier {
    fn name(self) -> &'static str {
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
    /// WstxStrategy::CallerOfMyCall, before the ignore check.
    fn calls_me(&self, f: &Facts) -> bool {
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
    /// WstxStrategy::GoalNeeded.
    fn goal_needed(&self, s: &Strategy, goal: Goal, f: &Facts) -> bool {
        let Some(w) = &self.worked else { return false };
        let entity = self.dxcc.lookup(&f.from);
        let of = |c: Category, band: Option<&str>, mode: Option<&str>| {
            entity
                .as_ref()
                .is_some_and(|r| s.needed.holds(w.entity_standing(c, r, band, mode)))
        };
        let band = self.band.as_deref();
        match goal {
            Goal::Dxcc => of(Category::Dxcc, None, None),
            Goal::DxccBand => band.is_some() && of(Category::Dxcc, band, None),
            Goal::DxccSlot => band.is_some() && of(Category::Dxcc, band, Some(&self.mode)),
            Goal::Waz => of(Category::CqZone, None, None),
            Goal::Wpx => s.needed.holds(w.wpx_standing(&f.from)),
            Goal::NewCall => s.needed.holds(w.call_standing(&f.from)),
            // D13: no grid in the message, or a logged QSO without one: unknown, never new.
            Goal::Grid => {
                !w.gridless(&f.from)
                    && f.grid
                        .as_deref()
                        .is_some_and(|g| s.needed.holds(w.grid_standing(g)))
            }
        }
    }
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
/// One record's classification before the ranks: the kind or the reason there is none.
fn classify(s: &Strategy, f: &Facts, st: &Station) -> (Option<Kind>, bool, String) {
    if let Some(tier) = st.ignored.get(&f.from) {
        return (
            None,
            false,
            format!("{} is ignored ({} list)", f.from, tier.name()),
        );
    }
    if st.greyed(f) {
        let text = not_for_me(
            f.target.as_deref().unwrap_or(""),
            st.my_continent.as_deref(),
        );
        return (None, true, text);
    }
    if f.from == st.my_call {
        return (None, false, "my own message".to_owned());
    }
    if st.calls_me(f) {
        return (Some(Kind::Caller), false, "calls my call".to_owned());
    }
    if !sane_call(&f.from) {
        return (None, false, "callsign guard".to_owned());
    }
    if !st.cq_like(f, s.treat_73_as_cq) {
        return (None, false, "not a CQ".to_owned());
    }
    if !st.region_holds(s, f) {
        return (None, false, "region".to_owned());
    }
    if s.min_snr_db
        .is_some_and(|m| f.snr.is_none_or(|snr| snr < m as f64))
    {
        return (None, false, "below min SNR".to_owned());
    }
    let needed: Vec<&str> = s
        .goals
        .iter()
        .filter(|g| st.goal_needed(s, **g, f))
        .map(|g| g.name())
        .collect();
    if needed.is_empty() {
        return (None, false, "not needed".to_owned());
    }
    (
        Some(Kind::Candidate),
        false,
        format!("needed: {}", needed.join(", ")),
    )
}
/// WstxStrategy::ValueOrder of ranked records, smaller first: callers, the Most Wanted list by
/// its rank, then the strongest and the sequence.
fn value_key(v: &Verdict, st: &Station) -> (u8, u32, f64, u64) {
    let snr = v.facts.snr.map_or(f64::INFINITY, |s| -s);
    if v.kind == Some(Kind::Caller) {
        return (0, 0, snr, v.facts.sequence);
    }
    let listed = st
        .most_wanted
        .as_ref()
        .and_then(|l| st.dxcc.lookup(&v.facts.from).and_then(|r| l.rank(&r.name)));
    match listed {
        Some(rank) => (1, rank, snr, v.facts.sequence),
        None => (2, 0, snr, v.facts.sequence),
    }
}
/// WstxStrategy::Verdict: one per decoded standard record with a resolved sender, in display
/// order: rank (the position in ValueOrder) ascending, then the records without a rank in
/// their order.
pub(crate) fn evaluate(s: &Strategy, records: &[Value], st: &Station) -> Vec<Verdict> {
    let mut list: Vec<Verdict> = records
        .iter()
        .filter_map(facts)
        .map(|f| {
            let (kind, grey, why) = classify(s, &f, st);
            Verdict {
                facts: f,
                rank: None,
                grey,
                why,
                kind,
            }
        })
        .collect();
    let (mut ranked, rest): (Vec<Verdict>, Vec<Verdict>) =
        list.drain(..).partition(|v| v.kind.is_some());
    let mut keyed: Vec<((u8, u32, f64, u64), Verdict)> =
        ranked.drain(..).map(|v| (value_key(&v, st), v)).collect();
    keyed.sort_by(|(a, _), (b, _)| {
        a.0.cmp(&b.0)
            .then(a.1.cmp(&b.1))
            .then(a.2.total_cmp(&b.2))
            .then(a.3.cmp(&b.3))
    });
    let mut out = Vec::with_capacity(keyed.len() + rest.len());
    for (i, (key, mut v)) in keyed.into_iter().enumerate() {
        v.rank = Some(i);
        if key.0 == 1 {
            v.why = format!("{} · Most Wanted #{}", v.why, key.1);
        }
        out.push(v);
    }
    out.extend(rest);
    out
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
    }
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
    /// The HaltTransmit count the selection has seen (a change sets active to None).
    halts_seen: std::sync::atomic::AtomicU64,
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
                        let configuration = match v["schema_version"].as_u64() {
                            Some(1) => upgrade(&v["configuration"]),
                            Some(2) => v["configuration"].clone(),
                            _ => return None,
                        };
                        ok.then(|| parse_config(&configuration).ok())
                            .flatten()
                            .map(|mut c| {
                                // active never survives a restart (WstxStrategy D2).
                                c.active = None;
                                (v["revision"].as_u64().unwrap_or(0), c)
                            })
                    });
                    match loaded {
                        Some((revision, config)) => {
                            inner.revision = revision;
                            inner.config = Some(config);
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
    /// A HaltTransmit from any source since the last step sets active to None (memory only:
    /// active is never read from the file), pushed by strategy.state.
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
        let revision = inner.revision + 1;
        let Some(config) = inner.config.as_mut().filter(|c| c.active.is_some()) else {
            return;
        };
        config.active = None;
        inner.revision = revision;
        self.revision_seen.store(revision, Ordering::Release);
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
        let inner = self.lock(state);
        let mine = inner
            .config
            .as_ref()
            .and_then(|c| my_continent(c, call.as_deref(), locator.as_deref(), &dxcc));
        json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"revision":inner.revision,
            "configuration":inner.config.as_ref().map(Config::json),
            "configuration_error":inner.error,"my_continent":mine,
            "derived_continent":call.as_deref().and_then(|c| dxcc.continent(c)),
            "session_ignore":session,"most_wanted":status,
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
    /// PUT /strategy after the route checks: the snapshot and whether active changed (the
    /// route then starts or stops the run, WstxStrategy::StrategyRun).
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
        let changed = config.active != before;
        if inner.revision >= MAX_SAFE {
            return Err(("counter_exhausted", None));
        }
        let revision = inner.revision + 1;
        // active is never read back: the file holds none (WstxStrategy D2).
        let mut stored = config.json();
        stored["active"] = Value::Null;
        let document = json!({"schema_version":2,"profile_id":r.profile,"revision":revision,
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
        self.most_wanted_load(state);
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
        if changed {
            station.strategy.most_wanted_load(&state);
            if let Some(s) = station
                .strategy
                .config(&state)
                .as_ref()
                .and_then(Config::active_strategy)
            {
                worked_build(&state, s.window);
            }
            // Taken after the strategy lock is free: the automation lock comes first.
            station.automation.selected(&station, &state, access);
        }
        Ok::<Value, Refusal>(snapshot)
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
/// strategy.state: announces a new store revision (a save, a selection, a HALT's None); the
/// browser then reads GET /strategy.
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
