#![forbid(unsafe_code)]
// Proves: CL-063-01; TC-063-001, TC-063-002. Hand tables from the rule sources listed on #63
// (the dates by a calendar, not by the schedule code).
use super::*;
use crate::contact::parse_utc;

fn profile(id: &str) -> Option<&'static Profile> {
    PROFILES.iter().find(|p| p.id == id)
}
fn at(text: &str) -> i64 {
    parse_utc(text).expect("a test instant")
}
fn period(id: &str, now: &str) -> Option<(String, String, Option<&'static str>)> {
    let p = profile(id).expect("a profile");
    p.next_period(at(now))
        .map(|o| (utc_text(o.start_ms), utc_text(o.end_ms), o.band))
}
fn when(start: &str, end: &str) -> Option<(String, String, Option<&'static str>)> {
    Some((start.to_owned(), end.to_owned(), None))
}

// Proves: TC-063-001
#[test]
fn tc_063_001_the_profile_table_holds_the_rule_facts() {
    let table: Vec<(&str, Activity, Dupes, Points, Multipliers, AutomationClause)> = PROFILES
        .iter()
        .map(|p| {
            (
                p.id,
                p.activity,
                p.dupes,
                p.points,
                p.multipliers,
                p.automation,
            )
        })
        .collect();
    use AutomationClause::{Forbidden, Silent};
    assert_eq!(
        table,
        vec![
            (
                "ww_digi",
                Activity::WwDigi,
                Dupes::Band,
                Points::OnePlusPer3000Km,
                Multipliers::FieldPerBand,
                Forbidden
            ),
            (
                "arrl_digi",
                Activity::ArrlDigi,
                Dupes::Band,
                Points::OnePlusPer500KmUp,
                Multipliers::None,
                Forbidden
            ),
            (
                "arrl_field_day",
                Activity::FieldDay,
                Dupes::BandModeClass,
                Points::FieldDay,
                Multipliers::None,
                Forbidden
            ),
            (
                "arrl_vhf_jan",
                Activity::NaVhf,
                Dupes::BandGrid,
                Points::VhfJanuary,
                Multipliers::GridPerBand,
                Forbidden
            ),
            (
                "arrl_vhf_jun",
                Activity::NaVhf,
                Dupes::BandGrid,
                Points::VhfJuneSeptember,
                Multipliers::GridPerBand,
                Forbidden
            ),
            (
                "arrl_vhf_sep",
                Activity::NaVhf,
                Dupes::BandGrid,
                Points::VhfJuneSeptember,
                Multipliers::GridPerBand,
                Forbidden
            ),
            (
                "iaru_50_mgm",
                Activity::None,
                Dupes::Band,
                Points::Kilometres,
                Multipliers::GridPerBand,
                Silent
            ),
            (
                "iaru_70_mgm",
                Activity::None,
                Dupes::Band,
                Points::Kilometres,
                Multipliers::GridPerBand,
                Silent
            ),
            (
                "ft8_activity",
                Activity::None,
                Dupes::Call,
                Points::OnePerCall,
                Multipliers::GridPerBand,
                Silent
            ),
        ]
    );
    let bands = |id: &str| profile(id).expect("a profile").bands.to_vec();
    assert_eq!(
        bands("ww_digi"),
        ["160m", "80m", "40m", "20m", "15m", "10m"],
        "WWD II: six bands only"
    );
    assert_eq!(
        bands("arrl_digi"),
        ["160m", "80m", "40m", "20m", "15m", "10m", "6m"],
        "ADC 2.1"
    );
    assert_eq!(bands("iaru_50_mgm"), ["6m"]);
    assert_eq!(bands("iaru_70_mgm"), ["4m"]);
    assert_eq!(bands("ft8_activity"), ["2m", "70cm", "23cm"]);
    assert!(bands("arrl_vhf_jun").contains(&"6m") && !bands("arrl_vhf_jun").contains(&"10m"));
    assert!(bands("arrl_field_day").contains(&"40m") && !bands("arrl_field_day").contains(&"30m"));
    // RTTY Roundup is dropped (operator 2026-11-06); no id twice.
    assert!(profile("rtty").is_none() && profile("arrl_rtty").is_none());
    let mut ids: Vec<&str> = PROFILES.iter().map(|p| p.id).collect();
    ids.sort_unstable();
    ids.dedup();
    assert_eq!(ids.len(), PROFILES.len());
    // The clauses as the rules word them, and an unconfirmed Cabrillo name stays marked.
    let ww = profile("ww_digi").expect("a profile");
    assert!(
        ww.automation_text
            .contains("A human operator must initiate")
    );
    assert_eq!(
        (ww.cabrillo, ww.cabrillo_confirmed),
        (Some("WW-DIGI"), true)
    );
    let fd = profile("arrl_field_day").expect("a profile");
    assert!(fd.automation_text.contains("Fully automated contacts"));
    assert!(!fd.cabrillo_confirmed);
    let vhf = profile("arrl_vhf_jun").expect("a profile");
    assert!(vhf.notes.iter().any(|n| n.contains("W/VE")), "AVHF 2.3");
    assert!(fd.notes.iter().any(|n| n.contains("check-log")), "AFD 1");
    let digi = profile("arrl_digi").expect("a profile");
    assert!(digi.notes.iter().any(|n| n.contains("24 of 30")), "ADC 1.1");
    let iaru = profile("iaru_50_mgm").expect("a profile");
    assert!(iaru.automation_text.contains("do not address"));
    assert!(
        iaru.notes.iter().any(|n| n.contains("6 hours")),
        "6H section"
    );
    assert!(
        profile("ft8_activity")
            .expect("a profile")
            .automation_text
            .contains("do not address")
    );
}

// Proves: TC-063-002
#[test]
fn tc_063_002_the_period_comes_from_the_rule() {
    // From before each 2026 occurrence.
    for (id, start, end) in [
        ("ww_digi", "2026-08-29T12:00Z", "2026-08-30T12:00Z"),
        ("arrl_digi", "2026-06-06T18:00Z", "2026-06-08T00:00Z"),
        ("arrl_field_day", "2026-06-27T18:00Z", "2026-06-28T21:00Z"),
        ("arrl_vhf_jun", "2026-06-13T18:00Z", "2026-06-15T03:00Z"),
        ("arrl_vhf_sep", "2026-09-12T18:00Z", "2026-09-14T03:00Z"),
        ("iaru_50_mgm", "2026-04-18T14:00Z", "2026-04-19T14:00Z"),
        ("iaru_70_mgm", "2026-05-16T14:00Z", "2026-05-17T14:00Z"),
    ] {
        assert_eq!(period(id, "2026-01-01T00:00:00Z"), when(start, end), "{id}");
    }
    // January VHF is never computed: the prompt asks.
    assert_eq!(period("arrl_vhf_jan", "2026-01-01T00:00:00Z"), None);
    // During the contest it is the current one, at its end the next year's.
    assert_eq!(
        period("ww_digi", "2026-08-30T11:59:59Z"),
        when("2026-08-29T12:00Z", "2026-08-30T12:00Z")
    );
    assert_eq!(
        period("ww_digi", "2026-08-30T12:00:00Z"),
        when("2027-08-28T12:00Z", "2027-08-29T12:00Z")
    );
    // A full weekend has both days in the month: 2024-08-31 is a Saturday with its Sunday in
    // September, so the last full one is the 24th; 2025-06-01 is a Sunday, so the first full
    // one is the 7th.
    assert_eq!(
        period("ww_digi", "2024-01-01T00:00:00Z"),
        when("2024-08-24T12:00Z", "2024-08-25T12:00Z")
    );
    assert_eq!(
        period("arrl_digi", "2025-01-01T00:00:00Z"),
        when("2025-06-07T18:00Z", "2025-06-09T00:00Z")
    );
    // FT8 Activity: the nearest round of its three, with the band of that round.
    let fta = |now: &str| period("ft8_activity", now);
    assert_eq!(
        fta("2026-11-01T00:00:00Z"),
        Some((
            "2026-11-04T17:00Z".to_owned(),
            "2026-11-04T21:00Z".to_owned(),
            Some("2m")
        ))
    );
    assert_eq!(
        fta("2026-11-04T21:00:00Z"),
        Some((
            "2026-11-11T17:00Z".to_owned(),
            "2026-11-11T21:00Z".to_owned(),
            Some("70cm")
        ))
    );
    assert_eq!(
        fta("2026-11-12T00:00:00Z"),
        Some((
            "2026-11-18T17:00Z".to_owned(),
            "2026-11-18T21:00Z".to_owned(),
            Some("23cm")
        ))
    );
    // Across the year end: December 2026's third round is over, January 2027's first is the 6th.
    assert_eq!(
        fta("2026-12-17T00:00:00Z"),
        Some((
            "2027-01-06T17:00Z".to_owned(),
            "2027-01-06T21:00Z".to_owned(),
            Some("2m")
        ))
    );
}

// Proves: TC-063-003
#[test]
fn tc_063_003_the_list_names_each_profile_with_its_period() {
    let list = profiles_json(at("2026-08-01T00:00:00Z"));
    let ids: Vec<&str> = list
        .as_array()
        .expect("a list")
        .iter()
        .filter_map(|p| p["id"].as_str())
        .collect();
    assert_eq!(
        ids,
        [
            "ww_digi",
            "arrl_digi",
            "arrl_field_day",
            "arrl_vhf_jan",
            "arrl_vhf_jun",
            "arrl_vhf_sep",
            "iaru_50_mgm",
            "iaru_70_mgm",
            "ft8_activity"
        ]
    );
    let ww = &list[0];
    assert_eq!(
        ww["period"],
        json!({"start":"2026-08-29T12:00Z","end":"2026-08-30T12:00Z","band":null})
    );
    assert_eq!(ww["activity"], "ww_digi");
    assert_eq!(ww["automation"], "forbidden");
    assert_eq!(ww["dupes"], "band");
    assert_eq!(ww["points"], "one_plus_per_3000_km");
    assert_eq!(ww["multipliers"], "field_per_band");
    assert_eq!(
        list[3]["period"],
        Value::Null,
        "January VHF: the prompt asks"
    );
    assert_eq!(list[6]["automation"], "silent");
    assert_eq!(list[6]["activity"], "none");
}
