//! WstxStationProtocol::LinkTrafficLog (#80, CL-003-05): the bytes between each client and the
//! station, per period, in `link-traffic.log` of the profile directory.
//!
//! Counting only adds to counters: each accepted TCP stream is wrapped below TLS (`Counted`),
//! the outermost router layer (`http`) tallies each HTTP exchange as HTTP/1.1 text, and the
//! WebSocket loop tallies each frame (`Socket`). At each period end the writer task takes the
//! counters, groups them by the client each connection belongs to then, and appends one line
//! per client with traffic; only that task takes the profile store's lock.
use axum::{
    Router,
    body::{Body, Bytes, HttpBody},
    extract::{ConnectInfo, MatchedPath, Request, ws::Message},
    middleware::Next,
    response::Response,
};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    io,
    net::SocketAddr,
    pin::Pin,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    task::{Context, Poll},
    time::Duration,
};
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};

pub(crate) const FILE: &str = "link-traffic.log";
pub(crate) const ROTATE_BYTES: u64 = 4_194_304;
const TLS_RECORD_OVERHEAD_BYTES: u64 = 29;
const TLS_RECORD_PAYLOAD_MAX: u64 = 16_384;
// WstxStationProtocol::IndependentLinkAccounting.
const SEGMENT_BYTES_MAX: u64 = 512;
const HEADER_BYTES_PER_SEGMENT: u64 = 80;
const REVERSE_ACK_BYTES_PER_SEGMENT: u64 = 80;
/// The commands a client sends on its socket; anything else is "ws other", so that a client
/// cannot grow the set of types.
const COMMANDS: [&str; 5] = [
    "station.get",
    "recording.get",
    "spectrum.thin",
    "spectrum.detail",
    "spectrum.off",
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Mode {
    Ft8,
    Ft4,
    Unselected,
}
impl Mode {
    pub(crate) fn of(operating: &str) -> Mode {
        match operating {
            "ft8" => Mode::Ft8,
            "ft4" => Mode::Ft4,
            _ => Mode::Unselected,
        }
    }
    fn period_ms(self) -> u64 {
        if self == Mode::Ft4 { 7500 } else { 15000 }
    }
    fn name(self) -> &'static str {
        match self {
            Mode::Ft8 => "FT8",
            Mode::Ft4 => "FT4",
            Mode::Unselected => "none",
        }
    }
}

/// The log's period clock: UTC and the selected operating mode.
pub(crate) trait PeriodClock: Send + Sync {
    fn utc_ms(&self) -> u64;
    fn mode(&self) -> Mode;
    /// The longest the writer waits before it looks at the clock again; None: only when woken.
    fn recheck(&self) -> Option<Duration>;
}
/// The station's: the system clock's UTC and the operating selection's mode, looked at every
/// 100 ms, so a mode change ends its period within 100 ms of the change.
pub(crate) struct StationClock(pub(crate) Arc<crate::recording::Recording>);
impl PeriodClock for StationClock {
    fn utc_ms(&self) -> u64 {
        crate::authorization_http::utc_ms()
    }
    fn mode(&self) -> Mode {
        Mode::of(self.0.operating_mode())
    }
    fn recheck(&self) -> Option<Duration> {
        Some(Duration::from_millis(100))
    }
}

#[derive(Clone, Copy)]
pub(crate) enum Way {
    ToClient,
    FromClient,
}

/// The messages of one direction: per type [count, bytes], and the estimate's wire bytes and
/// segments of each message.
#[derive(Default)]
struct Messages {
    types: BTreeMap<String, (u64, u64)>,
    wire: u64,
    segments: u64,
}
impl Messages {
    fn add(&mut self, kind: &str, bytes: u64, tls: bool) {
        let entry = self.types.entry(kind.to_owned()).or_default();
        entry.0 = entry.0.saturating_add(1);
        entry.1 = entry.1.saturating_add(bytes);
        let records = if tls {
            bytes.div_ceil(TLS_RECORD_PAYLOAD_MAX)
        } else {
            0
        };
        let wire = bytes.saturating_add(TLS_RECORD_OVERHEAD_BYTES.saturating_mul(records));
        self.wire = self.wire.saturating_add(wire);
        self.segments = self
            .segments
            .saturating_add(wire.div_ceil(SEGMENT_BYTES_MAX));
    }
    fn merge(&mut self, other: Messages) {
        for (kind, (count, bytes)) in other.types {
            let entry = self.types.entry(kind).or_default();
            entry.0 = entry.0.saturating_add(count);
            entry.1 = entry.1.saturating_add(bytes);
        }
        self.wire = self.wire.saturating_add(other.wire);
        self.segments = self.segments.saturating_add(other.segments);
    }
    /// S: the messages' segments and those of the rest of the direction's bytes.
    fn segments(&self, bytes: u64) -> u64 {
        self.segments
            .saturating_add(bytes.saturating_sub(self.wire).div_ceil(SEGMENT_BYTES_MAX))
    }
}
/// estimate = bytes + headerBytesPerSegment x S(this) + reverseAckBytesPerSegment x S(other).
pub(crate) fn estimate(bytes: u64, segments: u64, other_segments: u64) -> u64 {
    bytes
        .saturating_add(HEADER_BYTES_PER_SEGMENT.saturating_mul(segments))
        .saturating_add(REVERSE_ACK_BYTES_PER_SEGMENT.saturating_mul(other_segments))
}

struct Usage {
    client: String,
    sockets: BTreeMap<u64, &'static str>,
    to_client: Messages,
    from_client: Messages,
}
/// One accepted TCP connection: its bytes below TLS, its messages and its client.
pub(crate) struct Connection {
    tls: bool,
    read: AtomicU64,
    written: AtomicU64,
    closed: AtomicBool,
    usage: Mutex<Usage>,
}
impl Connection {
    /// The client of a request the station accepted with credentials; the connection belongs
    /// to it until another one is accepted.
    pub(crate) fn credential(&self, client: String) {
        if let Ok(mut usage) = self.usage.lock() {
            usage.client = client;
        }
    }
    pub(crate) fn message(&self, way: Way, kind: &str, bytes: u64) {
        if let Ok(mut usage) = self.usage.lock() {
            match way {
                Way::ToClient => usage.to_client.add(kind, bytes, self.tls),
                Way::FromClient => usage.from_client.add(kind, bytes, self.tls),
            }
        }
    }
    fn socket(&self, id: u64, profile: Option<&'static str>) {
        if let Ok(mut usage) = self.usage.lock() {
            match profile {
                Some(profile) => usage.sockets.insert(id, profile),
                None => usage.sockets.remove(&id),
            };
        }
    }
}

#[derive(Default)]
struct ClientPeriod {
    read: u64,
    written: u64,
    sockets: Vec<(u64, &'static str)>,
    to_client: Messages,
    from_client: Messages,
}

pub(crate) struct Log {
    clock: Box<dyn PeriodClock>,
    wake: tokio::sync::Notify,
    connections: Mutex<Vec<Arc<Connection>>>,
    /// The open period: its start and mode.
    open: Mutex<(u64, Mode)>,
}
impl Log {
    pub(crate) fn new(clock: Box<dyn PeriodClock>) -> Arc<Log> {
        let (now, mode) = (clock.utc_ms(), clock.mode());
        Arc::new(Log {
            clock,
            wake: tokio::sync::Notify::new(),
            connections: Mutex::new(Vec::new()),
            open: Mutex::new((now - now % mode.period_ms(), mode)),
        })
    }
    pub(crate) fn accept(&self, tls: bool) -> Arc<Connection> {
        let connection = Arc::new(Connection {
            tls,
            read: AtomicU64::new(0),
            written: AtomicU64::new(0),
            closed: AtomicBool::new(false),
            usage: Mutex::new(Usage {
                client: "local".into(),
                sockets: BTreeMap::new(),
                to_client: Messages::default(),
                from_client: Messages::default(),
            }),
        });
        if let Ok(mut connections) = self.connections.lock() {
            connections.push(connection.clone());
        }
        connection
    }
    /// Makes the writer look at the period clock now (a test's driven clock never wakes it).
    #[cfg(test)]
    pub(crate) fn wake(&self) {
        self.wake.notify_one();
    }
    /// The lines of every period that ended by the clock's time; a mode change ends the open
    /// period at that time and starts one that runs to the next period start of the new mode.
    fn advance(&self) -> Vec<String> {
        let (now, mode) = (self.clock.utc_ms(), self.clock.mode());
        let Ok(mut open) = self.open.lock() else {
            return Vec::new();
        };
        let mut lines = Vec::new();
        loop {
            let (start, current) = *open;
            let length = current.period_ms();
            let end = start - start % length + length;
            if now < end {
                break;
            }
            lines.extend(self.close(start, end - start, current));
            // Periods without any traffic in between give no line.
            *open = (end.max(now - now % length), current);
        }
        let (start, current) = *open;
        if mode != current && now >= start {
            if now > start {
                lines.extend(self.close(start, now - start, current));
            }
            *open = (now, mode);
        }
        lines
    }
    fn close(&self, start: u64, length: u64, mode: Mode) -> Vec<String> {
        let mut clients: BTreeMap<String, ClientPeriod> = BTreeMap::new();
        if let Ok(mut connections) = self.connections.lock() {
            connections.retain(|connection| {
                let closed = connection.closed.load(Ordering::Acquire);
                let read = connection.read.swap(0, Ordering::AcqRel);
                let written = connection.written.swap(0, Ordering::AcqRel);
                if let Ok(mut usage) = connection.usage.lock() {
                    let client = clients.entry(usage.client.clone()).or_default();
                    client.read = client.read.saturating_add(read);
                    client.written = client.written.saturating_add(written);
                    client
                        .sockets
                        .extend(usage.sockets.iter().map(|(id, p)| (*id, *p)));
                    client.to_client.merge(std::mem::take(&mut usage.to_client));
                    client
                        .from_client
                        .merge(std::mem::take(&mut usage.from_client));
                }
                !closed
            });
        }
        clients
            .into_iter()
            .filter(|(_, c)| {
                c.read > 0
                    || c.written > 0
                    || !c.to_client.types.is_empty()
                    || !c.from_client.types.is_empty()
            })
            .map(|(client, mut c)| {
                c.sockets.sort_unstable();
                let to = c.to_client.segments(c.written);
                let from = c.from_client.segments(c.read);
                let direction = |bytes: u64, messages: &Messages, mine: u64, other: u64| {
                    let typed: u64 = messages.types.values().map(|(_, b)| *b).sum();
                    let types: serde_json::Map<String, Value> = messages
                        .types
                        .iter()
                        .map(|(kind, (count, bytes))| (kind.clone(), json!([count, bytes])))
                        .collect();
                    json!({"bytes":bytes,"other":i128::from(bytes)-i128::from(typed),
                        "estimate":estimate(bytes,mine,other),"types":types})
                };
                json!({"utc_ms":start,"period_ms":length,"mode":mode.name(),"client":client,
                    "display":c.sockets.iter().map(|(_, p)| *p).collect::<Vec<_>>(),
                    "to_client":direction(c.written,&c.to_client,to,from),
                    "from_client":direction(c.read,&c.from_client,from,to)})
                .to_string()
            })
            .collect()
    }
}

/// The writer task: at each period end it appends the lines to the profile's log file.
pub(crate) fn spawn_writer(log: Arc<Log>, state: Arc<crate::ProfileState>) {
    tokio::spawn(async move {
        loop {
            match log.clock.recheck() {
                Some(wait) => {
                    let _ = tokio::time::timeout(wait, log.wake.notified()).await;
                }
                None => log.wake.notified().await,
            }
            let lines = log.advance();
            if lines.is_empty() {
                continue;
            }
            let state = state.clone();
            let _ = tokio::task::spawn_blocking(move || {
                let Ok(mut store) = state.store.lock() else {
                    return;
                };
                for line in lines {
                    if store.append_log_line(FILE, &line, ROTATE_BYTES).is_err() {
                        return;
                    }
                }
            })
            .await;
        }
    });
}

/// An accepted TCP stream whose payload bytes are counted for its connection.
pub(crate) struct Counted<T> {
    inner: T,
    link: Option<Arc<Connection>>,
}
impl<T: AsyncRead + Unpin> AsyncRead for Counted<T> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let before = buf.filled().len();
        let polled = Pin::new(&mut self.inner).poll_read(cx, buf);
        if let (Poll::Ready(Ok(())), Some(link)) = (&polled, &self.link) {
            let n = buf.filled().len().saturating_sub(before);
            link.read.fetch_add(n as u64, Ordering::AcqRel);
        }
        polled
    }
}
impl<T: AsyncWrite + Unpin> AsyncWrite for Counted<T> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        let polled = Pin::new(&mut self.inner).poll_write(cx, buf);
        if let (Poll::Ready(Ok(n)), Some(link)) = (&polled, &self.link) {
            link.written.fetch_add(*n as u64, Ordering::AcqRel);
        }
        polled
    }
    fn poll_write_vectored(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        bufs: &[io::IoSlice<'_>],
    ) -> Poll<io::Result<usize>> {
        let polled = Pin::new(&mut self.inner).poll_write_vectored(cx, bufs);
        if let (Poll::Ready(Ok(n)), Some(link)) = (&polled, &self.link) {
            link.written.fetch_add(*n as u64, Ordering::AcqRel);
        }
        polled
    }
    fn is_write_vectored(&self) -> bool {
        self.inner.is_write_vectored()
    }
    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.inner).poll_flush(cx)
    }
    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.inner).poll_shutdown(cx)
    }
}
impl<T> Drop for Counted<T> {
    fn drop(&mut self) {
        if let Some(link) = &self.link {
            link.closed.store(true, Ordering::Release);
        }
    }
}

/// The connection a request arrived on (a request extension, as ConnectInfo); none without a
/// log, and none on the station's own in-process dispatch.
#[derive(Clone)]
pub(crate) struct Link(pub(crate) Option<Arc<Connection>>);
impl Link {
    pub(crate) fn of(request: &Request) -> Option<Arc<Connection>> {
        request
            .extensions()
            .get::<ConnectInfo<Link>>()
            .and_then(|info| info.0.0.clone())
    }
}
/// A response extension: the request was accepted with this client's credentials.
#[derive(Clone)]
pub(crate) struct Credential(pub(crate) String);

/// The plaintext listener.
pub(crate) struct Listener {
    inner: tokio::net::TcpListener,
    log: Option<Arc<Log>>,
}
impl axum::serve::Listener for Listener {
    type Io = Counted<tokio::net::TcpStream>;
    type Addr = SocketAddr;
    async fn accept(&mut self) -> (Self::Io, SocketAddr) {
        let (io, address) = axum::serve::Listener::accept(&mut self.inner).await;
        let link = self.log.as_ref().map(|log| log.accept(false));
        (Counted { inner: io, link }, address)
    }
    fn local_addr(&self) -> io::Result<SocketAddr> {
        self.inner.local_addr()
    }
}
impl axum::extract::connect_info::Connected<axum::serve::IncomingStream<'_, Listener>> for Link {
    fn connect_info(stream: axum::serve::IncomingStream<'_, Listener>) -> Self {
        Link(stream.io().link.clone())
    }
}
/// The TLS listener's TCP stage, below rustls.
#[derive(Clone)]
pub(crate) struct Acceptor(Option<Arc<Log>>);
impl<S> axum_server::accept::Accept<tokio::net::TcpStream, S> for Acceptor {
    type Stream = Counted<tokio::net::TcpStream>;
    type Service = axum::middleware::AddExtension<S, ConnectInfo<Link>>;
    type Future = std::future::Ready<io::Result<(Self::Stream, Self::Service)>>;
    fn accept(&self, stream: tokio::net::TcpStream, service: S) -> Self::Future {
        let link = self.0.as_ref().map(|log| log.accept(true));
        let service =
            tower::Layer::layer(&axum::Extension(ConnectInfo(Link(link.clone()))), service);
        std::future::ready(Ok((
            Counted {
                inner: stream,
                link,
            },
            service,
        )))
    }
}
/// The station's listener, TLS or plaintext, with every accepted stream counted.
pub(crate) enum Server {
    Tls(Box<axum_server::Server<SocketAddr, axum_server::tls_rustls::RustlsAcceptor<Acceptor>>>),
    Plain(Listener),
}
impl Server {
    pub(crate) fn new(
        listener: std::net::TcpListener,
        tls: Option<axum_server::tls_rustls::RustlsConfig>,
        log: Option<Arc<Log>>,
    ) -> io::Result<Server> {
        Ok(match tls {
            Some(tls) => Server::Tls(Box::new(axum_server::from_tcp(listener)?.acceptor(
                axum_server::tls_rustls::RustlsAcceptor::new(tls).acceptor(Acceptor(log)),
            ))),
            None => Server::Plain(Listener {
                inner: tokio::net::TcpListener::from_std(listener)?,
                log,
            }),
        })
    }
    pub(crate) async fn serve(self, app: Router) -> io::Result<()> {
        match self {
            Server::Tls(server) => server.serve(app.into_make_service()).await,
            Server::Plain(listener) => {
                axum::serve(listener, app.into_make_service_with_connect_info::<Link>()).await
            }
        }
    }
}

/// The outermost router layer: each HTTP exchange of a counted connection as "<METHOD>
/// <route>", the request as read and the response as sent, both as HTTP/1.1 text.
pub(crate) async fn http(request: Request, next: Next) -> Response {
    let Some(link) = Link::of(&request) else {
        return next.run(request).await;
    };
    let route = request
        .extensions()
        .get::<MatchedPath>()
        .map_or("unrouted", |path| path.as_str());
    let kind = format!("{} {route}", request.method());
    let path = request
        .uri()
        .path_and_query()
        .map_or(request.uri().path(), |p| p.as_str());
    let head = request.method().as_str().len() + 1 + path.len() + " HTTP/1.1\r\n".len();
    let read = Arc::new(AtomicU64::new((head + fields(request.headers())) as u64));
    let request = request.map(|body| {
        Body::new(Tally {
            inner: body,
            bytes: read.clone(),
            done: None,
        })
    });
    let mut response = next.run(request).await;
    link.message(Way::FromClient, &kind, read.load(Ordering::Acquire));
    if let Some(Credential(client)) = response.extensions_mut().remove::<Credential>() {
        link.credential(client);
    }
    let status = response.status();
    let head = "HTTP/1.1 000 \r\n".len() + status.canonical_reason().unwrap_or("").len();
    let written = Arc::new(AtomicU64::new((head + fields(response.headers())) as u64));
    response.map(|body| {
        Body::new(Tally {
            inner: body,
            bytes: written,
            done: Some((link, kind)),
        })
    })
}
/// Each header field as "name: value" CRLF, then the empty line.
fn fields(headers: &axum::http::HeaderMap) -> usize {
    headers
        .iter()
        .map(|(name, value)| name.as_str().len() + 2 + value.len() + 2)
        .sum::<usize>()
        + 2
}
/// A body whose data bytes are counted as they pass; a response body records its exchange's
/// response when it is dropped (sent, or abandoned).
struct Tally {
    inner: Body,
    bytes: Arc<AtomicU64>,
    done: Option<(Arc<Connection>, String)>,
}
impl HttpBody for Tally {
    type Data = Bytes;
    type Error = axum::Error;
    fn poll_frame(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<Option<Result<http_body::Frame<Bytes>, axum::Error>>> {
        let polled = Pin::new(&mut self.inner).poll_frame(cx);
        if let Poll::Ready(Some(Ok(frame))) = &polled
            && let Some(data) = frame.data_ref()
        {
            self.bytes.fetch_add(data.len() as u64, Ordering::AcqRel);
        }
        polled
    }
    fn is_end_stream(&self) -> bool {
        self.inner.is_end_stream()
    }
    fn size_hint(&self) -> http_body::SizeHint {
        self.inner.size_hint()
    }
}
impl Drop for Tally {
    fn drop(&mut self) {
        if let Some((link, kind)) = self.done.take() {
            link.message(Way::ToClient, &kind, self.bytes.load(Ordering::Acquire));
        }
    }
}

/// A frame's header: 2 bytes, 4 from 126 payload bytes, 10 from 65536; a client's mask adds 4.
fn frame_bytes(payload: usize, masked: bool) -> u64 {
    let header = match payload {
        n if n < 126 => 2,
        n if n < 65536 => 4,
        _ => 10,
    };
    (header + payload + if masked { 4 } else { 0 }) as u64
}
#[derive(serde::Deserialize)]
struct Typed<'a> {
    #[serde(borrow, rename = "type")]
    kind: Option<std::borrow::Cow<'a, str>>,
}
/// A message's type and its frame bytes; a received text is typed only by a known command.
fn tally(message: &Message, received: bool) -> (String, u64) {
    let (kind, payload) = match message {
        Message::Text(text) => {
            let kind = serde_json::from_str::<Typed>(text.as_str())
                .ok()
                .and_then(|t| t.kind)
                .filter(|kind| !received || COMMANDS.contains(&kind.as_ref()))
                .map_or_else(|| "ws other".to_owned(), |kind| format!("ws {kind}"));
            (kind, text.len())
        }
        Message::Binary(data) => ("ws binary".to_owned(), data.len()),
        Message::Ping(data) => ("ws ping".to_owned(), data.len()),
        Message::Pong(data) => ("ws pong".to_owned(), data.len()),
        Message::Close(frame) => (
            "ws close".to_owned(),
            frame.as_ref().map_or(0, |f| 2 + f.reason.len()),
        ),
    };
    (kind, frame_bytes(payload, received))
}

static SOCKETS: AtomicU64 = AtomicU64::new(0);
/// A station WebSocket whose frames are tallied for its connection, with its display profile.
pub(crate) struct Socket {
    inner: axum::extract::ws::WebSocket,
    link: Option<Arc<Connection>>,
    id: u64,
}
impl Socket {
    pub(crate) fn new(inner: axum::extract::ws::WebSocket, link: Option<Arc<Connection>>) -> Self {
        let id = SOCKETS.fetch_add(1, Ordering::Relaxed);
        if let Some(link) = &link {
            link.socket(id, Some("none"));
        }
        Socket { inner, link, id }
    }
    pub(crate) fn display(&self, profile: &'static str) {
        if let Some(link) = &self.link {
            link.socket(self.id, Some(profile));
        }
    }
    pub(crate) async fn send(&mut self, message: Message) -> Result<(), axum::Error> {
        let sent = self.link.as_ref().map(|_| tally(&message, false));
        self.inner.send(message).await?;
        if let (Some(link), Some((kind, bytes))) = (&self.link, sent) {
            link.message(Way::ToClient, &kind, bytes);
        }
        Ok(())
    }
    pub(crate) async fn recv(&mut self) -> Option<Result<Message, axum::Error>> {
        let received = self.inner.recv().await;
        if let (Some(link), Some(Ok(message))) = (&self.link, &received) {
            let (kind, bytes) = tally(message, true);
            link.message(Way::FromClient, &kind, bytes);
        }
        received
    }
}
impl futures_sink::Sink<Message> for Socket {
    type Error = axum::Error;
    fn poll_ready(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        Pin::new(&mut self.inner).poll_ready(cx)
    }
    fn start_send(mut self: Pin<&mut Self>, message: Message) -> Result<(), Self::Error> {
        let sent = self.link.as_ref().map(|_| tally(&message, false));
        Pin::new(&mut self.inner).start_send(message)?;
        if let (Some(link), Some((kind, bytes))) = (&self.link, sent) {
            link.message(Way::ToClient, &kind, bytes);
        }
        Ok(())
    }
    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        Pin::new(&mut self.inner).poll_flush(cx)
    }
    fn poll_close(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        Pin::new(&mut self.inner).poll_close(cx)
    }
}
impl Drop for Socket {
    fn drop(&mut self) {
        if let Some(link) = &self.link {
            link.socket(self.id, None);
        }
    }
}
