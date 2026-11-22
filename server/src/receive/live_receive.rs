//! Live receive: the decode windows, record timing, period views and transmit periods.

use super::*;

impl Recording {
    /// The station clock correction in 100 ns: 0 without a station clock.
    pub(crate) fn clock_correction(&self) -> i128 {
        self.clock
            .get()
            .map_or(0, |c| i128::from(c.station.correction_ms()) * 10_000)
    }
    /// The latest Rx level while audio runs and the station receives
    /// (WstxLiveReceive::RxLevel), else None: never while on the air or in the rest of a Tx period
    /// (CL-061-04; the live worker resets the measurement there).
    pub(crate) fn rx_level(&self) -> Option<i32> {
        if self.observe_transmit() {
            return None;
        }
        let s = self.state.lock().unwrap();
        let l = s.live.as_ref()?;
        if l.audio.state == audio::AudioState::Running {
            l.level.3
        } else {
            None
        }
    }
    /// Reads the transmit owner's on-air state without waiting for it and records the
    /// Tx period; returns whether the station is on the air (the last known state while the
    /// owner is busy). Never called under the station mutex.
    pub(crate) fn observe_transmit(&self) -> bool {
        let period = if self.operating_mode() == "ft4" {
            7500
        } else {
            15000
        };
        let observed = self.transmit.get().and_then(|t| {
            t.service.try_with(|c| {
                let (keyed, last) = c.on_air();
                (c.hardware().now_utc_ms(), keyed, last)
            })
        });
        let mut tx = self.tx.lock().unwrap_or_else(|p| p.into_inner());
        if let Some((now, keyed, last)) = observed {
            tx.note(now, keyed, last, period);
        }
        tx.keyed
    }
    /// Whether the UTC period holding canonical `frame` of this live receive is a Tx
    /// period (false without a correlated clock).
    fn tx_period_at(&self, l: &LiveState, frame: u64) -> bool {
        let drift = l.capture_drift.map_or(0, |(d, _)| d) + l.clock_correction;
        period_start_ms(l.timing.as_ref(), l.mode, frame, drift).is_some_and(|start| {
            self.tx
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .contains(start)
        })
    }
    /// Whether the analysis window `interval` belongs to a Tx period (the period
    /// publish_view selects for it).
    fn tx_window(&self, interval: (u64, u64)) -> bool {
        let s = self.state.lock().unwrap();
        let Some(l) = s.live.as_ref() else {
            return false;
        };
        window_slot(l, interval).is_some_and(|(_, slot)| {
            self.tx
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .contains(unix_ms(slot))
        })
    }
    /// The latest receive publication (id, first_sequence, next_sequence, complete,
    /// period_start_utc).
    pub(crate) fn latest_publication(&self) -> crate::automation::Publication {
        let s = self.state.lock().unwrap();
        s.latest_decode.as_ref().map(|d| {
            (
                d.id,
                d.first_sequence,
                d.next_sequence,
                d.complete,
                d.period_start_utc.clone(),
            )
        })
    }
    /// (decoding now, windows begun) of the live decoder, for the UDP Status.
    pub(crate) fn decoder_activity(&self) -> (bool, u64) {
        let s = self.state.lock().unwrap_or_else(|p| p.into_inner());
        (s.decoding, s.decode_windows)
    }
    /// Marks the start of one analysis window's decode; the returned guard ends it when
    /// dropped (also on an abandoned, failed or cancelled decode). WSJT-X
    /// MainWindow::beginDecode / endDecode.
    pub(crate) fn begin_window_decode(self: &Arc<Self>) -> WindowDecode {
        let mut s = self.state.lock().unwrap_or_else(|p| p.into_inner());
        s.decoding = true;
        s.decode_windows = s.decode_windows.wrapping_add(1);
        WindowDecode(self.clone())
    }
    pub(super) fn publish_latest_decode(
        &self,
        context: &Job,
        interval: (u64, u64),
        first: u64,
        complete: bool,
        late: bool,
    ) -> Result<()> {
        self.publish_view(context, interval, first, complete, late, false)
    }
    /// Publishes the latest view of the window `interval`; `transmitted` (CL-061-04)
    /// publishes its period as a Tx period: no attempt, no records, not complete.
    fn publish_view(
        &self,
        context: &Job,
        interval: (u64, u64),
        first: u64,
        complete: bool,
        late: bool,
        transmitted: bool,
    ) -> Result<()> {
        let mut s = self.state.lock().unwrap();
        if context.cancel.load(Ordering::Acquire)
            || !s.job.as_ref().is_some_and(|j| {
                j.id == context.id
                    && j.generation == context.generation
                    && j.source_id == context.source_id
                    && j.state == "running"
            })
        {
            return Ok(());
        }
        let l = s.live.as_ref().ok_or("state_conflict")?;
        let period = if l.timing.as_ref().is_some_and(|t| t.correlated) {
            let (Some((begin, slot)), Some((_, nominal, _))) =
                (window_slot(l, interval), period_parameters(l.mode))
            else {
                return Ok(());
            };
            // A scheduled late window begins after its period's nominal start and republishes
            // that period's view, now including its late starters.
            if slot + nominal < begin && !late {
                return Ok(());
            }
            Some(
                utc_from_filetime(u64::try_from(slot).map_err(|_| "decode_limit")?)
                    .ok_or("decode_limit")?,
            )
        } else {
            None
        };
        if let (Some(previous), Some(next)) = (
            s.latest_decode
                .as_ref()
                .and_then(|v| v.period_start_utc.as_ref()),
            period.as_ref(),
        ) && next < previous
        {
            return Ok(());
        }
        let (first_sequence, next_sequence) = if transmitted {
            (l.next_sequence, l.next_sequence)
        } else if let Some(period) = period.as_ref() {
            let mut matching = l
                .records
                .iter()
                .filter(|(r, _)| r["period_start_utc"].as_str() == Some(period));
            if let Some((record, _)) = matching.next() {
                let first = record["sequence"].as_u64().ok_or("decode_limit")?;
                let last = matching
                    .next_back()
                    .map(|(r, _)| r["sequence"].as_u64().unwrap())
                    .unwrap_or(first);
                (first, last + 1)
            } else {
                (l.next_sequence, l.next_sequence)
            }
        } else {
            (first.max(l.first_sequence), l.next_sequence)
        };
        // A later window of the same period (the scheduled late window) extends that period's
        // view under the same id: an unchanged view publishes nothing, a grown one only moves
        // next_sequence, so clients keep their rows and cursor.
        if let Some(view) = s.latest_decode.as_mut().filter(|v| {
            period.is_some() && v.period_start_utc == period && v.first_sequence == first_sequence
        }) && next_sequence >= view.next_sequence
        {
            view.next_sequence = next_sequence;
            view.complete |= complete;
            view.transmitted |= transmitted;
            self.publication.send_modify(|n| *n = n.wrapping_add(1));
            return Ok(());
        }
        let id = s
            .decode_counter
            .checked_add(1)
            .filter(|id| *id <= source::MAX_COUNTER)
            .ok_or("counter_exhausted")?;
        s.decode_counter = id;
        s.latest_decode = Some(LatestDecode {
            id,
            first_sequence,
            next_sequence,
            period_start_utc: period,
            complete,
            transmitted,
        });
        self.publication.send_modify(|n| *n = n.wrapping_add(1));
        Ok(())
    }
}
impl LiveWorker {
    pub(super) fn step(&mut self) -> Result<Option<receive::AnalysisWindow>> {
        let event = self.input.poll();
        {
            let mut s = self.owner.state.lock().unwrap();
            if let Some(l) = s.live.as_mut() {
                l.audio = self.input.status();
            }
        }
        match event {
            SourcePoll::EpochChanged(p) => {
                self.epoch(p)?;
                Ok(None)
            }
            SourcePoll::Block(block) => {
                let outcome = self
                    .window
                    .as_mut()
                    .map(|w| w.push(&block))
                    .transpose()
                    .map_err(window_error)?;
                let frames = self.spectrum.push(&block)?;
                let drift = self.track_clock(block.timing.as_deref());
                // Read the transmit owner before the station mutex.
                let keyed = self.owner.observe_transmit();
                let mut s = self.owner.state.lock().unwrap();
                if !self.current() {
                    return Err("cancelled");
                }
                let j = s
                    .job
                    .as_mut()
                    .filter(|j| j.id == self.job.id && j.generation == self.job.generation)
                    .ok_or("state_conflict")?;
                j.processed_frames = outcome
                    .as_ref()
                    .map(|o| o.captured_next_frame)
                    .unwrap_or(block.first_frame + block.samples.len() as u64);
                let next = j.processed_frames;
                let gap_reset = outcome.as_ref().is_some_and(|o| o.reset_decoder);
                if gap_reset {
                    s.latest_decode = None;
                }
                let l = s.live.as_mut().ok_or("state_conflict")?;
                if let Some(drift) = drift {
                    l.capture_drift = Some(drift);
                }
                l.clock_correction = self.air;
                l.next_frame = next;
                // CL-061-04: no Rx level while on the air or in the rest of a Tx period;
                // the measurement restarts in the next receive period.
                if keyed || self.owner.tx_period_at(l, next) {
                    l.level = (0.0, 0, None, None);
                } else {
                    l.accumulate_level(&block.samples, Instant::now());
                }
                // WstxHoldTx::SlotLevel: each row's period, for the per-period power, and
                // whether that period is a Tx period. The row's mark also holds while on the
                // air, which the per-period power must not use: a detailed row completes 0.4 s
                // after its middle (its last 4096-point transform), so keying PTT at a Tx period's
                // start marks the last 2 rows of the received period before it.
                let drift = l.capture_drift.map_or(0, |(d, _)| d) + l.clock_correction;
                let period_ms = if l.mode == "ft4" { 7500 } else { 15000 };
                let tx_rows = frames
                    .iter()
                    .flatten()
                    .map(|row| {
                        let middle = (row.first + row.end) / 2;
                        let tx_period = self.owner.tx_period_at(l, middle);
                        (
                            keyed || tx_period,
                            tx_period,
                            period_start_ms(l.timing.as_ref(), l.mode, middle, drift),
                        )
                    })
                    .collect::<Vec<_>>();
                self.reset |= outcome.as_ref().is_some_and(|o| o.reset_decoder);
                if self.reset {
                    self.modem = None;
                }
                for (
                    SpectrumRow {
                        first,
                        end,
                        levels,
                        detailed,
                    },
                    (tx, tx_period, period),
                ) in frames.into_iter().flatten().zip(tx_rows)
                {
                    if detailed && let Some(start) = period {
                        self.owner
                            .waterfall
                            .lock()
                            .unwrap_or_else(|p| p.into_inner())
                            .row(
                                (&self.job.id, self.job.generation),
                                start,
                                period_ms,
                                &levels,
                                tx_period,
                            );
                    }
                    let row_frames = if detailed {
                        spectrum::ROW_FRAMES
                    } else {
                        12000
                    };
                    let sequence = first / row_frames;
                    let kind = if detailed {
                        "spectrum.detail.frame"
                    } else {
                        "spectrum.frame"
                    };
                    let mut frame = json!({"v":1,"type":kind,"data":{"boot_id":self.owner.boot,
                        "source_id":self.job.source_id,"job_id":self.job.id,"generation":self.job.generation,
                        "sequence":sequence,"first_frame":first,"end_frame":end,"levels_b64":STANDARD.encode(&levels)}});
                    // CL-061-04: a row of a Tx period is marked; the key is present only then.
                    if tx {
                        frame["data"]["tx"] = json!(true);
                    }
                    if detailed {
                        push_detail(&mut s, frame);
                    } else {
                        let mut frame = frame;
                        frame["data"].as_object_mut().unwrap().remove("levels_b64");
                        frame["data"]["levels"] = json!(levels);
                        s.frame = Some(frame);
                    }
                }
                Ok(if self.mode.is_some() {
                    outcome.and_then(|o| o.window)
                } else {
                    None
                })
            }
            SourcePoll::Failed(source::SourceError::Unavailable) => {
                self.window = None;
                self.modem = None;
                self.reset = true;
                let mut s = self.owner.state.lock().unwrap();
                if !self.current() {
                    return Err("cancelled");
                }
                if self.job.source_id.is_some() {
                    let generation = s
                        .generation
                        .checked_add(1)
                        .filter(|g| *g <= source::MAX_COUNTER)
                        .ok_or("generation_exhausted")?;
                    self.job.id = profile::new_uuid().map_err(|_| "storage_unavailable")?;
                    self.job.generation = generation;
                    self.job.source_id = None;
                    self.job.processed_frames = 0;
                    s.generation = generation;
                    s.job = Some(self.job.clone());
                    self.epoch_seen = false;
                }
                s.frame = None;
                s.detail_frame = None;
                s.detail_recent.clear();
                s.latest_decode = None;
                s.decode_counter = 0;
                if let Some(l) = s.live.as_mut() {
                    l.clear_context();
                }
                Ok(None)
            }
            SourcePoll::Failed(e) => Err(audio_error(e)),
            SourcePoll::End => Err("audio_unavailable"),
            SourcePoll::Pending => Ok(None),
        }
    }
    /// Measures the capture clock against the epoch anchor and, when the smoothed offset
    /// moved by more than RESCHEDULE_TICKS or the station clock correction changed,
    /// re-anchors the window schedule on their sum. Returns the drift update.
    pub(super) fn track_clock(
        &mut self,
        timing: Option<&source::SourceTiming>,
    ) -> Option<(i128, Option<f64>)> {
        let timing = timing.filter(|t| t.correlated)?;
        let before = self.clock.applied + self.air;
        let update = self
            .input
            .clock_utc()
            .and_then(|(frame, utc)| self.clock.observe(timing, frame, utc));
        self.air = self.owner.clock_correction();
        let after = self.clock.applied + self.air;
        if after != before
            && let (Some(mode), Some(window)) = (self.mode, self.window.as_mut())
            && let Some(schedule) = window_schedule(timing, mode, after)
        {
            // A larger offset (capture clock or system clock behind UTC) completes windows
            // earlier.
            let shift = -((after - before) * 12000 / 10_000_000);
            window.reschedule(&schedule, i64::try_from(shift).unwrap_or(0));
        }
        update
    }
    pub(super) fn analyze(&mut self, mut window: receive::AnalysisWindow) -> Result<()> {
        use std::{
            future::Future,
            task::{Context, Poll, Waker},
        };
        // One late window may wait for the decode in progress; any other arrival
        // abandons that decode as an overrun.
        let mut pending: Option<receive::AnalysisWindow> = None;
        loop {
            let mode = self.mode.ok_or("state_conflict")?;
            // CL-061-04: no decode attempt for a period this station transmitted in; its
            // view is published as a Tx period (WSJT-X stops monitoring while it transmits).
            let span = (window.origin, window.origin + window.samples.len() as u64);
            if self.owner.tx_window(span) {
                let job = self.job.clone();
                self.owner
                    .publish_view(&job, span, 0, false, window.waits, true)?;
                if let Some(next) = pending.take() {
                    window = next;
                    continue;
                }
                return Ok(());
            }
            let mut state = if self.reset {
                self.modem = None;
                decoder::DecodeState::new_live(mode)
            } else {
                self.modem.take().ok_or("state_conflict")?
            };
            self.reset = false;
            let decoder = decoder::Decoder::new();
            let cancel = self.job.cancel.clone();
            let job = self.job.clone();
            let owner = self.owner.clone();
            let cancelled = || cancel.load(Ordering::Acquire);
            let mut publish = |decoded: &decoder::Decode| owner.publish_decode(&job, decoded);
            let interval = (window.origin, window.origin + window.samples.len() as u64);
            let late = window.waits;
            let (first_sequence, period_start, period_utc, drift_ms) = self
                .owner
                .state
                .lock()
                .unwrap()
                .live
                .as_ref()
                .map(|l| {
                    let middle = window.origin + window.samples.len() as u64 / 2;
                    // Station UTC: capture drift plus the air-clock correction, as
                    // the window schedule and the published records use.
                    let drift = l.capture_drift.map_or(0, |(d, _)| d) + l.clock_correction;
                    let start = period_start_frame(l.timing.as_ref(), l.mode, middle, drift);
                    let utc = start.and_then(|frame| {
                        relative_decode_timing(l.timing.as_ref(), l.mode, frame, drift)
                            .map(|(utc, _)| utc)
                    });
                    let drift_ms = l
                        .capture_drift
                        .map(|(d, _)| (d as f64 / 10_000.0).round() as i64);
                    (l.next_sequence, start, utc, drift_ms)
                })
                .ok_or("state_conflict")?;
            // FT8 SNR measures from the UTC period start, as WSJT-X does.
            state.set_period_start(period_start);
            // The station's a-priori context (MyCall, DxCall, QSO state) of this window.
            state.set_a_priori(
                self.owner
                    .contact
                    .get()
                    .map(|s| s.a_priori())
                    .unwrap_or_default(),
            );
            self.note_window(&window, mode, period_start, period_utc, drift_ms);
            // UDP Status decoding is true from here until this window's decode returns.
            let busy = self.owner.begin_window_decode();
            let mut complete = false;
            let mut future = Box::pin(decoder.decode_window_into_async(
                window.samples,
                window.origin,
                &mut state,
                &cancelled,
                &mut publish,
            ));
            let mut context = Context::from_waker(Waker::noop());
            let mut replacement = None;
            let mut skipped = None;
            let result = loop {
                if !self.current() {
                    break Err("cancelled");
                }
                match future.as_mut().poll(&mut context) {
                    Poll::Ready(result) => {
                        break match result {
                            Ok(()) => {
                                complete = true;
                                Ok(())
                            }
                            Err(decoder::DecodeError::Cancelled) => Err("cancelled"),
                            Err(decoder::DecodeError::SearchLimited) => {
                                if let Some(l) = self.owner.state.lock().unwrap().live.as_mut() {
                                    l.search_limited = true;
                                }
                                Err("decode_limit")
                            }
                            Err(_) => Err(self
                                .owner
                                .state
                                .lock()
                                .unwrap()
                                .live
                                .as_ref()
                                .and_then(|l| l.publication_error)
                                .unwrap_or("decode_limit")),
                        };
                    }
                    Poll::Pending => {}
                }
                // Drain the real capture queue between cooperative numerical yields.
                for _ in 0..128 {
                    match self.step() {
                        Ok(Some(next)) if next.waits && pending.is_none() => {
                            pending = Some(next);
                        }
                        Ok(Some(next)) => {
                            skipped = pending
                                .take()
                                .map(|p| (p.origin, p.origin + p.samples.len() as u64));
                            replacement = Some(next);
                            break;
                        }
                        Ok(None) => {}
                        Err(error) => {
                            drop(future);
                            return Err(error);
                        }
                    }
                    if self.reset {
                        break;
                    }
                }
                if replacement.is_some() || self.reset {
                    if replacement.is_some()
                        && let Some(l) = self.owner.state.lock().unwrap().live.as_mut()
                    {
                        l.last_overrun = Some(skipped.unwrap_or(interval));
                    }
                    break Ok(());
                }
            };
            drop(future);
            drop(busy);
            self.modem = if self.reset { None } else { Some(state) };
            result?;
            if !self.reset {
                self.owner
                    .publish_latest_decode(&job, interval, first_sequence, complete, late)?;
                // One completed decode window re-estimates the clock from the
                // air; the correction moves at most 1000 ms within one period of the mode.
                if let Some(clock) = self.owner.clock.get() {
                    clock.station.period_done(if mode == decoder::Mode::Ft4 {
                        7_500
                    } else {
                        15_000
                    });
                }
            }
            if self.reset {
                pending = None;
            }
            if let Some(next) = replacement.or_else(|| pending.take()) {
                window = next;
            } else {
                return Ok(());
            }
        }
    }
}
fn period_parameters(mode: &str) -> Option<(i128, i128, i128)> {
    match mode {
        "ft8" => Some((150_000_000, 5_000_000, 126_400_000)),
        "ft4" => Some((75_000_000, 4_520_000, 50_400_000)),
        _ => None,
    }
}
/// UTC-aligned live analysis windows of one mode, as (completion after the period start,
/// window length), both in 100 ns ticks. A window holds the complete frames that start
/// between (completion - length) and (completion - frame duration).
/// - Prompt: FT8 completes at +13.8 s with 15 s of audio (DT -1.7 s to +0.66 s; frames
///   nominally end at +13.14 s), FT4 at +6.5 s with 7.5 s (DT -1.5 s to +0.96 s), leaving
///   1.2 s and 1.0 s to publish every decode by +15.0 s and +7.5 s.
/// - Late: completes early in the next period for the late starters, FT8 at +15.7 s
///   (DT +0.2 s to +2.56 s) and FT4 at +7.9 s (DT -0.1 s to +2.36 s); repeated frames of
///   the overlap are deduplicated by the modem history.
///
/// Without a correlated UTC anchor the plain 30 s/15 s (FT4 15 s/7.5 s) counter grid stays.
pub(crate) const LIVE_WINDOWS: [(decoder::Mode, [(i128, i128); 2]); 2] = [
    (
        decoder::Mode::Ft8,
        [
            (FT8_PROMPT_END_MS * 10_000, 150_000_000),
            (FT8_LATE_END_MS * 10_000, 150_000_000),
        ],
    ),
    (
        decoder::Mode::Ft4,
        [
            (FT4_PROMPT_END_MS * 10_000, 75_000_000),
            (FT4_LATE_END_MS * 10_000, 75_000_000),
        ],
    ),
];
/// WstxLiveReceive::WindowSchedule: the ends of the prompt and the late window after the
/// period start.
const FT8_PROMPT_END_MS: i128 = 13_800;
const FT8_LATE_END_MS: i128 = 15_700;
const FT4_PROMPT_END_MS: i128 = 6_500;
const FT4_LATE_END_MS: i128 = 7_900;
/// Source-counter residues and lengths (frames) of the UTC-aligned live windows; None
/// without a correlated UTC anchor.
pub(super) fn window_schedule(
    timing: &source::SourceTiming,
    mode: decoder::Mode,
    drift: i128,
) -> Option<Vec<(u64, usize, bool)>> {
    let (period, _, _) = period_parameters(match mode {
        decoder::Mode::Ft8 => "ft8",
        decoder::Mode::Ft4 => "ft4",
    })?;
    let windows = LIVE_WINDOWS.iter().find(|(m, _)| *m == mode)?.1;
    let anchor = source_ticks(timing, timing.canonical_anchor_frame)? + drift;
    let advance = period * 12000 / 10_000_000;
    windows
        .iter()
        .enumerate()
        .map(|(index, &(completion, length))| {
            let after = (completion - anchor).rem_euclid(period);
            let frames = (after * 12000 + 5_000_000) / 10_000_000;
            let residue = (i128::from(timing.canonical_anchor_frame) + frames).rem_euclid(advance);
            Some((
                u64::try_from(residue).ok()?,
                usize::try_from(length * 12000 / 10_000_000).ok()?,
                // The late window waits for its period's prompt decode.
                index == 1,
            ))
        })
        .collect()
}
pub(super) fn source_ticks(timing: &source::SourceTiming, frame: u64) -> Option<i128> {
    if !timing.correlated {
        return None;
    }
    let anchor = i128::from(filetime_from_utc(timing.system_utc_anchor.as_deref()?)?);
    Some(
        anchor
            + (i128::from(frame) - i128::from(timing.canonical_anchor_frame)) * 10_000_000 / 12000,
    )
}
/// The window's begin (station UTC FILETIME ticks) and the period slot it publishes: the
/// latest UTC period whose nominal support ends inside the window (RadioIO
/// LatestDecodePeriod). None without a correlated clock or a period mode.
fn window_slot(l: &LiveState, interval: (u64, u64)) -> Option<(i128, i128)> {
    let timing = l.timing.as_ref().filter(|t| t.correlated)?;
    let (period, nominal, support) = period_parameters(l.mode)?;
    let drift = l.capture_drift.map_or(0, |(d, _)| d) + l.clock_correction;
    let begin = source_ticks(timing, interval.0)? + drift;
    let end = source_ticks(timing, interval.1)? + drift;
    Some((begin, (end - nominal - support).div_euclid(period) * period))
}
/// Station UTC FILETIME ticks as Unix milliseconds.
fn unix_ms(ticks: i128) -> i64 {
    i64::try_from((ticks - 116_444_736_000_000_000).div_euclid(10_000)).unwrap_or(i64::MIN)
}
/// The start (station UTC ms) of the UTC period holding canonical `frame`.
fn period_start_ms(
    timing: Option<&source::SourceTiming>,
    mode: &str,
    frame: u64,
    drift: i128,
) -> Option<i64> {
    let observed = source_ticks(timing?, frame)? + drift;
    let (period, _, _) = period_parameters(mode)?;
    Some(unix_ms(observed.div_euclid(period) * period))
}
impl LiveWorker {
    /// The window's zero-sample and capture counters, and its dump when enabled.
    fn note_window(
        &self,
        window: &receive::AnalysisWindow,
        mode: decoder::Mode,
        period_start: Option<u64>,
        period_utc: Option<String>,
        drift_ms: Option<i64>,
    ) {
        let end = window.origin + window.samples.len() as u64;
        let (zeros, longest, early) =
            diagnostics::zero_counts(&window.samples, window.origin, period_start);
        let marked = self.input.marked_frames(window.origin, end);
        let capture = self.input.capture_diagnostics().map(|c| {
            json!({"queue_contention":c.queue_contention,"queue_full":c.queue_full,
                "pool_exhausted":c.pool_exhausted,"invalid_packet":c.invalid_packet,
                "clock_step":c.clock_step,"timestamp_error":c.timestamp_error,
                "native_discontinuity":c.native_discontinuity,"frame_backstep":c.frame_backstep})
        });
        let record = json!({"mode":if mode == decoder::Mode::Ft8 { "ft8" } else { "ft4" },
            "origin":window.origin,"frames":window.samples.len(),"late":window.waits,
            "period_start_frame":period_start,"period_start_utc":period_utc,
            "window_offset_ms":period_start.map(|p| (i128::from(window.origin) - i128::from(p)) * 1000 / 12000),
            "zero_samples":zeros,"longest_zero_run":longest,"early_buffer_zero_samples":early,
            "zero_filled_frames":marked.map(|m| m.0),"glitch_frames":marked.map(|m| m.1),
            "capture":capture,"capture_drift_ms":drift_ms,"dump":null});
        self.owner.note_window(
            record,
            &window.samples,
            mode == decoder::Mode::Ft8 && !window.waits,
        );
    }
}
/// The canonical frame where the UTC period containing `frame` began.
pub(super) fn period_start_frame(
    timing: Option<&source::SourceTiming>,
    mode: &str,
    frame: u64,
    drift: i128,
) -> Option<u64> {
    let observed = source_ticks(timing?, frame)? + drift;
    let (period, _, _) = period_parameters(mode)?;
    let into = observed.rem_euclid(period) * 12000 / 10_000_000;
    u64::try_from(i128::from(frame) - into).ok()
}
pub(super) fn relative_decode_timing(
    timing: Option<&source::SourceTiming>,
    mode: &str,
    frame: u64,
    drift: i128,
) -> Option<(String, f64)> {
    let observed = source_ticks(timing?, frame)? + drift;
    let (period, nominal, _) = period_parameters(mode)?;
    let slot = (observed - nominal + period / 2).div_euclid(period) * period;
    Some((
        utc_from_filetime(u64::try_from(slot).ok()?)?,
        (observed - slot - nominal) as f64 / 10_000_000.0,
    ))
}
pub(super) fn filetime_from_utc(text: &str) -> Option<u64> {
    let b = text.as_bytes();
    if b.len() < 20
        || b.get(4) != Some(&b'-')
        || b.get(7) != Some(&b'-')
        || b.get(10) != Some(&b'T')
        || b.get(13) != Some(&b':')
        || b.get(16) != Some(&b':')
        || b.last() != Some(&b'Z')
    {
        return None;
    }
    let number = |a: usize, z: usize| -> Option<u64> {
        let part = b.get(a..z)?;
        if !part.iter().all(u8::is_ascii_digit) {
            return None;
        }
        std::str::from_utf8(part).ok()?.parse().ok()
    };
    let (year, month, day, hour, minute, second) = (
        number(0, 4)?,
        number(5, 7)?,
        number(8, 10)?,
        number(11, 13)?,
        number(14, 16)?,
        number(17, 19)?,
    );
    if !(1970..=9999).contains(&year)
        || !(1..=12).contains(&month)
        || hour > 23
        || minute > 59
        || second > 59
    {
        return None;
    }
    let leap = |y: u64| y.is_multiple_of(4) && (!y.is_multiple_of(100) || y.is_multiple_of(400));
    let months = [
        31,
        if leap(year) { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ];
    if day == 0 || day > months[(month - 1) as usize] {
        return None;
    }
    let mut days = 0;
    for y in 1970..year {
        days += if leap(y) { 366 } else { 365 };
    }
    days += months[..(month - 1) as usize].iter().sum::<u64>() + day - 1;
    let fraction = if b.len() == 20 {
        0
    } else {
        if b.get(19) != Some(&b'.') || !(22..=28).contains(&b.len()) {
            return None;
        }
        let digits = b.len() - 21;
        number(20, b.len() - 1)? * 10_u64.pow((7 - digits) as u32)
    };
    (11_644_473_600 + days * 86400 + hour * 3600 + minute * 60 + second)
        .checked_mul(10_000_000)?
        .checked_add(fraction)
}

pub(super) fn utc_from_filetime(ticks: u64) -> Option<String> {
    let seconds = ticks.checked_div(10_000_000)?.checked_sub(11_644_473_600)?;
    let mut days = seconds / 86400;
    let mut year = 1970u64;
    let leap = |year: u64| {
        year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400))
    };
    while year <= 9999 {
        let count = if leap(year) { 366 } else { 365 };
        if days < count {
            break;
        }
        days -= count;
        year += 1;
    }
    if year > 9999 {
        return None;
    }
    let months = [
        31,
        if leap(year) { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ];
    let mut month = 1;
    for count in months {
        if days < count {
            break;
        }
        days -= count;
        month += 1;
    }
    let time = seconds % 86400;
    Some(format!(
        "{year:04}-{month:02}-{:02}T{:02}:{:02}:{:02}.{:07}Z",
        days + 1,
        time / 3600,
        time % 3600 / 60,
        time % 60,
        ticks % 10_000_000
    ))
}
