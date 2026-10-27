//! Original FSD 4.4/6.4/12.6 independent byte/math/state oracles. Cost 2, Windows PC; no hardware.
use super::*;
use std::cell::Cell;

// Proves: CL-006-03/04; TC-010-008 shared history, actual eviction and stale publication.
#[test]
fn detailed_history_retains_eight_shared_events_and_only_actual_eviction() {
    let fixture = Fixture::new();
    let recording = fixture.recording();
    let (job, _) = live_ring(&recording);
    let event = |sequence| {
        json!({"v":1,"type":"spectrum.detail.frame","data":{
        "boot_id":recording.boot,"source_id":job.source_id,"job_id":job.id,"generation":job.generation,
        "sequence":sequence,"first_frame":sequence*2400,"end_frame":(sequence+1)*2400,
        "levels_b64":STANDARD.encode(vec![sequence as u8;1024])}})
    };
    let mut state = recording.state.lock().unwrap();
    let identity = state.detail_identity(&recording.boot);
    assert!(state.detail_candidate(0, &identity).is_none());
    state.publish_detail(event(4), &recording.boot);
    assert_eq!(state.detail_history.len(), 1);
    for sequence in [6, 7, 8] {
        state.publish_detail(event(sequence), &recording.boot);
    }
    assert_eq!(state.detail_evicted, None);
    assert_eq!(state.detail_candidate(5, &identity).unwrap().sequence, 6);
    let shared = state.detail_frame.clone().unwrap();
    assert!(Arc::ptr_eq(&shared, state.detail_history.back().unwrap()));
    for sequence in 9..=12 {
        state.publish_detail(event(sequence), &recording.boot);
    }
    assert_eq!(state.detail_history.len(), 8);
    assert!(
        state
            .detail_history
            .iter()
            .map(|f| f.text.len())
            .sum::<usize>()
            <= 16384
    );
    state.publish_detail(event(13), &recording.boot);
    assert_eq!(state.detail_evicted, Some(4));
    assert_eq!(state.detail_candidate(5, &identity).unwrap().sequence, 6);
    state.publish_detail(event(14), &recording.boot);
    assert_eq!(state.detail_evicted, Some(6));
    assert_eq!(state.detail_candidate(5, &identity).unwrap().sequence, 14);
    assert!(state.detail_candidate(15, &identity).is_none());
    for key in ["boot_id", "source_id", "job_id", "generation"] {
        let mut stale = event(15);
        stale["data"][key] = json!("obsolete");
        state.publish_detail(stale, &recording.boot);
    }
    state.publish_detail(event(14), &recording.boot);
    assert_eq!(state.detail_history.len(), 8);
    assert_eq!(state.detail_frame.as_ref().unwrap().sequence, 14);
    assert!(
        state
            .detail_candidate(0, &json!("wrong identity"))
            .is_none()
    );
    state.clear_detail();
    assert!(state.detail_history.is_empty());
    assert!(state.detail_frame.is_none());
    assert_eq!(state.detail_evicted, None);
    job.cancel.store(true, Ordering::Release);
    state.publish_detail(event(15), &recording.boot);
    assert!(state.detail_history.is_empty());
}

thread_local! { static FAULT: Cell<Option<&'static str>> = const { Cell::new(None) }; }

fn live_ring(r: &Recording) -> (Job, decoder::Decode) {
    let source = Arc::new(SourceDescriptor {
        schema_version: 1,
        profile_id: r.profile.clone(),
        boot_id: r.boot.clone(),
        source_id: profile::new_uuid().unwrap(),
        rate_hz: 12000,
        channel: "mono_real",
        total_frames: None,
        utc_anchor: None,
    });
    let job = Job {
        id: profile::new_uuid().unwrap(),
        source_id: Some(source.source_id.clone()),
        generation: 1,
        kind: "live",
        state: "running",
        processed_frames: 180000,
        error: None,
        cancel: Arc::new(AtomicBool::new(false)),
    };
    let mut s = r.state.lock().unwrap();
    s.generation = 1;
    s.job = Some(job.clone());
    s.live = Some(LiveState {
        mode: "ft8",
        audio: audio::AudioStatus {
            state: audio::AudioState::Running,
            error: None,
            retry_after_ms: None,
        },
        device_id: "isolated-test".into(),
        source: Some(source),
        timing: None,
        next_frame: 180000,
        records: VecDeque::new(),
        record_bytes: 0,
        first_sequence: 0,
        next_sequence: 0,
        search_limited: false,
        last_overrun: None,
        publication_error: None,
    });
    let decoded = decoder::Decode {
        payload: decoder::unpack(&[0; 77]),
        start_frame: 6000,
        frequency_hz: 1000.0,
        snr_db: None,
    };
    (job, decoded)
}

// Proves: CL-008-03; TC-009-004 live ring2047/2048/2049 and explicit cursors.
#[test]
fn live_results_evict_oldest_and_never_restart_sequence() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (job, decoded) = live_ring(&r);
    for sequence in 0..2054 {
        r.publish_decode(&job, &decoded).unwrap();
        let s = r.state.lock().unwrap();
        let l = s.live.as_ref().unwrap();
        assert_eq!(l.next_sequence, sequence + 1);
        assert_eq!(l.records.len(), ((sequence + 1) as usize).min(2048));
        assert_eq!(l.first_sequence, (sequence + 1).saturating_sub(2048));
    }
    let source = job.source_id.as_deref().unwrap();
    let expired = r.receive_results(source, &job.id, 1, 5, 1).unwrap();
    assert_eq!(
        expired,
        json!({"v":1,"error":{"code":"cursor_expired","message":"Result history expired"},"first_sequence":6,"next_sequence":2054})
    );
    let page = r.receive_results(source, &job.id, 1, 7, 1).unwrap();
    assert_eq!(page["records"][0]["sequence"], 7);
    assert_eq!(page["next"], 8);
    assert_eq!(page["more"], true);
    assert!(serde_json::to_vec(&page).unwrap().len() <= 3072);
    let end = r.receive_results(source, &job.id, 1, 2054, 16).unwrap();
    assert_eq!(end["records"], json!([]));
    assert_eq!(end["more"], false);
    assert_eq!(
        r.receive_results(source, &job.id, 1, 2055, 1),
        Err("invalid_request")
    );
    r.state.lock().unwrap().live.as_mut().unwrap().source = None;
    assert_eq!(
        r.receive_results(source, &job.id, 1, 7, 1),
        Err("not_found")
    );
}

// Proves: CL-008-03; TC-009-004 seeded byte/safe-counter bounds and invalid/stale publication.
#[test]
fn live_publication_is_atomic_at_byte_counter_and_context_boundaries() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (job, mut decoded) = live_ring(&r);
    r.publish_decode(&job, &decoded).unwrap();
    {
        let mut s = r.state.lock().unwrap();
        let l = s.live.as_mut().unwrap();
        // Seed the charged retained history at its exact byte cap.
        l.records.front_mut().unwrap().1 = 2 * 1024 * 1024;
        l.record_bytes = 2 * 1024 * 1024;
    }
    r.publish_decode(&job, &decoded).unwrap();
    {
        let s = r.state.lock().unwrap();
        let l = s.live.as_ref().unwrap();
        assert_eq!(l.first_sequence, 1);
        assert_eq!(l.next_sequence, 2);
        assert_eq!(l.records.len(), 1);
        assert_eq!(l.record_bytes, l.records[0].1);
    }
    decoded.frequency_hz = f64::NAN;
    assert_eq!(
        r.publish_decode(&job, &decoded),
        Err(decoder::DecodeError::DecodeLimit)
    );
    assert_eq!(
        r.state.lock().unwrap().live.as_ref().unwrap().next_sequence,
        2
    );
    let (job, decoded) = live_ring(&r);
    {
        let mut s = r.state.lock().unwrap();
        let l = s.live.as_mut().unwrap();
        l.first_sequence = source::MAX_COUNTER;
        l.next_sequence = source::MAX_COUNTER;
    }
    assert_eq!(
        r.publish_decode(&job, &decoded),
        Err(decoder::DecodeError::DecodeLimit)
    );
    assert_eq!(
        r.state
            .lock()
            .unwrap()
            .live
            .as_ref()
            .unwrap()
            .publication_error,
        Some("counter_exhausted")
    );
    let (job, decoded) = live_ring(&r);
    r.state.lock().unwrap().job.as_mut().unwrap().id = profile::new_uuid().unwrap();
    assert_eq!(
        r.publish_decode(&job, &decoded),
        Err(decoder::DecodeError::Cancelled)
    );
    assert_eq!(
        r.state.lock().unwrap().live.as_ref().unwrap().next_sequence,
        0
    );
}

// Proves: CL-008-02; TC-009-004 source clock metadata never invents external accuracy.
#[test]
fn live_clock_filetime_mapping_handles_epoch_leap_and_range() {
    assert_eq!(
        utc_from_filetime(116444736000000000).as_deref(),
        Some("1970-01-01T00:00:00.0000000Z")
    );
    assert_eq!(
        utc_from_filetime(132274080001234567).as_deref(),
        Some("2020-02-29T00:00:00.1234567Z")
    );
    assert!(utc_from_filetime(0).is_none());
    assert!(utc_from_filetime(u64::MAX).is_none());
}

// Proves: CL-008-02/03/05; TC-009-004 actual provider epoch and owner identity.
#[test]
fn live_manager_rotates_unknown_epoch_before_ack_and_rejects_old_stop_results() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (job, decoded) = live_ring(&r);
    let (mut input, queue) = crate::receive_http_tests::Input::queued();
    input.start().unwrap();
    let mut worker = LiveWorker::new(r.clone(), job, Box::new(input), "ft8");
    // Initial provider ACK keeps the admitted job/gen; no made-up source ID.
    worker.epoch_seen = false;
    assert!(queue.push(&[], 1024, 0, 0, audio::SILENT | audio::TIMESTAMP_ERROR));
    assert!(worker.step().unwrap().is_none());
    let first_job = worker.job.clone();
    assert!(worker.window.is_some());
    assert!(worker.reset);
    worker.reset = false;
    for _ in 0..4 {
        worker.step().unwrap();
    }
    let old_source = first_job.source_id.clone().unwrap();
    r.publish_decode(
        &first_job,
        &decoder::Decode {
            start_frame: 0,
            ..decoded.clone()
        },
    )
    .unwrap();
    r.publish_latest_decode(&first_job, (0, 224), 0, false)
        .unwrap();
    assert_eq!(r.receive_snapshot()["job"]["latest_decode"]["id"], 1);
    // A marked measured gap resets private analysis but keeps source/job/gen.
    assert!(queue.push(
        &[],
        1024,
        48000,
        0,
        audio::SILENT | audio::DATA_DISCONTINUITY
    ));
    worker.step().unwrap();
    assert!(worker.reset);
    assert!(
        r.receive_snapshot()["job"]["latest_decode"].is_null(),
        "measured gap invalidates previous period view"
    );
    r.publish_latest_decode(&first_job, (12000, 12224), 1, false)
        .unwrap();
    assert_eq!(
        r.receive_snapshot()["job"]["latest_decode"]["id"],
        2,
        "gap must not reuse descriptor identity"
    );
    assert_eq!(worker.job.id, first_job.id);
    assert_eq!(worker.job.generation, first_job.generation);
    assert_eq!(
        r.state.lock().unwrap().live.as_ref().unwrap().records.len(),
        1
    );
    // An invalid packet is an actual unknown-loss epoch in PacketQueue/LiveSource.
    assert!(!queue.push(&[], 8193, 49024, 0, audio::SILENT));
    assert!(queue.push(&[], 1024, 49024, 0, audio::SILENT));
    worker.step().unwrap();
    assert_ne!(worker.job.id, first_job.id);
    assert!(
        r.receive_snapshot()["job"]["latest_decode"].is_null(),
        "unknown epoch clears descriptor"
    );
    assert_eq!(
        r.state.lock().unwrap().decode_counter,
        0,
        "new epoch restarts descriptor counter"
    );
    assert_ne!(worker.job.source_id, first_job.source_id);
    assert_eq!(worker.job.generation, first_job.generation + 1);
    assert_eq!(
        r.state.lock().unwrap().live.as_ref().unwrap().next_sequence,
        0
    );
    assert_eq!(
        r.receive_results(&old_source, &first_job.id, first_job.generation, 0, 1),
        Err("not_found")
    );
    assert_eq!(
        r.receive_stop(&r.profile, &r.boot, first_job.generation, &first_job.id),
        Err("state_conflict")
    );
    assert_eq!(
        r.publish_decode(&first_job, &decoded),
        Err(decoder::DecodeError::Cancelled)
    );
    worker.input.request_stop();
    assert_eq!(worker.input.status().state, audio::AudioState::Closed);
}

// Proves: CL-008-03; TC-009-004 resource release precedes terminal publication.
#[test]
fn live_terminal_is_unobservable_until_actual_input_drop_releases() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (mut input, _) = crate::receive_http_tests::Input::queued();
    let (entered, released) = input.block_release();
    let snapshot = r
        .receive_start_input(
            &r.profile,
            &r.boot,
            0,
            "native-queue-fixture".into(),
            "ft8",
            Box::new(input),
        )
        .unwrap();
    let generation = snapshot["generation"].as_u64().unwrap();
    let id = snapshot["job"]["id"].as_str().unwrap();
    r.receive_stop(&r.profile, &r.boot, generation, id).unwrap();
    let deadline = Instant::now() + Duration::from_secs(1);
    while !entered.load(Ordering::Acquire) && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(1));
    }
    let observed = r.receive_snapshot();
    let admission = r.reserve(&r.profile, &r.boot, generation);
    // Release before assertions so even a red candidate cannot strand the fixture.
    released.store(true, Ordering::Release);
    assert!(entered.load(Ordering::Acquire));
    assert_eq!(observed["job"]["state"], "cancelling");
    assert_eq!(admission, Err("busy"));
    let deadline = Instant::now() + Duration::from_secs(1);
    while r.receive_snapshot()["job"]["state"] != "cancelled" && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(1));
    }
    assert_eq!(r.receive_snapshot()["job"]["state"], "cancelled");
}

// Proves: CL-008-03; TC-009-004 a refused OS worker cannot strand station admission.
#[test]
fn live_worker_spawn_failure_releases_admission_without_reusing_generation() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    r.resources.lock().unwrap().fail_live_spawn = true;
    let (input, _) = crate::receive_http_tests::Input::queued();
    assert_eq!(
        r.receive_start_input(
            &r.profile,
            &r.boot,
            0,
            "native-queue-fixture".into(),
            "ft8",
            Box::new(input)
        ),
        Err("audio_unavailable")
    );
    let snapshot = r.receive_snapshot();
    assert_eq!(snapshot["generation"], 1);
    assert_eq!(snapshot["job"]["state"], "failed");
    assert_eq!(snapshot["audio"]["state"], "closed");
    assert_eq!(
        r.receive_context(&r.profile, &r.boot, 0),
        Err("state_conflict")
    );
    let reservation = r.reserve(&r.profile, &r.boot, 1).unwrap();
    assert_eq!(reservation["generation"], 2);
}

// Proves: CL-008-03; TC-009-004 a failed fresh source identity cannot orphan the old owner.
#[test]
fn live_second_epoch_source_uuid_failure_releases_original_admission() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (input, queue) = crate::receive_http_tests::Input::queued();
    r.receive_start_input(
        &r.profile,
        &r.boot,
        0,
        "native-queue-fixture".into(),
        "ft8",
        Box::new(input),
    )
    .unwrap();
    assert!(queue.push(&[], 1024, 0, 0, audio::SILENT));
    let deadline = Instant::now() + Duration::from_secs(1);
    while r.receive_snapshot()["source"].is_null() && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(1));
    }
    let first = r.receive_snapshot();
    assert!(!first["source"].is_null());
    r.resources.lock().unwrap().fail_source_uuid = true;
    assert!(!queue.push(&[], 8193, 1024, 0, audio::SILENT));
    assert!(queue.push(&[], 1024, 1024, 0, audio::SILENT));
    let deadline = Instant::now() + Duration::from_secs(1);
    while r.receive_snapshot()["job"]["state"] != "failed" && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(1));
    }
    let failed = r.receive_snapshot();
    assert_eq!(failed["audio"]["state"], "closed");
    assert_eq!(failed["job"]["state"], "failed");
    assert_eq!(failed["job"]["id"], first["job"]["id"]);
    assert_eq!(failed["generation"], first["generation"]);
    assert_eq!(failed["job"]["error"], "storage_unavailable");
    assert!(
        r.reserve(&r.profile, &r.boot, failed["generation"].as_u64().unwrap())
            .is_ok()
    );
}
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
        source_id: Some(id),
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
        source_id: Some(profile::new_uuid().unwrap()),
        generation: 1,
        kind: "spectrum",
        state: "running",
        processed_frames: 0,
        error: None,
        cancel: Arc::new(AtomicBool::new(false)),
    };
    let metadata = Metadata {
        schema_version: 1,
        recording_id: obsolete.source_id.clone().unwrap(),
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

// Proves: CL-006-02; TC-018-003 review regression, absent manifest never authorizes guessing which UUID original to delete.
#[test]
fn absent_manifest_artifacts_are_unavailable_and_retained_until_valid_commit() {
    let f = Fixture::new();
    let empty = f.recording();
    assert_eq!(empty.snapshot()["source_error"], Value::Null);
    assert_eq!(empty.snapshot()["recording"], Value::Null);
    // These bytes are indistinguishable from a pre-commit crash or loss of a previously committed manifest.
    let id = profile::new_uuid().unwrap();
    let bytes = wav(&[1]);
    fs::write(empty.path(&id, "wav"), &bytes).unwrap();
    write_json(
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
// Proves: CL-006-03/04; TC-010-004, independent f64 DFT, native bins and power/EOS rows.
#[test]
fn detailed_native_bins_and_power_rows_follow_independent_dft() {
    use base64::{Engine, engine::general_purpose::STANDARD};
    fn direct(x: &[f32], k: usize) -> f64 {
        let (mut re, mut im) = (0.0, 0.0);
        for (n, &sample) in x.iter().enumerate() {
            let w = (1.0 - (std::f64::consts::TAU * n as f64 / 4096.0).cos()) / 2.0;
            let a = std::f64::consts::TAU * k as f64 * n as f64 / 4096.0;
            re += f64::from(sample) * w * a.cos();
            im -= f64::from(sample) * w * a.sin();
        }
        re.hypot(im) * if k == 0 { 1.0 } else { 2.0 } / 2048.0
    }
    for scalar in [false, true] {
        let mut fft = spectrum::Spectrum::detailed(scalar);
        for frequencies in [
            &[750.0][..],
            &[752.9296875][..],
            &[750.0, 752.9296875][..],
            &[750.0, 756.25][..],
        ] {
            let x: Vec<f32> = (0..4096)
                .map(|n| {
                    let v: f64 = frequencies
                        .iter()
                        .map(|f| 0.25 * (std::f64::consts::TAU * f * n as f64 / 12000.0).sin())
                        .sum();
                    (v * 32768.0).round() as f32 / 32768.0
                })
                .collect();
            let observed = fft.native_amplitudes(&x).unwrap();
            assert_eq!(observed.len(), 1024);
            for (k, &observed_amplitude) in observed.iter().enumerate() {
                let expected = direct(&x, k);
                assert!(
                    (f64::from(observed_amplitude) - expected).abs() < 2e-6,
                    "scalar={scalar},bin={k}"
                );
                if expected > 1e-4 {
                    assert!(
                        (20.0 * (f64::from(observed_amplitude) / expected).log10()).abs() < 0.05
                    );
                }
            }
        }
        assert!(fft.native_amplitudes(&vec![0.0; 4097]).is_err());
        assert!(fft.native_amplitudes(&[f32::NAN]).is_err());
    }
    for length in [1, 2399, 2400, 2401, 2879, 2880, 2881, 6000] {
        let f = Fixture::new();
        let r = f.recording();
        let pcm: Vec<i16> = (0..length)
            .map(|n| {
                if n < 1920 {
                    0
                } else {
                    (12000.0 * (std::f64::consts::TAU * 756.25 * n as f64 / 12000.0).sin()).round()
                        as i16
                }
            })
            .collect();
        let id = import(&r, &wav(&pcm)).unwrap();
        let generation = r.state.lock().unwrap().generation;
        r.replay(&r.profile, &r.boot, generation, &id).unwrap();
        let began = Instant::now();
        while r.snapshot()["job"]["state"] == "running" {
            assert!(began.elapsed() < Duration::from_secs(3));
            std::thread::sleep(Duration::from_millis(5));
        }
        assert_eq!(r.snapshot()["job"]["state"], "completed");
        let frame = r.state.lock().unwrap().detail_frame.clone().unwrap();
        let frame: Value = serde_json::from_str(&frame.text).unwrap();
        assert_eq!(frame["type"], "spectrum.detail.frame");
        assert!(frame.to_string().len() <= 2048);
        let first = ((length - 1) / 2400) * 2400;
        assert_eq!(frame["data"]["first_frame"], first);
        assert_eq!(frame["data"]["end_frame"], length);
        let encoded = frame["data"]["levels_b64"].as_str().unwrap();
        assert_eq!(encoded.len(), 1368);
        let levels = STANDARD.decode(encoded).unwrap();
        assert_eq!(levels.len(), 1024);
        let starts: Vec<usize> = (first..length).step_by(480).collect();
        for k in [0, 1, 255, 256, 257, 258, 1023] {
            let p = starts
                .iter()
                .map(|&start| {
                    let end = (start + 4096).min(length);
                    let x: Vec<f32> = pcm[start..end]
                        .iter()
                        .map(|&v| f32::from(v) / 32768.0)
                        .collect();
                    direct(&x, k).powi(2)
                })
                .sum::<f64>()
                / starts.len() as f64;
            let expected = (10.0 * p.max(1e-12).log10()).clamp(-120.0, 0.0) + 120.0;
            assert!(
                (f64::from(levels[k]) - expected.round()).abs() <= 1.0,
                "length={length},bin={k}"
            );
        }
        if length == 2401 {
            assert!(levels.iter().all(|&q| q == 0));
        }
    }
}

fn relative_clock(r: &Recording, mode: &'static str, anchor: &str, anchor_frame: u64) {
    let mut s = r.state.lock().unwrap();
    let live = s.live.as_mut().unwrap();
    live.mode = mode;
    live.timing = Some(source::SourceTiming {
        source_id: live.source.as_ref().unwrap().source_id.clone(),
        segment: 0,
        native_rate: 48000,
        native_anchor_frame: 0.0,
        canonical_anchor_frame: anchor_frame,
        converter_delay_native_frames: 0.0,
        qpc_anchor_100ns: Some(0),
        system_utc_anchor: Some(anchor.into()),
        uncertainty_ns: Some(500),
        correlated: true,
        external_accuracy: source::ExternalAccuracy::Unknown,
    });
}

// Proves: CL-010-09; TC-007-006. Independent hand-calculated UTC/frame vectors.
#[test]
fn latest_decode_relative_station_timing_uses_mode_origin_and_source_clock() {
    for (mode, starts, period) in [
        ("ft8", [3600, 6000, 8400], "2026-10-27T12:00:00.0000000Z"),
        ("ft4", [3024, 5424, 7824], "2026-10-27T12:00:00.0000000Z"),
    ] {
        let fixture = Fixture::new();
        let r = fixture.recording();
        let (job, mut decoded) = live_ring(&r);
        relative_clock(&r, mode, "2026-10-27T12:00:00.0000000Z", 0);
        for (index, start) in starts.into_iter().enumerate() {
            decoded.start_frame = start;
            r.publish_decode(&job, &decoded).unwrap();
            let p = r
                .receive_results(job.source_id.as_ref().unwrap(), &job.id, 1, index as u64, 1)
                .unwrap();
            assert_eq!(p["records"][0]["period_start_utc"], period);
            assert!(
                (p["records"][0]["dt_seconds"].as_f64().unwrap() - [-0.2, 0.0, 0.2][index]).abs()
                    < 0.000001
            );
        }
        if mode == "ft4" {
            decoded.start_frame = 95424;
            r.publish_decode(&job, &decoded).unwrap();
            let p = r
                .receive_results(job.source_id.as_ref().unwrap(), &job.id, 1, 3, 1)
                .unwrap();
            assert_eq!(
                p["records"][0]["period_start_utc"],
                "2026-10-27T12:00:07.5000000Z"
            );
            assert_eq!(p["records"][0]["dt_seconds"], 0.0);
        }
    }
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (job, mut decoded) = live_ring(&r);
    relative_clock(&r, "ft8", "2026-10-27T23:59:59.9000000Z", 1200);
    decoded.start_frame = 8400;
    r.publish_decode(&job, &decoded).unwrap();
    let p = r
        .receive_results(job.source_id.as_ref().unwrap(), &job.id, 1, 0, 1)
        .unwrap();
    assert_eq!(
        p["records"][0]["period_start_utc"],
        "2026-10-28T00:00:00.0000000Z"
    );
    assert_eq!(p["records"][0]["dt_seconds"], 0.0);
    for (mode, start, dt, period) in [
        ("ft8", 96000, -7.5, "2026-10-27T12:00:15.0000000Z"),
        ("ft4", 50424, -3.75, "2026-10-27T12:00:07.5000000Z"),
    ] {
        relative_clock(&r, mode, "2026-10-27T12:00:00.0000000Z", 0);
        decoded.start_frame = start;
        r.publish_decode(&job, &decoded).unwrap();
        let end = r.receive_snapshot()["job"]["next_sequence"]
            .as_u64()
            .unwrap();
        let p = r
            .receive_results(job.source_id.as_ref().unwrap(), &job.id, 1, end - 1, 1)
            .unwrap();
        assert_eq!(p["records"][0]["dt_seconds"], dt);
        assert_eq!(
            p["records"][0]["period_start_utc"], period,
            "nearest-slot tie selects later period"
        );
    }
    relative_clock(&r, "ft8", "2026-10-27T12:00:00.0001000Z", 0);
    decoded.start_frame = 6000;
    r.publish_decode(&job, &decoded).unwrap();
    let end = r.receive_snapshot()["job"]["next_sequence"]
        .as_u64()
        .unwrap();
    assert_eq!(
        r.receive_results(job.source_id.as_ref().unwrap(), &job.id, 1, end - 1, 1)
            .unwrap()["records"][0]["dt_seconds"],
        0.0001
    );
    for anchor in [
        "not UTC",
        "2026-02-30T12:00:00.0000000Z",
        "2026-10-27T12:00:00.00000000Z",
    ] {
        relative_clock(&r, "ft8", anchor, 0);
        r.publish_decode(&job, &decoded).unwrap();
        let end = r.receive_snapshot()["job"]["next_sequence"]
            .as_u64()
            .unwrap();
        let p = r
            .receive_results(job.source_id.as_ref().unwrap(), &job.id, 1, end - 1, 1)
            .unwrap();
        assert!(p["records"][0]["period_start_utc"].is_null());
        assert!(p["records"][0]["dt_seconds"].is_null());
    }
    r.state.lock().unwrap().live.as_mut().unwrap().timing = None;
    r.publish_decode(&job, &decoded).unwrap();
    let end = r.receive_snapshot()["job"]["next_sequence"]
        .as_u64()
        .unwrap();
    assert!(
        r.receive_results(job.source_id.as_ref().unwrap(), &job.id, 1, end - 1, 1)
            .unwrap()["records"][0]["dt_seconds"]
            .is_null()
    );
}

// Proves: CL-010-09; TC-007-006. Actual numerical silence completes; result inputs are explicit manager fixtures.
#[test]
fn latest_decode_replaces_period_atomically_including_empty_and_all_retained_rows() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (job, mut decoded) = live_ring(&r);
    relative_clock(&r, "ft8", "2026-10-27T12:00:00.0000000Z", 0);
    r.state.lock().unwrap().live.as_mut().unwrap().next_frame = 540000;
    decoded.start_frame = 6000;
    r.publish_decode(&job, &decoded).unwrap();
    for i in 0..18 {
        decoded.start_frame = 186000;
        decoded.frequency_hz = 1000.0 + f64::from(i);
        r.publish_decode(&job, &decoded).unwrap();
    }
    let input = crate::receive_http_tests::Input::queued().0;
    let mut worker = LiveWorker::new(r.clone(), job.clone(), Box::new(input), "ft8");
    worker
        .analyze(receive::AnalysisWindow {
            origin: 0,
            samples: vec![0.0; 360000],
        })
        .unwrap();
    let s = r.receive_snapshot();
    let view = &s["job"]["latest_decode"];
    assert_eq!(view["id"], 1);
    assert_eq!(view["first_sequence"], 1);
    assert_eq!(view["next_sequence"], 19);
    assert_eq!(view["complete"], true);
    assert_eq!(view["period_start_utc"], "2026-10-27T12:00:15.0000000Z");
    let page = r
        .receive_results(job.source_id.as_ref().unwrap(), &job.id, 1, 1, 16)
        .unwrap();
    assert_eq!(page["latest_decode"], *view);
    assert_eq!(page["records"].as_array().unwrap().len(), 16);
    assert_eq!(
        r.receive_results(job.source_id.as_ref().unwrap(), &job.id, 1, 17, 16)
            .unwrap()["records"]
            .as_array()
            .unwrap()
            .len(),
        2
    );
    worker
        .analyze(receive::AnalysisWindow {
            origin: 180000,
            samples: vec![0.0; 360000],
        })
        .unwrap();
    let s = r.receive_snapshot();
    let empty = &s["job"]["latest_decode"];
    assert_eq!(empty["id"], 2);
    assert_eq!(empty["first_sequence"], 19);
    assert_eq!(empty["next_sequence"], 19);
    assert_eq!(empty["period_start_utc"], "2026-10-27T12:00:30.0000000Z");
}

struct DecodeBoundaryInput {
    context: source::SourceContext,
    next: Option<SampleBlock>,
    owner: Arc<Recording>,
    views: Arc<Mutex<Vec<Value>>>,
    running: bool,
}
impl SampleSource for DecodeBoundaryInput {
    fn descriptor(&self) -> Option<Arc<SourceDescriptor>> {
        Some(self.context.descriptor.clone())
    }
    fn acknowledge_epoch(
        &mut self,
        _: u64,
        _: Arc<SourceDescriptor>,
        _: source::SourceTiming,
    ) -> std::result::Result<(), source::SourceError> {
        Err(source::SourceError::InvalidContext)
    }
    fn poll(&mut self) -> SourcePoll {
        let view = self.owner.receive_snapshot()["job"]["latest_decode"].clone();
        if !view.is_null() && self.views.lock().unwrap().last() != Some(&view) {
            self.views.lock().unwrap().push(view);
        }
        self.next
            .take()
            .map(SourcePoll::Block)
            .unwrap_or(SourcePoll::Pending)
    }
}
impl LiveInput for DecodeBoundaryInput {
    fn start(&mut self) -> std::result::Result<(), source::SourceError> {
        self.running = true;
        Ok(())
    }
    fn request_stop(&mut self) {
        self.running = false;
    }
    fn status(&self) -> audio::AudioStatus {
        audio::AudioStatus {
            state: if self.running {
                audio::AudioState::Running
            } else {
                audio::AudioState::Closed
            },
            error: None,
            retry_after_ms: None,
        }
    }
}
// Proves: CL-010-09; TC-007-006. Actual cooperative numerical/manager overrun, not a pre-labelled wire response.
#[test]
fn latest_decode_actual_overrun_stays_partial_then_completes_the_next_period() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (job, decoded) = live_ring(&r);
    relative_clock(&r, "ft8", "2026-10-27T12:00:00.0000000Z", 0);
    r.publish_decode(&job, &decoded).unwrap();
    let context = {
        let s = r.state.lock().unwrap();
        let l = s.live.as_ref().unwrap();
        source::SourceContext {
            descriptor: l.source.as_ref().unwrap().clone(),
            timing: Arc::new(l.timing.as_ref().unwrap().clone()),
        }
    };
    let block =
        |first| SampleBlock::live(&context, first, Arc::from(vec![0.0; 240]), false).unwrap();
    let mut window =
        receive::WindowBuffer::new(decoder::Mode::Ft8, context.descriptor.clone()).unwrap();
    for first in (180000..359760).step_by(240) {
        assert!(window.push(&block(first)).unwrap().window.is_none());
    }
    r.state.lock().unwrap().live.as_mut().unwrap().next_frame = 359760;
    let views = Arc::new(Mutex::new(vec![]));
    let next = block(359760);
    let input = DecodeBoundaryInput {
        context,
        next: Some(next),
        owner: r.clone(),
        views: views.clone(),
        running: true,
    };
    let mut worker = LiveWorker::new(r.clone(), job, Box::new(input), "ft8");
    worker.window = Some(window);
    worker.spectrum.reset(359760);
    worker
        .analyze(receive::AnalysisWindow {
            origin: 0,
            samples: vec![0.0; 180000],
        })
        .unwrap();
    let observed = views.lock().unwrap();
    assert!(
        observed
            .iter()
            .any(|v| v["id"] == 1 && v["complete"] == false),
        "abandoned analysis must publish explicit partial view: {observed:?}"
    );
    let s = r.receive_snapshot();
    assert_eq!(
        s["job"]["last_overrun"],
        json!({"first_frame":0,"end_frame":180000})
    );
    assert_eq!(s["job"]["latest_decode"]["id"], 2);
    assert_eq!(s["job"]["latest_decode"]["complete"], true);
    assert_eq!(
        s["job"]["latest_decode"]["period_start_utc"],
        "2026-10-27T12:00:15.0000000Z"
    );
}
// Proves: CL-010-09; TC-007-006. Real terminal owner path preserves last view, never an invented completion.
#[test]
fn latest_decode_cancel_and_failure_preserve_published_period_without_new_identity() {
    for cancelled in [false, true] {
        let fixture = Fixture::new();
        let r = fixture.recording();
        let (job, decoded) = live_ring(&r);
        r.publish_decode(&job, &decoded).unwrap();
        r.publish_latest_decode(&job, (0, 180000), 0, false)
            .unwrap();
        let before = r.receive_snapshot()["job"]["latest_decode"].clone();
        r.state.lock().unwrap().decode_counter = source::MAX_COUNTER;
        assert_eq!(
            r.publish_latest_decode(&job, (0, 180000), 0, false),
            Err("counter_exhausted")
        );
        assert_eq!(
            r.receive_snapshot()["job"]["latest_decode"],
            before,
            "counter exhaustion cannot replace last view"
        );
        let input = crate::receive_http_tests::Input::queued().0;
        let worker = LiveWorker::new(r.clone(), job.clone(), Box::new(input), "ft8");
        if cancelled {
            job.cancel.store(true, Ordering::Release);
        }
        worker.run(if cancelled {
            Ok(())
        } else {
            Err("audio_failed")
        });
        let after = r.receive_snapshot();
        assert_eq!(
            after["job"]["state"],
            if cancelled { "cancelled" } else { "failed" }
        );
        assert_eq!(after["job"]["latest_decode"], before);
        assert_eq!(after["job"]["latest_decode"]["complete"], false);
    }
}

// Proves: CL-006-03/04; TC-010-008 actual history plus two fixed phases and independent integer-token oracle.
#[tokio::test(start_paused = true)]
async fn detailed_phased_jitter_delivers_all_150_shared_rows() {
    let fixture = Fixture::new();
    let recording = fixture.recording();
    let (job, _) = live_ring(&recording);
    let identity = recording
        .state
        .lock()
        .unwrap()
        .detail_identity(&recording.boot);
    let origin = tokio::time::Instant::now();
    let mut peers = [
        crate::DetailDelivery::new(identity.clone(), 0),
        crate::DetailDelivery::new(identity.clone(), 0),
    ];
    peers[1].epoch += Duration::from_millis(100);
    peers[1].updated = peers[1].epoch;
    let jitter = [0u64, 17, 149, 3, 95, 0];
    let mut ticks = [0usize; 2];
    let mut wake = [200u64, 300];
    let mut credits = [1000i64; 2];
    let mut previous = [0u64, 100];
    let mut accepted = [Vec::new(), Vec::new()];
    let mut encoded = [Vec::new(), Vec::new()];
    for millis in 1u64..=31000 {
        tokio::time::advance(Duration::from_millis(1)).await;
        if millis % 200 == 0 && millis <= 30000 {
            let sequence = millis / 200 - 1;
            let frame = json!({"v":1,"type":"spectrum.detail.frame","data":{
                "boot_id":recording.boot,"source_id":job.source_id,"job_id":job.id,"generation":job.generation,
                "sequence":sequence,"first_frame":sequence*2400,"end_frame":(sequence+1)*2400,
                "levels_b64":STANDARD.encode(vec![(sequence%121) as u8;1024])}});
            let mut state = recording.state.lock().unwrap();
            state.publish_detail(frame, &recording.boot);
            assert!(state.detail_history.len() <= 8);
            assert!(
                state
                    .detail_history
                    .iter()
                    .map(|f| f.text.len())
                    .sum::<usize>()
                    <= 16384
            );
        }
        for n in 0..2 {
            if millis != wake[n] {
                continue;
            }
            let peer = &mut peers[n];
            let now = origin + Duration::from_millis(millis);
            peer.refill(now);
            credits[n] = (credits[n] + 5 * (millis - previous[n]) as i64).min(2000);
            previous[n] = millis;
            let mut burst = 0;
            while peer.tokens >= 1.0 {
                let frame = recording
                    .state
                    .lock()
                    .unwrap()
                    .detail_candidate(peer.cursor, &peer.identity);
                let Some(frame) = frame else { break };
                assert!(credits[n] >= 1000);
                credits[n] -= 1000;
                accepted[n].push((frame.sequence, millis));
                encoded[n].push(frame.text.clone());
                peer.accepted(frame.sequence);
                burst += 1;
            }
            assert!(burst <= 2);
            assert!((peer.tokens - credits[n] as f64 / 1000.0).abs() < 1e-8);
            ticks[n] += 1;
            wake[n] = n as u64 * 100 + 200 * (ticks[n] as u64 + 1) + jitter[ticks[n] % 6];
        }
    }
    for rows in &accepted {
        assert_eq!(
            rows.iter().map(|r| r.0).collect::<Vec<_>>(),
            (0..150).collect::<Vec<_>>()
        );
        for first in 0..rows.len() {
            for last in first..rows.len() {
                assert!(
                    ((last - first + 1) as u64) * 1000 <= 2000 + 5 * (rows[last].1 - rows[first].1)
                );
            }
        }
    }
    assert_eq!(encoded[0], encoded[1]);
}
