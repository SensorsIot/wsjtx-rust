#![forbid(unsafe_code)]
use std::cell::Cell;
use wstx_rust::decoder::{Decode, DecodeError, Mode, unpack};
#[path = "../src/decoder/history.rs"]
mod history;
use history::DecodeState;

fn record(start: u64, id: &str) -> Decode {
    let vectors: serde_json::Value = serde_json::from_str(include_str!(
        "../../fixtures/decoder/independent-vectors/manifest.json"
    ))
    .unwrap();
    let vector = vectors["vectors"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["mode"] == "ft8" && v["id"] == id)
        .unwrap();
    let bits = vector["payload77"]
        .as_str()
        .unwrap()
        .bytes()
        .map(|x| x - b'0')
        .collect::<Vec<_>>();
    Decode {
        payload: unpack(&bits.try_into().unwrap()),
        start_frame: start,
        frequency_hz: 1000.,
        snr_db: None,
    }
}

// Proves: FR-003, FR-004, CL-007-04.
#[test]
fn continuous_history_outlives_2048_publications_but_finite_utility_does_not() {
    for mode in [Mode::Ft4, Mode::Ft8] {
        let public = wstx_rust::decoder::DecodeState::new_live(mode);
        assert_eq!(public.mode(), mode);
        assert_eq!((public.available_count(), public.encoded_bytes()), (0, 0));
        let mut live = DecodeState::new_live(mode);
        let mut finite = DecodeState::new(mode);
        assert_eq!(live.mode(), mode);
        let live_callbacks = Cell::new(0);
        let finite_callbacks = Cell::new(0);
        let mut live_publish = |_: &Decode| {
            live_callbacks.set(live_callbacks.get() + 1);
            Ok(())
        };
        let mut finite_publish = |_: &Decode| {
            finite_callbacks.set(finite_callbacks.get() + 1);
            Ok(())
        };
        let mut sample = record(6000, "cq");
        for ordinal in 0..2050u64 {
            let origin = ordinal * 180000;
            sample.start_frame = origin + 6000;
            live.prepare_window(origin).unwrap();
            live.publish_if_new(&sample, &mut live_publish).unwrap();
            live.publish_if_new(&sample, &mut live_publish).unwrap();
            assert_eq!(live.available_count(), 1);
            assert!(live.encoded_bytes() <= 1024);
            assert_eq!(live.active_frequencies(origin, 180000), vec![1000.]);
            finite.prepare_window(origin).unwrap();
            let result = finite.publish_if_new(&sample, &mut finite_publish);
            if ordinal < 2048 {
                assert!(result.is_ok());
            } else {
                assert_eq!(result, Err(DecodeError::DecodeLimit));
            }
        }
        assert_eq!(live_callbacks.get(), 2050);
        assert_eq!(finite_callbacks.get(), 2048);
        assert_eq!(finite.available_count(), 2048);
        assert!(finite.encoded_bytes() <= 2097152);
    }
}

// Proves: FR-003, FR-004, CL-007-04.
#[test]
fn exact_half_symbol_boundary_is_retained_and_byte_charges_retire_exactly() {
    for mode in [Mode::Ft4, Mode::Ft8] {
        let half = (mode.symbol_frames() / 2) as u64;
        let mut state = DecodeState::new_live(mode);
        let callbacks = Cell::new(0);
        let mut publish = |_: &Decode| {
            callbacks.set(callbacks.get() + 1);
            Ok(())
        };
        state.prepare_window(0).unwrap();
        let first = record(0, "cq");
        state.publish_if_new(&first, &mut publish).unwrap();
        let first_charge = state.encoded_bytes();
        let mut finite = DecodeState::new(mode);
        finite.publish_if_new(&first, &mut |_| Ok(())).unwrap();
        assert_eq!(
            first_charge,
            finite.encoded_bytes() + 15,
            "live reserves16digits instead of ordinal0"
        );
        state.prepare_window(half).unwrap();
        let mut duplicate = first.clone();
        duplicate.start_frame = half;
        state.publish_if_new(&duplicate, &mut publish).unwrap();
        assert_eq!(callbacks.get(), 1);
        assert_eq!(
            (state.available_count(), state.encoded_bytes()),
            (1, first_charge)
        );
        let other = record(half + 10, "free");
        state.publish_if_new(&other, &mut publish).unwrap();
        let total = state.encoded_bytes();
        assert_eq!(state.available_count(), 2);
        state.prepare_window(half + 1).unwrap();
        assert_eq!(state.available_count(), 1);
        assert_eq!(state.encoded_bytes(), total - first_charge);
        duplicate.start_frame = half + 1;
        state.publish_if_new(&duplicate, &mut publish).unwrap();
        assert_eq!(callbacks.get(), 3);
    }
}

// Proves: FR-003, FR-004, CL-007-04.
#[test]
fn backwards_origin_rejects_atomically_and_new_context_resets_history() {
    let mut state = DecodeState::new_live(Mode::Ft8);
    state.prepare_window(1000).unwrap();
    state
        .publish_if_new(&record(1200, "cq"), &mut |_| Ok(()))
        .unwrap();
    let before = (state.available_count(), state.encoded_bytes());
    for _ in 0..2 {
        assert_eq!(state.prepare_window(999), Err(DecodeError::InvalidSamples));
        assert_eq!((state.available_count(), state.encoded_bytes()), before);
    }
    state.prepare_window(1000).unwrap();
    assert_eq!((state.available_count(), state.encoded_bytes()), before);
    let fresh = DecodeState::new_live(Mode::Ft8);
    assert_eq!((fresh.available_count(), fresh.encoded_bytes()), (0, 0));
}

// Proves: FR-003, FR-004, CL-007-04.
#[test]
fn rejected_publications_do_not_consume_history_or_invoke_limit_callbacks() {
    let mut state = DecodeState::new_live(Mode::Ft4);
    let sample = record(6000, "cq");
    assert_eq!(
        state.publish_if_new(&sample, &mut |_| Err(DecodeError::Cancelled)),
        Err(DecodeError::Cancelled)
    );
    assert_eq!((state.available_count(), state.encoded_bytes()), (0, 0));
    let mut oversized = sample.clone();
    oversized.payload.text = Some("A".repeat(2048));
    assert_eq!(
        state.publish_if_new(&oversized, &mut |_| panic!(
            "over-limit record must not publish"
        )),
        Err(DecodeError::DecodeLimit)
    );
    assert_eq!((state.available_count(), state.encoded_bytes()), (0, 0));
}
