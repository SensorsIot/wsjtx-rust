use super::super::search::complete;
use super::*;
// Proves: FR-003, FR-004, CL-007-03.
#[test]
fn independent_decimal_exhaustive_metric_families() {
    let fixture: serde_json::Value = serde_json::from_str(include_str!(
        "../../../fixtures/decoder/physical-metric-cases.json"
    ))
    .unwrap();
    let cases = fixture["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 6);
    for case in cases {
        let mode = match case["mode"].as_str().unwrap() {
            "ft8" => Mode::Ft8,
            "ft4" => Mode::Ft4,
            _ => panic!("mode"),
        };
        let rows = case["rows"]
            .as_array()
            .unwrap()
            .iter()
            .map(|row| {
                row.as_array()
                    .unwrap()
                    .iter()
                    .map(|z| Complex64::new(z[0].as_f64().unwrap(), z[1].as_f64().unwrap()))
                    .collect::<Vec<_>>()
            })
            .collect::<Vec<_>>();
        let never = || false;
        let mut budget = CpuBudget::new(&never);
        let actual = match mode {
            Mode::Ft8 => complete(ft8(&rows, &mut budget)),
            Mode::Ft4 => complete(ft4(&rows, &mut budget)),
        }
        .unwrap();
        let expected = case["expected_f32"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|x| !x.is_null())
            .collect::<Vec<_>>();
        assert_eq!(actual.len(), expected.len(), "{}", case["id"]);
        for (family, (actual, expected)) in actual.iter().zip(expected).enumerate() {
            for (bit, (&a, e)) in actual.iter().zip(expected.as_array().unwrap()).enumerate() {
                let e = e.as_f64().unwrap() as f32;
                assert!(
                    a.is_finite() && (a == e || a.to_bits().abs_diff(e.to_bits()) <= 1),
                    "{} family{family} bit{bit}: {a} != Decimal80 {e}",
                    case["id"]
                );
            }
        }
    }
}
// Proves: FR-003, FR-004, CL-007-03, CL-007-04.
#[test]
fn population_normalization_has_no_mean_subtraction_or_clipping() {
    let constant = normalize(&[2.; 174]).unwrap();
    assert!(constant.iter().all(|&x| (x + 2.83).abs() < 1e-12));
    let mut impulse = [0.; 174];
    impulse[41] = 1.;
    let actual = normalize(&impulse).unwrap();
    let expected = -2.83 * 174. / 173f64.sqrt();
    assert!((actual[41] - expected).abs() < 1e-10 && actual[41] < -37.);
    assert!(actual.iter().enumerate().all(|(i, &x)| i == 41 || x == 0.));
    for raw in [
        vec![0.; 174],
        vec![],
        vec![f64::NAN; 174],
        vec![f64::INFINITY; 174],
    ] {
        assert!(normalize(&raw).is_none());
    }
}
fn sync_rows(mode: Mode, correct: usize, single_bit_errors: usize) -> Vec<Vec<Complex64>> {
    let mut rows = vec![
        vec![Complex64::new(0., 0.); mode.tone_count()];
        if mode == Mode::Ft8 { 79 } else { 103 }
    ];
    for (i, (s, tone)) in mode.sync().into_iter().enumerate() {
        let physical = if i < correct {
            tone as usize
        } else if mode == Mode::Ft8 {
            (tone as usize + 1) % 8
        } else {
            let value = mode
                .gray_map()
                .iter()
                .position(|&t| t == tone as usize)
                .unwrap();
            mode.gray_map()[value
                ^ if i - correct < single_bit_errors {
                    1
                } else {
                    3
                }]
        };
        rows[if mode == Mode::Ft4 { s - 1 } else { s }][physical].re = 1.;
    }
    rows
}
// Proves: FR-003, FR-004, CL-007-03, CL-007-04.
#[test]
fn physical_sync_boundaries_are_independent_tone_and_bit_barriers() {
    assert!(!physical_accepts(Mode::Ft8, &sync_rows(Mode::Ft8, 8, 0)));
    assert!(physical_accepts(Mode::Ft8, &sync_rows(Mode::Ft8, 9, 0)));
    assert_eq!(
        physical_hits(Mode::Ft4, &sync_rows(Mode::Ft4, 8, 3)),
        (8, 19)
    );
    assert!(!physical_accepts(Mode::Ft4, &sync_rows(Mode::Ft4, 8, 3)));
    assert_eq!(
        physical_hits(Mode::Ft4, &sync_rows(Mode::Ft4, 8, 4)),
        (8, 20)
    );
    assert!(physical_accepts(Mode::Ft4, &sync_rows(Mode::Ft4, 8, 4)));
    assert_eq!(
        physical_hits(Mode::Ft4, &sync_rows(Mode::Ft4, 7, 9)),
        (7, 23)
    );
    assert!(!physical_accepts(Mode::Ft4, &sync_rows(Mode::Ft4, 7, 9)));
}

fn vector_word() -> Vec<u8> {
    let manifest: serde_json::Value = serde_json::from_str(include_str!(
        "../../../fixtures/decoder/independent-vectors/manifest.json"
    ))
    .unwrap();
    manifest["vectors"][0]["codeword174"]
        .as_str()
        .unwrap()
        .bytes()
        .map(|b| b - b'0')
        .collect()
}
/// Channel LLRs of the word with the first `errors` bits weak and of the wrong sign.
fn weak_errors(bits: &[u8], errors: usize) -> [f32; 174] {
    let mut llr = std::array::from_fn(|i| if bits[i] == 0 { 8f32 } else { -8f32 });
    for x in &mut llr[..errors] {
        *x = -x.signum() * 0.001;
    }
    llr
}
// Proves: FR-003, FR-004, CL-007-03.
#[test]
fn a_rejected_word_does_not_erase_later_metric_family() {
    let bits = vector_word();
    let good = weak_errors(&bits, 0);
    let earlier = weak_errors(&bits, MAX_HARD_ERRORS + 1);
    let channel = Channel::new();
    let (word, errors) = channel
        .decode_counted(&earlier, &|| false)
        .expect("fixed weak 37-bit errors must be corrected");
    assert_eq!(word.as_slice(), bits.as_slice());
    assert_eq!(errors, MAX_HARD_ERRORS + 1);
    assert!(!accepted(&word, errors));
    assert!(accepted(&word, 0));
    let never = || false;
    let alone = complete(decode_families(
        vec![earlier],
        &channel,
        &mut CpuBudget::new(&never),
    ))
    .unwrap();
    assert_eq!(alone, None);
    let result = complete(decode_families(
        vec![earlier, good],
        &channel,
        &mut CpuBudget::new(&never),
    ))
    .unwrap();
    assert_eq!(result.unwrap().as_slice(), bits.as_slice());
}
// Proves: FR-003, FR-004, CL-007-03 (#56). ft8b accepts a word with up to 36 hard
// disagreements; the former 24-disagreement gate refused 25..36.
#[test]
fn a_word_with_up_to_36_hard_disagreements_is_accepted() {
    let bits = vector_word();
    let channel = Channel::new();
    let never = || false;
    for errors in [25, 30, MAX_HARD_ERRORS] {
        let llr = weak_errors(&bits, errors);
        let word = complete(decode_families(
            vec![llr],
            &channel,
            &mut CpuBudget::new(&never),
        ))
        .unwrap();
        assert_eq!(
            word.map(|w| w.to_vec()),
            Some(bits.clone()),
            "{errors} weak hard errors"
        );
    }
    assert!(!accepted(&[0; 174], 0), "the all-zero codeword is refused");
}
