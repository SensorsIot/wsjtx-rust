#![forbid(unsafe_code)]
//! WstxStrategy::FreeTxSlot: the quietest Tx slot a strategy or contest run or a pounce calls
//! from (#39 strategydef, operator grill 2026-11-07 Q18, Q30-Q32, Q36, Q39), judged in my Rx
//! periods by each slot's level above the WSJT-X passband floor, clear of the stations decoded in
//! them (#66). Pure: the counted periods and their decodes, the bounds, the called station and his
//! decoded frequencies in, a slot out. The per-period waterfall power is kept by `Waterfall`, fed
//! by the live receive's detailed rows.
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
/// FreeTxSlot periodsPerParity: the last periods of my Rx parity on the clock whose received ones
/// count (#66 "Only if recent").
pub(crate) const PERIODS_PER_PARITY: usize = 4;
/// The detailed waterfall's native bin: 12000 Hz over a 4096-point transform (about 2.93 Hz).
pub(crate) const BIN_HZ: f64 = 12000.0 / 4096.0;
/// FreeTxSlot floorLowHz and floorHighHz: the floor bins are the native bins in [300, 2700) Hz.
const FLOOR_LOW_HZ: f64 = 300.0;
const FLOOR_HIGH_HZ: f64 = 2700.0;
/// The upper edge my whole signal stays below (FrequencyControls: FT8 300..2650, FT4 300..2610).
const PASSBAND_TOP_HZ: u32 = 2700;
/// The counted periods kept per live job and parity, more than the clock's window needs, each
/// parity apart.
const PERIODS_KEPT: usize = 4 * PERIODS_PER_PARITY;
/// Rises of one slot in two periods closer than this are equal, so that the latest counts: the
/// floating-point rounding of the fit, not a threshold of the rule.
const EQUAL_DB: f64 = 1e-6;

pub(crate) fn width_hz(mode: Mode) -> u32 {
    match mode {
        Mode::Ft8 => 50,
        Mode::Ft4 => 90,
    }
}
pub(crate) fn period_ms(mode: Mode) -> i64 {
    match mode {
        Mode::Ft8 => 15_000,
        Mode::Ft4 => 7_500,
    }
}
/// The lowest and highest slot of `mode`: my whole signal inside the Tx range (the open-slot
/// marks, FreeTxSlots, from 300 Hz).
pub(crate) fn band(mode: Mode) -> (u32, u32) {
    (
        300.max(TX_MIN_HZ),
        (PASSBAND_TOP_HZ - width_hz(mode)).min(tx_max_hz(mode)),
    )
}
/// #97 (#90) Auto's candidates start at 500 Hz (WstxStrategy::FreeTxSlot candidateLowHz).
pub(crate) const CANDIDATE_LOW_HZ: u32 = 500;
/// #97 (#90, Q3) a slot whose signal reaches above 2400 Hz loses every tie.
pub(crate) const UPPER_EDGE_HZ: u32 = 2400;
/// Auto's candidate range of `mode`: FT8 500..2650, FT4 500..2610.
pub(crate) fn auto_band(mode: Mode) -> (u32, u32) {
    (CANDIDATE_LOW_HZ, band(mode).1)
}
/// #97 the slot's signal reaches above the upper edge.
fn on_upper_edge(f: u32, width: u32) -> bool {
    f + width > UPPER_EDGE_HZ
}
/// #97 BusyPartner split clearance: my signal at `f` is clear of his at `d` (FT8 100 Hz, FT4
/// 140 Hz between the lower edges: width + 50).
pub(crate) fn split_clear(mode: Mode, f: u32, d: u32) -> bool {
    (i64::from(f) - i64::from(d)).abs() >= i64::from(width_hz(mode)) + CLEARANCE_HZ
}
/// #97 WstxContact::BusyPartner split frequency: FreeTxSlot's grid from 500 Hz inside the Tx range,
/// clear of his signal at `his_signal` (`split_clear`); of them those overlapping no station
/// `decoded` while one is free, and those at least 50 Hz from a frequency his PSK Reporter spots
/// show him decoding in my Tx parity (`his`) while one is free; the nearest to `current`, the lower
/// on a tie. No power is used. None only when no candidate is clear of him.
pub(crate) fn split_target(
    mode: Mode,
    current: u32,
    his_signal: u32,
    decoded: &[f64],
    his: &[u32],
) -> Option<u32> {
    let ((low, high), width) = (auto_band(mode), width_hz(mode));
    let mut list: Vec<u32> = (low..=high)
        .step_by(STEP_HZ as usize)
        .filter(|f| split_clear(mode, *f, his_signal))
        .collect();
    let free: Vec<u32> = list
        .iter()
        .copied()
        .filter(|f| !occupied(*f, decoded, width))
        .collect();
    if !free.is_empty() {
        list = free;
    }
    let at_end: Vec<u32> = list
        .iter()
        .copied()
        .filter(|f| at_his_end(*f, his))
        .collect();
    if !at_end.is_empty() {
        list = at_end;
    }
    nearest(&list, current)
}
/// #97 WstxStrategy::TxMoveRule: another quiet slot. FreeTxSlot's choice (from 500 Hz, clear of
/// every signal in `avoid`, of the decoded stations while one is free) with two exclusions of its
/// own and no fallback: never overlapping the current Tx (|f - tx| below the width), never within
/// 50 Hz of a frequency he decodes in my Tx parity (`his`). None: no candidate left (Tx stays).
pub(crate) fn moved(
    mode: Mode,
    current: u32,
    avoid: &[u32],
    decoded: &[f64],
    his: Option<&[u32]>,
    power: &dyn Fn(u32) -> Option<f64>,
) -> Option<Slot> {
    let ((low, high), width) = (auto_band(mode), width_hz(mode));
    let mut list: Vec<u32> = (low..=high)
        .step_by(STEP_HZ as usize)
        .filter(|f| clear_of_all(*f, avoid, width))
        .filter(|f| (i64::from(*f) - i64::from(current)).abs() >= i64::from(width))
        .collect();
    let free: Vec<u32> = list
        .iter()
        .copied()
        .filter(|f| !occupied(*f, decoded, width))
        .collect();
    if !free.is_empty() {
        list = free;
    }
    let his = his.filter(|h| !h.is_empty());
    if let Some(his) = his {
        list.retain(|f| at_his_end(*f, his));
    }
    if list.is_empty() {
        return None;
    }
    let powers: Option<Vec<(u32, i64)>> = list
        .iter()
        .map(|f| power(*f).map(|p| (*f, compared(p))))
        .collect();
    let (hz, power_db) = match powers {
        Some(powers) => {
            let least = powers.iter().map(|p| p.1).min().unwrap_or_default();
            let quietest: Vec<u32> = powers
                .iter()
                .filter(|p| p.1 == least)
                .map(|p| p.0)
                .collect();
            (pick_tied(&quietest, current, width), Some(least))
        }
        None => (pick_tied(&list, current, width), None),
    };
    Some(Slot {
        hz,
        power_db,
        his_end: his_end_of(hz, his),
    })
}
/// Among equally quiet slots: off the upper edge first, then the current Tx, then nearer it,
/// then lower.
fn pick_tied(quietest: &[u32], current: u32, width: u32) -> u32 {
    let off_edge: Vec<u32> = quietest
        .iter()
        .copied()
        .filter(|f| !on_upper_edge(*f, width))
        .collect();
    let pool = if off_edge.is_empty() {
        quietest
    } else {
        &off_edge
    };
    if pool.contains(&current) {
        current
    } else {
        nearest(pool, current).unwrap_or(current)
    }
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
    /// The whole-dB compared value of the chosen slot (its largest rise above the passband floor
    /// clamped at 0, #66, `compared`); None before any counted period.
    pub power_db: Option<i64>,
    pub his_end: HisEnd,
}
impl Slot {
    pub(crate) fn json(&self) -> Value {
        json!({"hz":self.hz,"power_db":self.power_db,"his_end":self.his_end.name()})
    }
}
/// The compared value of a slot in whole dB: its largest rise above the passband floor clamped
/// at 0 (#66, operator 2026-11-08 "At or under floor = free": a single fourth-order floor cannot
/// follow a sharp receive-filter knee, where slots read below it; at or under the floor a slot is
/// free, never quieter than another free one).
pub(crate) fn compared(rise: f64) -> i64 {
    rise.max(0.0).round() as i64
}
/// My signal of `width` at `f` keeps CLEARANCE_HZ from the called station's signal at `called`.
fn clear_of(f: u32, called: Option<u32>, width: u32) -> bool {
    called.is_none_or(|c| {
        let (f, c, w) = (i64::from(f), i64::from(c), i64::from(width));
        f + w + CLEARANCE_HZ <= c || f >= c + w + CLEARANCE_HZ
    })
}
/// My signal at `f` keeps CLEARANCE_HZ from every signal in `avoid` (the called station, my Rx).
fn clear_of_all(f: u32, avoid: &[u32], width: u32) -> bool {
    avoid.iter().all(|a| clear_of(f, Some(*a), width))
}
/// My signal of `width` at `f` overlaps a station decoded at `decoded` (its audio frequency, the
/// lower edge of its signal): |f - d| below the width (#66 round 1 Q2).
fn occupied(f: u32, decoded: &[f64], width: u32) -> bool {
    decoded
        .iter()
        .any(|d| (f64::from(f) - d).abs() < f64::from(width))
}
/// The slot nearest `current`, the lower on a tie.
fn nearest(slots: &[u32], current: u32) -> Option<u32> {
    slots
        .iter()
        .copied()
        .min_by_key(|f| ((i64::from(*f) - i64::from(current)).abs(), *f))
}
/// WstxStrategy::FreeTxSlot choice. Candidates every STEP_HZ and the current Tx inside the Tx
/// range, never within CLEARANCE_HZ of the called station; while one is free, none overlapping a
/// station `decoded` in the counted periods; where his decoded frequencies of my Tx parity are
/// known (`his`), only those at least CLEARANCE_HZ from each (when that leaves none, his end is
/// not used: his_end no). `power` is the largest rise of a slot in dB (None: no counted
/// period); compared clamped at 0 in whole dB (`compared`), the lowest wins, a tie keeps the current Tx when it is among the
/// quietest, else the nearer to it, then the lower. No power: the current Tx, or the nearest
/// candidate when it is too near the called station.
pub(crate) fn quietest(
    mode: Mode,
    current: u32,
    called: Option<u32>,
    decoded: &[f64],
    his: Option<&[u32]>,
    power: &dyn Fn(u32) -> Option<f64>,
) -> Slot {
    quietest_clear(mode, current, called.as_slice(), decoded, his, power)
}
/// No frequency he decodes from my Tx parity lies within CLEARANCE_HZ of `f`.
fn at_his_end(f: u32, his: &[u32]) -> bool {
    his.iter()
        .all(|o| (i64::from(f) - i64::from(*o)).abs() >= CLEARANCE_HZ)
}
/// The candidates of one FreeTxSlot decision: every STEP_HZ and the current Tx inside the Tx
/// range, clear of every signal in `avoid`; of them those not overlapping a station `decoded` in
/// the counted periods, all of them when that leaves none (#66); among those, where his decoded
/// frequencies are known (`his`), only those free at his end, all of them when that leaves none
/// (his_end no).
fn candidates(
    mode: Mode,
    current: u32,
    avoid: &[u32],
    decoded: &[f64],
    his: Option<&[u32]>,
) -> (Vec<u32>, HisEnd) {
    let ((low, high), width) = (auto_band(mode), width_hz(mode));
    let mut candidates: Vec<u32> = (low..=high).step_by(STEP_HZ as usize).collect();
    if (low..=high).contains(&current) && !candidates.contains(&current) {
        candidates.push(current);
    }
    candidates.retain(|f| clear_of_all(*f, avoid, width));
    let free: Vec<u32> = candidates
        .iter()
        .copied()
        .filter(|f| !occupied(*f, decoded, width))
        .collect();
    if !free.is_empty() {
        candidates = free;
    }
    match his.filter(|h| !h.is_empty()) {
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
    }
}
/// `quietest` keeping clear of every signal in `avoid`: the called station and, with Hold Tx on,
/// my Rx (#39 holdtx, "never to the Rx frequency"). A current Tx outside the Tx range is no
/// candidate (round 3 Q6).
pub(crate) fn quietest_clear(
    mode: Mode,
    current: u32,
    avoid: &[u32],
    decoded: &[f64],
    his: Option<&[u32]>,
    power: &dyn Fn(u32) -> Option<f64>,
) -> Slot {
    let ((low, high), width) = (auto_band(mode), width_hz(mode));
    let his = his.filter(|h| !h.is_empty());
    let (candidates, his_end) = candidates(mode, current, avoid, decoded, his);
    let powers: Option<Vec<(u32, i64)>> = candidates
        .iter()
        .map(|f| power(*f).map(|p| (*f, compared(p))))
        .collect();
    match powers.filter(|p| !p.is_empty()) {
        Some(powers) => {
            let least = powers.iter().map(|p| p.1).min().unwrap_or_default();
            let quietest: Vec<u32> = powers
                .iter()
                .filter(|p| p.1 == least)
                .map(|p| p.0)
                .collect();
            Slot {
                hz: pick_tied(&quietest, current, width),
                power_db: Some(least),
                his_end,
            }
        }
        None => {
            let hz = if (low..=high).contains(&current) && clear_of_all(current, avoid, width) {
                current
            } else {
                nearest(&candidates, current).unwrap_or(current)
            };
            Slot {
                hz,
                power_db: None,
                his_end: his_end_of(hz, his),
            }
        }
    }
}
fn his_end_of(hz: u32, his: Option<&[u32]>) -> HisEnd {
    match his.filter(|h| !h.is_empty()) {
        Some(his) if at_his_end(hz, his) => HisEnd::Yes,
        Some(_) => HisEnd::No,
        None => HisEnd::Unknown,
    }
}
/// Hold Tx on at a selection (a caller of my call as well, also from the run's CQ; #39 holdtx
/// round 1 Q1, Q2, D4, D7): Tx stays, also outside the Tx range, unless the station's signal at
/// `station` (or my Rx) is within CLEARANCE_HZ of it; then the nearest candidate in range clear of
/// both (so also of the decoded stations while one is free, #66 D4), free at his end where known,
/// the lower on a tie, no power used. `power` only names the value of the slot in the status.
pub(crate) fn held(
    mode: Mode,
    current: u32,
    avoid: &[u32],
    decoded: &[f64],
    his: Option<&[u32]>,
    power: &dyn Fn(u32) -> Option<f64>,
) -> Slot {
    let slot = if clear_of_all(current, avoid, width_hz(mode)) {
        Slot {
            hz: current,
            power_db: None,
            his_end: his_end_of(current, his),
        }
    } else {
        quietest_clear(mode, current, avoid, decoded, his, &|_| None)
    };
    Slot {
        power_db: power(slot.hz).map(compared),
        ..slot
    }
}

/// The numbers of one slot of a decision: its largest rise above the passband floor over the
/// counted periods (#66; the compared value is that rise clamped at 0, `compared`), and the level
/// and the floor of that busiest period as measured, in dB.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Numbers {
    pub rise: f64,
    /// The measured level and floor, read by TC-039-010 and TC-039-050; the station uses the rise
    /// only (#82: no per-slot numbers on the wire).
    pub level: f64,
    pub floor: f64,
}
/// WstxStrategy::FreeTxSlots Open (#82): the Tx frequencies f of FreeTxSlot's candidate grid
/// (every STEP_HZ inside the Tx range, `band`) whose compared value is 0 (at or under the floor;
/// None, no counted period, is not 0) and whose signal [f, f + width) overlaps no station
/// `decoded` in a counted period. No other filter, no fallback, no ranking, no limit.
pub(crate) fn open_slots(
    mode: Mode,
    decoded: &[f64],
    value: &dyn Fn(u32) -> Option<f64>,
) -> Vec<u32> {
    let ((low, high), width) = (band(mode), width_hz(mode));
    (low..=high)
        .step_by(STEP_HZ as usize)
        .filter(|f| !occupied(*f, decoded, width) && value(*f).map(compared) == Some(0))
        .collect()
}
/// WstxStrategy::FreeTxSlots Open ranges (#82): the union of the half-open signals [f, f + width)
/// of the ascending open `slots`; overlapping signals join, touching ones stay separate.
pub(crate) fn open_ranges(mode: Mode, slots: &[u32]) -> Vec<(u32, u32)> {
    let width = width_hz(mode);
    let mut ranges: Vec<(u32, u32)> = Vec::new();
    for f in slots {
        match ranges.last_mut() {
            Some((_, hi)) if *f < *hi => *hi = (*hi).max(f + width),
            _ => ranges.push((*f, f + width)),
        }
    }
    ranges
}
/// One received period: its start and the mean level of each detailed bin over its rows.
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
/// The per-period waterfall power of the live receive (WstxStrategy::FreeTxSlot "Counted
/// periods"): fed with every detailed row, its period and whether that period is a Tx period (one
/// I transmitted in, #61), never whether the station was on the air when the row completed (#66:
/// the last rows of a received period complete after PTT is keyed for the next). A period I
/// transmitted in is not kept; a new live job starts empty.
#[derive(Debug, Default)]
pub(crate) struct Waterfall {
    job: Option<(String, u64)>,
    open: Option<Open>,
    /// The received periods of the even and of the odd parity, each oldest first.
    closed: [VecDeque<Period>; 2],
}
impl Waterfall {
    /// One detailed row of live job `job` in the period starting at `start_ms`; `tx`: that period
    /// is a Tx period.
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
        let Some(open) = self.open.take() else {
            return;
        };
        if let Some(period) = open.period() {
            let kept = &mut self.closed
                [usize::from(open.start_ms.div_euclid(open.period_ms.max(1)) % 2 != 0)];
            if kept.len() == PERIODS_KEPT {
                kept.pop_front();
            }
            kept.push_back(period);
        }
    }
    /// The received periods of `job`, oldest first, with the open one once it has ended at
    /// `now_ms`.
    pub(crate) fn periods(&self, job: (&str, u64), now_ms: i64) -> Vec<Period> {
        if self
            .job
            .as_ref()
            .is_none_or(|(j, g)| (j.as_str(), *g) != job)
        {
            return Vec::new();
        }
        let mut out: Vec<Period> = self.closed.iter().flatten().cloned().collect();
        if let Some(open) = self
            .open
            .as_ref()
            .filter(|o| o.start_ms + o.period_ms <= now_ms)
            .and_then(Open::period)
        {
            out.push(open);
        }
        out.sort_by_key(|p| p.start_ms);
        out
    }
}
/// The starts of the last PERIODS_PER_PARITY periods of my Rx parity `rx` on the clock before the
/// period in progress at `now_ms`, the latest first (FT8 the last 2 minutes, FT4 the last minute).
pub(crate) fn recent_starts(mode: Mode, rx: Parity, now_ms: i64) -> Vec<i64> {
    let t = period_ms(mode);
    let mut start = now_ms.div_euclid(t) * t;
    let mut out = Vec::with_capacity(PERIODS_PER_PARITY);
    while out.len() < PERIODS_PER_PARITY {
        start -= t;
        if parity(mode, start) == rx {
            out.push(start);
        }
    }
    out
}
/// The floor bins: the native bins k whose frequency k x BIN_HZ lies in [300, 2700) Hz, (first,
/// last) = (103, 921).
pub(crate) fn floor_bins() -> (usize, usize) {
    (
        (FLOOR_LOW_HZ / BIN_HZ).ceil() as usize,
        (FLOOR_HIGH_HZ / BIN_HZ).ceil() as usize - 1,
    )
}
/// WstxStrategy::FreeTxSlot Floor: the WSJT-X passband floor of one period's mean levels (dB per
/// native bin) over the floor bins, in dB per bin (the WSJT-X decoder baseline: ten segments of
/// 81 bins from bin 103, the points at or below each segment's 8th lowest level, a fourth-order
/// least-squares fit plus 0.65 dB). None when the levels do not reach the last floor bin
/// (Coverage), or where the baseline has none.
pub(crate) fn passband_floor(levels: &[f32]) -> Option<Vec<f64>> {
    let (first, last) = floor_bins();
    if levels.len() <= last {
        return None;
    }
    let power: Vec<f64> = levels
        .iter()
        .map(|l| 10f64.powf(f64::from(*l) / 10.0))
        .collect();
    let floor = wstx_rust::decoder::passband_baseline(&power, first, last)?;
    Some(floor.iter().map(|p| 10.0 * p.log10()).collect())
}
/// One counted period of a decision, with its passband floor.
#[derive(Debug)]
pub(crate) struct Counted<'a> {
    pub period: &'a Period,
    pub floor: Vec<f64>,
}
/// What one slot decision judges (WstxStrategy::FreeTxSlot Parity, Counted periods, Floor,
/// Value, decoded stations): the counted periods, my Rx parity's received periods among its last
/// PERIODS_PER_PARITY on the clock, from a band change on, with a floor; and the stations decoded
/// in them.
#[derive(Debug)]
pub(crate) struct Judged<'a> {
    mode: Mode,
    counted: Vec<Counted<'a>>,
    decoded: Vec<f64>,
}
impl<'a> Judged<'a> {
    /// `periods` the received periods of the live job and `decodes` its decodes (period start,
    /// audio frequency); my Rx parity `rx`, from `since_ms` on (a station band change), at the
    /// decision's station time `now_ms`.
    pub(crate) fn new(
        periods: &'a [Period],
        mode: Mode,
        rx: Parity,
        since_ms: i64,
        now_ms: i64,
        decodes: &[(i64, f64)],
    ) -> Self {
        let starts = recent_starts(mode, rx, now_ms);
        let mut counted: Vec<Counted<'a>> = periods
            .iter()
            .filter(|p| p.start_ms >= since_ms && starts.contains(&p.start_ms))
            .filter_map(|p| passband_floor(&p.levels).map(|floor| Counted { period: p, floor }))
            .collect();
        counted.sort_by_key(|c| c.period.start_ms);
        let decoded = decodes
            .iter()
            .filter(|(start, _)| counted.iter().any(|c| c.period.start_ms == *start))
            .map(|(_, hz)| *hz)
            .collect();
        Self {
            mode,
            counted,
            decoded,
        }
    }
    /// The number of counted periods (FreeTxSlots periods now).
    pub(crate) fn count(&self) -> usize {
        self.counted.len()
    }
    /// The audio frequencies of the stations decoded in the counted periods.
    pub(crate) fn decoded(&self) -> &[f64] {
        &self.decoded
    }
    /// The numbers of a slot at `f` covering [f, f + width): in each counted period its level (the
    /// mean level of its bins), its floor (the mean of the floor over the same bins) and its rise
    /// (level - floor); the period with the largest rise counts, of equal rises the latest. None
    /// without a counted period.
    pub(crate) fn numbers(&self, f: u32) -> Option<Numbers> {
        let width = width_hz(self.mode);
        let first = (f64::from(f) / BIN_HZ).ceil() as usize;
        let end = (f64::from(f + width) / BIN_HZ).ceil() as usize;
        let mean = |v: &mut dyn Iterator<Item = f64>| {
            let (sum, n) = v.fold((0.0, 0usize), |(s, n), x| (s + x, n + 1));
            (n > 0).then(|| sum / n as f64)
        };
        let mut best: Option<Numbers> = None;
        for c in &self.counted {
            let (Some(levels), Some(floor)) =
                (c.period.levels.get(first..end), c.floor.get(first..end))
            else {
                continue;
            };
            let (Some(level), Some(floor)) = (
                mean(&mut levels.iter().map(|l| f64::from(*l))),
                mean(&mut floor.iter().copied()),
            ) else {
                continue;
            };
            let n = Numbers {
                rise: level - floor,
                level,
                floor,
            };
            if best.is_none_or(|b| n.rise > b.rise - EQUAL_DB) {
                best = Some(n);
            }
        }
        best
    }
}
fn parity_name(of: Parity) -> &'static str {
    match of {
        Parity::Even => "even",
        Parity::Odd => "odd",
    }
}
/// The value of one build (#82 WstxStrategy::FreeTxSlots, WstxMcp::AutomationWire
/// free_tx_slots): {at_utc_ms, mode, rx_parity, qso, periods (the counted number), open [[lo_hz,
/// hi_hz], ...]}, no per-slot numbers.
pub(crate) fn value(
    at_utc_ms: i64,
    mode: Mode,
    rx: Parity,
    qso: bool,
    periods: usize,
    open: &[(u32, u32)],
) -> Value {
    let mode = match mode {
        Mode::Ft8 => "ft8",
        Mode::Ft4 => "ft4",
    };
    let open: Vec<[u32; 2]> = open.iter().map(|(lo, hi)| [*lo, *hi]).collect();
    json!({"at_utc_ms":at_utc_ms,"mode":mode,"rx_parity":parity_name(rx),"qso":qso,
        "periods":periods,"open":open})
}
