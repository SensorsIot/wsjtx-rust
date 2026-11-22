use super::*;

// Runs at cost 2 on Windows.
// Proves: TC-018-001
#[test]
fn original_bytes_samples_blocks_and_restart_identity() {
    let f = Fixture::new();
    let r = f.recording();
    let rate = recording_limit("rateHz");
    for count in [1, 2048, 4096, 4097, recording_limit("importMaxFrames")] {
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
            rate_hz: rate.try_into().unwrap(),
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
        assert_eq!(restarted.snapshot()["recording"]["rate_hz"], rate);
        assert_eq!(restarted.snapshot()["recording"]["frames"], count);
    }
}

// Runs at cost 2 on Windows.
// Proves: TC-018-002
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
    let file_limit = recording_limit("fileBytes");
    let chunk_limit = recording_limit("importMaxRiffChunks");
    cases.push((
        wav(&vec![0; recording_limit("importMaxFrames") + 1]),
        "recording_limit",
    ));
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
    // A file of exactly the file cap is accepted; one byte more is refused.
    let mut cap = valid.clone();
    let padding = file_limit - cap.len() - 8;
    cap.extend(b"JUNK");
    cap.extend((padding as u32).to_le_bytes());
    cap.resize(file_limit, 0);
    cap[4..8].copy_from_slice(&((file_limit - 8) as u32).to_le_bytes());
    assert_eq!(
        validate(&mut f.wave(&cap)).unwrap().bytes,
        file_limit as u64
    );
    let mut over = cap;
    over.push(0);
    over[4..8].copy_from_slice(&((file_limit - 7) as u32).to_le_bytes());
    assert_eq!(validate(&mut f.wave(&over)).unwrap_err(), "recording_limit");
    // fmt and data plus ancillary chunks: exactly the chunk cap is accepted, one more is not.
    let chunks = |total: usize| {
        let mut many = valid.clone();
        for _ in 0..total - 2 {
            many.extend(b"JUNK\0\0\0\0");
        }
        let size = (many.len() - 8) as u32;
        many[4..8].copy_from_slice(&size.to_le_bytes());
        many
    };
    assert_eq!(
        validate(&mut f.wave(&chunks(chunk_limit))).unwrap().frames,
        3
    );
    assert_eq!(
        validate(&mut f.wave(&chunks(chunk_limit + 1))).unwrap_err(),
        "recording_limit"
    );
}

// Runs at cost 2 on Windows.
// Proves: TC-018-002
#[test]
fn import_failures_keep_old_source_and_quarantine_until_real_release() {
    let f = Fixture::new();
    let r = f.recording();
    let bytes = wav(&[1, 2, 3]);
    let old = import(&r, &bytes).unwrap();
    let scope = FaultScope::ArmingThread;
    for (_stage, fault) in [
        ("append", Fault::fail(Step::Write, scope)),
        ("original_flush", Fault::fail(Step::Flush, scope)),
        // The metadata file is the second create of the import, after the append open.
        ("metadata", Fault::fail(Step::Create, scope).after(1)),
        ("manifest", Fault::fail(Step::Create, scope).after(2)),
        ("replace", Fault::fail(Step::Replace, scope)),
    ] {
        f.1.arm(fault);
        assert_eq!(
            import(&r, &wav(&[4, 5, 6])).unwrap_err(),
            "storage_unavailable"
        );
        f.1.disarm();
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

// The manifest is authoritative even when the final HTTP outcome is lost.
// Proves: TC-018-002
#[test]
fn post_commit_failure_never_reverts_new_original_on_restart() {
    let f = Fixture::new();
    let r = f.recording();
    let old = import(&r, &wav(&[1])).unwrap();
    // The first listing of the import is the cleanup after the manifest replace.
    f.1.arm(Fault::fail(Step::List, FaultScope::ArmingThread));
    assert_eq!(import(&r, &wav(&[2])).unwrap_err(), "storage_unavailable");
    f.1.disarm();
    let committed = r.snapshot()["recording"]["id"].as_str().unwrap().to_owned();
    assert_ne!(committed, old);
    assert_eq!(fs::read(r.path(&committed, "wav")).unwrap(), wav(&[2]));
    assert_eq!(f.recording().snapshot()["recording"]["id"], committed);
}

// Reservation/idle/total timeout and failed real cleanup quarantine.
// Proves: TC-018-002
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
    f.1.arm(Fault::fail(Step::List, FaultScope::ArmingThread));
    r.finish_cleanup(id.to_owned());
    assert_eq!(r.snapshot()["storage_error"], "storage_unavailable");
    assert!(r.path(id, "wav").exists());
    assert!(r.state.lock().unwrap().import.as_ref().unwrap().worker);
    assert_eq!(
        f.recording().snapshot()["storage_error"],
        "storage_unavailable"
    );
    f.1.disarm();
    let restarted = f.recording();
    assert_eq!(restarted.snapshot()["storage_error"], Value::Null);
    assert_eq!(restarted.snapshot()["recording"]["id"], old);
    assert!(!r.path(id, "wav").exists());
}

// A readable truncation differs from an OS read failure.
// Proves: TC-018-002
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

// An absent manifest never authorizes guessing which UUID original to delete.
#[test]
fn absent_manifest_artifacts_are_unavailable_and_retained_until_valid_commit() {
    let f = Fixture::new();
    let empty = f.recording();
    assert_eq!(empty.snapshot()["source_error"], Value::Null);
    assert_eq!(empty.snapshot()["recording"], Value::Null);
    // These bytes are indistinguishable from a pre-commit crash or the loss of a committed manifest.
    let id = profile::new_uuid().unwrap();
    let bytes = wav(&[1]);
    fs::write(empty.path(&id, "wav"), &bytes).unwrap();
    write_json(
        &profile::Disk,
        &empty.path(&id, "json"),
        &Metadata {
            schema_version: 1,
            recording_id: id.clone(),
            file_bytes: bytes.len() as u64,
            frames: 1,
            rate_hz: 12000,
        },
    )
    .unwrap();
    let recovered = f.recording();
    assert_eq!(
        recovered.snapshot()["source_error"],
        "recording_unavailable"
    );
    assert_eq!(fs::read(recovered.path(&id, "wav")).unwrap(), bytes);
    assert!(recovered.path(&id, "json").exists());
    let replacement = import(&recovered, &wav(&[2])).unwrap();
    assert_eq!(recovered.snapshot()["source_error"], Value::Null);
    assert_eq!(recovered.snapshot()["recording"]["id"], replacement);
    assert!(!recovered.path(&id, "wav").exists());
}

// Proves: TC-018-002
#[test]
fn chunk_order_count_and_fmt_faults_are_refused() {
    let f = Fixture::new();
    let fmt = wav(&[])[20..36].to_vec();
    let data = vec![1, 0, 2, 0];
    let with = |extra: &[u8]| [fmt.as_slice(), extra].concat();
    let mut other = fmt.clone();
    other[0] = 3;
    for chunks in [
        vec![(b"fmt ", fmt.clone()), (b"data", data.clone())],
        vec![(b"fmt ", with(&[0, 0])), (b"data", data.clone())],
    ] {
        assert_eq!(validate(&mut f.wave(&riff(&chunks))).unwrap().frames, 2);
    }
    for (chunks, expected) in [
        (
            vec![
                (b"fmt ", fmt.clone()),
                (b"fmt ", fmt.clone()),
                (b"data", data.clone()),
            ],
            "invalid_recording",
        ),
        (
            vec![(b"data", data.clone()), (b"fmt ", fmt.clone())],
            "invalid_recording",
        ),
        (vec![(b"fmt ", fmt.clone())], "invalid_recording"),
        (
            vec![
                (b"fmt ", fmt.clone()),
                (b"data", data.clone()),
                (b"data", data.clone()),
            ],
            "invalid_recording",
        ),
        (
            vec![(b"fmt ", fmt.clone()), (b"data", vec![1, 0, 2])],
            "invalid_recording",
        ),
        (
            vec![(b"fmt ", with(&[1, 0])), (b"data", data.clone())],
            "invalid_recording",
        ),
        (
            vec![(b"fmt ", with(&[0; 4])), (b"data", data.clone())],
            "unsupported_audio",
        ),
        (
            vec![(b"fmt ", other.clone()), (b"data", data.clone())],
            "unsupported_audio",
        ),
        // Another form and a fault of the build: the fault decides.
        (vec![(b"fmt ", other.clone())], "invalid_recording"),
    ] {
        assert_eq!(
            validate(&mut f.wave(&riff(&chunks))).unwrap_err(),
            expected,
            "{:?}",
            chunks.iter().map(|(n, b)| (n, b.len())).collect::<Vec<_>>()
        );
    }
}

// Proves: TC-018-002
#[test]
fn a_cancelled_import_keeps_the_stored_recording() {
    let f = Fixture::new();
    let r = f.recording();
    let bytes = wav(&[1, 2, 3]);
    let old = import(&r, &bytes).unwrap();
    let generation = r.state.lock().unwrap().generation;
    let reserved = r.reserve(&r.profile, &r.boot, generation).unwrap();
    let id = reserved["id"].as_str().unwrap().to_owned();
    r.begin_chunk(&id, 0, 100).unwrap();
    r.chunk(&id, 0, 100, vec![0, 0]).unwrap();
    assert_eq!(r.cancel_import(&id).unwrap()["state"], "cancelling");
    let deadline = Instant::now() + Duration::from_secs(2);
    while r.import_view(&id).unwrap()["state"] != "cancelled" {
        assert!(Instant::now() < deadline, "the cancel did not end");
        std::thread::sleep(Duration::from_millis(2));
    }
    assert!(!r.path(&id, "wav").exists());
    assert_eq!(r.snapshot()["recording"]["id"], old);
    assert_eq!(fs::read(r.path(&old, "wav")).unwrap(), bytes);
    assert_eq!(f.recording().snapshot()["recording"]["id"], old);
}

// Proves: TC-018-002
#[test]
fn import_commands_it_does_not_carry_out_are_refused_and_change_nothing() {
    let f = Fixture::new();
    let r = f.recording();
    let unknown = profile::new_uuid().unwrap();
    assert_eq!(r.import_view(&unknown).unwrap_err(), "not_found");
    assert_eq!(r.begin_chunk(&unknown, 0, 100).unwrap_err(), "not_found");
    assert_eq!(r.cancel_import(&unknown).unwrap_err(), "not_found");
    // ReserveImport while a live job has not given up what it held.
    r.state.lock().unwrap().live_owner_released = false;
    assert_eq!(r.reserve(&r.profile, &r.boot, 0).unwrap_err(), "busy");
    r.state.lock().unwrap().live_owner_released = true;
    // ReserveImport while a job has not ended.
    r.state.lock().unwrap().job = Some(Job {
        id: profile::new_uuid().unwrap(),
        source_id: Some(profile::new_uuid().unwrap()),
        generation: 0,
        kind: "spectrum",
        state: "running",
        processed_frames: 0,
        error: None,
        cancel: Arc::new(AtomicBool::new(false)),
    });
    assert_eq!(r.reserve(&r.profile, &r.boot, 0).unwrap_err(), "busy");
    r.state.lock().unwrap().job = None;
    assert_eq!(r.snapshot()["import"], Value::Null);
    assert_eq!(r.snapshot()["generation"], 0);
    // ImportChunk with another total than its first part.
    let reserved = r.reserve(&r.profile, &r.boot, 0).unwrap();
    let id = reserved["id"].as_str().unwrap().to_owned();
    r.begin_chunk(&id, 0, 100).unwrap();
    r.chunk(&id, 0, 100, vec![0, 0]).unwrap();
    let before = r.import_view(&id).unwrap();
    assert_eq!(r.begin_chunk(&id, 2, 200).unwrap_err(), "state_conflict");
    assert_eq!(r.import_view(&id).unwrap(), before);
    // CancelImport of an import that commits.
    r.state.lock().unwrap().import.as_mut().unwrap().state = "committing";
    assert_eq!(r.cancel_import(&id).unwrap_err(), "invalid_state");
    r.state.lock().unwrap().import.as_mut().unwrap().state = "receiving";
    r.cancel_import(&id).unwrap();
    let deadline = Instant::now() + Duration::from_secs(2);
    while r.import_view(&id).unwrap()["state"] != "cancelled" {
        assert!(Instant::now() < deadline, "the cancel did not end");
        std::thread::sleep(Duration::from_millis(2));
    }
    // ReserveImport while the files of an import that ended are still being removed.
    r.state.lock().unwrap().import.as_mut().unwrap().worker = true;
    let generation = r.state.lock().unwrap().generation;
    assert_eq!(
        r.reserve(&r.profile, &r.boot, generation).unwrap_err(),
        "busy"
    );
    r.state.lock().unwrap().import.as_mut().unwrap().worker = false;
    // ImportChunk to an import that has ended.
    let bytes = wav(&[1, 2]);
    let done = import(&r, &bytes).unwrap();
    let total = bytes.len() as u64;
    let view = r.import_view(&done).unwrap();
    assert_eq!(view["state"], "completed");
    assert_eq!(
        r.begin_chunk(&done, total, total).unwrap_err(),
        "invalid_state"
    );
    assert_eq!(r.import_view(&done).unwrap(), view);
}
