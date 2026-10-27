use super::baseband::BandPlan;
use super::bitmetrics::{self, channel_gates};
use super::fit::{fit_coefficients, fit_signal};
use super::history::DecodeState;
use super::physical_sync;
use super::subtraction::Subtractor;
use super::synchronization::{Candidate, Spectrum};
use super::{Channel, Mode, Payload, quadratures, unpack};
use serde::{Deserialize, Serialize};
use std::{
    f64::consts::PI,
    future::{Future, poll_fn},
    pin::pin,
    task::{Context, Poll, Waker},
    time::{Duration, Instant},
};
pub(super) struct CpuBudget<'a> {
    pub(super) cancel: &'a dyn Fn() -> bool,
    deadline: Instant,
    resume: bool,
}
impl<'a> CpuBudget<'a> {
    pub(super) fn new(cancel: &'a dyn Fn() -> bool) -> Self {
        Self {
            cancel,
            deadline: Instant::now() + Duration::from_millis(10),
            resume: false,
        }
    }
    pub(super) async fn checkpoint(&mut self) -> Result<(), DecodeError> {
        poll_fn(|cx| {
            if (self.cancel)() {
                return Poll::Ready(Err(DecodeError::Cancelled));
            }
            if self.resume {
                self.resume = false;
                self.deadline = Instant::now() + Duration::from_millis(10);
            }
            if Instant::now() >= self.deadline {
                self.resume = true;
                cx.waker().wake_by_ref();
                Poll::Pending
            } else {
                Poll::Ready(Ok(()))
            }
        })
        .await
    }
}
pub(super) fn complete<T>(future: impl Future<Output = T>) -> T {
    let mut cx = Context::from_waker(Waker::noop());
    let mut future = pin!(future);
    loop {
        if let Poll::Ready(value) = future.as_mut().poll(&mut cx) {
            return value;
        }
    }
}
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
struct Subtraction {
    start: usize,
    frequency: f64,
    tones: Vec<u8>,
}
/// Pure modem instance: no source, device, job, thread, network or transmit authority.
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
            scalar: true,
            ..Self::new()
        }
    }
    /// Explicit pure FT8 Deep policy entry point; existing constructors stay baseline.
    pub fn new_deep_ft8() -> Self {
        // Interface checkpoint: numerical Deep implementation follows in this branch.
        Self::new()
    }
    /// Scalar-transform counterpart of the explicit pure FT8 Deep policy.
    pub fn new_scalar_deep_ft8() -> Self {
        Self::with_scalar_transform()
    }
    /// Blocking numerical convenience wrapper; station workers poll a cooperative future.
    pub fn decode(
        &self,
        samples: &[f32],
        mode: Mode,
        cancel: &impl Fn() -> bool,
    ) -> Result<Vec<Decode>, DecodeError> {
        complete(self.decode_async(samples, mode, cancel))
    }
    pub async fn decode_async(
        &self,
        samples: &[f32],
        mode: Mode,
        cancel: &impl Fn() -> bool,
    ) -> Result<Vec<Decode>, DecodeError> {
        let mut output = vec![];
        self.decode_into_async(samples, mode, cancel, &mut |record| {
            output.push(record.clone());
            Ok(())
        })
        .await?;
        Ok(output)
    }
    /// Verified records reach the caller before any later cancellation/limit error.
    pub async fn decode_into_async(
        &self,
        samples: &[f32],
        mode: Mode,
        cancel: &impl Fn() -> bool,
        publish: &mut impl FnMut(&Decode) -> Result<(), DecodeError>,
    ) -> Result<(), DecodeError> {
        if samples.iter().any(|x| !x.is_finite()) {
            return Err(DecodeError::InvalidSamples);
        }
        let mut state = DecodeState::new(mode);
        for origin in (0..samples.len()).step_by(180000) {
            if cancel() {
                return Err(DecodeError::Cancelled);
            }
            let end = (origin + 360000).min(samples.len());
            self.decode_window_into_async(
                samples[origin..end].to_vec(),
                origin as u64,
                &mut state,
                cancel,
                publish,
            )
            .await?;
        }
        if cancel() {
            Err(DecodeError::Cancelled)
        } else {
            Ok(())
        }
    }
    /// Takes one worker-owned residual copy (<=30 s). The caller may keep accepting canonical
    /// blocks into its own history while this future yields; no source-block references are held.
    pub async fn decode_window_into_async(
        &self,
        mut samples: Vec<f32>,
        origin: u64,
        state: &mut DecodeState,
        cancel: &impl Fn() -> bool,
        publish: &mut impl FnMut(&Decode) -> Result<(), DecodeError>,
    ) -> Result<(), DecodeError> {
        if samples.len() > 360000 {
            return Err(DecodeError::DecodeLimit);
        }
        if samples.iter().any(|x| !x.is_finite())
            || origin
                .checked_add(samples.len() as u64)
                .is_none_or(|end| end > 9007199254740991)
        {
            return Err(DecodeError::InvalidSamples);
        }
        state.prepare_window(origin)?;
        let mut budget = CpuBudget::new(cancel);
        budget.checkpoint().await?;
        let mode = state.mode();
        let n = mode.symbol_frames();
        let frame = n * mode.symbol_count();
        if samples.len() < frame {
            return Ok(());
        }
        let plan = BandPlan::new(mode, samples.len(), self.scalar)?;
        let mut subtractor = Subtractor::new(mode, self.scalar)?;
        budget.checkpoint().await?;
        let mut subtractions = 0;
        let mut window_seen = Vec::<(String, u64)>::new();
        for _pass in 0..3 {
            let spectrum = Spectrum::new(&samples, mode, self.scalar, &mut budget).await?;
            let mut physical = plan.current_pass(&samples, &mut budget).await?;
            let candidates = if mode == Mode::Ft4 {
                let mut candidates = vec![];
                for frequency in
                    super::coarse_ft4::candidates(&samples, self.scalar, &mut budget).await?
                {
                    candidates.extend(
                        super::physical_ft4::qualify(
                            &mut physical,
                            frequency,
                            &candidates,
                            &mut budget,
                        )
                        .await?,
                    );
                }
                candidates
            } else {
                spectrum
                    .candidates(samples.len(), &mut physical, &mut budget)
                    .await?
            };
            let accepted = state.active_frequencies(origin, samples.len());
            let mut pending = vec![];
            let mut verified = 0;
            for c in candidates {
                budget.checkpoint().await?;
                let observation =
                    bitmetrics::observe(&mut physical, c, &self.channel, &mut budget).await?;
                let Some(word) = observation.word else {
                    continue;
                };
                if !channel_gates(&word, &observation.llr) {
                    continue;
                }
                let Some(payload) = self.channel.payload(&word, mode) else {
                    continue;
                };
                let payload = unpack(&payload);
                let absolute = origin + c.start as u64;
                if window_seen.iter().any(|(bits, start)| {
                    *bits == payload.payload77 && start.abs_diff(absolute) <= (n / 2) as u64
                }) {
                    continue;
                }
                let tones = self.channel.tones(&word, mode);
                let fitted = refine_known(&samples, mode, &tones, c, cancel, &mut budget).await?;
                let absolute = origin + fitted.start as u64;
                if window_seen.iter().any(|(bits, start)| {
                    *bits == payload.payload77 && start.abs_diff(absolute) <= (n / 2) as u64
                }) {
                    continue;
                }
                if !physical_sync::supports(&mut physical, fitted, &mut budget).await? {
                    continue;
                }
                let wave = quadratures(mode, &tones, fitted.frequency)
                    .ok_or(DecodeError::InvalidSamples)?;
                let fit = fit_signal(&samples, fitted.start, &wave);
                let variance =
                    spectrum.noise_variance(fitted.start, frame, fitted.frequency, &accepted);
                let snr = fit
                    .and_then(|(a, b, _)| {
                        variance
                            .filter(|&v| v / 6000. > 1e-20)
                            .map(|v| 10. * (((a * a + b * b) / 2.) / (v * 2500. / 6000.)).log10())
                    })
                    .filter(|x| x.is_finite())
                    .map(|x| x.clamp(-60., 60.));
                window_seen.push((payload.payload77.clone(), absolute));
                verified += 1;
                let record = Decode {
                    payload,
                    start_frame: absolute,
                    frequency_hz: fitted.frequency,
                    snr_db: snr,
                };
                state.publish_if_new(&record, publish)?;
                if pending.len() + subtractions < 32 {
                    pending.push(Subtraction {
                        start: fitted.start,
                        frequency: fitted.frequency,
                        tones,
                    });
                }
            }
            // Discard the immutable current-pass transform before modifying its residual.
            drop(physical);
            for subtraction in pending {
                budget.checkpoint().await?;
                let wave = quadratures(mode, &subtraction.tones, subtraction.frequency)
                    .ok_or(DecodeError::InvalidSamples)?;
                subtractor
                    .subtract(&mut samples, subtraction.start, &wave, &mut budget)
                    .await?;
                subtractions += 1;
            }
            if verified == 0 || subtractions >= 32 {
                break;
            }
        }
        budget.checkpoint().await?;
        Ok(())
    }
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
        let (mut cc, mut ss, mut cs) = (0., 0., 0.);
        for j in (lo..hi).step_by(stride) {
            let w = wave[j];
            let a = w[0] as f64 * co - w[1] as f64 * si;
            let b = w[0] as f64 * si + w[1] as f64 * co;
            cc += a * a;
            ss += b * b;
            cs += a * b;
            let x = samples[start + j] as f64;
            re += x * a;
            im += x * b;
            (co, si) = (co * dc - si * ds, si * dc + co * ds);
        }
        let Some((_, _, explained)) = fit_coefficients(cc, ss, cs, re, im) else {
            return f64::NEG_INFINITY;
        };
        score += explained;
    }
    score
}
async fn refine_known(
    samples: &[f32],
    mode: Mode,
    tones: &[u8],
    c: Candidate,
    cancel: &impl Fn() -> bool,
    budget: &mut CpuBudget<'_>,
) -> Result<Candidate, DecodeError> {
    let wave = quadratures(mode, tones, 0.).unwrap();
    let n = mode.symbol_frames();
    let ranges = [(n / 2, wave.len() - n / 2)];
    let step = 6000. / wave.len() as f64;
    let count = mode.symbol_count() as i32;
    let lower = (c.frequency - mode.spacing() / 2.).max(200.);
    let upper = (c.frequency + mode.spacing() / 2.).min(3500.);
    let mut frequencies = (-count..=count)
        .map(|df| c.frequency + df as f64 * step)
        .filter(|&f| f >= lower && f <= upper)
        .chain([lower, upper])
        .collect::<Vec<_>>();
    frequencies.sort_by(f64::total_cmp);
    frequencies.dedup_by(|a, b| (*a - *b).abs() < 1e-12);
    let mut best = Candidate { score: -1., ..c };
    for dt in -4isize..=4 {
        let start = c.start as isize + dt * (n / 16) as isize;
        if start < 0 || start as usize + wave.len() > samples.len() {
            continue;
        }
        for &frequency in &frequencies {
            budget.checkpoint().await?;
            if cancel() {
                return Err(DecodeError::Cancelled);
            }
            if !(200. - 1e-7..=3500. + 1e-7).contains(&frequency) {
                continue;
            }
            let score = coherent(samples, start as usize, &wave, &ranges, frequency, 1);
            if score > best.score
                || score == best.score
                    && (frequency < best.frequency
                        || frequency == best.frequency && (start as usize) < best.start)
            {
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
            budget.checkpoint().await?;
            if cancel() {
                return Err(DecodeError::Cancelled);
            }
            let frequency = coarse.frequency + df as f64 * step / 8.;
            if !(200. - 1e-7..=3500. + 1e-7).contains(&frequency) {
                continue;
            }
            let score = coherent(samples, start as usize, &wave, &ranges, frequency, 1);
            if score > best.score
                || score == best.score
                    && (frequency < best.frequency
                        || frequency == best.frequency && (start as usize) < best.start)
            {
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
        budget.checkpoint().await?;
        if cancel() {
            return Err(DecodeError::Cancelled);
        }
        let frequency = fine.frequency;
        let score = coherent(samples, start as usize, &wave, &ranges, frequency, 1);
        if score > best.score
            || score == best.score
                && (frequency < best.frequency
                    || frequency == best.frequency && (start as usize) < best.start)
        {
            best = Candidate {
                start: start as usize,
                frequency: fine.frequency,
                score,
            };
        }
    }
    Ok(best)
}

#[cfg(test)]
#[path = "search_test.rs"]
mod tests;
