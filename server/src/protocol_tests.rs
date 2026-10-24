use super::reply;
use serde_json::json;

// Proves: FR-021; TC-021-005. Level 2: isolated tests on Windows PC/CI.
#[test]
fn protocol_returns_specified_response_and_errors() {
    assert_eq!(
        reply(r#"{"v":1,"type":"station.get","id":12}"#),
        json!({"v":1,"type":"station.status","id":12,"data":{"version":"0.1.0","radio":"unconfigured"}})
    );
    for (input, code) in [
        ("{", "invalid_json"),
        ("[]", "invalid_request"),
        (
            r#"{"v":2,"type":"station.get","id":1}"#,
            "unsupported_version",
        ),
        (r#"{"v":1,"type":"unknown","id":1}"#, "unknown_command"),
        (r#"{"v":1,"type":"station.get"}"#, "invalid_request"),
        (
            r#"{"v":1,"type":"station.get","id":"1"}"#,
            "invalid_request",
        ),
        (r#"{"v":1,"type":null,"id":1}"#, "invalid_request"),
        (
            r#"{"v":1,"type":"station.get","id":9007199254740992}"#,
            "invalid_request",
        ),
    ] {
        assert_eq!(reply(input)["data"]["code"], code, "{input}");
    }
}
