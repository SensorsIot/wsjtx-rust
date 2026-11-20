//! The capture evidence reader of the hardware capture probe: it takes each canonical
//! block's first frame, samples and discontinuity flag, refuses a bad block and measures
//! the samples.

#[derive(Default)]
pub struct Evidence {
    pub blocks: u64,
    pub samples: u64,
    pub epochs: u64,
    pub discontinuities: u64,
    pub known_missing: u64,
    pub unknown_loss_epochs: u64,
    pub previous_end: Option<u64>,
    squares: f64,
    pub peak: f64,
}
impl Evidence {
    pub fn observe(
        &mut self,
        first_frame: u64,
        samples: &[f32],
        discontinuity: bool,
    ) -> Result<(), String> {
        if samples.is_empty() || samples.len() > 240 || !samples.iter().all(|v| v.is_finite()) {
            return Err("invalid canonical block".into());
        }
        if let Some(previous) = self.previous_end {
            if first_frame < previous {
                return Err("canonical frame counter went backwards".into());
            }
            if first_frame > previous {
                if !discontinuity {
                    return Err("unmarked canonical gap".into());
                }
                self.known_missing += first_frame - previous;
            }
        }
        self.previous_end = Some(first_frame + samples.len() as u64);
        self.blocks += 1;
        self.samples += samples.len() as u64;
        self.discontinuities += u64::from(discontinuity);
        for &v in samples.iter() {
            let v = f64::from(v);
            self.squares += v * v;
            self.peak = self.peak.max(v.abs());
        }
        Ok(())
    }
    pub fn rms(&self) -> f64 {
        if self.samples == 0 {
            0.0
        } else {
            (self.squares / self.samples as f64).sqrt()
        }
    }
}

#[test]
fn hardware_probe_evidence_rejects_bad_blocks_and_measures_samples() {
    let mut first_frame = 0;
    let mut samples = vec![0.5_f32, -0.5];
    let mut discontinuity = true;
    let mut evidence = Evidence::default();
    evidence
        .observe(first_frame, &samples, discontinuity)
        .unwrap();
    assert_eq!(evidence.rms(), 0.5);
    assert_eq!(evidence.peak, 0.5);
    first_frame = 4;
    discontinuity = false;
    assert!(
        evidence
            .observe(first_frame, &samples, discontinuity)
            .is_err()
    );
    discontinuity = true;
    evidence
        .observe(first_frame, &samples, discontinuity)
        .unwrap();
    assert_eq!(evidence.known_missing, 2);
    first_frame = 0;
    assert!(
        evidence
            .observe(first_frame, &samples, discontinuity)
            .is_err()
    );
    first_frame = 6;
    samples = vec![f32::NAN];
    assert!(
        evidence
            .observe(first_frame, &samples, discontinuity)
            .is_err()
    );
}
