#![forbid(unsafe_code)]
//! Pure FT8/FT4 transmit preparation: message packing, channel symbols, waveform and
//! period scheduling; `service` is the slice B transmit owner (arming, PTT, audio, halt),
//! `clock` the station's SNTP clock measurement (TransmitClock) and `air` the clock from
//! the air and the station clock combining both by the profile's source (#43).
pub mod air;
pub mod clock;
mod pack;
mod schedule;
pub mod service;
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

/// The a-priori call bits of WstxStationDecode::APrioriContext (WSJT-X ft8apset): payload
/// bits 0..29 of MyCall and 29..58 of DxCall in the standard message "MyCall DxCall RRR",
/// which must pack as i3=1 and render exactly. Without a DxCall of at least three characters
/// the dummy KA1ABC packs MyCall and there are no DxCall bits; without such a message, neither.
pub fn a_priori_calls(
    my_call: &str,
    dx_call: Option<&str>,
) -> (Option<[u8; 29]>, Option<[u8; 29]>) {
    let my = my_call.trim().to_ascii_uppercase();
    let dx = dx_call
        .map(|c| c.trim().to_ascii_uppercase())
        .filter(|c| c.len() >= 3);
    if my.len() < 3 {
        return (None, None);
    }
    let text = format!("{my} {} RRR", dx.as_deref().unwrap_or("KA1ABC"));
    match pack(&text) {
        Ok(p) if p.i3 == 1 && p.family == Family::Standard && p.text == text => (
            Some(p.bits[..29].try_into().expect("29 bits")),
            dx.map(|_| p.bits[29..58].try_into().expect("29 bits")),
        ),
        _ => (None, None),
    }
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
