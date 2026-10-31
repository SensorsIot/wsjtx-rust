#![forbid(unsafe_code)]
// Proves: TC-005-001, TC-006-001, CL-009-01, CL-009-02
use serde_json::Value;
use std::sync::OnceLock;
use wstx_rust::decoder::{Decoder, Mode};
use wstx_rust::transmit::{
    ClockState, Family, PackError, Parity, SampleRate, ScheduleError, Start, WaveformError, encode,
    next_period, plan_start, waveform,
};

fn vectors() -> &'static Value {
    static V: OnceLock<Value> = OnceLock::new();
    V.get_or_init(|| {
        serde_json::from_str(include_str!("../../fixtures/transmit/ft8code-vectors.json")).unwrap()
    })
}
fn bits(s: &str) -> Vec<u8> {
    s.bytes().map(|b| b - b'0').collect()
}
fn fixture(message: &str) -> &'static Value {
    vectors()["vectors"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["message"] == message)
        .unwrap()
}
fn wav(name: &str) -> Vec<f64> {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../fixtures/transmit")
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
fn tc_005_001_ft8code_bits_crc_parity_and_tones_match_exactly() {
    let supported = ["1.", "2.", "4.", "0.0", "0.5"];
    let (mut encoded, mut refused) = (0, 0);
    for v in vectors()["vectors"].as_array().unwrap() {
        let message = v["message"].as_str().unwrap();
        let expect_ok = !v["altered"].as_bool().unwrap()
            && supported.contains(&v["type"].as_str().unwrap_or(""));
        match encode(message) {
            Ok(frame) if expect_ok => {
                encoded += 1;
                assert_eq!(
                    frame.packed.bits.to_vec(),
                    bits(v["bits77"].as_str().unwrap()),
                    "{message}"
                );
                assert_eq!(
                    frame.codeword[77..91].to_vec(),
                    bits(v["crc14"].as_str().unwrap()),
                    "{message}"
                );
                assert_eq!(
                    frame.codeword[91..].to_vec(),
                    bits(v["parity83"].as_str().unwrap()),
                    "{message}"
                );
                assert_eq!(
                    frame.tones.to_vec(),
                    bits(v["tones79"].as_str().unwrap()),
                    "{message}"
                );
                assert_eq!(
                    frame.packed.text,
                    v["decoded"].as_str().unwrap(),
                    "{message}"
                );
                let ty = v["type"].as_str().unwrap();
                let (i3, n3) = match ty {
                    "0.0" => (0, Some(0)),
                    "0.5" => (0, Some(5)),
                    _ => (ty[..1].parse().unwrap(), None),
                };
                assert_eq!((frame.packed.i3, frame.packed.n3), (i3, n3), "{message}");
            }
            Err(_) if !expect_ok => refused += 1,
            other => panic!("{message}: expected ok={expect_ok}, got {other:?}"),
        }
    }
    assert!(
        encoded >= 60 && refused >= 13,
        "{encoded} encoded, {refused} refused"
    );
}

#[test]
fn tc_005_001_families_and_explicit_refusals() {
    let family = |m: &str| encode(m).unwrap().packed.family;
    assert_eq!(family("CQ K1ABC FN42"), Family::Standard);
    assert_eq!(family("CQ G4ABC/P IO91"), Family::Portable);
    assert_eq!(family("CQ PJ4/K1ABC"), Family::Nonstandard);
    assert_eq!(family("TNX BOB 73 GL"), Family::FreeText);
    assert_eq!(family("123456789ABCDEF012"), Family::Telemetry);
    let refusal = |m: &str| encode(m).unwrap_err();
    assert_eq!(refusal(""), PackError::Empty);
    assert_eq!(refusal("   "), PackError::Empty);
    assert_eq!(refusal("HELLO WORLD 123"), PackError::TooLong);
    assert_eq!(refusal(&"K1ABC ".repeat(7)), PackError::TooLong);
    assert_eq!(refusal("TNX BOB 73 GL!"), PackError::InvalidText);
    assert_eq!(refusal("HÉLLO"), PackError::InvalidText);
    assert_eq!(refusal("CQ <PJ4/K1ABC>"), PackError::InvalidText);
    assert_eq!(refusal("A"), PackError::NotExact);
    assert_eq!(refusal("CAFE"), PackError::NotExact);
    for m in [
        "K1ABC FN42 37",
        "PJ4/K1ABC 37",
        "K1A K2B 6A WI",
        "K1ABC W9XYZ R 17B EMA",
        "K1ABC RR73; W9XYZ <KH1/KH7Z> -08",
        "TU; K1ABC W9XYZ 579 WI",
    ] {
        assert_eq!(refusal(m), PackError::UnsupportedFamily, "{m}");
    }
    // Normalization is the only accepted difference.
    assert_eq!(
        encode("cq  k1abc   fn42 ").unwrap().packed.text,
        "CQ K1ABC FN42"
    );
    assert_eq!(
        encode("cq  k1abc   fn42").unwrap().packed.bits,
        encode("CQ K1ABC FN42").unwrap().packed.bits
    );
}

fn peak_normalized(x: &[f32]) -> Vec<f64> {
    let peak = x.iter().fold(0f64, |m, &v| m.max(v.abs() as f64));
    x.iter().map(|&v| v as f64 / peak).collect()
}
fn deviation(ours: &[f64], reference: &[f64]) -> f64 {
    let peak = reference.iter().fold(0f64, |m, v| m.max(v.abs()));
    ours.iter()
        .zip(reference)
        .map(|(a, b)| (a - b / peak).abs())
        .fold(0., f64::max)
}

#[test]
fn tc_005_001_waveform_matches_zero_noise_ft8sim_within_tolerance() {
    const TOLERANCE: f64 = 0.003;
    for w in vectors()["ft8sim_waves"].as_array().unwrap() {
        let message = w["message"].as_str().unwrap();
        let f0 = w["f0_hz"].as_f64().unwrap();
        let reference = wav(w["file"].as_str().unwrap());
        assert_eq!(reference.len(), 180000);
        assert!(
            reference[..6000]
                .iter()
                .chain(&reference[6000 + 151680..])
                .all(|&x| x == 0.)
        );
        let signal = &reference[6000..6000 + 151680];
        let tones = encode(message).unwrap().tones;
        let ours = waveform(&tones, f0, SampleRate::Hz12000).unwrap();
        assert_eq!(ours.len(), 151680);
        let d = deviation(&peak_normalized(&ours), signal);
        eprintln!("{message} at {f0} Hz: max deviation {d:.3e}");
        assert!(d <= TOLERANCE, "{message}: {d}");
        // Negative controls: the tolerance rejects a one-sample shift and a 0.01 Hz error.
        let shifted = &reference[6001..6001 + 151680];
        assert!(deviation(&peak_normalized(&ours), shifted) > TOLERANCE);
        let detuned = waveform(&tones, f0 + 0.01, SampleRate::Hz12000).unwrap();
        assert!(deviation(&peak_normalized(&detuned), signal) > TOLERANCE);
    }
}

#[test]
fn tc_005_001_48k_waveform_and_ramps() {
    let tones = encode("CQ HB9BLA JN47").unwrap().tones;
    for f0 in [200., 1500., 2950.] {
        let low = waveform(&tones, f0, SampleRate::Hz12000).unwrap();
        let high = waveform(&tones, f0, SampleRate::Hz48000).unwrap();
        assert_eq!(high.len(), 606720);
        let d = low
            .iter()
            .zip(high.iter().step_by(4))
            .map(|(a, b)| (a - b).abs())
            .fold(0f32, f32::max);
        assert!(d <= 0.006, "{f0}: {d}");
        for w in [&low, &high] {
            let ramp = w.len() / 79 / 8;
            assert_eq!(w[0], 0.);
            assert!(w.iter().all(|x| x.abs() <= 1.0));
            // Inside the ramps the envelope is below one; after them it reaches unit peak.
            assert!(w[..ramp].iter().all(|x| x.abs() < 1.0));
            let body = w[ramp..w.len() - ramp]
                .iter()
                .fold(0f32, |m, x| m.max(x.abs()));
            assert!(body > 0.999);
            let tail = w[w.len() - ramp / 8..]
                .iter()
                .fold(0f32, |m, x| m.max(x.abs()));
            assert!(tail < 0.05, "{tail}");
        }
    }
}

#[test]
fn tc_005_001_waveform_refusals() {
    let tones = encode("CQ K1ABC FN42").unwrap().tones;
    for f0 in [199.99, 2950.01, f64::NAN, f64::INFINITY, -1500.] {
        assert_eq!(
            waveform(&tones, f0, SampleRate::Hz12000),
            Err(WaveformError::FrequencyOutOfRange),
            "{f0}"
        );
    }
    let mut bad = tones;
    bad[40] = 8;
    assert_eq!(
        waveform(&bad, 1500., SampleRate::Hz48000),
        Err(WaveformError::InvalidTone)
    );
}

#[test]
fn tc_005_001_receive_decoder_recovers_generated_waveforms() {
    let decoder = Decoder::new();
    for (message, f0, rate) in [
        ("CQ HB9BLA JN47", 1000., SampleRate::Hz12000),
        ("<W9XYZ> PJ4/K1ABC RRR", 2100., SampleRate::Hz48000),
    ] {
        let frame = encode(message).unwrap();
        let wave = waveform(&frame.tones, f0, rate).unwrap();
        let step = if rate == SampleRate::Hz48000 { 4 } else { 1 };
        let mut window = vec![0f32; 180000];
        for (i, x) in wave.iter().step_by(step).enumerate() {
            window[6000 + i] = 0.5 * x;
        }
        let decoded = decoder.decode(&window, Mode::Ft8, &|| false).unwrap();
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
        // The receive search reports start to its own frame resolution.
        assert!(
            hit.start_frame.abs_diff(6000) <= 2,
            "{message}: {}",
            hit.start_frame
        );
    }
    assert_eq!(fixture("CQ HB9BLA JN47")["altered"], false);
}

#[test]
fn tc_006_001_period_selection_and_parity() {
    // 2026-10-31T12:00:00Z is an even period (multiple of 30 s).
    let t0: i64 = 1_793_448_000_000;
    assert_eq!(t0 % 30_000, 0);
    assert_eq!(next_period(t0, Parity::Even), t0);
    assert_eq!(next_period(t0, Parity::Odd), t0 + 15_000);
    assert_eq!(next_period(t0 + 11_249, Parity::Even), t0);
    assert_eq!(next_period(t0 + 11_250, Parity::Even), t0 + 30_000);
    assert_eq!(next_period(t0 + 14_999, Parity::Odd), t0 + 15_000);
    assert_eq!(next_period(t0 + 26_250, Parity::Odd), t0 + 45_000);
    assert_eq!(next_period(t0 - 1, Parity::Even), t0);
}

#[test]
fn tc_006_001_start_plan_late_start_and_refusals() {
    let p: i64 = 1_793_448_015_000;
    let sync = ClockState::Synchronized;
    let start = |now, rate| plan_start(now, sync, p, rate);
    assert_eq!(
        start(p - 3_000, 48_000),
        Ok(Start {
            audio_start_ms: p + 500,
            skipped_samples: 0
        })
    );
    assert_eq!(
        start(p + 499, 12_000),
        Ok(Start {
            audio_start_ms: p + 500,
            skipped_samples: 0
        })
    );
    assert_eq!(
        start(p + 500, 48_000),
        Ok(Start {
            audio_start_ms: p + 500,
            skipped_samples: 0
        })
    );
    assert_eq!(
        start(p + 2_750, 48_000),
        Ok(Start {
            audio_start_ms: p + 2_750,
            skipped_samples: 108_000
        })
    );
    assert_eq!(
        start(p + 11_249, 12_000),
        Ok(Start {
            audio_start_ms: p + 11_249,
            skipped_samples: 128_988
        })
    );
    assert_eq!(start(p + 11_250, 12_000), Err(ScheduleError::StalePeriod));
    assert_eq!(start(p + 15_001, 48_000), Err(ScheduleError::StalePeriod));
    assert_eq!(start(p + 60_000, 48_000), Err(ScheduleError::StalePeriod));
    assert_eq!(
        plan_start(p, sync, p + 1, 48_000),
        Err(ScheduleError::MisalignedPeriod)
    );
    for clock in [ClockState::Unsynchronized, ClockState::Unknown] {
        assert_eq!(
            plan_start(p + 100, clock, p, 48_000),
            Err(ScheduleError::ClockNotSynchronized)
        );
    }
}
