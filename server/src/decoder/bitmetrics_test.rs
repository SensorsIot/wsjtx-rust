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

// Proves: FR-003, FR-004, CL-007-03.
#[test]
fn a_failed_hard_gate_does_not_erase_later_metric_family() {
    let manifest: serde_json::Value = serde_json::from_str(include_str!(
        "../../../fixtures/decoder/independent-vectors/manifest.json"
    ))
    .unwrap();
    let bits = manifest["vectors"][0]["codeword174"]
        .as_str()
        .unwrap()
        .bytes()
        .map(|b| b - b'0')
        .collect::<Vec<_>>();
    let good = std::array::from_fn(|i| if bits[i] == 0 { 8f32 } else { -8f32 });
    let mut earlier = good;
    for x in &mut earlier[..25] {
        *x = -x.signum() * 0.001;
    }
    let channel = Channel::new();
    let word = channel
        .decode(&earlier, &|| false)
        .expect("fixed weak25-bit errors must be corrected");
    assert_eq!(word.as_slice(), bits.as_slice());
    assert!(!channel_gates(&word, &earlier));
    assert!(channel_gates(&word, &good));
    let never = || false;
    let result = complete(decode_families(
        vec![earlier, good],
        &channel,
        &mut CpuBudget::new(&never),
    ))
    .unwrap();
    assert_eq!(result.word.unwrap().as_slice(), bits.as_slice());
    assert_eq!(result.llr, good);
}
