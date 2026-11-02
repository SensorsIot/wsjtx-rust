use super::*;
// Proves: CL-007-02.
#[test]
fn ft8_period_follows_the_receive_period_grid() {
    // A known period start places every window's periods on its 180000-frame grid (#52).
    assert_eq!(period_of(360000, 22000, Some(14400)), 14400);
    assert_eq!(
        period_of(360000, 22000 + 180000, Some(14400)),
        14400 + 180000
    );
    assert_eq!(period_of(0, 6000 + 9000, Some(0)), 0);
    // A window that starts after its period start sees it at a negative offset.
    assert_eq!(period_of(194400 + 8400, 0, Some(14400)), -8400);
    // Unknown: the period begins 0.5 s before the frame.
    assert_eq!(period_of(360000, 22000, None), 16000);
}
