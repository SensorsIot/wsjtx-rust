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
/// How many decoding periods of my Tx parity count as recent.
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
/// The signals of the last RECENT_PERIODS periods of `tx_parity` that decoded anything.
pub(crate) fn recent_signals(records: &[Value], mode: Mode, tx_parity: Parity) -> Vec<Signal> {
    let period = |v: &Value| {
        v["period_start_utc"]
            .as_str()
            .and_then(parse_utc)
            .filter(|ms| parity(mode, *ms) == tx_parity)
    };
    let periods: BTreeSet<i64> = records.iter().filter_map(period).collect();
    let recent: Vec<i64> = periods.into_iter().rev().take(RECENT_PERIODS).collect();
    records
        .iter()
        .filter(|v| period(v).is_some_and(|ms| recent.contains(&ms)))
        .filter_map(|v| v["frequency_hz"].as_f64())
        .map(|hz| (hz.round().max(0.0) as u32, width_hz(mode)))
        .collect()
}
/// The free slot nearest `preferred` (when given), then nearest `current`, then the lowest;
/// None when `bounds` hold no free slot. A signal of `width` at a slot must keep MARGIN_HZ
/// from each occupied signal. The later #39 slice that retries "on a different slot near
/// what the target decodes" passes those frequencies as `preferred` and the slot it leaves
/// as occupied.
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
