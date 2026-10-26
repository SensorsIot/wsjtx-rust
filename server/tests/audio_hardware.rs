#![deny(unsafe_code)]
#![cfg(windows)]
#[path = "../src/audio.rs"]
pub mod audio;
#[path = "../src/source.rs"]
pub mod source;
use audio::{CaptureHandle, Encoding, LiveSource};
use source::*;
use std::{
    sync::Arc,
    thread,
    time::{Duration, Instant},
};

const RADIO_INPUT: &str = "{0.0.1.00000000}.{fe449f9f-e759-4d7f-87e7-e6845d1bddfe}";

// TC-002-001/003 receive-only acceptance. Uses the actual selected WASAPI backend and converter.
#[test]
#[ignore = "Explicit selected-endpoint hardware capture; coordinator runs on HB9BLA only"]
fn selected_radio_audio_capture_evidence() {
    assert_eq!(
        std::env::var("WSTX_AUDIO_PROBE_ENDPOINT").as_deref(),
        Ok(RADIO_INPUT)
    );
    let mut capture = CaptureHandle::begin(RADIO_INPUT).expect("selected input open begins");
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
                SourcePoll::Block(block) => evidence.observe(&block)?,
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

#[derive(Default)]
struct Evidence {
    blocks: u64,
    samples: u64,
    epochs: u64,
    discontinuities: u64,
    known_missing: u64,
    unknown_loss_epochs: u64,
    previous_end: Option<u64>,
    squares: f64,
    peak: f64,
}
impl Evidence {
    fn observe(&mut self, block: &SampleBlock) -> Result<(), String> {
        if block.samples.is_empty()
            || block.samples.len() > 240
            || !block.samples.iter().all(|v| v.is_finite())
        {
            return Err("invalid canonical block".into());
        }
        if let Some(previous) = self.previous_end {
            if block.first_frame < previous {
                return Err("canonical frame counter went backwards".into());
            }
            if block.first_frame > previous {
                if !block.discontinuity {
                    return Err("unmarked canonical gap".into());
                }
                self.known_missing += block.first_frame - previous;
            }
        }
        self.previous_end = Some(block.first_frame + block.samples.len() as u64);
        self.blocks += 1;
        self.samples += block.samples.len() as u64;
        self.discontinuities += u64::from(block.discontinuity);
        for &v in block.samples.iter() {
            let v = f64::from(v);
            self.squares += v * v;
            self.peak = self.peak.max(v.abs());
        }
        Ok(())
    }
    fn rms(&self) -> f64 {
        if self.samples == 0 {
            0.0
        } else {
            (self.squares / self.samples as f64).sqrt()
        }
    }
}

#[test]
fn hardware_probe_evidence_rejects_bad_blocks_and_measures_samples() {
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
        samples: Arc::from([0.5_f32, -0.5]),
        discontinuity: true,
        end_of_stream: false,
        timing: None,
    };
    let mut evidence = Evidence::default();
    evidence.observe(&block).unwrap();
    assert_eq!(evidence.rms(), 0.5);
    assert_eq!(evidence.peak, 0.5);
    block.first_frame = 4;
    block.discontinuity = false;
    assert!(evidence.observe(&block).is_err());
    block.discontinuity = true;
    evidence.observe(&block).unwrap();
    assert_eq!(evidence.known_missing, 2);
    block.first_frame = 0;
    assert!(evidence.observe(&block).is_err());
    block.first_frame = 6;
    block.samples = Arc::from([f32::NAN]);
    assert!(evidence.observe(&block).is_err());
}
