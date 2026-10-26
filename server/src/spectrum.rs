use rustfft::{Fft, FftPlanner, FftPlannerScalar, num_complex::Complex};
use std::sync::Arc;

pub const SIZE: usize = 2048;
pub const HOP: u64 = 256;
pub const RATE: u64 = 12000;

/// Worker-owned FFT storage. Samples are copied before windowing; source blocks stay immutable.
pub struct Spectrum {
    plan: Arc<dyn Fft<f32>>,
    window: Vec<f32>,
    buffer: Vec<Complex<f32>>,
    scratch: Vec<Complex<f32>>,
}
impl Spectrum {
    pub fn new(scalar: bool) -> Self {
        Self::with_size(scalar, SIZE)
    }
    pub fn detailed(scalar: bool) -> Self {
        Self::with_size(scalar, 4096)
    }
    fn with_size(scalar: bool, size: usize) -> Self {
        let plan = if scalar {
            FftPlannerScalar::<f32>::new().plan_fft_forward(size)
        } else {
            FftPlanner::<f32>::new().plan_fft_forward(size)
        };
        let scratch = vec![Complex::default(); plan.get_inplace_scratch_len()];
        Self {
            plan,
            window: (0..size)
                .map(|n| (1.0 - (std::f32::consts::TAU * n as f32 / size as f32).cos()) * 0.5)
                .collect(),
            buffer: vec![Complex::default(); size],
            scratch,
        }
    }
    pub fn amplitudes(&mut self, samples: &[f32]) -> Result<[f32; 128], &'static str> {
        let native = self.native_amplitudes(samples)?;
        Ok(std::array::from_fn(|group| {
            native[group * 4..group * 4 + 4]
                .iter()
                .copied()
                .fold(0.0, f32::max)
        }))
    }
    pub fn native_amplitudes(&mut self, samples: &[f32]) -> Result<Vec<f32>, &'static str> {
        if samples.len() > self.window.len() || samples.iter().any(|v| !v.is_finite()) {
            return Err("invalid_recording");
        }
        for (n, value) in self.buffer.iter_mut().enumerate() {
            *value = Complex::new(samples.get(n).copied().unwrap_or(0.0) * self.window[n], 0.0);
        }
        self.plan
            .process_with_scratch(&mut self.buffer, &mut self.scratch);
        let sum: f32 = self.window.iter().sum();
        Ok((0..self.window.len() / 4)
            .map(|k| self.buffer[k].norm() * if k == 0 { 1.0 } else { 2.0 } / sum)
            .collect())
    }
}
pub fn quantize(amplitude: f32) -> u8 {
    ((20.0 * amplitude.max(0.000001).log10()).clamp(-120.0, 0.0) + 120.5).floor() as u8
}
