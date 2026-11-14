// Cost 2: isolated disposable profile directories; hand-authored ADIF 3.1.8 ADI
// fixtures and hand-written expected bytes/values (independent of the writer).
use super::*;

fn open_gate(
    publish: &mut dyn FnMut() -> std::io::Result<()>,
) -> Result<std::io::Result<()>, crate::authorization::Error> {
    Ok(publish())
}
const GATE: Gate = &open_gate;

pub(crate) struct Dir(pub(crate) PathBuf);
impl Dir {
    pub(crate) fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "wstx-logbook-{}",
            crate::profile::new_uuid().unwrap()
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
    fn file(&self) -> Option<Vec<u8>> {
        fs::read(self.0.join(FILE_NAME)).ok()
    }
    fn leftovers(&self) -> Vec<String> {
        fs::read_dir(&self.0)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .filter(|n| n.ends_with(".tmp"))
            .collect()
    }
}
impl Drop for Dir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

const ID1: &str = "11111111-1111-4111-8111-111111111111";
const ID2: &str = "22222222-2222-4222-8222-222222222222";

fn reviewed(id: &str, call: &str) -> Record {
    let v = |s: &str| Some(s.to_owned());
    Record {
        contact_id: id.into(),
        values: [
            v(call),
            v("FN42"),
            v("FT8"),
            None,
            v("-12"),
            v("-05"),
            v("20261031"),
            v("123015"),
            v("20261031"),
            v("123200"),
            v("20m"),
            v("14.075500"),
            v("HB9BLA"),
            v("JN47AA"),
            v("10"),
            v("Tnx QSO"),
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
        ],
        source: None,
        activity: None,
        unknown: Vec::new(),
    }
}
fn limits() -> Limits {
    Limits {
        records: IMPORT_RECORDS_MAX,
    }
}
/// Reserve and upload `bytes` in 16 KiB chunks; returns the final chunk result and
/// the retained import view.
fn import(log: &Logbook, bytes: &[u8]) -> (Result<Value, &'static str>, Value) {
    let id = crate::profile::new_uuid().unwrap();
    log.reserve(&id, bytes.len() as u64, &sha256_hex(bytes), Instant::now())
        .unwrap();
    let mut result = Err("no chunk");
    for (i, chunk) in bytes.chunks(IMPORT_CHUNK_BYTES_MAX).enumerate() {
        let start = (i * IMPORT_CHUNK_BYTES_MAX) as u64;
        result = log.chunk(&id, start, bytes.len() as u64, chunk, Instant::now(), GATE);
    }
    (result, log.import_view(&id).unwrap())
}
/// The next chunk of an ExportAdi stream (it is always ready).
fn next_chunk(export: &mut AdiExport) -> Option<String> {
    use futures_core::Stream;
    let mut cx = std::task::Context::from_waker(std::task::Waker::noop());
    match std::pin::Pin::new(export).poll_next(&mut cx) {
        std::task::Poll::Ready(chunk) => chunk.map(|c| c.unwrap()),
        std::task::Poll::Pending => panic!("an export chunk is always ready"),
    }
}
fn drain(mut export: AdiExport) -> Vec<String> {
    std::iter::from_fn(|| next_chunk(&mut export)).collect()
}
fn calls(log: &Logbook) -> Vec<String> {
    let page = log.history(ID1, 0, 10).unwrap();
    page["records"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["call"].as_str().unwrap().to_owned())
        .collect()
}

// Proves: CL-010-04; TC-011-002 exact WSJT-X-compatible ADI writing and reading.
#[test]
fn adi_record_is_written_in_wsjtx_field_order_with_exact_lengths_and_round_trips() {
    let mut record = reviewed(ID1, "K1ABC");
    record.values[15] = Some("<eor> 73 & \"thanks\"".into());
    record.unknown.push(Unknown {
        name: "APP_OTHER_NOTE".into(),
        kind: Some("M".into()),
        value: "a\tb\r\nc".into(),
    });
    let expected = concat!(
        "<call:5>K1ABC <gridsquare:4>FN42 <mode:3>FT8 <rst_sent:3>-12 <rst_rcvd:3>-05 ",
        "<qso_date:8>20261031 <time_on:6>123015 <qso_date_off:8>20261031 <time_off:6>123200 ",
        "<band:3>20m <freq:9>14.075500 <station_callsign:6>HB9BLA <my_gridsquare:6>JN47AA ",
        "<tx_pwr:2>10 <comment:19><eor> 73 & \"thanks\" ",
        "<app_wstxrust_contact_id:36>11111111-1111-4111-8111-111111111111 ",
        "<APP_OTHER_NOTE:6:M>a\tb\r\nc <eor>\n"
    );
    assert_eq!(record.to_adi(), expected);
    let parsed = parse_records(expected.as_bytes(), &limits()).unwrap();
    assert_eq!(parsed, vec![record]);
}

// Proves: CL-010-04; TC-011-002 header, case, type indicators and boundaries.
#[test]
fn adi_parser_accepts_header_case_variants_and_line_breaks_between_fields() {
    let text = "Exported by another logger\r\n<ADIF_VER:5>3.1.8 <PROGRAMID:5>OTHER\r\n<EOH>\r\n\
        <CALL:6:S>dl1abc\r\n<Qso_Date:8:D>20250101<TIME_ON:4>0959 <mode:4>MFSK\n<SUBMODE:3>FT4 \
        <BAND:3>20M<gridsquare:0> <USERDEF1:2>xy <eOr>\n\n<call:4>W1XY<qso_date:8>20240229<time_on:6>235959<mode:3>FT8<eor>";
    let records = parse_records(text.as_bytes(), &limits()).unwrap();
    assert_eq!(records.len(), 2);
    assert_eq!(records[0].get("call"), Some("dl1abc"));
    assert_eq!(records[0].get("time_on"), Some("0959"));
    assert_eq!(records[0].get("band"), Some("20M"));
    assert_eq!(
        records[0].get("gridsquare"),
        None,
        "WSJT-X empty gridsquare is absent"
    );
    assert_eq!(records[0].contact_id, "");
    assert_eq!(
        records[0].unknown,
        vec![Unknown {
            name: "USERDEF1".into(),
            kind: None,
            value: "xy".into()
        }]
    );
    assert_eq!(records[1].get("qso_date"), Some("20240229"));
    assert_eq!(parse_records(b"", &limits()).unwrap(), vec![]);
    assert_eq!(
        parse_records(b"header only <eoh>\n", &limits()).unwrap(),
        vec![]
    );
}

// Proves: CL-010-04; TC-011-002 malformed, length, character and required-field refusals.
#[test]
fn adi_parser_refuses_malformed_length_character_and_missing_fields_with_context() {
    let ok = "<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <mode:3>FT8 <eor>";
    let cases: [(&str, &str, Option<usize>, Option<&str>); 13] = [
        (
            "<call:3>K1ABC <qso_date:8>20261031 <time_on:4>1230 <mode:3>FT8 <eor>",
            "length_mismatch",
            Some(0),
            Some("call"),
        ),
        (
            "<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <mode:30>FT8 <eor>",
            "length_mismatch",
            Some(0),
            Some("mode"),
        ),
        (
            "<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <mode:3>FT8",
            "malformed",
            Some(0),
            None,
        ),
        (
            "<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <mode:3>FT8 <eor",
            "malformed",
            Some(0),
            None,
        ),
        ("<call:x>K1ABC <eor>", "malformed", Some(0), Some("call")),
        (
            "<call:5>K1\u{e4}BC <qso_date:8>20261031 <time_on:4>1230 <mode:3>FT8 <eor>",
            "unsupported_character",
            Some(0),
            Some("call"),
        ),
        (
            "<call:5>K1\tBC <qso_date:8>20261031 <time_on:4>1230 <mode:3>FT8 <eor>",
            "unsupported_character",
            Some(0),
            Some("call"),
        ),
        (
            "<call:5>K1ABC <qso_date:8>20261032 <time_on:4>1230 <mode:3>FT8 <eor>",
            "invalid_value",
            Some(0),
            Some("qso_date"),
        ),
        (
            "<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1260 <mode:3>FT8 <eor>",
            "invalid_value",
            Some(0),
            Some("time_on"),
        ),
        (
            "<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <mode:3>FT8 <freq:2>-1 <eor>",
            "invalid_value",
            Some(0),
            Some("freq"),
        ),
        (
            "<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <mode:3>FT8 <gridsquare:5>FN42A <eor>",
            "invalid_value",
            Some(0),
            Some("gridsquare"),
        ),
        (
            "<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <eor>",
            "missing_required_field",
            Some(0),
            Some("mode"),
        ),
        ("no end of header <call:5>K1ABC", "malformed", Some(0), None),
    ];
    assert!(parse_records(ok.as_bytes(), &limits()).is_ok());
    for (text, code, record, field) in cases {
        let fault = parse_records(format!("{ok}\n{text}").as_bytes(), &limits())
            .err()
            .or_else(|| parse_records(text.as_bytes(), &limits()).err())
            .unwrap_or_else(|| panic!("accepted {text}"));
        let alone = parse_records(text.as_bytes(), &limits()).err().unwrap();
        assert_eq!(alone.code, code, "{text}");
        assert_eq!(alone.record, record, "{text}");
        assert_eq!(alone.field.as_deref(), field, "{text}");
        assert_eq!(fault.code, code, "{text} after a valid record");
    }
    let second =
        parse_records(format!("{ok}\n<call:3>K1ABC <eor>").as_bytes(), &limits()).unwrap_err();
    assert_eq!((second.code, second.record), ("length_mismatch", Some(1)));
}

// Proves: CL-010-04; TC-011-002 AdiLimits exactly admitted and one over refused.
#[test]
fn adi_limits_admit_exact_maximum_and_refuse_one_over() {
    let field = |n: usize| {
        format!(
            "<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <mode:3>FT8 <comment:{n}>{} <eor>",
            "x".repeat(n)
        )
    };
    assert!(parse_records(field(1024).as_bytes(), &limits()).is_ok());
    let over = parse_records(field(1025).as_bytes(), &limits()).unwrap_err();
    assert_eq!(
        (over.code, over.field.as_deref()),
        ("field_too_long", Some("comment"))
    );
    let name = |n: usize| {
        format!(
            "<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <mode:3>FT8 <{}:1>x <eor>",
            "N".repeat(n)
        )
    };
    assert!(parse_records(name(64).as_bytes(), &limits()).is_ok());
    assert_eq!(
        parse_records(name(65).as_bytes(), &limits())
            .unwrap_err()
            .code,
        "field_too_long"
    );
    let one = "<call:5>K1ABC<qso_date:8>20261031<time_on:4>1230<mode:3>FT8<eor>\n";
    let exact = one.repeat(100_000);
    assert_eq!(
        parse(exact.as_bytes(), &limits()).unwrap().records.len(),
        100_000
    );
    let over = parse(format!("{exact}{one}").as_bytes(), &limits()).unwrap_err();
    assert_eq!(
        (over.code, over.record),
        ("too_many_records", Some(100_000))
    );
}

// Proves: CL-010-04; TC-011-002 exactly 64 MiB import admitted through 16 KiB chunks.
#[test]
fn import_of_exactly_sixty_four_mebibytes_is_admitted_and_published() {
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    let record = "<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <mode:3>FT8 <eor>\n";
    let mut bytes = record.as_bytes().to_vec();
    bytes.resize(IMPORT_BYTES_MAX as usize, b' ');
    let (result, view) = import(&log, &bytes);
    assert_eq!(result.unwrap()["added"], 1);
    assert_eq!(view["received_bytes"], IMPORT_BYTES_MAX);
    assert_eq!(log.total().unwrap(), 1);
}

fn summary(view: &Value) -> (Value, Value, Value) {
    (
        view["added"].clone(),
        view["present"].clone(),
        view["skipped"].clone(),
    )
}

/// A synthetic export shaped like Log4OM 2.42 (UTF-8 byte order mark, '#' banner, ADIF
/// 3.1.0 header with PROGRAMID LOG4OM2, about 30 fields per record including personal
/// ones with non-ASCII values whose LEN counts characters). No real log data.
const LOG4OM_HEADER: &str = "\u{feff}#++++++++++++++++++++++++++++++++++++\n#   Log4OM 2 by IW3HMH version 2.42.1.0\n#   http://www.log4om.com\n#   created: Dienstag, 3. M\u{e4}rz 2026\n#++++++++++++++++++++++++++++++++++++\n\n<ADIF_VER:5>3.1.0 <PROGRAMID:7>LOG4OM2 <PROGRAMVERSION:8>2.42.1.0 <eoh>\n\n";
const LOG4OM_FT8: &str = "<CALL:5>K1ABC <BAND:3>30m <MODE:3>FT8 <QSO_DATE:8>20250218 <TIME_ON:6>225630 <A_INDEX:2>15 <CONT:2>NA <COUNTRY:13>United States <CNTY:6>MA,ESX // Essex <CQZ:1>5 <DISTANCE:7>6182.69 <DXCC:3>291 <EMAIL:17>k1abc@example.net <EQSL_QSL_RCVD:1>R <FREQ:9>10.138691 <GRIDSQUARE:6>FN42ab <ITUZ:1>8 <LOTW_QSL_SENT:1>Y <MY_CITY:6>Testen <MY_GRIDSQUARE:6>JN37vl <MY_NAME:11>Test Pr\u{fc}fer <MY_STREET:13>Stra\u{df}e 1, Ort <NAME:9>Jos\u{e9} Test <OPERATOR:6>HB9BLA <OWNER_CALLSIGN:6>HB9BLA <STATION_CALLSIGN:6>HB9BLA <PROGRAMID:7>LOG4OM2 <QSL_RCVD:1>R <QSO_COMPLETE:1>Y <QSO_DATE_OFF:8>20250218 <RST_RCVD:3>-02 <RST_SENT:3>-14 <SWL:1>N <TIME_OFF:6>225900 <TX_PWR:3>100 <LAT:11>N000 00.000 <CLUBLOG_QSO_UPLOAD_STATUS:1>N <eor>\n\n";
const LOG4OM_FT4: &str = "<CALL:6>DL1ABC <BAND:3>20m <MODE:4>MFSK <SUBMODE:3>FT4 <QSO_DATE:8>20250219 <TIME_ON:6>101500 <CONT:2>EU <NAME:4>J\u{fc}rg <QTH:6>K\u{f6}ln 1 <STATION_CALLSIGN:6>HB9BLA <eor>\n\n";
const LOG4OM_SSB: &str = "<CALL:5>W1XYZ <BAND:3>40m <MODE:3>SSB <SUBMODE:3>LSB <QSO_DATE:8>20250220 <TIME_ON:4>0815 <DXCC:3>291 <eor>\n\n";

// Proves: CL-010-04; TC-011-002 Update logbook from a Log4OM-shaped export: byte order
// mark, banner, UTF-8 personal fields not stored, only the log's fields kept, the source
// marked, MFSK/FT4 and FT4 one mode, and the added records feed worked-before.
#[test]
fn update_reads_a_log4om_shaped_export_keeps_only_log_fields_and_marks_the_source() {
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    let file = format!("{LOG4OM_HEADER}{LOG4OM_FT8}{LOG4OM_FT4}{LOG4OM_SSB}");
    let (result, view) = import(&log, file.as_bytes());
    let result = result.unwrap();
    assert_eq!(summary(&result), (json!(3), json!(0), json!(0)), "{result}");
    assert_eq!(view["reasons"], json!([]));
    assert_eq!(view["dropped"], json!([]));
    let stored = String::from_utf8(dir.file().unwrap()).unwrap();
    let lines: Vec<&str> = stored.lines().filter(|l| l.starts_with("<call:")).collect();
    assert_eq!(lines.len(), 3, "{stored}");
    let id =
        |line: &str| line.split("<app_wstxrust_contact_id:36>").nth(1).unwrap()[..36].to_owned();
    assert_eq!(
        lines[0],
        format!(
            "<call:5>K1ABC <gridsquare:6>FN42ab <mode:3>FT8 <rst_sent:3>-14 <rst_rcvd:3>-02 \
             <qso_date:8>20250218 <time_on:6>225630 <qso_date_off:8>20250218 <time_off:6>225900 \
             <band:3>30m <freq:9>10.138691 <station_callsign:6>HB9BLA <my_gridsquare:6>JN37vl \
             <tx_pwr:3>100 <qsl_rcvd:1>R <eqsl_qsl_rcvd:1>R <app_wstxrust_contact_id:36>{} <app_wstxrust_source:7>LOG4OM2 <eor>",
            id(lines[0])
        )
    );
    assert_eq!(
        lines[1],
        format!(
            "<call:6>DL1ABC <mode:4>MFSK <submode:3>FT4 <qso_date:8>20250219 <time_on:6>101500 \
             <band:3>20m <station_callsign:6>HB9BLA <app_wstxrust_contact_id:36>{} \
             <app_wstxrust_source:7>LOG4OM2 <eor>",
            id(lines[1])
        )
    );
    assert!(lines[2].starts_with("<call:5>W1XYZ <mode:3>SSB <submode:3>LSB <qso_date:8>20250220 <time_on:4>0815 <band:3>40m <app_wstxrust_contact_id:36>"));
    assert!(crate::profile::valid_uuid(&id(lines[0])) && id(lines[0]) != id(lines[1]));
    for personal in [
        "Jos", "example", "Stra", "dxcc", "cont:", "name", "qth", "\u{fc}",
    ] {
        assert!(
            !stored
                .to_ascii_lowercase()
                .contains(&personal.to_ascii_lowercase()),
            "{personal} stored"
        );
    }
    assert_eq!(
        log.history(ID1, 0, 3).unwrap()["records"][1]["unknown_field_count"],
        0
    );
    assert_eq!(
        Logbook::open(&dir.0).total().unwrap(),
        3,
        "the stored log reloads"
    );
    // The added records answer worked-before and the worked grids.
    let calls: Vec<String> = ["DL1ABC", "k1abc", "W1XYZ"].map(String::from).to_vec();
    assert_eq!(
        log.worked(&calls, "20m", "FT4").unwrap(),
        [
            "worked_this_band_and_mode",
            "worked_other_band_or_mode",
            "worked_other_band_or_mode"
        ]
    );
    assert_eq!(
        log.worked(&calls[2..], "40M", "SSB").unwrap(),
        ["worked_this_band_and_mode"]
    );
    // MODE FT4 (no submode) 30 s later is the same QSO as MFSK/FT4: already present.
    let ft4 = format!(
        "{LOG4OM_HEADER}<CALL:6>DL1ABC <BAND:3>20m <MODE:3>FT4 <QSO_DATE:8>20250219 <TIME_ON:6>101530 <eor>\n"
    );
    assert_eq!(
        summary(&import(&log, ft4.as_bytes()).0.unwrap()),
        (json!(0), json!(1), json!(0))
    );
    // Without a header PROGRAMID the marker is ADIF.
    let plain = "<call:5>N0NEW <qso_date:8>20261031 <time_on:4>1300 <mode:3>FT8 <eor>\n";
    import(&log, plain.as_bytes()).0.unwrap();
    assert!(String::from_utf8(dir.file().unwrap()).unwrap().contains("<call:5>N0NEW <mode:3>FT8 <qso_date:8>20261031 <time_on:4>1300 <app_wstxrust_contact_id:36>"));
    assert!(
        String::from_utf8(dir.file().unwrap())
            .unwrap()
            .contains("<app_wstxrust_source:4>ADIF <eor>")
    );
    // N0NEW has no band: worked, but never on "this band", not even an unknown one.
    let n0new = ["N0NEW".to_owned()];
    assert_eq!(
        log.worked(&n0new, "", "FT8").unwrap(),
        ["worked_other_band_or_mode"]
    );
}

// Proves: CL-010-04; TC-011-002 consolidation key call + band + effective mode + start
// within 120 s; the stored station record wins byte for byte; repeatable and incremental.
#[test]
fn update_consolidates_within_two_minutes_and_existing_records_win_and_repeat_adds_nothing() {
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    // Station record: K1ABC 20m FT8 2026-10-31 12:30:15 (reviewed()).
    assert_eq!(
        log.save(reviewed(ID1, "K1ABC"), GATE).unwrap(),
        SaveOutcome::Saved
    );
    let before = dir.file().unwrap();
    let file = format!(
        "<call:5>K1ABC <qso_date:8>20261031 <time_on:6>123215 <band:3>20m <mode:3>FT8 <rst_rcvd:3>+03 <eor>\n\
         <call:5>k1abc <qso_date:8>20261031 <time_on:6>122815 <freq:9>14.075500 <mode:3>ft8 <eor>\n\
         <call:5>K1ABC <qso_date:8>20261031 <time_on:6>123216 <band:3>20m <mode:3>FT8 <eor>\n\
         <call:5>K1ABC <qso_date:8>20261031 <time_on:6>123015 <band:3>40m <mode:3>FT8 <eor>\n\
         <call:5>K1ABC <qso_date:8>20261031 <time_on:6>123015 <band:3>20m <mode:4>MFSK <submode:3>FT4 <eor>\n\
         <call:5>K1ABC <qso_date:8>20261031 <time_on:4>1233 <band:3>20m <mode:3>FT8 <eor>\n\
         <call:5>K9ZZZ <qso_date:8>20200101 <time_on:4>0000 <mode:3>FT8 <app_wstxrust_contact_id:36>{ID1} <eor>\n"
    );
    // 12:32:15 is 120 s after the stored start, 12:28:15 120 s before it (band from FREQ,
    // call and mode case): present. 12:32:16 is 121 s: added; 12:33 is then within 44 s
    // of that added record: present. 40m and MFSK/FT4: added. The stored id: present.
    let (result, _) = import(&log, file.as_bytes());
    assert_eq!(summary(&result.unwrap()), (json!(3), json!(4), json!(0)));
    let after = dir.file().unwrap();
    assert!(
        after.starts_with(&before),
        "the station record and file prefix are unchanged"
    );
    assert_eq!(calls(&log), ["K1ABC", "K1ABC", "K1ABC", "K1ABC"]);
    let stored = log.history(ID1, 0, 1).unwrap()["records"][0].clone();
    assert_eq!(
        (stored["rst_rcvd"].clone(), stored["time_on"].clone()),
        (json!("-05"), json!("123015"))
    );
    // Again: nothing added, the file untouched; a grown file adds only its new record.
    let (again, _) = import(&log, file.as_bytes());
    assert_eq!(summary(&again.unwrap()), (json!(0), json!(7), json!(0)));
    assert_eq!(dir.file().unwrap(), after);
    let grown = format!(
        "{file}<call:5>N0NEW <qso_date:8>20261101 <time_on:4>0900 <band:3>20m <mode:3>FT8 <eor>\n"
    );
    assert_eq!(
        summary(&import(&log, grown.as_bytes()).0.unwrap()),
        (json!(1), json!(7), json!(0))
    );
    // Export then update adds nothing.
    let exported = drain(log.export().unwrap()).concat();
    assert_eq!(
        summary(&import(&log, exported.as_bytes()).0.unwrap()),
        (json!(0), json!(5), json!(0))
    );
    assert_eq!(log.total().unwrap(), 5);
}

// Proves: CL-010-04; TC-011-002 invalid records skipped and invalid optional fields dropped
// with grouped reasons (at most 16 groups); a structural fault publishes nothing.
#[test]
fn update_skips_invalid_records_drops_invalid_fields_and_refuses_a_broken_file() {
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    let file = "<qso_date:8>20261031 <time_on:4>1300 <mode:3>FT8 <eor>\n\
        <call:5>N1AAA <qso_date:8>20261032 <time_on:4>1300 <mode:3>FT8 <eor>\n\
        <qso_date:8>20261031 <time_on:4>1300 <mode:3>FT8 <name:3>Bob <eor>\n\
        <call:5>N2BBB <qso_date:8>20261031 <time_on:4>1301 <mode:3>FT8 <gridsquare:5>JN4qe <freq:2>-1 <comment:5>Gr\u{fc}\u{df}e <eor>\n\
        <call:5>N3CCC <call:5>N3CCC <qso_date:8>20261031 <time_on:4>1302 <mode:3>FT8 <eor>\n\
        <call:5>N4D\u{c4}D <qso_date:8>20261031 <time_on:4>1303 <mode:3>FT8 <eor>\n\
        <call:5>N7GGG x <qso_date:8>20261031 <time_on:4>1304 <mode:3>FT8 <eor>\n\
        <call:5>N8HHH <qso_date:8>20261031 <time_on:4>1305 <mode:3>FT8 <gridsquare:4>FN42 // Here <eor>\n";
    let (result, view) = import(&log, file.as_bytes());
    assert_eq!(summary(&result.unwrap()), (json!(2), json!(0), json!(6)));
    assert_eq!(
        view["reasons"],
        json!([
            {"code":"missing_required_field","field":"call","count":2,"record":0},
            {"code":"invalid_value","field":"qso_date","count":1,"record":1},
            {"code":"malformed","field":"call","count":1,"record":4},
            {"code":"unsupported_character","field":"call","count":1,"record":5},
            {"code":"length_mismatch","field":"call","count":1,"record":6}
        ])
    );
    assert_eq!(
        view["dropped"],
        json!([
            {"code":"invalid_value","field":"gridsquare","count":1,"record":3},
            {"code":"invalid_value","field":"freq","count":1,"record":3},
            {"code":"unsupported_character","field":"comment","count":1,"record":3},
            {"code":"length_mismatch","field":"gridsquare","count":1,"record":7}
        ])
    );
    let stored = log.history(ID1, 0, 1).unwrap()["records"][0].clone();
    assert_eq!(
        (
            stored["call"].clone(),
            stored["gridsquare"].clone(),
            stored["freq"].clone(),
            stored["comment"].clone()
        ),
        (json!("N2BBB"), Value::Null, Value::Null, Value::Null)
    );
    // One distinct reason per kept field (a repeated kept field each, 26 with #24): 16 groups listed, all counted.
    let mut many = String::new();
    for name in FIELDS.iter().chain(&[ID_FIELD, SOURCE_FIELD]) {
        many.push_str(&format!("<call:5>N5EEE <qso_date:8>20261031 <time_on:4>1300 <mode:3>FT8 <{name}:1>1 <{name}:1>1 <eor>\n"));
    }
    // A value over 1024 characters faults only its field: a long unknown NOTES is not
    // stored, a long COMMENT is dropped, a long CALL skips its record.
    let long = |name: &str, c: &str| format!("<{name}:1025>{}", c.repeat(1025));
    let too_long = format!(
        "<call:5>N9III <qso_date:8>20261031 <time_on:4>1300 <mode:3>FT8 {} {} <eor>\n{} <qso_date:8>20261031 <time_on:4>1301 <mode:3>FT8 <eor>\n",
        long("notes", "x"),
        long("comment", "x"),
        long("call", "K")
    );
    let (result, view) = import(&log, too_long.as_bytes());
    assert_eq!(summary(&result.unwrap()), (json!(1), json!(0), json!(1)));
    assert_eq!(
        (view["reasons"].clone(), view["dropped"].clone()),
        (
            json!([{"code":"field_too_long","field":"call","count":1,"record":1}]),
            json!([{"code":"field_too_long","field":"comment","count":1,"record":0}])
        )
    );
    let (_, view) = import(&log, many.as_bytes());
    assert_eq!(
        summary(&view),
        (json!(0), json!(0), json!(FIELDS.len() + 2))
    );
    assert_eq!(view["reasons"].as_array().unwrap().len(), 16);
    let file_before = dir.file().unwrap();
    for (broken, code, record, field) in [
        (
            "<call:5>N6FFF <qso_date:8>20261031 <time_on:4>1300 <mode:3>FT8 <eor>\n<call:30>K1ABC <eor>",
            "length_mismatch",
            1,
            Some("call"),
        ),
        (
            "<call:5>N6FFF <qso_date:8>20261031 <time_on:4>1300 <mode:3>FT8 <eor>\n<call:5>K1ABC <qso_date:8>20261031",
            "malformed",
            1,
            None,
        ),
        (
            "<call:5>N6FFF <qso_date:8>20261031 <time_on:4>1300 <mode:3>FT8 <eor>\n\u{1}",
            "unsupported_character",
            1,
            None,
        ),
    ] {
        let (result, view) = import(&log, broken.as_bytes());
        assert_eq!(result, Err("import_failed"), "{broken}");
        assert_eq!(
            view["error"],
            json!({"code":code,"record":record,"field":field}),
            "{broken}"
        );
        assert_eq!(dir.file().unwrap(), file_before, "nothing published");
    }
    let (result, view) = import(&log, &[b'<', 0xff, b'>']);
    assert_eq!(
        (result, view["error"]["code"].clone()),
        (Err("import_failed"), json!("unsupported_character"))
    );
    assert_eq!(log.total().unwrap(), 3);
}

// Proves: CL-010-04, CL-010-13; TC-011-002 workload: a 27,000-QSO export of about 27 MB
// (Log4OM-shaped records) is consolidated in one update; worked-before then answers
// from the index. Timing is printed, not asserted (functional suite).
#[test]
fn update_of_twenty_seven_thousand_qsos_is_consolidated_and_worked_before_uses_the_index() {
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    let mut file = String::from(LOG4OM_HEADER);
    let padding = format!("<NOTES:800>{}", "n".repeat(800));
    for i in 0..27_000u32 {
        let (day, minute) = (1 + i / 1440 % 28, i % 1440);
        file.push_str(&format!(
            "<CALL:7>K{:06} <BAND:3>20m <MODE:4>MFSK <SUBMODE:3>FT4 <QSO_DATE:8>2025{:02}{:02} <TIME_ON:6>{:02}{:02}00 <GRIDSQUARE:4>FN{:02} <NAME:9>Jos\u{e9} Test <EMAIL:17>k1abc@example.net {padding} <eor>\n",
            i, 1 + i / 40_320, day, minute / 60, minute % 60, i % 100
        ));
    }
    assert!(
        file.len() > 25_000_000 && file.len() < IMPORT_BYTES_MAX as usize,
        "{}",
        file.len()
    );
    let started = Instant::now();
    let (result, _) = import(&log, file.as_bytes());
    eprintln!(
        "27000 QSOs, {} bytes: update {:?}",
        file.len(),
        started.elapsed()
    );
    assert_eq!(
        summary(&result.unwrap()),
        (json!(27_000), json!(0), json!(0))
    );
    let calls: Vec<String> = (0..64).map(|i| format!("K{:06}", i * 400)).collect();
    let started = Instant::now();
    let first = log.worked(&calls, "20m", "FT4").unwrap();
    let again = log.worked(&calls, "20m", "FT4").unwrap();
    eprintln!(
        "worked-before 64 calls: first (builds the index) and second {:?}",
        started.elapsed()
    );
    assert!(
        first
            .iter()
            .chain(&again)
            .all(|s| *s == "worked_this_band_and_mode")
    );
    let started = Instant::now();
    assert_eq!(Logbook::open(&dir.0).total().unwrap(), 27_000);
    eprintln!("reopen {:?}", started.elapsed());
    // #10 the rerun of the export with every QSO confirmed in LoTW upgrades all of them
    // in one replace, and the worked set includes the confirmation.
    let confirmed = file.replace(
        " <eor>\n",
        " <LOTW_QSL_RCVD:1>Y <LOTW_QSLRDATE:8>20250301 <eor>\n",
    );
    let started = Instant::now();
    let (result, _) = import(&log, confirmed.as_bytes());
    eprintln!(
        "27000 QSOs rerun with confirmations {:?}",
        started.elapsed()
    );
    let result = result.unwrap();
    assert_eq!(summary(&result), (json!(0), json!(27_000), json!(0)));
    assert_eq!(result["confirmed"], json!(27_000));
    let started = Instant::now();
    let w = log.worked_set().unwrap();
    let (table, _) = log.dxcc();
    let usa = table.lookup("K000001").unwrap();
    let standing = w.entity_standing(crate::dxcc::Category::Dxcc, &usa, Some("20m"), Some("FT4"));
    eprintln!("worked set with confirmation {:?}", started.elapsed());
    assert!(standing.worked && standing.confirmed);
}

// Proves: CL-010-04; TC-011-002 import retry identity and integrity check.
#[test]
fn import_retry_by_id_and_sha256_has_no_second_effect_and_mismatch_is_refused() {
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    let bytes = b"<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <mode:3>FT8 <eor>";
    let sha = sha256_hex(bytes);
    let id = "33333333-3333-4333-8333-333333333333";
    let now = Instant::now();
    assert!(log.reserve(id, bytes.len() as u64, &sha, now).unwrap().0);
    assert!(
        !log.reserve(id, bytes.len() as u64, &sha, now).unwrap().0,
        "identical retry returns the resource"
    );
    assert_eq!(
        log.reserve(id, bytes.len() as u64 + 1, &sha, now),
        Err("state_conflict")
    );
    assert_eq!(
        log.reserve(id, bytes.len() as u64, &"0".repeat(64), now),
        Err("state_conflict")
    );
    assert_eq!(
        log.reserve(ID2, 10, &sha, now),
        Err("busy"),
        "one import per profile at a time"
    );
    assert_eq!(
        log.chunk(id, 1, bytes.len() as u64, &bytes[1..], now, GATE),
        Err("state_conflict"),
        "in order"
    );
    let done = log
        .chunk(id, 0, bytes.len() as u64, bytes, now, GATE)
        .unwrap();
    assert_eq!(done["state"], "completed");
    let file = dir.file().unwrap();
    let (created, retry) = log.reserve(id, bytes.len() as u64, &sha, now).unwrap();
    assert!(!created);
    assert_eq!(retry, done, "final result without a second effect");
    assert_eq!(
        log.chunk(id, 0, bytes.len() as u64, bytes, now, GATE),
        Err("state_conflict")
    );
    assert_eq!(dir.file().unwrap(), file);
    let wrong = "44444444-4444-4444-8444-444444444444";
    log.reserve(wrong, bytes.len() as u64, &"a".repeat(64), now)
        .unwrap();
    assert_eq!(
        log.chunk(wrong, 0, bytes.len() as u64, bytes, now, GATE),
        Err("import_failed")
    );
    assert_eq!(
        log.import_view(wrong).unwrap()["error"],
        json!({"code":"integrity_mismatch","record":null,"field":null})
    );
    assert_eq!(log.total().unwrap(), 1);
    // An idle receiving import no longer blocks the next reservation.
    log.reserve(ID1, 5, &sha, now).unwrap();
    assert_eq!(
        log.reserve(ID2, 5, &sha, now + Duration::from_secs(61))
            .map(|r| r.0),
        Ok(true)
    );
}

// Proves: CL-010-04; TC-011-001 exactly once, Saved only after the atomic replace.
#[test]
fn save_is_exactly_once_and_injected_failures_leave_no_torn_file() {
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    assert_eq!(
        log.save(reviewed(ID1, "K1ABC"), GATE).unwrap(),
        SaveOutcome::Saved
    );
    let first = dir.file().unwrap();
    for stage in ["write", "flush", "replace"] {
        log.inject_fault(Some(stage));
        assert_eq!(
            log.save(reviewed(ID2, "W1XYZ"), GATE),
            Err(StoreError::Unavailable),
            "{stage}"
        );
        assert_eq!(
            dir.file().unwrap(),
            first,
            "{stage}: contacts.adi unchanged"
        );
        assert!(
            dir.leftovers().is_empty(),
            "{stage}: no temporary file left"
        );
        assert_eq!(log.total().unwrap(), 1);
    }
    log.inject_fault(None);
    assert_eq!(
        log.save(reviewed(ID2, "W1XYZ"), GATE).unwrap(),
        SaveOutcome::Saved,
        "retry under the same identity"
    );
    assert_eq!(
        log.save(reviewed(ID2, "W1XYZ"), GATE).unwrap(),
        SaveOutcome::AlreadySaved
    );
    let mut changed = reviewed(ID2, "W1XYZ");
    changed.values[14] = Some("5".into());
    assert_eq!(log.save(changed, GATE).unwrap(), SaveOutcome::Conflict);
    // Same call again: a separate contact, no dupe refusal.
    assert_eq!(
        log.save(
            reviewed("55555555-5555-4555-8555-555555555555", "K1ABC"),
            GATE
        )
        .unwrap(),
        SaveOutcome::Saved
    );
    let stored = parse_records(&dir.file().unwrap(), &limits()).unwrap();
    assert_eq!(
        stored,
        vec![
            reviewed(ID1, "K1ABC"),
            reviewed(ID2, "W1XYZ"),
            reviewed("55555555-5555-4555-8555-555555555555", "K1ABC")
        ]
    );
    let refused =
        |_: &mut dyn FnMut() -> std::io::Result<()>| Err(crate::authorization::Error::Unauthorized);
    assert_eq!(
        log.save(
            reviewed("66666666-6666-4666-8666-666666666666", "N0NEW"),
            &refused
        ),
        Err(StoreError::Unauthorized(
            crate::authorization::Error::Unauthorized
        ))
    );
    assert!(dir.leftovers().is_empty());
    drop(log);
    let reopened = Logbook::open(&dir.0);
    assert_eq!(
        reopened.total().unwrap(),
        3,
        "restart reads the committed log"
    );
}

// Proves: CL-010-04; TC-011-002 an invalid stored log is unavailable, never overwritten.
#[test]
fn invalid_stored_log_is_unavailable_and_never_rewritten() {
    let dir = Dir::new();
    fs::write(dir.0.join(FILE_NAME), b"<call:3>K1ABC <eor>").unwrap();
    let log = Logbook::open(&dir.0);
    assert_eq!(
        log.save(reviewed(ID1, "K1ABC"), GATE),
        Err(StoreError::Unavailable)
    );
    assert_eq!(log.total(), Err(StoreError::Unavailable));
    assert_eq!(dir.file().unwrap(), b"<call:3>K1ABC <eor>");
}

// Proves: CL-010-04; TC-011-002 stable history indexes and the 16384-byte page bound.
#[test]
fn history_pages_have_stable_indexes_and_stay_within_the_byte_bound() {
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    for i in 0..12 {
        let mut record = reviewed(&format!("{i:08x}-0000-4000-8000-000000000000"), "K1ABC");
        record.values[15] = Some("\"".repeat(1023) + "\\");
        assert_eq!(log.save(record, GATE).unwrap(), SaveOutcome::Saved);
    }
    let page = log.history(ID1, 0, 10).unwrap();
    let size = page.to_string().len();
    assert!(size <= HISTORY_PAGE_BYTES_MAX, "{size}");
    let n = page["records"].as_array().unwrap().len();
    assert!(
        (1..10).contains(&n),
        "escaped comments shrink the page to {n}"
    );
    assert_eq!(page["next"], n);
    assert_eq!(page["more"], true);
    assert_eq!(page["total"], 12);
    let last = log.history(ID1, 11, 10).unwrap();
    assert_eq!(last["records"][0]["index"], 11);
    assert_eq!(last["more"], false);
    let end = log.history(ID1, 12, 1).unwrap();
    assert_eq!(end["records"], json!([]));
    assert_eq!(end["next"], 12);
    let keys: Vec<_> = last["records"][0]
        .as_object()
        .unwrap()
        .keys()
        .cloned()
        .collect();
    let mut expected = vec![
        "index",
        "contact_id",
        "call",
        "gridsquare",
        "mode",
        "submode",
        "rst_sent",
        "rst_rcvd",
        "qso_date",
        "time_on",
        "qso_date_off",
        "time_off",
        "band",
        "freq",
        "station_callsign",
        "my_gridsquare",
        "tx_pwr",
        "comment",
        "stx",
        "stx_string",
        "srx",
        "contest_id",
        "srx_string",
        "class",
        "arrl_sect",
        "state",
        "unknown_field_count",
    ];
    expected.sort_unstable();
    let mut keys: Vec<&str> = keys.iter().map(String::as_str).collect();
    keys.sort_unstable();
    assert_eq!(keys, expected);
    assert_eq!(last["records"][0]["submode"], Value::Null);
}

// Proves: CL-010-13; TC-011-003 worked-before by call and by band plus mode.
#[test]
fn worked_before_matches_call_case_insensitively_and_band_with_mode() {
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    let text = "<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <band:3>20m <mode:3>FT8 <eor>\n\
        <call:5>W1XYZ <qso_date:8>20261031 <time_on:4>1231 <band:3>40m <mode:3>FT8 <eor>\n\
        <call:6>DL1ABC <qso_date:8>20261031 <time_on:4>1232 <freq:6>14.080 <mode:4>MFSK <submode:3>FT4 <eor>\n";
    import(&log, text.as_bytes()).0.unwrap();
    let query: Vec<String> = ["K1ABC", "W1XYZ", "DL1ABC", "k1abc", "N0NEW"]
        .map(String::from)
        .to_vec();
    assert_eq!(
        log.worked(&query, "20m", "FT8").unwrap(),
        [
            "worked_this_band_and_mode",
            "worked_other_band_or_mode",
            "worked_other_band_or_mode",
            "worked_this_band_and_mode",
            "not_worked"
        ]
    );
    assert_eq!(
        log.worked(&query[2..3], "20M", "FT4").unwrap(),
        ["worked_this_band_and_mode"]
    );
    let mut n0new = reviewed(ID1, "N0NEW");
    n0new.values[10] = Some("20m".into());
    log.save(n0new, GATE).unwrap();
    assert_eq!(
        log.worked(&query[4..], "20m", "FT8").unwrap(),
        ["worked_this_band_and_mode"],
        "saved this session"
    );
}

// Proves: CL-010-04; TC-011-001 review field domains refused beside the field.
#[test]
fn review_validation_refuses_each_invalid_field_with_its_key() {
    let good = reviewed(ID1, "K1ABC");
    assert_eq!(validate_record(&good, "HB9BLA", "JN47AA"), Ok(()));
    let mut ft4 = good.clone();
    ft4.values[2] = Some("MFSK".into());
    ft4.values[3] = Some("FT4".into());
    assert_eq!(validate_record(&ft4, "HB9BLA", "JN47AA"), Ok(()));
    let mut none = good.clone();
    for i in [1, 4, 5, 10, 11, 14, 15] {
        none.values[i] = None;
    }
    assert_eq!(
        validate_record(&none, "HB9BLA", "JN47AA"),
        Ok(()),
        "optional fields may be null"
    );
    let cases: [(usize, &str, &str); 18] = [
        (0, "k1abc", "record.call"),
        (1, "FN4", "record.gridsquare"),
        (2, "SSB", "record.mode"),
        (3, "FT4", "record.submode"),
        (4, "-51", "record.rst_sent"),
        (5, "+50", "record.rst_rcvd"),
        (6, "20260230", "record.qso_date"),
        (7, "1230", "record.time_on"),
        (9, "123000", "record.time_off"),
        (10, "21m", "record.band"),
        (11, "14.0755", "record.freq"),
        (11, "7.074000", "record.freq"),
        (12, "HB9XYZ", "record.station_callsign"),
        (14, "-1", "record.tx_pwr"),
        (15, "line\r\nbreak", "record.comment"),
        (15, "", "record.comment"),
        (15, "see <eor> here", "record.comment"),
        (15, "a>b", "record.comment"),
    ];
    for (index, value, field) in cases {
        let mut record = good.clone();
        record.values[index] = Some(value.into());
        assert_eq!(
            validate_record(&record, "HB9BLA", "JN47AA"),
            Err(field),
            "{value}"
        );
    }
    let mut long = good.clone();
    long.values[15] = Some("x".repeat(1025));
    assert_eq!(
        validate_record(&long, "HB9BLA", "JN47AA"),
        Err("record.comment")
    );
    long.values[15] = Some("x".repeat(1024));
    assert_eq!(validate_record(&long, "HB9BLA", "JN47AA"), Ok(()));
    let mut bad_id = good.clone();
    bad_id.contact_id = "not-a-uuid".into();
    assert_eq!(
        validate_record(&bad_id, "HB9BLA", "JN47AA"),
        Err("record.contact_id")
    );
    assert_eq!(
        validate_record(&good, "HB9BLA", ""),
        Err("record.my_gridsquare")
    );
}

// Proves: CL-010-04; TC-011-001 an unreadable contacts.adi (not NotFound) is never
// treated as an empty log and is never replaced.
#[test]
fn unreadable_stored_log_is_unavailable_and_left_untouched() {
    let dir = Dir::new();
    let path = dir.0.join(FILE_NAME);
    fs::create_dir(&path).unwrap();
    fs::write(path.join("marker"), b"kept").unwrap();
    let log = Logbook::open(&dir.0);
    assert_eq!(
        log.save(reviewed(ID1, "K1ABC"), GATE),
        Err(StoreError::Unavailable)
    );
    assert_eq!(log.total(), Err(StoreError::Unavailable));
    assert!(path.is_dir(), "the unreadable path is not replaced");
    assert_eq!(fs::read(path.join("marker")).unwrap(), b"kept");
    assert!(dir.leftovers().is_empty());
}

// Proves: CL-024-03; TC-024-008 (f). The contest fields and RTTY RSTs of LogRecord.
#[test]
fn contest_fields_and_rtty_rst_are_validated() {
    let mut r = reviewed(ID1, "K1ABC");
    r.values[4] = Some("559".into());
    r.values[5] = Some("579".into());
    r.set("stx", "0001".into());
    r.set("state", "MA".into());
    assert_eq!(validate_record(&r, "HB9BLA", "JN47AA"), Ok(()));
    assert!(
        r.adi_fields()
            .contains("<stx:4>0001 <state:2>MA <app_wstxrust_contact_id")
    );
    let mut bad = r.clone();
    bad.values[4] = Some("519".into());
    assert_eq!(
        validate_record(&bad, "HB9BLA", "JN47AA"),
        Err("record.rst_sent")
    );
    let mut bad = r.clone();
    bad.set("srx_string", "2A <WI>".into());
    assert_eq!(
        validate_record(&bad, "HB9BLA", "JN47AA"),
        Err("record.srx_string")
    );
    let mut bad = r.clone();
    bad.set("stx", "00001".into());
    assert_eq!(validate_record(&bad, "HB9BLA", "JN47AA"), Err("record.stx"));
}

// Proves: CL-010-04, CL-024-03; TC-011-002 Update logbook keeps only contest values that
// SaveContact admits (coordinator decision on #10, 2026-11-04): a non-conforming STX, SRX
// or contest text is dropped and reported, the record is still added, a conforming value
// (exactly 32 characters, 4 digits) is kept.
#[test]
fn update_drops_contest_values_that_save_would_refuse_and_keeps_conforming_ones() {
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    let at32 = "A".repeat(32);
    let at33 = "B".repeat(33);
    let file = format!(
        "<call:5>N1AAA <qso_date:8>20261031 <time_on:4>1300 <mode:3>FT8 <stx:3>12A <srx:5>12345 <contest_id:33>{at33} <srx_string:7>2A <WI> <state:2>MA <eor>\n\
         <call:5>N2BBB <qso_date:8>20261031 <time_on:4>1301 <mode:3>FT8 <stx:4>0001 <srx:1>7 <contest_id:32>{at32} <class:2>3A <eor>\n"
    );
    let (result, view) = import(&log, file.as_bytes());
    assert_eq!(summary(&result.unwrap()), (json!(2), json!(0), json!(0)));
    assert_eq!(
        view["dropped"],
        json!([
            {"code":"invalid_value","field":"stx","count":1,"record":0},
            {"code":"invalid_value","field":"srx","count":1,"record":0},
            {"code":"invalid_value","field":"contest_id","count":1,"record":0},
            {"code":"invalid_value","field":"srx_string","count":1,"record":0}
        ])
    );
    let records = log.history(ID1, 0, 2).unwrap()["records"].clone();
    let pick = |r: &Value| {
        [
            "call",
            "stx",
            "srx",
            "contest_id",
            "srx_string",
            "class",
            "state",
        ]
        .map(|k| r[k].clone())
    };
    let rows: Vec<_> = records.as_array().unwrap().iter().map(pick).collect();
    let n = Value::Null;
    assert!(rows.contains(&[
        json!("N1AAA"),
        n.clone(),
        n.clone(),
        n.clone(),
        n.clone(),
        n.clone(),
        json!("MA")
    ]));
    assert!(rows.contains(&[
        json!("N2BBB"),
        json!("0001"),
        json!("7"),
        json!(at32),
        n.clone(),
        json!("3A"),
        n.clone()
    ]));
    // Every kept record passes the SaveContact contest rule on reload.
    let reopened = Logbook::open(&dir.0);
    assert_eq!(reopened.history(ID1, 0, 2).unwrap()["records"], records);
}

// Proves: CL-010-04; TC-011-002 ExportAdi streamed (#10 2026-11-04): a 300-record log is
// exported as the header with the first 128 records, then 128 and 44 records, each chunk
// formatted when taken; the chunks together are exactly the stored log's records after a
// fresh header; the export is a snapshot that holds no lock, so a save during it succeeds
// and appears only in the next export.
#[test]
fn export_streams_the_log_in_bounded_chunks_from_a_snapshot_without_the_lock() {
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    let mut file = String::new();
    for i in 0..300 {
        file.push_str(&format!(
            "<call:6>K{:05} <qso_date:8>20261031 <time_on:6>{:02}{:02}00 <band:3>20m <mode:3>FT8 <eor>
",
            i,
            i / 60,
            i % 60
        ));
    }
    assert_eq!(
        summary(&import(&log, file.as_bytes()).0.unwrap()),
        (json!(300), json!(0), json!(0))
    );
    let stored = String::from_utf8(dir.file().unwrap()).unwrap();
    let stored_records = &stored[stored
        .find(
            "<eoh>
",
        )
        .unwrap()
        + 6..];
    let mut export = log.export().unwrap();
    let first = next_chunk(&mut export).unwrap();
    assert!(first.starts_with(
        "ADIF Export
<adif_ver:5>3.1.8
<created_timestamp:15>"
    ));
    assert!(first.contains(
        "<programid:8>WSTXRUST
"
    ));
    // While the export runs the log is not locked: a save succeeds now.
    assert_eq!(
        log.save(reviewed(ID2, "W1XYZ"), GATE).unwrap(),
        SaveOutcome::Saved
    );
    let mut chunks = vec![first];
    chunks.extend(drain(export));
    let counts: Vec<usize> = chunks
        .iter()
        .map(|c| {
            c.matches(
                " <eor>
",
            )
            .count()
        })
        .collect();
    assert_eq!(
        counts,
        [128, 128, 44],
        "bounded chunks of the snapshot (no W1XYZ)"
    );
    let whole = chunks.concat();
    assert_eq!(
        &whole[whole
            .find(
                "<eoh>
"
            )
            .unwrap()
            + 6..],
        stored_records
    );
    let next = drain(log.export().unwrap()).concat();
    assert_eq!(
        next.matches(
            " <eor>
"
        )
        .count(),
        301
    );
    assert!(next.contains("<call:5>W1XYZ "));
}

// ------------------------------------------------------------------ #10 confirmation
/// Synthetic confirmation fixtures (no real log data): ADIF 3.1 QSL Rcvd fields as a
/// logger such as Log4OM 2 exports them.
const CONFIRM_HEADER: &str = "Log4OM 2 test export\n<ADIF_VER:5>3.1.0 <PROGRAMID:7>LOG4OM2 <eoh>\n";

// Proves: CL-010-04; TC-011-002 #10 (2026-11-04) UpdateLogbook keeps LOTW_QSL_RCVD,
// QSL_RCVD, EQSL_QSL_RCVD with their dates and QSL_RCVD_VIA, drops invalid ones, and the
// export carries them (export then update changes nothing); ContactHistory is unchanged.
#[test]
fn update_keeps_each_confirmation_field_and_the_export_round_trips_them() {
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    let file = format!(
        "{CONFIRM_HEADER}<CALL:5>K1ABC <BAND:3>20m <MODE:3>FT8 <QSO_DATE:8>20250218 <TIME_ON:6>225630 \
         <LOTW_QSL_RCVD:1>Y <LOTW_QSLRDATE:8>20250301 <QSL_RCVD:1>V <QSLRDATE:8>20250402 \
         <QSL_RCVD_VIA:1>D <EQSL_QSL_RCVD:1>n <EQSL_QSLRDATE:8>20250219 <QSL_SENT:1>Y <eor>\n\
         <CALL:6>DL1ABC <BAND:3>40m <MODE:3>FT8 <QSO_DATE:8>20250219 <TIME_ON:4>1015 \
         <LOTW_QSL_RCVD:1>X <QSLRDATE:8>20251301 <QSL_RCVD_VIA:1>Q <eor>\n"
    );
    let (result, view) = import(&log, file.as_bytes());
    let result = result.unwrap();
    assert_eq!(summary(&result), (json!(2), json!(0), json!(0)), "{result}");
    assert_eq!(result["confirmed"], json!(0));
    assert_eq!(
        view["dropped"],
        json!([
            {"code":"invalid_value","field":"lotw_qsl_rcvd","count":1,"record":1},
            {"code":"invalid_value","field":"qslrdate","count":1,"record":1},
            {"code":"invalid_value","field":"qsl_rcvd_via","count":1,"record":1}
        ])
    );
    let stored = String::from_utf8(dir.file().unwrap()).unwrap();
    assert!(
        stored.contains(
            "<band:3>20m <lotw_qsl_rcvd:1>Y <lotw_qslrdate:8>20250301 <qsl_rcvd:1>V \
             <qslrdate:8>20250402 <qsl_rcvd_via:1>D <eqsl_qsl_rcvd:1>n <eqsl_qslrdate:8>20250219 \
             <app_wstxrust_contact_id:36>"
        ),
        "{stored}"
    );
    assert!(
        !stored.to_ascii_lowercase().contains("qsl_sent"),
        "{stored}"
    );
    assert!(
        stored.contains("<band:3>40m <app_wstxrust_contact_id:36>"),
        "{stored}"
    );
    // ContactHistory keeps its exact LogRecord keys.
    let history = log.history(ID1, 0, 1).unwrap();
    assert!(history["records"][0].get("lotw_qsl_rcvd").is_none());
    assert_eq!(
        Logbook::open(&dir.0).total().unwrap(),
        2,
        "the stored log reloads"
    );
    let records = parse_records(&dir.file().unwrap(), &limits()).unwrap();
    assert!(records[0].confirmed() && !records[1].confirmed());
    // Export then update: all present, nothing upgraded, the file untouched.
    let before = dir.file().unwrap();
    let exported = drain(log.export().unwrap()).concat();
    assert!(exported.contains("<lotw_qsl_rcvd:1>Y <lotw_qslrdate:8>20250301"));
    let (again, _) = import(&log, exported.as_bytes());
    let again = again.unwrap();
    assert_eq!(summary(&again), (json!(0), json!(2), json!(0)));
    assert_eq!(again["confirmed"], json!(0));
    assert_eq!(dir.file().unwrap(), before);
}

// Proves: CL-010-04; TC-011-002 #10 (2026-11-04) a rerun upgrades the confirmation of
// records already present (N, R, I or absent to Y/V, with date and via), never removes or
// downgrades one, leaves every other stored field, and the summary counts the upgrades.
#[test]
fn update_rerun_upgrades_confirmations_of_present_records_and_never_removes_one() {
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    // The station's own record K1ABC 20m FT8 2026-10-31 12:30:15 (grid FN42).
    assert_eq!(
        log.save(reviewed(ID1, "K1ABC"), GATE).unwrap(),
        SaveOutcome::Saved
    );
    let first = format!(
        "{CONFIRM_HEADER}<CALL:5>W1AAA <BAND:3>40m <MODE:3>FT8 <QSO_DATE:8>20250101 <TIME_ON:4>1000 <LOTW_QSL_RCVD:1>N <eor>\n\
         <CALL:5>W2BBB <BAND:3>40m <MODE:3>FT8 <QSO_DATE:8>20250102 <TIME_ON:4>1000 <LOTW_QSL_RCVD:1>Y <LOTW_QSLRDATE:8>20250110 <eor>\n\
         <CALL:5>W3CCC <BAND:3>40m <MODE:3>FT8 <QSO_DATE:8>20250103 <TIME_ON:4>1000 <QSL_RCVD:1>R <eor>\n"
    );
    let (result, _) = import(&log, first.as_bytes());
    assert_eq!(summary(&result.unwrap()), (json!(3), json!(0), json!(0)));
    let rerun = format!(
        "{CONFIRM_HEADER}<CALL:5>K1ABC <BAND:3>20m <MODE:3>FT8 <QSO_DATE:8>20261031 <TIME_ON:6>123045 <GRIDSQUARE:4>EM10 <RST_RCVD:3>+09 <LOTW_QSL_RCVD:1>Y <LOTW_QSLRDATE:8>20261102 <eor>\n\
         <CALL:5>W1AAA <BAND:3>40m <MODE:3>FT8 <QSO_DATE:8>20250101 <TIME_ON:4>1001 <LOTW_QSL_RCVD:1>V <LOTW_QSLRDATE:8>20250201 <TX_PWR:2>50 <eor>\n\
         <CALL:5>W2BBB <BAND:3>40m <MODE:3>FT8 <QSO_DATE:8>20250102 <TIME_ON:4>1000 <LOTW_QSL_RCVD:1>N <LOTW_QSLRDATE:8>20250301 <QSL_RCVD:1>I <eor>\n\
         <CALL:5>W3CCC <BAND:3>40m <MODE:3>FT8 <QSO_DATE:8>20250103 <TIME_ON:4>1000 <QSL_RCVD:1>Y <QSLRDATE:8>20250120 <QSL_RCVD_VIA:1>B <eor>\n\
         <CALL:5>W3CCC <BAND:3>40m <MODE:3>FT8 <QSO_DATE:8>20250103 <TIME_ON:4>1000 <EQSL_QSL_RCVD:1>Y <eor>\n\
         <CALL:5>W4DDD <BAND:3>40m <MODE:3>FT8 <QSO_DATE:8>20250104 <TIME_ON:4>1000 <EQSL_QSL_RCVD:1>Y <eor>\n\
         <CALL:5>W4DDD <BAND:3>40m <MODE:3>FT8 <QSO_DATE:8>20250104 <TIME_ON:4>1000 <LOTW_QSL_RCVD:1>Y <eor>\n"
    );
    let (result, view) = import(&log, rerun.as_bytes());
    let result = result.unwrap();
    // W4DDD is new (added); its repeat in the same file upgrades the added record.
    assert_eq!(summary(&result), (json!(1), json!(6), json!(0)), "{result}");
    assert_eq!(result["confirmed"], json!(5), "{result}");
    assert_eq!(view["confirmed"], json!(5));
    let records = parse_records(&dir.file().unwrap(), &limits()).unwrap();
    let field = |r: &Record, name: &str| r.get(name).map(str::to_owned);
    let some = |v: &str| Some(v.to_owned());
    // The station record: only its confirmation changed; its grid, report and time won.
    let mut expected = reviewed(ID1, "K1ABC");
    expected.set("lotw_qsl_rcvd", "Y".into());
    expected.set("lotw_qslrdate", "20261102".into());
    assert_eq!(records[0], expected);
    // N -> V with its date; the other fields of the stored record win (no TX_PWR).
    assert_eq!(
        ["lotw_qsl_rcvd", "lotw_qslrdate", "tx_pwr"].map(|n| field(&records[1], n)),
        [some("V"), some("20250201"), None]
    );
    // Y is never downgraded to N and keeps its date; I adds no status either.
    assert_eq!(
        ["lotw_qsl_rcvd", "lotw_qslrdate", "qsl_rcvd"].map(|n| field(&records[2], n)),
        [some("Y"), some("20250110"), None]
    );
    // R -> Y with date and via; the second record of the same QSO adds the eQSL channel.
    assert_eq!(
        ["qsl_rcvd", "qslrdate", "qsl_rcvd_via", "eqsl_qsl_rcvd"].map(|n| field(&records[3], n)),
        [some("Y"), some("20250120"), some("B"), some("Y")]
    );
    assert_eq!(
        ["eqsl_qsl_rcvd", "lotw_qsl_rcvd"].map(|n| field(&records[4], n)),
        [some("Y"), some("Y")]
    );
    assert!(records.iter().all(Record::confirmed));
    // Again: nothing to upgrade and the file stays as it is.
    let after = dir.file().unwrap();
    let (again, _) = import(&log, rerun.as_bytes());
    let again = again.unwrap();
    assert_eq!(summary(&again), (json!(0), json!(7), json!(0)));
    assert_eq!(again["confirmed"], json!(0));
    assert_eq!(dir.file().unwrap(), after);
    // A file that says "not confirmed" removes no confirmation.
    let unconfirm = format!(
        "{CONFIRM_HEADER}<CALL:5>W1AAA <BAND:3>40m <MODE:3>FT8 <QSO_DATE:8>20250101 <TIME_ON:4>1000 <LOTW_QSL_RCVD:1>N <eor>\n"
    );
    assert_eq!(
        import(&log, unconfirm.as_bytes()).0.unwrap()["confirmed"],
        json!(0)
    );
    assert_eq!(dir.file().unwrap(), after);
    // SaveContact of the same record is still already saved; DirectLog replacing the
    // station record (Log QSO again) keeps its confirmation.
    assert_eq!(
        log.save(reviewed(ID1, "K1ABC"), GATE).unwrap(),
        SaveOutcome::AlreadySaved
    );
    let mut changed = reviewed(ID1, "K1ABC");
    changed.set("rst_rcvd", "-07".into());
    assert_eq!(
        log.put(changed.clone(), GATE).unwrap(),
        LogOutcome::Replaced
    );
    let records = parse_records(&dir.file().unwrap(), &limits()).unwrap();
    assert_eq!(field(&records[0], "lotw_qsl_rcvd"), some("Y"));
    assert_eq!(log.put(changed, GATE).unwrap(), LogOutcome::AlreadySaved);
}

// Measurement for review 6683200740 finding 4: the rebuild of a worked set from a 26,902-QSO
// log after one log write (run with --release --nocapture); no timing assertion.
#[cfg(not(debug_assertions))]
#[test]
fn worked_set_rebuild_time_of_a_26902_qso_log() {
    let dir = Dir::new();
    let log = std::sync::Arc::new(Logbook::open(&dir.0));
    let prefixes = [
        "DL", "F", "JA", "VK", "K", "W", "G", "EA", "I", "OH", "UA9", "PY", "ZS", "LU",
    ];
    let mut file = String::from(CONFIRM_HEADER);
    for i in 0..26_902u32 {
        let (day, minute) = (1 + i / 1440 % 28, i % 1440);
        let call = format!(
            "{}{}A{}",
            prefixes[i as usize % prefixes.len()],
            i % 10,
            base26(i)
        );
        // About a quarter with a grid, as the operator's log (6,729 of 26,902).
        let grid = if i % 4 == 0 {
            "<GRIDSQUARE:4>JO62 "
        } else {
            ""
        };
        file.push_str(&format!(
            "<CALL:{}>{call} <BAND:3>20m <MODE:3>FT8 {grid}<QSO_DATE:8>2025{:02}{:02} <TIME_ON:6>{:02}{:02}00 <LOTW_QSL_RCVD:1>Y <eor>\n",
            call.len(), 1 + i / 40_320, day, minute / 60, minute % 60
        ));
    }
    import(&log, file.as_bytes()).0.unwrap();
    assert_eq!(log.total().unwrap(), 26_902);
    for round in 0..5 {
        let more = format!(
            "{CONFIRM_HEADER}<CALL:6>Z{round}1ABC <BAND:3>20m <MODE:3>FT8 <QSO_DATE:8>20260101 <TIME_ON:6>12{round}000 <eor>\n"
        );
        import(&log, more.as_bytes()).0.unwrap();
        let started = Instant::now();
        log.worked_set().unwrap();
        let all = started.elapsed();
        let started = Instant::now();
        log.worked_window(20250101, 20251231).unwrap();
        let window = started.elapsed();
        import(&log, format!("{CONFIRM_HEADER}<CALL:6>Z{round}2ABC <BAND:3>20m <MODE:3>FT8 <QSO_DATE:8>20260102 <TIME_ON:6>12{round}000 <eor>
").as_bytes()).0.unwrap();
        let started = Instant::now();
        assert!(log.worked_latest(None).is_some());
        eprintln!(
            "MEASURE worked_set {all:?} worked_window {window:?} worked_latest (the step) {:?}",
            started.elapsed()
        );
    }
}
#[cfg(not(debug_assertions))]
fn base26(mut n: u32) -> String {
    let mut s = String::new();
    for _ in 0..3 {
        s.push((b'A' + (n % 26) as u8) as char);
        n /= 26;
    }
    s
}

// Proves: TC-039-030 WstxValueOrder::WorkedWindowRule off the station step: the last set at once,
// never built on the caller's thread; the new one follows on its own thread.
#[test]
fn worked_latest_returns_the_last_set_and_builds_off_the_caller() {
    let dir = Dir::new();
    let log = std::sync::Arc::new(Logbook::open(&dir.0));
    let add = |call: &str| {
        let file = format!(
            "{CONFIRM_HEADER}<CALL:6>{call} <BAND:3>20m <MODE:3>FT8 <QSO_DATE:8>20250101 <TIME_ON:4>1000 <eor>\n"
        );
        import(&log, file.as_bytes()).0.unwrap();
    };
    let wait_for = |window: Option<(u32, u32)>, call: &str| {
        let deadline = Instant::now() + std::time::Duration::from_secs(10);
        loop {
            if log
                .worked_latest(window)
                .is_some_and(|w| w.call_standing(call).worked)
            {
                return;
            }
            assert!(Instant::now() < deadline, "never built");
            std::thread::yield_now();
        }
    };
    add("DL1ABC");
    for window in [None, Some((20250101, 20250102))] {
        wait_for(window, "DL1ABC");
        let before = log.worked_latest(window).unwrap();
        add(if window.is_none() { "F1ABCD" } else { "G1ABCD" });
        // At once the set from before the write, whatever a build thread is doing.
        let stale = log.worked_latest(window).unwrap();
        assert!(std::sync::Arc::ptr_eq(&stale, &before));
        wait_for(window, if window.is_none() { "F1ABCD" } else { "G1ABCD" });
    }
    // An unknown window: nothing yet, then its set.
    assert!(log.worked_latest(Some((20250103, 20250104))).is_none());
    let deadline = Instant::now() + std::time::Duration::from_secs(10);
    while log.worked_latest(Some((20250103, 20250104))).is_none() {
        assert!(Instant::now() < deadline, "never built");
        std::thread::yield_now();
    }
}

// Proves: TC-039-030 WstxValueOrder::WorkedWindowRule: only the records of the window, cached until
// the log changes, a record without a date only for all time.
#[test]
fn worked_window_reads_only_the_dated_records_and_is_cached_per_revision() {
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    let file = format!(
        "{CONFIRM_HEADER}<CALL:6>DL1ABC <BAND:3>20m <MODE:3>FT8 <QSO_DATE:8>20250101 <TIME_ON:4>1000 <eor>\n\
         <CALL:5>F1ABC <BAND:3>20m <MODE:3>FT8 <QSO_DATE:8>20250103 <TIME_ON:4>1000 <eor>\n"
    );
    import(&log, file.as_bytes()).0.unwrap();
    let worked = |w: &crate::dxcc::Worked, c: &str| w.call_standing(c).worked;
    let first = log.worked_window(20250101, 20250102).unwrap();
    assert!(worked(&first, "DL1ABC") && !worked(&first, "F1ABC"));
    let second = log.worked_window(20250103, 20250103).unwrap();
    assert!(!worked(&second, "DL1ABC") && worked(&second, "F1ABC"));
    let all = log.worked_set().unwrap();
    assert!(worked(&all, "DL1ABC") && worked(&all, "F1ABC"));
    assert!(
        std::sync::Arc::ptr_eq(&first, &log.worked_window(20250101, 20250102).unwrap()),
        "not rebuilt per evaluation"
    );
    // At most four windows are kept: a fifth drops the oldest.
    for day in 4..8 {
        log.worked_window(20250100 + day, 20250100 + day).unwrap();
    }
    assert!(!std::sync::Arc::ptr_eq(
        &first,
        &log.worked_window(20250101, 20250102).unwrap()
    ));
    // The log changes: the window is rebuilt.
    let cached = log.worked_window(20250103, 20250110).unwrap();
    let more = format!(
        "{CONFIRM_HEADER}<CALL:5>G1ABC <BAND:3>20m <MODE:3>FT8 <QSO_DATE:8>20250104 <TIME_ON:4>1000 <eor>\n"
    );
    import(&log, more.as_bytes()).0.unwrap();
    let rebuilt = log.worked_window(20250103, 20250110).unwrap();
    assert!(!std::sync::Arc::ptr_eq(&cached, &rebuilt));
    assert!(worked(&rebuilt, "G1ABC"));
}

// Proves: CL-010-04; TC-011-002 #10 (2026-11-04) the award query layer: worked vs confirmed
// per DXCC entity, entity x band and entity x band x mode from one lookup of the worked set
// (needed = not worked or not confirmed), rebuilt when a rerun adds a confirmation.
#[test]
fn worked_set_reports_worked_and_confirmed_per_entity_band_and_mode() {
    use crate::dxcc::{Category, Standing};
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    let file = format!(
        "{CONFIRM_HEADER}<CALL:6>DL1ABC <BAND:3>20m <MODE:3>FT8 <QSO_DATE:8>20250101 <TIME_ON:4>1000 <LOTW_QSL_RCVD:1>Y <eor>\n\
         <CALL:6>DL2XYZ <BAND:3>40m <MODE:3>FT8 <QSO_DATE:8>20250102 <TIME_ON:4>1000 <LOTW_QSL_RCVD:1>N <eor>\n\
         <CALL:6>DL3QRP <BAND:3>40m <MODE:4>MFSK <SUBMODE:3>FT4 <QSO_DATE:8>20250103 <TIME_ON:4>1000 <QSL_RCVD:1>V <eor>\n\
         <CALL:5>F1ABC <BAND:3>20m <MODE:3>FT8 <QSO_DATE:8>20250104 <TIME_ON:4>1000 <eor>\n"
    );
    import(&log, file.as_bytes()).0.unwrap();
    let (table, _) = log.dxcc();
    let germany = table.lookup("DL9ZZZ").unwrap();
    let france = table.lookup("F9ZZZ").unwrap();
    let japan = table.lookup("JA1ZZZ").unwrap();
    let w = log.worked_set().unwrap();
    let s = |r, band, mode| w.entity_standing(Category::Dxcc, r, band, mode);
    let (yes, unconfirmed, no) = (
        Standing {
            worked: true,
            confirmed: true,
        },
        Standing {
            worked: true,
            confirmed: false,
        },
        Standing {
            worked: false,
            confirmed: false,
        },
    );
    assert_eq!(s(&germany, None, None), yes);
    assert_eq!(s(&germany, Some("20M"), None), yes);
    assert_eq!(
        s(&germany, Some("40m"), None),
        yes,
        "DL3QRP 40m FT4 confirms 40m"
    );
    assert_eq!(s(&germany, Some("20m"), Some("ft8")), yes);
    assert_eq!(s(&germany, Some("40m"), Some("FT8")), unconfirmed);
    assert_eq!(s(&germany, Some("40m"), Some("FT4")), yes);
    assert_eq!(s(&germany, Some("15m"), None), no);
    assert_eq!(s(&france, None, None), unconfirmed);
    assert_eq!(s(&france, Some("20m"), Some("FT8")), unconfirmed);
    assert_eq!(s(&japan, None, None), no);
    assert!(!yes.needed() && unconfirmed.needed() && no.needed());
    // A rerun that confirms F1ABC rebuilds the worked set.
    let confirm = format!(
        "{CONFIRM_HEADER}<CALL:5>F1ABC <BAND:3>20m <MODE:3>FT8 <QSO_DATE:8>20250104 <TIME_ON:4>1000 <EQSL_QSL_RCVD:1>Y <eor>\n"
    );
    assert_eq!(
        import(&log, confirm.as_bytes()).0.unwrap()["confirmed"],
        json!(1)
    );
    let w = log.worked_set().unwrap();
    assert_eq!(
        w.entity_standing(Category::Dxcc, &france, Some("20m"), Some("FT8")),
        yes
    );
    assert_eq!(
        w.entity_standing(Category::Dxcc, &germany, Some("40m"), Some("FT8")),
        unconfirmed
    );
}

// Proves: CL-010-04; TC-011-002 #10 a log written before #10 (the former ImportAdi kept
// unknown fields verbatim) whose QSL fields are invalid or repeated stays readable: those
// stay unknown fields; a valid one becomes the record's confirmation.
#[test]
fn stored_log_with_former_verbatim_qsl_fields_stays_readable() {
    let dir = Dir::new();
    let text = format!(
        "header\n<eoh>\n<call:5>K1ABC <mode:3>FT8 <qso_date:8>20250101 <time_on:4>1000 <app_wstxrust_contact_id:36>{ID1} <QSL_RCVD:1>Y <QSL_RCVD:1>N <LOTW_QSL_RCVD:3>yes <eor>\n"
    );
    fs::write(dir.0.join(FILE_NAME), &text).unwrap();
    let log = Logbook::open(&dir.0);
    assert_eq!(log.total().unwrap(), 1);
    let records = parse_records(text.as_bytes(), &limits()).unwrap();
    assert_eq!(records[0].get("qsl_rcvd"), Some("Y"));
    assert_eq!(records[0].get("lotw_qsl_rcvd"), None);
    assert_eq!(
        records[0]
            .unknown
            .iter()
            .map(|u| u.name.as_str())
            .collect::<Vec<_>>(),
        ["QSL_RCVD", "LOTW_QSL_RCVD"]
    );
}
