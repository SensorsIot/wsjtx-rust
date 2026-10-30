use super::super::search::complete;
use super::*;

// Direct time-domain convolution at selected independent points, never an FFT oracle.
fn expected_at(original: &[f32], start: usize, wave: &[[f32; 2]], k: usize, mode: Mode) -> f64 {
    let radius = if mode == Mode::Ft8 {
        2000isize
    } else {
        700isize
    };
    let weight = |j: isize| (PI * j as f64 / (2 * radius) as f64).cos().powi(2);
    let total = (-radius..=radius).map(weight).sum::<f64>();
    let mut envelope = Complex64::new(0., 0.);
    for j in -radius..=radius {
        let position = k as isize - j;
        if !(0..wave.len() as isize).contains(&position) {
            continue;
        }
        let i = position as usize;
        envelope += Complex64::new(wave[i][0] as f64, -(wave[i][1] as f64))
            * original[start + i] as f64
            * (weight(j) / total);
    }
    if mode == Mode::Ft8 {
        let edge = k.min(wave.len() - 1 - k);
        if edge <= radius as usize {
            envelope *= total / (-radius..=edge as isize).map(weight).sum::<f64>();
        }
    }
    original[start + k] as f64
        - 2. * (wave[k][0] as f64 * envelope.re - wave[k][1] as f64 * envelope.im)
}
// Proves: FR-003, FR-004, CL-007-03, CL-007-04.
#[test]
fn envelope_cancellation_matches_scalar_convolution_and_edges() {
    for mode in [Mode::Ft8, Mode::Ft4] {
        let (frame, radius) = if mode == Mode::Ft8 {
            (151680, 2000)
        } else {
            (60480, 700)
        };
        let wave = (0..frame)
            .map(|k| {
                let phase = 2. * PI * 1000. * (k + 1) as f64 / 12000. + 0.31;
                [phase.cos() as f32, phase.sin() as f32]
            })
            .collect::<Vec<_>>();
        let start = 13;
        let mut original = vec![0.123f32; frame + 29];
        for (k, q) in wave.iter().enumerate() {
            let t = k as f64 / 12000.;
            original[start + k] = ((0.35 + 0.1 * (2. * PI * 0.7 * t).cos()) * q[0] as f64
                + (0.2 - 0.05 * (2. * PI * 0.4 * t).sin()) * q[1] as f64
                + 0.001 * (2. * PI * 3000. * t + 0.6).cos())
                as f32;
        }
        let points = [
            0,
            1,
            radius - 1,
            radius,
            radius + 1,
            frame / 2,
            frame - radius - 2,
            frame - radius - 1,
            frame - 2,
            frame - 1,
        ];
        let expected = points.map(|k| expected_at(&original, start, &wave, k, mode));
        for scalar in [false, true] {
            let mut subtractor = Subtractor::new(mode, scalar).unwrap();
            let mut actual = original.clone();
            let never = || false;
            let mut budget = CpuBudget::new(&never);
            complete(subtractor.subtract(&mut actual, start, &wave, &mut budget)).unwrap();
            assert_eq!(&actual[..start], &original[..start]);
            assert_eq!(&actual[start + frame..], &original[start + frame..]);
            for (&k, expected) in points.iter().zip(expected) {
                assert!(
                    (actual[start + k] as f64 - expected).abs() <= 1e-7,
                    "{mode:?} scalar{scalar} k{k}: {} != direct{expected}",
                    actual[start + k]
                );
            }
        }
    }
}
// Proves: FR-003, FR-004, CL-007-04.
#[test]
fn cancelled_or_incomplete_subtraction_leaves_input_unchanged() {
    let mut subtractor = Subtractor::new(Mode::Ft4, false).unwrap();
    let wave = vec![[1f32, 0.]; 60480];
    let original = vec![0.25; 60480];
    let mut actual = original.clone();
    let cancel = || true;
    let mut budget = CpuBudget::new(&cancel);
    assert_eq!(
        complete(subtractor.subtract(&mut actual, 0, &wave, &mut budget)),
        Err(DecodeError::Cancelled)
    );
    assert_eq!(actual, original);
    let never = || false;
    let mut budget = CpuBudget::new(&never);
    assert_eq!(
        complete(subtractor.subtract(&mut actual, 1, &wave, &mut budget)),
        Err(DecodeError::InvalidSamples)
    );
    assert_eq!(actual, original);
}
