use super::*;
// Proves: CL-007-03. An independent power table distinguishes ABC, BC and eighth-tone noise.
#[test]
fn seven_tone_costas_uses_the_better_abc_or_bc_score() {
    let mut spectrum = Spectrum {
        values: vec![Complex32::new(1., 0.); 317 * 16],
        width: 16,
        regular: 1,
        frequencies: vec![200.],
        hop: 480,
        mode: Mode::Ft8,
        sync: Mode::Ft8.sync(),
    };
    for (index, &(symbol, tone)) in spectrum.sync.iter().enumerate() {
        let row = 4 * symbol;
        // A: target power 1; B/C: target power 4. Six competitor powers are all 1.
        spectrum.values[row * 16 + 2 * tone as usize] =
            Complex32::new(if index < 7 { 1. } else { 2. }, 0.);
        // The eighth tone must never enter this source's seven-tone statistic.
        spectrum.values[row * 16 + 14] = Complex32::new(1000., 0.);
    }
    // ABC = 6*(7+14*4)/(21*6) = 3; BC = 6*(14*4)/(14*6) = 4.
    assert!((spectrum.deep_costas_ratio(0, 0) - 4.).abs() < 1e-12);
}
// Proves: CL-007-03. Two starts per frequency prevent a global percentile implementation passing.
#[test]
fn normalization_uses_frequency_maxima_and_source_percentile() {
    let mut scores = [1., 2., 3., 4., 5., 10., 8., 6., 4., 2.];
    assert!(normalize_deep_scores(&mut scores, 2, 5));
    // Frequency maxima [10,8,6,4,5], sorted [4,5,6,8,10]; nint(.4*5)=2 => 5.
    assert_eq!(scores, [0.2, 0.4, 0.6, 0.8, 1., 2., 1.6, 1.2, 0.8, 0.4]);
    assert!(!normalize_deep_scores(&mut [0.; 10], 2, 5));
    assert!(!normalize_deep_scores(&mut [f64::INFINITY; 10], 2, 5));
}
