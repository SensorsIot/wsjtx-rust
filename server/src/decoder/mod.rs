#![forbid(unsafe_code)]
//! Pure FT4/FT8 modem kernels. Samples use the canonical 12 kHz clock.
mod baseband;
mod bitmetrics;
mod channel;
mod coarse_ft4;
mod deep_channel;
mod deep_confidence;
mod fit;
mod history;
mod payload;
mod physical_ft4;
mod physical_sync;
mod search;
mod subtraction;
mod synchronization;
mod waveform;
pub use channel::{Channel, ChannelWord};
pub use history::DecodeState;
pub use payload::{Call, CallKind, Exchange, Fields, Payload, PayloadStatus, unpack};
pub use search::{Decode, DecodeError, Decoder};
use serde::{Deserialize, Serialize};
pub use waveform::quadratures;
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Mode {
    Ft4,
    Ft8,
}
impl Mode {
    pub fn symbol_frames(self) -> usize {
        match self {
            Self::Ft4 => 576,
            Self::Ft8 => 1920,
        }
    }
    pub fn tone_count(self) -> usize {
        match self {
            Self::Ft4 => 4,
            Self::Ft8 => 8,
        }
    }
    pub fn symbol_count(self) -> usize {
        match self {
            Self::Ft4 => 105,
            Self::Ft8 => 79,
        }
    }
    pub fn spacing(self) -> f64 {
        12000.0 / self.symbol_frames() as f64
    }
    pub fn bits_per_symbol(self) -> usize {
        if self == Self::Ft4 { 2 } else { 3 }
    }
    pub fn gray_map(self) -> &'static [usize] {
        match self {
            Self::Ft4 => &[0, 1, 3, 2],
            Self::Ft8 => &[0, 1, 3, 2, 5, 6, 4, 7],
        }
    }
    pub fn gaussian_bt(self) -> f64 {
        if self == Self::Ft4 { 1. } else { 2. }
    }
    pub fn ramp_frames(self) -> usize {
        if self == Self::Ft4 {
            self.symbol_frames()
        } else {
            self.symbol_frames() / 8
        }
    }
    pub fn sync_blocks(self) -> &'static [(usize, &'static [u8])] {
        match self {
            Self::Ft8 => &[
                (0, &[3, 1, 4, 0, 6, 5, 2]),
                (36, &[3, 1, 4, 0, 6, 5, 2]),
                (72, &[3, 1, 4, 0, 6, 5, 2]),
            ],
            Self::Ft4 => &[
                (1, &[0, 1, 3, 2]),
                (34, &[1, 0, 2, 3]),
                (67, &[2, 3, 1, 0]),
                (100, &[3, 2, 0, 1]),
            ],
        }
    }
    pub fn sync(self) -> Vec<(usize, u8)> {
        self.sync_blocks()
            .iter()
            .flat_map(|&(s, tones)| tones.iter().enumerate().map(move |(j, &t)| (s + j, t)))
            .collect()
    }
    pub fn data_symbols(self) -> Vec<usize> {
        let sync = self.sync();
        (0..self.symbol_count())
            .filter(|&s| {
                !(self == Self::Ft4 && (s == 0 || s == 104)) && !sync.iter().any(|x| x.0 == s)
            })
            .collect()
    }
}
