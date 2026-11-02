//! Private modem publication history; application result retention stays with its owner.
use super::{Decode, DecodeError, Mode};
use serde::Serialize;

const MAX_SAFE_SEQUENCE: u64 = 9_007_199_254_740_991;

/// Real fixed-table graphs plus the old inline array of one lists() reallocation.
/// MaybeUninit slots represent moved String headers, never duplicate String owners.
#[cfg(test)]
pub(super) struct UnpackTableReserve {
    sections: Vec<String>,
    states: Vec<String>,
    old_inline: Vec<std::mem::MaybeUninit<String>>,
}
#[cfg(test)]
impl UnpackTableReserve {
    pub(super) fn new() -> Self {
        let sections: Vec<String> = serde_json::from_str(include_str!(
            "../../../fixtures/decoder/protocol-data/arrl_rac_sections.json"
        ))
        .unwrap();
        let states: Vec<String> = serde_json::from_str(include_str!(
            "../../../fixtures/decoder/protocol-data/states_provinces.json"
        ))
        .unwrap();
        for (table, count, twos, threes) in [(&sections, 84, 54, 30), (&states, 65, 63, 2)] {
            assert_eq!(table.len(), count);
            assert_eq!(table.iter().filter(|s| s.len() == 2).count(), twos);
            assert_eq!(table.iter().filter(|s| s.len() == 3).count(), threes);
            assert!(
                table
                    .iter()
                    .all(|s| s.is_ascii() && s.capacity() == s.len())
            );
            assert!(table.capacity() >= 128);
        }
        let mut old_inline = Vec::with_capacity(64);
        old_inline.resize_with(64, std::mem::MaybeUninit::uninit);
        let data = serde_json::json!({"owner":"unpack_fixed_tables_and_old_inline",
            "section_count":sections.len(),"state_count":states.len(),
            "section_vector_capacity":sections.capacity(),"state_vector_capacity":states.capacity(),
            "section_string_capacities":sections.iter().map(String::capacity).sum::<usize>(),
            "state_string_capacities":states.iter().map(String::capacity).sum::<usize>(),
            "old_inline_slots":old_inline.len(),"old_inline_capacity":old_inline.capacity(),
            "old_inline_reserved_bytes":old_inline.capacity()*std::mem::size_of::<String>(),
            "old_inline_has_initialized_string_owners":false,"is_decoded_success":false,
            "both_parser_branches_retained_conservatively":true,"new_decode_old_generation_added":false});
        let encoded = serde_json::to_string(&data).unwrap();
        assert!(encoded.len() < 16000);
        eprintln!("RESOURCE_CAPACITY {encoded}");
        Self {
            sections,
            states,
            old_inline,
        }
    }
    pub(super) fn retain(&self) {
        std::hint::black_box((&self.sections, &self.states, &self.old_inline));
    }
}

/// Inspect only real unpack-created String owners; inline enums are not heap owners.
#[cfg(test)]
pub(super) fn record_string_paths(record: &Decode) -> Vec<(&'static str, &String)> {
    use super::{Call, Exchange, Fields};
    fn call<'a>(out: &mut Vec<(&'static str, &'a String)>, path: &'static str, call: &'a Call) {
        if let Some(s) = &call.text {
            out.push((path, s));
        }
    }
    fn exchange<'a>(out: &mut Vec<(&'static str, &'a String)>, e: &'a Exchange) {
        match e {
            Exchange::Grid(s) => out.push(("fields.exchange.grid", s)),
            Exchange::Roger(s) => out.push(("fields.exchange.roger", s)),
            Exchange::State(s) => out.push(("fields.exchange.state", s)),
            _ => {}
        }
    }
    let p = &record.payload;
    let mut out = vec![("payload77", &p.payload77)];
    if let Some(s) = &p.text {
        out.push(("text", s));
    }
    if let Some(f) = &p.fields {
        match f {
            Fields::FreeText { value } | Fields::Telemetry { value } => {
                out.push(("fields.value", value))
            }
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
            } => {
                call(&mut out, "fields.to.text", to);
                call(&mut out, "fields.from.text", from);
                exchange(&mut out, e);
            }
            Fields::Dxpedition {
                first,
                second,
                hashed,
                ..
            } => {
                call(&mut out, "fields.first.text", first);
                call(&mut out, "fields.second.text", second);
                call(&mut out, "fields.hashed.text", hashed);
            }
            Fields::FieldDay {
                to,
                from,
                class_name,
                section,
                ..
            } => {
                call(&mut out, "fields.to.text", to);
                call(&mut out, "fields.from.text", from);
                out.push(("fields.class_name", class_name));
                out.push(("fields.section", section));
            }
            Fields::Nonstandard {
                full_call,
                hashed_call,
                roger,
                ..
            } => {
                call(&mut out, "fields.full_call.text", full_call);
                call(&mut out, "fields.hashed_call.text", hashed_call);
                out.push(("fields.roger", roger));
            }
            Fields::Vhf { to, from, grid, .. } => {
                call(&mut out, "fields.to.text", to);
                call(&mut out, "fields.from.text", from);
                out.push(("fields.grid", grid));
            }
        }
    }
    out
}

#[cfg(test)]
pub(super) fn string_layout_ledger(
    label: &str,
    variant: &str,
    record: &Decode,
) -> serde_json::Value {
    let strings = record_string_paths(record);
    let reserved = strings.iter().map(|(_, s)| s.capacity()).sum::<usize>();
    assert_eq!(reserved, retained_record_bytes(record));
    #[derive(Serialize)]
    struct Numbered<'a> {
        sequence: u64,
        #[serde(flatten)]
        record: &'a Decode,
    }
    serde_json::json!({"label":label,"variant":variant,"payload77":record.payload.payload77,
        "text":record.payload.text,"status":record.payload.status,"is_decoded_success":false,
        "owner_count":strings.len(),"string_lengths_sum":strings.iter().map(|(_,s)|s.len()).sum::<usize>(),
        "string_capacities_sum":reserved,"inline_decode_bytes":std::mem::size_of::<Decode>(),
        "record_serialized_bytes":serde_json::to_vec(record).unwrap().len(),
        "live_history_semantic_charge_bytes":serde_json::to_vec(&Numbered { sequence: MAX_SAFE_SEQUENCE, record }).unwrap().len(),
        "strings":strings.iter().map(|(path,s)|serde_json::json!({"path":path,"len":s.len(),"capacity":s.capacity()})).collect::<Vec<_>>()})
}

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
        // Legal RX FieldDay n3=4, six real String owners, distinct four-letter CQ tokens.
        let mut number = index;
        let mut letters = [b'A'; 4];
        for letter in letters.iter_mut().rev() {
            *letter += (number % 26) as u8;
            number /= 26;
        }
        assert_eq!(number, 0);
        let word = std::str::from_utf8(&letters).unwrap();
        let to = 1003
            + letters
                .iter()
                .fold(0u128, |value, c| value * 27 + (c - b'A' + 1) as u128);
        let mut bits = [0u8; 77];
        for (start, width, value) in [
            (0, 28, to),
            (28, 28, 532443),
            (56, 1, 1),
            (57, 4, 15),
            (61, 3, 5),
            (64, 7, 11),
            (71, 3, 4),
        ] {
            assert!(value < (1u128 << width));
            for j in 0..width {
                bits[start + j] = ((value >> (width - 1 - j)) & 1) as u8;
            }
        }
        let record = Decode {
            payload: super::unpack(&bits),
            start_frame: 0,
            frequency_hz: 1000.,
            snr_db: Some(-20.),
        };
        assert_eq!(record.payload.status, super::PayloadStatus::Decoded);
        assert!(matches!(
            record.payload.fields.as_ref(),
            Some(super::Fields::FieldDay { .. })
        ));
        assert_eq!(
            record.payload.text.as_deref(),
            Some(format!("CQ {word} CQ ZZZZ R 32F EMA").as_str())
        );
        assert_eq!(record_string_paths(&record).len(), 6);
        assert_eq!(record.payload.text.as_ref().unwrap().len(), 25);
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
        "cohort":"legal_field_day_n3_4_four_letter_cq_tokens","string_owners_per_record":6,
        "largest_attained_record_nested_bytes":records.iter().map(retained_record_bytes).max(),
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
    reserved_bytes: usize,
}

#[cfg(test)]
#[test]
fn resource_history_capacity_counts_reserved_key_storage() {
    {
        let tables = UnpackTableReserve::new();
        for mode in [Mode::Ft8, Mode::Ft4] {
            let (mut state, records, cohort) = capacity_state(mode);
            assert_eq!(records.len(), 2048);
            assert_eq!(state.available_count(), 2048);
            assert_eq!(cohort["prepared_callbacks"], 2048);
            for (record, expected) in [
                (&records[0], "CQ AAAA CQ ZZZZ R 32F EMA"),
                (&records[2047], "CQ ADAT CQ ZZZZ R 32F EMA"),
            ] {
                assert_eq!(record.payload.text.as_deref(), Some(expected));
                let paths = record_string_paths(record);
                assert_eq!(
                    paths.iter().map(|(path, _)| *path).collect::<Vec<_>>(),
                    [
                        "payload77",
                        "text",
                        "fields.to.text",
                        "fields.from.text",
                        "fields.class_name",
                        "fields.section",
                    ]
                );
                let capacities = paths.iter().map(|(_, s)| s.capacity()).sum::<usize>();
                let lengths = paths.iter().map(|(_, s)| s.len()).sum::<usize>();
                assert_eq!(retained_record_bytes(record), capacities);
                let layout = string_layout_ledger("cohort_endpoint", "field_day", record);
                assert_eq!(layout["owner_count"], 6);
                assert_eq!(layout["string_lengths_sum"], serde_json::json!(lengths));
                assert_eq!(
                    layout["string_capacities_sum"],
                    serde_json::json!(capacities)
                );
                assert_eq!(
                    layout["inline_decode_bytes"],
                    serde_json::json!(std::mem::size_of::<Decode>())
                );
                let before = (state.available_count(), state.encoded_bytes());
                state
                    .publish_if_new(record, &mut |_| panic!("cohort duplicate cannot publish"))
                    .unwrap();
                assert_eq!((state.available_count(), state.encoded_bytes()), before);
            }
        }
        tables.retain();
    }
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
    period_start: Option<u64>,
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
            // Finite decodes take their windows from frame 0 at a period start.
            period_start: Some(0),
        }
    }
    /// Continuous receive context. The caller resets it on a job/source/gap/history reset.
    pub fn new_live(mode: Mode) -> Self {
        Self {
            live_history: true,
            period_start: None,
            ..Self::new(mode)
        }
    }
    pub fn mode(&self) -> Mode {
        self.mode
    }
    /// The canonical frame of one UTC period start, which places each window's periods;
    /// None when the receive clock does not establish it.
    pub fn set_period_start(&mut self, frame: Option<u64>) {
        self.period_start = frame;
    }
    pub fn period_start(&self) -> Option<u64> {
        self.period_start
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
            reserved_bytes: bytes,
        });
        Ok(())
    }
}
