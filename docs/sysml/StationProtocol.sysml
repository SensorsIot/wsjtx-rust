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
        doc /* version is the candidate package version. This legacy status field stays
             unconfigured; authoritative native CAT/receive state uses WstxRadioIO's
             separate schema and is never inferred from this placeholder. */
    }
    item def StatusReply {
        attribute v : Integer = 1;
        attribute 'type' : String = "station.status";
        attribute id : Integer;
        item data : StatusData;
        doc /* Exact envelope{v,type,id,data}; data exactly{version,radio}. */
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
             marks state stale immediately. Reconnect waits1,2,4s then caps4s;
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
        attribute connectedStatusDisplayMs : Integer = 2000;
        attribute initialStatusAfterPageLoadMs : Integer = 10000;
        doc /* Shared bottleneck, not one32kbit link per browser. Idle includes
             heartbeat and accounted protocol overhead. Cold page/assets bytes/time
             are reported separately. This original status-only workload has no raw
             audio or spectrum stream; explicit Thin/live/display extensions retain
             their own measured limits and do not inherit an unproved N-station claim. */
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
    dependency stationOwner from exchangeStatus to WstxArchitecture::physicalStation::controller::stations::station;
    dependency transportOwner from exchangeStatus to WstxArchitecture::physicalStation::controller::stations::web;
    dependency presentationOwner from BrowserSnapshotPolicy to WstxArchitecture::physicalStation::viewer::browsers;
    dependency securityPromise from SessionSecurity to WstxRequirements::'CL-003-07';
    dependency reconnectPromise from BrowserLinkLifecycle to WstxRequirements::'CL-003-04';
    dependency budgetPromise from ThinLinkBudget to WstxRequirements::'CL-003-05';
    dependency bufferPromise from Limits to WstxRequirements::'CL-003-06';
    dependency exchangeVerification from ExchangeStatus to WstxRequirements::'TC-021-005';
    dependency browserVerification from BrowserSnapshotPolicy to WstxRequirements::'TC-021-006';
    dependency reconnectVerification from BrowserLinkLifecycle to WstxRequirements::'TC-021-007';
    dependency linkVerification from ThinLinkBudget to WstxRequirements::'TC-021-008';
    dependency tlsVerification from SessionSecurity to WstxRequirements::'TC-021-009';
}
