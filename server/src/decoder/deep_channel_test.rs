use super::*;
use crate::decoder::search::complete;
use serde_json::Value;
use std::cell::Cell;

fn oracle() -> Value {
    serde_json::from_str(include_str!("../../../fixtures/decoder/deep-oracles.json")).unwrap()
}
fn numbers(value: &Value) -> Vec<f32> {
    value
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_f64().unwrap() as f32)
        .collect()
}

// Proves: CL-007-03, TC-004-002. Independent named-evidence oracle, not a decoder golden.
#[test]
fn cumulative_snapshots_include_full_posteriors() {
    let o = oracle();
    let o = &o["snapshots"];
    let l = numbers(&o["L"]);
    let c1 = numbers(&o["C1"]);
    let c2 = numbers(&o["C2"]);
    let mut cumulative = [0.; 174];
    let mut posterior = [0.; 174];
    posterior[..3].copy_from_slice(&l);
    accumulate(&mut cumulative, &posterior);
    for i in 0..3 {
        posterior[i] = l[i] + c1[i];
    }
    accumulate(&mut cumulative, &posterior);
    assert_eq!(&cumulative[..3], numbers(&o["first"]));
    assert_ne!(&cumulative[..3], numbers(&o["wrong_check_only_first"]));
    for i in 0..3 {
        posterior[i] = l[i] + c2[i];
    }
    accumulate(&mut cumulative, &posterior);
    assert_eq!(&cumulative[..3], numbers(&o["second"]));
    assert_ne!(&cumulative[..3], numbers(&o["wrong_check_only_second"]));
}

// Proves: CL-007-03, TC-004-002. 80-digit Decimal ln(5/3) and exact sign/zero controls.
#[test]
fn sum_product_matches_independent_check_oracle() {
    let o = oracle();
    let o = &o["check_message"];
    let expected: f64 = o["expected_2atanh_product"]
        .as_str()
        .unwrap()
        .parse()
        .unwrap();
    assert!((invert_check_product(0.25) - expected).abs() <= 1e-12);
    assert!((invert_check_product(-0.25) + expected).abs() <= 1e-12);
    assert_eq!(check_message(&[1., 0., 100.], 0), 0.);
    let ln3 = 3f32.ln();
    assert!((check_message(&[0., ln3, ln3], 0) - expected as f32).abs() <= f32::EPSILON);
    assert!(check_message(&[0., 1000., 1000.], 0).is_finite());
}

// Proves: CL-007-03, TC-004-003. Exhaustive independent small-code catalogue.
#[test]
fn nearest_parity_word_is_not_filtered_by_crc_during_search() {
    let o = oracle();
    let o = &o["nearest_then_crc_negative"];
    let mut reliability = [0.; 174];
    reliability[..6].copy_from_slice(&numbers(&o["llr"]));
    let mut rows = vec![];
    for raw in [[1, 0, 0, 1, 0, 1], [0, 1, 0, 1, 1, 0], [0, 0, 1, 1, 1, 1]] {
        let mut word = Bits::default();
        for (i, b) in raw.into_iter().enumerate() {
            if b != 0 {
                word.set(i);
            }
        }
        rows.push(word);
    }
    let cancel = || false;
    let mut budget = CpuBudget::new(&cancel);
    let basis = complete(OrderedBasis::new(&rows, &reliability, &mut budget))
        .unwrap()
        .unwrap();
    let word = complete(basis.nearest(&mut budget))
        .unwrap()
        .unwrap()
        .word();
    let fixed = &o["all_eight_words"][0];
    assert_eq!(
        &word[..6],
        fixed["word"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_u64().unwrap() as u8)
            .collect::<Vec<_>>()
    );
    assert_eq!(word[0] ^ word[1], 1);
    assert_eq!(
        word[2], 0,
        "nearest parity word must fail independent toy CRC"
    );
    assert_eq!(basis.cost(Bits::default()), 12.);
}

// Proves: CL-007-03, TC-004-002. Frozen external payload/channel vectors.
#[test]
fn independent_channel_words_and_low_reliability_errors_decode() {
    let vectors: Value = serde_json::from_str(include_str!(
        "../../../fixtures/decoder/independent-vectors/manifest.json"
    ))
    .unwrap();
    let channel = Channel::new();
    let deep = DeepChannel::new(&channel);
    for vector in vectors["vectors"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|v| v["mode"] == "ft8")
        .take(5)
    {
        let expected: ChannelWord = vector["codeword174"]
            .as_str()
            .unwrap()
            .bytes()
            .map(|b| b - b'0')
            .collect::<Vec<_>>()
            .try_into()
            .unwrap();
        let mut llr = std::array::from_fn(|i| if expected[i] == 0 { 5. } else { -5. });
        for i in [0, 11, 22, 33, 44, 55, 66, 77, 88, 99, 110, 121] {
            llr[i] *= -0.03;
        }
        let cancel = || false;
        let mut budget = CpuBudget::new(&cancel);
        let words = complete(deep.decode(&channel, &llr, &mut budget)).unwrap();
        assert!(words.contains(&expected), "{}", vector["id"]);
    }
}

// Proves: CL-007-04, TC-004-003. Parity validity cannot substitute for independent CRC.
#[test]
fn full_rank_parity_word_with_bad_crc_is_rejected() {
    let channel = Channel::new();
    let deep = DeepChannel::new(&channel);
    let bad = deep.generator[80].word();
    assert!(
        deep.checks
            .iter()
            .all(|row| row.iter().fold(0, |p, &i| p ^ bad[i]) == 0)
    );
    assert!(!channel.valid(&bad));
    let llr = std::array::from_fn(|i| if bad[i] == 0 { 100. } else { -100. });
    let cancel = || false;
    let mut budget = CpuBudget::new(&cancel);
    assert!(
        complete(deep.decode(&channel, &llr, &mut budget))
            .unwrap()
            .is_empty()
    );
}

// Proves: CL-007-04, TC-004-003. Cooperative rejection is distinct from cancellation.
#[test]
fn invalid_values_zero_word_and_osd_cancellation() {
    let channel = Channel::new();
    let deep = DeepChannel::new(&channel);
    let cancel = || false;
    let mut budget = CpuBudget::new(&cancel);
    assert!(
        complete(deep.decode(&channel, &[f32::NAN; 174], &mut budget))
            .unwrap()
            .is_empty()
    );
    assert!(
        complete(deep.decode(&channel, &[5.; 174], &mut budget))
            .unwrap()
            .is_empty()
    );
    let calls = Cell::new(0);
    let cancel = || {
        calls.set(calls.get() + 1);
        calls.get() > 100
    };
    let mut budget = CpuBudget::new(&cancel);
    let rows = deep.generator.clone();
    let llr = [1.; 174];
    let result = complete(async {
        let b = OrderedBasis::new(&rows, &llr, &mut budget).await?.unwrap();
        b.nearest(&mut budget).await
    });
    assert_eq!(result.unwrap_err(), DecodeError::Cancelled);
}

// Observation-only events originate in the production loop/search, never substitute decisions.
#[derive(Clone, Debug)]
pub(super) enum Event {
    Posterior(usize, usize),
    Update(usize),
    Snapshot(usize, [f32; 174]),
    Pattern(usize, bool),
    BasisInput([f32; 174]),
}
thread_local! {
    static TRACE: std::cell::RefCell<Option<Vec<Event>>> = const {std::cell::RefCell::new(None)};
}
pub(super) fn record(event: Event) {
    TRACE.with(|trace| {
        if let Some(events) = trace.borrow_mut().as_mut() {
            events.push(event);
        }
    });
}
fn trace_start() {
    TRACE.with(|trace| *trace.borrow_mut() = Some(vec![]));
}
fn trace_finish() -> Vec<Event> {
    TRACE.with(|trace| trace.borrow_mut().take().unwrap())
}
fn identity_rows(rank: usize) -> Vec<Bits> {
    (0..rank)
        .map(|i| {
            let mut row = Bits::default();
            row.set(i);
            row
        })
        .collect()
}

// Proves: CL-007-03, TC-004-002. Degree-one checks send a constant positive clamped message.
// -1000 input stays negative for all16 checks, so unsatisfied counts are independently fixed.
#[test]
fn production_bp_update_and_early_stop_boundaries() {
    let channel = Channel::new();
    for count in [14, 15, 16] {
        let deep = DeepChannel {
            generator: identity_rows(1),
            checks: vec![vec![0]; count],
        };
        let mut llr = [0.; 174];
        llr[0] = -1000.;
        let cancel = || false;
        let mut budget = CpuBudget::new(&cancel);
        trace_start();
        complete(deep.decode(&channel, &llr, &mut budget)).unwrap();
        let trace = trace_finish();
        let posteriors = trace
            .iter()
            .filter_map(|event| match event {
                Event::Posterior(i, n) => Some((*i, *n)),
                _ => None,
            })
            .collect::<Vec<_>>();
        let updates = trace
            .iter()
            .filter_map(|event| match event {
                Event::Update(i) => Some(*i),
                _ => None,
            })
            .collect::<Vec<_>>();
        let last = if count == 16 { 10 } else { 30 };
        assert_eq!(
            posteriors,
            (0..=last).map(|i| (i, count)).collect::<Vec<_>>()
        );
        assert_eq!(updates, (0..last).collect::<Vec<_>>());
        assert!(posteriors.contains(&(9, count)) && posteriors.contains(&(10, count)));
        if count <= 15 {
            assert_eq!(updates.len(), 30);
            assert_eq!(posteriors.len(), 31);
        } else {
            assert_eq!(updates.last(), Some(&9));
            assert_eq!(posteriors.last(), Some(&(10, 16)));
        }
    }
}

// Proves: CL-007-03, TC-004-002. One degree-two parity check returns the other variable's LLR.
// L0=L1=1 => C1=C2=1 exactly; stored cumulative snapshots must therefore be3 and5, not2.
#[test]
fn production_snapshot_capture_contains_accumulated_full_posteriors() {
    let channel = Channel::new();
    let mut row = Bits::default();
    row.set(0);
    row.set(1);
    let deep = DeepChannel {
        generator: vec![row],
        checks: vec![vec![0, 1]],
    };
    let mut llr = [0.; 174];
    llr[0] = 1.;
    llr[1] = 1.;
    let cancel = || false;
    let mut budget = CpuBudget::new(&cancel);
    trace_start();
    complete(deep.decode(&channel, &llr, &mut budget)).unwrap();
    let trace = trace_finish();
    let basis_inputs = trace
        .iter()
        .filter_map(|event| match event {
            Event::BasisInput(input) => Some(input),
            _ => None,
        })
        .collect::<Vec<_>>();
    assert_eq!(basis_inputs.len(), 2);
    assert_eq!(&basis_inputs[0][..2], &[3., 3.]);
    assert_eq!(&basis_inputs[1][..2], &[5., 5.]);
    let snapshots = trace
        .into_iter()
        .filter_map(|event| match event {
            Event::Snapshot(i, s) => Some((i, s)),
            _ => None,
        })
        .collect::<Vec<_>>();
    assert_eq!(snapshots.len(), 2);
    for ((iteration, snapshot), value) in snapshots.iter().zip([3., 5.]) {
        assert_eq!(*iteration, if value == 3. { 1 } else { 2 });
        assert_eq!(&snapshot[..2], &[value, value]);
        assert!(snapshot[2..].iter().all(|&x| x == 0.));
    }
}

// Proves: CL-007-03, TC-004-002. Independent identity-column rank and combinatorial enumeration.
#[test]
fn production_rank_and_4187_pattern_boundaries() {
    let cancel = || false;
    let mut budget = CpuBudget::new(&cancel);
    let reliability = [1.; 174];
    let production = DeepChannel::new(&Channel::new());
    assert_eq!(production.generator.len(), 91);
    let production_basis = complete(OrderedBasis::new(
        &production.generator,
        &reliability,
        &mut budget,
    ))
    .unwrap()
    .unwrap();
    assert_eq!(production_basis.rows.len(), 91);
    let mut deficient = identity_rows(91);
    deficient[90] = deficient[89];
    assert!(
        complete(OrderedBasis::new(&deficient, &reliability, &mut budget))
            .unwrap()
            .is_none()
    );
    let basis = complete(OrderedBasis::new(
        &identity_rows(91),
        &reliability,
        &mut budget,
    ))
    .unwrap()
    .unwrap();
    assert_eq!(basis.rows.len(), 91);
    trace_start();
    assert_eq!(
        complete(basis.nearest(&mut budget)).unwrap(),
        Some(Bits::default())
    );
    let patterns = trace_finish()
        .into_iter()
        .filter_map(|event| match event {
            Event::Pattern(w, a) => Some((w, a)),
            _ => None,
        })
        .collect::<Vec<_>>();
    // Independent count: one zero,91 singles,C(91,2)=4095 pairs.
    assert_eq!(patterns.len(), 4187);
    assert_eq!(patterns.iter().filter(|&&(w, _)| w == 0).count(), 1);
    assert_eq!(patterns.iter().filter(|&&(w, _)| w == 1).count(), 91);
    assert_eq!(patterns.iter().filter(|&&(w, _)| w == 2).count(), 4095);
    assert_eq!(patterns.get(4185), Some(&(2, true)));
    assert_eq!(patterns.get(4186), Some(&(1, true)));
    assert_eq!(patterns.get(4187), None);
}

// Proves: CL-007-03, TC-004-002. A rank-one code whose only nonzero word is cheaper.
// Hard-zero pivot costs5 to flip;32/31/30 negative parity signs make that word nearer.
// In first40 parity columns its total mismatch+pattern weight is9/10/11 respectively.
#[test]
fn production_prefilter_9_10_11_controls_nearest_word() {
    for total in [9, 10, 11] {
        let mut row = Bits::default();
        for i in 0..=40 {
            row.set(i);
        }
        let mut reliability = [0.01; 174];
        reliability[0] = 5.;
        for value in &mut reliability[1..=41 - total] {
            *value = -1.;
        }
        let cancel = || false;
        let mut budget = CpuBudget::new(&cancel);
        let basis = complete(OrderedBasis::new(&[row], &reliability, &mut budget))
            .unwrap()
            .unwrap();
        trace_start();
        let actual = complete(basis.nearest(&mut budget)).unwrap().unwrap();
        let patterns = trace_finish()
            .into_iter()
            .filter_map(|event| match event {
                Event::Pattern(w, a) => Some((w, a)),
                _ => None,
            })
            .collect::<Vec<_>>();
        assert_eq!(patterns, vec![(0, true), (1, total <= 10)]);
        assert_eq!(actual, if total <= 10 { row } else { Bits::default() });
    }
}
