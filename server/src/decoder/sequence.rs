//! Bounded FT4 two-symbol observation and pair-chain log marginals.
use super::demodulation::tone_llrs;
use super::likelihood::logsum;
use super::search::CpuBudget;
use super::{DecodeError, Mode};
use rustfft::num_complex::Complex64;
use std::f64::consts::PI;

pub(super) struct PairBank {
    conjugate_templates: Vec<Vec<Complex64>>,
}
impl PairBank {
    pub fn new() -> Self {
        let frames = 2 * Mode::Ft4.symbol_frames();
        let phases = (-1..=2)
            .map(|lag| super::waveform::pulse_phase(Mode::Ft4, lag, frames))
            .collect::<Vec<_>>();
        let conjugate_templates = (0..256)
            .map(|index| {
                let tones = [index / 64, index / 16 % 4, index / 4 % 4, index % 4];
                (0..frames)
                    .map(|k| {
                        let phase = phases
                            .iter()
                            .zip(tones)
                            .map(|(p, t)| t as f64 * p[k])
                            .sum::<f64>();
                        Complex64::from_polar(1., -phase)
                    })
                    .collect()
            })
            .collect();
        Self {
            conjugate_templates,
        }
    }

    /// `frame` is the complete current-pass residual support at the candidate start.
    pub async fn observe(
        &self,
        frame: &[f32],
        frequency: f64,
        variance: f64,
        budget: &mut CpuBudget<'_>,
    ) -> Result<[f32; 174], DecodeError> {
        let mode = Mode::Ft4;
        let n = mode.symbol_frames();
        if frame.len() != n * mode.symbol_count()
            || !variance.is_finite()
            || variance < 1e-20
            || !frequency.is_finite()
            || !(200. - 1e-7..=3500. + 1e-7).contains(&frequency)
        {
            return Err(DecodeError::InvalidSamples);
        }
        let groups = 52;
        let carrier = (0..2 * n)
            .map(|k| Complex64::from_polar(1., -2. * PI * frequency * k as f64 / 12000.))
            .collect::<Vec<_>>();
        let mut input = vec![Complex64::new(0., 0.); 2 * n];
        let mut factors = vec![[0.; 256]; groups];
        for (g, row) in factors.iter_mut().enumerate() {
            budget.checkpoint().await?;
            for (k, x) in input.iter_mut().enumerate() {
                *x = carrier[k] * frame[2 * g * n + k] as f64;
            }
            for (factor, template) in row.iter_mut().zip(&self.conjugate_templates) {
                let z = input
                    .iter()
                    .zip(template)
                    .fold(Complex64::new(0., 0.), |z, (&x, &h)| z + x * h);
                *factor = z.norm_sqr() / (2 * n) as f64 / variance;
            }
        }
        let mut allowed = vec![[true; 4]; mode.symbol_count()];
        for (s, t) in mode.sync() {
            allowed[s] = [false; 4];
            allowed[s][t as usize] = true;
        }
        for s in [0, 104] {
            allowed[s] = [true, false, false, false];
        }
        budget.checkpoint().await?;
        let marginals = pair_marginals(&mut factors, &allowed)?;
        budget.checkpoint().await?;
        let mut llr = [0.; 174];
        for (i, s) in mode.data_symbols().into_iter().enumerate() {
            tone_llrs(mode, &marginals[s], &mut llr[2 * i..2 * i + 2]);
        }
        if llr.iter().any(|x| !x.is_finite()) {
            return Err(DecodeError::InvalidSamples);
        }
        Ok(llr)
    }
}

fn center(row: &mut [f64]) -> Result<(), DecodeError> {
    let maximum = row.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    if !maximum.is_finite() {
        return Err(DecodeError::InvalidSamples);
    }
    for value in row {
        *value -= maximum;
        if value.is_nan() || *value == f64::INFINITY {
            return Err(DecodeError::InvalidSamples);
        }
    }
    Ok(())
}

/// Factors are centered in place, retaining only one bounded factor bank.
fn pair_marginals(
    factors: &mut [[f64; 256]],
    allowed: &[[bool; 4]],
) -> Result<Vec<[f64; 4]>, DecodeError> {
    let groups = factors.len();
    if !(1..=52).contains(&groups)
        || allowed.len() != 2 * groups + 1
        || allowed.last() != Some(&[true, false, false, false])
        || allowed.iter().any(|mask| !mask.iter().any(|&x| x))
    {
        return Err(DecodeError::InvalidSamples);
    }
    for row in factors.iter_mut() {
        if row.iter().any(|x| !x.is_finite()) {
            return Err(DecodeError::InvalidSamples);
        }
        center(row)?;
        if row.iter().any(|x| !x.is_finite()) {
            return Err(DecodeError::InvalidSamples);
        }
    }
    let mut alpha = vec![[f64::NEG_INFINITY; 16]; groups + 1];
    alpha[0][..4].fill(0.);
    for (g, factor) in factors.iter().enumerate() {
        for u in 0..4 {
            if !allowed[2 * g + 1][u] {
                continue;
            }
            for r in 0..4 {
                let terms = std::array::from_fn::<_, 16, _>(|previous| {
                    let t = previous % 4;
                    if allowed[2 * g][t] {
                        alpha[g][previous] + factor[previous * 16 + u * 4 + r]
                    } else {
                        f64::NEG_INFINITY
                    }
                });
                alpha[g + 1][u * 4 + r] = logsum(&terms);
            }
        }
        center(&mut alpha[g + 1])?;
    }
    let mut beta = vec![[f64::NEG_INFINITY; 16]; groups + 1];
    for u in 0..4 {
        beta[groups][u * 4] = 0.;
    }
    for (g, factor) in factors.iter().enumerate().rev() {
        for l in 0..4 {
            for t in 0..4 {
                if !allowed[2 * g][t] {
                    continue;
                }
                let terms = std::array::from_fn::<_, 16, _>(|next| {
                    let u = next / 4;
                    if allowed[2 * g + 1][u] {
                        factor[(l * 4 + t) * 16 + next] + beta[g + 1][next]
                    } else {
                        f64::NEG_INFINITY
                    }
                });
                beta[g][l * 4 + t] = logsum(&terms);
            }
        }
        center(&mut beta[g])?;
    }
    let mut marginals = vec![[f64::NEG_INFINITY; 4]; 2 * groups + 1];
    for (g, factor) in factors.iter().enumerate() {
        for side in 0..2 {
            for target in 0..4 {
                if !allowed[2 * g + side][target] {
                    continue;
                }
                let mut terms = [f64::NEG_INFINITY; 64];
                let mut count = 0;
                for l in 0..4 {
                    for t in 0..4 {
                        if !allowed[2 * g][t] {
                            continue;
                        }
                        for u in 0..4 {
                            if !allowed[2 * g + 1][u] {
                                continue;
                            }
                            for r in 0..4 {
                                if (if side == 0 { t } else { u }) == target {
                                    terms[count] = alpha[g][l * 4 + t]
                                        + factor[(l * 4 + t) * 16 + u * 4 + r]
                                        + beta[g + 1][u * 4 + r];
                                    count += 1;
                                }
                            }
                        }
                    }
                }
                marginals[2 * g + side][target] = logsum(&terms[..count]);
            }
            let row = &mut marginals[2 * g + side];
            let normal = logsum(row);
            if !normal.is_finite() {
                return Err(DecodeError::InvalidSamples);
            }
            for value in row {
                *value -= normal;
            }
        }
    }
    marginals[2 * groups] = [0., f64::NEG_INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY];
    Ok(marginals)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

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
}
