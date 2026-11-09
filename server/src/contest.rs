#![forbid(unsafe_code)]
//! WstxContest (#63, #98): the selection of a contest record of the contest file
//! (contest_rules.rs) and its evaluation: the state from the log of the period (ContestLog),
//! the serial from the log (ContestSerial), the value as projected score gain (ContestValue),
//! the verdicts (ContestVerdict) and their order (ContestValueOrder).
use crate::contact::{civil, parse_utc};
pub(crate) use crate::contest_rules::{Clause, File, ModeClass, PValue, Profile};
use crate::contest_rules::{Dim, MultKind, MyStation, Per, Vars};
use crate::strategy::{Facts, Kind, Station, Verdict, sane_call};
use serde_json::{Map, Value, json};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::Arc;

#[cfg(test)]
#[path = "contest_tests.rs"]
mod tests;

const DAY_MS: i64 = 86_400_000;
const MINUTE_MS: i64 = 60_000;

/// "YYYY-MM-DDTHH:MMZ".
pub(crate) fn utc_text(ms: i64) -> String {
    let (y, mo, d, h, mi, _) = civil(ms);
    format!("{y:04}-{mo:02}-{d:02}T{h:02}:{mi:02}Z")
}
/// The profiles of GET /strategy/contests, in file order.
pub(crate) fn profiles_json(now_ms: i64, file: &File, me: &MyStation) -> Value {
    Value::Array(
        file.contests
            .iter()
            .map(|p| p.json(now_ms, me, file))
            .collect(),
    )
}
/// A record of the bundled file.
pub(crate) fn profile(id: &str) -> Option<Arc<Profile>> {
    crate::contest_rules::bundled().profile(id).cloned()
}

// ------------------------------------------------------------------ the selection
/// WstxContest::ContestSelection operation (with Auto on; Auto off only marks, strategydef).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Operation {
    /// Search and pounce.
    Sp,
    /// Call CQ, answer the most valuable caller.
    Run,
}
impl Operation {
    fn name(self) -> &'static str {
        match self {
            Operation::Sp => "sp",
            Operation::Run => "run",
        }
    }
}
/// WstxContest::ContestSelection: the contest in force, in memory only.
#[derive(Clone, Debug)]
pub(crate) struct Selection {
    pub file: Arc<File>,
    pub profile: Arc<Profile>,
    pub start_ms: i64,
    pub end_ms: i64,
    pub operation: Operation,
    /// x of WstxStrategy::LeaveRule, 1..20.
    pub repetitions: u64,
    /// WstxStrategy::QuietTime minutes, 1..120.
    pub quiet_minutes: u64,
    /// #98 the entry params, every one of the record's (absent ones at their default).
    pub entry: BTreeMap<String, PValue>,
}
impl PartialEq for Selection {
    fn eq(&self, o: &Self) -> bool {
        Arc::ptr_eq(&self.profile, &o.profile)
            && (
                self.start_ms,
                self.end_ms,
                self.operation,
                self.repetitions,
                self.quiet_minutes,
                &self.entry,
            ) == (
                o.start_ms,
                o.end_ms,
                o.operation,
                o.repetitions,
                o.quiet_minutes,
                &o.entry,
            )
    }
}
/// The longest period a selection accepts.
const PERIOD_MAX_MS: i64 = 31 * DAY_MS;
/// A real instant "YYYY-MM-DDTHH:MMZ".
fn minute(v: &Value) -> Option<i64> {
    let text = v.as_str().filter(|t| t.len() == 17 && t.is_ascii())?;
    let ms = parse_utc(&format!("{}:00Z", &text[..16]))?;
    (utc_text(ms) == text).then_some(ms)
}
/// Exact ContestSelection parsing in the bundled file (the error names the refused field).
pub(crate) fn parse_selection(v: &Value, field: &str) -> Result<Selection, String> {
    parse_selection_in(v, field, &crate::contest_rules::bundled())
}
/// Exact ContestSelection parsing in the contest file in use.
pub(crate) fn parse_selection_in(
    v: &Value,
    field: &str,
    file: &Arc<File>,
) -> Result<Selection, String> {
    let o = v.as_object().ok_or(field)?;
    let keys = [
        "profile",
        "start",
        "end",
        "operation",
        "repetitions",
        "quiet_minutes",
    ];
    let f = |k: &str| format!("{field}.{k}");
    // automation_confirmed is gone (the confirmation goes with Auto on, strategydef): refused
    // by its own path; any other extra key by the selection's.
    if o.contains_key("automation_confirmed") {
        return Err(f("automation_confirmed"));
    }
    let with_entry = o.contains_key("entry");
    if o.len() != keys.len() + usize::from(with_entry) || !keys.iter().all(|k| o.contains_key(*k))
    {
        return Err(field.to_owned());
    }
    let profile = v["profile"]
        .as_str()
        .and_then(|id| file.profile(id))
        .cloned()
        .ok_or(f("profile"))?;
    let start_ms = minute(&v["start"]).ok_or(f("start"))?;
    let end_ms = minute(&v["end"])
        .filter(|e| *e > start_ms && *e - start_ms <= PERIOD_MAX_MS)
        .ok_or(f("end"))?;
    let operation = match v["operation"].as_str() {
        Some("sp") => Operation::Sp,
        Some("run") => Operation::Run,
        _ => return Err(f("operation")),
    };
    let bounded = |k: &str, hi: u64| v[k].as_u64().filter(|n| (1..=hi).contains(n)).ok_or(f(k));
    let mut entry = profile.entry_defaults();
    if with_entry {
        let e = v["entry"].as_object().ok_or(f("entry"))?;
        for (name, value) in e {
            let param = profile
                .entry
                .params
                .iter()
                .find(|p| p.name == *name)
                .ok_or(format!("{field}.entry.{name}"))?;
            let value = param
                .value(value)
                .ok_or(format!("{field}.entry.{name}"))?;
            entry.insert(name.clone(), value);
        }
    }
    Ok(Selection {
        file: file.clone(),
        profile,
        start_ms,
        end_ms,
        operation,
        repetitions: bounded("repetitions", 20)?,
        quiet_minutes: bounded("quiet_minutes", 120)?,
        entry,
    })
}
impl Selection {
    pub(crate) fn json(&self) -> Value {
        let mut v = json!({"profile":self.profile.id,"start":utc_text(self.start_ms),
            "end":utc_text(self.end_ms),"operation":self.operation.name(),
            "repetitions":self.repetitions,"quiet_minutes":self.quiet_minutes});
        if !self.entry.is_empty() {
            v["entry"] = Value::Object(
                self.entry
                    .iter()
                    .map(|(k, p)| (k.clone(), p.json()))
                    .collect::<Map<String, Value>>(),
            );
        }
        v
    }
    pub(crate) fn in_period(&self, now_ms: i64) -> bool {
        now_ms >= self.start_ms && now_ms < self.end_ms
    }
    /// The clause in force for the selected section (AutomationClause).
    pub(crate) fn clause(&self) -> Clause {
        self.profile.clause_for(&self.entry).0
    }
    /// ExchangeRule: the record's CQ word.
    pub(crate) fn cq_word(&self) -> Option<&str> {
        self.profile.exchange.cq.as_deref()
    }
    /// ExchangeRule.unsendable_for holds for my station.
    pub(crate) fn unsendable(&self, dxcc: &crate::dxcc::Table, my_call: Option<&str>) -> bool {
        let me = my_call.and_then(|c| dxcc.lookup(c));
        self.profile.exchange.unsendable_for.as_ref().is_some_and(|e| {
            e.holds(&Vars {
                my_prefix: me.as_ref().map(|r| r.prefix.as_str()),
                my_cont: me.as_ref().map(|r| r.continent),
                params: Some(&self.entry),
                sets: Some(&self.file.sets),
                ..Vars::default()
            })
        })
    }
    /// The bands of the record (and of its rounds).
    pub(crate) fn has_band(&self, band: &str) -> bool {
        self.profile.bands.iter().any(|b| b == band)
            || self
                .profile
                .schedule
                .rounds
                .iter()
                .flat_map(|r| r.bands.iter().flatten())
                .any(|b| b == band)
    }
}

// ------------------------------------------------------------------ the log
/// One logged contact as a contest reads it (ContestLog).
#[derive(Clone, Debug, PartialEq, Default)]
pub(crate) struct Qso {
    pub call: String,
    /// GRIDSQUARE up to 6 characters.
    pub grid: Option<String>,
    pub band: Option<String>,
    pub mode: String,
    pub submode: Option<String>,
    pub ms: i64,
    pub my_grid: Option<String>,
    pub stx: Option<String>,
    pub srx: Option<String>,
    pub srx_string: Option<String>,
    pub state: Option<String>,
    pub class: Option<String>,
    pub arrl_sect: Option<String>,
    pub rst_rcvd: Option<String>,
}
impl Qso {
    /// The received exchange field (ExchangeRule: where ContestLog reads it).
    fn field(&self, name: &str) -> Option<String> {
        match name {
            "serial" => self.srx.clone(),
            "section" => self.arrl_sect.clone(),
            "fd_class" => self.class.clone(),
            "state_province" => self.state.clone(),
            "grid4" => self.grid.as_ref().and_then(|g| g.get(..4)).map(str::to_owned),
            "grid6" => self.grid.clone().filter(|g| g.len() >= 6),
            "report" | "rst" => self.rst_rcvd.clone(),
            _ => self.srx_string.clone(),
        }
        .map(|s| s.to_ascii_uppercase())
    }
}
/// One QSO of the period as the evaluation reads it.
#[derive(Clone, Debug)]
struct Item {
    call: String,
    ms: i64,
    band: String,
    mode: String,
    class: ModeClass,
    round: Option<usize>,
    my_grid: Option<String>,
    their_grid: Option<String>,
    their: Option<crate::dxcc::Resolved>,
    fields: Option<Qso>,
    /// The points by PointsRule (before the cap).
    raw: f64,
    dupe_key: Vec<Option<String>>,
}
/// WstxContest::ContestLog: the log of the period by the record's rules.
#[derive(Clone, Debug, Default)]
pub(crate) struct Log {
    /// The non-dupe QSOs (scoring or not) for the dupe test: call -> dimension keys.
    keys: HashMap<String, Vec<Vec<Option<String>>>>,
    /// Each multiplier set's keys.
    sets: Vec<HashSet<String>>,
    /// all_bands sets: (set, key) -> the bands of the call's scoring QSOs.
    band_cover: HashMap<(usize, String), HashSet<String>>,
    /// The scoring QSOs in time order: start, points after the cap, keys added per set.
    scoring: Vec<(i64, f64, Vec<usize>)>,
    /// The capped QSOs that kept their points, and the scoring QSOs (for a new QSO's cap).
    capped_kept: u64,
    pub qsos: u64,
    pub points: f64,
    /// ScoredWindow first: the operating minutes so far and the last non-dupe QSO's start.
    operating_ms: i64,
    last_ms: Option<i64>,
    /// ScoredWindow best: points per unit.
    /// ContestSerial: the highest STX of the period's contacts.
    pub max_stx: Option<u64>,
    names: Vec<String>,
}
fn upper(s: Option<&str>) -> Option<String> {
    s.map(str::to_ascii_uppercase).filter(|s| !s.is_empty())
}
/// What the evaluation of one QSO needs of my station.
struct Me<'a> {
    s: &'a Selection,
    dxcc: &'a crate::dxcc::Table,
    me: Option<crate::dxcc::Resolved>,
    station_grid: Option<String>,
}
impl<'a> Me<'a> {
    fn new(s: &'a Selection, dxcc: &'a crate::dxcc::Table, call: Option<&str>, grid: Option<&str>) -> Self {
        Self {
            s,
            dxcc,
            me: call.and_then(|c| dxcc.lookup(c)),
            station_grid: upper(grid),
        }
    }
    fn vars<'b>(&'b self, it: &'b Item, estimate: bool) -> Vars<'b> {
        let p = &self.s.profile;
        let member = p
            .members
            .as_ref()
            .and_then(|m| self.s.file.call_lists.get(m))
            .is_some_and(|l| l.iter().any(|c| *c == it.call));
        Vars {
            band: &it.band,
            class: Some(it.class),
            my_grid: it.my_grid.as_deref(),
            their_grid: it.their_grid.as_deref(),
            their_centre: estimate
                .then(|| it.their.as_ref().map(|r| (r.lat, r.lon)))
                .flatten(),
            my_prefix: self.me.as_ref().map(|r| r.prefix.as_str()),
            my_cont: self.me.as_ref().map(|r| r.continent),
            their_prefix: it.their.as_ref().map(|r| r.prefix.as_str()),
            their_cont: it.their.as_ref().map(|r| r.continent),
            their_member: member,
            params: Some(&self.s.entry),
            sets: Some(&self.s.file.sets),
            ..Vars::default()
        }
    }
    fn item(&self, q: &Qso, band: &str, mode: String) -> Item {
        let p = &self.s.profile;
        let my_grid = upper(q.my_grid.as_deref()).or_else(|| self.station_grid.clone());
        let their_grid = upper(q.grid.as_deref()).filter(|g| g.len() >= 4);
        let class = ModeClass::of(&q.mode);
        let round = p.schedule.round_at(q.ms);
        let mut it = Item {
            call: q.call.to_ascii_uppercase(),
            ms: q.ms,
            band: band.to_owned(),
            class,
            round,
            my_grid,
            their_grid,
            their: self.dxcc.lookup(&q.call),
            fields: Some(q.clone()),
            raw: 0.0,
            dupe_key: Vec::new(),
            mode,
        };
        it.dupe_key = self.dupe_key(&it);
        it.raw = p.points.number(&self.vars(&it, false)).unwrap_or(0.0);
        it
    }
    fn dupe_key(&self, it: &Item) -> Vec<Option<String>> {
        let p = &self.s.profile;
        p.dupe
            .per
            .iter()
            .map(|d| match d {
                Dim::Band => Some(it.band.clone()),
                Dim::Mode => Some(it.mode.clone()),
                Dim::ModeGroup => Some(p.modes.group(&it.mode)),
                Dim::ModeClass => Some(it.class.name().to_owned()),
                Dim::Round => Some(it.round.map_or("-".into(), |r| r.to_string())),
                Dim::UtcDay => Some((it.ms.div_euclid(DAY_MS)).to_string()),
                Dim::TheirGrid4 => it.their_grid.as_ref().and_then(|g| g.get(..4)).map(str::to_owned),
                Dim::MyGrid4 => it.my_grid.as_ref().and_then(|g| g.get(..4)).map(str::to_owned),
            })
            .collect()
    }
    /// The multiplier keys of a QSO: (set, key) for each set it counts in.
    fn mult_keys(&self, it: &Item) -> Vec<(usize, String)> {
        let p = &self.s.profile;
        let vars = self.vars(it, false);
        let mut out = Vec::new();
        for (i, m) in p.multipliers.iter().enumerate() {
            if m.only.as_ref().is_some_and(|c| !c.holds(&vars)) {
                continue;
            }
            let key = match &m.kind {
                MultKind::Dxcc => it.their.as_ref().map(|r| r.prefix.clone()),
                MultKind::Wpx => Some(crate::dxcc::wpx_prefix(&it.call)).filter(|w| !w.is_empty()),
                MultKind::Continent => it.their.as_ref().map(|r| r.continent.to_owned()),
                MultKind::CqZone => it.their.as_ref().map(|r| r.cq_zone.to_string()),
                MultKind::ItuZone => it.their.as_ref().map(|r| r.itu_zone.to_string()),
                MultKind::GridField => it.their_grid.as_ref().and_then(|g| g.get(..2)).map(str::to_owned),
                MultKind::Grid4 => it.their_grid.as_ref().and_then(|g| g.get(..4)).map(str::to_owned),
                MultKind::MyGrid4 => it.my_grid.as_ref().and_then(|g| g.get(..4)).map(str::to_owned),
                MultKind::CallArea(t) => self.s.file.call_area(t, &it.call),
                MultKind::Exchange(f) => it.fields.as_ref().and_then(|q| q.field(f)),
                MultKind::Call => Some(it.call.clone()),
            };
            let Some(key) = key else { continue };
            let round = it.round.map_or("-".into(), |r| r.to_string());
            let scoped = match m.per {
                Per::Contest => key,
                Per::Band => format!("{key}|{}", it.band),
                Per::BandMode => format!("{key}|{}|{}", it.band, it.mode),
                Per::Round => format!("{key}|r{round}"),
                Per::BandRound => format!("{key}|{}|r{round}", it.band),
            };
            out.push((i, scoped));
        }
        out
    }
}
/// A QSO dupes an earlier one: the same call and every dimension equal (a grid missing on
/// either side matches every grid).
fn dupes(per: &[Dim], a: &[Option<String>], b: &[Option<String>]) -> bool {
    per.iter().enumerate().all(|(i, d)| match (&a[i], &b[i]) {
        (Some(x), Some(y)) => x == y,
        _ => d.grid(),
    })
}
impl Log {
    /// Builds the state from the contacts that started in the period (any order), with the
    /// station's call and locator for my side.
    pub(crate) fn of(
        s: &Selection,
        my_call: Option<&str>,
        my_locator: Option<&str>,
        dxcc: &crate::dxcc::Table,
        list: &[Qso],
    ) -> Self {
        let me = Me::new(s, dxcc, my_call, my_locator);
        let p = &s.profile;
        let mut log = Log {
            sets: vec![HashSet::new(); p.multipliers.len()],
            names: p.multipliers.iter().map(|m| m.name.clone()).collect(),
            ..Log::default()
        };
        let mut ordered: Vec<&Qso> = list
            .iter()
            .filter(|q| q.ms >= s.start_ms && q.ms < s.end_ms)
            .collect();
        ordered.sort_by_key(|q| q.ms);
        // Dupes, in time order (keep best: the most points of QSOs that dupe each other).
        let mut kept: Vec<Item> = Vec::new();
        for q in ordered {
            let Some(band) = q.band.as_deref().filter(|b| s.has_band(b)) else {
                continue;
            };
            let Some(mode) = p.modes.counted(&q.mode, q.submode.as_deref()) else {
                continue;
            };
            if let Some(n) = q.stx.as_deref().and_then(|x| x.trim().parse::<u64>().ok()) {
                log.max_stx = Some(log.max_stx.map_or(n, |m| m.max(n)));
            }
            let it = me.item(q, band, mode);
            let earlier = kept
                .iter()
                .position(|k| k.call == it.call && dupes(&p.dupe.per, &k.dupe_key, &it.dupe_key));
            match earlier {
                None => kept.push(it),
                Some(i) if p.dupe.best && it.raw > kept[i].raw => {
                    kept.remove(i);
                    kept.push(it);
                }
                Some(_) => {}
            }
        }
        kept.sort_by_key(|k| k.ms);
        for k in &kept {
            log.keys
                .entry(k.call.clone())
                .or_default()
                .push(k.dupe_key.clone());
        }
        // ScoredWindow.
        let scores = log.window(s, &kept);
        // points_cap over the period.
        let scoring: Vec<&Item> = kept
            .iter()
            .zip(&scores)
            .filter_map(|(k, ok)| ok.then_some(k))
            .collect();
        let cap = p.points_cap.as_ref().map(|c| {
            let allowed = scoring.len() as u64 * c.n / c.d;
            (c, allowed)
        });
        for it in scoring {
            let mut points = it.raw;
            if let Some((c, allowed)) = &cap
                && c.when.holds(&me.vars(it, false))
            {
                if log.capped_kept < *allowed {
                    log.capped_kept += 1;
                } else {
                    points = 0.0;
                }
            }
            let added = log.add_keys(&me, it, p);
            log.qsos += 1;
            log.points += points;
            log.scoring.push((it.ms, points, added));
        }
        log
    }
    /// Which non-dupe QSOs score (ScoredWindow); tracks the operating time for the value.
    fn window(&mut self, s: &Selection, kept: &[Item]) -> Vec<bool> {
        let p = &s.profile;
        let Some(w) = &p.schedule.window else {
            if let Some(last) = kept.last() {
                self.last_ms = Some(last.ms);
            }
            return vec![true; kept.len()];
        };
        let limit = p.window_limit(&s.entry).unwrap_or(f64::INFINITY);
        if w.best {
            let unit = if w.utc_day { DAY_MS } else { 3_600_000 };
            let mut per: BTreeMap<i64, f64> = BTreeMap::new();
            for k in kept {
                *per.entry(k.ms.div_euclid(unit)).or_default() += k.raw;
            }
            let mut units: Vec<(i64, f64)> = per.into_iter().collect();
            // The most points first; a tie goes to the earlier unit.
            units.sort_by(|a, b| b.1.total_cmp(&a.1).then(a.0.cmp(&b.0)));
            let chosen: HashSet<i64> = units
                .iter()
                .take(limit.max(0.0) as usize)
                .map(|u| u.0)
                .collect();
            return kept
                .iter()
                .map(|k| chosen.contains(&k.ms.div_euclid(unit)))
                .collect();
        }
        let off = w.min_off_minutes * MINUTE_MS;
        let limit_ms = (limit * 3_600_000.0) as i64;
        let mut out = Vec::new();
        for k in kept {
            if let Some(prev) = self.last_ms {
                let gap = k.ms - prev;
                if off == 0 || gap < off {
                    self.operating_ms += gap;
                }
            }
            self.last_ms = Some(k.ms);
            out.push(self.operating_ms <= limit_ms);
        }
        out
    }
    /// Adds a scoring QSO's multiplier keys; returns how many each set gained.
    fn add_keys(&mut self, me: &Me, it: &Item, p: &Profile) -> Vec<usize> {
        let mut added = vec![0; p.multipliers.len()];
        for (i, key) in me.mult_keys(it) {
            let m = &p.multipliers[i];
            if m.all_bands {
                let cover = self.band_cover.entry((i, key.clone())).or_default();
                cover.insert(it.band.clone());
                if !p.bands.iter().all(|b| cover.contains(b)) {
                    continue;
                }
            }
            if self.sets[i].insert(key) {
                added[i] += 1;
            }
        }
        added
    }
    /// DupeRule: a decoded station on this band, mode and grid is a dupe of the period.
    fn is_dupe(&self, s: &Selection, it: &Item) -> bool {
        self.keys
            .get(&it.call)
            .is_some_and(|l| l.iter().any(|k| dupes(&s.profile.dupe.per, k, &it.dupe_key)))
    }
    pub(crate) fn multipliers(&self) -> usize {
        self.sets.iter().map(HashSet::len).sum()
    }
    /// The totals now (Z without projection).
    fn totals(&self) -> Totals {
        Totals {
            qsos: self.qsos as f64,
            points: self.points,
            sets: self.sets.iter().map(|s| s.len() as f64).collect(),
        }
    }
    /// ScoreRule on the totals now.
    pub(crate) fn score(&self, s: &Selection) -> f64 {
        score(s, &self.names, &self.totals())
    }
    pub(crate) fn summary(&self, s: &Selection) -> Value {
        json!({"qsos":self.qsos,"multipliers":self.multipliers(),"points":half_up(self.points),
            "score":half_up(self.score(s))})
    }
    /// ContestSerial: the next serial number (1 + the highest STX of the period, 1 for none).
    pub(crate) fn next_serial(&self) -> u64 {
        self.max_stx.map_or(1, |m| m + 1)
    }
}
/// Rounded half up, as the wire carries points and values.
pub(crate) fn half_up(x: f64) -> i64 {
    (x + 0.5).floor() as i64
}
/// The totals a score is computed on.
#[derive(Clone, Debug, PartialEq)]
struct Totals {
    qsos: f64,
    points: f64,
    sets: Vec<f64>,
}
fn score(s: &Selection, names: &[String], t: &Totals) -> f64 {
    let sizes: BTreeMap<String, f64> = names.iter().cloned().zip(t.sets.iter().copied()).collect();
    s.profile
        .score
        .number(&Vars {
            qsos: t.qsos,
            points: t.points,
            sets_sizes: Some(&sizes),
            ..Vars::default()
        })
        .unwrap_or(0.0)
}

// ------------------------------------------------------------------ the value
/// What a verdict adds in a contest (Verdict contest keys).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub(crate) struct ContestValue {
    pub dupe: bool,
    pub new_multiplier: bool,
    /// PointsRule for this QSO now (None: not known).
    pub points: Option<f64>,
    /// ContestValue, the projected score gain (None without a rank).
    pub value: Option<f64>,
}
/// ContestValue: the projected end state of the period at `now_ms` (Z) and its score.
fn projected(s: &Selection, log: &Log, now_ms: i64) -> (Totals, bool) {
    let e = ((now_ms - s.start_ms) as f64 / MINUTE_MS as f64).max(0.0);
    let span = e.min(60.0);
    let w = e.clamp(15.0, 60.0).max(15.0);
    let mut t = (s.end_ms - now_ms).max(0) as f64 / MINUTE_MS as f64;
    let mut used_up = false;
    if let (Some(win), Some(limit)) = (&s.profile.schedule.window, s.profile.window_limit(&s.entry))
        && !win.best
    {
        // A first window: at most the operating time it has left; 0 once used up.
        let mut op = log.operating_ms;
        if let Some(last) = log.last_ms {
            let gap = now_ms - last;
            if win.min_off_minutes == 0 || gap < win.min_off_minutes * MINUTE_MS {
                op += gap.max(0);
            }
        }
        let left = limit * 60.0 - op as f64 / MINUTE_MS as f64;
        used_up = left < 0.0;
        t = t.min(left.max(0.0));
    }
    let from = now_ms - (span * MINUTE_MS as f64) as i64;
    let mut g = Totals {
        qsos: 0.0,
        points: 0.0,
        sets: vec![0.0; log.sets.len()],
    };
    for (ms, points, added) in &log.scoring {
        if *ms > from && *ms <= now_ms {
            g.qsos += 1.0;
            g.points += points;
            for (i, a) in added.iter().enumerate() {
                g.sets[i] += *a as f64;
            }
        }
    }
    let now = log.totals();
    let z = Totals {
        qsos: now.qsos + g.qsos / w * t,
        points: now.points + g.points / w * t,
        sets: now
            .sets
            .iter()
            .zip(&g.sets)
            .map(|(x, gx)| x + gx / w * t)
            .collect(),
    };
    (z, used_up)
}
/// One decoded station as a hypothetical QSO now.
fn decoded_item(me: &Me, st: &Station, f: &Facts, band: &str) -> Item {
    let mode = st.mode.to_ascii_uppercase();
    let mut it = Item {
        call: f.from.to_ascii_uppercase(),
        ms: st.now_ms,
        band: band.to_owned(),
        class: ModeClass::Digital,
        round: me.s.profile.schedule.round_at(st.now_ms),
        my_grid: me.station_grid.clone(),
        their_grid: upper(f.grid.as_deref()),
        their: st.dxcc.lookup(&f.from),
        fields: None,
        raw: 0.0,
        dupe_key: Vec::new(),
        mode,
    };
    it.dupe_key = me.dupe_key(&it);
    it
}
/// The value of a hypothetical QSO with this station now: S(Z + q) - S(Z).
fn value_of(me: &Me, log: &Log, it: &Item, now_ms: i64) -> (f64, Option<f64>, bool) {
    let s = me.s;
    let p = &s.profile;
    let logged = p.points.number(&me.vars(it, false));
    let estimate = p.points.number(&me.vars(it, true)).unwrap_or(0.0);
    let (z, used_up) = projected(s, log, now_ms);
    // The cap: a capped QSO keeps its points while the cap of N + 1 scoring QSOs allows it.
    let mut points = estimate;
    if let Some(c) = &p.points_cap
        && c.when.holds(&me.vars(it, false))
        && log.capped_kept >= (log.qsos + 1) * c.n / c.d
    {
        points = 0.0;
    }
    let mut added = vec![0.0; p.multipliers.len()];
    let mut new_multiplier = false;
    for (i, key) in me.mult_keys(it) {
        let m = &p.multipliers[i];
        if log.sets[i].contains(&key) {
            continue;
        }
        if m.all_bands {
            let cover = log.band_cover.get(&(i, key.clone()));
            let complete = p
                .bands
                .iter()
                .all(|b| *b == it.band || cover.is_some_and(|c| c.contains(b)));
            if !complete {
                continue;
            }
        }
        added[i] += 1.0;
        new_multiplier = true;
    }
    if used_up {
        return (0.0, logged, new_multiplier);
    }
    let mut with = z.clone();
    with.qsos += 1.0;
    with.points += points;
    for (x, a) in with.sets.iter_mut().zip(&added) {
        *x += a;
    }
    let gain = score(s, &log.names, &with) - score(s, &log.names, &z);
    (gain.max(0.0), logged, new_multiplier)
}

// ------------------------------------------------------------------ the verdicts
/// One record's classification (WstxContest::ContestVerdict): kind, grey, why and the value.
fn classify(
    s: &Selection,
    f: &Facts,
    st: &Station,
    log: Option<&Log>,
) -> (Option<Kind>, bool, String, Option<ContestValue>) {
    let p = &s.profile;
    if let Some(tier) = st.ignored.get(&f.from) {
        return (
            None,
            false,
            format!("{} is ignored ({} list)", f.from, tier.name()),
            None,
        );
    }
    if st.greyed(f) {
        return (None, true, st.directive_text(f), None);
    }
    if f.from == st.my_call {
        return (None, false, "my own message".to_owned(), None);
    }
    let Some(band) = st.band.as_deref() else {
        return (None, false, "band unknown".to_owned(), None);
    };
    if !s.has_band(band) {
        return (None, false, "band not in the contest".to_owned(), None);
    }
    if !p.modes.counts_station(&st.mode) {
        return (None, false, "mode not in the contest".to_owned(), None);
    }
    let Some(log) = log else {
        return (None, false, "log unreadable".to_owned(), None);
    };
    let me = Me::new(s, &st.dxcc, Some(&st.my_call), st.my_locator.as_deref());
    let it = decoded_item(&me, st, f, band);
    if let Some(w) = &p.entry.workable
        && !w.holds(&me.vars(&it, false))
    {
        return (None, false, "not workable".to_owned(), None);
    }
    if log.is_dupe(s, &it) {
        let value = ContestValue {
            dupe: true,
            ..ContestValue::default()
        };
        return (None, false, "dupe".to_owned(), Some(value));
    }
    let rover = p.dupe.per.contains(&Dim::TheirGrid4);
    let call_guard = if rover {
        // A rover counts again from a new grid (AVHF 2.2).
        f.from.trim_end_matches("/R")
    } else {
        f.from.as_str()
    };
    let calls_me = st.calls_me(f);
    let (gain, points, new_multiplier) = value_of(&me, log, &it, st.now_ms);
    if !calls_me {
        if !sane_call(call_guard) {
            return (None, false, "callsign guard".to_owned(), None);
        }
        if !st.cq_like(f, true) {
            return (None, false, "not a CQ".to_owned(), None);
        }
        if gain <= 0.0 {
            let value = ContestValue {
                dupe: false,
                new_multiplier,
                points,
                value: None,
            };
            return (None, false, "no score".to_owned(), Some(value));
        }
    }
    let value = ContestValue {
        dupe: false,
        new_multiplier,
        points,
        value: Some(gain),
    };
    let mut why = if calls_me {
        vec!["calls my call".to_owned()]
    } else {
        Vec::new()
    };
    if value.new_multiplier {
        why.push("new multiplier".to_owned());
    }
    if let Some(n) = value.points {
        why.push(format!("{} points", half_up(n)));
    }
    why.push(format!("value {}", half_up(gain)));
    (
        Some(if calls_me {
            Kind::Caller
        } else {
            Kind::Candidate
        }),
        false,
        why.join(" \u{b7} "),
        Some(value),
    )
}
/// What the evaluator reads of a record: a standard one, or a Field Day exchange to a call (its
/// own message type; ContestVerdict).
fn record_facts(record: &Value) -> Option<Facts> {
    let f = &record["fields"];
    if record["status"] != "decoded" || f["type"] != "field_day" {
        return crate::strategy::facts(record);
    }
    if f["from"]["kind"] != "call" || f["to"]["kind"] != "call" {
        return None;
    }
    Some(Facts {
        sequence: record["sequence"].as_u64()?,
        from: f["from"]["text"].as_str()?.to_owned(),
        to_call: f["to"]["text"].as_str().map(str::to_owned),
        cq: false,
        target: None,
        signoff: false,
        grid: None,
        snr: record["snr_db"].as_f64(),
        hz: record["frequency_hz"].as_f64(),
    })
}
/// WstxContest::ContestValueOrder, smaller first: callers of my call (while callers first is
/// on: always before #97), then the larger value, the stronger SNR, then for an exact tie only
/// the lower audio frequency and the call.
pub(crate) fn order(a: &Verdict, b: &Verdict) -> std::cmp::Ordering {
    let caller = |v: &Verdict| v.kind != Some(Kind::Caller);
    let value = |v: &Verdict| -v.contest.and_then(|c| c.value).unwrap_or(0.0);
    caller(a)
        .cmp(&caller(b))
        .then_with(|| value(a).total_cmp(&value(b)))
        .then_with(|| {
            let snr = |v: &Verdict| v.facts.snr.map_or(f64::INFINITY, |s| -s);
            snr(a).total_cmp(&snr(b))
        })
        // An exact tie only: the lower audio frequency, then the call; never decode order.
        .then_with(|| crate::strategy::exact_tie(&a.facts, &b.facts))
}
/// WstxContest::ContestVerdict: in display order, by ContestValueOrder.
pub(crate) fn evaluate(
    s: &Selection,
    records: &[Value],
    st: &Station,
    log: Option<&Log>,
) -> Vec<Verdict> {
    let (mut ranked, rest): (Vec<Verdict>, Vec<Verdict>) = records
        .iter()
        .filter_map(record_facts)
        .map(|f| {
            let (kind, grey, why, contest) = classify(s, &f, st, log);
            Verdict {
                facts: f,
                rank: None,
                grey,
                why,
                kind,
                contest,
            }
        })
        .partition(|v| v.kind.is_some());
    ranked.sort_by(order);
    ranked
        .iter_mut()
        .enumerate()
        .for_each(|(i, v)| v.rank = Some(i));
    ranked.extend(rest);
    ranked
}
