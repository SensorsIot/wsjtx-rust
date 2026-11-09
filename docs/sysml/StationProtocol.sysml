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
             identifier segment as {id}; the WebSocket upgrade is "GET /ws"), so the set of types
             is bounded. An HTTP request counts "<METHOD> <path and query> HTTP/1.1" CRLF, each header
             field the router received as "name: value" CRLF, CRLF, and its body bytes as read; a
             response counts "HTTP/1.1 <code> <reason>" CRLF, each header field it carries when it
             leaves the outermost router layer (after content coding) as "name: value" CRLF, CRLF,
             and its body bytes as sent after content coding (no chunk framing). What the HTTP
             server adds itself (date, a content-length or transfer-encoding it sets, chunk framing,
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
             counted below TLS because only there is the total exact. */
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
             selection.state and receive.state carry their state (WstxTransmit::TransmitWire,
             WstxContact::ContactStateEvent, WstxOperatingReceive::SelectionStateEvent, the
             receive wire); decode records are not carried yet;
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
}
