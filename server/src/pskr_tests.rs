#![forbid(unsafe_code)]
// Proves: CL-039-20; TC-039-020. Everything here stays on the loopback interface: a local
// peer written from the OASIS MQTT 3.1.1 packet tables stands in for the broker, spots are
// hand-authored in the form of the broker's published payload schema.
use super::*;
use rustls::client::danger::ServerCertVerifier;
use rustls::pki_types::{CertificateDer, ServerName, UnixTime, pem::PemObject};
use std::net::TcpListener;
use std::sync::mpsc;

const SPOT: &str = r#"{"sq":30142870791,"f":7075512,"md":"FT8","rp":-5,"t":1000,"t_tx":990,
    "sc":"HB9BLA","sl":"JN37vl","rc":"K1ABC","rl":"FN42","sa":287,"ra":291,"b":"40m"}"#;

fn spot(sender: &str, receiver: &str, hz: u64, utc_s: i64) -> Spot {
    Spot {
        sender: sender.into(),
        receiver: receiver.into(),
        mode: "FT8".into(),
        band: "40m".into(),
        hz,
        utc_s,
    }
}

// Proves: CL-039-20; TC-039-020. The payload fields and the choice of t_tx over t.
#[test]
fn parse_spot_reads_the_schema_and_refuses_the_rest() {
    assert_eq!(
        parse_spot(SPOT.as_bytes()),
        Some(spot("HB9BLA", "K1ABC", 7075512, 990))
    );
    let no_tx = SPOT.replace("\"t_tx\":990,", "");
    assert_eq!(parse_spot(no_tx.as_bytes()).unwrap().utc_s, 1000);
    for bad in [
        "",
        "null",
        "{",
        "[]",
        r#"{"f":1}"#,
        r#"{"f":-1,"md":"FT8","t":1,"sc":"A","rc":"B","b":"40m"}"#,
        r#"{"f":7074000,"md":"FT8","t":1,"sc":"","rc":"B","b":"40m"}"#,
        r#"{"f":7074000,"md":"FT8","t":1,"sc":"AAAAAAAAAAAAAAAAA","rc":"B","b":"40m"}"#,
    ] {
        assert_eq!(parse_spot(bad.as_bytes()), None, "{bad}");
    }
}

// Proves: CL-039-20; TC-039-020. Exactly the two filters, and no data ever becomes a wildcard.
#[test]
fn filters_are_exact_and_no_call_makes_a_wildcard() {
    assert_eq!(
        sender_filter("HB9BLA").unwrap(),
        "pskr/filter/v2/+/+/HB9BLA/+/#"
    );
    assert_eq!(
        receiver_filter("K1ABC").unwrap(),
        "pskr/filter/v2/+/+/+/K1ABC/#"
    );
    for hostile in [
        "",
        "+",
        "#",
        "K1+",
        "K1#",
        "K1ABC/P",
        "HB9/K1ABC",
        "/",
        "K1 AB",
        "k1abc",
        "<K1ABC>",
        "K1\u{0}",
        "K\u{00c4}",
        "AAAAAAAAAAAAAAAAA",
    ] {
        assert_eq!(sender_filter(hostile), None, "{hostile:?}");
        assert_eq!(receiver_filter(hostile), None, "{hostile:?}");
    }
}

// Proves: CL-039-20; TC-039-020. The id names the call and stays inside what 3.1.1 obliges a
// server to accept.
#[test]
fn client_id_carries_the_call_and_stays_legal() {
    assert_eq!(client_id("HB9BLA", "1a2b3c4d-0000"), "wstxHB9BLA1a2b");
    let long = client_id("HB9BLA/QRP/ABCDEFGH", "1a2b-3c");
    assert!(
        long.len() <= 23 && long.bytes().all(|b| b.is_ascii_alphanumeric()),
        "{long}"
    );
}

// Proves: CL-039-20; TC-039-020. A spot counts for its band and mode inside the window, and no
// longer.
#[test]
fn hears_us_expires_and_ignores_other_band_and_mode() {
    let mut h = Hearing::default();
    h.record("HB9BLA", None, spot("HB9BLA", "K1ABC", 7075512, 1000), 1000);
    assert!(h.hears_us("K1ABC", "FT8", "40m", 1000));
    assert!(h.hears_us("K1ABC", "FT8", "40m", 1000 + HEARD_WINDOW_S));
    assert!(!h.hears_us("K1ABC", "FT8", "40m", 1001 + HEARD_WINDOW_S));
    assert!(!h.hears_us("K1ABC", "FT8", "20m", 1000));
    assert!(!h.hears_us("K1ABC", "FT4", "40m", 1000));
    assert!(!h.hears_us("W1AW", "FT8", "40m", 1000));
    // Already too old on arrival; a clock ahead of ours does not stretch the window.
    let mut h = Hearing::default();
    h.record("HB9BLA", None, spot("HB9BLA", "K1ABC", 7075512, 0), 601);
    assert!(!h.hears_us("K1ABC", "FT8", "40m", 601));
    h.record(
        "HB9BLA",
        None,
        spot("HB9BLA", "K1ABC", 7075512, 90_000),
        1000,
    );
    assert!(!h.hears_us("K1ABC", "FT8", "40m", 1001 + HEARD_WINDOW_S));
    // A spot of someone else to the target is no hearing of me.
    let mut h = Hearing::default();
    h.record(
        "HB9BLA",
        Some("K1ABC"),
        spot("DL1XYZ", "K1ABC", 7075512, 1000),
        1000,
    );
    assert!(!h.hears_us("K1ABC", "FT8", "40m", 1000));
}

// Proves: CL-039-20; TC-039-020. RF to audio from the dial, newest first, distinct, inside the
// range.
#[test]
fn decoded_offsets_come_from_the_dial_of_this_band_and_mode() {
    let mut h = Hearing::default();
    let target = Some("K1ABC");
    let dial = 7_074_000;
    for (hz, t) in [
        (7_075_200, 1000),
        (7_074_800, 1001),
        (7_075_200, 1002),
        (7_074_100, 1003), // below the range
        (7_077_500, 1004), // above the range
        (7_073_000, 1005), // below the dial
    ] {
        h.record("HB9BLA", target, spot("DL1XYZ", "K1ABC", hz, t), 1005);
    }
    let mut other_band = spot("DL1XYZ", "K1ABC", 7_075_000, 1005);
    other_band.band = "20m".into();
    h.record("HB9BLA", target, other_band, 1005);
    let mut other_mode = spot("DL1XYZ", "K1ABC", 7_075_000, 1005);
    other_mode.mode = "FT4".into();
    h.record("HB9BLA", target, other_mode, 1005);
    // Someone received by another station, and my own spot, are no frequency of the target.
    h.record(
        "HB9BLA",
        target,
        spot("DL1XYZ", "W1AW", 7_075_000, 1005),
        1005,
    );
    h.record(
        "HB9BLA",
        target,
        spot("HB9BLA", "K1ABC", 7_075_000, 1005),
        1005,
    );
    assert_eq!(
        h.decoded_offsets("FT8", "40m", dial, (300, 2650), 1005),
        vec![1200, 800]
    );
    assert_eq!(
        h.decoded_offsets("FT8", "40m", dial, (300, 2650), 1002 + HEARD_WINDOW_S),
        vec![1200],
        "the older spot of 800 Hz expired, the 1200 Hz one was seen again"
    );
    h.clear_decoded();
    assert!(
        h.decoded_offsets("FT8", "40m", dial, (300, 2650), 1005)
            .is_empty()
    );
}

// Proves: CL-039-20; TC-039-020. Memory stays bounded whatever the broker sends; the newest stay.
#[test]
fn the_model_is_bounded() {
    let mut h = Hearing::default();
    for n in 0..(HEARD_MAX as i64 + 50) {
        h.record(
            "HB9BLA",
            None,
            spot("HB9BLA", &format!("R{n}"), 7075000, 1000 + n),
            1400,
        );
    }
    assert_eq!(h.heard.len(), HEARD_MAX);
    assert!(h.hears_us(&format!("R{}", HEARD_MAX + 49), "FT8", "40m", 1400));
    assert!(!h.hears_us("R0", "FT8", "40m", 1400));
    // Repeats of one receiver take one entry and keep the newest time.
    let mut h = Hearing::default();
    h.record("HB9BLA", None, spot("HB9BLA", "K1ABC", 7075000, 1000), 1000);
    h.record("HB9BLA", None, spot("HB9BLA", "K1ABC", 7075000, 1100), 1100);
    h.record("HB9BLA", None, spot("HB9BLA", "K1ABC", 7075000, 1050), 1100);
    assert_eq!(h.heard.len(), 1);
    assert!(h.hears_us("K1ABC", "FT8", "40m", 1100 + HEARD_WINDOW_S));
    let mut h = Hearing::default();
    for n in 0..(DECODED_MAX as u64 + 50) {
        h.record(
            "HB9BLA",
            Some("K1ABC"),
            spot("DL1XYZ", "K1ABC", 7074300 + n, 1000),
            1000,
        );
    }
    assert_eq!(h.decoded.len(), DECODED_MAX);
    let offsets = h.decoded_offsets("FT8", "40m", 7_074_000, (300, 2650), 1000);
    assert_eq!(offsets.len(), PREFERRED_MAX);
    assert_eq!(offsets[0], 300 + DECODED_MAX as u32 + 49);
}

// Proves: CL-039-20; TC-039-020. The packets, byte by byte, from the OASIS 3.1.1 tables.
#[test]
fn packets_match_the_specification() {
    assert_eq!(
        connect_packet("wstxK1A", 60),
        [
            &[0x10, 19, 0, 4][..],
            b"MQTT",
            &[4, 0x02, 0, 60, 0, 7],
            b"wstxK1A"
        ]
        .concat()
    );
    assert_eq!(
        subscribe_packet(1, "a/+"),
        [&[0x82, 8, 0, 1, 0, 3][..], b"a/+", &[0]].concat()
    );
    assert_eq!(
        unsubscribe_packet(258, "a/+"),
        [&[0xa2, 7, 1, 2, 0, 3][..], b"a/+"].concat()
    );
    // A remaining length past 127 takes a continuation byte.
    let long = packet(0x82, &[0u8; 200]);
    assert_eq!(&long[..3], &[0x82, 200, 1]);
}

// Proves: CL-039-20; TC-039-020. Whole, split and hostile input; nothing panics or grows.
#[test]
fn next_packet_parses_and_bounds() {
    let mut buffer = vec![0x20, 2, 0];
    assert_eq!(next_packet(&mut buffer), Ok(None), "incomplete");
    buffer.push(5);
    assert_eq!(next_packet(&mut buffer), Ok(Some(Packet::ConnAck(5))));
    assert!(buffer.is_empty());
    let mut buffer = vec![0x30, 6, 0, 2, b'a', b'b', b'{', b'}', 0xd0, 0];
    assert_eq!(
        next_packet(&mut buffer),
        Ok(Some(Packet::Publish(b"{}".to_vec())))
    );
    assert_eq!(next_packet(&mut buffer), Ok(Some(Packet::PingResp)));
    let mut buffer = vec![0x90, 3, 0, 1, 0x80];
    assert_eq!(next_packet(&mut buffer), Ok(Some(Packet::SubAck(false))));
    let mut buffer = vec![0x90, 3, 0, 1, 0];
    assert_eq!(next_packet(&mut buffer), Ok(Some(Packet::SubAck(true))));
    let mut buffer = vec![0xb0, 2, 0, 1];
    assert_eq!(next_packet(&mut buffer), Ok(Some(Packet::UnsubAck)));
    for hostile in [
        vec![0x30, 0xff, 0xff, 0xff, 0xff, 0x7f], // a length of too many bytes
        vec![0x30, 0x81, 0x80, 0x04],             // past PACKET_MAX
        vec![0x32, 2, 0, 0],                      // QoS 1
        vec![0x30, 3, 0, 9, 1],                   // a topic past the packet
        vec![0x10, 0],                            // a server never sends CONNECT
        vec![0x20, 1, 0],                         // a short CONNACK
        vec![0xf0, 0],                            // reserved
    ] {
        assert_eq!(
            next_packet(&mut hostile.clone()),
            Err("protocol_error"),
            "{hostile:?}"
        );
    }
}

// Proves: CL-039-20; TC-039-020. The reconnect delay doubles to its bound and starts over only
// after a healthy session.
#[test]
fn backoff_doubles_to_the_bound() {
    let mut b = Backoff::new(&Timing::BROKER);
    let delays: Vec<u64> = (0..9).map(|_| b.step().as_secs()).collect();
    assert_eq!(delays, [5, 10, 20, 40, 80, 160, 300, 300, 300]);
    b.reset();
    assert_eq!(b.step().as_secs(), 5);
}

const FAST: Timing = Timing {
    poll: Duration::from_millis(10),
    handshake: Duration::from_secs(5),
    ping: Duration::from_millis(100),
    keep_alive_s: 60,
    silence: Duration::from_secs(5),
    backoff_first: Duration::from_millis(40),
    backoff_max: Duration::from_millis(160),
    stable: Duration::from_secs(600),
};
struct Dir(PathBuf);
impl Dir {
    fn new() -> Self {
        let dir = std::env::temp_dir().join(format!("wstx-pskr-{}", profile::new_uuid().unwrap()));
        std::fs::create_dir(&dir).unwrap();
        Self(dir)
    }
}
impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
fn local_connector(port: u16) -> Connector {
    station_connector(Some(&format!("tcp:127.0.0.1:{port}"))).unwrap()
}
/// A broker's side of one connection: read one MQTT packet, as (first byte, body).
fn read_packet(stream: &mut TcpStream) -> Option<(u8, Vec<u8>)> {
    let mut first = [0u8; 2];
    stream.read_exact(&mut first).ok()?;
    assert!(first[1] < 128, "these packets are short");
    let mut body = vec![0u8; usize::from(first[1])];
    stream.read_exact(&mut body).ok()?;
    Some((first[0], body))
}
fn publish(stream: &mut TcpStream, topic: &str, payload: &str) {
    let mut body = Vec::new();
    text(&mut body, topic);
    body.extend_from_slice(payload.as_bytes());
    stream.write_all(&packet(0x30, &body)).unwrap();
}
fn until(what: &str, mut done: impl FnMut() -> bool) {
    let start = Instant::now();
    while !done() {
        assert!(start.elapsed() < Duration::from_secs(10), "{what}");
        std::thread::sleep(Duration::from_millis(5));
    }
}
fn fresh_spot(sender: &str, receiver: &str) -> String {
    format!(
        r#"{{"f":7075512,"md":"FT8","t":{},"sc":"{sender}","rc":"{receiver}","b":"40m"}}"#,
        utc_s()
    )
}
fn next_ping(log: &mpsc::Receiver<(u8, Vec<u8>)>) -> (u8, Vec<u8>) {
    loop {
        let p = log.recv_timeout(Duration::from_secs(5)).unwrap();
        if p.0 == 0xc0 {
            return p;
        }
    }
}

// Proves: CL-039-20; TC-039-020. The whole session against a local peer: only the handshake, the
// two filters and pings on the wire; a target change replaces its subscription; spots reach the
// model only by their payload; status from connecting through connected to off.
#[test]
fn session_against_a_local_peer() {
    let dir = Dir::new();
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let (log_tx, log) = mpsc::channel::<(u8, Vec<u8>)>();
    let (say_tx, say) = mpsc::channel::<(String, String)>();
    let peer = std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        stream
            .set_read_timeout(Some(Duration::from_millis(5)))
            .unwrap();
        let mut buffer: Vec<u8> = Vec::new();
        loop {
            let mut chunk = [0u8; 256];
            match stream.read(&mut chunk) {
                Ok(0) => return,
                Ok(n) => buffer.extend_from_slice(&chunk[..n]),
                Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {}
                Err(_) => return,
            }
            while buffer.len() >= 2 && buffer.len() >= 2 + usize::from(buffer[1]) {
                let body: Vec<u8> = buffer.drain(..2 + usize::from(buffer[1])).collect();
                let (first, body) = (body[0], body[2..].to_vec());
                match first {
                    0x10 => stream.write_all(&[0x20, 2, 0, 0]).unwrap(),
                    0x82 => stream.write_all(&[0x90, 3, body[0], body[1], 0]).unwrap(),
                    0xa2 => stream.write_all(&[0xb0, 2, body[0], body[1]]).unwrap(),
                    0xc0 => stream.write_all(&[0xd0, 0]).unwrap(),
                    _ => {}
                }
                log_tx.send((first, body)).unwrap();
            }
            while let Ok((topic, payload)) = say.try_recv() {
                publish(&mut stream, &topic, &payload);
            }
        }
    });
    let feed = Feed::start(&dir.0, "p", "b00t", Some(local_connector(port)), FAST);
    assert_eq!(
        feed.view()["state"],
        "off",
        "no call yet: nothing to subscribe"
    );
    feed.observe(Some("HB9BLA"), None);
    until("connected", || feed.view()["state"] == "connected");

    let connect = log.recv_timeout(Duration::from_secs(5)).unwrap();
    assert_eq!(connect.0, 0x10);
    assert_eq!(&connect.1[8..10], &[0, 60], "keep-alive");
    assert_eq!(&connect.1[10..12], &[0, 14]);
    assert_eq!(&connect.1[12..], b"wstxHB9BLAb00t");
    assert_eq!(connect.1[7], 0x02, "no will, no user name, no password");
    let filter_of = |p: &(u8, Vec<u8>), tail: usize| {
        String::from_utf8(p.1[4..p.1.len() - tail].to_vec()).unwrap()
    };
    let next = |wanted: u8| loop {
        let p = log.recv_timeout(Duration::from_secs(5)).unwrap();
        if p.0 != 0xc0 {
            assert_eq!(p.0, wanted, "only pings between the expected packets");
            return p;
        }
    };
    assert_eq!(filter_of(&next(0x82), 1), "pskr/filter/v2/+/+/HB9BLA/+/#");

    feed.observe(Some("HB9BLA"), Some("K1ABC"));
    assert_eq!(filter_of(&next(0x82), 1), "pskr/filter/v2/+/+/+/K1ABC/#");

    // A hostile target subscribes nothing, and the old subscription goes.
    feed.observe(Some("HB9BLA"), Some("K1+/#"));
    assert_eq!(filter_of(&next(0xa2), 0), "pskr/filter/v2/+/+/+/K1ABC/#");
    feed.observe(Some("HB9BLA"), Some("W1AW"));
    assert_eq!(filter_of(&next(0x82), 1), "pskr/filter/v2/+/+/+/W1AW/#");

    // The payload decides, not the topic.
    let topic = "pskr/filter/v2/40m/FT8/HB9BLA/W1AW/JN37/FN31/287/291".to_owned();
    say_tx.send((topic.clone(), "not json".into())).unwrap();
    say_tx
        .send((topic.clone(), fresh_spot("DL1XYZ", "F5AAA")))
        .unwrap();
    say_tx
        .send((topic.clone(), fresh_spot("HB9BLA", "W1AW")))
        .unwrap();
    say_tx
        .send((topic.clone(), fresh_spot("DL1XYZ", "W1AW")))
        .unwrap();
    until("the spot", || feed.hears_us("W1AW", "FT8", "40m"));
    until("the frequency", || {
        feed.decoded_offsets("FT8", "40m", 7_074_000, (300, 2650)) == vec![1512]
    });
    assert!(!feed.view()["last_spot_utc_s"].is_null());
    assert!(!feed.hears_us("F5AAA", "FT8", "40m"));

    // Keep-alive: a ping goes out and the link stays up.
    assert_eq!(next_ping(&log), (0xc0, vec![]));
    assert_eq!(feed.view()["state"], "connected");

    // Off: a clean disconnect, and nothing known any more.
    assert_eq!(
        feed.set_enabled("other", "b00t", false),
        Err("wrong_profile")
    );
    assert_eq!(feed.set_enabled("p", "other", false), Err("state_conflict"));
    let view = feed.set_enabled("p", "b00t", false).unwrap();
    assert_eq!(view["state"], "off");
    assert_eq!(view["enabled"], false);
    assert!(!feed.hears_us("W1AW", "FT8", "40m"));
    assert!(
        feed.decoded_offsets("FT8", "40m", 7_074_000, (300, 2650))
            .is_empty()
    );
    loop {
        let p = log.recv_timeout(Duration::from_secs(5)).unwrap();
        if p.0 == 0xe0 {
            break;
        }
        assert_eq!(p.0, 0xc0, "after off only a ping may still be under way");
    }
    drop(say_tx);
    peer.join().unwrap();
    // The choice is kept for the next start.
    assert_eq!(
        Feed::start(&dir.0, "p", "b00t", None, FAST).view()["enabled"],
        false
    );
}

// Proves: CL-039-20; TC-039-020. A peer that accepts and drops at once sees the attempts spread
// by the doubling delay; the status names the error, then recovers without any operator step.
#[test]
fn reconnect_backs_off_against_a_failing_peer_and_recovers() {
    let dir = Dir::new();
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let (times_tx, times) = mpsc::channel::<Instant>();
    std::thread::spawn(move || {
        for n in 0.. {
            let Ok((mut stream, _)) = listener.accept() else {
                return;
            };
            let _ = times_tx.send(Instant::now());
            if n < 5 {
                continue; // dropped at once
            }
            let Some((0x10, _)) = read_packet(&mut stream) else {
                return;
            };
            stream.write_all(&[0x20, 2, 0, 0]).unwrap();
            while read_packet(&mut stream).is_some() {}
            return;
        }
    });
    let feed = Feed::start(&dir.0, "p", "b00t", Some(local_connector(port)), FAST);
    feed.observe(Some("HB9BLA"), None);
    let mut errors = 0;
    until("recovered", || {
        errors += usize::from(feed.view()["state"] == "error");
        feed.view()["state"] == "connected"
    });
    assert!(errors > 0, "the status named the failure on the way");
    assert_eq!(
        feed.view()["error"],
        Value::Null,
        "a good connection clears it"
    );
    let stamps: Vec<Instant> = times.try_iter().collect();
    assert_eq!(stamps.len(), 6);
    let gaps: Vec<u128> = stamps
        .windows(2)
        .map(|w| (w[1] - w[0]).as_millis())
        .collect();
    for (gap, least) in gaps.iter().zip([40u128, 80, 160, 160, 160]) {
        assert!(*gap + 5 >= least, "{gaps:?}");
    }
}

// Proves: CL-039-20; TC-039-020. Refused and broken brokers: a named error, never a panic.
#[test]
fn a_refusing_or_broken_peer_is_a_named_error() {
    for (script, code) in [
        (vec![0x20, 2, 0, 5], "connection_refused"),
        (
            vec![0x20, 2, 0, 0, 0x90, 3, 0, 1, 0x80],
            "subscribe_refused",
        ),
        (vec![0x20, 2, 0, 0, 0xf0, 0], "protocol_error"),
    ] {
        let dir = Dir::new();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let _ = read_packet(&mut stream);
            let _ = stream.write_all(&script);
            std::thread::sleep(Duration::from_millis(500));
        });
        let feed = Feed::start(&dir.0, "p", "b00t", Some(local_connector(port)), FAST);
        feed.observe(Some("HB9BLA"), None);
        until(code, || feed.view()["error"] == code);
    }
}

// Proves: CL-039-20; TC-039-020. The default is on; a setting from another profile or a broken
// file reads as the default.
#[test]
fn the_setting_defaults_on_and_survives() {
    let dir = Dir::new();
    let feed = Feed::start(&dir.0, "p", "b", None, FAST);
    assert_eq!(feed.view()["enabled"], true);
    assert_eq!(feed.view()["state"], "off", "no connector: no connection");
    feed.set_enabled("p", "b", false).unwrap();
    drop(feed);
    assert_eq!(
        Feed::start(&dir.0, "p", "b", None, FAST).view()["enabled"],
        false
    );
    let foreign = Feed::start(&dir.0, "q", "b", None, FAST).view();
    assert_eq!(foreign["enabled"], true);
    assert_eq!(foreign["storage_error"], "invalid_pskr");
    std::fs::write(dir.0.join(FILE), b"{").unwrap();
    assert_eq!(
        Feed::start(&dir.0, "p", "b", None, FAST).view()["storage_error"],
        "invalid_pskr"
    );
}

// Proves: CL-039-20; TC-039-020. Only WSTX_PSKR=tcp: with a loopback address replaces the broker;
// anything else unknown opens no connection.
#[test]
fn the_broker_can_only_be_replaced_on_loopback() {
    let some = |setting: Option<&str>| station_connector(setting).is_some();
    assert!(some(None));
    assert!(!some(Some("off")));
    assert!(!some(Some("")));
    assert!(!some(Some("tcp:192.168.0.37:1883")));
    assert!(!some(Some("tcp:mqtt.pskreporter.info:1883")));
    assert!(some(Some("tcp:127.0.0.1:1883")));
}

fn chain() -> Vec<CertificateDer<'static>> {
    CertificateDer::pem_slice_iter(include_bytes!(
        "../../fixtures/pskr/broker-chain-20261106.pem"
    ))
    .map(Result::unwrap)
    .collect()
}
fn verify(host: &'static str, utc_s: u64) -> Result<(), rustls::Error> {
    let verifier = rustls::client::WebPkiServerVerifier::builder_with_provider(
        Arc::new(root_store(ISRG_ROOTS).unwrap()),
        Arc::new(rustls::crypto::ring::default_provider()),
    )
    .build()
    .unwrap();
    let chain = chain();
    verifier
        .verify_server_cert(
            &chain[0],
            &chain[1..],
            &ServerName::try_from(host).unwrap(),
            &[],
            UnixTime::since_unix_epoch(Duration::from_secs(utc_s)),
        )
        .map(|_| ())
}
// Proves: CL-039-20; TC-039-020. The compiled-in roots validate the chain the broker presented on
// 2026-11-06 (captured once, checked here with no network) and refuse another name or time.
#[test]
fn the_compiled_roots_validate_the_captured_broker_chain() {
    const CAPTURED: u64 = 1_793_923_200; // 2026-11-06 00:00 UTC
    assert_eq!(verify(HOST, CAPTURED), Ok(()));
    assert!(verify("mqtt.example.org", CAPTURED).is_err());
    assert!(verify(HOST, CAPTURED + 200 * 86_400).is_err(), "expired");
}

// Proves: CL-039-20; TC-039-020. A peer without valid TLS is never spoken to in MQTT.
#[test]
fn a_peer_without_tls_is_refused() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let peer = std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut hello = [0u8; 1];
        stream.read_exact(&mut hello).unwrap();
        stream
            .write_all(b"HTTP/1.0 400 nothing like TLS\r\n\r\n")
            .unwrap();
        hello[0]
    });
    let code = tls_connect("localhost", port, ISRG_ROOTS, &FAST).err();
    assert_eq!(code, Some("tls_failed"));
    assert_eq!(peer.join().unwrap(), 0x16, "the client spoke TLS first");
}

// Proves: CL-039-20; TC-039-020. GET and POST /pskr through the station router; the push event.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn http_routes_read_and_switch_the_feed() {
    let f = crate::contact_http_tests::fixture("http://127.0.0.1:18453", false);
    let (status, _, _, _) = f.call("GET", "/pskr", None).await;
    assert_eq!(
        status,
        StatusCode::NOT_FOUND,
        "no feed in an in-process station"
    );
    let dir = Dir::new();
    let feed = Feed::start(&dir.0, &f.id, &f.boot, None, FAST);
    f.state.recording.pskr.set(feed.clone()).ok().unwrap();
    let (status, view, _, _) = f.call("GET", "/pskr", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(view["enabled"], true);
    assert_eq!(view["state"], "off");
    assert_eq!(view["last_spot_utc_s"], Value::Null);
    let before = feed.revision();
    let body = |enabled: bool| json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"enabled":enabled});
    let (status, view, _, _) = f.call("POST", "/pskr", Some(body(false))).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(view["enabled"], false);
    assert!(feed.revision() > before, "the change reaches pushed peers");
    let (revision, event) = feed.event();
    assert_eq!(revision, feed.revision());
    let event: Value = serde_json::from_str(&event).unwrap();
    assert_eq!(event["type"], "pskr.state");
    assert_eq!(event["data"]["enabled"], false);
    let mut extra = body(true);
    extra["host"] = json!("evil.example");
    let (status, _, _, _) = f.call("POST", "/pskr", Some(extra)).await;
    assert_ne!(status, StatusCode::OK, "no other broker through the route");
    assert_eq!(feed.view()["enabled"], false);
    let (status, _, _, _) = f.call("GET", "/pskr?x=1", None).await;
    assert_ne!(status, StatusCode::OK);
}
