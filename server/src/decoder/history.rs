//! Private modem publication history; application result retention stays with its owner.
use super::{Decode, DecodeError, Mode};
use serde::Serialize;

const MAX_SAFE_SEQUENCE: u64 = 9_007_199_254_740_991;
struct PublicationKey {
    payload: String,
    start: u64,
    frequency: f64,
    reserved_bytes: usize,
}

#[cfg(test)]
#[test]
fn resource_history_capacity_counts_reserved_key_storage() {
    let mut history = DecodeState::new_live(Mode::Ft8);
    let mut publications = 0;
    for index in 0..2048usize {
        let bits = std::array::from_fn(|j| {
            if j < 11 {
                ((index >> (10 - j)) & 1) as u8
            } else {
                0
            }
        });
        let record = Decode {
            payload: super::unpack(&bits),
            start_frame: 1000,
            frequency_hz: 1000.,
            snr_db: Some(-20.),
        };
        history
            .publish_if_new(&record, &mut |_| {
                publications += 1;
                Ok(())
            })
            .unwrap();
    }
    assert_eq!(publications, 2048);
    assert_eq!(history.available_count(), 2048);
    assert!(history.encoded_bytes() <= 2 * 1024 * 1024);
    let keys_reserved = history.published.capacity() * std::mem::size_of::<PublicationKey>();
    let strings_reserved = history
        .published
        .iter()
        .map(|key| key.payload.capacity())
        .sum::<usize>();
    assert!(keys_reserved > 0 && strings_reserved >= 2048 * 77);
    eprintln!(
        "RESOURCE_CAPACITY {}",
        serde_json::json!({
            "owner":"modem_history", "records":2048,"key_vector_capacity":history.published.capacity(),
            "key_vector_reserved_bytes":keys_reserved,"payload_reserved_bytes":strings_reserved,
            "encoded_charge_bytes":history.encoded_bytes(),"is_decoded_success":false,
            "whole_workspace_proved":false,
        })
    );
    let extra = Decode {
        payload: super::unpack(&[1; 77]),
        start_frame: 1000,
        frequency_hz: 1000.,
        snr_db: None,
    };
    assert_eq!(
        history.publish_if_new(&extra, &mut |_| panic!("over-cap record cannot publish")),
        Err(DecodeError::DecodeLimit)
    );
    assert_eq!(history.available_count(), 2048);
}
/// Modem observations only: no station/source identity, wire cursor or worker authority.
pub struct DecodeState {
    mode: Mode,
    published: Vec<PublicationKey>,
    encoded_bytes: usize,
    live_history: bool,
    last_window_origin: Option<u64>,
}
impl DecodeState {
    /// Finite numerical-test context with lifetime publication limits.
    pub fn new(mode: Mode) -> Self {
        Self {
            mode,
            published: vec![],
            encoded_bytes: 0,
            live_history: false,
            last_window_origin: None,
        }
    }
    /// Continuous receive context. The caller resets it on a job/source/gap/history reset.
    pub fn new_live(mode: Mode) -> Self {
        Self {
            live_history: true,
            ..Self::new(mode)
        }
    }
    pub fn mode(&self) -> Mode {
        self.mode
    }
    /// Retained modem keys, not the live application's result-ring count or wire cursor.
    pub fn available_count(&self) -> usize {
        self.published.len()
    }
    /// Original byte charges of retained keys; live records reserve a 16-digit sequence.
    pub fn encoded_bytes(&self) -> usize {
        self.encoded_bytes
    }

    pub(super) fn prepare_window(&mut self, origin: u64) -> Result<(), DecodeError> {
        if !self.live_history {
            return Ok(());
        }
        if self.last_window_origin.is_some_and(|last| origin < last) {
            return Err(DecodeError::InvalidSamples);
        }
        let minimum = origin.saturating_sub((self.mode.symbol_frames() / 2) as u64);
        let mut retired_bytes = 0;
        self.published.retain(|key| {
            if key.start < minimum {
                retired_bytes += key.reserved_bytes;
                false
            } else {
                true
            }
        });
        self.encoded_bytes = self
            .encoded_bytes
            .checked_sub(retired_bytes)
            .expect("retired charges belong to the retained modem byte budget");
        self.last_window_origin = Some(origin);
        Ok(())
    }
    pub(super) fn active_frequencies(&self, origin: u64, frames: usize) -> Vec<f64> {
        let end = origin.saturating_add(frames as u64);
        self.published
            .iter()
            .filter(|key| key.start >= origin && key.start < end)
            .map(|key| key.frequency)
            .collect()
    }
    pub(super) fn publish_if_new(
        &mut self,
        record: &Decode,
        publish: &mut impl FnMut(&Decode) -> Result<(), DecodeError>,
    ) -> Result<(), DecodeError> {
        if self.published.iter().any(|key| {
            key.payload == record.payload.payload77
                && key.start.abs_diff(record.start_frame) <= (self.mode.symbol_frames() / 2) as u64
        }) {
            return Ok(());
        }
        #[derive(Serialize)]
        struct Numbered<'a> {
            sequence: u64,
            #[serde(flatten)]
            record: &'a Decode,
        }
        let sequence = if self.live_history {
            MAX_SAFE_SEQUENCE
        } else {
            u64::try_from(self.published.len()).expect("modem key count is bounded by 2048")
        };
        let bytes = serde_json::to_vec(&Numbered { sequence, record })
            .map_err(|_| DecodeError::DecodeLimit)?
            .len();
        if self.published.len() >= 2048 || bytes > 1024 || self.encoded_bytes + bytes > 2097152 {
            return Err(DecodeError::DecodeLimit);
        }
        publish(record)?;
        self.encoded_bytes += bytes;
        self.published.push(PublicationKey {
            payload: record.payload.payload77.clone(),
            start: record.start_frame,
            frequency: record.frequency_hz,
            reserved_bytes: bytes,
        });
        Ok(())
    }
}
