//! Private modem publication history; application result retention stays with its owner.
use super::{Decode, DecodeError, Mode};
use serde::Serialize;

const MAX_SAFE_SEQUENCE: u64 = 9_007_199_254_740_991;

/// Actual heap capacities, not serialized byte charges or decoded observations.
#[cfg(test)]
pub(super) fn retained_record_bytes(record: &Decode) -> usize {
    use super::{Call, Exchange, Fields};
    fn call(c: &Call) -> usize {
        c.text.as_ref().map_or(0, String::capacity)
    }
    fn exchange(e: &Exchange) -> usize {
        match e {
            Exchange::Grid(s) | Exchange::Roger(s) | Exchange::State(s) => s.capacity(),
            _ => 0,
        }
    }
    let p = &record.payload;
    p.payload77.capacity()
        + p.text.as_ref().map_or(0, String::capacity)
        + p.fields.as_ref().map_or(0, |f| match f {
            Fields::FreeText { value } | Fields::Telemetry { value } => value.capacity(),
            Fields::Standard {
                to,
                from,
                exchange: e,
                ..
            }
            | Fields::Rtty {
                to,
                from,
                exchange: e,
                ..
            } => call(to) + call(from) + exchange(e),
            Fields::Dxpedition {
                first,
                second,
                hashed,
                ..
            } => call(first) + call(second) + call(hashed),
            Fields::FieldDay {
                to,
                from,
                class_name,
                section,
                ..
            } => call(to) + call(from) + class_name.capacity() + section.capacity(),
            Fields::Nonstandard {
                full_call,
                hashed_call,
                roger,
                ..
            } => call(full_call) + call(hashed_call) + roger.capacity(),
            Fields::Vhf { to, from, grid, .. } => call(to) + call(from) + grid.capacity(),
        })
}

#[cfg(test)]
pub(super) fn capacity_state(mode: Mode) -> (DecodeState, Vec<Decode>, serde_json::Value) {
    let mut state = DecodeState::new_live(mode);
    let mut records = Vec::new();
    let mut setup_callbacks = 0;
    for index in 0..2048u128 {
        // Legal radix42 FreeText, distinct full payloads, not padded allocations.
        let value = 42u128.pow(12) + index;
        let bits = std::array::from_fn(|j| {
            if j < 71 {
                ((value >> (70 - j)) & 1) as u8
            } else {
                0
            }
        });
        let record = Decode {
            payload: super::unpack(&bits),
            start_frame: 0,
            frequency_hz: 1000.,
            snr_db: Some(-20.),
        };
        assert_eq!(record.payload.status, super::PayloadStatus::Decoded);
        state
            .publish_if_new(&record, &mut |_| {
                setup_callbacks += 1;
                Ok(())
            })
            .unwrap();
        records.push(record);
    }
    state.prepare_window(0).unwrap();
    assert_eq!(state.available_count(), 2048);
    assert_eq!(setup_callbacks, 2048);
    let ledger = serde_json::json!({"prepared_records":records.len(), "prepared_callbacks":setup_callbacks,
        "actual_decoded_callbacks":0,"is_decoded_success":false,"origin":0,"start_frame":0,
        "history_key_capacity":state.published.capacity(),
        "history_key_reserved_bytes":state.published.capacity()*std::mem::size_of::<PublicationKey>(),
        "history_string_reserved_bytes":state.published.iter().map(|k|k.payload.capacity()).sum::<usize>(),
        "semantic_encoded_charge_bytes":state.encoded_bytes(),"record_capacity":records.capacity(),
        "record_inline_reserved_bytes":records.capacity()*std::mem::size_of::<Decode>(),
        "record_nested_reserved_bytes":records.iter().map(retained_record_bytes).sum::<usize>(),
        "unexercised_maximum_nested_record_allowance_bytes":null,
        "maximum_legal_retained_graph_proved":false});
    (state, records, ledger)
}
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
