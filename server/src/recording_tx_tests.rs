//! #61 Tx periods (CL-061-04, TC-061-005): the station neither decodes nor measures the Rx
//! level in a period it transmitted in, and marks that period's waterfall rows. Cost 2,
//! Windows PC; no hardware. The Tx periods are noted directly on the station's Tx period
//! record, an explicit fixture of the transmit owner's observation.
use super::*;

/// Station UTC milliseconds of an RFC 3339 period start (independent of the code under test:
/// the hand-written FILETIME epoch offset).
fn ms(utc: &str) -> i64 {
    (filetime_from_utc(utc).unwrap() as i64 - 116_444_736_000_000_000) / 10_000
}

/// Queued live blocks of one source; Pending when empty.
struct Blocks {
    descriptor: Arc<SourceDescriptor>,
    queue: Arc<Mutex<VecDeque<SampleBlock>>>,
}
impl SampleSource for Blocks {
    fn descriptor(&self) -> Option<Arc<SourceDescriptor>> {
        Some(self.descriptor.clone())
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
        self.queue
            .lock()
            .unwrap()
            .pop_front()
            .map(SourcePoll::Block)
            .unwrap_or(SourcePoll::Pending)
    }
}
impl LiveInput for Blocks {
    fn start(&mut self) -> std::result::Result<(), source::SourceError> {
        Ok(())
    }
    fn request_stop(&mut self) {}
    fn status(&self) -> audio::AudioStatus {
        audio::AudioStatus {
            state: audio::AudioState::Running,
            error: None,
            retry_after_ms: None,
        }
    }
}

/// Router test seam (#66, TC-066-002): the actual live worker of the injected live job
/// (`fixture_live_job`, FT8), its capture clock putting canonical frame 0 at station UTC
/// `anchor_ms` (a period start), fed with silent blocks. The worker observes the station's own
/// transmit owner (on the Router the hardware double) at each block, as live.
pub(crate) struct Capture {
    worker: LiveWorker,
    queue: Arc<Mutex<VecDeque<SampleBlock>>>,
    context: source::SourceContext,
    anchor_ms: i64,
    next: u64,
}
impl Capture {
    /// Feeds the blocks of the capture up to station UTC `until_ms`; the detailed rows completed
    /// meanwhile, each as (the station UTC of its first frame, whether its frame is marked tx).
    pub(crate) fn until(&mut self, until_ms: i64) -> Vec<(i64, bool)> {
        let end = u64::try_from((until_ms - self.anchor_ms) * 12).unwrap();
        let mut rows = Vec::new();
        while self.next < end {
            let count = (end - self.next).min(source::LIVE_BLOCK_FRAMES as u64);
            let samples: Arc<[f32]> = Arc::from(vec![0.0; count as usize]);
            self.queue.lock().unwrap().push_back(
                SampleBlock::live(&self.context, self.next, samples, self.next == 0).unwrap(),
            );
            self.next += count;
            assert!(self.worker.step().unwrap().is_none());
            let mut s = self.worker.owner.state.lock().unwrap();
            rows.extend(s.detail_recent.drain(..).map(|f| {
                let first = f["data"]["first_frame"].as_i64().unwrap();
                (self.anchor_ms + first / 12, f["data"].get("tx").is_some())
            }));
        }
        rows
    }
}
impl Recording {
    pub(crate) fn fixture_capture(self: &Arc<Self>, anchor_ms: i64) -> Capture {
        relative_clock(
            self,
            "ft8",
            &crate::contact_http_tests::period_text(anchor_ms),
            0,
        );
        let (job, context) = {
            let s = self.state.lock().unwrap();
            let l = s.live.as_ref().unwrap();
            (
                s.job.clone().unwrap(),
                source::SourceContext {
                    descriptor: l.source.clone().unwrap(),
                    timing: Arc::new(l.timing.clone().unwrap()),
                },
            )
        };
        let queue = Arc::new(Mutex::new(VecDeque::new()));
        let input = Blocks {
            descriptor: context.descriptor.clone(),
            queue: queue.clone(),
        };
        Capture {
            worker: LiveWorker::new(self.clone(), job, Box::new(input), "ft8"),
            queue,
            context,
            anchor_ms,
            next: 0,
        }
    }
}

// Proves: CL-061-04; TC-061-005. The noted Tx period 12:00:15 gets no decode attempt and a
// transmitted view; the receive period after it is decoded as before.
#[test]
fn tx_period_has_no_decode_attempt_and_publishes_a_transmitted_view() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (job, _) = live_ring(&r);
    relative_clock(&r, "ft8", "2026-10-27T12:00:00.0000000Z", 0);
    r.state.lock().unwrap().live.as_mut().unwrap().next_frame = 540000;
    let tx = ms("2026-10-27T12:00:15.0000000Z");
    r.tx.lock().unwrap().note(tx + 2000, true, None, 15000);
    r.tx.lock()
        .unwrap()
        .note(tx + 13600, false, Some(tx), 15000);
    let input = crate::receive_http_tests::Input::queued().0;
    let mut worker = LiveWorker::new(r.clone(), job, Box::new(input), "ft8");
    let attempts = r.decoder_activity().1;
    // The prompt window of 12:00:15 (+13.8 s, 15 s of audio).
    worker
        .analyze(receive::AnalysisWindow {
            origin: 165600,
            samples: vec![0.0; 180000],
            waits: false,
        })
        .unwrap();
    let view = r.receive_snapshot()["job"]["latest_decode"].clone();
    assert_eq!(view["period_start_utc"], "2026-10-27T12:00:15.0000000Z");
    assert_eq!(view["transmitted"], true, "{view}");
    assert_eq!(view["complete"], false);
    assert_eq!(view["first_sequence"], view["next_sequence"]);
    assert_eq!(r.decoder_activity().1, attempts, "no decode attempt");
    // Its late window (+15.7 s) keeps that view.
    worker
        .analyze(receive::AnalysisWindow {
            origin: 188400,
            samples: vec![0.0; 180000],
            waits: true,
        })
        .unwrap();
    assert_eq!(r.receive_snapshot()["job"]["latest_decode"], view);
    assert_eq!(r.decoder_activity().1, attempts, "no decode attempt");
    // 12:00:30 is a receive period: decoded, complete, no transmitted key.
    worker
        .analyze(receive::AnalysisWindow {
            origin: 345600,
            samples: vec![0.0; 180000],
            waits: false,
        })
        .unwrap();
    let s = r.receive_snapshot();
    let next = &s["job"]["latest_decode"];
    assert_eq!(next["period_start_utc"], "2026-10-27T12:00:30.0000000Z");
    assert_eq!(next["complete"], true);
    assert!(next.get("transmitted").is_none(), "{next}");
    assert_eq!(r.decoder_activity().1, attempts + 1);
    let page = r
        .receive_results(
            s["source"]["id"].as_str().unwrap(),
            s["job"]["id"].as_str().unwrap(),
            1,
            next["first_sequence"].as_u64().unwrap(),
            16,
        )
        .unwrap();
    assert_eq!(page["latest_decode"], *next);
}

// Proves: CL-061-04, CL-039-09; TC-061-005. No Rx level while on the air or in the rest of a Tx
// period; Tx rows are marked; the next receive period measures again. Capture is never stopped.
// Neither Tx period is kept in the per-period waterfall power (#66).
#[test]
fn tx_period_measures_no_level_and_marks_its_waterfall_rows() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (job, _) = live_ring(&r);
    relative_clock(&r, "ft8", "2026-10-27T12:00:00.0000000Z", 0);
    let context = {
        let mut s = r.state.lock().unwrap();
        let l = s.live.as_mut().unwrap();
        // The level of the receive period before the transmission.
        l.level = (0.0, 0, None, Some(60));
        source::SourceContext {
            descriptor: l.source.as_ref().unwrap().clone(),
            timing: Arc::new(l.timing.as_ref().unwrap().clone()),
        }
    };
    assert_eq!(r.rx_level(), Some(60));
    let queue = Arc::new(Mutex::new(VecDeque::new()));
    let input = Blocks {
        descriptor: context.descriptor.clone(),
        queue: queue.clone(),
    };
    let identity = (job.id.clone(), job.generation);
    let mut worker = LiveWorker::new(r.clone(), job, Box::new(input), "ft8");
    let run = |worker: &mut LiveWorker, first: u64, count: u64, amplitude: f32| {
        for k in 0..count {
            let start = first + 240 * k;
            queue.lock().unwrap().push_back(
                SampleBlock::live(&context, start, Arc::from(vec![amplitude; 240]), k == 0)
                    .unwrap(),
            );
            assert!(worker.step().unwrap().is_none());
        }
    };
    let rows = |r: &Recording| {
        let mut s = r.state.lock().unwrap();
        let rows = s
            .detail_recent
            .iter()
            .map(|f| f["data"].get("tx").cloned())
            .collect::<Vec<_>>();
        s.detail_recent.clear();
        rows
    };
    // 12:00:15 was transmitted in; PTT is released at +13.6 s (the rest of the Tx period).
    let tx = ms("2026-10-27T12:00:15.0000000Z");
    r.tx.lock()
        .unwrap()
        .note(tx + 13600, false, Some(tx), 15000);
    run(&mut worker, 300000, 40, 0.9);
    assert_eq!(r.rx_level(), None, "no level in the rest of the Tx period");
    let marked = rows(&r);
    assert!(!marked.is_empty());
    assert!(marked.iter().all(|t| t == &Some(json!(true))), "{marked:?}");
    // 12:00:30 is a receive period: rows unmarked, a level after 1 s of samples.
    run(&mut worker, 360000, 40, 0.01);
    let unmarked = rows(&r);
    assert!(!unmarked.is_empty());
    assert!(unmarked.iter().all(Option::is_none), "{unmarked:?}");
    std::thread::sleep(Duration::from_millis(1100));
    run(&mut worker, 369600, 1, 0.01);
    assert_eq!(r.rx_level(), Some(50), "-40 dBFS DC in a receive period");
    // On the air again (12:00:30 becomes a Tx period): no level at once, rows marked.
    r.tx.lock()
        .unwrap()
        .note(tx + 15000 + 9900, true, Some(tx), 15000);
    assert_eq!(r.rx_level(), None, "no level while on the air");
    run(&mut worker, 372000, 40, 0.01);
    let keyed = rows(&r);
    assert!(!keyed.is_empty());
    assert!(keyed.iter().all(|t| t == &Some(json!(true))), "{keyed:?}");
    // #66 WstxStrategy::FreeTxSlot: neither Tx period is kept in the per-period power, also
    // 12:00:30, keyed late (its rows before the keying unmarked).
    let kept: Vec<i64> = r
        .waterfall
        .lock()
        .unwrap()
        .periods(
            (&identity.0, identity.1),
            ms("2026-10-27T12:01:00.0000000Z"),
        )
        .iter()
        .map(|p| p.start_ms - tx)
        .collect();
    assert_eq!(kept, Vec::<i64>::new(), "periods kept, from 12:00:15");
    let s = r.receive_snapshot();
    assert_eq!(s["audio"]["state"], "running");
    assert_eq!(s["audio"]["loss_epochs"], 0, "capture is never restarted");
}

// Proves: CL-061-04; TC-061-005. The actual transmit owner (frozen-clock hardware double, no
// radio) puts the station on the air with Tune: the Rx level is unavailable at once, the live
// worker resets its measurement and marks the block's period, and the period start on the
// mode's grid (FT8 15 s, FT4 7.5 s) stays a Tx period after the release.
#[test]
fn transmit_owner_on_the_air_records_the_tx_period_and_suspends_the_level() {
    for (mode, now, start) in [
        (
            "ft8",
            "2026-10-27T12:00:23.0000000Z",
            "2026-10-27T12:00:15.0000000Z",
        ),
        (
            "ft4",
            "2026-10-27T12:00:23.0000000Z",
            "2026-10-27T12:00:22.5000000Z",
        ),
    ] {
        let fixture = Fixture::new();
        let r = fixture.recording();
        let (job, _) = live_ring(&r);
        relative_clock(&r, mode, "2026-10-27T12:00:00.0000000Z", 0);
        r.state.lock().unwrap().operating_mode = mode;
        let bench = crate::contact_http_tests::Bench::default();
        bench.frozen.store(ms(now), Ordering::SeqCst);
        let station = crate::transmit_http::Station::start_with(Box::new(bench)).unwrap();
        let _ = r.transmit.set(station.clone());
        let context = {
            let mut s = r.state.lock().unwrap();
            let l = s.live.as_mut().unwrap();
            l.level = (0.0, 0, None, Some(60));
            source::SourceContext {
                descriptor: l.source.as_ref().unwrap().clone(),
                timing: Arc::new(l.timing.as_ref().unwrap().clone()),
            }
        };
        assert_eq!(r.rx_level(), Some(60), "{mode}: receiving");
        station.service.with(|c| {
            c.arm(3).unwrap();
            c.set_tune(true, 1500).unwrap();
        });
        assert_eq!(r.rx_level(), None, "{mode}: no level while on the air");
        // A block of a receive period (12:01:00) while on the air: the measurement is reset.
        let queue = Arc::new(Mutex::new(VecDeque::from([SampleBlock::live(
            &context,
            720000,
            Arc::from(vec![0.5; 240]),
            true,
        )
        .unwrap()])));
        let mut worker = LiveWorker::new(
            r.clone(),
            job,
            Box::new(Blocks {
                descriptor: context.descriptor.clone(),
                queue,
            }),
            mode,
        );
        assert!(worker.step().unwrap().is_none());
        assert_eq!(
            r.state.lock().unwrap().live.as_ref().unwrap().level,
            (0.0, 0, None, None),
            "{mode}: no level accumulated while on the air"
        );
        station.service.with(|c| c.set_tune(false, 1500).unwrap());
        r.observe_transmit();
        let tx = r.tx.lock().unwrap();
        assert!(!tx.keyed, "{mode}: released");
        assert!(
            tx.contains(ms(start)),
            "{mode}: the Tx period {start} is recorded"
        );
        assert_eq!(tx.starts.len(), 1, "{mode}: only that period");
    }
}
