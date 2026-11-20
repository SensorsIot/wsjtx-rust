use super::search::CpuBudget;
use super::{
    DECODE_BAND_HIGH_HZ, DECODE_BAND_LOW_HZ, DecodeError, Mode, baseband::PassBand, physical_sync,
};
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

/// Coarse Costas ratio admitting a raw FT8 peak (2.0).
const COSTAS_THRESHOLD: f64 = 2.0;
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
        threads: usize,
        budget: &mut CpuBudget<'_>,
    ) -> Result<Self, DecodeError> {
        let n = mode.symbol_frames();
        let hop = n / 4;
        if samples.len() < n || samples.len() > 360000 {
            return Err(DecodeError::DecodeLimit);
        }
        let rows = (samples.len() - n) / hop + 1;
        let regular = ((DECODE_BAND_HIGH_HZ - DECODE_BAND_LOW_HZ) / (mode.spacing() / 2.)).floor()
            as usize
            + 1;
        let width = regular + 15 + mode.tone_count();
        let mut frequencies = (0..regular)
            .map(|j| DECODE_BAND_LOW_HZ + j as f64 * mode.spacing() / 2.)
            .collect::<Vec<_>>();
        let endpoint = (frequencies.last().copied().unwrap() - DECODE_BAND_HIGH_HZ).abs() > 1e-7;
        if endpoint {
            frequencies.push(DECODE_BAND_HIGH_HZ);
        }
        let mut values = vec![Complex32::new(0., 0.); rows * width];
        let fft = if scalar {
            FftPlannerScalar::new().plan_fft_forward(n)
        } else {
            FftPlanner::new().plan_fft_forward(n)
        };
        let scratch_len = fft.get_inplace_scratch_len();
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
        // The rows are independent, so they are transformed in parallel, each into its own
        // row of the table and exactly as on one thread (CL-057-02).
        let slots = values
            .chunks_mut(width)
            .enumerate()
            .map(std::sync::Mutex::new)
            .collect::<Vec<_>>();
        let transformed = super::parallel::map(
            threads,
            &slots,
            budget,
            || {
                (
                    vec![Complex32::new(0., 0.); n],
                    vec![Complex32::new(0., 0.); scratch_len],
                )
            },
            |slot, (buffer, scratch), _| {
                let mut slot = slot.lock().unwrap();
                let (row, out) = &mut *slot;
                let row = *row;
                for (half, oscillator) in oscillators.iter().enumerate() {
                    for j in 0..n {
                        buffer[j] = oscillator[j] * samples[row * hop + j];
                    }
                    fft.process_with_scratch(buffer, scratch);
                    if buffer
                        .iter()
                        .any(|z| !z.re.is_finite() || !z.im.is_finite())
                    {
                        return Err(DecodeError::InvalidSamples);
                    }
                    for j in (half..regular + 15).step_by(2) {
                        out[j] = buffer[j / 2];
                    }
                }
                if endpoint {
                    for tone in 0..mode.tone_count() {
                        let angle = -2. * PI * (DECODE_BAND_HIGH_HZ + tone as f64 * mode.spacing())
                            / 12000.;
                        let rotation = Complex64::from_polar(1., angle);
                        let mut oscillator = Complex64::new(1., 0.);
                        let mut z = Complex64::new(0., 0.);
                        for &x in &samples[row * hop..row * hop + n] {
                            z += oscillator * x as f64;
                            oscillator *= rotation;
                        }
                        out[regular + 15 + tone] = Complex32::new(z.re as f32, z.im as f32);
                    }
                }
                Ok(())
            },
        )
        .await?;
        drop(slots);
        for row in transformed {
            budget.checkpoint().await?;
            row?;
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
        physical: &PassBand<'_>,
        threads: usize,
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
        // Each frequency's tone powers are computed once for all its rows; the sums below
        // add exactly the same values in the same order as one power call per term. The
        // frequencies are independent, so they are scored in parallel (CL-057-02).
        let rows = starts + 4 * (self.mode.symbol_count() - 1);
        let frequencies = (0..nf).collect::<Vec<_>>();
        let columns = super::parallel::map(
            threads,
            &frequencies,
            budget,
            || vec![0f64; rows * q],
            |&f, power, _| {
                for row in 0..rows {
                    for tone in 0..q {
                        power[row * q + tone] = self.power(row, f, tone);
                    }
                }
                (0..starts)
                    .map(|r| {
                        let (mut yes, mut other) = (0., 0.);
                        for &(j, t) in sync {
                            let cell = &power[(r + 4 * j) * q..(r + 4 * j + 1) * q];
                            yes += cell[t as usize];
                            for (tone, &p) in cell.iter().enumerate() {
                                if tone != t as usize {
                                    other += p;
                                }
                            }
                        }
                        if other > 0. {
                            (q - 1) as f64 * yes / other
                        } else if yes > 0. {
                            f64::INFINITY
                        } else {
                            0.
                        }
                    })
                    .collect::<Vec<_>>()
            },
        )
        .await?;
        let mut scores = vec![0f64; starts * nf];
        for (f, column) in columns.iter().enumerate() {
            for (r, &score) in column.iter().enumerate() {
                scores[r * nf + f] = score;
            }
        }
        let mut heap = BinaryHeap::new();
        for r in 0..starts {
            budget.checkpoint().await?;
            for f in 0..nf {
                let score = scores[r * nf + f];
                if score < COSTAS_THRESHOLD {
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
        // Blocking depends only on the peak order, never on qualification, so the peaks are
        // qualified in parallel and kept in that order (CL-057-02).
        let mut raws = vec![];
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
            raws.push(raw);
        }
        let qualified = super::parallel::map(
            threads,
            &raws,
            budget,
            || physical.fork(),
            |&raw, pass, budget| super::search::complete(physical_sync::qualify(pass, raw, budget)),
        )
        .await?;
        let mut out = vec![];
        for candidate in qualified {
            let Some(candidate) = candidate? else {
                continue;
            };
            if out.len() == 256 {
                return Err(DecodeError::SearchLimited);
            }
            out.push(candidate);
        }
        Ok(out)
    }
}
