use super::super::{ChannelWord, QsoProgress};
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
        // Producer push trajectory, distinct from the consumer's batched extend path.
        {
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
        let mut consumer = Vec::new();
        let batch = (0..255)
            .map(|start| Candidate {
                start,
                frequency: 1000.,
                score: 1.3,
            })
            .collect::<Vec<_>>();
        consumer.extend(batch.into_iter());
        assert_eq!(consumer.len(), 255);
        let consumer_old_capacity = consumer.capacity();
        assert_eq!(consumer_old_capacity, 255);
        let old_consumer = consumer.clone();
        consumer.extend(
            vec![Candidate {
                start: 255,
                frequency: 1000.,
                score: 1.3,
            }]
            .into_iter(),
        );
        assert_eq!(consumer.len(), 256);
        assert!(consumer.capacity() >= 510);
        output_traces.push(vec![
            serde_json::json!({"op":"extend_into_iter","count":255,"len":255,"old_capacity":0,"new_capacity":consumer_old_capacity}),
            serde_json::json!({"op":"extend_into_iter","count":1,"len":256,"old_capacity":consumer_old_capacity,"new_capacity":consumer.capacity()})]);
        outputs.push(consumer);
        outputs.push(old_consumer);
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
            "candidate_buffer_roles":["producer_push_new","producer_push_old","consumer_extend_new","consumer_extend_old"],
            "consumer_255_then_1_is_capacity_upper_witness_not_signal_attainment":true,
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
            a_priori: None,
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
                    a_priori: None,
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

// Proves: CL-007-04, CL-007-05; TC-004-004. Pruned grid scoring keeps the exhaustive result.
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

/// The #56 Ft8PaddedResidual case: a strong FT8 frame that began 1.5 s before the window
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

// Proves: FR-003, FR-004, CL-007-03 (#56 Ft8PaddedResidual). A frame that runs past the
// window start is found and subtracted but never published; the weak frame under it decodes.
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

// Proves: FR-003, FR-004, CL-007-03 (#56 Ft8PaddedResidual, end edge). A strong frame that
// runs 0.64 s past the window end is subtracted, not published; the weak frame under it decodes.
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

// Proves: FR-003, CL-007-03 (#56 Ft8PaddedResidual publication boundary). A frame starting up
// to half a symbol (960 frames) before the window is published at start 0; one starting
// further before is not.
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

// Proves: FR-003, FR-004 (#56 duplicate on another carrier). The same word on carriers 100 Hz
// apart is published once, and both copies are subtracted: a weak frame 3 Hz from the second
// copy decodes.
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

// Proves: CL-007-03 (#56 ft8b weak-word guard). Rejected exactly when an FT8 word has at most
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

// Proves: FR-003, CL-007-03 (#56 Ft8DataPoint). A weak word that fails at its fine point
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

// Proves: FR-003, FR-004, CL-007-03 (#56 slice 5 APrioriHypotheses). Weak FT8 QSO messages
// below the unassisted limit decode only through the a-priori pass with the right MyCall,
// DxCall, QSO state and Rx/Tx frequency, and the published record carries the AP type.
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

// Proves: CL-007-03 (#56 slice 5). Under a wrong DxCall, in every QSO state, and in pure
// noise under the right one, the a-priori passes never yield a word other than the one on
// the air, at any level from buried to strong, in FT8 and FT4.
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

// Proves: FR-003, CL-007-03 (#56 slice 5). FT4 a-priori: a weak CQ below the unassisted limit
// decodes through type 1 without any QSO context, and a weak HB9BLA K1ABC RR73 through type 6
// with the right calls only.
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
