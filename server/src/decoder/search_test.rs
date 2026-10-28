use super::*;
// Proves: CL-007-04; TC-004-003. Capacity setup is not a decoded-success fixture.
#[test]
fn resource_candidate_and_sic_reserved_storage_ledger() {
    for mode in [Mode::Ft8, Mode::Ft4] {
        let candidates = (0..256)
            .map(|index| Candidate {
                start: index,
                frequency: 1000.,
                score: 1.,
            })
            .collect::<Vec<_>>();
        let pending = (0..32)
            .map(|index| Subtraction {
                start: index,
                frequency: 1000.,
                tones: vec![0u8; mode.symbol_count()],
            })
            .collect::<Vec<_>>();
        let window_seen = (0..256)
            .map(|index| (format!("{index:077b}"), index as u64))
            .collect::<Vec<_>>();
        let bytes = candidates.capacity() * std::mem::size_of::<Candidate>()
            + pending.capacity() * std::mem::size_of::<Subtraction>()
            + pending
                .iter()
                .map(|item| item.tones.capacity())
                .sum::<usize>()
            + window_seen.capacity() * std::mem::size_of::<(String, u64)>()
            + window_seen
                .iter()
                .map(|item| item.0.capacity())
                .sum::<usize>();
        assert_eq!(candidates.len(), 256);
        assert_eq!(pending.len(), 32);
        assert_eq!(window_seen.len(), 256);
        assert!(bytes > 256 * std::mem::size_of::<Candidate>());
        eprintln!(
            "RESOURCE_CAPACITY {}",
            serde_json::json!({
                "owner":"candidate_suppression_sic", "mode":mode, "reserved_bytes":bytes,
                "candidates":256,"pending_sic":32,"window_seen":256,
                "is_decoded_success":false,"whole_workspace_proved":false,
                "separate_owners":["input_window_ring","channel_matrices_recovery","band_plans_rustfft_internal_and_scratch","current_pass_fft","subtractor_and_waveform","modem_history","station_result_ring","teardown_overlap"],
            })
        );
        std::hint::black_box((&candidates, &pending, &window_seen));
    }
}
// Proves: CL-007-04; TC-004-003. Cancels only after a real completed spectrum row.
#[test]
#[cfg(not(debug_assertions))]
fn resource_phase_detection_observes_work_without_publishing() {
    use crate::decoder::resource_observer::{self, Phase};
    use std::sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    };
    for mode in [Mode::Ft8, Mode::Ft4] {
        let samples = resource_observer::pinned_samples(mode);
        for scalar in [false, true] {
            let decoder = if scalar {
                Decoder::with_scalar_transform()
            } else {
                Decoder::new()
            };
            let context = serde_json::json!({"phase":"detection","mode":mode,"scalar":scalar,"positive":true});
            let (positive, _) = resource_observer::poll_to_completion(
                decoder.decode_async(&samples, mode, &|| false),
                &context,
            );
            let expected = positive.unwrap();
            assert_eq!(expected.len(), 1);
            assert_eq!(
                expected[0].payload.payload77,
                resource_observer::cases()["payload77"].as_str().unwrap()
            );
            let cancel = Arc::new(AtomicBool::new(false));
            let observed = resource_observer::install(cancel.clone(), Some(Phase::DetectionRow));
            let mut published = 0;
            let context = serde_json::json!({"phase":"detection","mode":mode,"scalar":scalar,"positive":false});
            let began = std::time::Instant::now();
            let (outcome, timing) = resource_observer::poll_to_completion(
                decoder.decode_into_async(
                    &samples,
                    mode,
                    &|| cancel.load(Ordering::SeqCst),
                    &mut |_| {
                        published += 1;
                        Ok(())
                    },
                ),
                &context,
            );
            observed.record_return(
                &context,
                began,
                timing.returned_at,
                "actual public async decode Future::poll",
            );
            assert_eq!(outcome, Err(DecodeError::Cancelled));
            assert_eq!(observed.report().counts[Phase::DetectionRow as usize], 1);
            assert_eq!(published, 0);
        }
    }
}
// Proves: FR-003, FR-004, CL-007-03.
#[test]
fn sampled_gram_projection_matches_independent_alias_oracles() {
    let fixture: serde_json::Value = serde_json::from_str(include_str!(
        "../../../fixtures/decoder/fit-metric-cases.json"
    ))
    .unwrap();
    let frames = fixture["support_frames"].as_u64().unwrap() as usize;
    let rows = fixture["rows"].as_array().unwrap();
    assert_eq!(rows.len(), 8);
    for row in rows {
        let frequency = row["frequency_hz"].as_f64().unwrap();
        let mut wave = Vec::with_capacity(frames);
        let mut samples = Vec::with_capacity(frames);
        for k in 0..frames {
            let t = (k + 1) as f64 / 12000.;
            let modulation = 0.4 * (2. * PI * t / 0.048).sin();
            wave.push([modulation.cos() as f32, modulation.sin() as f32]);
            let phase = 2. * PI * frequency * t + modulation;
            samples.push((0.6 * phase.cos() - 0.8 * phase.sin()) as f32);
        }
        let actual = coherent(&samples, 0, &wave, &[(288, frames - 288)], frequency, 4);
        let full = coherent(&samples, 0, &wave, &[(288, frames - 288)], frequency, 1);
        let full_expected = oracle_energy(&samples, 288, frames - 288, frequency, &wave);
        assert!((full - full_expected).abs() <= full_expected * 5e-7);
        let expected = row["expected_explained_energy"].as_f64().unwrap();
        assert!(
            (actual - expected).abs() <= expected * 5e-7,
            "{frequency}Hz: actual{actual}, independent{expected}"
        );
    }
}

// Independent scalar projection: direct trig and explicit normal equations, no modem fits.
fn oracle_energy(samples: &[f32], lo: usize, hi: usize, carrier: f64, wave: &[[f32; 2]]) -> f64 {
    let (mut cc, mut ss, mut cs, mut xc, mut xs) = (0., 0., 0., 0., 0.);
    for k in lo..hi {
        let phase = 2. * PI * carrier * (k + 1) as f64 / 12000.;
        let (s, c) = phase.sin_cos();
        let u = wave[k][0] as f64 * c - wave[k][1] as f64 * s;
        let w = wave[k][0] as f64 * s + wave[k][1] as f64 * c;
        cc += u * u;
        ss += w * w;
        cs += u * w;
        xc += samples[k] as f64 * u;
        xs += samples[k] as f64 * w;
    }
    (ss * xc * xc - 2. * cs * xc * xs + cc * xs * xs) / (cc * ss - cs * cs)
}
// Proves: FR-003, FR-004, CL-007-03, CL-007-04.
#[test]
fn refinement_rejects_unrelated_carrier_sampling_alias() {
    for mode in [Mode::Ft4, Mode::Ft8] {
        let n = mode.symbol_frames();
        let frames = n * mode.symbol_count();
        let ramp = mode.ramp_frames();
        let wave = (0..frames)
            .map(|k| {
                let edge = k.min(frames - 1 - k);
                [
                    if edge < ramp {
                        ((1. - (PI * edge as f64 / ramp as f64).cos()) / 2.) as f32
                    } else {
                        1.
                    },
                    0.,
                ]
            })
            .collect::<Vec<_>>();
        for frequency in [400., 1000.] {
            for mixed in [false, true] {
                let samples = (0..frames)
                    .map(|k| {
                        let t = (k + 1) as f64 / 12000.;
                        let unrelated = (2. * PI * (3000. - frequency) * t + 0.7).cos();
                        let phase = 2. * PI * frequency * t;
                        let target = if mixed {
                            wave[k][0] as f64 * (0.25 * phase.cos() - 0.5 * phase.sin())
                        } else {
                            0.
                        };
                        (unrelated + target) as f32
                    })
                    .collect::<Vec<_>>();
                let mut budget = CpuBudget {
                    cancel: &|| false,
                    deadline: Instant::now(),
                    resume: false,
                };
                let result = complete(refine_known(
                    &samples,
                    mode,
                    &vec![0; mode.symbol_count()],
                    Candidate {
                        start: 0,
                        frequency,
                        score: 0.,
                    },
                    &|| false,
                    &mut budget,
                ))
                .unwrap();
                assert_eq!(result.start, 0);
                let expected =
                    oracle_energy(&samples, n / 2, frames - n / 2, result.frequency, &wave);
                let total = samples[n / 2..frames - n / 2]
                    .iter()
                    .map(|&x| (x as f64).powi(2))
                    .sum::<f64>();
                assert!(
                    (result.score - expected).abs() <= total * 5e-7,
                    "{mode:?} {frequency} mixed={mixed}: production grid energy{}, full-rate oracle{expected}",
                    result.score
                );
                if !mixed {
                    assert!(result.score / total < 0.001);
                }
            }
        }
    }
}
// Proves: FR-003, FR-004, CL-007-03.
#[test]
fn full_rate_metric_distinguishes_conjugate_modulated_interferer() {
    let frames = 60480;
    let wave = (0..frames)
        .map(|k| {
            let psi = 0.4 * (2. * PI * (k + 1) as f64 / 12000. / 0.048).sin();
            [psi.cos() as f32, psi.sin() as f32]
        })
        .collect::<Vec<_>>();
    for frequency in [400., 1000.] {
        for mixed in [false, true] {
            let samples = (0..frames)
                .map(|k| {
                    let t = (k + 1) as f64 / 12000.;
                    let psi = 0.4 * (2. * PI * t / 0.048).sin();
                    let unrelated = (2. * PI * (3000. - frequency) * t - psi + 0.7).cos();
                    let phase = 2. * PI * frequency * t + psi;
                    (unrelated
                        + if mixed {
                            0.25 * phase.cos() - 0.5 * phase.sin()
                        } else {
                            0.
                        }) as f32
                })
                .collect::<Vec<_>>();
            let expected = oracle_energy(&samples, 288, frames - 288, frequency, &wave);
            let actual = coherent(&samples, 0, &wave, &[(288, frames - 288)], frequency, 1);
            let energy = samples[288..frames - 288]
                .iter()
                .map(|&x| (x as f64).powi(2))
                .sum::<f64>();
            assert!((actual - expected).abs() <= energy * 5e-7);
            if !mixed {
                let aliased = coherent(&samples, 0, &wave, &[(288, frames - 288)], frequency, 4);
                let strided_energy = samples[288..frames - 288]
                    .iter()
                    .step_by(4)
                    .map(|&x| (x as f64).powi(2))
                    .sum::<f64>();
                assert!(actual / energy < 0.001 && aliased / strided_energy > 0.999);
            }
        }
    }
}
