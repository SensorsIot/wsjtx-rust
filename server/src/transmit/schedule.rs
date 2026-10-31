//! FT8 period scheduling on a virtual UTC clock (integer milliseconds since the epoch).
//! Values follow WSJT-X 3.3.0-beta5: Modulator.cpp (500 ms FT8 audio delay, late-start
//! skip), TxStartPolicy.hpp (start allowed below 75 % of the period) and mainwindow.cpp
//! (even/odd = UTC seconds mod 30 below/above 15).
pub const PERIOD_MS: i64 = 15_000;
pub const AUDIO_DELAY_MS: i64 = 500;
pub const LATEST_START_MS: i64 = PERIOD_MS * 3 / 4;

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

pub fn parity(period_start_ms: i64) -> Parity {
    if period_start_ms.div_euclid(PERIOD_MS) % 2 == 0 {
        Parity::Even
    } else {
        Parity::Odd
    }
}

/// The earliest period of `wanted` parity whose start window is still open at `now_ms`.
pub fn next_period(now_ms: i64, wanted: Parity) -> i64 {
    let mut start = now_ms.div_euclid(PERIOD_MS) * PERIOD_MS;
    if now_ms - start >= LATEST_START_MS {
        start += PERIOD_MS;
    }
    if parity(start) != wanted {
        start += PERIOD_MS;
    }
    start
}

/// Plans the start of a transmission bound to `period_start_ms`; a missed period is
/// refused, never moved to a later one.
pub fn plan_start(
    now_ms: i64,
    clock: ClockState,
    period_start_ms: i64,
    rate_hz: u32,
) -> Result<Start, ScheduleError> {
    if clock != ClockState::Synchronized {
        return Err(ScheduleError::ClockNotSynchronized);
    }
    if period_start_ms.rem_euclid(PERIOD_MS) != 0 {
        return Err(ScheduleError::MisalignedPeriod);
    }
    let elapsed = now_ms - period_start_ms;
    if elapsed >= LATEST_START_MS {
        return Err(ScheduleError::StalePeriod);
    }
    if elapsed <= AUDIO_DELAY_MS {
        return Ok(Start {
            audio_start_ms: period_start_ms + AUDIO_DELAY_MS,
            skipped_samples: 0,
        });
    }
    Ok(Start {
        audio_start_ms: now_ms,
        skipped_samples: (elapsed - AUDIO_DELAY_MS) as u64 * u64::from(rate_hz) / 1000,
    })
}
