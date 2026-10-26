use super::{Channel, Mode, Payload, quadratures, unpack};
use rustfft::{FftPlanner, FftPlannerScalar, num_complex::Complex32};
use serde::{Deserialize, Serialize};
use std::f64::consts::PI;
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Decode {
    #[serde(flatten)]
    pub payload: Payload,
    pub start_frame: u64,
    pub frequency_hz: f64,
    pub snr_db: Option<f64>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DecodeError {
    Cancelled,
    InvalidSamples,
    SearchLimited,
    DecodeLimit,
}
#[derive(Clone, Copy)]
struct Candidate {
    start: usize,
    frequency: f64,
    score: f64,
}
struct Spectrum {
    values: Vec<f32>,
    width: usize,
    regular: usize,
    frequencies: Vec<f64>,
    hop: usize,
    noise: Option<f64>,
}
impl Spectrum {
    fn at(&self, row: usize, f: usize, t: usize) -> f64 {
        let col = if f == self.regular {
            self.regular + 2 * 7 + 1 + t
        } else {
            f + 2 * t
        };
        self.values[row * self.width + col] as f64
    }
    fn candidates(
        &self,
        mode: Mode,
        len: usize,
        cancel: &impl Fn() -> bool,
    ) -> Result<Vec<Candidate>, DecodeError> {
        let frame = mode.symbol_count() * mode.symbol_frames();
        if len < frame {
            return Ok(vec![]);
        }
        let starts = (len - frame) / self.hop + 1;
        let nf = self.frequencies.len();
        let sync = mode.sync();
        let q = mode.tone_count();
        let mut scores = vec![0f32; starts * nf];
        for r in 0..starts {
            if cancel() {
                return Err(DecodeError::Cancelled);
            }
            for f in 0..nf {
                let (mut yes, mut other) = (0., 0.);
                for &(s, t) in &sync {
                    let row = r + 4 * s;
                    let p = self.at(row, f, t as usize);
                    yes += p;
                    for tone in 0..q {
                        if tone != t as usize {
                            other += self.at(row, f, tone);
                        }
                    }
                }
                scores[r * nf + f] = if other > 0. {
                    ((q - 1) as f64 * yes / other) as f32
                } else if yes > 0. {
                    f32::MAX
                } else {
                    0.
                };
            }
        }
        let mut out = vec![];
        for r in 0..starts {
            for f in 0..nf {
                let s = scores[r * nf + f];
                if s < 2.7 {
                    continue;
                }
                let mut maximum = true;
                for rr in r.saturating_sub(1)..=(r + 1).min(starts - 1) {
                    for ff in f.saturating_sub(1)..=(f + 1).min(nf - 1) {
                        if (rr, ff) != (r, f)
                            && (scores[rr * nf + ff] > s
                                || scores[rr * nf + ff] == s && (rr, ff) < (r, f))
                        {
                            maximum = false;
                        }
                    }
                }
                if maximum {
                    out.push(Candidate {
                        start: r * self.hop,
                        frequency: self.frequencies[f],
                        score: s as f64,
                    });
                }
            }
        }
        out.sort_by(|a, b| {
            b.score
                .total_cmp(&a.score)
                .then(a.frequency.total_cmp(&b.frequency))
                .then(a.start.cmp(&b.start))
        });
        let mut selected: Vec<Candidate> = vec![];
        for c in out {
            if selected.iter().all(|p| {
                p.start.abs_diff(c.start) > mode.symbol_frames() / 2
                    || (p.frequency - c.frequency).abs() > mode.spacing() / 2. + 1e-7
            }) {
                selected.push(c);
            }
        }
        if selected.len() > 256 {
            return Err(DecodeError::SearchLimited);
        }
        Ok(selected)
    }
}
/// A pure decoder instance has no source, job, profile, device or thread authority.
pub struct Decoder {
    channel: Channel,
    scalar: bool,
}
impl Default for Decoder {
    fn default() -> Self {
        Self::new()
    }
}
impl Decoder {
    pub fn new() -> Self {
        Self {
            channel: Channel::new(),
            scalar: false,
        }
    }
    pub fn with_scalar_transform() -> Self {
        Self {
            channel: Channel::new(),
            scalar: true,
        }
    }
    pub fn decode(
        &self,
        samples: &[f32],
        mode: Mode,
        cancel: &impl Fn() -> bool,
    ) -> Result<Vec<Decode>, DecodeError> {
        if samples.iter().any(|x| !x.is_finite()) {
            return Err(DecodeError::InvalidSamples);
        }
        if cancel() {
            return Err(DecodeError::Cancelled);
        }
        let mut results = vec![];
        for window_start in (0..samples.len()).step_by(180000) {
            let end = (window_start + 360000).min(samples.len());
            let input = &samples[window_start..end];
            if input.len() < mode.symbol_count() * mode.symbol_frames() {
                continue;
            }
            let mut residual = input.to_vec();
            let original_energy = input.iter().map(|&x| (x as f64).powi(2)).sum::<f64>();
            let mut subtractions = 0;
            for pass in 0..3 {
                if pass > 0
                    && residual.iter().map(|&x| (x as f64).powi(2)).sum::<f64>()
                        <= original_energy * f32::EPSILON as f64
                {
                    break;
                }
                let spectrum = make_spectrum(&residual, mode, self.scalar, cancel)?;
                let candidates = spectrum.candidates(mode, input.len(), cancel)?;
                let mut added = 0;
                for c in candidates {
                    if cancel() {
                        return Err(DecodeError::Cancelled);
                    }
                    let c = refine_sync(&residual, mode, c, cancel)?;
                    let llr = self.soft_bits(
                        &residual,
                        mode,
                        c,
                        spectrum.noise.unwrap_or(1e-20),
                        cancel,
                    )?;
                    let Some(word) = self.channel.decode(&llr, cancel) else {
                        if cancel() {
                            return Err(DecodeError::Cancelled);
                        }
                        continue;
                    };
                    let mean = llr.iter().map(|x| x.abs()).sum::<f32>() / 174.;
                    let disagreements = word
                        .iter()
                        .zip(llr)
                        .filter(|(b, l)| **b != u8::from(*l < 0.))
                        .count();
                    if mean < 1. || disagreements > 24 {
                        continue;
                    }
                    let Some(payload) = self.channel.payload(&word, mode) else {
                        continue;
                    };
                    let payload = unpack(&payload);
                    let absolute = window_start + c.start;
                    if results.iter().any(|r: &Decode| {
                        r.payload.payload77 == payload.payload77
                            && r.start_frame.abs_diff(absolute as u64)
                                <= (mode.symbol_frames() / 2) as u64
                    }) {
                        continue;
                    }
                    let tones = self.channel.tones(&word, mode);
                    let fitted = refine_known(&residual, mode, &tones, c, cancel)?;
                    let wave = quadratures(mode, &tones, fitted.frequency)
                        .ok_or(DecodeError::InvalidSamples)?;
                    let fit = fit_signal(&residual, fitted.start, &wave);
                    let symbol_fit = (0..mode.symbol_count())
                        .filter_map(|j| {
                            fit_signal(
                                &residual,
                                fitted.start + j * mode.symbol_frames(),
                                &wave[j * mode.symbol_frames()..(j + 1) * mode.symbol_frames()],
                            )
                            .map(|f| f.2)
                        })
                        .sum::<f64>();
                    if fit.is_none_or(|f| f.2 < 0.25 * symbol_fit) {
                        continue;
                    }
                    let snr = fit
                        .and_then(|(a, b, _)| {
                            spectrum.noise.filter(|&n| n > 1e-20).map(|n| {
                                10. * (((a * a + b * b) / 2.) / (n * 2500. / 6000.)).log10()
                            })
                        })
                        .filter(|x| x.is_finite())
                        .map(|x| x.clamp(-60., 60.));
                    results.push(Decode {
                        payload,
                        start_frame: (window_start + fitted.start) as u64,
                        frequency_hz: fitted.frequency,
                        snr_db: snr,
                    });
                    if results.len() > 2048 {
                        return Err(DecodeError::DecodeLimit);
                    }
                    added += 1;
                    if subtractions < 32 {
                        if let Some((a, b, _)) = fit {
                            for (x, q) in residual[fitted.start..].iter_mut().zip(&wave) {
                                *x -= (a * q[0] as f64 + b * q[1] as f64) as f32;
                            }
                            subtractions += 1;
                        }
                    }
                }
                if added == 0 || subtractions >= 32 {
                    break;
                }
            }
        }
        results.sort_by(|a, b| {
            a.start_frame
                .cmp(&b.start_frame)
                .then(a.frequency_hz.total_cmp(&b.frequency_hz))
        });
        Ok(results)
    }
    fn soft_bits(
        &self,
        samples: &[f32],
        mode: Mode,
        c: Candidate,
        noise: f64,
        cancel: &impl Fn() -> bool,
    ) -> Result<[f32; 174], DecodeError> {
        let n = mode.symbol_frames();
        let q = mode.tone_count();
        let mut tones = vec![0; mode.symbol_count()];
        let mut basis = vec![vec![[0f64; 2]; n]; q];
        for (t, row) in basis.iter_mut().enumerate() {
            let step = 2. * PI * (c.frequency + mode.spacing() * t as f64) / 12000.;
            let (mut co, mut si) = (1., 0.);
            let (dc, ds) = (step.cos(), step.sin());
            for x in row {
                *x = [co, si];
                (co, si) = (co * dc - si * ds, si * dc + co * ds);
            }
        }
        for (s, tone) in tones.iter_mut().enumerate() {
            if cancel() {
                return Err(DecodeError::Cancelled);
            }
            let mut best = 0.;
            for (t, b) in basis.iter().enumerate() {
                let mut z = [0., 0.];
                for (&x, v) in samples[c.start + s * n..c.start + (s + 1) * n]
                    .iter()
                    .zip(b)
                {
                    z[0] += x as f64 * v[0];
                    z[1] += x as f64 * v[1];
                }
                let e = z[0] * z[0] + z[1] * z[1];
                if e > best {
                    best = e;
                    *tone = t as u8;
                }
            }
        }
        for (s, t) in mode.sync() {
            tones[s] = t;
        }
        let phase = pulse_phases(mode);
        let width = if mode == Mode::Ft4 { 2 } else { 3 };
        let gray: &[usize] = if width == 2 {
            &[0, 1, 3, 2]
        } else {
            &[0, 1, 3, 2, 5, 6, 4, 7]
        };
        let mut llr = [0.; 174];
        for _ in 0..3 {
            let old = tones.clone();
            for (i, s) in mode.data_symbols().into_iter().enumerate() {
                if cancel() {
                    return Err(DecodeError::Cancelled);
                }
                let mut energy = vec![[0.; 2]; q];
                for k in 0..n {
                    let mut fixed = 2. * PI * c.frequency * k as f64 / 12000.;
                    for lag in -2isize..=2 {
                        let j = s as isize + lag;
                        if lag != 0 && j >= 0 && (j as usize) < old.len() {
                            fixed += old[j as usize] as f64 * phase[(lag + 2) as usize][k];
                        }
                    }
                    let x = samples[c.start + s * n + k] as f64;
                    for (tone, e) in energy.iter_mut().enumerate() {
                        let angle = fixed + tone as f64 * phase[2][k];
                        e[0] += x * angle.cos();
                        e[1] += x * angle.sin();
                    }
                }
                let powers = energy
                    .iter()
                    .map(|v| ((v[0] * v[0] + v[1] * v[1]) / n as f64 / noise.max(1e-20)))
                    .collect::<Vec<_>>();
                tones[s] = powers
                    .iter()
                    .enumerate()
                    .max_by(|a, b| a.1.total_cmp(b.1))
                    .unwrap()
                    .0 as u8;
                for bit in 0..width {
                    let mut a = vec![];
                    let mut b = vec![];
                    for (value, &tone) in gray.iter().enumerate() {
                        if (value >> (width - bit - 1)) & 1 == 0 {
                            a.push(powers[tone]);
                        } else {
                            b.push(powers[tone]);
                        }
                    }
                    llr[i * width + bit] = (logsum(&a) - logsum(&b)).clamp(-12., 12.) as f32;
                }
            }
        }
        Ok(llr)
    }
}
fn logsum(a: &[f64]) -> f64 {
    let m = a.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    m + a.iter().map(|&x| (x - m).exp()).sum::<f64>().ln()
}
fn pulse_phases(mode: Mode) -> Vec<Vec<f64>> {
    let n = mode.symbol_frames();
    let bt = if mode == Mode::Ft8 { 2. } else { 1. };
    let k = PI * (2. / 2f64.ln()).sqrt();
    (-2isize..=2)
        .map(|lag| {
            let mut phase = 0.;
            (0..n)
                .map(|s| {
                    let t = (s as f64 + 0.5 - (lag as f64 + 0.5) * n as f64) / n as f64;
                    let p = (super::waveform::erf(k * bt * (t + 0.5))
                        - super::waveform::erf(k * bt * (t - 0.5)))
                        / 2.;
                    phase += 2. * PI * p / n as f64;
                    phase
                })
                .collect()
        })
        .collect()
}
fn make_spectrum(
    samples: &[f32],
    mode: Mode,
    scalar: bool,
    cancel: &impl Fn() -> bool,
) -> Result<Spectrum, DecodeError> {
    let n = mode.symbol_frames();
    let hop = n / 4;
    let rows = (samples.len() - n) / hop + 1;
    let regular = ((3500. - 200.) / (mode.spacing() / 2.)).floor() as usize + 1;
    let width = regular + 2 * 7 + 1 + mode.tone_count();
    let mut frequencies = (0..regular)
        .map(|j| 200. + j as f64 * mode.spacing() / 2.)
        .collect::<Vec<_>>();
    let endpoint = (frequencies.last().copied().unwrap() - 3500.).abs() > 1e-7;
    if endpoint {
        frequencies.push(3500.);
    }
    let mut values = vec![0.; rows * width];
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
                        (-2. * PI * (200. + half as f64 * mode.spacing() / 2.) * j as f64 / 12000.)
                            as f32,
                    )
                })
                .collect::<Vec<_>>()
        })
        .collect::<Vec<_>>();
    let mut noise = vec![];
    for row in 0..rows {
        if cancel() {
            return Err(DecodeError::Cancelled);
        }
        for half in 0..2 {
            for j in 0..n {
                buffer[j] = oscillators[half][j] * samples[row * hop + j];
            }
            fft.process_with_scratch(&mut buffer, &mut scratch);
            for j in (half..regular + 2 * 7 + 1).step_by(2) {
                let power = buffer[j / 2].norm_sqr();
                values[row * width + j] = power;
                if row % 4 == 0 && half == 0 {
                    noise.push(power);
                }
            }
        }
        if endpoint {
            for tone in 0..mode.tone_count() {
                let angle = 2. * PI * (3500. + tone as f64 * mode.spacing()) / 12000.;
                let (dc, ds) = (angle.cos(), angle.sin());
                let (mut co, mut si) = (1., 0.);
                let (mut re, mut im) = (0., 0.);
                for &x in &samples[row * hop..row * hop + n] {
                    re += x as f64 * co;
                    im += x as f64 * si;
                    (co, si) = (co * dc - si * ds, si * dc + co * ds);
                }
                values[row * width + regular + 2 * 7 + 1 + tone] = (re * re + im * im) as f32;
            }
        }
    }
    let noise = if noise.len() >= 128 && rows >= 29 {
        let m = noise.len() / 2;
        noise.select_nth_unstable_by(m, f32::total_cmp);
        Some(noise[m] as f64 / (n as f64 * 2f64.ln()))
    } else {
        None
    };
    Ok(Spectrum {
        values,
        width,
        regular,
        frequencies,
        hop,
        noise,
    })
}
fn sync_template(mode: Mode) -> (Vec<[f32; 2]>, Vec<(usize, usize)>) {
    let mut tones = vec![0; mode.symbol_count()];
    for (s, t) in mode.sync() {
        tones[s] = t;
    }
    let n = mode.symbol_frames();
    let ranges = if mode == Mode::Ft8 {
        vec![
            (n / 2, 7 * n - n / 2),
            (36 * n + n / 2, 43 * n - n / 2),
            (72 * n + n / 2, 79 * n - n / 2),
        ]
    } else {
        [1, 34, 67, 100]
            .into_iter()
            .map(|s| (s * n + n / 2, (s + 4) * n - n / 2))
            .collect()
    };
    (quadratures(mode, &tones, 0.).unwrap(), ranges)
}
fn coherent(
    samples: &[f32],
    start: usize,
    wave: &[[f32; 2]],
    ranges: &[(usize, usize)],
    frequency: f64,
    stride: usize,
) -> f64 {
    let step = 2. * PI * frequency * stride as f64 / 12000.;
    let (dc, ds) = (step.cos(), step.sin());
    let mut score = 0.;
    for &(lo, hi) in ranges {
        let angle = 2. * PI * frequency * (lo + 1) as f64 / 12000.;
        let (mut co, mut si) = (angle.cos(), angle.sin());
        let (mut re, mut im) = (0., 0.);
        for j in (lo..hi).step_by(stride) {
            let w = wave[j];
            let a = w[0] as f64 * co - w[1] as f64 * si;
            let b = w[0] as f64 * si + w[1] as f64 * co;
            let x = samples[start + j] as f64;
            re += x * a;
            im += x * b;
            (co, si) = (co * dc - si * ds, si * dc + co * ds);
        }
        score += (re * re + im * im) / ((hi - lo) / stride) as f64;
    }
    score
}
fn refine_sync(
    samples: &[f32],
    mode: Mode,
    c: Candidate,
    cancel: &impl Fn() -> bool,
) -> Result<Candidate, DecodeError> {
    let (wave, ranges) = sync_template(mode);
    let n = mode.symbol_frames();
    let mut best = Candidate { score: -1., ..c };
    for dt in -2isize..=2 {
        let start = c.start as isize + dt * (n / 16) as isize;
        if start < 0 || start as usize + wave.len() > samples.len() {
            continue;
        }
        for df in -4..=4 {
            if cancel() {
                return Err(DecodeError::Cancelled);
            }
            let frequency = c.frequency + df as f64 * mode.spacing() / 16.;
            if !(200. - 1e-7..=3500. + 1e-7).contains(&frequency) {
                continue;
            }
            let score = coherent(samples, start as usize, &wave, &ranges, frequency, 1);
            if score > best.score {
                best = Candidate {
                    start: start as usize,
                    frequency,
                    score,
                };
            }
        }
    }
    Ok(best)
}
fn refine_known(
    samples: &[f32],
    mode: Mode,
    tones: &[u8],
    c: Candidate,
    cancel: &impl Fn() -> bool,
) -> Result<Candidate, DecodeError> {
    let wave = quadratures(mode, tones, 0.).unwrap();
    let n = mode.symbol_frames();
    let ranges = [(n / 2, wave.len() - n / 2)];
    let step = 6000. / wave.len() as f64;
    let count = (mode.spacing() / 2. / step).ceil() as i32 + 1;
    let mut best = Candidate { score: -1., ..c };
    for dt in -4isize..=4 {
        let start = c.start as isize + dt * (n / 16) as isize;
        if start < 0 || start as usize + wave.len() > samples.len() {
            continue;
        }
        for df in -count..=count {
            if cancel() {
                return Err(DecodeError::Cancelled);
            }
            let frequency = c.frequency + df as f64 * step;
            if !(200. - 1e-7..=3500. + 1e-7).contains(&frequency) {
                continue;
            }
            let score = coherent(samples, start as usize, &wave, &ranges, frequency, 4);
            if score > best.score {
                best = Candidate {
                    start: start as usize,
                    frequency,
                    score,
                };
            }
        }
    }
    let coarse = best;
    for dt in -(n as isize / 16)..=n as isize / 16 {
        if dt % (n as isize / 128).max(1) != 0 {
            continue;
        }
        let start = coarse.start as isize + dt;
        if start < 0 || start as usize + wave.len() > samples.len() {
            continue;
        }
        for df in -4..=4 {
            if cancel() {
                return Err(DecodeError::Cancelled);
            }
            let frequency = coarse.frequency + df as f64 * step / 8.;
            if !(200. - 1e-7..=3500. + 1e-7).contains(&frequency) {
                continue;
            }
            let score = coherent(samples, start as usize, &wave, &ranges, frequency, 4);
            if score > best.score {
                best = Candidate {
                    start: start as usize,
                    frequency,
                    score,
                };
            }
        }
    }
    let fine = best;
    let radius = (n as isize / 128).max(1);
    for dt in -radius..=radius {
        let start = fine.start as isize + dt;
        if start < 0 || start as usize + wave.len() > samples.len() {
            continue;
        }
        if cancel() {
            return Err(DecodeError::Cancelled);
        }
        let score = coherent(samples, start as usize, &wave, &ranges, fine.frequency, 4);
        if score > best.score {
            best = Candidate {
                start: start as usize,
                frequency: fine.frequency,
                score,
            };
        }
    }
    Ok(best)
}
fn fit_signal(samples: &[f32], start: usize, wave: &[[f32; 2]]) -> Option<(f64, f64, f64)> {
    let (mut cc, mut ss, mut cs, mut xc, mut xs) = (0., 0., 0., 0., 0.);
    for (&x, q) in samples.get(start..start + wave.len())?.iter().zip(wave) {
        let (c, s) = (q[0] as f64, q[1] as f64);
        cc += c * c;
        ss += s * s;
        cs += c * s;
        xc += x as f64 * c;
        xs += x as f64 * s;
    }
    let det = cc * ss - cs * cs;
    if !det.is_finite() || det <= 1e-12 * cc * ss {
        return None;
    }
    let a = (xc * ss - xs * cs) / det;
    let b = (xs * cc - xc * cs) / det;
    Some((a, b, a * xc + b * xs))
}
