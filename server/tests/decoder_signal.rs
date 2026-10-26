#![forbid(unsafe_code)]
#![cfg(not(debug_assertions))]
use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
    time::Instant,
};
use wstx_rust::decoder::{Decoder, Mode, quadratures};
fn prepared(kind: &str) -> PathBuf {
    static QUALITY: std::sync::OnceLock<PathBuf> = std::sync::OnceLock::new();
    static FROZEN: std::sync::OnceLock<PathBuf> = std::sync::OnceLock::new();
    let slot = if kind == "quality" { &QUALITY } else { &FROZEN };
    slot.get_or_init(|| {
        let key = if kind == "quality" {
            "WSTX_DECODER_CACHE"
        } else {
            "WSTX_DECODER_VECTORS"
        };
        let explicit = std::env::var_os(key);
        let root = explicit
            .as_ref()
            .map(PathBuf::from)
            .unwrap_or_else(|| std::env::temp_dir().join("wstx-independent-decoder-inputs"));
        let tool = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../fixtures/decoder/independent-vector-tool/cache.py");
        let mut command =
            std::process::Command::new(if cfg!(windows) { "python" } else { "python3" });
        command
            .arg(tool)
            .args(["--kind", kind])
            .arg(if explicit.is_some() {
                "--output"
            } else {
                "--cache-root"
            })
            .arg(&root);
        if explicit.is_some() {
            command.arg("--verify-only");
        }
        let output = command
            .output()
            .expect("Python fixture preparation must execute");
        assert!(
            output.status.success(),
            "independent inputs failed verification: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        eprintln!("{}", String::from_utf8_lossy(&output.stdout));
        let metadata: Value = serde_json::from_slice(&output.stdout).unwrap();
        PathBuf::from(metadata["output"].as_str().unwrap())
    })
    .clone()
}
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
    let root = prepared("frozen");
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
    let root = prepared("quality");
    let fixtures: Value =
        serde_json::from_str(include_str!("../../fixtures/decoder/quality-cases.json")).unwrap();
    let decoder = Decoder::new();
    let selected = std::env::var("WSTX_DECODER_CASE_FILTER").ok();
    let mut count = 0;
    let mut errors = 0;
    let mut totals = std::collections::BTreeMap::<String, (usize, usize, [usize; 2])>::new();
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
        assert!(
            actual.len() <= expected.len(),
            "duplicate publication {id}: {actual:?}"
        );
        for (index, x) in expected.iter().enumerate() {
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
                total.2[index] += 1;
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
        assert_eq!(totals.len(), 18);
    }
    for (key, (n, success, individual)) in totals {
        if key.ends_with("/strong") && n == 40 {
            assert!(success >= 36, "{key}: {success}/40");
        } else if key.ends_with("/weak") && n == 40 {
            assert!(success >= 20, "{key}: {success}/40");
        } else if key.ends_with("/offset") {
            assert_eq!(success, n, "{key}");
        } else if key.ends_with("/two-spacing") && n == 20 {
            assert!(success >= 18, "{key}: {success}/20");
        } else if key.ends_with("/one-spacing-6db") && n == 20 {
            assert!(individual[0] >= 18, "{key} stronger: {:?}", individual);
            assert!(individual[1] >= 10, "{key} weaker: {:?}", individual);
        } else if key.ends_with("/noise-only")
            || key.ends_with("/silence")
            || key.ends_with("/wrong-mode")
            || key.ends_with("/crc-negative")
        {
            assert_eq!(success, n, "{key}");
        }
    }
}

#[test]
fn cooperative_quanta_and_partial_cancellation() {
    use std::{
        future::Future,
        sync::atomic::{AtomicBool, Ordering},
        task::{Context, Poll, Waker},
    };
    let root = prepared("quality");
    let samples = wav(&root.join("ft8-strong-00/000000_000000.wav"));
    let decoder = Decoder::new();
    let cancelled = AtomicBool::new(false);
    let cancel = || cancelled.load(Ordering::Relaxed);
    let mut published = vec![];
    let mut publish = |d: &wstx_rust::decoder::Decode| {
        published.push(d.clone());
        cancelled.store(true, Ordering::Relaxed);
        Ok(())
    };
    let mut future =
        Box::pin(decoder.decode_into_async(&samples, Mode::Ft8, &cancel, &mut publish));
    let mut cx = Context::from_waker(Waker::noop());
    let mut polls = 0;
    let mut maximum = std::time::Duration::ZERO;
    loop {
        let now = Instant::now();
        let result = future.as_mut().poll(&mut cx);
        maximum = maximum.max(now.elapsed());
        polls += 1;
        match result {
            Poll::Pending => {}
            Poll::Ready(result) => {
                assert!(matches!(
                    result,
                    Err(wstx_rust::decoder::DecodeError::Cancelled)
                ));
                break;
            }
        }
    }
    drop(future);
    assert_eq!(published.len(), 1);
    assert!(polls > 1, "future never yielded");
    assert!(maximum.as_millis() <= 50, "largest quantum {maximum:?}");
    eprintln!("{polls} cooperative polls, maximum {maximum:?}");
}
#[test]
fn planned_scalar_and_gain_invariance() {
    let root = prepared("quality");
    for (mode, name) in [
        (Mode::Ft8, "ft8-one-spacing-6db-00"),
        (Mode::Ft4, "ft4-strong-00"),
    ] {
        let samples = wav(&root.join(name).join("000000_000000.wav"));
        let planned = Decoder::new().decode(&samples, mode, &|| false).unwrap();
        let scalar = Decoder::with_scalar_transform()
            .decode(&samples, mode, &|| false)
            .unwrap();
        assert!(!planned.is_empty());
        assert_eq!(planned.len(), scalar.len());
        for (a, b) in planned.iter().zip(scalar) {
            assert_eq!(a.payload, b.payload);
            assert!(a.start_frame.abs_diff(b.start_frame) <= 1);
            assert!(
                (a.frequency_hz - b.frequency_hz).abs()
                    <= if mode == Mode::Ft8 { 0.2 } else { 0.5 }
            );
        }
        for gain in [0.0001, 16.] {
            let scaled = samples.iter().map(|&x| x * gain).collect::<Vec<_>>();
            let actual = Decoder::new().decode(&scaled, mode, &|| false).unwrap();
            assert_eq!(planned.len(), actual.len(), "gain {gain}");
            for (a, b) in planned.iter().zip(actual) {
                assert_eq!(a.payload, b.payload, "gain {gain}");
                assert!(a.start_frame.abs_diff(b.start_frame) <= 1);
                assert!((a.frequency_hz - b.frequency_hz).abs() < 0.1);
            }
        }
    }
}
#[test]
fn unmodulated_sources_are_not_frames() {
    for mode in [Mode::Ft4, Mode::Ft8] {
        let dc = vec![0.1; 180000];
        let mut impulse = vec![0.; 180000];
        impulse[6000] = 0.5;
        let tone = (0..180000)
            .map(|i| (0.1 * (2. * std::f64::consts::PI * 1000. * i as f64 / 12000.).cos()) as f32)
            .collect::<Vec<_>>();
        for input in [&dc, &tone, &impulse] {
            assert!(
                Decoder::new()
                    .decode(input, mode, &|| false)
                    .unwrap()
                    .is_empty()
            );
        }
    }
}
#[test]
fn crc_valid_unsupported_and_invalid_payloads_are_retained() {
    let fixture: Value = serde_json::from_str(include_str!(
        "../../fixtures/decoder/payload-boundary-cases.json"
    ))
    .unwrap();
    let temporary = std::env::temp_dir().join(format!(
        "wstx-source-classes-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    fs::create_dir(&temporary).unwrap();
    let tool = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../fixtures/decoder/independent-vector-tool/generate.py");
    let protocol = tool.parent().unwrap().join("../protocol-data");
    for mode in [Mode::Ft4, Mode::Ft8] {
        for name in [
            "free-71-3-6",
            "standard-fixed-74-3-7",
            "standard-fixed-59-15-32400",
        ] {
            let expected = fixture["cases"]
                .as_array()
                .unwrap()
                .iter()
                .find(|x| x["id"] == name)
                .unwrap();
            let output = temporary.join(format!("{mode:?}-{name}"));
            let recipe = serde_json::json!({"rate_hz":12000,"frames":180000,"noise_std":0,"signals":[{"mode":mode,"payload77":expected["payload77"],"start_frame":6000,"frequency_hz":1000,"amplitude":0.15,"phase_radians":0.7}]});
            let recipe_file = temporary.join("case.json");
            fs::write(&recipe_file, serde_json::to_vec(&recipe).unwrap()).unwrap();
            let result =
                std::process::Command::new(if cfg!(windows) { "python" } else { "python3" })
                    .arg(&tool)
                    .arg("--case")
                    .arg(&recipe_file)
                    .arg("--out")
                    .arg(&output)
                    .arg("--protocol-data")
                    .arg(&protocol)
                    .output()
                    .unwrap();
            assert!(
                result.status.success(),
                "{}",
                String::from_utf8_lossy(&result.stderr)
            );
            let samples = wav(&output.join("000000_000000.wav"));
            let decoded = Decoder::new().decode(&samples, mode, &|| false).unwrap();
            assert_eq!(decoded.len(), 1, "{mode:?} {name}");
            let d = &decoded[0];
            assert_eq!(d.payload.payload77, expected["payload77"].as_str().unwrap());
            assert_eq!(
                serde_json::to_value(d.payload.status).unwrap(),
                expected["expected_status"]
            );
            assert!(d.payload.text.is_none() && d.payload.fields.is_none());
        }
    }
    let resolved = temporary.canonicalize().unwrap();
    assert!(resolved.starts_with(std::env::temp_dir().canonicalize().unwrap()));
    assert!(
        resolved
            .file_name()
            .unwrap()
            .to_string_lossy()
            .starts_with("wstx-source-classes-")
    );
    fs::remove_dir_all(resolved).unwrap();
}
#[test]
fn fixture_cache_refuses_forged_observations() {
    let tool = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../fixtures/decoder/independent-vector-tool/test_cache.py");
    let output = std::process::Command::new(if cfg!(windows) { "python" } else { "python3" })
        .arg(tool)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(String::from_utf8_lossy(&output.stderr).contains("Ran 3 tests"));
}

#[test]
fn phase_drift_dynamic_range_and_residual_regressions() {
    let fixtures: Value = serde_json::from_str(include_str!(
        "../../fixtures/decoder/synchronization-cases.json"
    ))
    .unwrap();
    let root = std::env::var_os("WSTX_DECODER_SYNCHRONIZATION")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            std::env::temp_dir()
                .join("wstx-decoder-synchronization")
                .join(fixtures["generator_sha256"].as_str().unwrap())
        });
    let tool = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../fixtures/decoder/independent-vector-tool/regressions.py");
    let output = std::process::Command::new(if cfg!(windows) { "python" } else { "python3" })
        .arg(tool)
        .arg("--output")
        .arg(&root)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "independent regression input verification: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let decoder = Decoder::new();
    let mut checked = 0;
    for case in fixtures["cases"].as_array().unwrap() {
        let id = case["id"].as_str().unwrap();
        let bytes = fs::read(root.join(id).join("samples.f32")).unwrap();
        assert_eq!(bytes.len(), case["frames"].as_u64().unwrap() as usize * 4);
        let samples = bytes
            .chunks_exact(4)
            .map(|b| f32::from_le_bytes(b.try_into().unwrap()))
            .collect::<Vec<_>>();
        assert!(samples.iter().all(|x| x.is_finite()));
        let mode = if case["decode_mode"] == "ft4" {
            Mode::Ft4
        } else {
            Mode::Ft8
        };
        let start = Instant::now();
        let decoded = decoder
            .decode(&samples, mode, &|| false)
            .unwrap_or_else(|e| panic!("{id}: {e:?}"));
        eprintln!(
            "{id} {:?}: {:?}",
            start.elapsed(),
            decoded
                .iter()
                .map(|d| (&d.payload.text, d.start_frame, d.frequency_hz))
                .collect::<Vec<_>>()
        );
        let expected = case["expected"].as_array().unwrap();
        assert_eq!(
            decoded.len(),
            expected.len(),
            "{id}: unexpected/missing publications"
        );
        for wanted in expected {
            let matching = decoded
                .iter()
                .filter(|d| d.payload.payload77 == wanted["payload77"].as_str().unwrap())
                .collect::<Vec<_>>();
            assert_eq!(
                matching.len(),
                1,
                "{id}: expected payload absent or duplicated"
            );
            let d = matching[0];
            assert_eq!(
                serde_json::to_value(&d.payload.fields).unwrap(),
                wanted["fields"],
                "{id}"
            );
            assert_eq!(
                serde_json::to_value(&d.payload.text).unwrap(),
                wanted["text"],
                "{id}"
            );
            assert!(
                d.start_frame
                    .abs_diff(wanted["start_frame"].as_u64().unwrap())
                    <= wanted["time_tolerance_frames"].as_u64().unwrap(),
                "{id}: time"
            );
            assert!(
                (d.frequency_hz - wanted["frequency_hz"].as_f64().unwrap()).abs()
                    <= wanted["frequency_tolerance_hz"].as_f64().unwrap(),
                "{id}: frequency"
            );
        }
        checked += 1;
    }
    assert_eq!(checked, 14);
}
