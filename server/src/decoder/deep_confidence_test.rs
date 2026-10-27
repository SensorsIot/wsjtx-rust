use super::*;
// Proves: CL-007-03, TC-004-002. Constant spectra have a constant quartic envelope.
#[test]
fn constant_envelope_and_private_confidence_boundaries() {
    let base = coarse_ft4::baseline_for_range(&vec![1.; 1921], 64, 1120).unwrap();
    let expected = 10f64.powf(0.65 / 10.);
    for value in &base[64..=1120] {
        assert!((value - expected).abs() < 1e-9);
    }
    let confidence = Confidence {
        baseline: Some(vec![1.; 1921]),
    };
    assert_eq!(confidence.score(1000., 0.), Some(-57.));
    // q=100: 10log10(100)-27=-7dB. This is not the public SNR estimator.
    assert!((confidence.score(1000., 3e6 * 1e-4 * 101.).unwrap() + 7.).abs() < 1e-12);
    let threshold = 3e6 * 1e-4 * (1. + 10f64.powf(0.2));
    assert!(confidence.score(1000., threshold * (1. - 1e-10)).unwrap() < -25.);
    assert!(confidence.score(1000., threshold * (1. + 1e-10)).unwrap() > -25.);
}
// Proves: CL-007-04, TC-004-003. Early upper-bound refusal cannot hide an accepted tone sequence.
#[test]
fn max_tone_power_is_an_upper_bound_for_every_selected_word() {
    let confidence = Confidence {
        baseline: Some(vec![1.; 1921]),
    };
    let rows = vec![vec![Complex64::new(1., 0.); 8]; 79];
    assert!(confidence.possible(&rows, 1000.));
    assert!(confidence.accepts(&rows, &[0; 79], 1000.));
    let rows = vec![vec![Complex64::new(0., 0.); 8]; 79];
    assert!(!confidence.possible(&rows, 1000.));
    assert!(!confidence.accepts(&rows, &[7; 79], 1000.));
}
