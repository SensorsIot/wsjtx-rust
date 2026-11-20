use super::*;
use wstx_test_tools::resource_observer::{self, CancelPoint};

// The first hardword/syndrome comes from H alone.
#[test]
fn resource_phase_fec_stops_at_next_real_check_after_first_iteration() {
    let channel = Channel::new();
    let mut llr = [1f32; 174];
    llr[0] = -12.;
    // Call 1 is the start of iteration 0; call 2, the start of iteration 1, answers true.
    let point = CancelPoint::after(1);
    let context = serde_json::json!({"phase":"fec","composition":"real private beliefs; no waveform BP-failure claim",
        "input_sha256":resource_observer::cases()["fec"]["sha256"]});
    let began = std::time::Instant::now();
    let (word, _) = channel.beliefs(&llr, &[false; 174], &|| point.cancelled());
    let returned = std::time::Instant::now();
    point.record_return(
        &context,
        began,
        returned,
        "synchronous private channel call; not a Future::poll",
    );
    assert!(word.is_none());
    assert_eq!(point.calls(), 2);
    // One bit wrong: iteration 0 does not stop, so the second check follows a whole
    // iteration over these unsatisfied rows.
    let mut expected = [0u8; 174];
    expected[0] = 1;
    let unsatisfied = channel
        .checks
        .iter()
        .enumerate()
        .filter_map(|(row, columns)| {
            (columns.iter().fold(0, |v, &j| v ^ expected[j]) != 0).then_some(row)
        })
        .collect::<Vec<_>>();
    assert_eq!(unsatisfied, [15, 44, 72]);
    let positive_began = std::time::Instant::now();
    channel.beliefs(&llr, &[false; 174], &|| false);
    eprintln!(
        "RESOURCE_SYNC_CONTROL {}",
        serde_json::json!({"context":context,"positive":true,
        "wall_seconds":positive_began.elapsed().as_secs_f64(),"future_poll":false,"cpu_time_measured":false})
    );
}

// Direct OSD composition, not a claim of BP failure.
#[test]
fn resource_phase_recovery_observes_rank_and_cost_before_cancel() {
    let channel = Channel::new();
    let llr = [1f32; 174];
    // Call 1 is the first position after the elimination; call 2, the next, answers true.
    let point = CancelPoint::after(1);
    let context = serde_json::json!({"phase":"recovery","composition":"real private OSD, not waveform-triggered BP failure",
        "input_sha256":resource_observer::cases()["recovery"]["sha256"]});
    let began = std::time::Instant::now();
    let outcome = channel.osd(&llr, &[false; 174], &|| point.cancelled());
    let returned = std::time::Instant::now();
    point.record_return(
        &context,
        began,
        returned,
        "synchronous private channel call; not a Future::poll",
    );
    assert!(outcome.is_none());
    assert_eq!(point.calls(), 2);
    let never = CancelPoint::after(1000);
    let positive_began = std::time::Instant::now();
    let (word, errors) = channel
        .osd(&llr, &[false; 174], &|| never.cancelled())
        .unwrap();
    eprintln!(
        "RESOURCE_SYNC_CONTROL {}",
        serde_json::json!({"context":context,"positive":true,
        "wall_seconds":positive_began.elapsed().as_secs_f64(),"future_poll":false,"cpu_time_measured":false})
    );
    assert_eq!(never.calls(), K);
    assert_eq!(word, [0; 174]);
    assert_eq!(errors, 0);
    assert!(channel.valid(&word));
    assert_eq!(channel.decode(&llr, &|| false), Some(word));
}
