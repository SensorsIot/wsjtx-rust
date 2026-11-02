// Adapted from WSJT-X ft8b.f90 (xsnr2), ft8_decode.f90, sync8.f90 and
// get_spectrum_baseline.f90. Copyright the WSJT-X contributors. GPL-3.0-only; see the
// project LICENSE. Reference: WSJT-X 3.3.0-beta5 source.
use super::coarse_ft4::{fitted_baseline, window};
use super::{DecodeError, baseband::fft_plan, search::CpuBudget};
use rustfft::{Fft, num_complex::Complex64};
use std::{collections::HashMap, f64::consts::PI, sync::Arc};
const N: usize = 3840;
const SYMBOL: usize = 1920;
const DF: f64 = 12000. / N as f64;
/// The fitted band of the decode search, 200..3500 Hz.
const IA: usize = 64;
const IB: usize = 1280;
/// get_spectrum_baseline's 92 half-overlapped transforms of a 15 s period.
const TRANSFORMS: usize = 92;
/// The period start precedes a DT=0 frame by 0.5 s.
const LEAD: i128 = 6000;
const PERIOD: i128 = 180000;
/// WSJT-X reports a frame's SNR from its first decoding, which sees only the first
/// 41*3456 frames of the period (nzhsym 41) followed by zeros.
const EARLY: isize = 41 * 3456;

/// Window-relative start of the period of a frame starting at window frame `start`: the
/// period grid of `period_start` nearest to a DT=0 start, or that DT=0 start when unknown.
pub(super) fn period_of(origin: u64, start: usize, period_start: Option<u64>) -> isize {
    let nominal = i128::from(origin) + start as i128 - LEAD;
    let period = period_start.map_or(nominal, |p| {
        let p = i128::from(p);
        p + (nominal - p + PERIOD / 2).div_euclid(PERIOD) * PERIOD
    });
    (period - i128::from(origin)) as isize
}
/// One pass's FT8 SNR state: the residual samples' Nuttall power rows by start frame.
pub(super) struct Ft8Snr {
    fft: Arc<dyn Fft<f64>>,
    taper: Vec<f64>,
    rows: HashMap<isize, Vec<f64>>,
}
impl Ft8Snr {
    pub(super) fn new(scalar: bool) -> Self {
        let sum = (0..N).map(|j| window(j, N)).sum::<f64>();
        Self {
            fft: fft_plan(N, false, scalar),
            taper: (0..N)
                .map(|j| window(j, N) * 2. * SYMBOL as f64 / 300. / sum)
                .collect(),
            rows: HashMap::new(),
        }
    }
    /// Power of the transform starting at `begin`, with samples outside the window or at
    /// or after `limit` taken as zero (as in ft8_decode's early period buffer).
    fn row(&mut self, samples: &[f32], begin: isize, limit: isize) -> Option<Vec<f64>> {
        let end = begin + N as isize;
        let cached = begin >= 0 && end <= limit && end as usize <= samples.len();
        if cached && let Some(row) = self.rows.get(&begin) {
            return Some(row.clone());
        }
        if end <= 0 || begin >= limit.min(samples.len() as isize) {
            return None;
        }
        let mut buffer = (0..N as isize)
            .map(|j| {
                let k = begin + j;
                let x = if k >= 0 && k < limit {
                    samples.get(k as usize).copied().unwrap_or(0.)
                } else {
                    0.
                };
                Complex64::new(x as f64 * self.taper[j as usize], 0.)
            })
            .collect::<Vec<_>>();
        self.fft.process(&mut buffer);
        let row = buffer[..=IB]
            .iter()
            .map(|z| z.norm_sqr())
            .collect::<Vec<_>>();
        if cached {
            self.rows.insert(begin, row.clone());
        }
        Some(row)
    }
    /// ft8b's xsnr2 from the early period buffer: the decoded tones' symbol power over the
    /// sync8 baseline at the lowest tone, 10*log10(xsig/xbase/3e6-1)-27 dB, floored at -25
    /// and rounded to whole dB.
    /// `period` is the window-relative start of the frame's period.
    pub(super) async fn snr_db(
        &mut self,
        samples: &[f32],
        period: isize,
        start: usize,
        frequency: f64,
        tones: &[u8],
        budget: &mut CpuBudget<'_>,
    ) -> Result<Option<f64>, DecodeError> {
        let bin = (frequency / DF).round() as usize;
        if !(IA..=IB).contains(&bin) {
            return Ok(None);
        }
        let mut power = vec![0.; IB + 1];
        for j in 0..TRANSFORMS as isize {
            budget.checkpoint().await?;
            if let Some(row) = self.row(samples, period + j * SYMBOL as isize, period + EARLY) {
                power.iter_mut().zip(&row).for_each(|(p, r)| *p += r);
            }
        }
        let Some(base) = fitted_baseline(&power, IA, IB) else {
            return Ok(None);
        };
        let xbase = base[bin] * 1e-4;
        let limit = period + EARLY;
        let mut xsig = 0.;
        for (k, &tone) in tones.iter().enumerate() {
            let step = Complex64::from_polar(
                1.,
                -2. * PI * (frequency + tone as f64 * 12000. / SYMBOL as f64) / 12000.,
            );
            let mut phasor = Complex64::new(1., 0.);
            let mut sum = Complex64::new(0., 0.);
            let first = (start + k * SYMBOL) as isize;
            for n in first..first + SYMBOL as isize {
                if n < limit
                    && let Some(&x) = samples.get(n as usize)
                {
                    sum += phasor * x as f64;
                }
                phasor *= step;
            }
            // The 32-point transform of ft8_downsample's 200 Hz baseband is 1/sqrt(60) of
            // the full-rate symbol transform.
            xsig += sum.norm_sqr() / 60.;
        }
        let arg = xsig / xbase / 3e6 - 1.;
        let db = 10. * (if arg > 0.1 { arg } else { 0.001 }).log10() - 27.;
        Ok(db.is_finite().then(|| db.clamp(-25., 60.).round()))
    }
}
#[cfg(test)]
#[path = "snr_test.rs"]
mod tests;
