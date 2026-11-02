#![forbid(unsafe_code)]
//! WstxDxcc (#55): the AD1C cty.dat country table and the WSJT-X entity resolution of a
//! call (logbook/AD1CCty.cpp lookup, Radio.cpp effective_prefix), plus the WSJT-X
//! "new DXCC / continent / CQ zone / ITU zone" status of an entity against the log
//! (logbook/WorkedBefore.cpp, highlight by mode off as in the WSJT-X default).
//! The bundled file is `server/third-party/cty/cty.dat`; an uploaded file replaces it
//! per station profile (`cty.dat` beside contacts.adi).
use serde_json::{Value, json};
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, OnceLock};

#[cfg(test)]
#[path = "dxcc_tests.rs"]
mod tests;

pub const FILE_NAME: &str = "cty.dat";
/// An uploaded cty.dat is at most this large (the shipped file is 354405 bytes; AD1C's
/// big variant is below 1 MiB as well).
pub const FILE_BYTES_MAX: usize = 1_048_576;
const BUNDLED: &str = include_str!("../third-party/cty/cty.dat");
pub const CONTINENTS: [&str; 7] = ["AF", "AN", "AS", "EU", "NA", "OC", "SA"];

#[derive(Debug)]
struct Entity {
    name: String,
    display: String,
    prefix: String,
    cq: u8,
    itu: u8,
    continent: &'static str,
    lat: f64,
    /// Degrees, positive West (cty.dat convention).
    lon_west: f64,
}
#[derive(Debug, Clone, Default, PartialEq)]
struct Overrides {
    cq: Option<u8>,
    itu: Option<u8>,
    continent: Option<&'static str>,
    position: Option<(f64, f64)>,
}
#[derive(Debug)]
struct Prefix {
    exact: bool,
    entity: usize,
    overrides: Overrides,
}
/// One resolved call: the entity of the matching cty.dat entry with that entry's
/// overrides applied (AD1CCty::Record).
#[derive(Debug, Clone, PartialEq)]
pub struct Resolved {
    /// The full cty.dat entity name (WSJT-X compares worked status by it, WAE included).
    pub name: String,
    /// The name as WSJT-X shows it: abbreviated, WAE entities shown as their DXCC.
    pub display: String,
    pub prefix: String,
    pub continent: &'static str,
    pub cq_zone: u8,
    pub itu_zone: u8,
    pub lat: f64,
    /// Degrees, positive East.
    pub lon: f64,
}

pub struct Cty {
    entities: Vec<Entity>,
    prefixes: HashMap<String, Prefix>,
    version: Option<String>,
}
impl std::fmt::Debug for Cty {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "Cty({:?}, {} entities)",
            self.version,
            self.entities.len()
        )
    }
}

/// WSJT-X AD1CCty::impl::abbreviated_entity_name, the same replacements in order.
fn abbreviated(name: &str) -> String {
    let mut s = name.to_owned();
    for (from, to) in [
        ("Islands", "Is."),
        ("Island", "Is."),
        ("North ", "N. "),
        ("Northern ", "N. "),
        ("South ", "S. "),
        ("East ", "E. "),
        ("Eastern ", "E. "),
        ("West ", "W. "),
        ("Western ", "W. "),
        ("Central ", "C. "),
        (" and ", " & "),
        ("Republic", "Rep."),
        ("United States of America", "U.S.A."),
        ("United States", "U.S.A."),
        ("Fed. Rep. of ", ""),
        ("French ", "Fr."),
        ("Asiatic", "AS"),
        ("European", "EU"),
        ("African", "AF"),
    ] {
        s = s.replace(from, to);
    }
    // displaytext.cpp with "Include extra WAE entities" off (the WSJT-X default).
    for (from, to) in [
        ("Bear Is.", "Svalbard"),
        ("Shetland Is.", "Scotland"),
        ("AF Italy", "Italy"),
        ("Sicily", "Italy"),
        ("Vienna Intl Ctr", "Austria"),
        ("AF Turkey", "Turkey"),
        ("EU Turkey", "Turkey"),
    ] {
        s = s.replace(from, to);
    }
    s
}
fn continent(code: &str) -> Option<&'static str> {
    CONTINENTS.iter().copied().find(|c| *c == code)
}
/// The text between `open` and `close` after the first `open` (AD1CCty override_value).
fn between(s: &str, open: char, close: char) -> Option<&str> {
    let start = s.find(open)? + 1;
    let rest = &s[start..];
    Some(rest.find(close).map_or(rest, |end| &rest[..end]))
}
fn overrides(entry: &str) -> Option<Overrides> {
    let zone = |v: &str| v.trim().parse::<u8>().ok();
    let mut o = Overrides::default();
    if let Some(v) = between(entry, '(', ')') {
        o.cq = Some(zone(v)?);
    }
    if let Some(v) = between(entry, '[', ']') {
        o.itu = Some(zone(v)?);
    }
    if let Some(v) = between(entry, '<', '>') {
        let (lat, lon) = v.split_once('/')?;
        o.position = Some((lat.trim().parse().ok()?, lon.trim().parse().ok()?));
    }
    if let Some(v) = between(entry, '{', '}') {
        o.continent = Some(continent(v)?);
    }
    if let Some(v) = between(entry, '~', '~') {
        v.trim().parse::<f64>().ok()?; // UTC offset: validated, not used here.
    }
    Some(o)
}

impl Cty {
    /// AD1CCty::impl::load_cty. Entity lines `name: cq: itu: cont: lat: lon: utc: prefix:`
    /// (a leading `*` marks a WAE-only entity) are followed by comma-separated entries up
    /// to `;`; `=` marks an exact call; `(cq)[itu]<lat/lon>{cont}~utc~` override the
    /// entity for that entry. The first entry of a key wins. Any invalid number or
    /// continent refuses the whole file (WSJT-X throws), naming the line.
    pub fn parse(text: &str) -> Result<Self, usize> {
        let mut entities = Vec::new();
        let mut prefixes = HashMap::new();
        let mut version = None;
        let mut lines = text.lines().enumerate().peekable();
        while let Some((number, line)) = lines.next() {
            let parts: Vec<&str> = line.split(':').collect();
            if parts.len() < 8 {
                continue; // WSJT-X skips a line that is no entity line.
            }
            let num = |i: usize| parts[i].trim().parse::<f64>().ok();
            let zone = |i: usize| parts[i].trim().parse::<u8>().ok();
            let primary = parts[7].trim();
            let entity = (|| {
                Some(Entity {
                    name: parts[0].trim().to_owned(),
                    display: abbreviated(parts[0].trim()),
                    prefix: primary.strip_prefix('*').unwrap_or(primary).to_owned(),
                    cq: zone(1)?,
                    itu: zone(2)?,
                    continent: continent(parts[3].trim())?,
                    lat: num(4)?,
                    lon_west: num(5)?,
                })
            })()
            .filter(|_| num(6).is_some() && !primary.is_empty())
            .ok_or(number + 1)?;
            let mut detail = String::new();
            loop {
                let Some((_, next)) = lines.next() else {
                    return Err(number + 1);
                };
                detail.push_str(next.trim_end());
                if detail.ends_with(';') {
                    break;
                }
            }
            detail.pop();
            let id = entities.len();
            for entry in detail.split(',') {
                let entry = entry.trim();
                let (exact, entry) = match entry.strip_prefix('=') {
                    Some(call) => (true, call),
                    None => (false, entry),
                };
                let key = &entry[..entry.find(['(', '{', '[', '<', '~']).unwrap_or(entry.len())];
                if key.is_empty() {
                    continue; // never searched (AD1CCty::lookup stops at an empty prefix)
                }
                if exact
                    && key.len() == 11
                    && key.starts_with("VER")
                    && key[3..].bytes().all(|b| b.is_ascii_digit())
                {
                    version = Some(key.to_owned());
                }
                let overrides = overrides(entry).ok_or(number + 1)?;
                prefixes.entry(key.to_ascii_uppercase()).or_insert(Prefix {
                    exact,
                    entity: id,
                    overrides,
                });
            }
            entities.push(entity);
        }
        if entities.is_empty() {
            return Err(1);
        }
        Ok(Self {
            entities,
            prefixes,
            version,
        })
    }
    /// The file's `=VERyyyymmdd` marker, if any.
    pub fn version(&self) -> Option<&str> {
        self.version.as_deref()
    }
    pub fn entity_count(&self) -> usize {
        self.entities.len()
    }
    fn resolve(&self, p: &Prefix, call: &str) -> Resolved {
        // AD1CCty lookup_entity: KG4 2x1 and 2x3 calls are mainland US, not Guantanamo.
        let id = if call.starts_with("KG4") && call.len() != 5 && call.len() != 3 {
            self.entities
                .iter()
                .position(|e| e.prefix == "K")
                .unwrap_or(p.entity)
        } else {
            p.entity
        };
        let e = &self.entities[id];
        let o = &p.overrides;
        let (lat, lon_west) = o.position.unwrap_or((e.lat, e.lon_west));
        Resolved {
            name: e.name.clone(),
            display: e.display.clone(),
            prefix: e.prefix.clone(),
            continent: o.continent.unwrap_or(e.continent),
            cq_zone: o.cq.unwrap_or(e.cq),
            itu_zone: o.itu.unwrap_or(e.itu),
            lat,
            lon: -lon_west,
        }
    }
    /// AD1CCty::lookup: /MM and /AM have no entity; a compound call whose full text is an
    /// exact entry resolves by it; otherwise the longest matching entry of the effective
    /// prefix, where an exact entry only matches the whole call.
    pub fn lookup(&self, call: &str) -> Option<Resolved> {
        let call = call.trim().to_ascii_uppercase();
        if call.is_empty() || call.ends_with("/MM") || call.ends_with("/AM") {
            return None;
        }
        let mut search = effective_prefix(&call);
        if search != call
            && let Some(p) = self.prefixes.get(&call).filter(|p| p.exact)
        {
            return Some(self.resolve(p, &call));
        }
        while !search.is_empty() {
            if let Some(p) = self.prefixes.get(search)
                && (!p.exact || call.len() == search.len())
            {
                return Some(self.resolve(p, &call));
            }
            search = &search[..search.len() - 1];
        }
        None
    }
}

/// Radio.cpp: a trailing /x is an operating suffix, not a DXCC prefix, when x is a digit,
/// A, M, P, Q, R, QRP, FD, FF, AM, MM, LH, LT or LGT.
fn operating_suffix(s: &str) -> bool {
    matches!(s, "QRP" | "FD" | "FF" | "AM" | "MM" | "LH" | "LT" | "LGT")
        || (s.len() == 1
            && matches!(
                s.as_bytes()[0],
                b'0'..=b'9' | b'A' | b'M' | b'P' | b'Q' | b'R'
            ))
}
/// Radio::effective_prefix: the operating suffixes removed, the shorter side of a
/// compound call (the left one when both are equally long), else the whole call.
pub fn effective_prefix(call: &str) -> &str {
    let mut call = call;
    while let Some(slash) = call.rfind('/') {
        if !operating_suffix(&call[slash + 1..]) {
            break;
        }
        call = &call[..slash];
    }
    match call.find('/') {
        Some(slash) if call.len() - slash > slash => &call[..slash],
        Some(slash) => &call[slash + 1..],
        None => call,
    }
}

/// The table in use: the bundled file unless a profile's upload replaced it.
#[derive(Clone, Debug)]
pub struct Table {
    pub cty: Arc<Cty>,
    pub uploaded: bool,
}
impl Default for Table {
    fn default() -> Self {
        static BUNDLED_TABLE: OnceLock<Arc<Cty>> = OnceLock::new();
        Self {
            cty: BUNDLED_TABLE
                .get_or_init(|| Arc::new(Cty::parse(BUNDLED).expect("bundled cty.dat parses")))
                .clone(),
            uploaded: false,
        }
    }
}
impl Table {
    pub fn uploaded(cty: Cty) -> Self {
        Self {
            cty: Arc::new(cty),
            uploaded: true,
        }
    }
    pub fn lookup(&self, call: &str) -> Option<Resolved> {
        self.cty.lookup(call)
    }
    /// The continent of a call's entity.
    pub fn continent(&self, call: &str) -> Option<&'static str> {
        self.lookup(call).map(|r| r.continent)
    }
}

/// WSJT-X decode highlighting categories that need the entity, each ever and on this
/// band (the names of the decoded-record flags).
pub const NEW_FLAGS: [&str; 8] = [
    "new_dxcc",
    "new_dxcc_band",
    "new_continent",
    "new_continent_band",
    "new_cq_zone",
    "new_cq_zone_band",
    "new_itu_zone",
    "new_itu_zone_band",
];
/// What the log holds per category, ever and per band (WorkedBefore with highlight by
/// mode off): entity names, continents and zones of the logged calls.
#[derive(Default)]
pub struct Worked {
    ever: HashSet<(u8, String)>,
    band: HashSet<(u8, String, String)>,
}
impl Worked {
    /// `logged`: (call, band in lower case) of each logged contact. A call without an
    /// entity counts for nothing (WSJT-X stores an empty name and never matches it).
    pub fn from_log(table: &Table, logged: &[(String, Option<String>)]) -> Self {
        let mut w = Self::default();
        for (call, band) in logged {
            let Some(r) = table.lookup(call) else {
                continue;
            };
            for (i, key) in keys(&r).into_iter().enumerate() {
                w.ever.insert((i as u8, key.clone()));
                if let Some(b) = band {
                    w.band.insert((i as u8, key, b.clone()));
                }
            }
        }
        w
    }
    /// The NEW_FLAGS that hold for this entity; the band flags only with a known band.
    pub fn new_flags(&self, r: &Resolved, band: Option<&str>) -> Vec<&'static str> {
        let band = band.map(str::to_ascii_lowercase);
        let mut out = Vec::new();
        for (i, key) in keys(r).into_iter().enumerate() {
            let i = i as u8;
            if !self.ever.contains(&(i, key.clone())) {
                out.push(NEW_FLAGS[2 * i as usize]);
            }
            if let Some(b) = &band
                && !self.band.contains(&(i, key, b.clone()))
            {
                out.push(NEW_FLAGS[2 * i as usize + 1]);
            }
        }
        out
    }
}
fn keys(r: &Resolved) -> [String; 4] {
    [
        r.name.clone(),
        r.continent.to_owned(),
        r.cq_zone.to_string(),
        r.itu_zone.to_string(),
    ]
}

/// The compact entity of a call as the browser shows it: {name (as WSJT-X shows it),
/// cont, cq, itu, km (great circle from my locator to the entity position; only with a
/// locator)}.
pub fn compact(r: &Resolved, me: Option<(f64, f64)>) -> Value {
    let mut v = json!({"name":r.display,"cont":r.continent,"cq":r.cq_zone,"itu":r.itu_zone});
    if let Some(m) = me {
        v["km"] = json!(crate::strategy::great_circle(m, (r.lat, r.lon)).0 as u32);
    }
    v
}

/// #55 DecodedEntity: adds to each decoded standard record with a resolved sender its
/// `dxcc` (compact, when the call has an entity) and `flags` (only the flags that hold:
/// new_call/new_grid ever and on this band and mode, and the NEW_FLAGS ever and on this
/// band; omitted when none holds or the log is unreadable). Band: the CAT dial band, else
/// the operating selection band; without a band no `_band` flag is set.
pub(crate) fn annotate(state: &crate::ProfileState, records: &mut [Value]) {
    if !records.iter().any(|r| crate::strategy::facts(r).is_some()) {
        return;
    }
    let st = crate::strategy::station(state, &Default::default(), records);
    let worked = state
        .logbook
        .logged_bands()
        .ok()
        .map(|l| Worked::from_log(&st.dxcc, &l));
    let me = st.my_grid.as_deref().and_then(crate::strategy::maidenhead);
    let band = st.band.as_deref();
    for record in records.iter_mut() {
        let Some(f) = crate::strategy::facts(record) else {
            continue;
        };
        let entity = st.dxcc.lookup(&f.from);
        let mut flags = serde_json::Map::new();
        if let Some(w) = &worked {
            let mut set = |name: &str| {
                flags.insert(name.to_owned(), Value::Bool(true));
            };
            let (ever, here) = st.calls.get(&f.from).copied().unwrap_or_default();
            let grid = f.grid.as_ref().map(|g| {
                st.grids
                    .get(&g[..4].to_ascii_uppercase())
                    .copied()
                    .unwrap_or_default()
            });
            for (prefix, worked) in [("new_call", Some((ever, here))), ("new_grid", grid)] {
                let Some((ever, here)) = worked else { continue };
                if !ever {
                    set(prefix);
                }
                if band.is_some() && !here {
                    set(&format!("{prefix}_band"));
                }
            }
            if let Some(r) = &entity {
                for name in w.new_flags(r, band) {
                    set(name);
                }
            }
        }
        if let Some(r) = &entity {
            record["dxcc"] = compact(r, me);
        }
        if !flags.is_empty() {
            record["flags"] = Value::Object(flags);
        }
    }
}
