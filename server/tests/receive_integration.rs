#![forbid(unsafe_code)]
pub use wstx_rust::decoder;
#[path = "../src/receive.rs"]
mod receive;
#[path = "../src/source.rs"]
pub mod source;

use decoder::Mode;
use receive::{WindowBuffer, WindowError};
use source::{ExternalAccuracy, SampleBlock, SourceDescriptor, SourceTiming};
use std::sync::Arc;

fn descriptor() -> Arc<SourceDescriptor> {
    Arc::new(SourceDescriptor {
        schema_version: 1,
        profile_id: "profile".into(),
        boot_id: "boot".into(),
        source_id: "source".into(),
        rate_hz: 12000,
        channel: "mono_real",
        total_frames: None,
        utc_anchor: None,
    })
}
fn timing() -> Arc<SourceTiming> {
    Arc::new(SourceTiming {
        source_id: "source".into(),
        segment: 1,
        native_rate: 48000,
        native_anchor_frame: 128.,
        canonical_anchor_frame: 0,
        converter_delay_native_frames: 128.,
        qpc_anchor_100ns: None,
        system_utc_anchor: None,
        uncertainty_ns: None,
        correlated: false,
        external_accuracy: ExternalAccuracy::Unknown,
    })
}
fn block(first: u64, count: usize) -> SampleBlock {
    SampleBlock {
        source: descriptor(),
        first_frame: first,
        samples: (0..count)
            .map(|offset| ((first + offset as u64) % 97) as f32 / 128.)
            .collect(),
        discontinuity: false,
        end_of_stream: false,
        timing: Some(timing()),
    }
}
fn windows(mode: Mode, frames: u64, partitions: &[usize]) -> Vec<(u64, Vec<f32>)> {
    let mut buffer = WindowBuffer::new(mode, descriptor()).unwrap();
    let mut output = vec![];
    let mut first = 0;
    let mut partition = 0;
    while first < frames {
        let count = (partitions[partition % partitions.len()] as u64).min(frames - first);
        let result = buffer.push(&block(first, count as usize)).unwrap();
        assert_eq!(result.captured_next_frame, first + count);
        assert!(!result.reset_decoder);
        if let Some(window) = result.window {
            output.push((window.origin, window.samples));
        }
        first += count;
        partition += 1;
    }
    output
}

// Proves: FR-002, FR-003, CL-008-02; TC-002-001/003. Integer sample clock fixes window edges.
#[test]
fn receive_windows_follow_mode_boundaries_independent_of_packet_partition() {
    for (mode, step, span) in [(Mode::Ft8, 180000, 360000), (Mode::Ft4, 90000, 180000)] {
        let partitioned = windows(mode, step * 4, &[239, 1, 117, 240]);
        let regular = windows(mode, step * 4, &[240]);
        assert_eq!(partitioned, regular);
        assert_eq!(partitioned.len(), 4);
        for (index, (origin, samples)) in partitioned.iter().enumerate() {
            let end = step * (index as u64 + 1);
            assert_eq!(*origin, end.saturating_sub(span));
            assert_eq!(samples.len() as u64, end - origin);
            for (offset, &sample) in samples.iter().enumerate() {
                assert_eq!(sample, ((*origin + offset as u64) % 97) as f32 / 128.);
            }
        }
    }
}

// Proves: FR-002, FR-003, CL-008-02; TC-002-001/003. A known gap never becomes decoder padding.
#[test]
fn receive_known_gap_resets_support_preserving_global_positions() {
    let mut buffer = WindowBuffer::new(Mode::Ft4, descriptor()).unwrap();
    for first in (0..90000).step_by(240) {
        buffer.push(&block(first, 240)).unwrap();
    }
    let mut marked = block(170000, 240);
    marked.discontinuity = true;
    let reset = buffer.push(&marked).unwrap();
    assert!(reset.reset_decoder);
    assert!(reset.window.is_none());
    let mut output = vec![];
    let mut first = 170240;
    while first < 270000 {
        let count = (270000 - first).min(240);
        if let Some(window) = buffer.push(&block(first, count as usize)).unwrap().window {
            output.push(window);
        }
        first += count;
    }
    // At180000 only10000 actually captured post-gap samples exist: no complete FT4 support.
    assert_eq!(output.len(), 1);
    assert_eq!(output[0].origin, 170000);
    assert_eq!(output[0].samples.len(), 100000);
    assert_eq!(output[0].samples[0], (170000 % 97) as f32 / 128.);
}

// Proves: FR-002, FR-003, CL-008-02; TC-002-001/003. Invalid blocks cannot mutate accepted history.
#[test]
fn receive_rejects_overlap_unmarked_gap_changed_context_and_bad_samples() {
    let mut buffer = WindowBuffer::new(Mode::Ft8, descriptor()).unwrap();
    buffer.push(&block(0, 240)).unwrap();
    for invalid in [block(0, 240), block(100, 240), block(241, 1)] {
        assert_eq!(buffer.push(&invalid).err(), Some(WindowError::InvalidBlock));
    }
    let mut changed = block(240, 1);
    Arc::make_mut(&mut changed.source).boot_id = "other-boot".into();
    assert_eq!(
        buffer.push(&changed).err(),
        Some(WindowError::InvalidContext)
    );
    changed = block(240, 1);
    Arc::make_mut(changed.timing.as_mut().unwrap()).native_anchor_frame = 129.;
    assert_eq!(
        buffer.push(&changed).err(),
        Some(WindowError::InvalidContext)
    );
    changed = block(240, 1);
    changed.samples = Arc::from([f32::NAN]);
    assert_eq!(buffer.push(&changed).err(), Some(WindowError::InvalidBlock));
    changed = block(240, 1);
    changed.end_of_stream = true;
    assert_eq!(buffer.push(&changed).err(), Some(WindowError::InvalidBlock));
    assert_eq!(
        buffer.push(&block(240, 1)).unwrap().captured_next_frame,
        241
    );
    assert!(
        WindowBuffer::new(
            Mode::Ft8,
            Arc::new(SourceDescriptor {
                total_frames: Some(180000),
                ..(*descriptor()).clone()
            })
        )
        .is_err()
    );
}

// Proves: FR-002, FR-003, CL-008-02; TC-002-001/003. Counter and block limits fail before wrapping.
#[test]
fn receive_input_limits_and_initial_discontinuity_are_explicit() {
    let mut buffer = WindowBuffer::new(Mode::Ft8, descriptor()).unwrap();
    for count in [0, 241] {
        assert_eq!(
            buffer.push(&block(0, count)).err(),
            Some(WindowError::InvalidBlock)
        );
    }
    assert_eq!(
        buffer.push(&block(source::MAX_COUNTER, 1)).err(),
        Some(WindowError::CounterExhausted)
    );
    let mut first = block(0, 240);
    first.discontinuity = true;
    assert!(!buffer.push(&first).unwrap().reset_decoder);
    let mut reset = block(240, 240);
    reset.discontinuity = true;
    assert!(buffer.push(&reset).unwrap().reset_decoder);
}
