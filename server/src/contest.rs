#![forbid(unsafe_code)]
//! WstxContest (#63): the contest profiles from the official rules and their schedule. A new
//! contest is one more entry of PROFILES; a profile holds rule facts only, no behaviour.
use crate::contact::{Activity, civil, parse_utc};
use serde_json::{Value, json};

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
    "6m", "4m", "2m", "1.25m", "70cm", "33cm", "23cm", "13cm", "9cm", "6cm", "3cm", "1.25cm",
    "6mm", "4mm", "2.5mm", "2mm", "1mm",
];
const FIELD_DAY: &[&str] = &[
    "160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m", "1.25m", "70cm", "33cm", "23cm", "13cm",
    "9cm", "6cm", "3cm", "1.25cm", "6mm", "4mm", "2.5mm", "2mm", "1mm",
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
