#![forbid(unsafe_code)]
// TC-080-001 link byte log (WstxStationLink::LinkTrafficLog): the actual router in the test
// process, served by the station's own listener (TLS on a selected HTTPS profile with one enrolled
// browser grant and one MCP client; plaintext loopback in case (i)). The log's period clock and
// mode are driven by the test, and so is the runtime clock (paused): the station's heartbeat and
// pushes move only when the test advances it. Raw peers on a second runtime hold their own TCP
// sockets, count every byte they write and read, run their TLS client on top and write and read
// HTTP/1.1 text, WebSocket frames and (one peer) HTTP/2 themselves; each step waits until its
// exchanges are complete before the period clock moves. The expected line is the peers' own
// count by the log's rule; the estimate is the contract's formula, computed here.
use super::*;
use crate::link_log::{FILE, Log, Mode, PeriodClock};
use crate::liveness_tests::{client_frame, parse_frame, plaintext_station, upgrade_request};
use std::{
    collections::{BTreeMap, HashSet},
    io::Write as _,
    net::SocketAddr,
    pin::Pin,
    sync::atomic::{AtomicU64, Ordering},
    task::{Context, Poll},
};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, ReadBuf, WriteHalf};

/// 2027-01-15 08:00:00 UTC, a period start of FT8 and FT4.
const T0: u64 = 1_800_000_000_000;

struct Driven {
    utc: AtomicU64,
    mode: Mutex<Mode>,
}
struct TestClock(Arc<Driven>);
impl PeriodClock for TestClock {
    fn utc_ms(&self) -> u64 {
        self.0.utc.load(Ordering::SeqCst)
    }
    fn mode(&self) -> Mode {
        *self.0.mode.lock().unwrap()
    }
    fn recheck(&self) -> Option<Duration> {
        None
    }
}

/// What one client's peers wrote and read in the period, and their messages by the log's rule.
#[derive(Default)]
struct Tally {
    read: AtomicU64,
    written: AtomicU64,
    to_client: Mutex<Vec<(String, u64)>>,
    from_client: Mutex<Vec<(String, u64)>>,
}
struct Period {
    to_bytes: u64,
    from_bytes: u64,
    to_client: Vec<(String, u64)>,
    from_client: Vec<(String, u64)>,
}
impl Tally {
    /// A message the station sent and the peer read.
    fn station_sent(&self, kind: &str, bytes: usize) {
        self.to_client
            .lock()
            .unwrap()
            .push((kind.to_owned(), bytes as u64));
    }
    /// A message the peer wrote.
    fn peer_sent(&self, kind: &str, bytes: usize) {
        self.from_client
            .lock()
            .unwrap()
            .push((kind.to_owned(), bytes as u64));
    }
    fn take(&self) -> Period {
        Period {
            to_bytes: self.read.swap(0, Ordering::SeqCst),
            from_bytes: self.written.swap(0, Ordering::SeqCst),
            to_client: std::mem::take(&mut *self.to_client.lock().unwrap()),
            from_client: std::mem::take(&mut *self.from_client.lock().unwrap()),
        }
    }
    fn total(&self) -> u64 {
        self.read.load(Ordering::SeqCst) + self.written.load(Ordering::SeqCst)
    }
}

/// A peer's TCP stream, counting every byte it writes and reads.
struct Wire<T> {
    inner: T,
    tally: Arc<Tally>,
}
impl<T: AsyncRead + Unpin> AsyncRead for Wire<T> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        let before = buf.filled().len();
        let polled = Pin::new(&mut self.inner).poll_read(cx, buf);
        if let Poll::Ready(Ok(())) = &polled {
            let n = (buf.filled().len() - before) as u64;
            self.tally.read.fetch_add(n, Ordering::SeqCst);
        }
        polled
    }
}
impl<T: AsyncWrite + Unpin> AsyncWrite for Wire<T> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        let polled = Pin::new(&mut self.inner).poll_write(cx, buf);
        if let Poll::Ready(Ok(n)) = &polled {
            self.tally.written.fetch_add(*n as u64, Ordering::SeqCst);
        }
        polled
    }
    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.inner).poll_flush(cx)
    }
    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.inner).poll_shutdown(cx)
    }
}

/// WstxStationLink::LinkTrafficLog estimate with IndependentLinkAccounting, as the contract
/// states it: t = 29 on TLS, 0 on plaintext; each message of b bytes takes
/// w = b + t x ceil(b / 16384) wire bytes and ceil(w / 512) segments, the rest of the bytes
/// ceil(r / 512); estimate = bytes + 80 x S(this direction) + 80 x S(other direction).
fn estimate(
    bytes: u64,
    messages: &[(String, u64)],
    other_bytes: u64,
    other: &[(String, u64)],
    tls: bool,
) -> u64 {
    let t = if tls { 29 } else { 0 };
    let segments = |bytes: u64, messages: &[(String, u64)]| {
        let (mut wire, mut segments) = (0, 0);
        for (_, b) in messages {
            let w = b + t * b.div_ceil(16384);
            wire += w;
            segments += w.div_ceil(512);
        }
        segments + bytes.saturating_sub(wire).div_ceil(512)
    };
    bytes + 80 * segments(bytes, messages) + 80 * segments(other_bytes, other)
}

// The oracle above reproduces the contract's worked example (TLS, one FT8 period, one Thin
// browser): 1995 and 1065 bytes.
#[test]
fn estimate_oracle_reproduces_the_worked_example() {
    let mut to = vec![("ws station.tick".to_owned(), 228); 3];
    to.extend(vec![("ws heartbeat".to_owned(), 28); 3]);
    to.extend(vec![("ws ping".to_owned(), 2); 3]);
    let from = vec![("ws pong".to_owned(), 6); 3];
    assert_eq!(estimate(1035, &to, 105, &from, true), 1995);
    assert_eq!(estimate(105, &from, 1035, &to, true), 1065);
}

/// The line's directions equal the peers' own count of the period.
fn check(line: &Value, period: Period, tls: bool) {
    for (name, bytes, mine, other_bytes, other) in [
        (
            "to_client",
            period.to_bytes,
            &period.to_client,
            period.from_bytes,
            &period.from_client,
        ),
        (
            "from_client",
            period.from_bytes,
            &period.from_client,
            period.to_bytes,
            &period.to_client,
        ),
    ] {
        let direction = &line[name];
        assert_eq!(direction["bytes"], bytes, "{name} bytes of {line}");
        let mut types: BTreeMap<&str, (u64, u64)> = BTreeMap::new();
        for (kind, b) in mine.iter() {
            let entry = types.entry(kind).or_default();
            entry.0 += 1;
            entry.1 += b;
        }
        let typed: u64 = types.values().map(|(_, b)| b).sum();
        let expected: serde_json::Map<String, Value> = types
            .iter()
            .map(|(kind, (count, b))| ((*kind).to_owned(), json!([count, b])))
            .collect();
        assert_eq!(
            direction["types"],
            Value::Object(expected),
            "{name} types of {line}"
        );
        assert_eq!(
            direction["other"],
            bytes as i64 - typed as i64,
            "{name} other of {line}"
        );
        assert_eq!(
            direction["estimate"],
            estimate(bytes, mine, other_bytes, other, tls),
            "{name} estimate of {line}"
        );
    }
}
fn only<'a>(lines: &'a [Value], client: &str) -> &'a Value {
    let found: Vec<_> = lines.iter().filter(|l| l["client"] == client).collect();
    assert_eq!(found.len(), 1, "one line of {client} in {lines:?}");
    found[0]
}
fn period(line: &Value, utc: u64, length: u64, mode: &str, display: &[&str]) {
    assert_eq!(line["utc_ms"], utc, "{line}");
    assert_eq!(line["period_ms"], length, "{line}");
    assert_eq!(line["mode"], mode, "{line}");
    assert_eq!(line["display"], json!(display), "{line}");
}

/// The script's requests to the station side, which runs on the paused runtime.
enum Command {
    Advance(Duration, tokio::sync::oneshot::Sender<()>),
    End(u64, Mode, usize, tokio::sync::oneshot::Sender<Vec<Value>>),
}
struct Control(std::sync::mpsc::Sender<Command>);
impl Control {
    /// Moves the station's runtime clock.
    async fn advance(&self, by: Duration) {
        let (reply, done) = tokio::sync::oneshot::channel();
        self.0.send(Command::Advance(by, reply)).unwrap();
        done.await.unwrap();
    }
    /// Moves the period clock (and mode), and returns the `count` lines the writer wrote.
    async fn end(&self, utc: u64, mode: Mode, count: usize) -> Vec<Value> {
        let (reply, lines) = tokio::sync::oneshot::channel();
        self.0.send(Command::End(utc, mode, count, reply)).unwrap();
        let lines = lines.await.unwrap();
        assert_eq!(lines.len(), count, "lines at {utc}: {lines:?}");
        lines
    }
}
/// Waits until no peer has read or written for 400 ms.
async fn settle(tallies: &[&Arc<Tally>]) {
    let sum = || tallies.iter().map(|t| t.total()).sum::<u64>();
    let mut last = sum();
    loop {
        tokio::time::sleep(Duration::from_millis(400)).await;
        let now = sum();
        if now == last {
            return;
        }
        last = now;
    }
}

/// Runs `script` on its own runtime and serves its requests on the station's paused runtime.
async fn drive<F>(clock: Arc<Driven>, log: Arc<Log>, dir: std::path::PathBuf, script: F)
where
    F: FnOnce(Control) -> Pin<Box<dyn std::future::Future<Output = ()> + Send>> + Send + 'static,
{
    let (commands_tx, commands) = std::sync::mpsc::channel();
    let peers = std::thread::spawn(move || {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .unwrap()
            .block_on(script(Control(commands_tx)));
    });
    let commands = Arc::new(Mutex::new(commands));
    let mut returned: HashSet<String> = HashSet::new();
    loop {
        // Waiting in a blocking task keeps the paused clock from advancing by itself.
        let next = commands.clone();
        let command = tokio::task::spawn_blocking(move || next.lock().unwrap().recv())
            .await
            .unwrap();
        match command {
            Ok(Command::Advance(by, reply)) => {
                tokio::time::advance(by).await;
                let _ = reply.send(());
            }
            Ok(Command::End(utc, mode, count, reply)) => {
                clock.utc.store(utc, Ordering::SeqCst);
                *clock.mode.lock().unwrap() = mode;
                log.wake();
                let (path, seen) = (dir.join(FILE), returned.clone());
                let lines = tokio::task::spawn_blocking(move || {
                    let read = || {
                        std::fs::read_to_string(&path)
                            .unwrap_or_default()
                            .lines()
                            .filter(|l| l.starts_with('{') && !seen.contains(*l))
                            .map(str::to_owned)
                            .collect::<Vec<_>>()
                    };
                    let deadline = Instant::now() + Duration::from_secs(10);
                    while read().len() < count && Instant::now() < deadline {
                        std::thread::sleep(Duration::from_millis(20));
                    }
                    // A line beyond the expected ones is written in the same pass.
                    std::thread::sleep(Duration::from_millis(200));
                    read()
                })
                .await
                .unwrap();
                returned.extend(lines.iter().cloned());
                let _ = reply.send(
                    lines
                        .iter()
                        .map(|l| serde_json::from_str(l).unwrap())
                        .collect(),
                );
            }
            Err(_) => break,
        }
    }
    let outcome = tokio::task::spawn_blocking(move || peers.join())
        .await
        .unwrap();
    if let Err(panic) = outcome {
        std::panic::resume_unwind(panic);
    }
}

#[derive(Debug)]
struct AnyCertificate(Arc<rustls::crypto::CryptoProvider>);
impl rustls::client::danger::ServerCertVerifier for AnyCertificate {
    fn verify_server_cert(
        &self,
        _: &rustls::pki_types::CertificateDer<'_>,
        _: &[rustls::pki_types::CertificateDer<'_>],
        _: &rustls::pki_types::ServerName<'_>,
        _: &[u8],
        _: rustls::pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        Ok(rustls::client::danger::ServerCertVerified::assertion())
    }
    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &rustls::pki_types::CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }
    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &rustls::pki_types::CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }
    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        self.0.signature_verification_algorithms.supported_schemes()
    }
}
/// A TLS client trusting the disposable certificate, offering `protocol` by ALPN.
fn tls_client(protocol: &[u8]) -> Arc<rustls::ClientConfig> {
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let mut config = rustls::ClientConfig::builder_with_provider(provider.clone())
        .with_safe_default_protocol_versions()
        .unwrap()
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(AnyCertificate(provider)))
        .with_no_client_auth();
    config.alpn_protocols = vec![protocol.to_vec()];
    Arc::new(config)
}
/// A disposable localhost certificate (the existing node selfsigned fixture).
async fn certificate() -> axum_server::tls_rustls::RustlsConfig {
    let generated = std::process::Command::new("node")
        .args(["--eval","require('selfsigned').generate([{name:'commonName',value:'localhost'}],{days:1,keySize:2048,extensions:[{name:'subjectAltName',altNames:[{type:2,value:'localhost'}]}]}).then(c=>process.stdout.write(JSON.stringify({cert:c.cert,key:c.private})))"])
        .current_dir(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap())
        .output()
        .unwrap();
    assert!(
        generated.status.success(),
        "certificate fixture generator failed"
    );
    let cert: Value = serde_json::from_slice(&generated.stdout).unwrap();
    axum_server::tls_rustls::RustlsConfig::from_pem(
        cert["cert"].as_str().unwrap().as_bytes().to_vec(),
        cert["key"].as_str().unwrap().as_bytes().to_vec(),
    )
    .await
    .unwrap()
}

type Tls = tokio_rustls::client::TlsStream<Wire<tokio::net::TcpStream>>;
async fn tcp(address: SocketAddr, tally: &Arc<Tally>) -> Wire<tokio::net::TcpStream> {
    Wire {
        inner: tokio::net::TcpStream::connect(address).await.unwrap(),
        tally: tally.clone(),
    }
}
async fn tls(address: SocketAddr, config: &Arc<rustls::ClientConfig>, tally: &Arc<Tally>) -> Tls {
    tokio_rustls::TlsConnector::from(config.clone())
        .connect(
            rustls::pki_types::ServerName::try_from("localhost").unwrap(),
            tcp(address, tally).await,
        )
        .await
        .unwrap()
}

async fn fill<S: AsyncRead + Unpin>(io: &mut S, buffer: &mut Vec<u8>) {
    let mut chunk = [0u8; 16384];
    let n = io.read(&mut chunk).await.unwrap();
    assert!(n > 0, "the station closed the connection");
    buffer.extend_from_slice(&chunk[..n]);
}
struct Reply {
    status: u16,
    body: Vec<u8>,
    rest: Vec<u8>,
}
/// A request head: request line, Host and the given fields (and a Content-Length of a body).
fn head(method: &str, path: &str, fields: &[(&str, &str)], body: &[u8]) -> String {
    let mut text = format!("{method} {path} HTTP/1.1\r\nHost: localhost\r\n");
    for (name, value) in fields {
        text.push_str(&format!("{name}: {value}\r\n"));
    }
    if !body.is_empty() {
        text.push_str(&format!("Content-Length: {}\r\n", body.len()));
    }
    text + "\r\n"
}
/// One HTTP/1.1 exchange written and read by hand. The tally gets the request as written and
/// the response as received without what the HTTP server adds itself (date, content-length,
/// transfer-encoding and the chunk framing).
async fn exchange<S: AsyncRead + AsyncWrite + Unpin>(
    io: &mut S,
    tally: &Tally,
    kind: &str,
    head: String,
    body: &[u8],
) -> Reply {
    let request = [head.as_bytes(), body].concat();
    io.write_all(&request).await.unwrap();
    io.flush().await.unwrap();
    tally.peer_sent(kind, request.len());
    let mut buffer = Vec::new();
    let end = loop {
        if let Some(end) = buffer.windows(4).position(|w| w == b"\r\n\r\n") {
            break end;
        }
        fill(io, &mut buffer).await;
    };
    let text = String::from_utf8(buffer[..end].to_vec()).unwrap();
    let mut rest = buffer[end + 4..].to_vec();
    let mut lines = text.split("\r\n");
    let status_line = lines.next().unwrap();
    let status: u16 = status_line[9..12].parse().unwrap();
    let fields: Vec<(String, String)> = lines
        .map(|l| {
            let (name, value) = l.split_once(": ").unwrap();
            (name.to_ascii_lowercase(), value.to_owned())
        })
        .collect();
    let field = |name: &str| {
        fields
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, v)| v.clone())
    };
    let body = if let Some(length) = field("content-length") {
        let length: usize = length.parse().unwrap();
        while rest.len() < length {
            fill(io, &mut rest).await;
        }
        rest.drain(..length).collect()
    } else if field("transfer-encoding").is_some_and(|v| v == "chunked") {
        let mut body = Vec::new();
        loop {
            let line = loop {
                if let Some(at) = rest.windows(2).position(|w| w == b"\r\n") {
                    break at;
                }
                fill(io, &mut rest).await;
            };
            let size = usize::from_str_radix(
                std::str::from_utf8(&rest[..line])
                    .unwrap()
                    .split(';')
                    .next()
                    .unwrap(),
                16,
            )
            .unwrap();
            while rest.len() < line + 2 + size + 2 {
                fill(io, &mut rest).await;
            }
            body.extend_from_slice(&rest[line + 2..line + 2 + size]);
            rest.drain(..line + 2 + size + 2);
            if size == 0 {
                break body;
            }
        }
    } else {
        Vec::new()
    };
    // The router adds the Allow field of a 405 itself, after its outermost layer, as the HTTP
    // server adds the others.
    let added = |n: &str| {
        ["date", "content-length", "transfer-encoding"].contains(&n)
            || (status == 405 && n == "allow")
    };
    let kept: usize = fields
        .iter()
        .filter(|(n, _)| !added(n))
        .map(|(n, v)| n.len() + 2 + v.len() + 2)
        .sum();
    tally.station_sent(kind, status_line.len() + 2 + kept + 2 + body.len());
    Reply { status, body, rest }
}

/// A WebSocket peer. Its reader tallies every frame the station sends, answers each Ping with a
/// Pong and keeps every text message.
struct Ws<S> {
    writer: Arc<tokio::sync::Mutex<WriteHalf<S>>>,
    texts: tokio::sync::mpsc::UnboundedReceiver<Value>,
    seen: Arc<Mutex<Vec<String>>>,
    tally: Arc<Tally>,
}
impl<S: AsyncRead + AsyncWrite + Unpin + Send + 'static> Ws<S> {
    async fn open(mut io: S, tally: &Arc<Tally>, origin: &str, extra: &str) -> Self {
        let reply = exchange(
            &mut io,
            tally,
            "GET /ws",
            upgrade_request(origin, extra).replace("Host: 127.0.0.1", "Host: localhost"),
            b"",
        )
        .await;
        assert_eq!(reply.status, 101);
        let (mut reader, writer) = tokio::io::split(io);
        let writer = Arc::new(tokio::sync::Mutex::new(writer));
        let (texts_tx, texts) = tokio::sync::mpsc::unbounded_channel();
        let seen = Arc::new(Mutex::new(Vec::new()));
        let (pong, tallied, kept) = (writer.clone(), tally.clone(), seen.clone());
        let mut buffer = reply.rest;
        tokio::spawn(async move {
            loop {
                while let Some((opcode, payload, length)) = parse_frame(&buffer) {
                    buffer.drain(..length);
                    match opcode {
                        1 => {
                            let text = String::from_utf8(payload).unwrap();
                            let value: Value = serde_json::from_str(&text).unwrap();
                            tallied.station_sent(
                                &format!("ws {}", value["type"].as_str().unwrap()),
                                length,
                            );
                            kept.lock().unwrap().push(text);
                            let _ = texts_tx.send(value);
                        }
                        9 => {
                            tallied.station_sent("ws ping", length);
                            let frame = client_frame(10, &payload);
                            let mut w = pong.lock().await;
                            w.write_all(&frame).await.unwrap();
                            w.flush().await.unwrap();
                            tallied.peer_sent("ws pong", frame.len());
                        }
                        8 => tallied.station_sent("ws close", length),
                        _ => panic!("unexpected opcode {opcode}"),
                    }
                }
                let mut chunk = [0u8; 16384];
                match reader.read(&mut chunk).await {
                    Ok(n) if n > 0 => buffer.extend_from_slice(&chunk[..n]),
                    _ => return,
                }
            }
        });
        Ws {
            writer,
            texts,
            seen,
            tally: tally.clone(),
        }
    }
    async fn send(&self, value: Value) {
        let frame = client_frame(1, value.to_string().as_bytes());
        let mut w = self.writer.lock().await;
        w.write_all(&frame).await.unwrap();
        w.flush().await.unwrap();
        self.tally.peer_sent(
            &format!("ws {}", value["type"].as_str().unwrap()),
            frame.len(),
        );
    }
    /// The reply to the command `id`.
    async fn call(&mut self, kind: &str, id: u64) -> Value {
        self.send(json!({"v":1,"type":kind,"id":id})).await;
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                let message = self.texts.recv().await.unwrap();
                if message["id"] == id {
                    return message;
                }
            }
        })
        .await
        .expect("reply")
    }
    async fn wait(&mut self, kind: &str) {
        tokio::time::timeout(Duration::from_secs(10), async {
            while self.texts.recv().await.unwrap()["type"] != kind {}
        })
        .await
        .unwrap_or_else(|_| panic!("no {kind}"));
    }
}

/// GET over HTTP/2 on its own TLS connection; the tally gets the exchange by the same rule,
/// re-serialized as HTTP/1.1 text. The connection is returned so that it stays open.
async fn http2_get(
    address: SocketAddr,
    tally: &Arc<Tally>,
    path: &str,
    fields: &[(&str, &str)],
) -> (u16, h2::client::SendRequest<Bytes>) {
    let io = tls(address, &tls_client(b"h2"), tally).await;
    assert_eq!(io.get_ref().1.alpn_protocol(), Some(&b"h2"[..]));
    let (client, connection) = h2::client::handshake(io).await.unwrap();
    tokio::spawn(connection);
    let mut client = client.ready().await.unwrap();
    let mut request = axum::http::Request::builder()
        .method("GET")
        .uri(format!("https://localhost{path}"));
    let mut text = format!("GET {path} HTTP/1.1\r\n").len();
    for (name, value) in fields {
        request = request.header(*name, *value);
        text += name.len() + 2 + value.len() + 2;
    }
    let (response, _) = client
        .send_request(request.body(()).unwrap(), true)
        .unwrap();
    tally.peer_sent(&format!("GET {path}"), text + 2);
    let response = response.await.unwrap();
    let (parts, mut body) = response.into_parts();
    let mut data = 0;
    while let Some(chunk) = body.data().await {
        let chunk = chunk.unwrap();
        data += chunk.len();
        body.flow_control().release_capacity(chunk.len()).unwrap();
    }
    let status = parts.status;
    let kept: usize = parts
        .headers
        .iter()
        .filter(|(n, _)| !["date", "content-length"].contains(&n.as_str()))
        .map(|(n, v)| n.as_str().len() + 2 + v.len() + 2)
        .sum();
    let line = format!(
        "HTTP/1.1 {} {}\r\n",
        status.as_str(),
        status.canonical_reason().unwrap_or("")
    );
    tally.station_sent(&format!("GET {path}"), line.len() + kept + 2 + data);
    (status.as_u16(), client)
}

// Proves: CL-003-05; TC-080-001 cases (a)-(h). One JSON line per client with traffic at each
// period end with the bytes its peers wrote and read, the types by the log's rule, other and the
// estimate; refused requests on their connection's client; MCP on its own line; a connection
// without credentials local, also on TLS; display per socket; FT4, mode change and no-mode
// periods; HTTP/2 by the same rule; rotation; no secret in a line and nothing of the log on a
// socket or response.
#[tokio::test(start_paused = true)]
async fn link_byte_log_counts_each_client_per_period() {
    rustls::crypto::ring::default_provider()
        .install_default()
        .ok();
    let f = crate::mcp_tests::station(false).await;
    let (mcp_id, mcp_token) = f.new_mcp_client("traffic agent").await;
    let config = certificate().await;
    let clock = Arc::new(Driven {
        utc: AtomicU64::new(T0),
        mode: Mutex::new(Mode::Ft8),
    });
    let log = Log::new(Box::new(TestClock(clock.clone())));
    crate::link_log::spawn_writer(log.clone(), f.state.clone());
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let address = listener.local_addr().unwrap();
    let server = crate::link_log::Server::new(listener, Some(config), Some(log.clone())).unwrap();
    let service = tokio::spawn(server.serve(router(f.app.clone())));

    let origin = f.app.origin.clone();
    let cookie = f.cookie();
    let browser_client = format!("browser:{}", f.gid);
    let secrets = [f.token.clone(), mcp_token.clone(), f.mcp.clone()];
    let dir = f.dir.clone();
    drive(clock, log, f.dir.clone(), move |control| {
        Box::pin(async move {
            let h1 = tls_client(b"http/1.1");
            let (browser, mcp, local) = (
                Arc::new(Tally::default()),
                Arc::new(Tally::default()),
                Arc::new(Tally::default()),
            );
            let all = [&browser, &mcp, &local];
            let credentials = [("Origin", origin.as_str()), ("Cookie", cookie.as_str())];
            let with_cookie = format!("Cookie: {cookie}\r\n");

            // (a) FT8: the browser's credentialed connection, its Thin socket, one MCP call.
            let mut h = tls(address, &h1, &browser).await;
            let r = exchange(&mut h, &browser, "GET /profile", head("GET", "/profile", &credentials, b""), b"").await;
            assert_eq!(r.status, 200);
            assert!(!String::from_utf8_lossy(&r.body).contains("to_client"));
            let body = br#"{"version":1}"#;
            let fields = [credentials[0], credentials[1], ("Content-Type", "application/json")];
            exchange(&mut h, &browser, "POST /authorization/v1/status", head("POST", "/authorization/v1/status", &fields, body), body).await;
            let r = exchange(&mut h, &browser, "POST /receive/select", head("POST", "/receive/select", &fields, b"{"), b"{").await;
            assert_eq!(r.status, 400, "the malformed selection is refused");
            let mut w1 = Ws::open(tls(address, &h1, &browser).await, &browser, &origin, &with_cookie).await;
            assert_eq!(w1.call("spectrum.thin", 1).await["data"]["profile"], "thin");
            for id in 2..=4 {
                assert_eq!(w1.call("station.get", id).await["type"], "station.status");
            }
            let mut m = tls(address, &h1, &mcp).await;
            let call = json!({"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"wstx_read",
                "arguments":{"view":"receive"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",
                "io.modelcontextprotocol/clientInfo":{"name":"wstx-test-client","version":"1"},
                "io.modelcontextprotocol/clientCapabilities":{}}}})
            .to_string();
            let bearer = format!("Bearer {mcp_token}");
            let fields = [("Content-Type", "application/json"), ("Accept", "application/json, text/event-stream"),
                ("Authorization", bearer.as_str()), ("Mcp-Protocol-Version", "2026-07-28"),
                ("Mcp-Method", "tools/call"), ("Mcp-Name", "wstx_read")];
            let r = exchange(&mut m, &mcp, "POST /mcp", head("POST", "/mcp", &fields, call.as_bytes()), call.as_bytes()).await;
            assert_eq!(r.status, 200, "{}", String::from_utf8_lossy(&r.body));
            // A heartbeat and its Ping in the period; the browser answers with a Pong.
            control.advance(Duration::from_secs(5)).await;
            w1.wait("heartbeat").await;
            settle(&all).await;
            let lines = control.end(T0 + 15000, Mode::Ft8, 2).await;
            let line = only(&lines, &browser_client);
            period(line, T0, 15000, "FT8", &["thin"]);
            assert_eq!(line["from_client"]["types"]["POST /receive/select"][0], 1);
            assert!(line["to_client"]["types"]["ws ping"][0].as_u64() >= Some(1));
            assert!(line["from_client"]["types"]["ws pong"][0].as_u64() >= Some(1));
            assert!(line["to_client"]["types"].get("POST /mcp").is_none());
            check(line, browser.take(), true);
            let line = only(&lines, &format!("mcp:{mcp_id}"));
            period(line, T0, 15000, "FT8", &[]);
            assert_eq!(line["from_client"]["types"]["POST /mcp"][0], 1);
            check(line, mcp.take(), true);

            // (b) A second socket of the grant on Off; the MCP client is silent: no line.
            let mut w2 = Ws::open(tls(address, &h1, &browser).await, &browser, &origin, &with_cookie).await;
            assert_eq!(w2.call("spectrum.off", 1).await["data"]["profile"], "off");
            settle(&all).await;
            let lines = control.end(T0 + 30000, Mode::Ft4, 1).await;
            let line = only(&lines, &browser_client);
            period(line, T0 + 15000, 15000, "FT8", &["thin", "off"]);
            check(line, browser.take(), true);

            // (c) Two FT4 periods; (d) back to FT8 at a period start, FT4 at 5.2 s into it.
            let mut id = 10;
            for (end, mode, start, length, name) in [
                (T0 + 37500, Mode::Ft4, T0 + 30000, 7500, "FT4"),
                (T0 + 45000, Mode::Ft8, T0 + 37500, 7500, "FT4"),
                (T0 + 50200, Mode::Ft4, T0 + 45000, 5200, "FT8"),
                (T0 + 52500, Mode::Ft4, T0 + 50200, 2300, "FT4"),
                (T0 + 60000, Mode::Unselected, T0 + 52500, 7500, "FT4"),
            ] {
                id += 1;
                assert_eq!(w1.call("station.get", id).await["type"], "station.status");
                settle(&all).await;
                let lines = control.end(end, mode, 1).await;
                let line = only(&lines, &browser_client);
                period(line, start, length, name, &["thin", "off"]);
                check(line, browser.take(), true);
            }

            // (e) No mode: 15 s periods "none"; (f) a TLS connection without credentials is local.
            assert_eq!(w1.call("station.get", 20).await["type"], "station.status");
            let mut l = tls(address, &h1, &local).await;
            let r = exchange(&mut l, &local, "GET /", head("GET", "/", &[], b""), b"").await;
            assert_eq!(r.status, 200);
            let r = exchange(&mut l, &local, "GET /profile", head("GET", "/profile", &[], b""), b"").await;
            assert_eq!(r.status, 401);
            settle(&all).await;
            let lines = control.end(T0 + 75000, Mode::Unselected, 2).await;
            let line = only(&lines, &browser_client);
            period(line, T0 + 60000, 15000, "none", &["thin", "off"]);
            check(line, browser.take(), true);
            let line = only(&lines, "local");
            period(line, T0 + 60000, 15000, "none", &[]);
            check(line, local.take(), true);

            // (g) The browser's GET /profile over HTTP/2.
            let h2_fields = [("origin", origin.as_str()), ("cookie", cookie.as_str())];
            let (status, h2) = http2_get(address, &browser, "/profile", &h2_fields).await;
            assert_eq!(status, 200);
            settle(&all).await;
            let lines = control.end(T0 + 90000, Mode::Unselected, 1).await;
            let line = only(&lines, &browser_client);
            period(line, T0 + 75000, 15000, "none", &["thin", "off"]);
            check(line, browser.take(), true);

            // (h) Past the rotation size the file moves to link-traffic.1.log, replacing it.
            std::fs::write(dir.join("link-traffic.1.log"), "older\n").unwrap();
            let filler = format!("{}\n", "x".repeat(4_194_304));
            std::fs::OpenOptions::new()
                .append(true)
                .open(dir.join(FILE))
                .unwrap()
                .write_all(filler.as_bytes())
                .unwrap();
            assert_eq!(w1.call("station.get", 21).await["type"], "station.status");
            settle(&all).await;
            let lines = control.end(T0 + 105000, Mode::Unselected, 1).await;
            check(only(&lines, &browser_client), browser.take(), true);
            let older = std::fs::read_to_string(dir.join("link-traffic.1.log")).unwrap();
            assert!(!older.starts_with("older"), "the older file is replaced");
            assert!(
                older
                    .lines()
                    .filter_map(|l| serde_json::from_str::<Value>(l).ok())
                    .any(|l| l["utc_ms"] == T0),
                "the earlier lines moved along"
            );
            let current = std::fs::read_to_string(dir.join(FILE)).unwrap();
            assert_eq!(current.lines().count(), 1, "the new file holds the new line");

            // No line holds a cookie, token or proof; nothing of the log reaches a socket.
            for text in [older, current] {
                for secret in &secrets {
                    assert!(!text.contains(secret.as_str()), "a secret in the log");
                }
            }
            for ws in [&w1, &w2] {
                assert!(ws.seen.lock().unwrap().iter().all(|t| !t.contains("to_client") && !t.contains("link-traffic")));
            }
            drop((h, m, l, h2, w1, w2));
        })
    })
    .await;
    service.abort();
}

// Proves: CL-003-05; TC-080-001 case (i). On a plaintext loopback profile t is 0 and the client
// is local.
#[tokio::test(start_paused = true)]
async fn link_byte_log_on_a_plaintext_profile() {
    let (app, dir) = plaintext_station("link-log");
    let state = app.profile.clone().unwrap();
    let clock = Arc::new(Driven {
        utc: AtomicU64::new(T0),
        mode: Mutex::new(Mode::Ft8),
    });
    let log = Log::new(Box::new(TestClock(clock.clone())));
    crate::link_log::spawn_writer(log.clone(), state);
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let address = listener.local_addr().unwrap();
    let server = crate::link_log::Server::new(listener, None, Some(log.clone())).unwrap();
    let service = tokio::spawn(server.serve(router(app.clone())));
    let origin = app.origin.clone();
    drive(clock, log, dir.clone(), move |control| {
        Box::pin(async move {
            let local = Arc::new(Tally::default());
            let mut ws = Ws::open(tcp(address, &local).await, &local, &origin, "").await;
            assert_eq!(ws.call("spectrum.thin", 1).await["data"]["profile"], "thin");
            assert_eq!(ws.call("station.get", 2).await["type"], "station.status");
            let mut h = tcp(address, &local).await;
            let r = exchange(
                &mut h,
                &local,
                "GET /profile",
                head("GET", "/profile", &[], b""),
                b"",
            )
            .await;
            assert_eq!(r.status, 200);
            settle(&[&local]).await;
            let lines = control.end(T0 + 15000, Mode::Ft8, 1).await;
            let line = only(&lines, "local");
            period(line, T0, 15000, "FT8", &["thin"]);
            check(line, local.take(), false);
            drop((ws, h));
        })
    })
    .await;
    service.abort();
    let _ = std::fs::remove_dir_all(dir);
}

// Proves: CL-003-05; TC-080-001 (review finding on #80): the set of types is bounded. A request
// method outside the standard ones (FOO1, FOO2) on a route and on an unknown path is typed
// "OTHER /" and "OTHER unrouted"; no client text reaches a key.
#[tokio::test(start_paused = true)]
async fn link_byte_log_bounds_the_request_methods() {
    let (app, dir) = plaintext_station("link-methods");
    let state = app.profile.clone().unwrap();
    let clock = Arc::new(Driven {
        utc: AtomicU64::new(T0),
        mode: Mutex::new(Mode::Ft8),
    });
    let log = Log::new(Box::new(TestClock(clock.clone())));
    crate::link_log::spawn_writer(log.clone(), state);
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let address = listener.local_addr().unwrap();
    let server = crate::link_log::Server::new(listener, None, Some(log.clone())).unwrap();
    let service = tokio::spawn(server.serve(router(app)));
    drive(clock, log, dir.clone(), move |control| {
        Box::pin(async move {
            let local = Arc::new(Tally::default());
            let mut h = tcp(address, &local).await;
            for (method, path, kind) in [
                ("FOO1", "/", "OTHER /"),
                ("FOO2", "/", "OTHER /"),
                ("FOO1", "/nowhere", "OTHER unrouted"),
                ("FOO2", "/nowhere/else", "OTHER unrouted"),
            ] {
                let r = exchange(&mut h, &local, kind, head(method, path, &[], b""), b"").await;
                assert!(r.status >= 400, "{method} {path}: {}", r.status);
            }
            settle(&[&local]).await;
            let lines = control.end(T0 + 15000, Mode::Ft8, 1).await;
            let line = only(&lines, "local");
            let keys: Vec<&String> = ["to_client", "from_client"]
                .iter()
                .flat_map(|d| line[*d]["types"].as_object().unwrap().keys())
                .collect();
            assert!(
                keys.iter()
                    .all(|k| !k.contains("FOO") && !k.contains("nowhere")),
                "client text in a type: {keys:?}"
            );
            assert_eq!(line["from_client"]["types"]["OTHER /"][0], 2, "{line}");
            assert_eq!(
                line["from_client"]["types"]["OTHER unrouted"][0], 2,
                "{line}"
            );
            check(line, local.take(), false);
            drop(h);
        })
    })
    .await;
    service.abort();
    let _ = std::fs::remove_dir_all(dir);
}
