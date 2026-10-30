use super::super::search::complete;
use super::*;
// Proves: FR-004, CL-007-03.
#[test]
fn periodic_nuttall_spectrum_matches_direct_dft() {
    let input = (0..N + 576)
        .map(|j| {
            let t = j as f64 / 12000.;
            (0.31 * (2. * PI * 1000.03 * t + 0.4).cos() + 0.17 * (2. * PI * 1500.7 * t - 0.2).sin())
                as f32
        })
        .collect::<Vec<_>>();
    for scalar in [false, true] {
        let never = || false;
        let actual = complete(spectrum(&input, scalar, &mut CpuBudget::new(&never))).unwrap();
        for k in [0, 38, 100, 191, 192, 288, 678, 1152] {
            let mut expected = 0.;
            for start in [0, 576] {
                let mut dot = Complex64::new(0., 0.);
                for j in 0..N {
                    // Independent explicit periodic formula and scalar DFT, no FFT/window helper.
                    let a = 2. * PI * j as f64 / 2304.;
                    let w = 0.3635819 - 0.4891775 * a.cos() + 0.1365995 * (2. * a).cos()
                        - 0.0106411 * (3. * a).cos();
                    dot += Complex64::from_polar(
                        input[start + j] as f64 * w / 300.,
                        -2. * PI * k as f64 * j as f64 / 2304.,
                    );
                }
                expected += dot.norm_sqr() / 2.;
            }
            assert!(
                (actual[k] - expected).abs() < 1e-12_f64.max(expected.abs() * 1e-10),
                "k{k} scalar{scalar}"
            );
        }
    }
}
// Proves: FR-004, CL-007-03.
#[test]
fn quartic_baseline_preserves_db_offset_and_positive_power() {
    for degree in [0, 4] {
        let db = |i: usize| {
            let x = (i as f64 - 358.) / 320.;
            if degree == 0 {
                -30.
            } else {
                -30. + 2. * x - 1.3 * x * x + 0.4 * x.powi(3) + 0.7 * x.powi(4)
            }
        };
        let powers = (0..=N / 2)
            .map(|i| 10f64.powf(db(i) / 10.))
            .collect::<Vec<_>>();
        let actual = baseline(&powers).unwrap();
        for (i, value) in actual.iter().enumerate().take(IB + 1).skip(IA) {
            let expected = 10f64.powf((db(i) + 0.65) / 10.);
            assert!((value / expected - 1.).abs() < 1e-10, "degree{degree} i{i}");
        }
    }
    assert!(baseline(&vec![0.; N / 2 + 1]).is_none());
    let mut invalid = vec![1.; N / 2 + 1];
    invalid[200] = f64::NAN;
    assert!(baseline(&invalid).is_none());
    invalid[200] = -1.;
    assert!(baseline(&invalid).is_none());
}

// Proves: FR-004, CL-007-03.
#[test]
fn percentile_half_ties_remainder_and_endpoint_contrast() {
    let mut ranks = (1..=65).rev().map(f64::from).collect::<Vec<_>>();
    assert_eq!(cutoff(&mut ranks), Some(7.)); //65*.1=6.5 -> rank7, one-based.
    assert_eq!(cutoff(&mut [4., 4., 4., 4., 4.]), Some(4.));
    assert_eq!(cutoff(&mut []), None);
    let mut powers = vec![1.; N / 2 + 1];
    powers[IB] = 1e10; //641fit bins: ten64-bin segments exclude final remainder.
    let actual = baseline(&powers).unwrap();
    assert!((actual[IB] - 10f64.powf(0.065)).abs() < 1e-11);
    let mut ratio = vec![0.; N / 2 + 1];
    ratio[44] = 1.;
    ratio[45] = 2.; //200Hz maps to44.4, interpolate AFTER ratio.
    assert!((endpoint_contrast(&ratio, 200.) - 1.4).abs() < 1e-13);
    ratio[678] = 1.18;
    ratio[679] = f64::NAN; //3500Hz is exact bin678: no neighbor read.
    assert_eq!(endpoint_contrast(&ratio, 3500.), 1.18);
}

// Proves: FR-004, CL-007-03.
#[test]
fn unused_quartic_extrapolation_cannot_erase_the_fit_band() {
    for scale in [-500., 500.] {
        let mut powers = vec![1.; N / 2 + 1];
        for (i, value) in powers.iter_mut().enumerate().take(IB + 1).skip(IA) {
            let x = (i as f64 - (IA + IB) as f64 / 2.) / ((IB - IA) as f64 / 2.);
            *value = 10f64.powf(scale * x.powi(4) / 10.);
        }
        let actual = baseline(&powers).expect("finite in-band quartic must remain eligible");
        for i in [IA, 100, 358, 600, IB] {
            assert!((actual[i] / (powers[i] * 10f64.powf(0.065)) - 1.).abs() < 1e-8);
        }
    }
}
// Proves: FR-004, CL-007-03.
#[test]
fn fifteen_bin_flat_maximum_retains_its_carrier_coverage() {
    // The exact ratio plateau made by smoothing one elevated bin over15bins.
    let mut ratio = vec![1.; N / 2 + 1];
    ratio[193..=207].fill(2.);
    let actual = peaks(&ratio);
    assert_eq!(actual.len(), 15);
    assert!((actual[0].0 - 976.5625).abs() < 1e-10);
    assert!((actual[1].0 - 1044.2708333333333).abs() < 1e-10);
    assert_eq!(actual[0].1, 2.125);
    assert_eq!(actual[1].1, 2.125);
    for (point, bin) in actual[2..].iter().zip(194..=206) {
        assert!((point.0 - (f64::from(bin) * 125. / 24. - 31.25)).abs() < 1e-10);
        assert_eq!(point.1, 2.);
    }
    assert!(actual.iter().any(|p| (p.0 - 1000.).abs() < 1e-10));
}
