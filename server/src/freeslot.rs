#![forbid(unsafe_code)]
//! WstxStrategy::FreeTxSlot: the free audio slot a strategy run or pounce calls from
//! (#39). Pure: occupied signals, bounds and the current Tx in, a slot out.
use crate::contact::{TX_MIN_HZ, parse_utc, tx_max_hz};
use serde_json::Value;
use std::collections::BTreeSet;
use wstx_rust::decoder::Mode;
use wstx_rust::transmit::{Parity, parity};

#[cfg(test)]
#[path = "freeslot_tests.rs"]
mod tests;

/// The gap to every occupied signal, and the edges my signal stays inside.
const MARGIN_HZ: i64 = 50;
const PASSBAND_HZ: (u32, u32) = (300, 2700);
/// How many decoding periods of my Tx parity count as recent; when these fill the band,
/// fewer are looked at, down to the latest one.
const RECENT_PERIODS: usize = 4;

/// A signal: its frequency (the lowest tone) and its width, in Hz.
pub(crate) type Signal = (u32, u32);

pub(crate) fn width_hz(mode: Mode) -> u32 {
    match mode {
        Mode::Ft8 => 50,
        Mode::Ft4 => 90,
    }
}
/// The lowest and highest slot of `mode`.
pub(crate) fn band(mode: Mode) -> (u32, u32) {
    (
        PASSBAND_HZ.0.max(TX_MIN_HZ),
        (PASSBAND_HZ.1 - width_hz(mode)).min(tx_max_hz(mode)),
    )
}
/// The slot Tx takes and whether it is free: free of the signals of the last RECENT_PERIODS
/// decoding periods of `tx_parity` or, when these fill the band, of fewer, and of the called
/// station. No free slot: `current`, or the nearest slot clear of the called station alone.
pub(crate) fn decide(
    records: &[Value],
    mode: Mode,
    tx_parity: Parity,
    current: u32,
    called: Option<u32>,
) -> (u32, bool) {
    let (bounds, width) = (band(mode), width_hz(mode));
    let station = called.map(|hz| (hz, width));
    let free = (1..=RECENT_PERIODS).rev().find_map(|periods| {
        let mut occupied = recent_signals(records, mode, tx_parity, periods);
        occupied.extend(station);
        choose(&occupied, bounds, width, current, &[])
    });
    match (free, station) {
        (Some(slot), _) => (slot, true),
        (None, Some(station)) => (
            choose(&[station], bounds, width, current, &[]).unwrap_or(current),
            false,
        ),
        (None, None) => (current, false),
    }
}
/// WstxStrategy::StrategyWatchdog: a new slot away from `current`, nearest what the target
/// decodes. No free slot: `current`, not free.
pub(crate) fn decide_away(
    records: &[Value],
    mode: Mode,
    tx_parity: Parity,
    current: u32,
    called: Option<u32>,
    preferred: &[u32],
) -> (u32, bool) {
    let (bounds, width) = (band(mode), width_hz(mode));
    let found = (1..=RECENT_PERIODS).rev().find_map(|periods| {
        let mut occupied = recent_signals(records, mode, tx_parity, periods);
        occupied.push((current, width));
        occupied.extend(called.map(|hz| (hz, width)));
        choose(&occupied, bounds, width, current, preferred)
    });
    (found.unwrap_or(current), found.is_some())
}
/// The signals of the last `periods` periods of `tx_parity` that decoded anything.
fn recent_signals(records: &[Value], mode: Mode, tx_parity: Parity, periods: usize) -> Vec<Signal> {
    let period = |v: &Value| {
        v["period_start_utc"]
            .as_str()
            .and_then(parse_utc)
            .filter(|ms| parity(mode, *ms) == tx_parity)
    };
    let decoding: BTreeSet<i64> = records.iter().filter_map(period).collect();
    let recent: Vec<i64> = decoding.into_iter().rev().take(periods).collect();
    records
        .iter()
        .filter(|v| period(v).is_some_and(|ms| recent.contains(&ms)))
        .filter_map(|v| v["frequency_hz"].as_f64())
        .map(|hz| (hz.round().max(0.0) as u32, width_hz(mode)))
        .collect()
}
/// The free slot nearest `preferred` (when given), then nearest `current`, then the lowest;
/// None when `bounds` hold no free slot. A signal of `width` at a slot must keep MARGIN_HZ
/// from each occupied signal.
pub(crate) fn choose(
    occupied: &[Signal],
    bounds: (u32, u32),
    width: u32,
    current: u32,
    preferred: &[u32],
) -> Option<u32> {
    let (low, high) = (i64::from(bounds.0), i64::from(bounds.1));
    let width = i64::from(width);
    let free = |slot: i64| {
        (low..=high).contains(&slot)
            && occupied.iter().all(|&(hz, w)| {
                let (hz, w) = (i64::from(hz), i64::from(w));
                slot + width + MARGIN_HZ <= hz || slot >= hz + w + MARGIN_HZ
            })
    };
    let current = i64::from(current);
    let preferred: Vec<i64> = preferred.iter().copied().map(i64::from).collect();
    // The nearest free slot to any frequency is that frequency inside the bounds, or an
    // edge of the range an occupied signal forbids, or a bound.
    let edges = occupied.iter().flat_map(|&(hz, w)| {
        let (hz, w) = (i64::from(hz), i64::from(w));
        [hz - width - MARGIN_HZ, hz + w + MARGIN_HZ]
    });
    preferred
        .iter()
        .copied()
        .chain([current])
        .map(|hz| hz.clamp(low, high))
        .chain([low, high])
        .chain(edges)
        .filter(|slot| free(*slot))
        .min_by_key(|slot| {
            let to_preferred = preferred.iter().map(|p| (p - slot).abs()).min();
            (to_preferred, (current - slot).abs(), *slot)
        })
        .map(|slot| slot as u32)
}
