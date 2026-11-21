#![deny(unsafe_code)]
// Integration imports exercise the production module and canonical source contract directly.
#[path = "../src/audio.rs"]
pub mod audio;
#[path = "../src/source.rs"]
pub mod source;
use audio::*;
use source::*;
use std::sync::Arc;
// The test-only model-value reader
// (harness/project/docs/specifics/local-windows-development.md, "Model values read by tests").
use wstx_test_tools::model_values;

/// A number of WstxCapture::CaptureStream, read from the model.
fn stream_value(feature: &str) -> f64 {
    let model = model_values::Model::load();
    let name = format!("WstxCapture::CaptureStream::{feature}");
    let read = model
        .number_with_unit(&name)
        .or_else(|_| model.number(&name))
        .unwrap_or_else(|e| panic!("model value {e}"));
    match read.unwrap_or_else(|| panic!("model value {name}: null")) {
        model_values::Number::Integer(n) => n as f64,
        model_values::Number::Real(x) => x,
    }
}
/// The conversion's limits: the top of the passband (Hz), its ripple (dB), the bottom of
/// the stopband (Hz) and the largest gain there, from passbandHighHz, passbandRippleDb,
/// stopbandLowHz and stopbandDb.
fn filter_limits() -> (f64, f64, f64, f64) {
    (
        stream_value("passbandHighHz"),
        stream_value("passbandRippleDb"),
        stream_value("stopbandLowHz"),
        10f64.powf(-stream_value("stopbandDb") / 20.0),
    )
}
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
// Independent complex DFT of every phase response.
// Proves: TC-002-003
#[test]
fn audio_filter_response() {
    let (passband, ripple, stopband, rejected) = filter_limits();
    for rate in [44100, 48000] {
        let c = Converter::new(rate).unwrap();
        for taps in c.response_taps() {
            for hz in (0..=passband as usize)
                .step_by(25)
                .chain((stopband as usize..=rate as usize / 2).step_by(25))
            {
                let mut re = 0.0;
                let mut im = 0.0;
                for (j, t) in taps.iter().enumerate() {
                    let p = std::f64::consts::TAU * hz as f64 * j as f64 / f64::from(rate);
                    re += t * p.cos();
                    im -= t * p.sin();
                }
                let gain = (re * re + im * im).sqrt();
                if hz as f64 <= passband {
                    assert!((20.0 * gain.log10()).abs() <= ripple, "{rate} {hz} {gain}");
                } else {
                    assert!(gain <= rejected, "{rate} {hz} {gain}");
                }
            }
        }
    }
}
// Rational count independent of callback partition, no padded edges.
// Proves: TC-002-003
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
// Channel0, integer extrema, nonfinite and alignment rejection.
// Proves: TC-002-001, TC-002-003
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
// Actual epoch acknowledgement and gaps without invented samples.
// Proves: TC-002-001, TC-002-003
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
// Queue duration cap, explicit loss and bounded cancellation.
// Proves: TC-002-003
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

// Exact bounded packet ownership recycles across ring wraps.
// Proves: TC-002-003
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
            assert!(queue.push(&bytes, 4, first, 0, 0));
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

// Impulse center and known-gap phase use an independent rational oracle.
// Proves: TC-002-003
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
// Overflow invalidates buffered samples before any old-context publication.
// Proves: TC-002-003
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
// Backoff and explicit stop never rely on UTC.
// Proves: TC-002-001, TC-002-003
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
/// A capture device that opens a software packet queue of `format` and hands it to the
/// test; no endpoint is activated. It delivers nothing until cancelled.
#[cfg(windows)]
struct PacketDevice {
    format: NativeFormat,
    queues: std::sync::Mutex<std::sync::mpsc::Sender<Arc<PacketQueue>>>,
}
#[cfg(windows)]
impl PacketDevice {
    fn new(format: NativeFormat) -> (Arc<Self>, std::sync::mpsc::Receiver<Arc<PacketQueue>>) {
        let (queues, opened) = std::sync::mpsc::channel();
        (
            Arc::new(Self {
                format,
                queues: std::sync::Mutex::new(queues),
            }),
            opened,
        )
    }
}
#[cfg(windows)]
impl CaptureDevice for PacketDevice {
    fn capture(
        &self,
        _endpoint_id: &str,
        opened: std::sync::mpsc::SyncSender<Opened>,
        cancel: Arc<std::sync::atomic::AtomicBool>,
        _wake: Arc<std::sync::Mutex<Option<usize>>>,
        _closed: &std::sync::mpsc::SyncSender<Result<(), SourceError>>,
    ) -> Result<(), SourceError> {
        let queue = PacketQueue::new(self.format)?;
        let _ = opened.send(Ok((queue.clone(), self.format)));
        let _ = self.queues.lock().unwrap().send(queue);
        while !cancel.load(std::sync::atomic::Ordering::Acquire) {
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
        Ok(())
    }
}
/// The close of one native capture owner, run through the same finalizer as WASAPI's: it
/// opens a new queue, then closes `owner` with `stop` after the read outcome `prior`.
#[cfg(windows)]
#[allow(clippy::type_complexity)]
struct CloseDevice<O> {
    close: std::sync::Mutex<
        Option<(
            O,
            Result<(), SourceError>,
            Box<dyn FnMut(&mut O) -> Result<(), SourceError> + Send>,
            Box<dyn FnMut() + Send>,
        )>,
    >,
}
#[cfg(windows)]
impl<O: Send + 'static> CaptureDevice for CloseDevice<O> {
    fn capture(
        &self,
        _endpoint_id: &str,
        opened: std::sync::mpsc::SyncSender<Opened>,
        _cancel: Arc<std::sync::atomic::AtomicBool>,
        _wake: Arc<std::sync::Mutex<Option<usize>>>,
        closed: &std::sync::mpsc::SyncSender<Result<(), SourceError>>,
    ) -> Result<(), SourceError> {
        let Some((owner, prior, stop, wait)) = self.close.lock().unwrap().take() else {
            let _ = opened.send(Err(SourceError::Unavailable));
            return Err(SourceError::Unavailable);
        };
        let queue = PacketQueue::new(format(48000))?;
        let _ = opened.send(Ok((queue.clone(), format(48000))));
        audio::finish_capture_owner(
            owner,
            prior,
            stop,
            || {
                queue.fail(SourceError::FailedClose);
                let _ = closed.try_send(Err(SourceError::FailedClose));
            },
            wait,
        )
    }
}
// Proves: TC-002-003
#[cfg(windows)]
#[test]
fn audio_capture_without_a_named_endpoint_is_refused_unavailable() {
    assert!(matches!(
        AudioController::new(String::new(), PacketDevice::new(format(48000)).0),
        Err(SourceError::Unavailable)
    ));
}
/// Runs `step` until it reports done, under a hang guard well above the observed time.
#[cfg(windows)]
fn until_done(what: &str, mut step: impl FnMut() -> bool) {
    let start = std::time::Instant::now();
    while !step() {
        assert!(
            start.elapsed() < std::time::Duration::from_secs(5),
            "timed out waiting for {what}"
        );
        std::thread::yield_now();
    }
}
/// Two controllers on packet drivers of 48000 and 44100 Hz, started, with their queues.
#[cfg(windows)]
#[allow(clippy::type_complexity)]
fn two_started_controllers() -> (
    (AudioController, std::sync::mpsc::Receiver<Arc<PacketQueue>>),
    (AudioController, std::sync::mpsc::Receiver<Arc<PacketQueue>>),
) {
    let (device_a, queue_a) = PacketDevice::new(format(48000));
    let (device_b, queue_b) = PacketDevice::new(format(44100));
    let mut a = AudioController::new("radio-A".into(), device_a).unwrap();
    let mut b = AudioController::new("radio-B".into(), device_b).unwrap();
    a.start().unwrap();
    b.start().unwrap();
    ((a, queue_a), (b, queue_b))
}
// Actual controller isolates two packet drivers and acknowledges stop.
// Proves: TC-002-001, TC-002-003
#[cfg(windows)]
#[test]
fn audio_controller_profiles_and_stop() {
    use std::time::Duration;
    let ((mut a, queue_a), (mut b, queue_b)) = two_started_controllers();
    until_done("both running", || {
        if a.status().state == AudioState::Running && b.status().state == AudioState::Running {
            return true;
        }
        assert!(matches!(a.poll(), SourcePoll::Pending));
        assert!(matches!(b.poll(), SourcePoll::Pending));
        false
    });
    let qa = queue_a.recv_timeout(Duration::from_millis(250)).unwrap();
    let qb = queue_b.recv_timeout(Duration::from_millis(250)).unwrap();
    assert_eq!(a.selected_endpoint(), "radio-A");
    assert_eq!(b.selected_endpoint(), "radio-B");
    qa.push(&bytes(&vec![0.1; 480]), 480, 100, 5, 0);
    let SourcePoll::EpochChanged(p) = a.poll() else {
        panic!()
    };
    assert_eq!(p.native_rate, 48000);
    assert!(matches!(b.poll(), SourcePoll::Pending));
    assert_eq!(qb.queued_frames(), 0);
    a.request_stop();
    assert!(a.descriptor().is_none());
    until_done("A closed", || {
        if a.status().state == AudioState::Closed {
            return true;
        }
        assert!(matches!(a.poll(), SourcePoll::Pending));
        false
    });
    assert_eq!(b.status().state, AudioState::Running);
    b.request_stop();
    until_done("B closed", || {
        if b.status().state == AudioState::Closed {
            return true;
        }
        let _ = b.poll();
        false
    });
}
// The controller reaches Running and acknowledges each stop within 250 ms
// (DeviceLifecycle::closeMaxMs).
// Timing: display
// Proves: TC-002-001, TC-002-003
#[cfg(windows)]
#[test]
fn realtime_bound_audio_controller_profiles_and_stop() {
    use std::time::{Duration, Instant};
    let ((mut a, queue_a), (mut b, queue_b)) = two_started_controllers();
    let start = Instant::now();
    while a.status().state != AudioState::Running || b.status().state != AudioState::Running {
        assert!(matches!(a.poll(), SourcePoll::Pending));
        assert!(matches!(b.poll(), SourcePoll::Pending));
        assert!(start.elapsed() < Duration::from_millis(250));
        std::thread::yield_now();
    }
    let qa = queue_a.recv_timeout(Duration::from_millis(250)).unwrap();
    let qb = queue_b.recv_timeout(Duration::from_millis(250)).unwrap();
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

// Actual converter waveform gain/rejection, not only coefficient response.
// Proves: TC-002-003
#[test]
fn audio_waveform_response() {
    let (passband, ripple, stopband, rejected) = filter_limits();
    for rate in [44100, 48000] {
        for hz in [100.0, 1000.0, 3000.0, passband, stopband, 6000.0, 9000.0] {
            let x = signal(rate, hz, rate as usize / 2);
            let mut converter = Converter::new(rate).unwrap();
            let mut out = Vec::new();
            for block in x.chunks(997) {
                out.extend(converter.convert(block).unwrap().1);
            }
            let rms =
                (out.iter().map(|v| f64::from(*v).powi(2)).sum::<f64>() / out.len() as f64).sqrt();
            if hz <= passband {
                let gain = 20.0 * (rms * 2.0_f64.sqrt()).log10();
                assert!(gain.abs() < ripple, "{rate} {hz}: {gain}");
            } else {
                assert!(rms * 2.0_f64.sqrt() <= rejected, "{rate} {hz}: {rms}");
            }
        }
    }
}

// Native driver metadata schema is independently encoded.
// Proves: TC-002-001, TC-002-003
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

// A failed bracket cannot conceal a later UTC jump.
// Proves: TC-002-003
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

// Failed Stop dominates read/cancel errors and
// retains every native owner plus its apartment until Stop acknowledges release.
// Proves: TC-002-003
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
        let device = Arc::new(CloseDevice {
            close: Mutex::new(Some((
                owner,
                prior,
                Box::new(move |_: &mut Owner| {
                    if stop_gate.load(Ordering::Acquire) {
                        Ok(())
                    } else {
                        Err(SourceError::Unavailable)
                    }
                }) as Box<dyn FnMut(&mut Owner) -> Result<(), SourceError> + Send>,
                Box::new(move || {
                    let (lock, changed) = &*wait_worker;
                    drop(
                        changed
                            .wait_timeout(lock.lock().unwrap(), Duration::from_millis(10))
                            .unwrap(),
                    );
                }) as Box<dyn FnMut() + Send>,
            ))),
        });
        let mut controller = AudioController::new("close-boundary-fixture".into(), device).unwrap();
        controller.start().unwrap();
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

// Successful Stop releases normally and preserves the read outcome.
// Proves: TC-002-003
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

/// Drains every ready block; returns (blocks, epoch proposals seen).
fn drain(source: &mut LiveSource, blocks: &mut Vec<SampleBlock>) -> Vec<EpochProposal> {
    let mut epochs = Vec::new();
    loop {
        match source.poll() {
            SourcePoll::Block(b) => blocks.push(b),
            SourcePoll::EpochChanged(p) => {
                let id = format!("epoch-{}", p.proposal_counter);
                acknowledge(source, p.clone(), &id);
                epochs.push(p);
            }
            SourcePoll::Pending => return epochs,
            _ => panic!("unexpected source failure"),
        }
    }
}

// The HB9BLA IC-7300 codec packet sequence: WASAPI
// flags DATA_DISCONTINUITY on packets whose device position and QPC both continue the
// previous packet (measured QPC step jitter up to 0.56 ms, flagged or not). That is a
// counted engine glitch on a continuous timeline: one source epoch, gap-free canonical
// frames, no reset.
// Proves: TC-002-001, TC-002-003
#[test]
fn audio_contiguous_engine_discontinuity_keeps_the_source_epoch() {
    let f = format(48000);
    let q = PacketQueue::new(f).unwrap();
    let mut s = LiveSource::new(q.clone(), f).unwrap();
    let x = bytes(&signal(48000, 1000.0, 480));
    let (mut blocks, mut epochs) = (Vec::new(), Vec::new());
    // Observed QPC steps (100 ns) and flags: start flag, single and back-to-back glitches.
    let mut qpc = 51_066_719_853_840_u64;
    let mut frame = 160_980_000_u64;
    for i in 0..400u64 {
        let flags = if matches!(i, 0 | 37 | 150 | 151 | 300) {
            DATA_DISCONTINUITY
        } else {
            0
        };
        assert!(q.push(&x, 480, frame, qpc, flags));
        epochs.extend(drain(&mut s, &mut blocks));
        frame += 480;
        qpc += match i % 3 {
            0 => 99_860,
            1 => 100_150,
            _ => 98_140,
        };
    }
    assert_eq!(epochs.len(), 1, "only the capture start opens an epoch");
    assert_eq!(epochs[0].reason, "capture_start");
    assert_eq!(epochs[0].trigger, "capture_start");
    assert!(blocks[0].discontinuity);
    for pair in blocks.windows(2) {
        assert_eq!(
            pair[1].first_frame,
            pair[0].first_frame + pair[0].samples.len() as u64,
            "canonical frames stay gap-free across engine glitches"
        );
        assert!(
            !pair[1].discontinuity,
            "engine glitch must not reset analysis"
        );
        assert_eq!(pair[1].source.source_id, blocks[0].source.source_id);
    }
    assert_eq!(
        q.diagnostics().native_discontinuity,
        5,
        "glitches stay counted"
    );
}

// A contiguous-position flag without a consistent QPC,
// and every own-queue loss, is still unknown loss; each epoch names its trigger.
// Proves: TC-002-003
#[test]
fn audio_unknown_loss_epochs_name_their_trigger() {
    let f = format(48000);
    let q = PacketQueue::new(f).unwrap();
    let mut s = LiveSource::new(q.clone(), f).unwrap();
    let x = bytes(&vec![0.25; 480]);
    let mut blocks = Vec::new();
    assert!(q.push(&x, 480, 0, 1_000_000, 0));
    assert_eq!(drain(&mut s, &mut blocks)[0].trigger, "capture_start");
    // Position continues but 50 ms of QPC time is unaccounted for.
    assert!(q.push(&x, 480, 480, 1_600_000, DATA_DISCONTINUITY));
    let e = drain(&mut s, &mut blocks);
    assert_eq!(
        (e.len(), e[0].reason, e[0].trigger),
        (1, "capture_loss", "native_discontinuity")
    );
    assert!(!q.push(&[], 8193, 960, 1_700_000, SILENT));
    assert!(q.push(&x, 480, 960, 1_700_000, 0));
    let e = drain(&mut s, &mut blocks);
    assert_eq!((e.len(), e[0].trigger), (1, "invalid_packet"));
    assert!(q.push(&x, 480, 1440, 1_800_000, TIMESTAMP_ERROR));
    assert_eq!(drain(&mut s, &mut blocks)[0].trigger, "timestamp_error");
    assert!(q.push(&x, 480, 1000, 1_900_000, 0));
    assert_eq!(drain(&mut s, &mut blocks)[0].trigger, "frame_backstep");
    // A flagged later position remains a known gap: no epoch.
    assert!(q.push(&x, 480, 9600, 2_900_000, DATA_DISCONTINUITY));
    assert!(drain(&mut s, &mut blocks).is_empty());
    assert!(blocks.last().unwrap().discontinuity);
}

// The 2 ms QPC bound for a contiguous flagged packet:
// +-0.55 ms (the observed jitter) and exactly 2 ms are kept; 2.1 ms early or late is loss.
// Proves: TC-002-001
#[test]
fn audio_contiguous_flag_qpc_tolerance_boundary() {
    let f = format(48000);
    let x = bytes(&vec![0.25; 480]);
    // (QPC step in 100 ns for a nominal 10 ms packet, epoch expected)
    for (step, epoch) in [
        (100_000 - 5_500, false),
        (100_000 + 5_500, false),
        (100_000 - 20_000, false),
        (100_000 + 20_000, false),
        (100_000 - 21_000, true),
        (100_000 + 21_000, true),
    ] {
        let q = PacketQueue::new(f).unwrap();
        let mut s = LiveSource::new(q.clone(), f).unwrap();
        let mut blocks = Vec::new();
        assert!(q.push(&x, 480, 0, 1_000_000, 0));
        assert_eq!(drain(&mut s, &mut blocks).len(), 1);
        assert!(q.push(&x, 480, 480, 1_000_000 + step, DATA_DISCONTINUITY));
        let e = drain(&mut s, &mut blocks);
        assert_eq!(!e.is_empty(), epoch, "QPC step {step}");
        if epoch {
            assert_eq!(
                (e[0].reason, e[0].trigger),
                ("capture_loss", "native_discontinuity")
            );
        } else {
            assert!(!blocks.last().unwrap().discontinuity, "QPC step {step}");
        }
    }
}

// A real native FIFO overflow names queue_full.
// Proves: TC-002-001
#[test]
fn audio_queue_full_epoch_names_its_trigger() {
    let f = format(48000);
    let q = PacketQueue::new(f).unwrap();
    let mut s = LiveSource::new(q.clone(), f).unwrap();
    let x = bytes(&vec![0.25; 480]);
    let mut blocks = Vec::new();
    assert!(q.push(&x, 480, 0, 1_000_000, 0));
    drain(&mut s, &mut blocks);
    // The consumer stalls: 500 ms of packets fill the FIFO, the next one is refused.
    let mut frame = 480;
    while q.push(
        &[],
        480,
        frame,
        1_000_000 + frame * 10_000_000 / 48_000,
        SILENT,
    ) {
        frame += 480;
    }
    assert_eq!(q.diagnostics().queue_full, 1);
    let e = drain(&mut s, &mut blocks);
    assert_eq!(
        (e.len(), e[0].reason, e[0].trigger),
        (1, "capture_loss", "queue_full")
    );
}

// Silent packets (zero-filled by the source) and
// accepted engine glitches are marked on the canonical timeline, so a window can count
// them; a new epoch forgets them.
// Proves: TC-002-001
#[test]
fn audio_zero_filled_and_glitch_frames_are_marked_per_window() {
    let f = format(48000);
    let q = PacketQueue::new(f).unwrap();
    let mut s = LiveSource::new(q.clone(), f).unwrap();
    let x = bytes(&signal(48000, 1000.0, 480));
    let mut blocks = Vec::new();
    let (mut frame, mut qpc) = (480_000u64, 1_000_000u64);
    for i in 0..100u64 {
        // Packet 0 opens the epoch; 10 and 11 are silent; 40 and 70 are glitches.
        let flags = match i {
            0 | 40 | 70 => DATA_DISCONTINUITY,
            10 | 11 => SILENT,
            _ => 0,
        };
        let data = if flags == SILENT { &[][..] } else { &x[..] };
        assert!(q.push(data, 480, frame, qpc, flags));
        drain(&mut s, &mut blocks);
        frame += 480;
        qpc += 100_000;
    }
    // 480 native frames at 48 kHz are 120 canonical frames; packet k starts at 120*k.
    assert_eq!(s.marked_frames(0, 12000), (240, 240));
    assert_eq!(s.marked_frames(1200, 1440), (240, 0));
    assert_eq!(s.marked_frames(1260, 4860), (180, 60));
    assert_eq!(s.marked_frames(1440, 4800), (0, 0));
    assert_eq!(s.capture_diagnostics().native_discontinuity, 3);
    // A timestamp error is unknown loss and starts a new epoch: its marks are gone.
    assert!(q.push(&x, 480, frame, qpc, TIMESTAMP_ERROR));
    drain(&mut s, &mut blocks);
    assert_eq!(s.marked_frames(0, u64::MAX), (0, 0));
}

// Sustained silence over more packets than the
// mark limit (600 silent 480-frame packets after one signal packet) stays counted in full.
// Proves: TC-002-001
#[test]
fn audio_sustained_silence_is_counted_in_full() {
    let f = format(48000);
    let q = PacketQueue::new(f).unwrap();
    let mut s = LiveSource::new(q.clone(), f).unwrap();
    let x = bytes(&signal(48000, 1000.0, 480));
    let mut blocks = Vec::new();
    let (mut frame, mut qpc) = (0u64, 1_000_000u64);
    for i in 0..601u64 {
        let silent = i > 0;
        assert!(q.push(
            if silent { &[][..] } else { &x[..] },
            480,
            frame,
            qpc,
            if silent { SILENT } else { 0 }
        ));
        drain(&mut s, &mut blocks);
        frame += 480;
        qpc += 100_000;
    }
    assert_eq!(s.marked_frames(0, u64::MAX), (600 * 120, 0));
    assert_eq!(s.marked_frames(120, 120 + 180000), (72000, 0));
}
