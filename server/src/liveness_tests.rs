#![forbid(unsafe_code)]
// TC-021-008 dead peer removal: the actual router in the test process on a plaintext loopback
// profile (no authorization), served over transports the test holds (in-process duplex streams
// with a 1 MiB buffer, so a peer that stops reading keeps accepting writes like a vanished
// browser behind a kernel buffer). The runtime clock is paused and driven by the runtime itself:
// no real wait. Each peer writes its own HTTP upgrade and masked WebSocket frames.
use super::*;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt, DuplexStream, ReadHalf, WriteHalf},
    sync::{mpsc, oneshot},
    time::Instant as Driven,
};

/// The listener of the transports the test holds.
pub(crate) struct Held(pub(crate) mpsc::UnboundedReceiver<DuplexStream>);
impl axum::serve::Listener for Held {
    type Io = DuplexStream;
    type Addr = ();
    async fn accept(&mut self) -> (DuplexStream, ()) {
        match self.0.recv().await {
            Some(io) => (io, ()),
            None => std::future::pending().await,
        }
    }
    fn local_addr(&self) -> std::io::Result<()> {
        Ok(())
    }
}

/// A client frame (RFC 6455 5.2): FIN, the opcode, the masked payload under a fixed key.
pub(crate) fn client_frame(opcode: u8, payload: &[u8]) -> Vec<u8> {
    let key = [0x37u8, 0xfa, 0x21, 0x3d];
    let mut frame = vec![0x80 | opcode];
    match payload.len() {
        n if n < 126 => frame.push(0x80 | n as u8),
        n if n < 65536 => {
            frame.push(0x80 | 126);
            frame.extend_from_slice(&(n as u16).to_be_bytes());
        }
        n => {
            frame.push(0x80 | 127);
            frame.extend_from_slice(&(n as u64).to_be_bytes());
        }
    }
    frame.extend_from_slice(&key);
    frame.extend(payload.iter().enumerate().map(|(i, b)| b ^ key[i % 4]));
    frame
}

/// One complete frame at the start of `buffer`: (opcode, payload, frame length).
pub(crate) fn parse_frame(buffer: &[u8]) -> Option<(u8, Vec<u8>, usize)> {
    let first = *buffer.first()?;
    let second = *buffer.get(1)?;
    let (length, mut at) = match second & 0x7f {
        126 => (
            u16::from_be_bytes(buffer.get(2..4)?.try_into().ok()?) as usize,
            4,
        ),
        127 => (
            u64::from_be_bytes(buffer.get(2..10)?.try_into().ok()?) as usize,
            10,
        ),
        n => (n as usize, 2),
    };
    let key = if second & 0x80 != 0 {
        let key: [u8; 4] = buffer.get(at..at + 4)?.try_into().ok()?;
        at += 4;
        Some(key)
    } else {
        None
    };
    let payload = buffer.get(at..at + length)?;
    let payload = match key {
        Some(key) => payload
            .iter()
            .enumerate()
            .map(|(i, b)| b ^ key[i % 4])
            .collect(),
        None => payload.to_vec(),
    };
    Some((first & 0x0f, payload, at + length))
}

pub(crate) fn upgrade_request(origin: &str, extra: &str) -> String {
    format!(
        "GET /ws HTTP/1.1\r\nHost: 127.0.0.1\r\nOrigin: {origin}\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Protocol: wstx.v1\r\n{extra}\r\n"
    )
}

/// A peer on a held transport. Its reader answers each Ping with a Pong only when `answers`;
/// it hands on every text message and reports when the station closed the transport.
struct Peer {
    writer: Arc<tokio::sync::Mutex<WriteHalf<DuplexStream>>>,
    texts: mpsc::UnboundedReceiver<Value>,
    closed: oneshot::Receiver<Driven>,
}
impl Peer {
    async fn open(
        listener: &mpsc::UnboundedSender<DuplexStream>,
        origin: &str,
        answers: bool,
    ) -> Peer {
        let (mut client, server) = tokio::io::duplex(1 << 20);
        listener.send(server).unwrap();
        client
            .write_all(upgrade_request(origin, "").as_bytes())
            .await
            .unwrap();
        let mut buffer = Vec::new();
        let head = loop {
            if let Some(end) = buffer.windows(4).position(|w| w == b"\r\n\r\n") {
                break buffer.drain(..end + 4).collect::<Vec<_>>();
            }
            let mut chunk = [0u8; 4096];
            let n = client.read(&mut chunk).await.unwrap();
            assert!(n > 0, "the station closed the upgrade");
            buffer.extend_from_slice(&chunk[..n]);
        };
        assert!(
            head.starts_with(b"HTTP/1.1 101"),
            "{}",
            String::from_utf8_lossy(&head)
        );
        let (reader, writer) = tokio::io::split(client);
        let writer = Arc::new(tokio::sync::Mutex::new(writer));
        let (texts_tx, texts) = mpsc::unbounded_channel();
        let (closed_tx, closed) = oneshot::channel();
        tokio::spawn(read_frames(
            reader,
            buffer,
            writer.clone(),
            answers,
            texts_tx,
            closed_tx,
        ));
        Peer {
            writer,
            texts,
            closed,
        }
    }
    async fn send(&self, value: Value) {
        let frame = client_frame(1, value.to_string().as_bytes());
        self.writer.lock().await.write_all(&frame).await.unwrap();
    }
}
async fn read_frames(
    mut reader: ReadHalf<DuplexStream>,
    mut buffer: Vec<u8>,
    writer: Arc<tokio::sync::Mutex<WriteHalf<DuplexStream>>>,
    answers: bool,
    texts: mpsc::UnboundedSender<Value>,
    closed: oneshot::Sender<Driven>,
) {
    loop {
        while let Some((opcode, payload, length)) = parse_frame(&buffer) {
            buffer.drain(..length);
            match opcode {
                1 => {
                    let _ = texts.send(serde_json::from_slice(&payload).unwrap());
                }
                9 if answers => {
                    let pong = client_frame(10, &payload);
                    let _ = writer.lock().await.write_all(&pong).await;
                }
                _ => {}
            }
        }
        let mut chunk = [0u8; 8192];
        match reader.read(&mut chunk).await {
            Ok(n) if n > 0 => buffer.extend_from_slice(&chunk[..n]),
            _ => {
                let _ = closed.send(Driven::now());
                return;
            }
        }
    }
}

/// A plaintext loopback profile: no authorization owner, the runtime-token contract without a
/// token (WstxStationProtocol::SessionSecurity, explicit loopback development).
pub(crate) fn plaintext_station(name: &str) -> (App, std::path::PathBuf) {
    let root = std::env::temp_dir().join(format!("wstx-{name}-{}", profile::new_uuid().unwrap()));
    std::fs::create_dir(&root).unwrap();
    let id = profile::new_uuid().unwrap();
    let boot = profile::new_uuid().unwrap();
    let document = json!({"schema_version":1,"profile_id":id,"revision":0,"display_name":"Plaintext fixture",
        "callsign":"HB9BLA","locator":"JN37VL","endpoint":{"bind":"127.0.0.1:18001","origin":null},
        "connection_type":"standard","audio":{"input_device":null,"output_device":null},
        "control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}});
    std::fs::write(
        root.join("profile.json"),
        serde_json::to_vec(&document).unwrap(),
    )
    .unwrap();
    let origin = "http://127.0.0.1:18001".to_owned();
    let (mut store, _) = profile::Store::open(&root).unwrap();
    let authorization = authorization_http::Service::initialize(&mut store, &origin).unwrap();
    assert!(authorization.is_none(), "plaintext has no grant authority");
    let recording = recording::Recording::open(&root, id.clone(), boot.clone());
    recording.initialize_profile_revision(0);
    let app = App {
        origin,
        profile: Some(Arc::new(ProfileState {
            store: Mutex::new(store),
            authorization: Mutex::new(authorization),
            boot,
            recording,
            logbook: Arc::new(crate::logbook::Logbook::open(&root)),
        })),
        profile_id: Some(id),
        token: None,
        connections: Arc::new(Semaphore::new(16)),
        login_attempts: Arc::new(Mutex::new((Instant::now(), 0))),
    };
    (app, root)
}

// Proves: CL-003-06, CL-003-02; TC-021-008. A peer that stops answering is removed with "no pong
// for 15 s" at the first heartbeat tick more than 15 s after its last Pong (driven time in
// (15 s, 20 s], never earlier); another peer's station.get every 5 s is answered within 2 s
// throughout and after; a peer answering every Ping stays open through 60 s.
#[tokio::test(start_paused = true)]
async fn silent_peer_is_removed_at_the_next_heartbeat_after_15_s() {
    let (app, root) = plaintext_station("liveness");
    let origin = app.origin.clone();
    let (listener, accepted) = mpsc::unbounded_channel();
    let service = tokio::spawn(axum::serve(Held(accepted), router(app)).into_future());
    let closes_before = SOCKET_CLOSES.lock().unwrap().len();
    let start = Driven::now();

    // Peer A subscribes Thin, then neither reads its messages nor answers Ping.
    let mut a = Peer::open(&listener, &origin, false).await;
    a.send(json!({"v":1,"type":"spectrum.thin","id":1})).await;
    let subscribed = a.texts.recv().await.unwrap();
    assert_eq!(
        subscribed,
        json!({"v":1,"type":"spectrum.subscription","id":1,"data":{"profile":"thin"}})
    );
    let b = Peer::open(&listener, &origin, true).await;
    let mut c = Peer::open(&listener, &origin, true).await;
    assert_eq!(Driven::now(), start, "the peers connect at driven time 0");

    // Peer B: station.get every 5 s through 60 s, each answered within 2 s.
    let healthy = tokio::spawn(async move {
        let mut b = b;
        let mut answered = Vec::new();
        for n in 1..=12u64 {
            tokio::time::sleep_until(start + Duration::from_secs(5 * n)).await;
            let sent = Driven::now();
            b.send(json!({"v":1,"type":"station.get","id":n})).await;
            let reply = tokio::time::timeout(Duration::from_secs(2), async {
                loop {
                    let message = b.texts.recv().await.expect("B was closed");
                    if message["type"] == "station.status" {
                        break message;
                    }
                }
            })
            .await
            .unwrap_or_else(|_| panic!("station.get {n} unanswered within 2 s"));
            assert_eq!(reply["id"], n);
            answered.push((sent - start, Driven::now() - sent));
        }
        (answered, b)
    });

    let closed = tokio::time::timeout(Duration::from_secs(25), &mut a.closed)
        .await
        .expect("the silent peer A is still open 25 s after its last Pong")
        .unwrap();
    let after = closed - start;
    assert!(
        after > Duration::from_secs(15) && after <= Duration::from_secs(20),
        "A removed after {after:?}, not in (15 s, 20 s]"
    );
    let reasons: Vec<Value> = SOCKET_CLOSES.lock().unwrap()[closes_before..]
        .iter()
        .map(|close| close["reason"].clone())
        .collect();
    assert!(
        reasons.contains(&json!("no pong for 15 s")),
        "close reasons {reasons:?}"
    );

    let (answered, b) = healthy.await.unwrap();
    assert_eq!(answered.len(), 12);
    for (at, took) in &answered {
        assert!(
            *took <= Duration::from_secs(2),
            "{at:?}: answered after {took:?}"
        );
    }
    assert!(
        answered.iter().any(|(at, _)| *at > after),
        "B used after A's removal"
    );

    // Control: C answered every Ping and is still open at 60 s, and usable.
    tokio::time::sleep_until(start + Duration::from_secs(61)).await;
    assert!(
        matches!(
            c.closed.try_recv(),
            Err(oneshot::error::TryRecvError::Empty)
        ),
        "a peer answering every Ping was closed"
    );
    c.send(json!({"v":1,"type":"station.get","id":99})).await;
    let reply = tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            let message = c.texts.recv().await.unwrap();
            if message["type"] == "station.status" {
                break message;
            }
        }
    })
    .await
    .unwrap();
    assert_eq!(reply["id"], 99);
    drop((b, c));
    service.abort();
    let _ = std::fs::remove_dir_all(root);
}

fn utc_now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64
}

// Evidence of #102 (no promise; the record of TC-009-005 case 7's failure output). Each socket the
// station ends leaves its reason, begin and end, last heartbeat write and longest heartbeat
// interval, in UTC ms: the begin's system UTC plus the driven runtime's elapsed time. Hand values
// from connection(): the first heartbeat tick is consumed at the begin, writes follow every
// 5000 ms, removal at the first tick more than 15000 ms after the last Pong.
#[tokio::test(start_paused = true)]
async fn station_records_each_ended_socket_on_the_one_utc_clock() {
    let (app, root) = plaintext_station("socket-record");
    let origin = app.origin.clone();
    let (listener, accepted) = mpsc::unbounded_channel();
    let service = tokio::spawn(axum::serve(Held(accepted), router(app)).into_future());
    let closes_before = SOCKET_CLOSES.lock().unwrap().len();
    let wall_before = utc_now_ms();
    let start = Driven::now();

    // (a) Peer A of TC-021-008: subscribes Thin and never answers Ping.
    let mut a = Peer::open(&listener, &origin, false).await;
    a.send(json!({"v":1,"type":"spectrum.thin","id":1})).await;
    assert_eq!(
        a.texts.recv().await.unwrap()["type"],
        "spectrum.subscription"
    );
    // (b) A peer that answers every Ping and closes itself at driven +12000.
    let b = Peer::open(&listener, &origin, true).await;
    assert_eq!(Driven::now(), start, "the peers connect at driven time 0");
    tokio::time::sleep_until(start + Duration::from_millis(12000)).await;
    b.writer
        .lock()
        .await
        .write_all(&client_frame(8, &[]))
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(25), &mut a.closed)
        .await
        .expect("the silent peer A is still open")
        .unwrap();
    // The station records the end after the transport closed: let its task finish.
    tokio::time::sleep(Duration::from_millis(1)).await;
    let wall_after = utc_now_ms();

    // Records of this test: begun inside its wall-clock span. A concurrent test's socket begun in
    // the same span differs in its driven offsets, so each case is found by its own reason.
    let records: Vec<Value> = SOCKET_CLOSES.lock().unwrap()[closes_before..]
        .iter()
        .filter(|r| {
            r["begin_utc_ms"]
                .as_u64()
                .is_some_and(|b| b >= wall_before && b <= wall_after)
        })
        .cloned()
        .collect();
    let offset = |record: &Value, field: &str| {
        let begin = record["begin_utc_ms"].as_u64().unwrap();
        record[field].as_u64().map(|t| t as i64 - begin as i64)
    };
    let found = |reason: &str, end: &dyn Fn(i64) -> bool| {
        records
            .iter()
            .find(|r| r["reason"] == reason && offset(r, "utc_ms").is_some_and(end))
            .unwrap_or_else(|| panic!("no record {reason:?} with its end; records {records:?}"))
            .clone()
    };

    // (a) heartbeat writes at +5000, +10000 and +15000; removed at the +20000 tick.
    let silent = found("no pong for 15 s", &|end| end == 20000);
    assert_eq!(
        offset(&silent, "last_heartbeat_utc_ms"),
        Some(15000),
        "{silent}"
    );
    assert_eq!(silent["longest_heartbeat_ms"], 5000, "{silent}");
    assert_eq!(
        offset(&silent, "longest_heartbeat_end_utc_ms"),
        Some(5000),
        "the earliest of the equal intervals: {silent}"
    );
    // (b) writes at +5000 and +10000; the peer's own close at +12000 ends it.
    let closed = found("peer closed or receive error", &|end| {
        (12000..15000).contains(&end)
    });
    assert_eq!(
        offset(&closed, "last_heartbeat_utc_ms"),
        Some(10000),
        "{closed}"
    );
    assert_eq!(closed["longest_heartbeat_ms"], 5000, "{closed}");
    assert_eq!(
        offset(&closed, "longest_heartbeat_end_utc_ms"),
        Some(5000),
        "{closed}"
    );
    // (c) `reason` and `utc_ms` keep their names and meaning: why, and the end on the UTC clock.
    for record in [&silent, &closed] {
        assert!(record["reason"].is_string(), "{record}");
        let begin = record["begin_utc_ms"].as_u64().unwrap();
        assert!(begin >= wall_before && begin <= wall_after, "{record}");
        assert!(record["utc_ms"].as_u64().unwrap() >= begin, "{record}");
    }
    drop((a, b));
    service.abort();
    let _ = std::fs::remove_dir_all(root);
}
