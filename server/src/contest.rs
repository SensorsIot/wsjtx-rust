#![forbid(unsafe_code)]
//! WstxContest (#63): the contest profiles from the official rules and their schedule, the
//! selection of a contest and its evaluation. A new contest is one more entry of PROFILES; a
//! profile holds rule facts only, its rule enums hold the behaviour.
use crate::contact::{Activity, civil, parse_utc};
use crate::strategy::{Facts, Kind, Station, Verdict, maidenhead, sane_call};
use serde_json::{Value, json};
use std::collections::HashSet;

#[cfg(test)]
#[path = "contest_tests.rs"]
mod tests;

/// What makes a second QSO a dupe (WstxContest::ContestProfile).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Dupes {
    Band,
    BandModeClass,
    BandGrid,
    Call,
}
impl Dupes {
    fn name(self) -> &'static str {
        match self {
            Dupes::Band => "band",
            Dupes::BandModeClass => "band_mode_class",
            Dupes::BandGrid => "band_grid",
            Dupes::Call => "call",
        }
    }
}
/// The QSO points rule (WstxContest::ContestProfile).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Points {
    OnePlusPer3000Km,
    OnePlusPer500KmUp,
    FieldDay,
    VhfJanuary,
    VhfJuneSeptember,
    Kilometres,
    OnePerCall,
}
impl Points {
    fn name(self) -> &'static str {
        match self {
            Points::OnePlusPer3000Km => "one_plus_per_3000_km",
            Points::OnePlusPer500KmUp => "one_plus_per_500_km_up",
            Points::FieldDay => "field_day",
            Points::VhfJanuary => "vhf_january",
            Points::VhfJuneSeptember => "vhf_june_september",
            Points::Kilometres => "kilometres",
            Points::OnePerCall => "one_per_call",
        }
    }
}
/// The multiplier rule (WstxContest::ContestProfile).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Multipliers {
    None,
    FieldPerBand,
    GridPerBand,
}
impl Multipliers {
    fn name(self) -> &'static str {
        match self {
            Multipliers::None => "none",
            Multipliers::FieldPerBand => "field_per_band",
            Multipliers::GridPerBand => "grid_per_band",
        }
    }
}
/// Which logged QSOs a contest counts at all (WstxContest::ContestLog).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Counted {
    Ft8Ft4,
    Digital,
    DigitalNoRtty,
    Any,
}
/// What the official rules say about automatic operation (WstxContest::AutomationClause).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum AutomationClause {
    Forbidden,
    Silent,
}
impl AutomationClause {
    fn name(self) -> &'static str {
        match self {
            AutomationClause::Forbidden => "forbidden",
            AutomationClause::Silent => "silent",
        }
    }
}
/// The day a round of a contest hangs on (WstxContest::ScheduleRule).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum When {
    /// The n-th (1-based) weekend of a month with Saturday and Sunday both in it: its Saturday.
    FullWeekend { month: u32, n: usize },
    /// The last such weekend: its Saturday.
    LastFullWeekend { month: u32 },
    /// The n-th (1-based) Saturday of a month.
    Saturday { month: u32, n: usize },
    /// The n-th (1-based) of a weekday (0 Sunday) in every month.
    EveryMonth { weekday: i64, n: usize },
    /// Not computable from the rule: the period prompt asks.
    Asked,
}
/// One round: the day, and start and end (exclusive) in minutes from 00:00 UTC of that day.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Round {
    pub when: When,
    pub start_min: i64,
    pub end_min: i64,
    /// The one band of the round (FT8 Activity).
    pub band: Option<&'static str>,
}
/// One occurrence of a contest.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Occurrence {
    pub start_ms: i64,
    pub end_ms: i64,
    pub band: Option<&'static str>,
}
/// WstxContest::ContestProfile: rule facts of one contest.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Profile {
    pub id: &'static str,
    pub name: &'static str,
    pub cabrillo: Option<&'static str>,
    pub cabrillo_confirmed: bool,
    pub activity: Activity,
    pub bands: &'static [&'static str],
    pub modes: &'static str,
    pub exchange: &'static str,
    pub dupes: Dupes,
    pub points: Points,
    pub multipliers: Multipliers,
    pub counted: Counted,
    pub score: &'static str,
    pub automation: AutomationClause,
    pub automation_text: &'static str,
    pub rounds: &'static [Round],
    pub schedule: &'static str,
    pub notes: &'static [&'static str],
    pub source: &'static str,
}
const HOUR: i64 = 60;
const HF: &[&str] = &["160m", "80m", "40m", "20m", "15m", "10m"];
const HF_6M: &[&str] = &["160m", "80m", "40m", "20m", "15m", "10m", "6m"];
const VHF: &[&str] = &[
    "6m", "5m", "4m", "2m", "1.25m", "70cm", "33cm", "23cm", "13cm", "9cm", "6cm", "3cm", "1.25cm",
    "6mm", "4mm", "2.5mm", "2mm", "1mm", "submm",
];
const FIELD_DAY: &[&str] = &[
    "160m", "80m", "40m", "20m", "15m", "10m", "6m", "5m", "4m", "2m", "1.25m", "70cm", "33cm",
    "23cm", "13cm", "9cm", "6cm", "3cm", "1.25cm", "6mm", "4mm", "2.5mm", "2mm", "1mm", "submm",
];
const FORBIDDEN_ARRL: &str = "Each contact must include contemporaneous direct initiation by both operators making a contact. Initiation of a contact may be by either local or remote control. Fully automated contacts are prohibited.";
const FORBIDDEN_VHF: &str = "Each contact must include contemporaneous direct initiation by both operators making a contact. Initiation of a contact may be by either local or remote control.";
const SILENT: &str = "The rules do not address automatic operation.";
const VHF_NOTES: &[&str] = &[
    "DX stations may only contact W/VE stations (2.3); W/VE stations may contact any station.",
    "Stations may be contacted once per band from any specific grid square (2.2): a rover counts again from a new grid.",
];
const IARU_NOTES: &[&str] = &[
    "Standard FT8 messages with report and 4-character locator; no serial number.",
    "6H section: 6 hours in at most two periods with a pause of more than 2 hours (a note, not tracked).",
    "Self-spots: only when first soliciting QSOs on a new frequency, then at most every 10 minutes.",
];
/// The profiles in the order the selector offers them.
pub(crate) const PROFILES: &[Profile] = &[
    Profile {
        id: "ww_digi",
        name: "WW Digi",
        cabrillo: Some("WW-DIGI"),
        cabrillo_confirmed: true,
        activity: Activity::WwDigi,
        bands: HF,
        modes: "FT4 and FT8 only",
        exchange: "4-character grid square",
        dupes: Dupes::Band,
        points: Points::OnePlusPer3000Km,
        multipliers: Multipliers::FieldPerBand,
        counted: Counted::Ft8Ft4,
        score: "QSO points x grid fields, over all bands",
        automation: AutomationClause::Forbidden,
        automation_text: "A human operator must initiate calling each QSO partner. Autonomous systems or robots that emulate this action are prohibited. (IX.12)",
        rounds: &[Round {
            when: When::LastFullWeekend { month: 8 },
            start_min: 12 * HOUR,
            end_min: 36 * HOUR,
            band: None,
        }],
        schedule: "Last full weekend of August (unconfirmed: the rules state only the dates), 1200 UTC Saturday to 1159 UTC Sunday",
        notes: &["Self-spotting or asking to be spotted is not permitted (IX.4)."],
        source: "http://ww-digi.com/rules/",
    },
    Profile {
        id: "arrl_digi",
        name: "ARRL Digi",
        cabrillo: Some("ARRL-DIGI"),
        cabrillo_confirmed: true,
        activity: Activity::ArrlDigi,
        bands: HF_6M,
        modes: "Any digital mode except RTTY",
        exchange: "4-character grid square",
        dupes: Dupes::Band,
        points: Points::OnePlusPer500KmUp,
        multipliers: Multipliers::None,
        counted: Counted::DigitalNoRtty,
        score: "Total QSO points",
        automation: AutomationClause::Forbidden,
        automation_text: FORBIDDEN_ARRL,
        rounds: &[Round {
            when: When::FullWeekend { month: 6, n: 1 },
            start_min: 18 * HOUR,
            end_min: 48 * HOUR,
            band: None,
        }],
        schedule: "First full weekend of June, 1800 UTC Saturday to 2359 UTC Sunday",
        notes: &[
            "Single-Op: 24 of 30 hours, off times of at least 60 minutes (a note, not tracked).",
            "Alternating CQs on two or more frequencies in one band are prohibited (OPRG.3).",
        ],
        source: "https://contests.arrl.org/ContestRules/Digital-Rules.pdf",
    },
    Profile {
        id: "arrl_field_day",
        name: "ARRL Field Day",
        cabrillo: Some("ARRL-FD"),
        cabrillo_confirmed: false,
        activity: Activity::FieldDay,
        bands: FIELD_DAY,
        modes: "Phone, CW and Digital; all non-CW digital modes count as one mode",
        exchange: "Class and ARRL/RAC section (DX: class and DX)",
        dupes: Dupes::BandModeClass,
        points: Points::FieldDay,
        multipliers: Multipliers::None,
        counted: Counted::Any,
        score: "QSO points x power multiplier + bonus points (power and bonus are not computed)",
        automation: AutomationClause::Forbidden,
        automation_text: FORBIDDEN_ARRL,
        rounds: &[Round {
            when: When::FullWeekend { month: 6, n: 4 },
            start_min: 18 * HOUR,
            end_min: 45 * HOUR,
            band: None,
        }],
        schedule: "Fourth full weekend of June, 1800 UTC Saturday to 2059 UTC Sunday",
        notes: &[
            "Entries from ARRL/RAC areas and IARU Region 2; DX stations in other regions may be contacted and may submit check-logs only (1).",
            "27 hours when set-up starts no earlier than 1800 UTC Saturday, otherwise 24 consecutive hours (a note, not tracked).",
        ],
        source: "https://www.arrl.org/files/file/Field-Day/2026/2026-Field-Day-Rules.pdf",
    },
    Profile {
        id: "arrl_vhf_jan",
        name: "ARRL January VHF",
        cabrillo: Some("ARRL-VHF-JAN"),
        cabrillo_confirmed: false,
        activity: Activity::NaVhf,
        bands: VHF,
        modes: "Any mode",
        exchange: "4-character grid square",
        dupes: Dupes::BandGrid,
        points: Points::VhfJanuary,
        multipliers: Multipliers::GridPerBand,
        counted: Counted::Any,
        score: "QSO points x grid squares per band (fixed station)",
        automation: AutomationClause::Forbidden,
        automation_text: FORBIDDEN_VHF,
        rounds: &[Round {
            when: When::Asked,
            start_min: 19 * HOUR,
            end_min: 52 * HOUR,
            band: None,
        }],
        schedule: "Third or fourth full weekend of January as announced (enter the date), 1900 UTC Saturday to 0359 UTC Monday",
        notes: VHF_NOTES,
        source: "https://contests.arrl.org/ContestRules/JanJunSep-VHF-Rules.pdf",
    },
    Profile {
        id: "arrl_vhf_jun",
        name: "ARRL June VHF",
        cabrillo: Some("ARRL-VHF-JUN"),
        cabrillo_confirmed: false,
        activity: Activity::NaVhf,
        bands: VHF,
        modes: "Any mode",
        exchange: "4-character grid square",
        dupes: Dupes::BandGrid,
        points: Points::VhfJuneSeptember,
        multipliers: Multipliers::GridPerBand,
        counted: Counted::Any,
        score: "QSO points x grid squares per band (fixed station)",
        automation: AutomationClause::Forbidden,
        automation_text: FORBIDDEN_VHF,
        rounds: &[Round {
            when: When::FullWeekend { month: 6, n: 2 },
            start_min: 18 * HOUR,
            end_min: 51 * HOUR,
            band: None,
        }],
        schedule: "Second full weekend of June, 1800 UTC Saturday to 0259 UTC Monday",
        notes: VHF_NOTES,
        source: "https://contests.arrl.org/ContestRules/JanJunSep-VHF-Rules.pdf",
    },
    Profile {
        id: "arrl_vhf_sep",
        name: "ARRL September VHF",
        cabrillo: Some("ARRL-VHF-SEP"),
        cabrillo_confirmed: false,
        activity: Activity::NaVhf,
        bands: VHF,
        modes: "Any mode",
        exchange: "4-character grid square",
        dupes: Dupes::BandGrid,
        points: Points::VhfJuneSeptember,
        multipliers: Multipliers::GridPerBand,
        counted: Counted::Any,
        score: "QSO points x grid squares per band (fixed station)",
        automation: AutomationClause::Forbidden,
        automation_text: FORBIDDEN_VHF,
        rounds: &[Round {
            when: When::FullWeekend { month: 9, n: 2 },
            start_min: 18 * HOUR,
            end_min: 51 * HOUR,
            band: None,
        }],
        schedule: "Second full weekend of September, 1800 UTC Saturday to 0259 UTC Monday",
        notes: VHF_NOTES,
        source: "https://contests.arrl.org/ContestRules/JanJunSep-VHF-Rules.pdf",
    },
    Profile {
        id: "iaru_50_mgm",
        name: "IARU R1 50 MHz MGM",
        cabrillo: None,
        cabrillo_confirmed: false,
        activity: Activity::None,
        bands: &["6m"],
        modes: "MGM",
        exchange: "Report and 4-character locator",
        dupes: Dupes::Band,
        points: Points::Kilometres,
        multipliers: Multipliers::GridPerBand,
        counted: Counted::Digital,
        score: "Total kilometres x large locator squares",
        automation: AutomationClause::Silent,
        automation_text: SILENT,
        rounds: &[Round {
            when: When::Saturday { month: 4, n: 3 },
            start_min: 14 * HOUR,
            end_min: 38 * HOUR,
            band: None,
        }],
        schedule: "Third Saturday of April, 1400 UTC Saturday to 1400 UTC Sunday",
        notes: IARU_NOTES,
        source: "https://www.iaru-r1.org/wp-content/uploads/2026/02/VHF_Handbook_V10_03_final.pdf",
    },
    Profile {
        id: "iaru_70_mgm",
        name: "IARU R1 70 MHz MGM",
        cabrillo: None,
        cabrillo_confirmed: false,
        activity: Activity::None,
        bands: &["4m"],
        modes: "MGM",
        exchange: "Report and 4-character locator",
        dupes: Dupes::Band,
        points: Points::Kilometres,
        multipliers: Multipliers::GridPerBand,
        counted: Counted::Digital,
        score: "Total kilometres x large locator squares",
        automation: AutomationClause::Silent,
        automation_text: SILENT,
        rounds: &[Round {
            when: When::Saturday { month: 5, n: 3 },
            start_min: 14 * HOUR,
            end_min: 38 * HOUR,
            band: None,
        }],
        schedule: "Third Saturday of May, 1400 UTC Saturday to 1400 UTC Sunday",
        notes: IARU_NOTES,
        source: "https://www.iaru-r1.org/wp-content/uploads/2026/02/VHF_Handbook_V10_03_final.pdf",
    },
    Profile {
        id: "ft8_activity",
        name: "FT8 Activity",
        cabrillo: None,
        cabrillo_confirmed: false,
        activity: Activity::None,
        bands: &["2m", "70cm", "23cm"],
        modes: "FT8 and FT4; standard mode, not the VHF contest mode",
        exchange: "Call and 4-character locator",
        dupes: Dupes::Call,
        points: Points::OnePerCall,
        multipliers: Multipliers::GridPerBand,
        counted: Counted::Digital,
        score: "Points x locators, per round",
        automation: AutomationClause::Silent,
        automation_text: SILENT,
        rounds: &[
            Round {
                when: When::EveryMonth { weekday: 3, n: 1 },
                start_min: 17 * HOUR,
                end_min: 21 * HOUR,
                band: Some("2m"),
            },
            Round {
                when: When::EveryMonth { weekday: 3, n: 2 },
                start_min: 17 * HOUR,
                end_min: 21 * HOUR,
                band: Some("70cm"),
            },
            Round {
                when: When::EveryMonth { weekday: 3, n: 3 },
                start_min: 17 * HOUR,
                end_min: 21 * HOUR,
                band: Some("23cm"),
            },
        ],
        schedule: "Each month: first Wednesday 2 m, second Wednesday 70 cm, third Wednesday 23 cm, 1700 to 2100 UTC",
        notes: &[
            "Self-spotting is forbidden; ON4KST is for skeds only.",
            "Multiple simultaneous signals (Fox mode or similar) are forbidden.",
        ],
        source: "https://ft8activity.eu/rules/",
    },
];
const DAY_MS: i64 = 86_400_000;
/// 00:00 UTC of each day of a month that is this weekday (0 Sunday).
fn weekdays(year: i64, month: u32, weekday: i64) -> Vec<i64> {
    (1..=31)
        .filter_map(|day| parse_utc(&format!("{year:04}-{month:02}-{day:02}T00:00:00Z")))
        .filter(|ms| civil(*ms).1 == month && (ms / DAY_MS + 4).rem_euclid(7) == weekday)
        .collect()
}
/// The Saturdays whose Sunday is in the same month ('full weekend', operator default #63).
fn full_weekends(year: i64, month: u32) -> Vec<i64> {
    let mut list = weekdays(year, month, 6);
    list.retain(|ms| civil(ms + DAY_MS).1 == month);
    list
}
impl Round {
    /// The occurrence in this month, if the round has one there.
    fn in_month(&self, year: i64, month: u32) -> Option<Occurrence> {
        let day = match self.when {
            When::FullWeekend { month: m, n } if m == month => {
                full_weekends(year, month).get(n - 1).copied()
            }
            When::LastFullWeekend { month: m } if m == month => {
                full_weekends(year, month).last().copied()
            }
            When::Saturday { month: m, n } if m == month => {
                weekdays(year, month, 6).get(n - 1).copied()
            }
            When::EveryMonth { weekday, n } => weekdays(year, month, weekday).get(n - 1).copied(),
            _ => None,
        }?;
        Some(Occurrence {
            start_ms: day + self.start_min * 60_000,
            end_ms: day + self.end_min * 60_000,
            band: self.band,
        })
    }
}
impl Profile {
    /// WstxContest::ScheduleRule: the current or next occurrence, the earliest that has not
    /// ended; None when the rule cannot compute it.
    pub(crate) fn next_period(&self, now_ms: i64) -> Option<Occurrence> {
        let (year, month, ..) = civil(now_ms);
        let first = year * 12 + i64::from(month) - 1;
        // The month before (a round may end in the next month) to one full cycle ahead.
        (first - 1..=first + 13)
            .flat_map(|m| {
                let (y, mo) = (m.div_euclid(12), m.rem_euclid(12) as u32 + 1);
                self.rounds.iter().filter_map(move |r| r.in_month(y, mo))
            })
            .filter(|o| o.end_ms > now_ms)
            .min_by_key(|o| o.start_ms)
    }
    fn json(&self, now_ms: i64) -> Value {
        json!({"id":self.id,"name":self.name,"cabrillo":self.cabrillo,
            "cabrillo_confirmed":self.cabrillo_confirmed,"activity":self.activity.name(),
            "bands":self.bands,"modes":self.modes,"exchange":self.exchange,
            "dupes":self.dupes.name(),"points":self.points.name(),
            "multipliers":self.multipliers.name(),"score":self.score,
            "automation":self.automation.name(),"automation_text":self.automation_text,
            "schedule":self.schedule,"notes":self.notes,"source":self.source,
            "period":self.next_period(now_ms).map(|o| json!({"start":utc_text(o.start_ms),
                "end":utc_text(o.end_ms),"band":o.band}))})
    }
}
/// "YYYY-MM-DDTHH:MMZ".
pub(crate) fn utc_text(ms: i64) -> String {
    let (y, mo, d, h, mi, _) = civil(ms);
    format!("{y:04}-{mo:02}-{d:02}T{h:02}:{mi:02}Z")
}
/// The profiles of GET /strategy/contests.
pub(crate) fn profiles_json(now_ms: i64) -> Value {
    Value::Array(PROFILES.iter().map(|p| p.json(now_ms)).collect())
}
pub(crate) fn profile(id: &str) -> Option<&'static Profile> {
    PROFILES.iter().find(|p| p.id == id)
}

/// #97 the contest table (WstxStrategy::BuiltinStrategies: one contest built-in per profile).
pub(crate) fn all_profiles() -> &'static [Profile] {
    PROFILES
}

// ------------------------------------------------------------------ the selection
/// WstxContest::ContestSelection: the contest in force, in memory only (#97 D11: the period
/// only; the operation, repetitions and quiet time are the contest strategy's own decisions).
#[derive(Clone, Copy, Debug)]
pub(crate) struct Selection {
    pub profile: &'static Profile,
    pub start_ms: i64,
    pub end_ms: i64,
}
impl PartialEq for Selection {
    fn eq(&self, o: &Self) -> bool {
        self.profile.id == o.profile.id && (self.start_ms, self.end_ms) == (o.start_ms, o.end_ms)
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
/// Exact ContestSelection parsing (the error names the refused field).
pub(crate) fn parse_selection(v: &Value, field: &str) -> Result<Selection, String> {
    let o = v.as_object().ok_or(field)?;
    let keys = ["profile", "start", "end"];
    let f = |k: &str| format!("{field}.{k}");
    // Gone keys are refused by their own path (automation_confirmed: strategydef; operation,
    // repetitions and quiet_minutes: #97 D11); any other extra key by the selection's.
    if let Some(k) = [
        "automation_confirmed",
        "operation",
        "repetitions",
        "quiet_minutes",
    ]
    .into_iter()
    .find(|k| o.contains_key(*k))
    {
        return Err(f(k));
    }
    if o.len() != keys.len() || !keys.iter().all(|k| o.contains_key(*k)) {
        return Err(field.to_owned());
    }
    let profile = v["profile"]
        .as_str()
        .and_then(profile)
        .ok_or(f("profile"))?;
    let start_ms = minute(&v["start"]).ok_or(f("start"))?;
    let end_ms = minute(&v["end"])
        .filter(|e| *e > start_ms && *e - start_ms <= PERIOD_MAX_MS)
        .ok_or(f("end"))?;
    Ok(Selection {
        profile,
        start_ms,
        end_ms,
    })
}
impl Selection {
    pub(crate) fn json(&self) -> Value {
        json!({"profile":self.profile.id,"start":utc_text(self.start_ms),
            "end":utc_text(self.end_ms)})
    }
    pub(crate) fn in_period(&self, now_ms: i64) -> bool {
        now_ms >= self.start_ms && now_ms < self.end_ms
    }
}

// ------------------------------------------------------------------ the rules
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum ModeClass {
    Phone,
    Cw,
    Digital,
}
fn mode_class(mode: &str) -> ModeClass {
    match mode {
        "CW" => ModeClass::Cw,
        "SSB" | "USB" | "LSB" | "AM" | "FM" | "DIGITALVOICE" => ModeClass::Phone,
        _ => ModeClass::Digital,
    }
}
impl Counted {
    fn holds(self, mode: &str) -> bool {
        match self {
            Counted::Ft8Ft4 => matches!(mode, "FT8" | "FT4"),
            Counted::Digital => mode_class(mode) == ModeClass::Digital,
            Counted::DigitalNoRtty => mode_class(mode) == ModeClass::Digital && mode != "RTTY",
            Counted::Any => true,
        }
    }
}
/// Kilometres between the centres of two 4-character squares on a sphere of this radius.
fn kilometres(a: &str, b: &str, radius: f64) -> Option<f64> {
    let (a, b) = (maidenhead(a.get(..4)?)?, maidenhead(b.get(..4)?)?);
    let r = std::f64::consts::PI / 180.0;
    let (la1, la2, dl) = (a.0 * r, b.0 * r, (b.1 - a.1) * r);
    let h = ((la2 - la1) / 2.0).sin().powi(2) + la1.cos() * la2.cos() * (dl / 2.0).sin().powi(2);
    Some(2.0 * radius * h.sqrt().min(1.0).asin())
}
const EARTH_KM: f64 = 6371.0;
/// IARU R1: a factor of 111.2 km per degree.
const IARU_RADIUS_KM: f64 = 111.2 * 180.0 / std::f64::consts::PI;
impl Points {
    /// The QSO points of one QSO; None when the rule needs a grid that is not known.
    fn of(
        self,
        my: Option<&str>,
        theirs: Option<&str>,
        band: &str,
        class: ModeClass,
    ) -> Option<u64> {
        let km = |radius| kilometres(my?, theirs?, radius);
        let vhf = |high: u64, top: u64| match band {
            "1.25m" | "70cm" => 2,
            "33cm" | "23cm" => high,
            "13cm" | "9cm" | "6cm" | "3cm" | "1.25cm" | "6mm" | "4mm" | "2.5mm" | "2mm" | "1mm"
            | "submm" => top,
            _ => 1,
        };
        Some(match self {
            Points::OnePlusPer3000Km => 1 + (km(EARTH_KM)? / 3000.0).floor() as u64,
            Points::OnePlusPer500KmUp => 1 + ((km(EARTH_KM)? / 500.0).ceil() as u64).max(1),
            Points::FieldDay => {
                if class == ModeClass::Phone {
                    1
                } else {
                    2
                }
            }
            Points::VhfJanuary => vhf(4, 8),
            Points::VhfJuneSeptember => vhf(3, 4),
            Points::Kilometres => {
                let (m, t) = (my?.get(..4)?, theirs?.get(..4)?);
                if m.eq_ignore_ascii_case(t) {
                    50
                } else {
                    km(IARU_RADIUS_KM)?.floor() as u64 + 1
                }
            }
            Points::OnePerCall => 1,
        })
    }
}
impl Multipliers {
    /// The multiplier this QSO would count for; None without one or without a grid.
    fn key(self, band: &str, grid: Option<&str>) -> Option<String> {
        let grid = grid?.to_ascii_uppercase();
        match self {
            Multipliers::None => None,
            Multipliers::FieldPerBand => Some(format!("{}|{band}", grid.get(..2)?)),
            Multipliers::GridPerBand => Some(format!("{}|{band}", grid.get(..4)?)),
        }
    }
}
/// One logged contact as a contest reads it.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Qso {
    pub call: String,
    pub grid: Option<String>,
    pub band: Option<String>,
    pub mode: String,
    pub ms: i64,
}
/// WstxContest::ContestLog: the log inside the period, by the profile's rules.
#[derive(Clone, Debug, Default)]
pub(crate) struct Log {
    keys: HashSet<String>,
    on_band: HashSet<String>,
    multipliers: HashSet<String>,
    pub qsos: u64,
    pub points: u64,
}
impl Log {
    /// Counts the QSOs in the period, oldest first; a repeat is a dupe and counts nothing.
    pub(crate) fn of(s: &Selection, my_grid: Option<&str>, list: &[Qso]) -> Self {
        let p = s.profile;
        let mut log = Log::default();
        let mut ordered: Vec<&Qso> = list
            .iter()
            .filter(|q| q.ms >= s.start_ms && q.ms < s.end_ms && p.counted.holds(&q.mode))
            .collect();
        ordered.sort_by_key(|q| q.ms);
        for q in ordered {
            let Some(band) = q.band.as_deref().filter(|b| p.bands.contains(b)) else {
                continue;
            };
            let grid = q.grid.as_deref().and_then(|g| g.get(..4));
            let class = mode_class(&q.mode);
            if log.dupe(p.dupes, &q.call, band, class, grid) {
                continue;
            }
            log.keys.insert(key(p.dupes, &q.call, band, class, grid));
            log.on_band.insert(format!("{}|{band}", q.call));
            log.qsos += 1;
            log.points += p.points.of(my_grid, grid, band, class).unwrap_or(0);
            if let Some(m) = p.multipliers.key(band, grid) {
                log.multipliers.insert(m);
            }
        }
        log
    }
    fn dupe(
        &self,
        rule: Dupes,
        call: &str,
        band: &str,
        class: ModeClass,
        grid: Option<&str>,
    ) -> bool {
        if rule == Dupes::BandGrid {
            // Without a grid on either side only the band can tell.
            return match grid {
                None => self.on_band.contains(&format!("{call}|{band}")),
                Some(_) => {
                    self.keys.contains(&key(rule, call, band, class, grid))
                        || self.keys.contains(&key(rule, call, band, class, None))
                }
            };
        }
        self.keys.contains(&key(rule, call, band, class, grid))
    }
    /// The score of the profile's rule; power and bonus points are not computed.
    pub(crate) fn score(&self, s: &Selection) -> u64 {
        match s.profile.multipliers {
            Multipliers::None => self.points,
            _ => self.points * self.multipliers.len() as u64,
        }
    }
    pub(crate) fn summary(&self, s: &Selection) -> Value {
        json!({"qsos":self.qsos,"multipliers":self.multipliers.len(),"points":self.points,
            "score":self.score(s)})
    }
}
fn key(rule: Dupes, call: &str, band: &str, class: ModeClass, grid: Option<&str>) -> String {
    match rule {
        Dupes::Band => format!("{call}|{band}"),
        Dupes::BandModeClass => format!("{call}|{band}|{class:?}"),
        Dupes::BandGrid => format!(
            "{call}|{band}|{}",
            grid.map(str::to_ascii_uppercase).unwrap_or_default()
        ),
        Dupes::Call => call.to_owned(),
    }
}
/// What a verdict adds in a contest (Verdict contest keys).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct ContestValue {
    pub dupe: bool,
    pub new_multiplier: bool,
    pub points: Option<u64>,
}
/// One record's classification (WstxContest::ContestVerdict): kind, grey, why and the value.
fn classify(
    s: &Selection,
    f: &Facts,
    st: &Station,
    log: Option<&Log>,
) -> (Option<Kind>, bool, String, Option<ContestValue>) {
    let p = s.profile;
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
    if !p.bands.contains(&band) {
        return (None, false, "band not in the contest".to_owned(), None);
    }
    let Some(log) = log else {
        return (None, false, "log unreadable".to_owned(), None);
    };
    let grid = f.grid.as_deref().and_then(|g| g.get(..4));
    if log.dupe(p.dupes, &f.from, band, ModeClass::Digital, grid) {
        let value = ContestValue {
            dupe: true,
            ..ContestValue::default()
        };
        return (None, false, "dupe".to_owned(), Some(value));
    }
    let call_guard = if p.dupes == Dupes::BandGrid {
        // A rover counts again from a new grid (AVHF 2.2).
        f.from.trim_end_matches("/R")
    } else {
        f.from.as_str()
    };
    let calls_me = st.calls_me(f);
    if !calls_me {
        if !sane_call(call_guard) {
            return (None, false, "callsign guard".to_owned(), None);
        }
        if !st.cq_like(f, true) {
            return (None, false, "not a CQ".to_owned(), None);
        }
    }
    let value = ContestValue {
        dupe: false,
        new_multiplier: p
            .multipliers
            .key(band, grid)
            .is_some_and(|m| !log.multipliers.contains(&m)),
        points: p
            .points
            .of(st.my_locator.as_deref(), grid, band, ModeClass::Digital),
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
        why.push(format!("{n} points"));
    }
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
/// WstxContest::ContestValueOrder, smaller first: callers of my call, a new multiplier, more
/// points, the stronger SNR, then for an exact tie only the lower audio frequency and the call.
pub(crate) fn order(a: &Verdict, b: &Verdict) -> std::cmp::Ordering {
    order_by(a, b, true)
}
/// #97 ContestValueOrder with the contest strategy's callers_first: off, callers rank by value.
pub(crate) fn order_by(a: &Verdict, b: &Verdict, callers_first: bool) -> std::cmp::Ordering {
    let key = |v: &Verdict| {
        let c = v.contest.unwrap_or_default();
        (
            callers_first && v.kind != Some(Kind::Caller),
            !c.new_multiplier,
            std::cmp::Reverse(c.points.unwrap_or(0)),
        )
    };
    key(a)
        .cmp(&key(b))
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
