use super::*;
use axum::http::StatusCode;

const PROFILE: &str = "00000000-0000-4000-8000-000000000001";

struct Dir(PathBuf);
impl Dir {
    fn new() -> Self {
        let path =
            std::env::temp_dir().join(format!("wstx-diagnostics-{}", profile::new_uuid().unwrap()));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
    fn open(&self) -> Arc<Recording> {
        Recording::open(&self.0, PROFILE.into(), profile::new_uuid().unwrap())
    }
}
impl Drop for Dir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn window(origin: u64) -> Value {
    json!({"mode":"ft8","origin":origin,"period_start_utc":"2026-11-02T09:16:00.0000000Z",
        "dump":null})
}
fn dumped(dir: &Path) -> Vec<String> {
    let mut names = fs::read_dir(dir.join(DUMP_DIR))
        .map(|d| {
            d.map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    names.sort();
    names
}
fn wait_for(dir: &Path, count: usize) -> Vec<String> {
    let started = Instant::now();
    loop {
        let names = dumped(dir);
        if names.len() >= count || started.elapsed() > Duration::from_secs(10) {
            return names;
        }
        std::thread::sleep(Duration::from_millis(5));
    }
}

// Proves: CL-052-01; TC-052-001. Hand-counted zeros, their longest run and those inside the
// FT8 early buffer [period, period + 141696).
#[test]
fn window_zero_counts_follow_the_early_buffer() {
    let mut x = vec![0.5f32; 20];
    for i in [2, 3, 4, 10, 18, 19] {
        x[i] = 0.0;
    }
    // Window frames 100..120; the early buffer starts at frame 104.
    assert_eq!(zero_counts(&x, 100, Some(104)), (6, 3, Some(4)));
    assert_eq!(zero_counts(&x, 100, None), (6, 3, None));
    // A period start ending before the window: no early-buffer zeros.
    assert_eq!(zero_counts(&x, 200_000, Some(0)), (6, 3, Some(0)));
    assert_eq!(zero_counts(&[], 0, Some(0)), (0, 0, Some(0)));
}

// Proves: CL-052-01; TC-052-001. A 12 kHz mono PCM16 WAV, as jt9 reads it.
#[test]
fn window_dump_is_a_12_khz_pcm16_wav() {
    let bytes = wav_bytes(&[0.0, 0.5, -1.0, 1.0]);
    assert_eq!(bytes.len(), 44 + 8);
    assert_eq!(&bytes[0..4], b"RIFF");
    assert_eq!(u32::from_le_bytes(bytes[4..8].try_into().unwrap()), 36 + 8);
    assert_eq!(&bytes[8..16], b"WAVEfmt ");
    assert_eq!(u16::from_le_bytes([bytes[22], bytes[23]]), 1);
    assert_eq!(u32::from_le_bytes(bytes[24..28].try_into().unwrap()), 12000);
    assert_eq!(u16::from_le_bytes([bytes[34], bytes[35]]), 16);
    assert_eq!(&bytes[36..40], b"data");
    let samples = bytes[44..]
        .as_chunks::<2>()
        .0
        .iter()
        .map(|&b| i16::from_le_bytes(b))
        .collect::<Vec<_>>();
    assert_eq!(samples, vec![0, 16384, -32768, 32767]);
}

// Proves: CL-052-01; TC-052-001. Off by default and after a foreign or corrupt file; the
// operator's choice persists next to profile.json; wrong profile or boot is refused.
#[test]
fn window_dump_setting_defaults_off_and_persists() {
    let dir = Dir::new();
    let r = dir.open();
    let v = r.diagnostics_view();
    assert_eq!(
        (&v["window_dump"], &v["storage_error"], &v["windows"]),
        (&json!(false), &Value::Null, &json!([]))
    );
    assert_eq!(
        r.set_window_dump("other", &r.boot, true),
        Err("wrong_profile")
    );
    assert_eq!(
        r.set_window_dump(PROFILE, "old-boot", true),
        Err("state_conflict")
    );
    assert_eq!(
        r.set_window_dump(PROFILE, &r.boot, true).unwrap()["window_dump"],
        true
    );
    let file: Value = serde_json::from_slice(&fs::read(dir.0.join(FILE)).unwrap()).unwrap();
    assert_eq!(
        file,
        json!({"schema_version":1,"profile_id":PROFILE,"window_dump":true})
    );
    drop(r);
    assert_eq!(dir.open().diagnostics_view()["window_dump"], true);
    for bad in [
        json!({"schema_version":1,"profile_id":"foreign","window_dump":true}),
        json!({"schema_version":2,"profile_id":PROFILE,"window_dump":true}),
        json!({"schema_version":1,"profile_id":PROFILE,"window_dump":true,"extra":1}),
    ] {
        fs::write(dir.0.join(FILE), serde_json::to_vec(&bad).unwrap()).unwrap();
        let v = dir.open().diagnostics_view();
        assert_eq!(
            (&v["window_dump"], &v["storage_error"]),
            (&json!(false), &json!("invalid_diagnostics")),
            "{bad}"
        );
    }
}

// Proves: CL-052-01; TC-052-001. Only an FT8 prompt window with the dump on is written (WAV
// and sidecar); the last 20 windows' counters are kept; the dump keeps the newest 20.
#[test]
fn window_dump_writes_prompt_windows_and_rotates() {
    let dir = Dir::new();
    let r = dir.open();
    let samples = vec![0.25f32; 1200];
    r.note_window(window(1), &samples, true);
    assert!(dumped(&dir.0).is_empty(), "off by default");
    r.set_window_dump(PROFILE, &r.boot, true).unwrap();
    r.note_window(window(2), &samples, false);
    assert!(dumped(&dir.0).is_empty(), "not a dumpable window");
    r.note_window(window(3), &samples, true);
    let names = wait_for(&dir.0, 2);
    let stem = "000000000000003-20261102T0916000000000Z";
    assert_eq!(names, vec![format!("{stem}.json"), format!("{stem}.wav")]);
    let wav = fs::read(dir.0.join(DUMP_DIR).join(format!("{stem}.wav"))).unwrap();
    assert_eq!(wav, wav_bytes(&samples));
    let sidecar: Value = serde_json::from_slice(
        &fs::read(dir.0.join(DUMP_DIR).join(format!("{stem}.json"))).unwrap(),
    )
    .unwrap();
    assert_eq!(sidecar["rate_hz"], 12000);
    assert_eq!(sidecar["window"]["origin"], 3);
    assert_eq!(sidecar["window"]["dump"], format!("{stem}.wav"));
    for origin in 4..30 {
        r.note_window(window(origin), &samples, true);
        // Each write completes (and rotates) before the next, with a distinct time.
        let sidecar = dir
            .0
            .join(DUMP_DIR)
            .join(format!("{origin:015}-20261102T0916000000000Z.json"));
        let started = Instant::now();
        while !sidecar.exists() && started.elapsed() < Duration::from_secs(10) {
            std::thread::sleep(Duration::from_millis(5));
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    let started = Instant::now();
    while dumped(&dir.0).len() != 2 * DUMP_KEEP && started.elapsed() < Duration::from_secs(10) {
        std::thread::sleep(Duration::from_millis(5));
    }
    let names = dumped(&dir.0);
    assert_eq!(names.len(), 2 * DUMP_KEEP);
    assert!(names[0].starts_with("000000000000010-"), "{names:?}");
    let v = r.diagnostics_view();
    let windows = v["windows"].as_array().unwrap();
    assert_eq!(windows.len(), WINDOWS);
    assert_eq!(windows[0]["origin"], 10);
    assert_eq!(
        windows[0]["dump"],
        "000000000000010-20261102T0916000000000Z.wav"
    );
    assert_eq!(v["dumped_windows"], 27);
    assert_eq!(v["dump_error"], Value::Null);
}

// Proves: CL-052-01; TC-052-001. The size cap removes the oldest windows first.
#[test]
fn window_dump_rotation_keeps_the_byte_cap() {
    let dir = Dir::new();
    let dump = dir.0.join(DUMP_DIR);
    fs::create_dir(&dump).unwrap();
    let big = vec![0u8; (DUMP_BYTES / 3) as usize];
    for i in 0..5 {
        fs::write(dump.join(format!("{i}.wav")), &big).unwrap();
        fs::write(dump.join(format!("{i}.json")), b"{}").unwrap();
        std::thread::sleep(Duration::from_millis(20));
    }
    rotate(&dump).unwrap();
    let mut names = fs::read_dir(&dump)
        .unwrap()
        .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
        .collect::<Vec<_>>();
    names.sort();
    // Three of a third plus their sidecars exceed the cap; the newest two remain.
    assert_eq!(names, vec!["3.json", "3.wav", "4.json", "4.wav"]);
}

// Proves: CL-052-01; TC-052-001. GET/POST /receive/diagnostics through the station router,
// with the station's refusal codes and no change on a refused request; GET /receive does
// not carry the window counters.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn diagnostics_http_view_and_dump_update() {
    let f = crate::contact_http_tests::fixture("http://127.0.0.1:18461", false);
    let (status, view, _, _) = f.call("GET", "/receive/diagnostics", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        (
            &view["v"],
            &view["window_dump"],
            &view["windows"],
            &view["profile_id"]
        ),
        (&json!(1), &json!(false), &json!([]), &json!(f.id))
    );
    let body = |on: bool| json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"window_dump":on});
    let (status, view, _, _) = f
        .call("POST", "/receive/diagnostics", Some(body(true)))
        .await;
    assert_eq!(
        (status, &view["window_dump"]),
        (StatusCode::OK, &json!(true))
    );
    let file: Value = serde_json::from_slice(&fs::read(f.dir.join(FILE)).unwrap()).unwrap();
    assert_eq!(file["window_dump"], true);
    let mut wrong = body(false);
    wrong["profile_id"] = json!(profile::new_uuid().unwrap());
    let mut stale = body(false);
    stale["boot_id"] = json!(profile::new_uuid().unwrap());
    let mut extra = body(false);
    extra["folder"] = json!("C:/");
    let mut text = body(false);
    text["window_dump"] = json!("false");
    for (b, code, status) in [
        (wrong, "wrong_profile", StatusCode::FORBIDDEN),
        (stale, "state_conflict", StatusCode::CONFLICT),
        (extra, "invalid_request", StatusCode::BAD_REQUEST),
        (text, "invalid_request", StatusCode::BAD_REQUEST),
    ] {
        let (got, v, _, _) = f.call("POST", "/receive/diagnostics", Some(b)).await;
        assert_eq!((got, v["error"]["code"].as_str()), (status, Some(code)));
    }
    let (got, v, _, _) = f
        .raw(
            "POST",
            "/receive/diagnostics",
            Some("http://evil.example"),
            Some(serde_json::to_vec(&body(false)).unwrap()),
            &[],
        )
        .await;
    assert_eq!(
        (got, v["error"]["code"].as_str()),
        (StatusCode::FORBIDDEN, Some("forbidden_origin"))
    );
    let (got, _, _, _) = f.call("GET", "/receive/diagnostics?x=1", None).await;
    assert_eq!(got, StatusCode::BAD_REQUEST);
    let (_, view, _, _) = f.call("GET", "/receive/diagnostics", None).await;
    assert_eq!(view["window_dump"], true);
    let (_, snapshot, _, _) = f.call("GET", "/receive", None).await;
    assert!(!snapshot.to_string().contains("zero_samples"));
    let _ = fs::remove_dir_all(&f.dir);
}
