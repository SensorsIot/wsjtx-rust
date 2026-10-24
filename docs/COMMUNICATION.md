# Station communication contract

Status: CR #3 target and implementation contract. Promises: FR-019, FR-021.

## Connection and security

The server serves its embedded HTML, JavaScript and CSS at `/`, `/app.js` and
`/style.css`. No frontend framework, CDN or build step is required. Each client
uses one WebSocket at `/ws`, subprotocol `wstx.v1`. Origin MUST equal the configured
origin exactly, including scheme and port. Missing Origin and subprotocol are denied.

Default development binding is `127.0.0.1:8080`, without authentication. This mode
is for a trusted local computer. A non-loopback binding MUST provide TLS certificate,
private key, access token and explicit HTTPS origin; startup fails otherwise.
TLS/token settings also work on loopback for isolated tests. Plaintext token use is refused.
There is no separate plaintext listener in TLS mode.

Runtime environment settings:

| Setting | Meaning |
|---|---|
| WSTX_BIND | Numeric IP and port; `127.0.0.1:8080` by default. Port zero selects a temporary port. |
| WSTX_ORIGIN | Exact browser origin, without trailing slash, path, query, credentials or fragment. Defaults to the bound loopback URL. |
| WSTX_TLS_CERT | Path to PEM certificate chain; required with TLS key. Use a certificate trusted by the browser for actual operation. |
| WSTX_TLS_KEY | Path to PEM private key; restrict file permissions to the server identity. |
| WSTX_TOKEN | Secret of 32 through 128 ASCII letters/digits; use cryptographically generated randomness and deliver through a protected runtime environment. Never put it in a URL or source file. |

The HTTPS page provides a token login form. `POST /session` requires the exact Origin
and a raw token body of at most 1,024 bytes. Success returns 204 and a Secure, HttpOnly,
SameSite=Strict cookie scoped to `/` with browser Max-Age 28,800 seconds. Invalid tokens
return 401; disallowed/missing Origin returns 403. Login is limited globally to ten
attempts per 60-second window (429 after that). This small-station limit may temporarily
deny legitimate login under attack; an internet-facing deployment should add edge rate limiting.

WebSocket upgrades require the cookie in TLS mode. The cookie is the bearer secret;
its browser expiry is not a server-enforced session expiry. Rotate the configured token
and restart to invalidate existing credentials; disconnect existing processes when rotating.
There is no user-account database or transmit authority in this CR. Static assets contain
no station data and can be loaded before login. Authentication failures do not reveal tokens.

## Messages and validation

Messages MUST be UTF-8 JSON text, at most 1,024 bytes per message and per frame.
Requests have exactly `v`, `type`, `id`; other fields are rejected. IDs are integers
from zero through 9,007,199,254,740,991. Duplicate IDs are permitted for read-only
requests; responses echo them on the requesting connection. Ordering follows request
order on that connection. No state-changing commands exist.

```json
{"v":1,"type":"station.get","id":12}
```

```json
{"v":1,"type":"station.status","id":12,"data":{"version":"0.1.0","radio":"unconfigured"}}
```

The version is the candidate application's package version. Radio is always
`unconfigured` until a later radio CR. On initial connection and reconnection the
client MUST request a complete snapshot before showing Connected. There are no changing
station properties or subscription commands in this slice, and no periodic status polling.

Errors have this envelope:

```json
{"v":1,"type":"error","id":12,"data":{"code":"unknown_command"}}
```

| Condition | Code / action |
|---|---|
| JSON cannot be parsed | invalid_json; id null |
| Non-object, missing/extra fields, invalid ID or non-string type | invalid_request; null ID unless valid ID was supplied |
| Version is not integer 1 | unsupported_version |
| String command other than station.get | unknown_command |
| Binary message | Close 1003 |
| Frame/message over limit | WebSocket transport rejects it; client reconnects |

The server validates request shape, version, then command in that order. Recoverable
JSON errors leave the connection open. No stack traces or internal exception details
are returned. There is no application or negotiated WebSocket compression.

## Liveness and resource limits

The server sends `{"v":1,"type":"heartbeat"}` and a WebSocket Ping every five seconds.
Browsers automatically answer the Ping. The server disconnects peers without a Pong
for more than 15 seconds at the next heartbeat tick. The client marks state stale
when its connection closes or when no message has arrived for more than 12 seconds,
checked once per second. Thus silent-loss detection can take 13 seconds.

Reconnect delays are one, two, then four seconds, capped at four seconds; successful
snapshot receipt resets the delay. Once connectivity is restored and loss is detected,
fresh status MUST arrive within ten seconds. Recovery including an undetected silent
failure includes the separate detection bound above.

At most 16 WebSockets are active; further upgrades return 503. Each peer processes
one request and response at a time, with no application output queue. The WebSocket
write buffer is capped at 2,048 bytes; each send has a two-second deadline. Socket/kernel
buffers are additional OS-managed bounds. A blocked peer is disconnected; it does not
block another peer's task. These limits bound application queuing, not total process
memory independently of HTTP/TLS connections managed by the runtime.

## Thin-link budget and test model

The minimum profile targets a shared bottleneck of 32,000 bits/s in each direction,
with 300 ms RTT and two clients. Mean idle-session usage MUST be at most 1,000 bytes/s
in each direction over 60 seconds, including heartbeat and accounted protocol overhead.
A connected status request MUST display within two seconds; first connection/status
MUST display within ten seconds after the page is loaded. Uncached page time and bytes
are reported separately. Raw audio and spectrum/waterfall streaming are absent.

The portable test proxy shapes actual TCP-stream bytes (including real TLS records
in TLS tests), in at most 512-byte segments, with a shared 4,000-byte/s schedule in each
direction and 150 ms one-way latency. Each segment is additionally charged 80 bytes
for TCP/IPv6 headers and 80 bytes in the reverse direction for an ACK. This is explicit
modelled network overhead, not a packet capture. It does not reproduce retransmissions,
packet loss, congestion control or exact kernel packetization. Its bulk-transfer timing
is tested independently of the station application. Physical-link certification is outside
this CR; results MUST identify this model rather than claim on-wire measurements.
The simulator disconnects overloaded peers above its 128 KiB per-direction pending/write
buffer cap instead of modelling an unlimited congestion queue.

TC-021-005 through TC-021-009 in issue #3 define verification. They are level 2:
isolated automated tests on the Windows development machine and Windows CI, with
disposable browser/server/TLS/proxy processes and no radio or live service.
