//! #43/#92 WstxTransmit::AirClock: the stations heard are the time reference. Station UTC
//! is always the system clock plus a correction from the air; the station keeps itself in
//! the middle of the stations it decodes. There is no source setting and no basis: the
//! SNTP measurement (TransmitClock) only measures the system clock for warnings, it is
//! never applied, and the system clock is never set.
//!
//! The estimate is taken from DT measured against the uncorrected system clock (raw DT)
//! plus the current correction, never from DT already shifted by the windows the
//! correction aligns, so the correction converges to the middle without oscillating.
use super::ClockState;
use super::clock::{MAX_AGE, MAX_STEP_MS, Measurement, Monitor, WindowsTime};
use crate::decoder::{CallKind, Fields};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// Decodes weaker than this carry too little timing information.
pub const MIN_SNR_DB: f64 = -20.0;
/// A raw |DT| above this is implausible (beyond any clock error the station corrects).
pub const MAX_DT_MS: i64 = 3000;
/// Decodes of the last WINDOW_MS of system time form the estimate (8 FT8 periods).
pub const WINDOW_MS: i64 = 120_000;
/// Evidence needs at least this many stations (votes) ...
pub const MIN_STATIONS: usize = 4;
/// ... of which at least this share (percent) lies on one side ...
pub const SAME_SIDE_PCT: usize = 80;
/// ... by more than this (ms).
pub const SIDE_MARGIN_MS: i64 = 100;
/// Evidence moves the correction by at most this much in total within one period.
pub const MAX_SLEW_PER_PERIOD_MS: i64 = 1000;
/// An estimate counts while at most this old (ms) and unstepped.
pub const MAX_AGE_MS: i64 = 60_000;
/// A counting evidence estimate with |median| above this is unsynchronized (Tx refused).
pub const TX_BOUND_MS: i64 = 1000;
/// A correction beyond this after a system clock step restarts at 0.
pub const MAX_STEP_RESTART_MS: i64 = 3000;
/// stations_off: SNTP synchronized and |correction| above this.
pub const STATIONS_OFF_MS: i64 = 500;

/// The air estimate of one completed decode window.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Estimate {
    /// Median of all votes (DT against station UTC), ms.
    pub median_dt_ms: i64,
    /// Votes: distinct stations heard in the window.
    pub stations: usize,
    /// Votes above +SIDE_MARGIN_MS.
    pub plus: usize,
    /// Votes below -SIDE_MARGIN_MS.
    pub minus: usize,
}
impl Estimate {
    /// At least MIN_STATIONS votes and plus or minus at least SAME_SIDE_PCT of them.
    pub fn evidence(&self) -> bool {
        self.stations >= MIN_STATIONS
            && 100 * self.plus.max(self.minus) >= SAME_SIDE_PCT * self.stations
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
/// The estimate of (station, raw DT ms) observations with `correction_ms` applied: one
/// vote per station (the median of its raw DT plus the correction), the median of all
/// votes (no trimming), the votes beyond each side margin. None without a vote.
pub fn estimate<'a>(
    samples: impl IntoIterator<Item = (&'a str, i64)>,
    correction_ms: i64,
) -> Option<Estimate> {
    let mut by_station: Vec<(&str, Vec<i64>)> = vec![];
    for (call, dt) in samples {
        match by_station.iter_mut().find(|(c, _)| *c == call) {
            Some((_, v)) => v.push(dt),
            None => by_station.push((call, vec![dt])),
        }
    }
    if by_station.is_empty() {
        return None;
    }
    let mut votes: Vec<i64> = by_station
        .iter_mut()
        .map(|(_, v)| {
            v.sort_unstable();
            median(v) + correction_ms
        })
        .collect();
    votes.sort_unstable();
    Some(Estimate {
        median_dt_ms: median(&votes),
        stations: votes.len(),
        plus: votes.iter().filter(|v| **v > SIDE_MARGIN_MS).count(),
        minus: votes.iter().filter(|v| **v < -SIDE_MARGIN_MS).count(),
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
    /// (period index of the system clock, |movement| spent in it).
    slewed: Option<(i64, i64)>,
}
impl AirClock {
    /// Forgets everything observed when the system clock stepped by more than 100 ms
    /// since the last observation (the raw DT before and after no longer describe the
    /// same clock) and subtracts the step from a nonzero correction, so station UTC stays
    /// continuous (a step that corrected the system clock leaves 0); a correction of 0
    /// stays 0 (the accepted time is the system clock). A correction beyond
    /// MAX_STEP_RESTART_MS after that restarts at 0.
    fn check_step(&mut self, mono_ms: i64, system_ms: i64) {
        if let Some((mono, system)) = self.reference {
            let step = (system_ms - system) - (mono_ms - mono);
            if step.abs() > MAX_STEP_MS {
                self.samples.clear();
                self.latest = None;
                if self.applied_ms != 0 {
                    self.applied_ms -= step;
                    if self.applied_ms.abs() > MAX_STEP_RESTART_MS {
                        self.applied_ms = 0;
                    }
                }
            }
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
    /// A decode window completed: re-estimate over the last WINDOW_MS and, when the
    /// estimate is evidence, move the correction toward the middle (correction minus the
    /// median) by at most MAX_SLEW_PER_PERIOD_MS in total within the current period of
    /// `period_ms` (the period of the system clock at completion); without evidence the
    /// correction is kept. Returns whether the correction changed.
    pub fn period_done(&mut self, mono_ms: i64, system_ms: i64, period_ms: i64) -> bool {
        self.check_step(mono_ms, system_ms);
        while self
            .samples
            .front()
            .is_some_and(|s| system_ms - s.system_ms > WINDOW_MS)
        {
            self.samples.pop_front();
        }
        let e = estimate(
            self.samples.iter().map(|s| (s.call.as_str(), s.dt_ms)),
            self.applied_ms,
        );
        self.latest = e.map(|e| (e, mono_ms));
        let Some(e) = e.filter(Estimate::evidence) else {
            return false;
        };
        let period = system_ms.div_euclid(period_ms.max(1));
        let spent = match self.slewed {
            Some((p, spent)) if p == period => spent,
            _ => 0,
        };
        let budget = (MAX_SLEW_PER_PERIOD_MS - spent).max(0);
        let movement = (-e.median_dt_ms).clamp(-budget, budget);
        self.slewed = Some((period, spent + movement.abs()));
        self.applied_ms += movement;
        movement != 0
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
    /// The correction applied to station UTC (station minus system, ms).
    pub fn applied_ms(&self) -> i64 {
        self.applied_ms
    }
    /// Never unknown: unsynchronized while the latest estimate counts (at most MAX_AGE_MS
    /// old, no system clock step since) and is evidence with |median| above TX_BOUND_MS;
    /// synchronized otherwise.
    pub fn state(&self, mono_ms: i64, system_ms: i64) -> ClockState {
        let stepped = self
            .reference
            .is_some_and(|(m, s)| ((system_ms - s) - (mono_ms - m)).abs() > MAX_STEP_MS);
        match self.latest(mono_ms) {
            Some((e, age))
                if age <= MAX_AGE_MS
                    && !stepped
                    && e.evidence()
                    && e.median_dt_ms.abs() > TX_BOUND_MS =>
            {
                ClockState::Unsynchronized
            }
            _ => ClockState::Synchronized,
        }
    }
}

/// The clock warning of CL-043-03, the first that holds.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Warning {
    PcClockOff,
    NtpUnreachable,
    StationsOff,
}
impl Warning {
    pub fn name(self) -> &'static str {
        match self {
            Self::PcClockOff => "pc_clock_off",
            Self::NtpUnreachable => "ntp_unreachable",
            Self::StationsOff => "stations_off",
        }
    }
}
/// The warning of CL-043-03 from the SNTP state, the age of the latest valid measurement,
/// whether any SNTP round since start asked a server, and the correction: pc_clock_off
/// while SNTP is unsynchronized; else ntp_unreachable while a round asked and no valid
/// measurement is at most 600 s old (a young measurement covers the step gap; no round
/// yet or an empty server list never asks); else stations_off while SNTP is synchronized
/// and |correction| is above STATIONS_OFF_MS.
pub fn warning(
    ntp: ClockState,
    ntp_age: Option<Duration>,
    asked: bool,
    correction_ms: i64,
) -> Option<Warning> {
    if ntp == ClockState::Unsynchronized {
        Some(Warning::PcClockOff)
    } else if asked && ntp_age.is_none_or(|age| age > MAX_AGE) {
        Some(Warning::NtpUnreachable)
    } else if ntp == ClockState::Synchronized && correction_ms.abs() > STATIONS_OFF_MS {
        Some(Warning::StationsOff)
    } else {
        None
    }
}

/// Everything the clock view shows, read at one instant.
#[derive(Clone, Debug, PartialEq)]
pub struct View {
    /// The station clock: never unknown.
    pub state: ClockState,
    /// The correction applied to station UTC.
    pub correction_ms: i64,
    /// The SNTP state of the system clock (may be unknown) and its latest measurement.
    pub ntp_state: ClockState,
    pub ntp: Option<Measurement>,
    /// The latest air estimate and its age (ms).
    pub air: Option<(Estimate, i64)>,
    pub warning: Option<Warning>,
}

type WindowsTimeReader = Box<dyn Fn() -> WindowsTime + Send + Sync>;
struct Inner {
    own: String,
    air: AirClock,
}
/// The station clock: the air estimator (the reference) and the SNTP monitor (warnings).
pub struct StationClock {
    ntp: Arc<Monitor>,
    origin: Instant,
    inner: Mutex<Inner>,
    windows_time: Mutex<WindowsTimeReader>,
}
fn system_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as i64)
}
impl StationClock {
    pub fn new(ntp: Arc<Monitor>) -> Arc<Self> {
        Arc::new(Self {
            ntp,
            origin: Instant::now(),
            inner: Mutex::new(Inner {
                own: String::new(),
                air: AirClock::default(),
            }),
            windows_time: Mutex::new(Box::new(super::clock::windows_time)),
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
        let Inner { own, air } = &mut *i;
        air.observe(mono, system, call, own, dt_ms, snr_db);
    }
    /// A decode window of a mode with periods of `period_ms` completed (see
    /// AirClock::period_done).
    pub fn period_done(&self, period_ms: i64) {
        let (mono, system) = (self.mono_ms(), system_ms());
        self.lock().air.period_done(mono, system, period_ms);
    }
    /// (monotonic ms since this clock's origin, system ms) now: the time base of
    /// `with_air`, so a fixture can drive the estimator on times consistent with reads.
    pub fn now_ms(&self) -> (i64, i64) {
        (self.mono_ms(), system_ms())
    }
    /// Test seam: the air estimator on explicit clocks.
    pub fn with_air<T>(&self, f: impl FnOnce(&mut AirClock) -> T) -> T {
        f(&mut self.lock().air)
    }
    /// Test seam: replaces the Windows Time service reader.
    pub fn set_windows_time_reader(&self, reader: WindowsTimeReader) {
        *self.windows_time.lock().unwrap_or_else(|p| p.into_inner()) = reader;
    }
    /// The Windows Time service state, read now (no administrator rights needed).
    pub fn windows_time(&self) -> WindowsTime {
        (self.windows_time.lock().unwrap_or_else(|p| p.into_inner()))()
    }
    pub fn view(&self) -> View {
        let ntp = self.ntp.latest();
        let ntp_state = self.ntp.state();
        let asked = self.ntp.asked();
        let (mono, system) = (self.mono_ms(), system_ms());
        let i = self.lock();
        let correction_ms = i.air.applied_ms();
        View {
            state: i.air.state(mono, system),
            correction_ms,
            ntp_state,
            warning: warning(
                ntp_state,
                ntp.as_ref().map(|m| m.taken.elapsed()),
                asked,
                correction_ms,
            ),
            ntp,
            air: i.air.latest(mono),
        }
    }
    /// The station clock state for transmit admission (never unknown).
    pub fn state(&self) -> ClockState {
        let (mono, system) = (self.mono_ms(), system_ms());
        self.lock().air.state(mono, system)
    }
    /// The correction added to the system clock for station UTC (receive windows, DT,
    /// transmit start).
    pub fn correction_ms(&self) -> i64 {
        self.lock().air.applied_ms()
    }
}
