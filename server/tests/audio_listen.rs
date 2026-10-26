#![cfg(windows)]
#![deny(unsafe_code)]
#[path = "../src/audio.rs"]
pub mod audio;
#[path = "../src/source.rs"]
pub mod source;

use audio::{CaptureHandle, Encoding, LiveSource};
use source::*;
use std::{
    fs::OpenOptions,
    io::Write,
    path::PathBuf,
    sync::Arc,
    thread,
    time::{Duration, Instant},
};

const RADIO_INPUT: &str = "{0.0.1.00000000}.{fe449f9f-e759-4d7f-87e7-e6845d1bddfe}";
const RATE: usize = 12_000;
const MAX_SAMPLES: usize = RATE * 120;
const MAX_SEGMENTS: usize = 16;

fn pcm16_wav(samples: &[f32]) -> Result<Vec<u8>, &'static str> {
    if samples.is_empty() || samples.len() > MAX_SAMPLES || samples.iter().any(|v| !v.is_finite()) {
        return Err("invalid or oversized canonical audio");
    }
    let bytes = u32::try_from(samples.len().checked_mul(2).ok_or("size overflow")?)
        .map_err(|_| "size overflow")?;
    let mut wav = Vec::with_capacity(44 + samples.len() * 2);
    wav.extend_from_slice(b"RIFF");
    wav.extend_from_slice(&(36 + bytes).to_le_bytes());
    wav.extend_from_slice(b"WAVEfmt ");
    wav.extend_from_slice(&16_u32.to_le_bytes());
    wav.extend_from_slice(&1_u16.to_le_bytes());
    wav.extend_from_slice(&1_u16.to_le_bytes());
    wav.extend_from_slice(&12_000_u32.to_le_bytes());
    wav.extend_from_slice(&24_000_u32.to_le_bytes());
    wav.extend_from_slice(&2_u16.to_le_bytes());
    wav.extend_from_slice(&16_u16.to_le_bytes());
    wav.extend_from_slice(b"data");
    wav.extend_from_slice(&bytes.to_le_bytes());
    for &sample in samples {
        // Finite samples are explicitly rounded and clipped into the PCM16 domain.
        let pcm = (f64::from(sample) * 32768.0)
            .round()
            .clamp(f64::from(i16::MIN), f64::from(i16::MAX)) as i16;
        wav.extend_from_slice(&pcm.to_le_bytes());
    }
    Ok(wav)
}

#[test]
fn listening_wav_has_independent_header_and_quantization_bytes() {
    let samples = [
        -2.0,
        -1.0,
        -0.5,
        -1.0 / 32768.0,
        0.0,
        1.0 / 32768.0,
        0.5,
        1.0,
        2.0,
    ];
    let wav = pcm16_wav(&samples).unwrap();
    let header: [u8; 44] = [
        82, 73, 70, 70, 54, 0, 0, 0, 87, 65, 86, 69, 102, 109, 116, 32, 16, 0, 0, 0, 1, 0, 1, 0,
        224, 46, 0, 0, 192, 93, 0, 0, 2, 0, 16, 0, 100, 97, 116, 97, 18, 0, 0, 0,
    ];
    assert_eq!(&wav[..44], &header);
    assert_eq!(
        &wav[44..],
        &[
            0, 128, 0, 128, 0, 192, 255, 255, 0, 0, 1, 0, 0, 64, 255, 127, 255, 127
        ]
    );
    assert!(pcm16_wav(&[]).is_err());
    assert!(pcm16_wav(&[f32::NAN]).is_err());
    assert!(pcm16_wav(&[f32::INFINITY]).is_err());
    assert!(pcm16_wav(&vec![0.0; MAX_SAMPLES + 1]).is_err());
    assert_eq!(pcm16_wav(&vec![0.0; MAX_SAMPLES]).unwrap().len(), 2_880_044);
}

fn selected_output() -> PathBuf {
    let path =
        PathBuf::from(std::env::var_os("WSTX_AUDIO_LISTEN_WAV").expect("explicit output path"));
    let stage = PathBuf::from(std::env::var_os("USERPROFILE").expect("Windows user profile"))
        .join("WstxRustStage426")
        .canonicalize()
        .expect("existing station test staging directory");
    assert_eq!(path.parent().unwrap().canonicalize().unwrap(), stage);
    let name = path.file_name().unwrap().to_str().unwrap();
    assert!(
        name.is_ascii()
            && name.len() <= 64
            && name.starts_with("ic7300-listen")
            && name.ends_with(".wav")
    );
    assert!(!path.exists(), "listening capture never overwrites a file");
    path
}

fn diagnostics(value: audio::CaptureDiagnostics) -> serde_json::Value {
    serde_json::json!({"queue_contention":value.queue_contention,"queue_full":value.queue_full,"pool_exhausted":value.pool_exhausted,"invalid_packet":value.invalid_packet,"clock_step":value.clock_step,"timestamp_error":value.timestamp_error,"native_discontinuity":value.native_discontinuity,"frame_backstep":value.frame_backstep,"native_channel_zero_samples":value.native_channel_zero_samples,"native_channel_zero_full_scale":value.native_channel_zero_full_scale,"native_channel_zero_peak":f32::from_bits(value.native_channel_zero_peak_bits)})
}
struct Segment {
    first: u64,
    next: u64,
    source_id: String,
    reason: String,
    samples: Vec<f32>,
    diagnostics: serde_json::Value,
}
struct ListeningCapture {
    segments: Vec<Segment>,
    total: usize,
    limit: usize,
    boundary: Option<String>,
}
impl Default for ListeningCapture {
    fn default() -> Self {
        Self {
            segments: Vec::new(),
            total: 0,
            limit: MAX_SAMPLES,
            boundary: None,
        }
    }
}
impl ListeningCapture {
    fn observe(
        &mut self,
        block: &SampleBlock,
        snapshot: audio::CaptureDiagnostics,
    ) -> Result<(), String> {
        if block.samples.is_empty()
            || block.samples.len() > 240
            || block.samples.iter().any(|v| !v.is_finite())
        {
            return Err("invalid canonical capture block".into());
        }
        let reason = self.boundary.take().or_else(|| {
            self.segments.last().and_then(|last| {
                if last.source_id != block.source.source_id {
                    Some("source_identity_changed".into())
                } else if last.next != block.first_frame {
                    Some("canonical_frame_gap_or_backstep".into())
                } else if block.discontinuity {
                    Some("canonical_discontinuity".into())
                } else {
                    None
                }
            })
        });
        if self.segments.is_empty() || reason.is_some() {
            if self.segments.len() >= MAX_SEGMENTS {
                return Err("segment limit reached; capture stopped without stitching gaps".into());
            }
            self.segments.push(Segment {
                first: block.first_frame,
                next: block.first_frame,
                source_id: block.source.source_id.clone(),
                reason: reason.unwrap_or_else(|| "capture_start".into()),
                samples: Vec::new(),
                diagnostics: diagnostics(snapshot),
            });
        }
        let count = (self.limit - self.total).min(block.samples.len());
        let last = self.segments.last_mut().unwrap();
        last.samples.extend_from_slice(&block.samples[..count]);
        last.next = block
            .first_frame
            .checked_add(u64::try_from(count).unwrap())
            .ok_or("frame counter overflow")?;
        self.total += count;
        Ok(())
    }
}

#[test]
fn listening_segments_keep_gaps_and_epochs_separate_without_padding() {
    let descriptor = Arc::new(SourceDescriptor {
        schema_version: 1,
        profile_id: "p".into(),
        boot_id: "b".into(),
        source_id: "s".into(),
        rate_hz: 12000,
        channel: "mono_real",
        total_frames: None,
        utc_anchor: None,
    });
    let mut block = SampleBlock {
        source: descriptor,
        first_frame: 0,
        samples: Arc::from([0.25_f32, 0.5]),
        discontinuity: true,
        end_of_stream: false,
        timing: None,
    };
    let mut capture = ListeningCapture::default();
    capture.observe(&block, Default::default()).unwrap();
    block.first_frame = 2;
    block.discontinuity = false;
    capture.observe(&block, Default::default()).unwrap();
    block.first_frame = 8;
    capture.observe(&block, Default::default()).unwrap();
    capture.boundary = Some("capture_loss".into());
    block.first_frame = 0;
    capture.observe(&block, Default::default()).unwrap();
    assert_eq!(capture.total, 8);
    assert_eq!(capture.segments.len(), 3);
    assert_eq!(capture.segments[0].samples, [0.25, 0.5, 0.25, 0.5]);
    assert_eq!(capture.segments[1].first, 8);
    assert_eq!(capture.segments[1].samples, [0.25, 0.5]);
    assert_eq!(capture.segments[2].reason, "capture_loss");
    for n in 3..MAX_SEGMENTS {
        capture.boundary = Some(format!("epoch-{n}"));
        capture.observe(&block, Default::default()).unwrap();
    }
    capture.boundary = Some("one-too-many".into());
    assert!(capture.observe(&block, Default::default()).is_err());
    let queue = audio::PacketQueue::new(audio::NativeFormat {
        rate: 48000,
        channels: 2,
        encoding: Encoding::Float32,
    })
    .unwrap();
    assert!(!queue.push(&[], 0, 0, 0, 0));
    for _ in 0..3 {
        assert!(queue.push(&[], 8000, 0, 0, audio::SILENT));
    }
    assert!(!queue.push(&[], 1, 0, 0, audio::SILENT));
    assert_eq!(queue.diagnostics().invalid_packet, 1);
    assert_eq!(queue.diagnostics().queue_full, 1);
    queue.mark_loss(audio::CaptureEvent::ClockStep);
    assert_eq!(queue.diagnostics().clock_step, 1);
}

// TC-002-001/003: opt-in listening artifact from the actual selected canonical input.
#[test]
#[ignore = "Coordinator selects HB9BLA and retrieves a 120-second receive-only listening capture"]
fn selected_radio_audio_to_listening_wav() {
    assert_eq!(
        std::env::var("WSTX_AUDIO_PROBE_ENDPOINT").as_deref(),
        Ok(RADIO_INPUT)
    );
    let seconds = std::env::var("WSTX_AUDIO_LISTEN_SECONDS")
        .map(|v| v.parse::<usize>().expect("integer duration"))
        .unwrap_or(120);
    assert!(
        (1..=120).contains(&seconds),
        "duration must be1..120seconds"
    );
    let requested_samples = RATE.checked_mul(seconds).unwrap();
    let output = selected_output();
    let manifest_path = output.with_extension("manifest.json");
    assert!(!manifest_path.exists(), "capture manifest already exists");
    let mut capture = CaptureHandle::begin(RADIO_INPUT).expect("selected radio input begins");
    let open_limit = Instant::now() + Duration::from_secs(5);
    let (queue, format) = loop {
        if let Some(result) = capture.poll_open() {
            break result.expect("selected radio input opens");
        }
        if Instant::now() >= open_limit {
            let close = capture.stop();
            panic!("capture opening timed out; close={close:?}");
        }
        thread::sleep(Duration::from_millis(1));
    };
    if (format.rate, format.channels, format.encoding) != (48000, 2, Encoding::Float32) {
        let close = capture.stop();
        panic!("unexpected selected-device format {format:?}; close={close:?}");
    }
    let mut source = LiveSource::new(queue.clone(), format).unwrap();
    let began = Instant::now();
    let mut listening = ListeningCapture {
        limit: requested_samples,
        ..Default::default()
    };
    let mut epochs = 0_u64;
    let result = (|| -> Result<(), String> {
        while listening.total < requested_samples
            && began.elapsed() < Duration::from_secs(u64::try_from(seconds + 2).unwrap())
        {
            match source.poll() {
                SourcePoll::Pending => thread::sleep(Duration::from_millis(1)),
                SourcePoll::EpochChanged(proposal) => {
                    epochs += 1;
                    listening.boundary = Some(proposal.reason.to_string());
                    println!(
                        "{}",
                        serde_json::json!({"event":"source_epoch","epoch":epochs,"reason":proposal.reason,"native_first_frame":proposal.first_device_frame,"diagnostics":diagnostics(queue.diagnostics())})
                    );
                    let id = format!("listen-{}", proposal.proposal_counter);
                    let descriptor = Arc::new(SourceDescriptor {
                        schema_version: 1,
                        profile_id: "hardware-listen".into(),
                        boot_id: format!("listen-{}", std::process::id()),
                        source_id: id.clone(),
                        rate_hz: 12000,
                        channel: "mono_real",
                        total_frames: None,
                        utc_anchor: None,
                    });
                    let timing = SourceTiming {
                        source_id: id,
                        segment: proposal.proposal_counter,
                        native_rate: proposal.native_rate,
                        native_anchor_frame: proposal.first_device_frame as f64
                            + proposal.converter_delay_native_frames,
                        canonical_anchor_frame: 0,
                        converter_delay_native_frames: proposal.converter_delay_native_frames,
                        qpc_anchor_100ns: None,
                        system_utc_anchor: None,
                        uncertainty_ns: None,
                        correlated: false,
                        external_accuracy: ExternalAccuracy::Unknown,
                    };
                    source
                        .acknowledge_epoch(proposal.proposal_counter, descriptor, timing)
                        .map_err(|e| format!("epoch acknowledgement failed: {e:?}"))?;
                }
                SourcePoll::Block(block) => listening.observe(&block, queue.diagnostics())?,
                SourcePoll::Failed(error) => return Err(format!("capture failed: {error:?}")),
                SourcePoll::End => return Err("live input ended".into()),
            }
        }
        if listening.total != requested_samples {
            return Err("requested audio duration unavailable within duration plus2seconds".into());
        }
        Ok(())
    })();
    source.stop();
    let closing = Instant::now();
    let close = capture.stop();
    let close_ms = closing.elapsed().as_millis();
    let mut segments = Vec::new();
    for (index, segment) in listening.segments.iter().enumerate() {
        if segment.samples.is_empty() {
            continue;
        }
        let path = if listening.segments.len() == 1 {
            output.clone()
        } else {
            output.with_file_name(format!(
                "{}-seg{:03}.wav",
                output.file_stem().unwrap().to_str().unwrap(),
                index + 1
            ))
        };
        let wav = pcm16_wav(&segment.samples).unwrap();
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
            .unwrap();
        file.write_all(&wav).unwrap();
        file.sync_all().unwrap();
        let squares: f64 = segment.samples.iter().map(|v| f64::from(*v).powi(2)).sum();
        let peak = segment
            .samples
            .iter()
            .map(|v| v.abs())
            .fold(0.0_f32, f32::max);
        segments.push(serde_json::json!({"wav":path,"samples":segment.samples.len(),"duration_seconds":segment.samples.len() as f64/RATE as f64,"bytes":wav.len(),"first_frame":segment.first,"source_id":segment.source_id,"boundary_reason":segment.reason,"diagnostics_at_start":segment.diagnostics,"rms":(squares/segment.samples.len() as f64).sqrt(),"peak":peak,"canonical_full_scale_samples":segment.samples.iter().filter(|v|v.abs()>=1.0).count(),"canonical_out_of_range_samples":segment.samples.iter().filter(|v|v.abs()>1.0).count(),"pcm16_full_scale_samples":wav[44..].as_chunks::<2>().0.iter().filter(|b|**b==[0,128] || **b==[255,127]).count()}));
    }
    let manifest = serde_json::json!({"probe":"ic7300_listening_capture","requested_seconds":seconds,"rate_hz":RATE,"channels":1,"pcm_bits":16,"gain_applied":1.0,"endpoint_id":RADIO_INPUT,"native_rate":format.rate,"native_channels":format.channels,"total_samples":listening.total,"duration_seconds":listening.total as f64/RATE as f64,"epochs":epochs,"elapsed_ms":began.elapsed().as_millis(),"close":format!("{close:?}"),"close_ms":close_ms,"capture_error":result.as_ref().err(),"complete":result.is_ok(),"diagnostics":diagnostics(queue.diagnostics()),"segments":segments,"gaps_padded":false,"segments_stitched":false,"utc_accuracy":"unknown"});
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&manifest_path)
        .unwrap();
    file.write_all(serde_json::to_string_pretty(&manifest).unwrap().as_bytes())
        .unwrap();
    file.sync_all().unwrap();
    println!(
        "{}",
        serde_json::json!({"manifest":manifest_path,"evidence":manifest})
    );
    close.expect("native input close acknowledged");
    result.unwrap();
}
