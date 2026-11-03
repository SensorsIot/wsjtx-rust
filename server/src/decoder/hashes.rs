//! The station's call hash table (WstxOfflineDecode::HashResolution, CL-024-01, #24 S1):
//! WSJT-X 3.3.0-beta5 packjt77.f90 save_hash_call, hash10/12/22 and hashmy10/12/22. One
//! table per station instance, fed by decoded and transmitted calls and by my own call;
//! the pure `unpack` never uses one.
use super::payload::{CallKind, Fields, Payload, PayloadStatus, unpack_with};
use std::collections::{HashMap, VecDeque};

/// MAXHASH of packjt77.f90: entries of the 22-bit list.
pub const MAX_HASH22: usize = 1000;
const BASE38: &[u8] = b" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ/";

/// ihashcall: the top `m` bits of the low 64 bits of 47055833459 times the base-38 value
/// of the call's first 11 characters, blank padded. None for a character outside base 38.
pub fn ihashcall(call: &str, m: u32) -> Option<u32> {
    let mut n = 0u64;
    for i in 0..11 {
        let c = call.as_bytes().get(i).copied().unwrap_or(b' ');
        n = n * 38 + BASE38.iter().position(|&a| a == c)? as u64;
    }
    Some((n.wrapping_mul(47_055_833_459) >> (64 - m)) as u32)
}

#[derive(Clone, Debug, Default)]
pub struct HashTable {
    calls10: HashMap<u32, String>,
    calls12: HashMap<u32, String>,
    /// (h22, call), most recently added first.
    calls22: VecDeque<(u32, String)>,
    /// My call and its 10/12/22-bit hashes.
    my: Option<(String, u32, u32, u32)>,
    /// The current contact's DX call (dxcall13), for unpack77's DX-call rule.
    dx: Option<String>,
}

impl HashTable {
    pub fn new() -> Self {
        Self::default()
    }
    /// Sets my call (the profile callsign); a new call of at least 3 characters is
    /// saved as unpack77 does when mycall13 changes. None or a shorter call clears it.
    pub fn set_my_call(&mut self, call: Option<&str>) {
        let call = call.map(|c| c.trim().to_ascii_uppercase());
        if call.as_deref() == self.my.as_ref().map(|m| m.0.as_str()) {
            return;
        }
        self.my = None;
        let Some(call) = call.filter(|c| c.len() > 2) else {
            return;
        };
        let (Some(h10), Some(h12), Some(h22)) = (
            ihashcall(&call, 10),
            ihashcall(&call, 12),
            ihashcall(&call, 22),
        ) else {
            return;
        };
        self.my = Some((call.clone(), h10, h12, h22));
        self.save(&call);
    }
    /// The current contact's DX call (None without a partner); calls of at most 2
    /// characters count as none, as in unpack77.
    pub fn set_dx_call(&mut self, call: Option<&str>) {
        self.dx = call
            .map(|c| c.trim().to_ascii_uppercase())
            .filter(|c| c.len() > 2);
    }
    pub fn dx_call(&self) -> Option<&str> {
        self.dx.as_deref()
    }
    pub fn my_call(&self) -> Option<&str> {
        self.my.as_ref().map(|m| m.0.as_str())
    }
    /// save_hash_call: brackets removed, at least 3 characters; calls10/12 skip my call;
    /// the 22-bit list updates an existing hash, else puts the call first.
    pub fn save(&mut self, call: &str) {
        let call = call.trim();
        if call.is_empty() || call.starts_with("<...>") {
            return;
        }
        let call = call.strip_prefix('<').unwrap_or(call);
        let call = call.split('>').next().unwrap_or("").trim();
        if call.len() < 3 {
            return;
        }
        let (Some(h10), Some(h12), Some(h22)) = (
            ihashcall(call, 10),
            ihashcall(call, 12),
            ihashcall(call, 22),
        ) else {
            return;
        };
        if self.my_call() != Some(call) {
            self.calls10.insert(h10, call.to_owned());
            self.calls12.insert(h12, call.to_owned());
        }
        if let Some(entry) = self.calls22.iter_mut().find(|(h, _)| *h == h22) {
            entry.1 = call.to_owned();
            return;
        }
        if self.calls22.len() == MAX_HASH22 {
            self.calls22.pop_back();
        }
        self.calls22.push_front((h22, call.to_owned()));
    }
    pub(crate) fn lookup10(&self, n: u32) -> Option<String> {
        self.calls10.get(&n).cloned()
    }
    pub(crate) fn lookup12(&self, n: u32) -> Option<String> {
        self.calls12.get(&n).cloned()
    }
    pub(crate) fn lookup22(&self, n: u32) -> Option<String> {
        self.calls22
            .iter()
            .find(|(h, _)| *h == n)
            .map(|(_, c)| c.clone())
    }
    /// My call when `n` is its `bits`-wide hash (hashmy10/12/22).
    pub(crate) fn mine(&self, bits: u8, n: u32) -> Option<String> {
        let (call, h10, h12, h22) = self.my.as_ref()?;
        (match bits {
            10 => *h10,
            12 => *h12,
            _ => *h22,
        } == n)
            .then(|| call.clone())
    }
    /// The payload as received (unpack77 nrx=1) with this table's calls filled in.
    pub fn resolve(&self, payload: &Payload) -> Payload {
        if payload.status != PayloadStatus::Decoded
            || !payload.text.as_ref().is_some_and(|t| t.contains("<...>"))
        {
            return payload.clone();
        }
        let mut bits = [0u8; 77];
        for (b, c) in bits.iter_mut().zip(payload.payload77.bytes()) {
            *b = u8::from(c == b'1');
        }
        unpack_with(&bits, Some(self))
    }
    /// The calls a received payload teaches (unpack77 nrx=1, not configured): the
    /// concrete 'from' call of a standard message, the full call of a nonstandard
    /// message whose hash is the 'to' call.
    pub fn learn(&mut self, payload: &Payload) {
        match &payload.fields {
            Some(Fields::Standard { from, .. }) if from.kind == CallKind::Call => {
                if let Some(c) = &from.text {
                    self.save(c);
                }
            }
            Some(Fields::Nonstandard {
                full_call,
                hash_second: false,
                ..
            }) => {
                if let Some(c) = &full_call.text {
                    self.save(c);
                }
            }
            _ => {}
        }
    }
    /// The calls a transmitted message teaches (pack28/pack77_hash_index): every
    /// concrete call of a standard (its base call, without /R or /P, as
    /// pack77_parse_type12_call stages it), Field Day or RTTY message, the full call of
    /// a nonstandard CQ and every bracketed `<CALL>` of the text.
    pub fn learn_sent(&mut self, payload: &Payload, text: &str) {
        let concrete =
            |c: &super::Call| (c.kind == CallKind::Call).then(|| c.text.clone()).flatten();
        let calls: Vec<String> = match &payload.fields {
            Some(
                Fields::Standard { to, from, .. }
                | Fields::FieldDay { to, from, .. }
                | Fields::Rtty { to, from, .. },
            ) => [to, from]
                .into_iter()
                .filter_map(concrete)
                .map(
                    |c| match c.strip_suffix("/R").or_else(|| c.strip_suffix("/P")) {
                        Some(base) if matches!(payload.fields, Some(Fields::Standard { .. })) => {
                            base.to_owned()
                        }
                        _ => c,
                    },
                )
                .collect(),
            Some(Fields::Nonstandard {
                full_call,
                cq: true,
                ..
            }) => full_call.text.iter().cloned().collect(),
            _ => Vec::new(),
        };
        for c in calls {
            self.save(&c);
        }
        for w in text.split_whitespace() {
            if let Some(body) = w.strip_prefix('<').and_then(|w| w.strip_suffix('>'))
                && w.len() <= 13
                && body.len() >= 3
                && !body.contains(['<', '>'])
                && body != "..."
            {
                self.save(body);
            }
        }
    }
}
