// Adapted from WSJT-X getcandidates4, ft4_baseline, baseline, nuttal_window and pctile.
// Copyright the WSJT-X contributors. GPL-3.0-only; see the project LICENSE.
// Reference: WSJTX/wsjtx 0f7d5928449ec747c3d1f6da1306f8c94404c3a9.
use super::{DecodeError, baseband::fft_plan, search::CpuBudget};
use rustfft::num_complex::Complex64;
use std::f64::consts::PI;
const N: usize = 2304;
const DF: f64 = 12000. / N as f64;
const IA: usize = 38;
const IB: usize = 678;
pub(super) fn window(j: usize, n: usize) -> f64 {
    let a = 2. * PI * j as f64 / n as f64;
    0.3635819 - 0.4891775 * a.cos() + 0.1365995 * (2. * a).cos() - 0.0106411 * (3. * a).cos()
}
fn cutoff(values: &mut [f64]) -> Option<f64> {
    if values.is_empty() || values.iter().any(|v| !v.is_finite()) {
        return None;
    }
    values.sort_by(f64::total_cmp);
    let index = ((0.1 * values.len() as f64 + 0.5).floor() as usize).clamp(1, values.len()) - 1;
    Some(values[index])
}
fn endpoint_contrast(ratio: &[f64], endpoint: f64) -> f64 {
    let u = (endpoint + 31.25) / DF;
    let j = u.floor() as usize;
    let a = u - j as f64;
    if a == 0. {
        ratio[j]
    } else {
        ratio[j] + a * (ratio[j + 1] - ratio[j])
    }
}
fn baseline(power: &[f64]) -> Option<Vec<f64>> {
    fitted_baseline(power, IA, IB)
}
/// The lower-envelope quartic (+0.65 dB) of ft4_baseline and FT8's baseline over bins
/// `ia..=ib`, as linear power; bins outside the fitted band stay 1.
// Scaled abscissa preserves the same quartic OLS space, with a finite rank-five solve.
pub(super) fn fitted_baseline(power: &[f64], ia: usize, ib: usize) -> Option<Vec<f64>> {
    if power.len() <= ib || power.iter().any(|p| !p.is_finite() || *p < 0.) {
        return None;
    }
    let minimum = power[ia..=ib]
        .iter()
        .copied()
        .filter(|p| *p > 0.)
        .min_by(f64::total_cmp)?;
    let db = power
        .iter()
        .map(|p| {
            if *p > 0. {
                10. * p.log10()
            } else {
                10. * minimum.log10() - 120.
            }
        })
        .collect::<Vec<_>>();
    let width = (ib - ia + 1) / 10;
    let x = |i: usize| (i as f64 - (ia + ib) as f64 / 2.) / ((ib - ia) as f64 / 2.);
    let mut a = [[0.; 6]; 5];
    let mut count = 0;
    for segment in 0..10 {
        let begin = ia + segment * width;
        let mut ordered = db[begin..begin + width].to_vec();
        let cutoff = cutoff(&mut ordered)?;
        for (i, &y) in db.iter().enumerate().skip(begin).take(width) {
            if y > cutoff {
                continue;
            }
            count += 1;
            if count > 1000 {
                return None;
            }
            let t = x(i);
            let mut powers = [1.; 9];
            for j in 1..9 {
                powers[j] = powers[j - 1] * t;
            }
            for r in 0..5 {
                for c in 0..5 {
                    a[r][c] += powers[r + c];
                }
                a[r][5] += y * powers[r];
            }
        }
    }
    if count < 5 {
        return None;
    }
    for col in 0..5 {
        let pivot = (col..5).max_by(|&i, &j| a[i][col].abs().total_cmp(&a[j][col].abs()))?;
        if !a[pivot][col].is_finite() || a[pivot][col].abs() < 1e-12 {
            return None;
        }
        a.swap(col, pivot);
        let d = a[col][col];
        for value in &mut a[col][col..] {
            *value /= d;
        }
        let pivot_row = a[col];
        for (r, row) in a.iter_mut().enumerate() {
            if r == col {
                continue;
            }
            let m = row[col];
            for (value, pivot) in row[col..].iter_mut().zip(&pivot_row[col..]) {
                *value -= m * pivot;
            }
        }
    }
    // The source contract defines this polynomial only on the fitted radio band.
    let mut out = vec![1.; power.len()];
    for (i, value) in out.iter_mut().enumerate().take(ib + 1).skip(ia) {
        let t = x(i);
        let y = (0..5).rev().fold(0., |y, j| y * t + a[j][5]);
        *value = 10f64.powf((y + 0.65) / 10.);
        if !value.is_finite() || *value <= 0. {
            return None;
        }
    }
    Some(out)
}

/// The pass's smoothed average spectrum over its baseline (getcandidates4 savsm/sbase);
/// empty when no baseline exists.
pub(super) struct Contrast(Vec<f64>);
impl Contrast {
    fn new(power: &[f64]) -> Self {
        let Some(base) = baseline(power) else {
            return Self(vec![]);
        };
        let mut ratio = vec![0.; power.len()];
        for i in IA..=IB {
            ratio[i] = power[i - 7..=i + 7].iter().sum::<f64>() / 15. / base[i];
        }
        Self(ratio)
    }
    pub(super) fn candidates(&self) -> Vec<f64> {
        if self.0.is_empty() {
            return vec![];
        }
        peaks(&self.0).into_iter().map(|p| p.0).collect()
    }
    /// ft4_decode's SNR: the candidate peak contrast at the decoded lowest tone,
    /// 10*log10(peak-1)-14.8 dB, within -21..60 and rounded to whole dB.
    pub(super) fn snr_db(&self, frequency: f64) -> Option<f64> {
        let ratio = &self.0;
        if ratio.is_empty() {
            return None;
        }
        let nominal = ((frequency + 31.25) / DF).round() as usize;
        let i = (nominal.saturating_sub(1)..=nominal + 1)
            .filter(|i| (IA + 1..IB).contains(i))
            .max_by(|&a, &b| ratio[a].total_cmp(&ratio[b]).then(b.cmp(&a)))?;
        let (l, c, r) = (ratio[i - 1], ratio[i], ratio[i + 1]);
        let peak = if c >= l && c >= r {
            let d = l - 2. * c + r;
            let delta = if d == 0. { 0. } else { 0.5 * (l - r) / d };
            c - 0.25 * (l - r) * delta
        } else {
            c
        };
        let snr = peak - 1.;
        let db = if snr > 0. {
            10. * snr.log10() - 14.8
        } else {
            -21.
        };
        db.is_finite().then(|| db.clamp(-21., 60.).round())
    }
}
fn peaks(ratio: &[f64]) -> Vec<(f64, f64)> {
    let mut out = vec![];
    for i in IA + 1..IB {
        let (l, c, r) = (ratio[i - 1], ratio[i], ratio[i + 1]);
        if c < 1.18 || c < l || c < r {
            continue;
        }
        let d = l - 2. * c + r;
        let delta = if d == 0. { 0. } else { 0.5 * (l - r) / d };
        let carrier = (i as f64 + delta) * DF - 31.25;
        let contrast = c - 0.25 * (l - r) * delta;
        if (200. ..=3500.).contains(&carrier) && contrast.is_finite() {
            out.push((carrier, contrast));
        }
    }
    for endpoint in [200., 3500.] {
        let contrast = endpoint_contrast(ratio, endpoint);
        if contrast >= 1.18 {
            out.push((endpoint, contrast));
        }
    }
    out.sort_by(|a, b| b.1.total_cmp(&a.1).then(a.0.total_cmp(&b.0)));
    out
}
async fn spectrum(
    samples: &[f32],
    scalar: bool,
    budget: &mut CpuBudget<'_>,
) -> Result<Vec<f64>, DecodeError> {
    if samples.len() < N {
        return Ok(vec![]);
    }
    let fft = fft_plan(N, false, scalar);
    let mut scratch = vec![Complex64::new(0., 0.); fft.get_inplace_scratch_len()];
    let mut buffer = vec![Complex64::new(0., 0.); N];
    let taper = (0..N).map(|j| window(j, N) / 300.).collect::<Vec<_>>();
    let mut average = vec![0.; N / 2 + 1];
    let mut count = 0;
    for begin in (0..=samples.len() - N).step_by(576) {
        budget.checkpoint().await?;
        for j in 0..N {
            buffer[j] = Complex64::new(samples[begin + j] as f64 * taper[j], 0.);
        }
        fft.process_with_scratch(&mut buffer, &mut scratch);
        for (p, z) in average.iter_mut().zip(&buffer) {
            *p += z.norm_sqr();
        }
        count += 1;
    }
    for p in &mut average {
        *p /= count as f64;
    }
    budget.checkpoint().await?;
    Ok(average)
}

pub(super) async fn contrast(
    samples: &[f32],
    scalar: bool,
    budget: &mut CpuBudget<'_>,
) -> Result<Contrast, DecodeError> {
    Ok(Contrast::new(&spectrum(samples, scalar, budget).await?))
}
#[cfg(test)]
#[path = "coarse_ft4_test.rs"]
mod tests;
