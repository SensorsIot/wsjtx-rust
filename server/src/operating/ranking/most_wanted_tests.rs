// Hand-written list text and replies; no network.
use super::*;
// Proves: TC-039-055
#[test]
fn tc_039_031_parser_refuses_all_but_the_exact_list() {
    let ok = List::parse(r#"{"1":"344","2":123,"3":"9999"}"#, "2026-11-06").unwrap();
    assert_eq!(ok.entries(), 3);
    assert_eq!(ok.unmapped, 1, "9999 has no entity");
    assert_eq!(ok.rank("Fed. Rep. of Germany"), None, "230 is not listed");
    assert_eq!(ok.rank("DPR of Korea"), Some(1), "ADIF 344");
    for bad in [
        "",
        "[]",
        "{}",
        r#"{"x":"344"}"#,
        r#"{"0":"344"}"#,
        r#"{"1":"x"}"#,
        r#"{"1":"0"}"#,
        r#"{"1":"10000"}"#,
        r#"{"1":"344","2":"344"}"#,
        r#"{"1":null}"#,
    ] {
        assert_eq!(List::parse(bad, "d"), None, "{bad}");
    }
    let many: serde_json::Map<String, Value> = (1..=1001)
        .map(|i| (i.to_string(), json!(i.to_string())))
        .collect();
    assert_eq!(List::from_value(&Value::Object(many), "d"), None);
}
// Proves: TC-039-031
#[test]
fn tc_039_031_every_bundled_entity_has_its_adif_number() {
    let table = crate::dxcc::Table::default();
    for name in table.cty.entity_names() {
        assert!(adif_number(name).is_some(), "{name}");
    }
    // The 340 current DXCC entities (the Club Log list of 2026-11-06 has 340 too).
    assert_eq!(known_numbers().len(), 340);
    // Known answers from the ADIF specification's DXCC table.
    for (name, number) in [
        ("Switzerland", 287),
        ("United States", 291),
        ("Fed. Rep. of Germany", 230),
        ("Japan", 339),
        ("DPR of Korea", 344),
        ("Sicily", 248),
        ("Italy", 248),
        ("Shetland Islands", 279),
        ("Scotland", 279),
        ("Cape Verde", 409),
        ("Cabo Verde", 409),
    ] {
        assert_eq!(adif_number(name), Some(number), "{name}");
    }
}
// Proves: TC-039-055
#[test]
fn tc_039_031_response_body() {
    assert_eq!(
        response_body(b"HTTP/1.1 200 OK\r\nServer: x\r\n\r\n{\"1\":\"344\"}"),
        Ok("{\"1\":\"344\"}".to_owned())
    );
    assert_eq!(
        response_body(b"HTTP/1.1 503 Busy\r\n\r\nno"),
        Err("status 503".to_owned())
    );
    assert_eq!(response_body(b"junk"), Err("no response".to_owned()));
}
