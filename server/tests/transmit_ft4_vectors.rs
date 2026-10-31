#![forbid(unsafe_code)]
// Proves: TC-005-002, TC-006-002, CL-011-01
use rustfft::{FftPlanner, num_complex::Complex};
use serde_json::Value;
use std::sync::OnceLock;
use wstx_rust::decoder::{Decoder, Mode};
use wstx_rust::transmit::{
    ClockState, PackError, Parity, SampleRate, ScheduleError, Start, WaveformError, encode_ft4,
    next_period, parity, plan_start, waveform_ft4,
};

/// Samples of one 12 kHz symbol, the 103-tone frame and the native (103 + 2)-symbol waveform.
const NSPS: usize = 576;
const LEN_12K: usize = 105 * NSPS;
/// ft4sim places the ramp-up symbol at nint(0.5 s * 12 kHz) - NSPS.
const SIM_OFFSET: usize = 6000 - NSPS;

fn vectors() -> &'static Value {
    static V: OnceLock<Value> = OnceLock::new();
    V.get_or_init(|| {
        serde_json::from_str(include_str!(
            "../../fixtures/transmit/ft4/ft4sim-vectors.json"
        ))
        .unwrap()
    })
}
fn digits(s: &str) -> Vec<u8> {
    s.bytes().map(|b| b - b'0').collect()
}
fn wav(name: &str) -> Vec<f64> {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../fixtures/transmit/ft4")
        .join(name);
    let bytes = std::fs::read(path).unwrap();
    assert_eq!(&bytes[..4], b"RIFF");
    bytes[44..]
        .as_chunks::<2>()
        .0
        .iter()
        .map(|&c| i16::from_le_bytes(c) as f64)
        .collect()
}

#[test]
fn tc_005_002_ft4sim_bits_codeword_and_tones_match_exactly() {
    let (mut encoded, mut refused) = (0, 0);
    for v in vectors()["vectors"].as_array().unwrap() {
        let message = v["message"].as_str().unwrap();
        let expect_ok = v["encoded"] == true && v["altered"] == false && {
            let (i3, n3) = (v["i3"].as_u64().unwrap(), v["n3"].as_u64().unwrap());
            matches!(i3, 1 | 2 | 4) || (i3 == 0 && matches!(n3, 0 | 5))
        };
        match encode_ft4(message) {
            Ok(frame) if expect_ok => {
                encoded += 1;
                let field = |k: &str| digits(v[k].as_str().unwrap());
                assert_eq!(frame.packed.bits.to_vec(), field("bits77"), "{message}");
                assert_eq!(frame.codeword.to_vec(), field("codeword174"), "{message}");
                assert_eq!(frame.tones.to_vec(), field("tones103"), "{message}");
                assert_eq!(
                    frame.packed.text,
                    v["decoded"].as_str().unwrap(),
                    "{message}"
                );
                assert_eq!(u64::from(frame.packed.i3), v["i3"].as_u64().unwrap());
            }
            Err(_) if !expect_ok => refused += 1,
            other => panic!("{message}: expected ok={expect_ok}, got {other:?}"),
        }
    }
    assert!(
        encoded >= 60 && refused >= 13,
        "{encoded} encoded, {refused} refused"
    );
    // The frame is the genft4 layout: four Costas 4x4 arrays around three data blocks.
    let tones = encode_ft4("CQ K1ABC FN42").unwrap().tones;
    for (at, costas) in [
        (0, [0, 1, 3, 2]),
        (33, [1, 0, 2, 3]),
        (66, [2, 3, 1, 0]),
        (99, [3, 2, 0, 1]),
    ] {
        assert_eq!(tones[at..at + 4], costas);
    }
    assert_eq!(encode_ft4(""), Err(PackError::Empty));
    assert_eq!(encode_ft4("HELLO WORLD 123"), Err(PackError::TooLong));
}

/// In-phase component of the reference: ft4sim writes the real part (cosine) of the
/// complex genft4 waveform, the native transmitter writes the sine. The analytic signal
/// (FFT, negative frequencies removed) turns cos(phi) into sin(phi) without using any
/// part of the implementation; its magnitude is the envelope used as full scale.
fn quadrature(reference: &[f64]) -> Vec<f64> {
    let n = reference.len();
    let mut x = reference
        .iter()
        .map(|&r| Complex::new(r, 0.))
        .collect::<Vec<_>>();
    let mut planner = FftPlanner::new();
    planner.plan_fft_forward(n).process(&mut x);
    for (k, c) in x.iter_mut().enumerate() {
        *c *= match k {
            0 => 1.,
            k if 2 * k == n => 1.,
            k if 2 * k < n => 2.,
            _ => 0.,
        };
    }
    planner.plan_fft_inverse(n).process(&mut x);
    let peak = x.iter().fold(0f64, |m, c| m.max(c.norm()));
    x.iter().map(|c| c.im / peak).collect()
}
fn deviation(ours: &[f32], reference: &[f64]) -> f64 {
    ours.iter()
        .zip(reference)
        .map(|(&a, b)| (a as f64 - b).abs())
        .fold(0., f64::max)
}

#[test]
fn tc_005_002_waveform_matches_zero_noise_ft4sim_within_tolerance() {
    const TOLERANCE: f64 = 1e-3;
    for w in vectors()["ft4sim_waves"].as_array().unwrap() {
        let message = w["message"].as_str().unwrap();
        let f0 = w["f0_hz"].as_f64().unwrap();
        let reference = wav(w["file"].as_str().unwrap());
        assert_eq!(reference.len(), 72576);
        assert!(
            reference[..SIM_OFFSET]
                .iter()
                .chain(&reference[SIM_OFFSET + LEN_12K..])
                .all(|&x| x == 0.)
        );
        let sine = quadrature(&reference);
        let signal = &sine[SIM_OFFSET..SIM_OFFSET + LEN_12K];
        let tones = encode_ft4(message).unwrap().tones;
        let ours = waveform_ft4(&tones, f0, SampleRate::Hz12000).unwrap();
        assert_eq!(ours.len(), LEN_12K);
        let d = deviation(&ours, signal);
        eprintln!("{message} at {f0} Hz: max deviation {d:.3e}");
        assert!(d <= TOLERANCE, "{message}: {d}");
        // Negative controls: a one-sample shift, a 0.01 Hz error and a ramp-up one sample
        // late all exceed the tolerance.
        let shifted = &sine[SIM_OFFSET + 1..SIM_OFFSET + 1 + LEN_12K];
        assert!(deviation(&ours, shifted) > TOLERANCE);
        let detuned = waveform_ft4(&tones, f0 + 0.01, SampleRate::Hz12000).unwrap();
        assert!(deviation(&detuned, signal) > TOLERANCE);
        let late_ramp = ours
            .iter()
            .enumerate()
            .map(|(k, &x)| {
                let native = (1. - (std::f64::consts::PI * k as f64 / NSPS as f64).cos()) / 2.;
                let late = (1. - (std::f64::consts::PI * (k + 1) as f64 / NSPS as f64).cos()) / 2.;
                if k > 0 && k < NSPS {
                    (x as f64 * late / native) as f32
                } else {
                    x
                }
            })
            .collect::<Vec<_>>();
        let d = deviation(&late_ramp, signal);
        assert!(d > TOLERANCE, "late ramp {d}");
    }
}

#[test]
fn tc_005_002_48k_waveform_and_ramps() {
    let tones = encode_ft4("CQ HB9BLA JN47").unwrap().tones;
    for f0 in [200., 1500., 2916.] {
        let low = waveform_ft4(&tones, f0, SampleRate::Hz12000).unwrap();
        let high = waveform_ft4(&tones, f0, SampleRate::Hz48000).unwrap();
        assert_eq!(high.len(), 241920);
        let d = low
            .iter()
            .zip(high.iter().step_by(4))
            .map(|(a, b)| (a - b).abs())
            .fold(0f32, f32::max);
        eprintln!("48k at {f0}: {d:.3e}");
        assert!(d <= 0.025, "{f0}: {d}");
        for w in [&low, &high] {
            let n = w.len() / 105;
            assert_eq!(w[0], 0.);
            assert!(w.iter().all(|x| x.abs() <= 1.0));
            // The ramps span the whole first and last symbol.
            assert!(w[..n].iter().all(|x| x.abs() < 1.0));
            assert!(w[w.len() - n..].iter().all(|x| x.abs() < 1.0));
            let body = w[n..w.len() - n].iter().fold(0f32, |m, x| m.max(x.abs()));
            assert!(body > 0.999);
            let tail = w[w.len() - n / 8..]
                .iter()
                .fold(0f32, |m, x| m.max(x.abs()));
            assert!(tail < 0.05, "{tail}");
        }
    }
}

#[test]
fn tc_005_002_waveform_refusals() {
    let tones = encode_ft4("CQ K1ABC FN42").unwrap().tones;
    let max = 3000. - 4. * 12000. / 576.;
    assert!(waveform_ft4(&tones, max, SampleRate::Hz12000).is_ok());
    for f0 in [199.99, max + 0.01, 2950., f64::NAN, f64::INFINITY, -1500.] {
        assert_eq!(
            waveform_ft4(&tones, f0, SampleRate::Hz12000),
            Err(WaveformError::FrequencyOutOfRange),
            "{f0}"
        );
    }
    let mut bad = tones;
    bad[50] = 4;
    assert_eq!(
        waveform_ft4(&bad, 1500., SampleRate::Hz48000),
        Err(WaveformError::InvalidTone)
    );
}

#[test]
fn tc_005_002_receive_decoder_recovers_generated_waveforms() {
    let decoder = Decoder::new();
    for (message, f0, rate) in [
        ("CQ HB9BLA JN47", 1000., SampleRate::Hz12000),
        ("<W9XYZ> PJ4/K1ABC RRR", 2100., SampleRate::Hz48000),
    ] {
        let frame = encode_ft4(message).unwrap();
        let wave = waveform_ft4(&frame.tones, f0, rate).unwrap();
        let step = if rate == SampleRate::Hz48000 { 4 } else { 1 };
        let mut window = vec![0f32; 72576];
        for (i, x) in wave.iter().step_by(step).enumerate() {
            window[SIM_OFFSET + i] = 0.5 * x;
        }
        let decoded = decoder.decode(&window, Mode::Ft4, &|| false).unwrap();
        let hit = decoded
            .iter()
            .find(|d| {
                d.payload
                    .payload77
                    .bytes()
                    .map(|b| b - b'0')
                    .eq(frame.packed.bits)
            })
            .unwrap_or_else(|| panic!("{message}: {decoded:?}"));
        assert!((hit.frequency_hz - f0).abs() < 1., "{message}");
        assert!(
            hit.start_frame.abs_diff(SIM_OFFSET as u64) <= 2,
            "{message}: {}",
            hit.start_frame
        );
    }
}

#[test]
fn tc_006_002_ft4_period_selection_and_parity() {
    // 2026-10-31T12:00:00Z is an even FT4 period (multiple of 15 s).
    let t0: i64 = 1_793_448_000_000;
    let ft4 = Mode::Ft4;
    assert_eq!(parity(ft4, t0), Parity::Even);
    assert_eq!(parity(ft4, t0 + 7_500), Parity::Odd);
    assert_eq!(parity(ft4, t0 + 15_000), Parity::Even);
    assert_eq!(next_period(ft4, t0, Parity::Even), t0);
    assert_eq!(next_period(ft4, t0, Parity::Odd), t0 + 7_500);
    assert_eq!(next_period(ft4, t0 + 5_624, Parity::Even), t0);
    assert_eq!(next_period(ft4, t0 + 5_625, Parity::Even), t0 + 15_000);
    assert_eq!(next_period(ft4, t0 + 7_499, Parity::Odd), t0 + 7_500);
    assert_eq!(next_period(ft4, t0 + 13_125, Parity::Odd), t0 + 22_500);
    assert_eq!(next_period(ft4, t0 - 1, Parity::Even), t0);
    // The same instant under FT8 keeps the 15 s rules.
    assert_eq!(parity(Mode::Ft8, t0 + 15_000), Parity::Odd);
    assert_eq!(next_period(Mode::Ft8, t0 + 7_500, Parity::Odd), t0 + 15_000);
}

#[test]
fn tc_006_002_ft4_start_plan_late_start_and_refusals() {
    let p: i64 = 1_793_448_007_500;
    let sync = ClockState::Synchronized;
    let start = |now, rate| plan_start(Mode::Ft4, now, sync, p, rate);
    let at = |audio_start_ms, skipped_samples| {
        Ok(Start {
            audio_start_ms,
            skipped_samples,
        })
    };
    assert_eq!(start(p - 3_000, 48_000), at(p + 300, 0));
    assert_eq!(start(p + 299, 12_000), at(p + 300, 0));
    assert_eq!(start(p + 300, 48_000), at(p + 300, 0));
    assert_eq!(start(p + 301, 48_000), at(p + 301, 48));
    assert_eq!(start(p + 2_750, 48_000), at(p + 2_750, 117_600));
    assert_eq!(start(p + 5_624, 12_000), at(p + 5_624, 63_888));
    assert_eq!(start(p + 5_625, 12_000), Err(ScheduleError::StalePeriod));
    assert_eq!(start(p + 7_501, 48_000), Err(ScheduleError::StalePeriod));
    assert_eq!(
        plan_start(Mode::Ft4, p, sync, p + 1, 48_000),
        Err(ScheduleError::MisalignedPeriod)
    );
    // A 7.5 s boundary is an FT4 period but not an FT8 one; FT8 keeps its 500 ms delay.
    assert_eq!(
        plan_start(Mode::Ft8, p, sync, p, 48_000),
        Err(ScheduleError::MisalignedPeriod)
    );
    assert_eq!(
        plan_start(Mode::Ft8, p, sync, p - 7_500, 48_000),
        at(p, 336_000)
    );
    for clock in [ClockState::Unsynchronized, ClockState::Unknown] {
        assert_eq!(
            plan_start(Mode::Ft4, p + 100, clock, p, 48_000),
            Err(ScheduleError::ClockNotSynchronized)
        );
    }
}
