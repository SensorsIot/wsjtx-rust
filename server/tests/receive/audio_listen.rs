#![cfg(windows)]
#![deny(unsafe_code)]
#[path = "../../src/audio/audio.rs"]
pub mod audio;
#[path = "../../src/audio/source.rs"]
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
use wstx_test_tools::listening::{Diagnostics, ListeningCapture, diagnostics, pcm16_wav};

const RADIO_INPUT: &str = "{0.0.1.00000000}.{fe449f9f-e759-4d7f-87e7-e6845d1bddfe}";
const RATE: usize = 12_000;

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

/// The fields of a capture diagnostics snapshot, as the listening capture takes them.
fn snapshot(value: audio::CaptureDiagnostics) -> Diagnostics {
    Diagnostics {
        queue_contention: value.queue_contention,
        queue_full: value.queue_full,
        pool_exhausted: value.pool_exhausted,
        invalid_packet: value.invalid_packet,
        clock_step: value.clock_step,
        timestamp_error: value.timestamp_error,
        native_discontinuity: value.native_discontinuity,
        frame_backstep: value.frame_backstep,
        native_channel_zero_samples: value.native_channel_zero_samples,
        native_channel_zero_full_scale: value.native_channel_zero_full_scale,
        native_channel_zero_peak_bits: value.native_channel_zero_peak_bits,
    }
}

// Proves: TC-002-001
#[test]
fn packet_queue_counts_invalid_full_and_clock_step_losses() {
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

// Proves: TC-002-002
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
    let mut capture = CaptureHandle::begin(RADIO_INPUT, std::sync::Arc::new(audio::Wasapi))
        .expect("selected radio input begins");
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
                        serde_json::json!({"event":"source_epoch","epoch":epochs,"reason":proposal.reason,"native_first_frame":proposal.first_device_frame,"diagnostics":diagnostics(snapshot(queue.diagnostics()))})
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
                SourcePoll::Block(block) => listening.observe(
                    &block.source.source_id,
                    block.first_frame,
                    &block.samples,
                    block.discontinuity,
                    snapshot(queue.diagnostics()),
                )?,
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
    let manifest = serde_json::json!({"probe":"ic7300_listening_capture","requested_seconds":seconds,"rate_hz":RATE,"channels":1,"pcm_bits":16,"gain_applied":1.0,"endpoint_id":RADIO_INPUT,"native_rate":format.rate,"native_channels":format.channels,"total_samples":listening.total,"duration_seconds":listening.total as f64/RATE as f64,"epochs":epochs,"elapsed_ms":began.elapsed().as_millis(),"close":format!("{close:?}"),"close_ms":close_ms,"capture_error":result.as_ref().err(),"complete":result.is_ok(),"diagnostics":diagnostics(snapshot(queue.diagnostics())),"segments":segments,"gaps_padded":false,"segments_stitched":false,"utc_accuracy":"unknown"});
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
