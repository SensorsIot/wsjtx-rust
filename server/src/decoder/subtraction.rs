// Portions adapted from WSJT-X subtractft8.f90 and subtractft4.f90.
// Copyright the WSJT-X contributors. GPL-3.0-only; see the project LICENSE.
// Reference: WSJTX/wsjtx 0f7d5928449ec747c3d1f6da1306f8c94404c3a9.
// Centered linear convolution and available-weight edges follow the product model.
use super::{DecodeError, Mode, baseband::fft_plan, search::CpuBudget};
use rustfft::{Fft, num_complex::Complex64};
use std::{f64::consts::PI, sync::Arc};

pub(super) struct Subtractor {
    mode: Mode,
    frame: usize,
    forward: Arc<dyn Fft<f64>>,
    inverse: Arc<dyn Fft<f64>>,
    kernel: Vec<Complex64>,
    correction: Vec<f64>,
    buffer: Vec<Complex64>,
    scratch: Vec<Complex64>,
}
impl Subtractor {
    pub fn new(mode: Mode, scalar: bool) -> Result<Self, DecodeError> {
        let radius = if mode == Mode::Ft8 {
            2000usize
        } else {
            700usize
        };
        let frame = mode.symbol_count() * mode.symbol_frames();
        let size = (frame + 2 * radius).next_power_of_two();
        let forward = fft_plan(size, false, scalar);
        let inverse = fft_plan(size, true, scalar);
        let scratch_len = forward
            .get_inplace_scratch_len()
            .max(inverse.get_inplace_scratch_len());
        if (2 * size + scratch_len) * 16 > 16 * 1024 * 1024 {
            return Err(DecodeError::InvalidSamples);
        }
        let weights = (-(radius as isize)..=radius as isize)
            .map(|j| (PI * j as f64 / (2 * radius) as f64).cos().powi(2))
            .collect::<Vec<_>>();
        let total = weights.iter().sum::<f64>();
        let mut kernel = vec![Complex64::new(0., 0.); size];
        for (j, weight) in weights.iter().enumerate() {
            let lag = j as isize - radius as isize;
            kernel[lag.rem_euclid(size as isize) as usize].re = weight / total;
        }
        let mut correction = Vec::with_capacity(radius + 1);
        let mut available = weights[..=radius].iter().sum::<f64>();
        for a in 0..=radius {
            if a > 0 {
                available += weights[radius + a];
            }
            correction.push(total / available);
        }
        let mut scratch = vec![Complex64::new(0., 0.); scratch_len];
        forward.process_with_scratch(&mut kernel, &mut scratch);
        for z in &mut kernel {
            *z /= size as f64;
        }
        Ok(Self {
            mode,
            frame,
            forward,
            inverse,
            kernel,
            correction,
            buffer: vec![Complex64::new(0., 0.); size],
            scratch,
        })
    }
    pub async fn subtract(
        &mut self,
        samples: &mut [f32],
        start: usize,
        wave: &[[f32; 2]],
        budget: &mut CpuBudget<'_>,
    ) -> Result<(), DecodeError> {
        if wave.len() != self.frame
            || start
                .checked_add(self.frame)
                .is_none_or(|end| end > samples.len())
        {
            return Err(DecodeError::InvalidSamples);
        }
        budget.checkpoint().await?;
        self.buffer.fill(Complex64::new(0., 0.));
        for (k, q) in wave.iter().enumerate() {
            self.buffer[k] =
                Complex64::new(q[0] as f64, -(q[1] as f64)) * samples[start + k] as f64;
        }
        self.forward
            .process_with_scratch(&mut self.buffer, &mut self.scratch);
        budget.checkpoint().await?;
        for (z, &filter) in self.buffer.iter_mut().zip(&self.kernel) {
            *z *= filter;
        }
        self.inverse
            .process_with_scratch(&mut self.buffer, &mut self.scratch);
        budget.checkpoint().await?;
        if self.mode == Mode::Ft8 {
            for (a, &correction) in self.correction.iter().enumerate() {
                self.buffer[a] *= correction;
                self.buffer[self.frame - 1 - a] *= correction;
            }
        }
        for (k, q) in wave.iter().enumerate() {
            let value = 2. * (q[0] as f64 * self.buffer[k].re - q[1] as f64 * self.buffer[k].im);
            samples[start + k] -= value as f32;
        }
        budget.checkpoint().await?;
        Ok(())
    }
}

#[cfg(test)]
#[path = "subtraction_test.rs"]
mod tests;
