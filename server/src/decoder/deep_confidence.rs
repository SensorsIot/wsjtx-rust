// Adapted from WSJT-X get_spectrum_baseline.f90, baseline.f90 and ft8b.f90.
// Copyright the WSJT-X contributors. GPL-3.0-only; see COPYING.
// Source: WSJTX/wsjtx 0f7d5928449ec747c3d1f6da1306f8c94404c3a9.
use super::{DecodeError, baseband::fft_plan, coarse_ft4, search::CpuBudget};
use rustfft::num_complex::Complex64;
const N: usize = 3840;
const DF: f64 = 12000. / N as f64;

/// Private source-compatibility confidence; never exposed as calibrated signal SNR.
pub(super) struct Confidence {
    baseline: Option<Vec<f64>>,
}
impl Confidence {
    pub async fn new(
        samples: &[f32],
        scalar: bool,
        budget: &mut CpuBudget<'_>,
    ) -> Result<Self, DecodeError> {
        let fft = fft_plan(N, false, scalar);
        let mut scratch = vec![Complex64::new(0., 0.); fft.get_inplace_scratch_len()];
        let mut buffer = vec![Complex64::new(0., 0.); N];
        let mut taper = (0..N)
            .map(|j| coarse_ft4::nuttall(j, N))
            .collect::<Vec<_>>();
        let scale = (N as f64 / 300.) / taper.iter().sum::<f64>();
        for value in &mut taper {
            *value *= scale;
        }
        let mut power = vec![0.; N / 2 + 1];
        let mut count = 0;
        for start in (0..=samples.len() - N).step_by(1920) {
            budget.checkpoint().await?;
            for j in 0..N {
                buffer[j] = Complex64::new(samples[start + j] as f64 * taper[j], 0.);
            }
            fft.process_with_scratch(&mut buffer, &mut scratch);
            for (value, z) in power.iter_mut().zip(&buffer) {
                *value += z.norm_sqr();
            }
            count += 1;
        }
        for value in &mut power {
            *value *= 92. / count as f64;
        }
        let baseline =
            coarse_ft4::baseline_for_range(&power, (200. / DF) as usize, (3500. / DF) as usize);
        Ok(Self { baseline })
    }
    fn score(&self, frequency: f64, unscaled_power: f64) -> Option<f64> {
        let baseline = self.baseline.as_ref()?;
        let bin = (frequency / DF).round() as usize;
        let xbase = baseline[bin] * 1e-4;
        let q = unscaled_power / (3e6 * xbase) - 1.;
        if !q.is_finite() {
            return None;
        }
        Some(if q > 0.1 { 10. * q.log10() - 27. } else { -57. })
    }
    pub fn accepts(&self, rows: &[Vec<Complex64>], tones: &[u8], frequency: f64) -> bool {
        let power = rows
            .iter()
            .zip(tones)
            .map(|(row, &tone)| row[tone as usize].norm_sqr() * 1e6)
            .sum();
        self.score(frequency, power)
            .is_some_and(|value| value >= -25.)
    }
    /// Safe early refusal: no recovered word can exceed the per-symbol maximum power.
    pub fn possible(&self, rows: &[Vec<Complex64>], frequency: f64) -> bool {
        let upper = rows
            .iter()
            .map(|row| row.iter().map(|z| z.norm_sqr()).fold(0., f64::max) * 1e6)
            .sum();
        self.score(frequency, upper)
            .is_some_and(|value| value >= -25.)
    }
}

#[cfg(test)]
#[path = "deep_confidence_test.rs"]
mod tests;
