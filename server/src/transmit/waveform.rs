//! FT8 and FT4 GFSK waveforms with the arithmetic of WSJT-X gen_ft8wave/emit_ft8_waveform
//! and gen_ft4wave, evaluated in binary64. See WstxTransmit::Ft8WaveformContract and
//! Ft4WaveformContract.
use crate::decoder::{Mode, gaussian_pulse};
use std::f64::consts::{PI, TAU};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SampleRate {
    Hz12000,
    Hz48000,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WaveformError {
    FrequencyOutOfRange,
    InvalidTone,
}
pub const MIN_TONE0_HZ: f64 = 200.;
pub const MAX_TONE0_HZ: f64 = 2950.;
/// FT4 tone 0 limits: the four 20.833 Hz tones stay within 200..3000 Hz.
pub const FT4_MIN_TONE0_HZ: f64 = 200.;
pub const FT4_MAX_TONE0_HZ: f64 = 3000. - 4. * 12000. / 576.;

/// Checks the request and returns the samples per symbol at `rate`.
fn prepare(
    mode: Mode,
    tones: &[u8],
    tone0_hz: f64,
    band: (f64, f64),
    rate: SampleRate,
) -> Result<usize, WaveformError> {
    if !(band.0..=band.1).contains(&tone0_hz) {
        return Err(WaveformError::FrequencyOutOfRange);
    }
    if tones.iter().any(|&t| usize::from(t) >= mode.tone_count()) {
        return Err(WaveformError::InvalidTone);
    }
    Ok(match rate {
        SampleRate::Hz12000 => mode.symbol_frames(),
        SampleRate::Hz48000 => 4 * mode.symbol_frames(),
    })
}

/// Pulse-weighted frequency increments over (tones + 2) symbols: tone j's three-symbol
/// pulse starts at sample j*N, sampled at t=(i+1-1.5N)/N. Also returns that pulse.
fn smoothed_increments(mode: Mode, tones: &[u8], nsps: usize) -> (Vec<f64>, Vec<f64>) {
    let peak = TAU / nsps as f64;
    let pulse = (0..3 * nsps)
        .map(|i| gaussian_pulse(mode, (i as f64 + 1. - 1.5 * nsps as f64) / nsps as f64))
        .collect::<Vec<_>>();
    let mut dphi = vec![0.; (tones.len() + 2) * nsps];
    for (j, &tone) in tones.iter().enumerate() {
        for (d, p) in dphi[j * nsps..].iter_mut().zip(&pulse) {
            *d += peak * p * f64::from(tone);
        }
    }
    (dphi, pulse)
}

fn rate_hz(rate: SampleRate) -> f64 {
    match rate {
        SampleRate::Hz12000 => 12000.,
        SampleRate::Hz48000 => 48000.,
    }
}

/// Real unit-peak FT8 waveform of 79 symbols; `tone0_hz` is the frequency of tone 0.
pub fn waveform(
    tones: &[u8; 79],
    tone0_hz: f64,
    rate: SampleRate,
) -> Result<Vec<f32>, WaveformError> {
    let nsps = prepare(
        Mode::Ft8,
        tones,
        tone0_hz,
        (MIN_TONE0_HZ, MAX_TONE0_HZ),
        rate,
    )?;
    let len = tones.len() * nsps;
    let peak = TAU / nsps as f64;
    let (mut dphi, pulse) = smoothed_increments(Mode::Ft8, tones, nsps);
    // The first and last symbols are extended by dummy symbols of the same tone.
    for q in 0..2 * nsps {
        dphi[q] += peak * f64::from(tones[0]) * pulse[nsps + q];
        dphi[len + q] += peak * f64::from(tones[78]) * pulse[q];
    }
    let carrier = TAU * tone0_hz / rate_hz(rate);
    let ramp = nsps / 8;
    let mut phase = 0f64;
    Ok((0..len)
        .map(|k| {
            let amplitude = if k < ramp {
                (1. - (PI * k as f64 / ramp as f64).cos()) / 2.
            } else if k >= len - ramp {
                (1. + (PI * (k - (len - ramp)) as f64 / ramp as f64).cos()) / 2.
            } else {
                1.
            };
            let sample = (amplitude * phase.sin()) as f32;
            phase = (phase + dphi[nsps + k] + carrier) % TAU;
            sample
        })
        .collect())
}

/// Real unit-peak FT4 waveform: the 103 channel tones framed by one ramp-up and one
/// ramp-down symbol, (103 + 2) symbols in all, as the native WSJT-X transmitter.
pub fn waveform_ft4(
    tones: &[u8; 103],
    tone0_hz: f64,
    rate: SampleRate,
) -> Result<Vec<f32>, WaveformError> {
    let nsps = prepare(
        Mode::Ft4,
        tones,
        tone0_hz,
        (FT4_MIN_TONE0_HZ, FT4_MAX_TONE0_HZ),
        rate,
    )?;
    let (dphi, _) = smoothed_increments(Mode::Ft4, tones, nsps);
    let len = dphi.len();
    let carrier = TAU * tone0_hz / rate_hz(rate);
    let mut phase = 0f64;
    Ok(dphi
        .iter()
        .enumerate()
        .map(|(k, d)| {
            // Ramps over the whole first and last symbol; sample N-1 of the fall is not zero.
            let amplitude = if k < nsps {
                (1. - (PI * k as f64 / nsps as f64).cos()) / 2.
            } else if k >= len - nsps {
                (1. + (PI * (k - (len - nsps)) as f64 / nsps as f64).cos()) / 2.
            } else {
                1.
            };
            let sample = (amplitude * phase.sin()) as f32;
            phase = (phase + d + carrier) % TAU;
            sample
        })
        .collect())
}
