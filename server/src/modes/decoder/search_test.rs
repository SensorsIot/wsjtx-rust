use super::super::{ChannelWord, QsoProgress};
use super::*;

// Capacity setup is not a decoded-success fixture.
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
// Cancels at the decoder's own checks before the first pass's spectrum: nothing is published, and the decode returns within 250 ms of its last unanswered check.
#[test]
#[cfg(not(debug_assertions))]
fn resource_phase_detection_observes_work_without_publishing() {
    use wstx_test_tools::resource_observer::{self, CancelPoint};
    for mode in [Mode::Ft8, Mode::Ft4] {
        let samples =
            resource_observer::pinned_samples(if mode == Mode::Ft8 { "ft8" } else { "ft4" });
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
            // Call 1 is the entry check of decode_into_async, call 2 the window's checkpoint
            // before BandPlan::new, call 3 its checkpoint after Subtractor::new (or call 2's
            // check again when that poll returned Pending). The answering call 4 is at most
            // the first round checkpoint of parallel::map in Spectrum::new.
            let observed = CancelPoint::after(3);
            let mut published = 0;
            let context = serde_json::json!({"phase":"detection","mode":mode,"scalar":scalar,"positive":false});
            let began = std::time::Instant::now();
            let (outcome, timing) = resource_observer::poll_to_completion(
                decoder.decode_into_async(&samples, mode, &|| observed.cancelled(), &mut |_| {
                    published += 1;
                    Ok(())
                }),
                &context,
            );
            observed.record_return(
                &context,
                began,
                timing.returned_at,
                "actual public async decode Future::poll",
            );
            assert_eq!(outcome, Err(DecodeError::Cancelled));
            assert_eq!(published, 0);
        }
    }
}
#[test]
fn sampled_gram_projection_matches_independent_alias_oracles() {
    let fixture: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../fixtures/decoder/fit-metric-cases.json"
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
                let plan = BandPlan::new(mode, samples.len(), false).unwrap();
                let mut pass = complete(plan.current_pass(&samples, &mut budget)).unwrap();
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
                    &mut pass,
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

// Detail test of WstxDecode: pruned grid scoring keeps the exhaustive result.
#[test]
fn ranked_refinement_matches_exhaustive_grid_search() {
    let channel = Channel::new();
    for mode in [Mode::Ft8, Mode::Ft4] {
        let frames = if mode == Mode::Ft8 { 180000 } else { 90000 };
        let word = |seed: u8| {
            let bits = std::array::from_fn(|i| ((i as u8).wrapping_mul(seed) >> 3) & 1);
            channel.tones(&channel.encode(&bits, mode), mode)
        };
        // A crowded frame: the target, an overlapping stronger station one tone away,
        // an unrelated carrier and deterministic noise.
        let (target, other) = (word(37), word(91));
        let (start, carrier) = (3000usize, 1234.567);
        let spacing = mode.spacing();
        let a = quadratures(mode, &target, carrier).unwrap();
        let b = quadratures(mode, &other, carrier + spacing * 1.37).unwrap();
        let mut state = 12345u64;
        let samples = (0..frames)
            .map(|k: usize| {
                state = state
                    .wrapping_mul(6364136223846793005)
                    .wrapping_add(1442695040888963407);
                let noise = ((state >> 33) as f64 / (1u64 << 31) as f64 - 0.5) * 0.4;
                let t = (k + 1) as f64 / 12000.;
                let mut x = noise + 0.3 * (2. * PI * 1900. * t).cos();
                if let Some(w) = k.checked_sub(start).and_then(|i| a.get(i)) {
                    x += 0.2 * w[0] as f64;
                }
                if let Some(w) = k.checked_sub(start + 700).and_then(|i| b.get(i)) {
                    x += 0.35 * w[0] as f64;
                }
                x as f32
            })
            .collect::<Vec<_>>();
        let never = || false;
        let mut budget = CpuBudget::new(&never);
        let plan = BandPlan::new(mode, samples.len(), false).unwrap();
        let mut pass = complete(plan.current_pass(&samples, &mut budget)).unwrap();
        let n = mode.symbol_frames();
        for (dt, df) in [(n as isize / 9, 0.21), (-(n as isize) / 7, -0.37)] {
            let c = Candidate {
                start: (start as isize + dt) as usize,
                frequency: carrier + df * spacing / 6.25,
                score: 0.,
            };
            let ranked = complete(refine_known(
                &samples,
                mode,
                &target,
                c,
                &never,
                &mut budget,
                &mut pass,
            ))
            .unwrap();
            let exhaustive = complete(refine_exhaustive(
                &samples,
                mode,
                &target,
                c,
                &never,
                &mut budget,
            ))
            .unwrap();
            let wave = quadratures(mode, &target, 0.).unwrap();
            let full = coherent(
                &samples,
                ranked.start,
                &wave,
                &[(n / 2, wave.len() - n / 2)],
                ranked.frequency,
                1,
            );
            assert_eq!(ranked.score, full, "{mode:?}: returned score is full rate");
            assert!(
                ranked.start.abs_diff(exhaustive.start) <= 32
                    && (ranked.frequency - exhaustive.frequency).abs() <= 0.02
                    && ranked.score >= 0.999 * exhaustive.score,
                "{mode:?} {dt}/{df}: ranked {ranked:?} exhaustive {exhaustive:?}"
            );
            assert!(
                ranked.start.abs_diff(start) <= 240 && (ranked.frequency - carrier).abs() <= 1.
            );
        }
    }
}

/// The padded residual case: a strong FT8 frame that began 1.5 s before the window
/// (its first 1.5 s, including the first Costas block, missing) masks a weak complete frame
/// on almost the same carrier.
fn partial_interferer_window() -> (Vec<f32>, Vec<u8>, Vec<u8>) {
    let channel = Channel::new();
    let word = |seed: u8| {
        let bits: [u8; 77] = std::array::from_fn(|i| ((i as u8).wrapping_mul(seed) >> 3) & 1);
        channel.tones(&channel.encode(&bits, Mode::Ft8), Mode::Ft8)
    };
    let (strong, weak) = (word(91), word(37));
    let a = quadratures(Mode::Ft8, &strong, 1000.).unwrap();
    let b = quadratures(Mode::Ft8, &weak, 1003.).unwrap();
    let mut state = 7u64;
    let samples = (0..180000usize)
        .map(|k| {
            state = state
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            let mut x = ((state >> 33) as f64 / (1u64 << 31) as f64 - 0.5) * 0.2;
            if let Some(w) = a.get(k + 18000) {
                x += w[0] as f64;
            }
            if let Some(w) = k.checked_sub(6000).and_then(|i| b.get(i)) {
                x += 0.08 * w[0] as f64;
            }
            x as f32
        })
        .collect();
    (samples, strong, weak)
}

// A frame that runs past the
// window start is found and subtracted but never published; the weak frame under it decodes.
// Proves: TC-004-002
#[test]
fn partial_frame_interferer_is_subtracted_not_published() {
    let channel = Channel::new();
    let (samples, strong, weak) = partial_interferer_window();
    let decoded = Decoder::new()
        .decode(&samples, Mode::Ft8, &|| false)
        .unwrap();
    let tones = |d: &Decode| {
        let bits: [u8; 77] = std::array::from_fn(|i| d.payload.payload77.as_bytes()[i] - b'0');
        channel.tones(&channel.encode(&bits, Mode::Ft8), Mode::Ft8)
    };
    assert!(
        decoded
            .iter()
            .any(|d| tones(d) == weak && d.start_frame.abs_diff(6000) <= 240),
        "weak complete frame under the partial interferer: {decoded:?}"
    );
    assert!(
        decoded.iter().all(|d| tones(d) != strong),
        "a frame starting 1.5 s before the window is never published: {decoded:?}"
    );
}

/// A 15 s FT8 window: uniform noise of the given peak-to-peak width plus frames (tones,
/// carrier, start relative to the window, possibly negative or past the end, amplitude).
fn ft8_window(frames: &[(&[u8], f64, isize, f64)], seed: u64, noise: f64) -> Vec<f32> {
    let waves = frames
        .iter()
        .map(|&(tones, carrier, start, amplitude)| {
            (
                quadratures(Mode::Ft8, tones, carrier).unwrap(),
                start,
                amplitude,
            )
        })
        .collect::<Vec<_>>();
    let mut state = seed;
    (0..180000isize)
        .map(|k| {
            state = state
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            let mut x = ((state >> 33) as f64 / (1u64 << 31) as f64 - 0.5) * noise;
            for (wave, start, amplitude) in &waves {
                if let Some(w) = usize::try_from(k - start).ok().and_then(|i| wave.get(i)) {
                    x += amplitude * w[0] as f64;
                }
            }
            x as f32
        })
        .collect()
}
fn ft8_word(seed: u8) -> Vec<u8> {
    let channel = Channel::new();
    let bits: [u8; 77] = std::array::from_fn(|i| ((i as u8).wrapping_mul(seed) >> 3) & 1);
    channel.tones(&channel.encode(&bits, Mode::Ft8), Mode::Ft8)
}
fn decoded_tones(d: &Decode) -> Vec<u8> {
    let channel = Channel::new();
    let bits: [u8; 77] = std::array::from_fn(|i| d.payload.payload77.as_bytes()[i] - b'0');
    channel.tones(&channel.encode(&bits, Mode::Ft8), Mode::Ft8)
}

// A strong frame that
// runs 0.64 s past the window end is subtracted, not published; the weak frame under it decodes.
// Proves: TC-004-002
#[test]
fn frame_past_the_window_end_is_subtracted_not_published() {
    let (strong, weak) = (ft8_word(91), ft8_word(37));
    let samples = ft8_window(
        &[(&strong, 1000., 36000, 1.), (&weak, 1003., 6000, 0.08)],
        7,
        0.2,
    );
    let decoded = Decoder::new()
        .decode(&samples, Mode::Ft8, &|| false)
        .unwrap();
    assert!(
        decoded
            .iter()
            .any(|d| decoded_tones(d) == weak && d.start_frame.abs_diff(6000) <= 240),
        "weak complete frame under the end-edge interferer: {decoded:?}"
    );
    assert!(
        decoded.iter().all(|d| decoded_tones(d) != strong),
        "a frame ending 0.64 s after the window is never published: {decoded:?}"
    );
}

// A frame starting up
// to half a symbol (960 frames) before the window is published at start 0; one starting
// further before is not.
// Proves: TC-004-002
#[test]
fn half_symbol_publication_boundary() {
    let tones = ft8_word(53);
    for (start, published) in [(-900isize, true), (-1100, false)] {
        let samples = ft8_window(&[(&tones, 1200., start, 0.5)], 11, 0.2);
        let decoded = Decoder::new()
            .decode(&samples, Mode::Ft8, &|| false)
            .unwrap();
        let found = decoded
            .iter()
            .filter(|d| decoded_tones(d) == tones)
            .collect::<Vec<_>>();
        assert_eq!(
            found.len(),
            usize::from(published),
            "start {start}: {decoded:?}"
        );
        if published {
            assert_eq!(found[0].start_frame, 0, "start {start}: {decoded:?}");
        }
    }
}

// The same word on carriers 100 Hz
// apart is published once, and both copies are subtracted: a weak frame 3 Hz from the second
// copy decodes.
// Proves: TC-004-002
#[test]
fn duplicate_on_a_distant_carrier_is_subtracted_and_published_once() {
    let (word, weak) = (ft8_word(91), ft8_word(37));
    let samples = ft8_window(
        &[
            (&word, 1000., 6000, 1.),
            (&word, 1100., 6000, 0.5),
            (&weak, 1103., 6000, 0.03),
        ],
        13,
        0.2,
    );
    let decoded = Decoder::new()
        .decode(&samples, Mode::Ft8, &|| false)
        .unwrap();
    assert_eq!(
        decoded.iter().filter(|d| decoded_tones(d) == word).count(),
        1,
        "{decoded:?}"
    );
    assert!(
        decoded.iter().any(|d| decoded_tones(d) == weak),
        "weak frame under the subtracted second copy: {decoded:?}"
    );
}

// Rejected exactly when an FT8 word has at most
// 10 of 21 Costas hits and a measured SNR below -25 dB.
#[test]
fn weak_word_guard_boundaries() {
    assert!(weak_word(Mode::Ft8, 10, Some(-25.01)));
    assert!(weak_word(Mode::Ft8, 0, Some(-40.)));
    assert!(!weak_word(Mode::Ft8, 11, Some(-40.)));
    assert!(!weak_word(Mode::Ft8, 10, Some(-25.)));
    assert!(!weak_word(Mode::Ft8, 10, None));
    assert!(!weak_word(Mode::Ft4, 0, Some(-40.)));
}

// A weak word that fails at its fine point
// decodes at the nearby point holding the most frame energy.
#[test]
fn failed_fine_point_retries_at_the_data_point() {
    let channel = Channel::new();
    let decoder = Decoder::new();
    let tones = ft8_word(77);
    let cancel = || false;
    let truth = Candidate {
        start: 6000,
        frequency: 1500.,
        score: 0.,
    };
    let displaced = Candidate {
        start: 6120,
        frequency: 1500.5,
        score: 0.,
    };
    let mut checked = None;
    'search: for seed in 1..40u64 {
        for step in 0..16 {
            let amplitude = 0.004 + step as f64 * 0.0005;
            let samples = ft8_window(&[(&tones, 1500., 6000, amplitude)], seed, 0.2);
            let plan = BandPlan::new(Mode::Ft8, samples.len(), false).unwrap();
            let mut budget = CpuBudget::new(&cancel);
            let mut pass = complete(plan.current_pass(&samples, &mut budget)).unwrap();
            let mut at = |c| {
                complete(bitmetrics::observe(
                    &mut pass,
                    c,
                    &channel,
                    &APriori::default(),
                    &mut budget,
                ))
                .unwrap()
            };
            if at(displaced).is_some() || at(truth).is_none() {
                continue;
            }
            let verified = complete(decoder.verify(
                &samples,
                displaced,
                &APriori::default(),
                &cancel,
                &|_: &[f32], _, _: &[u8]| None,
                &mut pass,
                &mut budget,
            ))
            .unwrap();
            checked = Some((seed, amplitude, verified.map(|(_, t, _, _)| t == tones)));
            break 'search;
        }
    }
    let (seed, amplitude, verified) = checked.expect("a window where only the true point decodes");
    assert_eq!(verified, Some(true), "seed {seed}, amplitude {amplitude}");
}

/// A window of `length` frames: uniform noise (0.2 peak to peak) plus one frame of `mode`
/// (tones, carrier, start, amplitude).
fn mode_window(
    mode: Mode,
    tones: &[u8],
    carrier: f64,
    start: usize,
    amplitude: f64,
    seed: u64,
    length: usize,
) -> Vec<f32> {
    let wave = quadratures(mode, tones, carrier).unwrap();
    let mut state = seed;
    (0..length)
        .map(|k| {
            state = state
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            let mut x = ((state >> 33) as f64 / (1u64 << 31) as f64 - 0.5) * 0.2;
            if let Some(w) = k.checked_sub(start).and_then(|i| wave.get(i)) {
                x += amplitude * w[0] as f64;
            }
            x as f32
        })
        .collect()
}
/// The a-priori context of `my` working `dx` (Rx = Tx = 1500 Hz).
fn qso(my: &str, dx: &str, progress: QsoProgress) -> APriori {
    let bits = crate::transmit::pack(&format!("{my} {dx} RRR"))
        .unwrap()
        .bits;
    APriori {
        my_call: Some(bits[..29].try_into().unwrap()),
        dx_call: Some(bits[29..58].try_into().unwrap()),
        progress,
        rx_hz: 1500.,
        tx_hz: 1500.,
        cq_only: false,
    }
}
/// The channel word and tones of a message in `mode`.
fn message(mode: Mode, text: &str) -> (ChannelWord, Vec<u8>) {
    let channel = Channel::new();
    let bits = crate::transmit::pack(text).unwrap().bits;
    let word = channel.encode(&bits, mode);
    (word, channel.tones(&word, mode))
}
/// The word observed at the true point of a one-frame window under a context.
fn observed(
    mode: Mode,
    samples: &[f32],
    at: Candidate,
    ap: &APriori,
) -> Option<(ChannelWord, Option<u8>)> {
    let cancel = || false;
    let plan = BandPlan::new(mode, samples.len(), false).unwrap();
    let mut budget = CpuBudget::new(&cancel);
    let mut pass = complete(plan.current_pass(samples, &mut budget)).unwrap();
    complete(bitmetrics::observe(
        &mut pass,
        at,
        &Channel::new(),
        ap,
        &mut budget,
    ))
    .unwrap()
}
const TRUE_POINT: Candidate = Candidate {
    start: 6000,
    frequency: 1500.,
    score: 0.,
};
/// The first (seed, amplitude) whose frame fails unassisted and under every `wrong` context,
/// below the first level of its seed that decodes unassisted,
/// decodes under `right` with AP type `kind` and satisfies `also`.
fn weak_assisted_window(
    mode: Mode,
    text: &str,
    right: &APriori,
    wrong: &[APriori],
    kind: u8,
    also: impl Fn(&[f32]) -> bool,
) -> (u64, f64, Vec<f32>) {
    let (word, tones) = message(mode, text);
    let length = if mode == Mode::Ft8 { 180000 } else { 90000 };
    for seed in 1..60u64 {
        for step in 0..24 {
            let amplitude = 0.002 + step as f64 * 0.0005;
            let samples = mode_window(mode, &tones, 1500., 6000, amplitude, seed, length);
            // Decoded without any a-priori pass: the level is above the unassisted limit.
            if let Some((_, None)) = observed(mode, &samples, TRUE_POINT, &APriori::default()) {
                break;
            }
            if observed(mode, &samples, TRUE_POINT, right) != Some((word, Some(kind))) {
                continue;
            }
            for ap in wrong {
                assert_eq!(
                    observed(mode, &samples, TRUE_POINT, ap),
                    None,
                    "{text}: seed {seed}, amplitude {amplitude}, {ap:?}"
                );
            }
            if !also(&samples) {
                continue;
            }
            return (seed, amplitude, samples);
        }
    }
    panic!("{text}: no weak window that only the a-priori pass decodes");
}

// Weak FT8 QSO messages
// below the unassisted limit decode only through the a-priori pass with the right MyCall,
// DxCall, QSO state and Rx/Tx frequency, and the published record carries the AP type.
// Proves: TC-004-002
#[test]
fn weak_qso_words_decode_only_with_the_right_calls() {
    use QsoProgress::*;
    for (text, progress, kind) in [
        ("HB9BLA K1ABC FN42", Report, 3),
        ("HB9BLA K1ABC RR73", Rogers, 6),
    ] {
        let right = qso("HB9BLA", "K1ABC", progress);
        let mut far = right.clone();
        (far.rx_hz, far.tx_hz) = (1600., 1700.);
        let mut wrong = vec![
            qso("HB9BLA", "K9XYZ", Rogers),
            qso("DL1ABC", "K1ABC", progress),
            APriori {
                cq_only: true,
                ..right.clone()
            },
        ];
        // Type 2 (MyCall ??? ???) needs no Rx/Tx proximity; the DxCall types do.
        if progress == Rogers {
            wrong.push(far);
        }
        // The full decode must find the frame's candidate: with the right context the word is
        // published, without any context it is not.
        let decode = |samples: &[f32], ap: &APriori| {
            let mut state = DecodeState::new(Mode::Ft8);
            state.set_a_priori(ap.clone());
            let mut decoded = vec![];
            complete(Decoder::new().decode_window_into_async(
                samples.to_vec(),
                0,
                &mut state,
                &|| false,
                &mut |d| {
                    decoded.push(d.clone());
                    Ok(())
                },
            ))
            .unwrap();
            decoded
        };
        let has = |decoded: &[Decode]| {
            decoded
                .iter()
                .any(|d| d.payload.text.as_deref() == Some(text))
        };
        let (seed, amplitude, samples) =
            weak_assisted_window(Mode::Ft8, text, &right, &wrong, kind, |samples| {
                has(&decode(samples, &right)) && !has(&decode(samples, &APriori::default()))
            });
        let decoded = decode(&samples, &right);
        let found = decoded
            .iter()
            .find(|d| d.payload.text.as_deref() == Some(text))
            .unwrap_or_else(|| panic!("{text}: seed {seed}, amplitude {amplitude}: {decoded:?}"));
        // In the full decode the first matching type of the state may be an earlier one at
        // its refined point (type 3 before type 6 in the rogers state).
        assert!(
            found.a_priori.is_some_and(|k| (2..=kind).contains(&k)),
            "{found:?}"
        );
        let record = serde_json::to_value(found).unwrap();
        assert_eq!(record["a_priori"], found.a_priori.unwrap(), "{record}");
    }
}

// Under a wrong DxCall, in every QSO state, and in pure
// noise under the right one, the a-priori passes never yield a word other than the one on
// the air, at any level from buried to strong, in FT8 and FT4.
// Proves: TC-004-002
#[test]
fn wrong_dx_call_never_yields_a_false_word() {
    use QsoProgress::*;
    let mut assisted = 0;
    for mode in [Mode::Ft8, Mode::Ft4] {
        let length = if mode == Mode::Ft8 { 180000 } else { 90000 };
        for text in ["HB9BLA K1ABC FN42", "HB9BLA K1ABC RR73", "HB9BLA K1ABC -12"] {
            let (word, tones) = message(mode, text);
            for seed in 1..9u64 {
                for amplitude in [0., 0.003, 0.005, 0.007, 0.01, 0.02] {
                    let samples = mode_window(mode, &tones, 1500., 6000, amplitude, seed, length);
                    for progress in [Calling, Replying, Report, RogerReport, Rogers, Signoff] {
                        for dx in ["K9XYZ", "W1AW", "K1ABD"] {
                            let ap = qso("HB9BLA", dx, progress);
                            if let Some((found, kind)) = observed(mode, &samples, TRUE_POINT, &ap) {
                                assert!(
                                    found == word && amplitude > 0.,
                                    "{mode:?} {text} under {dx} {progress:?}: false word \
                                     (type {kind:?}), seed {seed}, amplitude {amplitude}"
                                );
                                assisted += usize::from(kind.is_some());
                            }
                        }
                        if amplitude == 0. {
                            let ap = qso("HB9BLA", "K1ABC", progress);
                            assert_eq!(
                                observed(mode, &samples, TRUE_POINT, &ap),
                                None,
                                "{mode:?} noise, seed {seed}"
                            );
                        }
                    }
                }
            }
        }
    }
    eprintln!("A_PRIORI wrong-DxCall checks: {assisted} correct a-priori words");
}

// FT4 a-priori: a weak CQ below the unassisted limit
// decodes through type 1 without any QSO context, and a weak HB9BLA K1ABC RR73 through type 6
// with the right calls only.
// Proves: TC-004-001
#[test]
fn ft4_a_priori_recovers_weak_cq_and_qso_words() {
    use QsoProgress::*;
    let mut no_my_call = qso("HB9BLA", "K1ABC", Rogers);
    no_my_call.my_call = None;
    weak_assisted_window(
        Mode::Ft4,
        "CQ K1ABC FN42",
        &APriori::default(),
        &[],
        1,
        |_| true,
    );
    weak_assisted_window(
        Mode::Ft4,
        "HB9BLA K1ABC RR73",
        &qso("HB9BLA", "K1ABC", Rogers),
        &[qso("HB9BLA", "K9XYZ", Rogers), no_my_call],
        6,
        |_| true,
    );
}

/// The unpruned three-stage search: every grid point at full rate (test oracle).
async fn refine_exhaustive(
    samples: &[f32],
    mode: Mode,
    tones: &[u8],
    c: Candidate,
    cancel: &impl Fn() -> bool,
    budget: &mut CpuBudget<'_>,
) -> Result<Candidate, DecodeError> {
    let wave = quadratures(mode, tones, 0.).unwrap();
    let n = mode.symbol_frames();
    let ranges = [(n / 2, wave.len() - n / 2)];
    let step = 6000. / wave.len() as f64;
    let count = mode.symbol_count() as i32;
    let lower = (c.frequency - mode.spacing() / 2.).max(DECODE_BAND_LOW_HZ);
    let upper = (c.frequency + mode.spacing() / 2.).min(DECODE_BAND_HIGH_HZ);
    let mut frequencies = (-count..=count)
        .map(|df| c.frequency + df as f64 * step)
        .filter(|&f| f >= lower && f <= upper)
        .chain([lower, upper])
        .collect::<Vec<_>>();
    frequencies.sort_by(f64::total_cmp);
    frequencies.dedup_by(|a, b| (*a - *b).abs() < 1e-12);
    let mut best = Candidate { score: -1., ..c };
    for dt in -4isize..=4 {
        let start = c.start as isize + dt * (n / 16) as isize;
        if start < 0 || start as usize + wave.len() > samples.len() {
            continue;
        }
        for &frequency in &frequencies {
            budget.checkpoint().await?;
            if cancel() {
                return Err(DecodeError::Cancelled);
            }
            if !(DECODE_BAND_LOW_HZ - 1e-7..=DECODE_BAND_HIGH_HZ + 1e-7).contains(&frequency) {
                continue;
            }
            let score = coherent(samples, start as usize, &wave, &ranges, frequency, 1);
            if score > best.score
                || score == best.score
                    && (frequency < best.frequency
                        || frequency == best.frequency && (start as usize) < best.start)
            {
                best = Candidate {
                    start: start as usize,
                    frequency,
                    score,
                };
            }
        }
    }
    let coarse = best;
    for dt in -(n as isize / 16)..=n as isize / 16 {
        if dt % (n as isize / 128).max(1) != 0 {
            continue;
        }
        let start = coarse.start as isize + dt;
        if start < 0 || start as usize + wave.len() > samples.len() {
            continue;
        }
        for df in -4..=4 {
            budget.checkpoint().await?;
            if cancel() {
                return Err(DecodeError::Cancelled);
            }
            let frequency = coarse.frequency + df as f64 * step / 8.;
            if !(DECODE_BAND_LOW_HZ - 1e-7..=DECODE_BAND_HIGH_HZ + 1e-7).contains(&frequency) {
                continue;
            }
            let score = coherent(samples, start as usize, &wave, &ranges, frequency, 1);
            if score > best.score
                || score == best.score
                    && (frequency < best.frequency
                        || frequency == best.frequency && (start as usize) < best.start)
            {
                best = Candidate {
                    start: start as usize,
                    frequency,
                    score,
                };
            }
        }
    }
    let fine = best;
    let radius = (n as isize / 128).max(1);
    for dt in -radius..=radius {
        let start = fine.start as isize + dt;
        if start < 0 || start as usize + wave.len() > samples.len() {
            continue;
        }
        budget.checkpoint().await?;
        if cancel() {
            return Err(DecodeError::Cancelled);
        }
        let frequency = fine.frequency;
        let score = coherent(samples, start as usize, &wave, &ranges, frequency, 1);
        if score > best.score
            || score == best.score
                && (frequency < best.frequency
                    || frequency == best.frequency && (start as usize) < best.start)
        {
            best = Candidate {
                start: start as usize,
                frequency: fine.frequency,
                score,
            };
        }
    }
    Ok(best)
}
