use super::*;
fn point(start: usize, frequency: f64) -> Candidate {
    Candidate {
        start,
        frequency,
        score: 2.,
    }
}
// Proves: FR-004, CL-007-03.
#[test]
fn qualified_support_geometry_order_and_reset() {
    let a = point(0, 200.);
    assert!(!distinct(&a, &point(60479, 200.)));
    assert!(distinct(&a, &point(60480, 200.)));
    assert!(distinct(&a, &point(60481, 200.)));
    let edge = 200. + 12000. / 576. / 2.;
    assert!(!distinct(&a, &point(0, edge)));
    assert!(distinct(&a, &point(0, f64::from_bits(edge.to_bits() + 1))));
    let mut out = vec![];
    assert!(!admit(&[], &mut out, a, false).unwrap()); // physical failure excludes nothing.
    let mut later = point(100, 200.);
    later.score = 3.;
    assert!(admit(&[], &mut out, later, true).unwrap());
    assert!(!admit(&[], &mut out, a, true).unwrap()); // first qualified winner is stable.
    // Selection has no FEC/payload input: later FEC failure cannot release its support.
    let prior = out.clone();
    out.clear();
    assert!(!admit(&prior, &mut out, a, true).unwrap()); // earlier frequency candidate.
    assert!(admit(&[], &mut out, a, true).unwrap()); // new residual pass resets exclusions.
    assert!(admit(&[], &mut out, point(60480, 200.), true).unwrap());
}
// Proves: FR-004, CL-007-03.
#[test]
fn qualified_support_count_keeps_the_256_257_barrier() {
    let prior = (0..256)
        .map(|i| point(i / 128 * 60480, 200. + 20. * (i % 128) as f64))
        .collect::<Vec<_>>();
    let mut out = vec![];
    assert!(!admit(&prior, &mut out, prior[0], true).unwrap());
    assert_eq!(
        admit(&prior, &mut out, point(120960, 200.), true),
        Err(DecodeError::SearchLimited)
    );
    assert!(out.is_empty());
}
