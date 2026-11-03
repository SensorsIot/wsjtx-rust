use super::baseband::{BandPlan, BandWindow, PassBand};
use super::bitmetrics;
use super::fit::fit_coefficients;
use super::history::DecodeState;
use super::physical_sync;
use super::snr::Ft8Snr;
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
    pub(super) cancel: &'a (dyn Fn() -> bool + Sync),
    deadline: Instant,
    resume: bool,
}
impl<'a> CpuBudget<'a> {
    pub(super) fn new(cancel: &'a (dyn Fn() -> bool + Sync)) -> Self {
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
/// Verified subtractions per window (#56: jt9 subtracts every decode, MAX_EARLY 200).
const SUBTRACTIONS: usize = 200;
/// Ft8PaddedResidual: 2.0 s of zeros before and 0.64 s after an FT8 window (jt9 sync8
/// lags -62..+62, DT -2.5..+2.5 s).
const PAD_BEFORE: usize = 24000;
const PAD_AFTER: usize = 7680;
/// Two verified words with the same payload and start are one frame only when their
/// carriers are this close.
const DUPLICATE_SEPARATION_HZ: f64 = 50.;
/// ft8b's weak-word guard: at most this many hard Costas hits and an SNR below -25 dB.
const WEAK_MAX_COSTAS_HITS: usize = 10;
const WEAK_SNR_DB: f64 = -25.;
struct Subtraction {
    start: usize,
    frequency: f64,
    tones: Vec<u8>,
}
/// Pure modem instance: no source, device, job, network or transmit authority. Its worker
/// threads are scoped to one decode stage and end with it.
pub struct Decoder {
    channel: Channel,
    scalar: bool,
    /// Threads of the parallel decode stages, this one included (#57 CL-057-02).
    threads: usize,
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
            threads: super::parallel::default_threads(),
        }
    }
    /// The same decoder on exactly `threads` threads (at least one); the decode set and
    /// order do not depend on it.
    pub fn with_threads(self, threads: usize) -> Self {
        Self {
            threads: threads.max(1),
            ..self
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
        cancel: &(impl Fn() -> bool + Sync),
    ) -> Result<Vec<Decode>, DecodeError> {
        complete(self.decode_async(samples, mode, cancel))
    }
    pub async fn decode_async(
        &self,
        samples: &[f32],
        mode: Mode,
        cancel: &(impl Fn() -> bool + Sync),
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
        cancel: &(impl Fn() -> bool + Sync),
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
        cancel: &(impl Fn() -> bool + Sync),
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
        // FT8 runs on the zero-padded residual (#56 Ft8PaddedResidual): frames that run past
        // either window edge are found and subtracted like jt9's, and published only when
        // they lie inside the window to within half a symbol.
        let length = samples.len();
        let (front, back) = if mode == Mode::Ft8 && length + PAD_BEFORE + PAD_AFTER <= 360000 {
            (PAD_BEFORE, PAD_AFTER)
        } else {
            (0, 0)
        };
        if front + back > 0 {
            let mut padded = vec![0f32; front];
            padded.extend_from_slice(&samples);
            padded.resize(front + length + back, 0.);
            samples = padded;
        }
        let inside =
            |start: usize| start + n / 2 >= front && start + frame <= front + length + n / 2;
        let plan = BandPlan::new(mode, samples.len(), self.scalar)?;
        let mut subtractor = Subtractor::new(mode, self.scalar)?;
        budget.checkpoint().await?;
        let mut subtractions = 0;
        // (payload, padded absolute start, carrier) of this window's verified words.
        let mut window_seen = Vec::<(String, u64, f64)>::new();
        let seen = |window_seen: &[(String, u64, f64)], bits: &str, at: u64, carrier: f64| {
            window_seen.iter().any(|(b, start, f)| {
                b == bits
                    && start.abs_diff(at) <= (n / 2) as u64
                    && (f - carrier).abs() <= DUPLICATE_SEPARATION_HZ
            })
        };
        for _pass in 0..3 {
            let spectrum = Spectrum::new(&samples, mode, self.scalar, &mut budget).await?;
            let mut physical = plan.current_pass(&samples, &mut budget).await?;
            let mut contrast = None;
            let candidates = if mode == Mode::Ft4 {
                let mut candidates = vec![];
                let coarse =
                    super::coarse_ft4::contrast(&samples, self.scalar, &mut budget).await?;
                for frequency in coarse.candidates() {
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
                contrast = Some(coarse);
                candidates
            } else {
                spectrum
                    .candidates(samples.len(), &physical, self.threads, &mut budget)
                    .await?
            };
            // Every candidate's verification is independent of the others; only the duplicate
            // checks depend on this window's earlier records. Candidates are therefore
            // verified in parallel and replayed here in order, each step and error taken
            // exactly where the single-threaded loop takes it (#57 CL-057-02).
            // Each verification holds one 1.2 MB known-word waveform while it refines, so at
            // most eight run at once (about 20 MB); more threads gain little here.
            let stop = || cancel();
            let verifications = super::parallel::map(
                self.threads.min(8),
                &candidates,
                &mut budget,
                || physical.fork(),
                |&c, pass, budget| complete(self.verify(&samples, c, &stop, pass, budget)),
            )
            .await?;
            // The SNR keeps its per-period baseline cache, so it is measured in this replay,
            // after the duplicate and physical checks, exactly as the serial loop did.
            let mut ft8_snr = Ft8Snr::new(self.scalar);
            let mut pending = vec![];
            let mut verified = 0;
            for (c, verification) in candidates.iter().zip(verifications) {
                budget.checkpoint().await?;
                let Some((payload, tones, fitted)) = verification? else {
                    continue;
                };
                // A repeat of this window's word on a carrier more than 50 Hz away is a
                // second transmission: it is subtracted (ft8b subtracts before ft8_decode
                // drops the duplicate message) and the history keeps it from publishing twice.
                if seen(
                    &window_seen,
                    &payload.payload77,
                    origin + c.start as u64,
                    c.frequency,
                ) {
                    continue;
                }
                let (fitted, supported) = fitted?;
                let absolute = origin + fitted.start as u64;
                if seen(&window_seen, &payload.payload77, absolute, fitted.frequency) {
                    continue;
                }
                let (supported, hits) = supported?;
                if !supported {
                    continue;
                }
                let complete = inside(fitted.start);
                let snr = match (&contrast, complete) {
                    (_, false) => None,
                    (Some(contrast), true) => contrast.snr_db(fitted.frequency).map(|db| (db, db)),
                    (None, true) => ft8_snr
                        .snr_db(
                            &samples[front..front + length],
                            super::snr::period_of(
                                origin,
                                fitted.start.max(front) - front,
                                state.period_start(),
                            ),
                            fitted.start.max(front) - front,
                            fitted.frequency,
                            &tones,
                            &mut budget,
                        )
                        .await?
                        .map(|db| (db, super::snr::reported(db))),
                };
                // ft8b: nsync<=10 .and. xsnr<-25 is a likely false decode.
                if mode == Mode::Ft8
                    && hits <= WEAK_MAX_COSTAS_HITS
                    && snr.is_some_and(|(db, _)| db < WEAK_SNR_DB)
                {
                    continue;
                }
                window_seen.push((payload.payload77.clone(), absolute, fitted.frequency));
                verified += 1;
                if complete {
                    let record = Decode {
                        payload,
                        start_frame: (origin + fitted.start as u64).saturating_sub(front as u64),
                        frequency_hz: fitted.frequency,
                        snr_db: snr.map(|(_, reported)| reported),
                    };
                    state.publish_if_new(&record, publish)?;
                }
                if pending.len() + subtractions < SUBTRACTIONS {
                    pending.push(Subtraction {
                        start: fitted.start,
                        frequency: fitted.frequency,
                        tones,
                    });
                }
            }
            // Discard the immutable current-pass transform before modifying its residual.
            drop(physical);
            // The residual is updated in order; only the waveforms are built in parallel,
            // at most four at a time (about 2.4 MB each while built) to bound their memory.
            for chunk in pending.chunks(self.threads.min(4)) {
                let waves = super::parallel::map(
                    self.threads,
                    chunk,
                    &mut budget,
                    || (),
                    |s, _, _| quadratures(mode, &s.tones, s.frequency),
                )
                .await?;
                for (subtraction, wave) in chunk.iter().zip(waves) {
                    budget.checkpoint().await?;
                    let wave = wave.ok_or(DecodeError::InvalidSamples)?;
                    subtractor
                        .subtract(&mut samples, subtraction.start, &wave, &mut budget)
                        .await?;
                    subtractions += 1;
                }
            }
            // The padding stays zero: a subtraction near a window edge spills into it.
            samples[..front].fill(0.);
            samples[front + length..].fill(0.);
            if verified == 0 || subtractions >= SUBTRACTIONS {
                break;
            }
        }
        budget.checkpoint().await?;
        Ok(())
    }
    /// One candidate's verification, everything that does not depend on the window's
    /// earlier records. The refined frame and its physical check are computed even where
    /// the caller's duplicate checks will skip them; the caller surfaces their errors only
    /// where its loop reaches them.
    async fn verify(
        &self,
        samples: &[f32],
        c: Candidate,
        cancel: &(impl Fn() -> bool + Sync),
        physical: &mut PassBand<'_>,
        budget: &mut CpuBudget<'_>,
    ) -> Verification {
        let mode = physical.plan.mode;
        let Some(word) = bitmetrics::observe(physical, c, &self.channel, budget).await? else {
            return Ok(None);
        };
        let Some(payload) = self.channel.payload(&word, mode) else {
            return Ok(None);
        };
        let payload = unpack(&payload);
        let tones = self.channel.tones(&word, mode);
        let fitted = async {
            let fitted = refine_known(samples, mode, &tones, c, cancel, budget, physical).await?;
            let supported = physical_sync::support(physical, fitted, budget).await;
            Ok((fitted, supported))
        }
        .await;
        Ok(Some((payload, tones, fitted)))
    }
}

/// [`Decoder::verify`] staged as the in-order replay consumes it: the payload and tones,
/// then the refined frame, then whether its physical check supports it.
type Verification = Result<
    Option<(
        Payload,
        Vec<u8>,
        Result<(Candidate, Result<(bool, usize), DecodeError>), DecodeError>,
    )>,
    DecodeError,
>;

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
