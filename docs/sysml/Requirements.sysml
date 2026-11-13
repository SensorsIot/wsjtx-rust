// Canonical authority: SysML
package WstxRequirements {
    private import ScalarValues::*;
    private import WstxModemDecode::'TC-004-001';
    private import WstxModemDecode::'TC-004-002';
    private import WstxModemDecode::'TC-004-003';
    private import WstxMessageEncode::'TC-005-002';
    private import WstxProfiles::'CL-005-01';
    private import WstxProfiles::'CL-005-04';
    private import WstxProfiles::'CL-005-05';
    private import WstxProfiles::'TC-022-002';
    private import WstxProfiles::'TC-022-003';
    private import WstxProfileRecordings::'TC-018-001';
    private import WstxProfileRecordings::'TC-018-002';
    public import WstxRequirementsFrontend::*;
    private import WstxLiveReceive::'CL-008-02';
    private import WstxRecordingReceive::'CL-008-03';
    private import WstxRecordingReceive::'CL-006-04';
    private import WstxReceiveStartup::'CL-045-01';
    private import WstxLiveReceive::'TC-009-002';
    private import WstxLiveReceive::'TC-002-003';
    private import WstxRecordingReceive::'TC-009-004';
    private import WstxLiveReceive::'CL-007-05';
    private import WstxMcpEndpoint::'TC-020-004';
    private import WstxRadioIO::'CL-008-04';
    private import WstxRadioIO::'CL-008-06';
    private import WstxRadioIO::'CL-008-05';
    private import WstxRadioIO::'CL-022-03';
    private import WstxCatLifecycle::'CL-022-04';
    private import WstxRadioSetup::'TC-044-002';
    private import WstxRadioSetup::'TC-044-004';
    private import WstxStationProtocol::'CL-003-08';
    private import WstxStationProtocol::'CL-005-03';
    private import WstxStationProtocol::'TC-021-006';
    private import WstxStationProtocol::'TC-009-005';
    private import WstxStationProtocol::'CL-022-02';
    private import WstxStationProtocol::'CL-022-05';
    private import WstxTransmit::'CL-039-06';
    private import WstxTransmit::'TC-111-015';
    private import WstxMessageEncode::'TC-006-002';
    private import WstxModemDecode::'TC-057-002';
    private import WstxModemDecode::'CL-057-02';
    private import WstxStandardQso::'TC-007-004';
    private import WstxContact::'CL-055-02';
    private import WstxUdp::'CL-040-02';
    private import WstxUdp::'CL-112-01';
    doc /* Canonical functional requirements and durable verification definitions.
         The other Wstx packages own detailed typed contracts; validation does not execute tests.
         Coverage flags describe implemented source slices, not acceptance or whole-project parity. */
    enum def ImplementationState { enum target; enum partial; enum implemented; }
    enum def AutomationState { enum planned; enum partial; enum implemented; }
    requirement 'FR-001' {
        doc /* Station setup
             Configure and persist station identity, locator, devices, radio settings, and operating preferences. Validate values and explain invalid input. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/profile.rs; client/app.js";
    }
    requirement 'FR-002' {
        doc /* Audio
             Select supported input and output devices; capture receive audio and play generated transmit audio with the timing and sample handling required by each mode. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/receive.rs";
    }
    requirement 'FR-003' {
        doc /* Receive processing
             Process live audio and supported saved recordings; expose mode-appropriate filtering, synchronization, decoding options, and results. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/receive.rs; server/src/recording.rs; server/src/decoder/mod.rs";
    }
    requirement 'FR-004' {
        doc /* Decoding
             Decode the baseline mode and message variants, reporting available callsigns, locators, signal measurements, timing, and frequency information. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/decoder/mod.rs; server/src/decoder/payload.rs; server/src/decoder/search.rs";
    }
    requirement 'FR-005' {
        doc /* Encoding
             Produce protocol-compatible messages, channel symbols, and waveforms for supported transmit modes and variants. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/transmit/mod.rs; server/src/transmit/pack.rs; server/src/transmit/waveform.rs; server/src/transmit/schedule.rs; server/src/decoder/channel.rs";
    }
    requirement 'FR-006' {
        doc /* Time and sequencing
             Schedule receive and transmit periods against UTC and apply each mode's timing rules. Surface clock or device problems that prevent reliable operation. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/audio.rs; server/src/receive.rs; server/src/recording.rs; server/src/transmit/schedule.rs";
    }
    requirement 'FR-007' {
        doc /* QSO operation
             Support the baseline workflows for choosing a decoded station, preparing messages, progressing an exchange, and completing or aborting a contact. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    requirement 'FR-008' {
        doc /* Transmit control
             Provide clear transmit state and an immediate halt action; handle PTT, radio errors, and device loss without leaving transmit active unintentionally. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/transmit/service.rs; server/src/transmit_http.rs; server/src/playback.rs";
    }
    requirement 'FR-009' {
        doc /* Radio control
             Support baseline radio-control capabilities, including frequency, mode, PTT, split operation, and supported device interfaces. The hardware support matrix is to be inventoried. The first hardware end-to-end test target is an Icom IC-7300 on a different PC; #8 must settle its setup and acceptance contract before the test. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/radio_control/mod.rs; server/src/radio_control/actor.rs; server/src/radio_control/executor.rs; server/src/radio_control/codec.rs";
    }
    requirement 'FR-010' {
        doc /* Displays
             Provide spectrum, waterfall, decode, frequency, and operating-state views sufficient to carry out the baseline workflows. Pixel-identical UI reproduction is not yet a requirement. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "client/recording.js; client/recording.css; server/src/spectrum.rs";
    }
    requirement 'FR-011' {
        doc /* Logging
             Record completed contacts and support the baseline log formats, import/export paths, and duplicate or prior-contact indications where applicable. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    requirement 'FR-012' {
        doc /* Integrations
             Preserve required external protocols and message formats, including baseline UDP integrations and reception-reporting workflows. The WSJT-X UDP interface is specified by issue #40, CL-040-01..04 (send-only, operator 2026-11-06), contract WstxUdp; reception reporting remains target. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/network_message.rs; server/src/udp.rs; server/src/pskr.rs";
    }
    requirement 'FR-013' {
        doc /* EME
             Provide baseline astronomical information, Doppler handling, and Echo measurement workflows applicable to each application. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    requirement 'FR-014' {
        doc /* Wideband reception
             Replace MAP65 and QMAP capabilities, including supported wideband input, band maps, polarization processing where applicable, and coordination with the narrowband application. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    requirement 'FR-015' {
        doc /* Utilities
             Identify the user and validation needs served by upstream utilities. Provide the selected capabilities through the smallest practical interface, documenting any required external compatibility. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    requirement 'FR-016' {
        doc /* Settings and migration
             Persist Rust application settings reliably. Define compatibility and migration behavior for existing WSJT-X profiles before a user migration release. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/profile.rs";
    }
    requirement 'FR-017' {
        doc /* Help and notices
             Provide operating guidance, version information, relevant attribution, license access, and a clear indication that this is an independent port. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "client/index.html; client/app.js";
    }
    requirement 'FR-018' {
        doc /* Recorded audio input
             Load and validate recorded receive audio for repeatable processing, preserving source data and reporting unsupported or invalid input. The first recorded-input format, bounded import/replay workflow and tests are specified in4.4/6.4/12.6 ; implementation coverage is declared below. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/recording.rs; server/src/recording_http.rs";
    }
    requirement 'FR-019' {
        doc /* Browser operator interface
             Provide a modern HTML/CSS/JavaScript operator interface that can run on the home computer, rendering station information and sending control requests to the server. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "client/index.html; client/app.js; client/recording.js; server/src/main.rs";
    }
    requirement 'FR-020' {
        doc /* MCP automation
             Expose shared station operations through MCP for observing and automating FT4/FT8 activity, including station selection and QSO workflows. Exact tools and automation policies are specified in their CRs: issue #12, CL-012-01..04, contract WstxMcp. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/mcp.rs; server/src/automation.rs";
    }
    requirement 'FR-021' {
        doc /* Station server and remote operation
             Separate the Rust station server and browser client through a defined interface. Support same-machine development and remote operation over limited-bandwidth links, with authoritative server state, explicit connection status, and state resynchronization. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/main.rs; client/app.js";
    }
    requirement 'FR-022' {
        doc /* Concurrent persisted station profiles — phase 1 target
             Support a variable number of independently startable/stoppable server instances on one Windows PC, using distinct listening ports, separate browser windows and isolated persisted configurations. Four is a minimum acceptance target, not a software limit. Preserve instance identity and access isolation across restart and concurrent use. Independent persisted profile functionality is implemented; coverage and verification are declared separately. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; server/src/main.rs; client/app.js";
    }
    requirement 'FR-023' {
        doc /* Optional direct FlexRadio integration — phase 2 target
             Offer a selectable native FlexRadio TCP/UDP connection type alongside the default audio-device/optional CAT/PTT path. Native profiles operate without requiring external SmartSDR desktop/CAT/DAX applications, persist their receive intent (never a radio identity, slice index or handle) and reconcile actual resources on connection. Both paths share the browser/DSP/MCP architecture. Receive and control at isolated level 2 are delivered (WstxFlexSession::NativeFlexWireSubset); live hardware qualification TC-023-004/005 and transmit TC-023-006 remain open. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/flex/session.rs; server/src/flex/wire.rs; server/src/flex_http.rs; server/src/profile.rs; client/recording.js";
    }
    requirement 'FR-024' {
        doc /* Contest, special-activity and DXpedition operation — phase three
             Offer WSJT-X's special operating activities chosen by the operator, the contest exchanges, the Hound role and the nonstandard message types, each with its decode, encode, sequencing and logging, on the shared browser/modem/QSO/log/MCP services. Approved slices (issue #24, operator 2026-11-03, WSJT-X 3.3.0-beta5 reference): S1 nonstandard/compound calls, filled-in hashed calls and free text; S2a grid-exchange contests; S2b Field Day and RTTY Roundup (ADIF contest fields, no Cabrillo); S4 classic Hound. S5 SuperFox Hound moved to its own phase-two issue #77 (operator 2026-11-08); Fox (S6) was dropped; EU VHF (S3), decoded since S1a, is sent by issue #99 (operator 2026-11-09, CL-099-01/02). */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/decoder/hashes.rs; server/src/recording.rs; server/src/contact.rs; server/src/transmit/pack.rs";
    }
    requirement 'CL-003-04' {
        doc /* The browser MUST distinguish stale/disconnected state from current station state, detect a silently unresponsive connection, retry at a bounded rate and obtain a full snapshot before showing Connected again. Recovery MUST not wait indefinitely for an old socket to close. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs; client/app.js";
    }
    dependency CL_003_04_to_FR_019 from 'CL-003-04' to 'FR-019';
    dependency CL_003_04_to_FR_021 from 'CL-003-04' to 'FR-021';
    requirement 'CL-003-05' {
        doc /* The minimal profile MUST support two clients sharing the contract's 32 kbit/s link model (WstxStationProtocol::ThinLinkBudget). Its traffic budgets are targets of normal operation that the operator judges from the station's link byte log, and its visible-response target is watched in the live check after each deploy (operator 2026-11-09) (WstxStationProtocol::LinkTrafficLog); no test asserts them (operator 2026-11-09, #80). The station MUST record that log: per period and client (an enrolled browser, an MCP client or local), the bytes each way in total and by message type, and the display profile of each of the client's sockets. Page and asset loading, reconnection, authorization recovery, CAT, selection changes, recording replay or import and log maintenance carry no link budget. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs; server/src/link_log.rs; server/src/mcp.rs; client/app.js";
    }
    dependency CL_003_05_to_FR_021 from 'CL-003-05' to 'FR-021';
    requirement 'CL-005-02' {
        doc /* Stable identity, schema, validated settings, revision and acknowledged saves MUST survive process restart. The browser MUST identify the selected profile and permit the bounded edits below. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/profile.rs; client/app.js";
    }
    dependency CL_005_02_to_FR_001 from 'CL-005-02' to 'FR-001';
    dependency CL_005_02_to_FR_016 from 'CL-005-02' to 'FR-016';
    dependency CL_005_02_to_FR_019 from 'CL-005-02' to 'FR-019';
    dependency CL_005_02_to_FR_022 from 'CL-005-02' to 'FR-022';
    requirement 'CL-007-02' {
        doc /* The common browser MUST show exact supported payload fields, hash identities (filled in by the station per CL-024-01 or unresolved), UTC period time and relative DT when correlated or explicit unknown timing under4.7.4, lowest-tone audio frequency and calibrated SNR or explicit unavailable SNR, with reliable bounded result delivery. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/decoder/mod.rs; server/src/receive.rs; client/recording.js";
    }
    dependency CL_007_02_to_FR_003 from 'CL-007-02' to 'FR-003';
    dependency CL_007_02_to_FR_004 from 'CL-007-02' to 'FR-004';
    dependency CL_007_02_to_FR_019 from 'CL-007-02' to 'FR-019';
    requirement 'CL-008-01' {
        doc /* Persist independently selected audio and typed IC-7300 control intent through the existing profile revision/atomic-store boundary; settings never assert device availability. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/radio_control/mod.rs; server/src/receive.rs";
    }
    dependency CL_008_01_to_FR_001 from 'CL-008-01' to 'FR-001';
    dependency CL_008_01_to_FR_002 from 'CL-008-01' to 'FR-002';
    dependency CL_008_01_to_FR_009 from 'CL-008-01' to 'FR-009';
    dependency CL_008_01_to_FR_022 from 'CL-008-01' to 'FR-022';
    verification 'TC-002-001' {
        doc /* TC-002-001 — Canonical live audio
             CL-008-01, CL-008-02, CL-008-03
             Inject independently timed mono/stereo native float/PCM packets, silence flags, arbitrary splits, exact queue limits/one-over, gaps, timestamp errors, DATA_DISCONTINUITY flags on contiguous positions with QPC steps inside and just outside the2 ms bound, missing devices and cancellation into actual capture/converter boundaries. Generate analytic tones/impulses and rational frame maps independently.
             Channel0/normalization/finite-value rules, exact rational counts and block partition invariance within2e-5, group-delay alignment within one canonical frame, passband0.1dB/stopband60dB, bounded storage and no gap-crossing/fake silence. A contiguous flag within2 ms of the QPC timeline keeps one epoch and gap-free frames; beyond2 ms it is unknown loss; every unknown-loss epoch names its trigger. Canonical recordings unchanged. Cancel release<=250ms except explicit failed-close state; capture never invokes CAT.
             2 — Isolated automated tests; Windows development PC, actual candidate modules and independent device/clock fixtures. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-008-01';
            verify 'CL-008-02';
            verify 'CL-008-03';
        }
        attribute executable : String = "server/tests/audio_contract.rs; server/tests/audio_receive.rs; server/tests/receive_integration.rs; server/tests/source_contract.rs; server/src/audio.rs";
    }
    verification 'TC-009-001' {
        doc /* TC-009-001 — Typed radio control
             CL-008-01, CL-008-03, CL-008-04, CL-008-06
             Feed manually derived CI-V query/set/ACK/NG/readback bytes through fragmented, malformed, echoed, foreign, stale, flooded and boundary-sized transport fixtures. Test auto-baud order/deadlines, invalid catalogue/URI, physical alias conflicts and cancellation before/after send.
             Exact bytes/readback semantics; no bytes for invalid/raw/TX requests; no deadline renewal/in-flight exchange retry/write replay; one owner/no queue; every cap and one-over; missing/busy/failed-close state truthful; two processes cannot own the same physical resource.
             2 — Isolated automated tests; Windows development PC, compiled control service and independent protocol/serial emulator. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-008-01';
            verify 'CL-008-03';
            verify 'CL-008-04';
            verify 'CL-008-06';
        }
        attribute executable : String = "server/tests/radio_control.rs";
        attribute method : String = "manual";
    }
    requirement 'CL-010-05' {
        doc /* Present one operating-first profile page with the fixed-band signal display above the message/contact workspace, an accessible adjustable split and secondary in-page settings. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/index.html; client/recording.js; client/recording.css; server/src/recording.rs";
    }
    dependency CL_010_05_to_FR_010 from 'CL-010-05' to 'FR-010';
    dependency CL_010_05_to_FR_019 from 'CL-010-05' to 'FR-019';
    requirement 'CL-010-07' {
        doc /* Show audio, CAT, decoder and transmit availability independently. Label unavailable values and visibly disable unsupported actions with adjacent reasons; status-link connection alone does not establish a radio capability. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/index.html; client/recording.js; client/recording.css; server/src/recording.rs";
    }
    dependency CL_010_07_to_FR_001 from 'CL-010-07' to 'FR-001';
    dependency CL_010_07_to_FR_008 from 'CL-010-07' to 'FR-008';
    dependency CL_010_07_to_FR_009 from 'CL-010-07' to 'FR-009';
    dependency CL_010_07_to_FR_019 from 'CL-010-07' to 'FR-019';
    requirement 'CL-010-09' {
        doc /* Band Activity shows only the latest published decode period and signed station timing relative to our clock, selectable presentation sorting and explicit partial/unavailable states. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/index.html; client/recording.js; client/recording.css; server/src/recording.rs";
    }
    dependency CL_010_09_to_FR_010 from 'CL-010-09' to 'FR-010';
    dependency CL_010_09_to_FR_019 from 'CL-010-09' to 'FR-019';
    requirement 'CL-010-08' {
        doc /* Preserve keyboard and narrow-screen operation, literal field rendering and existing signal/status transport contracts. Secondary in-page regions keep the persistent station bar and disabled Halt Tx accessible. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/index.html; client/recording.js; client/recording.css; server/src/recording.rs";
    }
    dependency CL_010_08_to_FR_019 from 'CL-010-08' to 'FR-019';
    dependency CL_010_08_to_FR_021 from 'CL-010-08' to 'FR-021';
    dependency CL_010_07_verified_by_TC_007_004 from 'CL-010-07' to 'TC-007-004';
    dependency CL_010_08_verified_by_TC_007_004 from 'CL-010-08' to 'TC-007-004';
    verification 'TC-021-007' {
        doc /* #### TC-021-007 — Disconnect, retry and state resynchronization

             Application payload codecs and negotiated WebSocket compression remain excluded.
             HTTP content coding12.1.1 changes no reconnect, snapshot, event or status deadline.

             **Clauses:** CL-003-04, CL-003-08. **Promise:** FR-021.
             **Level:** 2 — Isolated automated tests.
             **Where it runs:** Windows PC, actual candidate server and real browser through a
             controllable disposable local proxy, with WebSocket message and attempt timestamps.

             **Inputs/actions and expected results:**

             1. Connect and observe an unchanged session across a heartbeat interval. Expect an
                initial snapshot request and no periodic station.get polling.
             2. Cut the connection and keep it unavailable. Expect visible stale/disconnected state
                and attempts at the bounded reconnect rate from the
                [liveness contract](backend/web/StationProtocol.sysml).
             3. Restore connectivity to the actual server. Expect a new station.get exchange and a
                fresh full snapshot before Connected, within the contract's recovery bound. If a
                server restart or version change is exercised, the fresh state MUST replace the old
                display; an unchanged unconfigured state still requires a newly observed exchange.
             4. Drop bytes without closing the established test connection. Expect stale detection
                within the contract's silent-loss bound and scheduler tolerance. Restore byte delivery;
                expect bounded recovery and another snapshot without waiting for the old close handshake.
             5. Hold (delay, not drop) every station-to-browser byte while the page's deferred
                client download is pending; with the page's clock installed before load, drive it
                16s (past the 12s bound and its 1-second tick), then deliver. Expect only the
                connected state, the same socket and no new connection (#8, issue70: driven, no
                real wait). The former real-time 31s check with a download that never completes is
                retired (#80, operator 2026-11-09: a setup case, not normal operation).

             **Oracle:** contract state transitions/time limits and observed request exchange.
             The automation cuts/restores the proxy to the actual server and checks a new snapshot
             exchange; it does not simulate a different application version. **Executable trace:**
             [communication.test.cjs](../../tests/communication.test.cjs),
             `TC-021-007: dropped connection, bounded retries, fresh snapshot`. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-003-04';
            verify 'CL-003-08';
            verify 'FR-021';
        }
        attribute executable : String = "tests/communication.test.cjs";
    }
    verification 'TC-080-001' {
        doc /* TC-080-001 — Link byte log
             CL-003-05
             Setup: the actual router in the test process on a selected HTTPS profile with a disposable directory, one enrolled browser grant and one MCP client; the log's period clock and the operating mode are driven by the test; raw test peers hold their own TCP sockets, count every TCP byte they write and read, run their TLS client on top, write and read HTTP/1.1 text and WebSocket frames themselves, and one peer speaks HTTP/2; each step waits until its exchanges are complete before the period clock moves.
             Steps: (a) FT8: in one period the browser's socket subscribes Thin and sends station.get three times; on the browser's credentialed connection GET /profile, POST /authorization/v1/status and POST /receive/select with a malformed body (refused 400); the MCP client makes one tools/call; the period ends. (b) A second socket of the same grant on Off in the next period. (c) FT4: two 7.5 s periods. (d) A mode change FT8 to FT4 at 5.2 s into a period. (e) No mode selected. (f) A TLS connection without credentials: GET / and a request refused 401. (g) The browser's GET /profile over HTTP/2. (h) Lines written past the rotation size. (i) A plaintext loopback profile. (j) Methods FOO1 and FOO2 on / and on an unknown path: types "OTHER /" and "OTHER unrouted", no client text in any key (#80 review finding).
             Expected (WstxStationProtocol::LinkTrafficLog): one JSON line per client with traffic at each period end, none for a client without traffic. bytes each way equals the TCP bytes the client's peers wrote and read in that period. Each type's count and bytes equal the peers' own counts by the log's rule: WebSocket frames header plus payload (mask included from the client); HTTP the request as written (request line, header fields, body) and the response as received minus the fields the HTTP server adds itself (date, and the content-length or transfer-encoding these routes leave unset) and minus chunk framing, re-serialized as HTTP/1.1 text; the same reconstruction for the HTTP/2 exchange. other = bytes - sum of types. estimate equals the hand calculation of the log's formula. The refused POST /receive/select is on the browser's line; the MCP client has its own line and the browser line holds no MCP bytes; (f) is on a local line on TLS. display lists each socket's profile (thin, then thin and off). FT4 lines are 7500 ms apart; the mode change gives (start, 5200, FT8), (change, until the next FT4 start, FT4), then 7500 ms FT4 lines; with no mode the lines say mode none and are 15000 ms apart. No line holds a cookie, token or proof. The file moves to link-traffic.1.log at its rotation size, replacing the older one. Nothing of the log reaches a socket or response. On the plaintext profile t is 0 and the client is local.
             2 — Isolated automated functional test; Windows development PC; no browser, link simulator or radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-003-05';
        }
        attribute executable : String = "server/src/link_log_tests.rs";
    }
    verification 'TC-022-001' {
        doc /* #### TC-022-001 — Variable independent servers and browser windows

             **Promises:** FR-001, FR-019, FR-021, FR-022; CL-005-01, CL-005-02, CL-005-03,
             CL-005-05. **Level:** 2 — isolated automated tests.
             **Where:** Windows PC, N real server processes and separate real browser windows.

             **Setup partition:** Operational browser windows and save/readiness regressions
             use four saved HTTPS localhost endpoints and legitimate selected grants in one
             browser context, per WstxOperatingLayout::IndependentVerification. Plaintext trusted
             numeric-loopback HTTP/launch compatibility is a separate mandatory companion,
             not an operational configuration GUI or Connected/protected-WS prerequisite.

             **Steps:** Launch each table profile with `--profile`; open one window per recorded
             endpoint. Match every visible full UUID, display name, endpoint, boot ID and revision
             to its fixture; require N distinct boot IDs/listeners/PIDs. Refresh every window.
             In window 1 save name `Edited station 1`, audio input `changed-input-1` and CAT endpoint
             `fixture-cat-1`, CAT mode and disabled PTT; retain its output and all other fields.
             Reload/Refresh a second window on profile 1 and all other station windows. Repeat with
             empty audio selections and disabled CAT; save audio alone and control alone.

             **Oracle/outcome:** Only profile 1 advances to the next revision and changes the
             specified fields; every other file and visible identity/settings remains equal to the
             input table. The second window observes the same acknowledged revision on refresh.
             All windows show radio unconfigured and saved device selections not activated. No
             serial/device access is attempted. The native option is visibly reserved/disabled.
             There is no four-entry ceiling. Check the form at desktop width and 360 px: identity,
             errors and Save remain readable/reachable with keyboard input.

             **Plaintext API companion:** With trusted numeric loopback, no cookie and the
             exact saved Origin where supplied, require GET/valid durable PUT200, identical
             JSON keys/UUID/revision/settings/size expectations, ordered errors/domain/byte
             boundaries, unchanged file bytes on rejection and exact durable fields on success.
             Retain the complete validation matrix below in this companion AND current-grant
             HTTPS protected ordered checks; no auth bypass or omitted existing variant.
             Plaintext auth-v1/protected WS/native remain denied, never operational readiness.

             **Validation variants:** In one isolated profile, submit every editable field's empty,
             maximum and one-beyond-maximum value from 4.2, controls/newlines, malformed callsign/
             locator, wrong JSON types, invalid CAT/PTT combinations and an attempted native selection.
             Empty callsign/locator and nullable audio are valid; empty display name/opaque identifier
             are invalid. Test literal markup in a valid display name and require visible text without
             HTML execution. In particular, save display name `<img src=x onerror=alert(1)>` and
             audio identifier `<script>alert(1)</script>`; require their exact literal text in the
             appropriate page/form fields, no injected element, and no script/dialog execution.
             Exercise wrong profile ID, stale revision, duplicate/extra/missing fields,
             invalid JSON, unsupported media type and exact 8,192/8,193-byte bodies per 12.5 (pad
             an otherwise valid JSON object with whitespace). Each rejected save
             leaves memory/revision/file unchanged and shows its field/error outcome; valid boundary
             saves persist exactly. Revision exhaustion refuses another save. Test a second window
             saving from an old revision: one save wins, one receives 409, no silent merge/lost update.
             Also hold an announced revision's GET response, begin and hold a PUT, then release the GET while the
             save remains pending. Save stays disabled and even a repeated form submission sends
             no second PUT. Release the PUT: exactly one revision advances, editable controls and
             Save recover their usable state, and permanently read-only controls remain disabled.
             Repeat with the opposite response order on an unchanged revision-0 station: hold the
             announced revision's GET response, complete the PUT, whose 200 reply is the revision-1
             snapshot (CL-073-01, no follow-up GET), then release the old response. Visible revision, saved fields and acknowledged-save feedback remain at
             revision 1. A changed boot identity still permits restart/recovery resynchronization.

             **Automation coverage:** Existing companions retain the delivered profile,
             domain/API and form-ordering subset. Operational HTTPS/grant fixture conversion
             and complete separate plaintext plus protected-HTTPS validation coverage remain
             pending; the expanded case is partial, without discarding existing assertions. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-005-01';
            verify 'CL-005-02';
            verify 'CL-005-03';
            verify 'CL-005-05';
            verify 'FR-001';
            verify 'FR-019';
            verify 'FR-021';
            verify 'FR-022';
        }
        attribute executable : String = "tests/profiles.test.cjs; server/src/profile_tests.rs";
    }
    verification 'TC-022-005' {
        doc /* #### TC-022-005 — Status readiness independent of settings transport

             Proves CL-005-02, CL-005-03 and CL-006-04. Level 2, automated Windows real Chromium/server
             fixture in tests/profiles.test.cjs, using the common four-process operational
             HTTPS/grant fixture before each relevant protected socket. Preserve separate
             plaintext HTTP/launch compatibility; auth setup requests do not count as profile
             GETs and auth status cannot replace correlated WS status.
             On an established socket a Refresh sends no GET /profile (#10 profile.state); an
             independent save makes the station announce the revision and the browser reads once.
             Hold that GET behind a controlled barrier, click Refresh,
             observe its actual correlated WebSocket status and require changed visible updated plus
             enabled Refresh within 2 seconds before releasing HTTP. Repeat Refresh while held: it adds no GET; a second independent save while held starts no parallel read, and
             one follow-up eventually obtains that newer
             revision without overwriting dirty input. On a fresh socket hold initial GET: Connected,
             station-ready and optional display remain withheld until validated success. Close that
             socket with HTTP held, establish a replacement, then release the old response: it cannot
             restore Connected, replace the newer profile snapshot or overwrite its form. Fail the
             initial/background GET separately: visible failure/stale, no false configuration success.
             Oracles are these independent canonical timing/identity expectations, real WS traffic and independently
             prepared profile revisions; barrier release happens only after the status assertion.

             **Automation coverage:** Existing companions retain the delivered legacy
             socket/settings-readiness subset. The operational HTTPS/grant fixture conversion
             remains pending; the expanded case is partial, with every existing timing,
             held-response, count and stale-form assertion retained. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-005-02';
            verify 'CL-005-03';
            verify 'CL-006-04';
        }
        attribute executable : String = "tests/profiles.test.cjs";
    }
    verification 'TC-007-002' {
        doc /* #### TC-007-002 — Read-only operating layout slice

             Proves CL-010-05, CL-010-07, CL-010-08. Cost level 2: offline integration tests on
             the development PC, using the actual server and headless Chromium; no radio or
             external network. Create an isolated saved profile whose display name includes HTML
             metacharacters and connect the browser. At 1440×900 and 360×800 CSS pixels, and a
             desktop 200% zoom-equivalent CSS viewport, verify station identity and truthful status,
             signal above separator above workspace, no document horizontal overflow, empty
             Band Activity/contact tables and explicit unsupported explanations. Verify unsupported
             controls are disabled and produce no requests. With the capability pushed from available
             to unavailable and back (#22): CQ, Tune, Now and Auto Seq disabled, badge Receive only, the
             reason shown, Control panel and pane unmoved, a running Tune can be turned off, Call 1st
             enabled; a double-click or a Calling me line sends select_row and no enable_tx, the
             menu's Reply disabled, "Auto Seq on" not offered; back to Ready without any action. After a real station restart (#22; a new boot's generation below
             the old one) with no receive job yet: whichever of /receive and /recording answers first,
             and while /receive is still pending, Band Activity heading "Latest decode period", no row
             or divider of the previous boot, Decoder unavailable; with a receive job already running
             at a lower generation: the same heading and rows, Listening for FT8.
             Open/close saved settings and recording
             regions with keyboard; verify existing controls remain reachable in the same page.
             Use separator ArrowUp/Down/Home/End and pointer dragging; verify actual height changes,
             ARIA value changes and the signal remains above the workspace. Disconnect the server
             and verify the global state becomes stale without enabling unsupported controls.
             Independent oracles: the specified layout/order/capability rules and existing server
             status contract; a screenshot alone is not an acceptance oracle. Existing TC-010-005,
             TC-010-006 and TC-010-007 remain the waveform/palette/geometry regressions.
             At360,1440 and1600CSSpx, inspect computed Band Activity cell, time and header
             styles against16CSSpx normal/time/numeric/message and14CSSpx label minima, rem-scaled
             at200% text enlargement, and8CSSpx vertical padding.
             All widths retain these minima; long text wraps without page overflow. Existing splitter, keyboard, capability and transport assertions remain.
             These style oracles come from the stated presentation values, not candidate CSS. Verify the dominant/full-width Band Activity proportions and labelled responsive rows at360/720/1200/1440/1600CSSpx and1x/2x text. Use captured physical FT4 message text strictly as a labelled presentation fixture, plus independent edge strings:3499.9Hz, signed SNR/DT, long callsigns/full messages, large source seconds, UTC-formatted text and every result status. All six values remain literal and inside their own cells; numbers never split, message tokens wrap only when needed, and table labels remain accessible. This fixture is not decoder/RF truth. Capture desktop/narrow/2x screenshots; retain the separate actual nativeFT4/FT8 decoder/browser proofs. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-05';
            verify 'CL-010-07';
            verify 'CL-010-08';
        }
        attribute executable : String = "tests/receive-integration.test.cjs; tests/ui-operating.test.cjs; tests/contact.test.cjs; tests/receive-page.test.cjs; server/src/receive_http_tests.rs";
    }
    verification 'TC-007-009' {
        doc /* #### TC-007-009 — Laptop operating screen (#37)

             Proves CL-010-16. Cost level 2: actual isolated server and headless Chromium on the
             development PC; no radio, audio device or network service. A Band Activity record
             with a_priori 1 shows the a1 marker after its message, outside the message text
             (#56 slice 5). At 1366x768: no page
             scroll or horizontal overflow; the top bar holds only the TopBarItem set; no Monitor,
             Enable Tx, Start/Stop receive or Next receive mode control exists; no status text or
             error field entry is shown for a healthy station and each injected exception (stale
             link, receive stopped, unknown receive outcome, audio unavailable) shows its entry in
             the error field below the QSO pane (CL-037-02), which opens its detail; the Rx/Tx strip, Band Activity with the strategy element and the QSO pane are
             visible. At 360x800 the page does not overflow horizontally. The Settings drawer has
             exactly General, Radio, Logging & Reporting and Expert and every control that left the
             operating screen is reachable there, with HALT visible and the waterfall running; a
             restart change during an active contact asks before Apply. Rx/Tx strip steps (1/10 Hz),
             Tx=Rx/Rx=Tx and Hold Tx send exactly the expected contact requests. Band Activity shows
             history newest first with period dividers, double-click replies (select then
             enable_tx) and the right-click menu acts. QSO pane CQ sends enable_tx and a fold-out Now (Tx4
             after RR73 chosen, Tx5) sends choose_next then enable_tx, each with the shown safety revision;
             the pane has no Reply, RR73 or 73 button; on a completed contact Now is disabled and a forced
             click sends no enable_tx. In the operating view one HALT is visible, the QSO pane's,
             the top-bar HALT shows on the Logbook page, in the Settings drawer, and at 1024x768
             and 360 px where the stacked pane HALT is below the fold; a HALT is in the viewport
             without scrolling at every size. With the confirmation popup open during an active QSO its HALT
             sends the halt request. Theme switch changes the theme without a request. Keyboard
             shortcuts act as KeyboardShortcuts and letters are inactive while typing. An
             unauthorized browser shows only the token form and its status line, then the full
             screen after authorization. Settings > General shows "Monitor off at startup" as read
             from GET /receive/startup; toggling it sends exactly one POST /receive/startup
             {v 1, profile_id, boot_id, monitor_off_at_startup} and no receive start, stop or
             selection, a refusal restores the previous value, and Expert shows the resume state;
             Logging & Reporting shows the UDP configuration read from GET /udp (no /udp request
             before the drawer opens) and the instance name as text with no input (CL-112-01);
             editing a target, adding one and Save send exactly one PUT
             /udp {v 1, profile_id, boot_id, expected_revision, configuration} whose configuration
             is the edited list, {targets} only, and no receive start, stop or selection; no Accept commands control exists; a refusal
             shows its code and field and keeps the edits; the send-only note and each target's
             status are shown. An IPv6
             group target [ff12::5754:5358]:2237 (#46, CL-040-06) shows the hop-limit/interface-index hint naming the link-local
             need, and saves with the TTL field as hop limit 2 and interface "1"; the same group
             without an interface is refused with targets[0].multicast_interface.
             Compact QSO pane (#37, QsoPane): with a running QSO at 1366x768 the pane shows the
             header, the last partner message "HB9BLA IW9FRA RR73  +17 dB ×3", the QSO
             dialogue as the #60 table (ten entries, oldest first, the newest row inside the
             section) and below it Calling me oldest first (every station calling me but the
             partner, ⚠ on those within +/-50 Hz of Rx 1500 Hz or Tx 2100 Hz, no DT/frequency;
             no ⚠ with Rx and Tx at 2800 Hz), NEXT "▸ next: <message>" while armed, and the
             buttons, all inside the pane (not clipped); item 8 (#37 2026-11-04): the pane at
             the top of its column, its fixed height proved by TC-037-003; at 1920x1080 at
             least 100 px free below the error field (#37 LowerPanel, TC-037-001); there is no LAST row or
             crowding badge; double-clicking a Calling me line during the QSO sends select_row
             with replace true then enable_tx. Idle, every station calling me is a Calling me row
             "<caller> | <SNR> | <grid> | <country>" (no CQ, even near Rx) whose double-click
             sends select_row then enable_tx. When the contact is
             completed (Log QSO or completion) the pane shows "✓ Logged <call>", no NEXT and
             no partner lines, and after loggedNoticeSeconds only the idle pane; a cancelled
             contact is gone at once. At 360x800 nothing overflows horizontally.
             Independent oracles: the design-interview decisions in the
             model, not the candidate markup. Screenshots at 1366x768 and 360x800. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-16';
            verify 'CL-045-01';
            verify 'CL-040-02';
            verify 'CL-037-03';
            verify 'CL-112-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs; server/src/contact_tests.rs";
    }
    verification 'TC-007-006' {
        doc /* #### TC-007-006 — Latest decode and signed relative timing

             Proves CL-010-09, CL-007-02. Cost2: offline automated Windows development-PC tests of the actual
             Rust manager/API and real Chromium using independently scripted sample/clock/result
             fixtures. Existing native FT4/FT8-through-real-decoder proofs remain separate; UI
             fixtures are not RF truth. Cost4 live acceptance uses HB9BLA IC-7300 and this PC's
             browser for operator-authorized receive-only FT4/FT8 observation.

             - Publish two periods with multiple stations and more than16 latest-period records;
               retrieve split/Thin pages, then a newly empty period. Expect every available latest
               row, no earlier rows, no page-size truncation and an explicit empty explanation.
             - Exercise complete/overrun attempts, known gaps, cancellation, failure, late results,
               changed descriptor mid-page, old sockets/epochs, reconnect, expired cursors and safe
               counters. Expect atomic monotonic view identity, truthful Partial/incomplete/stale
               labels, no invented completion and no obsolete row/cursor movement. Existing ring,
               page/record sizes and single pending/cadence remain (the 32 kbit/s link budget is
               judged from the link byte log, #80).
             - Hand oracle: anchor2026-10-27T12:00:00Z at frame0. FT8 starts3600/6000/8400 yield
               DT-0.2/+0.0/+0.2 in12:00:00. FT4 starts3024/5424/7824 yield the same, and frame95424
               yields+0.0 in12:00:07.5. Repeat with a nonzero canonical anchor, day rollover,
               sub-millisecond UTC anchor, nearest-slot ties and signed rounded zero. Without
               correlation both timing fields are null; with correlation and external_accuracy
               unknown timing stays relative to our station, not falsely certified external UTC.
             - At1440px/360px and normal/doubled text inspect the actual UTC Time, signed DT,
               callsigns and all six fields: literal values, unbroken numeric text and no horizontal
               page overflow. In live acceptance observe actual decoded calls in both modes and
               record clock quality without claiming independently measured transmitter clock error.

             Sorting checks: use independently scripted frequency200/1000/3499.9, SNR-20/+10/-5,
             signed DT-0.2/+0.2/unknown and case-varied literal messages. Check all fields and both
             directions, unknown-last, stable ties, arrivals spanning pages, empty/next periods,
             mode/reconnect retention and profile reset (to the #55 value order, the default); verify no new server mutations or changed
             result request cadence. Cost2 Windows actual Chromium/candidate server; cost4 actual
             live calls, operator changes both controls and observes only latest-period rows. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-007-02';
            verify 'CL-010-09';
        }
        attribute executable : String = "tests/ui-operating.test.cjs; server/src/recording_tests.rs";
    }
    dependency CL_003_04_verified_by_TC_021_006 from 'CL-003-04' to 'TC-021-006';
    dependency CL_003_04_verified_by_TC_021_007 from 'CL-003-04' to 'TC-021-007';
    dependency CL_003_05_verified_by_TC_080_001 from 'CL-003-05' to 'TC-080-001';
    dependency CL_005_02_verified_by_TC_022_001 from 'CL-005-02' to 'TC-022-001';
    dependency CL_005_02_verified_by_TC_022_002 from 'CL-005-02' to 'TC-022-002';
    dependency CL_005_02_verified_by_TC_022_005 from 'CL-005-02' to 'TC-022-005';
    dependency CL_007_02_verified_by_TC_004_001 from 'CL-007-02' to 'TC-004-001';
    dependency CL_007_02_verified_by_TC_004_002 from 'CL-007-02' to 'TC-004-002';
    dependency CL_007_02_verified_by_TC_004_003 from 'CL-007-02' to 'TC-004-003';
    dependency CL_007_02_verified_by_TC_007_006 from 'CL-007-02' to 'TC-007-006';
    dependency CL_008_01_verified_by_TC_002_001 from 'CL-008-01' to 'TC-002-001';
    dependency CL_008_01_verified_by_TC_009_001 from 'CL-008-01' to 'TC-009-001';
    dependency CL_010_05_verified_by_TC_007_002 from 'CL-010-05' to 'TC-007-002';
    dependency CL_010_05_verified_by_TC_009_004 from 'CL-010-05' to 'TC-009-004';
    dependency CL_010_05_verified_by_TC_009_005 from 'CL-010-05' to 'TC-009-005';
    dependency CL_010_07_verified_by_TC_007_002 from 'CL-010-07' to 'TC-007-002';
    dependency CL_010_07_verified_by_TC_009_004 from 'CL-010-07' to 'TC-009-004';
    dependency CL_010_07_verified_by_TC_009_005 from 'CL-010-07' to 'TC-009-005';
    dependency CL_010_08_verified_by_TC_007_002 from 'CL-010-08' to 'TC-007-002';
    dependency CL_010_08_verified_by_TC_009_004 from 'CL-010-08' to 'TC-009-004';
    dependency CL_010_08_verified_by_TC_009_005 from 'CL-010-08' to 'TC-009-005';
    dependency CL_010_09_verified_by_TC_007_006 from 'CL-010-09' to 'TC-007-006';

    doc /* Issue22 contract. Delivered: CL-022-01 persistent browser key,
         enrollment, challenge/proof transport, retained-key recovery and the
         browser Log out / forget-rejected-credential actions; CL-022-02 durable
         private record, revocation (logout, revoke-all), dispatch fencing of every
         operating HTTP/WS effect under the authority lock, safety-revision
         advance and the commissioning server API (POST /authorization/v1/commission
         and the status condition). Delivered:
         CL-022-03 'Confirm receive-only setup' UI and the automatic read-only CAT
         lifecycle, CL-022-04 cadence, CL-022-05 CAT status/freshness presentation;
         TC-022-009 automated companions. Radio identity Add/Replace/Remove is dropped
         from the contract (operator 2026-11-06, CL-022-02). The CL-022-05 freeze was accepted on
         the recorded trace (comment 6622256637); TC-022-008 is implemented (its planned Thin/Off
         accounted-traffic companion was retired by #80); TC-022-010 was accepted live (6719540079).
         Existing99 identities retain meaning and numbering. No parser, model
         declaration or issue checkpoint proves execution/acceptance. */
    requirement 'CL-022-01' {
        doc /* Initial bootstrap authorization enrolls one browser proof key for an
             exact station/profile/radio tuple. Grant validity has no time expiry.
             Delivered credential mechanism: browser creates an ECDSA P-256 signing key through WebCrypto;
             private CryptoKey extractable=false, usages=sign only, persisted solely
             in origin-scoped IndexedDB. Public verifier and random grant identifier
             are enrolled over TLS after existing raw-token authorization succeeds.
             Bootstrap token is never put in IndexedDB or other browser stores.
             No export/wrap/postMessage/worker transfer of private key is permitted.
             This deliberately adds one narrowly named browser credential store;
             it does not claim that existing HttpOnly-only policy already permits it.
             localStorage/sessionStorage/URLs/public JSON/logs remain forbidden.
             Non-extractability is an API export barrier, not protection against
             same-origin injected script, browser compromise or disk administrators.
             Existing script/input/Origin/TLS protections remain mandatory.

             Existing 28800-second HttpOnly Secure SameSite=Strict host-only cookie
             becomes a replaceable transport credential, not grant lifetime. Its
             random 256-bit handle refers to the exact active grant; no runtime
             bootstrap token appears in that cookie. On missing/expired transport
             cookie, browser automatically proves its retained key, without token
             entry, before re-establishing HTTP/WS readiness. Thus a closed browser
             needs no background renewal and may return after arbitrary elapsed
             inactivity while its browser profile/key and server grant are retained.
             A finite cookie extension is not the persistence mechanism.
             Credential erasure/eviction, private-mode loss, origin change and lost
             browser profile are reported as lost credentials, never fabricated as
             revocation or recovered by an embedded bootstrap secret. Browser storage
             retention cannot be guaranteed against erasure by the user agent/OS;
             supported acceptance retains the same ordinary persistent profile.

             Renewal uses a fresh cryptographically random 32-byte one-use challenge
             valid for60seconds, bound to exact HTTPS origin, station/profile/radio,
             grant identifier and protocol version. Signed payload is unambiguous
             length-delimited canonical bytes including the challenge; no arbitrary
             signing oracle. Server consumes a valid challenge atomically before
             cookie issuance; replay/wrong tuple/wrong origin/expired challenge fails.
             Exact Origin is required on enrollment/challenge/proof/revocation; no
             credentialed CORS. Preserve existing TLS and10attempts/60seconds per
             process admission ceiling and1024-byte authentication payload cap.
             Decision (issue22 supervisor): that ceiling is the SETUP budget and counts
             only POST /session, bootstrap-scope and enroll. Grant operations
             (challenge, proof, status, receipt, revoke, commission) never spend it, so
             several browsers can enroll and reconnect at once; they stay bounded by
             the64 pending one-use60s challenges (429 on saturation), one transport
             per grant, proof-of-key and the1024-byte cap.
             New strict typed auth payloads/endpoints are explicit canonical API
             additions, not extra keys silently accepted by old POST /session.
             Cookie missing/duplicate/malformed/wrong profile remains401; automatic
             proof recovery is a separate authenticated transition, not a401 bypass.
             At most64 active grants and64 pending challenges per profile process;
             challenge saturation fails closed429, new enrollment beyond grant cap
             fails explicitly and never expires/evicts an existing unrevoked grant.
             Expired/consumed challenges and expired transport handles are removed;
             no background elapsed-time deletion of active grant verifiers.
             Rejected or lost credentials are terminal for automatic recovery: a
             retained-rejected, invalid or missing credential is never retried
             without an operator action, so it cannot spam challenges or drain any
             admission bound; transient failures back off exponentially to60s.
             Opening a page with a retained credential starts its renewal only after the
             page's load event (issue10 TC-007-005): the asset bytes share the link with
             the challenge, whose 10 s attempt bound would otherwise run out behind them
             and add the 4 s back-off to the first status. A browser without a usable
             credential shows the token form without waiting for the load event.
             Slow-link setup retry (operator decision 2026-11-03, issue22): during one
             token login each setup step (POST /session, bootstrap-scope, enroll, and
             the challenge/proof/status renewal) has its own 10 s attempt bound. A step
             whose attempt timed out or failed on the network (no HTTP status) is
             retried automatically, at most 3 attempts per step after 1 s then 2 s,
             and the whole login stops after 45 s, without a second operator press.
             Enroll repeats the same operation ID and verifier (idempotent receipt);
             a renewal attempt starts from a fresh challenge. Any HTTP refusal
             (401/403/409/413/429/503) or invalid/mismatched response is definitive
             and never retried. While retrying the existing authorizing state stays
             and the connection status shows 'Retrying authorization' with the attempt; page
             unload (pagehide) cancels pending attempts and waits. Each retried
             session/bootstrap-scope/enroll attempt spends the setup budget above.
             Browser Log out revokes this grant (revoke all_for_radio=false), then
             deletes the local key after the committed receipt; the server clears
             the transport cookie. A confirmed rejected/invalid retained credential
             offers 'Forget this browser credential and authorize again', which
             deletes only the local key and shows the bootstrap token form. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/authorization.js; client/app.js; server/src/authorization.rs; server/src/authorization_http.rs";
    }
    dependency CL_022_01_to_FR_019 from 'CL-022-01' to 'FR-019';
    dependency CL_022_01_to_FR_021 from 'CL-022-01' to 'FR-021';
    dependency CL_022_01_to_FR_022 from 'CL-022-01' to 'FR-022';
    verification 'TC-022-006' {
        doc /* TC-022-006, CL-022-01/02; cost2 profiles/protocol companions
             using existing TLS/browser helpers. Reopening a page with a retained credential while
             its last asset is held sends no challenge before the load event, then one.
             Fresh-browser initial journey: POST
             session204 then bootstrap-scope200 with strict independently expected tuple;
             no ordinary status/grant, challenge/transport or CAT I/O is created by read.
             Enroll that exact scope, prove key possession, then grant status is usable.
             Missing/expired/duplicate/cross-profile bootstrap401, wrong Origin403, bad
             TLS/type/unknown/duplicate fields/body/rate bounds have zero effects. Race
             a configuration edit after scope read: stale enrollment409 and no verifier.
             Scope wire oracle is exactly profile_id/radio_id/safety_revision, never
             body Origin; reject body-origin/extra/duplicate keys. Independently use
             valid long saved-origin admission fixtures up to the existing6174 escaped
             origin-byte allowance; exact Origin header is still required, signed
             bytes contain that full origin, compact auth bodies do not echo it.
             Hand-count canonical ASCII widths (UUID36/revision16/IDs43/key87/signature86),
             including JSON quotes/punctuation: scope138, enrollment374, receipt-proof426,
             challenge-response396, conservative receipt302 and bootstrap response170.
             Require actual compact serialization
             <= these envelopes and <=1024; no candidate serializer as expected oracle.
             Full status still includes bounded receive/error fields within1024, not
             truncation or a weakened origin/profile domain. Whitespace-padded request
             exactly1024 accepted when otherwise valid,1025 rejected before effects.
             Independently count volatile transport entries: two valid proofs for A
             leave exactly one current handle, old cookie401/new cookie200, B unchanged;
             <=64 entries, no verifier eviction. Verify durable verifier/receipt bytes,
             revocation generation and commissioning unchanged, with zero independently
             counted native open/query/set/PTT/close effects. Invalid/replayed/expired/
             wrong-Origin/wrong-scope proof and failed randomness/response preparation
             retain the prior current handle. Receipt-purpose proof never rotates it.
             At exact monotonic28800 expiry only transport becomes unusable; purge and
             restart retain grants/receipts/commissioning. Use two ACTUAL tabs sharing
             one context to overlap valid proofs and hold/reverse Set-Cookie responses:
             last committed proof owns the sole handle, while late delivery can yield401.
             Include lost204, existing openWS and queued user mutation; after held
             responses quiesce, fresh proof AND protected read-only status restore the
             shared cookie without key deletion/token prompt or automatic mutation
             replay. UI truth remains<=2s; rotation alone does not revoke an existing
             WS grant or disconnect CAT/audio, while actual revoke still fences effects
             and closes affected WS. Same-document readiness sharing is not a claimed
             cross-tab lock; keep rate10/60 and all other caps/budgets unchanged.
             A record with a null scope, which no delivered operation writes, returns null
             and enrolls nothing (no automated case). Authorize A once; preserve ordinary
             browser profile/key, close actual browser process, remove/expire only its
             transport cookie under test control, advance injected times across28800s
             and browser-cookie retention boundary, restart server/browser. A becomes
             usable through signed proof with zero bootstrap submissions; no long real
             wait claimed. Test retained identity/revision vs another scope, other
             profile/origin, malformed/duplicate cookies, stale/replayed/wrong tuple/
             expired signatures, consumed nonce and challenge saturation. Independently
             fixed tuples/challenge bytes and effect counters are oracle, not server
             status. Erase stored key: explicit lost credential, zero silent recreation.
             Block/corrupt IndexedDB, verifier read/write/commit: explicit failure, no
             unauthorized enrollment or CAT I/O. Reject export/wrap/transfer of key by
             application paths. Verify new-browser bootstrap still required.
             Lost-enrollment-response oracle: hold response independently, persist
             enrollment then drop response and restart server/browser with same
             profile/key/operation ID. Independently inspect committed-store fixture
             and native peer: one retained grant, no duplicate enrollment and zero
             queued browser CAT effects while unauthorized/unknown. Read-only receipt
             reconciliation identifies the exact committed tuple/verifier, then scoped
             proof establishes readiness. Contrast pre-commit failure: no retained
             grant after restart and no successful receipt/proof. No assumption that
             server can observe browser receipt of a success response is allowed.
             Slow-link setup retry oracle (independent request counters on the actual
             browser; the page's clock is installed before load and driven, issue70,
             no real wait): hold the first bootstrap-scope response; at 9999 ms no
             retry is shown and one bootstrap-scope was sent, at 10000 ms the status
             shows 'Retrying authorization (attempt 2 of 3)'; the late response is
             then delivered and the page becomes connected after one token press with
             one session, two bootstrap-scope and one enrollment.
             A network-failed enrollment is repeated once with the identical operation
             ID and verifier and connects. Network failure of every /session
             attempt: 1 attempt at +999 ms and 2 at +1000 ms after the first failure,
             2 at +1999 ms and 3 at +2000 ms after the second, then 'Could not
             authenticate', and still exactly 3 after the clock runs past the 45 s
             login bound. A 401 bootstrap-scope is never retried (counts 1/1/0 after
             the clock runs past 45 s). A pagehide event on the live page during a
             held attempt cancels it: no further setup request after the clock runs
             past 45 s (counts 1/1/0).
             Held profile bodies across a renewal (#73): a GET /profile 200 whose body is held
             while the transport cookie is cleared, the authorization renews and a new
             socket connects is never applied ('Could not load saved settings', form
             kept). A PUT /profile 200 held the same way is the save's outcome
             (CL-073-01): on release 'Saved revision 1', Save enabled, the form holds
             the saved value, exactly one PUT and revision 1 on disk.
             Grant revocation and configuration edits (operator 2026-11-06: moved here from
             the retired TC-022-007). Disable/re-enable and endpoint edit preserve UUID;
             endpoint change advances safety revision/invalidates commissioning only.
             Two A browser grants plus B; logout one A leaves otherA/B; revoke-allA
             removes bothA only; restart cannot revive acknowledged revocation. Race
             queued HTTP/WS mutations and selection against revocation with independently
             held dispatch barrier and peer counters: none dispatches after commit;
             pre-dispatched effects follow cancellation/release rather than fabricated
             rollback. Drop ack before/after commit, retry same operation ID, reload
             receipt; no duplicate operation or new credential. Inject durable-write
             failure/restart and verify documented last-committed-state limitation and
             failclosed current process. Cap64 grants without evicting active grants;
             delete verifier and replay old proof/cookie: rejected, no tombstone growth.
             Automated companions: tests/profiles.test.cjs TC-022-006 cases (TC-022-004
             covers browser logout and revoke-all) and server/src/auth_tests.rs, including
             plaintext runtime-token operating access, logout/revoke fencing of every
             operating HTTP route and WS upgrade, foreign grant refusal and commission
             receipts; station-authority unit tests in server/src/authorization_tests.rs.
             Injected-time restart: the store-level cases there use an injected clock (a
             transport usable at 28799 s and refused at exactly 28800 s, a challenge 400 days
             on, a reopen keeping grants and receipts with no transport), and
             tests/profiles.test.cjs "actual browser and server process restart" removes the
             cookie and restarts both processes. Only the slow-link setup retry case
             drives a browser's clock; the cookie-retention and 28800 s combination stays
             unautomated, and TC-022-010 observes controlled cookie expiry live. */
        attribute automation : AutomationState = AutomationState::partial;
        attribute executable : String = "tests/profiles.test.cjs; server/src/auth_tests.rs; server/src/authorization_tests.rs";
        objective {
            verify 'CL-022-01';
            verify 'CL-022-02';
            verify 'CL-073-01';
        }
    }
    dependency CL_022_01_verified_by_TC_022_006 from 'CL-022-01' to 'TC-022-006';
    verification 'TC-022-010' {
        doc /* TC-022-010 CL-022-01..05 authorized cost4 IC7300 receive-only acceptance. Record the actual deployed SHA/receipt/fresh radio identity and preserve official
             WSJTX noCAT/PTT comparison. Observe explicit initial commissioning once,
             ordinary startup/reconnect with no Connect buttons, unavailable/return/
             cable/server/browser restart, truthful independent health/freshness and
             latest real decode rows. Retained-browser proof after controlled cookie
             expiry is observed; simulated clock boundary labelled simulated. PTT
             remains released; zero transmit acceptance is added. Accepted live
             on 2026-11-08 (6719540079); the freeze is accepted on the trace. Independent source/model review,
             red-on-parent, exact ordinary gates and actual acceptance all required.
             Where: HB9BLA installed exact gated candidate, actual IC-7300 COM3/USB Audio CODEC and authenticated browser. Physical acceptance is planned and consent-bound, not an automated simulator verdict. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-022-01';
            verify 'CL-022-02';
            verify 'CL-022-03';
            verify 'CL-022-04';
            verify 'CL-022-05';
        }
    }
    dependency CL_022_01_verified_by_TC_022_010 from 'CL-022-01' to 'TC-022-010';
    requirement 'CL-044-05' {
        doc /* PUT /profile refuses an audio device that is not a WASAPI endpoint ID: settings.audio.input_device must be a capture endpoint ID {0.0.1.00000000}.{GUID} and settings.audio.output_device a render endpoint ID {0.0.0.00000000}.{GUID} (lower- or upper-case hex), else 400 audio_device_not_endpoint with the field; null stays allowed. At station start an existing profile whose device entry is not an endpoint ID is migrated: when exactly one active endpoint of that flow has exactly that friendly name, the entry is replaced by its ID and the profile saved (revision + 1); otherwise it is kept and the startup log names the field and the reason (not_found or ambiguous). Loading a profile never fails because of a device entry. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; server/src/main.rs; server/src/radio_control/setup.rs; server/src/audio/windows.rs";
    }
    dependency CL_044_05_to_FR_001 from 'CL-044-05' to 'FR-001';
    dependency CL_044_05_to_FR_002 from 'CL-044-05' to 'FR-002';
    dependency CL_044_05_to_FR_016 from 'CL-044-05' to 'FR-016';
    requirement 'CL-044-06' {
        doc /* Settings > Radio "Detect radio" (operating screen of #37): the Detect radio button is enabled only after the operator ticks the confirmation that USB SEND and USB keying (CW/RTTY) are OFF or the radio is on a dummy load, and that opening a port can pulse DTR/RTS also on other CP210x boards; one press sends one POST /radio/detect {v 1, profile_id, boot_id, keying_inhibit_confirmed true} and clears the tick. Nothing is fetched without a press (no polling). The panel shows each port's state and radio, the proposal (port, model, CI-V address, baud, control endpoint, input and output endpoint names as CL-044-07 (the endpoint ID only on hover), or "not matched") and the settings items with value, severity and guidance. "Use this setup" only fills the Radio section (control mode, endpoint, PTT, audio input and output IDs); the operator saves it with Apply ⟳, which restarts receive as any Radio change, and then gives the existing receive-only confirmation (CL-022-03). "Apply recommended radio settings" and "Undo radio settings" are enabled only while CAT is ready with a known connection generation, the transmit state is known (the operating client with its confirmation dialog is loaded) and the transmitter is disarmed and not tuning, each asks its own confirmation and sends one POST /radio/settings/apply or /undo {v 1, profile_id, boot_id, connection_generation}, then shows the written items or the refusal. All server text is shown as text. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js";
    }
    dependency CL_044_06_to_FR_019 from 'CL-044-06' to 'FR-019';
    requirement 'CL-044-08' {
        doc /* Settings > Radio has one Audio section (#settings-audio, a restart setting marked ⟳) holding all audio settings: the Input select with the Rx level meter beside it, the Output select, and the radio's recommendation. Each select offers "None" (null) and the endpoints of its flow from GET /audio/endpoints (read when the Settings drawer opens, at most every 5 s, and after Reload saved settings or a save); an option's text is the label of CL-044-07, its value the endpoint ID, and the ID appears only in the option's hover title and in Settings > Expert ("Audio endpoint IDs": the saved input and output IDs). A saved endpoint that is not present is shown as the selected, disabled option "<last known name> · not present"; while the listing is unavailable the saved value stays selected as "Saved device". There is no free-text endpoint input and no separate input listing. When an endpoint is marked with the radio, the section shows "Recommended: <input label> / <output label>" and the button "Use IC-7300 audio", which selects those endpoints and saves them with the same Apply ⟳ (one PUT /profile, with its usual confirmation); choosing in a select alone saves nothing. The Audio capability line in Expert names the running input by /receive audio.device_name. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/index.html; client/app.js; client/recording.js";
    }
    dependency CL_044_08_to_FR_019 from 'CL-044-08' to 'FR-019';
    dependency CL_044_08_to_FR_002 from 'CL-044-08' to 'FR-002';
    verification 'TC-044-007' {
        doc /* TC-044-007 — Audio section shows names, not endpoint IDs
             CL-044-08
             Setup: actual candidate server on a disposable plaintext profile whose saved input is a fixture capture ID and Chromium; GET /audio/endpoints answered by a route fixture (the CODEC pair marked IC-7300, two same-named headsets, the saved input absent with its last known name), so no device is read.
             Steps: open Settings > Radio; read the Audio section, its options and their hover titles; read Settings > Expert; choose the second headset (no PUT); press Use IC-7300 audio; GET /profile; 360 px width.
             Expected: one Audio section holding #audio-input, the Rx level meter and #audio-output, no #audio-enumerate, no text input for a device; option texts "Microphone (USB Audio CODEC) — IC-7300", "Headset ... #1", "... #2", the saved input selected, disabled and labelled "... · not present"; no visible text of the Radio section contains an endpoint ID ("{0.0."), each option's title is its ID, Expert shows the saved ID; choosing sends no PUT; Use IC-7300 audio sends exactly one PUT /profile and the saved profile holds the two CODEC IDs; no horizontal scroll at 360 px; no page error.
             2 — Isolated automated browser test; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-08';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_044_08_verified_by_TC_044_007 from 'CL-044-08' to 'TC-044-007';
    verification 'TC-044-005' {
        doc /* TC-044-005 — Detect radio panel
             CL-044-06
             Setup: actual candidate server on a disposable plaintext profile (CAT not authorized, so no CAT owner opens anything) and Chromium; /radio/detect and /radio/settings/* answered by route fixtures with a hand-written IC-7300 proposal on COM250, so no serial port is probed.
             Steps: (separately) hold back the operating client and press Apply recommended radio settings with CAT ready; open Settings > Radio; wait 1.5 s; try Detect radio without the tick; tick and press it; Use this setup; check Apply/Undo with CAT not ready; with CAT ready and the station's connection generation, Apply recommended radio settings, cancel, again with Continue, Undo with Continue; Apply ⟳; GET /profile; 360 px width.
             Expected: with the client held back both buttons disabled and no /radio/settings request; no /radio request before the press; the button disabled without the tick; exactly one detect body {v 1, profile_id, boot_id, keying_inhibit_confirmed true}; port, model, 94h, 19200, endpoint, both friendly names (each endpoint ID only in its hover title, not in the text) and the 0078 DTR blocking item shown; the tick cleared; the five Radio fields filled with no PUT; Apply/Undo disabled until CAT ready; the cancelled apply sends nothing, then exactly apply and undo with {v 1, profile_id, boot_id, connection_generation} of that generation; the saved profile holds the proposed control and the two endpoint IDs; no horizontal scroll at 360 px; no page error.
             2 — Isolated automated browser test; Windows development PC, no radio, serial port or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-06';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_044_06_verified_by_TC_044_005 from 'CL-044-06' to 'TC-044-005';
    dependency CL_044_05_verified_by_TC_044_002 from 'CL-044-05' to 'TC-044-002';
    dependency CL_044_05_verified_by_TC_044_004 from 'CL-044-05' to 'TC-044-004';
    // #68 (operator 2026-11-08: "you could show it somewhere in the UI and mark it red if it is
    // above two"; grill-me 2026-11-09: end of the Rx/Tx strip, the last reading stays, red
    // strictly above 2.0, the error field entries and the Tx stop at 3.0 unchanged).
    requirement 'CL-068-01' {
        doc /* (#68) SWR on the operating screen. The Rx/Tx strip under the waterfall (WstxOperatingLayout::RxTxStrip) ends, after Rx=Tx, with the text "SWR x.x": the SWR of the latest radio.tx_level push (CL-044-13) of this profile and boot, swr_x10 / 10 with one decimal, shown while that push has managed true and meters with a non-null swr_x10, and hidden otherwise (no push yet, meters null, swr_x10 null, managed false, or a station-ready of another boot). The value is the last reading: it stays after the transmission or Tune that produced it, until a push changes it, and is not cleared by a band change. It is red, in the page's error colour (--op-error, remapped by the Day and Night themes like the page), when swr_x10 is above 20 (2.1 and up; on the IC-7300 raw 0084 and up), and in the strip's normal text colour at 20 (2.0) and below. Nothing is requested or polled for it: it follows the pushed radio.tx_level only. It takes no pointer input and adds no strip line: at 1366x768 and wider the strip keeps its one-line height and the waterfall its place; at 360 px the strip may wrap, with no horizontal scroll. Unchanged by #68: the meter readings and their timing (CL-044-14: one reading per transmission, once per second during Tune, pushed only when they change), the Settings > Radio > Audio meter line (CL-044-13), the error field entries txSwrHigh (SWR at or above 2.0 from the third transmission in a row) and txSwrFault (CL-037-02), and the station's own Tx stop at SWR at or above 3.0 (raw 0120, CL-044-14). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/contact.js; client/recording.css";
    }
    dependency CL_068_01_to_FR_019 from 'CL-068-01' to 'FR-019';
    verification 'TC-068-001' {
        doc /* TC-068-001 — SWR at the end of the Rx/Tx strip
             CL-068-01
             Setup: actual candidate server on a disposable plaintext profile and Chromium at 1366x768, 1920x1080 and 360x800; radio.tx_level events injected into the page's station-message stream as the server sends them (as TC-044-015), every request of the page recorded.
             Steps: (a) open the operating screen with no radio.tx_level yet; (b) push managed true, meters null; (c) push meters {alc 0, po_pct 40, swr_x10 null}; (d) push swr_x10 14; (e) push a level change with the same meters (as after the transmission); (f) a band change; (g) push swr_x10 20, then 21, then 30 with warnings [swr_fault]; (h) in the Dark, Day and Night themes read the colour at 14 and at 21; (i) push managed false with swr_x10 14; (j) push managed true with swr_x10 14 and another profile's id, then a station-ready of another boot; (k) at each width measure the strip's height and the waterfall's top and height with and without the value; (l) click the value.
             Expected (oracle: CL-068-01 and the operator's #68 answers): (a) to (c) no SWR text in the strip; (d) the strip's last item, after Rx=Tx, reads exactly "SWR 1.4" in the strip's normal text colour; (e) and (f) still "SWR 1.4"; (g) "SWR 2.0" not red, "SWR 2.1" and "SWR 3.0" in --op-error, and the error field shows its swr_fault entry as before; (h) in each theme the 2.1 colour is the theme's --op-error and the 1.4 colour the strip's text colour; (i) hidden; (j) unchanged by the other profile's push, hidden after the other boot's station-ready; (k) at 1366x768 and 1920x1080 the strip height, waterfall top and height equal those without the value (within 0.5 px); at 360x800 no horizontal scroll; (l) no request, nothing changes; no request at all caused by the pushes and no timer request; no page error. Red on the parent: no SWR text in the strip.
             2 — Isolated automated browser test; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-068-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_068_01_verified_by_TC_068_001 from 'CL-068-01' to 'TC-068-001';
    verification 'TC-068-002' {
        doc /* TC-068-002 — SWR on the operating screen on HB9BLA
             CL-068-01
             Setup: the gated candidate installed on HB9BLA, the IC-7300 on CAT on 40 m FT8 into the station antenna, within the operator's standing transmit consent; the radio.tx_level frames recorded from the station's socket.
             Steps: open the operating screen after a station restart; transmit at least two FT8 transmissions (a CQ suffices); after the last one watch the strip through the following receive period; switch to 20 m without transmitting.
             Expected (oracle: the recorded radio.tx_level frames, not the radio's display, operator decision of 2026-11-08): no SWR text before the first reading; from the first frame with meters the strip's last item reads "SWR " and swr_x10 / 10 of the latest frame, red exactly when that is above 2.0 (on the station antenna normally not red); the value stays through the receive period after the transmission and after the band change; the Settings > Radio > Audio meter line shows the same SWR; the strip stays one line at the operator's screen width. A mismatched antenna is not used (#44 decision of 2026-11-08); red is proven by TC-068-001.
             5 — Live with RF on the station, operator consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-068-01';
        }
    }
    dependency CL_068_01_verified_by_TC_068_002 from 'CL-068-01' to 'TC-068-002';

    // #57 Decode display speed (operator 2026-11-02; defaults recorded on issue #57).
    requirement 'CL-057-01' {
        doc /* Band Activity on the Detailed display profile shows a published decode view without waiting for a refresh cadence: each new or grown latest_decode publication is announced to every Detailed WebSocket peer at once as a receive.state event (Thin and Off peers keep the 2 s receive tick), and a Detailed browser then fetches the view's records immediately, page after page (limit 16), until its cursor reaches the view's frozen end, instead of at most once per 4 s. A failed result read (which falls back to at most once per 4 s until a page succeeds) and the Thin rules (one pending request, limit 1, at most once per 4 s, page at most 3072 bytes) are unchanged; with no announced or unread view and no failed GET /receive or result read, the idle read on every display profile is only a safety read at most once per 30 s (#10 WstxStationProtocol::PushedStationState), so the two-browser 32 kbit/s budget still holds. On a LAN every row of a published view is painted at most 0.3 s after its publication; "Loading results" shows only while records of the view are still being fetched. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/recording.rs; server/src/main.rs; client/recording.js";
    }
    dependency CL_057_01_to_FR_010 from 'CL-057-01' to 'FR-010';
    dependency CL_057_01_to_FR_019 from 'CL-057-01' to 'FR-019';
    verification 'TC-057-001' {
        doc /* TC-057-001 — Busy live period reaches Band Activity promptly (Detailed)
             CL-057-01
             Setup: actual isolated station Router, Recording owner, native live source, converter, UTC window schedule and modem, fed in real time with the hash-pinned busy recording websdr_test7.wav as 48 kHz native capture whose QPC clock is the system clock, filling an FT8 UTC period and again the periods 30 s and 60 s later, with silence around them; one Chromium page on the Detailed default.
             Steps: start FT8 receive from the Receive stopped chip; record the server's published counters and latest_decode (1 ms sampling), the browser's receive.state frames, /receive and /receive/results requests and every Band Activity change at the next animation frame, all on the system clock; read the first two period views' records through the actual results API; while the third busy period is published, every /receive/results read answers 503 for 9 s, then normally.
             Expected (independent oracle: the published records themselves and the issue's 0.3 s decode-to-row target): for each of the two periods: at least 25 records in the view; the painted rows are exactly the view's records (same message texts); every row is painted at most 300 ms after the view's publication. During the outage the failing reads start at least 3950 ms apart (no faster retry with records pending), and the third period's rows are painted within 5 s after reads recover. The parent client (2 s receive tick, one 16-record page per 4 s) painted them about 5 s after publication.
             2 — Isolated automated functional test; Windows PC, release build, WSTX_SAMPLE_DIR, no radio or audio device. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-057-01';
        }
        attribute executable : String = "server/src/receive_http_tests.rs; tests/receive-latency.test.cjs";
    }
    dependency CL_057_01_verified_by_TC_057_001 from 'CL-057-01' to 'TC-057-001';
    dependency CL_057_01_verified_by_TC_057_002 from 'CL-057-01' to 'TC-057-002';
    verification 'TC-057-003' {
        doc /* TC-057-003 — Live decode display on HB9BLA
             CL-057-01, CL-057-02, CL-007-05
             Setup: the gated candidate installed on HB9BLA, IC-7300 on COM3 receiving a busy FT8 band, one browser on the LAN on the Detailed profile; no transmission.
             Steps: watch Band Activity over 10 consecutive FT8 periods; read GET /receive audio over the same periods.
             Expected: no "Loading results" visible in normal operation; every row of each period is painted by period start + 15.3 s (CL-007-05 publication by +15.0 s plus CL-057-01's 0.3 s; #72), the observed times being reported; under that decode load no audio_stalled loss (#49): loss_epochs unchanged.
             4 — Live on the station, receive only; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-057-01';
            verify 'CL-057-02';
            verify 'CL-007-05';
        }
    }
    dependency CL_057_01_verified_by_TC_057_003 from 'CL-057-01' to 'TC-057-003';
    verification 'TC-055-006' {
        doc /* TC-055-006 — Band Activity colours, hover text and value order for every sender
             CL-055-04, CL-055-02
             Setup: actual router with a selected profile whose log holds DL1ABC JO62 20m FT8 (TC-055-002); in the browser the operating fixture with routed result records carrying #55 flags and dxcc, selection band 20m and the worked_status of each sender.
             Steps: read /receive/results for a report and an R-report to other stations from new senders (K9XX G4XYZ -10, K9XX YO3ABC R-07) and an RR73 from a sender worked on 20m FT8 (K9XX DL1ABC RR73); in the browser render one period with a report from a new-DXCC sender (YO3ABC K9XX -07), a row to my call, a new CQ zone, a new grid, a new call, two rows of equal value with different SNR and a worked-before CQ without flags; turn Highlight on with a strategy hit.
             Expected: the server gives both non-CQ senders their dxcc and flags (England new call, DXCC and ITU zone; Romania new DXCC) and the worked sender Germany without flags; the YO3ABC report colours only its sender call new DXCC (#50 CL-050-08) and its reason tip is "New DXCC · New call"; the row to my call keeps the my-call colour over the whole row and its tip is "New call"; the new CQ zone CQ is coloured over the whole row; the worked-before CQ has no colour and no reason tip; rows are in value order calling me, strategy hit, new DXCC, new zone, new grid, new call, no flag, equal values strongest first; the DXCC header restores this order after a Freq sort.
             2 — Isolated automated (functional) tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-055-04';
            verify 'CL-055-02';
        }
        attribute executable : String = "server/src/dxcc_tests.rs; tests/ui-operating.test.cjs";
    }
    requirement 'CL-054-01' {
        doc /* A Detailed waterfall subscriber receives every Detailed row of the current job in order after a processing stall: the station retains the last 25 rows and sends each peer the oldest row it has not sent, 200 ms apart, 170 ms apart while rows wait (WstxStationProtocol::TransferDisplay). Live Thin sends keep a fixed 2 s grid from the previous deadline, restarted at a send more than 1 s late, so sends stay at least 1 s apart. The browser draws a gap row only for a real gap; one or two live Thin rows paced out between two sent rows are drawn with the next row. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/recording.rs; server/src/main.rs; client/recording.js";
    }
    dependency CL_054_01_to_FR_019 from 'CL-054-01' to 'FR-019';
    dependency CL_054_01_to_FR_021 from 'CL-054-01' to 'FR-021';
    requirement 'CL-111-04' {
        doc /* Display. On a station with transmit capability the operating view shows the transmit state and the cause of its last change at all times, in every region, at 360 px and at 1366x768. It follows only the pushed station state and takes no pointer or keyboard input. Texts. On: "Tx on"; "Tx on · Auto". Off: "Tx off" (startup); "· QSO complete"; "· QSO cancelled"; "· halted"; "· Tx watchdog: same message sent N times"; "· radio lost"; "· radio settings changed"; "· Tx refused · <reason>"; "· <call> works another station"; "· mode changed"; "· band changed"; "· automation ended". Not delivered yet: the display. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    dependency CL_111_04_to_FR_019 from 'CL-111-04' to 'FR-019';
    requirement 'CL-111-09' {
        doc /* The Now button is removed. The Tx lines of the fold-out "Messages Tx1-Tx6" keep their Next choice and their text and have no Now button. Not delivered yet: the Now button is still there. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    dependency CL_111_09_to_FR_019 from 'CL-111-09' to 'FR-019';
    verification 'TC-111-005' {
        doc /* TC-111-005 — The display shows state and cause
             CL-111-04
             Setup: Chromium against the candidate server with a recording hardware double.
             Steps: each text of CL-111-04, at 360x800 and 1366x768, in each region, after a reload and in a second browser; a click and a key on the display.
             Expected (the texts of CL-111-04): each text is shown; the click and the key send no request.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-111-04';
        }
    }
    dependency CL_111_04_verified_by_TC_111_005 from 'CL-111-04' to 'TC-111-005';
    verification 'TC-111-014' {
        doc /* TC-111-014 — No Now button
             CL-111-09
             Setup: Chromium against the candidate server.
             Steps: the fold-out "Messages Tx1-Tx6"; choosing Next on a Tx line.
             Expected (CL-111-09): no .ct-now element; each Tx line has its Next choice and text; choosing Next sends one choose_next and no start.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-111-09';
        }
    }
    dependency CL_111_09_verified_by_TC_111_014 from 'CL-111-09' to 'TC-111-014';
    dependency CL_111_04_verified_by_TC_111_015 from 'CL-111-04' to 'TC-111-015';
    verification 'TC-054-001' {
        doc /* TC-054-001 — Detailed rows in order after a stall; gaps only for real gaps
             CL-054-01
             Setup: the station's detail_after/arm_detail functions with a hand-written ring; the browser page with injected live frames.
             Steps: five rows 11..15 retained after the socket sent row 10; a new job's rows; a caught-up socket; Thin sends 100 ms late for 10 periods, after a 5 s pause, 1.5 s and 1 s late; inject live Thin frames 0, 2, 5, 6 and 10; run the Detailed replay cadence.
             Expected: rows 11..15 sent once in order, "behind" true until the last; a new job starts at its oldest row; nothing resent; catch-up spacing 170 ms, steady 200 ms; Thin anchors stay on the 2 s grid, restart after the pause and after a send 1.5 s late, and the next send is at least 1 s later; row 1 drawn with row 2's levels and rows 3..4 with row 5's, rows 7..9 grey gaps; Detailed sends at least 165 ms apart and at most 5.9 per second.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-054-01';
        }
        attribute executable : String = "server/src/protocol_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_054_01_verified_by_TC_054_001 from 'CL-054-01' to 'TC-054-001';
    verification 'TC-054-003' {
        doc /* TC-054-003 — Live waterfall on HB9BLA
             CL-054-01, CL-054-02, CL-050-01, CL-050-02
             Setup: the gated candidate installed on HB9BLA, 40 m FT8 receive, the operator's page.
             Steps: watch 5 min of receive; the operator, who knows the WSJT-X Wide Graph, judges the waterfall against it (coordinator decision on #54: no WSJT-X GUI run).
             Expected: no grey seams during continuous receive; FT8 signals show start and end; strong signals distinguishable; the operator confirms the colours and the pointer mapping.
             3 — Live, read-only on the station; with the operator at acceptance. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-054-01';
            verify 'CL-054-02';
            verify 'CL-050-01';
            verify 'CL-050-02';
        }
    }
    dependency CL_054_01_verified_by_TC_054_003 from 'CL-054-01' to 'TC-054-003';
    requirement 'CL-037-05' {
        doc /* (#37, operator 2026-11-04: the QSO area offered "Change contact to W4WFC DL1FRH JO30", "This makes no sense") While a contact is active, a click on a Band Activity row offers a contact change only for a row that can start a contact for me, a CQ/QRZ complying with the directed-CQ rule (WstxStrategy::DirectedCqRule, also without Highlight or an active strategy) or a row addressed to my call, and the offer names the sender ("Change contact to K1ABC"); a click on a row of a QSO between others or on a CQ directed elsewhere offers nothing and leaves no refusal text. A deliberate double-click on such a row calls its sender and its command line reads "Call <sender>", never the foreign message. Details: WstxOperatingLayout::BandActivityView. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.js; server/src/contact_http.rs";
    }
    dependency CL_037_05_to_FR_007 from 'CL-037-05' to 'FR-007';
    verification 'TC-037-004' {
        doc /* TC-037-004 — A contact change is offered only for a row that can start a contact for me
             CL-037-05
             Setup: actual candidate server and Chromium at 1366x768; my continent EU from HB9BLA; routed live rows "CQ K1ABC FN42", "QRZ W1XYZ FN31", "HB9BLA DL1ABC JO31", "W4WFC DL1FRH JO30", "CQ EU G4ABC IO91", "CQ DX K2DX FN42" (NA), "CQ NA K3NA FN42" and "CQ DX DL2DX JO31" (EU); a running contact with IW9FRA; a routed POST /contact/command that refuses select_row without replace as directive_not_answerable for "CQ NA K3NA FN42" and "CQ DX DL2DX JO31" and as contact_active for the other rows, and accepts everything else.
             Steps: click each row and read the change button and the command line; double-click the foreign row and read the commands and the command line.
             Expected (independent oracle: the operator's report of 2026-11-04 on #37): CQ, QRZ, addressed and complying directed rows offer "Change contact to K1ABC", "Change contact to W1XYZ", "Change contact to DL1ABC", "Change contact to G4ABC" and "Change contact to K2DX"; the foreign row and both CQs directed elsewhere each remove the offer, show none and leave the command line empty; its double-click sends select_row with replace true, then enable_tx, and the command line reads "Call DL1FRH: accepted".
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-037-05';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_037_05_verified_by_TC_037_004 from 'CL-037-05' to 'TC-037-004';
    // #74 An open page after a station restart (operator 2026-11-08, one grill-me round).
    requirement 'CL-074-01' {
        doc /* (#74, live acceptance 2026-11-08, #39 comment 6719540492: after a station restart an open page kept "Strategy Farthest new on band · Auto off" until reloaded, while the station had None and Auto off) After a station restart an open page shows the new boot's state without a reload, within the push rule. When the browser learns a boot_id other than the one a view's held station state belongs to, that view drops the state at once and shows the form of a freshly loaded page before its reads; it never shows a value of the previous boot, alone or with values of the new boot; a snapshot reply naming another boot is discarded; once the new boot's reads and first events have arrived the page equals a freshly loaded one. The automation view reads GET /automation only after an automation.state event, never once per socket, and on a new boot holds the never-used state without a request. The strategy element's line is drawn from the current strategy and automation snapshots together at each change of either; with None and no strategy run it shows the automation text, "Automation idle" without a run. No new request kind, no retry timer, no server change. Details: WstxStationProtocol::PushedStationState, WstxMcp::AutomationIndicator, WstxStrategy::StrategySelector. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/app.js; client/contact.js; client/recording.js";
    }
    dependency CL_074_01_to_FR_019 from 'CL-074-01' to 'FR-019';
    verification 'TC-074-001' {
        doc /* TC-074-001 — Reproduction: a page open across a station restart
             CL-074-01
             Setup: the actual isolated candidate server restarted under the test's control with the page left open (as the #22 restart in tests/receive-page.test.cjs), Chromium at 1366x768, no radio; the page's GET /strategy of the new socket held back 2 s by the test (the order a thin link gives), other requests unchanged; requests recorded.
             Steps: select "Farthest new on band" with Auto off and wait for "Strategy Farthest new on band · Auto off"; restart the server; record the line #station-automation, the selector and the Auto button at each change from the reconnect until 3 s after GET /strategy answered; then open a second page on the same server and read the same three.
             Expected (oracles: the station's state after a restart, active None and Auto off, WstxStrategy D2; the freshly opened second page): the line never shows "Strategy Farthest new on band" after the new boot is learned; at the end the line is "Automation idle", the selector None, and line, selector value and Auto pressed state, disabled state and title equal those of the second page; no GET /automation after the restart (no automation.state while automation is unused); no page error. Red on the parent: the line keeps "Strategy Farthest new on band · Auto off".
             2 — Isolated automated browser test; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-074-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_074_01_verified_by_TC_074_001 from 'CL-074-01' to 'TC-074-001';
    verification 'TC-074-002' {
        doc /* TC-074-002 — The strategy line with None and no strategy run
             CL-074-01
             Setup: actual browser with hand-written replies for GET and PUT /strategy and GET /automation and pushed strategy.state and automation.state (as TC-039-046); no automation.state before the steps.
             Steps: read the line; select "New calls" with Auto off; select None; push a pounce run (automation.state, configuration strategy false, pounce K1ABC waiting); push its stop with reason no_answer; push run null.
             Expected (oracle: the texts of WstxMcp::AutomationIndicator and WstxStrategy::StrategySelector): "Automation idle"; "Strategy New calls · Auto off"; "Automation idle" (not the previous text); "Pounce K1ABC waiting · HALT ends it"; "Automation stopped · no answer"; "Automation idle"; no GET /automation before the first automation.state and exactly one after each. Red on the parent: "Strategy New calls · Auto off" stays after None.
             2 — Isolated automated browser test; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-074-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_074_01_verified_by_TC_074_002 from 'CL-074-01' to 'TC-074-002';
    verification 'TC-074-003' {
        doc /* TC-074-003 — Every view on a new boot
             CL-074-01
             Setup: actual browser and isolated server; the test rewrites the server's replies and socket messages to name boot A, then boot B, and holds boot B's reads (GET /contact, /recording, /strategy, /pskr, /receive/startup, /strategy/alerts) and a boot A POST /strategy/ignore reply until it releases them; boot A has replies for GET /profile, /contact, /strategy (Farthest new on band selected, Auto on), /automation (an active strategy run in contact with K1ABC, with hearing and free_tx_slots, announced by automation.state), /pskr (connected), /receive/startup (Monitor off at startup on), /strategy/alerts and the recording and receive reads, and pushed radio.agc, radio.tx_level and transmit.state of boot A; "Show free Tx slots" on; then the socket closed and a new one whose GET /profile names boot B, the replies of boot B (None, Auto off, PSK Reporter off, Monitor off at startup off, no alerts, no automation.state) each held back 2 s; a late reply of boot A to GET /strategy and GET /pskr delivered after boot B is learned; a second case in which boot B's GET /strategy and GET /pskr answer 503.
             Steps: read every view listed in WstxStationProtocol::PushedStationState at each change from the moment boot B is learned until 3 s after the last reply; then open a second page on boot B's replies and read the same views; count the requests.
             Expected (oracles: the boot B replies written in the test and the second page): from the moment boot B is learned no view shows a value of boot A: line not "Pounce", data-active false, no Free Tx slot marks, no PSK hearing lines, Auto not pressed, the selector not on "Farthest new on band", PSK Reporter and Monitor off at startup not shown as on; while the replies are held each faulty view shows the second page's form before its reads; the late boot A replies change nothing; at the end every view equals the second page's; with 503 the strategy and PSK Reporter views stay in their empty form and nothing of boot A returns; no GET /automation on boot B, no request beyond one read per state and socket, no timer request in 5 s; the already conforming views (contact, recording, receive, operating, AGC, Tx level, native, transmit, alerts) show no boot A value as well. Red on the parent: boot A's strategy, automation and PSK Reporter values are shown after boot B is learned.
             #82: there is no "Show free Tx slots" checkbox (the marks are always shown); boot A's open slot marks come from a pushed free_tx_slots.state of boot A, and from the moment boot B is learned no mark of boot A is drawn until boot B's first free_tx_slots.state.
             2 — Isolated automated browser test; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-074-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_074_01_verified_by_TC_074_003 from 'CL-074-01' to 'TC-074-003';
    verification 'TC-074-004' {
        doc /* TC-074-004 — Live: the operator's page across the deploy restart on HB9BLA
             CL-074-01
             Setup: the gated candidate deployed on HB9BLA by the operator's approved deploy, its own station restart; the operator's page (or the live page check, tests/live-page-check.cjs) open before the restart with a strategy selected and Auto off; no transmission.
             Steps: keep the page open across the restart; after it is connected to the new boot read the line, the selector, Auto and the PSK Reporter view, then reload and read them again.
             Expected (oracle: the reload of the same page): without a reload the line is "Automation idle", the selector None, Auto off; the values equal those after the reload; recorded on the issue.
             3 — Live read-only observation on the station during the deploy's own restart; no RF. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-074-01';
        }
    }
    dependency CL_074_01_verified_by_TC_074_004 from 'CL-074-01' to 'TC-074-004';

}
