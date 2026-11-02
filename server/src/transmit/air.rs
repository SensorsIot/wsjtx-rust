//! #43 WstxTransmit::AirClock: the station's UTC offset estimated from the DT of the
//! stations it decodes, as an alternative or fallback to its SNTP measurement
//! (TransmitClock), and the station clock that combines both by the profile's clock
//! source. The estimate is applied as a station-internal correction of receive window
//! alignment, DT and transmit start; the system clock is never set.
//!
//! The estimate is derived from DT measured against the uncorrected system clock (raw
//! DT), never from DT that already contains the applied correction, so applying it
//! cannot feed back into the next estimate.
use super::ClockState;
use super::clock::{MAX_OFFSET_MS, MAX_STEP_MS, Measurement, Monitor};
use crate::decoder::{CallKind, Fields};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

/// The profile's clock source.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Source {
    #[default]
    Ntp,
    Air,
    Both,
}
impl Source {
    pub fn name(self) -> &'static str {
        match self {
            Self::Ntp => "ntp",
            Self::Air => "air",
            Self::Both => "both",
        }
    }
    pub fn parse(text: &str) -> Option<Self> {
        [Self::Ntp, Self::Air, Self::Both]
            .into_iter()
            .find(|s| s.name() == text)
    }
}

/// Decodes weaker than this carry too little timing information.
pub const MIN_SNR_DB: f64 = -20.0;
/// A raw |DT| above this is implausible (beyond any clock error the station corrects).
pub const MAX_DT_MS: i64 = 3000;
/// Decodes of the last WINDOW_MS of system time form the estimate (8 FT8 periods).
pub const WINDOW_MS: i64 = 120_000;
/// No estimate is derived from fewer distinct stations (never from one or two).
pub const MIN_HEARD: usize = 3;
/// A station whose DT is further than this from the median of all stations is an
/// outlier (a station with a bad clock) and is trimmed.
pub const TRIM_MS: i64 = 400;
/// Confident: at least this many stations agree (inliers) ...
pub const MIN_STATIONS: usize = 4;
/// ... and they are at least this share of the stations heard (percent).
pub const MIN_CONFIDENCE_PCT: u32 = 60;
/// The applied correction follows a confident estimate once they differ by more than this
/// (hysteresis) ...
pub const HYSTERESIS_MS: i64 = 50;
/// ... by at most this much per completed decode window (rate limit): a burst of wrong
/// decodes cannot throw the correction by seconds at once.
pub const MAX_SLEW_MS: i64 = 1000;
/// An estimate not renewed for this long (receive stopped) no longer counts.
pub const MAX_AGE_MS: i64 = 60_000;
/// In Both, NTP and air disagreeing by more than this is a warning.
pub const MAX_DISAGREEMENT_MS: i64 = 200;

/// The air estimate of one evaluation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Estimate {
    /// True UTC minus station system UTC (the sign of an SNTP offset) = -median raw DT.
    pub offset_ms: i64,
    /// Inlier stations the offset is the median of.
    pub stations: usize,
    /// Distinct stations heard in the window.
    pub heard: usize,
    /// stations / heard, percent.
    pub confidence_pct: u32,
}
impl Estimate {
    pub fn confident(&self) -> bool {
        self.stations >= MIN_STATIONS && self.confidence_pct >= MIN_CONFIDENCE_PCT
    }
}

fn median(sorted: &[i64]) -> i64 {
    let n = sorted.len();
    if n % 2 == 1 {
        sorted[n / 2]
    } else {
        (sorted[n / 2 - 1] + sorted[n / 2]).div_euclid(2)
    }
}
/// The robust estimate of (station, raw DT ms) samples: one vote per station (its median
/// DT), stations further than TRIM_MS from the median of all votes trimmed, the offset
/// the negated median of the rest. None below MIN_HEARD distinct stations.
pub fn estimate<'a>(samples: impl IntoIterator<Item = (&'a str, i64)>) -> Option<Estimate> {
    let mut by_station: Vec<(&str, Vec<i64>)> = vec![];
    for (call, dt) in samples {
        match by_station.iter_mut().find(|(c, _)| *c == call) {
            Some((_, v)) => v.push(dt),
            None => by_station.push((call, vec![dt])),
        }
    }
    if by_station.len() < MIN_HEARD {
        return None;
    }
    let mut votes: Vec<i64> = by_station
        .iter_mut()
        .map(|(_, v)| {
            v.sort_unstable();
            median(v)
        })
        .collect();
    votes.sort_unstable();
    let center = median(&votes);
    let inliers: Vec<i64> = votes
        .iter()
        .copied()
        .filter(|v| (v - center).abs() <= TRIM_MS)
        .collect();
    Some(Estimate {
        // A crowd split wider than TRIM_MS around its median has no inliers.
        offset_ms: -median(if inliers.is_empty() { &votes } else { &inliers }),
        stations: inliers.len(),
        heard: votes.len(),
        confidence_pct: (inliers.len() * 100 / votes.len()) as u32,
    })
}

/// The station sending a decoded message, when it names one: the `from` call of the
/// standard families, the full call of a nonstandard CQ.
pub fn sender(fields: &Fields) -> Option<&str> {
    let call = match fields {
        Fields::Standard { from, .. }
        | Fields::FieldDay { from, .. }
        | Fields::Rtty { from, .. }
        | Fields::Vhf { from, .. } => from,
        Fields::Nonstandard { full_call, cq, .. } if *cq => full_call,
        _ => return None,
    };
    (call.kind == CallKind::Call)
        .then_some(call.text.as_deref())
        .flatten()
}

#[derive(Clone, Debug)]
struct Sample {
    system_ms: i64,
    call: String,
    dt_ms: i64,
}
/// The air estimator: decodes of the window, the latest estimate and the applied
/// correction. Times are explicit (monotonic and system ms) so it runs on virtual clocks.
#[derive(Clone, Debug, Default)]
pub struct AirClock {
    samples: VecDeque<Sample>,
    /// (monotonic ms, system ms) of the latest observation, for step detection.
    reference: Option<(i64, i64)>,
    latest: Option<(Estimate, i64)>,
    applied_ms: i64,
}
impl AirClock {
    /// Forgets everything observed when the system clock stepped since the last
    /// observation (the raw DT before and after no longer describe the same clock).
    fn check_step(&mut self, mono_ms: i64, system_ms: i64) {
        if let Some((mono, system)) = self.reference
            && ((system_ms - system) - (mono_ms - mono)).abs() > MAX_STEP_MS
        {
            self.samples.clear();
            self.latest = None;
        }
        self.reference = Some((mono_ms, system_ms));
    }
    /// One decode from `call` with raw DT `dt_ms` and `snr_db`; `own` is the station's
    /// own call (its echo never counts). Returns whether it was admitted.
    pub fn observe(
        &mut self,
        mono_ms: i64,
        system_ms: i64,
        call: &str,
        own: &str,
        dt_ms: i64,
        snr_db: Option<f64>,
    ) -> bool {
        self.check_step(mono_ms, system_ms);
        let own = !own.is_empty() && call.eq_ignore_ascii_case(own);
        if own || dt_ms.abs() > MAX_DT_MS || snr_db.is_none_or(|s| s.is_nan() || s < MIN_SNR_DB) {
            return false;
        }
        self.samples.push_back(Sample {
            system_ms,
            call: call.to_ascii_uppercase(),
            dt_ms,
        });
        true
    }
    /// A decode window completed: re-estimate over the window and, when the estimate is
    /// confident and differs from the applied correction by more than HYSTERESIS_MS,
    /// move the correction toward it by at most MAX_SLEW_MS. Returns whether the applied
    /// correction changed.
    pub fn period_done(&mut self, mono_ms: i64, system_ms: i64) -> bool {
        self.check_step(mono_ms, system_ms);
        while self
            .samples
            .front()
            .is_some_and(|s| system_ms - s.system_ms > WINDOW_MS)
        {
            self.samples.pop_front();
        }
        let e = estimate(self.samples.iter().map(|s| (s.call.as_str(), s.dt_ms)));
        self.latest = e.map(|e| (e, mono_ms));
        match e {
            Some(e) if e.confident() && (e.offset_ms - self.applied_ms).abs() > HYSTERESIS_MS => {
                self.applied_ms += (e.offset_ms - self.applied_ms).clamp(-MAX_SLEW_MS, MAX_SLEW_MS);
                true
            }
            _ => false,
        }
    }
    /// The admitted (station, raw DT ms) observations of the window, oldest first.
    pub fn observed(&self) -> Vec<(String, i64)> {
        self.samples
            .iter()
            .map(|s| (s.call.clone(), s.dt_ms))
            .collect()
    }
    /// The latest estimate and its age.
    pub fn latest(&self, mono_ms: i64) -> Option<(Estimate, i64)> {
        self.latest.map(|(e, at)| (e, mono_ms - at))
    }
    /// The correction applied to station UTC (true minus system, ms).
    pub fn applied_ms(&self) -> i64 {
        self.applied_ms
    }
    /// synchronized: a confident estimate at most MAX_AGE_MS old, with no system clock
    /// step since, that the applied correction matches within MAX_OFFSET_MS (the residual
    /// offset); unsynchronized: confident and recent but the residual is larger; else
    /// unknown (too few stations, low confidence, no recent estimate).
    pub fn state(&self, mono_ms: i64, system_ms: i64) -> ClockState {
        let stepped = self
            .reference
            .is_some_and(|(m, s)| ((system_ms - s) - (mono_ms - m)).abs() > MAX_STEP_MS);
        match self.latest(mono_ms) {
            Some((e, age)) if e.confident() && age <= MAX_AGE_MS && !stepped => {
                if (e.offset_ms - self.applied_ms).abs() <= MAX_OFFSET_MS {
                    ClockState::Synchronized
                } else {
                    ClockState::Unsynchronized
                }
            }
            _ => ClockState::Unknown,
        }
    }
}

/// Which measurement the station clock currently follows.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Basis {
    Ntp,
    Air,
}
/// The station clock state and basis of `source` from the two states: Ntp and Air use
/// their own; Both uses NTP while it is synchronized, else air (synchronized when either
/// is, unsynchronized when either is, else unknown).
pub fn combine(source: Source, ntp: ClockState, air: ClockState) -> (ClockState, Basis) {
    use ClockState::*;
    match source {
        Source::Ntp => (ntp, Basis::Ntp),
        Source::Air => (air, Basis::Air),
        Source::Both if ntp == Synchronized => (Synchronized, Basis::Ntp),
        Source::Both => (
            if air == Synchronized {
                Synchronized
            } else if ntp == Unsynchronized || air == Unsynchronized {
                Unsynchronized
            } else {
                Unknown
            },
            Basis::Air,
        ),
    }
}

/// Everything the clock settings show, read at one instant.
#[derive(Clone, Debug, PartialEq)]
pub struct View {
    pub source: Source,
    pub state: ClockState,
    pub basis: Basis,
    /// The correction applied to station UTC now (0 on the NTP basis).
    pub correction_ms: i64,
    pub ntp_state: ClockState,
    pub ntp: Option<Measurement>,
    pub air_state: ClockState,
    /// The latest air estimate and its age (ms).
    pub air: Option<(Estimate, i64)>,
    pub air_applied_ms: i64,
    /// |NTP offset - air offset| while both a current SNTP measurement and a confident
    /// air estimate exist.
    pub disagreement_ms: Option<i64>,
    /// Both only: the disagreement exceeds MAX_DISAGREEMENT_MS.
    pub warning: bool,
}

struct Inner {
    source: Source,
    own: String,
    air: AirClock,
}
/// The station clock: the SNTP monitor, the air estimator and the profile's source.
pub struct StationClock {
    ntp: Arc<Monitor>,
    origin: Instant,
    inner: Mutex<Inner>,
}
fn system_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as i64)
}
impl StationClock {
    pub fn new(ntp: Arc<Monitor>, source: Source) -> Arc<Self> {
        Arc::new(Self {
            ntp,
            origin: Instant::now(),
            inner: Mutex::new(Inner {
                source,
                own: String::new(),
                air: AirClock::default(),
            }),
        })
    }
    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|p| p.into_inner())
    }
    fn mono_ms(&self) -> i64 {
        self.origin.elapsed().as_millis() as i64
    }
    pub fn ntp(&self) -> &Arc<Monitor> {
        &self.ntp
    }
    pub fn source(&self) -> Source {
        self.lock().source
    }
    pub fn set_source(&self, source: Source) {
        self.lock().source = source;
    }
    /// The profile's call sign, whose own decodes never count.
    pub fn set_own_call(&self, call: &str) {
        let mut i = self.lock();
        if i.own != call {
            i.own = call.into();
        }
    }
    /// One decoded message from `call` with raw DT (against the uncorrected system clock).
    pub fn observe(&self, call: &str, dt_ms: i64, snr_db: Option<f64>) {
        let (mono, system) = (self.mono_ms(), system_ms());
        let mut i = self.lock();
        let Inner { own, air, .. } = &mut *i;
        air.observe(mono, system, call, own, dt_ms, snr_db);
    }
    /// A decode period completed (see AirClock::period_done).
    pub fn period_done(&self) {
        let (mono, system) = (self.mono_ms(), system_ms());
        self.lock().air.period_done(mono, system);
    }
    /// Test seam: replaces the air estimator (virtual-clock fixtures).
    pub fn with_air<T>(&self, f: impl FnOnce(&mut AirClock) -> T) -> T {
        f(&mut self.lock().air)
    }
    pub fn view(&self) -> View {
        let ntp = self.ntp.latest();
        let ntp_state = self.ntp.state();
        let (mono, system) = (self.mono_ms(), system_ms());
        let i = self.lock();
        let air_state = i.air.state(mono, system);
        let (state, basis) = combine(i.source, ntp_state, air_state);
        let air = i.air.latest(mono);
        let disagreement_ms = match (&ntp, air) {
            (Some(m), Some((e, _)))
                if ntp_state != ClockState::Unknown && air_state != ClockState::Unknown =>
            {
                Some((m.offset_ms - e.offset_ms).abs())
            }
            _ => None,
        };
        View {
            source: i.source,
            state,
            basis,
            correction_ms: if basis == Basis::Air {
                i.air.applied_ms()
            } else {
                0
            },
            ntp_state,
            ntp,
            air_state,
            air,
            air_applied_ms: i.air.applied_ms(),
            disagreement_ms,
            warning: i.source == Source::Both
                && disagreement_ms.is_some_and(|d| d > MAX_DISAGREEMENT_MS),
        }
    }
    /// The station clock state for transmit admission.
    pub fn state(&self) -> ClockState {
        self.view().state
    }
    /// The correction added to the system clock for station UTC (receive windows, DT,
    /// transmit start): the applied air correction on the air basis, else 0.
    pub fn correction_ms(&self) -> i64 {
        let i = self.lock();
        let air = match i.source {
            Source::Ntp => false,
            Source::Air => true,
            Source::Both => self.ntp.state() != ClockState::Synchronized,
        };
        if air { i.air.applied_ms() } else { 0 }
    }
}
