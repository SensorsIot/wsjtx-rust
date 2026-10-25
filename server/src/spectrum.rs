use rustfft::{Fft, FftPlanner, FftPlannerScalar, num_complex::Complex};
use std::sync::Arc;

pub const SIZE: usize = 2048;
pub const HOP: u64 = 256;
pub const RATE: u64 = 12000;

/// Worker-owned FFT storage. Samples are copied before windowing; source blocks stay immutable.
pub struct Spectrum {
    plan: Arc<dyn Fft<f32>>,
    window: [f32; SIZE],
    buffer: Vec<Complex<f32>>,
    scratch: Vec<Complex<f32>>,
}
impl Spectrum {
    pub fn new(scalar: bool) -> Self {
        let plan = if scalar {
            FftPlannerScalar::<f32>::new().plan_fft_forward(SIZE)
        } else {
            FftPlanner::<f32>::new().plan_fft_forward(SIZE)
        };
        let scratch = vec![Complex::default(); plan.get_inplace_scratch_len()];
        Self {
            plan,
            window: std::array::from_fn(|n| {
                (1.0 - (std::f32::consts::TAU * n as f32 / SIZE as f32).cos()) * 0.5
            }),
            buffer: vec![Complex::default(); SIZE],
            scratch,
        }
    }
    pub fn amplitudes(&mut self, samples: &[f32]) -> Result<[f32; 128], &'static str> {
        if samples.len() > SIZE || samples.iter().any(|v| !v.is_finite()) {
            return Err("invalid_recording");
        }
        for (n, value) in self.buffer.iter_mut().enumerate() {
            *value = Complex::new(samples.get(n).copied().unwrap_or(0.0) * self.window[n], 0.0);
        }
        self.plan
            .process_with_scratch(&mut self.buffer, &mut self.scratch);
        let sum: f32 = self.window.iter().sum();
        Ok(std::array::from_fn(|group| {
            (group * 4..group * 4 + 4)
                .map(|k| self.buffer[k].norm() * if k == 0 { 1.0 } else { 2.0 } / sum)
                .fold(0.0, f32::max)
        }))
    }
}
pub fn quantize(amplitude: f32) -> u8 {
    ((20.0 * amplitude.max(0.000001).log10()).clamp(-120.0, 0.0) + 120.5).floor() as u8
}
