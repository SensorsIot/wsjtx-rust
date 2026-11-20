//! The listening capture of the hardware listening probe: it keeps canonical blocks in
//! segments (no padding, no stitching of gaps) and writes a segment as a PCM16 WAV. It takes
//! plain values: a block's source id, first frame, samples and discontinuity flag, and the
//! fields of a capture diagnostics snapshot.

const RATE: usize = 12_000;
pub const MAX_SAMPLES: usize = RATE * 120;
pub const MAX_SEGMENTS: usize = 16;

pub fn pcm16_wav(samples: &[f32]) -> Result<Vec<u8>, &'static str> {
    if samples.is_empty() || samples.len() > MAX_SAMPLES || samples.iter().any(|v| !v.is_finite()) {
        return Err("invalid or oversized canonical audio");
    }
    let bytes = u32::try_from(samples.len().checked_mul(2).ok_or("size overflow")?)
        .map_err(|_| "size overflow")?;
    let mut wav = Vec::with_capacity(44 + samples.len() * 2);
    wav.extend_from_slice(b"RIFF");
    wav.extend_from_slice(&(36 + bytes).to_le_bytes());
    wav.extend_from_slice(b"WAVEfmt ");
    wav.extend_from_slice(&16_u32.to_le_bytes());
    wav.extend_from_slice(&1_u16.to_le_bytes());
    wav.extend_from_slice(&1_u16.to_le_bytes());
    wav.extend_from_slice(&12_000_u32.to_le_bytes());
    wav.extend_from_slice(&24_000_u32.to_le_bytes());
    wav.extend_from_slice(&2_u16.to_le_bytes());
    wav.extend_from_slice(&16_u16.to_le_bytes());
    wav.extend_from_slice(b"data");
    wav.extend_from_slice(&bytes.to_le_bytes());
    for &sample in samples {
        // Finite samples are explicitly rounded and clipped into the PCM16 domain.
        let pcm = (f64::from(sample) * 32768.0)
            .round()
            .clamp(f64::from(i16::MIN), f64::from(i16::MAX)) as i16;
        wav.extend_from_slice(&pcm.to_le_bytes());
    }
    Ok(wav)
}

#[test]
fn listening_wav_has_independent_header_and_quantization_bytes() {
    let samples = [
        -2.0,
        -1.0,
        -0.5,
        -1.0 / 32768.0,
        0.0,
        1.0 / 32768.0,
        0.5,
        1.0,
        2.0,
    ];
    let wav = pcm16_wav(&samples).unwrap();
    let header: [u8; 44] = [
        82, 73, 70, 70, 54, 0, 0, 0, 87, 65, 86, 69, 102, 109, 116, 32, 16, 0, 0, 0, 1, 0, 1, 0,
        224, 46, 0, 0, 192, 93, 0, 0, 2, 0, 16, 0, 100, 97, 116, 97, 18, 0, 0, 0,
    ];
    assert_eq!(&wav[..44], &header);
    assert_eq!(
        &wav[44..],
        &[
            0, 128, 0, 128, 0, 192, 255, 255, 0, 0, 1, 0, 0, 64, 255, 127, 255, 127
        ]
    );
    assert!(pcm16_wav(&[]).is_err());
    assert!(pcm16_wav(&[f32::NAN]).is_err());
    assert!(pcm16_wav(&[f32::INFINITY]).is_err());
    assert!(pcm16_wav(&vec![0.0; MAX_SAMPLES + 1]).is_err());
    assert_eq!(pcm16_wav(&vec![0.0; MAX_SAMPLES]).unwrap().len(), 2_880_044);
}

/// The fields of a capture diagnostics snapshot.
#[derive(Clone, Copy, Debug, Default)]
pub struct Diagnostics {
    pub queue_contention: u64,
    pub queue_full: u64,
    pub pool_exhausted: u64,
    pub invalid_packet: u64,
    pub clock_step: u64,
    pub timestamp_error: u64,
    pub native_discontinuity: u64,
    pub frame_backstep: u64,
    pub native_channel_zero_samples: u64,
    pub native_channel_zero_full_scale: u64,
    pub native_channel_zero_peak_bits: u32,
}

pub fn diagnostics(value: Diagnostics) -> serde_json::Value {
    serde_json::json!({"queue_contention":value.queue_contention,"queue_full":value.queue_full,"pool_exhausted":value.pool_exhausted,"invalid_packet":value.invalid_packet,"clock_step":value.clock_step,"timestamp_error":value.timestamp_error,"native_discontinuity":value.native_discontinuity,"frame_backstep":value.frame_backstep,"native_channel_zero_samples":value.native_channel_zero_samples,"native_channel_zero_full_scale":value.native_channel_zero_full_scale,"native_channel_zero_peak":f32::from_bits(value.native_channel_zero_peak_bits)})
}
pub struct Segment {
    pub first: u64,
    pub next: u64,
    pub source_id: String,
    pub reason: String,
    pub samples: Vec<f32>,
    pub diagnostics: serde_json::Value,
}
pub struct ListeningCapture {
    pub segments: Vec<Segment>,
    pub total: usize,
    pub limit: usize,
    pub boundary: Option<String>,
}
impl Default for ListeningCapture {
    fn default() -> Self {
        Self {
            segments: Vec::new(),
            total: 0,
            limit: MAX_SAMPLES,
            boundary: None,
        }
    }
}
impl ListeningCapture {
    pub fn observe(
        &mut self,
        source_id: &str,
        first_frame: u64,
        samples: &[f32],
        discontinuity: bool,
        snapshot: Diagnostics,
    ) -> Result<(), String> {
        if samples.is_empty() || samples.len() > 240 || samples.iter().any(|v| !v.is_finite()) {
            return Err("invalid canonical capture block".into());
        }
        let reason = self.boundary.take().or_else(|| {
            self.segments.last().and_then(|last| {
                if last.source_id != source_id {
                    Some("source_identity_changed".into())
                } else if last.next != first_frame {
                    Some("canonical_frame_gap_or_backstep".into())
                } else if discontinuity {
                    Some("canonical_discontinuity".into())
                } else {
                    None
                }
            })
        });
        if self.segments.is_empty() || reason.is_some() {
            if self.segments.len() >= MAX_SEGMENTS {
                return Err("segment limit reached; capture stopped without stitching gaps".into());
            }
            self.segments.push(Segment {
                first: first_frame,
                next: first_frame,
                source_id: source_id.to_owned(),
                reason: reason.unwrap_or_else(|| "capture_start".into()),
                samples: Vec::new(),
                diagnostics: diagnostics(snapshot),
            });
        }
        let count = (self.limit - self.total).min(samples.len());
        let last = self.segments.last_mut().unwrap();
        last.samples.extend_from_slice(&samples[..count]);
        last.next = first_frame
            .checked_add(u64::try_from(count).unwrap())
            .ok_or("frame counter overflow")?;
        self.total += count;
        Ok(())
    }
}

#[test]
fn listening_segments_keep_gaps_and_epochs_separate_without_padding() {
    let source_id = "s";
    let samples = [0.25_f32, 0.5];
    let mut first_frame = 0;
    let mut discontinuity = true;
    let mut capture = ListeningCapture::default();
    capture
        .observe(
            source_id,
            first_frame,
            &samples,
            discontinuity,
            Default::default(),
        )
        .unwrap();
    first_frame = 2;
    discontinuity = false;
    capture
        .observe(
            source_id,
            first_frame,
            &samples,
            discontinuity,
            Default::default(),
        )
        .unwrap();
    first_frame = 8;
    capture
        .observe(
            source_id,
            first_frame,
            &samples,
            discontinuity,
            Default::default(),
        )
        .unwrap();
    capture.boundary = Some("capture_loss".into());
    first_frame = 0;
    capture
        .observe(
            source_id,
            first_frame,
            &samples,
            discontinuity,
            Default::default(),
        )
        .unwrap();
    assert_eq!(capture.total, 8);
    assert_eq!(capture.segments.len(), 3);
    assert_eq!(capture.segments[0].samples, [0.25, 0.5, 0.25, 0.5]);
    assert_eq!(capture.segments[1].first, 8);
    assert_eq!(capture.segments[1].samples, [0.25, 0.5]);
    assert_eq!(capture.segments[2].reason, "capture_loss");
    for n in 3..MAX_SEGMENTS {
        capture.boundary = Some(format!("epoch-{n}"));
        capture
            .observe(
                source_id,
                first_frame,
                &samples,
                discontinuity,
                Default::default(),
            )
            .unwrap();
    }
    capture.boundary = Some("one-too-many".into());
    assert!(
        capture
            .observe(
                source_id,
                first_frame,
                &samples,
                discontinuity,
                Default::default()
            )
            .is_err()
    );
}
