//! Canonical receive values. The receive manager, not a device adapter, owns identities.
use serde::Serialize;
use std::sync::Arc;

pub const CANONICAL_HZ: u32 = 12_000;
pub const LIVE_BLOCK_FRAMES: usize = 240;
pub const MAX_COUNTER: u64 = 9_007_199_254_740_991;

#[derive(Clone, Debug, Serialize)]
pub struct SourceDescriptor {
    pub schema_version: u8,
    pub profile_id: String,
    pub boot_id: String,
    pub source_id: String,
    pub rate_hz: u32,
    pub channel: &'static str,
    pub total_frames: Option<u64>,
    pub utc_anchor: Option<String>,
}

impl SourceDescriptor {
    pub fn valid(&self) -> bool {
        self.schema_version == 1
            && self.rate_hz == CANONICAL_HZ
            && self.channel == "mono_real"
            && [&self.profile_id, &self.boot_id, &self.source_id]
                .iter()
                .all(|id| !id.is_empty() && id.len() <= 64)
            && self
                .total_frames
                .is_none_or(|frames| frames > 0 && frames <= MAX_COUNTER)
    }
}

/// A segment maps sample positions to the system clock, without claiming external UTC accuracy.
#[derive(Clone, Debug, Serialize)]
pub struct SourceTiming {
    pub source_id: String,
    pub segment: u64,
    pub native_rate: u32,
    pub native_anchor_frame: f64,
    pub canonical_anchor_frame: u64,
    pub converter_delay_native_frames: f64,
    pub qpc_anchor_100ns: Option<u64>,
    pub system_utc_anchor: Option<String>,
    pub uncertainty_ns: Option<u64>,
    pub correlated: bool,
    pub external_accuracy: ExternalAccuracy,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ExternalAccuracy {
    Unknown,
}

impl SourceTiming {
    pub fn valid_for(&self, descriptor: &SourceDescriptor) -> bool {
        self.source_id == descriptor.source_id
            && matches!(self.native_rate, 44_100 | 48_000)
            && self.segment <= MAX_COUNTER
            && self.native_anchor_frame.is_finite()
            && (0.0..=MAX_COUNTER as f64).contains(&self.native_anchor_frame)
            && self.canonical_anchor_frame <= MAX_COUNTER
            && self.converter_delay_native_frames.is_finite()
            && (0.0..=f64::from(self.native_rate) * 0.020)
                .contains(&self.converter_delay_native_frames)
            && if self.correlated {
                self.qpc_anchor_100ns.is_some()
                    && self
                        .system_utc_anchor
                        .as_ref()
                        .is_some_and(|utc| !utc.is_empty())
                    && self.uncertainty_ns.is_some_and(|ns| ns <= 2_000_000)
            } else {
                self.system_utc_anchor.is_none() && self.uncertainty_ns.is_none()
            }
    }
}

#[derive(Clone, Debug)]
pub struct SourceContext {
    pub descriptor: Arc<SourceDescriptor>,
    pub timing: Arc<SourceTiming>,
}

#[derive(Clone, Debug)]
pub struct SampleBlock {
    pub source: Arc<SourceDescriptor>,
    pub first_frame: u64,
    pub samples: Arc<[f32]>,
    pub discontinuity: bool,
    pub end_of_stream: bool,
    pub timing: Option<Arc<SourceTiming>>,
}

impl SampleBlock {
    pub fn live(
        context: &SourceContext,
        first_frame: u64,
        samples: Arc<[f32]>,
        discontinuity: bool,
    ) -> Result<Self, SourceError> {
        if samples.is_empty()
            || samples.len() > LIVE_BLOCK_FRAMES
            || !samples.iter().all(|sample| sample.is_finite())
            || first_frame
                .checked_add(samples.len() as u64)
                .is_none_or(|end| end > MAX_COUNTER)
            || !context.descriptor.valid()
            || context.descriptor.total_frames.is_some()
            || !context.timing.valid_for(&context.descriptor)
        {
            return Err(SourceError::InvalidBlock);
        }
        Ok(Self {
            source: context.descriptor.clone(),
            first_frame,
            samples,
            discontinuity,
            end_of_stream: false,
            timing: Some(context.timing.clone()),
        })
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct EpochProposal {
    pub proposal_counter: u64,
    pub reason: &'static str,
    pub native_rate: u32,
    pub first_device_frame: u64,
    pub packet_qpc_100ns: Option<u64>,
    pub converter_delay_native_frames: f64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SourceError {
    InvalidContext,
    StaleAcknowledgement,
    CounterExhausted,
    InvalidBlock,
    Unavailable,
    UnsupportedFormat,
    Cancelled,
    FailedClose,
}

pub enum SourcePoll {
    Pending,
    Block(SampleBlock),
    EpochChanged(EpochProposal),
    End,
    Failed(SourceError),
}

pub trait SampleSource {
    fn descriptor(&self) -> Option<Arc<SourceDescriptor>>;
    fn poll(&mut self) -> SourcePoll;
    fn acknowledge_epoch(
        &mut self,
        proposal_counter: u64,
        descriptor: Arc<SourceDescriptor>,
        timing: SourceTiming,
    ) -> Result<(), SourceError>;
}

/// The producer may propose a new epoch, but cannot publish until its owner acknowledges it.
#[derive(Default)]
pub struct EpochLatch {
    counter: u64,
    pending: Option<EpochProposal>,
    context: Option<SourceContext>,
    previous_source_id: Option<String>,
}

impl EpochLatch {
    pub fn propose(
        &mut self,
        reason: &'static str,
        native_rate: u32,
        first_device_frame: u64,
        packet_qpc_100ns: Option<u64>,
        converter_delay_native_frames: f64,
    ) -> Result<EpochProposal, SourceError> {
        if !matches!(native_rate, 44_100 | 48_000)
            || first_device_frame > MAX_COUNTER
            || !converter_delay_native_frames.is_finite()
            || !(0.0..=f64::from(native_rate) * 0.020).contains(&converter_delay_native_frames)
        {
            return Err(SourceError::InvalidContext);
        }
        self.counter = self
            .counter
            .checked_add(1)
            .filter(|n| *n <= MAX_COUNTER)
            .ok_or(SourceError::CounterExhausted)?;
        if let Some(context) = self.context.take() {
            self.previous_source_id = Some(context.descriptor.source_id.clone());
        }
        let proposal = EpochProposal {
            proposal_counter: self.counter,
            reason,
            native_rate,
            first_device_frame,
            packet_qpc_100ns,
            converter_delay_native_frames,
        };
        self.pending = Some(proposal.clone());
        Ok(proposal)
    }

    pub fn acknowledge(
        &mut self,
        counter: u64,
        descriptor: Arc<SourceDescriptor>,
        timing: SourceTiming,
    ) -> Result<(), SourceError> {
        let proposal = self
            .pending
            .as_ref()
            .filter(|p| p.proposal_counter == counter)
            .ok_or(SourceError::StaleAcknowledgement)?;
        if !descriptor.valid()
            || descriptor.total_frames.is_some()
            || !timing.valid_for(&descriptor)
            || timing.native_rate != proposal.native_rate
            || timing.converter_delay_native_frames != proposal.converter_delay_native_frames
            || self.previous_source_id.as_ref() == Some(&descriptor.source_id)
        {
            return Err(SourceError::InvalidContext);
        }
        self.context = Some(SourceContext {
            descriptor,
            timing: Arc::new(timing),
        });
        self.pending = None;
        Ok(())
    }

    pub fn context(&self) -> Option<&SourceContext> {
        self.context.as_ref()
    }
    pub fn pending(&self) -> Option<&EpochProposal> {
        self.pending.as_ref()
    }
}
