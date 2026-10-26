use super::*;
use serde_json::Value;

// Proves: FR-003, FR-004, CL-007-03.
#[test]
fn pair_chain_matches_independent_complete_enumeration() {
    let inputs: Value = serde_json::from_str(include_str!(
        "../../../fixtures/decoder/pair-chain/inputs.json"
    ))
    .unwrap();
    let expected: Value = serde_json::from_str(include_str!(
        "../../../fixtures/decoder/pair-chain/expected.json"
    ))
    .unwrap();
    let cases = inputs["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 8);
    let mut paths = 0;
    for case in cases {
        let truth = expected["cases"]
            .as_array()
            .unwrap()
            .iter()
            .find(|x| x["id"] == case["id"])
            .unwrap();
        paths += truth["enumerated_paths"].as_u64().unwrap();
        let mut factors = case["factors"]
            .as_array()
            .unwrap()
            .iter()
            .map(|row| {
                row.as_array()
                    .unwrap()
                    .iter()
                    .map(|x| x.as_f64().unwrap())
                    .collect::<Vec<_>>()
                    .try_into()
                    .unwrap()
            })
            .collect::<Vec<[f64; 256]>>();
        let allowed = case["allowed"]
            .as_array()
            .unwrap()
            .iter()
            .map(|row| {
                row.as_array()
                    .unwrap()
                    .iter()
                    .map(|x| x.as_bool().unwrap())
                    .collect::<Vec<_>>()
                    .try_into()
                    .unwrap()
            })
            .collect::<Vec<[bool; 4]>>();
        let actual = pair_marginals(&mut factors, &allowed).unwrap();
        let rows = truth["log_marginals"].as_array().unwrap();
        assert_eq!(actual.len(), rows.len());
        for (row, expected) in actual.iter().zip(rows) {
            for (&value, truth) in row.iter().zip(expected.as_array().unwrap()) {
                if truth.is_null() {
                    assert_eq!(value, f64::NEG_INFINITY);
                } else {
                    let reference = truth.as_str().unwrap().parse::<f64>().unwrap();
                    assert!(
                        (value - reference).abs() <= 1e-9,
                        "{}: {value} vs {reference}",
                        case["id"]
                    );
                }
            }
            assert!(logsum(row).abs() <= 1e-10);
        }
    }
    assert_eq!(paths, 12848);
}

// Proves: FR-003, FR-004, CL-007-03.
#[test]
fn invalid_pair_domains_are_rejected() {
    let mask = [true, false, false, false];
    assert!(pair_marginals(&mut [], &[]).is_err());
    assert!(pair_marginals(&mut [[0.; 256]; 53], &[mask; 107]).is_err());
    assert!(pair_marginals(&mut [[0.; 256]; 1], &[mask; 2]).is_err());
    assert!(pair_marginals(&mut [[0.; 256]; 1], &[[true; 4]; 3]).is_err());
    assert!(pair_marginals(&mut [[0.; 256]; 1], &[mask, [false; 4], mask]).is_err());
    for value in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        let mut factors = [[0.; 256]; 1];
        factors[0][8] = value;
        assert!(pair_marginals(&mut factors, &[mask; 3]).is_err());
    }
    let mut overflowing = [[f64::MAX; 256]; 1];
    overflowing[0][0] = -f64::MAX;
    assert!(pair_marginals(&mut overflowing, &[mask; 3]).is_err());
}

// Proves: FR-003, FR-004, CL-007-03.
#[test]
fn pair_templates_keep_reconstruction_phase_up_to_independent_gain() {
    let bank = PairBank::new();
    let n = Mode::Ft4.symbol_frames();
    assert_eq!(bank.conjugate_templates.len(), 256);
    assert_eq!(
        bank.conjugate_templates
            .iter()
            .map(|t| t.len() * std::mem::size_of::<Complex64>())
            .sum::<usize>(),
        4_718_592
    );
    for tones in [
        [0, 0, 0, 0],
        [3, 3, 3, 3],
        [0, 1, 2, 3],
        [3, 2, 1, 0],
        [3, 0, 3, 0],
        [0, 3, 0, 3],
        [1, 0, 0, 2],
        [2, 3, 3, 1],
    ] {
        let mut full = vec![0u8; 105];
        full[3..7].copy_from_slice(&tones);
        let wave = super::super::quadratures(Mode::Ft4, &full, 0.).unwrap();
        let index = tones.iter().fold(0usize, |i, &t| 4 * i + t as usize);
        let template = &bank.conjugate_templates[index];
        let origin =
            Complex64::new(wave[4 * n][0] as f64, wave[4 * n][1] as f64) / template[0].conj();
        for (sample, h) in wave[4 * n..6 * n].iter().zip(template) {
            let actual = Complex64::new(sample[0] as f64, sample[1] as f64);
            assert!((actual - origin * h.conj()).norm() <= 3e-7, "{tones:?}");
        }
    }
}
