#![forbid(unsafe_code)]
#[path = "../src/source.rs"]
pub mod source;

use source::*;
use std::sync::Arc;

fn context(id: &str) -> (Arc<SourceDescriptor>, SourceTiming) {
    let descriptor = Arc::new(SourceDescriptor {
        schema_version: 1,
        profile_id: "profile".into(),
        boot_id: "boot".into(),
        source_id: id.into(),
        rate_hz: CANONICAL_HZ,
        channel: "mono_real",
        total_frames: None,
        utc_anchor: None,
    });
    let timing = SourceTiming {
        source_id: id.into(),
        segment: 0,
        native_rate: 48_000,
        native_anchor_frame: 1000.0,
        canonical_anchor_frame: 0,
        converter_delay_native_frames: 255.5,
        qpc_anchor_100ns: Some(123),
        system_utc_anchor: None,
        uncertainty_ns: None,
        correlated: false,
        external_accuracy: ExternalAccuracy::Unknown,
    };
    (descriptor, timing)
}

// Proves: CL-008-02, CL-008-03; TC-002-001, TC-009-004.
#[test]
fn epoch_requires_current_owner_ack_and_rejects_old_identity() {
    let mut latch = EpochLatch::default();
    let first = latch
        .propose("opening", 48_000, 1000, Some(123), 255.5)
        .unwrap();
    assert!(latch.context().is_none());
    assert_eq!(latch.pending(), Some(&first));
    let (desc, timing) = context("source-one");
    assert_eq!(
        latch.acknowledge(first.proposal_counter + 1, desc.clone(), timing.clone()),
        Err(SourceError::StaleAcknowledgement)
    );
    assert!(latch.context().is_none());
    latch
        .acknowledge(first.proposal_counter, desc.clone(), timing.clone())
        .unwrap();
    assert!(Arc::ptr_eq(&latch.context().unwrap().descriptor, &desc));
    let block =
        SampleBlock::live(latch.context().unwrap(), 0, Arc::from([0.0, 0.5]), false).unwrap();
    assert!(Arc::ptr_eq(&block.source, &desc));
    assert_eq!(block.samples.as_ref(), &[0.0, 0.5]);
    assert!(!block.end_of_stream);
    let next = latch
        .propose("timestamp_error", 48_000, 2000, None, 255.5)
        .unwrap();
    assert!(latch.context().is_none());
    assert_eq!(
        latch.acknowledge(next.proposal_counter, desc, timing),
        Err(SourceError::InvalidContext)
    );
    let (desc, timing) = context("source-two");
    latch
        .acknowledge(next.proposal_counter, desc, timing)
        .unwrap();
    assert_eq!(
        latch.acknowledge(
            first.proposal_counter,
            context("source-three").0,
            context("source-three").1
        ),
        Err(SourceError::StaleAcknowledgement)
    );
}

// Proves: CL-008-02; TC-002-001.
#[test]
fn source_blocks_enforce_real_finite_bounded_sample_intervals() {
    let (descriptor, timing) = context("source");
    let ctx = SourceContext {
        descriptor,
        timing: Arc::new(timing),
    };
    assert!(
        SampleBlock::live(&ctx, MAX_COUNTER - 240, Arc::from([0.0; 240]), true)
            .unwrap()
            .discontinuity
    );
    for samples in [
        Vec::new(),
        vec![0.0; 241],
        vec![f32::NAN],
        vec![f32::INFINITY],
    ] {
        assert!(matches!(
            SampleBlock::live(&ctx, 0, Arc::from(samples), false),
            Err(SourceError::InvalidBlock)
        ));
    }
    assert!(matches!(
        SampleBlock::live(&ctx, MAX_COUNTER, Arc::from([0.0]), false),
        Err(SourceError::InvalidBlock)
    ));
}

// Proves: CL-008-02, CL-008-03; TC-002-001.
#[test]
fn correlated_system_clock_is_not_an_external_accuracy_claim() {
    let (descriptor, mut timing) = context("source");
    timing.correlated = true;
    assert!(!timing.valid_for(&descriptor));
    timing.system_utc_anchor = Some("2026-10-26T12:00:00Z".into());
    timing.uncertainty_ns = Some(2_000_000);
    assert!(timing.valid_for(&descriptor));
    timing.uncertainty_ns = Some(2_000_001);
    assert!(!timing.valid_for(&descriptor));
    timing.uncertainty_ns = Some(1);
    timing.converter_delay_native_frames = f64::NAN;
    assert!(!timing.valid_for(&descriptor));
}
