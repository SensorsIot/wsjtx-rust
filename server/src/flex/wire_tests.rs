use super::*;

fn bytes(hex: &str) -> Vec<u8> {
    (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
        .collect()
}

// Proves: TC-023-001. Independently authored issue-13 preparation vector
// (hb9bla-progress/flex-readiness/independent-protocol-vectors.json, SHA256
// d706e67b6bf78ae46ddc8c7b7a3331d8fdde5c15e2a1446eb0110586fa893f3e), not vendor output.
#[test]
fn independent_narrow48_vector_decodes_field_by_field() {
    let raw = bytes(
        "18ef000b8100000100001c2d534c03e40000000100000000000000003f000000bf0000003f800000bf800000",
    );
    let p = parse_vita(&raw).unwrap();
    assert_eq!(
        (
            p.packet_type,
            p.class_present,
            p.trailer_present,
            p.tsi,
            p.tsf
        ),
        (1, true, false, 3, 2)
    );
    assert_eq!((p.packet_count, p.words), (15, 11));
    assert_eq!(p.stream_id, Some(2_164_260_865));
    assert_eq!(
        (p.oui, p.information_class, p.packet_class),
        (Some(7213), Some(21324), Some(996))
    );
    assert_eq!((p.integer_time, p.fractional_time), (Some(1), Some(0)));
    assert_eq!(dax_samples(&p).unwrap(), vec![0.5, -0.5, 1.0, -1.0]);
}

// Proves: TC-023-001. The vector's negative cases with their expected refusals.
#[test]
fn independent_negative_vectors_are_refused() {
    let wrong = bytes(
        "18ef000b8100000100001c2d534c03e40000000100000000000000003f000000bf0000003f800000bf8000",
    );
    assert_eq!(parse_vita(&wrong), Err(WireError::InvalidPacketLength));
    assert_eq!(
        parse_vita(&bytes("18ef000b8100000100001c2d")),
        Err(WireError::TruncatedPacket)
    );
    let nonfinite = bytes(
        "18ef000b8100000100001c2d534c03e40000000100000000000000003f000000bf0000003f8000007fc00000",
    );
    assert_eq!(
        dax_samples(&parse_vita(&nonfinite).unwrap()),
        Err(WireError::NonfiniteSample)
    );
    // 24 kHz float (class 0x03E3) is a known but unadmitted format.
    let mut other = bytes(
        "18ef000b8100000100001c2d534c03e40000000100000000000000003f000000bf0000003f800000bf800000",
    );
    other[15] = 0xe3;
    assert_eq!(
        dax_samples(&parse_vita(&other).unwrap()),
        Err(WireError::UnsupportedFormat)
    );
    // An odd float count cannot form stereo frames: header words 10, one sample less.
    let mut odd =
        bytes("18ef000a8100000100001c2d534c03e40000000100000000000000003f000000bf0000003f800000");
    assert_eq!(
        dax_samples(&parse_vita(&odd).unwrap()),
        Err(WireError::InvalidPacketLength)
    );
    odd[0] = 0x58; // type 5 is not DAX audio
    assert!(matches!(
        parse_vita(&odd).map(|p| dax_samples(&p)),
        Ok(Err(WireError::NotDaxAudio))
    ));
}

// Proves: TC-023-001. Literal command/reply/status/handle/version lines from the
// SmartSDR TCP/IP API wiki examples.
#[test]
fn documented_control_lines_parse_and_commands_are_bounded() {
    assert_eq!(
        command(1, "client udpport 4993").unwrap(),
        "C1|client udpport 4993\n"
    );
    assert!(command(1, "slice tune 0 14.074|x").is_err());
    assert!(command(1, "a\nb").is_err());
    assert!(command(0, "ping").is_err());
    assert!(
        command(1, &"x".repeat(1020)).is_ok(),
        "1024 bytes including LF"
    );
    assert!(command(1, &"x".repeat(1021)).is_err());
    assert_eq!(
        parse_line("R1|0|").unwrap(),
        Line::Reply {
            sequence: 1,
            code: 0,
            message: String::new()
        }
    );
    assert_eq!(
        parse_line("R21|0|2|OK Slice receiver 2 created").unwrap(),
        Line::Reply {
            sequence: 21,
            code: 0,
            message: "2".into()
        }
    );
    assert_eq!(
        parse_line("R5|50000001|").unwrap(),
        Line::Reply {
            sequence: 5,
            code: 0x5000_0001,
            message: String::new()
        }
    );
    assert_eq!(parse_line("H6F4EC23D").unwrap(), Line::Handle(0x6F4E_C23D));
    assert_eq!(
        parse_line("V1.4.0.0").unwrap(),
        Line::Version(SUPPORTED_PROTOCOL)
    );
    assert!(parse_line("V1.4.0").is_err());
    let Line::Status { handle, status } = parse_line(
        "S6F4EC23D|slice 3 in_use=1 RF_frequency=14.074000 client_handle=0x6F4EC23D index_letter=D",
    )
    .unwrap() else {
        panic!("status");
    };
    assert_eq!(handle, 0x6F4E_C23D);
    assert_eq!((status.object.as_str(), status.id.as_str()), ("slice", "3"));
    assert_eq!(status.get("RF_frequency"), Some("14.074000"));
    assert_eq!(
        parse_hex(status.get("client_handle").unwrap()),
        Some(0x6F4E_C23D)
    );
    let Line::Status { status, .. } = parse_line(
        "S0|client 0x1234ABCD connected client_id=72E8C7F3-5766-4ADE-9286-EBF2F525C77A program=X",
    )
    .unwrap() else {
        panic!("status");
    };
    assert!(status.has_word("connected"));
    assert!(parse_line("Sx|slice 0").is_err());
    assert!(parse_line("Q1|0|").is_err());
}

// Proves: TC-023-001. Partial, coalesced and CRLF chunks; the 4096-byte line bound.
#[test]
fn line_buffer_splits_chunks_and_bounds_each_line() {
    let mut buffer = LineBuffer::default();
    let mut lines = Vec::new();
    for chunk in [b"V1.4".as_slice(), b".0.0\r", b"\nH1\nR1|0|\n", b"S0|slice"] {
        buffer.push(chunk, &mut lines).unwrap();
    }
    assert_eq!(lines, ["V1.4.0.0", "H1", "R1|0|"]);
    assert!(buffer.partial());
    let mut long = vec![b'S'; MAX_LINE - 1];
    long.push(b'\n');
    let mut fresh = LineBuffer::default();
    fresh.push(&long, &mut lines).unwrap();
    let mut over = vec![b'S'; MAX_LINE];
    over.push(b'\n');
    assert_eq!(
        LineBuffer::default().push(&over, &mut lines),
        Err(WireError::LineTooLong)
    );
    assert_eq!(
        LineBuffer::default().push(b"\xff\n", &mut lines),
        Err(WireError::InvalidText)
    );
}

// Proves: TC-023-002. Discovery is identified by Flex OUI and class 0xFFFF; the
// serial, not the address or nickname, is retained as identity.
#[test]
fn discovery_packet_fields_and_refusals() {
    let text = b"model=FLEX-6600 serial=1234-5678-9012-3456 version=4.1.3.39644 nickname=Shack ip=10.0.0.9 port=4992 available_clients=2 available_slices=4";
    // Type 3 (extension data with stream ID), class present, stream 0x800.
    let mut raw = vec![
        0x38, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0x1c, 0x2d, 0x53, 0x4c, 0xff, 0xff,
    ];
    raw.extend_from_slice(text);
    while raw.len() % 4 != 0 {
        raw.push(0);
    }
    let words = (raw.len() / 4) as u16;
    raw[2..4].copy_from_slice(&words.to_be_bytes());
    let found = parse_discovery(&raw).unwrap();
    assert_eq!(found.serial, "1234-5678-9012-3456");
    assert_eq!(found.ip, Some("10.0.0.9".parse().unwrap()));
    assert_eq!(
        (found.port, found.available_clients, found.available_slices),
        (Some(4992), Some(2), Some(4))
    );
    assert_eq!(found.firmware.as_deref(), Some("4.1.3.39644"));
    raw[15] = 0xfe;
    assert_eq!(parse_discovery(&raw), Err(WireError::NotDiscovery));
}
