#![forbid(unsafe_code)]
// Proves: CL-055-01, CL-055-02; TC-055-001 (known answers against the bundled cty.dat and
// WSJT-X's own Radio::effective_prefix unit vectors) and TC-055-002 (worked categories).
// The expected entities, zones and names are read from the cty.dat lines cited beside
// each case and WSJT-X logbook/AD1CCty.cpp, not from this resolver's output.
use super::*;
use serde_json::json;

fn bundled() -> Table {
    Table::default()
}
fn row(t: &Table, call: &str) -> Option<(String, String, String, &'static str, u8, u8)> {
    t.lookup(call).map(|r| {
        (
            r.name,
            r.display,
            r.prefix,
            r.continent,
            r.cq_zone,
            r.itu_zone,
        )
    })
}
fn e(
    name: &str,
    display: &str,
    prefix: &str,
    cont: &'static str,
    cq: u8,
    itu: u8,
) -> Option<(String, String, String, &'static str, u8, u8)> {
    Some((name.into(), display.into(), prefix.into(), cont, cq, itu))
}

// Proves: TC-055-001
#[test]
fn tc_055_001_effective_prefix_matches_wsjtx_unit_vectors() {
    // WSJT-X tests/unit/common/test_radio_callsign.cpp identity_data, each with the
    // suffixes "", /P, /QRP and /P/QRP.
    for (call, prefix) in [
        ("K1ABC", "K1ABC"),
        ("EA8/K1ABC", "EA8"),
        ("K1ABC/EA8", "EA8"),
        ("EA8/K1A", "EA8"),
    ] {
        for suffix in ["", "/P", "/QRP", "/P/QRP"] {
            assert_eq!(
                effective_prefix(&format!("{call}{suffix}")),
                prefix,
                "{call}{suffix}"
            );
        }
    }
    assert_eq!(
        effective_prefix("W1AW/4"),
        "W1AW",
        "a digit suffix is operating"
    );
    assert_eq!(effective_prefix("DL/HB9BLA/M"), "DL");
    assert_eq!(effective_prefix("HB9BLA/LGT"), "HB9BLA");
}

// Proves: TC-055-001
#[test]
fn tc_055_001_known_answers_from_the_bundled_file() {
    let t = bundled();
    let usa = e("United States", "U.S.A.", "K", "NA", 5, 8); // line 1251
    let swiss = e("Switzerland", "Switzerland", "HB", "EU", 14, 28); // line 1118
    let germany = e("Fed. Rep. of Germany", "Germany", "DL", "EU", 14, 28); // line 669
    let canary = e("Canary Islands", "Canary Is.", "EA8", "AF", 33, 36); // line 751
    let gitmo = e("Guantanamo Bay", "Guantanamo Bay", "KG4", "NA", 8, 11); // line 2344
    let fiji = e("Fiji", "Fiji", "3D2", "OC", 32, 56); // line 19
    for (call, expected) in [
        // ordinary prefixes, longest match
        ("HB9BLA", swiss.clone()),
        ("hb9bla", swiss.clone()),
        ("K1ABC", usa.clone()),
        ("DL1XYZ", germany.clone()),
        ("EA8ABC", canary.clone()),
        // portable and operating suffixes
        ("HB9BLA/P", swiss.clone()),
        ("HB9BLA/QRP", swiss.clone()),
        ("HB9BLA/P/QRP", swiss.clone()),
        ("W1AW/4", usa.clone()),
        // compound calls: the shorter side is the prefix
        ("DL/HB9BLA", germany.clone()),
        ("HB9BLA/DL", germany.clone()),
        ("EA8/K1ABC", canary.clone()),
        ("K1ABC/EA8", canary.clone()),
        // maritime and aeronautical mobile have no entity
        ("HB9BLA/MM", None),
        ("K1ABC/AM", None),
        // KG4: 2x1 (5 characters) Guantanamo, other lengths mainland US
        ("KG4AB", gitmo.clone()),
        ("KG4ABC", usa.clone()),
        ("KG4AB/P", usa.clone()),
        // exact calls (=CALL) only for the whole call
        (
            "3D2CR",
            e("Conway Reef", "Conway Reef", "3D2/c", "OC", 32, 56),
        ), // line 21
        ("3D2CR/P", fiji.clone()),
        ("3D2ABC", fiji.clone()),
        (
            "3D2AG/P",
            e("Rotuma Island", "Rotuma Is.", "3D2/r", "OC", 32, 56),
        ), // line 23
        ("W1AW/KG4", gitmo.clone()),
        // zone overrides (n)[n] of a prefix and of an exact compound call
        (
            "RA0DAA",
            e("Asiatic Russia", "AS Russia", "UA9", "AS", 19, 33),
        ), // RA0(19)[33], line 3385
        (
            "RA0ABC",
            e("Asiatic Russia", "AS Russia", "UA9", "AS", 18, 32),
        ), // longer RA0A(18)[32], line 3656
        (
            "RA9ABC",
            e("Asiatic Russia", "AS Russia", "UA9", "AS", 17, 30),
        ),
        ("KG4IJS/0", e("United States", "U.S.A.", "K", "NA", 4, 7)), // line 1280
        // WAE entities are shown as their DXCC but keep their own name
        ("IT9ABC", e("Sicily", "Italy", "IT9", "EU", 15, 28)), // line 1206
        (
            "4U1VIC",
            e("Vienna Intl Ctr", "Austria", "4U1V", "EU", 15, 28),
        ), // line 50
        (
            "2M0BDR",
            e("Shetland Islands", "Scotland", "GM/s", "EU", 14, 27),
        ), // line 1014
        // a key listed twice keeps its first entity: =GB3LER is Scotland (line 955)
        // before Shetland (line 1016)
        ("GB3LER", e("Scotland", "Scotland", "GM", "EU", 14, 27)),
        // WSJT-X abbreviations
        (
            "FO5ABC",
            e("French Polynesia", "Fr.Polynesia", "FO", "OC", 32, 63),
        ), // line 823
        (
            "UA3ABC",
            e("European Russia", "EU Russia", "UA", "EU", 16, 29),
        ), // line 3132
        // no entity
        ("Q1ABC", None),
        ("", None),
    ] {
        assert_eq!(row(&t, call), expected, "{call}");
    }
    let us = t.lookup("K1ABC").unwrap();
    assert_eq!(
        (us.lat, us.lon),
        (37.60, -91.87),
        "cty.dat longitude is positive West"
    );
    assert_eq!(t.cty.version(), Some("VER20250115"));
    assert_eq!(t.cty.entity_count(), 346);
    assert!(!t.uploaded);
}

// Proves: TC-055-001
#[test]
fn tc_055_001_overrides_and_refused_files() {
    // A hand-written file in the cty.dat format with every override kind.
    let text = "Alpha Islands:  10: 20: NA:  10.00:  20.00:  -1.0:  AA:\n    AA,AB(3)[4],=AA1X<1.5/-2.5>,AC{SA}~-3.0~,\n    =AA9Z;\nBeta:  11: 21: EU: 50.00: -8.00: 1.0: *BB:\n    BB,AA2,AB;\n";
    let t = Table::uploaded(Cty::parse(text).unwrap());
    let r = |c: &str| t.lookup(c).unwrap();
    assert_eq!(
        (r("AA5Q").display.as_str(), r("AA5Q").cq_zone),
        ("Alpha Is.", 10)
    );
    assert_eq!((r("AB5Q").cq_zone, r("AB5Q").itu_zone), (3, 4));
    assert_eq!((r("AA1X").lat, r("AA1X").lon), (1.5, 2.5));
    assert_eq!(r("AA1XY").lat, 10.0, "an exact entry is not a prefix");
    assert_eq!(r("AC1A").continent, "SA");
    assert_eq!(
        (r("AA2B").name.as_str(), r("AA2B").prefix.as_str()),
        ("Beta", "BB")
    );
    assert!(t.cty.version().is_none());
    // The first entry of a key wins: Beta lists AB again, AB stays Alpha.
    assert_eq!(r("AB5Q").name, "Alpha Islands");
    assert_eq!(r("AA9Z").name, "Alpha Islands");
    for (bad, line) in [
        ("X: 1: 2: XX: 0: 0: 0: X:\n X;\n", 1),
        ("X: 1: 2: EU: 0: 0: 0: X:\n X(a);\n", 1),
        ("X: 1: 2: EU: 0: 0: 0: X:\n X,\n", 1),
        (
            "ok: 1: 2: EU: 0: 0: 0: OK:\n OK;\nX: 1: z: EU: 0: 0: 0: X:\n X;\n",
            3,
        ),
        ("no entity lines at all\n", 1),
    ] {
        assert_eq!(Cty::parse(bad).err(), Some(line), "{bad}");
    }
}

// Proves: TC-055-002
#[test]
fn tc_055_002_new_dxcc_band_continent_and_zone_against_the_log() {
    let t = bundled();
    // Logged: DL1ABC on 20m (Germany, EU, CQ 14, ITU 28), K1ABC with no band known.
    let logged = vec![
        ("DL1ABC".to_owned(), Some("20m".to_owned())),
        ("K1ABC".to_owned(), None),
        ("Q1ABC".to_owned(), Some("40m".to_owned())),
    ];
    let w = Worked::from_log(&t, &logged);
    let flags = |call: &str, band: Option<&str>| w.new_flags(&t.lookup(call).unwrap(), band);
    let band_flags = [
        "new_dxcc_band",
        "new_continent_band",
        "new_cq_zone_band",
        "new_itu_zone_band",
    ];
    assert_eq!(
        flags("DL2XYZ", Some("20m")),
        Vec::<&str>::new(),
        "Germany on 20m worked"
    );
    assert_eq!(flags("DL2XYZ", Some("40M")), band_flags);
    assert_eq!(
        flags("DL2XYZ", None),
        Vec::<&str>::new(),
        "no band: no band flags"
    );
    // Switzerland: new DXCC, but EU and CQ 14 / ITU 28 are worked (Germany) on 20m.
    assert_eq!(flags("HB9BLA", Some("20m")), ["new_dxcc", "new_dxcc_band"]);
    // A US call: entity worked ever (no band), so only the band flags.
    assert_eq!(flags("W1AW", Some("20m")), band_flags);
    assert_eq!(flags("JA1XYZ", Some("20m")), NEW_FLAGS);
    // Sicily is its own (WAE) name for worked status, as in WSJT-X.
    let italy = Worked::from_log(&t, &[("I1ABC".into(), Some("20m".into()))]);
    assert!(
        italy
            .new_flags(&t.lookup("IT9ABC").unwrap(), Some("20m"))
            .contains(&"new_dxcc")
    );
    // JN47AA (47.0208, 8.0417) to 37.60 N 91.87 W: hand haversine, R 6371 km.
    let us = t.lookup("K1ABC").unwrap();
    assert_eq!(
        compact(&us, crate::strategy::maidenhead("JN47AA")),
        json!({"name":"U.S.A.","cont":"NA","cq":5,"itu":8,"km":7706})
    );
    assert_eq!(
        compact(&us, None),
        json!({"name":"U.S.A.","cont":"NA","cq":5,"itu":8})
    );
}

// Proves: TC-055-002 the actual /receive/results route adds dxcc and only the flags that
// hold to each decoded sender, from the profile log and the station band.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_055_002_receive_results_carry_entity_and_new_flags() {
    use crate::automation_tests::{at_even, publish};
    let f = crate::mcp_tests::station(false).await;
    let adi = "<call:6>DL1ABC <gridsquare:4>JO62 <qso_date:8>20261031 <time_on:4>1230 <band:3>20m <mode:3>FT8 <eor>\n<call:5>K1ABC <gridsquare:4>FN42 <qso_date:8>20261031 <time_on:4>1240 <band:3>40m <mode:3>FT8 <eor>\n";
    let id = crate::profile::new_uuid().unwrap();
    let open = |publish: &mut dyn FnMut() -> std::io::Result<()>| -> Result<std::io::Result<()>, crate::authorization::Error> { Ok(publish()) };
    let sha: String = ring::digest::digest(&ring::digest::SHA256, adi.as_bytes())
        .as_ref()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    let now = std::time::Instant::now();
    f.state
        .logbook
        .reserve(&id, adi.len() as u64, &sha, now)
        .unwrap();
    f.state
        .logbook
        .chunk(&id, 0, adi.len() as u64, adi.as_bytes(), now, &open)
        .unwrap();
    assert_eq!(f.state.logbook.total().unwrap(), 2);
    let (source, job, generation) = f.state.recording.fixture_live_job("ft8");
    let e = at_even(&f);
    publish(
        &f,
        e,
        &[
            ("CQ K1ABC FN42", 1000.0, Some(-5.0)),
            ("CQ DL2XYZ JO62", 1100.0, Some(-5.0)),
            ("CQ JA1XYZ PM95", 1200.0, Some(-5.0)),
            ("HB9BLA G4ABC IO91", 1300.0, Some(-5.0)),
            ("TNX BOB 73 GL", 1400.0, Some(-5.0)),
        ],
    );
    let uri = format!(
        "/receive/results?source_id={source}&job_id={job}&generation={generation}&cursor=0&limit=16"
    );
    async fn read(f: &crate::mcp_tests::Mcp, uri: &str) -> Value {
        f.browser("GET", uri, None).await.json["records"].clone()
    }
    let pick = |r: &Value| (r["dxcc"].clone(), r["flags"].clone());
    let flags = |names: &[&str]| {
        Value::Object(names.iter().map(|n| (n.to_string(), json!(true))).collect())
    };
    // No band known: no _band flag; K1ABC, FN42 and the US are all worked ever.
    let records = read(&f, &uri).await;
    assert_eq!(records.as_array().unwrap().len(), 5);
    let us = json!({"name":"U.S.A.","cont":"NA","cq":5,"itu":8,"km":7706});
    assert_eq!(pick(&records[0]), (us.clone(), Value::Null));
    assert_eq!(pick(&records[1]).1, flags(&["new_call"]));
    assert_eq!(
        (records[4].get("dxcc"), records[4].get("flags")),
        (None, None),
        "free text"
    );

    f.state.recording.fixture_band("20m");
    let records = read(&f, &uri).await;
    assert_eq!(
        pick(&records[0]),
        (
            us,
            flags(&[
                "new_call_band",
                "new_grid_band",
                "new_dxcc_band",
                "new_continent_band",
                "new_cq_zone_band",
                "new_itu_zone_band"
            ])
        )
    );
    // Germany (465 km) with JO62 worked on 20m FT8: only the call is new.
    assert_eq!(
        pick(&records[1]),
        (
            json!({"name":"Germany","cont":"EU","cq":14,"itu":28,"km":465}),
            flags(&["new_call", "new_call_band"])
        )
    );
    let mut all = vec!["new_call", "new_call_band", "new_grid", "new_grid_band"];
    all.extend(NEW_FLAGS);
    assert_eq!(pick(&records[2]).1, flags(&all));
    assert_eq!(records[2]["dxcc"]["name"], "Japan");
    // England: EU and CQ 14 worked on 20m (Germany), ITU 27 is not.
    assert_eq!(
        pick(&records[3]).1,
        flags(&[
            "new_call",
            "new_call_band",
            "new_grid",
            "new_grid_band",
            "new_dxcc",
            "new_dxcc_band",
            "new_itu_zone",
            "new_itu_zone_band"
        ])
    );
}
