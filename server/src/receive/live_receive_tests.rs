use super::*;

// Source clock metadata never invents external accuracy.
// Timing: clock
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

// Independent hand-calculated UTC/frame vectors.
// Proves: TC-007-006, TC-007-012
// Timing: signal
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

// Actual numerical silence completes; result inputs are explicit manager fixtures.
// Proves: TC-007-006, TC-007-012
// Timing: signal
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
            waits: false,
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
            waits: false,
        })
        .unwrap();
    let s = r.receive_snapshot();
    let empty = &s["job"]["latest_decode"];
    assert_eq!(empty["id"], 2);
    assert_eq!(empty["first_sequence"], 19);
    assert_eq!(empty["next_sequence"], 19);
    assert_eq!(empty["period_start_utc"], "2026-10-27T12:00:30.0000000Z");
}

// Actual cooperative numerical/manager overrun, not a pre-labelled wire response.
// Proves: TC-007-006, TC-007-012
// Timing: signal
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
        activity: Default::default(),
        running: true,
    };
    let mut worker = LiveWorker::new(r.clone(), job, Box::new(input), "ft8");
    worker.window = Some(window);
    worker.spectrum.reset(359760);
    worker
        .analyze(receive::AnalysisWindow {
            origin: 0,
            samples: vec![0.0; 180000],
            waits: false,
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

// A late window waits for the prompt decode instead of abandoning it.
// Proves: TC-004-004
#[test]
fn late_window_waits_for_the_prompt_decode_without_overrun() {
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
    let mut window = receive::WindowBuffer::new(decoder::Mode::Ft8, context.descriptor.clone())
        .unwrap()
        .with_schedule(&[(0, 180000, true)]);
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
        activity: Default::default(),
        running: true,
    };
    let mut worker = LiveWorker::new(r.clone(), job, Box::new(input), "ft8");
    worker.window = Some(window);
    worker.spectrum.reset(359760);
    worker
        .analyze(receive::AnalysisWindow {
            origin: 0,
            samples: vec![0.0; 180000],
            waits: false,
        })
        .unwrap();
    let observed = views.lock().unwrap();
    assert!(
        observed.iter().all(|v| v["complete"] == true),
        "the waiting window must not cut the decode in progress: {observed:?}"
    );
    let s = r.receive_snapshot();
    assert!(s["job"]["last_overrun"].is_null());
    assert_eq!(s["job"]["latest_decode"]["id"], 2);
    assert_eq!(s["job"]["latest_decode"]["complete"], true);
}

// The actual live worker marks each analysis window's
// decode (the UDP Status decoding flag) while it runs and clears it when it returns,
// observed from the capture poll the decode in progress drives, also when a window
// abandons the decode before it as an overrun.
// Proves: TC-012-007
#[test]
fn live_worker_marks_decoding_for_each_window_and_clears_it_after() {
    for late in [true, false] {
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
        if late {
            window = window.with_schedule(&[(0, 180000, true)]);
        }
        for first in (180000..359760).step_by(240) {
            assert!(window.push(&block(first)).unwrap().window.is_none());
        }
        r.state.lock().unwrap().live.as_mut().unwrap().next_frame = 359760;
        let activity = Arc::new(Mutex::new(vec![]));
        let next = block(359760);
        let input = DecodeBoundaryInput {
            context,
            next: Some(next),
            owner: r.clone(),
            views: Default::default(),
            activity: activity.clone(),
            running: true,
        };
        assert_eq!(r.decoder_activity(), (false, 0), "idle before any window");
        let mut worker = LiveWorker::new(r.clone(), job, Box::new(input), "ft8");
        worker.window = Some(window);
        worker.spectrum.reset(359760);
        worker
            .analyze(receive::AnalysisWindow {
                origin: 0,
                samples: vec![0.0; 180000],
                waits: false,
            })
            .unwrap();
        // Hand table: window 1 decodes (true, 1); window 2 (the waiting late window, or the
        // overrun replacement) decodes (true, 2); both returned: (false, 2).
        let seen = activity.lock().unwrap().clone();
        assert_eq!(seen.first(), Some(&(true, 1)), "late {late}: {seen:?}");
        assert!(seen.contains(&(true, 2)), "late {late}: {seen:?}");
        assert!(
            seen.iter().all(|a| a.0),
            "polled only while decoding: {seen:?}"
        );
        assert_eq!(r.decoder_activity(), (false, 2), "late {late}");
    }
}

// Real terminal owner path preserves last view, never an invented completion.
// Proves: TC-007-006, TC-007-012
#[test]
fn latest_decode_cancel_and_failure_preserve_published_period_without_new_identity() {
    for cancelled in [false, true] {
        let fixture = Fixture::new();
        let r = fixture.recording();
        let (job, decoded) = live_ring(&r);
        r.publish_decode(&job, &decoded).unwrap();
        r.publish_latest_decode(&job, (0, 180000), 0, false, false)
            .unwrap();
        let before = r.receive_snapshot()["job"]["latest_decode"].clone();
        r.state.lock().unwrap().decode_counter = source::MAX_COUNTER;
        assert_eq!(
            r.publish_latest_decode(&job, (0, 180000), 0, false, false),
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

// Hand-calculated residues from a correlated UTC anchor.
// Proves: TC-004-004
#[test]
fn live_window_schedule_follows_the_utc_period_grid() {
    let timing = |anchor: Option<&str>, frame: u64| source::SourceTiming {
        source_id: "s".into(),
        segment: 0,
        native_rate: 48000,
        native_anchor_frame: 0.0,
        canonical_anchor_frame: frame,
        converter_delay_native_frames: 0.0,
        qpc_anchor_100ns: Some(0),
        system_utc_anchor: anchor.map(Into::into),
        uncertainty_ns: Some(500),
        correlated: anchor.is_some(),
        external_accuracy: source::ExternalAccuracy::Unknown,
    };
    // 7.5 s into an FT8 period (= an FT4 period start) at canonical frame 1000:
    // FT8 +13.8 s/+15.7 s are 6.3 s/8.2 s later; FT4 +6.5 s/+7.9 s are 6.5 s/0.4 s later.
    let anchored = timing(Some("2026-11-01T19:23:07.5000000Z"), 1000);
    assert_eq!(
        window_schedule(&anchored, decoder::Mode::Ft8, 0),
        Some(vec![(76600, 180000, false), (99400, 180000, true)])
    );
    assert_eq!(
        window_schedule(&anchored, decoder::Mode::Ft4, 0),
        Some(vec![(79000, 90000, false), (5800, 90000, true)])
    );
    // A completion before the anchor wraps into the next period, modulo the advance.
    let late = timing(Some("2026-11-01T19:23:14.0000000Z"), 179000);
    assert_eq!(
        window_schedule(&late, decoder::Mode::Ft8, 0),
        Some(vec![(176600, 180000, false), (19400, 180000, true)])
    );
    assert_eq!(
        window_schedule(&timing(None, 0), decoder::Mode::Ft8, 0),
        None
    );
}

// Hand-calculated FT8 period starts for the SNR measurement
// Proves: TC-007-012
// Timing: signal
#[test]
fn ft8_snr_period_start_follows_the_utc_period_grid() {
    let timing = |anchor: Option<&str>| source::SourceTiming {
        source_id: "s".into(),
        segment: 0,
        native_rate: 48000,
        native_anchor_frame: 0.0,
        canonical_anchor_frame: 100000,
        converter_delay_native_frames: 0.0,
        qpc_anchor_100ns: Some(0),
        system_utc_anchor: anchor.map(Into::into),
        uncertainty_ns: Some(500),
        correlated: anchor.is_some(),
        external_accuracy: source::ExternalAccuracy::Unknown,
    };
    // Frame 100000 is 7.5 s into the 19:23:00 period, which began at frame 10000.
    let anchored = timing(Some("2026-11-01T19:23:07.5000000Z"));
    assert_eq!(
        period_start_frame(Some(&anchored), "ft8", 100000, 0),
        Some(10000)
    );
    assert_eq!(
        period_start_frame(Some(&anchored), "ft8", 172000, 0),
        Some(10000)
    );
    // 15.5 s: the 19:23:15 period began at frame 190000.
    assert_eq!(
        period_start_frame(Some(&anchored), "ft8", 196000, 0),
        Some(190000)
    );
    // A measured capture offset of +0.5 s moves the period start 6000 frames earlier.
    assert_eq!(
        period_start_frame(Some(&anchored), "ft8", 100000, 5_000_000),
        Some(4000)
    );
    // Before frame 0, and without a correlated clock: unknown.
    assert_eq!(period_start_frame(Some(&anchored), "ft8", 5000, 0), None);
    assert_eq!(
        period_start_frame(Some(&timing(None)), "ft8", 100000, 0),
        None
    );
    assert_eq!(period_start_frame(None, "ft8", 100000, 0), None);
}

// Re-anchoring keeps ordinary frames in the prompt window
// through more than 1 s of cumulative capture-clock drift and a clock step.
// Proves: TC-007-011
// Timing: signal
#[test]
fn drifting_capture_clock_keeps_prompt_windows_on_the_utc_period() {
    // 2000 ppm slow over 600 s accumulates 1.2 s, plus the 0.4 s step at 300 s.
    let (tracked, clock) = drifting_prompt_windows(true, 600, 2000.0);
    assert!(
        tracked.len() >= 38,
        "one prompt window per period: {}",
        tracked.len()
    );
    // After the first periods (the tracker's one-second average settles, and a correction
    // lands at the next due point) every prompt completes within 100 ms of +13.8 s UTC (the
    // 50 ms re-anchor threshold plus 30 ms of drift per period at this exaggerated rate)
    // and holds the DT 0 frame, including across the step.
    for (index, &(error, holds)) in tracked.iter().enumerate().skip(2) {
        assert!(
            error.abs() <= 0.1 && holds,
            "prompt {index}: completion error {error:.3} s, DT 0 frame held {holds}"
        );
    }
    assert!(
        clock["capture_drift_ms"].as_f64().unwrap() >= 1500.0,
        "{clock}"
    );
    let ppm = clock["capture_drift_ppm"].as_f64().unwrap();
    assert!((1800.0..2200.0).contains(&ppm), "{clock}");
    // Negative control: without re-anchoring the same capture completes its prompt window
    // more than 1 s late, past the +15.0 s deadline for every decode.
    let (fixed, _) = drifting_prompt_windows(false, 600, 2000.0);
    let last = fixed.last().unwrap();
    assert!(last.0 > 1.2, "fixed schedule drifted only {:.3} s", last.0);
}

// The clock from the air shifts the UTC reference
// of live windows, periods and DT on top of the measured capture drift: with the system
// clock 2 s ahead, prompt windows complete at +13.8 s of corrected UTC through 300 ppm of
// drift, none is lost or repeated, and the estimator is fed DT against the uncorrected
// system clock whatever correction is applied (no feedback loop).
// Proves: TC-004-004, TC-007-012
// Timing: clock
#[test]
fn air_correction_composes_with_capture_drift_and_never_feeds_its_own_estimate() {
    let (_fixture, r, clock, time, job, _) = air_station();
    let (context, timing) = {
        let s = r.state.lock().unwrap();
        let l = s.live.as_ref().unwrap();
        let timing = l.timing.as_ref().unwrap().clone();
        (
            source::SourceContext {
                descriptor: l.source.as_ref().unwrap().clone(),
                timing: Arc::new(timing.clone()),
            },
            timing,
        )
    };
    let anchor = filetime_from_utc("2026-11-01T00:00:00.0000000Z").unwrap() as f64;
    // 301 s: the last period's prompt completes 2 s later, at +300.8 s of system time.
    let total = 301 * 12000;
    // System UTC (100 ns) of canonical frame f: the capture clock runs 300 ppm slow.
    let system = |f: u64| anchor + f as f64 * (10_000_000.0 / 12000.0) * (1.0 + 300e-6);
    let input_clock = Arc::new(Mutex::new(None));
    let input = ClockInput {
        context: context.clone(),
        clock: input_clock.clone(),
    };
    let mut worker = LiveWorker::new(r.clone(), job.clone(), Box::new(input), "ft8");
    worker.window = Some(
        receive::WindowBuffer::new(decoder::Mode::Ft8, context.descriptor.clone())
            .unwrap()
            .with_schedule(&window_schedule(&timing, decoder::Mode::Ft8, 0).unwrap()),
    );
    let samples: Arc<[f32]> = Arc::from(vec![0.0; 240]);
    let mut prompts = vec![];
    let mut correction = 0.0;
    let mut first = 0;
    while first < total {
        if first == 150 * 12000 {
            // Twelve stations heard 2 s late against the system clock: windows of two
            // periods apply the -2000 ms correction, at most 1000 ms per period.
            clock.station.set_own_call("HB9BLA");
            for k in 0..2 {
                time.set_offset(Duration::from_millis(k * 15_000));
                for i in 0..12 {
                    clock.station.observe(&format!("K{i}ABC"), 2000, Some(-6.0));
                }
                clock.station.period_done(15_000);
            }
            time.set_offset(Duration::ZERO);
            assert_eq!(r.clock_correction(), -20_000_000);
            correction = -20_000_000.0;
        }
        let block = SampleBlock::live(&context, first, samples.clone(), false).unwrap();
        let outcome = worker.window.as_mut().unwrap().push(&block).unwrap();
        *input_clock.lock().unwrap() = Some((first, system(first) as u64));
        if let Some(drift) = worker.track_clock(Some(&timing)) {
            r.state.lock().unwrap().live.as_mut().unwrap().capture_drift = Some(drift);
        }
        if let Some(window) = outcome.window.filter(|w| !w.waits) {
            // Error of the completion against +13.8 s of corrected UTC.
            let completed =
                system(window.origin + window.samples.len() as u64) + correction - anchor;
            let slot = ((completed - 138_000_000.0) / 150_000_000.0).round() * 150_000_000.0;
            prompts.push((first, (completed - slot - 138_000_000.0) / 10_000_000.0));
        }
        first += 240;
    }
    assert_eq!(
        prompts.len(),
        20,
        "one prompt window per period, none lost or repeated"
    );
    for (index, &(at, error)) in prompts.iter().enumerate().skip(1) {
        assert!(
            error.abs() <= 0.1,
            "prompt {index} at frame {at}: completion error {error:.3} s"
        );
    }
    // Period and DT carry drift plus correction; the estimator gets the raw DT only.
    // Frame 204000 is 17.0 s after the anchor; with 0.5 s drift that is system 17.5 s:
    // raw DT +2.0 s in the 00:00:15 period, corrected 00:00:15 DT 0.0. They run on a second
    // station set up as the first, whose station clock is fresh (correction 0).
    let (_fixture, r, clock, _, job, mut decoded) = air_station();
    decoded.payload = decoder::unpack(&wstx_rust::transmit::pack("CQ K1ABC FN42").unwrap().bits);
    decoded.snr_db = Some(-7.0);
    decoded.start_frame = 204_000;
    for (applied, period, dt) in [
        (-20_000_000, "2026-11-01T00:00:15.0000000Z", 0.0),
        (0, "2026-11-01T00:00:15.0000000Z", 2.0),
    ] {
        {
            let mut s = r.state.lock().unwrap();
            let l = s.live.as_mut().unwrap();
            l.capture_drift = Some((5_000_000, None));
            l.clock_correction = applied;
            l.next_frame = 400_000;
        }
        r.publish_decode(&job, &decoded).unwrap();
        let s = r.state.lock().unwrap();
        let (record, _) = s.live.as_ref().unwrap().records.back().unwrap();
        assert_eq!(record["period_start_utc"], period);
        assert!(
            (record["dt_seconds"].as_f64().unwrap() - dt).abs() < 1e-6,
            "{record}"
        );
    }
    // Both fed raw DT 2000 ms: one station at median 2000 (a corrected feed gives 1000).
    clock.station.period_done(15_000);
    let (estimate, _) = clock.station.view().air.unwrap();
    assert_eq!((estimate.stations, estimate.median_dt_ms), (1, 2000));
}

// Both a new period view and the late window's growth
// of that view signal the Detailed WebSocket peers' publication watch.
#[test]
fn new_and_grown_views_signal_the_publication_watch() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (job, mut decoded) = live_ring(&r);
    relative_clock(&r, "ft8", "2026-10-27T12:00:00.0000000Z", 0);
    r.state.lock().unwrap().live.as_mut().unwrap().next_frame = 400000;
    let mut watch = r.publication.subscribe();
    let period = 180000;
    decoded.start_frame = period + 6000;
    r.publish_decode(&job, &decoded).unwrap();
    r.publish_latest_decode(&job, (period - 14400, period + 165600), 0, true, false)
        .unwrap();
    assert!(watch.has_changed().unwrap(), "a new view signals");
    watch.borrow_and_update();
    let id = r.receive_snapshot()["job"]["latest_decode"]["id"].clone();
    decoded.start_frame = period + 20400;
    decoded.payload.payload77 = "1".repeat(77);
    r.publish_decode(&job, &decoded).unwrap();
    r.publish_latest_decode(&job, (period + 8400, period + 188400), 1, true, true)
        .unwrap();
    let view = r.receive_snapshot()["job"]["latest_decode"].clone();
    assert_eq!(
        (view["id"].clone(), view["next_sequence"].clone()),
        (id, json!(2))
    );
    assert!(watch.has_changed().unwrap(), "a grown view signals");
}

// The FT8 late window (UTC +0.7..+15.7 s) extends its period's
// view under the same id: nothing new publishes nothing, a late starter (DT +1.2 s) only grows
// next_sequence, so the browser keeps its rows and cursor.
// Proves: TC-004-004
// Timing: signal
#[test]
fn late_window_republishes_its_period_view_with_late_starters() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (job, mut decoded) = live_ring(&r);
    relative_clock(&r, "ft8", "2026-10-27T12:00:00.0000000Z", 0);
    r.state.lock().unwrap().live.as_mut().unwrap().next_frame = 400000;
    // Prompt window of the 12:00:15 period: UTC +13.8 s, 15 s of audio.
    let period = 180000;
    decoded.start_frame = period + 6000;
    r.publish_decode(&job, &decoded).unwrap();
    r.publish_latest_decode(&job, (period - 14400, period + 165600), 0, true, false)
        .unwrap();
    let prompt = r.receive_snapshot()["job"]["latest_decode"].clone();
    assert_eq!(prompt["period_start_utc"], "2026-10-27T12:00:15.0000000Z");
    assert_eq!(
        (
            prompt["first_sequence"].clone(),
            prompt["next_sequence"].clone()
        ),
        (json!(0), json!(1))
    );
    let late = (period + 8400, period + 188400);
    // The live worker analyses the scheduled late window and publishes through its flag.
    let context = {
        let s = r.state.lock().unwrap();
        let l = s.live.as_ref().unwrap();
        source::SourceContext {
            descriptor: l.source.as_ref().unwrap().clone(),
            timing: Arc::new(l.timing.as_ref().unwrap().clone()),
        }
    };
    let input = ClockInput {
        context,
        clock: Arc::new(Mutex::new(None)),
    };
    let mut worker = LiveWorker::new(r.clone(), job.clone(), Box::new(input), "ft8");
    let mut analyse_late = || {
        worker
            .analyze(receive::AnalysisWindow {
                origin: late.0,
                samples: vec![0.0; (late.1 - late.0) as usize],
                waits: true,
            })
            .unwrap()
    };
    // A late window that adds nothing leaves the view and the whole snapshot unchanged.
    let before = r.receive_snapshot();
    analyse_late();
    assert_eq!(r.receive_snapshot(), before);
    // A DT +1.2 s frame found by the late window, which begins at +0.7 s and ends at +15.7 s:
    // the same view (same id) only grows next_sequence.
    decoded.start_frame = period + 20400;
    decoded.payload.payload77 = "1".repeat(77);
    r.publish_decode(&job, &decoded).unwrap();
    analyse_late();
    let view = r.receive_snapshot()["job"]["latest_decode"].clone();
    assert_eq!(view["period_start_utc"], "2026-10-27T12:00:15.0000000Z");
    assert_eq!(view["id"], prompt["id"]);
    assert_eq!(view["complete"], true);
    assert_eq!(
        (
            view["first_sequence"].clone(),
            view["next_sequence"].clone()
        ),
        (json!(0), json!(2))
    );
    let page = r
        .receive_results(job.source_id.as_ref().unwrap(), &job.id, 1, 1, 1)
        .unwrap();
    assert_eq!(
        page["records"][0]["period_start_utc"],
        "2026-10-27T12:00:15.0000000Z"
    );
    assert!((page["records"][0]["dt_seconds"].as_f64().unwrap() - 1.2).abs() < 1e-6);
    // The same interval from an ordinary (non-late) window still publishes nothing.
    r.publish_latest_decode(&job, late, 1, true, false).unwrap();
    assert_eq!(r.receive_snapshot()["job"]["latest_decode"], view);
}

// The live worker with a correlated UTC clock names
// the period start to the decoder, so the published FT8 SNR equals the file decode of the
// same period-aligned audio.
// Timing: signal
#[test]
fn live_ft8_snr_measures_from_the_utc_period_start() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (job, _) = live_ring(&r);
    relative_clock(&r, "ft8", "2026-10-27T12:00:00.0000000Z", 0);
    // Prompt window of the 12:00:30 period (frame 360000): UTC -1.2 s .. +13.8 s.
    let period = 360000usize;
    let origin = period - 14400;
    let audio = ft8_period_audio(origin + 180000, period);
    r.state.lock().unwrap().live.as_mut().unwrap().next_frame = (origin + 180000) as u64;
    let file = decoder::Decoder::new()
        .decode(&audio[period..period + 165600], decoder::Mode::Ft8, &|| {
            false
        })
        .unwrap();
    assert_eq!(file.len(), 1, "{file:?}");
    let expected = file[0].snr_db.unwrap();
    let context = {
        let s = r.state.lock().unwrap();
        let l = s.live.as_ref().unwrap();
        source::SourceContext {
            descriptor: l.source.as_ref().unwrap().clone(),
            timing: Arc::new(l.timing.as_ref().unwrap().clone()),
        }
    };
    let input = ClockInput {
        context,
        clock: Arc::new(Mutex::new(None)),
    };
    let mut worker = LiveWorker::new(r.clone(), job.clone(), Box::new(input), "ft8");
    worker
        .analyze(receive::AnalysisWindow {
            origin: origin as u64,
            samples: audio[origin..].to_vec(),
            waits: false,
        })
        .unwrap();
    let page = r
        .receive_results(job.source_id.as_ref().unwrap(), &job.id, 1, 0, 16)
        .unwrap();
    let records = page["records"].as_array().unwrap();
    assert_eq!(records.len(), 1, "{page}");
    assert_eq!(
        records[0]["period_start_utc"],
        "2026-10-27T12:00:30.0000000Z"
    );
    assert_eq!(records[0]["snr_db"].as_f64(), Some(expected), "{page}");
    // The window's diagnostics name the same period start.
    let w = &r.diagnostics_view()["windows"][0];
    assert_eq!(w["period_start_frame"], period);
    assert_eq!(w["window_offset_ms"], -1200);
}

// The live worker names the FT8 period
// start and the window diagnostics on station UTC (system clock plus the air-clock
// correction), the same timing the published records use. The system clock here is 2 s
// slow (anchor 11:59:58 at frame 0) and the correction +2 s puts station UTC 12:00:00 there,
// so the expected values are those of the uncorrected test above.
// Proves: TC-004-004
// Timing: signal
#[test]
fn live_ft8_period_start_and_window_diagnostics_follow_the_air_clock_correction() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (job, _) = live_ring(&r);
    relative_clock(&r, "ft8", "2026-10-27T11:59:58.0000000Z", 0);
    let period = 360000usize;
    let origin = period - 14400;
    let audio = ft8_period_audio(origin + 180000, period);
    {
        let mut s = r.state.lock().unwrap();
        let l = s.live.as_mut().unwrap();
        l.next_frame = (origin + 180000) as u64;
        l.clock_correction = 20_000_000;
    }
    let file = decoder::Decoder::new()
        .decode(&audio[period..period + 165600], decoder::Mode::Ft8, &|| {
            false
        })
        .unwrap();
    assert_eq!(file.len(), 1, "{file:?}");
    let expected = file[0].snr_db.unwrap();
    let context = {
        let s = r.state.lock().unwrap();
        let l = s.live.as_ref().unwrap();
        source::SourceContext {
            descriptor: l.source.as_ref().unwrap().clone(),
            timing: Arc::new(l.timing.as_ref().unwrap().clone()),
        }
    };
    let input = ClockInput {
        context,
        clock: Arc::new(Mutex::new(None)),
    };
    let mut worker = LiveWorker::new(r.clone(), job.clone(), Box::new(input), "ft8");
    worker
        .analyze(receive::AnalysisWindow {
            origin: origin as u64,
            samples: audio[origin..].to_vec(),
            waits: false,
        })
        .unwrap();
    let page = r
        .receive_results(job.source_id.as_ref().unwrap(), &job.id, 1, 0, 16)
        .unwrap();
    let records = page["records"].as_array().unwrap();
    assert_eq!(records.len(), 1, "{page}");
    assert_eq!(
        records[0]["period_start_utc"],
        "2026-10-27T12:00:30.0000000Z"
    );
    assert_eq!(records[0]["snr_db"].as_f64(), Some(expected), "{page}");
    let w = &r.diagnostics_view()["windows"][0];
    assert_eq!(w["period_start_frame"], period, "{w}");
    assert_eq!(w["period_start_utc"], "2026-10-27T12:00:30.0000000Z", "{w}");
    assert_eq!(w["window_offset_ms"], -1200, "{w}");
}

// The live publication fills hashed calls in from
// the calls heard so far and my call; earlier records keep their text; UDP Decode messages
// carry the same text; a hashed 'from' still gives no strategy facts.
// Proves: TC-024-002
#[test]
fn live_publication_fills_in_hashed_calls() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (job, mut decoded) = live_ring(&r);
    relative_clock(&r, "ft8", "2026-10-27T12:00:00.0000000Z", 0);
    r.state.lock().unwrap().live.as_mut().unwrap().next_frame = 400000;
    decoded.start_frame = 186000;
    r.set_my_call(Some("HB9BLA"));
    let publish = |text: &str| {
        let mut d = decoded.clone();
        d.payload = decoder::unpack(&wstx_rust::transmit::pack(text).unwrap().bits);
        r.publish_decode(&job, &d).unwrap();
        let s = r.state.lock().unwrap();
        s.live.as_ref().unwrap().records.back().unwrap().0.clone()
    };
    let early = publish("<VP2X/K1JT> W9XYZ -05");
    publish("CQ VP2X/K1JT");
    let later = publish("<VP2X/K1JT> W9XYZ -05");
    let mine = publish("<HB9BLA> VP2X/K1JT");
    let unknown = publish("<DL/K1ABC> W9XYZ");
    let reply = publish("W9XYZ <VP2X/K1JT> -07");
    let plain = publish("CQ W9XYZ EN37");
    let s = r.state.lock().unwrap();
    let records: Vec<Value> = s
        .live
        .as_ref()
        .unwrap()
        .records
        .iter()
        .map(|(v, _)| v.clone())
        .collect();
    drop(s);
    assert_eq!(
        records[0]["text"], "<...> W9XYZ -05",
        "no rewriting of history"
    );
    assert_eq!(early["fields"]["to"]["text"], Value::Null);
    assert_eq!(later["text"], "<VP2X/K1JT> W9XYZ -05");
    assert_eq!(
        later["fields"]["to"],
        json!({"kind":"hash","text":"VP2X/K1JT","hash_bits":22,
               "hash_value":decoder::ihashcall("VP2X/K1JT",22).unwrap()})
    );
    assert_eq!(mine["text"], "<HB9BLA> VP2X/K1JT");
    assert_eq!(unknown["text"], "<...> W9XYZ");
    assert_eq!(unknown["fields"]["to"]["text"], Value::Null);
    assert_eq!(reply["text"], "W9XYZ <VP2X/K1JT> -07");
    for record in [&early, &later, &mine, &unknown, &reply] {
        let udp = crate::udp::decode_of(record, "ft8").unwrap();
        assert_eq!(udp.message, record["text"].as_str().unwrap());
    }
    assert!(crate::strategy::facts(&reply).is_none());
    assert_eq!(crate::strategy::facts(&plain).unwrap().from, "W9XYZ");
    r.set_my_call(Some("HB9BLB"));
    assert_eq!(publish("<HB9BLB> VP2X/K1JT")["text"], "<HB9BLB> VP2X/K1JT");
}
