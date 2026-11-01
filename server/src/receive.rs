//! Bounded live analysis history. Device, modem and station authority remain with their owners.
use crate::decoder::Mode;
use crate::source::{LIVE_BLOCK_FRAMES, MAX_COUNTER, SampleBlock, SourceDescriptor, SourceTiming};
use std::{collections::VecDeque, sync::Arc};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum WindowError {
    InvalidContext,
    InvalidBlock,
    CounterExhausted,
    DecodeLimit,
}

pub(crate) struct AnalysisWindow {
    pub samples: Vec<f32>,
    pub origin: u64,
    /// A scheduled late window that may wait for the analysis in progress instead of
    /// replacing it. The audio test targets include this file without the live worker.
    #[allow(dead_code)]
    pub waits: bool,
}

pub(crate) struct IngestOutcome {
    pub captured_next_frame: u64,
    pub reset_decoder: bool,
    pub window: Option<AnalysisWindow>,
}

/// One scheduled window: its source-counter residue modulo the advance, its length, whether
/// it may wait for the analysis in progress, and its next completion position.
struct Due {
    phase: u64,
    frames: usize,
    waits: bool,
    next: u64,
    /// The aligned completion after `next` when `next` is off the residue grid: a correction
    /// moved it into the past, or it was deferred behind a coinciding window.
    after: Option<u64>,
}

pub(crate) struct WindowBuffer {
    source: Arc<SourceDescriptor>,
    timing: Option<Arc<SourceTiming>>,
    history: VecDeque<f32>,
    history_first: u64,
    previous_end: Option<u64>,
    advance: u64,
    /// Due boundaries; the default is the plain counter grid with the whole span.
    schedule: Vec<Due>,
    span: usize,
    complete_support: usize,
}

impl WindowBuffer {
    pub(crate) fn new(mode: Mode, source: Arc<SourceDescriptor>) -> Result<Self, WindowError> {
        if !source.valid() || source.total_frames.is_some() {
            return Err(WindowError::InvalidContext);
        }
        let (advance, span) = match mode {
            Mode::Ft8 => (180000, 360000),
            Mode::Ft4 => (90000, 180000),
        };
        let mut history = VecDeque::new();
        history
            .try_reserve_exact(span)
            .map_err(|_| WindowError::DecodeLimit)?;
        Ok(Self {
            source,
            timing: None,
            history,
            history_first: 0,
            previous_end: None,
            advance,
            schedule: vec![Due {
                phase: 0,
                frames: span,
                waits: false,
                next: advance,
                after: None,
            }],
            span,
            complete_support: mode.symbol_frames() * mode.symbol_count(),
        })
    }

    /// Replaces the counter grid with due boundaries at fixed residues of the advance, each
    /// with its own window length (at most the span), so windows can complete at fixed points
    /// of the source's period grid. Positions remain source counters.
    // The audio test targets include this file without the live worker that calls it.
    #[allow(dead_code)]
    pub(crate) fn with_schedule(mut self, schedule: &[(u64, usize, bool)]) -> Self {
        if !schedule.is_empty() {
            self.schedule = schedule
                .iter()
                .map(|&(phase, frames, waits)| Due {
                    phase: phase % self.advance,
                    frames: frames.min(self.span),
                    waits,
                    next: 0,
                    after: None,
                })
                .collect();
            for due in &mut self.schedule {
                due.next = due_after(due.phase, self.advance, 0);
            }
        }
        self
    }

    /// Re-anchors the schedule (same entries, same order) after a clock correction that moved
    /// every completion by `shift` source frames (positive: later). Each entry's next
    /// completion stays the completion of the same UTC period, whatever the size or sign of
    /// the shift: one moved into the past completes now (coinciding entries one after the
    /// other, in schedule order), one moved later waits, and the entry then returns to its
    /// residue grid, so no window is dropped, repeated or moved by a period.
    #[allow(dead_code)]
    pub(crate) fn reschedule(&mut self, schedule: &[(u64, usize, bool)], shift: i64) {
        if schedule.len() != self.schedule.len() {
            return;
        }
        let advance = self.advance as i128;
        let floor = self.previous_end.map_or(0, |end| end + 1) as i128;
        for (due, &(phase, frames, waits)) in self.schedule.iter_mut().zip(schedule) {
            // The aligned (on-grid) completion this entry is waiting for, moved by the shift.
            let aligned = due.after.map_or(due.next, |after| after - self.advance) as i128;
            let moved = aligned + i128::from(shift);
            let (next, after) = if moved >= floor {
                (moved, None)
            } else {
                // Completes now; the next aligned completion is the first one after now.
                let periods = (floor - moved).div_euclid(advance) + 1;
                (floor, Some(moved + periods * advance))
            };
            *due = Due {
                phase: phase % self.advance,
                frames: frames.min(self.span),
                waits,
                next: next as u64,
                after: after.map(|a| a as u64),
            };
        }
    }

    pub(crate) fn push(&mut self, block: &SampleBlock) -> Result<IngestOutcome, WindowError> {
        let end = block
            .first_frame
            .checked_add(block.samples.len() as u64)
            .filter(|end| *end <= MAX_COUNTER)
            .ok_or(WindowError::CounterExhausted)?;
        if block.samples.is_empty()
            || block.samples.len() > LIVE_BLOCK_FRAMES
            || block.end_of_stream
            || !block.samples.iter().all(|sample| sample.is_finite())
        {
            return Err(WindowError::InvalidBlock);
        }
        if !same_source(&self.source, &block.source) {
            return Err(WindowError::InvalidContext);
        }
        let timing = block
            .timing
            .as_ref()
            .filter(|timing| timing.valid_for(&self.source))
            .ok_or(WindowError::InvalidContext)?;
        if self
            .timing
            .as_ref()
            .is_some_and(|previous| !same_timing(previous, timing))
        {
            return Err(WindowError::InvalidContext);
        }
        if let Some(previous) = self.previous_end
            && (block.first_frame < previous
                || (block.first_frame > previous && !block.discontinuity))
        {
            return Err(WindowError::InvalidBlock);
        }

        let reset_decoder = self.previous_end.is_some() && block.discontinuity;
        if self.previous_end.is_none() || reset_decoder {
            self.history.clear();
            self.history_first = block.first_frame;
            // Source counters, not callback arrival time, fix the advance grid; its residue is
            // the caller's period phase. The private due boundary may exceed MAX_COUNTER;
            // accepted sample counters never do.
            for due in &mut self.schedule {
                due.next = due_after(due.phase, self.advance, block.first_frame);
                due.after = None;
            }
        }
        if self.timing.is_none() {
            self.timing = Some(timing.clone());
        }
        let mut window = None;
        for (offset, &sample) in block.samples.iter().enumerate() {
            if self.history.len() == self.span {
                self.history.pop_front();
                self.history_first += 1;
            }
            self.history.push_back(sample);
            let position = block.first_frame + offset as u64 + 1;
            // One window per ingest call: a coinciding entry (after a correction) is deferred
            // to the next block's first sample, keeping its aligned completion.
            let mut first = None;
            for due in self.schedule.iter_mut().filter(|due| due.next == position) {
                if first.is_some() || window.is_some() {
                    due.after = due.after.or(Some(due.next + self.advance));
                    due.next = end + 1;
                    continue;
                }
                due.next = due.after.take().unwrap_or(due.next + self.advance);
                first = Some((due.frames, due.waits));
            }
            let Some((frames, waits)) = first else {
                continue;
            };
            let frames = frames.min(self.history.len());
            if frames >= self.complete_support {
                let skip = self.history.len() - frames;
                let mut samples = Vec::new();
                samples
                    .try_reserve_exact(frames)
                    .map_err(|_| WindowError::DecodeLimit)?;
                samples.extend(self.history.iter().skip(skip).copied());
                window = Some(AnalysisWindow {
                    samples,
                    origin: self.history_first + skip as u64,
                    waits,
                });
            }
        }
        self.previous_end = Some(end);
        Ok(IngestOutcome {
            captured_next_frame: end,
            reset_decoder,
            window,
        })
    }
}

/// The first boundary with residue `phase` strictly after `position`.
fn due_after(phase: u64, advance: u64, position: u64) -> u64 {
    let behind = (position % advance + advance - phase) % advance;
    position + (advance - behind)
}

fn same_source(a: &SourceDescriptor, b: &SourceDescriptor) -> bool {
    a.schema_version == b.schema_version
        && a.profile_id == b.profile_id
        && a.boot_id == b.boot_id
        && a.source_id == b.source_id
        && a.rate_hz == b.rate_hz
        && a.channel == b.channel
        && a.total_frames == b.total_frames
        && a.utc_anchor == b.utc_anchor
}

fn same_timing(a: &SourceTiming, b: &SourceTiming) -> bool {
    a.source_id == b.source_id
        && a.segment == b.segment
        && a.native_rate == b.native_rate
        && a.native_anchor_frame == b.native_anchor_frame
        && a.canonical_anchor_frame == b.canonical_anchor_frame
        && a.converter_delay_native_frames == b.converter_delay_native_frames
        && a.qpc_anchor_100ns == b.qpc_anchor_100ns
        && a.system_utc_anchor == b.system_utc_anchor
        && a.uncertainty_ns == b.uncertainty_ns
        && a.correlated == b.correlated
        && a.external_accuracy == b.external_accuracy
}
