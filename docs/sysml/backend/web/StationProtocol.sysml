package WstxStationProtocol {
    private import ScalarValues::*;
    private import WstxRecordingReceive::ErrorCode;
    private import WstxReceiveSpectrum::DetailedSpectrumFrame;
    private import WstxReceiveSpectrum::SpectrumFrame;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::'FR-021';
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-019';
    private import WstxRequirements::'FR-022';
    private import WstxRequirements::'CL-003-04';
    private import WstxProfiles::'CL-005-04';
    private import WstxRecordingReceive::'CL-008-03';
    private import WstxRadioIO::'CL-008-05';
    private import WstxOperatingReceive::'CL-008-07';
    private import WstxRequirements::'CL-010-05';
    private import WstxRequirements::'CL-010-07';
    private import WstxRequirements::'CL-010-08';
    private import WstxRequirements::'TC-021-007';
    private import WstxRequirements::'TC-022-001';
    private import WstxProfiles::'TC-022-003';
    private import WstxRequirements::'TC-022-005';
    private import WstxRequirements::'FR-003';
    private import WstxRequirements::'FR-010';
    private import WstxRequirements::'TC-022-006';
    private import WstxRequirements::'TC-022-010';
    private import WstxRequirementsFrontend::'CL-051-02';
    doc /* Canonical status, authentication and transport contract. Profile, recording,
         live receive and display extensions refine this shared boundary in WstxProfiles,
         WstxProfileRecordings, WstxRecordingReceive WstxRadioIO and WstxOperatingReceive. They do not create separate authentication
         or transport authorities. Implemented status is not a complete operating API. */

    enum def DeploymentMode { enum trustedLoopback; enum authenticatedTls; }
    enum def LinkState { enum connecting; enum connected; enum stale; }
    enum def RequestError { enum invalid_json; enum invalid_request; enum unsupported_version; enum unknown_command; }
    attribute def Limits {
        attribute controlBytes : Integer = 1024;
        attribute safeIntegerMax : Integer = 900719925 * 10000000 + 4740991;
        attribute socketCount : Integer = 16;
        attribute writeBufferBytes : Integer = 4096;
        attribute sendDeadlineMs : Integer = 2000;
        attribute heartbeatMs : Integer = 5000;
        attribute stalePongMs : Integer = 15000;
        attribute clientSilenceMs : Integer = 12000;
        attribute clientWatchdogMs : Integer = 1000;
        attribute clientConnectMs : Integer = 5000;
        attribute restoredSnapshotMs : Integer = 10000;
        attribute cookieMaxAgeSeconds : Integer = 28800;
        attribute loginAttempts : Integer = 10;
        attribute loginWindowSeconds : Integer = 60;
        doc /* Incoming text/frame and outbound control/Thin are <=1024 UTF-8 bytes.
             WstxRecordingReceive explicitly permits <=2048-byte Detailed events.
             OS socket/kernel and HTTP/TLS memory are additional runtime bounds;
             application limits do not claim a total process-memory bound. */
    }
    attribute def EndpointPolicy {
        attribute mode : DeploymentMode;
        attribute bindAddress : String = "127.0.0.1:8080";
        attribute exactOrigin : String;
        attribute tlsCertificatePath : String[0..1];
        attribute tlsPrivateKeyPath : String[0..1];
        attribute accessToken : String[0..1];
        attribute webSocketPath : String = "/ws";
        attribute webSocketSubprotocol : String = "wstx.v1";
        attribute plaintextTokenAllowed : Boolean = false;
        doc /* Environment-only startup uses WSTX_BIND (numeric IP:port; port zero is
             temporary), WSTX_ORIGIN, WSTX_TLS_CERT, WSTX_TLS_KEY and WSTX_TOKEN.
             Default bind is trusted local plaintext. Non-loopback requires TLS chain,
             private key, token and explicit HTTPS origin, or startup fails. TLS also
             works on loopback; no second plaintext listener exists in TLS mode.
             Origin is exact scheme/host/port, without trailing slash, path, query,
             credentials or fragment; default is the bound loopback URL. Profile startup
             instead uses WstxProfiles' persisted endpoint/identity rules.
             Token is32..128 ASCII letters/digits from cryptographic randomness;
             deliver privately, never in URL/source. Private-key permissions restrict
             use to the server identity. A production browser trusts the selected TLS
             certificate; disposable test certificates do not grant production trust. */
    }
    attribute def LoginInput {
        attribute originPresentAndExact : Boolean;
        attribute tokenValid : Boolean;
        attribute bodyBytes : Integer;
        attribute attemptsInWindow : Integer;
        doc /* POST /session accepts raw token body <=1024 bytes. Exact Origin is
             required. A successful TLS login returns204 and a Secure, HttpOnly,
             SameSite=Strict cookie scoped to/. Invalid token=>401; missing/wrong
             Origin=>403; requests beyond ten per60s global window=>429. This may
             temporarily deny legitimate logins under attack; internet-facing deployment
             adds edge rate limiting. Oversized requests are refused before acceptance.
             No failure reveals tokens. This boundary has no user-account database. */
    }
    calc def UpgradeAllowed {
        in originPresentAndExact : Boolean;
        in subprotocolPresentAndExact : Boolean;
        in tls : Boolean;
        in sessionValid : Boolean;
        in activeSockets : Integer;
        return accepted : Boolean = originPresentAndExact and subprotocolPresentAndExact and
            (not tls or sessionValid) and activeSockets < 16;
        doc /* Wrong/missing Origin or wstx.v1 is denied. TLS upgrades require the
             selected session cookie; exhausted16-socket capacity returns503. */
    }
    requirement SessionSecurity {
        doc /* The cookie is a bearer secret: browser Max-Age does not establish a
             server-enforced session expiry. Rotate the configured token and restart
             to invalidate credentials, disconnecting existing station processes.
             Static assets contain no station data and may load before login.
             AuthenticateProfile supplies profile-specific cookie naming/session routing.
             Distinct ports do not isolate cookies or make mutually hostile services
             trusted; same-host station processes assume one operator trust domain. */
    }
    item def StatusRequest {
        attribute v : Integer = 1;
        attribute 'type' : String = "station.get";
        attribute id : Integer;
        assert constraint safeId { id >= 0 and id <= (900719925 * 10000000 + 4740991) }
        doc /* Exact request keys are{v,type,id}, no others. Integers are JSON integers,
             not strings/Boolean/fractional or values outside the safe range. Duplicate
             IDs are allowed for read-only requests. The response echoes this ID only
             on its requesting connection, preserving that connection's request order. */
    }
    item def StatusData {
        attribute version : String;
        attribute radio : String = "unconfigured";
        attribute build : String;
        doc /* version is the candidate package version. This legacy status field stays
             unconfigured; authoritative native CAT/receive state uses WstxRadioIO's
             separate schema and is never inferred from this placeholder. build is the
             station's ClientBuild (#51, CL-051-01). */
    }
    attribute def ClientBuild {
        attribute hexDigits : Integer = 16;
        doc /* CL-051-01 (#51). The identity of the browser client a station serves: the
             first 16 lower-case hex digits of the SHA-256 over the served client files
             index.html, authorization.js, app.js, recording.js, recording.css, contact.js,
             logbook.js and style.css, concatenated in that order. The page carries the
             build it was served with (body data-build); every station.status carries the
             station's (StatusData::build). Equal builds mean the page's client is the
             station's; a station update that changes the client changes the build. */
    }
    attribute def PageUpdate {
        attribute reloadsAtMostOncePerBuild : Boolean = true;
        attribute keepsBrowserSettings : Boolean = true;
        attribute heldByQsoDialogOrUnsavedSettings : Boolean = true;
        attribute rejectedSnapshotSilent : Boolean = false;
        doc /* CL-051-02/03 (#51). On every station.status (each connect and reconnect,
             and Refresh) the page compares StatusData::build with its own ClientBuild.
             Different: the page reloads itself, once per station build (the build it
             reloaded for is kept in this tab's session storage; a later mismatch for
             that same build shows the chip instead of reloading again). Browser storage
             (theme, display and speed preferences) is kept. The operating screen holds
             the reload while a contact or transmission is in progress (contact not idle,
             completed or cancelled; Tx armed; Tune on), a confirmation or editor popup is
             open or the Settings form has unsaved edits; it then shows the
             ErrorFieldEntry stationUpdated (WstxOperatingLayout::ErrorField) "Station updated · reload", whose click
             reloads. A held page keeps working with its old client.
             A station snapshot the page rejects by its exact validation (the receive
             snapshot, a result page, the operating selection snapshot, the contact
             snapshot, a waterfall frame of an unknown shape) shows the ErrorFieldEntry stationDataRejected "Station data not
             understood (<which>) · reload" with the same reload action; a later valid
             snapshot of that kind clears it. Neither chip opens the Settings drawer.
             Chosen defaults (#51 implementation, the issue left them open): the build is
             compared on every station.status, that is on each connect and reconnect and
             on Refresh; a held update stays a chip until the operator clicks it, with no
             later automatic reload; unsaved Settings edits hold the reload like a popup.
             CAT status (WstxRadioIO) keeps its own CAT chip and is not part of this chip;
             a page of another build reloads before any of its snapshots matter. */
    }
    item def StatusReply {
        attribute v : Integer = 1;
        attribute 'type' : String = "station.status";
        attribute id : Integer;
        item data : StatusData;
        doc /* Exact envelope{v,type,id,data}; data exactly{version,radio,build}. */
    }
    item def ErrorData { attribute code : RequestError; }
    item def ErrorReply {
        attribute v : Integer = 1;
        attribute 'type' : String = "error";
        attribute id : Integer[0..1];
        item data : ErrorData;
        doc /* Exact envelope{v,type,id,data}; data exactly{code}. Null id is used
             where no valid request ID is available; no stack/internal exception text. */
    }
    calc def RequestDecision {
        in jsonParsed : Boolean;
        in exactObjectShapeAndTypes : Boolean;
        in versionOne : Boolean;
        in knownCommand : Boolean;
        return error : RequestError[0..1] = if not jsonParsed ? RequestError::invalid_json else
            if not exactObjectShapeAndTypes ? RequestError::invalid_request else
            if not versionOne ? RequestError::unsupported_version else
            if not knownCommand ? RequestError::unknown_command else null;
        doc /* Validation precedence is parse, object/exactkeys/ID/type, version,
             then command. invalid_json=>nullID; invalid_request=>nullID unless a
             valid ID was supplied. Recoverable errors leave the socket usable.
             station.get is the legacy known command; explicitly defined recording
             extensions add their own shapes without weakening shared validation.
             Binary frames close1003; excessive frame/message size is transport
             rejection/closure followed by normal reconnect. No application payload codec or negotiated WebSocket compression; bounded
             HTTP content coding is solely WstxHttpContentCoding::HttpContentCodingBoundary, and no arbitrary station-object dump. */
    }
    item def Heartbeat {
        attribute v : Integer = 1;
        attribute 'type' : String = "heartbeat";
        doc /* Exact{v:1,type:heartbeat} plus a WebSocket Ping every5s. Browsers answer
             Ping. On the next heartbeat tick, >15s without Pong disconnects that peer. */
    }
    action def ExchangeStatus {
        in request : StatusRequest;
        out response : StatusReply;
        doc /* One request/response processed at a time per peer, no application
             output queue; each send<=2s. An unresponsive peer is removed without
             blocking another task. Ready control/state/heartbeat traffic precedes
             optional visualization under WstxRecordingReceive's headroom policy. */
    }
    attribute def BrowserSnapshotPolicy {
        attribute requiredBeforeConnected : Boolean = true;
        attribute refreshUsesExistingSocket : Boolean = true;
        attribute constantStatusPolling : Boolean = false;
        attribute changingStatusEventDriven : Boolean = true;
        doc /* Initial/reconnected socket requests a complete status snapshot before
             Connected. Profile-mode readiness additionally needs WstxProfiles' valid
             GET. Refresh sends station.get on the existing socket. Last updated
             changes only when a matching snapshot is rendered. No changing station
             properties or subscriptions are implied by the legacy status slice.
             Native receive events have their explicitly declared extension schema.
             UI renders literal text and distinguishes confirmed/pending/stale state. */
    }
    state def BrowserLinkLifecycle {
        in connectionOpened : Boolean;
        in snapshotAccepted : Boolean;
        in connectionClosed : Boolean;
        in silentTooLong : Boolean;
        state connecting; state connected; state stale;
        entry; then connecting;
        transition ready first connecting if connectionOpened and snapshotAccepted then connected;
        transition closed first connected if connectionClosed then stale;
        transition silent first connected if silentTooLong then stale;
        transition retry first stale then connecting;
        doc /* >12s with no message checked each1s permits13s detection. Closed socket
             marks state stale immediately. The page's own deferred client download
             (WstxContact log and contact clients after the first snapshots) shares the one
             station-to-browser bottleneck and can hold queued messages behind it (#8): while
             one is pending the bound is >30s, checked each1s (31s detection); its
             completion or failure counts as a message, so the 12s bound restarts there.
             No other request extends the bound. Reconnect waits1,2,4s then caps4s;
             accepted fresh snapshot resets backoff. A new connection not open within5s
             is abandoned. Watchdog starts reconnect without waiting for old close
             handshake. Ignore replaced-socket callbacks. After restored connectivity
             and loss detection, fresh displayed status<=10s; undetected loss adds its
             separate detection bound. Reconnect never replays old mutable operations. */
    }
    attribute def ThinLinkBudget {
        attribute bitsPerSecondEachDirection : Integer = 32000;
        attribute roundTripMs : Integer = 300;
        attribute clients : Integer = 2;
        attribute measurementSeconds : Integer = 60;
        attribute idleBytesPerSecondEachDirectionMax : Integer = 1000;
        attribute thinBytesPerSecondEachDirectionMax : Integer = 3000;
        attribute connectedStatusDisplayMs : Integer = 2000;
        doc /* Shared bottleneck, not one32kbit link per browser. Targets of normal operation
             (#80, operator 2026-11-09): two browsers loaded and connected, live receive on a
             busy band (FT8, about 40 decodes per period), the waterfall on Thin, one complete
             QSO answering a CQ, the operator sorting and scrolling Band Activity and refreshing
             status; then Off with the same receive and the operator idle. Thin at most
             thinBytesPerSecondEachDirectionMax and Off at most idleBytesPerSecondEachDirectionMax
             per direction, heartbeat and accounted protocol overhead included, over
             measurementSeconds; connected status within connectedStatusDisplayMs. No test asserts
             these numbers: the operator judges the bytes from LinkTrafficLog, and the live check
             after a deploy watches that Refresh status shows within connectedStatusDisplayMs on
             the thin link (operator 2026-11-09, "Watch it in the live check"). Page and asset loading,
             reconnection, authorization recovery, CAT, selection or mode/band changes, recording
             replay or import and log maintenance carry no link budget. Detailed carries no
             32 kbit/s promise. */
    }
    attribute def LinkTrafficLog {
        attribute fileName : String = "link-traffic.log";
        attribute rotateBytes : Integer = 4194304;
        attribute tlsRecordOverheadBytes : Integer = 29;
        attribute tlsRecordPayloadMax : Integer = 16384;
        doc /* (#80, operator 2026-11-09) The station counts the bytes between each client and
             itself and writes them, per period, to fileName in the profile directory: one JSON
             line per client that had traffic in the period, written at the period's end; at
             rotateBytes the file first moves to link-traffic.1.log, replacing the older one (as the
             MCP audit, WstxMcpEndpoint::McpCredential). A station without a profile directory writes no
             log. The log is local: nothing of it is sent on a socket or in a response, and no
             client reads it; the operator reads the file. Counting never waits, and the line is
             written by its own task, never on a socket's or a request's path (the profile store's
             lock is not taken there).
             Period: the selected operating mode's (FT8 15000 ms, FT4 7500 ms), aligned to UTC
             period starts; mode "none" with 15000 ms periods when no mode is selected. A mode
             change at time c ends the open period there (its line: utc_ms its start, period_ms
             c - start, the old mode); the next period runs from c to the next UTC period start of
             the new mode (utc_ms c, period_ms up to that start, the new mode), then full periods.
             Example: FT8 period 12:00:00, change to FT4 at 12:00:05.200: lines (12:00:00, 5200,
             FT8), (12:00:05.200, 2300, FT4), (12:00:07.500, 7500, FT4).
             Client: "browser:<grant_id>" for an enrolled browser, "mcp:<client_id>" for an MCP
             client, "local" otherwise. Each TCP connection belongs, at each period end, to the
             client of its most recent request the station accepted with credentials (a browser
             grant, also by the WebSocket upgrade, or an MCP bearer); a connection without one is
             local (plaintext loopback, a page before enrollment, requests refused before
             authentication, also on TLS). Everything counted on a connection, its refused requests
             included, goes to that client. No cookie, token, proof or body content is logged.
             Line: {utc_ms, period_ms, mode, client, display (the display profile of each of the
             client's sockets at the period's end: "detail", "thin", "off" or "none"), to_client and
             from_client, each {bytes, other, estimate, types}}.
             bytes (exact): the TCP payload bytes the station wrote (to_client) or read (from_client)
             on the client's connections in the period, counted below TLS, so TLS records and
             handshakes are included; the same on HTTP/1.1, HTTP/2 and WebSocket connections.
             types maps a message type to [count, bytes], each message counted in the period in
             which the station finished writing or reading it, by one rule for every HTTP version:
             "ws <type>" for a WebSocket text message by its JSON type (station.status,
             spectrum.subscription and error replies included), "ws ping", "ws pong", "ws close",
             each the frame's header and payload as written or read (a client frame's mask
             included); "<METHOD> <route>" for an HTTP exchange with the route's template (an
             identifier segment as {id}; the WebSocket upgrade is "GET /ws"; the method is named only when it is GET, HEAD, POST, PUT, DELETE, OPTIONS, PATCH, CONNECT or TRACE, any other is "OTHER", and a request matching no route has the route "unrouted", so no client text becomes a type), so the set of types
             is bounded. An HTTP request counts "<METHOD> <path and query> HTTP/1.1" CRLF, each header
             field the router received as "name: value" CRLF, CRLF, and its body bytes as read; a
             response counts "HTTP/1.1 <code> <reason>" CRLF, each header field it carries when it
             leaves the outermost router layer (after content coding) as "name: value" CRLF, CRLF,
             and its body bytes as sent after content coding (no chunk framing). What the HTTP
             server adds itself (date, a content-length or transfer-encoding it sets, the Allow field of a 405, chunk framing,
             HTTP/2 frames and header compression) is not in types.
             other = bytes - sum of the types' bytes: TLS, handshakes and what the HTTP server adds;
             signed, since HTTP/2 header compression can make it negative.
             estimate (the IndependentLinkAccounting model, so that the numbers compare with
             ThinLinkBudget): with t = tlsRecordOverheadBytes on TLS and 0 on plaintext, each message
             m of a direction with type bytes b takes w = b + t x ceil(b / tlsRecordPayloadMax) wire
             bytes and ceil(w / segmentBytesMax) segments; the rest r = max(0, bytes - sum of w)
             takes ceil(r / segmentBytesMax) segments; S is the direction's segment total, and
             estimate = bytes + headerBytesPerSegment x S(this direction)
             + reverseAckBytesPerSegment x S(other direction).
             Worked example (TLS, one FT8 period, one Thin browser): to_client 3 ws station.tick of
             228 B (224-byte payload, 4-byte header), 3 ws heartbeat of 28 B and 3 ws ping of 2 B,
             each in one 29-byte TLS record, so bytes = 684 + 84 + 6 + 9 x 29 = 1035, r = 0, S = 9;
             from_client 3 ws pong of 6 B (2-byte header, 4-byte mask), each in one record,
             bytes = 3 x 35 = 105, S = 3. estimate to_client = 1035 + 80 x 9 + 80 x 3 = 1995
             (133 B/s), from_client = 105 + 80 x 3 + 80 x 9 = 1065 (71 B/s).
             Types are application bytes because only they can be told apart by message; bytes is
             counted below TLS because only there is the total exact.
             Implementation facts (#80 coder, 2026-11-09): periods follow the system clock's UTC (not the corrected station
             clock) and the operating mode read every 100 ms, so a mode change ends its period within 100 ms; received
             WebSocket text is typed only by a known command (station.get, recording.get, spectrum.thin, spectrum.detail,
             spectrum.off), any other text is "ws other" and binary "ws binary", so a client cannot grow the set of
             types; a request without a route is "<METHOD> unrouted"; a request is recorded when its response is
             produced, a response when its body is dropped; a closed connection's counts go into the next period line. */
    }
    attribute def PushedStationState {
        attribute safetyReadMinimumMs : Integer = 30000;
        doc /* Governing rule of the station-browser interface (operator decision #10,
             2026-11-04): a client-server application. Each browser holds one wstx.v1
             WebSocket; the station pushes typed state events on that socket when its
             state changes (transmit/PTT, contact, decode records, selection/radio/band,
             clock, log changes), each throttled per peer by that peer's
             display subscription (Detailed, Thin, Off), so an idle Off peer receives
             almost nothing beyond heartbeat and station.tick. HTTP carries commands and
             one snapshot read per state on (re)connect. transmit.state, contact.state,
             selection.state, receive.state and clock.state (#92, every profile) carry
             their state (WstxTransmit::TransmitWire, WstxContact::ContactStateEvent,
             WstxOperatingReceive::SelectionStateEvent, the receive wire, WstxRequirements
             CL-043-01); decode records are not carried yet;
             a state not yet carried is read after its announcement event (one pending read
             per state and browser) and after the browser's own mutation; a browser does not
             poll on a timer, except a safety read of a state not yet carried no more often
             than once per safetyReadMinimumMs. The browser holds the state (snapshot plus events) and
             renders locally. Safety decisions (HALT, watchdog, PTT keying and release)
             stay on the station and never wait for a browser read. Existing reads are
             migrated in slices: first GET /transmit (WstxTransmit::TransmitWire
             transmit.state), then receive results, recording (WstxRecordingReceive
             recording.state), profile (profile.state: exactly {v:1,type:"profile.state",
             data:{profile_id,boot_id,revision}}, sent to a display-subscribed peer once
             after its first subscription and then when the saved revision changes, checked
             once per second; the browser reads GET /profile once per socket for its first
             status and on a newer announced revision, not on a later status of the socket),
             operating selection (WstxOperatingReceive::SelectionStateEvent) and radio;
             free_tx_slots.state (#65, #82) carries its state: exactly {v:1,type:"free_tx_slots.state",
             data:{profile_id,boot_id,free_tx_slots}} (WstxStrategy::FreeTxSlots, at most 1024
             bytes), sent to each Detailed or Thin peer at each build of the value (every period start, when the decodes of a counted
             period are published (operator 2026-11-09, Rebuild on decodes), and at once when a QSO starts or ends or the live job, mode or band
             changes), once with free_tx_slots null when the value becomes null, and once to
             a peer that subscribes Detailed or Thin while a value exists; with or without a
             run, also while automation is never used; never to an Off peer. Its cost on the
             thin link is a target within ThinLinkBudget's Thin envelope, judged from
             LinkTrafficLog (#80): at most
             2 x (1024 + 4 WS + 29 TLS + 3 x 160 accounted TCP/ACK) / 7.5 s, about 410 B/s
             for two FT4 browsers, half that in FT8, and in a QSO one more build per Rx period
             (at most 1.5 times that, about 615 B/s for two FT4 browsers); until a read
             is migrated its existing cadence rules apply.
             A new boot (#74, operator 2026-11-08, CL-074-01): the browser learns the station's
             boot_id from GET /profile of a socket and from profile.state. When it learns a
             boot_id other than the one a view's held station state belongs to, that view drops
             the state at once and shows the form a freshly loaded page shows before its reads
             (no value of the previous boot, alone or together with values of the new boot),
             then reads its snapshot under its own rule (one read per socket, or only after its
             announcement event where its rule says so, as WstxMcp::AutomationIndicator) or
             waits for its first event; a snapshot reply that names another boot_id than the
             browser's current one is discarded (events of a closed socket are already
             ignored). This holds for every view of station state:
             contact, recording, receive, operating selection, AGC, Tx level, native radio,
             transmit, strategy (WstxStrategy::StrategySelector), automation, PSK Reporter,
             Monitor off at startup and alerts. Once the reads and first events of the new boot
             have arrived, each view shows what a page loaded fresh at that moment shows. A
             failed read leaves the empty form until that view's next read under its rule; no
             retry timer. While the socket is down, views keep their values under the existing
             stale marks until the new boot is learned. The logbook is stored history, not
             state of one boot, and keeps its own rules. */
    }
    attribute def IndependentLinkAccounting {
        attribute payloadBytesPerSecond : Integer = 4000;
        attribute oneWayMs : Integer = 150;
        attribute segmentBytesMax : Integer = 512;
        attribute headerBytesPerSegment : Integer = 80;
        attribute reverseAckBytesPerSegment : Integer = 80;
        attribute pendingAndWriteBytesMax : Integer = 131072;
        attribute silentDetectionSchedulerToleranceMs : Integer = 1000;
        doc /* Account actual TCP stream including real TLS records in TLS tests.
             Charge each <=512-byte segment80B TCP/IPv6 and reverse80B ACK. The
             128KiB per-direction pending/write cap disconnects overload. This model
             excludes retransmission, packet loss, congestion control and exact kernel
             packetization; it is not on-wire capture or physical-link certification.
             Browser Navigation/Resource Timing separately measures HTTP layer and its
             reported headers, excluding TLS/TCP/IP. Blackhole fixture discards bytes
             without closing, not packet loss emulation. Bulk timing is independently
             checked against the shaper; scheduler tolerance does not redefine budgets. */
    }
    action exchangeStatus : ExchangeStatus;
    satisfy WstxStationProtocol::'CL-003-02' by exchangeStatus;
    dependency stationOwner from exchangeStatus to WstxArchitecture::physicalStation::backend::stations::station;
    dependency transportOwner from exchangeStatus to WstxArchitecture::physicalStation::backend::stations::web;
    dependency presentationOwner from BrowserSnapshotPolicy to WstxArchitecture::physicalStation::frontend::browsers;
    dependency securityPromise from SessionSecurity to WstxStationProtocol::'CL-003-07';
    dependency reconnectPromise from BrowserLinkLifecycle to WstxRequirements::'CL-003-04';
    dependency budgetPromise from ThinLinkBudget to WstxRequirements::'CL-003-05';
    dependency pushedStatePromise from PushedStationState to WstxRequirements::'CL-003-05';
    dependency pushedStateBootPromise from PushedStationState to WstxRequirements::'CL-074-01';
    dependency pushedStateOwner from PushedStationState to WstxArchitecture::physicalStation::backend::stations::web;
    dependency bufferPromise from Limits to WstxStationProtocol::'CL-003-06';
    dependency exchangeVerification from ExchangeStatus to WstxStationProtocol::'TC-021-005';
    dependency browserVerification from BrowserSnapshotPolicy to WstxStationProtocol::'TC-021-006';
    dependency reconnectVerification from BrowserLinkLifecycle to WstxRequirements::'TC-021-007';
    dependency budgetJudgedFromLog from ThinLinkBudget to LinkTrafficLog;
    dependency trafficLogPromise from LinkTrafficLog to WstxRequirements::'CL-003-05';
    dependency trafficLogOwner from LinkTrafficLog to WstxArchitecture::physicalStation::backend::stations::web;
    dependency trafficLogVerification from LinkTrafficLog to WstxRequirements::'TC-080-001';
    dependency livenessVerification from Heartbeat to WstxStationProtocol::'TC-021-008';
    dependency tlsVerification from SessionSecurity to WstxStationProtocol::'TC-021-009';
    dependency buildPromise from ClientBuild to WstxStationProtocol::'CL-051-01';
    dependency pageUpdatePromise from PageUpdate to WstxRequirements::'CL-051-02';
    dependency rejectedSnapshotPromise from PageUpdate to WstxRequirements::'CL-051-03';
    dependency buildPresentationOwner from PageUpdate to WstxArchitecture::physicalStation::frontend::browsers;

    attribute loginBodyMaxBytes : Integer = 1024;
    attribute cookieMaxAgeSeconds : Integer = 28800;
    attribute def RuntimeInputs {
        doc /* WSTX_TLS_CERT/KEY/TOKEN only; relative TLS paths resolve process CWD
             in BOTH modes. They are never serialized into settings/profile responses.
             Profile mode rejects present WSTX_BIND/WSTX_ORIGIN, including empty values.
             TLS pair complete, token 32..128 ASCII letters/digits with TLS only;
             non-loopback requires TLS/token plus saved explicit HTTPS origin.
             Independent random tokens per profile are an operator prerequisite:
             deliberately sharing the same login secret authorizes both logins. */
        attribute tlsCertificatePath : String[0..1];
        attribute tlsKeyPath : String[0..1];
        attribute token : String[0..1];
        attribute forbiddenBindPresent : Boolean;
        attribute forbiddenOriginPresent : Boolean;
    }
    action def AuthenticateProfile {
        doc /* Issue22 authentication for selected persisted HTTPS profiles. CL-022-01/02
             supersede the old UUID.runtime-token transport cookie, restart revocation
             and HttpOnly-only persistence rule; delivered (the radio identity
             Add/Replace/Remove slice was dropped, operator 2026-11-06, CL-022-02). A selected profile on a plaintext
             loopback origin has no grant authority: its configuration GET/PUT,
             operating HTTP routes and WS upgrade keep the runtime-token cookie
             wstx_session_<UUID>=<UUID>.<token> (no configured token = trusted
             loopback), with exact Origin checks, and its WS carries no grant
             revocation fence. Every HTTPS operating HTTP route and WS upgrade instead
             requires the current grant transport, re-validated for dispatch
             (scope/grant/revocation generation) under the one authority lock. Preserve POST /session raw-token body<=1024,
             exact Origin403 before authentication, invalid token401, oversized413,
             rate10attempts/60seconds per process429, TLS only and successful204.
             Successful bootstrap creates only a random256-bit ephemeral bootstrap
             context (60seconds), never a runtime-token cookie or ordinary-control grant.
             Host-only wstx_bootstrap_<UUID>, Path=/, Secure, HttpOnly, SameSite=Strict;
             its only uses are strict enrollment and the explicit bootstrap scope/identity
             setup operations below; it never authorizes ordinary control.
             Normal wstx_session_<UUID> contains a random256-bit opaque transport handle
             bound to one unrevoked scoped grant, Max-Age=28800. Verify exactly one
             expected cookie; malformed/duplicate/missing/cross-profile cookies401.
             Wrong/legacy token-valued cookies are not migrated into grants. Other
             names ignored. Expiry only removes transport readiness; retained key proof
             restores it automatically without another bootstrap submission.
             Transport handles follow RotateScopedTransport below; at most one current
             handle per grant and64 overall, elapsed monotonic lifetime28800seconds.
             Grant persistence is independent of transport rotation or expiry.
             One narrow new credential exception permits only a nonextractable P256
             signing CryptoKey in origin-scoped IndexedDB; no bootstrap token, private
             key export or token persistence in localStorage/sessionStorage/public
             profileJSON/URLs/logs/reports/retained submitted form state. Same-origin
             injected script/browser/OS compromise remains outside nonextractability.
             Environment-only legacy launch without a persisted selected profile retains
             its transient legacy auth contract and does not claim this durable grant.
             Existing WS exact Origin/wstx.v1/frame/rate/liveness protections remain;
             grant revocation closes affected WS and rejects later protected effects.
             Same-host processes remain trusted; distinct ports are not hostile-service
             isolation. No transmit role or permission is created. */
        @ModelNotes::FollowsSource { reference = "RFC 6265 section 8.5 (cookies)"; }
        in selectedUuid : String;
        in runtime : RuntimeInputs;
        out cookieName : String;
    }
    action authenticate : AuthenticateProfile;
    dependency authenticationOwner from authenticate to WstxArchitecture::physicalStation::backend::stations::web;
    satisfy WstxStationProtocol::'CL-005-03' by authenticate;

    doc /* Issue22 target data/actions below implement CL-022-01/02 only after exact
         independent meaning review, supported-browser primitive qualification and
         source-scope admission. They reuse selected profile/station authority; no new
         physical component or public-profile schema field is introduced. */
    enum def GrantCondition { enum unauthorized; enum authorized; enum revoked; enum unknown; }
    enum def AuthOperationKind { enum enroll; enum challenge; enum prove; enum logout; enum revokeAll; enum receipt; enum commission; enum bootstrapScope; enum status; }
    enum def AuthOperationOutcome { enum committed; enum proofRequired; enum unauthorized; enum wrongOrigin; enum invalid; enum saturated; enum persistenceFailed; enum unknown; }
    attribute maxActiveBrowserGrants : Integer = 64;
    attribute maxPendingProofChallenges : Integer = 64;
    attribute proofChallengeLifetimeSeconds : Integer = 60;
    attribute maxActiveTransportHandles : Integer = 64;
    attribute maxTransportHandlesPerGrant : Integer = 1;
    attribute transportLifetimeSeconds : Integer = 28800;
    action def RotateScopedTransport {
        doc /* Issue22 target behavior, not an implementation declaration. The volatile
             transport table is owned by the same selected-station authorization
             authority, not another credential store or lifecycle owner. It contains
             at most one current handle per existing unrevoked verifier grant and at
             most64 entries overall; no disk transport persistence or verifier eviction.
             Successful ordinary grant proof serializes current scope/grant/revocation
             validation, one-use challenge consumption and installation of a new
             CSPRNG256bit opaque handle. Installation atomically replaces the previous
             current handle for that SAME grant only. It does not replace a verifier,
             advance revocation generation, revoke another grant, change commissioning
             or disconnect CAT/audio. Other grants/profile processes remain unchanged.
             Replay or invalid/expired/wrong-Origin/wrong-scope proof never replaces a
             current handle. Random-generation or response-preparation failure fails
             closed without installing a handle or invalidating the prior current one;
             an already consumed nonce requires a new challenge, never proof replay.
             Installed handles expire after28800 elapsed monotonic seconds, never
             extended by use; cookie Max-Age remains28800. Expired/replaced/revoked/
             wrong-scope handles return401 for new protected HTTP requests/WS upgrades.
             Purge, rotation, expiry and ordinary restart do not delete or age-evict a
             verifier, operation receipt or commissioning. Restart drops only volatile
             transport; retained-key proof recovers without another bootstrap token.
             Receipt-purpose proof NEVER installs or replaces transport. Revocation or
             radio removal still invalidates dependent handles and existing effects/WS
             according to the existing authority/cancellation rules.
             Rotation is distinct from revocation: an already authenticated WS retains
             only its existing grant/scope/revocation authority and existing dispatch
             checks; rotation alone neither grants a new effect nor revokes its grant.
             An open socket never establishes current browser authorization readiness.
             Concurrent same-key proofs serialize; last committed proof determines the
             sole current handle. HTTP delivery can be reordered or lost, so204 alone
             does not prove the last-delivered cookie is current. The client shares its
             existing readiness promise within a document and checks protected read-only
             status after renewal. A401 or lost renewal response leaves readiness
             unavailable/unknown and recovers through fresh challenge/proof/status using
             the retained key, without bootstrap resubmission or user-mutation replay.
             Same-origin tabs share cookie storage; once overlapping responses quiesce,
             any tab can recover through fresh proof/status. Rotation by another tab
             never deletes the retained key or claims revocation. No cross-tab framework
             or additional credential store is introduced. Existing<=2s truthfulness,
             rate10/60, TLS/Origin/profile checks and1024byte auth bounds all remain. */
    }
    attribute def SelectedRadioAuthorizationScope {
        doc /* ProfileId is the persisted logical station identity in this phase;
             HTTPS origin is exact effective Endpoint.origin including port. UUIDs are
             lowercase RFC9562v4; safetyRevision is positive safe integer<=maxRevision.
             RadioId is authority-assigned, not COM endpoint/boot/browser identity.
             Migration assigns identity only, no grant or commissioning. An
             endpoint/model/PTT change increments revision and
             invalidates commissioning. Unchanged USB return preserves both. */
        attribute profileId : String;
        attribute radioId : String;
        attribute safetyRevision : Integer;
        attribute httpsOrigin : String;
    }
    attribute def AuthWireScope {
        doc /* Every auth-v1 JSON scope/current_scope/expected_scope, including
             bootstrap/status/challenge/receipt/identity projections, is EXACTLY
             {profile_id,radio_id,safety_revision}; no https_origin/origin/extra keys.
             This is an ephemeral wire projection of SelectedRadioAuthorizationScope,
             not another selected-radio identity/current-value owner. Copy UUID/revision
             unchanged. In a request, first validate TLS and exact HTTP Origin against
             the selected Endpoint; reconstruct httpsOrigin only from that validated
             effective origin, never a body field. In responses browser already knows
             its exact location.origin. Reconstruction is lossless within this required
             endpoint context; the projection alone is not globally authoritative.
             Internal scope, persistence and both signed proof-purpose payloads KEEP
             the full exact origin and its length-prefixed signed bytes unchanged.
             For a new operation compare reconstructed profile/radio/revision with the
             current authority snapshot; stale tuple409/no effect. Explicit receipt
             reconciliation instead compares its stored operation tuple and never
             grants current control. Wrong transport Origin remains403 before auth;
             public profile origin domains/ResponseBudgetAdmission remain unchanged.
             Fixed UUID36/revision<=9007199254740991 give scope138UTF8bytes including
             all JSON punctuation/quotes. Compact-output independent width bounds:
             enrollment374, ordinary proof225, receipt proof426,
             commissioning244, revoke236, challenge response396, receipt response<=302
             (conservative18ASCII outcome/43grantId). Delivered bootstrap response
             {version,current_scope} is<=170bytes. All below unchanged1024 logical-byte cap.
             These bounds are for compact server JSON; input whitespace may consume
             the remaining request allowance but total>1024 still413. All bounded
             strings here are canonical ASCII, so no hidden UTF8/escape growth.
             Status scope is likewise138, not an origin echo; its existing complete
             response<=1024 admission still includes condition/error/receive summary.
             No unbounded native text or copied numerical/result state is permitted. */
        attribute profileId : String;
        attribute radioId : String;
        attribute safetyRevision : Integer;
    }
    attribute def BrowserPublicVerifier {
        doc /* Public, not a secret. GrantId is fresh CSPRNG256bits encoded unpadded
             base64url43characters; never recycled. P256 SEC1 uncompressed public key
             is65bytes beginning04, canonical base64url87characters, on-curve validated.
             Enrollment operationId persists with this verifier for restart reconciliation.
             Exactly ECDSA_P256_SHA256_FIXED-compatible r||s; no algorithm negotiation.
             Grant lifetime keys only origin/profileId/radioId; recorded safetyRevision
             is not grant lifetime. A same-radio safety edit preserves the verifier,
             but proof binds the new current revision and CAT remains uncommissioned.
             This permits re-confirmation without bootstrap token re-entry. */
        attribute grantId : String;
        attribute enrollmentOperationId : String;
        attribute uncompressedPublicKeyBase64url : String;
        attribute scope : SelectedRadioAuthorizationScope;
    }
    attribute def RadioCommissioningRecord {
        doc /* Single current observable acknowledgement for exact scope and effective
             endpoint/model/PTT configuration. Owner persists it only after explicit
             Confirm receive-only setup. Never a CAT open/query or transmit action.
             Changed safety configuration invalidates it and exposes explicit recovery. */
        attribute scope : SelectedRadioAuthorizationScope;
        attribute receiveOnlyConfirmed : Boolean;
    }
    enum def RequestPrincipal { enum browser; enum mcp; enum automation; }
    attribute def RequestPrincipalRule {
        doc /* (#58) The station attaches a RequestPrincipal to every request at the auth
             boundary from its credential, never from the route: a browser grant transport
             (or the plaintext runtime token) is browser; an MCP client's internal transport
             is mcp; commands of the station's own automation
             run are automation. Only browser is an operator action (Tx watchdog,
             set_watchdogs, WstxStrategy::WatchdogFromOperator); an unreadable credential is
             never browser. The auth-v1 status/revoke/commission operations and MCP client
             management accept only the browser principal. */
    }
    attribute maxMcpClients : Integer = 8;
    attribute def McpClientCredential {
        doc /* (#58) A durable MCP client credential in the private authorization record:
             id (UUID), name (1..32 printable ASCII, no leading or trailing space),
             created_utc_ms, last_used_utc_ms (null until used; written at most every
             10 minutes, exact in memory) and token_sha256 (unpadded base64url SHA-256 of the
             complete token); never the token. At most maxMcpClients, ids and digests unique;
             the record field mcp_clients is omitted while empty (records before #58 read
             unchanged). Browser-only routes, Origin exact, JSON body <= 1024 bytes:
             GET /authorization/v1/mcp-clients (read-only, Cache-Control no-store; a
             present Origin must be exact) lists {version, max_clients,
             clients [{client_id, name, created_utc_ms, last_used_utc_ms}], recent (newest
             first audit entries, WstxMcpEndpoint::McpCredential)}; .../create {version:1, name}
             returns 200 {version, client_id, name, created_utc_ms, token} with Cache-Control
             no-store, the only time the token is shown (cap reached 429, invalid name 400);
             .../revoke {version:1, client_id} removes it and every transport of it at once
             and returns the listing (unknown 409). An auth-v1 revoke with all_for_radio
             also removes every MCP client. An MCP token is never accepted as a browser
             cookie, by /session or by these routes. Settings > General > Access & grants
             shows the list with Revoke (after confirmation), the create field and the new
             token once with Copy and Done, and the recent use; it reads them only when
             Settings opens. */
        attribute id : String;
        attribute name : String;
        attribute createdUtcMs : Integer;
        attribute lastUsedUtcMs : Integer[0..1];
        attribute tokenSha256 : String;
    }
    attribute def PrivateAuthorizationRecord {
        doc /* Version1 private per-profile atomic record under existing OS-protected
             service data, one selected-profile writer. Contains public verifiers and
             authority metadata, never browser private key/bootstrap token. Reuse
             acknowledged atomic replacement, not another database/storage writer.
             Corrupt/missing expected record or failed commit fails closed. Only a new
             never-enrolled profile may create an empty record; no reset-on-read-error.
             Unrevoked verifiers have no timed deletion. Removing a radio removes its
             grants; grant-cap failure never evicts active grants. Existing trusted-OS
             persistence boundary remains; no universal power-loss durability claim. */
        attribute schemaVersion : Integer = 1;
        attribute currentScope : SelectedRadioAuthorizationScope[0..1];
        attribute commissioning : RadioCommissioningRecord[0..1];
        attribute grants : BrowserPublicVerifier[0..64];
        attribute revocationGeneration : Integer;
        attribute operationReceipts : AuthOperationReceipt[0..64];
        attribute mcpClients : McpClientCredential[0..8];
    }
    attribute def BootstrapScopeRequest {
        doc /* Delivered: exact POST /authorization/v1/bootstrap-scope request is
             {version:1}; no optional/unknown/duplicate fields. */
        attribute version : Integer = 1;
    }
    attribute def BootstrapScopeResponse {
        doc /* Delivered strict200 {version,current_scope}. Scope is the station-
             authority snapshot, never a browser-supplied tuple. No grant/verifier
             enumeration, cookies, keys or credentials in response. */
        attribute version : Integer = 1;
        attribute currentScope : AuthWireScope[0..1];
    }
    action def ReadBootstrapScope {
        doc /* Valid unexpired ephemeral bootstrap cookie for this selected profile
             required (missing/duplicate/wrong-profile401), exact Origin/TLS and all
             strict auth-v1 request/response/rate bounds apply. Cache-Control:no-store.
             POST is read-only: no identity/grant/receipt/challenge mutation, transport
             issuance, CAT/native I/O or implicit enrollment. After POST/session204,
             a fresh browser reads this response, then enrolls its exact non-null scope.
             Every HTTPS profile receives a scope when its record is first created, whether
             or not a radio is configured. A persisted record whose current scope is null,
             which no delivered operation writes, yields null and cannot enroll.
             Scope may race configuration: enrollment still compares authoritative
             scope and bootstrap binding at dispatch; stale tuple409, no effect.
             A read never rebinds a bootstrap context or broadens its enrollment scope. */
        in request : BootstrapScopeRequest;
        out response : BootstrapScopeResponse;
    }
    attribute def AuthChallenge {
        doc /* Server CSPRNG32byte nonce, canonical unpadded base64url43characters,
             one-use and60second monotonic validity; no wall-clock-expiry extension.
             Challenge binds currentScope,grantId,protocol1 and intended prove operation;
             currentScope is authority-selected current safety revision, not copied
             from an old verifier enrollment. Radio/profile/origin must still match.
             Signature payload is UTF8("WSTX-AUTH-PROOF") then byte01 then six fields:
             exact origin,profileId,radioId,decimal safetyRevision,grantId,nonce raw32.
             Each field is preceded by unsigned32-bit big-endian byte length; UUID and
             decimal fields ASCII, no padding/leadingzero, no Unicode normalization.
             Exactly this payload is signed with ECDSA SHA256; signature is64byte r||s
             (32byte unsigned big-endian coordinates), canonical base64url86characters.
             Reject noncanonical encoding, DER/ASN1, other length/curve/version/tuple,
             wrong origin, consumed/expired nonce. Valid proof atomically consumes nonce
             before transport issuance. Replays never mint another session. */
        attribute verifier : BrowserPublicVerifier;
        attribute currentScope : SelectedRadioAuthorizationScope;
        attribute nonceBase64url : String;
        attribute lifetimeSeconds : Integer = 60;
    }
    attribute def AuthEnrollmentRequest {
        doc /* Strict JSON version1,operation_id,scope,grant_id,public_key only. GrantId
             is browser-CSPRNG256bits generated and retained BEFORE submission;
             collision with a different verifier/operation is409, never replacement.
             This permits restart proof even when the enrollment response is lost.
             OperationId is
             fresh UUIDv4 retained by browser through unknown outcome. Bootstrap context
             authorizes this one exact scope; never grants another radio implicitly. */
        attribute version : Integer = 1;
        attribute operationId : String;
        attribute scope : AuthWireScope;
        attribute grantId : String;
        attribute publicKeyBase64url : String;
    }
    attribute def AuthProofRequest {
        doc /* Strict JSON version1,grant_id,nonce,signature only. Fields carry exact
             encodings above; server obtains scope from its challenge, never trusts a
             client-selected replacement. Request cap remains1024 logical UTF8bytes. */
        attribute version : Integer = 1;
        attribute grantId : String;
        attribute nonceBase64url : String;
        attribute signatureBase64url : String;
    }
    attribute def AuthOperationReceipt {
        doc /* Public strict response version1,operation_id,scope,outcome,grant_id;
             grant_id nullable; scope uses AuthWireScope on the wire, while journal
             scope below retains full internal context. No token,cookie,signature,nonce
             or private material.
             Receipt reconciliation identifies a committed operation, not authorization
             itself. Lost enrollment ACK retains a committed verifier; browser remains
             unknown/unauthorized until same operation receipt and scoped proof recover.
             Uncommitted enrollment is unusable after restart. Revocation commit fences
             queued effects; already-dispatched I/O follows acknowledged cancellation.
             Delivered entries are verifier-owned (enroll/logout/revokeAll/commission)
             and require ownerVerifier; any other persisted entry is corrupt and fails
             closed.
             A failed revocation write quarantines current-process access but discloses
             NOT durably revoked; restart may restore last committed grant. */
        attribute version : Integer = 1;
        attribute operationId : String;
        attribute scope : SelectedRadioAuthorizationScope;
        attribute outcome : AuthOperationOutcome;
        attribute grantId : String[0..1];
        // Internal journal discriminator/owner; not additional public response keys.
        attribute operationKind : AuthOperationKind;
        attribute ownerVerifier : BrowserPublicVerifier[0..1];
    }
    action def HandleScopedAuthorization {
        doc /* Delivered strict auth API v1. Exact paths POST /authorization/v1/bootstrap-scope,
             /status,/enroll,/challenge,/proof,/revoke,/commission,/receipt; no credentialed CORS.
             Existing POST /session stays raw-token, never accepts JSON extension keys.
             Every new request exactly version1 plus its listed fields; unknown,
             missing,duplicate keys/wrongtype/noncanonicalencoding400, contenttype
             application/json else415, body>1024bytes413, wrongOrigin403 first, TLS
             required before accepting credentials. At most10setup attempts(session/bootstrap-scope/enroll)/60s/process;
             grant/challenge caps64, saturation429. All responses<=1024UTF8bytes,
             uncompressed, no auth material in errors/logs. No endpoint opens CAT.
             bootstrap-scope: BootstrapScopeRequest/Response via ReadBootstrapScope;
             status: WstxStationAuthority::AuthStatusRequest, read-only active-grant
             snapshot per AutomaticCatStatus, no effects and no GET fallback;
             enroll: AuthEnrollmentRequest, ephemeral bootstrap cookie required;
             non-null current scope and exact bootstrap-scope binding required, stale
             tuple409, no grant. A null scope cannot enroll or prove readiness;
             challenge: {version,grant_id}, exact Origin and known verifier required;
             proof: AuthProofRequest; successful204 issues only new opaque transport;
             revoke: {version,operation_id,scope,all_for_radio}, matching active grant
             required; false logs out that grant, true revokes matching radio grants;
             a committed revoke also clears the caller's session cookie (Max-Age=0);
             commission: {version,operation_id,scope,receive_only_confirmed:true}, active
             matching grant required, commits exact displayed safety configuration;
             receipt: {version,operation_id,scope,grant_id,nonce,signature}; one-use
             receipt-purpose proof validates the operation owner, not ordinary-control
             authorization. Retain a bounded64-entry FIFO public receipt journal with
             original verifier for verifier-owned entries and committed outcome; it
             cannot authorize control or revive a revoked grant. Evicted/absent receipt returns409 unknown and
             browser remains unknown, never fabricates durable success. Journal entries
             persist atomically with their mutation and carry only bounded public
             verifier/scope/operation/outcome metadata;
             no bootstrap secret or unbounded tombstones. A separate challenge request
             {version,operation_id,scope} addresses a known receipt. Its payload uses
             UTF8 WSTX-AUTH-RECEIPT then byte01, followed by the same six length-prefixed
             proof fields plus operationId before nonce. Only receipt consumes this
             nonce; it never issues transport/control readiness. Ordinary grant proof
             uses WSTX-AUTH-PROOF and cannot substitute for receipt-purpose proof.
             Lost enrollment browser knows its pre-generated grantId, can prove its
             retained committed key then reconcile receipt while local readiness stays
             unknown; it dispatches no queued browser CAT effect before both succeed.
             Committed mutations return200 AuthOperationReceipt; unknown/failed commit
             never reports success (503persistence failure,409identity/unknown conflict).
             Missing/unknown/revoked/mismatched grant or cookie401. New challenge returns
             200 strict {version,grant_id,scope,public_key,nonce,lifetime_seconds},
             projecting AuthChallenge.currentScope through AuthWireScope and public
             verifier metadata; no origin is echoed or removed from signed bytes.
             Receipt uses same operationId only and is read-only even though POST.
             Bootstraprotation is explicit revoke-allprofile; process restart is not.
             Before protected HTTP/WS/native dispatch, station authority serializes
             current grant/scope/revocation generation with selection. No blanket
             session readiness from an open WS. Disconnect/401 is truthful<=2s and
             automatic retained-key proof does not replay a user mutation. */
        in kind : AuthOperationKind;
        in selected : SelectedRadioAuthorizationScope[0..1];
        out receipt : AuthOperationReceipt;
    }
    verification sharedBrowserSessions {
        subject operation : AuthenticateProfile;
        objective { verify WstxStationProtocol::'CL-005-03'; verify WstxProfiles::'CL-005-04'; }
        doc /* TC-022-004: four TLS localhost ports/tokens, ONE Chromium cookie
             context. Before authorization GET/PUT/WS401. Fresh selected authorization
             is session204, bootstrap-scope200 with non-null migrated scope, completed
             persistence of the key/grant/operation IDs before enroll200, then
             challenge/proof204/status200. Session204 alone grants no ordinary access.
             Reverse-order retained authorization proves the existing key/grant and
             verifies status without token reentry or enrollment replay.
             Ordinary same-origin browser GET without manual Origin200; cookie
             names/attributes only reported. All four Refresh/reconnect independently.
             Station1 token to station2 login401; copied name/value or value under
             station2's expected name401; legacy cookie or duplicate expected name401.
             Missing/wrong Origin login/PUT/WS403, including other station port and
             unrelated origin. Transport-cookie expiry/proof recovery does not clear other cookies; ordinary restart retains grants.
             Operator bootstrap rotation is explicit profile revoke-all, unlike
             transport rotation/expiry or ordinary restart with unchanged bootstrap.
             Require actual durable revoke-all commit/receipt, then rotation/restart:
             old grants/token401, fresh explicitly authorized enrollment succeeds,
             other three usable. Environment-variable change alone is not commit proof.
             Exact UUID in PUT matches selected profile; wrong
             UUID403, WS numeric correlation IDs retain existing local meaning.
             Check 12.1 login body/rate independently per process, cookie attributes,
             and the shared auth-v1 budget: count setup admissions and independently
             prove10 admitted/11th429 per process without clock/rate changes or polling.
             Preserve existing request/count/deadline bounds;
             only HttpOnly handles and the CL-022-01 nonextractable IndexedDB key persist; no
             local/sessionStorage/profileJSON/retained form/URL/log/report leakage. Failed
             network login also clears DOM token immediately on submission.
             Repeated Cookie headers are checked in the
             separate auth_tests.rs vector, not only a single cookie string.
             Oracle: original cookie/error/identity table and independent inputs;
             trusted same-host processes only, not hostile-host isolation proof. */
    }
    dependency identity004 from sharedBrowserSessions to WstxStationProtocol::'TC-022-004';
    enum def DisplayProfile { enum off; enum thin; enum detail; }
    enum def HttpMethod { enum get; enum mutation; }
    attribute def HttpResponsePolicy {
        attribute cacheControl : String = "no-store";
        attribute corsAllowed : Boolean = false;
        attribute jsonMediaType : String = "application/json";
        doc /* contract 12.6: UTF-8 JSON except raw WAV input. No CORS permission is emitted.
             JSON accepts optional UTF-8 charset as12.5. JSON schemas are exact:
             reject duplicate/unknown/missing keys. */
    }
    attribute def HttpErrorDetail {
        attribute code : ErrorCode;
        attribute 'field' : String[0..0];
        doc /* Exact members code and field. field is JSON null; code is the stable
             declared error code, never reflected request input. */
    }
    attribute def HttpErrorBody {
        attribute error : HttpErrorDetail;
        doc /* Exact UTF-8 wire shape {"error":{"code":"...","field":null}}. */
    }
    calc def OriginAllowed {
        in method : HttpMethod;
        in originHeaderCount : Integer;
        in suppliedOriginEqualsSelectedOrigin : Boolean;
        return allowed : Boolean =
            (method == HttpMethod::get and originHeaderCount == 0) or
            (originHeaderCount == 1 and suppliedOriginEqualsSelectedOrigin);
        doc /* contract 12.6: GET alone permits absent Origin. Every mutation requires
             one exact Origin even on loopback. Repeated Origin is refused. */
    }
    calc def HttpAccessStatus {
        in selectedProfileModeAndKnownRoute : Boolean;
        in originAllowed : Boolean;
        in tls : Boolean;
        in selectedProfileSessionValid : Boolean;
        return status : Integer = if not selectedProfileModeAndKnownRoute ? 404 else
            if not originAllowed ? 403 else
            if tls and not selectedProfileSessionValid ? 401 else 200;
        doc /* Precedence is mode/route, Origin, TLS session, then payload/resource
             checks in HttpValidation. TLS requires its selected profile's session
             on every recording route. 200 means admitted, not a final route result. */
    }
    attribute def HttpValidation {
        attribute selectedProfile : Boolean;
        attribute originAllowed : Boolean;
        attribute authenticated : Boolean;
        attribute responsePolicy : HttpResponsePolicy;
        attribute mediaAllowed : Boolean;
        attribute bodyBounded : Boolean;
        attribute schemaValid : Boolean;
        attribute versionSupported : Boolean;
        attribute sameProfile : Boolean;
        attribute sameBootGeneration : Boolean;
        attribute resourceKnown : Boolean;
        attribute stateAllowed : Boolean;
        doc /* Validation order: mode/route existence; Origin (403 forbidden_origin); TLS auth
             (401 unauthorized); content type/encoding (415 unsupported_media_type); declared or
             observed body bound (413 request_too_large, transport rejection may occur earlier);
             exact JSON/UUID/safe-integer/version schema (400 invalid_request/unsupported_version);
             profile mismatch (403 wrong_profile); boot/generation mismatch (409 state_conflict);
             resource existence (404 not_found); busy/state compatibility (409 busy/invalid_state);
             file structure (422 invalid_recording); supported PCM capability (422 unsupported_audio);
             frame/duration/chunk limit (422 recording_limit); I/O/cleanup (503 storage_unavailable).
             Malformed/missing/duplicate Content-Range is400 invalid_request; incorrect byte offset
             or changed total is409 state_conflict. An import total above the file cap is413
             request_too_large. A stalled/expired import is408 upload_timeout, explicit cancel is409 cancelled on an
             in-flight PUT; completed DELETE still returns200. A missing recording is409 no_recording;
             generation ceiling is409 generation_exhausted. Syntactic UUID errors are400; foreign
             well-formed UUIDs are404 except explicit profile_id mismatch. Errors do not echo input.
             Input progress is bytes received/declared Content-Range total while receiving; before
             the first chunk show awaiting upload rather than a fabricated percent. Validation/commit states are distinct from completed. */
    }
    action def TransferDisplay {
        in 'frame' : SpectrumFrame[0..1];
        in detailedFrame : DetailedSpectrumFrame[0..1];
        in requestedProfile : DisplayProfile;
        doc /* **Opt-in WebSocket extension.** Keep `wstx.v1`, 1024-byte incoming request/frame/message
             limits; outbound Thin/control payloads remain <=1024 bytes, except receive.state (RadioIO). Set the outbound write
             buffer cap to4096 bytes to admit a <=2048-byte Detailed event while reserving a full
             1024-byte control payload and two conservative14-byte framing allowances. Preserve existing station.get/status/error envelopes, validation order,
             binary1003, heartbeats and liveness unchanged. Add exact three-field requests
             `{v:1,type:"recording.get"|"spectrum.thin"|"spectrum.detail"|"spectrum.off",id}`. `recording.get` returns
             `{v:1,type:"recording.state",id,data:{generation,source_id,job_id,state}}` with nullable
             IDs/state; full snapshot stays HTTP. A peer that has chosen a display subscription also
             receives the pushed event without id (WstxStationProtocol::PushedStationState, #10):
             `{v:1,type:"recording.state",data:{generation,source_id,job_id,state,import}}`, `import` null
             or `{id,state,received_bytes,total_bytes,error}` of the running import. It is sent once after
             the first subscription and then only on a change, checked once per second, on every display
             profile including Off; a change of received_bytes alone is sent at most once per
             5 s. It is an optional write that a full socket defers and never loses. The browser sends no
             recording.get: it reads GET /recording once per socket (the snapshot), after its own mutation
             and when the event differs from its snapshot in identity, job state or import identity;
             the rest of the import updates its view without a read. A failed read on a subscribed socket closes
             the socket: an event is sent once and no timer reads, so the reconnect reads again; an upload in progress then stops with its reservation left to cancel. Thin/detail/off acknowledge
             `{v:1,type:"spectrum.subscription",id,data:{profile:"thin"|"detail"|"off"}}`. Selected-profile
             absence returns recoverable `unavailable` for these commands. Every new connection starts
             off; legacy peers receive only existing status/heartbeat messages. New browser obtains
             status/profile/recording HTTP snapshots before opting into the selected profile and showing current
             recording data; unknown_command from an older server visibly disables recording display.
             Default browser selection is Detailed on every origin, including remote HTTPS,
             using existing1024 native bins at3000/1024 = 2.9296875Hz; no FFT/protocol/source
             resolution change. The selector offers
             "Detailed (fast link, up to 10 KiB/s per viewer)", "Thin (32 kbit/s link)" and Off.
             Without a valid saved choice, Detailed is selected. RestoreDisplayChoice resolves the
             origin/profile-specific BrowserDisplayPreference; explicit selector changes use
             SelectDisplayChoice. Only a user choice persists; runtime Thin fallback does not replace it.
             Storage failure/invalid value preserves normal defaults and usable in-memory controls.
             Detailed is explicitly selectable on HTTPS but carries no32 kbit/s promise. A server
             that supports recording/Thin but refuses spectrum.detail with unknown_command triggers
             one Thin subscription and visible "Detailed unavailable; using Thin" feedback. A server
             refusing recording.get/Thin disables recording display visibly as before. Never loop
             retries or replay a mutation. An environment-only server returns unavailable.
             No side effects occur through new WS requests apart from that connection's subscription.

             Only subscribed thin peers receive events
             `{v:1,type:"spectrum.frame",data:{boot_id,source_id,job_id,generation,sequence,first_frame,end_frame,levels}}`.
             IDs are UUIDs, sequence starts0 per replay row and increments even when rows are dropped;
             frame interval is [first_frame,end_frame), with first=12000*sequence, end=min(first+12000,
             source_frames). `levels` is exactly128 integers0..120 under 4.4's frequency/level contract.
             No null/unbounded extension fields. Each encoded event remains<=1024 bytes. No unsolicited
             recording snapshot/status payload change or application compression. Incoming binary still
             closes1003. Obsolete boot/source/job/generation events and callbacks from old sockets are
             ignored. Event loss cannot be used to infer missed decoder results.

             Detailed peers instead receive exactly
             `{v:1,type:"spectrum.detail.frame",data:{boot_id,source_id,job_id,generation,sequence,first_frame,end_frame,levels_b64}}`.
             A live row of a Tx period (#61 CL-061-04) carries "tx": true in data, in Thin and
             Detailed frames alike; the key is absent otherwise, and the browser paints such a
             row as a Tx row RGB(90,20,30), not with its levels; a run of such rows is collapsed to a thin band (CL-061-05).
             The UUID/safe-integer identity rules are unchanged, first=2400*sequence,
             end=min(first+2400,source_frames), sequence0..599. levels_b64 is canonical RFC4648
             standard base64 with padding: exactly1368 ASCII characters decoding to1024 bytes,
             each0..120. Reject wrong alphabet/padding/length/noncanonical pad bits, values>120,
             unknown/missing fields, unsafe/out-of-range sequence/interval or stale identity/socket;
             never render partially accepted data. Every encoded Detailed event is<=2048 UTF-8
             bytes; no binary messages, lossy nibble packing or application compression.
These application-payload and WebSocket exclusions do not prohibit the bounded
HTTP response content coding of12.1.1; no spectrum event is compressed by H1.

             One replaceable pending Thin event per peer and <=1 Thin send per second. #54 (CL-054-01):
             the station retains the last 25 Detailed rows (5 s) of the current job, and each
             Detailed peer receives every retained row after the last one it was sent, oldest
             first: 200 ms apart, 170 ms apart while rows wait (at most 5.9 sends per second,
             within 10 KiB/s), so a processing stall delays rows instead of dropping them; a peer
             further behind than the retained window has a real gap. A new subscription starts at
             the newest row; no replay of old
             frames after reconnect or off. Ready status replies and heartbeats take precedence;
             optional display output never waits in the connection loop and is skipped when send
             readiness/control headroom is unavailable. Its guard enforces event payload <=2048 and
             payload+1024+2*14<=4096; this intentionally replaces the previous996-byte guard, not
             bypasses it. A partially flushed optional write retains the original2s deadline;
             subsequent control output cannot reset or extend that deadline. Switching/off/reconnect
             forgets prior frame cursors and pending replacements; already buffered output remains
             bounded and is rejected by browser profile/identity guards. No old rows are replayed.
             Maintain existing two-second write deadline and bounded peer removal. Browser schedules
             at most one pending repaint and bounds history as in4.4. In normal operation two Thin
             clients stay within WstxStationProtocol::ThinLinkBudget, judged from the link byte log
             (#80); a recording replay or import carries no link budget. Browser sends one
             <=2048-byte chunk and waits for its response before the next. No completion-time
             promise is made for bulk import. Reconnection resets subscription and refreshes snapshots,
             never resumes or retries a mutation implicitly. */
    }
    action transfer : TransferDisplay;
    dependency transferOwner from transfer to WstxArchitecture::physicalStation::backend::stations::web;
    requirement 'CL-003-03' {
        doc /* The server MUST validate request structure, protocol version, command and message size in the contract's order. Rejected input MUST follow the defined error/close behavior; recoverable errors MUST leave the server available without exposing internal details. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs; client/app.js";
    }
    dependency CL_003_03_to_FR_021 from 'CL-003-03' to 'FR-021';
    requirement 'CL-003-06' {
        doc /* Application output buffering and active connections MUST have explicit bounds (WstxStationProtocol::Limits; design bounds, checked by review). A peer that stops answering (no Pong for more than 15 s) MUST be removed at the next heartbeat tick, without delaying another client's status requests (#80: the one liveness case that matters in normal operation, a browser that vanishes without closing). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs; client/app.js";
    }
    dependency CL_003_06_to_FR_021 from 'CL-003-06' to 'FR-021';
    verification 'TC-021-005' {
        doc /* #### TC-021-005 — Message exchange and invalid-input handling

             **Clauses:** CL-003-02, CL-003-03. **Level:** 2 — Isolated automated tests.
             **Where it runs:** Windows PC, actual candidate Rust server on a temporary loopback
             port, independent WebSocket test peer; the parser examples also run as Rust unit tests.

             **Inputs/actions and expected results:**

             1. Send the contract's valid station.get example. Expect the specified station.status
                envelope, matching ID, candidate package version, radio state unconfigured and
                the ClientBuild (#51) computed independently from the client files; the page
                carries the same build.
             2. Send different request IDs through two concurrent connections. Expect each response
                on its originating connection with its own ID and authoritative state.
             3. Send malformed JSON, a non-object, unknown command, unsupported version, missing ID,
                wrong ID type, out-of-range ID, invalid type field and an extra field. Expect the
                contract's error for each input. A request combining an unsupported version with an
                invalid type MUST follow shape-before-version validation. A valid peer MUST remain usable.
             4. Send a valid request padded to the message-size boundary. Expect its normal response.
                Exceed the boundary by one byte and expect transport rejection/closure while the other
                peer remains usable. Send a binary frame and expect the specified close behavior.

             **Oracle:** hand-authored contract examples, candidate version and
             [message/error rules](StationProtocol.sysml).
             **Executable trace:** [communication.test.cjs](../../../../tests/communication.test.cjs),
             `TC-021-005: actual-server correlation, negative cases and size boundaries`;
             [protocol_tests.rs](../../../../server/src/protocol_tests.rs),
             `protocol_returns_specified_response_and_errors`. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-003-02';
            verify 'CL-003-03';
        }
        attribute executable : String = "tests/communication.test.cjs; server/src/protocol_tests.rs";
    }
    verification 'TC-021-008' {
        doc /* #### TC-021-008 — Dead peer removal

             **Clauses:** CL-003-02, CL-003-06. **Promise:** FR-021. **Level:** 2 — Isolated automated tests.
             **Where it runs:** Windows PC, the actual router in the test process; the connection loop's
             clock is the runtime's and the test drives it (no real wait); the test holds each peer's
             transport; the connections run without authorization (plaintext loopback). #80 (operator 2026-11-09): the 32 kbit/s budget variant and the real-time
             stalled-reader variant are retired; the link budget is judged from the link byte log
             (TC-080-001); the write and flush deadlines are design bounds checked by review.

             **Inputs/actions and expected results:**

             1. Peer A subscribes Thin, then neither reads nor answers Ping; its transport keeps
                accepting writes (a vanished browser behind a kernel buffer). Expect A closed with
                reason "no pong for 15 s" at the first heartbeat tick more than 15 s after its last
                Pong (driven time in (15 s, 20 s]), never earlier.
             2. Peer B sends station.get every 5 s throughout. Expect each answered within 2 s, and
                B usable after A's removal.
             3. Control: a peer answering every Ping stays open through 60 s of driven time.

             **Oracle:** Limits stalePongMs 15000 and heartbeatMs 5000 and the Heartbeat rule
             ("on the next heartbeat tick, >15 s without Pong disconnects that peer") in the
             [liveness rules](StationProtocol.sysml). Removing the Pong check (#70 mutation M8)
             must turn case 1 red. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-003-02';
            verify 'CL-003-06';
            verify 'FR-021';
        }
        attribute executable : String = "server/src/liveness_tests.rs";
    }
    dependency CL_003_03_verified_by_TC_021_005 from 'CL-003-03' to 'TC-021-005';
    dependency CL_003_06_verified_by_TC_021_008 from 'CL-003-06' to 'TC-021-008';

    // #51 An open page recovers after a station update (chosen defaults: WstxStationProtocol::PageUpdate).
    requirement 'CL-051-01' {
        doc /* The station identifies the browser client it serves with WstxStationProtocol::ClientBuild: the first 16 lower-case hex digits of the SHA-256 over its served client files in route order. The served page carries it as body data-build and every station.status reply carries it as data.build (data exactly {version, radio, build}). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs";
    }
    dependency CL_051_01_to_FR_021 from 'CL-051-01' to 'FR-021';
    dependency CL_051_01_verified_by_TC_051_001 from 'CL-051-01' to 'TC-051-001';
    dependency CL_051_01_verified_by_TC_051_003 from 'CL-051-01' to 'TC-051-003';
    requirement 'CL-003-01' {
        doc /* The Rust server MUST serve the HTML/CSS/JavaScript operator client. The browser MUST visibly show server version, connection state and an unconfigured radio. Refresh status MUST request a fresh snapshot and update the displayed last-update time. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs; client/app.js";
    }
    dependency CL_003_01_to_FR_019 from 'CL-003-01' to 'FR-019';
    dependency CL_003_01_to_FR_021 from 'CL-003-01' to 'FR-021';
    requirement 'CL-003-02' {
        doc /* Each browser MUST use one versioned WebSocket connection for status requests and responses. The server MUST echo each request ID on the requesting connection and return authoritative version/radio state. Concurrent clients MUST remain independent. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs; client/app.js";
    }
    dependency CL_003_02_to_FR_021 from 'CL-003-02' to 'FR-021';
    requirement 'CL-003-07' {
        doc /* Remote access MUST use the contract's authenticated TLS path and exact Origin validation. The browser MUST offer token login, and invalid or oversized login requests MUST be refused. Insecure remote startup and invalid access settings MUST fail closed. Explicit loopback development MAY remain unauthenticated. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs; client/app.js";
    }
    dependency CL_003_07_to_FR_021 from 'CL-003-07' to 'FR-021';
    requirement 'CL-003-08' {
        doc /* Status MUST use initial/reconnection snapshots, explicit refresh requests and event-driven updates when state changes exist. The client MUST avoid constant status polling and tolerate protocol heartbeats between responses. The initial profile MUST carry no raw audio or spectrum stream and use no application payload codec or negotiated WebSocket compression. Bounded negotiated HTTP content coding is permitted only by12.1.1. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs; client/app.js";
    }
    dependency CL_003_08_to_FR_019 from 'CL-003-08' to 'FR-019';
    dependency CL_003_08_to_FR_021 from 'CL-003-08' to 'FR-021';
    requirement 'CL-005-03' {
        doc /* Profile lifecycle, revision, configuration and authenticated sessions MUST be independent, including one browser cookie store on one hostname with distinct TLS ports. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; client/app.js";
    }
    dependency CL_005_03_to_FR_019 from 'CL-005-03' to 'FR-019';
    dependency CL_005_03_to_FR_021 from 'CL-005-03' to 'FR-021';
    dependency CL_005_03_to_FR_022 from 'CL-005-03' to 'FR-022';
    verification 'TC-021-006' {
        doc /* #### TC-021-006 — Actual browser interface

             **Clauses:** CL-003-01, CL-003-04. **Promises:** FR-019, FR-021.
             **Level:** 2 — Isolated automated tests.
             **Where it runs:** Windows PC, automated Chromium with fresh independent browser
             contexts connected to the locally started candidate server.

             **Inputs/actions and expected results:**

             1. Navigate to the station page. Expect the required HTML, JavaScript and CSS to load
                successfully, no uncaught page errors, and visible Connected state, candidate version
                and Radio not configured text.
             2. Open a second independent browser context. Expect the same authoritative version
                and radio state in both clients.
             3. Capture the desktop view and a 360-pixel-wide view. Expect no horizontal overflow;
                inspect the screenshots for readable status, login/refresh controls and responsive layout.
             4. Stop the actual server. Expect the page to mark its last state stale/disconnected.

             **Oracle:** visible functions in CL-003-01/04 and package version, not a golden image
             generated by the implementation. **Executable trace:**
             [communication.test.cjs](../../../../tests/communication.test.cjs),
             `TC-021-006: real browser, two clients, desktop and mobile layout`.
             Screenshots are `test-results/station-desktop.png` and `test-results/station-mobile.png`. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-003-01';
            verify 'CL-003-04';
            verify 'FR-019';
            verify 'FR-021';
        }
        attribute executable : String = "tests/communication.test.cjs";
    }
    verification 'TC-021-009' {
        doc /* #### TC-021-009 — Remote access boundary

             **Clause:** CL-003-07. **Promise:** FR-021.
             **Level:** 2 — Isolated automated tests.
             **Where it runs:** Windows PC, candidate server, real browser and independent peers
             using a disposable local TLS certificate, test token and configured allowed Origin.

             **Inputs/actions and expected results:**

             1. Open the TLS page and submit the valid test token through its login form. Expect an
                authenticated status exchange and the contract's protected cookie attributes.
             2. Attempt WebSocket upgrade with absent/invalid credentials and, separately, a
                disallowed Origin. Expect the specified denial before station data is returned.
             3. Submit login with missing/disallowed Origin. Expect refusal. Submit an invalid token
                body at the HTTP body limit and one byte beyond; expect authentication refusal for
                the former and size rejection for the latter. Exhaust the login-attempt budget and
                expect the contract's rate-limit response.
             4. Attempt plaintext access to the TLS listener. Expect refusal and no plaintext
                station response.
             5. Attempt non-loopback startup with required TLS, token or explicit Origin missing;
                plaintext token configuration; and an Origin containing a path. Expect startup failure.
                The explicit loopback development fixture remains limited to its configured loopback address.

             **Oracle:** [access and startup contract](StationProtocol.sysml),
             HTTP/upgrade outcomes and protected cookie attributes. **Executable trace:**
             [communication.test.cjs](../../../../tests/communication.test.cjs),
             `TC-021-009: TLS login, unauthorized/origin denial, plaintext refusal`. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-003-07';
            verify 'FR-021';
        }
        attribute executable : String = "tests/communication.test.cjs";
    }
    verification 'TC-022-004' {
        doc /* #### TC-022-004 — Multi-instance authentication in one browser profile

             **Promises:** FR-019, FR-021, FR-022; CL-005-03, CL-005-04.
             **Level:** 2 — isolated automated tests. **Where:** Windows PC, N real disposable TLS
             listeners on **localhost**, different ports/tokens, N windows in **one browser context**.
             Independent contexts do not satisfy this case; tests never contact an external service.

             **Steps:** Before login request GET/PUT /profile and WebSocket upgrade without a cookie.
             Fresh selected authorization at each station is session204, bootstrap-scope200
             with non-null migrated scope, completed storage of key/grant/enrollment operation
             IDs BEFORE enroll200, then challenge/proof204/status200. Session204 alone is not
             ordinary permission. Initial migration assigns identity to existing selection even
             with disabled control, but creates no grant/commission or native effects; a
             null scope cannot be invented. Fetch GET `/profile` using
             ordinary same-origin browser fetch with no manually supplied Origin and require200.
             Inspect cookie names/attributes only, then Refresh/reconnect every window. Repeat
             retained authorization in reverse order with proof/status, no token or enrollment
             replay. Copy station
             1's token to station 2's login, cookie name/value to station 2's upgrade and /profile
             requests, and station 1's session value under station 2's expected cookie name. Supply
             a legacy `wstx_session` cookie and duplicate expected-name cookies. Exercise missing/
             wrong Origin on login, PUT and upgrade, including another station's port and an unrelated
             origin. Operator bootstrap rotation is explicit profile revoke-all, unlike
             transport-handle rotation/expiry or ordinary restart with unchanged bootstrap.
             Require actual durable revoke-all commit/receipt for profile1, then rotate its
             bootstrap token and restart; an environment-variable change alone is not proof;
             query other stations throughout. Run local and cross-station negatives with the same
             four-server fixture. Exercise namespaced transport-cookie expiry and automatic retained-key proof recovery without clearing others; ordinary restart does not revoke grants.

             **Delivered amendment:** the companion converts rotation to the actual revoke-all receipt then restart with a new token; the rejected browser makes no automatic retry, uses Forget to re-enroll with the new token, and Log out deletes its key/cookie while other profiles stay usable. Only setup calls count against the 10/60 budget (enrollment 3 admissions, retained proof none).

             **Oracle/outcome:** Exactly one expected namespaced session per logged-in UUID exists
             with the 12.1 attributes and no Domain attribute. All independent sessions survive other
             ports' logins/reconnects. Missing/wrong/duplicated/cross-profile cookies yield 401; wrong
             Origin yields 403 before credentials or settings are accepted. Wrong-station token login
             returns 401. Only the HttpOnly transport cookie and CL-022-01 nonextractable IndexedDB signing key are permitted browser-persisted credentials. No secret appears in localStorage/sessionStorage, profile JSON, retained
             form/page state after login submission, URLs, stdout or test reports. Reports inspect
             cookie names/attributes only; the test may transfer values internally for negative cases.
             The explicitly revoked profile1 grant and old bootstrap token are refused; fresh enrollment with its new token succeeds while other profiles keep working. Ordinary restart preserves unrevoked grants. Exact-own-Origin authenticated saves succeed only
             at their selected profile, and a different profile's UUID in the HTTP PUT body's
             `profile_id` is denied. Numeric WebSocket correlation IDs retain 12.2's unchanged
             connection-local meaning and are not profile identities. Verify 12.1's body
             and per-process rate limits independently of other profiles. Count actual auth-v1
             setup admissions (session/bootstrap-scope/enroll) under the10/60 budget and prove10 admitted/11th429 per
             process in bounded fixture subcases; no production clock/rate switch, status poll
             stream, relaxed deadline or omitted companion. Same-host cookie transport
             is explicitly observed; it is not proof against a hostile service on that hostname. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-005-03';
            verify 'CL-005-04';
            verify 'FR-019';
            verify 'FR-021';
            verify 'FR-022';
        }
        attribute executable : String = "tests/profiles.test.cjs; server/src/auth_tests.rs";
    }
    verification 'TC-009-005' {
        doc /* #### TC-009-005 — Coherent receive operating controls

             Proves CL-003-08, CL-008-03/05/07 and CL-010-05/07/08. Cost2, isolated Windows development PC:
             actual station/receive manager, converter, decoder, HTTPS API and Chromium, independent
             native/CI-V fixtures and TLS (no 32 kbit/s link, #80). This is planned coverage,
             not an execution verdict. TC-009-002 remains the separate authorized cost4 physical
             IC-7300/browser readback check. All existing cases remain required.

             1. From a validated stopped snapshot, the explicit receive start (Expert, or the
                Receive stopped chip; #37 removed Monitor/Stop from the operating screen) uses
                the existing Start, and the explicit stop cancels the exact running tuple. Hold native close and inject failed
                close: Start stays blocked until real release. Start uses the operating FT8/FT4 selection;
                there is no separate Next receive mode control. Retain partial latest-period rows after Stop,
                clear on a fresh identity. Unsupported/invalid audio, CAT-disabled, stale snapshot,
                lost response, pre-intent read and reconnect cases never create a second owner,
                implicit input selection, automatic restart or mutation retry; reconnects,
                status refreshes, readiness events and a second tab send no receive start, stop
                or selection by themselves (#37 guard). Keyboard/360px/200% text retains
                accessible receive state and persistent unsupported Halt Tx.
             2. Use the complete4.7.5 table as fixed independent integer truth. Test every admitted
                preferred band/mode plus missing160m/4m FT4, backend range edges and wrong enum.
                Expect20m14074000/14080000 and40m7074000/7047500. Cold unknown band/nominal mode
                selection returns409select_band_first with zero revision/device/stop/start effects;
                fresh unique exact readback can resolve the explicit mode, stale/off-grid cannot.
                Manual Monitor-off→band and off→mode start the actual new receive mode without CAT;
                a fixed independently known native FT4/FT8 payload traverses the real pipeline and
                appears literally in the browser. No positive mock decoder or fabricated rows.
             3. Independent fragmented CI-V replies prove ReadRxTx RX, exact ReceiveSetup and final
                per-field readback. ACK, echo, foreign/broadcast/stale reply and unrelated query do
                not refresh another field. Verify original timestamps remain, connection replacement
                clears facts, and partial setter failures mark all possibly touched facts unconfirmed.
                Mismatch,NG,timeout,busy alias,unverified receive-only and configured-unavailable CAT
                refuse truthfully with no automatic manual fallback, replay or restoring writes.
             4. Hold old worker/release, then release or fail it: no setters/new input before actual
                release. Inject CAT-applied/audio-start failure, Stop before/after sent writes,
                profile edit and late setup/page/old job callback. Expect exactly4.7.5 lifecycle,
                unchanged250ms/2s bounds, fresh context and no cross-retune windows or stale restart.
             5. Exercise each12.8.1 request union: missing/unknown/duplicate keys, malformed UUID,
                enums,1024/1025 bytes, required media/Origin/auth/profile/boot/revision/generation,
                safe counter maximum/one-over and exhaustion. Refusals occur before device effects.
                Build maximum valid receipt/snapshot/metadata shapes and check384/3072/4096 byte
                caps without truncation. Two authenticated browsers racing commands admit one.
             6. Delay the original POST body until after an empty GET: that GET cannot clear the
                unknown barrier. An explicit unseen-command fence increments revision, returns
                phase cancelled and cancellation.result=fenced, creates no normal operation, and
                causes delayed old POST refusal. Same cancel replay returns200 without effects;
                changed body with retained ID conflicts. Before/after-job target cancellation may
                stop only its own current tuple; superseded target cannot stop a later job. Old
                boot/pre-intent reads never clear newer intent. Test profile edit/intervening fence.
             7. New server/old strict client keeps all old shapes; old server/new client disables
                only unsupported operating controls. Invalid schema/identity is stale/error, never
                manual fallback. Include the pushed selection.state (WstxOperatingReceive::SelectionStateEvent),
                normal receive/results/status, mode/band traffic, stalls and explicit Stop
                in a two-browser workload on an unshaped TLS connection (#80, operator 2026-11-09:
                CAT and selection tests run off the 32 kbit/s link; its budget is judged from the
                link byte log, TC-080-001). Assert one pending selection read/ordinary mutation.
                Without a timer read: the first selection.state of a socket
                holds what GET /receive/selection gives, a later one the changed fields (at most 2048 B,
                at most one per second), a change from outside shown with no read, and the radio
                facts' new dates alone at most every 2 s on Detailed and every 30 s below it.

                Read evidence classifies each selection read using recorded CDP initiators and the
                caller mapping derived from the served client source (its single selection fetch, every
                caller explicit; a caller inside a timer, a missing, ambiguous or unmapped site refuses),
                joined to validated responses. In EACH Thin/Off window a browser makes at
                most one selection read per operator gesture, and each command's pending state is
                seen by at least one browser through an event or a read; each browser ends holding the
                command's result. Missing coverage fails rather than fabricating pending values or
                forcing a legal short command to last longer. Frozen negative controls refuse a timer
                caller, an unknown stack and a lost or doubled fetch. Preserve all five CQ contexts and
                two transitions/window; each window is as long as its gestures need; no product
                delay or padding.

                A Thin or Off window that fails prints in the test output, for each browser:
                - every socket with its open and close times;
                - each stale event with its path label, the page's silence, pending deferred
                  download, socket state and authorization state;
                - the frames received in the 12000 ms up to and including each close.
                For every socket the station ended, it prints the station's reason, begin and end
                times, last heartbeat write and longest heartbeat interval (from the begin; earliest
                on a tie). All times are UTC milliseconds of the one machine; station times are the
                begin's UTC plus the runtime clock's elapsed time. This is failure evidence, not a
                pass condition.

             8. Bounded HTTP content coding12.1.1 (same cost2 boundary):
                A. Real application/router + normal TLS/session: authenticate once through existing /session; for each allowlisted successful GET gzip decode must equal identity logical JSON exactly on immutable state, exact shape/caps preserved. Use independent standard decoder (Node zlib) and assert actual raw gzip magic/header/trailer + body rather than fetch auto-decoded size. Check Content-Type/Vary/Content-Length correctness; existing Vary/cache/security headers retained. Mutable facts compare frozen fixture context, never pretend two temporally distinct snapshots must match timestamps.
                B. Table: absent/empty, identity, gzip, GZip case-insensitivity, gzip;q=0, gzip;q=0.5 vs identity;q=1, identity;q=0 with gzip acceptable, br-only, wildcard and explicit exclusions, invalid q/token/multiple header instances. Expected outcomes are frozen in the ordered12.1.1 negotiation table from the pinned source; malformed headers must follow the frozen ordered12.1.1 negotiation table without panic/leak; duplicate/wildcard selection follows the exact table, not a blanket last-q or any-q0 rule. Both gzip+identity explicitly forbidden=>406 only eligible successful GET. Preserve original401/403/404/400/409/500 on excluded error paths even with forbidden encodings. Every row of the frozen ordered table runs through the product's own response encoder (http_compression::encode_response) on an eligible successful JSON GET, never through a bare library layer (#71).
                C. Every excluded method/path including POST/session, PUT/profile, POST/receive/select and /radio operations remains unencoded and byte/schema compatible; no duplicate mutation effects. Authenticate cookies/tokens never appear in body/debug logs. Authenticated eligible snapshots contain no credential fields; malicious literal decoded text is unchanged. Oversized logical result rejected/capped BEFORE gzip, encoded size cannot admit extra rows; valid max logical result still decodes within original cap. Request Content-Encoding:gzip must not add support or bypass request body limit. HEAD/no-body/range/already-encoded cases must not be double-compressed or misframed.
                D. Retired by #80 (operator 2026-11-09): content coding is not measured on the
                32 kbit/s link; identity path correctness stays mandatory (A-C).
                Include tiny `{}` (2bytes) with `identity;q=0,gzip`; selected gzip must encode
                it despite a default library minimum-size predicate. HEAD/204/304/range/already-
                encoded responses bypass negotiation even when all encodings are forbidden.
                Preserve Vary fields `[Origin,X-Accept-Encoding-Other]` and append the exact
                Accept-Encoding token; existing case-insensitive exact token and Vary:* remain.
                Preserve security/cache headers. Every table row retains actual multiheader order.
                Unknown/excess serialized size on an otherwise eligible success returns the existing
                bounded503snapshot_limit before negotiation even with all encodings forbidden; verify
                each route own logical cap, no body polling/buffering/redispatch, and retained security headers.

             Independent oracles are the pinned source/table and observed default flow, manually
             derived CI-V exchanges, independently fixed waveform payloads, exact wire schemas and
             the pre-existing lifecycle/identity/resource bounds. Expected records are not derived
             from candidate output. Placement: wstx-rust typed/control/receive tests, protocol and
             live-browser/profile regressions, recording-thin encrypted transport tests and layout
             accessibility cases; additive wiring must preserve every existing suite and assertion.
             Physical TC-009-002 checks actual receive-only settings, numeric width/notches/PBT
             independently when available, physical frequency/USB/DATA/FIL versus browser facts,
             mode/band changes and Stop, with verified restoration. A quiet band is not fabricated
             as successful decoding; fixture proof and actual RF observations are labelled separately. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-003-08';
            verify 'CL-008-03';
            verify 'CL-008-05';
            verify 'CL-008-07';
            verify 'CL-010-05';
            verify 'CL-010-07';
            verify 'CL-010-08';
        }
        attribute executable : String = "tests/radio-selection.test.cjs; server/src/selection_http_tests.rs; server/src/http_compression_tests.rs; server/src/recording_tests.rs; server/tests/radio_control.rs; tests/contact.test.cjs; tests/recording.test.cjs; tests/ui-operating.test.cjs";
    }

    // Reciprocal ownership is verification intent, not an execution verdict.
    dependency CL_003_01_verified_by_TC_021_006 from 'CL-003-01' to 'TC-021-006';
    dependency CL_003_02_verified_by_TC_021_005 from 'CL-003-02' to 'TC-021-005';
    dependency CL_003_02_verified_by_TC_021_008 from 'CL-003-02' to 'TC-021-008';
    dependency CL_003_07_verified_by_TC_021_009 from 'CL-003-07' to 'TC-021-009';
    dependency CL_003_08_verified_by_TC_009_005 from 'CL-003-08' to 'TC-009-005';
    dependency CL_003_08_verified_by_TC_021_007 from 'CL-003-08' to 'TC-021-007';
    dependency CL_005_03_verified_by_TC_022_001 from 'CL-005-03' to 'TC-022-001';
    dependency CL_005_03_verified_by_TC_022_003 from 'CL-005-03' to 'TC-022-003';
    dependency CL_005_03_verified_by_TC_022_004 from 'CL-005-03' to 'TC-022-004';
    dependency CL_005_03_verified_by_TC_022_005 from 'CL-005-03' to 'TC-022-005';
    requirement 'CL-022-02' {
        doc /* SelectedRadioId is a station-assigned random UUID persisted with the
             selected radio configuration, separate from profile UUID, COM endpoint,
             browser identity, boot/generation and radio-model label. Existing station
             authority alone owns it; audio/CAT adapters refer to that same identity.
             Initial migration assigns one UUID to the existing selected configuration,
             but creates NO authorization grant or commissioning acknowledgement.
             Operator decision 2026-11-06 (#22): no explicit radio identity
             Add/Replace/Remove operation exists. Automatic discovery of an available
             transmitter is requested on #44 and is not delivered or promised by this
             clause. Fresh
             bootstrap alone grants no control: ReadBootstrapScope provides its read-only
             authority tuple before enrollment. Disable/re-enable never removes or
             changes identity. Endpoint/model/PTT edits
             preserve selected UUID but increment SafetyConfigurationRevision and
             invalidate commissioning; they cannot make a newly configured device
             usable until explicit re-commissioning. Endpoint reversion also needs
             re-commissioning. USB disappearance/reappearance at unchanged configured
             endpoint does not change UUID/revision. No claim of cryptographic hardware
             identification: substituted hardware at the same endpoint is within the
             existing trusted operator physical-configuration boundary. Radio identity
             here is the selected configured asset, not an inferred COM3 hardware ID.

             Durable store is one versioned atomic record per profile under
             its existing private OS-protected service data, separate from public
             profile JSON: radio identities/revisions, commissioning record, grant
             public verifiers/IDs and revocation generation. No private browser key
             or bootstrap token is persisted there by this change. Existing atomic
             acknowledged-write protocol and OS ACL boundary apply; no new database
             service or shared writer. Enrollment/revocation/commissioning success is
             acknowledged only after durable commit. Corrupt/unreadable/unwritable
             store fails closed with explicit reason; never synthesize empty/default
             authorization. Uncommitted enrollment is unusable after restart.
             A durably committed enrollment whose success response was lost remains
             retained after restart; response delivery is not a server-observable
             commit condition. Its browser remains unauthorized/unknown and queues
             no CAT effects until read-only reconciliation of the same enrollment
             operation ID proves the committed tuple/verifier and completes scoped
             proof recovery. Do not replay enrollment or infer success from status.

             Logout revokes this browser grant for the selected tuple and deletes its
             matching cookie/key only after reconciliation; other browser grants and
             other radios/profiles remain usable. Explicit Revoke all for this radio
             deletes all matching verifiers and increments durable generation.
             Bootstrap rotation is an explicit operator revoke-all operation for this
             profile; ordinary restart neither rotates bootstrap nor revokes grants.
             Removing a radio deletes its verifiers; recreating it assigns a new UUID.
             Deleted verifier IDs never become valid by renewal; re-enrollment needs
             fresh bootstrap authorization. No unbounded revoked-ID tombstone list:
             unknown/deleted grant ID always rejects, including old cookies/signatures.

             Station authority serializes grant validation and protected-effect
             dispatch with selection/revocation transitions. The revocation commit is
             the linearization point: effects whose request has not passed the locked
             admission check before it are rejected (see accepted bound below for an
             admitted request still in flight); already-dispatched I/O cannot be retroactively undone and is
             cancelled using existing acknowledged-release rules without unsafe replay.
             Existing affected sockets close and new HTTP/WS effects fail. Revocation
             write failure quarantines affected access in memory immediately, reports
             NOT durably revoked, and requires successful retry before acknowledgement;
             restart can restore the last committed grant, which UI must disclose.
             Lost acknowledgement uses idempotent operation ID and read-only receipt
             reconciliation; no blind new enrollment or mutation replay. If response
             reconciliation is unavailable, browser stays unauthorized/unknown until
             resolved. Server restart reloads only committed state.
             Delivered: durable record, logout/revoke-all, a locked admission check of
             every operating HTTP route and WS upgrade, WS-message rechecks of an earlier
             admitted grant, safety-revision advance and the commissioning server API.
             Accepted bound: an operating HTTP request is admitted by validating its
             transport (scope, grant, current revocation generation) under the authority
             lock; the lock is then released. Such an admitted request may still be
             queued (body parsing, the recording/native owner lock, the blocking pool)
             when a revocation commits. It is not re-checked, refused or undone: at most
             one in-flight effect per admitted request follows, under the existing
             cancellation/release rules. Every request admitted after the commit is
             refused, and the affected WS closes before its next message. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/authorization.rs; server/src/authorization_http.rs; server/src/recording_http.rs; server/src/main.rs";
    }
    dependency CL_022_02_to_FR_019 from 'CL-022-02' to 'FR-019';
    dependency CL_022_02_to_FR_021 from 'CL-022-02' to 'FR-021';
    dependency CL_022_02_to_FR_022 from 'CL-022-02' to 'FR-022';
    requirement 'CL-022-05' {
        doc /* Session, CAT and audio/decoder health remain distinct current observations. HTTP401 marks
             session authorization unavailable within existing<=2s visible-status
             acceptance even if WS still open; retained key proof may recover it.
             Show proof retry/revocation/lost credential/persistence failure distinctly.
             CAT waiting/connecting/retry/unavailable/quarantined never labels retained
             frequency fresh. Audio/decoder state remains separate. No new status poll
             stream; reuse versioned status publication/heartbeat. Its status reads and
             recovery are not part of a 32 kbit/s link test; their bytes appear in the link
             byte log (CL-003-05; #80, operator 2026-11-09). Issue10 existing
             continuity/stale fixes are reused; this proposal adds no duplicate helper.
             The freeze is accepted on the recorded trace (6622256637).
             Delivered: POST /authorization/v1/status reports the actual lifecycle
             condition, mapped error and retry delay, with receive_state separate; the
             browser reads it only when the versioned /receive/selection
             snapshot_sequence changes or after a confirmation (no own timer) and
             shows session, CAT and audio/decoder separately. A retained frequency is
             labelled stale/unconfirmed unless the WS is connected and its fact is
             confirmed in ready. The lifecycle reports a serial open refused because
             the port is held (Windows access denied or sharing violation, or another
             station's ownership lock; also the rare ambiguous case of two serial
             interfaces with the same port name) as error port_in_use, and the browser names it
             '<port> in use by another program' (for example 'COM3 in use by another
             program'); other unavailable causes keep radio_unavailable. The Thin/Off
             accounted-traffic companion once planned here is retired (#80). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/authorization_http.rs; client/recording.js; client/authorization.js; client/app.js";
    }
    dependency CL_022_05_to_FR_003 from 'CL-022-05' to 'FR-003';
    dependency CL_022_05_to_FR_010 from 'CL-022-05' to 'FR-010';
    dependency CL_022_05_to_FR_021 from 'CL-022-05' to 'FR-021';
    dependency CL_022_02_verified_by_TC_022_006 from 'CL-022-02' to 'TC-022-006';
    // TC-022-007 retired (operator 2026-11-06, radio identity Add/Replace/Remove dropped, #22);
    // its revocation and configuration-edit cases moved to TC-022-006. The identity is not reused.
    verification 'TC-022-008' {
        doc /* TC-022-008 CL-022-05 cost2 actual TLS browser. Preserve original missing-cookie/
             openWS reproduction and held-old-response cases; prove401 invalidation and
             proof recovery with independent network observations. Actual same-origin
             browser POST /authorization/v1/status sends only {version:1}; independently
             observe its automatically supplied exact Origin and current-grant200, with
             no identity/session/native effects. Independent TLS peer missing/wrong
             Origin403 before auth, invalid grant401, extra/duplicate/missing fields400,
             wrong media415,1025bytes413; GETnewstatus405/no effects/no fallback. Existing
             GET/profile permits absent Origin as before, not a relaxed POST policy.
             The real freeze
             is accepted on the recorded trace (6622256637). Existing issue10 barriers/unknown
             state assertions remain. The once planned Thin/Off accounted-traffic companion is
             retired (#80, operator 2026-11-09: no 32 kbit/s link test; the link byte log shows
             these bytes). Automated: tests/profiles.test.cjs TC-022-008 (the original freeze
             reproduction: transport cookie lost under an OPEN WebSocket without
             reload; the 401 read ends 'Connected' within2s, retained-key proof
             reconnects with one OPEN socket and zero token/session/enrollment, every
             status read is POST {"version":1} with the exact page Origin) and
             server/src/auth_tests.rs (status GET405, wrong and missing Origin403
             before auth, strict body/media/size refusals, unknown transport401). */
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/profiles.test.cjs; server/src/auth_tests.rs";
        objective {
            verify 'CL-022-05';
        }
    }
    dependency CL_022_05_verified_by_TC_022_008 from 'CL-022-05' to 'TC-022-008';
    dependency CL_022_02_verified_by_TC_022_010 from 'CL-022-02' to 'TC-022-010';
    dependency CL_022_05_verified_by_TC_022_010 from 'CL-022-05' to 'TC-022-010';
    verification 'TC-051-001' {
        doc /* TC-051-001 — An open page reloads after a station update and receives again
             CL-051-01, CL-051-02
             Setup: actual candidate server on a disposable profile and Chromium at 1366x768; browser storage theme day and waterfall speed 4; a WebSocket proxy (Playwright routeWebSocket) forwards every message and, after the restart, rewrites the build of one station.status to 0123456789abcdef, standing for the updated station. The communication suite computes the build independently (Node SHA-256 over the client files on disk).
             Steps: read the page's data-build; reconnect; stop the server and start it again on the same profile; wait for the page; let a later status of the same rewritten build arrive.
             Expected: the page build is 16 hex digits and equals the status build of the unchanged station (no reload); after the restart exactly one reload, a new boot id, the receive snapshot of the new station accepted, theme day and speed 4 kept, the tab's session storage names the build; the second mismatch for the same build shows "Station updated · reload" with no second reload. The status envelope is {version 0.1.0, radio unconfigured, build}.
             2 — Isolated automated functional tests; Windows development PC, loopback only. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-051-01';
            verify 'CL-051-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs; tests/communication.test.cjs; server/src/protocol_tests.rs";
    }
    verification 'TC-051-003' {
        doc /* TC-051-003 — Live update with the operating page open
             CL-051-01, CL-051-02
             Setup: HB9BLA running a build of this CR or later, the operator's page open and receiving, no QSO in progress.
             Steps: install a later candidate whose client differs, with the page open.
             Expected: the page reloads by itself and the waterfall moves again within about 10 s of the station's restart; browser settings kept.
             3 — Live, read-only on the station; run at CR acceptance with the operator. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-051-01';
            verify 'CL-051-02';
        }
    }

    // #33 The station reports its own source commit, for the independent post-install probe.
    requirement 'CL-033-01' {
        doc /* Every response to GET / carries exactly one header x-wstx-source-commit: the 40 lower-case hex digits of the source commit the executable was built from (compile-time WSTX_SOURCE_COMMIT), or unknown when the build had none or a value of any other form. It needs no authentication; station.status and the served page body are unchanged. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs";
    }
    dependency CL_033_01_to_FR_021 from 'CL-033-01' to 'FR-021';
    verification 'TC-033-001' {
        doc /* TC-033-001 — The served page reports the build's source commit
             CL-033-01
             Setup: the router of the test build with no selected profile; the source-commit validation called directly.
             Steps: GET / through the router; validate a 40-digit lower-case commit, none, an empty, a short, an upper-case, a CR/LF-terminated and a 41-digit value.
             Expected: exactly one x-wstx-source-commit header, equal to the test build's own WSTX_SOURCE_COMMIT when it is 40 lower-case hex and unknown otherwise; the valid commit is reported unchanged and every other value as unknown.
             2 — Isolated automated functional tests; Windows development PC, no network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-033-01';
        }
        attribute executable : String = "server/src/protocol_tests.rs";
    }
    dependency CL_033_01_verified_by_TC_033_001 from 'CL-033-01' to 'TC-033-001';
}
