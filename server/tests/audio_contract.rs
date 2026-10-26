#![deny(unsafe_code)]
// Integration imports exercise the production module and canonical source contract directly.
#[path = "../src/audio.rs"]
pub mod audio;
#[path = "../src/source.rs"]
pub mod source;
use audio::*;
use source::*;
use std::sync::Arc;
fn format(rate: u32) -> NativeFormat {
    NativeFormat {
        rate,
        channels: 2,
        encoding: Encoding::Float32,
    }
}
fn bytes(samples: &[f32]) -> Vec<u8> {
    samples
        .iter()
        .flat_map(|x| x.to_le_bytes().into_iter().chain((-*x).to_le_bytes()))
        .collect()
}
fn signal(rate: u32, hz: f64, n: usize) -> Vec<f32> {
    (0..n)
        .map(|j| (std::f64::consts::TAU * hz * j as f64 / f64::from(rate)).sin() as f32)
        .collect()
}
// Proves: CL-008-02; TC-002-003. Independent complex DFT of every phase response.
#[test]
fn audio_filter_response() {
    for rate in [44100, 48000] {
        let c = Converter::new(rate).unwrap();
        for taps in c.response_taps() {
            for hz in (0..=3500)
                .step_by(25)
                .chain((5500..=rate as usize / 2).step_by(25))
            {
                let mut re = 0.0;
                let mut im = 0.0;
                for (j, t) in taps.iter().enumerate() {
                    let p = std::f64::consts::TAU * hz as f64 * j as f64 / f64::from(rate);
                    re += t * p.cos();
                    im -= t * p.sin();
                }
                let gain = (re * re + im * im).sqrt();
                if hz <= 3500 {
                    assert!((20.0 * gain.log10()).abs() <= 0.1, "{rate} {hz} {gain}");
                } else {
                    assert!(gain <= 0.001, "{rate} {hz} {gain}");
                }
            }
        }
    }
}
// Proves: CL-008-02; TC-002-003. Rational count independent of callback partition, no padded edges.
#[test]
fn audio_partition_count_delay() {
    for rate in [44100, 48000] {
        let x = signal(rate, 1000.0, rate as usize);
        let run = |sizes: &[usize]| {
            let mut c = Converter::new(rate).unwrap();
            let mut out = Vec::new();
            let mut at = 0;
            let mut j = 0;
            while at < x.len() {
                let end = (at + sizes[j % sizes.len()]).min(x.len());
                let (first, y) = c.convert(&x[at..end]).unwrap();
                assert_eq!(first, out.len() as u64);
                out.extend(y);
                at = end;
                j += 1;
            }
            out
        };
        let a = run(&[8192]);
        let b = run(&[1, 441, 37, 2048]);
        assert_eq!(a.len(), b.len());
        let expected = ((x.len() - FILTER_TAPS) * 12000 / (rate as usize)) + 1;
        assert_eq!(a.len(), expected);
        for (i, (a, b)) in a.iter().zip(b).enumerate() {
            assert!((a - b).abs() < 2e-5);
            let center = 128.0 + i as f64 * f64::from(rate) / 12000.0;
            let expected = (std::f64::consts::TAU * 1000.0 * center / f64::from(rate)).sin();
            assert!((f64::from(*a) - expected).abs() < 0.001);
        }
    }
}
// Proves: CL-008-02; TC-002-001/003. Channel0, integer extrema, nonfinite and alignment rejection.
#[test]
fn audio_native_normalization() {
    let f = format(48000);
    assert_eq!(
        f.channel_zero(&bytes(&[0.25, -1.0]), 2, false).unwrap(),
        [0.25, -1.0]
    );
    assert_eq!(f.channel_zero(&[], 3, true).unwrap(), [0.0; 3]);
    assert!(f.channel_zero(&[0; 3], 1, false).is_err());
    assert!(f.channel_zero(&bytes(&[f32::NAN]), 1, false).is_err());
    for (enc, data) in [
        (Encoding::Pcm16, vec![0, 128]),
        (Encoding::Pcm24, vec![0, 0, 128]),
        (Encoding::Pcm32, vec![0, 0, 0, 128]),
    ] {
        let f = NativeFormat {
            rate: 44100,
            channels: 1,
            encoding: enc,
        };
        assert_eq!(f.channel_zero(&data, 1, false).unwrap(), [-1.0]);
    }
}
fn acknowledge(source: &mut LiveSource, p: EpochProposal, id: &str) {
    let descriptor = Arc::new(SourceDescriptor {
        schema_version: 1,
        profile_id: "p".into(),
        boot_id: "b".into(),
        source_id: id.into(),
        rate_hz: 12000,
        channel: "mono_real",
        total_frames: None,
        utc_anchor: None,
    });
    let timing = SourceTiming {
        source_id: id.into(),
        segment: 0,
        native_rate: p.native_rate,
        native_anchor_frame: p.first_device_frame as f64 + 128.0,
        canonical_anchor_frame: 0,
        converter_delay_native_frames: 128.0,
        qpc_anchor_100ns: p.packet_qpc_100ns,
        system_utc_anchor: None,
        uncertainty_ns: None,
        correlated: false,
        external_accuracy: ExternalAccuracy::Unknown,
    };
    source
        .acknowledge_epoch(p.proposal_counter, descriptor, timing)
        .unwrap();
}
// Proves: CL-008-02/03; TC-002-001/003. Actual epoch acknowledgement and gaps without invented samples.
#[test]
fn audio_epoch_known_unknown_gap_and_cancel() {
    let f = format(48000);
    let q = PacketQueue::new(f).unwrap();
    let mut s = LiveSource::new(q.clone(), f).unwrap();
    let x = bytes(&vec![0.5; 480]);
    assert!(q.push(&x, 480, 1000, 10, 0));
    let SourcePoll::EpochChanged(p) = s.poll() else {
        panic!()
    };
    assert!(s.descriptor().is_none());
    assert!(matches!(s.poll(), SourcePoll::Pending));
    acknowledge(&mut s, p, "one");
    let SourcePoll::Block(b) = s.poll() else {
        panic!()
    };
    assert_eq!(b.first_frame, 0);
    assert_eq!(b.samples.len(), 56);
    assert!(b.discontinuity);
    assert!(q.push(&x, 480, 1960, 20, DATA_DISCONTINUITY));
    let SourcePoll::Block(b) = s.poll() else {
        panic!()
    };
    assert_eq!(b.first_frame, 240);
    assert!(b.discontinuity);
    assert!(q.push(&x, 480, 2440, 30, TIMESTAMP_ERROR));
    let SourcePoll::EpochChanged(p) = s.poll() else {
        panic!()
    };
    assert!(p.packet_qpc_100ns.is_none());
    acknowledge(&mut s, p, "two");
    let SourcePoll::Block(b) = s.poll() else {
        panic!()
    };
    assert_eq!(b.source.source_id, "two");
    assert_eq!(b.first_frame, 0);
    s.stop();
    assert!(matches!(
        s.poll(),
        SourcePoll::Failed(SourceError::Cancelled)
    ));
}
// Proves: CL-008-02/03; TC-002-003. Queue duration cap, explicit loss and bounded cancellation.
#[test]
fn audio_queue_and_clock_bounds() {
    let q = PacketQueue::new(format(48000)).unwrap();
    for i in 0..3 {
        assert!(q.push(&[], 8000, i * 8000, 0, SILENT));
    }
    assert_eq!(q.queued_frames(), 24000);
    assert!(!q.push(&[], 1, 24000, 0, SILENT));
    assert!(!q.push(&[], 8193, 24001, 0, SILENT));
    q.cancel();
    assert!(!q.push(&[], 1, 0, 0, SILENT));
    let packet_limited = PacketQueue::new(format(48000)).unwrap();
    for first in 0..64 {
        assert!(packet_limited.push(&[], 1, first, 0, SILENT));
    }
    assert!(!packet_limited.push(&[], 1, 64, 0, SILENT));
    assert_eq!(packet_limited.queued_frames(), 64);
    assert_eq!(packet_limited.diagnostics().queue_full, 1);
    let a = ClockCorrelation::bracket(100000, 1000000, 140000).unwrap();
    assert_eq!(a.uncertainty_ns, 2000000);
    assert!(ClockCorrelation::bracket(0, 0, 40001).is_none());
    let mut b = a;
    b.utc_filetime_100ns += 200000;
    assert!(!a.jumped(b));
    b.utc_filetime_100ns += 1;
    assert!(a.jumped(b));
    assert_eq!(a.utc_at(120001), Some(1000001));
}

// Proves: CL-008-02; TC-002-003. Available native FIFO capacity survives consumer bookkeeping.
#[test]
fn audio_consumer_bookkeeping_cannot_drop_an_admissible_native_packet() {
    let queue = PacketQueue::new(format(48000)).unwrap();
    let producer = queue.clone();
    let (start, ready) = std::sync::mpsc::sync_channel(0);
    let (done, result) = std::sync::mpsc::sync_channel(1);
    let worker = std::thread::spawn(move || {
        ready.recv().unwrap();
        done.send(producer.push(&[], 480, 0, 0, SILENT)).unwrap();
    });
    queue.with_consumer_bookkeeping(|| {
        start.send(()).unwrap();
        assert_eq!(
            result.recv_timeout(std::time::Duration::from_millis(250)),
            Ok(true),
            "consumer bookkeeping blocked/discarded an otherwise admissible native packet"
        );
    });
    worker.join().unwrap();
    assert_eq!(queue.queued_frames(), 480);
    assert_eq!(queue.diagnostics().queue_contention, 0);
    let mut source = LiveSource::new(queue, format(48000)).unwrap();
    assert!(matches!(source.poll(), SourcePoll::EpochChanged(_)));
}

// Proves: CL-008-02; TC-002-003. Exact bounded packet ownership recycles across ring wraps.
#[test]
fn audio_native_packet_buffers_recycle_without_loss_or_counter_drift() {
    let format = format(48000);
    let queue = PacketQueue::new(format).unwrap();
    let mut source = LiveSource::new(queue.clone(), format).unwrap();
    let bytes = bytes(&[0.5; 4]);
    let mut epochs = 0;
    let mut count = 0;
    let mut next = 0;
    for batch in 0..20 {
        for packet in 0..64 {
            let first = (batch * 64 + packet) * 4;
            if packet == 0 {
                queue.with_consumer_bookkeeping(|| assert!(queue.push(&bytes, 4, first, 0, 0)));
            } else {
                assert!(queue.push(&bytes, 4, first, 0, 0));
            }
        }
        assert_eq!(queue.queued_frames(), 256);
        for _ in 0..64 {
            match source.poll() {
                SourcePoll::EpochChanged(proposal) => {
                    epochs += 1;
                    acknowledge(&mut source, proposal, "recycled");
                }
                SourcePoll::Block(block) => {
                    assert_eq!(block.first_frame, next);
                    assert!(block.samples.iter().all(|v| (*v - 0.5).abs() < 1e-6));
                    count += block.samples.len() as u64;
                    next = count;
                }
                SourcePoll::Pending => {}
                _ => panic!("unexpected native source outcome"),
            }
        }
        assert_eq!(queue.queued_frames(), 0);
    }
    assert_eq!(count, 1216);
    assert_eq!(epochs, 1);
    let diagnostic = queue.diagnostics();
    assert_eq!(diagnostic.queue_contention, 0);
    assert_eq!(diagnostic.queue_full, 0);
    assert_eq!(diagnostic.pool_exhausted, 0);
}

// Proves: CL-008-02; TC-002-003. Impulse center and known-gap phase use an independent rational oracle.
#[test]
fn audio_impulse_and_large_gap_phase() {
    for rate in [44100, 48000] {
        let mut c = Converter::new(rate).unwrap();
        let mut x = vec![0.0; 4096];
        x[2000] = 1.0;
        let (_, y) = c.convert(&x).unwrap();
        let peak = y
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.abs().total_cmp(&b.1.abs()))
            .unwrap()
            .0;
        let sample_native = 128.0 + peak as f64 * f64::from(rate) / 12000.0;
        assert!((sample_native - 2000.0).abs() <= f64::from(rate) / 12000.0);
        let start = 8_000_000_000_000_001;
        let expected = (u128::from(start) * 12000).div_ceil(u128::from(rate)) as u64;
        c.reset_at(start).unwrap();
        let (first, out) = c.convert(&vec![0.0; 1000]).unwrap();
        assert_eq!(first, expected);
        let mut count = 0;
        while (u128::from(expected + count) * u128::from(rate) / 12000) + 257
            <= u128::from(start) + 1000
        {
            count += 1;
        }
        assert_eq!(out.len() as u64, count);
        assert!(c.reset_at(MAX_COUNTER + 1).is_err());
    }
}
// Proves: CL-008-02/03; TC-002-003. Overflow invalidates buffered samples before any old-context publication.
#[test]
fn audio_overflow_and_duplicate_epoch() {
    let f = format(44100);
    let q = PacketQueue::new(f).unwrap();
    let mut source = LiveSource::new(q.clone(), f).unwrap();
    let x = bytes(&vec![0.2; 4096]);
    q.push(&x, 4096, 0, 100, 0);
    let SourcePoll::EpochChanged(p) = source.poll() else {
        panic!()
    };
    acknowledge(&mut source, p.clone(), "initial");
    assert!(matches!(source.poll(), SourcePoll::Block(_)));
    assert!(!q.push(&[], 8193, 4096, 101, SILENT));
    q.push(&x, 4096, 4096, 102, 0);
    let SourcePoll::EpochChanged(next) = source.poll() else {
        panic!()
    };
    assert!(next.proposal_counter > p.proposal_counter);
    assert!(source.descriptor().is_none());
    assert!(matches!(source.poll(), SourcePoll::Pending));
    acknowledge(&mut source, next, "overflow");
    while matches!(source.poll(), SourcePoll::Block(_)) {}
    q.push(&x, 4096, 4096, 103, 0);
    let SourcePoll::EpochChanged(p) = source.poll() else {
        panic!()
    };
    acknowledge(&mut source, p, "duplicate");
    q.fail(SourceError::UnsupportedFormat);
    assert!(matches!(
        source.poll(),
        SourcePoll::Failed(SourceError::UnsupportedFormat)
    ));
    assert!(matches!(
        source.poll(),
        SourcePoll::Failed(SourceError::UnsupportedFormat)
    ));
}
// Proves: CL-008-03/05; TC-002-001/003/009-004. Backoff and explicit stop never rely on UTC.
#[test]
fn audio_lifecycle_retries() {
    let mut lifecycle = Lifecycle::default();
    assert_eq!(lifecycle.status(0).state, AudioState::Closed);
    lifecycle.request_start();
    let mut now = 100;
    for delay in [1000, 2000, 4000, 8000, 8000] {
        lifecycle.failed(SourceError::Unavailable, now);
        assert_eq!(lifecycle.status(now).retry_after_ms, Some(delay));
        assert!(!lifecycle.due(now + delay - 1));
        assert!(lifecycle.due(now + delay));
        now += delay;
        lifecycle.running();
    }
    lifecycle.request_stop();
    assert!(!lifecycle.due(u64::MAX));
    lifecycle.closed();
    assert_eq!(lifecycle.status(now).state, AudioState::Closed);
    for error in [
        SourceError::UnsupportedFormat,
        SourceError::CounterExhausted,
        SourceError::FailedClose,
        SourceError::InvalidBlock,
        SourceError::InvalidContext,
        SourceError::StaleAcknowledgement,
        SourceError::Cancelled,
    ] {
        lifecycle.request_start();
        lifecycle.failed(error, now);
        assert_eq!(lifecycle.status(now).retry_after_ms, None);
        assert!(!lifecycle.due(u64::MAX));
    }
}
// Proves: CL-008-03/05; TC-002-001/003. Actual controller isolates two packet drivers and acknowledges stop within250ms.
#[cfg(windows)]
#[test]
fn audio_controller_profiles_and_stop() {
    use std::time::{Duration, Instant};
    let (mut a, qa) = AudioController::packet_fixture("radio-A".into(), format(48000)).unwrap();
    let (mut b, qb) = AudioController::packet_fixture("radio-B".into(), format(44100)).unwrap();
    let start = Instant::now();
    while a.status().state != AudioState::Running || b.status().state != AudioState::Running {
        assert!(matches!(a.poll(), SourcePoll::Pending));
        assert!(matches!(b.poll(), SourcePoll::Pending));
        assert!(start.elapsed() < Duration::from_millis(250));
        std::thread::yield_now();
    }
    assert_eq!(a.selected_endpoint(), "radio-A");
    assert_eq!(b.selected_endpoint(), "radio-B");
    qa.push(&bytes(&vec![0.1; 480]), 480, 100, 5, 0);
    let SourcePoll::EpochChanged(p) = a.poll() else {
        panic!()
    };
    assert_eq!(p.native_rate, 48000);
    assert!(matches!(b.poll(), SourcePoll::Pending));
    assert_eq!(qb.queued_frames(), 0);
    let start = Instant::now();
    a.request_stop();
    assert!(a.descriptor().is_none());
    while a.status().state != AudioState::Closed {
        assert!(matches!(a.poll(), SourcePoll::Pending));
        assert!(start.elapsed() < Duration::from_millis(250));
        std::thread::yield_now();
    }
    assert_eq!(b.status().state, AudioState::Running);
    b.request_stop();
    let start = Instant::now();
    while b.status().state != AudioState::Closed {
        let _ = b.poll();
        assert!(start.elapsed() < Duration::from_millis(250));
        std::thread::yield_now();
    }
}

// Proves: CL-008-02; TC-002-003. Actual converter waveform gain/rejection, not only coefficient response.
#[test]
fn audio_waveform_response() {
    for rate in [44100, 48000] {
        for hz in [100.0, 1000.0, 3000.0, 3500.0, 5500.0, 6000.0, 9000.0] {
            let x = signal(rate, hz, rate as usize / 2);
            let mut converter = Converter::new(rate).unwrap();
            let mut out = Vec::new();
            for block in x.chunks(997) {
                out.extend(converter.convert(block).unwrap().1);
            }
            let rms =
                (out.iter().map(|v| f64::from(*v).powi(2)).sum::<f64>() / out.len() as f64).sqrt();
            if hz <= 3500.0 {
                let gain = 20.0 * (rms * 2.0_f64.sqrt()).log10();
                assert!(gain.abs() < 0.1, "{rate} {hz}: {gain}");
            } else {
                assert!(rms * 2.0_f64.sqrt() <= 0.001, "{rate} {hz}: {rms}");
            }
        }
    }
}

// Proves: CL-008-02/04; TC-002-001/003. Native driver metadata schema is independently encoded.
#[test]
fn audio_wave_format_validation() {
    for rate in [44100_u32, 48000] {
        for channels in [1_u16, 2] {
            for (tag, bits, encoding) in [
                (3_u16, 32_u16, Encoding::Float32),
                (1, 16, Encoding::Pcm16),
                (1, 24, Encoding::Pcm24),
                (1, 32, Encoding::Pcm32),
            ] {
                let align = channels * (bits / 8);
                let mut b = Vec::new();
                b.extend(tag.to_le_bytes());
                b.extend(channels.to_le_bytes());
                b.extend(rate.to_le_bytes());
                b.extend((rate * u32::from(align)).to_le_bytes());
                b.extend(align.to_le_bytes());
                b.extend(bits.to_le_bytes());
                b.extend(0_u16.to_le_bytes());
                assert_eq!(
                    NativeFormat::from_wave_format(&b).unwrap(),
                    NativeFormat {
                        rate,
                        channels,
                        encoding
                    }
                );
                let mut ext = b.clone();
                ext[0..2].copy_from_slice(&0xfffe_u16.to_le_bytes());
                ext[16..18].copy_from_slice(&22_u16.to_le_bytes());
                ext.extend(bits.to_le_bytes());
                ext.extend(3_u32.to_le_bytes());
                ext.extend([
                    tag as u8, 0, 0, 0, 0, 0, 16, 0, 128, 0, 0, 170, 0, 56, 155, 113,
                ]);
                assert_eq!(
                    NativeFormat::from_wave_format(&ext).unwrap().encoding,
                    encoding
                );
                for cut in 0..ext.len() {
                    assert!(NativeFormat::from_wave_format(&ext[..cut]).is_err());
                }
                ext[18] = 1;
                assert!(NativeFormat::from_wave_format(&ext).is_err());
                b[12] = 255;
                assert!(NativeFormat::from_wave_format(&b).is_err());
            }
        }
    }
    assert!(
        NativeFormat {
            rate: 12000,
            channels: 1,
            encoding: Encoding::Float32
        }
        .validate()
        .is_err()
    );
    assert!(
        NativeFormat {
            rate: 48000,
            channels: 3,
            encoding: Encoding::Float32
        }
        .validate()
        .is_err()
    );
}

// Proves: CL-008-02; TC-002-003. A failed bracket cannot conceal a later UTC jump.
#[test]
fn audio_clock_rejected_bracket_preserves_reference() {
    let a = ClockCorrelation::bracket(100, 1000, 102).unwrap();
    let mut previous = None;
    assert!(!ClockCorrelation::observe(&mut previous, Some(a)));
    assert!(!ClockCorrelation::observe(&mut previous, None));
    assert_eq!(previous, Some(a));
    let mut b = a;
    b.utc_filetime_100ns += 200_001;
    assert!(ClockCorrelation::observe(&mut previous, Some(b)));
    assert_eq!(previous, Some(b));
    assert!(!ClockCorrelation::observe(&mut previous, Some(b)));
}

// Proves: CL-008-02/04; TC-002-003. Failed Stop dominates read/cancel errors and
// retains every native owner plus its apartment until Stop acknowledges release.
#[cfg(windows)]
#[test]
fn audio_failed_stop_quarantines_owner_and_apartment_without_reopen() {
    use std::sync::{
        Condvar, Mutex,
        atomic::{AtomicBool, Ordering},
    };
    use std::time::{Duration, Instant};
    struct Guard(&'static str, Arc<Mutex<Vec<&'static str>>>);
    impl Drop for Guard {
        fn drop(&mut self) {
            self.1.lock().unwrap().push(self.0);
        }
    }
    struct Owner {
        _native: Guard,
        _apartment: Guard,
    }
    for prior in [
        Err(SourceError::Unavailable),
        Ok(()),
        Err(SourceError::Cancelled),
    ] {
        let dropped = Arc::new(Mutex::new(Vec::new()));
        let owner = Owner {
            _native: Guard("native", dropped.clone()),
            _apartment: Guard("apartment", dropped.clone()),
        };
        let released = Arc::new(AtomicBool::new(false));
        let stop_gate = released.clone();
        let wait = Arc::new((Mutex::new(()), Condvar::new()));
        let wait_worker = wait.clone();
        let mut controller = AudioController::capture_close_fixture(
            format(48000),
            owner,
            prior,
            move |_| {
                if stop_gate.load(Ordering::Acquire) {
                    Ok(())
                } else {
                    Err(SourceError::Unavailable)
                }
            },
            move || {
                let (lock, changed) = &*wait_worker;
                drop(
                    changed
                        .wait_timeout(lock.lock().unwrap(), Duration::from_millis(10))
                        .unwrap(),
                );
            },
        )
        .unwrap();
        let deadline = Instant::now() + Duration::from_secs(2);
        loop {
            if matches!(
                controller.poll(),
                SourcePoll::Failed(SourceError::FailedClose)
            ) {
                break;
            }
            assert!(Instant::now() < deadline);
            std::thread::sleep(Duration::from_millis(1));
        }
        assert!(dropped.lock().unwrap().is_empty());
        assert_eq!(controller.status().error, Some(SourceError::FailedClose));
        assert_eq!(controller.status().retry_after_ms, None);
        assert!(controller.descriptor().is_none());
        assert_eq!(controller.start(), Err(SourceError::Unavailable));
        for _ in 0..10 {
            assert!(matches!(controller.poll(), SourcePoll::Pending));
        }
        assert!(dropped.lock().unwrap().is_empty());
        released.store(true, Ordering::Release);
        wait.1.notify_all();
        while dropped.lock().unwrap().len() != 2 {
            assert!(Instant::now() < deadline);
            std::thread::sleep(Duration::from_millis(1));
        }
        assert_eq!(*dropped.lock().unwrap(), vec!["native", "apartment"]);
        for _ in 0..10 {
            assert!(matches!(controller.poll(), SourcePoll::Pending));
        }
        assert_eq!(controller.status().error, Some(SourceError::FailedClose));
        assert_eq!(controller.status().retry_after_ms, None);
    }
}

// Proves: CL-008-02; TC-002-003. Successful Stop releases normally and preserves the read outcome.
#[test]
fn audio_successful_stop_preserves_prior_outcome_without_quarantine() {
    for prior in [
        Ok(()),
        Err(SourceError::Unavailable),
        Err(SourceError::Cancelled),
    ] {
        let released = Arc::new(std::sync::atomic::AtomicBool::new(false));
        struct Owner(Arc<std::sync::atomic::AtomicBool>);
        impl Drop for Owner {
            fn drop(&mut self) {
                self.0.store(true, std::sync::atomic::Ordering::Release);
            }
        }
        let result = audio::finish_capture_owner(
            Owner(released.clone()),
            prior,
            |_| Ok(()),
            || panic!("successful Stop cannot report FailedClose"),
            || panic!("successful Stop cannot enter quarantine"),
        );
        assert_eq!(result, prior);
        assert!(released.load(std::sync::atomic::Ordering::Acquire));
    }
}
