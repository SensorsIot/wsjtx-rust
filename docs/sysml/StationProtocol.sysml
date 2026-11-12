package WstxStationProtocol {
    private import ScalarValues::*;
    doc /* Canonical status, authentication and transport contract. Profile, recording,
         live receive and display extensions refine this shared boundary in WstxProfiles,
         WstxRecordingReceive WstxRadioIO and WstxOperatingReceive. They do not create separate authentication
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
             WstxProfiles supplies profile-specific cookie naming/session routing.
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
             HTTP content coding is solely WstxOperatingReceive::HttpContentCodingBoundary, and no arbitrary station-object dump. */
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
             MCP audit, WstxMcp::McpCredential). A station without a profile directory writes no
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
    satisfy WstxRequirements::'CL-003-02' by exchangeStatus;
    dependency stationOwner from exchangeStatus to WstxArchitecture::physicalStation::backend::stations::station;
    dependency transportOwner from exchangeStatus to WstxArchitecture::physicalStation::backend::stations::web;
    dependency presentationOwner from BrowserSnapshotPolicy to WstxArchitecture::physicalStation::frontend::browsers;
    dependency securityPromise from SessionSecurity to WstxRequirements::'CL-003-07';
    dependency reconnectPromise from BrowserLinkLifecycle to WstxRequirements::'CL-003-04';
    dependency budgetPromise from ThinLinkBudget to WstxRequirements::'CL-003-05';
    dependency pushedStatePromise from PushedStationState to WstxRequirements::'CL-003-05';
    dependency pushedStateBootPromise from PushedStationState to WstxRequirements::'CL-074-01';
    dependency pushedStateOwner from PushedStationState to WstxArchitecture::physicalStation::backend::stations::web;
    dependency bufferPromise from Limits to WstxRequirements::'CL-003-06';
    dependency exchangeVerification from ExchangeStatus to WstxRequirements::'TC-021-005';
    dependency browserVerification from BrowserSnapshotPolicy to WstxRequirements::'TC-021-006';
    dependency reconnectVerification from BrowserLinkLifecycle to WstxRequirements::'TC-021-007';
    dependency budgetJudgedFromLog from ThinLinkBudget to LinkTrafficLog;
    dependency trafficLogPromise from LinkTrafficLog to WstxRequirements::'CL-003-05';
    dependency trafficLogOwner from LinkTrafficLog to WstxArchitecture::physicalStation::backend::stations::web;
    dependency trafficLogVerification from LinkTrafficLog to WstxRequirements::'TC-080-001';
    dependency livenessVerification from Heartbeat to WstxRequirements::'TC-021-008';
    dependency tlsVerification from SessionSecurity to WstxRequirements::'TC-021-009';
    dependency buildPromise from ClientBuild to WstxRequirements::'CL-051-01';
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
        in selectedUuid : String;
        in runtime : RuntimeInputs;
        out cookieName : String;
    }
    action authenticate : AuthenticateProfile;
    dependency authenticationOwner from authenticate to WstxArchitecture::physicalStation::backend::stations::web;
    satisfy WstxRequirements::'CL-005-03' by authenticate;

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
             first audit entries, WstxMcp::McpCredential)}; .../create {version:1, name}
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
             status: WstxOperatingReceive::AuthStatusRequest, read-only active-grant
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
        objective { verify WstxRequirements::'CL-005-03'; verify WstxProfiles::'CL-005-04'; }
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
    dependency identity004 from sharedBrowserSessions to WstxRequirements::'TC-022-004';
}
