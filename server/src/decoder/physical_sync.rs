// Portions adapted from WSJT-X sync8d.f90 and its driver.
// Copyright the WSJT-X contributors. GPL-3.0-only; see the project LICENSE.
// Reference: WSJTX/wsjtx 0f7d5928449ec747c3d1f6da1306f8c94404c3a9.
use super::{
    DecodeError, Mode,
    baseband::{BandWindow, PassBand},
    bitmetrics,
    search::CpuBudget,
    synchronization::Candidate,
};
use rustfft::num_complex::Complex64;
use std::f64::consts::PI;

fn complete(start: isize, frequency: f64, frames: usize, mode: Mode) -> bool {
    start >= 0
        && start as usize + mode.symbol_count() * mode.symbol_frames() <= frames
        && (200. - 1e-7..=3500. + 1e-7).contains(&frequency)
}
fn better(candidate: Candidate, best: Option<Candidate>) -> bool {
    candidate.score.is_finite()
        && best.is_none_or(|b| {
            candidate.score > b.score
                || candidate.score == b.score
                    && (candidate.frequency, candidate.start) < (b.frequency, b.start)
        })
}
fn sync8(window: &BandWindow, origin: usize, frequency: f64) -> f64 {
    let delta = frequency - window.center_hz;
    let mut power = 0.;
    for (symbol, tone) in Mode::Ft8.sync() {
        let mut dot = Complex64::new(0., 0.);
        for j in 0..32 {
            let phase = -2. * PI * (tone as f64 / 32. + delta / 200.) * j as f64;
            dot += window.samples[origin + symbol * 32 + j] * Complex64::from_polar(1., phase);
        }
        power += dot.norm_sqr();
    }
    power
}
async fn ft8(
    pass: &mut PassBand<'_>,
    coarse: Candidate,
    budget: &mut CpuBudget<'_>,
) -> Result<Option<Candidate>, DecodeError> {
    let Some(window) = pass.window(coarse.frequency, budget).await? else {
        return Ok(None);
    };
    let initial = ((coarse.start + 30) / 60) as isize;
    let mut best = None;
    for b in initial - 10..=initial + 10 {
        budget.checkpoint().await?;
        if !complete(b * 60, coarse.frequency, pass.frames, Mode::Ft8) {
            continue;
        }
        let c = Candidate {
            start: b as usize * 60,
            frequency: coarse.frequency,
            score: sync8(&window, b as usize, coarse.frequency),
        };
        if better(c, best) {
            best = Some(c);
        }
    }
    let Some(time) = best else {
        return Ok(None);
    };
    best = None;
    for df in -5..=5 {
        budget.checkpoint().await?;
        let frequency = coarse.frequency + df as f64 * 0.5;
        if !complete(time.start as isize, frequency, pass.frames, Mode::Ft8) {
            continue;
        }
        let c = Candidate {
            start: time.start,
            frequency: frequency.clamp(200., 3500.),
            score: sync8(&window, time.start / 60, frequency),
        };
        if better(c, best) {
            best = Some(c);
        }
    }
    let Some(frequency) = best else {
        return Ok(None);
    };
    let Some(window) = pass.window(frequency.frequency, budget).await? else {
        return Ok(None);
    };
    best = None;
    for b in frequency.start as isize / 60 - 4..=frequency.start as isize / 60 + 4 {
        budget.checkpoint().await?;
        if !complete(b * 60, frequency.frequency, pass.frames, Mode::Ft8) {
            continue;
        }
        let c = Candidate {
            start: b as usize * 60,
            frequency: frequency.frequency,
            score: sync8(&window, b as usize, frequency.frequency),
        };
        if better(c, best) {
            best = Some(c);
        }
    }
    Ok(best)
}
pub(super) async fn supports(
    pass: &mut PassBand<'_>,
    c: Candidate,
    budget: &mut CpuBudget<'_>,
) -> Result<bool, DecodeError> {
    let Some(rows) = pass.rows(c.start, c.frequency, budget).await? else {
        return Ok(false);
    };
    Ok(bitmetrics::physical_accepts(pass.plan.mode, &rows))
}
pub(super) async fn qualify(
    pass: &mut PassBand<'_>,
    coarse: Candidate,
    budget: &mut CpuBudget<'_>,
) -> Result<Option<Candidate>, DecodeError> {
    debug_assert_eq!(pass.plan.mode, Mode::Ft8);
    let candidate = ft8(pass, coarse, budget).await?;
    if let Some(c) = candidate
        && supports(pass, c, budget).await?
    {
        return Ok(Some(c));
    }
    Ok(None)
}
