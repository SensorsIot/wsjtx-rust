// Portions adapted from WSJT-X ft8b.f90 and get_ft4_bitmetrics.f90.
// Copyright the WSJT-X contributors. GPL-3.0-only; see the project LICENSE.
// Reference: WSJTX/wsjtx 0f7d5928449ec747c3d1f6da1306f8c94404c3a9.
use super::{
    APriori, Channel, ChannelWord, DecodeError, Mode, apriori, baseband::PassBand,
    search::CpuBudget, synchronization::Candidate,
};
use rustfft::num_complex::Complex64;

/// Acceptance of a channel word: never the all-zero codeword; FT8 (ft8b) at most 36 hard
/// disagreements (nharderrors); FT4 (ft4_decode) any count.
pub(super) const MAX_HARD_ERRORS: usize = 36;
pub(super) fn accepted(mode: Mode, word: &ChannelWord, hard_errors: usize) -> bool {
    word.contains(&1) && (mode == Mode::Ft4 || hard_errors <= MAX_HARD_ERRORS)
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
    let width = mode.bits_per_symbol();
    let gray = mode.gray_map();
    let mut scores = vec![0.; 1 << (width * symbols)];
    for (value, score) in scores.iter_mut().enumerate() {
        let mut sum = Complex64::new(0., 0.);
        for j in 0..symbols {
            let value = (value >> (width * (symbols - 1 - j))) & (mode.tone_count() - 1);
            sum += rows[first + j][gray[value]];
        }
        *score = sum.norm();
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
    let mut raw = vec![vec![0f64; 174]; 5];
    for symbols in 1..=3 {
        for half in 0..2 {
            for k in (0..29).step_by(symbols) {
                budget.checkpoint().await?;
                let first = if half == 0 { 7 + k } else { 43 + k };
                let scores = group_scores(rows, first, symbols, Mode::Ft8);
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
/// The word of one fine point and, for an a-priori word, its WSJT-X AP type (1..6).
pub(super) async fn observe(
    pass: &mut PassBand<'_>,
    c: Candidate,
    channel: &Channel,
    ap: &APriori,
    budget: &mut CpuBudget<'_>,
) -> Result<Option<(ChannelWord, Option<u8>)>, DecodeError> {
    let Some(rows) = pass.rows(c.start, c.frequency, budget).await? else {
        return Ok(None);
    };
    let mode = pass.plan.mode;
    if !physical_accepts(mode, &rows) {
        return Ok(None);
    }
    let families = match mode {
        Mode::Ft8 => ft8(&rows, budget).await?,
        Mode::Ft4 => ft4(&rows, budget).await?,
    };
    let assisted = apriori::hypotheses(mode, &families, ap, c.frequency);
    if let Some(word) = decode_families(mode, families, channel, budget).await? {
        return Ok(Some((word, None)));
    }
    Ok(decode_assisted_families(mode, assisted, channel, budget)
        .await?
        .map(|(word, kind)| (word, Some(kind))))
}
/// The a-priori passes (WstxStationDecode::APrioriHypotheses), tried in order only after
/// every unassisted family failed. A word needs at most 36 hard disagreements in both modes,
/// a decoded payload (WSJT-X drops an a-priori word that does not unpack and tries the next
/// pass) and, except for FT8's CQ type 1, WSJT-X's confidence (not marked '?').
async fn decode_assisted_families(
    mode: Mode,
    hypotheses: Vec<(u8, [f32; 174], [bool; 174])>,
    channel: &Channel,
    budget: &mut CpuBudget<'_>,
) -> Result<Option<(ChannelWord, u8)>, DecodeError> {
    for (kind, llr, fixed) in hypotheses {
        budget.checkpoint().await?;
        if let Some((word, errors)) = channel.decode_assisted(&llr, &fixed, &|| (budget.cancel)())
            && accepted(Mode::Ft8, &word, errors)
            && (mode == Mode::Ft8 && kind == 1 || apriori::confident(&word, &llr, errors))
            && channel
                .payload(&word, mode)
                .is_some_and(|p| super::unpack(&p).status == super::PayloadStatus::Decoded)
        {
            return Ok(Some((word, kind)));
        }
    }
    Ok(None)
}
/// The first family whose word passes the acceptance rule wins; a rejected word does not
/// stop later families.
async fn decode_families(
    mode: Mode,
    families: Vec<[f32; 174]>,
    channel: &Channel,
    budget: &mut CpuBudget<'_>,
) -> Result<Option<ChannelWord>, DecodeError> {
    for llr in families {
        budget.checkpoint().await?;
        if let Some((word, errors)) = channel.decode_counted(&llr, &|| (budget.cancel)())
            && accepted(mode, &word, errors)
        {
            return Ok(Some(word));
        }
    }
    budget.checkpoint().await?;
    Ok(None)
}

#[cfg(test)]
#[path = "bitmetrics_test.rs"]
mod tests;
