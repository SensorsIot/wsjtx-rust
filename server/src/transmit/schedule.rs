//! FT8 and FT4 period scheduling on a virtual UTC clock (integer milliseconds since the
//! epoch). Values follow WSJT-X 3.3.0-beta5: Modulator.cpp (audio delay 500 ms FT8,
//! 300 ms FT4; late-start skip), TxStartPolicy.hpp (start allowed below 75 % of the
//! period) and mainwindow.cpp (TR period 15 s FT8, 7.5 s FT4; even/odd = UTC time mod
//! two periods below/above one period).
use crate::decoder::Mode;

/// Period length, audio delay and latest admitted start offset of `mode`.
struct Timing {
    period_ms: i64,
    audio_delay_ms: i64,
    latest_start_ms: i64,
}
fn timing(mode: Mode) -> Timing {
    let (period_ms, audio_delay_ms) = match mode {
        Mode::Ft8 => (15_000, 500),
        Mode::Ft4 => (7_500, 300),
    };
    Timing {
        period_ms,
        audio_delay_ms,
        latest_start_ms: period_ms * 3 / 4,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ClockState {
    Synchronized,
    Unsynchronized,
    Unknown,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Parity {
    Even,
    Odd,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScheduleError {
    ClockNotSynchronized,
    MisalignedPeriod,
    StalePeriod,
}
/// When playback starts and how many leading waveform samples are skipped.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Start {
    pub audio_start_ms: i64,
    pub skipped_samples: u64,
}

pub fn parity(mode: Mode, period_start_ms: i64) -> Parity {
    if period_start_ms.div_euclid(timing(mode).period_ms) % 2 == 0 {
        Parity::Even
    } else {
        Parity::Odd
    }
}

/// The earliest `mode` period of `wanted` parity whose start window is still open at `now_ms`.
pub fn next_period(mode: Mode, now_ms: i64, wanted: Parity) -> i64 {
    let t = timing(mode);
    let mut start = now_ms.div_euclid(t.period_ms) * t.period_ms;
    if now_ms - start >= t.latest_start_ms {
        start += t.period_ms;
    }
    if parity(mode, start) != wanted {
        start += t.period_ms;
    }
    start
}

/// Plans the start of a `mode` transmission bound to `period_start_ms`; a missed period
/// is refused, never moved to a later one.
pub fn plan_start(
    mode: Mode,
    now_ms: i64,
    clock: ClockState,
    period_start_ms: i64,
    rate_hz: u32,
) -> Result<Start, ScheduleError> {
    let t = timing(mode);
    if clock != ClockState::Synchronized {
        return Err(ScheduleError::ClockNotSynchronized);
    }
    if period_start_ms.rem_euclid(t.period_ms) != 0 {
        return Err(ScheduleError::MisalignedPeriod);
    }
    let elapsed = now_ms - period_start_ms;
    if elapsed >= t.latest_start_ms {
        return Err(ScheduleError::StalePeriod);
    }
    if elapsed <= t.audio_delay_ms {
        return Ok(Start {
            audio_start_ms: period_start_ms + t.audio_delay_ms,
            skipped_samples: 0,
        });
    }
    Ok(Start {
        audio_start_ms: now_ms,
        skipped_samples: (elapsed - t.audio_delay_ms) as u64 * u64::from(rate_hz) / 1000,
    })
}
