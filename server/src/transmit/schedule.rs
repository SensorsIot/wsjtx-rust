//! FT8 and FT4 period scheduling on a virtual UTC clock (integer milliseconds since the
//! epoch). Values follow WSJT-X 3.3.0-beta5: Modulator.cpp (audio delay 500 ms FT8,
//! 300 ms FT4; late-start skip), TxStartPolicy.hpp (start allowed below 75 % of the
//! period) and mainwindow.cpp (TR period 15 s FT8, 7.5 s FT4; even/odd = UTC time mod
//! two periods below/above one period). Unlike WSJT-X, a start is also stale once the
//! waveform's audio would already have ended, so no empty transmission is admitted.
use crate::decoder::Mode;

/// Period length, audio delay and latest admitted start offset (75 % of the period) of `mode`.
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
/// Samples of the whole `mode` waveform at `rate_hz` (FT4 105, FT8 79 symbols).
fn waveform_samples(mode: Mode, rate_hz: u64) -> u64 {
    (mode.symbol_count() * mode.symbol_frames()) as u64 * rate_hz / 12_000
}
/// Elapsed time into the period from which no start is admitted: 75 % of the period
/// or the end of the waveform's audio, whichever is earlier.
fn window_close_ms(mode: Mode) -> i64 {
    let t = timing(mode);
    let audio_end = t.audio_delay_ms + waveform_samples(mode, 1_000) as i64;
    t.latest_start_ms.min(audio_end)
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
    if now_ms - start >= window_close_ms(mode) {
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
    let skipped_samples = (elapsed - t.audio_delay_ms) as u64 * u64::from(rate_hz) / 1000;
    if skipped_samples >= waveform_samples(mode, u64::from(rate_hz)) {
        return Err(ScheduleError::StalePeriod);
    }
    Ok(Start {
        audio_start_ms: now_ms,
        skipped_samples,
    })
}
