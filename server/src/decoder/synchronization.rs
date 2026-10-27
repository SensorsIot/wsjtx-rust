use super::search::CpuBudget;
use super::{DecodeError, Mode, baseband::PassBand, physical_sync};
use rustfft::{
    FftPlanner, FftPlannerScalar,
    num_complex::{Complex32, Complex64},
};
use std::{cmp::Ordering, collections::BinaryHeap, f64::consts::PI};
#[derive(Clone, Copy, Debug)]
pub(super) struct Candidate {
    pub start: usize,
    pub frequency: f64,
    pub score: f64,
}
#[derive(Clone, Copy)]
struct Peak {
    score: f64,
    row: usize,
    frequency_index: usize,
}
impl PartialEq for Peak {
    fn eq(&self, other: &Self) -> bool {
        self.cmp(other) == Ordering::Equal
    }
}
impl Eq for Peak {}
impl PartialOrd for Peak {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}
impl Ord for Peak {
    fn cmp(&self, other: &Self) -> Ordering {
        self.score
            .total_cmp(&other.score)
            .then(other.frequency_index.cmp(&self.frequency_index))
            .then(other.row.cmp(&self.row))
    }
}
pub(super) struct Spectrum {
    values: Vec<Complex32>,
    width: usize,
    regular: usize,
    frequencies: Vec<f64>,
    hop: usize,
    mode: Mode,
    sync: Vec<(usize, u8)>,
}
impl Spectrum {
    fn coefficient(&self, row: usize, f: usize, t: usize) -> Complex64 {
        let col = if f == self.regular {
            self.regular + 15 + t
        } else {
            f + 2 * t
        };
        let z = self.values[row * self.width + col];
        Complex64::new(z.re as f64, z.im as f64)
    }
    fn power(&self, row: usize, f: usize, t: usize) -> f64 {
        self.coefficient(row, f, t).norm_sqr()
    }
    pub async fn new(
        samples: &[f32],
        mode: Mode,
        scalar: bool,
        budget: &mut CpuBudget<'_>,
    ) -> Result<Self, DecodeError> {
        let n = mode.symbol_frames();
        let hop = n / 4;
        if samples.len() < n || samples.len() > 360000 {
            return Err(DecodeError::DecodeLimit);
        }
        let rows = (samples.len() - n) / hop + 1;
        let regular = ((3500. - 200.) / (mode.spacing() / 2.)).floor() as usize + 1;
        let width = regular + 15 + mode.tone_count();
        let mut frequencies = (0..regular)
            .map(|j| 200. + j as f64 * mode.spacing() / 2.)
            .collect::<Vec<_>>();
        let endpoint = (frequencies.last().copied().unwrap() - 3500.).abs() > 1e-7;
        if endpoint {
            frequencies.push(3500.);
        }
        let mut values = vec![Complex32::new(0., 0.); rows * width];
        let fft = if scalar {
            FftPlannerScalar::new().plan_fft_forward(n)
        } else {
            FftPlanner::new().plan_fft_forward(n)
        };
        let mut buffer = vec![Complex32::new(0., 0.); n];
        let mut scratch = vec![Complex32::new(0., 0.); fft.get_inplace_scratch_len()];
        let oscillators = (0..2)
            .map(|half| {
                (0..n)
                    .map(|j| {
                        Complex32::from_polar(
                            1.,
                            (-2. * PI * (200. + half as f64 * mode.spacing() / 2.) * j as f64
                                / 12000.) as f32,
                        )
                    })
                    .collect::<Vec<_>>()
            })
            .collect::<Vec<_>>();
        for row in 0..rows {
            budget.checkpoint().await?;
            for (half, oscillator) in oscillators.iter().enumerate() {
                for j in 0..n {
                    buffer[j] = oscillator[j] * samples[row * hop + j];
                }
                fft.process_with_scratch(&mut buffer, &mut scratch);
                if buffer
                    .iter()
                    .any(|z| !z.re.is_finite() || !z.im.is_finite())
                {
                    return Err(DecodeError::InvalidSamples);
                }
                for j in (half..regular + 15).step_by(2) {
                    values[row * width + j] = buffer[j / 2];
                }
            }
            if endpoint {
                for tone in 0..mode.tone_count() {
                    let angle = -2. * PI * (3500. + tone as f64 * mode.spacing()) / 12000.;
                    let rotation = Complex64::from_polar(1., angle);
                    let mut oscillator = Complex64::new(1., 0.);
                    let mut z = Complex64::new(0., 0.);
                    for &x in &samples[row * hop..row * hop + n] {
                        z += oscillator * x as f64;
                        oscillator *= rotation;
                    }
                    values[row * width + regular + 15 + tone] =
                        Complex32::new(z.re as f32, z.im as f32);
                }
            }
        }
        budget.checkpoint().await?;
        let sync = mode.sync();
        Ok(Self {
            values,
            width,
            regular,
            frequencies,
            hop,
            mode,
            sync,
        })
    }
    pub async fn candidates(
        &self,
        length: usize,
        physical: &mut PassBand<'_>,
        budget: &mut CpuBudget<'_>,
    ) -> Result<Vec<Candidate>, DecodeError> {
        self.select_candidates(length, physical, false, 9, budget)
            .await
    }
    pub async fn deep_candidates(
        &self,
        length: usize,
        physical: &mut PassBand<'_>,
        minimum_hits: usize,
        budget: &mut CpuBudget<'_>,
    ) -> Result<Vec<Candidate>, DecodeError> {
        self.select_candidates(length, physical, true, minimum_hits, budget)
            .await
    }
    async fn select_candidates(
        &self,
        length: usize,
        physical: &mut PassBand<'_>,
        deep: bool,
        minimum_hits: usize,
        budget: &mut CpuBudget<'_>,
    ) -> Result<Vec<Candidate>, DecodeError> {
        let n = self.mode.symbol_frames();
        let frame = n * self.mode.symbol_count();
        if length < frame {
            return Ok(vec![]);
        }
        let starts = (length - frame) / self.hop + 1;
        let nf = self.frequencies.len();
        let q = self.mode.tone_count();
        let sync = &self.sync;
        let mut scores = vec![0f64; starts * nf];
        for r in 0..starts {
            budget.checkpoint().await?;
            for f in 0..nf {
                let (mut yes, mut other) = (0., 0.);
                if deep {
                    scores[r * nf + f] = self.deep_costas_ratio(r, f);
                    continue;
                }
                for &(j, t) in sync {
                    let row = r + 4 * j;
                    yes += self.power(row, f, t as usize);
                    for tone in 0..q {
                        if tone != t as usize {
                            other += self.power(row, f, tone);
                        }
                    }
                }
                scores[r * nf + f] = if other > 0. {
                    (q - 1) as f64 * yes / other
                } else if yes > 0. {
                    f64::INFINITY
                } else {
                    0.
                };
            }
        }
        if deep {
            if !normalize_deep_scores(&mut scores, starts, nf) {
                return Ok(vec![]);
            }
        }
        let threshold = if deep { 1.3 } else { 2.7 };
        let mut heap = BinaryHeap::new();
        for r in 0..starts {
            budget.checkpoint().await?;
            for f in 0..nf {
                let score = scores[r * nf + f];
                if score < threshold {
                    continue;
                }
                let mut maximum = true;
                for rr in r.saturating_sub(1)..=(r + 1).min(starts - 1) {
                    for ff in f.saturating_sub(1)..=(f + 1).min(nf - 1) {
                        if (rr, ff) != (r, f)
                            && (scores[rr * nf + ff] > score
                                || scores[rr * nf + ff] == score && (ff, rr) < (f, r))
                        {
                            maximum = false;
                        }
                    }
                }
                if maximum {
                    heap.push(Peak {
                        score,
                        row: r,
                        frequency_index: f,
                    });
                }
            }
        }
        let mut blocked = vec![false; starts * nf];
        let mut out = vec![];
        while let Some(peak) = heap.pop() {
            budget.checkpoint().await?;
            let (r, f) = (peak.row, peak.frequency_index);
            if blocked[r * nf + f] {
                continue;
            }
            for rr in r.saturating_sub(2)..=(r + 2).min(starts - 1) {
                for ff in f.saturating_sub(1)..=(f + 1).min(nf - 1) {
                    blocked[rr * nf + ff] = true;
                }
            }
            let raw = Candidate {
                start: r * self.hop,
                frequency: self.frequencies[f],
                score: peak.score,
            };
            let qualified = if deep {
                physical_sync::qualify_at_least(physical, raw, minimum_hits, budget).await?
            } else {
                physical_sync::qualify(physical, raw, budget).await?
            };
            let Some(candidate) = qualified else {
                continue;
            };
            if out.len() == 256 {
                return Err(DecodeError::SearchLimited);
            }
            out.push(candidate);
        }
        Ok(out)
    }
    fn deep_costas_ratio(&self, start_row: usize, frequency: usize) -> f64 {
        let ratio = |skip| {
            let (mut yes, mut other) = (0., 0.);
            for &(symbol, expected) in self.sync.iter().skip(skip) {
                let row = start_row + 4 * symbol;
                yes += self.power(row, frequency, expected as usize);
                for tone in 0..7 {
                    if tone != expected as usize {
                        other += self.power(row, frequency, tone);
                    }
                }
            }
            if other > 0. {
                6. * yes / other
            } else if yes > 0. {
                f64::INFINITY
            } else {
                0.
            }
        };
        ratio(0).max(ratio(7))
    }
    /// PSD*v conversion uses nonoverlapping symbol periodograms inside this frame support.
    pub fn noise_variance(
        &self,
        start: usize,
        frames: usize,
        frequency: f64,
        accepted: &[f64],
    ) -> Option<f64> {
        let n = self.mode.symbol_frames();
        let spacing = self.mode.spacing();
        let band = |f: f64| {
            ((f - frequency) >= -2. * spacing
                && (f - frequency) <= (self.mode.tone_count() + 1) as f64 * spacing)
                || accepted.iter().any(|&base| {
                    (f - base) >= -2. * spacing
                        && (f - base) <= (self.mode.tone_count() + 1) as f64 * spacing
                })
        };
        let mut powers = vec![];
        let mut windows = 0;
        let mut row = start.div_ceil(self.hop);
        let end = start.checked_add(frames)?;
        while row * self.hop + n <= end && row * self.width < self.values.len() {
            windows += 1;
            for j in (0..self.regular).step_by(2) {
                let f = 200. + j as f64 * spacing / 2.;
                if !band(f) {
                    powers.push(self.coefficient(row, j, 0).norm_sqr());
                }
            }
            row += 4;
        }
        if windows < 8 || powers.len() < 128 {
            return None;
        }
        let middle = powers.len() / 2;
        let even = middle * 2 == powers.len();
        let (lower, value, _) = powers.select_nth_unstable_by(middle, f64::total_cmp);
        let median = if even {
            (*value + lower.iter().copied().fold(0., f64::max)) / 2.
        } else {
            *value
        };
        let variance = median / (n as f64 * 2f64.ln());
        variance.is_finite().then_some(variance)
    }
}

fn normalize_deep_scores(scores: &mut [f64], starts: usize, frequencies: usize) -> bool {
    let mut maxima = (0..frequencies)
        .map(|f| {
            (0..starts)
                .map(|r| scores[r * frequencies + f])
                .fold(0f64, f64::max)
        })
        .collect::<Vec<_>>();
    maxima.sort_by(f64::total_cmp);
    let index = ((0.4 * frequencies as f64 + 0.5).floor() as usize).clamp(1, frequencies) - 1;
    let baseline = maxima[index];
    if !baseline.is_finite() || baseline <= 0. {
        return false;
    }
    for score in scores {
        *score /= baseline;
    }
    true
}

#[cfg(test)]
mod deep_tests {
    use super::*;
    // Proves: CL-007-03. An independent power table distinguishes ABC, BC and eighth-tone noise.
    #[test]
    fn seven_tone_costas_uses_the_better_abc_or_bc_score() {
        let mut spectrum = Spectrum {
            values: vec![Complex32::new(1., 0.); 317 * 16],
            width: 16,
            regular: 1,
            frequencies: vec![200.],
            hop: 480,
            mode: Mode::Ft8,
            sync: Mode::Ft8.sync(),
        };
        for (index, &(symbol, tone)) in spectrum.sync.iter().enumerate() {
            let row = 4 * symbol;
            // A: target power 1; B/C: target power 4. Six competitor powers are all 1.
            spectrum.values[row * 16 + 2 * tone as usize] =
                Complex32::new(if index < 7 { 1. } else { 2. }, 0.);
            // The eighth tone must never enter this source's seven-tone statistic.
            spectrum.values[row * 16 + 14] = Complex32::new(1000., 0.);
        }
        // ABC = 6*(7+14*4)/(21*6) = 3; BC = 6*(14*4)/(14*6) = 4.
        assert!((spectrum.deep_costas_ratio(0, 0) - 4.).abs() < 1e-12);
    }
    // Proves: CL-007-03. Two starts per frequency prevent a global percentile implementation passing.
    #[test]
    fn normalization_uses_frequency_maxima_and_source_percentile() {
        let mut scores = [1., 2., 3., 4., 5., 10., 8., 6., 4., 2.];
        assert!(normalize_deep_scores(&mut scores, 2, 5));
        // Frequency maxima [10,8,6,4,5], sorted [4,5,6,8,10]; nint(.4*5)=2 => 5.
        assert_eq!(scores, [0.2, 0.4, 0.6, 0.8, 1., 2., 1.6, 1.2, 0.8, 0.4]);
        assert!(!normalize_deep_scores(&mut [0.; 10], 2, 5));
        assert!(!normalize_deep_scores(&mut [f64::INFINITY; 10], 2, 5));
    }
}
