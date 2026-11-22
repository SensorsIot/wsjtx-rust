use super::*;

// Deterministically hold the operation in
// restarting while the real PacketQueue/LiveSource rotates its continuing worker.
// Proves: TC-009-005
#[test]
fn selection_cancel_tracks_its_worker_through_unknown_source_epoch() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (job, _) = live_ring(&r);
    let (mut input, queue) = crate::receive_http_tests::Input::queued();
    input.start().unwrap();
    let mut worker = LiveWorker::new(r.clone(), job, Box::new(input), "ft8");
    worker.epoch_seen = false;
    assert!(queue.push(&[], 1024, 0, 0, audio::SILENT | audio::TIMESTAMP_ERROR));
    worker.step().unwrap();
    let original = worker.job.clone();
    let command = profile::new_uuid().unwrap();
    {
        let mut s = r.state.lock().unwrap();
        s.operating.revision = 1;
        s.operating.operation = Some(selection::Operation {
            command_id: command.clone(),
            base_revision: 0,
            revision: 1,
            action: "band",
            requested: selection::Requested {
                mode: "ft8",
                band: "40m",
                nominal_hz: 7074000,
            },
            phase: "restarting",
            result: "pending",
            error: None,
            monitor_before: false,
            monitor_wanted: true,
            old_job_id: None,
            new_job_id: Some(original.id.clone()),
            new_generation: Some(original.generation),
            old_generation: 0,
            new_worker_cancel: Some(original.cancel.clone()),
            cancelled: Arc::new(AtomicBool::new(false)),
        });
    }
    assert!(!queue.push(&[], 8193, 1024, 0, audio::SILENT));
    assert!(queue.push(&[], 1024, 1024, 0, audio::SILENT));
    worker.step().unwrap();
    assert_ne!(worker.job.id, original.id);
    assert_eq!(worker.job.generation, original.generation + 1);
    assert!(
        Arc::ptr_eq(&worker.job.cancel, &original.cancel),
        "an epoch replacement retains its actual worker cancel token"
    );
    let ack = r
        .selection_cancel(
            &r.profile,
            &r.boot,
            profile::new_uuid().unwrap(),
            command,
            0,
        )
        .unwrap();
    let cancelled = worker.job.cancel.load(Ordering::Acquire);
    worker.input.request_stop();
    assert_eq!(ack.0["phase"], "cancelled");
    assert!(
        cancelled,
        "target cancellation must stop its own continuing worker after an unknown epoch"
    );
}

// A later real Start owns a distinct
// cancellation Arc even if old operation metadata remains visible.
// Proves: TC-009-005
#[test]
fn selection_old_command_cannot_cancel_unrelated_later_start() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (old, _) = live_ring(&r);
    let command = profile::new_uuid().unwrap();
    {
        let mut s = r.state.lock().unwrap();
        s.job.as_mut().unwrap().state = "cancelled";
        s.operating.revision = 1;
        s.operating.operation = Some(selection::Operation {
            command_id: command.clone(),
            base_revision: 0,
            revision: 1,
            action: "band",
            requested: selection::Requested {
                mode: "ft8",
                band: "40m",
                nominal_hz: 7074000,
            },
            phase: "applied",
            result: "success",
            error: None,
            monitor_before: false,
            monitor_wanted: true,
            old_job_id: None,
            new_job_id: Some(old.id.clone()),
            new_generation: Some(old.generation),
            old_generation: 0,
            new_worker_cancel: Some(old.cancel.clone()),
            cancelled: Arc::new(AtomicBool::new(false)),
        });
    }
    let (input, _) = crate::receive_http_tests::Input::queued();
    let started = fixture
        .start(&r, 1, "independent-new-input", "ft4", input)
        .unwrap();
    let current = r.state.lock().unwrap().job.as_ref().unwrap().clone();
    assert!(!Arc::ptr_eq(&current.cancel, &old.cancel));
    r.selection_cancel(
        &r.profile,
        &r.boot,
        profile::new_uuid().unwrap(),
        command,
        0,
    )
    .unwrap();
    let stayed_running = !current.cancel.load(Ordering::Acquire);
    r.receive_stop(
        &r.profile,
        &r.boot,
        started["generation"].as_u64().unwrap(),
        started["job"]["id"].as_str().unwrap(),
    )
    .unwrap();
    let deadline = Instant::now() + Duration::from_secs(2);
    while !r.selection_snapshot(false).unwrap()["receive"]["owner_released"]
        .as_bool()
        .unwrap()
        && Instant::now() < deadline
    {
        std::thread::sleep(Duration::from_millis(1));
    }
    assert!(
        stayed_running,
        "retained old command must not acquire authority over a fresh Start"
    );
    assert_eq!(
        r.selection_snapshot(false).unwrap()["receive"]["owner_released"],
        true
    );
}

// Domain refusal is earlier than missing
// configured CAT and every counter increments only for a genuinely admitted command.
// Proves: TC-009-005
#[test]
fn selection_unknown_band_and_safe_counter_refuse_without_effects() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    assert_eq!(
        r.selection_begin(selection_intent(&r, "mode", Some("ft4"), None), None, true),
        Err("select_band_first")
    );
    assert_eq!(r.state.lock().unwrap().operating.revision, 0);
    r.state.lock().unwrap().operating.revision = profile::MAX_REVISION;
    assert_eq!(
        r.selection_begin(selection_intent(&r, "band", None, Some("40m")), None, false),
        Err("counter_exhausted")
    );
    assert!(r.state.lock().unwrap().operating.operation.is_none());
    assert_eq!(
        r.selection_cancel(
            &r.profile,
            &r.boot,
            profile::new_uuid().unwrap(),
            profile::new_uuid().unwrap(),
            profile::MAX_REVISION
        ),
        Err("counter_exhausted")
    );
    assert_eq!(r.receive_snapshot()["generation"], 0);
}

// The Start revision guard. A loaded saved
// revision is independent station state; later edits invalidate a captured old input.
// Proves: TC-006-004
#[test]
fn selection_start_checks_independent_loaded_profile_revision_after_unlock() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    r.initialize_profile_revision(7);
    let (input, _) = crate::receive_http_tests::Input::queued();
    fixture.2.replace(Box::new(input));
    assert_eq!(
        r.receive_start(&r.profile, &r.boot, 0, 6, "must-not-open".into(), "ft8"),
        Err("state_conflict")
    );
    assert_eq!(r.state.lock().unwrap().operating.revision, 0);
    assert_eq!(r.receive_snapshot()["generation"], 0);
    let (input, _) = crate::receive_http_tests::Input::queued();
    fixture.2.replace(Box::new(input));
    let started = r
        .receive_start(&r.profile, &r.boot, 0, 7, "current-input".into(), "ft8")
        .unwrap();
    r.receive_stop(
        &r.profile,
        &r.boot,
        started["generation"].as_u64().unwrap(),
        started["job"]["id"].as_str().unwrap(),
    )
    .unwrap();
    selection_released(&r);
    r.profile_changed(8);
    r.profile_changed(9);
    // The input the old start would open: its open succeeds, its revision is refused.
    fixture
        .2
        .replace(Box::new(crate::receive_http_tests::Input::queued().0));
    assert_eq!(
        r.receive_start(&r.profile, &r.boot, 1, 7, "old-input".into(), "ft4"),
        Err("state_conflict")
    );
    assert_eq!(r.receive_snapshot()["generation"], 1);
    assert_eq!(r.state.lock().unwrap().operating.profile_revision, 9);
}

#[test]
fn selection_preferred_entries_match_complete_canonical_integer_table() {
    let rows = PREFERRED_BAND_ENTRIES;
    assert_eq!(selection::BANDS.len(), rows.len());
    for (index, (band, ft8, ft4)) in rows.iter().enumerate() {
        assert_eq!(selection::BANDS[index], *band);
        for (mode, expected) in [("ft8", Some(*ft8)), ("ft4", *ft4)] {
            assert_eq!(selection::frequency(mode, band), expected, "{mode} {band}");
        }
    }
    assert_eq!(
        rows.len(),
        12,
        "the entire independent table, including both unsupported cells, was tested"
    );
}

// Real native-wrapper Drop is deliberately
// held. A failed release never becomes timeout permission to tune or open again.
// Proves: TC-009-005
#[test]
fn selection_release_timeout_retains_owner_and_never_commits_target() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (mut input, _) = crate::receive_http_tests::Input::queued();
    let (entered, released) = input.block_release();
    fixture.start(&r, 0, "held-input", "ft8", input).unwrap();
    r.selection_begin(selection_intent(&r, "band", None, Some("40m")), None, false)
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(2);
    while !entered.load(Ordering::Acquire) && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(1));
    }
    let snapshot = selection_wait(&r);
    released.store(true, Ordering::Release);
    selection_released(&r);
    assert_eq!(snapshot["operation"]["phase"], "release_blocked");
    assert_eq!(snapshot["operation"]["error"], "release_failed");
    assert_eq!(snapshot["receive"]["owner_released"], false);
    assert!(snapshot["selection"]["nominal_hz"].is_null());
    assert_eq!(snapshot["radio"]["connection_generation"], 0);
}

// The same owner restarts in an immutable new
// mode only after actual release; Stop/profile edit invalidate every late restart.
// Proves: TC-009-005
#[test]
fn selection_manual_mode_switch_uses_same_owner_and_profile_change_blocks_restart() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (first, _) = crate::receive_http_tests::Input::queued();
    let old = fixture.start(&r, 0, "first-input", "ft8", first).unwrap();
    let (next, _) = crate::receive_http_tests::Input::queued();
    fixture.2.replace(Box::new(next));
    r.selection_begin(
        selection_intent(&r, "band", None, Some("40m")),
        Some("next-input".into()),
        false,
    )
    .unwrap();
    let current = selection_wait(&r);
    assert_eq!(current["operation"]["result"], "success");
    assert_eq!(current["selection"]["nominal_hz"], 7074000);
    assert_ne!(current["receive"]["job_id"], old["job"]["id"]);
    assert!(current["generation"].as_u64().unwrap() > old["generation"].as_u64().unwrap());
    let id = current["receive"]["job_id"].as_str().unwrap();
    r.receive_stop(
        &r.profile,
        &r.boot,
        current["generation"].as_u64().unwrap(),
        id,
    )
    .unwrap();
    selection_released(&r);
    let (mut held, _) = crate::receive_http_tests::Input::queued();
    let (entered, released) = held.block_release();
    let generation = r.receive_snapshot()["generation"].as_u64().unwrap();
    fixture
        .start(&r, generation, "held-input", "ft8", held)
        .unwrap();
    let admitted = r
        .selection_begin(
            selection_intent(&r, "mode", Some("ft4"), None),
            Some("must-not-open".into()),
            false,
        )
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(1);
    while !entered.load(Ordering::Acquire) && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(1));
    }
    r.profile_changed(1);
    released.store(true, Ordering::Release);
    selection_released(&r);
    let failed = selection_wait(&r);
    assert_eq!(failed["operation"]["command_id"], admitted["command_id"]);
    assert_eq!(failed["operation"]["error"], "state_conflict");
    assert_eq!(failed["selection"]["mode"], "ft8");
    assert_eq!(failed["receive"]["state"], "cancelled");
    assert_eq!(failed["profile_revision"], 1);
}

// A persisted rename is deliberately observed
// while Recording invalidation is held. The SAME Store mutex prevents a new reader
// from seeing the edit until cancellation has been published, before HTTP success.
// Proves: TC-009-005
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn selection_profile_success_publishes_cancellation_before_new_reader() {
    let (fixture, r, app, settings, cancelled) = selection_profile_fixture();
    let state = app.profile.as_ref().unwrap().clone();
    let (headers, body) = selection_edit_request(&app, settings);
    let (writer, reader) = {
        let held = r.state.lock().unwrap();
        let writer = tokio::spawn(crate::put_profile(crate::State(app), headers, body));
        let deadline = Instant::now() + Duration::from_secs(2);
        loop {
            if fs::read(fixture.0.join("profile.json"))
                .ok()
                .and_then(|b| serde_json::from_slice::<Value>(&b).ok())
                .is_some_and(|v| v["revision"] == 1)
            {
                break;
            }
            assert!(Instant::now() < deadline);
            std::thread::sleep(Duration::from_millis(1));
        }
        let entered = Arc::new(AtomicBool::new(false));
        let returned = Arc::new(AtomicBool::new(false));
        let entry = entered.clone();
        let result = returned.clone();
        let token = cancelled.clone();
        let reader = std::thread::spawn(move || {
            entry.store(true, Ordering::Release);
            let store = state.store.lock().unwrap();
            let observed = (store.document.revision, token.load(Ordering::Acquire));
            result.store(true, Ordering::Release);
            observed
        });
        while !entered.load(Ordering::Acquire) {
            std::thread::yield_now();
        }
        std::thread::sleep(Duration::from_millis(20));
        assert!(
            !returned.load(Ordering::Acquire),
            "edited settings cannot be read before Recording invalidation"
        );
        assert!(
            !cancelled.load(Ordering::Acquire),
            "fixture really held the invalidation interval"
        );
        drop(held);
        (writer, reader)
    };
    assert_eq!(writer.await.unwrap().status(), crate::StatusCode::OK);
    assert_eq!(reader.join().unwrap(), (1, true));
    assert_eq!(
        r.selection_snapshot(false).unwrap()["operation"]["error"],
        "state_conflict"
    );
}

// A real atomic-store
// refusal cannot invalidate the old operation. This uses only a disposable fixture,
// no ACL changes or production fault switch.
// Proves: TC-009-005
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn selection_profile_save_failure_preserves_existing_token() {
    let (fixture, r, app, settings, cancelled) = selection_profile_fixture();
    let state = app.profile.as_ref().unwrap().clone();
    let original = fixture.0.join("profile.json");
    let backup = fixture.0.join("original-profile.json");
    fs::rename(&original, &backup).unwrap();
    fs::create_dir(&original).unwrap();
    let (headers, body) = selection_edit_request(&app, settings);
    let response = crate::put_profile(crate::State(app), headers, body).await;
    fs::remove_dir(&original).unwrap();
    fs::rename(&backup, &original).unwrap();
    assert_eq!(response.status(), crate::StatusCode::SERVICE_UNAVAILABLE);
    assert!(!cancelled.load(Ordering::Acquire));
    assert_eq!(state.store.lock().unwrap().document.revision, 0);
    let snapshot = r.selection_snapshot(false).unwrap();
    assert_eq!(snapshot["operating_revision"], 1);
    assert_eq!(snapshot["operation"]["result"], "pending");
}

#[test]
fn review_stale_profile_frequency_cannot_infer_unknown_manual_band() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (actor, rig) = crate::radio_http_tests::actor(r.profile.clone(), r.boot.clone(), 0, false);
    r.fixture_radio(actor.clone());
    let current = selection_intent(&r, "mode", Some("ft4"), None);
    {
        let s = r.state.lock().unwrap();
        assert_eq!(
            r.selection_preflight(&s, &current, false).unwrap().band,
            "40m"
        );
    }
    r.profile_changed(1);
    let before = r.selection_snapshot(false).unwrap();
    assert_eq!(before["selection"]["band"], Value::Null);
    assert_eq!(
        before["radio"]["observations"]["frequency"]["confirmed"],
        false
    );
    let writes = rig.lock().unwrap().writes.len();
    let result = r.selection_begin(selection_intent(&r, "mode", Some("ft4"), None), None, false);
    assert_eq!(
        result,
        Err("select_band_first"),
        "stale prior-profile physical frequency cannot choose a manual band"
    );
    let after = r.selection_snapshot(false).unwrap();
    assert_eq!(after["operating_revision"], before["operating_revision"]);
    assert_eq!(after["generation"], before["generation"]);
    assert_eq!(after["operation"], before["operation"]);
    assert_eq!(after["receive"], before["receive"]);
    assert_eq!(rig.lock().unwrap().writes.len(), writes);
    let explicit = selection_intent(&r, "band", None, Some("20m"));
    {
        let s = r.state.lock().unwrap();
        assert_eq!(
            r.selection_preflight(&s, &explicit, false).unwrap().band,
            "20m"
        );
    }
    actor.request_close();
}

#[test]
fn review_frequency_inference_requires_profile_boot_and_connection_authority() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (actor, _) = crate::radio_http_tests::actor(r.profile.clone(), r.boot.clone(), 0, false);
    r.fixture_radio(actor.clone());
    let good = actor.snapshot().unwrap();
    for mismatch in 0..3 {
        let mut wrong = good.clone();
        match mismatch {
            0 => wrong.authority.profile_id = profile::new_uuid().unwrap(),
            1 => wrong.authority.boot_id = profile::new_uuid().unwrap(),
            _ => wrong.authority.connection_generation += 1,
        }
        let intent = selection_intent(&r, "mode", Some("ft4"), None);
        let mut s = r.state.lock().unwrap();
        s.operating.radio.cached = Some(wrong);
        assert_eq!(
            r.selection_preflight(&s, &intent, false).err(),
            Some("select_band_first")
        );
        assert_eq!(s.operating.revision, 0);
        assert!(s.job.is_none());
    }
    actor.request_close();
}

// Proves: TC-009-005
#[test]
fn a_selection_refused_by_the_selection_rule_changes_nothing() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let refused = |intent: selection::Intent, cat: bool, expected: &str| {
        let (revision, generation) = {
            let s = r.state.lock().unwrap();
            (s.operating.revision, s.generation)
        };
        assert_eq!(r.selection_begin(intent, None, cat).unwrap_err(), expected);
        let s = r.state.lock().unwrap();
        assert_eq!(
            (s.operating.revision, s.generation, s.operating.nominal.band),
            (revision, generation, None),
            "{expected}"
        );
    };
    let band = |r: &Recording| selection_intent(r, "band", None, Some("40m"));
    let mut intent = band(&r);
    intent.profile_revision += 1;
    refused(intent, false, "state_conflict");
    let mut intent = band(&r);
    intent.revision += 1;
    refused(intent, false, "state_conflict");
    r.state.lock().unwrap().operating.operation =
        Some(pending_selection(&profile::new_uuid().unwrap(), 0));
    refused(band(&r), false, "busy");
    r.state.lock().unwrap().operating.operation = None;
    let reserved = r.reserve(&r.profile, &r.boot, 0).unwrap();
    refused(band(&r), false, "busy");
    r.cancel_import(reserved["id"].as_str().unwrap()).unwrap();
    r.state.lock().unwrap().job = Some(Job {
        id: profile::new_uuid().unwrap(),
        source_id: Some(profile::new_uuid().unwrap()),
        generation: 1,
        kind: "spectrum",
        state: "running",
        processed_frames: 0,
        error: None,
        cancel: Arc::new(AtomicBool::new(false)),
    });
    refused(band(&r), false, "busy");
    r.state.lock().unwrap().job = None;
    refused(
        selection_intent(&r, "band", Some("ft4"), Some("160m")),
        false,
        "selection_unavailable",
    );
    refused(band(&r), true, "radio_unavailable");
    assert!(r.flex.set(ScriptedSession::new()).is_ok());
    refused(band(&r), false, "radio_unavailable");
}

// Proves: TC-009-005
#[test]
fn a_cancel_it_does_not_carry_out_is_refused_and_changes_nothing() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let uuid = || profile::new_uuid().unwrap();
    let cancel = |command: &str, target: &str, revision: u64| {
        r.selection_cancel(&r.profile, &r.boot, command.into(), target.into(), revision)
    };
    let target = uuid();
    {
        let mut s = r.state.lock().unwrap();
        s.operating.revision = 1;
        s.operating.operation = Some(pending_selection(&target, 1));
    }
    // Neither the revision the selection was made from nor the one it was admitted at.
    assert_eq!(
        cancel(&uuid(), &target, 5).unwrap_err(),
        "operation_superseded"
    );
    // The operating revision has moved since the selection was admitted.
    r.state.lock().unwrap().operating.revision = 2;
    assert_eq!(
        cancel(&uuid(), &target, 1).unwrap_err(),
        "operation_superseded"
    );
    // An unseen command id while a selection is pending.
    assert_eq!(
        cancel(&uuid(), &uuid(), 2).unwrap_err(),
        "operation_superseded"
    );
    {
        let s = r.state.lock().unwrap();
        assert_eq!(s.operating.revision, 2);
        assert_eq!(s.operating.operation.as_ref().unwrap().result, "pending");
        assert!(s.operating.cancellation.is_none());
    }
    // An unseen command id from another revision.
    r.state
        .lock()
        .unwrap()
        .operating
        .operation
        .as_mut()
        .unwrap()
        .result = "success";
    assert_eq!(
        cancel(&uuid(), &uuid(), 1).unwrap_err(),
        "operation_superseded"
    );
    // A fence, then the same cancel with another target or revision.
    let (command, unseen) = (uuid(), uuid());
    let (receipt, repeated) = cancel(&command, &unseen, 2).unwrap();
    assert!(!repeated);
    assert_eq!(receipt["operating_revision"], 3);
    assert_eq!(cancel(&command, &uuid(), 2).unwrap_err(), "state_conflict");
    assert_eq!(cancel(&command, &unseen, 3).unwrap_err(), "state_conflict");
    assert_eq!(cancel(&command, &unseen, 2).unwrap(), (receipt, true));
    // The fenced selection, arriving from the revision it was made at.
    let mut late = selection_intent(&r, "band", None, Some("40m"));
    late.command_id = unseen;
    late.revision = 2;
    assert_eq!(
        r.selection_begin(late, None, false).unwrap_err(),
        "state_conflict"
    );
    assert_eq!(r.state.lock().unwrap().operating.revision, 3);
}

// Proves: TC-009-008
#[test]
fn the_dial_is_not_taken_while_a_selection_pends_or_on_another_revision() {
    use crate::cat_lifecycle::{Gate, Key};
    use crate::cat_lifecycle_tests::{Device, ENDPOINT, attach_peer};
    let gate = Gate::Eligible {
        key: Key {
            radio_id: "00000000-0000-4000-8000-0000000000aa".into(),
            safety_revision: 1,
            profile_revision: 0,
            endpoint: ENDPOINT.into(),
        },
        configuration: wstx_rust::radio_control::Configuration::parse(ENDPOINT).unwrap(),
    };
    for pending in [true, false] {
        let fixture = Fixture::new();
        let r = fixture.recording();
        attach_peer(&r, Device::Present);
        let t0 = Instant::now();
        r.cat_maintain(&gate, t0);
        let deadline = Instant::now() + Duration::from_secs(5);
        while r.radio_actor().map(|a| a.snapshot().unwrap().state)
            != Some(wstx_rust::radio_control::State::Ready)
        {
            assert!(
                Instant::now() < deadline,
                "the connection did not become ready"
            );
            std::thread::sleep(Duration::from_millis(2));
        }
        if pending {
            r.state.lock().unwrap().operating.operation =
                Some(pending_selection(&profile::new_uuid().unwrap(), 0));
        } else {
            r.initialize_profile_revision(5);
        }
        r.cat_maintain(&gate, t0 + Duration::from_millis(100));
        {
            let s = r.state.lock().unwrap();
            assert_eq!(
                (s.operating.nominal.band, s.operating.nominal.origin),
                (None, "unknown"),
                "pending {pending}"
            );
        }
        // Without the pending selection, on the connection's revision, the dial is taken.
        if pending {
            r.state.lock().unwrap().operating.operation = None;
        } else {
            r.initialize_profile_revision(0);
        }
        r.cat_maintain(&gate, t0 + Duration::from_millis(200));
        assert_eq!(
            r.state.lock().unwrap().operating.nominal.band,
            Some("40m"),
            "pending {pending}"
        );
        r.radio_actor().unwrap().request_close();
    }
}
