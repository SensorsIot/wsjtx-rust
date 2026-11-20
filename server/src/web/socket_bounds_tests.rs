#![forbid(unsafe_code)]
// TC-021-008 bounds (WstxListener::BoundsRule): the actual router in the test process on the
// plaintext loopback profile with the product's socket bound, served over transports the test
// holds, on a runtime clock paused from driven time 0 and driven by the runtime itself (no real
// wait). Each test observes only at the peer: the status line of the upgrade answer, the frames
// the peer reads, and the driven instant the station drops its end of the peer's transport.
// A stalled peer reads nothing, so it learns of its close from that drop, not by reading.
//
// Hand values from connection(): the first heartbeat write is at +5000 ms; a peer that never
// subscribes is owed no write before it (receive.state goes only with a job, and this station
// has none); the heartbeat text {"v":1,"type":"heartbeat"} is 26 bytes, 28 with its frame header.
use super::*;
use crate::liveness_tests::{Held, plaintext_station, upgrade_request};
use std::{
    pin::Pin,
    task::{Context, Poll},
};
use tokio::{
    io::{
        AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, DuplexStream, ReadBuf, ReadHalf,
        WriteHalf,
    },
    sync::{
        mpsc,
        oneshot::{self, error::TryRecvError},
    },
    time::Instant as Driven,
};
use wstx_test_tools::ws_frame::{client_frame, parse_frame};

/// The station's end of a held transport: it reports the driven instant the station drops it.
struct Watched {
    io: DuplexStream,
    dropped: Option<oneshot::Sender<Driven>>,
}
impl Drop for Watched {
    fn drop(&mut self) {
        if let Some(dropped) = self.dropped.take() {
            let _ = dropped.send(Driven::now());
        }
    }
}
impl AsyncRead for Watched {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.io).poll_read(cx, buf)
    }
}
impl AsyncWrite for Watched {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        Pin::new(&mut self.io).poll_write(cx, buf)
    }
    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.io).poll_flush(cx)
    }
    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.io).poll_shutdown(cx)
    }
}

/// The plaintext station with the product's socket bound, served over watched transports.
struct Station {
    listener: mpsc::UnboundedSender<Watched>,
    origin: String,
    service: tokio::task::JoinHandle<std::io::Result<()>>,
    root: std::path::PathBuf,
}
impl Station {
    fn start(name: &str) -> Station {
        let (mut app, root) = plaintext_station(name);
        app.connections = Arc::new(Semaphore::new(SOCKET_BOUND));
        let origin = app.origin.clone();
        let (listener, accepted) = mpsc::unbounded_channel();
        let service = tokio::spawn(axum::serve(Held(accepted), router(app)).into_future());
        Station {
            listener,
            origin,
            service,
            root,
        }
    }
    /// A transport of `buffer` bytes each way: the peer's end, and the instant the station
    /// drops its end.
    fn transport(&self, buffer: usize) -> (DuplexStream, oneshot::Receiver<Driven>) {
        let (client, server) = tokio::io::duplex(buffer);
        let (dropped, closed) = oneshot::channel();
        self.listener
            .send(Watched {
                io: server,
                dropped: Some(dropped),
            })
            .unwrap();
        (client, closed)
    }
    fn stop(self) {
        self.service.abort();
        let _ = std::fs::remove_dir_all(self.root);
    }
}

/// Writes the upgrade request and reads the head of its answer one byte at a time, so that
/// nothing after the head is taken from the transport.
async fn upgrade(client: &mut DuplexStream, origin: &str) -> String {
    client
        .write_all(upgrade_request(origin, "").as_bytes())
        .await
        .unwrap();
    let mut head = Vec::new();
    while !head.ends_with(b"\r\n\r\n") {
        let mut byte = [0u8; 1];
        let n = client.read(&mut byte).await.unwrap();
        assert!(
            n > 0,
            "the station closed the upgrade: {}",
            String::from_utf8_lossy(&head)
        );
        head.push(byte[0]);
    }
    String::from_utf8(head).unwrap()
}

fn open(closed: &mut oneshot::Receiver<Driven>) -> bool {
    matches!(closed.try_recv(), Err(TryRecvError::Empty))
}

/// A peer with a 1 MiB transport that reads all it is sent and answers each Ping.
struct Peer {
    writer: Arc<tokio::sync::Mutex<WriteHalf<DuplexStream>>>,
    texts: mpsc::UnboundedReceiver<Value>,
    closed: oneshot::Receiver<Driven>,
}
impl Peer {
    async fn open(station: &Station, which: &str) -> Peer {
        let (mut client, closed) = station.transport(1 << 20);
        let head = upgrade(&mut client, &station.origin).await;
        assert!(head.starts_with("HTTP/1.1 101"), "{which}: {head}");
        let (reader, writer) = tokio::io::split(client);
        let writer = Arc::new(tokio::sync::Mutex::new(writer));
        let (texts_tx, texts) = mpsc::unbounded_channel();
        tokio::spawn(answer_pings(reader, writer.clone(), texts_tx));
        Peer {
            writer,
            texts,
            closed,
        }
    }
    async fn frame(&self, opcode: u8, payload: &[u8]) {
        let frame = client_frame(opcode, payload);
        self.writer.lock().await.write_all(&frame).await.unwrap();
    }
    /// Sends station.get with `id` and returns the driven instant of its station.status.
    async fn status(&mut self, id: u64) -> Driven {
        let request = json!({"v":1,"type":"station.get","id":id});
        self.frame(1, request.to_string().as_bytes()).await;
        loop {
            let message = self
                .texts
                .recv()
                .await
                .unwrap_or_else(|| panic!("closed before answering station.get {id}"));
            if message["type"] == "station.status" {
                assert_eq!(message["id"], id, "{message}");
                return Driven::now();
            }
        }
    }
}
async fn answer_pings(
    mut reader: ReadHalf<DuplexStream>,
    writer: Arc<tokio::sync::Mutex<WriteHalf<DuplexStream>>>,
    texts: mpsc::UnboundedSender<Value>,
) {
    let mut buffer = Vec::new();
    loop {
        while let Some((opcode, payload, length)) = parse_frame(&buffer) {
            buffer.drain(..length);
            match opcode {
                1 => {
                    let _ = texts.send(serde_json::from_slice(&payload).unwrap());
                }
                9 => {
                    let pong = client_frame(10, &payload);
                    let _ = writer.lock().await.write_all(&pong).await;
                }
                _ => {}
            }
        }
        let mut chunk = [0u8; 8192];
        match reader.read(&mut chunk).await {
            Ok(n) if n > 0 => buffer.extend_from_slice(&chunk[..n]),
            _ => return,
        }
    }
}

/// A peer with a 16-byte transport, below the 28-byte heartbeat frame, that reads only when
/// the test says.
struct Stalled {
    client: DuplexStream,
    closed: oneshot::Receiver<Driven>,
}
impl Stalled {
    async fn open(station: &Station) -> Stalled {
        let (mut client, closed) = station.transport(16);
        let head = upgrade(&mut client, &station.origin).await;
        assert!(head.starts_with("HTTP/1.1 101"), "the stalled peer: {head}");
        Stalled { client, closed }
    }
    /// Reads one byte at a time until one text frame is complete, and nothing after it.
    async fn read_text(&mut self) -> Value {
        let mut buffer = Vec::new();
        loop {
            if let Some((opcode, payload, _)) = parse_frame(&buffer) {
                assert_eq!(opcode, 1, "a text frame");
                return serde_json::from_slice(&payload).unwrap();
            }
            let mut byte = [0u8; 1];
            let n = self.client.read(&mut byte).await.unwrap();
            assert!(n > 0, "closed before a whole frame");
            buffer.push(byte[0]);
        }
    }
}

// 16 sockets open at driven time 0; the 17th upgrade is answered 503 and not 101; each of the
// 16 then answers station.get; after one of them closes, a new upgrade is answered 101.
// Proves: TC-021-008
#[tokio::test(start_paused = true)]
async fn a_socket_beyond_16_is_refused_with_503_and_the_16_keep_answering() {
    let station = Station::start("socket-bound");
    let start = Driven::now();
    let mut peers = Vec::new();
    for n in 1..=16 {
        peers.push(Peer::open(&station, &format!("socket {n} of 16")).await);
    }
    assert_eq!(Driven::now(), start, "the 16 connect at driven time 0");

    let (mut extra, _) = station.transport(1 << 20);
    let head = upgrade(&mut extra, &station.origin).await;
    assert!(head.starts_with("HTTP/1.1 503"), "the 17th socket: {head}");
    drop(extra);

    for (n, peer) in peers.iter_mut().enumerate() {
        peer.status(n as u64 + 1).await;
    }

    // One of the 16 closes; once the station has closed its transport, its place is free.
    let mut leaving = peers.pop().unwrap();
    leaving.frame(8, &[]).await;
    tokio::time::timeout(Duration::from_secs(5), &mut leaving.closed)
        .await
        .expect("the station keeps a socket its peer closed")
        .unwrap();
    let (mut again, _) = station.transport(1 << 20);
    let head = upgrade(&mut again, &station.origin).await;
    assert!(
        head.starts_with("HTTP/1.1 101"),
        "an upgrade after a close: {head}"
    );
    drop((peers, leaving, again));
    station.stop();
}

// A takes no output: its first write, the heartbeat at +5000 ms, cannot complete, and A's
// transport is closed in (6000, 7000] ms (hand value 7000: the heartbeat plus 2 s). B's
// station.get at +5500 and +6500 ms, while A is open, are each answered at the driven instant
// they were sent; B still answers at +8000 ms.
// Proves: TC-021-008
#[tokio::test(start_paused = true)]
async fn a_socket_that_takes_no_output_for_2_s_is_closed_and_delays_no_other() {
    let station = Station::start("stalled-write");
    let start = Driven::now();
    let mut a = Stalled::open(&station).await;
    let b = Peer::open(&station, "peer B").await;
    assert_eq!(Driven::now(), start, "the peers connect at driven time 0");

    let other = tokio::spawn(async move {
        let mut b = b;
        let mut answers = Vec::new();
        for (id, at) in [(1u64, 5500u64), (2, 6500), (3, 8000)] {
            tokio::time::sleep_until(start + Duration::from_millis(at)).await;
            let sent = Driven::now();
            let answered = b.status(id).await;
            answers.push((sent - start, answered - start));
        }
        (answers, b)
    });

    let closed = tokio::time::timeout_at(start + Duration::from_secs(25), &mut a.closed)
        .await
        .expect("A is still open at +25000 ms")
        .unwrap()
        - start;
    assert!(
        closed > Duration::from_millis(6000) && closed <= Duration::from_millis(7000),
        "A closed at {closed:?}, not in (6000, 7000] ms"
    );

    let (answers, b) = other.await.unwrap();
    for (sent, answered) in &answers {
        assert_eq!(
            answered, sent,
            "B's station.get at {sent:?} answered at {answered:?}"
        );
    }
    assert!(
        answers[..2].iter().all(|(sent, _)| *sent < closed),
        "B asked while A was open: {answers:?}, A closed at {closed:?}"
    );
    drop((a, b));
    station.stop();
}

// A subscribes Thin and reads until its spectrum.subscription answer at driven instant S, then
// reads nothing. The first recording_tick is taken at the subscription, so the station hands A
// its first optional event at S, and it stays unflushed. A's transport is closed in
// [S + 2000, S + 2500) ms (hand value S + 2000), before its heartbeat at +5000 ms.
// Proves: TC-021-008
#[tokio::test(start_paused = true)]
async fn a_socket_whose_event_stays_unflushed_for_2_s_is_closed() {
    let station = Station::start("stalled-flush");
    let start = Driven::now();
    let mut a = Stalled::open(&station).await;
    let request = json!({"v":1,"type":"spectrum.thin","id":1});
    a.client
        .write_all(&client_frame(1, request.to_string().as_bytes()))
        .await
        .unwrap();
    assert_eq!(
        a.read_text().await,
        json!({"v":1,"type":"spectrum.subscription","id":1,"data":{"profile":"thin"}})
    );
    let subscribed = Driven::now();
    assert!(open(&mut a.closed), "A closed at its subscription");

    let closed = tokio::time::timeout_at(start + Duration::from_secs(25), &mut a.closed)
        .await
        .expect("A is still open at +25000 ms")
        .unwrap();
    let after = closed - subscribed;
    assert!(
        after >= Duration::from_millis(2000) && after < Duration::from_millis(2500),
        "A closed {after:?} after its subscription at {:?}, not in [2000, 2500) ms",
        subscribed - start
    );
    drop(a);
    station.stop();
}
