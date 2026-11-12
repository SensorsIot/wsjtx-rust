#![forbid(unsafe_code)]
// Proves: CL-063-05; TC-063-009.
// Proves: CL-063-01, CL-063-03, CL-063-04; TC-063-001, TC-063-002, TC-063-005, TC-063-006. Hand tables from the rule sources listed on #63
// (the dates by a calendar, not by the schedule code).
use super::*;
use crate::contact::parse_utc;

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
    // "All bands 50 MHz and above" (AFD 2), "any band above 50 MHz" (AVHF 2.1).
    for band in ["6m", "5m", "4m", "2m", "submm"] {
        assert!(bands("arrl_field_day").contains(&band), "Field Day {band}");
        assert!(bands("arrl_vhf_jun").contains(&band), "VHF {band}");
    }
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

fn selection(id: &str, start: &str, end: &str) -> Selection {
    parse_selection(&json!({"profile":id,"start":start,"end":end}), "contest").expect("a selection")
}
fn qso(call: &str, grid: Option<&str>, band: &str, mode: &str, when: &str) -> Qso {
    Qso {
        call: call.into(),
        grid: grid.map(str::to_owned),
        band: Some(band.into()),
        mode: mode.into(),
        ms: at(when),
    }
}
const IN: &str = "2026-08-29T13:00:00Z";
fn ww() -> Selection {
    selection("ww_digi", "2026-08-29T12:00Z", "2026-08-30T12:00Z")
}

// Proves: TC-063-005
#[test]
fn tc_063_005_the_points_rules_by_hand() {
    use ModeClass::Digital as D;
    // Distances computed apart from this code (haversine, R 6371 km; IARU 111.2 km/degree):
    // JN37-FN42 5894.6 km, JN37-JO62 701.6, JN37-JN38 111.2, JN37-PM95 9624.3.
    for (mine, theirs, ww, digi, iaru) in [
        ("JN37", "FN42", 2, 13, 5895),
        ("JN37", "JO62", 1, 3, 702),
        ("JN37", "JN38", 1, 2, 112),
        ("JN37", "PM95", 4, 21, 9625),
    ] {
        let (m, t) = (Some(mine), Some(theirs));
        assert_eq!(Points::OnePlusPer3000Km.of(m, t, "20m", D), Some(ww));
        assert_eq!(Points::OnePlusPer500KmUp.of(m, t, "20m", D), Some(digi));
        assert_eq!(Points::Kilometres.of(m, t, "6m", D), Some(iaru));
    }
    // A locator of six characters scores by its square; the same large square is 50.
    assert_eq!(
        Points::Kilometres.of(Some("JN37VL"), Some("jn37"), "6m", D),
        Some(50)
    );
    assert_eq!(
        Points::OnePlusPer500KmUp.of(Some("JN37VL"), Some("JN37"), "20m", D),
        Some(2),
        "ADC 5.2: the minimum distance value is 1"
    );
    // No grid: no claim, where the rule needs one.
    assert_eq!(
        Points::OnePlusPer3000Km.of(Some("JN37"), None, "20m", D),
        None
    );
    assert_eq!(
        Points::OnePlusPer3000Km.of(None, Some("FN42"), "20m", D),
        None
    );
    assert_eq!(Points::OnePerCall.of(None, None, "2m", D), Some(1));
    // The band tables of AVHF 5.1 and 5.2.
    for (band, january, june) in [
        ("6m", 1, 1),
        ("2m", 1, 1),
        ("1.25m", 2, 2),
        ("70cm", 2, 2),
        ("33cm", 4, 3),
        ("23cm", 4, 3),
        ("13cm", 8, 4),
        ("3cm", 8, 4),
        ("submm", 8, 4),
    ] {
        assert_eq!(Points::VhfJanuary.of(None, None, band, D), Some(january));
        assert_eq!(Points::VhfJuneSeptember.of(None, None, band, D), Some(june));
    }
    // AFD 7.1.
    assert_eq!(Points::FieldDay.of(None, None, "20m", D), Some(2));
    assert_eq!(
        Points::FieldDay.of(None, None, "20m", ModeClass::Cw),
        Some(2)
    );
    assert_eq!(
        Points::FieldDay.of(None, None, "20m", ModeClass::Phone),
        Some(1)
    );
    // Multipliers.
    assert_eq!(
        Multipliers::FieldPerBand.key("20m", Some("fn42")),
        Some("FN|20m".to_owned())
    );
    assert_eq!(
        Multipliers::GridPerBand.key("6m", Some("FN42")),
        Some("FN42|6m".to_owned())
    );
    assert_eq!(Multipliers::None.key("20m", Some("FN42")), None);
    assert_eq!(Multipliers::GridPerBand.key("6m", None), None);
}

// Proves: TC-063-006
#[test]
fn tc_063_006_only_the_period_counts_and_each_dupe_rule() {
    let s = ww();
    let log = Log::of(
        &s,
        Some("JN37"),
        &[
            // Outside the period: before it, and at its exclusive end.
            qso("K1OUT", Some("FN42"), "20m", "FT8", "2026-08-29T11:59:59Z"),
            qso("K1END", Some("EM12"), "20m", "FT8", "2026-08-30T12:00:00Z"),
            qso("K1ABC", Some("FN42"), "20m", "FT8", IN),
            // FT4 on the same band is a dupe (WWD IV.B), another band is not.
            qso("K1ABC", Some("FN42"), "20m", "FT4", "2026-08-29T13:05:00Z"),
            qso("K1ABC", Some("FN42"), "40m", "FT8", "2026-08-29T13:10:00Z"),
            // SSB is no WW Digi QSO; 30 m is no WW Digi band.
            qso("W1SSB", Some("EM12"), "20m", "SSB", "2026-08-29T13:15:00Z"),
            qso("W1WRC", Some("EM12"), "30m", "FT8", "2026-08-29T13:20:00Z"),
        ],
    );
    assert_eq!(
        (log.qsos, log.multipliers.len()),
        (2, 2),
        "FN|20m and FN|40m"
    );
    assert_eq!(log.points, 4, "2 + 2: JN37-FN42 is 5894.6 km");
    assert_eq!(log.score(&s), 8);
    let class = ModeClass::Digital;
    let dupes = Dupes::Band;
    assert!(log.dupe(dupes, "K1ABC", "20m", class, None));
    assert!(!log.dupe(dupes, "K1ABC", "15m", class, None));
    assert!(
        !log.dupe(dupes, "K1OUT", "20m", class, None),
        "before the period"
    );
    assert!(!log.dupe(dupes, "K1END", "20m", class, None), "at the end");
    // ARRL VHF: per band and grid; a rover counts again from a new grid.
    let vhf = selection("arrl_vhf_jun", "2026-06-13T18:00Z", "2026-06-15T03:00Z");
    let at_vhf = "2026-06-13T19:00:00Z";
    let log = Log::of(
        &vhf,
        None,
        &[qso("K1ABC/R", Some("FN42"), "6m", "FT8", at_vhf)],
    );
    assert!(log.dupe(Dupes::BandGrid, "K1ABC/R", "6m", class, Some("FN42")));
    assert!(!log.dupe(Dupes::BandGrid, "K1ABC/R", "6m", class, Some("FN43")));
    assert!(log.dupe(Dupes::BandGrid, "K1ABC/R", "6m", class, None));
    // A logged QSO without a grid: every grid of that call on the band is a dupe.
    let log = Log::of(&vhf, None, &[qso("K1NOG", None, "6m", "SSB", at_vhf)]);
    assert!(log.dupe(Dupes::BandGrid, "K1NOG", "6m", class, Some("FN42")));
    // Field Day: per band and mode class; SSB does not dupe a digital QSO.
    let fd = selection("arrl_field_day", "2026-06-27T18:00Z", "2026-06-28T21:00Z");
    let at_fd = "2026-06-27T19:00:00Z";
    let log = Log::of(&fd, None, &[qso("K1ABC", None, "20m", "SSB", at_fd)]);
    assert!(!log.dupe(Dupes::BandModeClass, "K1ABC", "20m", class, None));
    assert!(log.dupe(Dupes::BandModeClass, "K1ABC", "20m", ModeClass::Phone, None));
    assert_eq!(log.points, 1);
    // FT8 Activity: one per call.
    let fta = selection("ft8_activity", "2026-11-04T17:00Z", "2026-11-04T21:00Z");
    let log = Log::of(
        &fta,
        None,
        &[qso(
            "DL1ABC",
            Some("JO62"),
            "2m",
            "FT4",
            "2026-11-04T18:00:00Z",
        )],
    );
    assert!(log.dupe(Dupes::Call, "DL1ABC", "70cm", class, None));
    assert_eq!(log.score(&fta), 1);
    // ARRL Digi counts no RTTY and has no multiplier: the score is the points.
    let digi = selection("arrl_digi", "2026-06-06T18:00Z", "2026-06-08T00:00Z");
    let at_digi = "2026-06-06T19:00:00Z";
    let log = Log::of(
        &digi,
        Some("JN37"),
        &[
            qso("W1RTY", Some("FN42"), "20m", "RTTY", at_digi),
            qso("K1ABC", Some("FN42"), "20m", "FT8", at_digi),
        ],
    );
    assert_eq!((log.qsos, log.points, log.score(&digi)), (1, 13, 13));
}

fn contest_station(band: &str) -> Station {
    Station {
        my_call: "HB9BLA".into(),
        my_continent: Some("EU".into()),
        my_locator: Some("JN37".into()),
        band: Some(band.into()),
        mode: "FT8".into(),
        activity: Activity::WwDigi,
        ..Station::default()
    }
}
fn rows(list: &[(&str, f64)]) -> Vec<Value> {
    list.iter()
        .enumerate()
        .map(|(i, (text, snr))| {
            let mut r =
                crate::contact_http_tests::record(text, 1000.0 + i as f64 * 100.0, Some(*snr));
            r["sequence"] = json!(i);
            r
        })
        .collect()
}

// Proves: TC-063-006
#[test]
fn tc_063_006_verdicts_callable_by_value() {
    let s = ww();
    let log = Log::of(
        &s,
        Some("JN37"),
        &[
            qso("W1DUP", Some("EM12"), "20m", "FT8", IN),
            qso("K1OLD", Some("FN20"), "20m", "FT8", IN),
        ],
    );
    let records = rows(&[
        // 0: FN already a multiplier on 20 m; 2 points; the strongest.
        ("CQ WW K1ABC FN42", 5.0),
        // 1: a new field, far: the most valuable.
        ("CQ WW JA1XYZ PM95", -18.0),
        // 2: a new field, near: fewer points.
        ("CQ WW OH1AA KP20", -3.0),
        // 3: a dupe of the period.
        ("CQ WW W1DUP EM12", 3.0),
        // 4: a CQ for another continent stays greyed.
        ("CQ NA W1AW FN31", 2.0),
        // 5: not a CQ.
        ("DL1ABC K1ZZZ FN42", 1.0),
        // 6: another station's RR73 counts as calling.
        ("DL1ABC W1RRR RR73", -9.0),
        // 7: a caller of mine, weak, comes first.
        ("HB9BLA VK2ABC QF56", -20.0),
        // 8: a dupe calling me is not answered by a strategy.
        ("HB9BLA K1OLD FN20", 9.0),
    ]);
    let list = evaluate(&s, &records, &contest_station("20m"), Some(&log));
    let ranked: Vec<(u64, usize)> = list
        .iter()
        .filter_map(|v| v.rank.map(|r| (v.facts.sequence, r)))
        .collect();
    assert_eq!(
        ranked,
        vec![(7, 0), (1, 1), (2, 2), (0, 3), (6, 4)],
        "caller; new multiplier by points; points; a 73 with no grid last"
    );
    let of = |seq: u64| {
        list.iter()
            .find(|v| v.facts.sequence == seq)
            .expect("a verdict")
    };
    assert_eq!(
        of(1).contest,
        Some(ContestValue {
            dupe: false,
            new_multiplier: true,
            points: Some(4)
        })
    );
    assert_eq!(of(1).why, "new multiplier \u{b7} 4 points");
    assert_eq!(
        of(0).contest.map(|c| (c.new_multiplier, c.points)),
        Some((false, Some(2)))
    );
    assert_eq!(of(3).contest.map(|c| c.dupe), Some(true));
    assert_eq!((of(3).rank, of(3).why.as_str()), (None, "dupe"));
    assert_eq!(
        (of(4).grey, of(4).why.as_str()),
        (true, "CQ NA \u{2014} not for EU")
    );
    assert_eq!(of(5).why, "not a CQ");
    assert_eq!(of(8).contest.map(|c| c.dupe), Some(true));
    assert_eq!(of(8).rank, None);
    // A band outside the contest: nothing is callable. Log unreadable: no claim.
    let none = evaluate(&s, &records, &contest_station("30m"), Some(&log));
    assert!(none.iter().all(|v| v.rank.is_none()));
    assert_eq!(
        none.iter()
            .find(|v| v.facts.sequence == 1)
            .expect("a verdict")
            .why,
        "band not in the contest"
    );
    let none = evaluate(&s, &records, &contest_station("20m"), None);
    assert!(none.iter().all(|v| v.rank.is_none()));
    // A verdict's wire form names the contest keys.
    let wire = of(1).json(false);
    assert_eq!(
        wire,
        json!({"sequence":1,"rank":1,"grey":false,"dupe":false,"new_multiplier":true,"points":4})
    );
    // Rovers pass the callsign guard only where a new grid counts (AVHF 2.2).
    let vhf = selection("arrl_vhf_jun", "2026-06-13T18:00Z", "2026-06-15T03:00Z");
    let rover = rows(&[("CQ K1ABC/R FN42", -3.0)]);
    let mut st = contest_station("6m");
    st.activity = Activity::NaVhf;
    assert_eq!(
        evaluate(&vhf, &rover, &st, Some(&Log::default()))[0].rank,
        Some(0)
    );
    let fta = selection("iaru_50_mgm", "2026-04-18T14:00Z", "2026-04-19T14:00Z");
    assert_eq!(
        evaluate(&fta, &rover, &st, Some(&Log::default()))[0].why,
        "callsign guard"
    );
}

// Proves: TC-063-006
#[test]
fn tc_063_006_a_field_day_exchange_to_my_call_is_a_caller() {
    let s = selection("arrl_field_day", "2026-06-27T18:00Z", "2026-06-28T21:00Z");
    let log = Log::of(
        &s,
        None,
        &[qso("K1OLD", None, "20m", "FT8", "2026-06-27T19:00:00Z")],
    );
    let exchange = |sequence: u64, from: &str, to: &str| {
        json!({"status":"decoded","sequence":sequence,"snr_db":-5.0,"fields":{"type":"field_day",
            "to":{"kind":"call","text":to},"from":{"kind":"call","text":from},"ack":false,
            "transmitters":6,"class":"A","section":"WI"}})
    };
    let records = [
        exchange(0, "K1OLD", "HB9BLA"),
        exchange(1, "W9XYZ", "HB9BLA"),
        exchange(2, "W9ABC", "K1ABC"),
    ];
    let mut st = contest_station("20m");
    st.activity = Activity::FieldDay;
    let list = evaluate(&s, &records, &st, Some(&log));
    let of = |seq: u64| {
        list.iter()
            .find(|v| v.facts.sequence == seq)
            .expect("a verdict")
    };
    assert_eq!((of(1).rank, of(1).kind), (Some(0), Some(Kind::Caller)));
    assert_eq!(of(1).contest.map(|c| c.points), Some(Some(2)), "AFD 7.1.3");
    assert_eq!((of(0).rank, of(0).why.as_str()), (None, "dupe"));
    assert_eq!(of(0).contest.map(|c| c.dupe), Some(true));
    assert_eq!((of(2).rank, of(2).why.as_str()), (None, "not a CQ"));
}

// Proves: TC-063-007
#[test]
fn tc_063_007_a_selection_is_parsed_exactly() {
    // #97 D11: {profile, start, end}; operation, repetitions and quiet_minutes are refused by
    // their own path.
    let good = json!({"profile":"ww_digi","start":"2026-08-29T12:00Z","end":"2026-08-30T12:00Z"});
    let s = parse_selection(&good, "contest").expect("a selection");
    assert_eq!(s.json(), good);
    for (key, value, field) in [
        ("profile", json!("rtty"), "contest.profile"),
        ("profile", json!(7), "contest.profile"),
        ("start", json!("2026-08-29 12:00"), "contest.start"),
        ("start", json!("2026-02-31T12:00Z"), "contest.start"),
        ("start", json!("2026-08-29T12:00:00Z"), "contest.start"),
        ("end", json!("2026-08-29T12:00Z"), "contest.end"),
        ("end", json!("2026-08-28T12:00Z"), "contest.end"),
        ("end", json!("2026-09-30T12:01Z"), "contest.end"),
        ("operation", json!("sp"), "contest.operation"),
        ("operation", Value::Null, "contest.operation"),
        ("repetitions", json!(2), "contest.repetitions"),
        ("quiet_minutes", json!(10), "contest.quiet_minutes"),
    ] {
        let mut bad = good.clone();
        bad[key] = value;
        assert_eq!(
            parse_selection(&bad, "contest").err().as_deref(),
            Some(field),
            "{bad}"
        );
    }
    let mut extra = good.clone();
    extra["x"] = json!(1);
    assert_eq!(
        parse_selection(&extra, "contest").err().as_deref(),
        Some("contest")
    );
    assert_eq!(
        parse_selection(&json!(1), "contest").err().as_deref(),
        Some("contest")
    );
}

// Proves: TC-063-009. strategydef: the confirmation goes with Auto on (POST /strategy/auto,
// strategy_tests.rs); a selection asks nothing, and colouring and automation_confirmed are
// refused on PUT with their field.
#[test]
fn tc_063_009_a_selection_asks_nothing_and_refuses_colouring_and_the_confirmation() {
    // #97 D11: a selection is {profile, start, end}; operation, repetitions and quiet_minutes
    // are refused by their own path (TC-097-015).
    let form = |id: &str, extra: Option<(&str, Value)>| {
        let mut v = json!({"profile":id,"start":"2026-08-29T12:00Z","end":"2026-08-30T12:00Z"});
        if let Some((k, x)) = extra {
            v[k] = x;
        }
        parse_selection(&v, "contest")
    };
    for id in [
        "ww_digi",
        "arrl_digi",
        "arrl_field_day",
        "arrl_vhf_jun",
        "iaru_50_mgm",
        "ft8_activity",
    ] {
        assert!(form(id, None).is_ok(), "{id}: nothing to confirm here");
        for c in [json!(true), json!(false), json!("yes")] {
            assert_eq!(
                form(id, Some(("automation_confirmed", c.clone())))
                    .err()
                    .as_deref(),
                Some("contest.automation_confirmed"),
                "{id} {c}"
            );
        }
        for (k, x) in [
            ("operation", json!("colouring")),
            ("operation", json!("run")),
            ("repetitions", json!(2)),
            ("quiet_minutes", json!(10)),
        ] {
            assert_eq!(
                form(id, Some((k, x))).err().as_deref(),
                Some(format!("contest.{k}").as_str()),
                "{id} {k}"
            );
        }
    }
    let s = form("ww_digi", None).expect("a selection");
    assert_eq!(
        s.json(),
        json!({"profile":"ww_digi","start":"2026-08-29T12:00Z","end":"2026-08-30T12:00Z"})
    );
    // The period holds its start and not its end.
    assert!(s.in_period(at("2026-08-29T12:00:00Z")));
    assert!(!s.in_period(at("2026-08-30T12:00:00Z")));
    assert!(!s.in_period(at("2026-08-29T11:59:59Z")));
}
