#![forbid(unsafe_code)]
use serde_json::Value;
use wstx_rust::decoder::DecodeError;
#[path = "../src/decoder/likelihood.rs"]
mod likelihood;
#[test]
fn independent_hundred_digit_mixture_oracles() {
    let fixture: Value =
        serde_json::from_str(include_str!("../../fixtures/decoder/likelihood-cases.json")).unwrap();
    let cases = fixture["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 8);
    for c in cases {
        let q = c["q"].as_u64().unwrap() as usize;
        let mut energies = [0.; 8];
        for (i, e) in c["E"].as_array().unwrap().iter().enumerate() {
            energies[i] = e.as_f64().unwrap();
        }
        let context = likelihood::LikelihoodContext {
            variance: c["v"].as_f64().unwrap(),
            signal: c["S"].as_f64().unwrap(),
            peer: c["peer"].as_bool().unwrap().then(|| likelihood::PeerNoise {
                energy: c["I"].as_f64().unwrap(),
                offset: c["d"].as_i64().unwrap() as i32,
            }),
        };
        let scores = likelihood::scores(&[energies], q, context).unwrap()[0];
        let gray: &[usize] = if q == 4 {
            &[0, 1, 3, 2]
        } else {
            &[0, 1, 3, 2, 5, 6, 4, 7]
        };
        let width = if q == 4 { 2 } else { 3 };
        for bit in 0..width {
            let zero = gray
                .iter()
                .enumerate()
                .filter(|(v, _)| (v >> (width - bit - 1)) & 1 == 0)
                .map(|(_, t)| scores[*t])
                .collect::<Vec<_>>();
            let one = gray
                .iter()
                .enumerate()
                .filter(|(v, _)| (v >> (width - bit - 1)) & 1 != 0)
                .map(|(_, t)| scores[*t])
                .collect::<Vec<_>>();
            let actual = (likelihood::logsum(&zero) - likelihood::logsum(&one)).clamp(-12., 12.);
            let expected = c["expected_llr"][bit].as_f64().unwrap();
            assert!(
                (actual - expected).abs() < 1e-10,
                "{} bit{bit}: {actual} != {expected}",
                c["id"]
            );
        }
    }
}
#[test]
fn undefined_likelihood_inputs_are_rejected() {
    let context = likelihood::LikelihoodContext {
        variance: 1.,
        signal: 1.,
        peer: None,
    };
    for x in [f64::NAN, f64::INFINITY, -1.] {
        let mut e = [0.; 8];
        e[0] = x;
        assert_eq!(
            likelihood::scores(&[e], 4, context).unwrap_err(),
            DecodeError::InvalidSamples
        );
    }
    assert_eq!(
        likelihood::scores(&[], 4, context).unwrap_err(),
        DecodeError::InvalidSamples
    );
}
