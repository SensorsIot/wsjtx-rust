#![forbid(unsafe_code)]
//! WstxDxcc (#55): the AD1C cty.dat country table and the WSJT-X entity resolution of a
//! call (logbook/AD1CCty.cpp lookup, Radio.cpp effective_prefix), plus the WSJT-X
//! "new DXCC / continent / CQ zone / ITU zone" status of an entity against the log
//! (logbook/WorkedBefore.cpp, highlight by mode off as in the WSJT-X default).
//! The bundled file is `server/third-party/cty/cty.dat`; an uploaded file replaces it
//! per station profile (`cty.dat` beside contacts.adi).
use serde_json::{Value, json};
use std::collections::HashMap;
use std::collections::HashSet;
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
/// Zone ranges the browser accepts (CQ zones 1..40, ITU zones 1..90; 0 tolerated).
const CQ_MAX: u8 = 40;
const ITU_MAX: u8 = 90;
fn zone(v: &str, max: u8) -> Option<u8> {
    v.trim().parse::<u8>().ok().filter(|z| *z <= max)
}
/// A shown name the browser accepts: 1..40 printable ASCII characters.
fn shown(name: &str) -> bool {
    (1..=40).contains(&name.len()) && name.bytes().all(|b| (0x20..0x7f).contains(&b))
}
fn overrides(entry: &str) -> Option<Overrides> {
    let mut o = Overrides::default();
    if let Some(v) = between(entry, '(', ')') {
        o.cq = Some(zone(v, CQ_MAX)?);
    }
    if let Some(v) = between(entry, '[', ']') {
        o.itu = Some(zone(v, ITU_MAX)?);
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
        let mut lines = text.lines().enumerate();
        while let Some((number, line)) = lines.next() {
            let parts: Vec<&str> = line.split(':').collect();
            if parts.len() < 8 {
                continue; // WSJT-X skips a line that is no entity line.
            }
            let num = |i: usize| parts[i].trim().parse::<f64>().ok();
            let primary = parts[7].trim();
            let entity = (|| {
                Some(Entity {
                    name: parts[0].trim().to_owned(),
                    display: abbreviated(parts[0].trim()),
                    prefix: primary.strip_prefix('*').unwrap_or(primary).to_owned(),
                    cq: zone(parts[1], CQ_MAX)?,
                    itu: zone(parts[2], ITU_MAX)?,
                    continent: continent(parts[3].trim())?,
                    lat: num(4)?,
                    lon_west: num(5)?,
                })
            })()
            .filter(|e| num(6).is_some() && !primary.is_empty() && shown(&e.display))
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
    /// The entity full names (the Most Wanted mapping's test; #97 CountryList names).
    pub fn entity_names(&self) -> impl Iterator<Item = &str> {
        self.entities.iter().map(|e| e.name.as_str())
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
        // Calls are ASCII (a logged ADIF call need not be): no entity otherwise.
        if call.is_empty() || !call.is_ascii() || call.ends_with("/MM") || call.ends_with("/AM") {
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
    /// WstxValueOrder::MyContinent's locator fallback: the continent of the entity whose
    /// cty.dat centre is nearest to this point (lat, lon east), by the haversine term.
    pub fn nearest_continent(&self, (lat, lon): (f64, f64)) -> Option<&'static str> {
        let rad = std::f64::consts::PI / 180.0;
        let term = |e: &Entity| {
            let dlat = (e.lat - lat) * rad;
            let dlon = (-e.lon_west - lon) * rad;
            (dlat / 2.0).sin().powi(2)
                + (lat * rad).cos() * (e.lat * rad).cos() * (dlon / 2.0).sin().powi(2)
        };
        self.cty
            .entities
            .iter()
            .min_by(|a, b| term(a).total_cmp(&term(b)))
            .map(|e| e.continent)
    }
}

/// The WSJT-X decode highlighting categories as decoded-record flags, each ever and on
/// this band: call, 4-character grid, DXCC entity, continent, CQ zone, ITU zone.
pub const FLAGS: [&str; 12] = [
    "new_call",
    "new_call_band",
    "new_grid",
    "new_grid_band",
    "new_dxcc",
    "new_dxcc_band",
    "new_continent",
    "new_continent_band",
    "new_cq_zone",
    "new_cq_zone_band",
    "new_itu_zone",
    "new_itu_zone_band",
];
/// One logged contact as the worked set reads it.
pub struct Logged {
    pub call: String,
    pub grid: Option<String>,
    /// ADIF band, lower case.
    pub band: Option<String>,
    /// #42 the effective ADIF mode (MFSK by its SUBMODE), upper case.
    pub mode: Option<String>,
    /// #10 the contact is confirmed (logbook::Record::confirmed).
    pub confirmed: bool,
    /// #39 QSO_DATE as YYYYMMDD (None: counts only for the all-time window).
    pub date: Option<u32>,
    /// #97 the ADIF STATE (WstxValueOrder::UsStateOf), upper case.
    pub state: Option<String>,
}
/// #10 award standing of a key (for example a DXCC entity) in a scope: worked by any
/// logged contact, and confirmed by at least one of them.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Standing {
    pub worked: bool,
    pub confirmed: bool,
}
impl Standing {
    /// #39 award strategies: needed when not worked or not confirmed.
    pub fn needed(self) -> bool {
        !self.worked || !self.confirmed
    }
}
/// The entity categories a WstxValueOrder::NewNeeded reads (their index follows `keys`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Category {
    Dxcc,
    Continent,
    CqZone,
    ItuZone,
}
impl Category {
    fn index(self) -> usize {
        match self {
            Category::Dxcc => 2,
            Category::Continent => 3,
            Category::CqZone => 4,
            Category::ItuZone => 5,
        }
    }
}
/// The index of the CQ WPX prefix in the per-band and per-band-and-mode maps (#97 NewNeeded
/// prefix per band and band_mode).
const WPX: u8 = 6;
/// #97 WstxValueOrder::UsStateOf: the entities whose ADIF STATE is a US state (291 United States,
/// 6 Alaska, 110 Hawaii), by their cty.dat names.
pub const US_ENTITIES: [&str; 3] = ["United States", "Alaska", "Hawaii"];
/// WstxValueOrder::WpxPrefix: the CQ WPX prefix of a call.
pub fn wpx_prefix(call: &str) -> String {
    /// Letters and digits up to the last digit; without a digit two letters and a zero.
    fn prefix_of(part: &str) -> String {
        match part.rfind(|c: char| c.is_ascii_digit()) {
            Some(last) => part[..=last].to_owned(),
            None => format!("{}0", part.get(..2).unwrap_or(part)),
        }
    }
    let call = call.trim().to_ascii_uppercase();
    let parts: Vec<&str> = call
        .split('/')
        .filter(|p| {
            !p.is_empty()
                && !matches!(
                    *p,
                    "P" | "M" | "MM" | "AM" | "A" | "E" | "J" | "QRP" | "B" | "R"
                )
        })
        .collect();
    match parts.as_slice() {
        [] => String::new(),
        [only] => prefix_of(only),
        // A single digit replaces the call's last digit (N8BJQ/3 is N3).
        [home, digit] if digit.len() == 1 && digit.as_bytes()[0].is_ascii_digit() => {
            let mut p = prefix_of(home);
            p.pop();
            p.push_str(digit);
            p
        }
        // Otherwise the shorter part is the designator (the left one when equally long).
        [left, right, ..] => prefix_of(if right.len() < left.len() {
            right
        } else {
            left
        }),
    }
}
/// WorkedBefore with highlight by mode off (the WSJT-X default): what the log holds per
/// category, ever and per band. Calls compare upper case, grids by their 4-character
/// square upper case; the entity categories use the logged call's entity (WSJT-X keys
/// DXCC by the full entity name, WAE entities included). A call without an entity adds
/// nothing to the entity categories. Each key maps to whether a confirmed contact holds
/// it (#10), so the confirmation costs no extra lookup.
#[derive(Default)]
pub struct Worked {
    ever: HashMap<(u8, String), bool>,
    band: HashMap<(u8, String, String), bool>,
    /// #42 per band and mode (the strategy's scope), for the entity categories.
    band_mode: HashMap<(u8, String, String, String), bool>,
    /// #39 the CQ WPX prefixes (WstxValueOrder::WpxPrefix) with their confirmation.
    wpx: HashMap<String, bool>,
    /// #39 calls with a logged contact that has no grid: their grid status is unknown.
    gridless: HashSet<String>,
    /// #97 WstxValueOrder::UsStateOf: per call the STATE of its newest record that has one, a
    /// confirmed record before an unconfirmed one: (confirmed, date, state). Every record
    /// counts, whatever the window.
    states: HashMap<String, (bool, u32, String)>,
}
impl std::fmt::Debug for Worked {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Worked({} keys)", self.ever.len())
    }
}
fn square(grid: &str) -> Option<String> {
    grid.get(..4).map(str::to_ascii_uppercase)
}
/// The keys of each category (None: the category does not apply).
fn keys(call: &str, grid: Option<&str>, r: Option<&Resolved>) -> [Option<String>; 6] {
    [
        Some(call.to_ascii_uppercase()),
        grid.and_then(square),
        r.map(|r| r.name.clone()),
        r.map(|r| r.continent.to_owned()),
        r.map(|r| r.cq_zone.to_string()),
        r.map(|r| r.itu_zone.to_string()),
    ]
}
fn standing(confirmed: Option<&bool>) -> Standing {
    Standing {
        worked: confirmed.is_some(),
        confirmed: confirmed.copied().unwrap_or(false),
    }
}
impl Worked {
    pub fn from_log(table: &Table, logged: &[Logged]) -> Self {
        Self::from_log_window(table, logged, None)
    }
    /// #39 WstxRankingControl::WorkedWindow: only the records dated in `window` (first and last
    /// date as YYYYMMDD, inclusive), if given; a record without a date counts only without.
    pub fn from_log_window(table: &Table, logged: &[Logged], window: Option<(u32, u32)>) -> Self {
        let mut w = Self::default();
        for l in logged {
            if let Some(state) = l.state.as_deref().filter(|s| !s.trim().is_empty()) {
                let held = (l.confirmed, l.date.unwrap_or(0));
                let entry = w.states.entry(l.call.to_ascii_uppercase());
                match entry {
                    std::collections::hash_map::Entry::Occupied(mut o) => {
                        if held >= (o.get().0, o.get().1) {
                            o.insert((held.0, held.1, state.trim().to_ascii_uppercase()));
                        }
                    }
                    std::collections::hash_map::Entry::Vacant(v) => {
                        v.insert((held.0, held.1, state.trim().to_ascii_uppercase()));
                    }
                }
            }
            if let Some((first, last)) = window
                && !l.date.is_some_and(|d| (first..=last).contains(&d))
            {
                continue;
            }
            let r = table.lookup(&l.call);
            for (i, key) in keys(&l.call, l.grid.as_deref(), r.as_ref())
                .into_iter()
                .enumerate()
            {
                let Some(key) = key else { continue };
                if let Some(b) = &l.band {
                    *w.band.entry((i as u8, key.clone(), b.clone())).or_default() |= l.confirmed;
                    if let Some(m) = l.mode.as_deref() {
                        *w.band_mode
                            .entry((i as u8, key.clone(), b.clone(), m.to_ascii_uppercase()))
                            .or_default() |= l.confirmed;
                    }
                }
                *w.ever.entry((i as u8, key)).or_default() |= l.confirmed;
            }
            let wpx = wpx_prefix(&l.call);
            if let Some(b) = &l.band {
                *w.band.entry((WPX, wpx.clone(), b.clone())).or_default() |= l.confirmed;
                if let Some(m) = l.mode.as_deref() {
                    *w.band_mode
                        .entry((WPX, wpx.clone(), b.clone(), m.to_ascii_uppercase()))
                        .or_default() |= l.confirmed;
                }
            }
            *w.wpx.entry(wpx).or_default() |= l.confirmed;
            if l.grid.as_deref().and_then(square).is_none() {
                w.gridless.insert(l.call.to_ascii_uppercase());
            }
        }
        w
    }
    /// #39 the standing of a call, ever.
    #[cfg(test)]
    pub fn call_standing(&self, call: &str) -> Standing {
        standing(self.ever.get(&(0, call.to_ascii_uppercase())))
    }
    /// #39 the standing of a grid's 4-character square, ever.
    #[cfg(test)]
    pub fn grid_standing(&self, grid: &str) -> Standing {
        standing(square(grid).and_then(|g| self.ever.get(&(1, g))))
    }
    /// #39 the standing of a call's CQ WPX prefix, ever.
    #[cfg(test)]
    pub fn wpx_standing(&self, call: &str) -> Standing {
        standing(self.wpx.get(&wpx_prefix(call)))
    }
    /// #97 the standing of a key of index `i` (0 call, 1 grid square, 6 WPX prefix) ever, on a
    /// band in any mode, or on a band and mode.
    fn scoped(&self, i: u8, key: String, band: Option<&str>, mode: Option<&str>) -> Standing {
        standing(match (band, mode) {
            (None, _) if i == WPX => self.wpx.get(&key),
            (None, _) => self.ever.get(&(i, key)),
            (Some(b), None) => self.band.get(&(i, key, b.to_ascii_lowercase())),
            (Some(b), Some(m)) => {
                self.band_mode
                    .get(&(i, key, b.to_ascii_lowercase(), m.to_ascii_uppercase()))
            }
        })
    }
    /// #97 NewNeeded call per ever, band or band and mode.
    pub fn call_scoped(&self, call: &str, band: Option<&str>, mode: Option<&str>) -> Standing {
        self.scoped(0, call.to_ascii_uppercase(), band, mode)
    }
    /// #97 NewNeeded grid (its 4-character square) per ever, band or band and mode.
    pub fn grid_scoped(&self, grid: &str, band: Option<&str>, mode: Option<&str>) -> Standing {
        square(grid).map_or(Standing::default(), |g| self.scoped(1, g, band, mode))
    }
    /// #97 NewNeeded prefix (WstxValueOrder::WpxPrefix) per ever, band or band and mode.
    pub fn wpx_scoped(&self, call: &str, band: Option<&str>, mode: Option<&str>) -> Standing {
        self.scoped(WPX, wpx_prefix(call), band, mode)
    }
    /// #97 WstxValueOrder::UsStateOf from the log: the STATE of the call's newest record that has
    /// one, a confirmed record first.
    pub fn state_of(&self, call: &str) -> Option<&str> {
        self.states
            .get(&call.to_ascii_uppercase())
            .map(|s| s.2.as_str())
    }
    /// #39 the call has a logged contact without a grid (WstxStrategy D13).
    pub fn gridless(&self, call: &str) -> bool {
        self.gridless.contains(&call.to_ascii_uppercase())
    }
    /// #10 worked and confirmed standing of an entity's key of the category: ever (no
    /// band), on a band in any mode, or on a band and mode. One lookup per query.
    pub fn entity_standing(
        &self,
        c: Category,
        r: &Resolved,
        band: Option<&str>,
        mode: Option<&str>,
    ) -> Standing {
        let i = c.index();
        let Some(key) = keys("", None, Some(r)).into_iter().nth(i).flatten() else {
            return Standing::default();
        };
        let confirmed = match (band, mode) {
            (None, _) => self.ever.get(&(i as u8, key)),
            (Some(b), None) => self.band.get(&(i as u8, key, b.to_ascii_lowercase())),
            (Some(b), Some(m)) => {
                self.band_mode
                    .get(&(i as u8, key, b.to_ascii_lowercase(), m.to_ascii_uppercase()))
            }
        };
        standing(confirmed)
    }
    /// The FLAGS that hold for a decoded sender; the _band flags only with a known band,
    /// the grid flags only with a message grid, the entity flags only with an entity.
    pub fn flags(
        &self,
        call: &str,
        grid: Option<&str>,
        r: Option<&Resolved>,
        band: Option<&str>,
    ) -> Vec<&'static str> {
        let band = band.map(str::to_ascii_lowercase);
        let mut out = Vec::new();
        for (i, key) in keys(call, grid, r).into_iter().enumerate() {
            let Some(key) = key else { continue };
            if !self.ever.contains_key(&(i as u8, key.clone())) {
                out.push(FLAGS[2 * i]);
            }
            if let Some(b) = &band
                && !self.band.contains_key(&(i as u8, key, b.clone()))
            {
                out.push(FLAGS[2 * i + 1]);
            }
        }
        out
    }
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

/// The concrete call that sent a decoded record, also a filled-in hash; None for a hash
/// nobody heard and for a message without a sender (free text, telemetry).
fn sender(record: &Value) -> Option<String> {
    if record["status"] != "decoded" {
        return None;
    }
    let f = &record["fields"];
    let call = match f["type"].as_str()? {
        "nonstandard" if f["hash_second"] == true && f["cq"] != true => &f["hashed_call"],
        "nonstandard" => &f["full_call"],
        "dxpedition" => &f["hashed"],
        _ => &f["from"],
    };
    matches!(call["kind"].as_str(), Some("call" | "hash"))
        .then(|| call["text"].as_str().map(str::to_owned))
        .flatten()
}
/// #55 DecodedEntity: adds to each decoded record with a resolved sender call its
/// `dxcc` (compact, when the call has an entity), `flags` (only the FLAGS that hold,
/// against the cached worked set of the log; omitted when none holds or the log is
/// unreadable) and `worked_status` (WorkedBeforeQuery, with a known band). Band: the CAT dial band, else the operating selection band; without a
/// band no `_band` flag is set. Blocking (log lock): call it off the async runtime.
pub(crate) fn annotate(state: &crate::ProfileState, records: &mut [Value]) {
    if !records.iter().any(|r| sender(r).is_some()) {
        return;
    }
    let (table, _) = state.logbook.dxcc();
    let worked = state.logbook.worked_set().ok();
    let me = crate::contact_http::profile_facts(state)
        .1
        .as_deref()
        .and_then(crate::strategy::maidenhead);
    let band = crate::strategy::station_band(&state.recording);
    let mode = state.recording.receive_snapshot()["job"]["mode"]
        .as_str()
        .map(str::to_ascii_uppercase);
    for record in records.iter_mut() {
        let Some(from) = sender(record) else {
            continue;
        };
        // WstxLogbook::WorkedBeforeQuery: this record's worked-before status, so the browser
        // needs no query (#10); a hash is no concrete call.
        if let (Some(band), Some(mode)) = (band, mode.as_deref())
            && record["fields"]["type"] == "standard"
            && record["fields"]["from"]["kind"] == "call"
            && let Ok(status) = state
                .logbook
                .worked(std::slice::from_ref(&from), band, mode)
            && let Some(status) = status.first()
        {
            record["worked_status"] = json!(status);
        }
        let entity = table.lookup(&from);
        if let Some(r) = &entity {
            record["dxcc"] = compact(r, me);
        }
        // The browser colours a row by its sender; a DXpedition message names none for it,
        // so a flag here would be a reason without a colour.
        if record["fields"]["type"] == "dxpedition" {
            continue;
        }
        let exchange = &record["fields"]["exchange"];
        let grid = (exchange["kind"] == "grid")
            .then(|| exchange["value"].as_str())
            .flatten()
            .filter(|g| crate::strategy::maidenhead(g).is_some());
        let flags = worked
            .as_ref()
            .map_or_else(Vec::new, |w| w.flags(&from, grid, entity.as_ref(), band));
        if !flags.is_empty() {
            record["flags"] = Value::Object(
                flags
                    .into_iter()
                    .map(|n| (n.to_owned(), Value::Bool(true)))
                    .collect(),
            );
        }
    }
}
