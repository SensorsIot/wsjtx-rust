//! Original FSD 4.4/6.4/12.6 independent byte/math/state oracles. Cost 2, Windows PC; no hardware.
use super::*;
use std::cell::Cell;
thread_local! { static FAULT: Cell<Option<&'static str>> = const { Cell::new(None) }; }
pub(super) fn checkpoint(stage: &'static str) -> Result<()> {
    if FAULT.get() == Some(stage) {
        Err("storage_unavailable")
    } else {
        Ok(())
    }
}
struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let path =
            std::env::temp_dir().join(format!("wstx-recording-{}", profile::new_uuid().unwrap()));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
    fn recording(&self) -> Arc<Recording> {
        Recording::open(
            &self.0,
            "00000000-0000-4000-8000-000000000001".into(),
            profile::new_uuid().unwrap(),
        )
    }
    fn wave(&self, bytes: &[u8]) -> File {
        let path = self.0.join("fixture.wav");
        fs::write(&path, bytes).unwrap();
        File::open(path).unwrap()
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}
fn wav(samples: &[i16]) -> Vec<u8> {
    let length = u32::try_from(samples.len() * 2).unwrap();
    let mut b = Vec::from(*b"RIFF");
    b.extend((36 + length).to_le_bytes());
    b.extend(b"WAVEfmt ");
    b.extend(16u32.to_le_bytes());
    b.extend(1u16.to_le_bytes());
    b.extend(1u16.to_le_bytes());
    b.extend(12000u32.to_le_bytes());
    b.extend(24000u32.to_le_bytes());
    b.extend(2u16.to_le_bytes());
    b.extend(16u16.to_le_bytes());
    b.extend(b"data");
    b.extend(length.to_le_bytes());
    for value in samples {
        b.extend(value.to_le_bytes());
    }
    b
}
fn import(r: &Arc<Recording>, bytes: &[u8]) -> Result<String> {
    let generation = r.state.lock().unwrap().generation;
    let v = r.reserve(&r.profile, &r.boot, generation)?;
    let id = v["id"].as_str().unwrap();
    for (n, chunk) in bytes.chunks(2048).enumerate() {
        let offset = (n * 2048) as u64;
        r.begin_chunk(id, offset, bytes.len() as u64)?;
        r.chunk(id, offset, bytes.len() as u64, chunk.to_vec())?;
    }
    Ok(id.to_owned())
}
// Proves: CL-006-01, CL-006-02; TC-018-001, cost 2 on Windows.
#[test]
fn original_bytes_samples_blocks_and_restart_identity() {
    let f = Fixture::new();
    let r = f.recording();
    for count in [1, 2048, 4096, 4097, 1_440_000] {
        let endpoint = [-32768, -1, 0, 1, 32767];
        let samples: Vec<_> = (0..count).map(|n| endpoint[n % 5]).collect();
        let bytes = wav(&samples);
        let id = import(&r, &bytes).unwrap();
        assert_eq!(fs::read(r.path(&id, "wav")).unwrap(), bytes);
        let descriptor = Arc::new(SourceDescriptor {
            schema_version: 1,
            profile_id: r.profile.clone(),
            boot_id: r.boot.clone(),
            source_id: id.clone(),
            rate_hz: 12000,
            channel: "mono_real",
            total_frames: Some(count as u64),
            utc_anchor: None,
        });
        let mut source = SourceFile::open(&r.path(&id, "wav"), descriptor).unwrap();
        let mut position = 0;
        let mut eos = 0;
        while let Some(block) = source.next().unwrap() {
            assert_eq!(block.first_frame, position as u64);
            assert!(block.samples.len() <= 4096);
            assert!(!block.discontinuity);
            assert_eq!(block.source.source_id, id);
            for &actual in block.samples.iter() {
                assert_eq!(actual, f32::from(samples[position]) / 32768.0);
                position += 1;
            }
            if block.end_of_stream {
                eos += 1;
                assert_eq!(position, count);
            }
        }
        assert_eq!(position, count);
        assert_eq!(eos, 1);
        let restarted = f.recording();
        assert_ne!(restarted.boot, r.boot);
        assert_eq!(restarted.snapshot()["recording"]["id"], id);
        assert_eq!(restarted.snapshot()["generation"], 0);
        assert_eq!(restarted.snapshot()["recording"]["utc_anchor"], Value::Null);
    }
}
// Proves: CL-006-01, CL-006-04; TC-018-002, cost 2 on Windows.
#[test]
fn byte_level_riff_limits_and_rejection_table() {
    let f = Fixture::new();
    let valid = wav(&[0, 1, -1]);
    let mut cases: Vec<(Vec<u8>, &str)> = Vec::new();
    for offset in [0, 8, 12, 36] {
        let mut b = valid.clone();
        b[offset] = b'X';
        cases.push((b, "invalid_recording"));
    }
    for offset in [20, 22, 24, 34] {
        let mut b = valid.clone();
        b[offset] = 3;
        cases.push((b, "unsupported_audio"));
    }
    for offset in [4, 16, 28, 32, 40] {
        let mut b = valid.clone();
        b[offset] = 255;
        cases.push((b, "invalid_recording"));
    }
    for n in 0..valid.len() {
        cases.push((valid[..n].to_vec(), "invalid_recording"));
    }
    cases.push((wav(&[]), "invalid_recording"));
    cases.push((wav(&vec![0; 1_440_001]), "recording_limit"));
    for (b, expected) in cases {
        assert_eq!(
            validate(&mut f.wave(&b)).unwrap_err(),
            expected,
            "bytes {}",
            b.len()
        );
    }
    let mut ancillary = valid.clone();
    ancillary.splice(12..12, b"JUNK\x01\0\0\0Z\0".iter().copied());
    let size = (ancillary.len() - 8) as u32;
    ancillary[4..8].copy_from_slice(&size.to_le_bytes());
    assert_eq!(validate(&mut f.wave(&ancillary)).unwrap().frames, 3);
    let mut cap = valid.clone();
    let padding = FILE_LIMIT as usize - cap.len() - 8;
    cap.extend(b"JUNK");
    cap.extend((padding as u32).to_le_bytes());
    cap.resize(FILE_LIMIT as usize, 0);
    cap[4..8].copy_from_slice(&((FILE_LIMIT - 8) as u32).to_le_bytes());
    assert_eq!(validate(&mut f.wave(&cap)).unwrap().bytes, FILE_LIMIT);
    let mut many = valid;
    for _ in 0..63 {
        many.extend(b"JUNK\0\0\0\0");
    }
    let size = (many.len() - 8) as u32;
    many[4..8].copy_from_slice(&size.to_le_bytes());
    assert_eq!(validate(&mut f.wave(&many)).unwrap_err(), "recording_limit");
}
// Proves: CL-006-02, CL-006-04; TC-018-002/003, cost 2 on Windows.
#[test]
fn import_failures_keep_old_source_and_quarantine_until_real_release() {
    let f = Fixture::new();
    let r = f.recording();
    let bytes = wav(&[1, 2, 3]);
    let old = import(&r, &bytes).unwrap();
    for stage in [
        "append",
        "original_flush",
        "metadata",
        "manifest",
        "replace",
    ] {
        FAULT.set(Some(stage));
        assert_eq!(
            import(&r, &wav(&[4, 5, 6])).unwrap_err(),
            "storage_unavailable"
        );
        FAULT.set(None);
        assert_eq!(r.snapshot()["recording"]["id"], old);
        assert_eq!(fs::read(r.path(&old, "wav")).unwrap(), bytes);
        assert_eq!(f.recording().snapshot()["recording"]["id"], old);
    }
    let generation = r.state.lock().unwrap().generation;
    let reservation = r.reserve(&r.profile, &r.boot, generation).unwrap();
    let id = reservation["id"].as_str().unwrap();
    r.begin_chunk(id, 0, 100).unwrap();
    assert_eq!(r.begin_chunk(id, 0, 100).unwrap_err(), "state_conflict");
    r.cancel_import(id).unwrap();
    {
        let mut s = r.state.lock().unwrap();
        s.import.as_mut().unwrap().cleanup_started = Some(Instant::now() - Duration::from_secs(6));
    }
    r.tick();
    assert_eq!(r.snapshot()["storage_error"], "storage_unavailable");
    assert_eq!(
        r.reserve(&r.profile, &r.boot, generation + 1).unwrap_err(),
        "storage_unavailable"
    );
    // Resume the held append after the watchdog has changed cancelling -> failed.
    // Its old token must still be unable to validate or commit.
    assert_eq!(
        r.chunk(id, 0, 100, vec![0, 0]).unwrap_err(),
        "storage_unavailable"
    );
    assert_eq!(r.snapshot()["storage_error"], Value::Null);
    assert!(!r.state.lock().unwrap().import.as_ref().unwrap().worker);
}
// Proves: CL-006-02, CL-006-04; TC-018-003 held worker failure + EOS vector, cost 2 Windows.
#[test]
fn processing_failure_with_eos_cannot_complete_before_or_after_release() {
    let f = Fixture::new();
    let r = f.recording();
    let id = import(&r, &wav(&[0; 2048])).unwrap();
    let meta = r.state.lock().unwrap().recording.clone().unwrap();
    let job = Job {
        id: profile::new_uuid().unwrap(),
        source_id: id,
        generation: 2,
        kind: "spectrum",
        state: "running",
        processed_frames: meta.frames,
        error: None,
        cancel: Arc::new(AtomicBool::new(false)),
    };
    {
        let mut s = r.state.lock().unwrap();
        s.generation = 2;
        s.job = Some(job.clone());
    }
    // Failure is held in worker result while source completion/progress has already arrived.
    let processing_result = Err("recording_unavailable");
    assert_eq!(r.snapshot()["job"]["state"], "running");
    assert_eq!(r.reserve(&r.profile, &r.boot, 2).unwrap_err(), "busy");
    r.release(job, meta, processing_result);
    assert_eq!(r.snapshot()["job"]["state"], "failed");
    assert_ne!(r.snapshot()["job"]["state"], "completed");
    let current = r.snapshot()["job"].clone();
    let obsolete = Job {
        id: profile::new_uuid().unwrap(),
        source_id: profile::new_uuid().unwrap(),
        generation: 1,
        kind: "spectrum",
        state: "running",
        processed_frames: 0,
        error: None,
        cancel: Arc::new(AtomicBool::new(false)),
    };
    let metadata = Metadata {
        schema_version: 1,
        recording_id: obsolete.source_id.clone(),
        file_bytes: 44,
        frames: 1,
        rate_hz: 12000,
    };
    r.release(obsolete, metadata, Ok(()));
    assert_eq!(r.snapshot()["job"], current);
}

// Proves: CL-006-02; TC-018-002, manifest is authoritative even when final HTTP outcome is lost.
#[test]
fn post_commit_failure_never_reverts_new_original_on_restart() {
    let f = Fixture::new();
    let r = f.recording();
    let old = import(&r, &wav(&[1])).unwrap();
    FAULT.set(Some("after_replace"));
    assert_eq!(import(&r, &wav(&[2])).unwrap_err(), "storage_unavailable");
    FAULT.set(None);
    let committed = r.snapshot()["recording"]["id"].as_str().unwrap().to_owned();
    assert_ne!(committed, old);
    assert_eq!(fs::read(r.path(&committed, "wav")).unwrap(), wav(&[2]));
    assert_eq!(f.recording().snapshot()["recording"]["id"], committed);
}

// Proves: CL-006-02/04; TC-018-002, reservation/idle/total timeout and failed real cleanup quarantine.
#[test]
fn deadlines_release_only_after_cleanup_and_startup_reconciles_quarantine() {
    let f = Fixture::new();
    let r = f.recording();
    let old = import(&r, &wav(&[1])).unwrap();
    for kind in ["reservation", "idle", "total"] {
        let generation = r.state.lock().unwrap().generation;
        let op = r.reserve(&r.profile, &r.boot, generation).unwrap();
        let id = op["id"].as_str().unwrap();
        if kind != "reservation" {
            r.begin_chunk(id, 0, 100).unwrap();
            r.chunk(id, 0, 100, vec![0, 0]).unwrap();
        }
        {
            let mut s = r.state.lock().unwrap();
            let i = s.import.as_mut().unwrap();
            if kind == "total" {
                i.started = Instant::now() - Duration::from_secs(1801);
            } else {
                i.touched = Instant::now()
                    - Duration::from_secs(if kind == "reservation" { 31 } else { 16 });
            }
        }
        r.tick();
        for _ in 0..100 {
            if !r.state.lock().unwrap().import.as_ref().unwrap().worker {
                break;
            }
            std::thread::sleep(Duration::from_millis(2));
        }
        assert_eq!(r.import_view(id).unwrap()["error"], "upload_timeout");
        assert_eq!(r.begin_chunk(id, 0, 100).unwrap_err(), "upload_timeout");
        assert_eq!(r.snapshot()["recording"]["id"], old);
    }
    let generation = r.state.lock().unwrap().generation;
    let op = r.reserve(&r.profile, &r.boot, generation).unwrap();
    let id = op["id"].as_str().unwrap();
    r.begin_chunk(id, 0, 100).unwrap();
    r.chunk(id, 0, 100, vec![0, 0]).unwrap();
    {
        let mut s = r.state.lock().unwrap();
        let i = s.import.as_mut().unwrap();
        i.state = "cancelling";
        i.error = Some("cancelled");
        i.worker = true;
    }
    FAULT.set(Some("cleanup"));
    r.finish_cleanup(id.to_owned());
    assert_eq!(r.snapshot()["storage_error"], "storage_unavailable");
    assert!(r.path(id, "wav").exists());
    assert!(r.state.lock().unwrap().import.as_ref().unwrap().worker);
    assert_eq!(
        f.recording().snapshot()["storage_error"],
        "storage_unavailable"
    );
    FAULT.set(None);
    let restarted = f.recording();
    assert_eq!(restarted.snapshot()["storage_error"], Value::Null);
    assert_eq!(restarted.snapshot()["recording"]["id"], old);
    assert!(!r.path(id, "wav").exists());
}
fn dft(samples: &[f32], k: usize) -> f64 {
    let mut re = 0.0;
    let mut im = 0.0;
    for (n, &x) in samples.iter().enumerate() {
        let window = (1.0 - (std::f64::consts::TAU * n as f64 / 2048.0).cos()) / 2.0;
        let angle = std::f64::consts::TAU * k as f64 * n as f64 / 2048.0;
        re += f64::from(x) * window * angle.cos();
        im -= f64::from(x) * window * angle.sin();
    }
    re.hypot(im) * (if k == 0 { 1.0 } else { 2.0 }) / 1024.0
}
// Proves: CL-006-03; TC-010-001, independently computed DFT and analytic tones, cost 2 Windows.
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

// Proves: CL-006-03/04; TC-010-001, actual worker row boundary/right padding against original DFT.
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
    {
        let resources = r.resources.lock().unwrap();
        assert_eq!(resources.active_workers, 0);
        assert_eq!(resources.peak_workers, 1);
        assert_eq!(resources.peak_blocks, 2);
    }
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

// Proves: CL-006-01/02; TC-018-002 review regression; readable truncation differs from OS read failure.
#[test]
fn parser_preserves_non_eof_os_read_errors() {
    let f = Fixture::new();
    let mut valid = f.wave(&wav(&[0]));
    assert!(validate(&mut valid).is_ok());
    drop(valid);
    let mut write_only = fs::OpenOptions::new()
        .write(true)
        .open(f.0.join("fixture.wav"))
        .unwrap();
    assert_eq!(
        validate(&mut write_only).unwrap_err(),
        "storage_unavailable"
    );
    drop(write_only);
    assert_eq!(
        validate(&mut f.wave(b"RIFF")).unwrap_err(),
        "invalid_recording"
    );
}

// Proves: CL-006-02/04; TC-018-003 review regression; worker preempted across a pacing deadline releases the slot.
#[test]
fn crossing_pacing_deadline_completes_and_releases_worker_slot() {
    let f = Fixture::new();
    let r = f.recording();
    let id = import(&r, &wav(&[0; 1200])).unwrap();
    r.resources.lock().unwrap().cross_deadline = true;
    let generation = r.snapshot()["generation"].as_u64().unwrap();
    r.replay(&r.profile, &r.boot, generation, &id).unwrap();
    let began = Instant::now();
    while r.snapshot()["job"]["state"] == "running" {
        assert!(began.elapsed() < Duration::from_secs(2));
        std::thread::sleep(Duration::from_millis(5));
    }
    assert_eq!(r.snapshot()["job"]["state"], "completed");
    let resources = r.resources.lock().unwrap();
    assert_eq!(resources.active_workers, 0);
    assert_eq!(resources.deadline_crossings, 1);
    drop(resources);
    assert!(r.reserve(&r.profile, &r.boot, generation + 1).is_ok());
}
