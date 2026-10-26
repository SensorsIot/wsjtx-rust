use super::likelihood::{self, LikelihoodContext};
use super::search::CpuBudget;
use super::{Channel, ChannelWord, DecodeError, Mode};
use rustfft::num_complex::Complex64;
use std::f64::consts::PI;
pub(super) struct Observation {
    pub llr: [f32; 174],
    pub word: Option<ChannelWord>,
}
pub(super) struct Demodulator {
    mode: Mode,
    rectangle: Vec<Vec<Complex64>>,
    local: Vec<Vec<Complex64>>,
    neighbors: Vec<Vec<Vec<Complex64>>>,
}
impl Demodulator {
    pub fn new(mode: Mode) -> Self {
        let n = mode.symbol_frames();
        let q = mode.tone_count();
        let phase = pulse_phases(mode);
        let rectangle = (0..q)
            .map(|t| {
                (0..n)
                    .map(|k| Complex64::from_polar(1., -2. * PI * t as f64 * k as f64 / n as f64))
                    .collect()
            })
            .collect();
        let neighbors = [0, 1, 3, 4]
            .into_iter()
            .map(|lag| {
                (0..q)
                    .map(|t| {
                        phase[lag]
                            .iter()
                            .map(|&p| Complex64::from_polar(1., -p * t as f64))
                            .collect()
                    })
                    .collect()
            })
            .collect();
        let mut local = vec![];
        if mode == Mode::Ft4 {
            for left in 0..q {
                for target in 0..q {
                    for right in 0..q {
                        local.push(
                            (0..n)
                                .map(|k| {
                                    Complex64::from_polar(
                                        1.,
                                        -(left as f64 * phase[1][k]
                                            + target as f64 * phase[2][k]
                                            + right as f64 * phase[3][k]),
                                    )
                                })
                                .collect(),
                        );
                    }
                }
            }
        } else {
            for t in 0..q {
                local.push(
                    phase[2]
                        .iter()
                        .map(|&p| Complex64::from_polar(1., -p * t as f64))
                        .collect(),
                );
            }
        }
        Self {
            mode,
            rectangle,
            local,
            neighbors,
        }
    }
    pub async fn observe(
        &self,
        samples: &[f32],
        start: usize,
        frequency: f64,
        context: LikelihoodContext,
        channel: &Channel,
        budget: &mut CpuBudget<'_>,
    ) -> Result<Observation, DecodeError> {
        let mode = self.mode;
        let n = mode.symbol_frames();
        let q = mode.tone_count();
        let symbols = mode.symbol_count();
        if start
            .checked_add(n * symbols)
            .is_none_or(|end| end > samples.len())
        {
            return Err(DecodeError::InvalidSamples);
        }
        let carrier = (0..n)
            .map(|k| Complex64::from_polar(1., -2. * PI * frequency * k as f64 / 12000.))
            .collect::<Vec<_>>();
        let mut tones = vec![0; symbols];
        let mut input = vec![Complex64::new(0., 0.); n];
        for (s, tone) in tones.iter_mut().enumerate() {
            budget.checkpoint().await?;
            for k in 0..n {
                input[k] = carrier[k] * samples[start + s * n + k] as f64;
            }
            let mut best = -1.;
            for (t, template) in self.rectangle.iter().enumerate() {
                let power = dot(&input, template).norm_sqr();
                if power > best {
                    best = power;
                    *tone = t as u8;
                }
            }
        }
        for (s, t) in mode.sync() {
            tones[s] = t;
        }
        if mode == Mode::Ft4 {
            tones[0] = 0;
            tones[symbols - 1] = 0;
        }
        let gray = mode.gray_map();
        let width = mode.bits_per_symbol();
        let mut priors = vec![[0.; 8]; symbols];
        for p in &mut priors {
            p[..q].fill(-(q as f64).ln());
        }
        for (s, t) in mode.sync() {
            priors[s][..q].fill(f64::NEG_INFINITY);
            priors[s][t as usize] = 0.;
        }
        if mode == Mode::Ft4 {
            for s in [0, symbols - 1] {
                priors[s][..q].fill(f64::NEG_INFINITY);
                priors[s][0] = 0.;
            }
        }
        let data = mode.data_symbols();
        let mut llr = [0.; 174];
        for iteration in 0..3 {
            let old = tones.clone();
            for (i, &s) in data.iter().enumerate() {
                budget.checkpoint().await?;
                for k in 0..n {
                    let mut factor = carrier[k];
                    for (lag, index) in [(-2isize, 0usize), (-1, 1), (1, 2), (2, 3)] {
                        if mode == Mode::Ft4 && (lag == -1 || lag == 1) {
                            continue;
                        }
                        let neighbor = s as isize + lag;
                        if neighbor >= 0 && (neighbor as usize) < symbols {
                            factor *= self.neighbors[index][old[neighbor as usize] as usize][k];
                        }
                    }
                    input[k] = factor * samples[start + s * n + k] as f64;
                }
                let mut energies = vec![[0.; 8]; if mode == Mode::Ft4 { 16 } else { 1 }];
                if mode == Mode::Ft4 {
                    for (neighbors, energy) in energies.iter_mut().enumerate() {
                        let (left, right) = (neighbors / q, neighbors % q);
                        for (target, value) in energy[..q].iter_mut().enumerate() {
                            let template = &self.local[(left * q + target) * q + right];
                            *value = dot(&input, template).norm_sqr() / n as f64;
                        }
                    }
                } else {
                    for (t, template) in self.local.iter().enumerate() {
                        energies[0][t] = dot(&input, template).norm_sqr() / n as f64;
                    }
                }
                let banks = likelihood::scores(&energies, q, context)?;
                let mut scores = [0.; 8];
                if mode == Mode::Ft4 {
                    for (target, score) in scores[..q].iter_mut().enumerate() {
                        let mut alternatives = [0.; 16];
                        for left in 0..q {
                            for right in 0..q {
                                alternatives[left * q + right] = banks[left * q + right][target]
                                    + priors[s - 1][left]
                                    + priors[s + 1][right];
                            }
                        }
                        *score = likelihood::logsum(&alternatives);
                    }
                } else {
                    scores = banks[0];
                }
                for bit in 0..width {
                    let mut zero = [0.; 4];
                    let mut one = [0.; 4];
                    let (mut z, mut o) = (0, 0);
                    for (value, &tone) in gray.iter().enumerate() {
                        if (value >> (width - bit - 1)) & 1 == 0 {
                            zero[z] = scores[tone];
                            z += 1;
                        } else {
                            one[o] = scores[tone];
                            o += 1;
                        }
                    }
                    llr[i * width + bit] = (likelihood::logsum(&zero[..z])
                        - likelihood::logsum(&one[..o]))
                    .clamp(-12., 12.) as f32;
                }
            }
            if iteration < 2 {
                budget.checkpoint().await?;
                let (word, posterior) = channel.beliefs(&llr, &|| (budget.cancel)());
                if let Some(word) = word
                    && channel_gates(&word, &llr)
                {
                    return Ok(Observation {
                        llr,
                        word: Some(word),
                    });
                }
                for (i, &s) in data.iter().enumerate() {
                    let bits = &posterior[i * width..(i + 1) * width];
                    let value = bits
                        .iter()
                        .fold(0usize, |a, &l| 2 * a + usize::from(l < 0.));
                    tones[s] = gray[value] as u8;
                    if mode == Mode::Ft4 {
                        for (value, &tone) in gray.iter().enumerate() {
                            let mut log_prior = 0.;
                            for (b, &l) in bits.iter().enumerate() {
                                let sign = if (value >> (width - b - 1)) & 1 == 0 {
                                    1.
                                } else {
                                    -1.
                                };
                                log_prior -= (-sign * (l as f64).clamp(-12., 12.)).exp().ln_1p();
                            }
                            priors[s][tone] = log_prior;
                        }
                        let normal = likelihood::logsum(&priors[s][..q]);
                        for p in &mut priors[s][..q] {
                            *p -= normal;
                        }
                    }
                }
            }
        }
        Ok(Observation { llr, word: None })
    }
}
pub(super) fn channel_gates(word: &ChannelWord, llr: &[f32; 174]) -> bool {
    let mean = llr.iter().map(|x| x.abs()).sum::<f32>() / 174.;
    mean >= 1.
        && word
            .iter()
            .zip(llr)
            .filter(|(b, l)| **b != u8::from(**l < 0.))
            .count()
            <= 24
}
fn dot(x: &[Complex64], template: &[Complex64]) -> Complex64 {
    x.iter()
        .zip(template)
        .fold(Complex64::new(0., 0.), |sum, (&a, &b)| sum + a * b)
}
fn pulse_phases(mode: Mode) -> Vec<Vec<f64>> {
    let n = mode.symbol_frames();
    let bt = mode.gaussian_bt();
    let k = PI * (2. / 2f64.ln()).sqrt();
    (-2isize..=2)
        .map(|lag| {
            let mut phase = 0.;
            (0..n)
                .map(|s| {
                    let t = (s as f64 + 0.5 - (lag as f64 + 0.5) * n as f64) / n as f64;
                    let pulse = (super::waveform::erf(k * bt * (t + 0.5))
                        - super::waveform::erf(k * bt * (t - 0.5)))
                        / 2.;
                    phase += 2. * PI * pulse / n as f64;
                    phase
                })
                .collect()
        })
        .collect()
}
