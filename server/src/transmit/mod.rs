#![forbid(unsafe_code)]
//! Pure FT8 transmit preparation: message packing, channel symbols, waveform and
//! period scheduling. No audio device, PTT or radio access (WstxTransmit model).
mod pack;
mod schedule;
mod waveform;
use crate::decoder::{Channel, Mode};
pub use pack::{Family, PackError, Packed, pack};
pub use schedule::{ClockState, Parity, ScheduleError, Start, next_period, parity, plan_start};
pub use waveform::{SampleRate, WaveformError, waveform};

/// A packed message with its CRC/LDPC codeword and 79 channel tones.
#[derive(Clone, Debug, PartialEq)]
pub struct Frame {
    pub packed: Packed,
    pub codeword: [u8; 174],
    pub tones: [u8; 79],
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
