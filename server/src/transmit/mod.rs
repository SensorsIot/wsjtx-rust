#![forbid(unsafe_code)]
//! Pure FT8/FT4 transmit preparation: message packing, channel symbols, waveform and
//! period scheduling. No audio device, PTT or radio access (WstxTransmit model).
mod pack;
mod schedule;
mod waveform;
use crate::decoder::{Channel, Mode};
pub use pack::{Family, PackError, Packed, pack};
pub use schedule::{ClockState, Parity, ScheduleError, Start, next_period, parity, plan_start};
pub use waveform::{SampleRate, WaveformError, waveform, waveform_ft4};

/// A packed message with its CRC/LDPC codeword and 79 channel tones.
#[derive(Clone, Debug, PartialEq)]
pub struct Frame {
    pub packed: Packed,
    pub codeword: [u8; 174],
    pub tones: [u8; 79],
}
/// A packed FT4 message with its codeword (over the scrambled payload) and 103 tones.
#[derive(Clone, Debug, PartialEq)]
pub struct Ft4Frame {
    pub packed: Packed,
    pub codeword: [u8; 174],
    pub tones: [u8; 103],
}

/// Packs `message` and encodes it with the receive codec's CRC-14, LDPC and Gray map.
pub fn encode(message: &str) -> Result<Frame, PackError> {
    let packed = pack(message)?;
    let channel = Channel::new();
    let codeword = channel.encode(&packed.bits, Mode::Ft8);
    let tones = channel
        .tones(&codeword, Mode::Ft8)
        .try_into()
        .expect("FT8 has 79 symbols");
    Ok(Frame {
        packed,
        codeword,
        tones,
    })
}

/// As `encode`, with the receive codec's FT4 scrambling; the codec's 105 symbols carry
/// the two ramp symbols, which are not channel tones.
pub fn encode_ft4(message: &str) -> Result<Ft4Frame, PackError> {
    let packed = pack(message)?;
    let channel = Channel::new();
    let codeword = channel.encode(&packed.bits, Mode::Ft4);
    let tones = channel.tones(&codeword, Mode::Ft4)[1..104]
        .try_into()
        .expect("FT4 has 103 channel symbols");
    Ok(Ft4Frame {
        packed,
        codeword,
        tones,
    })
}
