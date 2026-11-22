//! The spectrum rows of a job and the pacing of a replay.

use super::*;

impl LiveSpectrum {
    pub(super) fn new() -> Self {
        Self {
            samples: VecDeque::with_capacity(8192),
            first: 0,
            next: 0,
            thin_start: 0,
            detail_start: 0,
            thin: spectrum::Spectrum::new(false),
            detail: spectrum::Spectrum::detailed(false),
            peak: [0.; 128],
            powers: [0.; 1024],
            count: 0,
        }
    }
    pub(super) fn reset(&mut self, first: u64) {
        self.samples.clear();
        self.first = first;
        self.next = first;
        self.thin_start = first.div_ceil(12000) * 12000;
        self.detail_start = first.div_ceil(spectrum::ROW_FRAMES) * spectrum::ROW_FRAMES;
        self.peak.fill(0.);
        self.powers.fill(0.);
        self.count = 0;
    }
    pub(super) fn push(&mut self, block: &SampleBlock) -> Result<[Option<SpectrumRow>; 2]> {
        if block.discontinuity {
            self.reset(block.first_frame);
        }
        if block.first_frame != self.next || block.samples.iter().any(|s| !s.is_finite()) {
            return Err("audio_failed");
        }
        self.next = self
            .next
            .checked_add(block.samples.len() as u64)
            .filter(|n| *n <= source::MAX_COUNTER)
            .ok_or("counter_exhausted")?;
        self.samples.extend(block.samples.iter().copied());
        let mut frames = [None, None];
        while self.thin_start + 2048 <= self.next {
            let offset = (self.thin_start - self.first) as usize;
            let x: Vec<_> = self
                .samples
                .iter()
                .skip(offset)
                .take(2048)
                .copied()
                .collect();
            for (peak, power) in self.peak.iter_mut().zip(self.thin.amplitudes(&x)?) {
                *peak = peak.max(power);
            }
            let first = self.thin_start / 12000 * 12000;
            self.thin_start += spectrum::HOP;
            if self.thin_start >= first + 12000 {
                frames[0] = Some(SpectrumRow {
                    first,
                    end: first + 12000,
                    levels: self.peak.into_iter().map(spectrum::quantize).collect(),
                    detailed: false,
                });
                self.peak.fill(0.);
            }
        }
        while self.detail_start + spectrum::DETAIL_SIZE as u64 <= self.next {
            let offset = (self.detail_start - self.first) as usize;
            let x: Vec<_> = self
                .samples
                .iter()
                .skip(offset)
                .take(spectrum::DETAIL_SIZE)
                .copied()
                .collect();
            for (power, a) in self
                .powers
                .iter_mut()
                .zip(self.detail.native_amplitudes(&x)?)
            {
                *power += a * a;
            }
            self.count += 1;
            let first = self.detail_start / spectrum::ROW_FRAMES * spectrum::ROW_FRAMES;
            self.detail_start += spectrum::DETAIL_HOP;
            if self.detail_start >= first + spectrum::ROW_FRAMES {
                let levels = self
                    .powers
                    .iter()
                    .map(|p| spectrum::quantize((p / self.count as f32).sqrt()))
                    .collect();
                frames[1] = Some(SpectrumRow {
                    first,
                    end: first + spectrum::ROW_FRAMES,
                    levels,
                    detailed: true,
                });
                self.powers.fill(0.);
                self.count = 0;
            }
        }
        let retain = self.thin_start.min(self.detail_start);
        while self.first < retain && !self.samples.is_empty() {
            self.samples.pop_front();
            self.first += 1;
        }
        if self.samples.len() > 8192 {
            return Err("decode_limit");
        }
        Ok(frames)
    }
}
impl Recording {
    pub(super) fn process(&self, job: &Job, meta: &Metadata) -> Result<()> {
        let source = Arc::new(SourceDescriptor {
            schema_version: 1,
            profile_id: self.profile.clone(),
            boot_id: self.boot.clone(),
            source_id: meta.recording_id.clone(),
            rate_hz: RATE_HZ,
            channel: "mono_real",
            total_frames: Some(meta.frames),
            utc_anchor: None,
        });
        let mut input = self
            .replays
            .open(&self.path(&meta.recording_id, "wav"), source)?;
        let mut block = input.next()?.ok_or("recording_unavailable")?;
        if Some(&block.source.source_id) != job.source_id.as_ref()
            || block.discontinuity
            || block.end_of_stream != (block.samples.len() as u64 == meta.frames)
        {
            return Err("recording_unavailable");
        }
        let mut thin = spectrum::Spectrum::new(false);
        let mut detail = spectrum::Spectrum::detailed(false);
        let mut history: VecDeque<f32> = block.samples.iter().copied().collect();
        let mut history_first = 0u64;
        let (mut thin_start, mut detail_start) = (0u64, 0u64);
        let mut thin_peak = [0f32; 128];
        let mut thin_sequence = 0;
        let began = self.time.now();
        for sequence in 0..meta.frames.div_ceil(spectrum::ROW_FRAMES) {
            let row_end = ((sequence + 1) * spectrum::ROW_FRAMES).min(meta.frames);
            let mut powers = [0f32; 1024];
            let mut count = 0;
            while thin_start.min(detail_start) < row_end {
                if job.cancel.load(Ordering::Acquire) {
                    return Err("cancelled");
                }
                let start = thin_start.min(detail_start);
                while history_first < start && !history.is_empty() {
                    history.pop_front();
                    history_first += 1;
                }
                let needed = (start
                    + if start == detail_start {
                        spectrum::DETAIL_SIZE as u64
                    } else {
                        2048
                    })
                .min(meta.frames);
                while history_first + (history.len() as u64) < needed {
                    let next = input.next()?.ok_or("recording_unavailable")?;
                    if next.first_frame != history_first + history.len() as u64 {
                        return Err("recording_unavailable");
                    }
                    block = next;
                    if history.len() + block.samples.len() > 8192 {
                        return Err("recording_unavailable");
                    }
                    history.extend(block.samples.iter().copied());
                }
                if start == thin_start {
                    let x: Vec<f32> = history.iter().take(2048).copied().collect();
                    for (peak, a) in thin_peak.iter_mut().zip(thin.amplitudes(&x)?) {
                        *peak = peak.max(a);
                    }
                    thin_start += spectrum::HOP;
                }
                if start == detail_start {
                    let x: Vec<f32> = history
                        .iter()
                        .take(spectrum::DETAIL_SIZE)
                        .copied()
                        .collect();
                    for (power, a) in powers.iter_mut().zip(detail.native_amplitudes(&x)?) {
                        *power += a * a;
                    }
                    count += 1;
                    detail_start += spectrum::DETAIL_HOP;
                }
            }
            let due = Duration::from_secs_f64(row_end as f64 / spectrum::RATE as f64);
            loop {
                let elapsed = self.time.now().saturating_duration_since(began);
                let remaining = due.saturating_sub(elapsed);
                if remaining.is_zero() {
                    break;
                }
                if job.cancel.load(Ordering::Acquire) {
                    return Err("cancelled");
                }
                self.time.sleep(remaining.min(Duration::from_millis(20)));
            }
            let levels: Vec<u8> = powers
                .into_iter()
                .map(|p| spectrum::quantize((p / count as f32).sqrt()))
                .collect();
            let mut s = self.state.lock().unwrap();
            if job.cancel.load(Ordering::Acquire) {
                return Err("cancelled");
            }
            if s.job.as_ref().is_some_and(|j| {
                j.id == job.id && j.generation == job.generation && j.state == "running"
            }) {
                s.job.as_mut().unwrap().processed_frames = row_end;
                push_detail(
                    &mut s,
                    json!({"v":1,"type":"spectrum.detail.frame","data":{"boot_id":self.boot,"source_id":job.source_id,"job_id":job.id,"generation":job.generation,"sequence":sequence,"first_frame":sequence*spectrum::ROW_FRAMES,"end_frame":row_end,"levels_b64":STANDARD.encode(levels)}}),
                );
                if row_end.is_multiple_of(12000) || row_end == meta.frames {
                    let levels: Vec<u8> = thin_peak.into_iter().map(spectrum::quantize).collect();
                    s.frame = Some(
                        json!({"v":1,"type":"spectrum.frame","data":{"boot_id":self.boot,"source_id":job.source_id,"job_id":job.id,"generation":job.generation,"sequence":thin_sequence,"first_frame":thin_sequence*12000,"end_frame":row_end,"levels":levels}}),
                    );
                    thin_peak.fill(0.0);
                    thin_sequence += 1;
                }
            }
        }
        Ok(())
    }
}
