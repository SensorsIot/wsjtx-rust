#![forbid(unsafe_code)]
use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
    time::Instant,
};
use wstx_rust::decoder::{Decoder, Mode, quadratures};
fn wav(path: &Path) -> Vec<f32> {
    let bytes = fs::read(path).unwrap();
    assert_eq!(&bytes[..4], b"RIFF");
    assert_eq!(&bytes[8..12], b"WAVE");
    let mut p = 12;
    let mut result = None;
    let mut format = false;
    while p + 8 <= bytes.len() {
        let n = u32::from_le_bytes(bytes[p + 4..p + 8].try_into().unwrap()) as usize;
        let data = &bytes[p + 8..p + 8 + n];
        match &bytes[p..p + 4] {
            b"fmt " => {
                assert_eq!(u16::from_le_bytes(data[0..2].try_into().unwrap()), 1);
                assert_eq!(u16::from_le_bytes(data[2..4].try_into().unwrap()), 1);
                assert_eq!(u32::from_le_bytes(data[4..8].try_into().unwrap()), 12000);
                assert_eq!(u16::from_le_bytes(data[14..16].try_into().unwrap()), 16);
                format = true;
            }
            b"data" => {
                result = Some(
                    data.chunks_exact(2)
                        .map(|b| i16::from_le_bytes(b.try_into().unwrap()) as f32 / 32768.)
                        .collect(),
                );
            }
            _ => {}
        }
        p += 8 + n + (n % 2);
    }
    assert!(format);
    result.unwrap()
}
#[test]
fn independent_waveforms_decode() {
    let root = PathBuf::from(std::env::var("WSTX_DECODER_VECTORS").expect(
        "set WSTX_DECODER_VECTORS to the independently composed frozen-waveform directory",
    ));
    let fixtures: Value = serde_json::from_str(include_str!(
        "../../fixtures/decoder/independent-vectors/manifest.json"
    ))
    .unwrap();
    let decoder = Decoder::new();
    for v in fixtures["vectors"].as_array().unwrap() {
        let mode = if v["mode"] == "ft4" {
            Mode::Ft4
        } else {
            Mode::Ft8
        };
        let id = format!(
            "{}-{}",
            v["mode"].as_str().unwrap(),
            v["id"].as_str().unwrap()
        );
        let samples = wav(&root.join(&id).join("000000_000000.wav"));
        let tones = v["tones"]
            .as_str()
            .unwrap()
            .bytes()
            .map(|x| x - b'0')
            .collect::<Vec<_>>();
        let wave = quadratures(mode, &tones, 1000.).unwrap();
        let max_error = wave
            .iter()
            .enumerate()
            .map(|(i, w)| (samples[6000 + i] as f64 - 0.15 * w[0] as f64 * 32767. / 32768.).abs())
            .fold(0f64, f64::max);
        assert!(max_error <= 1. / 32768., "waveform {id}: {max_error}");
        let t = Instant::now();
        let decoded = decoder.decode(&samples, mode, &|| false).unwrap();
        eprintln!(
            "{id} {:?}: {:?}",
            t.elapsed(),
            decoded
                .iter()
                .map(|d| (&d.payload.text, d.start_frame, d.frequency_hz, d.snr_db))
                .collect::<Vec<_>>()
        );
        assert_eq!(decoded.len(), 1, "{id}");
        let d = &decoded[0];
        assert_eq!(
            serde_json::to_value(&d.payload.fields).unwrap(),
            v["fields"],
            "{id}"
        );
        assert_eq!(
            d.payload.payload77,
            v["payload77"].as_str().unwrap(),
            "{id}"
        );
        assert!(
            d.start_frame.abs_diff(6000)
                <= v["expected_receive"]["time_tolerance_frames"]
                    .as_u64()
                    .unwrap(),
            "{id}"
        );
        assert!(
            (d.frequency_hz - 1000.).abs()
                <= v["expected_receive"]["frequency_tolerance_hz"]
                    .as_f64()
                    .unwrap(),
            "{id}"
        );
    }
}
#[test]
fn quality_corpus() {
    let root = PathBuf::from(
        std::env::var("WSTX_DECODER_CACHE")
            .expect("set WSTX_DECODER_CACHE to the hash-verified immutable quality input cache"),
    );
    let fixtures: Value =
        serde_json::from_str(include_str!("../../fixtures/decoder/quality-cases.json")).unwrap();
    let decoder = Decoder::new();
    let selected = std::env::var("WSTX_DECODER_CASE_FILTER").ok();
    let mut count = 0;
    let mut errors = 0;
    let mut totals = std::collections::BTreeMap::<String, (usize, usize)>::new();
    for case in fixtures["cases"].as_array().unwrap() {
        let id = case["id"].as_str().unwrap();
        if selected.as_ref().is_some_and(|s| !id.contains(s)) {
            continue;
        }
        count += 1;
        let mode = if case["decode_mode"] == "ft4" {
            Mode::Ft4
        } else {
            Mode::Ft8
        };
        let input = wav(&root.join(id).join("000000_000000.wav"));
        let now = Instant::now();
        let result = decoder.decode(&input, mode, &|| false);
        let group = case["group"].as_str().unwrap();
        let key = format!("{:?}/{group}", mode);
        let total = totals.entry(key).or_default();
        total.0 += 1;
        let actual = match result {
            Ok(r) => r,
            Err(e) => {
                eprintln!("{id}: ERROR {e:?}");
                errors += 1;
                continue;
            }
        };
        let expected = case["expected"].as_array().unwrap();
        let mut found = 0;
        for d in &actual {
            if !expected
                .iter()
                .any(|x| x["payload77"] == d.payload.payload77)
            {
                panic!("FALSE PUBLICATION {id}: {d:?}");
            }
        }
        for x in expected {
            if let Some(d) = actual
                .iter()
                .find(|d| x["payload77"] == d.payload.payload77)
            {
                if !x["fields"].is_null() {
                    assert_eq!(
                        serde_json::to_value(&d.payload.fields).unwrap(),
                        x["fields"],
                        "fields {id}"
                    );
                }
                assert_eq!(
                    serde_json::to_value(&d.payload.text).unwrap(),
                    x["text"],
                    "text {id}"
                );
                assert!(
                    d.start_frame.abs_diff(x["start_frame"].as_u64().unwrap())
                        <= x["time_tolerance_frames"]
                            .as_u64()
                            .unwrap_or(if mode == Mode::Ft8 { 240 } else { 144 }),
                    "time {id}: {d:?}"
                );
                assert!(
                    (d.frequency_hz - x["frequency_hz"].as_f64().unwrap()).abs()
                        <= x["frequency_tolerance_hz"]
                            .as_f64()
                            .unwrap_or(if mode == Mode::Ft8 { 1. } else { 3. }),
                    "frequency {id}: {d:?}"
                );
                if let (Some(snr), Some(tolerance)) =
                    (x["snr2500_db"].as_f64(), x["snr_tolerance_db"].as_f64())
                {
                    assert!(
                        (d.snr_db.expect("noise-defined SNR") - snr).abs() <= tolerance,
                        "SNR {id}: {d:?}"
                    );
                }
                found += 1;
            }
        }
        if found == expected.len() {
            total.1 += 1;
        }
        eprintln!("{id} {:?}: {found}/{}", now.elapsed(), expected.len());
    }
    assert!(count > 0);
    eprintln!("QUALITY {count}: {totals:?}");
    assert_eq!(errors, 0);
    if selected.is_none() {
        assert_eq!(count, 2286);
        for (key, (n, success)) in totals {
            if key.contains("/strong") {
                assert_eq!(n, 40);
                assert!(success >= 36, "{key}: {success}");
            } else if key.contains("/weak") {
                assert_eq!(n, 40);
                assert!(success >= 20, "{key}: {success}");
            } else if key.contains("/offset") {
                assert_eq!(success, n, "{key}");
            } else if key.contains("/two-spacing") {
                assert!(success >= 18, "{key}: {success}");
            }
        }
    }
}
