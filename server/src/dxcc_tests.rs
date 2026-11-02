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
        ("DL\u{e9}1AB", None), // non-ASCII text (an imported ADIF call) never panics
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
        // values the browser would refuse (it would stop Band Activity): CQ zone over
        // 40, ITU zone over 90 (also as overrides), an empty or long or non-ASCII name
        ("X: 41: 2: EU: 0: 0: 0: X:\n X;\n", 1),
        ("X: 1: 91: EU: 0: 0: 0: X:\n X;\n", 1),
        ("X: 1: 2: EU: 0: 0: 0: X:\n X(41);\n", 1),
        ("X: 1: 2: EU: 0: 0: 0: X:\n X[91];\n", 1),
        (" : 1: 2: EU: 0: 0: 0: X:\n X;\n", 1),
        (
            "Xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx1: 1: 2: EU: 0: 0: 0: X:\n X;\n",
            1,
        ),
        ("Z\u{fc}rich: 1: 2: EU: 0: 0: 0: X:\n X;\n", 1),
    ] {
        assert_eq!(Cty::parse(bad).err(), Some(line), "{bad}");
    }
}

// Proves: TC-055-002
#[test]
fn tc_055_002_new_dxcc_band_continent_and_zone_against_the_log() {
    let t = bundled();
    // Logged: DL1ABC on 20m (Germany, EU, CQ 14, ITU 28), K1ABC with no band known.
    let log = |call: &str, grid: Option<&str>, band: Option<&str>| Logged {
        call: call.into(),
        grid: grid.map(Into::into),
        band: band.map(Into::into),
    };
    let logged = vec![
        log("DL1ABC", Some("JO62"), Some("20m")),
        log("K1ABC", None, None),
        log("Q1ABC", None, Some("40m")),
    ];
    let w = Worked::from_log(&t, &logged);
    // The entity flags of a call (its call and grid flags left out).
    let flags = |call: &str, band: Option<&str>| {
        let mut f = w.flags(call, None, t.lookup(call).as_ref(), band);
        f.retain(|n| !n.starts_with("new_call"));
        f
    };
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
    assert_eq!(flags("JA1XYZ", Some("20m")), FLAGS[4..]);
    // Call and grid: case-insensitive, the 4-character square; no grid, no grid flag;
    // an unresolved call still has its call flags.
    assert_eq!(
        w.flags("dl1abc", Some("jo62xx"), None, Some("20m")),
        Vec::<&str>::new()
    );
    assert_eq!(
        w.flags("DL1ABC", Some("JO62"), None, Some("40m")),
        ["new_call_band", "new_grid_band"]
    );
    assert_eq!(w.flags("Q1ABC", None, None, None), Vec::<&str>::new());
    assert_eq!(
        w.flags("Q2ABC", Some("AA00"), None, None),
        ["new_call", "new_grid"]
    );
    // Sicily is its own (WAE) name for worked status, as in WSJT-X.
    let italy = Worked::from_log(&t, &[log("I1ABC", None, Some("20m"))]);
    assert!(
        italy
            .flags("IT9ABC", None, t.lookup("IT9ABC").as_ref(), Some("20m"))
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
    // W1AW was worked on 20m in FT4: on 20m FT8 it is not new on the band (WSJT-X
    // highlights by band, not mode, by default).
    let adi = "<call:6>DL1ABC <gridsquare:4>JO62 <qso_date:8>20261031 <time_on:4>1230 <band:3>20m <mode:3>FT8 <eor>\n<call:5>K1ABC <gridsquare:4>FN42 <qso_date:8>20261031 <time_on:4>1240 <band:3>40m <mode:3>FT8 <eor>\n<call:4>W1AW <gridsquare:4>FN31 <qso_date:8>20261031 <time_on:4>1250 <band:3>20m <mode:4>MFSK <submode:3>FT4 <eor>\n";
    fn import(f: &crate::mcp_tests::Mcp, adi: &str) {
        let id = crate::profile::new_uuid().unwrap();
        let open = |publish: &mut dyn FnMut() -> std::io::Result<()>| -> Result<std::io::Result<()>, crate::authorization::Error> { Ok(publish()) };
        let sha: String = ring::digest::digest(&ring::digest::SHA256, adi.as_bytes())
            .as_ref()
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect();
        let now = std::time::Instant::now();
        let log = &f.state.logbook;
        log.reserve(&id, adi.len() as u64, &sha, now).unwrap();
        log.chunk(&id, 0, adi.len() as u64, adi.as_bytes(), now, &open)
            .unwrap();
    }
    import(&f, adi);
    assert_eq!(f.state.logbook.total().unwrap(), 3);
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
            ("CQ W1AW FN31", 1500.0, Some(-5.0)),
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
    assert_eq!(records.as_array().unwrap().len(), 6);
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
    // K1ABC and FN42 only on 40m; the US (W1AW) on 20m in another mode.
    assert_eq!(
        pick(&records[0]),
        (us, flags(&["new_call_band", "new_grid_band"]))
    );
    assert_eq!(
        pick(&records[5]).1,
        Value::Null,
        "same band, other mode: nothing new"
    );
    // Germany (465 km) with JO62 worked on 20m FT8: only the call is new.
    assert_eq!(
        pick(&records[1]),
        (
            json!({"name":"Germany","cont":"EU","cq":14,"itu":28,"km":465}),
            flags(&["new_call", "new_call_band"])
        )
    );
    assert_eq!(pick(&records[2]).1, flags(&FLAGS));
    // A contact logged later counts at once (the cached worked set follows the log).
    import(
        &f,
        "<call:6>DL2XYZ <qso_date:8>20261101 <time_on:4>0800 <band:3>20m <mode:3>FT8 <eor>\n",
    );
    assert_eq!(pick(&read(&f, &uri).await[1]).1, Value::Null);
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
