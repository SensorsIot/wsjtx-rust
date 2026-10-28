//! Bounded receive intent and immutable ordinary preferred-frequency facts.
use crate::*;
use std::sync::atomic::{AtomicBool, Ordering};
use wstx_rust::radio_control::{self as cat, actor::Actor};

pub const BANDS: [&str; 12] = [
    "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m", "4m",
];
// Independent source facts pinned in FSD4.7.5, not a translated lookup algorithm.
pub const FREQUENCIES: [(u64, u64); 12] = [
    (1840000, 0),
    (3573000, 3575000),
    (5357000, 5357000),
    (7074000, 7047500),
    (10136000, 10140000),
    (14074000, 14080000),
    (18100000, 18104000),
    (21074000, 21140000),
    (24915000, 24919000),
    (28074000, 28180000),
    (50313000, 50318000),
    (70154000, 0),
];
pub fn frequency(mode: &str, band: &str) -> Option<u64> {
    let pair = FREQUENCIES[*BANDS.iter().position(|b| *b == band).as_ref()?];
    match mode {
        "ft8" => Some(pair.0),
        "ft4" => Some(pair.1),
        _ => None,
    }
    .filter(|n| *n != 0)
}
pub fn band_for(frequency: u64) -> Option<&'static str> {
    let mut rows = BANDS
        .iter()
        .zip(FREQUENCIES)
        .filter(|(_, p)| p.0 == frequency || p.1 == frequency);
    let band = *rows.next()?.0;
    rows.next().is_none().then_some(band)
}
#[derive(Clone, serde::Serialize)]
pub struct Nominal {
    pub mode: &'static str,
    pub band: Option<&'static str>,
    pub nominal_hz: Option<u64>,
    pub origin: &'static str,
    pub confirmed_command_id: Option<String>,
}
#[derive(Clone, PartialEq, Eq, serde::Serialize)]
pub struct Requested {
    pub mode: &'static str,
    pub band: &'static str,
    pub nominal_hz: u64,
}
#[derive(Clone, serde::Serialize)]
pub struct Operation {
    pub command_id: String,
    pub base_revision: u64,
    pub revision: u64,
    pub action: &'static str,
    pub requested: Requested,
    pub phase: &'static str,
    pub result: &'static str,
    pub error: Option<&'static str>,
    pub monitor_before: bool,
    pub monitor_wanted: bool,
    pub old_job_id: Option<String>,
    pub new_job_id: Option<String>,
    #[serde(skip)]
    pub new_generation: Option<u64>,
    #[serde(skip)]
    pub old_generation: u64,
    #[serde(skip)]
    pub new_worker_cancel: Option<Arc<AtomicBool>>,
    #[serde(skip)]
    pub cancelled: Arc<AtomicBool>,
}
#[derive(Clone, serde::Serialize)]
pub struct Cancellation {
    pub command_id: String,
    pub target_command_id: String,
    pub revision: u64,
    pub result: &'static str,
    #[serde(skip)]
    pub expected_revision: u64,
}
pub struct Radio {
    pub actor: Option<Arc<Actor>>,
    pub generation: u64,
    pub connecting: bool,
    pub cached: Option<cat::Snapshot>,
    pub error: Option<&'static str>,
}
impl Radio {
    pub fn new() -> Self {
        Self {
            actor: None,
            generation: 0,
            connecting: false,
            cached: None,
            error: None,
        }
    }
}
pub struct Intent {
    pub command_id: String,
    pub profile_id: String,
    pub boot_id: String,
    pub profile_revision: u64,
    pub generation: u64,
    pub revision: u64,
    pub action: &'static str,
    pub mode: Option<&'static str>,
    pub band: Option<String>,
}
pub struct Operating {
    pub revision: u64,
    pub profile_revision: u64,
    pub nominal: Nominal,
    pub operation: Option<Operation>,
    pub cancellation: Option<Cancellation>,
    pub snapshot_sequence: u64,
    pub last_material: Option<Value>,
    pub boot_at: Instant,
    pub radio: Radio,
}
impl Operating {
    pub fn new() -> Self {
        Self {
            revision: 0,
            profile_revision: 0,
            nominal: Nominal {
                mode: "ft8",
                band: None,
                nominal_hz: None,
                origin: "unknown",
                confirmed_command_id: None,
            },
            operation: None,
            cancellation: None,
            snapshot_sequence: 0,
            last_material: None,
            boot_at: Instant::now(),
            radio: Radio::new(),
        }
    }
    pub fn active(&self) -> bool {
        self.operation
            .as_ref()
            .is_some_and(|o| o.result == "pending" && !o.cancelled.load(Ordering::Acquire))
    }
    pub fn next_revision(&mut self) -> Result<u64, &'static str> {
        if self.revision == profile::MAX_REVISION {
            return Err("counter_exhausted");
        }
        self.revision += 1;
        Ok(self.revision)
    }
}
pub fn state_name(state: cat::State) -> &'static str {
    match state {
        cat::State::Closed => "closed",
        cat::State::Connecting => "connecting",
        cat::State::Ready => "ready",
        cat::State::Closing => "closing",
        cat::State::Unavailable => "unavailable",
    }
}
/// Physical observations from an old saved-context binding are retained as dated
/// facts, but cannot establish readiness for the newly selected configuration.
pub fn bound_snapshot(snapshot: Option<&cat::Snapshot>, revision: u64) -> Option<cat::Snapshot> {
    snapshot.map(|snapshot| {
        let mut value = snapshot.clone();
        if value.authority.profile_revision != revision && value.state == cat::State::Ready {
            value.state = cat::State::Unavailable;
            value.last_error = Some(cat::Error::StaleContext);
        }
        value
    })
}
pub fn radio_error(e: cat::Error) -> &'static str {
    match e {
        cat::Error::Busy => "busy",
        cat::Error::Cancelled => "cancelled",
        cat::Error::Timeout => "radio_timeout",
        cat::Error::Rejected => "radio_rejected",
        cat::Error::ReadbackMismatch => "readback_mismatch",
        cat::Error::FailedClose => "radio_failed_close",
        cat::Error::StaleContext => "state_conflict",
        cat::Error::InvalidRequest | cat::Error::InvalidConfiguration => "invalid_request",
        cat::Error::Unsupported => "selection_unavailable",
        _ => "radio_unavailable",
    }
}
pub fn observation(o: &cat::Observation, at: Instant) -> Value {
    json!({"frequency_hz":o.frequency_hz,"mode":o.mode.map(|m|match m.code {0=>"LSB".into(),1=>"USB".into(),v=>format!("{v:02X}")}),"filter":o.mode.map(|m|m.filter),"data":o.data.map(|d|d.enabled),"data_filter":o.data.map(|d|d.filter),"split":o.split,"rx_tx":o.transmitting.map(|t|if t {"TX"}else{"RX"}),"observed_at_ms":o.observed_at.map(|t|t.saturating_duration_since(at).as_millis() as u64)})
}
pub fn fact<T>(
    fact: &cat::Fact<T>,
    ready: bool,
    at: Instant,
    map: impl FnOnce(&T) -> Value,
) -> Value {
    json!({"value":fact.value.as_ref().map(map),"query_sequence":fact.query_sequence,"observed_at_ms":fact.observed_at.map(|t|t.saturating_duration_since(at).as_millis() as u64),"confirmed":ready&&fact.confirmed})
}
pub fn facts(snapshot: Option<&cat::Snapshot>, at: Instant) -> Value {
    let empty = cat::Facts::default();
    let f = snapshot.map(|s| &s.facts).unwrap_or(&empty);
    let ready = snapshot.is_some_and(|s| s.state == cat::State::Ready);
    json!({"frequency":fact(&f.frequency,ready,at,|v|json!(v)),"mode":fact(&f.mode,ready,at,|v|json!({"mode":match v.code {0=>"LSB".into(),1=>"USB".into(),v=>format!("{v:02X}")},"filter":v.filter})),"data":fact(&f.data,ready,at,|v|json!({"enabled":v.enabled,"filter":v.filter})),"rx_tx":fact(&f.rx_tx,ready,at,|v|json!(if *v {"TX"}else{"RX"})),"split":fact(&f.split,ready,at,|v|json!(v))})
}
