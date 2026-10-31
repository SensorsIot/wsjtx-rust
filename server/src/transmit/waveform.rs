//! FT8 GFSK waveform with the arithmetic of WSJT-X gen_ft8wave/emit_ft8_waveform,
//! evaluated in binary64. See WstxTransmit::Ft8WaveformContract.
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

/// Real unit-peak FT8 waveform of 79 symbols; `tone0_hz` is the frequency of tone 0.
pub fn waveform(
    tones: &[u8; 79],
    tone0_hz: f64,
    rate: SampleRate,
) -> Result<Vec<f32>, WaveformError> {
    if !(MIN_TONE0_HZ..=MAX_TONE0_HZ).contains(&tone0_hz) {
        return Err(WaveformError::FrequencyOutOfRange);
    }
    if tones.iter().any(|&t| t > 7) {
        return Err(WaveformError::InvalidTone);
    }
    let fs = match rate {
        SampleRate::Hz12000 => 12000,
        SampleRate::Hz48000 => 48000,
    };
    let nsps = Mode::Ft8.symbol_frames() * fs / 12000;
    let len = tones.len() * nsps;
    let peak = TAU / nsps as f64;
    let pulse = (0..3 * nsps)
        .map(|i| gaussian_pulse(Mode::Ft8, (i as f64 + 1. - 1.5 * nsps as f64) / nsps as f64))
        .collect::<Vec<_>>();
    // Frequency increments over (79 + 2) symbols; the first and last symbols are
    // extended by dummy symbols of the same tone.
    let mut dphi = vec![0.; len + 2 * nsps];
    for (j, &tone) in tones.iter().enumerate() {
        for (d, p) in dphi[j * nsps..].iter_mut().zip(&pulse) {
            *d += peak * p * f64::from(tone);
        }
    }
    for q in 0..2 * nsps {
        dphi[q] += peak * f64::from(tones[0]) * pulse[nsps + q];
        dphi[len + q] += peak * f64::from(tones[78]) * pulse[q];
    }
    let carrier = TAU * tone0_hz / fs as f64;
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
