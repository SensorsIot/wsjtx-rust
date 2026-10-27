// FT4 filtered Costas timing adapted from WSJT-X sync4d and ft4_decode.
// Copyright the WSJT-X contributors. GPL-3.0-only; see the project LICENSE.
// Reference: WSJTX/wsjtx 0f7d5928449ec747c3d1f6da1306f8c94404c3a9.
use super::{
    DecodeError,
    baseband::{BandWindow, PassBand},
    physical_sync,
    search::CpuBudget,
    synchronization::Candidate,
};
use rustfft::num_complex::Complex64;
use std::f64::consts::PI;
fn templates(delta: f64) -> Vec<Complex64> {
    let patterns = [[0, 1, 3, 2], [1, 0, 2, 3], [2, 3, 1, 0], [3, 2, 0, 1]];
    patterns
        .into_iter()
        .flat_map(|pattern| {
            (0..64).map(move |j| {
                let phase = -2.
                    * PI
                    * (pattern[j / 16] as f64 * (j % 16) as f64 / 16.
                        + delta * (2 * j) as f64 / (12000. / 18.));
                Complex64::from_polar(1., phase)
            })
        })
        .collect()
}
fn score(window: &BandWindow, origin: usize, template: &[Complex64]) -> f64 {
    (0..4)
        .map(|block| {
            (0..64)
                .map(|j| {
                    window.samples[origin + block * 33 * 32 + 2 * j] * template[block * 64 + j]
                })
                .sum::<Complex64>()
                .norm()
                / 64.
        })
        .sum()
}
fn distinct(a: &Candidate, b: &Candidate) -> bool {
    a.start.abs_diff(b.start) >= 60480 || (a.frequency - b.frequency).abs() > 12000. / 576. / 2.
}
// Per-pass physical hypotheses only: payload/FEC results have no selection authority.
fn admit(
    prior: &[Candidate],
    out: &mut Vec<Candidate>,
    c: Candidate,
    physical: bool,
) -> Result<bool, DecodeError> {
    if !physical
        || prior
            .iter()
            .chain(out.iter())
            .any(|other| !distinct(other, &c))
    {
        return Ok(false);
    }
    if prior.len() + out.len() == 256 {
        return Err(DecodeError::SearchLimited);
    }
    out.push(c);
    Ok(true)
}
fn eligible(b: isize, frequency: f64, frames: usize) -> bool {
    b >= 32 && (b as usize - 32) * 18 + 60480 <= frames && (200. ..=3500.).contains(&frequency)
}
fn better(a: &Candidate, b: &Candidate) -> bool {
    a.score > b.score || a.score == b.score && (a.frequency, a.start) < (b.frequency, b.start)
}
pub(super) async fn qualify(
    pass: &mut PassBand<'_>,
    frequency: f64,
    prior: &[Candidate],
    budget: &mut CpuBudget<'_>,
) -> Result<Vec<Candidate>, DecodeError> {
    if pass.frames < 60480 {
        return Ok(vec![]);
    }
    let Some(window) = pass.window(frequency, budget).await? else {
        return Ok(vec![]);
    };
    let last = (pass.frames - 60480) / 18 + 32;
    let mut times = (32..=last).step_by(4).collect::<Vec<_>>();
    if times.last() != Some(&last) {
        times.push(last);
    }
    let frequencies = (-12..=12)
        .step_by(3)
        .map(|d| frequency + d as f64)
        .collect::<Vec<_>>();
    let templates = frequencies
        .iter()
        .map(|f| templates(f - window.center_hz))
        .collect::<Vec<_>>();
    let mut scores = vec![0.; times.len() * 9];
    for (r, &b) in times.iter().enumerate() {
        budget.checkpoint().await?;
        for f in 0..9 {
            if eligible(b as isize, frequencies[f], pass.frames) {
                scores[r * 9 + f] = score(&window, b, &templates[f]);
            }
        }
    }
    let mut peaks = vec![];
    for r in 0..times.len() {
        budget.checkpoint().await?;
        for f in 0..9 {
            let s = scores[r * 9 + f];
            if s < 1.2 || !s.is_finite() {
                continue;
            }
            let c = Candidate {
                start: (times[r] - 32) * 18,
                frequency: frequencies[f],
                score: s,
            };
            let maximum = (r.saturating_sub(1)..=(r + 1).min(times.len() - 1)).all(|rr| {
                (f.saturating_sub(1)..=(f + 1).min(8)).all(|ff| {
                    let other = Candidate {
                        start: (times[rr] - 32) * 18,
                        frequency: frequencies[ff],
                        score: scores[rr * 9 + ff],
                    };
                    !better(&other, &c)
                })
            });
            if maximum {
                peaks.push((r * 9 + f, c));
            }
        }
    }
    peaks.sort_by(|(_, a), (_, b)| {
        b.score
            .total_cmp(&a.score)
            .then(a.frequency.total_cmp(&b.frequency))
            .then(a.start.cmp(&b.start))
    });
    let mut blocked = vec![false; scores.len()];
    let mut out = vec![];
    for (index, peak) in peaks {
        budget.checkpoint().await?;
        if blocked[index] {
            continue;
        }
        // Raw-grid NMS retains half-symbol/half-tone support, using bounded bitmap visits.
        let b = times[index / 9];
        let low = times.partition_point(|&t| t + 16 < b);
        let high = times.partition_point(|&t| t <= b + 16);
        for row in low..high {
            for (f, carrier) in frequencies.iter().enumerate() {
                if (carrier - peak.frequency).abs() <= 12000. / 576. / 2. {
                    blocked[row * 9 + f] = true;
                }
            }
        }
        let mut best = None;
        for df in -4..=4 {
            let carrier = peak.frequency + df as f64;
            let template = templates_for(carrier - window.center_hz);
            for dt in -5..=5 {
                budget.checkpoint().await?;
                let b = (peak.start / 18 + 32) as isize + dt;
                if !eligible(b, carrier, pass.frames) {
                    continue;
                }
                let c = Candidate {
                    start: (b as usize - 32) * 18,
                    frequency: carrier,
                    score: score(&window, b as usize, &template),
                };
                if best.as_ref().is_none_or(|other| better(&c, other)) {
                    best = Some(c);
                }
            }
        }
        let Some(c) = best else {
            continue;
        };
        if c.score < 1.2 || prior.iter().chain(&out).any(|other| !distinct(other, &c)) {
            continue;
        }
        let physical = physical_sync::supports(pass, c, budget).await?;
        admit(prior, &mut out, c, physical)?;
    }
    Ok(out)
}
// Separate name avoids shadowing the cached coarse templates above.
fn templates_for(delta: f64) -> Vec<Complex64> {
    templates(delta)
}

#[cfg(test)]
#[path = "physical_ft4_test.rs"]
mod tests;
