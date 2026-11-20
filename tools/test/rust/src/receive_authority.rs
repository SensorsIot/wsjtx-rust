//! The test authority of the standalone receive-only radio query probe: the evidence that
//! keying is inhibited, or the operator's explicit unrestricted receive test.

pub fn receive_test_authority(
    inhibit: Option<&str>,
    operator: Option<&str>,
) -> Option<(&'static str, &'static str)> {
    if inhibit == Some("USB_SEND_CW_RTTY_OFF") {
        Some(("verified_keying_inhibit", "USB_SEND_CW_RTTY_OFF"))
    } else if operator == Some("UNRESTRICTED_RECEIVE_TEST") {
        Some(("user_explicit_unrestricted", "unverified"))
    } else {
        None
    }
}

#[test]
fn standalone_query_authority_preserves_truthful_keying_evidence() {
    assert_eq!(receive_test_authority(None, None), None);
    assert_eq!(receive_test_authority(None, Some("yes")), None);
    assert_eq!(receive_test_authority(Some("unknown"), None), None);
    assert_eq!(
        receive_test_authority(Some("USB_SEND_CW_RTTY_OFF"), None),
        Some(("verified_keying_inhibit", "USB_SEND_CW_RTTY_OFF"))
    );
    assert_eq!(
        receive_test_authority(None, Some("UNRESTRICTED_RECEIVE_TEST")),
        Some(("user_explicit_unrestricted", "unverified"))
    );
}
