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
                    data.as_chunks::<2>()
                        .0
                        .iter()
                        .map(|&b| i16::from_le_bytes(b) as f32 / 32768.)
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
// Proves: FR-003, FR-004, CL-007-04.
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
// Proves: FR-003, FR-004, CL-007-04.
#[test]
fn quality_corpus() {
    let root = prepared("quality");
    let fixtures: Value =
        serde_json::from_str(include_str!("../../fixtures/decoder/quality-cases.json")).unwrap();
    let decoder = Decoder::new();
    let selected = std::env::var("WSTX_DECODER_CASE_FILTER").ok();
    assert!(
        selected.is_none(),
        "The mandatory corpus forbids diagnostic case filters"
    );
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

// Proves: FR-003, FR-004, CL-007-04.
#[test]
fn cooperative_quanta_and_partial_cancellation() {
    use std::{
        future::Future,
        sync::atomic::{AtomicBool, Ordering},
        task::{Context, Poll, Waker},
    };
    let root = prepared("quality");
    for (mode, name) in [(Mode::Ft8, "ft8-strong-00"), (Mode::Ft4, "ft4-strong-00")] {
        let samples = wav(&root.join(name).join("000000_000000.wav"));
        let decoder = Decoder::new();
        let cancelled = AtomicBool::new(false);
        let cancel = || cancelled.load(Ordering::Relaxed);
        let mut published = vec![];
        let mut publish = |d: &wstx_rust::decoder::Decode| {
            published.push(d.clone());
            cancelled.store(true, Ordering::Relaxed);
            Ok(())
        };
        let mut future = Box::pin(decoder.decode_into_async(&samples, mode, &cancel, &mut publish));
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
        eprintln!("{mode:?}: {polls} cooperative polls, maximum {maximum:?}");
    }
}
// Proves: FR-003, FR-004, CL-007-04.
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
// Proves: FR-003, FR-004, CL-007-04.
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
// Proves: FR-003, FR-004, CL-007-04.
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
// Proves: FR-003, FR-004, CL-007-04.
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

// Proves: FR-003, FR-004, CL-007-04.
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
            .as_chunks::<4>()
            .0
            .iter()
            .map(|&b| f32::from_le_bytes(b))
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

// Proves: FR-003, FR-004, CL-007-04.
#[test]
fn official_modern_recording_baselines() {
    let cases: Value = serde_json::from_str(include_str!(
        "../../fixtures/decoder/recording-baselines.json"
    ))
    .unwrap();
    let samples = PathBuf::from(
        std::env::var_os("WSTX_SAMPLE_DIR").expect("WSTX_SAMPLE_DIR recording cache required"),
    );
    let decoder = Decoder::new();
    let mut failures = vec![];
    for case in cases["cases"].as_array().unwrap() {
        let id = case["id"].as_str().unwrap();
        let mode = if case["mode"] == "ft4" {
            Mode::Ft4
        } else {
            Mode::Ft8
        };
        let file = if mode == Mode::Ft4 {
            samples
                .join("ft4/modern-candidates")
                .join(case["input_filename"].as_str().unwrap())
        } else {
            PathBuf::from(
                std::env::var_os("WSTX_DECODER_OFFICIAL_FT8")
                    .expect("WSTX_DECODER_OFFICIAL_FT8 pinned recording required"),
            )
        };
        let check=std::process::Command::new(if cfg!(windows) {"python"}else{"python3"})
            .args(["-c","import hashlib,pathlib,sys;assert hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest()==sys.argv[2]"])
            .arg(&file).arg(case["input_sha256"].as_str().unwrap()).output().unwrap();
        assert!(
            check.status.success(),
            "{id}: original recording hash changed: {}",
            String::from_utf8_lossy(&check.stderr)
        );
        let input = wav(&file);
        let start = Instant::now();
        let decoded = decoder.decode(&input, mode, &|| false).unwrap();
        eprintln!(
            "RECORDING {id} {:?} {} results: {}",
            start.elapsed(),
            decoded.len(),
            serde_json::to_string(&decoded).unwrap()
        );
        // A separate R before a signed numerical report has the same standard-message fields.
        let canonical = |text: &str| text.replace(" R -", " R-").replace(" R +", " R+");
        let observations = case["observations"].as_array().unwrap();
        let matches = observations
            .iter()
            .filter(|r| {
                decoded.iter().any(|d| {
                    d.payload
                        .text
                        .as_ref()
                        .is_some_and(|t| canonical(t) == canonical(r["text"].as_str().unwrap()))
                        && (d.frequency_hz - r["frequency_hz"].as_f64().unwrap()).abs() <= 5.
                })
            })
            .count();
        let missing = observations
            .iter()
            .filter(|r| {
                !decoded.iter().any(|d| {
                    d.payload
                        .text
                        .as_ref()
                        .is_some_and(|t| canonical(t) == canonical(r["text"].as_str().unwrap()))
                })
            })
            .collect::<Vec<_>>();
        eprintln!(
            "BASELINE {id}: {matches}/{}; missing {missing:?}",
            observations.len()
        );
        if matches < case["minimum_matches"].as_u64().unwrap() as usize {
            failures.push((id, matches));
        }
    }
    assert!(
        failures.is_empty(),
        "baseline thresholds not reached: {failures:?}"
    );
}

// Proves: FR-003, FR-004, CL-007-04.
#[test]
fn release_runtime_and_overlapping_window_history() {
    let root = prepared("quality");
    for scalar in [false, true] {
        let initialize = || {
            if scalar {
                Decoder::with_scalar_transform()
            } else {
                Decoder::new()
            }
        };
        for (mode, id, ceiling, transmissions) in [
            (Mode::Ft8, "ft8-strong-00", 5., 8usize),
            (Mode::Ft4, "ft4-strong-00", 3., 16usize),
        ] {
            let samples = wav(&root.join(id).join("000000_000000.wav"));
            let cold = Instant::now();
            let decoder = initialize();
            let expected = decoder.decode(&samples, mode, &|| false).unwrap();
            assert_eq!(expected.len(), 1);
            assert!(
                cold.elapsed().as_secs_f64() <= ceiling + 2.,
                "{mode:?} cold startup"
            );
            // Warmup is excluded from the ten recorded repeat measurements.
            decoder.decode(&samples, mode, &|| false).unwrap();
            let mut timings = vec![];
            for _ in 0..10 {
                let start = Instant::now();
                let actual = decoder.decode(&samples, mode, &|| false).unwrap();
                timings.push(start.elapsed().as_secs_f64());
                assert_eq!(actual.len(), expected.len());
                for (a, b) in actual.iter().zip(&expected) {
                    assert_eq!(a.payload, b.payload);
                    assert!(a.start_frame.abs_diff(b.start_frame) <= 1);
                    assert!(
                        (a.frequency_hz - b.frequency_hz).abs()
                            <= if mode == Mode::Ft8 { 0.2 } else { 0.5 }
                    );
                }
            }
            timings.sort_by(f64::total_cmp);
            eprintln!(
                "RUNTIME {mode:?} scalar{scalar} ten runs min{} median{} p95{} max{}",
                timings[0],
                (timings[4] + timings[5]) / 2.,
                timings[9],
                timings[9]
            );
            assert!(
                timings[9] <= ceiling,
                "{mode:?} release runtime exceeded {ceiling}s"
            );
            let long = samples.repeat(transmissions);
            assert_eq!(long.len(), 1_440_000);
            let start = Instant::now();
            let actual = decoder.decode(&long, mode, &|| false).unwrap();
            let elapsed = start.elapsed();
            assert_eq!(
                actual.len(),
                transmissions,
                "overlapping windows must neither lose edge frames nor duplicate the same transmission"
            );
            for index in 0..transmissions {
                assert!(
                    actual.iter().any(|d| d.payload == expected[0].payload
                        && d.start_frame
                            .abs_diff(expected[0].start_frame + (index * samples.len()) as u64)
                            <= if mode == Mode::Ft8 { 240 } else { 144 }),
                    "missing transmission {index}"
                );
            }
            assert!(
                elapsed.as_secs_f64() <= 40.,
                "{mode:?}120s source runtime{elapsed:?}"
            );
            eprintln!(
                "RUNTIME {mode:?} scalar{scalar}120s source {elapsed:?}; {} distinct transmissions",
                actual.len()
            );
        }
    }
}

// Proves: FR-003, FR-004, CL-007-03, CL-007-04.
#[test]
fn physical_noise_reproduction_has_no_frame() {
    let root = prepared("quality");
    let input = wav(&root.join("ft4-noise-2-143").join("000000_000000.wav"));
    let actual = Decoder::new().decode(&input, Mode::Ft4, &|| false).unwrap();
    assert!(
        actual.is_empty(),
        "independently specified noise has no injected frame: {actual:?}"
    );
}

// Proves: FR-004, CL-007-03, CL-007-04.
#[test]
fn same_frequency_preserves_two_temporal_frames() {
    let root = prepared("frozen");
    let fixtures: Value = serde_json::from_str(include_str!(
        "../../fixtures/decoder/independent-vectors/manifest.json"
    ))
    .unwrap();
    let vectors = fixtures["vectors"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|v| v["mode"] == "ft4")
        .take(2)
        .collect::<Vec<_>>();
    assert_eq!(vectors.len(), 2);
    let mut samples = vec![0f32; 180000];
    for (v, start) in vectors.iter().zip([6000usize, 96000]) {
        let source = wav(&root
            .join(format!("ft4-{}", v["id"].as_str().unwrap()))
            .join("000000_000000.wav"));
        samples[start..start + 60480].copy_from_slice(&source[6000..66480]);
    }
    let result = Decoder::new()
        .decode(&samples, Mode::Ft4, &|| false)
        .unwrap();
    for (v, start) in vectors.iter().zip([6000u64, 96000]) {
        assert!(
            result.iter().any(|r| r.start_frame.abs_diff(start) <= 144
                && r.payload.text == v["expected_receive"]["text"].as_str().map(str::to_owned)),
            "missing temporal frame {start}: {result:?}"
        );
    }
    assert_eq!(result.len(), 2);
}

// Proves: FR-004, CL-007-04.
#[test]
fn physical_wrong_mode_reproduction_has_no_frame_or_search_error() {
    let root = prepared("quality");
    let input = wav(&root.join("ft4-wrong-mode").join("000000_000000.wav"));
    let actual = Decoder::new().decode(&input, Mode::Ft4, &|| false).unwrap();
    assert!(
        actual.is_empty(),
        "FT8 audio is not an FT4 frame: {actual:?}"
    );
}
