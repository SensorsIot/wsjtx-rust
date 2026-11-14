package WstxStationLink {
    private import ScalarValues::*;
    private import WstxRecordingTransfer::Recording;
    private import WstxStationCommands::StationOperations;
    private import WstxReceiveControl::ErrorCode;
    port def BrowserExchange :> StationOperations {
        out item upload : Recording;
    }
    interface def StationLink {
        doc /* The one front-to-back connection: a browser client and the web function of the
             station process it is attached to. */
        end client : BrowserExchange;
        end web : ~BrowserExchange;
    }
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
    item def Heartbeat {
        attribute v : Integer = 1;
        attribute 'type' : String = "heartbeat";
        doc /* Exact{v:1,type:heartbeat} plus a WebSocket Ping every5s. Browsers answer
             Ping. On the next heartbeat tick, >15s without Pong disconnects that peer. */
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
             MCP audit, WstxMcpInterface::McpCredential). A station without a profile directory writes no
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
             their state (WstxTransmitControl::TransmitWire, WstxQsoControl::ContactStateEvent,
             WstxStationCommands::SelectionStateEvent, the receive wire, WstxRequirements
             CL-043-01); decode records are not carried yet;
             a state not yet carried is read after its announcement event (one pending read
             per state and browser) and after the browser's own mutation; a browser does not
             poll on a timer, except a safety read of a state not yet carried no more often
             than once per safetyReadMinimumMs. The browser holds the state (snapshot plus events) and
             renders locally. Safety decisions (HALT, watchdog, PTT keying and release)
             stay on the station and never wait for a browser read. Existing reads are
             migrated in slices: first GET /transmit (WstxTransmitControl::TransmitWire
             transmit.state), then receive results, recording (WstxRecordingReceive
             recording.state), profile (profile.state: exactly {v:1,type:"profile.state",
             data:{profile_id,boot_id,revision}}, sent to a display-subscribed peer once
             after its first subscription and then when the saved revision changes, checked
             once per second; the browser reads GET /profile once per socket for its first
             status and on a newer announced revision, not on a later status of the socket),
             operating selection (WstxStationCommands::SelectionStateEvent) and radio;
             free_tx_slots.state (#65, #82) carries its state: exactly {v:1,type:"free_tx_slots.state",
             data:{profile_id,boot_id,free_tx_slots}} (WstxAutoControl::FreeTxSlots, at most 1024
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
             announcement event where its rule says so, as WstxOperatingLayout::AutomationIndicator) or
             waits for its first event; a snapshot reply that names another boot_id than the
             browser's current one is discarded (events of a closed socket are already
             ignored). This holds for every view of station state:
             contact, recording, receive, operating selection, AGC, Tx level, native radio,
             transmit, strategy (WstxOperatingLayout::StrategySelector), automation, PSK Reporter,
             Monitor off at startup and alerts. Once the reads and first events of the new boot
             have arrived, each view shows what a page loaded fresh at that moment shows. A
             failed read leaves the empty form until that view's next read under its rule; no
             retry timer. While the socket is down, views keep their values under the existing
             stale marks until the new boot is learned. The logbook is stored history, not
             state of one boot, and keeps its own rules. */
    }
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
    attribute def RadioCommissioningRecord {
        doc /* Single current observable acknowledgement for exact scope and effective
             endpoint/model/PTT configuration. Owner persists it only after explicit
             Confirm receive-only setup. Never a CAT open/query or transmit action.
             Changed safety configuration invalidates it and exposes explicit recovery. */
        attribute scope : SelectedRadioAuthorizationScope;
        attribute receiveOnlyConfirmed : Boolean;
    }
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
             first audit entries, WstxMcpInterface::McpCredential)}; .../create {version:1, name}
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
    attribute def BootstrapScopeRequest {
        doc /* Delivered: exact POST /authorization/v1/bootstrap-scope request is
             {version:1}; no optional/unknown/duplicate fields. */
        attribute version : Integer = 1;
    }
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
}
