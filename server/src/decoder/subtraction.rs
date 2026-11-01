// Portions adapted from WSJT-X subtractft8.f90 and subtractft4.f90.
// Copyright the WSJT-X contributors. GPL-3.0-only; see the project LICENSE.
// Reference: WSJTX/wsjtx 0f7d5928449ec747c3d1f6da1306f8c94404c3a9.
// Centered linear convolution and available-weight edges follow the product model.
use super::{DecodeError, Mode, search::CpuBudget};
use rustfft::num_complex::Complex64;
use std::f64::consts::PI;

pub(super) struct Subtractor {
    mode: Mode,
    frame: usize,
    radius: usize,
    /// e^{-i pi m / radius} for one period (2*radius) of the raised-cosine kernel.
    phasors: Vec<Complex64>,
    total: f64,
    correction: Vec<f64>,
    /// Prefix sums of the demodulated envelope u, u*e^{-i pi m/R} and u*e^{+i pi m/R}.
    prefix: [Vec<Complex64>; 3],
}
impl Subtractor {
    #[cfg(all(test, not(debug_assertions)))]
    pub(super) fn capacity_ledger(&self) -> serde_json::Value {
        serde_json::json!({"phasor_complex64_capacity":self.phasors.capacity(),
            "correction_f64_capacity":self.correction.capacity(),
            "prefix_complex64_capacity":self.prefix.iter().map(Vec::capacity).sum::<usize>(),
            "frame":self.frame})
    }
    pub fn new(mode: Mode, _scalar: bool) -> Result<Self, DecodeError> {
        let radius = if mode == Mode::Ft8 {
            2000usize
        } else {
            700usize
        };
        let frame = mode.symbol_count() * mode.symbol_frames();
        if 3 * (frame + 1) * 16 > 16 * 1024 * 1024 {
            return Err(DecodeError::InvalidSamples);
        }
        let weights = (-(radius as isize)..=radius as isize)
            .map(|j| (PI * j as f64 / (2 * radius) as f64).cos().powi(2))
            .collect::<Vec<_>>();
        let total = weights.iter().sum::<f64>();
        let phasors = (0..2 * radius)
            .map(|m| Complex64::from_polar(1., -PI * m as f64 / radius as f64))
            .collect();
        let mut correction = Vec::with_capacity(radius + 1);
        let mut available = weights[..=radius].iter().sum::<f64>();
        for a in 0..=radius {
            if a > 0 {
                available += weights[radius + a];
            }
            correction.push(total / available);
        }
        let prefix = std::array::from_fn(|_| vec![Complex64::new(0., 0.); frame + 1]);
        Ok(Self {
            mode,
            frame,
            radius,
            phasors,
            total,
            correction,
            prefix,
        })
    }
    /// Centered linear convolution of the demodulated envelope with the raised-cosine
    /// kernel cos^2(pi j/2R) = (1 + cos(pi j/R))/2, |j| <= R, as three exact window sums
    /// (constant and two cosine-modulated prefix sums); support outside the frame is zero.
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
        let period = 2 * self.radius;
        let [plain, lower, upper] = &mut self.prefix;
        let zero = Complex64::new(0., 0.);
        let (mut p, mut l, mut u) = (zero, zero, zero);
        for (k, q) in wave.iter().enumerate() {
            let value = Complex64::new(q[0] as f64, -(q[1] as f64)) * samples[start + k] as f64;
            let phasor = self.phasors[k % period];
            p += value;
            l += value * phasor;
            u += value * phasor.conj();
            plain[k + 1] = p;
            lower[k + 1] = l;
            upper[k + 1] = u;
        }
        #[cfg(test)]
        super::resource_observer::hit(super::resource_observer::Phase::SubtractionForward);
        budget.checkpoint().await?;
        let r = self.radius;
        let scale = 1. / (2. * self.total);
        for (k, q) in wave.iter().enumerate() {
            let (lo, hi) = (k.saturating_sub(r), (k + r + 1).min(self.frame));
            let constant = plain[hi] - plain[lo];
            // sum_m e^{+i pi (k-m)/R} u[m] and sum_m e^{-i pi (k-m)/R} u[m].
            let rotation = self.phasors[k % period];
            let forward = (lower[hi] - lower[lo]) * rotation.conj();
            let backward = (upper[hi] - upper[lo]) * rotation;
            let mut envelope = (constant + (forward + backward) * 0.5) * scale;
            if self.mode == Mode::Ft8 {
                let edge = k.min(self.frame - 1 - k);
                if edge <= r {
                    envelope *= self.correction[edge];
                }
            }
            let value = 2. * (q[0] as f64 * envelope.re - q[1] as f64 * envelope.im);
            samples[start + k] -= value as f32;
        }
        #[cfg(test)]
        super::resource_observer::hit(super::resource_observer::Phase::SubtractionCommit);
        budget.checkpoint().await?;
        Ok(())
    }
}

#[cfg(test)]
#[path = "subtraction_test.rs"]
mod tests;
