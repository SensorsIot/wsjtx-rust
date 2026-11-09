#![forbid(unsafe_code)]
// Proves: TC-005-001, TC-006-001, TC-024-007, TC-099-001, CL-009-01, CL-009-02, CL-024-03, CL-099-01
use serde_json::Value;
use std::sync::OnceLock;
use wstx_rust::decoder::{Decoder, HashTable, Mode, unpack, unpack_with};
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

// Proves: TC-005-001.
#[test]
fn tc_005_001_ft8code_bits_crc_parity_and_tones_match_exactly() {
    let supported = ["1.", "2.", "3.", "4.", "5.", "0.0", "0.3", "0.4", "0.5"];
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
                let (i3, n3) = match ty.strip_prefix("0.") {
                    Some(n3) => (0, Some(n3.parse().unwrap())),
                    None => (ty[..1].parse().unwrap(), None),
                };
                assert_eq!((frame.packed.i3, frame.packed.n3), (i3, n3), "{message}");
            }
            Err(_) if !expect_ok => refused += 1,
            other => panic!("{message}: expected ok={expect_ok}, got {other:?}"),
        }
    }
    assert!(
        encoded >= 80 && refused >= 30,
        "{encoded} encoded, {refused} refused"
    );
}

// Proves: TC-005-001.
#[test]
fn tc_005_001_families_and_explicit_refusals() {
    let family = |m: &str| encode(m).unwrap().packed.family;
    assert_eq!(family("CQ K1ABC FN42"), Family::Standard);
    assert_eq!(family("CQ G4ABC/P IO91"), Family::Portable);
    assert_eq!(family("CQ PJ4/K1ABC"), Family::Nonstandard);
    assert_eq!(family("TNX BOB 73 GL"), Family::FreeText);
    assert_eq!(family("123456789ABCDEF012"), Family::Telemetry);
    assert_eq!(family("<K1ABC> <W9XYZ>"), Family::Standard);
    // A type 1 shape whose round trip fails falls through to free text, as in WSJT-X.
    for m in ["AB1 W9XYZ", "AB1 W9XYZ -10", "CQ AB1 FN42"] {
        assert_eq!(family(m), Family::FreeText, "{m}");
    }
    let refusal = |m: &str| encode(m).unwrap_err();
    assert_eq!(refusal(""), PackError::Empty);
    assert_eq!(refusal("   "), PackError::Empty);
    assert_eq!(refusal("HELLO WORLD 123"), PackError::TooLong);
    assert_eq!(refusal(&"K1ABC ".repeat(7)), PackError::TooLong);
    assert_eq!(refusal("TNX BOB 73 GL!"), PackError::InvalidText);
    assert_eq!(refusal("HÉLLO"), PackError::InvalidText);
    assert_eq!(refusal("CQ <PJ4/K1ABC>"), PackError::InvalidText);
    // A hashed call next to a slashed call (also inside brackets) is not type 1.
    for m in [
        "<PJ4/K1ABC> <W9XYZ>",
        "<K1ABC> <PJ4/W9XYZ>",
        "<K1ABC/P> <W9XYZ>",
        "<PJ4/K1ABC> <W9XYZ> -10",
    ] {
        assert_eq!(refusal(m), PackError::InvalidText, "{m}");
    }
    assert_eq!(refusal("A"), PackError::NotExact);
    assert_eq!(refusal("CAFE"), PackError::NotExact);
    for m in [
        "K1ABC FN42 37",
        "PJ4/K1ABC 37",
        "K1ABC RR73; W9XYZ <KH1/KH7Z> -08",
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

/// Field Day and RTTY Roundup (#24 S2b): every oracle vector of the two families packs
/// exactly, and every contest shape WSJT-X alters or rejects is refused.
// Proves: TC-024-007, CL-024-03
#[test]
fn tc_024_007_field_day_and_rtty_roundup_pack_exactly() {
    let mut exact = 0;
    for v in vectors()["vectors"].as_array().unwrap() {
        let message = v["message"].as_str().unwrap();
        let ty = v["type"].as_str().unwrap_or("");
        if v["altered"] == false && ["0.3", "0.4", "3."].contains(&ty) {
            exact += 1;
            let frame = encode(message).unwrap_or_else(|e| panic!("{message}: {e:?}"));
            assert_eq!(
                frame.packed.bits.to_vec(),
                bits(v["bits77"].as_str().unwrap()),
                "{message}"
            );
            assert_eq!(
                frame.tones.to_vec(),
                bits(v["tones79"].as_str().unwrap()),
                "{message}"
            );
            assert_eq!(frame.packed.text, v["decoded"].as_str().unwrap());
            let family = if ty == "3." {
                Family::RttyRoundup
            } else {
                Family::FieldDay
            };
            assert_eq!(frame.packed.family, family, "{message}");
        }
    }
    assert!(exact >= 20, "{exact} contest vectors");
    let n3 = |m: &str| {
        let p = encode(m).unwrap().packed;
        (p.i3, p.n3)
    };
    assert_eq!(n3("K1ABC W9XYZ 10A WI"), (0, Some(3)));
    assert_eq!(n3("W9XYZ K1ABC 16D NB"), (0, Some(3)));
    assert_eq!(n3("K1ABC W9XYZ R 17B EMA"), (0, Some(4)));
    assert_eq!(n3("W9XYZ K1ABC 32F DX"), (0, Some(4)));
    assert_eq!(n3("TU; W9XYZ G8ABC R 559 0013").0, 3);
    assert_eq!(
        encode("tu;  k1abc w9xyz 579 ma").unwrap().packed.text,
        "TU; K1ABC W9XYZ 579 MA"
    );
    // WSJT-X would send these call slots as hashes and render them <CALL>.
    for m in [
        "PJ4/K1ABC W9XYZ 6A WI",
        "K1ABC/R W9XYZ 6A WI",
        "PJ4/K1ABC W9XYZ 579 MA",
        "W9XYZ K1ABC/R 579 MA",
    ] {
        assert_eq!(encode(m).unwrap_err(), PackError::NotExact, "{m}");
    }
    // Shapes WSJT-X alters (truncated free text) or rejects are refused, never sent.
    for m in [
        "<PJ4/K1ABC> W9XYZ 6A WI",
        "K1ABC W9XYZ 33A WI",
        "K1ABC W9XYZ 06A WI",
        "K1ABC W9XYZ 6G WI",
        "K1ABC W9XYZ 0A WI",
        "Q1ABC W9XYZ 6A WI",
        "TU; <PJ4/K1ABC> W9XYZ R 579 MA",
        "W9XYZ G8ABC 529 8000",
        "W9XYZ G8ABC 529 0000",
        "W9XYZ G8ABC 519 0001",
        "W9XYZ G8ABC 599 13",
        "W9XYZ G8ABC 599 DX",
        "TU; K1ABC W9XYZ RR73",
        "TU; TU; K1ABC W9XYZ 579 MA",
        "K1ABC W9XYZ 579",
    ] {
        assert!(fixture(m)["altered"] == true, "{m}");
        assert!(encode(m).is_err(), "{m}");
    }
}

/// TC-099-001: the EU VHF messages WSJT-X 3.3.0-beta5 encodes unaltered as type 5
/// (fixtures/transmit/generate.py MESSAGES), and the shapes it rejects or alters.
const EU_VHF: [&str; 8] = [
    "<K1ABC> <HB9BLA> 550001 JN37VL",
    "<HB9BLA> <K1ABC> R 590003 FN42AX",
    "<G4ABC/P> <HB9BLA> 522047 IO91NP",
    "<PJ4/K1ABC> <HB9BLA> 590123 FK52UD",
    "<ABC> <ABCDEFGHIJK> 570010 AA00AA",
    "<HB9BLA> <K1ABC> 590001 RR99XX",
    "<k1abc> <hb9bla> 550001 jn37vl",
    "<K1ABCDEFGH> <HB9BLA> R 550001 JN37VL",
];
const EU_VHF_REJECTED: [&str; 13] = [
    "<K1ABC> <HB9BLA> 550000 JN37VL",
    "<K1ABC> <HB9BLA> 552048 JN37VL",
    "<K1ABC> <HB9BLA> 510001 JN37VL",
    "<K1ABC> <HB9BLA> 600001 JN37VL",
    "<K1ABC> <HB9BLA> 55001 JN37VL",
    "<K1ABC> <HB9BLA> 5500001 JN37VL",
    "<K1ABC> <HB9BLA> 550001 JN37",
    "<K1ABC> <HB9BLA> 550001 SS00AA",
    "K1ABC <HB9BLA> 550001 JN37VL",
    "<AB> <HB9BLA> 550001 JN37VL",
    "<K1ABCDEFGHIJ> <HB9BLA> 550001 JN37VL",
    "<K1ABC> <HB9BLA> X 550001 JN37VL",
    "<K1ABC> <HB9BLA> R 550001 JN37VL 73",
];
fn oracle(message: &str) -> &'static Value {
    vectors()["vectors"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["message"] == message)
        .unwrap_or_else(|| {
            panic!("{message}: no ft8code vector; run fixtures/transmit/generate.py --bin")
        })
}

/// EU VHF (#99): every oracle vector packs bit for bit as ft8code, renders its own tokens
/// with a hash table that knows both calls and <...> without one; every rejected shape is
/// never packed as EU VHF; the 38-character message is refused tooLong.
// Proves: TC-099-001, CL-099-01
#[test]
fn tc_099_001_eu_vhf_packs_exactly_as_ft8code() {
    for message in EU_VHF {
        let v = oracle(message);
        assert_eq!(
            (v["type"].as_str(), v["altered"].as_bool()),
            (Some("5."), Some(false)),
            "{message}"
        );
        let frame = encode(message).unwrap_or_else(|e| panic!("{message}: {e:?}"));
        assert_eq!(
            (frame.packed.family, frame.packed.i3),
            (Family::EuVhf, 5),
            "{message}"
        );
        for (got, key) in [
            (frame.packed.bits.to_vec(), "bits77"),
            (frame.codeword[77..91].to_vec(), "crc14"),
            (frame.codeword[91..].to_vec(), "parity83"),
            (frame.tones.to_vec(), "tones79"),
        ] {
            assert_eq!(got, bits(v[key].as_str().unwrap()), "{message} {key}");
        }
        let normalized = message.to_ascii_uppercase();
        assert_eq!(frame.packed.text, normalized);
        assert_eq!(frame.packed.text, v["decoded"].as_str().unwrap());
        // With a table that knows both calls the tokens come back; with none, <...>.
        let bare = unpack(&frame.packed.bits);
        let mut table = HashTable::new();
        table.learn_sent(&bare, &normalized);
        let known = unpack_with(&frame.packed.bits, Some(&table));
        assert_eq!(known.text.as_deref(), Some(normalized.as_str()));
        let words = normalized.split(' ').collect::<Vec<_>>();
        let hidden = ["<...>", "<...>"]
            .into_iter()
            .chain(words[2..].iter().copied())
            .collect::<Vec<_>>()
            .join(" ");
        assert_eq!(bare.text.as_deref(), Some(hidden.as_str()), "{message}");
    }
    assert_eq!(
        unpack(
            &encode("<HB9BLA> <K1ABC> R 590003 FN42AX")
                .unwrap()
                .packed
                .bits
        )
        .text
        .as_deref(),
        Some("<...> <...> R 590003 FN42AX")
    );
    for message in EU_VHF_REJECTED {
        let v = oracle(message);
        match encode(message) {
            Ok(frame) => {
                assert_ne!(frame.packed.family, Family::EuVhf, "{message}");
                assert_eq!(v["altered"], false, "{message}");
                assert_eq!(
                    frame.packed.bits.to_vec(),
                    bits(v["bits77"].as_str().unwrap()),
                    "{message}"
                );
            }
            Err(_) => assert!(v["type"] != "5." || v["altered"] == true, "{message}"),
        }
    }
    let long = "<K1ABCDEFGHI> <HB9BLA> R 550001 JN37VL";
    assert_eq!(long.len(), 38);
    assert_eq!(encode(long).unwrap_err(), PackError::TooLong);
    assert_eq!(EU_VHF[7].len(), 37);
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

// Proves: TC-005-001.
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

// Proves: TC-005-001.
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

// Proves: TC-005-001.
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

// Proves: TC-005-001.
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

// Proves: TC-006-001.
#[test]
fn tc_006_001_period_selection_and_parity() {
    // 2026-10-31T12:00:00Z is an even period (multiple of 30 s).
    let t0: i64 = 1_793_448_000_000;
    assert_eq!(t0 % 30_000, 0);
    assert_eq!(next_period(Mode::Ft8, t0, Parity::Even), t0);
    assert_eq!(next_period(Mode::Ft8, t0, Parity::Odd), t0 + 15_000);
    assert_eq!(next_period(Mode::Ft8, t0 + 11_249, Parity::Even), t0);
    assert_eq!(
        next_period(Mode::Ft8, t0 + 11_250, Parity::Even),
        t0 + 30_000
    );
    assert_eq!(
        next_period(Mode::Ft8, t0 + 14_999, Parity::Odd),
        t0 + 15_000
    );
    assert_eq!(
        next_period(Mode::Ft8, t0 + 26_250, Parity::Odd),
        t0 + 45_000
    );
    assert_eq!(next_period(Mode::Ft8, t0 - 1, Parity::Even), t0);
}

// Proves: TC-006-001.
#[test]
fn tc_006_001_start_plan_late_start_and_refusals() {
    let p: i64 = 1_793_448_015_000;
    let sync = ClockState::Synchronized;
    let start = |now, rate| plan_start(Mode::Ft8, now, sync, p, rate);
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
        plan_start(Mode::Ft8, p, sync, p + 1, 48_000),
        Err(ScheduleError::MisalignedPeriod)
    );
    for clock in [ClockState::Unsynchronized, ClockState::Unknown] {
        assert_eq!(
            plan_start(Mode::Ft8, p + 100, clock, p, 48_000),
            Err(ScheduleError::ClockNotSynchronized)
        );
    }
}
