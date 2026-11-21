use super::*;
// Every capture-thread loss event names its own
// epoch trigger (pool, contention and clock-step losses have no public injection path).
// Proves: TC-002-001
#[test]
fn each_loss_event_names_its_epoch_trigger() {
    let f = NativeFormat {
        rate: 48000,
        channels: 1,
        encoding: Encoding::Float32,
    };
    for event in CaptureEvent::ALL {
        if matches!(
            event,
            CaptureEvent::TimestampError
                | CaptureEvent::NativeDiscontinuity
                | CaptureEvent::FrameBackstep
        ) {
            continue; // packet-derived, not queue loss events
        }
        let q = PacketQueue::new(f).unwrap();
        let mut s = LiveSource::new(q.clone(), f).unwrap();
        assert!(q.push(&[], 480, 0, 0, SILENT));
        let SourcePoll::EpochChanged(first) = s.poll() else {
            panic!("initial epoch")
        };
        assert_eq!(first.trigger, "capture_start");
        let descriptor = Arc::new(SourceDescriptor {
            schema_version: 1,
            profile_id: "p".into(),
            boot_id: "b".into(),
            source_id: "first".into(),
            rate_hz: CANONICAL_HZ,
            channel: "mono_real",
            total_frames: None,
            utc_anchor: None,
        });
        let timing = SourceTiming {
            source_id: "first".into(),
            segment: 0,
            native_rate: 48000,
            native_anchor_frame: FILTER_DELAY as f64,
            canonical_anchor_frame: 0,
            converter_delay_native_frames: FILTER_DELAY as f64,
            qpc_anchor_100ns: Some(0),
            system_utc_anchor: None,
            uncertainty_ns: None,
            correlated: false,
            external_accuracy: crate::source::ExternalAccuracy::Unknown,
        };
        s.acknowledge_epoch(first.proposal_counter, descriptor, timing)
            .unwrap();
        while matches!(s.poll(), SourcePoll::Block(_)) {}
        q.mark_loss(event);
        q.mark_loss(CaptureEvent::QueueFull); // a later loss is counted, not the trigger
        assert!(q.push(&[], 480, 480, 100_000, SILENT));
        let SourcePoll::EpochChanged(loss) = s.poll() else {
            panic!("loss epoch")
        };
        assert_eq!((loss.reason, loss.trigger), ("capture_loss", event.code()));
    }
}
