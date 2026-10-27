// Portions adapted from WSJT-X ft8_downsample.f90 and ft4_downsample.f90.
// Copyright the WSJT-X contributors. GPL-3.0-only; see the project LICENSE.
// Reference: WSJTX/wsjtx 0f7d5928449ec747c3d1f6da1306f8c94404c3a9.
use super::{DecodeError, Mode, search::CpuBudget};
use rustfft::{Fft, FftPlanner, FftPlannerScalar, num_complex::Complex64};
use std::{f64::consts::PI, sync::Arc};

pub(super) fn fft_plan(size: usize, inverse: bool, scalar: bool) -> Arc<dyn Fft<f64>> {
    if scalar {
        let mut planner = FftPlannerScalar::new();
        if inverse {
            planner.plan_fft_inverse(size)
        } else {
            planner.plan_fft_forward(size)
        }
    } else {
        let mut planner = FftPlanner::new();
        if inverse {
            planner.plan_fft_inverse(size)
        } else {
            planner.plan_fft_forward(size)
        }
    }
}

pub(super) struct BandPlan {
    pub mode: Mode,
    long_len: usize,
    short_len: usize,
    forward: Arc<dyn Fft<f64>>,
    inverse: Arc<dyn Fft<f64>>,
    symbol: Arc<dyn Fft<f64>>,
    scratch_len: usize,
}
impl BandPlan {
    pub fn new(mode: Mode, frames: usize, scalar: bool) -> Result<Self, DecodeError> {
        if frames == 0 || frames > 360000 {
            return Err(DecodeError::InvalidSamples);
        }
        let (unit, window, down) = match mode {
            Mode::Ft8 => (192000usize, 180000usize, 60usize),
            Mode::Ft4 => (72576usize, 72576usize, 18usize),
        };
        let long_len = frames
            .div_ceil(window)
            .checked_mul(unit)
            .ok_or(DecodeError::InvalidSamples)?;
        let short_len = long_len / down;
        let forward = fft_plan(long_len, false, scalar);
        let inverse = fft_plan(short_len, true, scalar);
        let symbol = fft_plan(32, false, scalar);
        let scratch_len = forward
            .get_inplace_scratch_len()
            .max(inverse.get_inplace_scratch_len())
            .max(symbol.get_inplace_scratch_len());
        // Checked dimensions include the long input, scratch and two simultaneous bands.
        let bytes = (long_len + scratch_len + 2 * short_len)
            .checked_mul(16)
            .ok_or(DecodeError::InvalidSamples)?;
        if bytes > 32 * 1024 * 1024 {
            return Err(DecodeError::InvalidSamples);
        }
        Ok(Self {
            mode,
            long_len,
            short_len,
            forward,
            inverse,
            symbol,
            scratch_len,
        })
    }
    pub async fn current_pass<'a>(
        &'a self,
        samples: &[f32],
        budget: &mut CpuBudget<'_>,
    ) -> Result<PassBand<'a>, DecodeError> {
        budget.checkpoint().await?;
        let mut spectrum = vec![Complex64::new(0., 0.); self.long_len];
        for (z, &x) in spectrum.iter_mut().zip(samples) {
            z.re = x as f64;
        }
        let mut scratch = vec![Complex64::new(0., 0.); self.scratch_len];
        self.forward
            .process_with_scratch(&mut spectrum, &mut scratch);
        budget.checkpoint().await?;
        Ok(PassBand {
            plan: self,
            spectrum,
            scratch,
            frames: samples.len(),
        })
    }
}

pub(super) struct BandWindow {
    pub samples: Vec<Complex64>,
    pub center_hz: f64,
}
pub(super) struct PassBand<'a> {
    pub plan: &'a BandPlan,
    spectrum: Vec<Complex64>,
    scratch: Vec<Complex64>,
    pub frames: usize,
}
impl PassBand<'_> {
    pub async fn window(
        &mut self,
        carrier: f64,
        budget: &mut CpuBudget<'_>,
    ) -> Result<Option<BandWindow>, DecodeError> {
        budget.checkpoint().await?;
        let n = self.plan.long_len;
        let m = self.plan.short_len;
        let df = 12000. / n as f64;
        let center = (carrier / df).round() as isize;
        let mut out = vec![Complex64::new(0., 0.); m];
        match self.plan.mode {
            Mode::Ft8 => {
                let lo = ((carrier - 9.375) / df).round().max(1.) as usize;
                let hi = ((carrier + 53.125) / df).round().min((n / 2) as f64) as usize;
                let taper = (6.25 / df).round() as usize;
                let length = hi - lo + 1;
                for i in lo..=hi {
                    let j = i - lo;
                    let weight = if j <= taper {
                        0.5 * (1. + (PI * (taper - j) as f64 / taper as f64).cos())
                    } else if j >= length - 1 - taper {
                        0.5 * (1. + (PI * (j - (length - 1 - taper)) as f64 / taper as f64).cos())
                    } else {
                        1.
                    };
                    out[(i as isize - center).rem_euclid(m as isize) as usize] =
                        self.spectrum[i] * weight;
                }
            }
            Mode::Ft4 => {
                let baud = 12000. / 576.;
                let transition = (0.5 * baud / df).floor() as usize;
                let flat = (4. * baud / df).floor() as usize;
                let shift = (baud / df).floor() as usize;
                for (k, value) in out.iter_mut().enumerate() {
                    let offset = if k <= m / 2 {
                        k as isize
                    } else {
                        k as isize - m as isize
                    };
                    let bin = center + offset;
                    if !(0..=n as isize / 2).contains(&bin) {
                        continue;
                    }
                    let j = (k + shift) % m;
                    let weight = if j < transition {
                        0.5 * (1. + (PI * (transition - 1 - j) as f64 / transition as f64).cos())
                    } else if j < transition + flat {
                        1.
                    } else if j < 2 * transition + flat {
                        0.5 * (1. + (PI * (j - transition - flat) as f64 / transition as f64).cos())
                    } else {
                        0.
                    };
                    *value = self.spectrum[bin as usize] * (weight / m as f64);
                }
            }
        }
        self.plan
            .inverse
            .process_with_scratch(&mut out, &mut self.scratch);
        if self.plan.mode == Mode::Ft8 {
            let scale = 1. / ((n * m) as f64).sqrt();
            for z in &mut out {
                *z *= scale;
            }
        } else {
            let rms = (out.iter().map(Complex64::norm_sqr).sum::<f64>() / m as f64).sqrt();
            if !rms.is_finite() || rms <= 0. {
                return Ok(None);
            }
            for z in &mut out {
                *z /= rms;
            }
        }
        budget.checkpoint().await?;
        Ok(Some(BandWindow {
            samples: out,
            center_hz: center as f64 * df,
        }))
    }
    pub async fn rows(
        &mut self,
        start: usize,
        carrier: f64,
        budget: &mut CpuBudget<'_>,
    ) -> Result<Option<Vec<Vec<Complex64>>>, DecodeError> {
        let mode = self.plan.mode;
        let frame = mode.symbol_count() * mode.symbol_frames();
        if start.checked_add(frame).is_none_or(|end| end > self.frames) {
            return Ok(None);
        }
        let (begin, symbols, rate) = match mode {
            Mode::Ft8 => (admission_origin(mode, start, self.frames), 79, 200.),
            Mode::Ft4 => (
                admission_origin(mode, start, self.frames),
                103,
                12000. / 18.,
            ),
        };
        let Some(window) = self.window(carrier, budget).await? else {
            return Ok(None);
        };
        if begin
            .checked_add(symbols * 32)
            .is_none_or(|end| end > window.samples.len())
        {
            return Ok(None);
        }
        // These are original-source spans, not zero-padded transform support.
        let down = if mode == Mode::Ft8 { 60 } else { 18 };
        if (begin + symbols * 32) * down > self.frames {
            return Ok(None);
        }
        let delta = carrier - window.center_hz;
        let mut rows = Vec::with_capacity(symbols);
        for s in 0..symbols {
            budget.checkpoint().await?;
            let origin = begin + s * 32;
            let mut row = (0..32)
                .map(|j| {
                    window.samples[origin + j]
                        * Complex64::from_polar(1., -2. * PI * delta * (origin + j) as f64 / rate)
                })
                .collect::<Vec<_>>();
            self.plan
                .symbol
                .process_with_scratch(&mut row, &mut self.scratch);
            row.truncate(mode.tone_count());
            if mode == Mode::Ft8 {
                for z in &mut row {
                    *z /= 1000.;
                }
            }
            rows.push(row);
        }
        Ok(Some(rows))
    }
}

// Source-coordinate adapter only; the reported canonical origin remains unchanged.
fn admission_origin(mode: Mode, start: usize, frames: usize) -> usize {
    match mode {
        Mode::Ft8 => ((start + 30) / 60).min((frames - 151680) / 60),
        Mode::Ft4 => (start + 9) / 18 + 32,
    }
}

#[cfg(test)]
#[path = "baseband_test.rs"]
mod tests;
