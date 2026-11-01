#![forbid(unsafe_code)]
#![cfg(not(debug_assertions))]
use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
    time::Instant,
};
use std::{
    io::{BufRead, BufReader, Write},
    process::{Child, ChildStdin, Command, Stdio},
    sync::{
        Arc, Mutex,
        mpsc::{Receiver, sync_channel},
    },
    thread::JoinHandle,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use wstx_rust::decoder::{Decode, DecodeError, DecodeState, Decoder, Mode, quadratures};
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
    resource_runtime_parent();
}

struct ResourcePeer {
    child: Child,
    input: Option<ChildStdin>,
    messages: Option<Receiver<Result<Value, String>>>,
    reader: Option<JoinHandle<()>>,
    cleanup: Arc<Mutex<Option<Value>>>,
}
impl ResourcePeer {
    fn spawn(command: &mut Command, marked: bool) -> Self {
        let child = command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .expect("spawn owned resource peer");
        // Own the process before any fallible pipe/reader setup.
        let mut peer = Self {
            child,
            input: None,
            messages: None,
            reader: None,
            cleanup: Arc::new(Mutex::new(None)),
        };
        peer.input = peer.child.stdin.take();
        let stdout = peer.child.stdout.take().expect("owned stdout");
        let (sender, receiver) = sync_channel(4);
        peer.messages = Some(receiver);
        peer.reader = Some(std::thread::spawn(move || {
            let mut reader = BufReader::new(stdout);
            loop {
                let line = match resource_line(&mut reader) {
                    Ok(Some(line)) => line,
                    Ok(None) => break,
                    Err(error) => {
                        let _ = sender.send(Err(error));
                        break;
                    }
                };
                let line = match std::str::from_utf8(&line) {
                    Ok(line) => line,
                    Err(error) => {
                        let _ = sender.send(Err(error.to_string()));
                        break;
                    }
                };
                let json = if marked {
                    let Some((_, suffix)) = line.split_once("WSTX_RESOURCE ") else {
                        continue;
                    };
                    suffix
                } else {
                    line
                };
                let message = serde_json::from_str(json).map_err(|error| error.to_string());
                if sender.send(message).is_err() {
                    break;
                }
            }
        }));
        peer
    }
    fn send(&mut self, value: Value) {
        let bytes = serde_json::to_vec(&value).unwrap();
        assert!(bytes.len() <= 4096);
        let input = self.input.as_mut().expect("owned input open");
        input.write_all(&bytes).unwrap();
        input.write_all(b"\n").unwrap();
        input.flush().unwrap();
    }
    fn receive(&self, seconds: u64) -> Value {
        self.messages
            .as_ref()
            .unwrap()
            .recv_timeout(Duration::from_secs(seconds))
            .expect("bounded owned peer reply")
            .expect("valid bounded resource JSON")
    }
    fn wait(&mut self, seconds: u64) {
        let status = self.wait_status(seconds);
        assert!(status.success(), "owned peer exit {status}");
    }
    fn wait_status(&mut self, seconds: u64) -> std::process::ExitStatus {
        self.input.take();
        let deadline = Instant::now() + Duration::from_secs(seconds);
        loop {
            if let Some(status) = self.child.try_wait().unwrap() {
                return status;
            }
            assert!(Instant::now() < deadline, "owned peer exit timeout");
            std::thread::sleep(Duration::from_millis(5));
        }
    }
}
impl Drop for ResourcePeer {
    fn drop(&mut self) {
        self.input.take();
        let kill_attempted = !matches!(self.child.try_wait(), Ok(Some(_)));
        let kill_error = if kill_attempted {
            self.child.kill().err().map(|error| error.to_string())
        } else {
            None
        };
        let waited = self.child.wait();
        // A blocked bounded sender must be released before joining its reader.
        self.messages.take();
        let reader_joined = self
            .reader
            .take()
            .is_none_or(|reader| reader.join().is_ok());
        let receipt = serde_json::json!({"kill_attempted":kill_attempted,"kill_error":kill_error,
            "wait_succeeded":waited.is_ok(),"exit_code":waited.as_ref().ok().and_then(|status|status.code()),
            "wait_error":waited.as_ref().err().map(|error|error.to_string()),"reader_joined":reader_joined});
        if let Ok(mut audit) = self.cleanup.lock() {
            *audit = Some(receipt);
        }
    }
}
fn resource_line(reader: &mut impl BufRead) -> Result<Option<Vec<u8>>, String> {
    let mut line = Vec::new();
    loop {
        let available = reader.fill_buf().map_err(|error| error.to_string())?;
        if available.is_empty() {
            return if line.is_empty() {
                Ok(None)
            } else {
                Err("truncated resource line".into())
            };
        }
        let count = available
            .iter()
            .position(|&b| b == b'\n')
            .map_or(available.len(), |i| i + 1);
        if line.len() + count > 8192 {
            return Err("resource line exceeds8192bytes".into());
        }
        let complete = available[count - 1] == b'\n';
        line.extend_from_slice(&available[..count]);
        reader.consume(count);
        if complete {
            return Ok(Some(line));
        }
    }
}
fn resource_guardian_before_probes(case: &str) {
    assert!(matches!(case, "matrix" | "busy"));
    assert_eq!(
        std::env::var("WSTX_RESOURCE_GUARDIAN_CASE").as_deref(),
        Ok(case),
        "resource selection requires its exact guardian context before probes"
    );
    let nonce = std::env::var("WSTX_RESOURCE_GUARDIAN_NONCE")
        .expect("resource selection requires a guardian nonce before probes");
    assert!(
        nonce.len() == 32
            && nonce
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte)),
        "guardian nonce must be32 lowercase hexadecimal characters"
    );
    let ready = serde_json::to_vec(&serde_json::json!({
        "v":1,"case":case,"nonce":nonce,"pid":std::process::id()
    }))
    .unwrap();
    assert!(ready.len() <= 512);
    eprintln!("WSTX_GUARDIAN_READY {}", String::from_utf8(ready).unwrap());
    std::io::stderr().flush().unwrap();
    let stdin = std::io::stdin();
    let line = resource_line(&mut stdin.lock())
        .expect("bounded guardian GO line")
        .expect("guardian stdin closed before GO");
    let payload = line
        .strip_prefix(b"WSTX_GUARDIAN_GO ")
        .expect("guardian GO prefix");
    #[derive(serde::Deserialize)]
    #[serde(deny_unknown_fields)]
    struct GuardianGo {
        v: u8,
        case: String,
        nonce: String,
    }
    let go: GuardianGo = serde_json::from_slice(payload).expect("guardian GO JSON");
    assert_eq!(
        (go.v, go.case.as_str(), go.nonce.as_str()),
        (1, case, nonce.as_str()),
        "guardian GO must have exactly the expected version, case and nonce"
    );
}
fn resource_emit(value: Value) {
    let bytes = serde_json::to_vec(&value).unwrap();
    assert!(bytes.len() <= 8000);
    println!("WSTX_RESOURCE {}", String::from_utf8(bytes).unwrap());
    std::io::stdout().flush().unwrap();
}
fn resource_helper() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../tools/windows_process_metrics.py")
}
fn resource_python() -> &'static str {
    if cfg!(windows) { "python" } else { "python3" }
}
struct ResourceCapture {
    child: Child,
    readers: Vec<JoinHandle<()>>,
}
impl Drop for ResourceCapture {
    fn drop(&mut self) {
        if self.child.try_wait().ok().flatten().is_none() {
            let _ = self.child.kill();
        }
        let _ = self.child.wait();
        for reader in self.readers.drain(..) {
            let _ = reader.join();
        }
    }
}
fn resource_capture(command: &mut Command, seconds: u64) -> std::process::Output {
    use std::io::Read;
    let child = command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let mut owned = ResourceCapture {
        child,
        readers: Vec::new(),
    };
    let stdout = owned.child.stdout.take().unwrap();
    let stderr = owned.child.stderr.take().unwrap();
    let (sender, receiver) = sync_channel(2);
    let start = Instant::now();
    for (index, stream) in [Box::new(stdout) as Box<dyn Read + Send>, Box::new(stderr)]
        .into_iter()
        .enumerate()
    {
        let sender = sender.clone();
        owned.readers.push(std::thread::spawn(move || {
            let mut bytes = Vec::new();
            let result = stream
                .take(65537)
                .read_to_end(&mut bytes)
                .map_err(|e| e.to_string())
                .and_then(|_| {
                    if bytes.len() > 65536 {
                        Err("bounded command output exceeded64KiB".to_owned())
                    } else {
                        Ok(bytes)
                    }
                });
            let _ = sender.send((index, result));
        }));
    }
    drop(sender);
    let mut output = [Vec::new(), Vec::new()];
    for _ in 0..2 {
        let remaining = Duration::from_secs(seconds)
            .checked_sub(start.elapsed())
            .expect("owned command deadline");
        let (index, bytes) = receiver
            .recv_timeout(remaining)
            .expect("owned command output deadline");
        output[index] = bytes.expect("bounded owned command output");
    }
    let status = loop {
        if let Some(status) = owned.child.try_wait().unwrap() {
            break status;
        }
        assert!(
            start.elapsed() < Duration::from_secs(seconds),
            "owned command exit deadline"
        );
        std::thread::sleep(Duration::from_millis(2));
    };
    std::process::Output {
        status,
        stdout: std::mem::take(&mut output[0]),
        stderr: std::mem::take(&mut output[1]),
    }
}
/// The reference label follows the observed host identity, never an unconditional claim.
fn resource_host_scope() -> Value {
    let computer = std::env::var("COMPUTERNAME").unwrap_or_default();
    let query = resource_capture(
        Command::new("reg").args([
            "query",
            r"HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0",
            "/v",
            "ProcessorNameString",
        ]),
        10,
    );
    let processor = String::from_utf8_lossy(&query.stdout)
        .lines()
        .find_map(|line| {
            line.split_once("REG_SZ")
                .map(|(_, name)| name.trim().to_owned())
        })
        .unwrap_or_default();
    let reference = query.status.success()
        && computer.eq_ignore_ascii_case(RESOURCE_REFERENCE_COMPUTER)
        && processor.contains("Ryzen 9 3900X");
    serde_json::json!({"computer_name":computer,"processor_name":processor,
        "label":if reference {"reference PC HB9BLA (AMD Ryzen 9 3900X, 32 GB, Windows 11)"} else {"supplemental, not reference"}})
}
const RESOURCE_REFERENCE_COMPUTER: &str = "DESKTOP-HB9BLA";
fn resource_hash(path: &Path) -> String {
    let output = resource_capture(Command::new(resource_python()).args(["-c", "import hashlib,pathlib,sys; print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())"])
        .arg(path),10);
    assert!(output.status.success());
    String::from_utf8(output.stdout).unwrap().trim().to_owned()
}
fn resource_metrics_source_identity() -> Value {
    let output = resource_capture(
        Command::new(resource_python())
            .args(["-c", "import hashlib,json,pathlib,sys; raw=pathlib.Path(sys.argv[1]).read_bytes(); canonical=raw.replace(b'\\r\\n',b'\\n'); assert b'\\r' not in canonical, 'bare CR is not an admitted source representation'; print(json.dumps({'raw_sha256':hashlib.sha256(raw).hexdigest(),'canonical_lf_sha256':hashlib.sha256(canonical).hexdigest()}))"])
            .arg(resource_helper()),
        10,
    );
    assert!(output.status.success());
    let identity: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        identity["canonical_lf_sha256"],
        "1d94a699e6f219c03a869313b7dd0f0e0d3eeabd8f6911a4188134e1c23e403e",
        "reviewed named metrics source; only CRLF/LF representation may differ"
    );
    identity
}
fn resource_source() -> String {
    let clean = resource_capture(
        Command::new("git")
            .arg("-C")
            .arg(env!("CARGO_MANIFEST_DIR"))
            .args(["status", "--porcelain"]),
        10,
    );
    assert!(
        clean.status.success() && clean.stdout.is_empty(),
        "resource evidence requires clean committed candidate"
    );
    let output = resource_capture(
        Command::new("git")
            .arg("-C")
            .arg(env!("CARGO_MANIFEST_DIR"))
            .args(["rev-parse", "HEAD"]),
        10,
    );
    assert!(output.status.success());
    String::from_utf8(output.stdout).unwrap().trim().to_owned()
}
fn resource_sample(monitor: &mut ResourcePeer, sequence: u64, pid: u32, creation: u64) -> Value {
    monitor.send(serde_json::json!({"op":"sample","id":sequence}));
    let value = monitor.receive(10);
    assert_eq!(value["pid"], pid);
    assert_eq!(value["creation_filetime"], creation);
    assert_eq!(value["id"], sequence);
    assert_eq!(value["unit"], "bytes");
    assert!(value["private_usage"].as_u64().unwrap() > 0);
    assert!(value["lifetime_peak_commit"].as_u64().unwrap() > 0);
    value
}
#[cfg(windows)]
fn resource_borrowed_child_handle(child: &Child) -> u64 {
    use std::os::windows::io::AsRawHandle;
    child.as_raw_handle() as usize as u64
}
#[cfg(not(windows))]
fn resource_borrowed_child_handle(_child: &Child) -> u64 {
    panic!("Windows owned-process handle qualification required")
}
fn resource_bind_monitor(worker: &ResourcePeer) -> (ResourcePeer, u64) {
    assert!(worker.child.id() > 0);
    let mut command = Command::new(resource_python());
    command.arg(resource_helper()).args([
        "--pid",
        &worker.child.id().to_string(),
        "--parent-handle",
        &resource_borrowed_child_handle(&worker.child).to_string(),
    ]);
    let monitor = ResourcePeer::spawn(&mut command, false);
    let bound = monitor.receive(10);
    assert_eq!(bound["state"], "bound");
    assert_eq!(bound["pid"], worker.child.id());
    let creation = bound["creation_filetime"].as_u64().unwrap();
    assert!(creation > 0);
    (monitor, creation)
}
#[test]
fn resource_owned_worker_failure_cleanup_uses_process_object_not_pid_reopen() {
    assert!(cfg!(windows) && usize::BITS == 64);
    resource_metrics_source_identity();
    let executable = std::env::current_exe().unwrap();
    let config = serde_json::json!({"worker_id":format!("cleanup-control-{}",std::process::id()),
        "source_sha":resource_source(),"executable_sha256":resource_hash(&executable)});
    let mut monitor_and_identity = None;
    let mut cleanup_receipt = None;
    let mut injected = false;
    let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut command = Command::new(&executable);
        command
            .args([
                "--exact",
                "resource_finite_child",
                "--ignored",
                "--nocapture",
                "--test-threads=1",
            ])
            .env("WSTX_RESOURCE_WORKER_CONFIG", config.to_string());
        let worker = ResourcePeer::spawn(&mut command, true);
        cleanup_receipt = Some(worker.cleanup.clone());
        let ready = worker.receive(20);
        assert_eq!(ready["state"], "ready");
        assert_eq!(ready["pid"], worker.child.id());
        let (monitor, creation) = resource_bind_monitor(&worker);
        monitor_and_identity = Some((monitor, creation, worker.child.id()));
        injected = true;
        panic!("controlled owner failure: parent guard must kill and reap its idle worker");
    }));
    assert!(
        outcome.is_err() && injected,
        "the planned cleanup control actually reached the failure point"
    );
    let cleanup = cleanup_receipt.unwrap().lock().unwrap().clone().unwrap();
    assert_eq!(cleanup["kill_attempted"], true);
    assert_eq!(cleanup["kill_error"], Value::Null);
    assert_eq!(cleanup["wait_succeeded"], true);
    assert_eq!(cleanup["reader_joined"], true);
    let (mut monitor, creation, pid) = monitor_and_identity.unwrap();
    monitor.send(serde_json::json!({"op":"sample","id":1}));
    let refusal = monitor.receive(10);
    assert_eq!(
        refusal,
        serde_json::json!({"v":1,"error":"process_not_live","winerror":null})
    );
    assert!(!monitor.wait_status(10).success());
    eprintln!(
        "RESOURCE_CLEANUP_CONTROL {}",
        serde_json::json!({"worker_pid":pid,"creation_filetime":creation,
        "worker_reaped_by_parent_guard":true,"held_process_object_observed_terminated":true,
        "directly_owned_monitor_reaped":true,"worker_cleanup":cleanup,"worker_grandchildren_created":0,"decoded_success_claim":false})
    );
}
fn resource_qualify_round(dispatch: &[u64], replies: &[Value]) -> Value {
    const SKEW_NS: u64 = 50_000_000;
    const CLOCK_MARGIN_NS: u64 = 5_000_000;
    assert!(
        matches!(replies.len(), 1 | 4) && dispatch.len() == replies.len(),
        "actual one/four round cardinality"
    );
    assert!(
        dispatch.windows(2).all(|pair| pair[1] >= pair[0]),
        "monotonic release timestamps"
    );
    let dispatch_skew = dispatch.last().unwrap() - dispatch.first().unwrap();
    assert!(
        dispatch_skew <= SKEW_NS,
        "barrier release qualification exceeds50ms"
    );
    let mut starts = Vec::new();
    let mut ends = Vec::new();
    let mut differences = Vec::new();
    for reply in replies {
        let start = reply["started_unix_ns"].as_u64().unwrap();
        let end = reply["ended_unix_ns"].as_u64().unwrap();
        let duration = reply["monotonic_duration_ns"].as_u64().unwrap();
        assert!(
            start > 0 && duration > 0 && end >= start,
            "real completed interval"
        );
        let difference = (end - start).abs_diff(duration);
        assert!(
            difference <= CLOCK_MARGIN_NS,
            "wall/monotonic clock qualification exceeds5ms"
        );
        let seconds = reply["seconds"].as_f64().unwrap();
        assert!(
            seconds.is_finite() && ((seconds * 1e9) - duration as f64).abs() <= 1.,
            "same monotonic duration in both representations"
        );
        starts.push(start);
        ends.push(end);
        differences.push(difference);
    }
    let latest_start = *starts.iter().max().unwrap();
    let earliest_start = *starts.iter().min().unwrap();
    let start_spread = latest_start - earliest_start;
    assert!(
        start_spread <= SKEW_NS,
        "actual four-worker start spread exceeds50ms qualification"
    );
    let overlap = if replies.len() == 4 {
        let lower = latest_start.checked_add(CLOCK_MARGIN_NS).unwrap();
        let upper = ends.iter().min().unwrap().saturating_sub(CLOCK_MARGIN_NS);
        assert!(
            upper > lower,
            "four actual kernel intervals have no qualified common overlap"
        );
        Some(upper - lower)
    } else {
        None
    };
    serde_json::json!({"qualified":true,"workers":replies.len(),"dispatch_skew_ns":dispatch_skew,
        "actual_start_spread_ns":start_spread,"wall_monotonic_discrepancy_ns":differences,
        "boundary_margin_ns":CLOCK_MARGIN_NS,"qualified_common_overlap_ns":overlap,
        "measurement_qualification_only":true,"padding_or_serialized_work_used":false})
}

#[test]
fn resource_concurrency_qualification_rejects_serial_work_and_clock_faults() {
    let interval = |start: u64, duration: u64| {
        serde_json::json!({"started_unix_ns":start,
        "ended_unix_ns":start+duration,"monotonic_duration_ns":duration,"seconds":duration as f64/1e9})
    };
    let valid = (0..4)
        .map(|index| interval(1_000_000_000 + index * 1_000_000, 200_000_000))
        .collect::<Vec<_>>();
    assert_eq!(
        resource_qualify_round(&[0, 1_000_000, 2_000_000, 3_000_000], &valid)["qualified_common_overlap_ns"],
        187_000_000u64
    );
    let serialized = (0..4)
        .map(|index| interval(1_000_000_000 + index * 10_000_000, 5_000_000))
        .collect::<Vec<_>>();
    assert!(
        std::panic::catch_unwind(|| resource_qualify_round(&[0, 1, 2, 3], &serialized)).is_err()
    );
    assert!(
        std::panic::catch_unwind(|| resource_qualify_round(&[0, 1, 2, 50_000_001], &valid))
            .is_err()
    );
    let mut bad_clock = valid.clone();
    bad_clock[0]["ended_unix_ns"] = serde_json::json!(1_210_000_000u64);
    assert!(
        std::panic::catch_unwind(|| resource_qualify_round(&[0, 1, 2, 3], &bad_clock)).is_err()
    );
    assert!(std::panic::catch_unwind(|| resource_qualify_round(&[0, 1, 2], &valid[..3])).is_err());
}
/// Wall-time sufficient criterion for the 50 ms cooperative CPU quantum (#36).
const RESOURCE_CPU_QUANTUM_WALL_SECONDS: f64 = 0.050;
/// Bounded re-qualification of one matrix configuration (#36); mirrored by the guardian.
const RESOURCE_QUALIFICATION_ATTEMPTS: u64 = 3;
fn resource_runtime_parent() {
    resource_guardian_before_probes("matrix");
    assert!(
        cfg!(windows) && usize::BITS == 64,
        "resource acceptance requires recorded64bit Windows host"
    );
    let root = PathBuf::from(
        std::env::var_os("WSTX_DECODER_CACHE")
            .expect("resource proof requires explicitly prepared immutable quality cache"),
    );
    let cases: Value =
        serde_json::from_str(include_str!("../../fixtures/decoder/resource-cases.json")).unwrap();
    let executable = std::env::current_exe().unwrap();
    let executable_hash = resource_hash(&executable);
    let source = resource_source();
    let metrics_source_identity = resource_metrics_source_identity();
    let compiler = resource_capture(Command::new("rustc").args(["--version", "--verbose"]), 10);
    assert!(compiler.status.success());
    let power = resource_capture(Command::new("powercfg").arg("/getactivescheme"), 10);
    assert!(power.status.success());
    let os_version = resource_capture(Command::new("cmd").args(["/c", "ver"]), 10);
    assert!(os_version.status.success());
    let host_scope = resource_host_scope();
    eprintln!(
        "RESOURCE_HOST {}",
        serde_json::json!({"source_sha":source,"executable_sha256":executable_hash,
        "compiler":String::from_utf8_lossy(&compiler.stdout),"os":std::env::consts::OS,
        "os_version":String::from_utf8_lossy(&os_version.stdout),"build_profile":"release",
        "arch":std::env::consts::ARCH,"processor_identifier":std::env::var("PROCESSOR_IDENTIFIER").unwrap_or_default(),
        "parallelism":std::thread::available_parallelism().unwrap().get(),"power_scheme":String::from_utf8_lossy(&power.stdout),
        "host_scope":host_scope,"full_station_proof":false,
        "metrics_source_identity":metrics_source_identity})
    );
    let mut completed_configurations = 0;
    let mut baselines = std::collections::BTreeMap::<(String, bool), Value>::new();
    for case in cases["samples"].as_array().unwrap() {
        let mode = case["mode"].as_str().unwrap();
        for scalar in [false, true] {
            for long in [false, true] {
                for concurrency in [1usize, 4] {
                    let input = root
                        .join(case["id"].as_str().unwrap())
                        .join("000000_000000.wav");
                    assert_eq!(resource_hash(&input), case["sha256"].as_str().unwrap());
                    let ceiling = if long {
                        40.
                    } else if mode == "ft8" {
                        5.
                    } else {
                        3.
                    };
                    let runtime_ceiling = ceiling * if concurrency == 4 { 2. } else { 1. };
                    // #36: a poll over the 50 ms wall criterion leaves the CPU quantum
                    // unmeasured (no CPU claim, not a violation). The configuration is
                    // re-measured up to RESOURCE_QUALIFICATION_ATTEMPTS times; every budget
                    // stays asserted in every attempt. The owning guardian classifies a
                    // configuration still unqualified after the last attempt as inconclusive.
                    for attempt in 0..RESOURCE_QUALIFICATION_ATTEMPTS {
                        let mut unqualified_polls = Vec::<Value>::new();
                        let mut prepared_polls = Vec::<Value>::with_capacity(concurrency);
                        let mut workers = Vec::with_capacity(concurrency);
                        let mut monitors = Vec::with_capacity(concurrency);
                        let mut identities = Vec::with_capacity(concurrency);
                        let mut idle = Vec::with_capacity(concurrency);
                        eprintln!(
                            "RESOURCE_BEGIN {}",
                            serde_json::json!({"mode":mode,"scalar":scalar,"long":long,"concurrency":concurrency,"configuration":completed_configurations,"attempt":attempt,"input_sha256":case["sha256"],"source_sha":source,"executable_sha256":executable_hash})
                        );
                        for index in 0..concurrency {
                            let identity = format!(
                                "{}-{completed_configurations}-{attempt}-{index}",
                                std::process::id()
                            );
                            let config = serde_json::json!({"mode":mode,"scalar":scalar,"long":long,"input":input,
                            "input_sha256":case["sha256"],"payload77":cases["payload77"],"worker_id":identity,
                            "source_sha":source,"executable_sha256":executable_hash,"cold_ceiling":ceiling+2.});
                            let mut command = Command::new(&executable);
                            command
                                .args([
                                    "--exact",
                                    "resource_finite_child",
                                    "--ignored",
                                    "--nocapture",
                                    "--test-threads=1",
                                ])
                                .env("WSTX_RESOURCE_WORKER_CONFIG", config.to_string());
                            workers.push(ResourcePeer::spawn(&mut command, true));
                            let worker = workers.last_mut().unwrap();
                            let ready = worker.receive(20);
                            assert_eq!(ready["state"], "ready");
                            assert_eq!(ready["worker_id"], identity);
                            assert_eq!(ready["pid"], worker.child.id());
                            assert_eq!(ready["source_sha"], source);
                            assert_eq!(ready["executable_sha256"], executable_hash);
                            let (monitor, creation) = resource_bind_monitor(worker);
                            monitors.push(monitor);
                            let monitor = monitors.last_mut().unwrap();
                            idle.push(resource_sample(monitor, 1, worker.child.id(), creation));
                            identities.push(creation);
                            worker.send(serde_json::json!({"op":"prepare"}));
                            let prepared = worker.receive((2. * ceiling) as u64 + 15);
                            eprintln!(
                                "RESOURCE_PREPARED {}",
                                serde_json::json!({"worker_id":identity,"pid":worker.child.id(),"result":prepared})
                            );
                            assert_eq!(prepared["state"], "prepared");
                            let cold_seconds = prepared["cold_seconds"].as_f64().unwrap();
                            assert!(cold_seconds <= ceiling + 2.);
                            let cold_poll =
                                prepared["cold_max_poll_wall_seconds"].as_f64().unwrap();
                            let warmup_poll =
                                prepared["warmup_max_poll_wall_seconds"].as_f64().unwrap();
                            prepared_polls.push(serde_json::json!({"worker":index,"cold_seconds":cold_seconds,
                            "cold_max_poll_wall_seconds":cold_poll,"warmup_max_poll_wall_seconds":warmup_poll}));
                            // Cold/warmup CPU quantum not established by the conservative 50 ms
                            // wall criterion: measure CPU before alleging a CPU violation.
                            if cold_poll > RESOURCE_CPU_QUANTUM_WALL_SECONDS
                                || warmup_poll > RESOURCE_CPU_QUANTUM_WALL_SECONDS
                            {
                                unqualified_polls.push(serde_json::json!({"worker":index,"phase":"prepare",
                                "cold_max_poll_wall_seconds":cold_poll,"warmup_max_poll_wall_seconds":warmup_poll}));
                            }
                            let baseline = prepared["baseline"].clone();
                            assert_eq!(
                                baseline.as_array().unwrap().len(),
                                if long {
                                    if mode == "ft8" { 8 } else { 16 }
                                } else {
                                    1
                                }
                            );
                            if let Some(reference) = baselines.get(&(mode.to_owned(), long)) {
                                resource_compare_baseline(reference, &baseline, mode);
                            } else {
                                baselines.insert((mode.to_owned(), long), baseline);
                            }
                        }
                        let mut timings = vec![Vec::<f64>::new(); concurrency];
                        let mut rounds = Vec::new();
                        for round in 0..10u64 {
                            for worker in &workers {
                                let armed = worker.receive(10);
                                assert_eq!(
                                    armed,
                                    serde_json::json!({"state":"armed","round":round})
                                );
                            }
                            let dispatch = Instant::now();
                            let mut dispatch_ns = Vec::new();
                            for worker in &mut workers {
                                dispatch_ns.push(dispatch.elapsed().as_nanos() as u64);
                                worker.send(serde_json::json!({"op":"round","round":round}));
                            }
                            let mut replies = Vec::new();
                            for (index, worker) in workers.iter().enumerate() {
                                let result = worker.receive(runtime_ceiling as u64 + 20);
                                eprintln!(
                                    "RESOURCE_ROUND {}",
                                    serde_json::json!({"configuration":completed_configurations,"attempt":attempt,"worker":index,"pid":worker.child.id(),"result":result})
                                );
                                assert_eq!(result["round"], round);
                                assert_eq!(result["state"], "completed");
                                let seconds = result["seconds"].as_f64().unwrap();
                                assert!(
                                    seconds <= runtime_ceiling,
                                    "{mode} long{long} scalar{scalar} workers{concurrency} round{round} actual{seconds}s > {runtime_ceiling}s"
                                );
                                // 50 ms CPU quantum not established by the sufficient wall-time
                                // criterion: actual CPU measurement or re-qualification required.
                                let poll = result["max_poll_wall_seconds"].as_f64().unwrap();
                                if poll > RESOURCE_CPU_QUANTUM_WALL_SECONDS {
                                    unqualified_polls
                                        .push(serde_json::json!({"worker":index,"phase":"round",
                                    "round":round,"max_poll_wall_seconds":poll}));
                                }
                                timings[index].push(seconds);
                                replies.push(result);
                            }
                            let qualification = resource_qualify_round(&dispatch_ns, &replies);
                            rounds.push(serde_json::json!({"round":round,"parent_dispatch_offsets_ns":dispatch_ns,"workers":replies,"concurrency_qualification":qualification}));
                        }
                        let mut metrics = Vec::new();
                        for worker in &mut workers {
                            worker.send(serde_json::json!({"op":"teardown"}));
                        }
                        for index in 0..concurrency {
                            let teardown = workers[index].receive(10);
                            assert_eq!(teardown["state"], "torn_down");
                            assert_eq!(teardown["completed_rounds"], 10);
                            assert_eq!(teardown["work_owners_live"], false);
                            let final_sample = resource_sample(
                                &mut monitors[index],
                                2,
                                workers[index].child.id(),
                                identities[index],
                            );
                            let peak = final_sample["lifetime_peak_commit"].as_u64().unwrap();
                            metrics.push(serde_json::json!({"idle":idle[index],"final_after_teardown":final_sample,
                            "teardown":teardown,"absolute_private_peak_within64MiB":peak<=64*1024*1024,
                            "over64MiB_disposition":"inconclusive sufficient criterion; complete owner accounting required, not automatic workspace failure",
                            "worst_capacity_workspace_audit_complete":false,"whole_workspace_proved":false,
                            "full_station_96MiB_proved":false}));
                            monitors[index].send(serde_json::json!({"op":"close","id":3}));
                            assert_eq!(monitors[index].receive(10)["state"], "closed");
                            monitors[index].wait(10);
                            workers[index].send(serde_json::json!({"op":"finish"}));
                            assert_eq!(workers[index].receive(10)["state"], "finished");
                            workers[index].wait(10);
                        }
                        let summaries = timings.iter_mut().map(|times| {
                        times.sort_by(f64::total_cmp); assert_eq!(times.len(),10);
                        serde_json::json!({"min":times[0],"median":(times[4]+times[5])/2.,"p95":times[9],"max":times[9]})
                    }).collect::<Vec<_>>();
                        eprintln!(
                            "RESOURCE_CONFIGURATION {}",
                            serde_json::json!({"mode":mode,"scalar":scalar,"long":long,
                        "concurrency":concurrency,"configuration":completed_configurations,"attempt":attempt,
                        "cpu_quantum_qualified":unqualified_polls.is_empty(),"unqualified_polls":unqualified_polls,
                        "prepared":prepared_polls,"warmup_excluded":1,"completed_rounds":10,"summaries":summaries,
                        "metrics":metrics,"rounds":rounds,"owned_children_reaped":true,"full_station_proof":false})
                        );
                        assert!(
                            metrics
                                .iter()
                                .all(|m| m["absolute_private_peak_within64MiB"] == true),
                            "workload absolute-peak criterion inconclusive; complete worst-capacity owner audit remains separately required"
                        );
                        if unqualified_polls.is_empty() {
                            break;
                        }
                    }
                    completed_configurations += 1;
                }
            }
        }
    }
    assert_eq!(completed_configurations, 16);
    assert_eq!(resource_source(), source);
    assert_eq!(resource_hash(&executable), executable_hash);
}

#[test]
#[ignore = "owned worker-only; unignored runtime parent explicitly runs and counts it"]
fn resource_finite_child() {
    let text =
        std::env::var("WSTX_RESOURCE_WORKER_CONFIG").expect("parent-owned worker configuration");
    assert!(text.len() <= 2048);
    let config: Value = serde_json::from_str(&text).unwrap();
    resource_emit(
        serde_json::json!({"state":"ready","pid":std::process::id(),"worker_id":config["worker_id"],
        "source_sha":config["source_sha"],"executable_sha256":config["executable_sha256"],
        "provenance_origin":"parent-owned frozen source/executable; worker performs no subprocess probes"}),
    );
    let stdin = std::io::stdin();
    let mut input = stdin.lock();
    let prepare: Value =
        serde_json::from_slice(&resource_line(&mut input).unwrap().expect("prepare command"))
            .unwrap();
    assert_eq!(prepare, serde_json::json!({"op":"prepare"}));
    let path = PathBuf::from(config["input"].as_str().unwrap());
    let mode = if config["mode"] == "ft8" {
        Mode::Ft8
    } else {
        assert_eq!(config["mode"], "ft4");
        Mode::Ft4
    };
    let base = wav(&path);
    let repetitions = if config["long"] == true {
        if mode == Mode::Ft8 { 8 } else { 16 }
    } else {
        1
    };
    let samples = base.repeat(repetitions);
    if repetitions > 1 {
        assert_eq!(samples.len(), 1_440_000);
    }
    let cold = Instant::now();
    let decoder = if config["scalar"] == true {
        Decoder::with_scalar_transform()
    } else {
        Decoder::new()
    };
    let (expected, cold_poll) = resource_decode(&decoder, &samples, mode);
    let cold_seconds = cold.elapsed().as_secs_f64();
    eprintln!(
        "RESOURCE_COLD {}",
        serde_json::json!({"worker_id":config["worker_id"],"cold_seconds":cold_seconds,"records":expected.len(),"complete":true})
    );
    assert_eq!(expected.len(), repetitions);
    for record in &expected {
        assert_eq!(
            record.payload.payload77,
            config["payload77"].as_str().unwrap()
        );
    }
    if repetitions > 1 {
        for index in 0..repetitions {
            assert!(
                expected.iter().any(|record| record
                    .start_frame
                    .abs_diff(expected[0].start_frame + index as u64 * base.len() as u64)
                    <= if mode == Mode::Ft8 { 240 } else { 144 }),
                "original120s edge/overlap oracle"
            );
        }
    }
    assert!(cold_seconds <= config["cold_ceiling"].as_f64().unwrap());
    let (warmup, warm_poll) = resource_decode(&decoder, &samples, mode);
    resource_repeat(&expected, &warmup, mode);
    resource_emit(
        serde_json::json!({"state":"prepared","cold_seconds":cold_seconds,"excluded_warmup":1,
        "records":expected.len(),"cold_max_poll_wall_seconds":cold_poll,"warmup_max_poll_wall_seconds":warm_poll,
        "baseline":expected.iter().map(|record|serde_json::json!({"payload77":record.payload.payload77,"start_frame":record.start_frame,"frequency_hz":record.frequency_hz})).collect::<Vec<_>>()}),
    );
    let mut work = Some((base, samples, decoder, expected, warmup));
    let mut next_round = 0;
    resource_emit(serde_json::json!({"state":"armed","round":next_round}));
    while let Some(line) = resource_line(&mut input).unwrap() {
        let command: Value = serde_json::from_slice(&line).unwrap();
        if command == serde_json::json!({"op":"teardown"}) {
            assert_eq!(next_round, 10);
            assert!(work.is_some(), "one actual teardown");
            drop(work.take());
            resource_emit(
                serde_json::json!({"state":"torn_down","completed_rounds":next_round,"work_owners_live":false,
                "owners_dropped":["decoder_channel","base_input","full_input","cold_baseline","warmup_records"]}),
            );
            continue;
        }
        if command == serde_json::json!({"op":"finish"}) {
            assert_eq!(next_round, 10);
            assert!(
                work.is_none(),
                "finish follows actual teardown and live final sample"
            );
            resource_emit(serde_json::json!({"state":"finished","rounds":next_round}));
            return;
        }
        assert_eq!(
            command,
            serde_json::json!({"op":"round","round":next_round})
        );
        let (_, samples, decoder, expected, _) = work.as_ref().expect("round before teardown");
        let started_unix_ns = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos() as u64;
        let began = Instant::now();
        let (actual, max_poll_wall_seconds) = resource_decode(&decoder, &samples, mode);
        let monotonic_duration = began.elapsed();
        let ended_unix_ns = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos() as u64;
        let seconds = monotonic_duration.as_secs_f64();
        resource_repeat(&expected, &actual, mode);
        resource_emit(
            serde_json::json!({"state":"completed","round":next_round,"seconds":seconds,"started_unix_ns":started_unix_ns,
            "ended_unix_ns":ended_unix_ns,"monotonic_duration_ns":monotonic_duration.as_nanos() as u64,
            "records":actual.len(),"max_poll_wall_seconds":max_poll_wall_seconds}),
        );
        next_round += 1;
        if next_round < 10 {
            resource_emit(serde_json::json!({"state":"armed","round":next_round}));
        }
    }
    panic!("parent pipe closed before required finish handshake");
}
fn resource_decode(
    decoder: &Decoder,
    samples: &[f32],
    mode: Mode,
) -> (Vec<wstx_rust::decoder::Decode>, f64) {
    use std::{
        future::Future,
        task::{Context, Poll, Waker},
    };
    let never = || false;
    let mut future = std::pin::pin!(decoder.decode_async(samples, mode, &never));
    let mut context = Context::from_waker(Waker::noop());
    let mut maximum = 0f64;
    loop {
        let start = Instant::now();
        let result = future.as_mut().poll(&mut context);
        maximum = maximum.max(start.elapsed().as_secs_f64());
        if let Poll::Ready(result) = result {
            return (result.unwrap(), maximum);
        }
    }
}
fn resource_repeat(
    expected: &[wstx_rust::decoder::Decode],
    actual: &[wstx_rust::decoder::Decode],
    mode: Mode,
) {
    assert_eq!(actual.len(), expected.len());
    for (a, b) in actual.iter().zip(expected) {
        assert_eq!(a.payload, b.payload);
        assert!(a.start_frame.abs_diff(b.start_frame) <= 1);
        assert!(
            (a.frequency_hz - b.frequency_hz).abs() <= if mode == Mode::Ft8 { 0.2 } else { 0.5 }
        );
    }
}
fn resource_compare_baseline(expected: &Value, actual: &Value, mode: &str) {
    let mut expected = expected.as_array().unwrap().iter().collect::<Vec<_>>();
    let mut actual = actual.as_array().unwrap().iter().collect::<Vec<_>>();
    let order = |a: &&Value, b: &&Value| {
        a["payload77"]
            .as_str()
            .cmp(&b["payload77"].as_str())
            .then(a["start_frame"].as_u64().cmp(&b["start_frame"].as_u64()))
    };
    expected.sort_by(order);
    actual.sort_by(order);
    assert_eq!(actual.len(), expected.len());
    for (a, b) in actual.into_iter().zip(expected) {
        assert_eq!(a["payload77"], b["payload77"]);
        assert!(
            a["start_frame"]
                .as_u64()
                .unwrap()
                .abs_diff(b["start_frame"].as_u64().unwrap())
                <= 1
        );
        assert!(
            (a["frequency_hz"].as_f64().unwrap() - b["frequency_hz"].as_f64().unwrap()).abs()
                <= if mode == "ft8" { 0.2 } else { 0.5 }
        );
    }
}

struct ResourceHashFile(PathBuf);
impl Drop for ResourceHashFile {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}
fn resource_f32_hash(samples: &[f32]) -> String {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let path = std::env::temp_dir().join(format!(
        "wstx-modem-input-{}-{}-{}.f32le",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos(),
        NEXT.fetch_add(1, std::sync::atomic::Ordering::SeqCst)
    ));
    let file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)
        .unwrap();
    let owned = ResourceHashFile(path);
    let mut output = std::io::BufWriter::new(file);
    for sample in samples {
        output.write_all(&sample.to_le_bytes()).unwrap();
    }
    output.flush().unwrap();
    drop(output);
    resource_hash(&owned.0)
}

struct ResourceLiveAttempt {
    outcome: Result<(), DecodeError>,
    records: Vec<Decode>,
    cancel_return: Option<Duration>,
}
fn resource_live_attempt(
    decoder: &Decoder,
    samples: Vec<f32>,
    origin: u64,
    state: &mut DecodeState,
    context: Value,
    cancel_after_pending: bool,
) -> ResourceLiveAttempt {
    use std::{
        cell::RefCell,
        future::Future,
        sync::atomic::{AtomicBool, Ordering},
        task::{Context, Poll, Waker},
    };
    assert_eq!(samples.len(), 360000);
    let began = Instant::now();
    let publications = RefCell::new(Vec::<(f64, Decode)>::new());
    let cancel = AtomicBool::new(false);
    let mut cancelled_at = None;
    let mut polls = 0u64;
    let mut pending = 0u64;
    let mut maximum = Duration::ZERO;
    let mut flushed = 0usize;
    eprintln!(
        "RESOURCE_LIVE_ATTEMPT_START {}",
        serde_json::json!({"context":context,"origin":origin,
        "frames":samples.len(),"public_api":"decode_window_into_async","live_history":true,
        "cancel_after_observed_pending":cancel_after_pending,"total_deadline_seconds":null,
        "cpu_time_measured":false,"manager_proof":false})
    );
    let (outcome, returned) = {
        let mut publish = |record: &Decode| {
            let mut values = publications.borrow_mut();
            assert!(
                values.len() < 2048,
                "bounded observer follows existing modem record ceiling"
            );
            values.push((began.elapsed().as_secs_f64(), record.clone()));
            Ok(())
        };
        let is_cancelled = || cancel.load(Ordering::SeqCst);
        let mut future = std::pin::pin!(decoder.decode_window_into_async(
            samples,
            origin,
            state,
            &is_cancelled,
            &mut publish
        ));
        let mut cx = Context::from_waker(Waker::noop());
        loop {
            let poll_started = Instant::now();
            let result = future.as_mut().poll(&mut cx);
            let poll_ended = Instant::now();
            let wall = poll_ended.duration_since(poll_started);
            polls += 1;
            maximum = maximum.max(wall);
            let ready = matches!(&result, Poll::Ready(_));
            if !ready {
                pending += 1;
            }
            eprintln!(
                "RESOURCE_LIVE_POLL {}",
                serde_json::json!({"context":context,"poll":polls,
                "started_seconds":poll_started.duration_since(began).as_secs_f64(),
                "wall_seconds":wall.as_secs_f64(),"ready":ready,"cpu_time_measured":false})
            );
            {
                let values = publications.borrow();
                for (at, record) in &values[flushed..] {
                    eprintln!(
                        "RESOURCE_LIVE_PUBLICATION {}",
                        serde_json::json!({"context":context,
                        "callback_seconds":at,"record":record,"genuine_verified_callback":true})
                    );
                }
                flushed = values.len();
            }
            match result {
                Poll::Ready(outcome) => break (outcome, poll_ended),
                Poll::Pending => {
                    if cancel_after_pending && cancelled_at.is_none() {
                        let accepted = Instant::now();
                        cancel.store(true, Ordering::SeqCst);
                        cancelled_at = Some(accepted);
                    }
                }
            }
        }
    };
    let records = publications
        .into_inner()
        .into_iter()
        .map(|(_, record)| record)
        .collect::<Vec<_>>();
    let cancel_return = cancelled_at.and_then(|accepted| returned.checked_duration_since(accepted));
    if let Some(accepted) = cancelled_at {
        eprintln!(
            "RESOURCE_LIVE_CANCEL {}",
            serde_json::json!({"context":context,
            "after_real_pending_boundary":true,"requested_seconds":accepted.duration_since(began).as_secs_f64(),
            "log_written_after_kernel_return":true,"manager_ack_or_publication_invalidation_claim":false})
        );
    }
    eprintln!(
        "RESOURCE_LIVE_ATTEMPT_END {}",
        serde_json::json!({"context":context,
        "outcome":format!("{outcome:?}"),"numerical_completion":outcome.is_ok(),"wall_seconds":returned.duration_since(began).as_secs_f64(),
        "polls":polls,"pending":pending,"maximum_poll_wall_seconds":maximum.as_secs_f64(),
        "wall_sufficient_for50ms_cpu":maximum<=Duration::from_millis(50),"cpu_time_measured":false,
        "over50ms_disposition":"CPU evidence inconclusive until justified CPU measurement; not automatically a CPU violation",
        "cancel_to_kernel_return_seconds":cancel_return.map(|time|time.as_secs_f64()),
        "history_records_after_future_drop":state.available_count(),"records":records,
        "manager_ack_release_terminal_or_status_proved":false,"new_busy_total_deadline":false})
    );
    ResourceLiveAttempt {
        outcome,
        records,
        cancel_return,
    }
}
fn resource_official_comparison(records: &[Decode], oracle: &Value, context: &str) {
    let canonical = |text: &str| text.replace(" R -", " R-").replace(" R +", " R+");
    let observations = oracle["observations"].as_array().unwrap();
    let missing = observations
        .iter()
        .filter(|wanted| {
            !records.iter().any(|record| {
                record.payload.text.as_ref().is_some_and(|text| {
                    canonical(text) == canonical(wanted["text"].as_str().unwrap())
                        && (record.frequency_hz - wanted["frequency_hz"].as_f64().unwrap()).abs()
                            <= 5.
                })
            })
        })
        .map(|wanted| wanted["text"].clone())
        .collect::<Vec<_>>();
    let extra = records
        .iter()
        .filter(|record| {
            !observations.iter().any(|wanted| {
                record.payload.text.as_ref().is_some_and(|text| {
                    canonical(text) == canonical(wanted["text"].as_str().unwrap())
                })
            })
        })
        .map(|record| record.payload.text.clone())
        .collect::<Vec<_>>();
    eprintln!(
        "RESOURCE_LIVE_REFERENCE_COMPARISON {}",
        serde_json::json!({"context":context,
        "oracle":"pinned nonexhaustive recording-baselines.json external observations",
        "observed_reference_rows":observations.len(),"missing_observed_texts":missing,
        "new_texts_outside_observation_list":extra,"is_exhaustive_ground_truth":false,
        "new_quality_threshold_inferred":false})
    );
}

// Proves: CL-007-04; TC-004-003. Explicit diagnostic selection is required; no total busy-window SLA is added.
#[test]
#[ignore = "explicit resource diagnostic: genuine30s public async windows; selected root CPU budget, no new total deadline"]
fn resource_busy_live_overlap_and_pending_cancel() {
    resource_guardian_before_probes("busy");
    assert!(
        cfg!(windows) && usize::BITS == 64,
        "recorded Windows resource diagnostic"
    );
    assert!(
        !cfg!(debug_assertions),
        "resource timing evidence requires the release test executable"
    );
    let cases: Value =
        serde_json::from_str(include_str!("../../fixtures/decoder/resource-cases.json")).unwrap();
    let live = &cases["live_window"];
    let quality =
        PathBuf::from(std::env::var_os("WSTX_DECODER_CACHE").expect("prepared quality cache"));
    let official = PathBuf::from(
        std::env::var_os("WSTX_DECODER_OFFICIAL_FT8").expect("pinned official FT8 WAV"),
    );
    let oracle_path =
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../fixtures/decoder/recording-baselines.json");
    let oracle_data: Value = serde_json::from_str(include_str!(
        "../../fixtures/decoder/recording-baselines.json"
    ))
    .unwrap();
    let oracle = oracle_data["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| case["id"] == "ft8-official")
        .unwrap();
    let single_path = quality.join("ft8-strong-00/000000_000000.wav");
    let inputs = live["inputs"].as_array().unwrap();
    assert_eq!(
        resource_hash(&single_path),
        inputs[1]["wav_sha256"].as_str().unwrap()
    );
    assert_eq!(
        resource_hash(&official),
        inputs[2]["wav_sha256"].as_str().unwrap()
    );
    assert_eq!(oracle["input_sha256"], inputs[2]["wav_sha256"]);
    let base_inputs = [vec![0f32; 180000], wav(&single_path), wav(&official)];
    // Hash the actual Rust canonical Vec bytes before any decoder invocation.
    for (index, base) in base_inputs.iter().enumerate() {
        assert_eq!(base.len(), 180000);
        assert_eq!(
            resource_f32_hash(base),
            inputs[index]["f32le_sha256"].as_str().unwrap()
        );
        assert_eq!(
            resource_f32_hash(&base.repeat(2)),
            inputs[index]["doubled_f32le_sha256"].as_str().unwrap()
        );
    }
    let compiler = resource_capture(Command::new("rustc").args(["--version", "--verbose"]), 10);
    let os_version = resource_capture(Command::new("cmd").args(["/c", "ver"]), 10);
    let power = resource_capture(Command::new("powercfg").arg("/getactivescheme"), 10);
    assert!(compiler.status.success() && os_version.status.success() && power.status.success());
    let host_scope = resource_host_scope();
    eprintln!(
        "RESOURCE_LIVE_HOST {}",
        serde_json::json!({"compiler":String::from_utf8_lossy(&compiler.stdout),
        "os_version":String::from_utf8_lossy(&os_version.stdout),"power_scheme":String::from_utf8_lossy(&power.stdout),
        "processor_identifier":std::env::var("PROCESSOR_IDENTIFIER").unwrap_or_default(),
        "parallelism":std::thread::available_parallelism().unwrap().get(),
        "build_profile":if cfg!(debug_assertions){"debug"}else{"release"},
        "debug_assertions":cfg!(debug_assertions),
        "host_scope":host_scope,"total_cpu_time_measured":false})
    );
    eprintln!(
        "RESOURCE_LIVE_INPUTS {}",
        serde_json::json!({"source_sha":resource_source(),
        "executable_sha256":resource_hash(&std::env::current_exe().unwrap()),"inputs":live,
        "oracle_manifest_raw_sha256":resource_hash(&oracle_path),"host_scope":host_scope,
        "geometry":{"stream_frames":720000,"window_frames":360000,"advance_frames":180000},
        "cpu_time_measured":false,"four_profile_or_memory_or_station_proof":false})
    );
    let constructed = Instant::now();
    let decoder = Decoder::new();
    eprintln!(
        "RESOURCE_LIVE_CONSTRUCTION {}",
        serde_json::json!({"backend":"planned","seconds":constructed.elapsed().as_secs_f64()})
    );
    let mut silence = DecodeState::new_live(Mode::Ft8);
    let control = resource_live_attempt(
        &decoder,
        base_inputs[0].repeat(2),
        0,
        &mut silence,
        serde_json::json!({"case":"silence","mode":"ft8","backend":"planned","state":"fresh","origin":0}),
        false,
    );
    assert_eq!(control.outcome, Ok(()));
    assert!(control.records.is_empty());
    let mut single = DecodeState::new_live(Mode::Ft8);
    let control = resource_live_attempt(
        &decoder,
        base_inputs[1].repeat(2),
        0,
        &mut single,
        serde_json::json!({"case":"single","mode":"ft8","backend":"planned","state":"fresh","origin":0}),
        false,
    );
    assert_eq!(control.outcome, Ok(()));
    assert_eq!(control.records.len(), 2);
    assert!(
        control
            .records
            .iter()
            .all(|record| record.payload.payload77 == cases["payload77"].as_str().unwrap())
    );
    let stream = base_inputs[2].repeat(4);
    assert_eq!(stream.len(), 720000);
    let first_window = stream[..360000].to_vec();
    let next_window = stream[180000..540000].to_vec();
    assert_eq!(&first_window[180000..], &next_window[..180000]);
    let mut retained = DecodeState::new_live(Mode::Ft8);
    let first = resource_live_attempt(
        &decoder,
        first_window.clone(),
        0,
        &mut retained,
        serde_json::json!({"case":"busy","mode":"ft8","backend":"planned","state":"retained-first","origin":0}),
        false,
    );
    resource_official_comparison(&first.records, oracle, "busy-first");
    assert_eq!(first.outcome, Ok(()));
    let next = resource_live_attempt(
        &decoder,
        next_window.clone(),
        180000,
        &mut retained,
        serde_json::json!({"case":"busy","mode":"ft8","backend":"planned","state":"retained-next","origin":180000}),
        false,
    );
    resource_official_comparison(&next.records, oracle, "busy-retained-next");
    assert_eq!(next.outcome, Ok(()));
    for record in &next.records {
        assert!(record.start_frame >= 180000 && record.start_frame < 540000);
        assert!(
            !first
                .records
                .iter()
                .any(|old| old.payload.payload77 == record.payload.payload77
                    && old.start_frame.abs_diff(record.start_frame) <= 960),
            "retained live history must not republish the same overlapping source record"
        );
    }
    let mut fresh = DecodeState::new_live(Mode::Ft8);
    let comparison = resource_live_attempt(
        &decoder,
        next_window,
        180000,
        &mut fresh,
        serde_json::json!({"case":"busy","mode":"ft8","backend":"planned","state":"fresh-same-next-window","origin":180000}),
        false,
    );
    resource_official_comparison(&comparison.records, oracle, "busy-fresh-next");
    assert_eq!(comparison.outcome, Ok(()));
    eprintln!(
        "RESOURCE_LIVE_HISTORY_COMPARISON {}",
        serde_json::json!({"same_source_interval":[180000,540000],
        "retained_published":next.records,"fresh_published":comparison.records,"does_not_require_equal_publications":true})
    );
    let mut cancelled = DecodeState::new_live(Mode::Ft8);
    let cancellation = resource_live_attempt(
        &decoder,
        first_window,
        0,
        &mut cancelled,
        serde_json::json!({"case":"busy","mode":"ft8","backend":"planned","state":"cancel-after-real-Pending","origin":0}),
        true,
    );
    assert_eq!(cancellation.outcome, Err(DecodeError::Cancelled));
    assert!(
        cancellation.cancel_return.is_some(),
        "real Pending boundary must be observed before cancellation"
    );
    assert!(
        cancellation.cancel_return.unwrap() <= Duration::from_millis(250),
        "pure kernel cancellation-return necessary sub-bound; manager ACK/release remains separately unproved"
    );
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
