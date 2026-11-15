use super::super::search::complete;
use super::*;

fn pattern() -> Vec<f32> {
    (0..24)
        .map(|k| {
            (0.6 * (2. * PI * k as f64 / 24. + 0.4).cos()
                + 0.9 * (2. * PI * 5. * k as f64 / 24. + 0.7).cos()) as f32
        })
        .collect()
}
// Exact finite periodic-sum DFT of the stored dyadic float32 pattern; no FFT helper.
fn scalar_bin(pattern: &[f32], repeats: usize, n: usize, bin: usize) -> Complex64 {
    let omega = -2. * PI * bin as f64 / n as f64;
    let one = pattern
        .iter()
        .enumerate()
        .map(|(j, &x)| Complex64::from_polar(x as f64, omega * j as f64))
        .sum::<Complex64>();
    let step = omega * pattern.len() as f64;
    let denominator = (step / 2.).sin();
    let repeated = if denominator.abs() < 1e-12 {
        Complex64::new(repeats as f64, 0.)
    } else {
        Complex64::from_polar(
            (repeats as f64 * step / 2.).sin() / denominator,
            step * (repeats - 1) as f64 / 2.,
        )
    };
    one * repeated
}
fn independent_band(
    mode: Mode,
    carrier: f64,
    n: usize,
    m: usize,
    pattern: &[f32],
    repeats: usize,
) -> (Vec<(isize, Complex64)>, f64) {
    let df = 12000. / n as f64;
    let center = (carrier / df).round() as isize;
    let mut frequencies = vec![];
    match mode {
        Mode::Ft8 => {
            let first = ((carrier - 9.375) / df).round() as usize;
            let last = ((carrier + 53.125) / df).round() as usize;
            let taper = (6.25 / df).round() as usize;
            for i in first..=last {
                let edge = (i - first).min(last - i);
                let weight = if edge < taper {
                    (1. - (PI * edge as f64 / taper as f64).cos()) / 2.
                } else {
                    1.
                };
                frequencies.push((
                    i as isize - center,
                    scalar_bin(pattern, repeats, n, i) * weight / ((n * m) as f64).sqrt(),
                ));
            }
        }
        Mode::Ft4 => {
            let transition = (10.416666666666666 / df).floor() as usize;
            let flat = (83.33333333333333 / df).floor() as usize;
            let shift = (20.833333333333332 / df).floor() as isize;
            for w in 0..2 * transition + flat {
                let offset = w as isize - shift;
                let weight = if w < transition {
                    (1. + (PI * (transition - 1 - w) as f64 / transition as f64).cos()) / 2.
                } else if w < transition + flat {
                    1.
                } else {
                    (1. + (PI * (w - transition - flat) as f64 / transition as f64).cos()) / 2.
                };
                frequencies.push((
                    offset,
                    scalar_bin(pattern, repeats, n, (center + offset) as usize) * weight / m as f64,
                ));
            }
        }
    }
    let rms = if mode == Mode::Ft4 {
        frequencies
            .iter()
            .map(|(_, z)| z.norm_sqr())
            .sum::<f64>()
            .sqrt()
    } else {
        1.
    };
    (frequencies, rms)
}
// Proves: FR-003, FR-004, CL-007-03, CL-007-04.
#[test]
fn bandlimit_matches_independent_periodic_dft_and_parseval() {
    let pattern = pattern();
    let repeats = 7500;
    let input = pattern.repeat(repeats);
    for mode in [Mode::Ft8, Mode::Ft4] {
        let plan = BandPlan::new(mode, input.len(), false).unwrap();
        let never = || false;
        let mut budget = CpuBudget::new(&never);
        let mut pass = complete(plan.current_pass(&input, &mut budget)).unwrap();
        let tolerance = 1e-9 * input.iter().map(|x| (*x as f64).abs()).sum::<f64>();
        for i in [
            1,
            371,
            plan.long_len / 24,
            5 * plan.long_len / 24,
            plan.long_len / 2,
        ] {
            assert!(
                (pass.spectrum[i] - scalar_bin(&pattern, repeats, plan.long_len, i)).norm()
                    < tolerance
            );
        }
        for carrier in [500.02, 500.04] {
            let window = complete(pass.window(carrier, &mut budget))
                .unwrap()
                .unwrap();
            let (frequency, rms) = independent_band(
                mode,
                carrier,
                plan.long_len,
                plan.short_len,
                &pattern,
                repeats,
            );
            let expected_center =
                (carrier * plan.long_len as f64 / 12000.).round() * 12000. / plan.long_len as f64;
            assert!((window.center_hz - expected_center).abs() <= 1e-12);
            for j in [0, 1, 17, 511, plan.short_len - 1] {
                let expected = frequency
                    .iter()
                    .map(|(bin, z)| {
                        *z * Complex64::from_polar(
                            1.,
                            2. * PI * *bin as f64 * j as f64 / plan.short_len as f64,
                        )
                    })
                    .sum::<Complex64>()
                    / rms;
                assert!(
                    (window.samples[j] - expected).norm() <= 1e-8,
                    "{mode:?} {carrier} sample{j}: {:?} != {expected:?}",
                    window.samples[j]
                );
            }
        }
    }
}

// Proves: FR-003, FR-004, CL-007-03.
#[test]
fn admission_rounding_half_ties_and_complete_end_support() {
    for (start, expected) in [(29, 0), (30, 1), (31, 1), (89, 1), (90, 2), (91, 2)] {
        assert_eq!(admission_origin(Mode::Ft8, start, 180000), expected);
    }
    for (start, expected) in [(8, 32), (9, 33), (10, 33)] {
        assert_eq!(admission_origin(Mode::Ft4, start, 180000), expected);
    }
    // Nearest sampling position would exceed actual support: clamp the observation,
    // rather than pad support or alter the original reported31-frame origin.
    assert_eq!(admission_origin(Mode::Ft8, 31, 151711), 0);
}
