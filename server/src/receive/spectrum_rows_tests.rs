use super::*;

// Independently computed DFT and analytic tones, at cost 2 on Windows.
// Proves: TC-010-001
#[test]
fn both_fft_paths_agree_with_direct_dft_and_analytic_dbfs() {
    let vectors: Vec<Vec<f32>> = vec![
        vec![0.0; 2048],
        vec![0.5; 2048],
        (0..2048)
            .map(|n| (0.5 * (std::f64::consts::TAU * 128.0 * n as f64 / 2048.0).sin()) as f32)
            .collect(),
        (0..2048)
            .map(|n| {
                (0.25 * (std::f64::consts::TAU * 256.0 * n as f64 / 2048.0).sin()
                    + 0.5 * (std::f64::consts::TAU * 384.0 * n as f64 / 2048.0).sin())
                    as f32
            })
            .collect(),
        (0..1700)
            .map(|n| ((std::f64::consts::TAU * 750.3 * n as f64 / 12000.0).sin() * 0.5) as f32)
            .collect(),
    ];
    for scalar in [false, true] {
        let mut fft = spectrum::Spectrum::new(scalar);
        for samples in &vectors {
            let actual = fft.amplitudes(samples).unwrap();
            for (group, &observed) in actual.iter().enumerate() {
                let expected = (group * 4..group * 4 + 4)
                    .map(|k| dft(samples, k))
                    .fold(0.0, f64::max);
                assert!(
                    (f64::from(observed) - expected).abs() < 0.000002,
                    "scalar={scalar} group={group}"
                );
                assert!(
                    (f64::from(spectrum::quantize(observed))
                        - (20.0 * expected.max(1e-6).log10()).clamp(-120.0, 0.0)
                        - 120.0)
                        .abs()
                        <= 0.55
                );
            }
        }
        let amplitude = fft.amplitudes(&vectors[2]).unwrap()[32];
        assert!((20.0 * amplitude.log10() + 6.0206).abs() < 0.05);
        assert!(fft.amplitudes(&vec![0.; 2049]).is_err());
    }
}

// Actual worker row boundary/right padding against original DFT.
// Proves: TC-010-001
#[test]
fn replay_window_start_and_partial_last_row_follow_source_clock() {
    let f = Fixture::new();
    let r = f.recording();
    let samples: Vec<i16> = (0..12120)
        .map(|n| {
            if n >= 11800 {
                (16384.0 * (std::f64::consts::TAU * 1234.5 * n as f64 / 12000.0).sin()).round()
                    as i16
            } else {
                0
            }
        })
        .collect();
    let id = import(&r, &wav(&samples)).unwrap();
    let generation = r.state.lock().unwrap().generation;
    let began = Instant::now();
    r.replay(&r.profile, &r.boot, generation, &id).unwrap();
    while r.snapshot()["job"]["state"] == "running" {
        assert!(began.elapsed() < Duration::from_secs(3));
        std::thread::sleep(Duration::from_millis(10));
    }
    assert_eq!(r.snapshot()["job"]["state"], "completed");
    // The worker counts as ended once its job has returned, after the terminal state.
    f.3.wait_idle(Duration::from_secs(3).saturating_sub(began.elapsed()));
    assert_eq!(f.3.active(), 0);
    assert_eq!(f.3.peak(), 1);
    assert_eq!(f.4.peak(), 2);
    assert!(began.elapsed() >= Duration::from_secs_f64(1.01));
    let frame = r.state.lock().unwrap().frame.clone().unwrap();
    assert_eq!(frame["data"]["sequence"], 1);
    assert_eq!(frame["data"]["first_frame"], 12000);
    assert_eq!(frame["data"]["end_frame"], 12120);
    // The only hop-aligned window starting in [12000,12120) begins at 12032.
    let partial: Vec<f32> = samples[12032..]
        .iter()
        .map(|&x| f32::from(x) / 32768.0)
        .collect();
    for group in 0..128 {
        let amplitude = (group * 4..group * 4 + 4)
            .map(|k| dft(&partial, k))
            .fold(0.0, f64::max);
        let expected =
            ((20.0 * amplitude.max(1e-6).log10()).clamp(-120.0, 0.0) + 120.5).floor() as u64;
        assert_eq!(frame["data"]["levels"][group], expected, "group {group}");
    }
}

// Independent f64 DFT, native bins and power/EOS rows.
// Proves: TC-010-004
#[test]
fn detailed_native_bins_and_power_rows_follow_independent_dft() {
    use base64::{Engine, engine::general_purpose::STANDARD};
    fn direct(x: &[f32], k: usize) -> f64 {
        let (mut re, mut im) = (0.0, 0.0);
        for (n, &sample) in x.iter().enumerate() {
            let w = (1.0 - (std::f64::consts::TAU * n as f64 / 4096.0).cos()) / 2.0;
            let a = std::f64::consts::TAU * k as f64 * n as f64 / 4096.0;
            re += f64::from(sample) * w * a.cos();
            im -= f64::from(sample) * w * a.sin();
        }
        re.hypot(im) * if k == 0 { 1.0 } else { 2.0 } / 2048.0
    }
    for scalar in [false, true] {
        let mut fft = spectrum::Spectrum::detailed(scalar);
        for frequencies in [
            &[750.0][..],
            &[752.9296875][..],
            &[750.0, 752.9296875][..],
            &[750.0, 756.25][..],
        ] {
            let x: Vec<f32> = (0..4096)
                .map(|n| {
                    let v: f64 = frequencies
                        .iter()
                        .map(|f| 0.25 * (std::f64::consts::TAU * f * n as f64 / 12000.0).sin())
                        .sum();
                    (v * 32768.0).round() as f32 / 32768.0
                })
                .collect();
            let observed = fft.native_amplitudes(&x).unwrap();
            assert_eq!(observed.len(), 1024);
            for (k, &observed_amplitude) in observed.iter().enumerate() {
                let expected = direct(&x, k);
                assert!(
                    (f64::from(observed_amplitude) - expected).abs() < 2e-6,
                    "scalar={scalar},bin={k}"
                );
                if expected > 1e-4 {
                    assert!(
                        (20.0 * (f64::from(observed_amplitude) / expected).log10()).abs() < 0.05
                    );
                }
            }
        }
        assert!(fft.native_amplitudes(&vec![0.0; 4097]).is_err());
        assert!(fft.native_amplitudes(&[f32::NAN]).is_err());
    }
    for length in [1, 2399, 2400, 2401, 2879, 2880, 2881, 6000] {
        let f = Fixture::new();
        let r = f.recording();
        let pcm: Vec<i16> = (0..length)
            .map(|n| {
                if n < 1920 {
                    0
                } else {
                    (12000.0 * (std::f64::consts::TAU * 756.25 * n as f64 / 12000.0).sin()).round()
                        as i16
                }
            })
            .collect();
        let id = import(&r, &wav(&pcm)).unwrap();
        let generation = r.state.lock().unwrap().generation;
        r.replay(&r.profile, &r.boot, generation, &id).unwrap();
        let began = Instant::now();
        while r.snapshot()["job"]["state"] == "running" {
            assert!(began.elapsed() < Duration::from_secs(3));
            std::thread::sleep(Duration::from_millis(5));
        }
        assert_eq!(r.snapshot()["job"]["state"], "completed");
        let frame = r.state.lock().unwrap().detail_frame.clone().unwrap();
        assert_eq!(frame["type"], "spectrum.detail.frame");
        assert!(frame.to_string().len() <= 2048);
        let first = ((length - 1) / 2400) * 2400;
        assert_eq!(frame["data"]["first_frame"], first);
        assert_eq!(frame["data"]["end_frame"], length);
        let encoded = frame["data"]["levels_b64"].as_str().unwrap();
        assert_eq!(encoded.len(), 1368);
        let levels = STANDARD.decode(encoded).unwrap();
        assert_eq!(levels.len(), 1024);
        let starts: Vec<usize> = (first..length).step_by(480).collect();
        for k in [0, 1, 255, 256, 257, 258, 1023] {
            let p = starts
                .iter()
                .map(|&start| {
                    let end = (start + 4096).min(length);
                    let x: Vec<f32> = pcm[start..end]
                        .iter()
                        .map(|&v| f32::from(v) / 32768.0)
                        .collect();
                    direct(&x, k).powi(2)
                })
                .sum::<f64>()
                / starts.len() as f64;
            let expected = (10.0 * p.max(1e-12).log10()).clamp(-120.0, 0.0) + 120.0;
            assert!(
                (f64::from(levels[k]) - expected.round()).abs() <= 1.0,
                "length={length},bin={k}"
            );
        }
        if length == 2401 {
            assert!(levels.iter().all(|&q| q == 0));
        }
    }
}
