use super::*;
use crate::decoder::resource_observer::{self, Phase};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

// Proves: CL-007-04; TC-004-003. The first hardword/syndrome comes from H alone.
#[test]
fn resource_phase_fec_stops_at_next_real_check_after_first_iteration() {
    let channel = Channel::new();
    let mut llr = [1f32; 174];
    llr[0] = -12.;
    let cancel = Arc::new(AtomicBool::new(false));
    let observed = resource_observer::install(cancel.clone(), Some(Phase::FecRow));
    let (word, _) = channel.beliefs(&llr, &|| cancel.load(Ordering::SeqCst));
    assert!(word.is_none());
    let report = observed.report();
    assert_eq!(report.counts[Phase::FecCheck as usize], 2);
    assert_eq!(report.counts[Phase::FecRow as usize], 83);
    assert_eq!(report.counts[Phase::FecIteration as usize], 1);
    let hard = report.first_fec_word.unwrap();
    let mut expected = [0u8; 174];
    expected[0] = 1;
    assert_eq!(hard, expected);
    let unsatisfied = channel
        .checks
        .iter()
        .enumerate()
        .filter_map(|(row, columns)| {
            (columns.iter().fold(0, |v, &j| v ^ hard[j]) != 0).then_some(row)
        })
        .collect::<Vec<_>>();
    assert_eq!(unsatisfied, [15, 44, 72]);
    drop(observed);
    let witness = resource_observer::install(Arc::new(AtomicBool::new(false)), None);
    channel.beliefs(&llr, &|| false);
    assert_eq!(witness.report().first_fec_word, Some(expected));
}

// Proves: CL-007-04; TC-004-003. Direct OSD composition, not a claim of BP failure.
#[test]
fn resource_phase_recovery_observes_rank_and_cost_before_cancel() {
    let channel = Channel::new();
    let llr = [1f32; 174];
    let cancel = Arc::new(AtomicBool::new(false));
    let observed = resource_observer::install(cancel.clone(), Some(Phase::RecoveryTrial));
    assert!(
        channel
            .osd(&llr, &llr, &|| cancel.load(Ordering::SeqCst))
            .is_none()
    );
    let report = observed.report();
    assert_eq!(report.counts[Phase::RecoveryRank as usize], 1);
    assert_eq!(report.counts[Phase::RecoveryTrial as usize], 1);
    assert_eq!(report.counts[Phase::RecoveryCheck as usize], 2);
    drop(observed);
    let word = channel.osd(&llr, &llr, &|| false).unwrap();
    assert_eq!(word, [0; 174]);
    assert!(channel.valid(&word));
    assert_eq!(channel.decode(&llr, &|| false), Some(word));
}
