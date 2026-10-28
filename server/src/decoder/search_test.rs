use super::*;

/// Test-owned FT4 upper envelope. These are legal typed capacity entries, not detections.
#[cfg(not(debug_assertions))]
struct Ft4CapacityReserve {
    times: Vec<usize>,
    old_times: Vec<usize>,
    physical: Vec<(usize, Candidate)>,
    old_physical: Vec<(usize, Candidate)>,
    physical_sort: Vec<std::mem::MaybeUninit<(usize, Candidate)>>,
    coarse: Vec<(f64, f64)>,
    old_coarse: Vec<(f64, f64)>,
    coarse_sort: Vec<std::mem::MaybeUninit<(f64, f64)>>,
    converted: Vec<f64>,
    powers: Vec<f64>,
    old_powers: Vec<f64>,
    outputs: Vec<Vec<Candidate>>,
    refinement: Vec<f64>,
    old_refinement: Vec<f64>,
}
#[cfg(not(debug_assertions))]
impl Ft4CapacityReserve {
    fn new() -> Self {
        fn push_trace<T>(
            items: impl IntoIterator<Item = T>,
        ) -> (Vec<T>, Vec<serde_json::Value>, usize) {
            let mut out = vec![];
            let mut trace = vec![];
            let mut largest_old = 0;
            for item in items {
                let old = out.capacity();
                out.push(item);
                let new = out.capacity();
                if old != new {
                    largest_old = largest_old.max(old);
                    trace.push(
                        serde_json::json!({"len":out.len(),"old_capacity":old,"new_capacity":new}),
                    );
                }
            }
            (out, trace, largest_old)
        }
        fn emit(data: serde_json::Value) {
            let encoded = serde_json::to_string(&data).unwrap();
            assert!(encoded.len() < 16000);
            eprintln!("RESOURCE_CAPACITY {encoded}");
        }
        let last = (359999 - 60480) / 18 + 32;
        let mut times = (32..=last).step_by(4).collect::<Vec<_>>();
        assert_eq!(times.len(), 4160);
        let old_times = times.clone();
        let times_before = times.capacity();
        if times.last() != Some(&last) {
            times.push(last);
        }
        assert_eq!(times.len(), 4161);
        assert!(times.capacity() >= 8320);
        let entries = (0..4161).step_by(2).flat_map(|r| {
            (0..9).step_by(2).map(move |f| {
                (
                    r * 9 + f,
                    Candidate {
                        start: r * 72,
                        frequency: 1000. + (f as f64 - 4.) * 3.,
                        score: 1.3,
                    },
                )
            })
        });
        let (mut physical, physical_trace, physical_old) = push_trace(entries);
        assert_eq!(physical.len(), 10405);
        assert!(physical.iter().all(|(index, c)| *index < 4161 * 9
            && c.start + 60480 <= 360000
            && (200. ..=3500.).contains(&c.frequency)
            && c.score.is_finite()));
        let old_physical = physical
            .iter()
            .take(physical_old)
            .copied()
            .collect::<Vec<_>>();
        physical.sort_by(|(_, a), (_, b)| {
            b.score
                .total_cmp(&a.score)
                .then(a.frequency.total_cmp(&b.frequency))
                .then(a.start.cmp(&b.start))
        });
        let mut physical_sort = Vec::with_capacity(10405);
        physical_sort.resize_with(10405, std::mem::MaybeUninit::uninit);
        let pairs = || (0..641).map(|i| (200. + 3300. * i as f64 / 640., 2f64));
        let (mut coarse, coarse_trace, coarse_old) = push_trace(pairs());
        assert!(coarse.iter().all(
            |(frequency, contrast)| (200. ..=3500.).contains(frequency) && contrast.is_finite()
        ));
        let old_coarse = coarse.iter().take(coarse_old).copied().collect::<Vec<_>>();
        coarse.sort_by(|a, b| b.1.total_cmp(&a.1).then(a.0.total_cmp(&b.0)));
        let mut coarse_sort = Vec::with_capacity(641);
        coarse_sort.resize_with(641, std::mem::MaybeUninit::uninit);
        let (conversion_source, conversion_trace, _) = push_trace(pairs());
        let conversion_capacity = conversion_source.capacity();
        let converted = conversion_source
            .into_iter()
            .map(|p| p.0)
            .collect::<Vec<_>>();
        assert_eq!(converted.len(), 641);
        assert!(converted.capacity() <= 2048);
        let (powers, powers_trace, powers_old) = push_trace((0..16695).map(|_| 1f64));
        let old_powers = powers.iter().take(powers_old).copied().collect::<Vec<_>>();
        assert!(powers.capacity() >= 32768);
        let mut outputs = vec![];
        let mut output_traces = vec![];
        for _ in 0..2 {
            let (new, trace, old) = push_trace((0..256).map(|start| Candidate {
                start,
                frequency: 1000.,
                score: 1.3,
            }));
            let previous = new.iter().take(old).copied().collect::<Vec<_>>();
            outputs.push(new);
            outputs.push(previous);
            output_traces.push(trace);
        }
        let lower = 1000. - Mode::Ft4.spacing() / 2.;
        let upper = 1000. + Mode::Ft4.spacing() / 2.;
        let step = 6000. / 60480.;
        let (refinement, refinement_trace, refinement_old) = push_trace(
            (-105..=105)
                .map(|df| 1000. + df as f64 * step)
                .filter(|f| *f >= lower && *f <= upper)
                .chain([lower, upper]),
        );
        let old_refinement = refinement
            .iter()
            .take(refinement_old)
            .copied()
            .collect::<Vec<_>>();
        assert!(refinement.len() <= 213 && refinement.capacity() <= 256);
        emit(
            serde_json::json!({"owner":"ft4_timing_coarse_capacity_reserve","mode":"ft4",
            "times_frames":359999,"times_before_capacity":times_before,"times_after_capacity":times.capacity(),
            "old_times_capacity":old_times.capacity(),"coarse_logical_upper":641,"coarse_growth":coarse_trace,
            "coarse_final_capacity":coarse.capacity(),"old_coarse_capacity":old_coarse.capacity(),
            "coarse_sort_scratch_slots":coarse_sort.capacity(),"conversion_growth":conversion_trace,
            "conversion_source_capacity":conversion_capacity,"converted_f64_capacity":converted.capacity(),
            "is_signal_generated":false,"is_decoded_success":false}),
        );
        emit(
            serde_json::json!({"owner":"ft4_physical_peak_sort_capacity_reserve","logical_upper":physical.len(),
            "growth":physical_trace,"final_capacity":physical.capacity(),"old_capacity":old_physical.capacity(),
            "sort_scratch_capacity":physical_sort.capacity(),"entry_bytes":std::mem::size_of::<(usize,Candidate)>(),
            "old_growth_and_sort_simultaneously_held_conservatively":true,"is_decoded_success":false}),
        );
        emit(
            serde_json::json!({"owner":"ft4_powers_outputs_refinement_capacity_reserve",
            "powers_logical_upper":powers.len(),"powers_growth":powers_trace,"powers_capacity":powers.capacity(),
            "old_powers_capacity":old_powers.capacity(),"candidate_output_growth":output_traces,
            "candidate_buffer_capacities":outputs.iter().map(Vec::capacity).collect::<Vec<_>>(),
            "refinement_growth":refinement_trace,"refinement_capacity":refinement.capacity(),
            "old_refinement_capacity":old_refinement.capacity(),"is_decoded_success":false,
            "all_are_prepared_capacity_owners":true}),
        );
        Self {
            times,
            old_times,
            physical,
            old_physical,
            physical_sort,
            coarse,
            old_coarse,
            coarse_sort,
            converted,
            powers,
            old_powers,
            outputs,
            refinement,
            old_refinement,
        }
    }
    fn retain(&self) {
        std::hint::black_box((
            &self.times,
            &self.old_times,
            &self.physical,
            &self.old_physical,
            &self.physical_sort,
            &self.coarse,
            &self.old_coarse,
            &self.coarse_sort,
            &self.converted,
            &self.powers,
            &self.old_powers,
            &self.outputs,
            &self.refinement,
            &self.old_refinement,
        ));
    }
}

/// Finite receive allocation-path witnesses, not TX surface-grammar or DSP successes.
#[cfg(not(debug_assertions))]
fn payload_layout_witnesses() -> Vec<(String, &'static str, Decode)> {
    use crate::decoder::{Fields, PayloadStatus};
    fn cq(word: &str) -> u128 {
        assert!((1..=4).contains(&word.len()) && word.bytes().all(|c| c.is_ascii_uppercase()));
        1003 + word.bytes().fold(0, |v, c| v * 27 + (c - b'A' + 1) as u128)
    }
    fn call(text: &str) -> u128 {
        let mut padded = if text.as_bytes()[1].is_ascii_digit() {
            format!(" {text}")
        } else {
            text.to_string()
        };
        while padded.len() < 6 {
            padded.push(' ');
        }
        assert_eq!(padded.len(), 6);
        let alphabets: [&[u8]; 6] = [
            b" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ",
            b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ",
            b"0123456789",
            b" ABCDEFGHIJKLMNOPQRSTUVWXYZ",
            b" ABCDEFGHIJKLMNOPQRSTUVWXYZ",
            b" ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        ];
        6257896
            + padded.bytes().zip(alphabets).fold(0, |v, (c, a)| {
                v * a.len() as u128 + a.iter().position(|x| *x == c).unwrap() as u128
            })
    }
    let mut out = vec![];
    let mut add = |label: String,
                   variant: &'static str,
                   fields: &[(usize, usize, u128)],
                   expected: String,
                   owners: usize| {
        let mut bits = [0u8; 77];
        for &(start, width, value) in fields {
            assert!(start + width <= 77 && value < (1u128 << width));
            for j in 0..width {
                bits[start + j] = ((value >> (width - 1 - j)) & 1) as u8;
            }
        }
        let record = Decode {
            payload: unpack(&bits),
            start_frame: 0,
            frequency_hz: 1000.,
            snr_db: Some(-20.),
        };
        assert_eq!(record.payload.status, PayloadStatus::Decoded, "{label}");
        let actual = match record.payload.fields.as_ref().unwrap() {
            Fields::FreeText { .. } => "free_text",
            Fields::Telemetry { .. } => "telemetry",
            Fields::Standard { .. } => "standard",
            Fields::Dxpedition { .. } => "dxpedition",
            Fields::FieldDay { .. } => "field_day",
            Fields::Rtty { .. } => "rtty",
            Fields::Nonstandard { .. } => "nonstandard",
            Fields::Vhf { .. } => "vhf",
        };
        assert_eq!(actual, variant, "{label}");
        assert_eq!(
            record.payload.text.as_deref(),
            Some(expected.as_str()),
            "{label}"
        );
        let paths = crate::decoder::history::record_string_paths(&record);
        assert_eq!(paths.len(), owners, "{label}");
        assert!(
            paths
                .iter()
                .all(|(_, s)| s.is_ascii() && s.len() <= s.capacity())
        );
        out.push((label, variant, record));
    };
    // Actual trailing-trim path: n question marks followed by13-n radix42 spaces.
    for n in 1..=13u32 {
        add(
            format!("free_width_{n}"),
            "free_text",
            &[(0, 71, (42u128.pow(n) - 1) * 42u128.pow(13 - n))],
            "?".repeat(n as usize),
            3,
        );
    }
    for body in [0, 1, 15, 16, (1u128 << 71) - 1] {
        add(
            format!("telemetry_body_{body}"),
            "telemetry",
            &[(0, 71, body), (71, 3, 5)],
            format!("{body:018X}"),
            3,
        );
    }
    for base in ["A0A", "AA0A", "AA0AA", "ZZ9ZZZ"] {
        for (tag, flag, suffix) in [(1, 0, ""), (1, 1, "/R"), (2, 1, "/P")] {
            for (raw, exchange, owners) in [
                (32399, "RR99", 5),
                (32403, "RR73", 5),
                (32485, "+50", 4),
                (32486, "-50", 4),
                (32401, "", 4),
            ] {
                let named = format!("{base}{suffix}");
                let expected = if exchange.is_empty() {
                    format!("{named} {named} R")
                } else {
                    format!("{named} {named} R {exchange}")
                };
                add(
                    format!("standard_{base}_{tag}_{flag}_{raw}"),
                    "standard",
                    &[
                        (0, 28, call(base)),
                        (28, 1, flag),
                        (29, 28, call(base)),
                        (57, 1, flag),
                        (58, 1, 1),
                        (59, 15, raw),
                        (74, 3, tag),
                    ],
                    expected,
                    owners,
                );
            }
        }
    }
    // RX c28 accepts tokens in either role; TX restrictions are intentionally irrelevant.
    for (value, text) in [
        (0, "DE"),
        (1, "QRZ"),
        (2, "CQ"),
        (10, "CQ 007"),
        (cq("A"), "CQ A"),
        (cq("AA"), "CQ AA"),
        (cq("AAA"), "CQ AAA"),
        (cq("AAAA"), "CQ AAAA"),
    ] {
        for second in [false, true] {
            let (to, from, to_text, from_text) = if second {
                (call("ZZ9ZZZ"), value, "ZZ9ZZZ", text)
            } else {
                (value, call("ZZ9ZZZ"), text, "ZZ9ZZZ")
            };
            add(
                format!("standard_token_{value}_second_{second}"),
                "standard",
                &[(0, 28, to), (29, 28, from), (59, 15, 32399), (74, 3, 1)],
                format!("{to_text} {from_text} RR99"),
                5,
            );
        }
    }
    add(
        "dxpedition_max_display".into(),
        "dxpedition",
        &[
            (0, 28, cq("AAAA")),
            (28, 28, cq("ZZZZ")),
            (56, 10, 1023),
            (66, 5, 31),
            (71, 3, 1),
        ],
        "CQ AAAA RR73; CQ ZZZZ <...> +32".into(),
        4,
    );
    for tu in [0, 1] {
        for ack in [0, 1] {
            for (raw, exchange, owners) in [(7999, "7999", 4), (8059, "NWT", 5)] {
                add(
                    format!("rtty_tu_{tu}_ack_{ack}_exchange_{raw}"),
                    "rtty",
                    &[
                        (0, 1, tu),
                        (1, 28, cq("AAAA")),
                        (29, 28, cq("ZZZZ")),
                        (57, 1, ack),
                        (58, 3, 7),
                        (61, 13, raw),
                        (74, 3, 3),
                    ],
                    format!(
                        "{}CQ AAAA CQ ZZZZ{} 599 {exchange}",
                        if tu == 1 { "TU; " } else { "" },
                        if ack == 1 { " R" } else { "" }
                    ),
                    owners,
                );
            }
        }
    }
    for (n3, transmitters) in [(3, 16), (4, 32)] {
        add(
            format!("field_day_subtype_{n3}"),
            "field_day",
            &[
                (0, 28, cq("AAAA")),
                (28, 28, cq("ZZZZ")),
                (56, 1, 1),
                (57, 4, 15),
                (61, 3, 5),
                (64, 7, 11),
                (71, 3, n3),
            ],
            format!("CQ AAAA CQ ZZZZ R {transmitters}F EMA"),
            6,
        );
    }
    for cq_flag in [0, 1] {
        for second in [0, 1] {
            let full = "/".repeat(11);
            let expected = if cq_flag == 1 {
                format!("CQ {full}")
            } else if second == 1 {
                format!("{full} <...> RR73")
            } else {
                format!("<...> {full} RR73")
            };
            add(
                format!("nonstandard_cq_{cq_flag}_hash_second_{second}"),
                "nonstandard",
                &[
                    (0, 12, 4095),
                    (12, 58, 38u128.pow(11) - 1),
                    (70, 1, second),
                    (71, 2, 2),
                    (73, 1, cq_flag),
                    (74, 3, 4),
                ],
                expected,
                4,
            );
        }
    }
    for serial in [0, 9, 10, 999, 1000, 2047] {
        add(
            format!("vhf_serial_{serial}"),
            "vhf",
            &[
                (0, 12, 4095),
                (12, 22, (1 << 22) - 1),
                (34, 1, 1),
                (35, 3, 7),
                (38, 11, serial),
                (49, 25, 18662399),
                (74, 3, 5),
            ],
            format!("<...> <...> R 59{serial:04} RR99XX"),
            3,
        );
    }
    assert_eq!(out.len(), 115);
    assert_eq!(
        out.iter()
            .map(|(_, v, _)| *v)
            .collect::<std::collections::BTreeSet<_>>()
            .len(),
        8
    );
    assert_eq!(
        out.iter()
            .map(|(label, _, _)| label)
            .collect::<std::collections::BTreeSet<_>>()
            .len(),
        115
    );
    out
}

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
    {
        // Mode-independent unpack allocation witnesses are measured once, then dropped.
        let layouts = payload_layout_witnesses();
        assert_eq!(
            layouts
                .iter()
                .map(|(_, _, r)| r.payload.text.as_ref().unwrap().len())
                .max(),
            Some(31)
        );
        assert_eq!(
            layouts
                .iter()
                .map(|(_, _, r)| history::record_string_paths(r).len())
                .max(),
            Some(6)
        );
        assert_eq!(
            layouts
                .iter()
                .map(|(_, _, r)| history::record_string_paths(r)
                    .iter()
                    .map(|(_, s)| s.len())
                    .sum::<usize>())
                .max(),
            Some(123)
        );
        let mut largest = None;
        for chunk in layouts.chunks(8) {
            let rows = chunk
                .iter()
                .map(|(label, variant, record)| {
                    let bytes = history::retained_record_bytes(record);
                    if largest.as_ref().is_none_or(|(_, max)| bytes > *max) {
                        largest = Some((label.clone(), bytes));
                    }
                    history::string_layout_ledger(label, variant, record)
                })
                .collect::<Vec<_>>();
            let event = serde_json::json!({"owner":"receive_payload_string_paths","witnesses":rows,
                "global_maximum_proved":false,"unexercised_allocation_residual_bytes":null});
            let encoded = serde_json::to_string(&event).unwrap();
            assert!(encoded.len() < 16000);
            eprintln!("RESOURCE_CAPACITY {encoded}");
        }
        eprintln!(
            "RESOURCE_CAPACITY {}",
            serde_json::json!({"owner":"attained_payload_layout_summary",
            "witness_count":layouts.len(),"variant_count":8,"batch_events":layouts.len().div_ceil(8),
            "largest_attained_label_and_nested_bytes":largest,"global_maximum_proved":false,
            "unexercised_allocation_residual_bytes":null,"prepared_not_dsp_decodes":true})
        );
        drop(layouts);
    }
    let table_reserve = history::UnpackTableReserve::new();
    let mut additional_tiers = vec![];
    for mode in [Mode::Ft8, Mode::Ft4] {
        let peak_reserve = if mode == Mode::Ft8 {
            Some(crate::decoder::synchronization::PeakCapacityReserve::new())
        } else {
            None
        };
        let ft4_reserve = if mode == Mode::Ft4 {
            Some(Ft4CapacityReserve::new())
        } else {
            None
        };
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
            if let Some(reserve) = &peak_reserve {
                reserve.retain();
            }
            if let Some(reserve) = &ft4_reserve {
                reserve.retain();
            }
            table_reserve.retain();
        }
        let missing: &[(usize, usize, usize)] = if mode == Mode::Ft8 {
            &[(180000, 192000, 3200)]
        } else {
            &[
                (72576, 72576, 4032),
                (145152, 145152, 8064),
                (217728, 217728, 12096),
                (290304, 290304, 16128),
            ]
        };
        for &(frames, long, short) in missing {
            for scalar in [false, true] {
                let scratch = [(long, false), (short, true), (32, false)].map(|(n, inverse)| {
                    crate::decoder::baseband::fft_plan(n, inverse, scalar).get_inplace_scratch_len()
                });
                eprintln!(
                    "RESOURCE_STORAGE {}",
                    serde_json::json!({"owner":"reconstructed_additional_bandplan_query",
                    "mode":mode,"frames":frames,"scalar":scalar,"long_len":long,"short_len":short,
                    "scratch_lengths":scratch,"direct_private_field_observation":false})
                );
                let decoder = if scalar {
                    Decoder::with_scalar_transform()
                } else {
                    Decoder::new()
                };
                let input = base
                    .iter()
                    .copied()
                    .cycle()
                    .take(frames)
                    .collect::<Vec<_>>();
                let observed = observer::install(Arc::new(AtomicBool::new(false)), None);
                let mut fresh = DecodeState::new_live(mode);
                let mut callbacks = 0;
                complete(decoder.decode_window_into_async(
                    input,
                    0,
                    &mut fresh,
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
                let identity = (mode, frames, scalar);
                assert!(!additional_tiers.contains(&identity));
                additional_tiers.push(identity);
                eprintln!(
                    "RESOURCE_CAPACITY {}",
                    serde_json::json!({"owner":"additional_fft_tier",
                    "mode":mode,"frames":frames,"scalar":scalar,"long_len":long,"short_len":short,
                    "complete":true,"actual_decoded_callbacks":callbacks,"phase_counts":observed.report().counts,
                    "is_prepared_decode":false,"runtime_sla_claimed":false})
                );
                assert_eq!(retained_state.available_count(), 2048);
                std::hint::black_box((&records, &witnesses, &candidates, &pending, &seen));
                if let Some(reserve) = &peak_reserve {
                    reserve.retain();
                }
                if let Some(reserve) = &ft4_reserve {
                    reserve.retain();
                }
                table_reserve.retain();
            }
        }
        drop(ft4_reserve);
        drop(peak_reserve);
    }
    assert_eq!(additional_tiers.len(), 10);
    drop(additional_tiers);
    drop(table_reserve);
    eprintln!(
        "RESOURCE_DISPOSITION {}",
        serde_json::json!({"unknown_maximum_nested_record_allowance":true,
        "unknown_unexercised_internal_grid_heap_allowance":true,"workspace_sufficient_proof":"INCONCLUSIVE",
        "station_96mib_proved":false,"all_test_owners_dropped":true,
        "one_unpack_string_buffers_requested_bound":197,
        "history_numbered_ascii_encoded_bound":625,"history_json_old_new_requested_bound":1536,
        "current_decode_inline_bytes":std::mem::size_of::<Decode>(),
        "clone_argument_inline_bytes":std::mem::size_of::<Decode>(),
        "one_unpack_bound_includes_inline_future_control_or_stack":false,
        "future_control_stack_proof":"separate real-kernel/source working-storage term",
        "universal_process_commit_claimed":false})
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
