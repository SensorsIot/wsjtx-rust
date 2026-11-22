use super::*;

// Live ring2047/2048/2049 and explicit cursors.
// Proves: TC-009-004
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

// Seeded byte/safe-counter bounds and invalid/stale publication.
// Proves: TC-009-004
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

// Actual provider epoch and owner identity.
// Proves: TC-009-004
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
    r.publish_latest_decode(&first_job, (0, 224), 0, false, false)
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
    r.publish_latest_decode(&first_job, (12000, 12224), 1, false, false)
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

// Through the real queue, converter and live worker:
// a WASAPI engine glitch on a continuous device/QPC timeline keeps job, generation and
// spectrum/decode window; a real unknown loss rotates once and GET /receive names it.
// Proves: TC-009-004
#[test]
fn live_worker_keeps_its_job_through_engine_glitches_and_reports_loss_epochs() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (job, _) = live_ring(&r);
    let (mut input, queue) = crate::receive_http_tests::Input::queued();
    input.start().unwrap();
    let mut worker = LiveWorker::new(r.clone(), job, Box::new(input), "ft8");
    worker.epoch_seen = false;
    let packet = vec![0_u8; 480 * 8];
    let (mut frame, mut qpc) = (160_980_000_u64, 51_066_719_853_840_u64);
    let push = |flags: u32, frame: &mut u64, qpc: &mut u64| {
        assert!(queue.push(&packet, 480, *frame, *qpc, flags));
        *frame += 480;
        *qpc += 100_150;
    };
    // The initial epoch (here without a valid timestamp) replaces nothing: not a loss restart.
    push(audio::TIMESTAMP_ERROR, &mut frame, &mut qpc);
    for _ in 0..4 {
        worker.step().unwrap();
    }
    let first = worker.job.clone();
    assert!(first.source_id.is_some());
    assert_eq!(r.receive_snapshot()["audio"]["loss_epochs"], 0);
    for i in 0..300 {
        let flags = if i % 50 == 7 {
            audio::DATA_DISCONTINUITY
        } else {
            0
        };
        push(flags, &mut frame, &mut qpc);
        for _ in 0..4 {
            worker.step().unwrap();
        }
    }
    let view = r.receive_snapshot();
    assert_eq!(
        worker.job.id, first.id,
        "engine glitch must not rotate the job"
    );
    assert_eq!(worker.job.generation, first.generation);
    assert_eq!(view["generation"], first.generation);
    assert_eq!(view["audio"]["loss_epochs"], 0);
    assert!(view["audio"]["last_loss"].is_null());
    assert!(worker.window.is_some());
    // Own-queue loss (oversized packet) is unknown loss: exactly one rotation, named.
    assert!(!queue.push(&[], 8193, frame, qpc, audio::SILENT));
    push(0, &mut frame, &mut qpc);
    for _ in 0..4 {
        worker.step().unwrap();
    }
    let view = r.receive_snapshot();
    assert_ne!(worker.job.id, first.id);
    assert_eq!(view["generation"], first.generation + 1);
    assert_eq!(view["audio"]["loss_epochs"], 1);
    assert_eq!(view["audio"]["last_loss"], "invalid_packet");
    worker.input.request_stop();
}

// Resource release precedes terminal publication.
// Proves: TC-018-003
#[test]
fn live_terminal_is_unobservable_until_actual_input_drop_releases() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (mut input, _) = crate::receive_http_tests::Input::queued();
    let (entered, released) = input.block_release();
    let snapshot = fixture
        .start(&r, 0, "native-queue-fixture", "ft8", input)
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

// A refused OS worker cannot strand station admission.
// Proves: TC-018-003
#[test]
fn live_worker_spawn_failure_releases_admission_without_reusing_generation() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    fixture.3.fail_next();
    let (input, _) = crate::receive_http_tests::Input::queued();
    assert_eq!(
        fixture.start(&r, 0, "native-queue-fixture", "ft8", input),
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

// A failed fresh source identity cannot orphan the old owner.
// Proves: TC-018-003
#[test]
fn live_second_epoch_source_uuid_failure_releases_original_admission() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (input, queue) = crate::receive_http_tests::Input::queued();
    fixture
        .start(&r, 0, "native-queue-fixture", "ft8", input)
        .unwrap();
    assert!(queue.push(&[], 1024, 0, 0, audio::SILENT));
    let deadline = Instant::now() + Duration::from_secs(1);
    while r.receive_snapshot()["source"].is_null() && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(1));
    }
    let first = r.receive_snapshot();
    assert!(!first["source"].is_null());
    // The live worker mints the source id: the fault meets every thread.
    fixture
        .1
        .arm(Fault::fail(Step::Id, FaultScope::EveryThread));
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

// Without live inputs a start opens no device of the PC and is refused before admission.
#[test]
fn recording_without_input_port_opens_no_device() {
    let fixture = Fixture::new();
    let r = Recording::open(
        &fixture.0,
        "00000000-0000-4000-8000-000000000001".into(),
        profile::new_uuid().unwrap(),
        fixture.1.clone(),
        DrivenClock::new(),
        Arc::new(Threads),
        Arc::new(WavFiles),
    );
    assert_eq!(
        r.receive_start(
            &r.profile,
            &r.boot,
            0,
            0,
            "{0.0.1.00000000}.{probe}".into(),
            "ft8"
        ),
        Err("audio_unavailable")
    );
    let view = r.receive_snapshot();
    assert_eq!(view["generation"], 0);
    assert!(view["job"].is_null(), "{view}");
}

// The real spawner runs each job on a thread of its own, named when a name is given.
#[test]
fn threads_run_each_job_on_its_own_named_thread() {
    let caller = std::thread::current().id();
    for name in [Some("station-receive"), None] {
        let (tx, rx) = std::sync::mpsc::channel();
        Threads
            .spawn(
                name,
                Box::new(move || {
                    let current = std::thread::current();
                    tx.send((current.id(), current.name().map(str::to_owned)))
                        .unwrap();
                }),
            )
            .unwrap()
            .join()
            .unwrap();
        let (id, seen) = rx.try_recv().unwrap();
        assert_ne!(id, caller);
        assert_eq!(seen.as_deref(), name);
    }
}

// A held worker failure and the EOS vector, at cost 2 on Windows.
// Proves: TC-018-003
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

// A worker preempted across a pacing deadline releases the slot.
// Proves: TC-018-003
// Timing: display
#[test]
fn crossing_pacing_deadline_completes_and_releases_worker_slot() {
    let f = Fixture::new();
    let clock = DrivenClock::new();
    let r = f.recording_on(clock.clone());
    let id = import(&r, &wav(&[0; 1200])).unwrap();
    // The first row is due 100 ms into the replay; the worker's first wait jumps past it.
    clock.arm_jump(Duration::from_secs(1));
    let generation = r.snapshot()["generation"].as_u64().unwrap();
    r.replay(&r.profile, &r.boot, generation, &id).unwrap();
    let began = Instant::now();
    while r.snapshot()["job"]["state"] == "running" {
        assert!(began.elapsed() < Duration::from_secs(2));
        std::thread::sleep(Duration::from_millis(5));
    }
    assert_eq!(r.snapshot()["job"]["state"], "completed");
    // The worker counts as ended once its job has returned, after the terminal state.
    f.3.wait_idle(Duration::from_secs(2).saturating_sub(began.elapsed()));
    assert_eq!(f.3.active(), 0);
    assert_eq!(clock.jumps(), 1);
    assert!(r.reserve(&r.profile, &r.boot, generation + 1).is_ok());
}

// Proves: TC-018-003
#[test]
fn a_replay_start_it_does_not_admit_is_refused_and_changes_nothing() {
    let f = Fixture::new();
    let r = f.recording();
    let other = profile::new_uuid().unwrap();
    assert_eq!(
        r.replay(&r.profile, &r.boot, 0, &other).unwrap_err(),
        "no_recording"
    );
    let id = import(&r, &wav(&[1, 2, 3])).unwrap();
    let g = r.state.lock().unwrap().generation;
    let refused = |expected: &str| {
        assert_eq!(r.replay(&r.profile, &r.boot, g, &id).unwrap_err(), expected);
        assert_eq!(r.state.lock().unwrap().generation, g, "{expected}");
    };
    assert_eq!(
        r.replay(&r.profile, &r.boot, g, &other).unwrap_err(),
        "not_found"
    );
    r.state.lock().unwrap().source_error = Some("recording_unavailable");
    refused("recording_unavailable");
    r.state.lock().unwrap().source_error = None;
    r.state.lock().unwrap().live_owner_released = false;
    refused("busy");
    r.state.lock().unwrap().live_owner_released = true;
    r.state.lock().unwrap().operating.operation =
        Some(pending_selection(&profile::new_uuid().unwrap(), 0));
    refused("busy");
    r.state.lock().unwrap().operating.operation = None;
    r.state.lock().unwrap().storage_error = Some("storage_unavailable");
    refused("storage_unavailable");
    r.state.lock().unwrap().storage_error = None;
    r.state.lock().unwrap().import.as_mut().unwrap().state = "receiving";
    refused("busy");
    r.state.lock().unwrap().import.as_mut().unwrap().state = "completed";
    r.state.lock().unwrap().job = Some(Job {
        id: profile::new_uuid().unwrap(),
        source_id: Some(id.clone()),
        generation: g,
        kind: "spectrum",
        state: "running",
        processed_frames: 0,
        error: None,
        cancel: Arc::new(AtomicBool::new(false)),
    });
    refused("busy");
}

// Proves: TC-009-004
#[test]
fn a_frame_outside_its_limits_never_becomes_a_record_and_reads_are_refused() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    type Edit = (&'static str, fn(&mut decoder::Decode));
    let edits: [Edit; 6] = [
        ("at the sample reached", |d: &mut decoder::Decode| {
            d.start_frame = 180000
        }),
        ("below the band", |d: &mut decoder::Decode| {
            d.frequency_hz = decoder::DECODE_BAND_LOW_HZ - 1.0
        }),
        ("above the band", |d: &mut decoder::Decode| {
            d.frequency_hz = decoder::DECODE_BAND_HIGH_HZ + 1.0
        }),
        ("SNR not a number", |d: &mut decoder::Decode| {
            d.snr_db = Some(f64::NAN)
        }),
        ("SNR above the limit", |d: &mut decoder::Decode| {
            d.snr_db = Some(SNR_LIMIT_DB + 1.0)
        }),
        ("SNR below the limit", |d: &mut decoder::Decode| {
            d.snr_db = Some(-SNR_LIMIT_DB - 1.0)
        }),
    ];
    for (what, edit) in edits {
        let (job, valid) = live_ring(&r);
        let mut bad = valid.clone();
        edit(&mut bad);
        assert_eq!(
            r.publish_decode(&job, &bad),
            Err(decoder::DecodeError::DecodeLimit),
            "{what}"
        );
        assert_eq!(
            r.publish_decode(&job, &valid),
            Err(decoder::DecodeError::DecodeLimit),
            "{what}: no later frame becomes a record"
        );
        let s = r.state.lock().unwrap();
        let l = s.live.as_ref().unwrap();
        assert_eq!(
            (l.next_sequence, l.records.len(), l.publication_error),
            (0, 0, Some("decode_limit")),
            "{what}"
        );
    }
    let (job, valid) = live_ring(&r);
    r.publish_decode(&job, &valid).unwrap();
    let source = job.source_id.clone().unwrap();
    let other = profile::new_uuid().unwrap();
    assert_eq!(
        r.receive_results(&source, &other, 1, 0, 1),
        Err("not_found")
    );
    assert_eq!(
        r.receive_results(&other, &job.id, 1, 0, 1),
        Err("not_found")
    );
    assert_eq!(
        r.receive_results(&source, &job.id, 2, 0, 1),
        Err("not_found")
    );
    r.state.lock().unwrap().live.as_mut().unwrap().mode = "spectrum";
    assert_eq!(
        r.receive_results(&source, &job.id, 1, 0, 1),
        Err("invalid_request")
    );
    r.state.lock().unwrap().live = None;
    assert_eq!(
        r.receive_results(&source, &job.id, 1, 0, 1),
        Err("not_found")
    );
}
