#![deny(unsafe_code)]
#![cfg(windows)]
#[path = "../../src/audio/audio.rs"]
pub mod audio;
#[path = "../../src/audio/source.rs"]
pub mod source;
use audio::{CaptureHandle, Encoding, LiveSource};
use source::*;
use std::{
    sync::Arc,
    thread,
    time::{Duration, Instant},
};
use wstx_test_tools::capture_evidence::Evidence;

const RADIO_INPUT: &str = "{0.0.1.00000000}.{fe449f9f-e759-4d7f-87e7-e6845d1bddfe}";

// Proves: TC-002-002
#[test]
#[ignore = "Explicit selected-endpoint hardware capture; coordinator runs on HB9BLA only"]
fn selected_radio_audio_capture_evidence() {
    assert_eq!(
        std::env::var("WSTX_AUDIO_PROBE_ENDPOINT").as_deref(),
        Ok(RADIO_INPUT)
    );
    let mut capture = CaptureHandle::begin(RADIO_INPUT, std::sync::Arc::new(audio::Wasapi))
        .expect("selected input open begins");
    let opening_deadline = Instant::now() + Duration::from_secs(5);
    let (queue, format) = loop {
        if let Some(result) = capture.poll_open() {
            break result.expect("selected endpoint opens");
        }
        if Instant::now() >= opening_deadline {
            let close = capture.stop();
            panic!("audio open timeout; close={close:?}")
        }
        thread::sleep(Duration::from_millis(1));
    };
    assert_eq!(
        (format.rate, format.channels, format.encoding),
        (48000, 2, Encoding::Float32)
    );
    let mut source = LiveSource::new(queue, format).unwrap();
    let mut evidence = Evidence::default();
    let began = Instant::now();
    let capture_result = (|| -> Result<(), String> {
        while began.elapsed() < Duration::from_secs(8) {
            match source.poll() {
                SourcePoll::Pending => thread::sleep(Duration::from_millis(1)),
                SourcePoll::EpochChanged(proposal) => {
                    evidence.epochs += 1;
                    evidence.previous_end = None;
                    if proposal.reason == "capture_loss" {
                        evidence.unknown_loss_epochs += 1;
                    }
                    let id = format!("audio-probe-{}", proposal.proposal_counter);
                    let descriptor = Arc::new(SourceDescriptor {
                        schema_version: 1,
                        profile_id: "hardware-probe".into(),
                        boot_id: format!("probe-{}", std::process::id()),
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
                        .map_err(|error| format!("epoch ACK: {error:?}"))?;
                }
                SourcePoll::Block(block) => {
                    evidence.observe(block.first_frame, &block.samples, block.discontinuity)?
                }
                SourcePoll::Failed(error) => return Err(format!("capture failed: {error:?}")),
                SourcePoll::End => return Err("live input ended".into()),
            }
        }
        Ok(())
    })();
    source.stop();
    let close_began = Instant::now();
    let close = capture.stop();
    println!(
        "{}",
        serde_json::json!({"probe":"selected_radio_audio","endpoint_id":RADIO_INPUT,"native_rate":format.rate,"native_channels":format.channels,"native_encoding":"float32","canonical_rate":12000,"elapsed_ms":began.elapsed().as_millis(),"blocks":evidence.blocks,"samples":evidence.samples,"epochs":evidence.epochs,"discontinuities":evidence.discontinuities,"known_missing_canonical_frames":evidence.known_missing,"unknown_loss_epochs":evidence.unknown_loss_epochs,"rms":evidence.rms(),"peak":evidence.peak,"last_end_frame":evidence.previous_end,"close_ms":close_began.elapsed().as_millis(),"close":format!("{close:?}"),"capture_error":capture_result.as_ref().err(),"utc_accuracy":"unknown"})
    );
    close.expect("native capture release acknowledged");
    capture_result.unwrap();
    assert!(
        evidence.samples >= 60_000,
        "less than five seconds of canonical audio captured"
    );
}
