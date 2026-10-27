use super::*;
// Proves: CL-007-03. Square coherent hypotheses before class maxima/differences.
#[test]
fn pass_power_is_applied_before_max_log_difference() {
    let mut rows = vec![vec![Complex64::new(0., 0.); 8]; 2];
    // Gray values 0 and 4 belong to opposite high-bit classes.
    let gray = Mode::Ft8.gray_map();
    rows[0][gray[0]] = Complex64::new(3., 0.);
    rows[0][gray[4]] = Complex64::new(2., 0.);
    let magnitude = group_scores_with_power(&rows, 0, 1, Mode::Ft8, false);
    let power = group_scores_with_power(&rows, 0, 1, Mode::Ft8, true);
    assert_eq!(raw_metric(&magnitude, 4), (-1., 3.));
    assert_eq!(raw_metric(&power, 4), (-5., 9.));
    assert_ne!(raw_metric(&power, 4).0, raw_metric(&magnitude, 4).0.powi(2));
}
// Proves: CL-007-03. The optional policy's hard-error gate is bounded independently of FEC.
#[test]
fn deep_hard_error_and_mean_magnitude_boundaries() {
    let mut word = [0; 174];
    word[100] = 1;
    let mut llr = [1.; 174];
    llr[100] = -1.;
    for value in &mut llr[..36] {
        *value = -1.;
    }
    assert!(deep_channel_gates(&word, &llr));
    llr[36] = -1.;
    assert!(!deep_channel_gates(&word, &llr));
    let low = std::array::from_fn(|i| if word[i] == 0 { 0.999 } else { -0.999 });
    assert!(!deep_channel_gates(&word, &low));
    assert!(!deep_channel_gates(&[0; 174], &[1.; 174]));
}
