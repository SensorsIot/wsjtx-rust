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
}

pub(crate) struct IngestOutcome {
    pub captured_next_frame: u64,
    pub reset_decoder: bool,
    pub window: Option<AnalysisWindow>,
}

pub(crate) struct WindowBuffer {
    source: Arc<SourceDescriptor>,
    timing: Option<Arc<SourceTiming>>,
    history: VecDeque<f32>,
    history_first: u64,
    previous_end: Option<u64>,
    next_due: u64,
    advance: u64,
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
            next_due: advance,
            advance,
            span,
            complete_support: mode.symbol_frames() * mode.symbol_count(),
        })
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
            // Source counters, not UTC or callback arrival time, fix the advance grid.
            // The private due boundary may exceed MAX_COUNTER; accepted sample counters never do.
            self.next_due = (block.first_frame / self.advance + 1) * self.advance;
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
            if position == self.next_due {
                if self.history.len() >= self.complete_support {
                    let mut samples = Vec::new();
                    samples
                        .try_reserve_exact(self.history.len())
                        .map_err(|_| WindowError::DecodeLimit)?;
                    samples.extend(self.history.iter().copied());
                    window = Some(AnalysisWindow {
                        samples,
                        origin: self.history_first,
                    });
                }
                self.next_due += self.advance;
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
