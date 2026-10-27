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
