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
    /// Ring of the prefix sums of the demodulated envelope u, u*e^{-i pi m/R} and
    /// u*e^{+i pi m/R}, indexed by prefix position modulo its power-of-two length.
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
        // A window sum spans at most 2R+2 prefix entries.
        let ring = (2 * radius + 2).next_power_of_two();
        let prefix = std::array::from_fn(|_| vec![Complex64::new(0., 0.); ring]);
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
    pub(super) fn mode(&self) -> Mode {
        self.mode
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
        #[cfg(test)]
        super::resource_observer::hit(super::resource_observer::Phase::SubtractionForward);
        // Cancellation is checked before the sweep, so a cancelled subtraction leaves the
        // residual unchanged.
        budget.checkpoint().await?;
        let period = 2 * self.radius;
        let mask = self.prefix[0].len() - 1;
        let [plain, lower, upper] = &mut self.prefix;
        let zero = Complex64::new(0., 0.);
        let (mut p, mut l, mut u) = (zero, zero, zero);
        (plain[0], lower[0], upper[0]) = (zero, zero, zero);
        // One sweep: the prefix sums run R+1 samples ahead of the output and live in a ring
        // of at least 2R+2 entries, so every window sum reads the same exact prefix values
        // as with full-length prefix arrays, while staying in cache. Each input sample is
        // read before the output overwrites it.
        let r = self.radius;
        let scale = 1. / (2. * self.total);
        let mut filled = 1;
        let mut ahead = 0;
        let mut index = 0;
        for (k, q) in wave.iter().enumerate() {
            let (lo, hi) = (k.saturating_sub(r), (k + r + 1).min(self.frame));
            while filled <= hi {
                let m = filled - 1;
                let w = wave[m];
                let value = Complex64::new(w[0] as f64, -(w[1] as f64)) * samples[start + m] as f64;
                let phasor = self.phasors[ahead];
                ahead += 1;
                if ahead == period {
                    ahead = 0;
                }
                p += value;
                l += value * phasor;
                u += value * phasor.conj();
                (
                    plain[filled & mask],
                    lower[filled & mask],
                    upper[filled & mask],
                ) = (p, l, u);
                filled += 1;
            }
            let (lo, hi) = (lo & mask, hi & mask);
            let constant = plain[hi] - plain[lo];
            // sum_m e^{+i pi (k-m)/R} u[m] and sum_m e^{-i pi (k-m)/R} u[m].
            let rotation = self.phasors[index];
            index += 1;
            if index == period {
                index = 0;
            }
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
