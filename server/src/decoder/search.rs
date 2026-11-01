use super::baseband::{BandPlan, BandWindow, PassBand};
use super::bitmetrics::{self, channel_gates};
use super::fit::{fit_coefficients, fit_signal};
use super::history::DecodeState;
use super::physical_sync;
use super::subtraction::Subtractor;
use super::synchronization::{Candidate, Spectrum};
use super::{Channel, Mode, Payload, quadratures, unpack};
use rustfft::num_complex::Complex64;
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
                let fitted = refine_known(
                    &samples,
                    mode,
                    &tones,
                    c,
                    cancel,
                    &mut budget,
                    &mut physical,
                )
                .await?;
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
    // Interleaved lanes break the serial phasor and accumulator chains; every sample of the
    // range still contributes at full rate (same Gram, different summation order).
    const LANES: usize = 4;
    let lanes = if stride == 1 { LANES } else { 1 };
    let step = 2. * PI * frequency * (stride * lanes) as f64 / 12000.;
    let (dc, ds) = (step.cos(), step.sin());
    let mut score = 0.;
    for &(lo, hi) in ranges {
        let mut co = [0f64; LANES];
        let mut si = [0f64; LANES];
        for lane in 0..lanes {
            let angle = 2. * PI * frequency * (lo + lane * stride + 1) as f64 / 12000.;
            (co[lane], si[lane]) = (angle.cos(), angle.sin());
        }
        let mut sums = [[0f64; LANES]; 5];
        let mut add = |lane: usize, w: [f32; 2], x: f32, co: f64, si: f64| {
            let a = w[0] as f64 * co - w[1] as f64 * si;
            let b = w[0] as f64 * si + w[1] as f64 * co;
            let x = x as f64;
            sums[0][lane] += a * a;
            sums[1][lane] += b * b;
            sums[2][lane] += a * b;
            sums[3][lane] += x * a;
            sums[4][lane] += x * b;
        };
        if lanes == LANES {
            let w = &wave[lo..hi];
            let x = &samples[start + lo..start + hi];
            let (wb, wt) = w.as_chunks::<LANES>();
            let (xb, xt) = x.as_chunks::<LANES>();
            for (wq, xq) in wb.iter().zip(xb) {
                for lane in 0..LANES {
                    add(lane, wq[lane], xq[lane], co[lane], si[lane]);
                    (co[lane], si[lane]) =
                        (co[lane] * dc - si[lane] * ds, si[lane] * dc + co[lane] * ds);
                }
            }
            for (lane, (&wq, &xq)) in wt.iter().zip(xt).enumerate() {
                add(lane, wq, xq, co[lane], si[lane]);
            }
        } else {
            for j in (lo..hi).step_by(stride) {
                add(0, wave[j], samples[start + j], co[0], si[0]);
                (co[0], si[0]) = (co[0] * dc - si[0] * ds, si[0] * dc + co[0] * ds);
            }
        }
        let [cc, ss, cs, re, im] = sums.map(|v| v.iter().sum::<f64>());
        let Some((_, _, explained)) = fit_coefficients(cc, ss, cs, re, im) else {
            return f64::NEG_INFINITY;
        };
        score += explained;
    }
    score
}
/// Band-limited ranking of known-word grid points. `band` is the current-pass candidate
/// baseband (the same transform the physical sync uses), so carriers outside the candidate
/// band are filtered, never aliased. It only orders grid points; scores stay full rate.
struct Ranking<'a> {
    band: &'a BandWindow,
    down: usize,
    wave: &'a [[f32; 2]],
    lo: usize,
    hi: usize,
    /// Forward transform of length 2*frame/down: bin k is grid frequency base + k*step.
    fft: &'a dyn rustfft::Fft<f64>,
    base: f64,
    step: f64,
}
impl Ranking<'_> {
    /// Squared magnitude of the decimated analytic correlation for one start and a set of
    /// carrier frequencies. It approximates the full-rate explained energy up to one common
    /// scale, without the small image term.
    fn scores(&self, start: usize, frequencies: &[f64], out: &mut Vec<f64>) {
        let d = self.down;
        let first = (self.lo + start).div_ceil(d);
        let last = (self.hi + start).div_ceil(d).min(self.band.samples.len());
        let products = (first..last)
            .map(|m| {
                let w = self.wave[m * d - start];
                self.band.samples[m] * Complex64::new(w[0] as f64, -(w[1] as f64))
            })
            .collect::<Vec<_>>();
        let angle =
            |frequency: f64| 2. * PI * (self.band.center_hz - frequency) * d as f64 / 12000.;
        let size = self.fft.len();
        let mut bins = None;
        if frequencies.len() > 16 && products.len() <= size {
            let rotation = Complex64::from_polar(1., angle(self.base));
            let mut phasor = Complex64::new(1., 0.);
            let mut buffer = vec![Complex64::new(0., 0.); size];
            for (z, &p) in buffer.iter_mut().zip(&products) {
                *z = p * phasor;
                phasor *= rotation;
            }
            self.fft.process(&mut buffer);
            bins = Some(buffer);
        }
        for &frequency in frequencies {
            let k = ((frequency - self.base) / self.step).round();
            if let Some(bins) = &bins
                && (self.base + k * self.step - frequency).abs() <= 1e-9
                && k.abs() < size as f64 / 2.
            {
                out.push(bins[(k as isize).rem_euclid(size as isize) as usize].norm_sqr());
                continue;
            }
            let rotation = Complex64::from_polar(1., angle(frequency));
            let mut phasor = Complex64::new(1., 0.);
            let mut sum = Complex64::new(0., 0.);
            for &p in &products {
                sum += p * phasor;
                phasor *= rotation;
            }
            out.push(sum.norm_sqr());
        }
    }
}
/// Grid points (start, frequencies) in contract order. When a ranking is available, only the
/// `keep` best-ranked points are scored at full rate; they are compared in grid order with the
/// unchanged tie rule, so the result is always a full-rate score at a contract grid point.
#[allow(clippy::too_many_arguments)]
async fn refine_stage(
    samples: &[f32],
    wave: &[[f32; 2]],
    ranges: &[(usize, usize)],
    points: &[(usize, Vec<f64>)],
    ranking: Option<&Ranking<'_>>,
    keep: usize,
    best: &mut Candidate,
    cancel: &impl Fn() -> bool,
    budget: &mut CpuBudget<'_>,
) -> Result<(), DecodeError> {
    let total = points.iter().map(|(_, f)| f.len()).sum::<usize>();
    let mut selected = vec![true; total];
    if let Some(ranking) = ranking.filter(|_| total > keep) {
        let mut approximate = Vec::with_capacity(total);
        for (start, frequencies) in points {
            budget.checkpoint().await?;
            ranking.scores(*start, frequencies, &mut approximate);
        }
        let mut order = (0..total).collect::<Vec<_>>();
        order.sort_by(|&a, &b| approximate[b].total_cmp(&approximate[a]).then(a.cmp(&b)));
        selected = vec![false; total];
        for &index in &order[..keep] {
            selected[index] = true;
        }
    }
    let mut index = 0;
    for (start, frequencies) in points {
        for &frequency in frequencies {
            let chosen = selected[index];
            index += 1;
            if !chosen {
                continue;
            }
            budget.checkpoint().await?;
            if cancel() {
                return Err(DecodeError::Cancelled);
            }
            let score = coherent(samples, *start, wave, ranges, frequency, 1);
            if score > best.score
                || score == best.score
                    && (frequency < best.frequency
                        || frequency == best.frequency && *start < best.start)
            {
                *best = Candidate {
                    start: *start,
                    frequency,
                    score,
                };
            }
        }
    }
    Ok(())
}
/// Full-rate grid evaluations kept per refinement stage after band-limited ranking.
const REFINE_KEEP: [usize; 3] = [6, 3, 2];
#[allow(clippy::too_many_arguments)]
async fn refine_known(
    samples: &[f32],
    mode: Mode,
    tones: &[u8],
    c: Candidate,
    cancel: &impl Fn() -> bool,
    budget: &mut CpuBudget<'_>,
    pass: &mut PassBand<'_>,
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
    frequencies.retain(|f| (200. - 1e-7..=3500. + 1e-7).contains(f));
    let fits = |start: isize| start >= 0 && start as usize + wave.len() <= samples.len();
    let band = pass.window(c.frequency, budget).await?;
    let ranking = band.as_ref().map(|band| Ranking {
        band,
        down: if mode == Mode::Ft8 { 60 } else { 18 },
        wave: &wave,
        lo: ranges[0].0,
        hi: ranges[0].1,
        fft: pass.plan.ranking.as_ref(),
        base: c.frequency,
        step,
    });
    let mut best = Candidate { score: -1., ..c };
    let coarse_points = (-4isize..=4)
        .map(|dt| c.start as isize + dt * (n / 16) as isize)
        .filter(|&start| fits(start))
        .map(|start| (start as usize, frequencies.clone()))
        .collect::<Vec<_>>();
    refine_stage(
        samples,
        &wave,
        &ranges,
        &coarse_points,
        ranking.as_ref(),
        REFINE_KEEP[0],
        &mut best,
        cancel,
        budget,
    )
    .await?;
    let coarse = best;
    let fine_frequencies = (-4..=4)
        .map(|df| coarse.frequency + df as f64 * step / 8.)
        .filter(|f| (200. - 1e-7..=3500. + 1e-7).contains(f))
        .collect::<Vec<_>>();
    let fine_points = (-(n as isize / 16)..=n as isize / 16)
        .filter(|dt| dt % (n as isize / 128).max(1) == 0)
        .map(|dt| coarse.start as isize + dt)
        .filter(|&start| fits(start))
        .map(|start| (start as usize, fine_frequencies.clone()))
        .collect::<Vec<_>>();
    refine_stage(
        samples,
        &wave,
        &ranges,
        &fine_points,
        ranking.as_ref(),
        REFINE_KEEP[1],
        &mut best,
        cancel,
        budget,
    )
    .await?;
    let fine = best;
    let radius = (n as isize / 128).max(1);
    let last_points = (-radius..=radius)
        .map(|dt| fine.start as isize + dt)
        .filter(|&start| fits(start))
        .map(|start| (start as usize, vec![fine.frequency]))
        .collect::<Vec<_>>();
    refine_stage(
        samples,
        &wave,
        &ranges,
        &last_points,
        ranking.as_ref(),
        REFINE_KEEP[2],
        &mut best,
        cancel,
        budget,
    )
    .await?;
    Ok(best)
}
/// The unpruned three-stage search: every grid point at full rate (test oracle).
#[cfg(test)]
async fn refine_exhaustive(
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
