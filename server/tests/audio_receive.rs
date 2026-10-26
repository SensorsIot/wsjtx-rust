#![forbid(unsafe_code)]
// Production safe interfaces only. Native controller lifecycle and OS ownership are
// exercised by audio_contract/audio_hardware; this target needs no FFI exception.
pub use wstx_rust::{decoder, source};
#[path = "../src/receive.rs"]
mod receive;

use receive::{AnalysisWindow, WindowBuffer, WindowError};
use source::*;
use std::sync::Arc;
use wstx_rust::audio::{
    DATA_DISCONTINUITY, Encoding, LiveSource, NativeFormat, PacketQueue, SILENT,
};

fn native_format() -> NativeFormat {
    NativeFormat {
        rate: 48_000,
        channels: 2,
        encoding: Encoding::Float32,
    }
}

fn acknowledge(source: &mut LiveSource, proposal: &EpochProposal) -> Arc<SourceDescriptor> {
    let id = format!("00000000-0000-4000-8000-{:012}", proposal.proposal_counter);
    let descriptor = Arc::new(SourceDescriptor {
        schema_version: 1,
        profile_id: "11111111-1111-4111-8111-111111111111".into(),
        boot_id: "22222222-2222-4222-8222-222222222222".into(),
        source_id: id.clone(),
        rate_hz: 12_000,
        channel: "mono_real",
        total_frames: None,
        utc_anchor: None,
    });
    source
        .acknowledge_epoch(
            proposal.proposal_counter,
            descriptor.clone(),
            SourceTiming {
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
            },
        )
        .unwrap();
    descriptor
}

struct Provider {
    queue: Arc<PacketQueue>,
    source: LiveSource,
    epochs: u64,
}
impl Provider {
    fn new() -> Self {
        let queue = PacketQueue::new(native_format()).unwrap();
        Self {
            source: LiveSource::new(queue.clone(), native_format()).unwrap(),
            queue,
            epochs: 0,
        }
    }
    fn drain_into(&mut self, mut accept: impl FnMut(SampleBlock)) {
        // An admitted native packet has at most8192 frames, so this independent
        // finite guard exceeds every possible block/epoch notification count.
        for _ in 0..128 {
            match self.source.poll() {
                SourcePoll::EpochChanged(proposal) => {
                    self.epochs += 1;
                    assert!(self.source.descriptor().is_none());
                    assert!(matches!(self.source.poll(), SourcePoll::Pending));
                    acknowledge(&mut self.source, &proposal);
                }
                SourcePoll::Block(block) => accept(block),
                SourcePoll::Pending => return,
                _ => panic!("unexpected live provider outcome"),
            }
        }
        panic!("bounded native provider did not drain");
    }
    fn drain(&mut self) -> Vec<SampleBlock> {
        let mut blocks = Vec::new();
        self.drain_into(|block| {
            assert!(
                blocks.len() < 2,
                "fixture never retains more than two blocks"
            );
            blocks.push(block);
        });
        blocks
    }
    fn silent(&mut self, first: u64, frames: usize, flags: u32) -> Vec<SampleBlock> {
        assert!(self.queue.push(&[], frames, first, 0, SILENT | flags));
        self.drain()
    }
}

fn ingest(
    buffer: &mut Option<WindowBuffer>,
    blocks: Vec<SampleBlock>,
    windows: &mut Vec<AnalysisWindow>,
) -> (u64, usize) {
    let mut next = 0;
    let mut resets = 0;
    for block in blocks {
        let buffer = buffer.get_or_insert_with(|| {
            WindowBuffer::new(decoder::Mode::Ft8, block.source.clone()).unwrap()
        });
        let outcome = buffer.push(&block).unwrap();
        next = outcome.captured_next_frame;
        resets += usize::from(outcome.reset_decoder);
        if let Some(window) = outcome.window {
            windows.push(window);
        }
    }
    (next, resets)
}

fn ingest_provider(
    provider: &mut Provider,
    buffer: &mut Option<WindowBuffer>,
    windows: &mut Vec<AnalysisWindow>,
) -> (u64, usize) {
    let mut next = 0;
    let mut resets = 0;
    provider.drain_into(|block| {
        // Copy into the real history before requesting the next shared block.
        let (end, reset) = ingest(buffer, vec![block], windows);
        next = end;
        resets += reset;
    });
    (next, resets)
}

// Proves: CL-008-02; TC-002-001, TC-002-003, TC-009-004.
// Native callback partitions cannot move the first15-second analysis boundary.
#[test]
fn live_provider_analysis_boundary_is_native_packet_partition_invariant() {
    for partitions in [&[8192][..], &[441, 1024, 37, 1920][..]] {
        let mut provider = Provider::new();
        let mut buffer = None;
        let mut windows = Vec::new();
        let mut first = 0;
        let mut packet = 0;
        let mut next = 0;
        while first < 720_480 {
            let frames = partitions[packet % partitions.len()].min((720_480 - first) as usize);
            assert!(provider.queue.push(&[], frames, first, 0, SILENT));
            let (end, resets) = ingest_provider(&mut provider, &mut buffer, &mut windows);
            assert_eq!(resets, 0);
            if end != 0 {
                next = end;
            }
            first += frames as u64;
            packet += 1;
        }
        // floor((720480−257)/4)+1 supported samples, without filter edge padding.
        assert_eq!(next, 180_056);
        assert_eq!(provider.epochs, 1);
        assert_eq!(windows.len(), 1);
        assert_eq!(windows[0].origin, 0);
        assert_eq!(windows[0].samples.len(), 180_000);
        assert!(windows[0].samples.iter().all(|sample| *sample == 0.0));
        assert_eq!(provider.queue.diagnostics().queue_contention, 0);
        assert_eq!(provider.queue.diagnostics().queue_full, 0);
        assert_eq!(provider.queue.diagnostics().pool_exhausted, 0);
        provider.source.stop();
    }
}

// Proves: CL-008-02/03; TC-002-003, TC-009-004.
#[test]
fn live_provider_known_gap_resets_history_without_renumbering_samples() {
    let mut provider = Provider::new();
    let first = provider.silent(0, 1024, 0);
    assert_eq!(first[0].first_frame, 0);
    let descriptor = first[0].source.clone();
    let mut buffer = Some(WindowBuffer::new(decoder::Mode::Ft8, descriptor).unwrap());
    let mut windows = Vec::new();
    assert_eq!(ingest(&mut buffer, first, &mut windows), (192, 0));
    let after_gap = provider.silent(48_000, 1024, DATA_DISCONTINUITY);
    assert_eq!(after_gap[0].first_frame, 12_000);
    assert!(after_gap[0].discontinuity);
    assert_eq!(ingest(&mut buffer, after_gap, &mut windows), (12_192, 1));
    let mut native = 49_024;
    while native < 720_480 {
        let count = 8192.min((720_480 - native) as usize);
        assert!(provider.queue.push(&[], count, native, 0, SILENT));
        let (_, resets) = ingest_provider(&mut provider, &mut buffer, &mut windows);
        assert_eq!(resets, 0);
        native += count as u64;
    }
    assert_eq!(provider.epochs, 1);
    assert_eq!(windows.len(), 1);
    assert_eq!(windows[0].origin, 12_000);
    assert_eq!(windows[0].samples.len(), 168_000);
    provider.source.stop();
}

// Proves: CL-008-02/03; TC-009-004. Unknown native loss requires a new owner context.
#[test]
fn live_provider_unknown_loss_requires_ack_and_rejects_old_window_context() {
    let mut provider = Provider::new();
    let first = provider.silent(0, 1024, 0);
    let old_source = first[0].source.clone();
    let mut old_buffer = WindowBuffer::new(decoder::Mode::Ft8, old_source.clone()).unwrap();
    for block in first {
        old_buffer.push(&block).unwrap();
    }
    assert!(!provider.queue.push(&[], 8193, 1024, 0, SILENT));
    assert!(provider.queue.push(&[], 1024, 1024, 0, SILENT));
    let SourcePoll::EpochChanged(proposal) = provider.source.poll() else {
        panic!("unknown loss must rotate the source epoch");
    };
    assert_eq!(proposal.reason, "capture_loss");
    assert!(provider.source.descriptor().is_none());
    assert!(matches!(provider.source.poll(), SourcePoll::Pending));
    let old_timing = SourceTiming {
        source_id: old_source.source_id.clone(),
        segment: 1,
        native_rate: 48000,
        native_anchor_frame: 1152.0,
        canonical_anchor_frame: 0,
        converter_delay_native_frames: 128.0,
        qpc_anchor_100ns: None,
        system_utc_anchor: None,
        uncertainty_ns: None,
        correlated: false,
        external_accuracy: ExternalAccuracy::Unknown,
    };
    assert_eq!(
        provider.source.acknowledge_epoch(1, old_source, old_timing),
        Err(SourceError::StaleAcknowledgement)
    );
    acknowledge(&mut provider.source, &proposal);
    let blocks = provider.drain();
    assert!(!blocks.is_empty());
    assert_eq!(blocks[0].first_frame, 0);
    assert!(matches!(
        old_buffer.push(&blocks[0]),
        Err(WindowError::InvalidContext)
    ));
    let mut new_buffer = WindowBuffer::new(decoder::Mode::Ft8, blocks[0].source.clone()).unwrap();
    assert_eq!(
        new_buffer.push(&blocks[0]).unwrap().captured_next_frame,
        192
    );
    provider.source.stop();
}

// Proves: CL-007-01/02, CL-008-02; TC-004-001, TC-002-001/003, TC-009-004.
// Mandatory release execution is registered as live-receive-integration. Debug
// retains the three cheaper actual-provider boundary tests above.
#[cfg(not(debug_assertions))]
#[tokio::test(flavor = "current_thread")]
async fn live_native_provider_decodes_independent_ft8_callsign() {
    use std::{fs, path::PathBuf, process::Command};
    let root =
        PathBuf::from(std::env::var_os("WSTX_DECODER_VECTORS").expect("verified vector cache"));
    let tool = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../fixtures/decoder/independent-vector-tool/cache.py");
    let verified = Command::new(if cfg!(windows) { "python" } else { "python3" })
        .arg(tool)
        .args(["--kind", "frozen", "--output"])
        .arg(&root)
        .arg("--verify-only")
        .output()
        .expect("independent fixture verification executes");
    assert!(
        verified.status.success(),
        "{}",
        String::from_utf8_lossy(&verified.stderr)
    );
    let manifest: serde_json::Value = serde_json::from_str(include_str!(
        "../../fixtures/decoder/independent-vectors/manifest.json"
    ))
    .unwrap();
    let vector = manifest["vectors"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["mode"] == "ft8" && v["id"] == "cq")
        .unwrap();
    let wav = fs::read(root.join("ft8-cq/000000_000000.wav")).unwrap();
    assert_eq!(&wav[..4], b"RIFF");
    assert_eq!(&wav[8..12], b"WAVE");
    assert_eq!(&wav[36..40], b"data");
    assert_eq!(wav.len(), 360_044);
    let samples: Vec<f32> = wav[44..]
        .as_chunks::<2>()
        .0
        .iter()
        .map(|bytes| f32::from(i16::from_le_bytes(*bytes)) / 32768.0)
        .collect();
    let mut provider = Provider::new();
    let mut buffer = None;
    let mut windows = Vec::new();
    let mut first = 0;
    let mut packet = 0;
    while first < 720_000 {
        let count = [441, 1024, 8192, 37][packet % 4].min(720_000 - first);
        // Explicit TEST-ONLY zero-order hold from the verified waveform to48kHz.
        // Channel1 is negated, so accidental channel summation erases the signal.
        let mut bytes = Vec::with_capacity(count * 8);
        for n in first..first + count {
            let value = samples[n / 4];
            bytes.extend_from_slice(&value.to_le_bytes());
            bytes.extend_from_slice(&(-value).to_le_bytes());
        }
        assert!(provider.queue.push(&bytes, count, first as u64, 0, 0));
        ingest_provider(&mut provider, &mut buffer, &mut windows);
        first += count;
        packet += 1;
    }
    // Explicit extra measured native SILENT interval permits FIR support beyond
    // the15-second boundary. The converter never pads unsupported waveform edges.
    assert_eq!(
        ingest(&mut buffer, provider.silent(720_000, 480, 0), &mut windows).0,
        180_056
    );
    assert_eq!(provider.epochs, 1);
    assert_eq!(windows.len(), 1);
    let window = windows.pop().unwrap();
    assert_eq!((window.origin, window.samples.len()), (0, 180_000));
    provider.source.stop();
    let decoder = decoder::Decoder::new();
    // This finite numerical-test context is not the production live history owner.
    let mut state = decoder::DecodeState::new(decoder::Mode::Ft8);
    let mut records = Vec::new();
    decoder
        .decode_window_into_async(
            window.samples,
            window.origin,
            &mut state,
            &|| false,
            &mut |record| {
                records.push(record.clone());
                Ok(())
            },
        )
        .await
        .unwrap();
    assert_eq!(records.len(), 1);
    let record = &records[0];
    assert_eq!(record.payload.text.as_deref(), Some("CQ K1ABC FN42"));
    assert_eq!(
        record.payload.payload77,
        vector["payload77"].as_str().unwrap()
    );
    assert_eq!(
        serde_json::to_value(&record.payload.fields).unwrap(),
        vector["fields"]
    );
    // FIRcenter128native frames is32canonical frames; it is accounted exactly once.
    assert!(record.start_frame.abs_diff(5968) <= 240);
    assert!((record.frequency_hz - 1000.0).abs() <= 1.0);
    println!(
        "verified native-provider FT8 callsign: {} start={} frequency={}",
        record.payload.text.as_deref().unwrap(),
        record.start_frame,
        record.frequency_hz
    );
}
