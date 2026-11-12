use super::*;

// Proves: TC-023-002. Slice status frequencies are exact integers in hertz.
#[test]
fn megahertz_text_round_trips_exact_hertz() {
    assert_eq!(megahertz("14.074000"), Some(14_074_000));
    assert_eq!(megahertz("7.0475"), Some(7_047_500));
    assert_eq!(megahertz("50.313"), Some(50_313_000));
    assert_eq!(megahertz_text(14_074_000), "14.074000");
    for bad in ["", ".5", "14,074", "-1.0", "1.0000000000"] {
        assert_eq!(megahertz(bad), None, "{bad}");
    }
}

// Runs counts through a reorder buffer: what was handed on as (packet, turns given up), and
// which packets were dropped.
fn reordered(counts: &[u8]) -> (Vec<(u8, u64)>, Vec<u8>) {
    let (mut order, mut out, mut dropped) = (Reorder::new(), Vec::new(), Vec::new());
    for &count in counts {
        if !order.accept(count, count, false, |p, missed| out.push((p, missed))) {
            dropped.push(count);
        }
    }
    (out, dropped)
}

// Proves: TC-023-001. Swapped packets go on in their count's order and lose nothing, also across
// the wrap of the 4-bit count.
#[test]
fn reorder_restores_the_order_and_counts_nothing_lost() {
    let (out, dropped) = reordered(&[14, 15, 1, 0, 2, 4, 5, 3, 6]);
    let expected: Vec<_> = [14, 15, 0, 1, 2, 3, 4, 5, 6].map(|c| (c, 0)).into();
    assert_eq!(out, expected);
    assert!(dropped.is_empty());
}

// Proves: TC-023-001. A packet waits until 5 packets wait behind it, not longer: 4 places is still
// put back, while at 5 its turn is given up, it counts lost once, and its late arrival is dropped.
#[test]
fn reorder_gives_up_a_turn_at_its_depth() {
    let (out, dropped) = reordered(&[0, 2, 3, 4, 5, 1, 6]);
    let expected: Vec<_> = [0, 1, 2, 3, 4, 5, 6].map(|c| (c, 0)).into();
    assert_eq!(out, expected);
    assert!(dropped.is_empty());

    let (out, dropped) = reordered(&[0, 2, 3, 4, 5, 6, 1, 7]);
    assert_eq!(
        out,
        vec![(0, 0), (2, 1), (3, 0), (4, 0), (5, 0), (6, 0), (7, 0)]
    );
    assert_eq!(dropped, vec![1]);
}

// Proves: TC-023-001. A burst of 7 lost packets counts in full, once the wait is over, and no
// packet after it is mistaken for a late one. At 8 the count cannot tell: those packets read as
// late, and the stream carries on at the wrap.
#[test]
fn reorder_counts_a_burst_of_lost_packets_up_to_half_the_count() {
    let (out, dropped) = reordered(&[0, 8, 9, 10, 11, 12, 13]);
    assert_eq!(
        out,
        vec![(0, 0), (8, 7), (9, 0), (10, 0), (11, 0), (12, 0), (13, 0)]
    );
    assert!(dropped.is_empty());

    let (out, dropped) = reordered(&[0, 9, 10, 11, 12, 13, 14, 15, 0, 1, 2]);
    assert_eq!(out, vec![(0, 0), (1, 0), (2, 0)]);
    assert_eq!(dropped, vec![9, 10, 11, 12, 13, 14, 15, 0]);
}

// Proves: TC-023-001. A duplicate never reaches the timeline, whether its turn has passed or its
// first copy still waits.
#[test]
fn reorder_drops_duplicates() {
    assert_eq!(reordered(&[0, 1, 1, 2]).1, vec![1]);
    let (out, dropped) = reordered(&[0, 2, 2, 1, 3]);
    let expected: Vec<_> = [0, 1, 2, 3].map(|c| (c, 0)).into();
    assert_eq!(out, expected);
    assert_eq!(dropped, vec![2]);
}

// Proves: TC-023-001. After a stall the count may have wrapped: what waits goes on first and the
// next packet starts the count over, whatever its value, with no loss derived from it.
#[test]
fn reorder_starts_over_after_a_stall() {
    let (mut order, mut out) = (Reorder::new(), Vec::new());
    for count in [0, 1, 3] {
        assert!(order.accept(count, count, false, |p, m| out.push((p, m))));
    }
    assert_eq!(out, vec![(0, 0), (1, 0)]);
    assert!(order.accept(14, 14, true, |p, m| out.push((p, m))));
    assert_eq!(out, vec![(0, 0), (1, 0), (3, 1), (14, 0)]);
    assert!(order.accept(15, 15, false, |p, m| out.push((p, m))));
    assert_eq!(out.last(), Some(&(15, 0)));
}

// Proves: TC-023-002. A slice's ownership and liveness follow the latest status;
// removal and another client's handle are visible to the reconciler.
#[test]
fn view_tracks_ownership_and_removal_from_status_lines() {
    let mut view = View::default();
    let status = |text: &str| wire::parse_status(text).unwrap();
    view.apply(&status("slice 2 in_use=1 client_handle=0x10 RF_frequency=14.074000 rxant=ANT1 dax=1 index_letter=A"));
    view.apply(&status("slice 5 in_use=1 client_handle=0x20 dax=2"));
    assert_eq!(view.slices[&2].client_handle, Some(0x10));
    assert_eq!(view.slices[&5].dax, Some(2));
    view.apply(&status("slice 2 in_use=0"));
    assert!(!view.slices.contains_key(&2));
    view.apply(&status(
        "stream 0x04000008 type=dax_rx dax_channel=2 client_handle=0x20",
    ));
    assert_eq!(view.streams[&0x0400_0008].client_handle, Some(0x20));
    view.apply(&status("stream 0x04000008 removed"));
    assert!(view.streams.is_empty());
    view.apply(&status("client 0x20 connected client_id=AB program=X"));
    assert_eq!(view.clients[&0x20].client_id.as_deref(), Some("AB"));
    view.apply(&status("client 0x20 disconnected forced=0"));
    assert!(view.clients.is_empty());
    for i in 0..200 {
        view.apply(&status(&format!("stream 0x{i:x} type=dax_rx")));
    }
    assert!(view.streams.len() <= MAX_TRACKED);
}

// Proves: TC-023-001. The measurement is this host's clock minus the packet's own time, with
// the sub-second part only where the timestamp kind carries real time.
#[test]
fn vita_offset_measures_host_clock_minus_packet_time() {
    let packet = |tsf, integer_time, fractional_time| wire::Vita {
        packet_type: 1,
        class_present: true,
        trailer_present: false,
        tsi: 1,
        tsf,
        packet_count: 0,
        words: 0,
        stream_id: None,
        oui: None,
        information_class: None,
        packet_class: None,
        integer_time,
        fractional_time,
        payload: &[],
    };
    let real_time = packet(2, Some(100), Some(250_000_000_000));
    assert_eq!(vita_offset_ms(&real_time, 100_500), Some(250));
    assert_eq!(vita_offset_ms(&real_time, 99_000), Some(-1250));
    let sample_count = packet(1, Some(100), Some(250_000_000_000));
    assert_eq!(vita_offset_ms(&sample_count, 100_500), Some(500));
    assert_eq!(vita_offset_ms(&packet(2, None, None), 100_500), None);
}

// A scripted radio on localhost for one tune: `slice tune` gets the reply code `tune_code`, and
// `sub slice all` gets a success reply and the slice's status at 14.074 MHz. The session's
// connection starts with its slice 0 at 7.000 MHz, published as after the ready step.
fn tune_against_scripted_radio(tune_code: u32) -> (Result<u64, Error>, Option<SliceFacts>) {
    use std::io::{BufRead, BufReader};
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    let radio = std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        let mut out = stream.try_clone().unwrap();
        for line in BufReader::new(stream).lines() {
            let Ok(line) = line else { return };
            let (sequence, text) = line[1..].split_once('|').unwrap();
            let answer = if text.starts_with("slice tune 0 ") {
                format!("R{sequence}|{tune_code:X}|\n")
            } else if text == "sub slice all" {
                format!(
                    "R{sequence}|0|\nS10|slice 0 in_use=1 client_handle=0x10 RF_frequency=14.074000 mode=DIGU rxant=ANT1 dax=1 index_letter=A\n"
                )
            } else {
                format!("R{sequence}|50000001|\n")
            };
            if out.write_all(answer.as_bytes()).is_err() {
                return;
            }
        }
    });
    let shared = Shared {
        snapshot: Mutex::new(Snapshot {
            state: State::Ready,
            error: None,
            radio_code: None,
            session: 1,
            radio: None,
            slice: None,
            counters: Counters::default(),
            last_peak: None,
            vita_tsi: None,
            vita_offset_ms: None,
            jitter_mean_ms: None,
            jitter_max_ms: None,
            retry_after_ms: None,
        }),
        sink: Mutex::new(None),
        attachments: Mutex::new(0),
        shutdown: AtomicBool::new(false),
        allowed: AtomicBool::new(true),
        tuned_hz: AtomicU64::new(0),
        revision: AtomicU64::new(1),
    };
    let tcp = TcpStream::connect(address).unwrap();
    tcp.set_read_timeout(Some(Duration::from_millis(10)))
        .unwrap();
    let mut conn = Conn::new(&shared, tcp, address.ip());
    conn.own = Some(0x10);
    conn.slice = Some(0);
    conn.view.apply(&wire::parse_status("slice 0 in_use=1 client_handle=0x10 RF_frequency=7.000000 mode=DIGU rxant=ANT1 dax=1 index_letter=A").unwrap());
    let before = conn.slice_facts();
    assert_eq!(
        before.as_ref().and_then(|s| s.frequency_hz),
        Some(7_000_000)
    );
    shared.update(|s| s.slice = before);

    let (reply, _answer) = sync_channel(1);
    let request = TuneRequest {
        frequency_hz: 14_074_000,
        deadline: Instant::now() + STEP,
        cancelled: Arc::new(AtomicBool::new(false)),
        reply,
    };
    let mut at_reply = None;
    let result = serve_tune(&mut conn, &request, |result| {
        // The caller reads the shared snapshot the moment it hears the result.
        let slice = shared.snapshot.lock().unwrap().slice.clone();
        at_reply = Some((result, slice));
    });
    drop(conn);
    radio.join().unwrap();
    let (replied, slice) = at_reply.expect("the caller is answered");
    assert_eq!(replied, result);
    (replied, slice)
}

// Proves: TC-023-001. A confirmed selection is never reported beside the slice's earlier
// frequency: when the caller hears that the tune succeeded, the shared snapshot already
// carries the frequency the radio read back.
#[test]
fn a_confirmed_tune_is_published_before_the_caller_hears_of_it() {
    let (result, slice) = tune_against_scripted_radio(0);
    assert_eq!(result, Ok(14_074_000));
    assert_eq!(slice.and_then(|s| s.frequency_hz), Some(14_074_000));
}

// Proves: TC-023-001. A refused tune confirms nothing, and the snapshot at the reply shows the
// slice as the radio reports it.
#[test]
fn a_refused_tune_confirms_nothing_and_keeps_the_reported_slice() {
    let (result, slice) = tune_against_scripted_radio(0x5000_002C);
    assert_eq!(result, Err(Error::RadioRefused));
    assert_eq!(slice.and_then(|s| s.frequency_hz), Some(7_000_000));
}

// Proves: TC-023-001. GET /native-flex reports the packets, the peak, the VITA time and the
// arrival jitter of the current session: when the next session becomes ready they start over,
// and the session number changes.
#[test]
fn a_ready_session_starts_its_packet_counters_and_measurements_over() {
    let mut s = Snapshot {
        state: State::Connecting,
        error: Some(Error::TransportLost),
        radio_code: None,
        session: 1,
        radio: None,
        slice: None,
        counters: Counters {
            accepted: 211,
            foreign: 26,
            invalid: 3,
            lost: 4,
            late: 2,
        },
        last_peak: Some(0.8),
        vita_tsi: Some(1),
        vita_offset_ms: Some(12),
        jitter_mean_ms: Some(1.5),
        jitter_max_ms: Some(9.0),
        retry_after_ms: None,
    };
    become_ready(&mut s, None);
    assert_eq!(s.state, State::Ready);
    assert_eq!(s.error, None);
    assert_eq!(s.session, 2);
    assert_eq!(s.counters, Counters::default());
    assert_eq!(s.last_peak, None);
    assert_eq!((s.vita_tsi, s.vita_offset_ms), (None, None));
    assert_eq!((s.jitter_mean_ms, s.jitter_max_ms), (None, None));
}

#[test]
fn intent_domains() {
    let valid = Intent {
        client_id: "72e8c7f3-5766-4ade-9286-ebf2f525c77a".into(),
        rx_antenna: "ANT1".into(),
        radio_address: None,
    };
    assert!(valid.valid());
    for bad in [
        Intent {
            rx_antenna: String::new(),
            ..valid.clone()
        },
        Intent {
            rx_antenna: "ant1".into(),
            ..valid.clone()
        },
        Intent {
            client_id: "x".into(),
            ..valid.clone()
        },
    ] {
        assert!(!bad.valid());
    }
}
