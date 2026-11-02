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
        ],
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
    assert_eq!(parse(exact.as_bytes(), &limits()).unwrap().len(), 100_000);
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
    assert_eq!(result.unwrap()["new"], 1);
    assert_eq!(view["received_bytes"], IMPORT_BYTES_MAX);
    assert_eq!(log.total().unwrap(), 1);
}

// Proves: CL-010-04; TC-011-002 unknown and other APP_ fields re-export byte-identical.
#[test]
fn unknown_fields_are_preserved_verbatim_and_new_records_gain_a_contact_id() {
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    let unknown = "<APP_N1MM_EXCHANGE1:4:S>5NN\t <userdef7:3>a<b <Name:4>Jo\r\n";
    let text =
        format!("<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <mode:3>FT8 {unknown} <eor>");
    let (result, _) = import(&log, text.as_bytes());
    assert_eq!(result.unwrap()["new"], 1);
    let exported = String::from_utf8(log.export().unwrap()).unwrap();
    assert!(exported.starts_with("ADIF Export\n<adif_ver:5>3.1.8\n<created_timestamp:15>"));
    assert!(exported.contains("<programid:8>WSTXRUST\n"));
    assert!(
        exported.contains("<APP_N1MM_EXCHANGE1:4:S>5NN\t <userdef7:3>a<b <Name:4>Jo\r\n <eor>\n"),
        "{exported}"
    );
    let stored = parse_records(&dir.file().unwrap(), &limits()).unwrap();
    assert!(crate::profile::valid_uuid(&stored[0].contact_id));
    assert_eq!(stored[0].unknown.len(), 3);
    assert_eq!(
        log.history(ID1, 0, 1).unwrap()["records"][0]["unknown_field_count"],
        3
    );
    let (again, _) = import(&log, exported.as_bytes());
    let again = again.unwrap();
    assert_eq!(
        (
            again["new"].clone(),
            again["duplicate"].clone(),
            again["conflict"].clone()
        ),
        (json!(0), json!(1), json!(0))
    );
    assert_eq!(
        log.total().unwrap(),
        1,
        "export then import yields only duplicates"
    );
}

// Proves: CL-010-04; TC-011-002 natural key duplicates, id conflicts, all-or-nothing.
#[test]
fn natural_key_duplicates_id_conflicts_and_any_conflict_publishes_nothing() {
    let dir = Dir::new();
    let log = Logbook::open(&dir.0);
    assert_eq!(
        log.save(reviewed(ID1, "K1ABC"), GATE).unwrap(),
        SaveOutcome::Saved
    );
    let saved = dir.file().unwrap();
    // CALL case, TIME_ON HHMM vs HHMMSS, FREQ only instead of BAND: same natural key.
    let natural = "<call:5>k1abc <qso_date:8>20261031 <time_on:4>1230 <freq:7>14.0755 <mode:3>ft8 <rst_sent:3>-12 <eor>\n";
    let fresh =
        "<call:5>N0NEW <qso_date:8>20261031 <time_on:4>1300 <band:3>40m <mode:3>FT8 <eor>\n";
    let (result, _) = import(&log, format!("{natural}{fresh}{fresh}").as_bytes());
    let result = result.unwrap();
    assert_eq!(
        (
            result["new"].clone(),
            result["duplicate"].clone(),
            result["conflict"].clone()
        ),
        (json!(1), json!(2), json!(0))
    );
    assert_eq!(calls(&log), ["K1ABC", "N0NEW"]);
    let after = dir.file().unwrap();
    // Natural-key match with a differing value, and an id match with a differing value.
    let differing = "<call:5>K1ABC <qso_date:8>20261031 <time_on:6>123015 <band:3>20m <mode:3>FT8 <rst_rcvd:3>+03 <eor>\n";
    let by_id = format!(
        "<call:5>K1ABC <qso_date:8>20261031 <time_on:6>123015 <mode:3>FT8 <app_wstxrust_contact_id:36>{ID1} <eor>\n"
    );
    let other = "<call:5>W1XYZ <qso_date:8>20261031 <time_on:4>1400 <mode:3>FT8 <eor>\n";
    for (bad, field) in [(differing.to_owned(), "rst_rcvd"), (by_id, "gridsquare")] {
        let (result, view) = import(&log, format!("{other}{bad}").as_bytes());
        assert_eq!(result, Err("import_failed"));
        assert_eq!(view["state"], "failed");
        assert_eq!(
            view["error"],
            json!({"code":"identity_conflict","record":1,"field":field})
        );
        assert_eq!(
            (view["new"].clone(), view["conflict"].clone()),
            (json!(1), json!(1)),
            "counts are still reported"
        );
        assert_eq!(dir.file().unwrap(), after, "zero records published");
        assert_eq!(log.total().unwrap(), 2);
    }
    let (invalid, view) = import(&log, format!("{other}<call:5>K1ABC <eor>").as_bytes());
    assert_eq!(invalid, Err("import_failed"));
    assert_eq!(
        view["error"],
        json!({"code":"missing_required_field","record":1,"field":"qso_date"})
    );
    assert_eq!(dir.file().unwrap(), after);
    assert_ne!(saved, after);
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
