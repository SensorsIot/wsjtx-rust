// Portions adapted from WSJT-X ft8b.f90 and get_ft4_bitmetrics.f90.
// Copyright the WSJT-X contributors. GPL-3.0-only; see the project LICENSE.
// Reference: WSJTX/wsjtx 0f7d5928449ec747c3d1f6da1306f8c94404c3a9.
use super::{
    Channel, ChannelWord, DecodeError, Mode, baseband::PassBand, search::CpuBudget,
    synchronization::Candidate,
};
use rustfft::num_complex::Complex64;

pub(super) struct Observation {
    pub llr: [f32; 174],
    pub word: Option<ChannelWord>,
}
pub(super) fn channel_gates(word: &ChannelWord, llr: &[f32; 174]) -> bool {
    llr.iter().map(|x| x.abs()).sum::<f32>() / 174. >= 1.
        && word
            .iter()
            .zip(llr)
            .filter(|(b, l)| **b != u8::from(**l < 0.))
            .count()
            <= 24
}

pub(super) fn physical_hits(mode: Mode, rows: &[Vec<Complex64>]) -> (usize, usize) {
    let gray = mode.gray_map();
    let (mut tones, mut bits) = (0, 0);
    for (s, expected) in mode.sync() {
        let index = if mode == Mode::Ft4 { s - 1 } else { s };
        let row = &rows[index];
        let mut best = 0;
        for t in 1..mode.tone_count() {
            if row[t].norm_sqr() > row[best].norm_sqr() {
                best = t;
            }
        }
        tones += usize::from(best == expected as usize);
        if mode == Mode::Ft4 {
            let expected_bits = gray
                .iter()
                .position(|&tone| tone == expected as usize)
                .unwrap();
            for bit in 0..2 {
                let mask = 1 << (1 - bit);
                let (mut zero, mut one) = (0f64, 0f64);
                for (v, &tone) in gray.iter().enumerate() {
                    if v & mask == 0 {
                        zero = zero.max(row[tone].norm());
                    } else {
                        one = one.max(row[tone].norm());
                    }
                }
                bits += usize::from(usize::from(one >= zero) == ((expected_bits >> (1 - bit)) & 1));
            }
        }
    }
    (tones, bits)
}
pub(super) fn physical_accepts(mode: Mode, rows: &[Vec<Complex64>]) -> bool {
    let (tones, bits) = physical_hits(mode, rows);
    match mode {
        Mode::Ft8 => tones >= 9,
        Mode::Ft4 => tones >= 8 && bits >= 20,
    }
}

fn group_scores(rows: &[Vec<Complex64>], first: usize, symbols: usize, mode: Mode) -> Vec<f64> {
    group_scores_with_power(rows, first, symbols, mode, false)
}
fn group_scores_with_power(
    rows: &[Vec<Complex64>],
    first: usize,
    symbols: usize,
    mode: Mode,
    power: bool,
) -> Vec<f64> {
    let width = mode.bits_per_symbol();
    let gray = mode.gray_map();
    let mut scores = vec![0.; 1 << (width * symbols)];
    for (value, score) in scores.iter_mut().enumerate() {
        let mut sum = Complex64::new(0., 0.);
        for j in 0..symbols {
            let value = (value >> (width * (symbols - 1 - j))) & (mode.tone_count() - 1);
            sum += rows[first + j][gray[value]];
        }
        *score = if power { sum.norm_sqr() } else { sum.norm() };
    }
    scores
}
fn raw_metric(scores: &[f64], mask: usize) -> (f64, f64) {
    let (mut zero, mut one) = (0f64, 0f64);
    for (value, &score) in scores.iter().enumerate() {
        if value & mask == 0 {
            zero = zero.max(score);
        } else {
            one = one.max(score);
        }
    }
    (one - zero, one.max(zero))
}
fn normalize(raw: &[f64]) -> Option<Vec<f64>> {
    let mean = raw.iter().sum::<f64>() / raw.len() as f64;
    let square = raw.iter().map(|x| x * x).sum::<f64>() / raw.len() as f64;
    let variance = square - mean * mean;
    let sigma = if variance > 0. {
        variance.sqrt()
    } else {
        square.sqrt()
    };
    if !sigma.is_finite() || sigma <= 0. {
        return None;
    }
    let normalized = raw.iter().map(|x| -2.83 * x / sigma).collect::<Vec<_>>();
    normalized
        .iter()
        .all(|x| x.is_finite())
        .then_some(normalized)
}
async fn ft8(
    rows: &[Vec<Complex64>],
    budget: &mut CpuBudget<'_>,
) -> Result<Vec<[f32; 174]>, DecodeError> {
    ft8_policy(rows, false, budget).await
}
async fn ft8_policy(
    rows: &[Vec<Complex64>],
    power: bool,
    budget: &mut CpuBudget<'_>,
) -> Result<Vec<[f32; 174]>, DecodeError> {
    let mut raw = vec![vec![0f64; 174]; 5];
    for symbols in 1..=3 {
        for half in 0..2 {
            for k in (0..29).step_by(symbols) {
                budget.checkpoint().await?;
                let first = if half == 0 { 7 + k } else { 43 + k };
                let scores = group_scores_with_power(rows, first, symbols, Mode::Ft8, power);
                for bit in 0..3 * symbols {
                    let index = half * 87 + 3 * k + bit;
                    if index >= 174 {
                        continue;
                    }
                    let (metric, maximum) = raw_metric(&scores, 1 << (3 * symbols - 1 - bit));
                    raw[symbols - 1][index] = metric;
                    if symbols == 1 {
                        raw[3][index] = if maximum > 0. { metric / maximum } else { 0. };
                    }
                }
            }
        }
    }
    for k in 0..174 {
        let mut strongest = raw[0][k];
        for row in raw.iter().take(3).skip(1) {
            if row[k].abs() > strongest.abs() {
                strongest = row[k];
            }
        }
        raw[4][k] = strongest;
    }
    Ok(raw
        .iter()
        .filter_map(|row| normalize(row))
        .map(|row| std::array::from_fn(|i| row[i] as f32))
        .collect())
}
async fn ft4(
    rows: &[Vec<Complex64>],
    budget: &mut CpuBudget<'_>,
) -> Result<Vec<[f32; 174]>, DecodeError> {
    let mut raw = vec![vec![0f64; 206]; 3];
    for (family, symbols) in [1usize, 2, 4].into_iter().enumerate() {
        for k in (0..=103 - symbols).step_by(symbols) {
            budget.checkpoint().await?;
            let scores = group_scores(rows, k, symbols, Mode::Ft4);
            for bit in 0..2 * symbols {
                raw[family][2 * k + bit] = raw_metric(&scores, 1 << (2 * symbols - 1 - bit)).0;
            }
        }
    }
    let (single, longer) = raw.split_at_mut(1);
    longer[0][204..206].copy_from_slice(&single[0][204..206]);
    longer[1][204..206].copy_from_slice(&single[0][204..206]);
    let (pair, quadruple) = longer.split_at_mut(1);
    quadruple[0][200..204].copy_from_slice(&pair[0][200..204]);
    Ok(raw
        .iter()
        .filter_map(|row| normalize(row))
        .map(|row| {
            std::array::from_fn(|k| {
                let index = if k < 58 {
                    8 + k
                } else if k < 116 {
                    74 + k - 58
                } else {
                    140 + k - 116
                };
                row[index] as f32
            })
        })
        .collect())
}
pub(super) async fn observe(
    pass: &mut PassBand<'_>,
    c: Candidate,
    channel: &Channel,
    budget: &mut CpuBudget<'_>,
) -> Result<Observation, DecodeError> {
    let last = [0f32; 174];
    let Some(rows) = pass.rows(c.start, c.frequency, budget).await? else {
        return Ok(Observation {
            llr: last,
            word: None,
        });
    };
    if !physical_accepts(pass.plan.mode, &rows) {
        return Ok(Observation {
            llr: last,
            word: None,
        });
    }
    let families = match pass.plan.mode {
        Mode::Ft8 => ft8(&rows, budget).await?,
        Mode::Ft4 => ft4(&rows, budget).await?,
    };
    decode_families(families, channel, budget).await
}
pub(super) fn deep_channel_gates(word: &ChannelWord, llr: &[f32; 174]) -> bool {
    llr.iter().map(|x| x.abs()).sum::<f32>() / 174. >= 1.
        && word
            .iter()
            .zip(llr)
            .filter(|(b, l)| **b != u8::from(**l < 0.))
            .count()
            <= 36
        && word.iter().any(|&b| b != 0)
}
pub(super) async fn observe_deep_ft8(
    pass: &mut PassBand<'_>,
    c: Candidate,
    channel: &Channel,
    deep: &super::deep_channel::DeepChannel,
    residual_pass: usize,
    confidence: &super::deep_confidence::Confidence,
    budget: &mut CpuBudget<'_>,
) -> Result<Observation, DecodeError> {
    let empty = || Observation {
        llr: [0.; 174],
        word: None,
    };
    let Some(rows) = pass.rows(c.start, c.frequency, budget).await? else {
        return Ok(empty());
    };
    let hits = physical_hits(Mode::Ft8, &rows).0;
    if hits < if residual_pass == 0 { 7 } else { 8 } {
        return Ok(empty());
    }
    if hits <= 10 && !confidence.possible(&rows, c.frequency) {
        return Ok(empty());
    }
    let mut last = [0.; 174];
    for llr in ft8_policy(&rows, residual_pass > 0, budget).await? {
        budget.checkpoint().await?;
        last = llr;
        if llr.iter().map(|x| x.abs()).sum::<f32>() / 174. < 1. {
            continue;
        }
        for word in deep.decode(channel, &llr, budget).await? {
            if !deep_channel_gates(&word, &llr) {
                continue;
            }
            let tones = channel.tones(&word, Mode::Ft8);
            if hits <= 10 && !confidence.accepts(&rows, &tones, c.frequency) {
                continue;
            }
            return Ok(Observation {
                llr,
                word: Some(word),
            });
        }
    }
    budget.checkpoint().await?;
    Ok(Observation {
        llr: last,
        word: None,
    })
}
async fn decode_families(
    families: Vec<[f32; 174]>,
    channel: &Channel,
    budget: &mut CpuBudget<'_>,
) -> Result<Observation, DecodeError> {
    let mut last = [0f32; 174];
    for llr in families {
        budget.checkpoint().await?;
        last = llr;
        if let Some(word) = channel.decode(&llr, &|| (budget.cancel)())
            && channel_gates(&word, &llr)
        {
            return Ok(Observation {
                llr,
                word: Some(word),
            });
        }
    }
    budget.checkpoint().await?;
    Ok(Observation {
        llr: last,
        word: None,
    })
}

#[cfg(test)]
#[path = "bitmetrics_test.rs"]
mod tests;

#[cfg(test)]
mod deep_metric_tests {
    use super::*;
    // Proves: CL-007-03. Square coherent hypotheses before class maxima/differences.
    #[test]
    fn pass_power_is_applied_before_max_log_difference() {
        let mut rows = vec![vec![Complex64::new(0., 0.); 8]; 2];
        // Gray values 0 and 4 belong to opposite high-bit classes.
        let gray = Mode::Ft8.gray_map();
        rows[0][gray[0]] = Complex64::new(3., 0.);
        rows[0][gray[4]] = Complex64::new(2., 0.);
        let magnitude = group_scores_with_power(&rows, 0, 1, Mode::Ft8, false);
        let power = group_scores_with_power(&rows, 0, 1, Mode::Ft8, true);
        assert_eq!(raw_metric(&magnitude, 4), (-1., 3.));
        assert_eq!(raw_metric(&power, 4), (-5., 9.));
        assert_ne!(raw_metric(&power, 4).0, raw_metric(&magnitude, 4).0.powi(2));
    }
    // Proves: CL-007-03. The optional policy's hard-error gate is bounded independently of FEC.
    #[test]
    fn deep_hard_error_and_mean_magnitude_boundaries() {
        let mut word = [0; 174];
        word[100] = 1;
        let mut llr = [1.; 174];
        llr[100] = -1.;
        for value in &mut llr[..36] {
            *value = -1.;
        }
        assert!(deep_channel_gates(&word, &llr));
        llr[36] = -1.;
        assert!(!deep_channel_gates(&word, &llr));
        let low = std::array::from_fn(|i| if word[i] == 0 { 0.999 } else { -0.999 });
        assert!(!deep_channel_gates(&word, &low));
        assert!(!deep_channel_gates(&[0; 174], &[1.; 174]));
    }
}
