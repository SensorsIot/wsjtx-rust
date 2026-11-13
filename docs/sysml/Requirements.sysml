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
             browser context, per WstxSettings::IndependentVerification. Plaintext trusted
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
    dependency CL_003_05_verified_by_TC_080_001 from 'CL-003-05' to 'TC-080-001';
    dependency CL_005_02_verified_by_TC_022_001 from 'CL-005-02' to 'TC-022-001';
    dependency CL_005_02_verified_by_TC_022_002 from 'CL-005-02' to 'TC-022-002';
    dependency CL_005_02_verified_by_TC_022_005 from 'CL-005-02' to 'TC-022-005';
    dependency CL_008_01_verified_by_TC_002_001 from 'CL-008-01' to 'TC-002-001';
    dependency CL_008_01_verified_by_TC_009_001 from 'CL-008-01' to 'TC-009-001';

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
    requirement 'CL-044-05' {
        doc /* PUT /profile refuses an audio device that is not a WASAPI endpoint ID: settings.audio.input_device must be a capture endpoint ID {0.0.1.00000000}.{GUID} and settings.audio.output_device a render endpoint ID {0.0.0.00000000}.{GUID} (lower- or upper-case hex), else 400 audio_device_not_endpoint with the field; null stays allowed. At station start an existing profile whose device entry is not an endpoint ID is migrated: when exactly one active endpoint of that flow has exactly that friendly name, the entry is replaced by its ID and the profile saved (revision + 1); otherwise it is kept and the startup log names the field and the reason (not_found or ambiguous). Loading a profile never fails because of a device entry. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; server/src/main.rs; server/src/radio_control/setup.rs; server/src/audio/windows.rs";
    }
    dependency CL_044_05_to_FR_001 from 'CL-044-05' to 'FR-001';
    dependency CL_044_05_to_FR_002 from 'CL-044-05' to 'FR-002';
    dependency CL_044_05_to_FR_016 from 'CL-044-05' to 'FR-016';
    dependency CL_044_05_verified_by_TC_044_002 from 'CL-044-05' to 'TC-044-002';
    dependency CL_044_05_verified_by_TC_044_004 from 'CL-044-05' to 'TC-044-004';

}
