#![forbid(unsafe_code)]
//! WstxStrategy::FreeTxSlot: the quietest Tx slot a strategy or contest run or a pounce calls
//! from (#39 strategydef, operator grill 2026-11-07 Q18, Q30-Q32, Q36, Q39), by waterfall power
//! in my Rx periods. Pure: the power of each candidate, the bounds, the called station and his
//! decoded frequencies in, a slot out. The per-period waterfall power is kept by `Waterfall`,
//! fed by the live receive's detailed rows.
use crate::contact::{TX_MIN_HZ, tx_max_hz};
use serde_json::{Value, json};
use std::collections::VecDeque;
use wstx_rust::decoder::Mode;
use wstx_rust::transmit::{Parity, parity};

#[cfg(test)]
#[path = "freeslot_tests.rs"]
mod tests;

/// FreeTxSlot clearanceHz: the gap to the called station's signal and to his decoded frequencies.
pub(crate) const CLEARANCE_HZ: i64 = 50;
/// FreeTxSlot stepHz: the candidate grid.
pub(crate) const STEP_HZ: u32 = 10;
/// FreeTxSlot periodsPerParity: the counted received periods of one parity that are averaged.
pub(crate) const PERIODS_PER_PARITY: usize = 4;
/// The detailed waterfall's native bin: 12000 Hz over a 4096-point transform (about 2.93 Hz).
pub(crate) const BIN_HZ: f64 = 12000.0 / 4096.0;
/// The upper edge my whole signal stays below (FrequencyControls: FT8 300..2650, FT4 300..2610).
const PASSBAND_TOP_HZ: u32 = 2700;
/// The counted periods kept per live job, both parities together.
const PERIODS_KEPT: usize = 4 * PERIODS_PER_PARITY;

pub(crate) fn width_hz(mode: Mode) -> u32 {
    match mode {
        Mode::Ft8 => 50,
        Mode::Ft4 => 90,
    }
}
/// The lowest and highest slot of `mode`: my whole signal inside the Tx range.
pub(crate) fn band(mode: Mode) -> (u32, u32) {
    (
        300.max(TX_MIN_HZ),
        (PASSBAND_TOP_HZ - width_hz(mode)).min(tx_max_hz(mode)),
    )
}
/// Whether the slot is free at his end (the status's "open at his end").
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum HisEnd {
    /// No frequency he decodes from my Tx parity lies within 50 Hz of the slot.
    Yes,
    /// The slot was chosen although one does: every candidate was within 50 Hz of one.
    No,
    /// He has no such spot, or the feed says nothing (no feed, Use off, no dial).
    Unknown,
}
impl HisEnd {
    pub(crate) fn name(self) -> &'static str {
        match self {
            HisEnd::Yes => "yes",
            HisEnd::No => "no",
            HisEnd::Unknown => "unknown",
        }
    }
}
/// One slot decision: the run's tx_slot {hz, power_db, his_end}.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Slot {
    pub hz: u32,
    /// The whole-dB power of the chosen slot; None before any counted period.
    pub power_db: Option<i64>,
    pub his_end: HisEnd,
}
impl Slot {
    pub(crate) fn json(&self) -> Value {
        json!({"hz":self.hz,"power_db":self.power_db,"his_end":self.his_end.name()})
    }
}
/// My signal of `width` at `f` keeps CLEARANCE_HZ from the called station's signal at `called`.
fn clear_of(f: u32, called: Option<u32>, width: u32) -> bool {
    called.is_none_or(|c| {
        let (f, c, w) = (i64::from(f), i64::from(c), i64::from(width));
        f + w + CLEARANCE_HZ <= c || f >= c + w + CLEARANCE_HZ
    })
}
/// The slot nearest `current`, the lower on a tie.
fn nearest(slots: &[u32], current: u32) -> Option<u32> {
    slots
        .iter()
        .copied()
        .min_by_key(|f| ((i64::from(*f) - i64::from(current)).abs(), *f))
}
/// WstxStrategy::FreeTxSlot choice. Candidates every STEP_HZ and the current Tx inside the Tx
/// range, never within CLEARANCE_HZ of the called station; where his decoded frequencies of my
/// Tx parity are known (`his`), only those at least CLEARANCE_HZ from each (when that leaves
/// none, his end is not used: his_end no). `power` is the power of a slot in dB (None: no counted
/// period); compared in whole dB, the lowest wins, a tie keeps the current Tx when it is among the
/// quietest, else the nearer to it, then the lower. No power: the current Tx, or the nearest
/// candidate when it is too near the called station.
pub(crate) fn quietest(
    mode: Mode,
    current: u32,
    called: Option<u32>,
    his: Option<&[u32]>,
    power: &dyn Fn(u32) -> Option<f64>,
) -> Slot {
    let ((low, high), width) = (band(mode), width_hz(mode));
    let mut candidates: Vec<u32> = (low..=high).step_by(STEP_HZ as usize).collect();
    if (low..=high).contains(&current) && !candidates.contains(&current) {
        candidates.push(current);
    }
    candidates.retain(|f| clear_of(*f, called, width));
    let at_his_end = |f: u32, his: &[u32]| {
        his.iter()
            .all(|o| (i64::from(f) - i64::from(*o)).abs() >= CLEARANCE_HZ)
    };
    let his = his.filter(|h| !h.is_empty());
    let (candidates, his_end) = match his {
        Some(his) => {
            let free: Vec<u32> = candidates
                .iter()
                .copied()
                .filter(|f| at_his_end(*f, his))
                .collect();
            if free.is_empty() {
                (candidates, HisEnd::No)
            } else {
                (free, HisEnd::Yes)
            }
        }
        None => (candidates, HisEnd::Unknown),
    };
    let powers: Option<Vec<(u32, i64)>> = candidates
        .iter()
        .map(|f| power(*f).map(|p| (*f, p.round() as i64)))
        .collect();
    match powers.filter(|p| !p.is_empty()) {
        Some(powers) => {
            let least = powers.iter().map(|p| p.1).min().unwrap_or_default();
            let quietest: Vec<u32> = powers
                .iter()
                .filter(|p| p.1 == least)
                .map(|p| p.0)
                .collect();
            let hz = if quietest.contains(&current) {
                current
            } else {
                nearest(&quietest, current).unwrap_or(current)
            };
            Slot {
                hz,
                power_db: Some(least),
                his_end,
            }
        }
        None => {
            let hz = if (low..=high).contains(&current) && clear_of(current, called, width) {
                current
            } else {
                nearest(&candidates, current).unwrap_or(current)
            };
            let his_end = match his {
                Some(his) if at_his_end(hz, his) => HisEnd::Yes,
                Some(_) => HisEnd::No,
                None => HisEnd::Unknown,
            };
            Slot {
                hz,
                power_db: None,
                his_end,
            }
        }
    }
}

/// One counted received period: its start and the mean level of each detailed bin over its rows.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Period {
    pub start_ms: i64,
    pub levels: Vec<f32>,
}
#[derive(Debug)]
struct Open {
    start_ms: i64,
    period_ms: i64,
    sums: Vec<f64>,
    rows: u32,
    tx: bool,
}
impl Open {
    fn period(&self) -> Option<Period> {
        (!self.tx && self.rows > 0).then(|| Period {
            start_ms: self.start_ms,
            levels: self
                .sums
                .iter()
                .map(|s| (*s / f64::from(self.rows)) as f32)
                .collect(),
        })
    }
}
/// The per-period waterfall power of the live receive (WstxStrategy::FreeTxSlot "Power"): fed
/// with every detailed row, its period and whether it belongs to a Tx period. A period I
/// transmitted in is not counted; a new live job starts empty.
#[derive(Debug, Default)]
pub(crate) struct Waterfall {
    job: Option<(String, u64)>,
    open: Option<Open>,
    closed: VecDeque<Period>,
}
impl Waterfall {
    /// One detailed row of live job `job` in the period starting at `start_ms`.
    pub(crate) fn row(
        &mut self,
        job: (&str, u64),
        start_ms: i64,
        period_ms: i64,
        levels: &[u8],
        tx: bool,
    ) {
        if self
            .job
            .as_ref()
            .is_none_or(|(j, g)| (j.as_str(), *g) != job)
        {
            *self = Self {
                job: Some((job.0.to_owned(), job.1)),
                ..Self::default()
            };
        }
        if self.open.as_ref().is_some_and(|o| o.start_ms != start_ms) {
            self.close();
        }
        let open = self.open.get_or_insert_with(|| Open {
            start_ms,
            period_ms,
            sums: vec![0.0; levels.len()],
            rows: 0,
            tx: false,
        });
        if open.sums.len() < levels.len() {
            open.sums.resize(levels.len(), 0.0);
        }
        for (sum, level) in open.sums.iter_mut().zip(levels) {
            *sum += f64::from(*level);
        }
        open.rows += 1;
        open.tx |= tx;
    }
    fn close(&mut self) {
        if let Some(period) = self.open.take().and_then(|o| o.period()) {
            if self.closed.len() == PERIODS_KEPT {
                self.closed.pop_front();
            }
            self.closed.push_back(period);
        }
    }
    /// The counted periods of `job`, oldest first, with the open one once it has ended at `now_ms`.
    pub(crate) fn periods(&self, job: (&str, u64), now_ms: i64) -> Vec<Period> {
        if self
            .job
            .as_ref()
            .is_none_or(|(j, g)| (j.as_str(), *g) != job)
        {
            return Vec::new();
        }
        let mut out: Vec<Period> = self.closed.iter().cloned().collect();
        if let Some(open) = self
            .open
            .as_ref()
            .filter(|o| o.start_ms + o.period_ms <= now_ms)
            .and_then(Open::period)
        {
            out.push(open);
        }
        out
    }
}
/// The last PERIODS_PER_PARITY periods of `of` that started at or after `since_ms`.
pub(crate) fn recent(periods: &[Period], mode: Mode, of: Parity, since_ms: i64) -> Vec<&Period> {
    let mut out: Vec<&Period> = periods
        .iter()
        .rev()
        .filter(|p| p.start_ms >= since_ms && parity(mode, p.start_ms) == of)
        .take(PERIODS_PER_PARITY)
        .collect();
    out.reverse();
    out
}
/// The power of a slot at `f`: the mean over `periods` of the mean level of the bins in
/// [f, f + width). None without a period or a bin.
pub(crate) fn slot_power(periods: &[&Period], f: u32, width: u32) -> Option<f64> {
    let first = (f64::from(f) / BIN_HZ).ceil() as usize;
    let end = (f64::from(f + width) / BIN_HZ).ceil() as usize;
    let means: Vec<f64> = periods
        .iter()
        .filter_map(|p| {
            let bins = p.levels.get(first..end.min(p.levels.len()))?;
            (!bins.is_empty())
                .then(|| bins.iter().map(|l| f64::from(*l)).sum::<f64>() / bins.len() as f64)
        })
        .collect();
    (!means.is_empty()).then(|| means.iter().sum::<f64>() / means.len() as f64)
}
