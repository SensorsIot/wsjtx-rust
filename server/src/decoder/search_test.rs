use super::*;

// Direct library capacity evidence. Never invoked by an ordinary test selection.
#[test]
#[ignore = "requires reviewed retained-handle parent and pinned inputs"]
#[cfg(not(debug_assertions))]
fn resource_capacity_owned_child() {
    use crate::decoder::{history, resource_observer as observer};
    use std::sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    };
    let nonce = std::env::var("WSTX_RESOURCE_CAPACITY_NONCE").expect("owned parent required");
    assert!(nonce.len() == 32 && nonce.bytes().all(|c| c.is_ascii_hexdigit()));
    let handshake = |state: &str, reply: &str| {
        eprintln!(
            "RESOURCE_HANDSHAKE {}",
            serde_json::json!({"state":state,"nonce":nonce})
        );
        let mut line = String::new();
        std::io::stdin().read_line(&mut line).unwrap();
        assert!(line.len() <= 256);
        assert_eq!(line.trim_end(), format!("{reply} {nonce}"));
    };
    handshake("READY", "START");
    for mode in [Mode::Ft8, Mode::Ft4] {
        let (mut retained_state, records, history_ledger) = history::capacity_state(mode);
        eprintln!("RESOURCE_CAPACITY {}", history_ledger);
        // Retain actual nested variant witnesses, never arbitrary padded buffers.
        let manifest: serde_json::Value = serde_json::from_str(include_str!(
            "../../../fixtures/decoder/independent-vectors/manifest.json"
        ))
        .unwrap();
        let witnesses = manifest["vectors"]
            .as_array()
            .unwrap()
            .iter()
            .map(|row| {
                let bits = std::array::from_fn(|i| {
                    row["payload77"].as_str().unwrap().as_bytes()[i] - b'0'
                });
                Decode {
                    payload: unpack(&bits),
                    start_frame: 0,
                    frequency_hz: 1000.,
                    snr_db: None,
                }
            })
            .collect::<Vec<_>>();
        assert!(
            witnesses
                .iter()
                .all(|record| record.payload.status == crate::decoder::PayloadStatus::Decoded)
        );
        eprintln!(
            "RESOURCE_CAPACITY {}",
            serde_json::json!({"owner":"variant_witnesses",
            "records":witnesses.len(),"inline_reserved_bytes":witnesses.capacity()*std::mem::size_of::<Decode>(),
            "nested_reserved_bytes":witnesses.iter().map(history::retained_record_bytes).sum::<usize>(),
            "is_decoded_success":false,"all_legal_graph_maxima_proved":false})
        );
        let candidates = (0..256)
            .map(|start| Candidate {
                start,
                frequency: 1000.,
                score: 1.,
            })
            .collect::<Vec<_>>();
        let pending = (0..32)
            .map(|start| Subtraction {
                start,
                frequency: 1000.,
                tones: vec![0; mode.symbol_count()],
            })
            .collect::<Vec<_>>();
        let seen = (0..256)
            .map(|i| (format!("{i:077b}"), i as u64))
            .collect::<Vec<_>>();
        eprintln!(
            "RESOURCE_CAPACITY {}",
            serde_json::json!({"owner":"direct_candidate_sic_suppression",
            "candidates":candidates.len(),"pending_sic":pending.len(),"window_seen":seen.len(),
            "reserved_bytes":candidates.capacity()*std::mem::size_of::<Candidate>()+
                pending.capacity()*std::mem::size_of::<Subtraction>()+pending.iter().map(|s|s.tones.capacity()).sum::<usize>()+
                seen.capacity()*std::mem::size_of::<(String,u64)>()+seen.iter().map(|s|s.0.capacity()).sum::<usize>(),
            "is_decoded_success":false,"internal_search_heap_maximum_exercised":false})
        );
        let base = observer::pinned_samples_no_probe(mode);
        let samples = base
            .iter()
            .copied()
            .cycle()
            .take(360000)
            .collect::<Vec<_>>();
        for scalar in [false, true] {
            let (long, short) = if mode == Mode::Ft8 {
                (384000, 6400)
            } else {
                (362880, 20160)
            };
            let scratch = [(long, false), (short, true), (32, false)].map(|(n, inv)| {
                crate::decoder::baseband::fft_plan(n, inv, scalar).get_inplace_scratch_len()
            });
            eprintln!(
                "RESOURCE_STORAGE {}",
                serde_json::json!({"owner":"reconstructed_bandplan_query",
                "mode":mode,"scalar":scalar,"long_len":long,"short_len":short,"scratch_lengths":scratch,
                "direct_private_field_observation":false})
            );
            let decoder = if scalar {
                Decoder::with_scalar_transform()
            } else {
                Decoder::new()
            };
            let cancel = Arc::new(AtomicBool::new(false));
            let observed = observer::install(cancel.clone(), None);
            let mut state = DecodeState::new_live(mode);
            let mut callbacks = 0;
            complete(decoder.decode_window_into_async(
                samples.clone(),
                0,
                &mut state,
                &|| false,
                &mut |record| {
                    assert_eq!(
                        record.payload.payload77,
                        observer::cases()["payload77"].as_str().unwrap()
                    );
                    callbacks += 1;
                    Ok(())
                },
            ))
            .unwrap();
            assert!(callbacks > 0);
            // Exercise the real complete subtraction kernel even if search chose no SIC.
            let bits = std::array::from_fn(|i| {
                observer::cases()["payload77"].as_str().unwrap().as_bytes()[i] - b'0'
            });
            let tones = decoder
                .channel
                .tones(&decoder.channel.encode(&bits, mode), mode);
            let wave = quadratures(mode, &tones, 1000.).unwrap();
            let mut residual = samples.clone();
            let mut subtractor = Subtractor::new(mode, scalar).unwrap();
            eprintln!("RESOURCE_STORAGE {}", subtractor.capacity_ledger());
            let never = || false;
            complete(subtractor.subtract(&mut residual, 6000, &wave, &mut CpuBudget::new(&never)))
                .unwrap();
            assert_ne!(residual, samples);
            let report = observed.report();
            assert!(report.counts[observer::Phase::SubtractionCommit as usize] > 0);
            eprintln!(
                "RESOURCE_KERNEL {}",
                serde_json::json!({"mode":mode,"scalar":scalar,"frames":samples.len(),
                "complete":true,"actual_decoded_callbacks":callbacks,"phase_counts":report.counts,
                "direct_subtraction_exercised":true,"prepared_records_are_decodes":false})
            );
            drop(observed);
            drop(subtractor);
            drop(residual);
            drop(wave);
            let cancelled = observer::install(cancel.clone(), Some(observer::Phase::DetectionRow));
            let mut unexpected = 0;
            assert_eq!(
                complete(decoder.decode_window_into_async(
                    samples.clone(),
                    0,
                    &mut retained_state,
                    &|| cancel.load(Ordering::SeqCst),
                    &mut |_| {
                        unexpected += 1;
                        Ok(())
                    }
                )),
                Err(DecodeError::Cancelled)
            );
            assert_eq!(unexpected, 0);
            assert_eq!(retained_state.available_count(), 2048);
            assert_eq!(
                cancelled.report().counts[observer::Phase::DetectionRow as usize],
                1
            );
            eprintln!(
                "RESOURCE_CAPACITY {}",
                serde_json::json!({"owner":"retained_history_cancel",
                "mode":mode,"scalar":scalar,"remaining_keys":retained_state.available_count(),
                "original_token_cancelled":cancel.load(Ordering::SeqCst),
                "actual_phase_counts":cancelled.report().counts,"unexpected_callbacks":unexpected,
                "manager_ack_proved":false,"cancellation_sla_proved":false})
            );
            std::hint::black_box((&records, &witnesses, &candidates, &pending, &seen));
        }
    }
    eprintln!(
        "RESOURCE_DISPOSITION {}",
        serde_json::json!({"unknown_maximum_nested_record_allowance":true,
        "unknown_unexercised_internal_grid_heap_allowance":true,"workspace_sufficient_proof":"INCONCLUSIVE",
        "station_96mib_proved":false,"all_test_owners_dropped":true})
    );
    handshake("FINISHED", "RELEASE");
}
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
