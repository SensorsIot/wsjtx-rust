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
    public import WstxRequirementsQso::*;
    public import WstxRequirementsUdp::*;
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
    // #11 slice B (CL-011-02..04): FT4 in the operating workflow through the shared
    // contact engine; detailed contract in WstxContact (StationOperatingMode,
    // ContactMode, ModeChange, FT4-NOTE rules). The issue's planned TC-007-002 collided
    // with the #10 operating-layout case of that number; the FT4 contact case is
    // TC-007-008 (agent decision, 2026-10-31). Physical FT4 RF acceptance belongs to a
    // separately approved level-5 case and is not part of this slice.
    requirement 'CL-011-02' {
        doc /* Make FT4 selectable per station through the existing operating selection
             and receive start, without a second browser, rig-control, logging or
             transmit-authority path: the station's operating mode (the running live
             decoding job's mode, else the operating selection's mode) sets the mode of
             manual entries and own CQs, the Tx offset domain and the period shown; the
             mode persists across a receive stop and a band change; an operating mode
             selection is refused busy while #9 reports PTT keyed, a transmission or
             Tune; the #9 panel's mode is a read-only display of it. Details:
             WstxContact::StationOperatingMode, ModeChange. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/recording.rs; server/src/selection_http.rs; server/src/receive_http.rs; server/src/contact_http.rs; server/src/contact.rs; client/contact.js; client/recording.js";
    }
    dependency CL_011_02_to_FR_006 from 'CL-011-02' to 'FR-006';
    dependency CL_011_02_to_FR_007 from 'CL-011-02' to 'FR-007';
    dependency CL_011_02_to_FR_019 from 'CL-011-02' to 'FR-019';
    requirement 'CL-011-04' {
        doc /* Keep FT8 behaviour unchanged and isolate the modes: a change of the
             station's operating mode disarms #9 and cancels a calling or active
             contact of the other mode (a completed contact keeps its review and mode),
             clamps the Tx offset into the new domain, the #9 owner never keys or plays
             a request of another station mode, and simultaneous FT4 and FT8 stations
             share no contact, arm or log state. Details: WstxContact::ModeChange,
             ContactMode, WstxTransmit::StationModeGate. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/transmit/service.rs; server/src/recording.rs; server/src/receive_http.rs";
    }
    dependency CL_011_04_to_FR_006 from 'CL-011-04' to 'FR-006';
    dependency CL_011_04_to_FR_007 from 'CL-011-04' to 'FR-007';
    dependency CL_011_04_to_FR_008 from 'CL-011-04' to 'FR-008';
    verification 'TC-007-008' {
        doc /* TC-007-008 — FT4 contact, logging and mixed-mode isolation
             CL-011-03, CL-011-04
             Setup: the contact engine against the actual #9 transmit owner core on a
             virtual UTC clock with a recording hardware double (no audio, PTT or
             radio); the actual router with live FT4 and FT8 fixture jobs; two
             independent station fixtures at once; profile HB9BLA/JN47; hand-authored
             rows packed with the real codec.
             Steps: (a) FT4 responder: select "CQ K1ABC FN42" (even FT4 period P0,
             -12.4 dB, 1234.6 Hz), Enable Tx, feed "HB9BLA K1ABC -05" and
             "HB9BLA K1ABC RR73" in the partner's FT4 periods; (b) FT4 caller: CQ, select
             the "HB9BLA K1ABC FN42" reply, feed "HB9BLA K1ABC R-07"; set_tx4 rrr; Tx
             2916 and 2917 Hz; (c) an FT4 row reaching an FT8 contact; (d) switch the
             station mode with an armed FT8 contact and a pending request and a
             2940 Hz Tx offset, and with a completed unsaved FT8 contact, then Enable Tx
             in FT4; (e) an FT4 and an FT8 station prepare and review contacts at the
             same time; (f) the FT8 contact tests of TC-007-001 unchanged; (g) an armed
             FT8 request pending, the station mode set to FT4 in the #9 owner only, the
             owner run across the period start without any contact step, then a new FT8
             request; (h) #11 IW9FRA replay (live 2026-11-02 13:44-13:46 UTC): select
             "CQ IW9FRA JM68" (+10 dB, 1838 Hz, even period P0), Hold Tx at 2439 Hz,
             Enable Tx, partner rows "+10", "+10", then three "RR73" (or "73") in the
             partner's periods, counted +6.7, +7.0, +7.3 s and +8.2 s after their period
             start, with and without the operator re-selecting the first "+10" row; the
             same in FT8 with RR73, RRR and 73; the same FT4 sequence through the station
             step and router on a virtual UTC (records published +7.0 s); (i) the same
             FT4 sequence with Auto Seq off, Tx3 chosen by the operator, then the offered
             Tx5 chosen; (j) the QSO pane (stubbed snapshot) with Auto Seq off in
             roger_report, without and with suggested_slot tx5.
             Expected (independent hand-written values): (h) transmissions Tx1
             "IW9FRA HB9BLA JN47" in my period 1, "R+10" in 3 and 5, "73" in 7, then
             completed with Enable Tx off and one completion log (IW9FRA, JM68, sent and
             received +10); counted after my audio start (+8.2 s) each message goes out one
             of my periods later (Tx1 1 and 3, R+10 5 and 7, 73 9); a re-selection keeps
             grid JM68; (i) every counted message keeps the state, TIME_OFF follows each
             counted RR73, suggested_slot tx3 after the report and tx5 after each RR73,
             choose_next clears it, 73 is sent in period 9 and the contact completes;
             (j) the "Auto Seq off" line (warning style), then "Send 73
             next" (title "Send IW9FRA HB9BLA 73 next") sending choose_next tx5 and
             enable_tx; at 1366x768 no page scroll and, in the compact QSO pane (#37, no
             Last row), the line, the 73 and Log QSO buttons fully visible; no horizontal
             overflow at 360 px; Auto Seq on sending set_auto_seq true; the line hidden
             with Auto Seq on and nothing offered. (j) runs in headless Chromium against
             the actual server binary with a stubbed contact snapshot. A manual entry of
             the same partner without a grid clears the grid (only a decoded row keeps it).
             Expected for (a)-(g) (independent hand-written values): (a) Tx4 text
             "K1ABC HB9BLA RR73", transmissions only in odd FT4 periods P0+7.5 s,
             P0+22.5 s, P0+37.5 s with audio 300 ms after the period start and 241920
             samples at 48 kHz, states replying -> rogerReport -> signoff -> completed
             after the completed Tx5, one log offer with mode FT4, TIME_ON P0+15 s (one
             7.5 s period before the first Tx3), TIME_OFF P0+45 s, review MODE MFSK
             SUBMODE FT4; (b) report/Tx2 -> rogers/Tx4 RR73 -> completed on the
             completed RR73 transmission; set_tx4 rrr refused out_of_range field form
             with tx4 unchanged; 2916 accepted, 2917 refused out_of_range; (c) no state
             change; (d) Enable Tx off with DisarmCause contactCancelled, no key after
             the switch, contact cancelled, Tx offset 2916, the completed contact's
             review kept with MODE FT8, a later CQ transmitted in FT4 periods;
             (e) each station keeps its own contact, messages, arm state and review mode
             (FT4 MFSK/FT4, FT8 FT8); (f) FT8 results identical to TC-007-001; (g) no
             PTT key and no audio, the pending request refused staleRequest and Enable
             Tx off, the new FT8 request refused staleRequest.
             2 — Isolated automated functional tests; Windows development PC, actual
             engine, #9 owner core and router, independent row and outcome fixtures; no
             RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-011-03';
            verify 'CL-011-04';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_011_02_verified_by_TC_006_002 from 'CL-011-02' to 'TC-006-002';
    dependency CL_011_04_verified_by_TC_007_008 from 'CL-011-04' to 'TC-007-008';
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
    requirement 'CL-010-02' {
        doc /* Progress the contact on the server by the WstxContact::AutoSequence table (messages from the partner addressed to my call; repeats resend, other stations ignored, a partner RRR/RR73 before my 73 answered with one 73 in every active state, completion after a transmitted RR73/73 or a received 73 after RRR) and show confirmed sequence, next message, last transmitted message, pending requests, stale observations and failures separately. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/main.rs; client/contact.js";
    }
    dependency CL_010_02_to_FR_007 from 'CL-010-02' to 'FR-007';
    dependency CL_010_02_to_FR_008 from 'CL-010-02' to 'FR-008';
    dependency CL_010_02_to_FR_019 from 'CL-010-02' to 'FR-019';
    requirement 'CL-010-03' {
        doc /* Offer explicit Enable Tx, disarm, contact cancellation, Abort QSO (Esc and a button beside HALT: the transmission stops now and the contact is cancelled without a halt, closing no panel; #39 2026-11-04) and the immediate Halt Tx emergency stop (buttons and Alt+H; the station and its automation never halt in normal flow); every transmission is a TransmitRequest through the #9 transmit service and its transmit authority, never direct PTT; loss, reconnect, retry or duplicates replay no transmit request and create no second contact. The live transmit path consumes the delivered #9 slice B owner (WstxTransmit::TransmitArming, TransmitRequest, TransmitOutcome, HaltTransmit) in-process. Details: WstxContact::SetEnableTx, HaltTx, AbortQso, CancelContact, TransmitSubmission, ContactCommand; WstxTransmit::AbortTransmission, TransmitHaltUse. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/main.rs; server/src/transmit/service.rs; client/contact.js";
    }
    dependency CL_010_03_to_FR_007 from 'CL-010-03' to 'FR-007';
    dependency CL_010_03_to_FR_008 from 'CL-010-03' to 'FR-008';
    requirement 'CL-010-10' {
        doc /* Bound unattended transmission with a server-owned Tx watchdog (#39, 2026-11-06: default 6, 1..99 repetitions of one message, the Rep of the contact dialogue; only a different message, a new contact or an operator Enable Tx restarts it, never a partner message, a browser click or a setting; a send that would exceed the limit is not keyed and Enable Tx goes off without a halt) and an always-on Tune watchdog (default 90 s, 1..300 s). Details: WstxContact::TxWatchdog, TuneWatchdog. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/transmit/service.rs; client/contact.js";
    }
    dependency CL_010_10_to_FR_008 from 'CL-010-10' to 'FR-008';
    requirement 'CL-010-11' {
        doc /* Set Rx and Tx audio offsets through labelled numeric inputs and waterfall pointer actions (#50: click Tx; double-click Rx and Tx; dragging the 3 px Rx/Tx lines and the Rx/Tx strip fields with 1 Hz/10 Hz steps), Hold Tx protecting only against implicit moves, each confirmed by the server and none enabling transmission. Details: WstxContact::PointerEffect, FrequencyControls. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; client/contact.js";
    }
    dependency CL_010_11_to_FR_007 from 'CL-010-11' to 'FR-007';
    dependency CL_010_11_to_FR_010 from 'CL-010-11' to 'FR-010';
    requirement 'CL-010-13' {
        doc /* Indicate worked-before status of decoded calls in Band Activity and the Rx Frequency pane (this band and mode, other band or mode, not worked, unknown) determined by the server from the profile log, by text or icon as well as colour, carried on each decoded record with no query. Details: WstxContact::WorkedBeforeQuery. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/logbook.rs; server/src/logbook_http.rs; client/logbook.js; client/contact.js; server/src/dxcc.rs";
    }
    dependency CL_010_13_to_FR_010 from 'CL-010-13' to 'FR-010';
    dependency CL_010_13_to_FR_011 from 'CL-010-13' to 'FR-011';
    requirement 'CL-010-14' {
        doc /* Show a UTC clock, a Tx period progress indicator and an Rx audio level meter (0..90 dB, high above 85, low below 15) from server observations, display-only and marked stale with the status link. Details: WstxContact::OperatorDisplays. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact_http.rs; server/src/recording.rs; server/src/main.rs; client/contact.js";
    }
    dependency CL_010_14_to_FR_006 from 'CL-010-14' to 'FR-006';
    dependency CL_010_14_to_FR_010 from 'CL-010-14' to 'FR-010';
    verification 'TC-007-010' {
        doc /* TC-007-010 — A partner's RRR or RR73 before my 73 (#69)
             CL-010-02
             Setup: the actual contact engine (server, not the browser) with a virtual UTC clock, profile HB9BLA/JN37, Auto Seq on, Call 1st off, Tx watchdog 6, hand-authored standard decoded rows in the partner's parity and the #9 transmit-service double that records TransmitRequests and returns started/completed/halted outcomes (no audio, PTT or radio).
             Steps: (a) reproduction of the SV2CLJ contact of 2026-11-08: Tx4 rrr; Enable Tx calling CQ; select "HB9BLA SV2CLJ KN10" (report/Tx2); after the sent Tx2 feed "HB9BLA SV2CLJ R+02"; after the sent Tx4 feed "HB9BLA SV2CLJ RR73"; run four more own periods; then feed "HB9BLA SV2CLJ 73"; (b) as (a), the partner answers my RRR with "HB9BLA SV2CLJ RRR"; (c) as (a) in FT4 (Tx4 rr73) and in FT8 with Tx4 rr73: my RR73 transmission is halted (state rogers kept), the partner's RR73 arrives, Enable Tx again; (d) replying: select "CQ K1ABC FN42", after the sent Tx1 feed "HB9BLA K1ABC RR73"; report: select a caller's "HB9BLA K1ABC FN42" after my CQ, after the sent Tx2 feed "HB9BLA K1ABC RRR"; (e) in rogers the partner's RR73 is counted once while my next Tx4 is pending before its audio starts, and once after that Tx4's audio has started; (f) Auto Seq off, the partner's RR73 in rogers, replying and report; (g) in rogers: "HB9BLA W1XYZ RR73" from another station, "W1XYZ SV2CLJ RR73" from the partner to another call, the partner's RR73 decoded in a period of my own parity, the same RR73 row delivered twice; "HB9BLA K1ABC 73" in replying and in report; "HB9BLA SV2CLJ 73" in rogers; (h) ww_digi: after my Tx4 RRR following the partner's R grid, the partner's RR73; (i) as (a), but my 73 transmission is halted, then Enable Tx again.
             Expected (independent hand-written table from WSJT-X 3.3.0-beta5 DecodedMessageReaction.cpp ~585-616 and mainwindow.cpp ~8237-8255, not candidate output): (a) report/Tx2 -> rogers/Tx4 "SV2CLJ HB9BLA RRR" -> after the RR73 signoff/Tx5; the next own period carries "SV2CLJ HB9BLA 73", exactly one 73 and no RRR after the RR73 period; after the completed 73 outcome state completed/Tx6, Enable Tx off (disarm cause contactCompleted), exactly one log entry of kind completion with call SV2CLJ, RST_SENT the sent report, RST_RCVD +02; nothing transmitted in the following periods; the late 73 changes nothing and logs nothing; (b) the same as (a); (c) the same: one 73, one log, completed; (d) replying -> signoff/Tx5 "K1ABC HB9BLA 73", one 73, completed, one log with RST_SENT and RST_RCVD absent; report -> signoff/Tx5, one 73, completed, one log with RST_SENT the sent report and RST_RCVD absent; (e) before the audio start that period carries Tx5 instead of Tx4; after it the Tx4 of that period is sent and Tx5 follows in my next own period, one 73 and one log either way; (f) state and next slot unchanged, suggested_slot tx5 in each, nothing completed or logged; (g) the other station's and the other-call rows and the own-parity row change nothing; the twice-delivered row gives one 73 and one log; 73 in replying or report changes nothing; 73 in rogers completes at once with no 73 sent and one log; (h) signoff/Tx5, one 73, completed, one log; (i) state signoff kept with nothing logged; Enable Tx again sends one 73, then completed and one log.
             2 — Isolated automated functional tests; Windows development PC, actual contact engine with independent decoded-row and transmit-outcome fixtures; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-02';
        }
        attribute executable : String = "server/src/contact_tests.rs";
    }
    verification 'TC-007-003' {
        doc /* TC-007-003 — Received views, Rx Frequency pane and partner selection
             CL-010-01, CL-010-06
             Setup: actual server/browser with an independently scripted result source and request recorder; rows with distinct UTC/DT/SNR/frequency/text including literal markup, unresolved hashes, duplicate/old tuples, 2047/2048/2049 retained records and expired cursors; Rx offset 1500 Hz; profile call HB9BLA, DX call K1ABC.
             Steps: filter/sort Band Activity; with no contact, read the QSO pane Calling me lines for one period with rows at 1449.9, 1450.0, 1489.9, 1510.1, 1550.0 Hz, "HB9BLA W1XYZ -10" at 400 Hz and "HB9BL K1ABC -01" at 2600 Hz (#37); select rows by click/Enter and by manual DX entry; switch profile.
             Expected (fixed input catalogue): the Calling me lines are exactly the HB9BLA row, plain (no warning sign), with call W1XYZ, SNR −10, no grid and country U.S.A. (#37 2026-11-04), and not the CQs near Rx or HB9BL; sorting Band Activity sends no request and changes no contact/log; selection sends the exact identity and changes the partner only after acceptance; unresolved/old/wrong-profile rows cannot prepare a contact; no invented UTC/callsign, executable markup or cross-profile state.
             2 — Isolated automated functional tests; Windows development PC, real browser/server and independent result source. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-01';
            verify 'CL-010-06';
        }
        attribute executable : String = "server/src/contact_http_tests.rs; tests/contact.test.cjs";
    }
    verification 'TC-007-004' {
        doc /* TC-007-004 — Authority, control and connection barriers
             CL-010-02, CL-010-03, CL-010-07, CL-010-08, CL-010-15
             Setup: actual server/browser; transmit-service and radio-control doubles with supported/unsupported transmit, CAT-only/audio-only, delayed/rejected/lost responses; two profiles; all secondary panels open.
             Steps: Enable Tx, Tune, Halt (button and Alt+H, also before the contact client loads and without a contact snapshot), Esc (focus in a text field, in the DX Call input and in an open panel; Abort QSO), Cancel while transmitting, the partner working another call within 50 Hz while transmitting, save and contact change while the link drops; reconnect; replay old requests; unauthenticated, wrong-Origin and wrong-profile requests; Tx offset 199/200/2950/2951 Hz; every ContactCommand action with missing/extra keys, 1024/1025-byte bodies, stale contact_revision (also for cancel and enable_tx false), a retained command_id with identical and different bodies; GET /contact at its 4096-byte maximum shape; Esc on a receive-only station.
             Expected (independent operation/state catalogue): Alt+H and Halt reach the #9 halt operation first even with panels open (exactly one halt per Alt+H); Esc sends exactly one ContactCommand abort and no halt, stops the transmission now (PTT released, outcome aborted, halt_state unchanged), cancels the contact with nothing logged and leaves the station ready for the next QSO; Cancel lets a transmission on the air finish; the partner working another call within 50 Hz while transmitting: in a manual contact (it pauses, CL-097-06) the transmission on the air finishes, Tx moves clear of his signal (FT8 100 Hz) for the next send and Enable Tx stays on, with no PTT release by a stop; in a pounce or an MCP policy run the partner-works-other stop releases PTT without a halt; Esc closes no panel; state shows pending/unknown until #9 confirms; reconnect loads the snapshot and replays no arm, tune, next-message or transmit request; no request reaches PTT except through the transmit-service double; unsupported transmit leaves Enable Tx/Tune disabled with a reason; 200 and 2950 accepted, 199/2951 refused; Tune is accepted with the transmit state off and leaves it off (CL-111-06); barrier refusals unchanged; no cross-profile contact. Each malformed command returns the independently expected ContactRefusal code and field with no state change; stale revisions refused except cancel/abort/disarm; an identical retained command_id returns the same receipt with no second effect, a different body state_conflict; the maximum snapshot (watchdog busy_with with a 13-character call, paused_calls 99) is exactly admitted within 4096 bytes and GET /contact is never gzip-coded; StatusReply keeps exactly {version,radio}; on the receive-only station Alt+H sends no halt, while row selection and Log QSO still work.
             2 — Isolated automated functional tests; Windows development PC, actual candidate server/browser and independent control, audio and transmit emulators. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-02';
            verify 'CL-010-03';
            verify 'CL-010-07';
            verify 'CL-010-08';
            verify 'CL-010-15';
        }
        attribute executable : String = "server/src/contact_http_tests.rs; tests/contact.test.cjs; tests/ui-operating.test.cjs; server/src/contact_tests.rs; server/src/logbook_http_tests.rs";
    }
    verification 'TC-007-007' {
        doc /* TC-007-007 — Live FT8 contact on the IC-7300
             CL-010-01, CL-010-02, CL-010-03, CL-010-04, CL-010-10
             Setup: deployed candidate on HB9BLA with the IC-7300 (USB audio and CAT, USB-D, 20 m 14.074 MHz or another FT8 dial frequency), operator present at the radio, RF power set by the test to at least 30 W before the first Tx (CI-V 14 0A, starting at 0090, with the station stopped and idle, because it holds COM3; read back; the first Tx must read Po at least 30 %; if below, raise the value and repeat; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported), Halt Tx and the radio's own power control within reach; transmit authorized by the operator on 2026-10-31 for this test only; the 30 W instructed by the operator on 2026-11-07. An independent receiver (separate WSJT-X station or PSK Reporter reception reports) observes our transmissions.
             Steps: run a UDP listener on 127.0.0.1:2237 enabled as a WSJT-X UDP target with QSO Logged and Logged ADIF; complete at least one contact answering a real CQ and, if band conditions allow, one by calling CQ, with Auto Seq, without pressing Log QSO; then Enable Tx without operator activity until the Tx watchdog (set to 2 repetitions for the test) stops it; Halt once during a transmission; restart the server.
             Expected: the partner's messages addressed to HB9BLA appear in the Rx Frequency pane with the report we sent echoed back; the independent receiver decodes exactly the transmitted texts in the expected periods and audio offset within 10 Hz; the contact completes per the AutoSequence table with Enable Tx off and logs itself (no review form; the Logbook page lists it); the listener receives one QSO Logged and one Logged ADIF with the same call, reports, times and frequency; contacts.adi contains exactly one record with the independent observations (call, grid, reports, date/time, band, FREQ = dial + Tx offset) after restart; Halt stops RF promptly as observed on the radio; watchdog expiry stops transmission and disarms. Failures are recorded, not reworded as passes.
             5 — Live RF transmission with operator authorization; HB9BLA station PC with the actual IC-7300 and antenna. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-010-01';
            verify 'CL-010-02';
            verify 'CL-010-03';
            verify 'CL-010-04';
            verify 'CL-010-10';
        }
    }
    verification 'TC-008-001' {
        doc /* TC-008-001 — Tx and Tune watchdogs
             CL-010-10
             Setup: actual server with virtual clock and the #9 transmit-service double; browser and MCP clients.
             Steps: refuse limits 0 and 100, accept 6 (default) and 1..99; with limit 2 call CQ with no answer for three periods; with limit 2 select a CQ, send Tx1 twice and let the partner answer with a report, then repeat the reply; with limit 3 let the partner repeat the same report every period while I repeat (R+report), with unrelated browser requests between the transmissions (hold, frequency, settings), and after the stop Enable Tx again; with limit 2 send Enable Tx while armed after the first reply and select the partner's row, at the same and at another SNR and after an edited Tx3, after the second; lower the limit to 2 with a third reply pending; at the limit with RR73 received and 73 pending choose Tx3; with limit 2 repeat the reply twice and let the partner advance with RR73 at +14.2 s, after the start window's lead for the third; with limit 2 call CQ, send one CQ and let a station answer with Call 1st off, then with Call 1st on; disarm and re-enable; Tune with 90 s default, 1 and 300 s, refuse 0 and 301; Halt during Tune.
             Expected (hand-counted): the third CQ is never keyed: Enable Tx goes off before keying with cause tx_watchdog, tx_expired true, halt_state unchanged (no halt), PTT released; remaining calls 2, 1, 0 while armed; the partner's report makes the next message a different one, which starts at the limit again (two repetitions before the stop); the partner's repeats and the browser requests change nothing: exactly three R+report go out, the fourth is never keyed, cause tx_watchdog without a halt, the dialogue shows the report and R+report each with their Rep; Enable Tx after the stop sends the same message again, a new tx entry with Rep 1; Enable Tx while armed and the partner's row change neither the remaining calls nor the dialogue, and the third reply is never sent, the lowered limit and the Tx button stop at once with nothing keyed; the RR73 makes 73 go out and the contact complete; with Call 1st off a caller leaves the CQ count unchanged, with Call 1st on the reply to the caller starts at the limit; a message from another station to someone else changes nothing; the counter is 0 while disarmed; the contact state is kept and "Tx watchdog: same message sent 2 times" is shown; Tune ends at its limit through #9; startup default 6 calls and 90 s.
             2 — Isolated automated functional tests; Windows development PC, virtual clock and independent transmit double; no RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-010-10';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/tests/transmit_service.rs";
    }
    verification 'TC-010-008' {
        doc /* TC-010-008 — Waterfall pointer actions and frequency inputs
             CL-010-11
             Setup: actual Chromium/server with injected spectrum rows at 1440x1000, DPR 1; request recorder. The pointer mapping at 1366x768 (DPR 1 and 2), 900x700 and 360x800 is checked by TC-050-007.
             Steps: at independently computed pixel positions for 700, 1000, 1500 and 2950 Hz perform click, double-click, shift-click with Hold Tx on and right-click; numeric Rx/Tx inputs with 199/200/2950/2951 Tx.
             Expected (#50): requested offsets equal the independently computed axis frequency rounded to integer Hz; click Tx only; a double-click exactly one request for Rx and Tx and no re-decode request; shift-click as click and with Hold Tx on; right-click nothing; the markers are 3 px lines (Rx rgb(48,208,80), Tx rgb(255,64,64)) without text at the confirmed values; out-of-domain refused; no Enable Tx request; the browser context menu does not open on the waterfall.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-11';
        }
        attribute executable : String = "tests/contact.test.cjs";
    }
    verification 'TC-010-009' {
        doc /* TC-010-009 — UTC clock, Tx progress and Rx level meter
             CL-010-14
             Setup: actual server/browser, virtual server UTC, independently synthesized canonical samples: silence, full-scale sine, sine at -40 dBFS and noise of known power; transmit double.
             Steps: observe across period boundaries, during a transmission, after link loss, with audio stopped.
             Expected: clock shows the server UTC HH:MM:SS (independent of a skewed browser clock) and is marked stale with the link; progress shows v/15 with v = whole elapsed seconds and a Transmitting label while transmitting; level = round(10 log10(mean(s^2))) with s scaled to 32768 (full-scale sine 87, -40 dBFS sine 47, silence clamped 0), labelled high above 85 and low below 15, unavailable with audio stopped, at most one value per second.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-010-14';
        }
        attribute executable : String = "server/src/contact_http_tests.rs; tests/contact.test.cjs";
    }
    verification 'TC-011-003' {
        doc /* TC-011-003 — Worked-before indication
             CL-010-13
             Setup: profile log fixture with K1ABC on 20m FT8, W1XYZ on 40m FT8, DL1ABC on 20m MFSK/FT4; dial 20m FT8; rows from K1ABC, W1XYZ, DL1ABC, k1abc case variant, N0NEW and a hashed call; 65 distinct calls in one period.
             Steps: publish periods, save a new contact with N0NEW, publish again.
             Expected: K1ABC this band and mode; W1XYZ and DL1ABC other band or mode; N0NEW not worked then this band and mode after the save; hashed unknown; the status is text (hover text and aria-description, BandActivityHover) in Band Activity and the QSO pane's stations calling me, colour only from the enabled new_* slots of the record flags, so worked before on this band and mode has no colour; each record carries its status (worked_status, WstxContact::DecodedEntity) and the browser sends no query; no change to decoding, sequence or log.
             QSO pane subset (#10 2026-11-04, WstxOperatingLayout::QsoPane item 3). Setup: selection 20m FT8; routed records of one period with callers to my call HB9BLA K1ABC FN42 (no flags, worked_this_band_and_mode), HB9BLA W1XYZ FN31 (new_call, new_call_band, not_worked) and HB9BLA DL1ABC -10 (new_call_band, worked_other_band_or_mode). Steps: wait for the worked-before status of the rows; read the callers; turn New call off in Settings; refresh status. Expected (#50 BandActivityHover compact rule, #37 2026-11-04): K1ABC no colour and no hover text; W1XYZ the New call colour and the one-line hover "New call"; DL1ABC the New call on band colour and "New on 20m (worked on another band or mode)"; no My call colour; with New call off W1XYZ takes New call on band and the hover "New on 20m"; no worked-before query.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-010-13';
        }
        attribute executable : String = "server/src/logbook_tests.rs; server/src/dxcc_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_010_02_verified_by_TC_007_001 from 'CL-010-02' to 'TC-007-001';
    dependency CL_010_02_verified_by_TC_007_004 from 'CL-010-02' to 'TC-007-004';
    dependency CL_010_02_verified_by_TC_007_007 from 'CL-010-02' to 'TC-007-007';
    dependency CL_010_02_verified_by_TC_007_010 from 'CL-010-02' to 'TC-007-010';
    dependency CL_010_03_verified_by_TC_007_001 from 'CL-010-03' to 'TC-007-001';
    dependency CL_010_03_verified_by_TC_007_004 from 'CL-010-03' to 'TC-007-004';
    dependency CL_010_03_verified_by_TC_007_007 from 'CL-010-03' to 'TC-007-007';
    dependency CL_010_07_verified_by_TC_007_004 from 'CL-010-07' to 'TC-007-004';
    dependency CL_010_08_verified_by_TC_007_004 from 'CL-010-08' to 'TC-007-004';
    dependency CL_010_10_verified_by_TC_008_001 from 'CL-010-10' to 'TC-008-001';
    dependency CL_010_10_verified_by_TC_007_007 from 'CL-010-10' to 'TC-007-007';
    dependency CL_010_11_verified_by_TC_010_008 from 'CL-010-11' to 'TC-010-008';
    dependency CL_010_13_verified_by_TC_011_003 from 'CL-010-13' to 'TC-011-003';
    dependency CL_010_14_verified_by_TC_010_009 from 'CL-010-14' to 'TC-010-009';
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
    requirement 'CL-112-05' {
        doc /* QSO Logged exchanges as WSJT-X. 1. The logged record carries its activity: when DirectLog stores a contact, the record gets the app field APP_WSTXRUST_ACTIVITY with the contact's activity at logging time, one of field_day, rtty, eu_vhf, na_vhf, ww_digi, arrl_digi, hound; it is absent for activity none, and a record without the field is activity none. In contacts.adi, the ADI export and the Logged ADIF datagram it is written after APP_WSTXRUST_CONTACT_ID and, when present, APP_WSTXRUST_SOURCE, and before any preserved unknown fields (WstxContact::LogRecord order). It is read back when the log loads. SaveContact accepts it; any other value is refused 400 log_invalid_field with field record.app_wstxrust_activity, as every other record field (WstxContact::ContactWire), and nothing is stored. UpdateLogbook keeps a valid value and drops an invalid one, as it does for other contest values. Listed default (as for APP_WSTXRUST_SOURCE: the resave comparison covers the main field list only): a SaveContact resave of a stored contact id that differs only in the activity is 200 already_saved, with the stored record unchanged and no datagram; likewise a DirectLog store that differs only in the activity is already_saved and keeps the stored activity. Field name, values and these rules are listed defaults; the operator decided only that the activity is stored in the record. 2. Exchange sent and Exchange received are the exchange WSJT-X passes from its log dialog (widgets/mainwindow_qso.cpp captureLogQso, widgets/logqso.cpp xsent/xrcvd), chosen by the record's activity: na_vhf, ww_digi, arrl_digi: sent is the first 4 characters of MY_GRIDSQUARE, received the first 4 of GRIDSQUARE ("JN47" / "FN42"); a missing partner grid gives "", as WSJT-X with its default ZZ00 off. field_day, rtty, eu_vhf: the contact's exchange_sent / exchange_rcvd as ContestExchange / EuVhfExchange define them ("1A EMA" / "2B CT", "559 0003" / "579 MA", "550001 JN37VL" / "590003 IO91NP"), rebuilt from the stored record's contest fields, RST, grid and activity: the reverse of ContestExchange's and EuVhfExchange's log mapping. hound, none, or no field: "" / "". 3. DirectLog and SaveContact build them the same way, from the stored record, so the same record always gives the same exchanges; the explicit save exists to resend what a logging program missed. Details: WstxUdp::OutboundRules, WstxContact::LogRecord. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs; server/src/logbook.rs; server/src/logbook_http.rs; server/src/contact_http.rs";
    }
    dependency CL_112_05_to_FR_012 from 'CL-112-05' to 'FR-012';
    verification 'TC-112-005' {
        doc /* TC-112-005 — QSO Logged exchanges
             CL-112-05
             Setup: actual candidate router, contact engine, logbook and UDP owner on the contact fixture (profile HB9BLA JN47AA); a loopback peer selecting qso_logged and logged_adif.
             Steps: each completed contact through DirectLog, then the same stored record through POST /contacts under a new contact id: field_day "1A EMA" / "2B CT"; rtty "559 MA" / "579 MA" and "559 0003" / "559 0013"; eu_vhf (profile JN37VL) "550001 JN37VL" / "590003 IO91NP"; na_vhf with partner FN42; ww_digi with partner FN42ab; arrl_digi without partner grid; hound; none. A record without app_wstxrust_activity (an older log); POST /contacts with app_wstxrust_activity "contest"; a resave of a stored contact id differing only in the activity; contacts.adi, the ADI export, a record with APP_WSTXRUST_SOURCE, and the export after a station restart.
             Expected (WSJT-X mainwindow_qso.cpp captureLogQso grids left 4, logqso.cpp; ContestExchange / EuVhfExchange; ContactWire refusal; CL-112-05 listed default), sent / received for both paths: "1A EMA" / "2B CT"; "559 MA" / "579 MA"; "559 0003" / "559 0013"; "550001 JN37VL" / "590003 IO91NP"; "JN47" / "FN42"; "JN47" / "FN42"; "JN47" / ""; "" / ""; "" / "". The older record "" / "". The Logged ADIF ends with the contact id then app_wstxrust_activity (absent for none); "contest" is refused 400 log_invalid_field field record.app_wstxrust_activity and nothing is stored; the resave is 200 already_saved, contacts.adi unchanged and no datagram; contacts.adi and the export carry <app_wstxrust_activity:6>na_vhf right after the contact id, after app_wstxrust_source on a record that has one, and it survives the restart.
             2 — Isolated automated functional tests; Windows development PC, loopback UDP only. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-112-05';
        }
        attribute executable : String = "server/src/udp_tests.rs";
    }
    dependency CL_112_05_verified_by_TC_112_005 from 'CL-112-05' to 'TC-112-005';
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

    // #39 Strategy engine: selection, value order, editor popup, directed-CQ rule (decisions
    // on #37/#39/#42, 2026-11-01); detailed contract in WstxStrategy.
    requirement 'CL-039-01' {
        doc /* Named strategies are a station setting of the selected profile: strategy.json (schema 4) beside profile.json holds {continent, strategies, ignore lists} with up to 16 strategies, each with the keys of CL-097-01 (classes and contest strategies: CL-097-01, CL-097-07). Exactly one strategy is active, or None; active never survives a station restart. Files of schema 1, 2 and 3 are read by the upgrade of WstxStrategy::StrategyConfiguration and written as schema 4 by the next PUT. GET /strategy and PUT /strategy (revision-checked, exact keys) read and save it; my continent is configurable there (Settings > General) and otherwise the cty.dat continent of my callsign (#55). Details: WstxStrategy::StrategyConfiguration, Strategy, StrategyHttp. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/contact_http.rs; server/src/main.rs; client/contact.js";
    }
    dependency CL_039_01_to_FR_007 from 'CL-039-01' to 'FR-007';
    dependency CL_039_01_to_FR_016 from 'CL-039-01' to 'FR-016';
    requirement 'CL-039-02' {
        doc /* One station evaluator gives each decoded standard message a verdict: its filters are CL-097-02 and its order CL-097-03, callers of my call included. SNR is always the hidden last tie-breaker, then for an exact tie the lower audio frequency and the call; decode order is never a ranking. Distance is from the profile locator to the message grid, else to the cty.dat entity centre. POST /strategy/evaluate returns the verdicts of retained live records for the saved strategy or a draft, with the reason when asked; the browser never evaluates a strategy itself. Details: WstxStrategy::NewNeeded, WpxPrefix, WorkedWindow, CallerOfMyCall, Candidate, ValueOrder, StationDistance, Verdict, StrategyHttp. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/logbook.rs; server/src/recording.rs; server/src/dxcc.rs";
    }
    dependency CL_039_02_to_FR_007 from 'CL-039-02' to 'FR-007';
    dependency CL_039_02_to_FR_011 from 'CL-039-02' to 'FR-011';
    requirement 'CL-039-03' {
        doc /* One directive rule before every strategy and for the operator: a CQ is answerable when it is a plain CQ, CQ <my continent> (derived from the profile call via cty.dat, locator fallback) or CQ DX from another continent. Every other directive is not answerable: a strategy skips it (greyed, never matches, never answered by a run or pounce) and an operator's selection shows a warning the operator can confirm ("CQ NA — not for EU"); automation, MCP and UDP cannot confirm it. In a contest activity its own word (CQ TEST, WW, FD, RU) is answerable too (CL-063-02). Details: WstxStrategy::DirectedCqRule, MyContinent, StrategyRun. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/automation.rs; server/src/contact_http.rs; server/src/dxcc.rs; client/contact.js";
    }
    dependency CL_039_03_to_FR_007 from 'CL-039-03' to 'FR-007';
    requirement 'CL-039-05' {
        doc /* Selecting a strategy marks its candidates; it transmits only while Auto is on (CL-039-22), through the existing station automation and contact engine (no second engine), with no confirmation and no client decision: the browser sends only the selection and the toggle, and HALT is always on screen. A strategy run calls CQ only with CQ when idle (CL-039-22) and goes on after each QSO without a contact limit, waiting for the next opportunity, for at most 8 hours from its start, also with a browser open (operator decision 2026-11-06: a new start gives a new 8 hours); it answers callers of my call (only with Calling stations are answered on, first), then the best candidate; it leaves a station by the leave rule (CL-039-23) and may call it again after its retry pause; it never selects a station the operator cancelled or aborted again in that run, nor one completed in that run on this band and mode. It follows its grant, not the transport of the starting request: a page reload or a second tab does not stop it, a revoked grant does. Unattended (operator decision, #39 comment 6685226511) and at the run limit ("Finish the QSO first", operator 2026-11-07): with no authenticated client (a status WebSocket session, or an authenticated MCP request) for 60 s, or past 8 hours, it selects no new station and answers no caller, its own CQ ends at once, a QSO the partner is answering is completed, otherwise the contact ends at x repetitions, and it stops with the reason no_client or run_limit; only an Auto on restarts it, never an AutomationCommand start. A band or mode change by the operator and HALT end the contact at once; Auto off, None, another selection, a contest deselected and the end of a contest period end at once a contact that is no started QSO and let a started QSO finish (#81, CL-081-01). It waits instead of stopping across a receive restart; a refused start or a stop turns Auto off with the reason shown and leaves the strategy selected. HALT from any source stops the run and turns Auto off, pushed to the browser; the selection stays. Esc does not. A double-click is always possible and is a manual intervention: the run waits for that QSO to end and resumes. An MCP principal cannot select a strategy nor switch Auto. Every Auto decision is taken at the earliest moment the information it needs is available, never later (#89, operator 2026-11-09: "decision always fastest when needed info is available. this is a general rule for the auto mode"). Details: WstxStrategy::StrategyRun (Decision timing), AutoToggle, StrategySelector, ManualIntervention, SaneCall; WstxMcp::OperatingAutomation. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/strategy.rs; client/contact.js";
    }
    dependency CL_039_05_to_FR_020 from 'CL-039-05' to 'FR-020';
    dependency CL_039_05_to_FR_007 from 'CL-039-05' to 'FR-007';
    requirement 'CL-039-07' {
        doc /* Outstanding, issue #39/#42 later slices: filtered-out view toggle; freeze Band Activity on hover; per-mode watchdog values; late-duplicate guard and false-decode heuristic; CQ-target prefer; stacked DXpedition replies. Delivered: the free Tx slot finder (CL-039-09), contests (#63), the busy pause (CL-097-06) for a busy partner, and the CQ target filter (CL-097-02). The outstanding slices are not offered. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    dependency CL_039_07_to_FR_007 from 'CL-039-07' to 'FR-007';
    verification 'TC-039-008' {
        doc /* TC-039-008 — Later strategy slices (outstanding: the CL-039-07 slices)
             CL-039-07
             Setup: actual candidate router with a pinned cty.dat fixture and hand-authored rows.
             Steps: the scenarios of each outstanding slice.
             Expected: defined when the slice is prepared.
             2 — Isolated automated functional tests; Windows development PC; not implemented. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-039-07';
        }
    }
    dependency CL_039_07_verified_by_TC_039_008 from 'CL-039-07' to 'TC-039-008';
    requirement 'CL-039-22' {
        doc /* Mode (operator grill 2026-11-07, Q5, Q11, Q12, Q17, Q29, Q35, Q40). Auto is a toggle above the QSO pane next to CQ, green on and grey off, not part of a strategy, one toggle for strategies and contests; the station owns it in memory: off after a station restart, after HALT from any source and after every run end, and only the browser switches it (POST /strategy/auto; an MCP principal is refused). With Auto off a selected strategy or contest only marks its candidates; switching it on needs a selection and starts the run, and a contest whose rules forbid automatic operation asks the existing warning and needs its confirmation; switching it off ends the run at once, and a QSO the run has started is finished as an ordinary contact (#81, CL-081-01: Auto only decides whether new QSOs start); selecting None turns it off, another selection with Auto on starts that one. CQ when idle is a strategy setting with its CQ wait (CL-097-01, CL-097-08; on in Casual and the contest built-ins): with it on the run calls CQ after cq_wait_periods publications with nothing callable, answers callers (with Calling stations are answered on) and calls a candidate that appears; the Tx watchdog stops its CQ. With Hold Tx on (#39 holdtx round 1 Q3) the CQ goes out on the held Tx without a slot decision; with Hold Tx off it takes the slot quiet in my Rx parity (CL-039-09, #66). Details: WstxStrategy::AutoToggle, CqWhenNoTarget, StrategyRun, PskrUse; WstxOperatingLayout::QsoPane. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/automation.rs; server/src/contact_http.rs; client/contact.js";
    }
    dependency CL_039_22_to_FR_007 from 'CL-039-22' to 'FR-007';
    dependency CL_039_22_to_FR_020 from 'CL-039-22' to 'FR-020';
    requirement 'CL-039-20' {
        doc /* A read-only PSK Reporter MQTT feed tells the station whether the current target hears my call (with the SNR it reported) and which frequencies it decodes, with their parity: two exact subscriptions (my call as sender; the strategy or contest target as receiver while Use PSK Reporter is on, replaced when the target changes), never a wildcard from a decoded call, TLS against compiled-in roots, an identifiable client id, bounded reconnect backoff, bounded memory, spots expiring after 600 s, a spot of another band or mode ignored. Settings shows the master switch (on by default) and the status, pushed; the Use PSK Reporter toggle next to Auto (on by default, kept across restarts) decides whether runs use the feed, and while it is on the QSO pane shows "hears us" (spot age and reported SNR, or no, or unknown) and "open at his end" with the chosen slot. It sends nothing but the handshake, keep-alive and subscriptions; everything works without it: no connection is unknown, never an operator error, and receive and the 50 ms station step never wait on it. Details: WstxStrategy::HearingFeed, PskrUse. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/pskr.rs; server/src/main.rs; server/src/contact_http.rs; server/src/recording.rs; client/contact.js";
    }
    dependency CL_039_20_to_FR_007 from 'CL-039-20' to 'FR-007';
    dependency CL_039_20_to_FR_012 from 'CL-039-20' to 'FR-012';
    verification 'TC-039-020' {
        doc /* TC-039-020 — The PSK Reporter feed against a local peer
             CL-039-20
             Setup: no network. A local TCP peer whose packets are written from the OASIS MQTT 3.1.1 tables; hand-authored payloads in the form of the broker's published schema; the certificate chain the broker presented on 2026-11-06, captured once as a fixture; shortened session timings; the actual station router for the routes.
             Steps: parse a full spot, one without t_tx, and malformed ones; build filters from my call, a target and hostile calls (wildcards, slash, space, lower case, control and non-ASCII characters, overlong); record spots past the window, on another band or mode, past each bound, repeated and ahead of the clock; read the decoded offsets of a 7074000 Hz dial; encode each packet and parse whole, split and hostile input; step the backoff; run a session and change the target, send a non-spot and spots with another sender and receiver than the topic says, wait for a ping, switch off; a peer that drops five connections and then accepts; peers that refuse CONNECT, refuse SUBSCRIBE, send a reserved packet; the setting by default, after a save, from another profile and broken; WSTX_PSKR values; verify the captured chain against the compiled-in roots, with another name and after it expired; a peer without TLS; GET and POST /pskr with and without a feed, an extra key, a query.
             Expected: exactly pskr/filter/v2/+/+/HB9BLA/+/# and pskr/filter/v2/+/+/+/K1ABC/#, no filter for any hostile call; hears us exactly up to 600 s, on that band and mode; offsets [1200, 800] for 7075200 and 7074800 Hz, none from another band, mode, receiver or from my own spot, none outside the range; at most 256 and 128 entries, 32 offsets, newest kept; packets equal the hand table; hostile input is protocol_error; delays 5, 10, 20, 40, 80, 160, 300, 300 s, 5 s after a reset; on the wire only CONNECT, SUBSCRIBE, UNSUBSCRIBE, PINGREQ, DISCONNECT; the old target unsubscribed, the hostile one not subscribed; the spot counts by its payload; off forgets everything; attempts at least 40, 80, 160, 160, 160 ms apart with the shortened timing, the status naming the error, recovery without any action; connection_refused, subscribe_refused, protocol_error; on by default, the save kept, invalid_pskr for the other two; only a loopback tcp: value replaces the broker; the chain valid on capture, refused otherwise; tls_failed with TLS spoken first; 404 without a feed, the exact view with one, other requests refused.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF, no network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-20';
        }
        attribute executable : String = "server/src/pskr_tests.rs";
    }
    dependency CL_039_20_verified_by_TC_039_020 from 'CL-039-20' to 'TC-039-020';
    verification 'TC-039-021' {
        doc /* TC-039-021 — Settings shows the PSK Reporter status, pushed
             CL-039-20
             Setup: the actual isolated station with WSTX_PSKR pointing at a local MQTT peer in the test, Chromium at 1366 x 768.
             Steps: open Settings > Logging; wait for the connection; publish a spot of my call 180 s old; uncheck the switch; drop the peer and check the switch again.
             Expected: the switch is in view and on by default; "Connected · no spot yet", then "Connected · last spot 3 min ago", with exactly one GET /pskr; "Off" and Saved after the switch, the station stores it and the peer sees DISCONNECT and no packet other than CONNECT, SUBSCRIBE, PINGREQ, DISCONNECT; "Not connected · <code> · retrying" with the broker gone; no page error.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF, no network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-20';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_039_20_verified_by_TC_039_021 from 'CL-039-20' to 'TC-039-021';
    requirement 'CL-039-08' {
        doc /* Hold Tx is on by default (operator decision 2026-11-04, #39; consistent with the split-frequency rule): a station starts with settings.hold_tx true, in manual operation and for a strategy alike, so selecting or answering a station moves Rx and never Tx; Tx stays on the operator's chosen slot until an explicit Tx action (the Tx input, a waterfall Tx pointer action, MCP set_frequency, the Hound's own rule). Automation (#39 holdtx, operator 2026-11-07: "Hold Tx on: the automation never moves Tx", corrected to "if the other station does not hear us we are allowed to change the frequency to a quiet place, but never to the Rx frequency"; this replaces "a run's free slot" as an explicit Tx action): with Hold Tx on a strategy or contest run or a pounce keeps Tx at a selection, before its CQ and when answering a caller from it, and moves Tx in exactly two cases: the station selected or answered is within 50 Hz of Tx (then Tx goes to the nearest slot 50 Hz away from it, round 1 Q2), and a Tx move of the Tx move rule (CL-097-05); Rx stays on the station. The operator may switch it off with set_hold_tx; the choice lasts for the station's running session, since Hold Tx is not saved (CL-110-01 point 8); the run reads it at each decision. Details: WstxStrategy::FreeTxSlot. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; client/contact.js; server/src/automation.rs; server/src/freeslot.rs";
    }
    dependency CL_039_08_to_FR_007 from 'CL-039-08' to 'FR-007';
    verification 'TC-039-009' {
        doc /* TC-039-009 — Hold Tx is on by default
             CL-039-08
             Setup: actual contact engine and actual station Router with a fresh profile (no explicit choice), hand-authored decode rows.
             Steps: read the first contact snapshot; select a CQ at another frequency; answer through a strategy pick; switch Hold Tx off and select again.
             Expected (oracle: the operator's decision on #39): settings.hold_tx true in a fresh snapshot and #contact-hold checked; after the selection Rx follows the row and Tx stays 1500; after the strategy pick Tx stays; with Hold Tx explicitly off a selection moves Tx to the row (the WSJT-X rule of FirstSlotOnSelection). On the parent the fresh snapshot says false and the selection moves Tx.
             2 — Isolated automated tests; Windows PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-08';
        }
        attribute executable : String = "server/src/contact_tests.rs::hold_tx_is_on_by_default_and_a_selection_keeps_tx; server/src/strategy_tests.rs::tc_039_004_selecting_starts_a_run_that_calls_by_value_and_never_calls_cq; tests/contact.test.cjs";
    }
    dependency CL_039_08_verified_by_TC_039_009 from 'CL-039-08' to 'TC-039-009';
    requirement 'CL-039-09' {
        doc /* A strategy or contest run or a pounce calls from the quietest Tx slot: the slot where the target can answer us, a free slot on my side, judged in every decision (a selection, a slot check, a CQ) in my Rx periods only (his Tx parity; #66 operator 2026-11-08 "judge the parity I will receive in"), and only in recent ones: the counted periods among the last 4 periods of my Rx parity that are due: ended on the clock, or earlier, while in progress, once their complete decodes are published, never before they start (#66 "Only if recent"; #89 operator 2026-11-09 "Count once decoded": a decision on the publication of my newest Rx period counts it; every contest Run CQ decided in waiting without a fresh publication, at Auto on, when a reason ends, when a manual contact ends or Esc gives a caller up, after a completion or a leaving, waits for that publication and decides at once when it arrives, at the latest when the period in progress ends, CL-039-05 decision timing), periods I transmitted in never counted. Slots are compared with each other across the whole passband (#66, operator 2026-11-08 "We want to have the quiet slots overall. Across the entire bandwidth of FT8."), not by their own usual level: in each counted period a slot's rise is its level minus the WSJT-X passband floor fitted to that period (so the receive filter's roll-off does not favour the edges), and its value is its largest rise over the counted periods clamped at 0 (#66, operator 2026-11-08 "At or under floor = free": a slot at or below the floor is free, so a sharp filter knee the floor cannot follow never makes the edges win); compared in whole dB, the lowest value winning; a tie keeps the current Tx when it is among the quietest, else goes nearer the current Tx, then lower; there is no threshold. A slot whose signal overlaps a station decoded in a counted period (less than one signal width from his decoded frequency) is left out while any other is free. Where known it is free at his end: at least 50 Hz from every frequency his PSK Reporter spots show him decoding, counting only spots from my Tx parity (ignored when that leaves no slot). Hold Tx off: Rx = Tx, the slot sets both, decided at each selection, before a CQ and at each move of the Tx move rule (CL-097-05). Hold Tx on (CL-039-08): Rx stays on the station and the slot sets Tx alone, only at a move of the Tx move rule, or as the nearest slot 50 Hz away when the station is within 50 Hz of Tx; a CQ goes out on the held Tx. Every slot the run chooses lies from 500 Hz inside the Tx range (FT8 500..2650, FT4 500..2610), a slot reaching above 2400 Hz losing every tie, and at least 50 Hz from the called station's signal and from Rx; without power data the current Tx is kept. Details: WstxStrategy::FreeTxSlot. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/freeslot.rs; server/src/automation.rs; server/src/contact_http.rs; client/contact.js";
    }
    dependency CL_039_09_to_FR_007 from 'CL-039-09' to 'FR-007';
    dependency CL_039_09_to_FR_020 from 'CL-039-09' to 'FR-020';
    verification 'TC-039-010' {
        doc /* TC-039-010 — The quietest Tx slot
             CL-039-09
             Setup: the pure slot function with hand-authored power tables (levels in dB per 10 Hz candidate, written in the test) and hand-authored spot frequencies; the actual station Router with the contact engine and #9 owner on the hardware double, an injected FT8 live job whose detailed waterfall rows are hand-authored (a flat floor of 20 with raised bands), a selected strategy with Auto on, a pounce, a plain MCP run; virtual UTC.
             Steps: choose on tables: one lowest slot; the current Tx tying the lowest; two lowest without the current Tx, at different distances from it and at equal distances; levels 40.4 and 40.0 (one whole dB, a tie) against 40.6 and 40.0 (no tie); the range edges for FT8 (500..2650) and FT4 (500..2610, width 90), the upper edge losing ties (TC-097-010), every slot at 500 Hz or above; the called station on the quietest slot; his decoded frequencies of my Tx parity and of the other parity near the quietest; his frequencies excluding every candidate; listening only, with one parity quiet and the other loud; no power yet, with the called station on and away from the current Tx. Router: periods of both parities with a quiet band at 1800 Hz only in my Rx parity; the 5th oldest period of the parity quiet at 600 Hz; a period I transmitted in; then a candidate CQ on 1500 Hz; a QSO to its end; a station band change within the job; Hold Tx off; a caller on my slot; a pounce; a plain MCP run.
             Expected (oracle: the operator's rule, hand-computed in the test): that slot; the current Tx kept; the nearer one, then the lower; 40.4 and 40.0 tie and keep the current Tx, 40.6 does not; never outside the range; never within 50 Hz of the called station; his frequency of my Tx parity excludes the slot within 50 Hz and the other parity does not; all excluded: his end ignored, his_end no; listening only (#66): judged on my Rx parity alone, the parity loud only in my Tx periods not avoided; no power: the current Tx kept, or the nearest away from the called station, power_db null. Router: Tx and Rx 1800 before the first call (the 5th period and the transmitted period ignored), tx_slot {hz 1800, power_db 20, his_end unknown}; Tx stays 1800 through the whole QSO; after the band change only the new band's periods count; with Hold Tx off Tx back on its slot; the caller answered from the quietest slot away from it; the pounce calls from the quietest slot; the plain run has tx_slot null and keeps its Tx.             #39 holdtx: the Router steps run with Hold Tx explicitly off (the Rx = Tx rule); with Hold Tx on they are TC-039-049. The tables give the compared value instead of the absolute power, and power_db is that value. #66: the compared value is the largest rise above the passband floor clamped at 0 (TC-039-050), so the Router's tx_slot reads power_db 0 on the flat floor of 20 (floor 20.65, rise -0.65 clamped); the decoded-station rule is TC-066-002.
             2 — Isolated automated tests; Windows PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-09';
        }
        attribute executable : String = "server/src/freeslot_tests.rs; server/src/strategy_tests.rs; server/src/automation_tests.rs";
    }
    dependency CL_039_09_verified_by_TC_039_010 from 'CL-039-09' to 'TC-039-010';
    requirement 'CL-039-10' {
        doc /* The value order can use the Club Log Most Wanted list: Settings shows "List from <date>" with its entries, unmapped numbers and source attribution, and one button Update Most Wanted that fetches it once on the operator's click; there is no upload, a failed download keeps the list and shows the reason in one line; it is validated, stored in the profile folder and mapped to cty.dat entities by ADIF number (an unmapped number is ignored and counted). No automatic refresh and nothing bundled (operator decision, #39 comment 6685317139; Club Log states no terms, recorded in WstxStrategy D12). Everything works without a list (strongest first). The list is read off the station step. Details: WstxStrategy::MostWantedList, ValueOrder. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/most_wanted.rs; server/src/strategy.rs; client/contact.js";
    }
    dependency CL_039_10_to_FR_007 from 'CL-039-10' to 'FR-007';
    verification 'TC-039-030' {
        doc /* TC-039-030 — Goals, windows, value order, callers and the WPX prefix
             CL-039-01, CL-039-02, CL-039-05
             Setup: hand-authored rows and a log of hand-written contacts (worked, confirmed, per band and mode, with and without a grid, with dates) for HB9BLA on 40m FT8, EU, and for a non-EU profile; the expected verdicts are written in the tests.
             Steps: each what of the schema 3 goals as the upgrade maps it (new [dxcc] per ever, band and band_mode, [cq_zone] per ever, [prefix] per ever, [grid] per ever, [call] per ever and per band; TC-097-002, TC-097-005) with worked and confirmed fixtures in both needed settings; grid with no message grid and with a logged QSO without a grid; region all, dx and selected for an EU and a non-EU profile; window all, today and from-to with an undated record; the worked set for the station step after a log write; min_snr_db; a caller against a Most Wanted station with a what, region and SNR that exclude it; value order with and without a list; the WPX prefix table; class contest; the old file upgrade.
             Expected: the tables of the tests; the caller that fails the filters has no rank (TC-097-007); without a list strongest first; with one the listed first by rank, the others after them strongest first; unknown grid is never needed; the step gets the last set at once and the new one follows on its own thread; class contest is accepted only with a contest (TC-097-001).
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-01';
            verify 'CL-039-02';
            verify 'CL-039-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs; server/src/dxcc_tests.rs; server/src/logbook_tests.rs";
    }
    dependency CL_039_01_verified_by_TC_039_030 from 'CL-039-01' to 'TC-039-030';
    dependency CL_039_02_verified_by_TC_039_030 from 'CL-039-02' to 'TC-039-030';
    dependency CL_039_05_verified_by_TC_039_030 from 'CL-039-05' to 'TC-039-030';
    verification 'TC-039-031' {
        doc /* TC-039-031 — Most Wanted list: parsing, mapping, routes
             CL-039-10
             Setup: hand-written list text (no network); the bundled cty.dat; the actual station router on a disposable HTTPS profile; a test seam in place of the HTTP fetch.
             Steps: parse valid and refused lists; map every bundled cty.dat entity; Update Most Wanted (the download route) with a fake fetch: a list with an unknown number, a failure, a reply that is no list; read the snapshot; open a new owner; POST to the former upload route; POST with the MCP cookie.
             Expected: the refused lists parse to nothing; every bundled entity has an ADIF number, exactly 340 distinct numbers; status {date, entries, unmapped 1}; the new owner reads it; each failure is 502 download_failed with its reason and changes nothing; the upload route is gone (405 or 404); the MCP cookie is refused 401.
             2 — Isolated automated tests; Windows development PC, no network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-10';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_10_verified_by_TC_039_031 from 'CL-039-10' to 'TC-039-031';
    requirement 'CL-039-11' {
        doc /* Read-only built-in strategies are offered beside the user's: the five of class strategy and one contest built-in per contest, with their values (CL-097-01, CL-097-07). They come from one server table, are listed with builtin true in the snapshot, can be selected like any strategy, cannot be edited through PUT /strategy (a user strategy with such a name is refused) and can be duplicated to a user strategy in the editor. Details: WstxStrategy::BuiltinStrategies, StrategyEditor, StrategySelector. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; client/contact.js";
    }
    dependency CL_039_11_to_FR_007 from 'CL-039-11' to 'FR-007';
    verification 'TC-039-032' {
        doc /* TC-039-032 — Built-in strategies: selection, refusal and copy
             CL-039-11
             Setup: the actual station router on a disposable HTTPS profile with the contact engine and #9 transmit owner on the recording hardware double; a browser case on the actual isolated station. The table of the built-ins is TC-097-003's.
             Steps: GET /strategy; parse a configuration with active "Casual", with "casual", with a user strategy "New DXCC" and "new dxcc", with the key builtin; PUT active "Casual", Auto on, and publish CQ DL1XYZ JO62 (+9 dB) and CQ K1ABC FN42 (-15 dB); read strategy.json; open a new owner; a PUT with a user strategy "Casual"; HALT; a saved file with a strategy named "New calls" (no built-in) and one named "Casual". Browser: the selector; open the editor with no user strategy; Save; open a built-in; try to change it; Duplicate; Save; rename the copy to a built-in's name and Save.
             Expected: every built-in with builtin true, none in configuration.strategies; active accepted exact only, "casual" refused active; strategies[0].name refused; strategies[0] refused for the key builtin; the run calls DL1XYZ (SNR bucket above 0 dB first); the file holds no built-in and active null; the new owner reads None; the PUT refused strategies[0].name; HALT turns Auto off and keeps "Casual"; the saved "New calls" reads as it is and the saved "Casual" reads renamed "Casual copy". Browser: None and the built-in names; the editor shows the first built-in, Save sends no strategy and active null; the built-in's fields disabled, Delete disabled, no PUT of a built-in; the copy "New DXCC copy" the only user strategy saved; the colliding rename refused with its field shown.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-11';
        }
        attribute executable : String = "server/src/strategy_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_039_11_verified_by_TC_039_032 from 'CL-039-11' to 'TC-039-032';
    verification 'TC-039-033' {
        doc /* TC-039-033 — A strategy without a client and its run limit
             CL-039-05
             Setup: as TC-039-004 (Auto on after each selection); the automation clock of the test moved by the seam; no status WebSocket unless a session is held or, in one case, a real upgrade over the served router; reads through the browser routes, which are not clients here.
             Steps: select and Auto on; at 59 s publish CQ K1ABC; at 60 s run the exchange to its end; publish a CQ and a call to my call; an MCP start; Auto on again; at 60 s without a contact publish a CQ; a session held from 0 s and released at 120 s, ticks at 179 s and 180 s; an MCP request at 59 s, a tick, ticks at 118 s and 119 s; a client back at 59 s of a contact past 60 s; at 60 s with K1ABC silent and a spot of my call at K1ABC; a CQ of a strategy with CQ when idle at 60 s; an actual status WebSocket upgrade with the browser cookie, past 60 s, then closed. Run limit, a client connected throughout: a CQ just before 8 h; at 8 h the exchange to its end; a CQ; Auto on again; again just before and at 8 h after that start.
             Expected: K1ABC selected and armed at 59 s; the contact goes on at 60 s to completed, then stopped no_client, Auto off, the strategy still selected, neither the CQ nor the caller called; the MCP start refused operator_required; Auto on waits and answers; stopped no_client at 60 s with nothing selected; waiting at 179 s and stopped at 180 s; waiting at 118 s and stopped at 119 s; no stop when the client came back before the contact ended; the silent K1ABC left at 4 repetitions, not 8, then stopped no_client; the CQ disarmed and cancelled at once and stopped no_client; waiting while the real WebSocket is open and stopped no_client after it closes. Run limit: selected and armed just before 8 h; the contact goes on at 8 h to completed, then stopped run_limit, Auto off, still selected, the CQ not called; the new start waits, answers and stops run_limit 8 h after it.
             2 — Isolated automated functional tests; Windows development PC, transmit double; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_05_verified_by_TC_039_033 from 'CL-039-05' to 'TC-039-033';
    verification 'TC-039-040' {
        doc /* TC-039-040 — The filter and the value order
             CL-039-02
             Setup: the evaluator as a function with the pinned cty.dat fixture, a hand log and hand-authored codec-packed rows for HB9BLA JN47AA (EU) on 20 m FT8: CQ K1ABC FN42 -12 at 1200 Hz, CQ JA1XYZ PM95 -15 at 900 Hz, CQ DL1XYZ JO62 -3 at 1500 Hz, CQ VK2ABC QF56 -20 at 600 Hz, CQ ZS6AA -8 at 2000 Hz (no grid), CQ OH1AA KP20 -3 at 1400 Hz, HB9BLA W1AW FN31 -25 (a caller); the log has K1ABC and W1AW on 20 m, DL1XYZ on 40 m only, OH1AA on 20 m today; a Most Wanted list with JA (rank 40) and VK (rank 90). Distances are computed in the test by the haversine formula written there from the locator and grid centres and the cty.dat centres.
             Steps: new [call] per band with order [snr], [distance], [most_wanted], [most_wanted, distance], [new_dxcc, snr]; new [call, grid, dxcc] (every station of the rows a candidate) with Calling stations are answered off and each needed-first criterion alone before [snr]: [new_dxcc] (log: a DL QSO on 40 m), [new_dxcc_band] (on 20 m: DL worked on 40 m only), [new_dxcc_band_mode] (an FT4 QSO with JA on 20 m), [new_call] (K1ABC logged), [new_call_band], [new_grid] (FN42 logged on 40 m), [new_grid_band] (FN42 logged on 40 m; a row without grid; a call with a logged 20 m QSO without grid); the same with the station band unknown; new [call] per ever; worked since today with Calling stations are answered on; DL1XYZ and OH1AA at the same SNR (an exact tie except frequency); two verdicts at the same SNR and frequency; Calling stations are answered on and off with order [snr]; an empty order list; the caller W1AW failing every filter line (worked, region, minimum SNR -10).
             Expected (hand-worked): each needed-first criterion puts the needed stations before the others and leaves SNR order inside each group, the caller W1AW without a rank (callers off): [new_dxcc] DL1XYZ after the rest; [new_dxcc_band] DL1XYZ needed on 20 m; [new_dxcc_band_mode] JA1XYZ needed (FT4 is another mode); [new_call] K1ABC after; [new_call_band] K1ABC and OH1AA after; [new_grid] K1ABC (FN42) after; [new_grid_band] K1ABC (FN42 not on 20 m) needed, the row without grid and the call with an unknown grid status not needed, a band unknown nothing needed; new_call_band excludes K1ABC and W1AW as candidates (worked on 20 m) and keeps DL1XYZ; [snr]: DL1XYZ, OH1AA (frequency 1400 before 1500 when tied: OH1AA first), ZS6AA, JA1XYZ, VK2ABC; [distance]: VK2ABC, JA1XYZ, ZS6AA (entity centre), OH1AA, DL1XYZ; [most_wanted]: JA1XYZ, VK2ABC, then the rest by SNR; [most_wanted, distance] the same for the listed, then by distance; band unknown: no candidate for new [call] per band; worked since today: OH1AA not needed by new [call] per band, W1AW (not in that log) a caller that passes, first; the exact tie of SNR and frequency ordered by call; Calling stations are answered on: W1AW first; off: W1AW has no rank (CL-097-03); the empty list: SNR order; W1AW ranks only where it passes the filters and fails them in the step failing every filter line (TC-097-007); the reasons name the needed whats; sequence (decode order) never changes an order. Red on the parent: the criteria do not exist.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-02';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_02_verified_by_TC_039_040 from 'CL-039-02' to 'TC-039-040';
    // TC-039-041 retired: its schema 2 and schema 3 store cases are TC-097-002's and its built-ins
    // TC-097-003's. The identity is not reused.
    verification 'TC-039-042' {
        doc /* TC-039-042 — The Auto toggle
             CL-039-22, CL-039-05
             Setup: the actual station router (HB9BLA JN47AA) with the contact engine and #9 transmit owner on the recording hardware double, virtual UTC, 20 m; a status session held open; the browser cookie grant; an MCP token; a saved strategy "New calls" of class strategy (new [call] per ever, not worked, order [most_wanted]).
             Steps: GET /strategy; select "New calls" and publish CQ K1ABC FN42 for two periods; POST /strategy/auto true; another selection with Auto on; Auto false; Auto true without a selection (None); select None with Auto on; HALT by route and by MCP; a station restart; Auto true from the MCP principal; extra key, wrong profile, stale boot; a contest WW Digi (forbidden) with Auto true without and with automation_confirmed; FT8 Activity (silent) without it; with Auto on for FT8 Activity, a selection change to WW Digi; a run stopped tx_watchdog by a manual contact, then a browser Auto on; with Auto off a pounce armed on K1ABC, then a PUT selecting "Test calls", then Auto on; a strategy.state subscriber across each change.
             Expected: auto false by default; with Auto off the verdicts mark K1ABC and nothing is armed or keyed; Auto true starts the run, K1ABC selected and armed; another selection ends the run and starts the new one, Auto still on; Auto false disarms and cancels at once, the run stopped, the strategy selected (K1ABC has sent nothing to my call, so no QSO has started: #81, CL-081-01; a started QSO is TC-081-001); 409 not_configured strategy and Auto off; None turns Auto off; HALT turns Auto off, the run stopped halted, active kept; after the restart auto false and active None; the MCP principal refused 401, nothing changed; 400 invalid_request, 403 wrong_profile, 409 state_conflict boot_id; WW Digi refused field automation_confirmed and accepted with it, FT8 Activity accepted; the change to WW Digi while Auto is on ends the run, starts none and turns Auto off; the Auto on ends the watchdog stop and arms; the PUT with Auto off leaves the pounce running and armed, and Auto on ends it; one strategy.state per change, none on subscription. No PTT exchange.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-22';
            verify 'CL-039-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_22_verified_by_TC_039_042 from 'CL-039-22' to 'TC-039-042';
    dependency CL_039_05_verified_by_TC_039_042 from 'CL-039-05' to 'TC-039-042';
    verification 'TC-039-043' {
        doc /* TC-039-043 — Leaving in a strategy run
             CL-039-23, CL-039-05
             Setup: as TC-039-042 with Auto on, strategy "Test" of class strategy (new [call] per ever, order [snr], leave {calls 4, calls_heard 8}, retry_minutes 10, Calling stations are answered on, busy_pause off), the feed without a connection fed hand-authored spots, a dial of 14074000 Hz; the run calling K1ABC (CQ FN42). The callers JA1XYZ and W1AW pass the filters (new calls). The other leave modes are TC-097-009.
             Steps: (a) K1ABC silent (not decoded) for 5 partner periods. (b) K1ABC calling CQ again each period. (c) As (a) with a spot of my call at K1ABC 60 s old; the same with Use PSK Reporter off. (d) K1ABC answers with -05 after the 2nd repetition and repeats -05 for 6 periods (the #63 fix). (e) A caller W1AW selected, repeating its first call 5 times. (f) A stronger new CQ DL1XYZ from the 2nd repetition on. (g) A caller JA1XYZ at the 2nd repetition; the same with Calling stations are answered off; with JA1XYZ in its retry pause; after K1ABC has answered. (h) After (a): K1ABC's CQ alone at 9 min 59 s and at 10 min, and its call to my call at 5 min. (i) leave {calls 1, calls_heard 2}. (j) The band changed to 40 m in a stay; a new live identity (FT4); Auto off; HALT.
             Expected (hand-worked from the operator's rule): (a) and (b) armed after 3, disarmed and cancelled at the 4th, left {K1ABC, repetitions}, quiet K1ABC 600 s, waiting; (c) armed after 7, left at the 8th; with Use off left at the 4th; (d) never left during the 6 repeats, unanswered back to 0 at each (red on the parent, which leaves at the calls); (e) left at the 4th; (f) K1ABC kept, DL1XYZ never selected before the 4th, selected at the next step after it; (g) left {K1ABC, caller} at once and JA1XYZ selected from the same publication; callers off, in its retry pause or after an answer: K1ABC kept; (h) not selected at 9 min 59 s nor answered at 5 min, selected at 10 min; (i) left at the 1st; (j) disarmed and cancelled at the next step, no quiet entry, left null, the run waiting (band, mode) and selecting from the next publication, stopped (Auto off, HALT); in a stay K1ABC has not answered, so no QSO has started and Auto off disarms at once (#81, CL-081-01).
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-23';
            verify 'CL-039-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_05_verified_by_TC_039_043 from 'CL-039-05' to 'TC-039-043';
    verification 'TC-039-044' {
        doc /* TC-039-044 — Leaving in a contest run
             CL-039-23, CL-063-05
             Setup: as TC-063-009 (WW Digi, 20 m, the period in force, W1DUP a dupe in the log) with Auto on and automation_confirmed; a copy of the contest built-in "WW Digi" with cq_when_idle false, leave {calls 2, calls_heard 4} for (a) and (b), leave {contest, tx_changes 1} with tx_move_every {heard 0, not_heard 1, no_reports 1} for (c), (d) and (e) (a move at the 1st call, the leaving at the 2nd), retry_minutes 10; for (f) the built-in with cq_when_idle true; the feed fed hand-authored spots; the run calling K1ABC FN42 (new multiplier).
             Steps: (a) K1ABC silent, no spot. (b) K1ABC silent with a spot of my call at K1ABC. (c) K1ABC calling CQ again for 10 periods with the spot; then CQ JA1XYZ PM95 (new multiplier, more points) from the 6th; again with JA1XYZ from the 1st repetition. (d) W1DUP (dupe) calling my call for 8 periods during (c) (the #63 fix). (e) A non-dupe caller K2NEW FN31 at the 1st repetition. (f) The CQ when idle: CQ, caller K2NEW answered, then silent; K2NEW calling again during its retry pause. (g) leave {calls 3, calls_heard 6} and retry_minutes 1 in the strategy. (h) The station clock past the period end in a contact; the contest deselected (None) in a contact.
             Expected (hand-worked): (a) left at the 2nd; (b) left at the 4th; (c) stays all 10 with the spot and nothing more valuable; with JA1XYZ listed from the 6th a stay has no count, so the 6th call is a change point and K1ABC is left at the 7th with reason tx_changes, then JA1XYZ is selected; JA1XYZ from the 1st: K1ABC kept until the 2nd, then left and JA1XYZ selected; (d) the stay holds, W1DUP never selected or answered (red on the parent, where the dupe ends the stay); (e) left {K1ABC, caller} at once, K2NEW selected; (f) K2NEW answered from the CQ's slot (Tx and Rx stay on 900, the CQ quiet in my Rx parity, #66), left at the 2nd, calling_cq again, K2NEW not answered while quiet; (g) left at the 3rd, called again after 1 minute; (h) disarmed and cancelled at once, waiting outside_period; stopped, Auto off (K1ABC has not answered the call in (h), so no QSO has started; a started contest QSO at the period end or deselection finishes: #81, TC-081-003).
             #39 holdtx: these steps run with Hold Tx explicitly off (they test the run logic; Rx = Tx on the slot); with Hold Tx on the CQ of (f) stays on the held Tx: TC-039-049 (j).
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-23';
            verify 'CL-063-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_063_05_verified_by_TC_039_044 from 'CL-063-05' to 'TC-039-044';
    verification 'TC-039-045' {
        doc /* TC-039-045 — CQ when idle
             CL-039-22
             Setup: as TC-039-042 with Auto on and the saved strategy "Casual 20 m" of class strategy (new [call] per band, worked_since today, order [snr], cq_when_idle true, cq_wait_periods 2); the log holds W1AW on 20 m today; Tx watchdog 6.
             Steps: two publications with nothing callable; a third; W1AW (worked today) calls my call, then N1NEW FN31 (not in the log); N1NEW's QSO to the end; two empty publications; CQ DL1XYZ JO62 while calling CQ; callers at 1200 Hz and at 920 Hz with the CQ on 900; the same strategy with cq_when_idle false for 6 empty publications; Tx watchdog 2 with an unanswered CQ; no client for 60 s while calling CQ; the slot of the CQ with one parity loud.
             Expected: waiting after the first, calling_cq after the second, armed, Tx6 "CQ HB9BLA JN47"; a caller is answered from the CQ's slot: with the CQ on 900 (quiet in my Rx parity, #66) a caller at 1200 Hz keeps Tx and Rx on 900, a caller at 920 Hz moves them to 820, the nearest candidate 50 Hz away from it; W1AW not answered (it fails the filters, TC-097-007); N1NEW answered with select_row {replace false} and Enable Tx kept; completed, then calling_cq again after two empty publications; DL1XYZ selected and called, the CQ ended; off: never a CQ, nothing armed; watchdog 2: stopped tx_watchdog, Auto off, not keyed again; unattended: the CQ disarmed and cancelled at once, stopped no_client; the CQ's slot the quietest in my Rx parity, the loud parity ignored when it is my Tx parity (#66: the CQ judges only my Rx periods).
             #39 holdtx: these steps run with Hold Tx explicitly off; with Hold Tx on the CQ goes out on the held Tx and the callers are TC-039-049 (h).
             #66: the step "the slot of the CQ with one parity loud" is run twice, the loud parity my Tx parity (ignored) and my Rx parity (avoided); a caller's nearest candidate 50 Hz away also skips a station decoded in my Rx periods (TC-066-002 (h)).             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-22';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_22_verified_by_TC_039_045 from 'CL-039-22' to 'TC-039-045';
    verification 'TC-039-046' {
        doc /* TC-039-046 — Auto, Use PSK Reporter, the QSO pane lines and the editor in the browser
             CL-039-04, CL-039-20, CL-039-22, CL-063-05
             Setup: the actual isolated server and Chromium at 1366x768 and 360x740; routed replies for GET and PUT /strategy, POST /strategy/auto, GET /pskr, POST /pskr/use, GET /strategy/contests and GET /automation; pushed strategy.state, pskr.state and automation.state.
             Steps: open with no selection; select the saved strategy "New calls" (class strategy); click Auto; push the snapshot with auto true; push a HALT (auto false); click PSK; push enabled false (Settings off); push a run with hearing {heard, 75 s old, -12} and tx_slot {1420, his_end yes}, then {heard, 600 s}, {no}, {unknown} and his_end no and unknown; Use off; 10 s with no event; a contest prompt for WW Digi, Start; Auto on with the warning declined, then confirmed; FT8 Activity. The editor's steps are TC-097-014's and the prompt's fields TC-097-015's.
             Status (the station element and the contest status, from pushed automation.state and strategy.state): a waiting run, calling_cq, Auto off, a contest with Auto on and with Auto off; the contact snapshot without transmit capability.
             Expected: the strategy element reads "Strategy New calls waiting", "Strategy New calls · calling CQ" and "Strategy New calls · Auto off"; the contest status "Contest WW Digi · <period> UTC · WW Digi · Auto on" and "· Auto off" (the strategy name); Auto disabled with the reason "Receive only" as its title without transmit capability; Auto disabled with its reason without a selection; selecting sends one PUT and nothing else; the click sends exactly one POST /strategy/auto {auto true}; the button green only after the push and grey after the HALT push; PSK sends POST /pskr/use {use false} and is disabled with "PSK Reporter is off in Settings" when the switch is off; the lines "Hears us: 75 s ago · −12 dB" and "Tx 1420 Hz · open at his end: yes", then "Hears us: 10 min ago · −12 dB", "Hears us: no", "Hears us: unknown", "· no", "· unknown"; no lines with Use off or without a target; no request during the silence (no polling); the prompt's Start sends one PUT without automation_confirmed; Auto on for WW Digi shows the clause, sends nothing when declined and one POST with automation_confirmed true when confirmed; no warning for FT8 Activity; no horizontal overflow at 360 px and the QSO pane keeps its height.
             2 — Isolated automated browser test; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-04';
            verify 'CL-039-20';
            verify 'CL-039-22';
            verify 'CL-063-05';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_039_20_verified_by_TC_039_046 from 'CL-039-20' to 'TC-039-046';
    dependency CL_039_22_verified_by_TC_039_046 from 'CL-039-22' to 'TC-039-046';
    dependency CL_063_05_verified_by_TC_039_046 from 'CL-063-05' to 'TC-039-046';
    verification 'TC-039-047' {
        doc /* TC-039-047 — Live strategydef on HB9BLA at 30 W, 20 m FT8
             CL-039-02, CL-039-09, CL-039-20, CL-039-21, CL-039-22, CL-039-23
             Setup: the gated candidate installed on HB9BLA, IC-7300 on COM3 on 20 m FT8 (14.074 MHz), RF power set by the test to at least 30 W before the first Tx (CI-V 14 0A, starting at 0090, with the station stopped and idle, because it holds COM3; read back; the first Tx must read Po at least 30 %; if below, raise the value and repeat; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported), operator consent; Tx watchdog 6; PSK Reporter on in Settings and Use PSK Reporter on; the saved strategies of class strategy "Strongest new on band" (new [call] per band, order [snr]), "Farthest new on band" (order [distance]) and "Casual 20 m" (as TC-039-045), each with leave {calls 4, calls_heard 8} and retry_minutes 10. The built-ins live are TC-097-016's.
             Steps: select "Strongest new on band" with Auto off for two periods; switch Auto on and let it work stations to two logged QSOs; watch a station that does not answer; watch the PSK Reporter lines and the Tx slot at each repetition; HALT; Auto on again; select "Farthest new on band" and let it work one QSO; select "Casual 20 m" and let it call CQ and answer a caller; Auto off during a CQ; select None.
             Expected: with Auto off the candidates are marked by SNR and nothing is transmitted; with Auto on the strongest new call on band is called first, to a logged QSO, and it goes on; a station that does not answer is left after 4 repetitions (8 while the QSO pane shows "Hears us" with a spot) and not called again for 10 minutes; while there is no spot Tx (with Hold Tx on; Tx and Rx together with Hold Tx off) moves to the quietest slot at a repetition or stays on a tie, and with a spot Tx stays; the QSO pane shows "Hears us" and "open at his end" with the slot; HALT stops at once, Auto grey, the selection kept; Farthest calls the farthest new call on band first; Casual calls CQ after 2 periods without a candidate and answers a caller to a logged QSO; Auto off ends the CQ at once; None leaves Auto off. Not live: the contest rules (no contest in progress; TC-039-044 at cost 2), the 8 h limit and the 60 s without a client (TC-039-033 at cost 2): named on #39 for the operator.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-039-02';
            verify 'CL-039-09';
            verify 'CL-039-20';
            verify 'CL-039-21';
            verify 'CL-039-22';
            verify 'CL-039-23';
        }
    }
    dependency CL_039_02_verified_by_TC_039_047 from 'CL-039-02' to 'TC-039-047';
    dependency CL_039_09_verified_by_TC_039_047 from 'CL-039-09' to 'TC-039-047';
    dependency CL_039_20_verified_by_TC_039_047 from 'CL-039-20' to 'TC-039-047';
    dependency CL_039_22_verified_by_TC_039_047 from 'CL-039-22' to 'TC-039-047';
    verification 'TC-039-048' {
        doc /* TC-039-048 — PSK Reporter use, reported SNR, his decodes by parity and the hearing state
             CL-039-20, CL-039-23, CL-039-09
             Setup: as TC-039-020 (no network, a local MQTT peer, hand-authored payloads, the actual station router) with the contact engine and #9 owner on the recording hardware double, virtual UTC, a dial of 14074000 Hz; a strategy run with Auto on calling K1ABC from Tx 1500; a contest run (the WW Digi built-in) for the subscription; hand-authored waterfall rows.
             Steps: parse spots with rp -5, -99, 99, absent, 100, "x" and 2.5; spots to K1ABC from other senders at 14075200 Hz with t_tx in an even and in an odd period, twice the same offset in both parities; pskr.json of schema 1, schema 2 with use false, broken; POST /pskr/use {use false} and true, with an extra key, another profile, a stale boot, from the MCP principal; GET /pskr; a pskr.state subscriber; Use off and on during the run, and the subscription of a contest run's target; hearing with the feed connected and no spot, a spot 60 s old with rp -12, 601 s old, the feed not connected, a target call with a slash; the slot with his decoded offset of my Tx parity at the quietest slot, of the other parity there, and none.
             Expected: rp -5, -99 and 99 kept; absent, 100, "x" and 2.5 read as unknown and the spot still counts; offsets [1200] with their parities, the same offset kept once per parity; schema 1 reads use true and is written as schema 2 at the next change, use false read, the broken file reads enabled true and use true with invalid_pskr; use saved and returned by GET /pskr and pskr.state, the refusals 400 invalid_request, 403 wrong_profile, 409 state_conflict boot_id, 401 for MCP; with Use off no target subscription (UNSUBSCRIBE seen) and the run's hearing state unknown, with Use on SUBSCRIBE pskr/filter/v2/+/+/+/K1ABC/# again, also for the contest target; hearing {no, null, null}, {heard, t, -12}, {no}, {unknown}, {unknown}; when the only slot left lies within 50 Hz of his offset of my Tx parity Tx stays on 1650 with slot_check.moved false (no fallback, WstxStrategy::TxMoveRule), else the next quietest slot with his_end yes, the other parity's offset not excluding, his_end unknown without spots. Red on the parent: rp, use and the parity do not exist.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF, no network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-20';
            verify 'CL-039-23';
            verify 'CL-039-09';
        }
        attribute executable : String = "server/src/pskr_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_039_20_verified_by_TC_039_048 from 'CL-039-20' to 'TC-039-048';
    dependency CL_039_09_verified_by_TC_039_048 from 'CL-039-09' to 'TC-039-048';
    verification 'TC-039-049' {
        doc /* TC-039-049 — Hold Tx on in a run: Tx stays, Rx on the station, Tx alone moves when he does not hear us
             CL-039-08, CL-039-09, CL-039-21, CL-039-22
             Setup: as TC-039-022 (the actual station router, contact engine, automation and #9 transmit owner on the recording hardware double, virtual UTC, a feed without a connection fed hand-authored spots, a dial of 14074000 Hz, hand-authored waterfall rows), Hold Tx on (the default), Tx 1500, FT8 and FT4; a strategy run with Auto on (leave {calls 4, calls_heard 8}, tx_move_every {heard 0, not_heard 1, no_reports 1}), a copy of the contest built-in WW Digi with cq_when_idle false, the built-in itself (cq_when_idle true), a pounce, a plain MCP run; the saved strategy "Casual 20 m" (class strategy, cq_when_idle true) for the CQ.
             Steps: (a) select K1ABC (CQ at 1800 Hz). (b) 2 repetitions with no spot, the quietest slot 1400, then 1300. (c) A repetition whose quietest slot lies within 50 Hz of Rx (1800 signal). (d) A spot of my call at K1ABC 60 s old. (e) His report after the 1st repetition, then silent periods. (f) Select a station at 1520 Hz (within 50 Hz of the held Tx), and a caller at 1530 Hz. (g) The held Tx at 2700 (FT4), a station at 1000; then an unanswered repetition with no spot. (h) The CQ when idle from the held Tx 900, one parity loud; callers at 1200 and at 920. (i) Hold Tx switched off during the contact, then the next repetition. (j) The contest copy: (a) and (b); the contest built-in: (h) (its CQ from the held Tx 900, callers at 1200 and at 920). (k) Pounce on K1ABC. (l) Plain MCP run.
             Expected (hand-worked from the operator's rule, #39 holdtx round 1): (a) Tx 1500, Rx 1800, no set_frequency of Tx, tx_slot.hz 1500; (b) Tx 1400 then 1300, Rx 1800 both times, slot_check {repetitions, hears_us false, hz}; (c) that slot excluded, the next quietest chosen; (d) Tx stays, hears_us true; (e) Tx never moves after the report; (f) Tx to the nearest slot 50 Hz clear of the station's signal (the lower on a tie), Rx on the station; (g) Tx 2700 kept at the selection, Rx 1000; at the repetition Tx moves to the quietest slot inside 500..2610 (2700 is no candidate, round 3 Q6), Rx stays 1000; (h) the CQ keyed on 900 with no slot decision; the caller at 1200 answered from 900, Rx 1200; the caller at 920 moves Tx to the nearest slot 50 Hz clear of it, Rx 920; (i) Tx and Rx together on the slot (Hold Tx off rule); (j) the copy as (a) and (b), the built-in as (h); (k) Tx stays 1500, Rx on K1ABC, never moved; (l) tx_slot null, Tx kept. Red on the parent: (a), (b), the selection of (g), (h), the built-in of (j) and (k) set Rx = Tx on the slot (the repetition of (g) is green on the parent, which also moves Tx into the range).
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-08';
            verify 'CL-039-09';
            verify 'CL-039-21';
            verify 'CL-039-22';
        }
        attribute executable : String = "server/src/strategy_tests.rs; server/src/automation_tests.rs::tc_039_010_a_plain_policy_run_keeps_its_tx_on_the_called_station";
    }
    dependency CL_039_08_verified_by_TC_039_049 from 'CL-039-08' to 'TC-039-049';
    dependency CL_039_09_verified_by_TC_039_049 from 'CL-039-09' to 'TC-039-049';
    dependency CL_039_22_verified_by_TC_039_049 from 'CL-039-22' to 'TC-039-049';
    verification 'TC-039-050' {
        doc /* TC-039-050 — Quietness above the passband floor (#66 replaces the usual level)
             CL-039-09
             Setup: the slot function and the per-period waterfall power with hand-authored detailed rows (levels in dB per bin, written in the test), FT4 and FT8, no decoded station unless a step names one; the actual station router for the status. Floor oracle: a flat floor F gives the floor F + 0.65 exactly (the lowest tenth of every segment is F); a sloped table's floor is a reference vector from an independent least-squares fourth-order fit (numpy.polynomial, version recorded with the vector) through the lowest-tenth points of its ten segments, plus 0.65 dB, stored next to the test with its source.
             Steps: (a) the FT4 roll-off table: a floor of 30 dB flat to 2400 Hz and falling linearly to 15 dB at 2700 Hz (5 dB per 100 Hz, a sharp knee the fourth-order floor cannot follow: the roll-off slots read about 2 dB below it) in all 4 counted Rx periods, and AA3B 12 dB above the floor at 2621 Hz (width 90), not decoded, the reproduction of 2026-11-07 (tx_slot 2610 power_db 29); twice: the current Tx 1500 on the flat floor, and the current Tx 1500 on an undecoded station 18 dB above the floor at 1500.5..1590.5 Hz (an FT4 signal; level and position chosen so that the parent's rule makes the same choice). The fixture is authored so that every candidate deciding the choice (those no farther from the current Tx than the chosen slot) has its compared value, its largest rise clamped at 0, at least 0.1 dB from a half dB (the vector's margin_db), so the whole-dB rounding of the choice is unambiguous. (b) FT8 flat floor 30, the current Tx 1500 on a slot 5 dB above the floor in all 4 periods, every other slot on the floor. (c) Busiest period: slot A on the floor in 3 periods and 6 dB above it in one, slot B 3 dB above it in all 4, every other candidate covered 10 dB above the floor. (d) The floor 30 in the two older periods and 32 in the two later, everywhere. (e) One counted period only, the current Tx on a slot 4 dB above the floor. (f) A period I transmitted in; a 5th older Rx period quiet at another slot; after the Tx parity changed, my last counted Rx periods 3 minutes old. (g) A station band change. (h) Values 0.4 against 0.0 (a tie) and 0.6 against 0.0. (i) Coverage: one period whose levels end at bin 921 (2698.2 Hz) and one whose levels end at bin 920 (2695.3 Hz), the other periods unchanged; a flat-floor period with one segment where only its 8 lowest bins sit at the floor (the minimum of 8 points from that segment). (j) No counted period. (k) The status of each.
             Expected (hand computation recorded in the test, the floor from the reference vector): (a) the roll-off slots below the floor read 0 (clamped), the same as the free mid-band slots, never lower; the slots on AA3B stay positive; with Tx 1500 on the flat floor Tx stays 1500 (value 0, the current Tx kept); with Tx 1500 on the station Tx goes to 1410 (value 0), the free slot nearest 1500, the lower on equal distance; never a slot in 2400..2610 and never 2530 (raw level alone would choose 2530 at 21 dB on the roll-off; the unclamped floor rule chose 2530 at about -2); (b) Tx leaves 1500 for the nearest floor slot, value 0 (rise -0.65 clamped), the slot at 1500 value 4; (c) B wins, values 2 against 5 (the mean would choose A); (d) a floor slot reads 0 in every period (rise -0.65), not raised by the floor change; (e) one period compares: Tx leaves for the nearest floor slot; (f) the transmitted period, the 5th older period and the 3-minute-old periods never count: no power, Tx kept, power_db null; (g) after the band change only later periods count; (h) 0.4 ties and keeps the current Tx, 0.6 does not; (i) the period ending at bin 921 counts and the one ending at bin 920 does not (its slot values and decodes absent from the result, periods now one less); the 8-point segment fits the floor of the hand computation (the cutoff is its 8th lowest level); (j) the current Tx kept, power_db null; (k) tx_slot.power_db is the whole-dB value of the chosen slot, never negative; free_tx_slots rise_db the same value while level_db and floor_db are the busiest period's as measured (level_db 30 and floor_db 31 on the flat floor of 30). Red on the parent: (b) and (e) keep the current Tx (every rise 0 over its own usual level); (a) is a regression guard, green on the parent and red on the unclamped floor rule.
             #82: (k) free_tx_slots carries no per-slot numbers; only tx_slot.power_db is checked, and the chosen floor slot lies in an open range of the same build when it overlaps no decode.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-09';
        }
        attribute executable : String = "server/src/freeslot_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_039_09_verified_by_TC_039_050 from 'CL-039-09' to 'TC-039-050';
    verification 'TC-039-051' {
        doc /* TC-039-051 — Live Hold Tx in Auto on HB9BLA
             CL-039-08, CL-039-09, CL-039-21, CL-039-22
             Setup: the gated candidate installed on HB9BLA, IC-7300, FT4 or FT8 within the operator's standing transmit consent, Hold Tx on, PSK Reporter on, Auto off at start; contact and run snapshots read from GET /contact and GET /automation at each step.
             Steps: select the saved strategy "Farthest new on band" (as TC-039-047), Auto on, let it call stations to one logged QSO and through a station that does not answer; note tx_hz and rx_hz before and after each selection and at each repetition; select "Casual 20 m" and let it call CQ; switch Hold Tx off and let it call one station; HALT.
             Expected: with Hold Tx on tx_hz unchanged by a selection unless the station is within 50 Hz of it, rx_hz the station's decoded frequency; at a repetition with slot_check.hears_us false only tx_hz changes and its signal stays at least 50 Hz from the Rx signal; after an answer or with a spot tx_hz unchanged; the CQ keyed on the held tx_hz; no chosen slot overlapping a station decoded in my Rx periods when a slot with a lower rise and none exists (power_db the rise); with Hold Tx off rx_hz equals tx_hz on the slot.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-039-08';
            verify 'CL-039-09';
            verify 'CL-039-21';
            verify 'CL-039-22';
        }
    }
    dependency CL_039_08_verified_by_TC_039_051 from 'CL-039-08' to 'TC-039-051';
    dependency CL_039_09_verified_by_TC_039_051 from 'CL-039-09' to 'TC-039-051';
    dependency CL_039_22_verified_by_TC_039_051 from 'CL-039-22' to 'TC-039-051';
    requirement 'CL-042-01' {
        doc /* What must be new reads the sender's cty.dat entity (#55) against the internal log: new [dxcc] per ever, band and band_mode, and new [cq_zone] per ever (WstxStrategy::NewNeeded); a sender without an entity, an unknown station band (for band and band_mode) or an unreadable log never counts as new. The editor offers them in decision 2; the live preview names why. Details: WstxStrategy::NewNeeded. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/dxcc.rs; server/src/logbook.rs; client/contact.js";
    }
    dependency CL_042_01_to_FR_007 from 'CL-042-01' to 'FR-007';
    dependency CL_042_01_to_FR_011 from 'CL-042-01' to 'FR-011';
    verification 'TC-042-001' {
        doc /* TC-042-001 — New DXCC and CQ zone against a hand log
             CL-042-01
             Setup: the bundled cty.dat; a worked set from a hand log: DL1ABC 40m FT8 unconfirmed (Fed. Rep. of Germany, EU, CQ 14, ITU 28), JA1XYZ 20m FT8 confirmed (Japan, AS, 25, 45), F1ABC 40m FT4 confirmed (France, EU, 14, 27), K2ABC with no band (United States, NA, 5, 8), Q1ABC 40m FT8 (no entity); station HB9BLA JN47AA on 40m FT8; rows CQ DL2XYZ, CQ F5ABC, CQ JA2ABC, CQ VK2ABC (Australia, OC, 30, 59), CQ K1ABC, CQ XX1ABC (no entity), CQ DL1ABC. A browser case: the editor offers what must be new and the station keeps it.
             Steps: evaluate strategies of new [dxcc] per ever, per band and per band_mode, and new [cq_zone] per ever, new means not_worked; the same with the station band unknown and with the log unreadable.
             Expected (entity columns of the cited cty.dat lines; the log of the test): [dxcc] ever VK2ABC only; [dxcc] band JA2ABC VK2ABC K1ABC; [dxcc] band_mode also F5ABC; [cq_zone] ever VK2ABC only; XX1ABC never; band unknown: band and band_mode never new, ever unchanged; log unreadable: nothing new.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-01';
        }
        attribute executable : String = "server/src/strategy_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_042_01_verified_by_TC_042_001 from 'CL-042-01' to 'TC-042-001';
    requirement 'CL-042-02' {
        doc /* Two-tier ignore lists govern the strategy: a permanent list of calls (Settings > General, saved in the strategy configuration) and a session list in station memory (Band Activity right-click "Ignore <call>" / "Stop ignoring <call>", POST /strategy/ignore), whose entries end after the configured minutes (1..720, default 30) and which the station empties on any change of the station band. An ignored sender (exact call) is never a candidate or a caller: it gets no mark and a run never selects it; a contact already in progress and a manual Reply or Select are not changed. A saved configuration from before the lists reads with empty lists and 30 minutes. Details: WstxStrategy::IgnoreLists. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/automation.rs; server/src/contact_http.rs; server/src/main.rs; client/contact.js; client/recording.css";
    }
    dependency CL_042_02_to_FR_007 from 'CL-042-02' to 'FR-007';
    dependency CL_042_02_to_FR_010 from 'CL-042-02' to 'FR-010';
    dependency CL_042_02_to_FR_020 from 'CL-042-02' to 'FR-020';
    verification 'TC-042-002' {
        doc /* TC-042-002 — Ignore lists in the evaluator, the store, the routes and strategy runs
             CL-042-02
             Setup: hand-authored rows CQ K1ABC FN42, CQ DL1XYZ JO62, CQ NA W1AW FN31, HB9BLA VK2ABC QF56; the station HB9BLA JN47AA on 40m; the actual station router, contact engine and #9 transmit owner on the recording hardware double (virtual UTC; no audio, PTT or radio); synthetic monotonic instants for the session expiry.
             Steps: parse the configuration with ignore_calls and session_ignore_minutes and refuse a duplicate, a lower-case or a 14-character call, 101 calls, minutes 0 and 721; read a saved pre-#42 file without both keys and with only one of them; evaluate a new_call strategy with K1ABC on the permanent list, on the session list and on both, and with W1AW (greyed) ignored; the session list: add, renew, remove, expiry at the minute boundary, 65 adds, a band change and a band unknown; POST /strategy/ignore accepted and refused (extra key, bad call, wrong profile, stale boot), GET /strategy session_ignore; the station tick on another band; a strategy run with the strongest candidate ignored, and with an ignored caller.
             Expected: the round trip keeps both keys; the refusals name ignore_calls[i], ignore_calls and session_ignore_minutes; the pre-#42 file reads with [] and 30, the one-key file is invalid_configuration; K1ABC rank null, grey false, why "K1ABC is ignored (permanent list)", "(session list)", session first when on both; W1AW also not greyed when ignored; an entry ends exactly at added + minutes and reports remaining_s rounded up; renewal moves it last with a new expiry; the 65th add drops the oldest; a band change (also to unknown) empties the list; the route returns the snapshot at an unchanged revision with the refusal codes and fields of PUT /strategy; a run selects the next candidate, never the ignored one, and the other caller, never the ignored one; no transmit key in any evaluation.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-02';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_042_02_verified_by_TC_042_002 from 'CL-042-02' to 'TC-042-002';
    verification 'TC-042-003' {
        doc /* TC-042-003 — Band Activity Ignore and the Settings ignore lists
             CL-042-02
             Setup: the browser fixture of the operating screen with the actual isolated station and its fixture live decodes; a strategy active.
             Steps: right-click a decoded row with a resolved sender; choose Ignore; open the menu again on that row; open Settings > General; enter two calls in the permanent list; change the session minutes; remove the session entry.
             Expected: the menu offers Reply, Select, Set Rx here, "Pounce <call>" (#42 CL-042-03) and "Ignore <call>", Ignore sends POST /strategy/ignore {call, ignore true} and does not set the Rx frequency; the row loses its strategy mark after the station's new verdicts; the menu then offers "Stop ignoring <call>"; Settings lists the call with its remaining minutes; the permanent list saves with PUT /strategy as ignore_calls in upper case, the minutes as session_ignore_minutes; remove sends ignore false and the list is empty; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_042_02_verified_by_TC_042_003 from 'CL-042-02' to 'TC-042-003';
    requirement 'CL-042-03' {
        doc /* Pounce waits for one chosen call and answers it: an operator action (Band Activity right-click "Pounce <call>") starts a station automation run with pounce <call> on the current band and mode (one run at a time, so never beside a strategy run, and needing a known band); when that call is decoded sending a CQ that the directed-CQ rule leaves to me, or an RR73/73 ending another QSO (then my Tx frequency is held), and it is on no ignore list, the station answers it as a double-click does (select_row, enable_tx; the contact engine calls in the next own period and Auto Seq runs the QSO). The pounce ends when that contact completes, on a station band change (band_changed), on HALT, the Tx watchdog or the operator's Stop pounce; a contact without an answer for max_unanswered_periods partner periods is cancelled and the pounce waits again. While it runs the QSO pane and the strategy element show it. Details: WstxStrategy::Pounce, WstxMcp::AutomationConfiguration, OperatingAutomation. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/mcp.rs; client/contact.js";
    }
    dependency CL_042_03_to_FR_007 from 'CL-042-03' to 'FR-007';
    dependency CL_042_03_to_FR_020 from 'CL-042-03' to 'FR-020';
    verification 'TC-042-004' {
        doc /* TC-042-004 — Pounce at the station: configuration, answer, ignore, band change and end
             CL-042-03
             Setup: hand-authored rows; the station HB9BLA JN47AA on 40m; the actual station router, contact engine and #9 transmit owner on the recording hardware double (virtual UTC; no audio, PTT or radio); FT8 live job; the browser's grant.
             Steps: parse configurations with pounce absent, null, K1ABC, lower case, 2 characters, K1ABC/R and with K1ABC in blocked_calls; start a pounce with the station band unknown; start a pounce on K1ABC on 40m; publish CQ W1AW FN31 and CQ DL1XYZ JO62; publish CQ K1ABC FN42; run the own period; the partner's report, RR73 and the own 73 period; start again and configure or start a second run while it waits; publish W1AW K1ABC RR73; a pounce on K1ABC with K1ABC on the session ignore list and a CQ K1ABC; a pounce with CQ NA K1ABC (not for EU); a pounce waiting when the station band changes to 20m; a pounce in its contact with max_unanswered_periods 2 and two partner periods without an answer.
             Expected: absent and null read as no pounce, K1ABC accepted, the others invalid_request pounce; not_ready band; the run waits with pounce {K1ABC, 40m} and selects nothing for the other calls (candidates 0); CQ K1ABC is selected (replying, Tx1 "K1ABC HB9BLA JN47", armed) and the own period keys "K1ABC HB9BLA JN47"; the completed contact stops the run completed; a second configure or start is state_conflict run; after the RR73 to W1AW K1ABC is selected with my Tx frequency kept; an ignored K1ABC and the CQ NA are never selected (the run keeps waiting); the band change stops band_changed; two unanswered partner periods disarm and cancel the contact and the run waits again for K1ABC.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-03';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_042_03_verified_by_TC_042_004 from 'CL-042-03' to 'TC-042-004';
    verification 'TC-042-005' {
        doc /* TC-042-005 — Band Activity Pounce and the pounce line in the QSO pane
             CL-042-03
             Setup: the browser fixture of the operating screen with the actual isolated station and its fixture live decodes; the automation routes are hand-written fixtures.
             Steps: right-click a decoded row with a resolved sender; choose Pounce; confirm; announce the started run; open the menu again; choose Stop pounce in the QSO pane.
             Expected: the menu offers "Pounce K1ABC"; it asks once per page session; configure sends exactly {modes [ft8], ranking first_seen, min_snr_db null, allowed_calls [], blocked_calls [], max_contacts 1, max_unanswered_periods 5, completion_action stop, max_run_minutes 480, strategy false, pounce K1ABC}, then start with the shown safety revision; no contact command (no enable_tx) is sent by the browser; the QSO pane reads "Pouncing on K1ABC (40m) · waiting for CQ or 73", the status "Pounce K1ABC waiting · HALT ends it"; the menu then offers "Stop pouncing K1ABC"; Stop pounce sends stop with the run id; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-03';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_042_03_verified_by_TC_042_005 from 'CL-042-03' to 'TC-042-005';
    requirement 'CL-042-04' {
        doc /* Alert has no setting: for each new candidate of the active strategy (an ignored sender, a directed CQ not for me and a caller of my call never alert), the station records an alert (time, call, message, strategy name, band, mode, SNR, DXCC entity) in a history of the last 100 alerts in station memory (kept across page reloads, empty after a station restart), at most one per call and band in 10 minutes, and announces it to the browser; the browser plays a short sound and/or shows a browser notification as the operator chose in Settings > General (both off by default; the notification permission is asked only on the operator's click; no sound while the page is hidden), and lists the history with a Clear. An alert never transmits or changes a contact or automation run. An MCP client may read the history (wstx_read alerts), not clear it. Details: WstxStrategy::Alert; WstxMcpEndpoint::ToolCatalog. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/contact_http.rs; server/src/main.rs; server/src/mcp.rs; client/contact.js";
    }
    dependency CL_042_04_to_FR_007 from 'CL-042-04' to 'FR-007';
    dependency CL_042_04_to_FR_020 from 'CL-042-04' to 'FR-020';
    verification 'TC-042-006' {
        doc /* TC-042-006 — Alert at the station: candidates, dedupe, ignore and directed-CQ rule, history and routes
             CL-042-04
             Setup: hand-authored rows and strategies; the station HB9BLA JN47AA on 40m; the actual station router and contact engine on the recording hardware double (virtual UTC; no audio, PTT or radio); FT8 live job; no grant in the selection path, so no run transmits.
             Steps: publish CQ JA1XYZ PM95 before any strategy is active, then select the strategy "Alerts" (goal new_call); publish in one period CQ K1ABC FN42 (-12 dB), CQ DL1XYZ JO62 (-3 dB), CQ NA W1AW FN31, CQ G4ABC IO91 with G4ABC on the session ignore list and HB9BLA VK2ABC QF56; publish CQ K1ABC FN42 30 s later and 10 minutes after the first; change the band to 20m and publish CQ K1ABC again; read GET /strategy/alerts and wstx_read alerts; clear with an extra key, a wrong profile, a wrong boot and correctly; read GET /strategy/alerts with the MCP principal's cookie and POST the clear with it; publish 101 CQs from different calls in one period.
             Expected: no alert for JA1XYZ; alerts exactly K1ABC {utc of the period, message "CQ K1ABC FN42", rule "Alerts", band 40m, mode ft8, snr_db -12, dxcc United States} and DL1XYZ (Fed. Rep. of Germany), ids 1 and 2, revision 2, none for W1AW, G4ABC or the message to me; nothing 30 s later; a third K1ABC alert 10 minutes later and a fourth on 20m; wstx_read alerts equals the browser's GET; the refusals 400 invalid_request, 403 wrong_profile, 409 state_conflict boot_id leave the history; the clear empties it with revision + 1; the MCP cookie may GET and is refused 401 on the clear; after 101 alerts the history holds the last 100; no contact, no selection and no keying throughout.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-04';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_042_04_verified_by_TC_042_006 from 'CL-042-04' to 'TC-042-006';
    verification 'TC-042-007' {
        doc /* TC-042-007 — The Settings alert history, sound and browser notification
             CL-042-04
             Setup: the browser fixture of the operating screen with the actual isolated station; the strategy and alert routes are hand-written fixtures; the page's Notification and AudioContext are recording test doubles (no sound device).
             Steps: open Settings > General with one alert in the history; announce alert.state with a second alert; tick Sound and announce a third; tick Browser notification (the double grants) and announce a fourth; make the page hidden and announce a fifth; reload; Clear.
             Expected: the editor offers no alert setting; Sound and Browser notification are unchecked by default and the history line reads "12:00:00 K1ABC CQ K1ABC FN42 · CQ · 40m FT8 · -12 dB · United States"; the second alert is listed first with no tone, no notification and no permission request; the third plays one tone and no notification; the permission is asked exactly once, on the click; the fourth plays one tone and shows one notification "Alert JA1XYZ" with body "CQ JA1XYZ PM95 · CQ"; the hidden page's fifth plays no tone and shows one notification; after the reload both checkboxes stay as chosen and nothing is announced; Clear sends exactly {v, profile_id, boot_id} to POST /strategy/alerts/clear and the list is empty; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-04';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_042_04_verified_by_TC_042_007 from 'CL-042-04' to 'TC-042-007';
    verification 'TC-039-001' {
        doc /* TC-039-001 — Strategy configuration is exact
             CL-039-01
             Setup: hand-written configuration JSON with a schema 4 strategy, the parser only.
             Steps: parse the valid configuration and serialize it; parse variants each with one refused value: an extra key of the configuration (highlight), two strategy names equal ignoring case, 17 strategies. The refusals of the strategy's own fields are TC-097-001's.
             Expected: the valid one round-trips to the same JSON; each refusal names exactly its field path (configuration, strategies[1].name, strategies).
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-01';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_01_verified_by_TC_039_001 from 'CL-039-01' to 'TC-039-001';
    verification 'TC-039-002' {
        doc /* TC-039-002 — Continent, directed-CQ tables and verdicts
             CL-039-02, CL-039-03
             Setup: hand-authored codec-packed rows for HB9BLA JN47AA (continent EU) on 40m: CQ K1ABC FN42 -12, CQ DL1XYZ JO62 -3, CQ NA W1AW FN31 -5, CQ EU G4ABC IO91 -8, CQ DX OH1AA KP20 -1, CQ DX JA1XYZ PM95 -15, W1AW K1ABC RR73 -6, HB9BLA VK2ABC QF56 -20, CQ TEST N1MM FN31 -2; continents from the cty.dat entities of the senders.
             Steps: continent (cty.dat entity) of HB9BLA K1ABC OH1AA JA1XYZ VK2ABC PY1AA ZS6AA CE9AA UA9ABC Q1ABC K1ABC/MM; DirectedCqRule for plain/EU/NA/DX/JA/TEST/POTA with known and unknown continents, an EU profile and a non-EU (K1ABC, NA) profile; MyContinent from a configured value, a callsign, and a locator with a call without entity; a new_call strategy with and without Treat 73 as CQ; my continent unknown; the reasons; an operator's selection of a CQ that is not answerable.
             Expected (hand table, continent column of the cited cty.dat lines): EU NA EU AS OC SA AF SA AS, none, none; for K1ABC: CQ NA and CQ DX from JA answerable, CQ EU and CQ DX from NA not; a call without entity: JN37 EU, FN42 NA, PM95 AS, QF56 OC, GG87 SA; none without call and locator; verdict order: VK2ABC (caller), then the candidates strongest first, rows 2, 4 and 8 greyed; with Treat 73 as CQ the RR73 of K1ABC has a rank and a call to me is never cq-like; unknown continent greys rows 2,3,4,5,8; reasons "calls my call", "needed: new_call", "CQ NA — not for EU"; the callsign guard refuses K1, ABCDE and W1AW/R; the selection warning as written in the test.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-02';
            verify 'CL-039-03';
        }
        attribute executable : String = "server/src/strategy_tests.rs; tests/contact.test.cjs";
    }
    dependency CL_039_02_verified_by_TC_039_002 from 'CL-039-02' to 'TC-039-002';
    dependency CL_039_03_verified_by_TC_039_002 from 'CL-039-03' to 'TC-039-002';
    verification 'TC-039-003' {
        doc /* TC-039-003 — Strategy store, routes and evaluation
             CL-039-01, CL-039-02, CL-039-03
             Setup: actual station router on a disposable selected HTTPS profile (HB9BLA, JN47AA) with one grant, the browser cookie and Origin; injected FT8 live job with rows CQ K1ABC FN42, CQ NA W1AW FN31, HB9BLA G4ABC IO91, CQ DL1XYZ JO62.
             Steps: GET /strategy; PUT a configuration; read strategy.json; open a new owner; PUT with a stale revision, another profile, another boot, v 2, an extra key, a foreign Origin; GET without credentials; PUT continent AS; evaluate the saved strategy, a draft with explain, another job id, a 2049-record range; an old schema 1 strategy.json; a strategy.state event after a change.
             Expected: default {null,null,[]} revision 0 with my_continent EU; revision 1 and the file {schema_version 3, profile_id, revision 1, configuration with active null}; the new owner reads it with active None; 409 stale_revision, 403 wrong_profile, 409 state_conflict boot_id, 400 unsupported_version, 400 invalid_request, 403, 401; my_continent AS; verdicts {caller 2 rank 0, candidates 3 and 0 by SNR, 1 grey} in display order; the draft lists all four with reasons; 409 stale_request; 400 next_sequence; the old file reads with strategies dropped, active None, continent and ignore lists kept; no PTT exchange.
             2 — Isolated automated functional tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-01';
            verify 'CL-039-02';
            verify 'CL-039-03';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_01_verified_by_TC_039_003 from 'CL-039-01' to 'TC-039-003';
    dependency CL_039_02_verified_by_TC_039_003 from 'CL-039-02' to 'TC-039-003';
    dependency CL_039_03_verified_by_TC_039_003 from 'CL-039-03' to 'TC-039-003';
    verification 'TC-039-004' {
        doc /* TC-039-004 — Strategy runs
             CL-039-03, CL-039-05
             Setup: as TC-039-003 with the contact engine and #9 transmit owner on the recording hardware double (virtual UTC set 1 s after an even FT8 period E; own periods odd); the strategy selected from the browser path (cookie grant) with "Test calls" (class strategy: new [call] per ever, Treat 73 as CQ, order [snr], leave {calls 2, calls_heard 4}, retry_minutes 1, Calling stations are answered on) and Auto switched on from the browser (POST /strategy/auto).
             Steps: (a) PUT with active and Auto on: the run starts, no CQ; publish CQ NA W1AW (strongest), CQ JA JA1XYZ, CQ 290 N1MM, CQ DL1XYZ, CQ K1ABC; two empty partner periods; CQ K1ABC and W1AW DL1XYZ RR73 at 1700 Hz; CQ K1ABC alone afterwards, before and after its quiet minute; PUT None; PUT active again and Auto on; HALT; Esc. (b) A QSO to its end, then the next station, repeatedly past the former limits; the deadline seam moved past 480 minutes. (c) A caller against a candidate; a browser select_row and enable_tx during the run's contact and while it waits; the partner's RR73; a new CQ; a run contact cancelled by the browser followed by the same station's CQ and its call to me; a browser selection racing the run's select_row and enable_tx; stop and Halt while manual. (d) Selecting with no receive; receive starts; the live identity changes during a contact; Auto on without a grant transport; an MCP configure with strategy true; an MCP stop then start; a station restart. (e) A station completed on 40m, as a caller on 40m and as a CQ and a caller on 20m; a retune with a station in its quiet time and with a station the operator gave up. (f) A new proof of the grant during a contact; past the transport's 8 h; the grant revoked.
             Expected: (a) no CQ is ever armed; DL1XYZ or K1ABC selected by value (W1AW, JA1XYZ and N1MM never); after two unanswered periods disarmed, waiting, left {DL1XYZ or K1ABC, repetitions}, no stop reason; the next publication goes to the other station with Rx and Tx on its slot; the left station is not called while in its quiet time, also alone, and is called again after it; None stops the run, disarms and turns Auto off; HALT stops halted, turns Auto off with a new revision and keeps active; Esc leaves active, Auto and the run. (b) The run stays waiting after each completion, no limit_reached, no time_limit. (c) the caller first (it passes the filters, TC-097-007); a double-click during the run: the run is manual, the strategy stays active, the run neither disarms nor cancels; the manual QSO completed: the run waits and answers the next match; the operator's cancel of the run's contact: that station is not selected again, also not as a caller; the race leaves the operator's contact and the state manual, no stop; Halt while manual stops halted. (d) waiting with reason no_receive and no contact; waiting without a reason after receive starts and it answers; the contact disarmed and cancelled at once and the run waiting on the new identity; strategy_refusal transmit_unavailable, Auto off, the strategy still selected; operator_required strategy, also for the start, nothing armed, an MCP policy of its own starts as ever; active None and Auto off after the restart. (e) not answered again on 40m, called and answered on 20m; the station in its quiet time on 40m is called on 20m, the given-up one is not. (f) the run and its contact go on through the proof and the deadline; the revocation stops authority_lost, disarms and turns Auto off. No PTT exchange.
             #39 holdtx: these steps run with Hold Tx explicitly off (they test the run logic; Rx = Tx on the slot); with Hold Tx on a selection keeps Tx and puts Rx on the station: TC-039-049.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-03';
            verify 'CL-039-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_03_verified_by_TC_039_004 from 'CL-039-03' to 'TC-039-004';
    dependency CL_039_05_verified_by_TC_039_004 from 'CL-039-05' to 'TC-039-004';
    verification 'TC-039-006' {
        doc /* TC-039-006 — Strategy selector, value marks, editor popup and Most Wanted in the browser
             CL-039-01, CL-039-04, CL-039-05, CL-039-10
             Setup: actual isolated server and Chromium at 1366x768 (and 360x740 for the popup); routed fixtures: an FT8 live job with CQ K1ABC FN42, CQ NA W1AW FN31, CQ DL1XYZ JO62, a strategy view (revision 4, "DX first", none active), station verdicts [2 rank 0, 0 rank 1, 1 grey] (with reasons when explain), the automation owner. A second case uses the real station store.
             Steps: wait; select "DX first"; click the Freq column; click Value; open the editor; read the preview; resize to 360 px; change a goal; Save; Close; announce automation.state with a waiting run; strategy.state with active null (a HALT); select None. Second case: choose continent AS in Settings > General; the Most Wanted section: a failed Update Most Wanted (routed, no network), a successful one. Third case: a new row published while an evaluation is held.
             Expected: no evaluation request and no mark while none is active; selecting sends one PUT {expected_revision 4, active "DX first"} and asks nothing; no POST /automation/command and no enable_tx from the browser; one evaluation {the live identity, 0..3, strategy null, explain false}, none on a timer; rows DL1XYZ, K1ABC marked in that order, W1AW greyed; a column click sorts by the column with the marks kept, Value returns to the station's order; the editor holds exactly the settings of Strategy; the popup HALT has the top-bar state; preview rows with their reasons from a draft evaluation with explain; no horizontal overflow at 360 px; an edit re-runs the preview; Save sends exactly the edited strategy and does not select; the run state reads "Strategy DX first waiting" after the event, GET /automation only on the event; strategy.state re-reads GET /strategy and the selector shows None. Second case: PUT saved continent AS (my_continent AS) and no browser storage key; the button reads Update Most Wanted and the status "No list; strategies call the strongest first"; no upload control; the failure shows its reason in one line and the status stays; after a success the status reads "List from <date> · 2 entries · 1 not mapped to an entity". Third case: a second evaluation with the larger next_sequence when the first ends and the new row marked.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-01';
            verify 'CL-039-04';
            verify 'CL-039-05';
            verify 'CL-039-10';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_039_01_verified_by_TC_039_006 from 'CL-039-01' to 'TC-039-006';
    dependency CL_039_05_verified_by_TC_039_006 from 'CL-039-05' to 'TC-039-006';
    dependency CL_039_10_verified_by_TC_039_006 from 'CL-039-10' to 'TC-039-006';
    verification 'TC-039-007' {
        doc /* TC-039-007 — Live strategy on HB9BLA
             CL-039-03, CL-039-04, CL-039-05, CL-039-06
             Setup: the gated candidate installed on HB9BLA, IC-7300 on COM3 on 40 m FT8, RF power set by the test to at least 30 W before the first Tx (CI-V 14 0A, starting at 0090, with the station stopped and idle, because it holds COM3; read back; the first Tx must read Po at least 30 %; if below, raise the value and repeat; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported), operator consent; Tx watchdog 6 repetitions (the profile default).
             Steps: duplicate a built-in to a strategy of class strategy (new [call] per ever, region dx, Treat 73 as CQ); select it with Auto off for two periods; switch Auto on; let it work two stations; HALT; switch Auto on again; Esc during a QSO; select None; in Settings > General click Update Most Wanted once.
             Expected: the stations it would call are marked and on top by value, CQ NA/AS and same-continent CQ DX greyed; nothing is transmitted with Auto off; no CQ is transmitted; it answers callers first, then the best candidate, to a logged QSO, and goes on; HALT stops at once, Auto turns grey and the selector keeps the strategy; Esc aborts the QSO, gives the station up and the strategy goes on; None stops it and Auto turns grey; a station restart leaves None and Auto off; Update Most Wanted fetches the list once and the status shows its date, its entries and how many are not mapped.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-039-03';
            verify 'CL-039-04';
            verify 'CL-039-05';
            verify 'CL-039-06';
        }
    }
    dependency CL_039_03_verified_by_TC_039_007 from 'CL-039-03' to 'TC-039-007';
    dependency CL_039_05_verified_by_TC_039_007 from 'CL-039-05' to 'TC-039-007';
    requirement 'CL-055-02' {
        doc /* Each decoded record of a resolved sender carries its entity (shown name, continent, CQ and ITU zone, entity distance) and the WSJT-X new-* flags that hold against the internal log (new call, grid, DXCC, continent, CQ zone and ITU zone, each ever and on this band), only the true ones, for the #50 row colours. Band Activity's DXCC column shows the shown name; Distance uses the message grid and otherwise the entity distance marked approximate; the QSO pane header shows the partner's country and continent. The strategy's continent condition and the directed-CQ rule use the sender's entity (WstxStrategy::ContinentOfCall). Details: WstxContact::DecodedEntity; WstxOperatingLayout BandActivity. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/dxcc.rs; server/src/receive_http.rs; server/src/strategy.rs; server/src/decoder/payload.rs; client/recording.js; client/contact.js";
    }
    dependency CL_055_02_to_FR_010 from 'CL-055-02' to 'FR-010';
    dependency CL_055_02_to_FR_019 from 'CL-055-02' to 'FR-019';
    requirement 'CL-055-03' {
        doc /* Settings > General shows the cty.dat in use (its date, bundled or uploaded, entity count) and replaces it by a file upload that the station validates first, or returns to the bundled file; there is no automatic download. A refused upload changes nothing; an unreadable stored upload leaves the bundled file in use and is reported. Details: WstxContact::CountryFile, CountryFileHttp. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/logbook.rs; server/src/logbook_http.rs; server/src/main.rs; client/logbook.js";
    }
    dependency CL_055_03_to_FR_016 from 'CL-055-03' to 'FR-016';
    verification 'TC-055-002' {
        doc /* TC-055-002 — Decoded records carry entity and new-* flags
             CL-055-02
             Setup: actual router with a selected profile (HB9BLA JN47AA) whose log holds DL1ABC JO62 20m FT8, K1ABC FN42 40m FT8 and W1AW FN31 20m FT4; a live FT8 job with CQ K1ABC FN42, CQ DL2XYZ JO62, CQ JA1XYZ PM95, HB9BLA G4ABC IO91, a free text and CQ W1AW FN31; a hand log for the worked categories.
             Steps: read /receive/results without a band, then with the selection band 20m; log DL2XYZ on 20m and read again; worked categories from the hand log.
             Expected: K1ABC dxcc {U.S.A., NA, 5, 8, 7706 km} without flags (no band), then only new_call_band and new_grid_band (the US is worked on 20m); W1AW worked on 20m in FT4 has no flag (band, not mode); DL2XYZ Germany 465 km with only new_call and new_call_band, none after it is logged; JA1XYZ all twelve flags; G4ABC new call, grid, DXCC and ITU zone (EU and CQ 14 worked); free text unchanged; calls compare case-insensitively, grids by square; Sicily counts as its own name. Every decoded sender call resolves (#55, live 2026-11-06): CQ HF6FIRAC Poland with new-* flags and no grid flag, a filled-in hash such as OH2DKQ <CT9/DL7VXX> -02 its entity, a nonstandard full call and a filled-in second hash likewise, a DXpedition hashed call the entity only; R330S <...> 73, OH2DKQ <...> -02 and the free text CQ SA7BKX JO6 no entity.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-055-02';
        }
        attribute executable : String = "server/src/dxcc_tests.rs";
    }
    dependency CL_055_02_verified_by_TC_055_002 from 'CL-055-02' to 'TC-055-002';
    verification 'TC-055-003' {
        doc /* TC-055-003 — Country file upload
             CL-055-03
             Setup: actual isolated router and profile directory; Chromium at 1366x768 on the isolated server.
             Steps: GET /dxcc; GET /dxcc?call= with DL/HB9BLA, K1ABC/MM and refused queries (empty, encoded slash, other key, 14 characters); PUT a one-entity file; PUT a file with an invalid continent, an empty file, a number and a file over 1 MiB; stale boot; wrong Origin; restart; PUT null; store an unreadable file and restart; revoked HTTPS grant; environment-only mode. In the browser: open Settings > General, upload an invalid then a valid file, then Use bundled file.
             Expected: bundled VER20250115 346; the upload is the file on disk and resolves HB9BLA to it and survives the restart; refusals 400 invalid_cty line 1 / invalid_request text, 409, 403 without change; null removes the file; an unreadable file stays and is reported with the bundled table; 401 and 404. The page shows "cty.dat 2025-01-15 · bundled with this station · 346 entities", the refusal with its line, "cty.dat 2099-12-31 · uploaded · 1 entities", then bundled again.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-055-03';
        }
        attribute executable : String = "server/src/logbook_http_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_055_03_verified_by_TC_055_003 from 'CL-055-03' to 'TC-055-003';
    verification 'TC-055-004' {
        doc /* TC-055-004 — DXCC column, approximate distance and QSO header in the browser
             CL-055-02
             Setup: actual candidate router with the contact engine (HB9BLA JN47AA); hand-authored rows published through the test control peer, including HB9BLA W1XYZ -10 without a grid; later the live K1WY rows KW8CW K1WY RR73 (exchange packed as the grid square RR73, 32373), CQ K1WY FN31 and SP6E K1WY +00 in one period and reversed in the next.
             Steps: wait for the rows; select CQ K1ABC FN42; publish the K1WY periods.
             Expected: W1XYZ row DXCC U.S.A. with title "U.S.A. · NA · CQ zone 5 · ITU zone 8 (cty.dat)" and distance "~7706 km"; DL1ABC Germany; K1ABC's distance from its grid without "~"; the QSO header "K1ABC · FN42" with its detail line starting "U.S.A. (NA) · <n> km · sent" (the exact distance, no "~"). In both K1WY orders: the RR73 and +00 rows "~7706 km", the CQ row "6188 km"; the unpacked RR73 square is the roger RR73 with unchanged text.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-055-02';
        }
        attribute executable : String = "tests/contact.test.cjs; server/tests/decoder_vectors.rs";
    }
    dependency CL_055_02_verified_by_TC_055_004 from 'CL-055-02' to 'TC-055-004';
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
    dependency CL_055_02_verified_by_TC_055_006 from 'CL-055-02' to 'TC-055-006';
    verification 'TC-055-005' {
        doc /* TC-055-005 — Live DXCC on HB9BLA
             CL-055-02, CL-055-03
             Setup: the gated candidate installed on HB9BLA, receive only (no transmission), the operator's contacts.adi.
             Steps: watch Band Activity for several periods on a busy band; compare rows against the log; open Settings > General.
             Expected: the DXCC column is filled for decoded calls; new-DXCC flags only for entities absent from the log and on-band flags only for entities not worked on this band; the country file date is shown.
             3 — Live, read-only on the station; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-055-02';
            verify 'CL-055-03';
        }
    }
    dependency CL_055_02_verified_by_TC_055_005 from 'CL-055-02' to 'TC-055-005';
    dependency CL_055_03_verified_by_TC_055_005 from 'CL-055-03' to 'TC-055-005';
    requirement 'CL-054-01' {
        doc /* A Detailed waterfall subscriber receives every Detailed row of the current job in order after a processing stall: the station retains the last 25 rows and sends each peer the oldest row it has not sent, 200 ms apart, 170 ms apart while rows wait (WstxStationProtocol::TransferDisplay). Live Thin sends keep a fixed 2 s grid from the previous deadline, restarted at a send more than 1 s late, so sends stay at least 1 s apart. The browser draws a gap row only for a real gap; one or two live Thin rows paced out between two sent rows are drawn with the next row. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/recording.rs; server/src/main.rs; client/recording.js";
    }
    dependency CL_054_01_to_FR_019 from 'CL-054-01' to 'FR-019';
    dependency CL_054_01_to_FR_021 from 'CL-054-01' to 'FR-021';
    // #50/#10 operator feedback 2026-11-02 evening (US5WFL/YO3GNF, TC2TR, the 22:48 CQ run on 40 m).
    requirement 'CL-050-04' {
        doc /* Replacing an active contact (ChangeContact, select_row or enter_dx with replace true) keeps Enable Tx as it is: with Enable Tx on, the next period of the new contact's parity carries the new contact's next message, and after a transmission already on the air nothing more goes to the old partner. A double-click (or Reply) on another station's Band Activity row, idle, after a completed contact, during a contact or during my CQ, also when the rows are redrawn between its two clicks or during its second press, is that selection without a confirmation, followed by Enable Tx on (WSJT-X double-click with "Double-click on call sets Tx enable"), each request retried at most twice after a stale_revision refusal; Auto Seq then runs the QSO to its completion and log. During a station automation run an operator replacement of the run's contact ends the run, which disarms (WstxMcp, TC-020-003). A single click only offers "Change contact to <call>" during a contact and never turns Enable Tx on. Details: WstxContact::ChangeContact, SelectDecodedRow, WstxOperatingLayout::BandActivity. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; client/contact.js";
    }
    dependency CL_050_04_to_FR_007 from 'CL-050-04' to 'FR-007';
    dependency CL_050_04_to_FR_008 from 'CL-050-04' to 'FR-008';
    requirement 'CL-010-17' {
        doc /* (#10) Call 1st (WSJT-X "CQ: First"), an operator setting next to Auto Seq, on at a profile's first start, then as saved (CL-110-01): while my own CQ runs with Enable Tx and Auto Seq on, the first decoded message to my call of a step, in decode order, whose exchange is a grid or a report is answered at once as a selection of that row with Enable Tx kept, so the next own period answers that caller. Off, a CQ moves only on an operator selection. Details: WstxContact::CallFirst. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; client/contact.js";
    }
    dependency CL_010_17_to_FR_007 from 'CL-010-17' to 'FR-007';
    verification 'TC-050-004' {
        doc /* TC-050-004 — A double-click switches to another station with Enable Tx kept
             CL-050-04
             Setup: the contact engine against the actual #9 transmit owner core on a virtual clock (contact_tests); the actual candidate Router, contact engine and #9 transmit owner on a recording hardware double with Chromium on the real clock (contact_http_tests::contact_browser_operating_flow, tests/contact.test.cjs).
             Steps: (a) engine: select "CQ K1ABC FN42", Enable Tx, send Tx1 in the odd period, then select "CQ DL1ABC JO62" (even period) with replace true and run two periods; then enter_dx W1AW with replace true; again switching 100 ms after my period start (PTT keyed, audio not started), also to "CQ DL1ABC JO62" decoded in an odd period; (b) browser: double-click "CQ K1ABC FN42"; after its Tx1 double-click "CQ DL1ABC JO62"; publish DL1ABC's report and RR73; then CQ right after that completed contact (armed, calling); on a second station and browser run at the same time: CQ and, while calling, double-click "CQ EA8BIA IL18" and run that QSO the same way; (c) browser, after the completed EA8BIA contact (disarmed, contact_completed): double-click "CQ G8KHF IO92" with the Band Activity rows redrawn during the second press (#50, operator 2026-11-03).
             Expected: (a) still armed, last_disarm_cause unchanged, the next odd period sends "DL1ABC HB9BLA JN47", no later period sends to K1ABC, the manual replacement keeps Enable Tx; the switch in the keyed window sends the new contact's Tx1 in that same period, still armed; a switch in the keyed window to "CQ DL1ABC JO62" decoded in an odd period (my own parity) still sends K1ABC's Tx1 in that period and DL1ABC's Tx1 in the next even period, still armed, never refused busy (#10); (b) each double-click sends select_row with replace true then enable_tx and shows no "Change contact" button; still armed, last_disarm_cause not contact_cancelled; the next own period sends "DL1ABC HB9BLA JN47", then "DL1ABC HB9BLA R-03" and "DL1ABC HB9BLA 73"; the contact completes and contacts.adi holds exactly one record for it; the same for EA8BIA from the CQ ("R+00"); (c) select_row with replace true then enable_tx, armed, and the next own period sends "G8KHF HB9BLA JN47".
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-050-04';
        }
        attribute executable : String = "server/src/contact_tests.rs; tests/contact.test.cjs";
    }
    dependency CL_050_04_verified_by_TC_050_004 from 'CL-050-04' to 'TC-050-004';
    requirement 'CL-050-06' {
        doc /* (#37) The contact snapshot carries the QSO dialogue of the current contact, at most 16 entries: each partner message the engine counted (with SNR) and each of our transmissions of that contact as sent, with its period start and a repeat count; the QSO pane shows it while the QSO runs, oldest first and newest at the bottom, scrolling inside the card without growing the page, and drops it with the QSO. Details: WstxContact::ContactSnapshot dialogue, WstxOperatingLayout::QsoPane. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; client/contact.js; client/recording.css";
    }
    dependency CL_050_06_to_FR_007 from 'CL-050-06' to 'FR-007';
    dependency CL_050_06_to_FR_019 from 'CL-050-06' to 'FR-019';
    verification 'TC-050-006' {
        doc /* TC-050-006 — QSO dialogue in the contact snapshot and the pane (#37)
             CL-050-06
             Setup: the contact engine against the actual #9 transmit owner core on a virtual clock (contact_tests); the snapshot shape bound (contact_http_tests); the operating screen with a routed ContactSnapshot in Chromium.
             Steps: (a) engine: replay a QSO with K1ABC (select their CQ, Tx1 twice, their report, Tx3, their RR73, 73) and read the dialogue after each step; cancel a second contact; push 20 distinct entries; (b) the maximum snapshot shape with 16 maximal entries; (c) browser: a running QSO with a 10-entry dialogue at 1366x768 and 360 px, then the completed contact.
             Expected: (a) entries in order tx "K1ABC HB9BLA JN47" count 2, rx "HB9BLA K1ABC -05" with SNR, tx "K1ABC HB9BLA R-12", rx "HB9BLA K1ABC RR73", tx "K1ABC HB9BLA 73", periods the period starts; a new contact starts empty, cancel empties it, at most 16 entries (the oldest dropped); a received message repeated at SNR −12, −3 and null is one entry with count 3, its first period and SNR −3 (#60); (b) at most 4096 bytes; (c) rows of the #60 QSO table "HH:MM:SS | <recipient> ◂ <sender> | <exchange> | <Rep> | <Rx SNR> | <Tx SNR>" (my first sent "JN47" with Rep "×2" and no SNR yet, a received "-05" with Rx SNR "−5" and Tx SNR "−5", the last received "RR73" with Rep "×3", Rx SNR "+17" and the carried Tx SNR "−5") oldest first, the header row kept and the newest row visible, no page scroll, gone once completed.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-050-06';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_050_06_verified_by_TC_050_006 from 'CL-050-06' to 'TC-050-006';
    verification 'TC-010-010' {
        doc /* TC-010-010 — Call 1st answers the first caller of my CQ
             CL-010-17
             Setup: the contact engine against the actual #9 transmit owner core on a virtual clock (contact_tests); hand-authored rows of the 2026-11-02 22:48 CQ run; the snapshot wire (contact_http_tests) on a fresh profile directory.
             Steps: Enable Tx with no partner (calling, odd parity), Hold Tx on; after my CQ deliver in one even period, decode order "HB9BLA EA4HTI IM69" (1678 Hz, -8) then "HB9BLA F1PBZ -13" (2144 Hz, -10), in reverse slice order; later "HB9BLA EA8BIA -11" and "HB9BLA SV1DZB KM18"; repeat with Call 1st off, with Auto Seq off, and with only "HB9BLA DL1ABC RR73", "HB9BLA DL2ABC 73", "HB9BLA DL3ABC RRR", "HB9BLA DL4ABC R-10".
             Also: the same callers after Enable Tx off (disarmed, still calling).
             Expected: Call 1st on: the contact is EA4HTI (grid IM69) in report with next Tx2 "EA4HTI HB9BLA -08" at once, still armed, Tx offset 1500 Hz kept, the next odd period sends it; the later callers change nothing; Call 1st off, Auto Seq off, Enable Tx off or only continuing exchanges: still calling (with Enable Tx off nothing is sent) and the next odd period sends "CQ HB9BLA JN47"; on a profile with nothing saved the snapshot settings carry call_first true.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-17';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs";
    }
    dependency CL_010_17_verified_by_TC_010_010 from 'CL-010-17' to 'TC-010-010';
    verification 'TC-110-004' {
        doc /* TC-110-004 — The restored values govern the station
             CL-110-01, CL-010-17, CL-010-02
             Setup: the contact engine against the actual transmit owner core on a virtual UTC clock (contact_tests), profile HB9BLA JN47, the engine as a station start creates it on a profile directory holding a hand-written qso-settings.json; hand-authored rows. For the strategy step the station with a strategy run (strategy_tests).
             Steps: (a) saved call_first false; Enable Tx with no partner (own CQ); "HB9BLA EA4HTI IM69" in the partner's period. (b) saved call_first true, the same row. (c) saved auto_seq false; a contact with K1ABC in replying, Enable Tx on; "HB9BLA K1ABC -05". (d) saved both true, and saved both false: 3 own periods without a start action. Also: saved auto_seq false; a strategy switched to Auto.
             Expected (WstxContact::CallFirst, AutoSequence, CL-009-04): (a) still calling, the next own period sends "CQ HB9BLA JN47". (b) EA4HTI in report with Tx2 next, as TC-010-010. (c) state and next slot unchanged, suggested_slot tx3. (d) directly after the start the transmit state is off with cause startup, no contact exists, and no TransmitRequest appears in the 3 own periods (guard of CL-009-04). Also: the run is waiting with reason auto_seq (guard of the automation readiness).
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-110-01';
            verify 'CL-010-17';
            verify 'CL-010-02';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_010_17_verified_by_TC_110_004 from 'CL-010-17' to 'TC-110-004';
    dependency CL_010_02_verified_by_TC_110_004 from 'CL-010-02' to 'TC-110-004';
    requirement 'CL-111-04' {
        doc /* Display. On a station with transmit capability the operating view shows the transmit state and the cause of its last change at all times, in every region, at 360 px and at 1366x768. It follows only the pushed station state and takes no pointer or keyboard input. Texts. On: "Tx on"; "Tx on · Auto". Off: "Tx off" (startup); "· QSO complete"; "· QSO cancelled"; "· halted"; "· Tx watchdog: same message sent N times"; "· radio lost"; "· radio settings changed"; "· Tx refused · <reason>"; "· <call> works another station"; "· mode changed"; "· band changed"; "· automation ended". Not delivered yet: the display. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    dependency CL_111_04_to_FR_019 from 'CL-111-04' to 'FR-019';
    requirement 'CL-111-07' {
        doc /* A start that cannot transmit. When a reply or call_dx is admitted but transmission is not possible (no transmit capability, radio or authorization not ready, clock not synchronized, Tune on), the command is accepted, the QSO is prepared, the transmit state stays off with its cause unchanged, and the transmit view's refusal names the reason (busy while Tune is on). The operating view shows that reason beside the state. Nothing starts by itself when the reason goes away. call_cq, send_next and reset_repetitions in the same situation are refused with that reason and change nothing. Not delivered yet: the operating view does not show the reason beside the state. Details: WstxContact::StartActions. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/contact.rs; server/src/transmit/service.rs";
    }
    dependency CL_111_07_to_FR_007 from 'CL-111-07' to 'FR-007';
    dependency CL_111_07_to_FR_008 from 'CL-111-07' to 'FR-008';
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
    verification 'TC-111-008' {
        doc /* TC-111-008 — Runs and MCP
             CL-111-02, CL-039-06
             Setup: the station with a strategy run and a contest run (strategy_tests) and with an MCP client (mcp_tests).
             Steps: each run starts; an MCP reply before any browser action, after a repetition-limit stop, and after an operator start.
             Expected (CL-039-06): a run starts by one reply or call_cq, cause auto; the MCP reply is tx_watchdog with nothing prepared in the first two, accepted in the third.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-111-02';
            verify 'CL-039-06';
        }
    }
    verification 'TC-111-011' {
        doc /* TC-111-011 — A start that cannot transmit
             CL-111-07
             Setup: as TC-111-001; for the view Chromium against the candidate server.
             Steps: reply and call_dx with no capability, radio unavailable and clock not synchronized; the reason removed, 3 periods; a new reply. call_cq and send_next in the same situations. With the transmit owner refusing to arm (a PTT release that failed, an owner fault): call_cq from idle and on an own CQ that is off, send_next on a kept QSO; with the failed PTT release, reset_repetitions after a repetition-limit stop. reset_repetitions while the state is on, with Tune on and with the PTT switch indeterminate.
             Expected (CL-111-07): accepted, QSO prepared, state off, cause unchanged, refusal names the reason, the view shows it. Nothing sent in the 3 periods; the new reply transmits. call_cq and send_next: refused, nothing changed. With the owner refusing: transmit_unavailable, nothing changed, no contact prepared, nothing sent. An owner fault itself stops with cause failed, so after it Reset is state_conflict by the outcome table. Reset while on: busy with Tune on, transmit_unavailable with the PTT switch indeterminate; the count stays.
             Not automated yet: the view shows the reason.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-111-07';
        }
        attribute executable : String = "server/src/transmit_state_tests.rs";
    }
    dependency CL_111_07_verified_by_TC_111_011 from 'CL-111-07' to 'TC-111-011';
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
    // #65 Free Tx slots (operator 2026-11-08, three grill-me rounds).
    requirement 'CL-065-01' {
        doc /* (#65, replaced by #82, operator 2026-11-09: "open slots are shown all the time as a part of the waterfall"; "we want to signal the other station a free frequency on our side when he will be transmitting"; "we just want to mark open slots, nothing else on screen. auto mode could use a quality ranking for its decision which of them to select") Open Tx slots: the station builds, with or without an automation run, a QSO or Auto, the open slots of my Rx parity, the periods the other station transmits in: in a QSO (Enable Tx on, my own CQ included, or a contact in progress; by a run or by hand) the contact's Rx parity; otherwise, while only listening, the parity of the period in progress, the Rx parity for transmitting in the next period, so it alternates every period. Counted periods, floor and value are #66's (WstxStrategy::FreeTxSlot: the last 4 periods of that parity that are due, ended or in progress with their complete decodes published (#89),the largest rise above the WSJT-X passband floor clamped at 0 in whole dB), of the station's live job and operating mode, from the last station band change on. A Tx frequency of the 10 Hz candidate grid inside the Tx range (FT8 300..2650, FT4 300..2610) is open when its value is 0 and its signal (FT8 50 Hz, FT4 90 Hz wide) overlaps no station decoded in a counted period; no other filter, no fallback, no ranking, no limit. The open signals join into open ranges [lo_hz, hi_hz) (overlapping ones join, touching ones stay separate). It is built at each period start, again when the decodes of a counted period are published (operator 2026-11-09, "Rebuild on decodes": the build at a period start counts the period just ended before its decodes exist), also the complete publication of the period in progress of the judged parity (#89), and at once when a QSO starts or ends or the live job, mode or band changes. The value null (no live receive) or {at_utc_ms, mode, rx_parity, qso, periods (the counted number), open [[lo_hz, hi_hz], ...]} is the top-level free_tx_slots of GET /automation and the MCP automation view, and is pushed at each build as free_tx_slots.state to every Detailed and Thin peer (at most 1024 bytes; once as null when it becomes null; once to a peer that subscribes while a value exists; never to Off), also while automation is never used, within the Thin link envelope. Auto's choice and tx_slot are unchanged (its own ranking, not shown); #65's five best of each run decision, its run_id and "no list without a run" go. Details: WstxStrategy::FreeTxSlots (D18), WstxMcp::AutomationWire, WstxStationProtocol::PushedStationState. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/freeslot.rs; server/src/automation.rs; server/src/main.rs; server/src/contact_http.rs";
    }
    dependency CL_065_01_to_FR_020 from 'CL-065-01' to 'FR-020';
    dependency CL_065_01_to_FR_007 from 'CL-065-01' to 'FR-007';
    verification 'TC-065-001' {
        doc /* TC-065-001 — The five best non-overlapping candidates
             CL-065-01
             Setup: the list function with hand-authored power tables (dB per candidate, written in the test), FT8 and FT4.
             Steps: seven separate quiet places; three candidates only; no power; rises 0.4 against 0.0 and 0.6 against 0.0; equal rises either side of the current Tx; FT8 a candidate 40 Hz and one 50 Hz from a listed one, FT4 80 Hz and 90 Hz; a candidate within 50 Hz of the called station; one within 50 Hz of my Rx with Hold Tx on and off; his frequencies of my Tx parity near some candidates, and everywhere; a rise of -1.4; listening with one parity higher.
             Expected (hand computation recorded in the test): 5 of seven in rank order; 3; empty; 0.4 ties and the current Tx is first, 0.6 does not; the nearer first, at equal distance the lower; 40 Hz skipped and 50 Hz listed, 80 Hz skipped and 90 Hz listed; the called station's neighbour never listed; my Rx's neighbour not listed with Hold Tx on, listed with it off; candidates near his frequencies excluded, his frequencies everywhere leave all; -1.4 listed as -1; level_db the larger parity's; the first listed equals quietest_clear's chosen hz for every table. Red on the parent: no list.
             #66: the tables give the largest rise above the passband floor, and the compared value is that rise clamped at 0: the rise of -1.4 is listed with rise_db 0 (not -1), tying with a rise of 0.0 by the tie rule, and its level_db and floor_db stay as measured; "listening with one parity higher" becomes my Tx parity higher, which changes nothing (only my Rx parity is judged), and level_db and floor_db are those of the busiest Rx period; a candidate overlapping a decoded station is not listed while a free one exists (TC-066-002).
             #82: the five-best list is gone (WstxStrategy D18); this case is replaced by TC-082-001 (the open ranges), and its test is rewritten to it. The choice parts ("the first listed equals quietest_clear's chosen hz") go with the list; the choice stays covered by TC-039-050 and TC-066-002.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/freeslot_tests.rs";
    }
    dependency CL_065_01_verified_by_TC_065_001 from 'CL-065-01' to 'TC-065-001';
    verification 'TC-065-002' {
        doc /* TC-065-002 — free_tx_slots in the snapshot and on the socket
             CL-065-01
             Setup: the actual station router with hand-authored detailed waterfall rows (as TC-039-050); a strategy run and a CQ run, Hold Tx off and on; socket peers subscribed Detailed, Thin and Off; GET /automation and the MCP automation view.
             Steps: read before any run; a selection with Hold Tx off; the same with only my Rx-parity periods counted since the band change; a CQ decision; a selection with Hold Tx on; a second decision with the same list; the run ends; a fourth peer subscribes Thin while a value exists; a separate session with no run at all.
             Expected: null before any run; the value with exactly {run_id, at_utc_ms, mode, rx_parity, listening, periods, slots}, the run's id, at_utc_ms the station clock of the decision, the hand-computed slots and period counts; one free_tx_slots.state each to the Detailed and Thin peer, data.free_tx_slots equal to the GET value, none to Off, at most 1024 bytes also with 5 slots at their longest numbers; tx_slot exactly as on the parent; the MCP view carries the same value; with only Rx-parity periods the Tx-parity usual count is 0; the CQ listening true with both now counts; Hold Tx on the list filled and Tx unchanged; a new event with a later at_utc_ms; after the end null and no free_tx_slots.state; the fourth peer gets the value once; without a run zero free_tx_slots.state and zero automation.state. Red on the parent: no key, no event.
             #66: periods carries {now} only, the count for my Rx parity and null for my Tx parity, in every decision (also the CQ, listening true); slots carry {hz, rise_db, level_db, floor_db} with no usual_db; "with only Rx-parity periods the Tx-parity usual count is 0" becomes "the Tx parity null"; at most 1024 bytes with 5 slots at their longest numbers (floor_db -999 and the like); rise_db is never negative (clamped at 0), while level_db and floor_db stay as measured.
             #82: replaced by TC-082-003. The value has no run_id, listening or slots ({at_utc_ms, mode, rx_parity, qso, periods, open}); it exists without a run, and free_tx_slots.state is sent every period also without a run (zero automation.state stays). "Null before any run", "after the end null and no free_tx_slots.state" and "without a run zero free_tx_slots.state" go; its test is rewritten to TC-082-003.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_065_01_verified_by_TC_065_002 from 'CL-065-01' to 'TC-065-002';
    verification 'TC-065-004' {
        doc /* TC-065-004 — Live Free Tx slots on HB9BLA
             CL-065-01, CL-065-02
             Setup: the gated candidate installed on HB9BLA, IC-7300 on 40 m FT8 within the operator's standing transmit consent, PSK Reporter on, Hold Tx on, "Show free Tx slots" on in the operator's browser.
             Steps: Auto on with a strategy; let it select and call through at least one QSO and one slot check; at each decision look at the marks against the traces of my recent Rx periods; where a mark lies on a visible station read free_tx_slots from GET /automation and record it on the issue; place Tx by hand between marks with a click; HALT, Auto off.
             Expected (oracle: the operator's look): 5 marks at each decision, staying until the next; each mark a separate pale green bar visible at a glance, also two adjacent slots, with no text (#76); their places comparable with the waterfall at a glance; the recorded numbers name why that slot ranked as it did; the click sets Tx as before; no marks after the run ends.
             #82: replaced by TC-082-005 and TC-082-006 (marks all the time, no checkbox, no five, kept after the run ends).
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-065-01';
            verify 'CL-065-02';
        }
    }
    dependency CL_065_01_verified_by_TC_065_004 from 'CL-065-01' to 'TC-065-004';
    verification 'TC-066-001' {
        doc /* TC-066-001 — The 10:28:58 capture: free Tx slots off the busy 800-1330 Hz region
             CL-039-09, CL-065-01
             Setup: the slot decision and list functions with hand-authored per-period bin levels modelled on the HB9BLA capture of 2026-11-08 10:28:58 UTC (10 m FT8, D:/wstx-tmp/live-20261108c/slots-102901.json and its waterfall): a run's CQ decision (listening), my Tx parity odd and Rx parity even, Hold Tx on, Tx 1930, Rx 906. Counted even periods 10:27:30, 10:28:00, 10:28:30 and odd periods 10:28:15, 10:28:45, each a flat floor of 30 dB (32 dB in the latest period of each parity), every station the capture decoded in that period as its decode (audio frequency, period) and as a band [hz, hz + 50) 12 dB above 30 dB (live, occupied slots read 4-12 dB above clear ones, #66 comment 6720568259); RK3AW's band at 1198.5 Hz also in both odd periods, undecoded there (the capture's 1180 Hz slot: level 50 against usual 48, busy in the odd periods too).
             Steps: the decision with Hold Tx on (no choice, the list only); the same with Hold Tx off (the choice).
             Expected (hand computation recorded in the test): the even decodes leave the candidates 300..400, 720..800, 1010..1050, 1250..1310, 1450..1680, 1890..1960, 2120..2130 and 2240..2650 (810..1000 within 50 Hz of Rx 906 with Hold Tx on); each reads 0 (floor 30.65 or 32.65, rise -0.65 clamped at 0, #66 "At or under floor = free"); the list is 1930, 2120, 1680, 1630, 2240 (the current Tx kept as free, then the free slots by distance), each {rise_db 0, level_db 32, floor_db 33} (level and floor of the latest, busiest period as measured); no listed slot overlaps a station decoded in my even periods and none lies in 800-1330 Hz; the odd stations (DL5XU at 1976, A61DD at 765) do not count; periods {even {now 3}, odd {now null}}; Hold Tx off: the CQ's slot is 1930, tx_slot power_db 0, the first listed. Red on the parent: its list holds slots on RK3AW (rise 0 there against 1 on the free slots, the live failure's ranks 2 and 3).
             #82: the list parts become the open ranges of the same tables (TC-082-001's rule: value 0 and no even decode overlapped, no clearance of Rx or the called station), hand-computed in the test; no open range overlaps a station decoded in my even periods, and the odd stations close nothing. The choice parts (Hold Tx off: the CQ's slot 1930, tx_slot power_db 0) stand.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-09';
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_09_verified_by_TC_066_001 from 'CL-039-09' to 'TC-066-001';
    dependency CL_065_01_verified_by_TC_066_001 from 'CL-065-01' to 'TC-066-001';
    verification 'TC-066-002' {
        doc /* TC-066-002 — Decoded stations, my Rx parity only, recent periods
             CL-039-09, CL-065-01, CL-039-22
             Setup: the slot decision and list functions with hand-authored per-period bin levels and decodes (audio frequency and period), FT8 and FT4; the actual station router with the contact engine on the hardware double for (g) and (h), virtual UTC.
             Steps: (a) the 07:29 reproduction (HB9BLA 2026-11-08, 20 m): Tx 1550, my Rx parity even, a flat floor 30 in the two older and 32 in the two later of 4 counted periods of each parity; a station decoded at 659.5 Hz at 38 dB in all 4 even periods, stations at 659.7 and 691.8 Hz at 38 dB in all 4 odd periods. (b) A decode at 1000.0 Hz: FT8 candidates 950, 960, 1040, 1050; FT4 910, 920, 1080, 1090; a decode at 1000.4 Hz and the candidate 1050. (c) A decode overlapping every candidate. (d) A station decoded only in my Tx parity, 20 dB above the floor, on the otherwise quietest slot. (e) A CQ decision: a slot loud only in the CQ's Tx parity, quietest in my Rx parity; and the reverse. (f) Decodes from a period that does not count: the 5th older Rx period, one before a band change, one older than the last 4 Rx periods on the clock. (g) Hold Tx on, a selection of a station within 50 Hz of Tx whose nearest candidate 50 Hz clear overlaps a decoded station; the same with every candidate overlapped. (h) Hold Tx off, the CQ on 900 answered for a caller at 920, with a station decoded at 800 Hz. (i) His frequencies of my Tx parity together with decodes. (j) The list at each step.
             Expected (hand computation recorded in the test): (a) Tx stays 1550 (value 0, every free slot 0 with rise -0.65 clamped, the current Tx kept); 610..700 never chosen or listed; (b) FT8 960 and 1040 left out, 950 and 1050 kept; FT4 920 and 1080 left out, 910 and 1090 kept; 1050 left out at 1000.4; (c) all candidates back, ranked by value; (d) that slot chosen, neither left out nor raised; (e) the slot quietest in my Rx parity chosen in both; (f) those decodes leave nothing out; (g) Tx to the next nearest candidate clear of the station and of the decoded station; with all overlapped the nearest 50 Hz clear; (h) Tx and Rx to the nearest candidate 50 Hz clear of 920 that does not overlap 800 (not 820); (i) his end applies among the candidates left by the decoded stations, his_end no when it leaves none; (j) the first listed equals the choice, no listed slot overlaps a counted decode while a free one exists. Red on the parent: (a) moves Tx to 680 (rise 0 on the station, 1 on the free slots), as live; (b), (g) and (h) choose the overlapped candidates.
             Added after the live run of 2026-11-08 (#66): a strategy run with Hold Tx on calls in my Tx periods through the actual router and the actual live worker; the last 2 rows of each received Rx period complete while keyed. Expected: each received Rx period counts (periods.<rx>.now 1, 2, 3 at the selection and the two slot checks); only periods I transmitted in are not counted, by the period, not by the on-air state of single rows.
             #82: (j) becomes: the open ranges at each step contain no signal overlapping a counted decode, also in (c), where every candidate is overlapped and open is [] (no fallback for the marks, while the choice still uses all candidates). The choice parts stand.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-09';
            verify 'CL-065-01';
            verify 'CL-039-22';
        }
        attribute executable : String = "server/src/freeslot_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_039_09_verified_by_TC_066_002 from 'CL-039-09' to 'TC-066-002';
    dependency CL_065_01_verified_by_TC_066_002 from 'CL-065-01' to 'TC-066-002';
    dependency CL_039_22_verified_by_TC_066_002 from 'CL-039-22' to 'TC-066-002';
    verification 'TC-066-003' {
        doc /* TC-066-003 — Live quiet slots on HB9BLA
             CL-039-09, CL-065-01
             Setup: the gated candidate installed on HB9BLA, IC-7300 FT8 on a busy band (20 m or 10 m) within the operator's standing transmit consent, PSK Reporter on, Hold Tx on, "Show free Tx slots" on; decodes and free_tx_slots read from GET /automation and the decode list at each decision.
             Steps: Auto on with a strategy with CQ when idle; let it call CQ, answer or call through at least one QSO and one Tx move; switch Hold Tx off for one call; at each decision record free_tx_slots and the decodes of my last 4 Rx periods on the issue; HALT, Auto off.
             Baseline before #66 (HB9BLA 2026-11-08, #66 comment 6720568259): in 14 decisions 52 of 70 listed slots, and rank 1 in 7 of 14, had a decoded station within 50 Hz while 23-67 decode-free 10 Hz points existed each time; occupied slots read 48-52 dB, clear ones 36-44 dB.
             Expected (oracle: the decodes and the operator's look at the waterfall): no listed slot and no chosen slot overlaps a station decoded in my last 4 Rx periods while the list has a free one (0 of the listed slots where the baseline had 52 of 70); the marks lie in stretches the waterfall shows empty in my Rx periods and are not all at the passband edges; rise_db of a slot free of decodes 0, 1 or 2 (never negative); with Hold Tx on Tx moves only at a slot check or by the 50 Hz rule, never onto Rx.
             #82: there is no checkbox and no listed slot: the marks (open ranges, recorded from GET /automation free_tx_slots at each decision) overlap no station decoded in my last 4 Rx periods; rise_db is read from tx_slot.power_db of the chosen slot only.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-039-09';
            verify 'CL-065-01';
        }
    }
    dependency CL_039_09_verified_by_TC_066_003 from 'CL-039-09' to 'TC-066-003';
    dependency CL_065_01_verified_by_TC_066_003 from 'CL-065-01' to 'TC-066-003';
    // #82 open slots all the time (operator 2026-11-09, two grill-me rounds and the simplification).
    verification 'TC-082-001' {
        doc /* TC-082-001 — Open slots and open ranges
             CL-065-01
             Setup: the open-slot function and the range join with hand-authored per-period bin levels and decodes (audio frequency, period), FT8 and FT4, 4 counted periods of the judged parity unless a step names fewer; the join also fed open frequency sets directly.
             Steps: (a) FT8 a flat floor of 30 dB everywhere (floor 30.65, every rise -0.65) and an undecoded station band 12 dB above it over 1000..1050 Hz in all 4 periods. (b) FT8 the flat floor and a decode at 1000.0 Hz; FT4 the same. (c) The join: FT8 open sets {2110, 2160}, {2100, 2110, 2130}, {2650}, every 5th grid point {300, 350, ..., 2650}; FT4 {300}, {300, 390}. (d) Values: a slot window whose largest rise is 0.4 dB and one whose is 0.6 dB. (e) A station decoded and 20 dB above the floor only in periods of the other parity. (f) Decodes in periods that do not count: the 5th older period, one before a band change, one older than the last 4 of the parity on the clock. (g) Decodes overlapping every grid point. (h) No counted period. (i) A slot on the floor in 3 periods and 3 dB above it in one.
             Expected (hand computation recorded in the test; oracle: the open rule of CL-065-01 and FreeTxSlot's floor and value, the flat-floor floor F + 0.65 of TC-039-050): (a) 950 and 1050 open, 960..1040 closed: open [[300, 1000], [1050, 2700]]; (b) FT8 the same; FT4 920..1080 closed, 910 and 1090 open: [[300, 1000], [1090, 2700]]; (c) [[2110, 2160], [2160, 2210]] (touching, not joined); [[2100, 2180]]; [[2650, 2700]]; 48 ranges [[300, 350], ..., [2650, 2700]]; FT4 [[300, 390]]; [[300, 390], [390, 480]]; (d) 0.4 open (value 0), 0.6 closed (value 1); (e) nothing closed by it; (f) those decodes close nothing; (g) open [] (no fallback); (h) open [], periods 0; (i) closed (its busiest period counts). Red on the parent: no open-slot function (the five-best list).
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/freeslot_tests.rs";
    }
    dependency CL_065_01_verified_by_TC_082_001 from 'CL-065-01' to 'TC-082-001';
    verification 'TC-082-002' {
        doc /* TC-082-002 — The judged parity and when the value is built
             CL-065-01
             Setup: the actual station router with hand-authored detailed waterfall rows of both parities (as TC-039-050), the contact engine on the hardware double, virtual UTC, FT8 and FT4; no automation run unless a step names one.
             Steps: (a) Listening without a run: read GET /automation free_tx_slots right after 4 consecutive period starts (FT8 at :00, :15, :30, :45; FT4 7.5 s apart), with one slot loud only in the even periods and one loud only in the period in progress. (b) Enable Tx on for my own CQ with Tx even in the middle of a period, then 4 period starts, then Enable Tx off with no contact. (c) A manual contact with a caller decoded in the odd periods (Tx even) through two periods. (d) A strategy run waiting, then its CQ decision and its contact; the same tables as for the run's choice on the parent. (e) A station band change; the live job stopped; restarted. (f) In a QSO with Tx even, a station decoded at 1200 Hz only in the odd period just ended, below the level that closes a slot by its waterfall rise; the build at the next even period start, then the publication of that period's decodes.
             Expected (hand computation recorded in the test; oracle: CL-065-01's parity rule and the operator's round 1 Q3 and round 2 Q1 answers): (a) rx_parity even, odd, even, odd at :00, :15, :30, :45 (the parity of the period in progress), qso false, at_utc_ms the period start; the even-loud slot closed in the even builds, open in the odd ones; the slot loud only in the period in progress not closed at that period's start; periods the counted periods of that parity before the period in progress (at most 4). (b) At Enable Tx at once a build with qso true and rx_parity odd; rx_parity odd at every following start, open changing only at builds at even period starts (when an odd period has ended); at Enable Tx off at once a build with qso false and the parity of the period in progress. (c) qso true, rx_parity odd, the caller's slot closed. (d) The waiting run as (a); in its CQ and contact as (b); the run's choice and tx_slot equal the parent's for the same tables, and the value has no run_id. (e) After the band change only later periods count (the first build periods 0, open []); a stopped live job: null; restarted: a value from its first period. (f) The period-start build has the 1200 Hz slot open (its decodes not yet published); at the publication at once a build with the same qso and rx_parity, a later at_utc_ms, and the slot overlapping 1200 Hz closed. Red on the parent: no value without a run, no alternation.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_065_01_verified_by_TC_082_002 from 'CL-065-01' to 'TC-082-002';
    verification 'TC-082-003' {
        doc /* TC-082-003 — free_tx_slots on the socket and in the snapshot without a run
             CL-065-01
             Setup: the actual station router with hand-authored detailed rows, virtual UTC; socket peers subscribed Detailed, Thin and Off; the MCP automation view; automation never used (no configuration, no run).
             Steps: 60 s of FT8 listening; 30 s of FT4 listening; Enable Tx on and off in the middle of a period; a fourth peer subscribes Thin; the live receive stops; a value with 48 ranges at 4-digit numbers.
             Expected (oracle: CL-065-01 and WstxStationProtocol::PushedStationState): GET /automation free_tx_slots with exactly {at_utc_ms, mode, rx_parity, qso, periods, open}, equal to the MCP view's; each Detailed and Thin peer one free_tx_slots.state per build (FT8 4 in 60 s, FT4 4 in 30 s, plus one at each QSO start and end), data.free_tx_slots equal to the GET value of that build; none to Off; zero automation.state throughout; the fourth peer exactly one with the current value; after the receive stops one event with free_tx_slots null, GET null, no further event; at most 1024 bytes also for the 48-range value with two UUIDs and a 13-digit at_utc_ms; no run_id, slots, rise_db, level_db or floor_db anywhere in it. Red on the parent: no event and null without a run.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_065_01_verified_by_TC_082_003 from 'CL-065-01' to 'TC-082-003';
    verification 'TC-082-005' {
        doc /* TC-082-005 — Live open slots while listening on HB9BLA
             CL-065-01, CL-065-02
             Setup: the gated candidate installed on HB9BLA, IC-7300 on 40 m (or 10, 15 or 20 m) FT8, Monitor on, Auto off, no run and no transmission; the operator's browser.
             Steps: for 2 minutes read GET /automation free_tx_slots after each period start (8 builds) together with the decodes of those periods, and look at the marks against the waterfall; then FT4 for 1 minute.
             Expected (oracle: the recorded decodes and the operator's look): rx_parity alternates build by build, qso false; no open range overlaps a station decoded in the counted periods of its parity; the marks change every period with the parity and lie on stretches the waterfall shows empty in that parity's periods; no text, no checkbox; the same in FT4 every 7.5 s.
             3 — Live read-only on the station (receive only, no transmission); not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-065-01';
            verify 'CL-065-02';
        }
    }
    dependency CL_065_01_verified_by_TC_082_005 from 'CL-065-01' to 'TC-082-005';
    verification 'TC-082-006' {
        doc /* TC-082-006 — Live open slots in a QSO on HB9BLA
             CL-065-01, CL-065-02
             Setup: the gated candidate installed on HB9BLA, IC-7300 1 W on 40 m (or 10, 15 or 20 m) FT8 within the operator's standing transmit consent; the operator's browser.
             Steps: a manual QSO (own CQ or answering a CQ) to its end; then Auto on with a strategy through one QSO; HALT not needed, Auto off. At each period start read GET /automation free_tx_slots and the run's tx_slot, and record them with the decodes on the issue.
             Expected (oracle: the recorded decodes and the operator's look): from Enable Tx on to the QSO's end qso true and rx_parity constant, the marks on my Rx parity only; no open range overlaps the partner or another station decoded in my counted Rx periods; after the QSO the marks alternate again; in the run its tx_slot is its own choice (power_db as before), and the marks are the same as without the run.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-065-01';
            verify 'CL-065-02';
        }
    }
    dependency CL_065_01_verified_by_TC_082_006 from 'CL-065-01' to 'TC-082-006';
    // #89 the newest Rx period counts once its decodes are published (operator 2026-11-09, "Count once decoded").
    verification 'TC-089-001' {
        doc /* TC-089-001 — Due periods at a decision
             CL-039-09, CL-065-01
             Setup: the slot decision and open-slot functions with hand-authored per-period bin levels (flat floor 30 dB) and decodes (audio frequency, period), FT8 my Rx parity odd, P the newest odd period; FT4 for (f).
             Steps: (a) a decision at P + 14.1 s with P's complete publication; (b) the same instant without it; (c) only a partial publication of P; (d) undecoded, in every period a flat 30 dB in every bin (floor 30.65, TC-039-050), except in P the 18 bins k = 512..529 of [1500, 1550) Hz at 42 dB in P's rows 3..64 (62 rows of 0.2 s, 0.6..12.8 s) and 30 dB in its other rows; the test feeds P's rows 0..69 (the 70 rows complete at P + 14.1 s) for the decision at (a), then rows 70..74 and a decision at P + 15.2 s; (e) a decision at P + 15.2 s, P ended without its publication, then after it; (f) FT4 a decision at P + 6.9 s with P's complete publication; (g) a complete publication naming the next odd period P + 2, published while P + 1 is in progress (a period not yet begun).
             Expected (hand computation recorded in the test; oracle: WstxStrategy::FreeTxSlot Due): (a) counted P and the 3 odd periods before it, the 4th older not; a decode at 2340 Hz in P closes the candidates 2300..2380 (|f - d| below 50); (b) P not counted, the 4 before it counted, 2340 closes nothing; (c) as (b); (d) at P + 14.1 s slot 1500 level (62 x 42 + 8 x 30) / 70 = 40.63, floor 30.65 (the band's 18 bins lie above each segment's 8th lowest level, so the flat-floor fit stands), rise 9.98, value 10 (every other period and every slot outside the band 0); at P + 15.2 s with all 75 rows level (62 x 42 + 13 x 30) / 75 = 39.92, rise 9.27, value 9; (e) P counted by its levels, 2340 closes nothing until the publication, then closes; (f) P counted; (g) P + 2 not due and not counted, its decodes close nothing. Red on the parent: (a) P not counted and 2340 open; (d) value 0.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-09';
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/freeslot_tests.rs; server/src/newest_rx_tests.rs";
    }
    dependency CL_039_09_verified_by_TC_089_001 from 'CL-039-09' to 'TC-089-001';
    dependency CL_065_01_verified_by_TC_089_001 from 'CL-065-01' to 'TC-089-001';
    verification 'TC-089-002' {
        doc /* TC-089-002 — Decisions on the newest Rx period (the 12:24:29 reproduction)
             CL-039-09
             Setup: the actual station router with the contact engine on the hardware double, virtual UTC; detailed rows and decodes modelled on HB9BLA 2026-11-09 12:24:15-12:24:29 (#66 comment 6740465378): Tx 2340 free in the 4 older odd periods, in the odd period P M7HNI decoded at 2340 Hz.
             Steps: a strategy run with Hold Tx off selects HA7NB (1001 Hz) on P's complete publication at P + 14.1 s; Hold Tx on, a slot check of a target that does not hear us with a station decoded on Tx only in P; the same selection by a pounce; a station decoded only in the 5th older odd period.
             Expected (hand computation recorded in the test; oracle: FreeTxSlot Due and Choice): Tx and Rx to the hand-computed nearest free slot clear of 2340 and 1001, tx_slot.hz not 2340; at the slot check Tx alone moves off the station; the pounce as the selection; the 5th older station closes nothing. Red on the parent: Tx stays on 2340.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-09';
        }
        attribute executable : String = "server/src/newest_rx_tests.rs";
    }
    dependency CL_039_09_verified_by_TC_089_002 from 'CL-039-09' to 'TC-089-002';
    verification 'TC-089-003' {
        doc /* TC-089-003 — Open slots rebuilt on the publication of the period in progress
             CL-065-01
             Setup: the actual station router with hand-authored detailed rows of both parities and decodes, the contact engine on the hardware double, virtual UTC (as TC-082-002).
             Steps: (a) in a QSO with Tx even, the complete publication of the odd period P at P + 14.1 s with a station decoded at 1200 Hz in P; (b) listening without a run, P's complete publication, then the next period start; (c) only a partial publication of P; (d) a publication of the other parity.
             Expected (hand computation recorded in the test; oracle: CL-065-01): (a) one build at once with periods counting P, the slot overlapping 1200 Hz closed, at_utc_ms the publication time; (b) a build with P's parity counting P, at the next period start the parity flips as before; (c) no build counting P; (d) the judged periods unchanged. Red on the parent: no build at P's publication, the 1200 Hz slot open until the next period start.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/newest_rx_tests.rs";
    }
    dependency CL_065_01_verified_by_TC_089_003 from 'CL-065-01' to 'TC-089-003';
    verification 'TC-089-004' {
        doc /* TC-089-004 — A contest strategy's CQ waits for the newest Rx period
             CL-039-09, CL-039-05
             Setup: the actual station router, the WW Digi contest built-in strategy (cq_when_idle on, cq_wait_periods 2: CQ only after two empty publications, CqWhenNoTarget), Hold Tx off, Tx 1500, Rx parity even, P = e, the contact engine on the hardware double, virtual UTC.
             Steps: (a) Auto on at P + 5 s, P's complete publication at P + 14.1 s (a station at 1500 calling another); (b) no publication at P + 15.0 and P + 29, then e + 15 published empty at e + 29.1; (c) Hold Tx on; (d) Auto off, and separately Halt, at P + 20 s; (e) P published before Auto on, Auto on at P + 20 s; (f) Auto on sent again at P + 20 s; (g) the operator's manual contact ended by Esc at P + 5 s, and separately completed (logged about e + 28).
             Expected (oracle: WstxStrategy::FreeTxSlot Waiting for the newest period and CqWhenNoTarget, hand-worked): (a) waiting, no decision and no enable_tx at P + 8 and P + 14; P's publication is the first empty one, still waiting; (b) no decision without a publication; at e + 29.1 (the second empty) the CQ slot taken with P counted, 1460..1540 closed, giving 1450, armed; (c) no CQ at Auto on or the first publication, CQ on the held 1500 at the second, no slot decision; (d) stopped, no decision at the second; (e) P not fresh, still waiting after the empty e + 15, CQ from 1450 after the empty e + 30; (f) one decision (1450) at the second; (g) Esc: no set_frequency at P + 14 or at P's publication, CQ at 1750 on e + 15's publication; completed: no CQ at e + 29.9, e + 30 or the first empty publication after (e + 30, published e + 44.1), CQ at the second (e + 45, published e + 59.1), Tx 1500 kept. Red on the parent: build only.
             2 — Isolated automated tests; Windows development PC, no radio (wstx-rust). */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-09';
            verify 'CL-039-05';
        }
        attribute executable : String = "server/src/newest_rx_tests.rs";
    }
    dependency CL_039_09_verified_by_TC_089_004 from 'CL-039-09' to 'TC-089-004';
    dependency CL_039_05_verified_by_TC_089_004 from 'CL-039-05' to 'TC-089-004';
    verification 'TC-089-005' {
        doc /* TC-089-005 — Live decisions on the newest Rx period on HB9BLA
             CL-039-09, CL-065-01
             Setup: the gated candidate installed on HB9BLA, IC-7300 1 W FT8 on 20 m or 10 m within the operator's standing transmit consent, PSK Reporter on.
             Steps: Auto on with a strategy through at least 20 decisions, Hold Tx on and off; at each decision record tx_slot, free_tx_slots and the decodes of the newest Rx period (as D:/wstx-tmp/live/20261109/tc66-decisions.txt) on the issue; HALT, Auto off.
             Baseline before #89 (#66 comment 6740465378): 16 of 98 listed slots in 10 of 23 decisions sat on stations of the newest Rx period, the kept Tx 2340 on M7HNI.
             Expected (oracle: the recorded decodes and the operator's look): no chosen slot overlaps a station decoded in the newest Rx period while a free one exists; no open range overlaps one from that period's publication on.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-039-09';
            verify 'CL-065-01';
        }
    }
    dependency CL_039_09_verified_by_TC_089_005 from 'CL-039-09' to 'TC-089-005';
    dependency CL_065_01_verified_by_TC_089_005 from 'CL-065-01' to 'TC-089-005';
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

    requirement 'CL-063-03' {
        doc /* The operator selects a contest with its period and a contest strategy of that contest (CL-097-07) through a prompt pre-filled from the schedule rule (empty for ARRL January VHF, which the prompt asks), shown with the strategy and editable; with Auto off it only colours (CL-039-22). It is exclusive with a strategy of class strategy, is held in station memory only, and None ends it. The log is evaluated only inside that period: dupes by the profile's rule, multipliers, points and the score. Choosing an activity sets no strategy and selecting a contest sets no activity. Details: WstxContest::ContestSelection, ContestLog, ContestPrompt. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contest.rs; server/src/strategy.rs; server/src/logbook.rs; client/contact.js";
    }
    dependency CL_063_03_to_FR_024 from 'CL-063-03' to 'FR-024';
    dependency CL_063_03_to_FR_019 from 'CL-063-03' to 'FR-019';
    requirement 'CL-063-04' {
        doc /* With a contest in force Band Activity lists only the stations that can be called (non-dupe in the period, directive allows it, a CQ or an RR73/73, on a band of the contest), ordered by callers of my call, new multiplier, QSO points, SNR, with the partner on top; a Show all toggle (off) shows the rest. Colour only for the callable, a new multiplier apart; a dupe and a directed CQ dimmed. The station evaluates, the browser renders after a publication, never on a timer. A contest also works by hand: every row stays selectable with Show all. Details: WstxContest::ContestVerdict, ContestValueOrder, ContestView. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contest.rs; server/src/strategy.rs; client/contact.js; client/recording.css";
    }
    dependency CL_063_04_to_FR_024 from 'CL-063-04' to 'FR-024';
    dependency CL_063_04_to_FR_010 from 'CL-063-04' to 'FR-010';
    verification 'TC-063-005' {
        doc /* TC-063-005 \— The points and multiplier rules
             CL-063-03
             Setup: distances computed apart from this code (haversine, R 6371 km; IARU 111.2 km per degree): JN37-FN42 5894.6 km, JN37-JO62 701.6, JN37-JN38 111.2, JN37-PM95 9624.3.
             Steps: each points rule for those pairs, a six-character locator, the same square, no grid; the VHF band tables; Field Day per mode; the multiplier keys.
             Expected: WW 2, 1, 1, 4; ARRL 13, 3, 2, 21; IARU 5895, 702, 112, 9625; the same large square 50; ARRL same square 2 (the minimum distance value); no grid none; 1 per call; January 1,1,2,2,4,4,8,8 and June/September 1,1,2,2,3,3,4,4 for 6 m, 2 m, 1.25 m, 70 cm, 33 cm, 23 cm, 13 cm, 3 cm; Field Day digital 2, CW 2, phone 1; keys FN|20m and FN42|6m, none without a rule or a grid.
             2 \— Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-03';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_005_the_points_rules_by_hand";
    }
    dependency CL_063_03_verified_by_TC_063_005 from 'CL-063-03' to 'TC-063-005';
    verification 'TC-063-006' {
        doc /* TC-063-006 \— The log inside the period, the dupe rules and the verdicts
             CL-063-03, CL-063-04
             Setup: hand-written QSO lists and decoded records for HB9BLA JN37 in EU on 20 m with activity ww_digi.
             Steps: a WW Digi log with a QSO before the period, one at its exclusive end, a repeat in FT4, another band, SSB and 30 m; ARRL VHF with a rover and without a grid; Field Day SSB; FT8 Activity on another band; ARRL Digi with RTTY. Verdicts for a known field, a new far field, a new near field, a dupe, CQ NA, no CQ, another station's RR73, a weak caller, a dupe caller; on 30 m; without a log; a /R CQ in ARRL VHF and IARU.
             Expected: 2 QSOs, 2 multipliers, 4 points, score 8, nothing outside the period counted; VHF dupe on the same grid only, every grid without a logged grid; Field Day digital no dupe of SSB; a Field Day exchange to my call a caller with 2 points or a dupe, to another call not a CQ; FT8 Activity a dupe on another band; ARRL Digi 1 QSO, 13 points, score 13. Rank order caller, far new multiplier, near new multiplier, the known field, the RR73; the dupes rank null with dupe true, also the caller; greyed CQ NA; nothing ranked on 30 m or without a log; the wire form of a verdict; the rover ranked in ARRL VHF, refused callsign guard in IARU.
             2 \— Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-03';
            verify 'CL-063-04';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_006_only_the_period_counts_and_each_dupe_rule; server/src/contest_tests.rs::tc_063_006_verdicts_callable_by_value; server/src/contest_tests.rs::tc_063_006_a_field_day_exchange_to_my_call_is_a_caller";
    }
    dependency CL_063_03_verified_by_TC_063_006 from 'CL-063-03' to 'TC-063-006';
    dependency CL_063_04_verified_by_TC_063_006 from 'CL-063-04' to 'TC-063-006';
    verification 'TC-063-007' {
        doc /* TC-063-007 \— The contest selection on the store and the evaluate route
             CL-063-03, CL-063-04
             Setup: exact-parse table; the actual station router on a disposable selected HTTPS profile (HB9BLA, JN47AA) on 40 m with an imported log (one QSO inside the period, one before), an injected FT8 live job with CQ WW W1DUP, K1OLD and JA1XYZ, activity ww_digi.
             Steps: each refused selection form, also with each key that WstxContest::ContestSelection refuses as an extra key; PUT with a contest {profile, start, end} and active the WW Digi built-in; read strategy.json; a new owner; the automation snapshot; PUT with a strategy of class strategy and a contest; a period with end not after start; evaluate; PUT without contest; evaluate.
             Expected: each field named, those keys refused as extra keys; the configuration echoes the contest, the file holds none, a new owner has none, no run; 400 field contest (a strategy plus a contest is accepted only when the strategy is a contest strategy of that profile, TC-097-015) and contest.end; verdicts JA1XYZ rank 0 new multiplier 4 points, K1OLD rank 1, W1DUP dupe with rank null; tally 1 QSO, 1 multiplier, 3 points, score 3 (JN47-EM12 8469.4 km); strategy WW Digi; after None the key is gone and evaluate says not_configured.
             2 \— Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-03';
            verify 'CL-063-04';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_007_a_selection_is_parsed_exactly; server/src/strategy_tests.rs::tc_063_007_a_contest_selection_store_and_evaluation";
    }
    dependency CL_063_03_verified_by_TC_063_007 from 'CL-063-03' to 'TC-063-007';
    dependency CL_063_04_verified_by_TC_063_007 from 'CL-063-04' to 'TC-063-007';
    verification 'TC-063-008' {
        doc /* TC-063-008 \— The contest prompt, the callable list and Show all in the browser
             CL-063-03, CL-063-04
             Setup: actual browser with hand-written station replies for the receive results, GET and PUT /strategy, GET /strategy/contests and POST /strategy/evaluate.
             Steps: no contest; the prompt on WW Digi; a page reload with the contest in force; ARRL January VHF without a date; Start, with a row to my call that is a dupe, rows carrying all-time flags (new call, new DXCC) and a row of the partner; the partner's contact prepared and ended; Show all on and off; 1.5 s of silence; reopen; None; the prompt at 360 px.
             Expected: the toggle hidden, the selector unchanged, nothing evaluated and no read of /strategy/contests without a contest; one read at the prompt, and one after the reload, which names the contest in the selector; the rule's period pre-filled, the clause, the activity line, the contest strategies offered with no operation choice (TC-097-015); January empty and refused with no request; one PUT with active the contest built-in and the contest; one evaluation; the row to my call stays beside JA1XYZ with the multiplier colour and K1ABC, the status with period and tally; no all-time slot colour and no new-call or new-DXCC reason on any row; a partner row is listed first while its contact stands, and hidden after; Show all adds the dupe and the directed CQ dimmed, without a slot colour, with no new request; no request during the silence; the period in force on reopening; None sends no contest, shows every row and brings the slot colour back; no sideways overflow on the phone.
             2 \— Isolated automated browser test; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-03';
            verify 'CL-063-04';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_063_03_verified_by_TC_063_008 from 'CL-063-03' to 'TC-063-008';
    dependency CL_063_04_verified_by_TC_063_008 from 'CL-063-04' to 'TC-063-008';
    requirement 'CL-063-05' {
        doc /* With Auto on the run applies the contest strategy (CL-097-04, CL-097-07): it calls the most valuable callable station by the contest's rules, and with its CQ when idle calls CQ with the contest's message and answers the most valuable non-dupe caller (with Calling stations are answered on; new multiplier, QSO points, SNR), not the first decoded; a dupe caller is never answered and never ends a stay. Leaving follows CL-039-23 with the strategy's leave and retry pause. Where the rules forbid automatic operation the browser shows the clause as a warning when Auto is switched on and transmits only after the operator's confirmation, and the station refuses Auto on without it; where they are silent a short note. It waits while the activity, the band or the period do not fit the contest; a contest can still be operated by hand. Details: WstxContest::ContestRun, AutomationClause, ContestSelection; WstxStrategy::AutoToggle, LeaveRule. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/contest.rs; server/src/strategy.rs; server/src/logbook.rs; client/contact.js";
    }
    dependency CL_063_05_to_FR_024 from 'CL-063-05' to 'FR-024';
    dependency CL_063_05_to_FR_020 from 'CL-063-05' to 'FR-020';
    verification 'TC-063-009' {
        doc /* TC-063-009 — Search and pounce, and the automation clause
             CL-063-05
             Setup: the selection form table; the actual station router (HB9BLA JN47AA) with the contact engine and #9 transmit owner on the recording hardware double, virtual UTC, on 20 m, an imported QSO with W1DUP inside the period; a status session held open; for the manual QSO, the CAT owner on a scripted IC-7300 whose dial reads 14.074 MHz, confirmed, and an empty log.
             Steps: each forbidding and silent profile with its contest built-in and with a copy (cq_when_idle false), then Auto on with and without the confirmation; a selection with operation colouring or with automation_confirmed; set_activity alone; the copy with Auto on and activity none, on 30 m, then fitting; CQ WW W1DUP (strongest), K1ABC and JA1XYZ (weakest); empty partner periods; W1DUP alone; a selection whose period starts in an hour; a run with a manual replacing QSO with W9XYZ to its end, nothing imported, the log rebuilt, then W9XYZ's CQ alone.
             Expected: Auto on refused field automation_confirmed where forbidden, accepted where silent; colouring and automation_confirmed refused on PUT with their field; no run with Auto off, after the refused Auto on and after set_activity; reasons activity, band, none; never a CQ; JA1XYZ selected and armed, Tx2 with the grid; after 2 partner periods without progress waiting, disarmed, JA1XYZ in its retry pause; nothing armed for the dupe alone; outside_period and nothing armed; the log holds exactly W9XYZ EN52 20m FT8, written by the completed QSO itself; the manual QSO's station a dupe, nothing armed.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-05';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_009_a_selection_asks_nothing_and_refuses_colouring_and_the_confirmation; server/src/strategy_tests.rs::tc_063_009_search_and_pounce_calls_the_most_valuable_and_waits_for_what_it_needs; server/src/strategy_tests.rs::tc_063_009_a_manual_qso_of_the_period_is_a_dupe_for_the_next_evaluation; server/src/strategy_tests.rs::tc_039_042_a_silent_contest_switches_auto_on_without_a_confirmation";
    }
    dependency CL_063_05_verified_by_TC_063_009 from 'CL-063-05' to 'TC-063-009';
    verification 'TC-063-010' {
        doc /* TC-063-010 — CQ when idle in a contest and the most valuable caller
             CL-063-05
             Setup: as TC-063-009 with the scripted IC-7300 on 14.074 MHz, activity ww_digi, the contest built-in WW Digi selected (cq_when_idle true, cq_wait_periods 2); no callable station in the published periods (only callers).
             Steps: two empty publications; callers W1DUP (dupe, strongest), K1ABC (first non-dupe decoded), JA1XYZ (weakest, new multiplier, most points); its R and 73; steps; nothing imported; JA1XYZ again; once the log is rebuilt, callers JA2ABC PM85 (more points) and K1NEW FN42; Abort of that QSO; an empty period; Abort of the run's own CQ; the band leaves the contest and returns (the dial to 10.136 MHz and back); the station clock past the period's end.
             Expected: calling_cq, armed, Tx6 "CQ WW HB9BLA JN47"; JA1XYZ answered with 2 candidates, not the first, not the strongest, not the dupe; completed, then calling_cq again with 1 completed; the log holds W1DUP EM12 and JA1XYZ PM95 20m FT8, the latter written by the completed QSO itself; not answered again; K1NEW selected, PM being no new multiplier any more; after that Abort calling_cq; the CQ goes on; after Abort of the CQ calling_cq, armed, with a new contact id; waiting band and disarmed, then calling_cq and armed again; waiting outside_period and disarmed.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs::tc_063_010_run_calls_cq_and_answers_the_most_valuable_caller";
    }
    dependency CL_063_05_verified_by_TC_063_010 from 'CL-063-05' to 'TC-063-010';
    verification 'TC-063-012' {
        doc /* TC-063-012 — Fully automatic in the browser
             CL-063-05
             Setup: actual browser with hand-written replies for GET and PUT /strategy, POST /strategy/auto, GET /strategy/contests and GET /automation.
             Steps: the contest built-in WW Digi chosen in the prompt (TC-097-015), Start; Auto on, decline; Auto on, confirm; 1.5 s of silence; automation.state pushes for calling_cq, waiting outside_period and stopped run_limit; reopen and Start the same selection; reopen; FT8 Activity with its built-in and Auto on.
             Expected: Start sends one PUT with active the built-in and the contest {profile, start, end}, no automation_confirmed; the warning with the clause on Auto on, nothing sent when declined; one POST /strategy/auto with automation_confirmed true when confirmed; no read of /automation during the silence; the status names each; Start of the same selection sends nothing new to the run (Auto stays as pushed); the strategy in force on reopening, the built-in of another contest chosen first, the note; no warning and no automation_confirmed for FT8 Activity.
             2 — Isolated automated browser test; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-05';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_063_05_verified_by_TC_063_012 from 'CL-063-05' to 'TC-063-012';
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
    // #81 A started QSO is finished whatever ends the run (operator 2026-11-08, two grill-me rounds).
    requirement 'CL-081-01' {
        doc /* (#81, operator 2026-11-08: "If Auto is deselected during a QSO, this QSO is finished, has to be finished as normal. Auto only starts."; "A started QSO should always be finished out of courtesy. If we did not answer, then this does not count as a QSO") Auto, and every run, decides only whether new QSOs start. A started QSO is a contact of a run whose dialogue holds a decoded message of the partner to my call and an own transmission to the partner that has started (keyed, also one still on the air); a station that called my call before our transmission to it started, and a station we called that has sent nothing to my call, are no started QSO. When Auto off, None, another strategy or contest selection, an Auto on that ends a pounce or MCP run, an AutomationCommand stop or a policy run's time limit ends the run, or a contest period ends during it, the run ends (or waits) at once with its reason as before, and a started QSO stays armed and is finished as an ordinary contact: sequenced to its end and logged once, bounded by the Tx watchdog's stop at N with no leave rule, slot check or exemption; Tx and Rx stay; nothing new is selected, called or answered for it, and a run started meanwhile waits for it as for the operator's contact. A contact that is no started QSO ends at once at these ends as before; a transmission already on the air finishes its period and nothing after it is keyed. Still at once: HALT, Abort QSO, the operator's selection of another station, the Tx watchdog's stop, the grant revoked or a safety edit, a band or mode change by the operator, a station restart, and the run's own leaving while it runs. Details: WstxStrategy::StartedQso, StrategyRun, AutoToggle; WstxMcp::OperatingAutomation; WstxContact::TxWatchdog. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/contact_http.rs; server/src/contact.rs; client/contact.js";
    }
    dependency CL_081_01_to_FR_007 from 'CL-081-01' to 'FR-007';
    dependency CL_081_01_to_FR_020 from 'CL-081-01' to 'FR-020';
    verification 'TC-081-001' {
        doc /* TC-081-001 — Reproduction: Auto off in a started QSO
             CL-081-01
             Setup: as TC-039-042 (the actual station router, HB9BLA JN47AA, with the contact engine, automation and #9 transmit owner on the recording hardware double, virtual UTC, 20 m FT8, a status session held open, the browser cookie grant); the saved strategy "New calls" of class strategy (new [call] per ever, order [most_wanted]) selected, Auto on; Tx watchdog 6; an empty log.
             Steps: publish CQ K1ABC FN42; let the run select and call K1ABC (Tx1 keyed); publish K1ABC's answer HB9BLA K1ABC -05 in his period; at the next station step POST /strategy/auto {auto false}; then publish HB9BLA K1ABC RR73 after our next transmission; afterwards publish CQ DL1XYZ JO62 and W1AW calling my call for three periods.
             Expected (oracle: the operator's rule of 2026-11-08 on #81 and the standard sequence of WstxContact::QsoAndLogging): Auto off at once (GET /strategy auto false, one strategy.state) and the run stopped with reason stopped; Enable Tx stays on: the R-report K1ABC HB9BLA R-.. is keyed in the next own period, then 73 after his RR73; the contact completed with Enable Tx off; exactly one log entry K1ABC FN42 20m FT8, written by the completed contact itself; after the completion nothing is armed, selected or keyed: DL1XYZ and W1AW never get a transmission. Red on the parent: Enable Tx off and the contact cancelled at the Auto off, no R-report keyed, nothing logged.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-081-01';
        }
        attribute executable : String = "server/src/autofinish_tests.rs";
    }
    dependency CL_081_01_verified_by_TC_081_001 from 'CL-081-01' to 'TC-081-001';
    verification 'TC-081-002' {
        doc /* TC-081-002 — What is a started QSO
             CL-081-01
             Setup: as TC-081-001; for (a), (b) and (d) the saved strategy "Casual 20 m" of class strategy (new [call] per band, cq_when_idle true, cq_wait_periods 2) calling CQ after two empty publications, Hold Tx off; each case from a new run.
             Steps: (a) W1AW FN31 calls my call during the CQ; the run answers; POST /strategy/auto {auto false} 2 s into the period in which our reply to W1AW is keyed; W1AW then sends R-.. and RR73 in turn. (b) The same, with Auto false after W1AW is selected and our reply armed, before its period starts; W1AW calls my call again for three periods. (c) The saved strategy "New calls" (new [call] per ever, order [most_wanted]) calling CQ K1ABC FN42, K1ABC silent; Auto false 2 s into the period of our second Tx1; then K1ABC answers HB9BLA K1ABC -05. (d) Auto false 2 s into a period in which the run's CQ is keyed, no caller.
             Expected (oracle: the definition of a started QSO in CL-081-01): (a) started: the reply's period ends normally (no abort, no halt), the exchange goes on to completed and one log entry of W1AW; (b) not started: Enable Tx off and the contact cancelled at once, no transmission to W1AW, his further calls not answered, nothing logged; (c) not started: the Tx1 on the air finishes its period (no abort, PTT released at its normal end), then nothing is keyed, the contact cancelled, K1ABC's answer not replied to, nothing logged; (d) the CQ on the air finishes its period, nothing keyed after it, no CQ contact left behind. Red on the parent: (a) Enable Tx off and cancelled at the Auto off; (b), (c) and (d) are regression guards, green on the parent.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-081-01';
        }
        attribute executable : String = "server/src/autofinish_tests.rs";
    }
    dependency CL_081_01_verified_by_TC_081_002 from 'CL-081-01' to 'TC-081-002';
    verification 'TC-081-003' {
        doc /* TC-081-003 — Every run end that lets a started QSO finish
             CL-081-01
             Setup: as TC-081-001; for (c) and (d) the contest WW Digi in force with a copy of its built-in (cq_when_idle false) and automation_confirmed (as TC-063-009); for (e) a pounce on K1ABC started by MCP with Auto off (as TC-039-042); for (f) and (g) an MCP policy run (as TC-020-003) with max_run_minutes 1 for (g) and the automation clock moved by the seam. Each case runs into the same started QSO: K1ABC FN42 called by the run, his answer HB9BLA K1ABC -05 decoded, then the end below, then his RR73 after our R-report.
             Steps: (a) PUT /strategy with active None; (b) PUT /strategy with the saved strategy "Farthest new on band" (order [distance]) while Auto is on, and CQ JA1XYZ PM95 published during the QSO and after its completion; (c) PUT /strategy without the contest; (d) the station clock past the contest period's end; (e) POST /strategy/auto {auto true} with the saved strategy "New calls" selected; (f) AutomationCommand stop of the run; (g) the run deadline passed; (h) POST /strategy/auto {auto false} sent twice, 1 s apart.
             Expected (oracle: the list of run ends in CL-081-01): every case completes K1ABC with exactly one log entry and keys nothing for another station until it has completed; the run's state and reason at the end: (a) stopped, Auto off; (b) the old run stopped, Auto on, the new run manual until the completion, then waiting, and JA1XYZ selected only from a publication after the completion; (c) stopped, Auto off; (d) waiting outside_period after manual, disarmed after the completion; (e) the pounce stopped, the strategy run manual until the completion; (f) stopped; (g) time_limit; (h) stopped once, the second request changes no revision and no contact. Red on the parent: each case disarms and cancels K1ABC at the end, nothing logged.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-081-01';
        }
        attribute executable : String = "server/src/autofinish_tests.rs";
    }
    dependency CL_081_01_verified_by_TC_081_003 from 'CL-081-01' to 'TC-081-003';
    verification 'TC-081-004' {
        doc /* TC-081-004 — The finishing QSO is bounded by the Tx watchdog, not by the run
             CL-081-01
             Setup: as TC-081-001 with the Tx watchdog set to 2 by the browser, the strategy's leave {calls 4, calls_heard 8}, a spot of my call at K1ABC 60 s old (he hears us: the leave rule would allow 8 calls), K1ABC called from Tx 1500 with the quietest slot elsewhere; the started QSO of TC-081-001.
             Steps: (a) Auto false after our 1st R-report; K1ABC sends RR73 after our 2nd R-report. (b) Auto false after our 1st R-report; K1ABC repeats HB9BLA K1ABC -05 every period. (c) Auto stays on while K1ABC repeats -05 until our R-report has been keyed 3 times (past the limit under the run's exemption, StrategyWatchdog); then Auto false.
             Expected (oracle: WstxContact::TxWatchdog, limit 2, and CL-081-01): (a) the 2nd R-report keyed, then 73, completed, one log entry (the limit not passed); (b) the R-report keyed a 2nd time, never a 3rd: 1.2 s into that period Enable Tx goes off with cause txWatchdog, no halt, nothing logged; (c) the R-report not keyed again after the Auto off, Enable Tx off with cause txWatchdog at 1.2 s into the next due period; in every case after the Auto off no leaving (left null, no quiet entry), no Tx move (tx_hz stays 1500, slot_check unchanged), the hearing subscription of K1ABC dropped, and the contact snapshot's tx_remaining_calls that of the Tx watchdog. Red on the parent: (a) disarmed at the Auto off, never completed.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-081-01';
        }
        attribute executable : String = "server/src/autofinish_tests.rs";
    }
    dependency CL_081_01_verified_by_TC_081_004 from 'CL-081-01' to 'TC-081-004';
    verification 'TC-081-005' {
        doc /* TC-081-005 — What still ends a finishing QSO at once
             CL-081-01
             Setup: as TC-081-001, Auto false sent in the started QSO and the R-report keyed once after it (the QSO finishing); a second run of (h) with Auto on.
             Steps: (a) HALT by route; (b) Abort QSO (ContactCommand abort); (c) a double-click of W1AW's call to my call (select_row replace true, then enable_tx); (d) the radio's dial to 7.074 MHz (band change); (e) the operating mode to FT4; (f) the browser grant revoked; (g) a safety edit; (h) with Auto on and the run still on, K1ABC silent after his report for 4 repetitions (no spot).
             Expected (oracle: the immediate stops of CL-081-01): (a) halted, the transmission stopped, nothing keyed after, nothing logged; (b) the transmission stopped now, the contact cancelled, nothing logged, no halt; (c) W1AW's contact replaces K1ABC's and is called, K1ABC never logged; (d), (e), (f) Enable Tx off and the contact cancelled at the next station step, nothing keyed after and nothing logged; (g) Enable Tx off with cause authorityChanged, nothing logged; (h) left {K1ABC, repetitions} at the 4th, disarmed and cancelled, waiting. Red on the parent: the precondition fails, the QSO is already ended at the Auto off ((h) is a regression guard, green on the parent).
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-081-01';
        }
        attribute executable : String = "server/src/autofinish_tests.rs";
    }
    dependency CL_081_01_verified_by_TC_081_005 from 'CL-081-01' to 'TC-081-005';
    verification 'TC-081-006' {
        doc /* TC-081-006 — The Auto button says what Auto off does
             CL-081-01
             Setup: actual browser with hand-written replies for GET /strategy (a strategy selected, auto true, then false) and GET /contact (transmit capability available, a contact in progress with K1ABC), and pushed strategy.state and automation.state (as TC-039-046).
             Steps: read the Auto button's title with Auto on; push Auto off with the run stopped and the contact still in progress; read the button, the strategy line and the QSO pane.
             Expected (oracle: the texts of WstxStrategy::AutoToggle and StrategySelector): with Auto on the title "Auto on: the selection transmits. Click to switch Auto off; a QSO already started is finished"; after the push the button grey with the title "Auto off: the selection only marks. Click to let it transmit", the line "Strategy New calls · Auto off" and the QSO pane still showing the contact with K1ABC. Red on the parent: the on title lacks the sentence on the started QSO.
             2 — Isolated automated browser test; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-081-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_081_01_verified_by_TC_081_006 from 'CL-081-01' to 'TC-081-006';
    verification 'TC-081-007' {
        doc /* TC-081-007 — Live: Auto off in a QSO on HB9BLA
             CL-081-01
             Setup: the gated candidate installed on HB9BLA, IC-7300 on 20 m or 40 m FT8 within the operator's standing transmit consent (1 W on 40 m), Tx watchdog 6; contact and run snapshots read from GET /contact and GET /automation at each step; the station log read before and after.
             Steps: Auto on with the saved strategy "Strongest new on band" (as TC-039-047); when a station has answered our call (his report decoded) switch Auto off in the browser; watch to the end of the QSO and two more periods; Auto on with the saved strategy "Casual 20 m" (as TC-039-045) until it calls CQ; switch Auto off while the CQ is keyed.
             Expected: after the first Auto off the Auto button grey and the line "Strategy Strongest new on band · Auto off" at once, the QSO goes on to RR73/73 and is logged once (one new log entry of that call), then nothing is keyed; after the second Auto off the CQ period ends normally and nothing is keyed after it; recorded on the issue.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-081-01';
        }
    }
    dependency CL_081_01_verified_by_TC_081_007 from 'CL-081-01' to 'TC-081-007';
    // #97 Strategy settings and ranking: one set of settings for every strategy (operator grill
    // 2026-11-09, re-scope 2026-11-12; takes over #84, #90, #91, #93, #94). Detailed contract in
    // WstxStrategy D19.
    requirement 'CL-097-01' {
        doc /* (#97, operator grill 2026-11-09 and 2026-11-12) There are two classes (operator grill Q12): strategy (Filters and Order from the filter questions) and contest (from a contest, CL-097-07); a strategy's class is never switched. strategy.json schema 4 holds, per strategy and in this order: name, class, bands, filters, order, contest, callers_first, leave, tx_move_every {heard, not_heard, no_reports}, busy_pause, cq_when_idle, cq_wait_periods, retry_minutes; each refusal names its field path. A strategy is new only as a duplicate (built-in or saved), keeping its class and contest. The editor shows the settings as the nine numbered decisions: 1 band, 2 filters, 3 order, 4 "Calling stations are answered", 5 leaving a station, 6 Tx frequency, 7 busy pause, 8 "CQ when idle, after <n> periods with nothing callable", 9 retry pause. Saved files of schema 1, 2 and 3 are upgraded at their revision as WstxStrategy::StrategyConfiguration maps them (a schema 3 strategy key by key, with cq_wait_periods 2), and a saved strategy whose name collides with a built-in is renamed, never dropped, with the rename shown once. Built-ins: the five of the table of 2026-11-09, DXCC all, New DXCC on band, New DXCC (until logged, gone 10 min, most wanted then SNR, CQ when idle off), Casual (new call per band, SNR bucket then distance, after 4 calls or 8 if he hears us, CQ when idle on) and POTA/SOTA (only CQ POTA and CQ SOTA, new call per band since today, SNR bucket then distance, after 4 calls or 8 if he hears us, CQ when idle off), all of class strategy, all bands, region all, Calling stations are answered on, Tx stay/every call/every 2nd call, busy pause on, retry 10 min; plus one contest built-in per contest (CL-097-07); each with cq_wait_periods 2. "DXCC all" is first in the list; no built-in is called the default, and active is None at a station start. A strategy defines values only: it never selects, calls, answers, arms or transmits. The settings of decisions 5 to 9 take effect only through the part that starts QSOs: the run (CL-097-04) until #119, then Auto. Details: WstxStrategy::Strategy, StrategyClass, BuiltinStrategies, StrategyConfiguration, StrategyEditor, StrategySelector, StrategyHttp. */
        attribute implementation : String = "server/src/strategy.rs; client/contact.js";
        attribute coverage : ImplementationState = ImplementationState::partial;
    }
    dependency CL_097_01_to_FR_007 from 'CL-097-01' to 'FR-007';
    dependency CL_097_01_to_FR_016 from 'CL-097-01' to 'FR-016';
    dependency CL_097_01_to_FR_019 from 'CL-097-01' to 'FR-019';
    requirement 'CL-097-04' {
        doc /* (#97 decisions 5, 8 and 9, #91; the run that applies a strategy's settings, the stopgap until #119 replaces it with Auto) Leaving a station, one of three modes per strategy: after n calls without an answer, m while he hears us; until logged, leaving when he has not been decoded for n minutes; contest style, staying while he hears us and is still the most valuable, else leaving after n Tx changes. Progress (his message to my call) resets the count; a caller of my call with a rank (CL-097-03: it passes the filters and Calling stations are answered is on) is answered at once; unattended or past the run limit there is no m, no contest stay and no busy pause, and the Tx watchdog's stop at N is back. After every leaving the retry pause (minutes) passes before the station is called or answered again. WD:n shows only the Tx watchdog: in a run's own contact, which the Tx watchdog does not stop while attended, no WD is shown and the leave count has its own label ("Leave in n calls", "Until logged", "Leave in n Tx changes", "Stay · most valuable", with "busy, not counted" while the target is busy); GET /transmit watchdog.tx_remaining_calls is null for such a contact (never the leave count) and the receive page leaves its WD part out. Contest style counts change points; with "stay" for the case Tx never moves at them. Off the strategy's bands the run waits with reason band. The run's own select_row of a CQ whose directive word is on the active strategy's CQ target include list passes the directed-CQ check; every other automatic select_row of a non-answerable directive stays refused directive_not_answerable (an MCP or UDP command, a pounce, a run of a strategy without the word). With CQ when idle on the run calls CQ after the CQ wait (CL-097-08). Details: WstxStrategy::LeaveRule, QuietTime, LeaveCountLabel, StrategyWatchdog, StrategyRun, DirectedCqRule, CqWhenNoTarget; WstxContact::ContactSnapshot, TxWatchdog. */
        attribute implementation : String = "server/src/automation.rs; server/src/contact_http.rs; client/contact.js; client/recording.js";
        attribute coverage : ImplementationState = ImplementationState::partial;
    }
    dependency CL_097_04_to_FR_007 from 'CL-097-04' to 'FR-007';
    dependency CL_097_04_to_FR_008 from 'CL-097-04' to 'FR-008';
    requirement 'CL-097-06' {
        doc /* (#97 decision 7, operator #93 "we pause counting ... till the called station finishes its other qso") Busy pause: the called station is busy from his message to another call carrying a grid, report or R-report (a hashed call not filled with my call is another call) until he ends that QSO with RR73, RRR or 73 to another call, a CQ, free text or a message to my call, however long he is not decoded. The station keeps calling, on a split frequency: when he sends to another call and my signal is not 50 Hz clear of his (FT8 100 Hz, FT4 140 Hz between the lower edges), Tx moves to the nearest clear candidate from 500 Hz (also clear of decoded stations and of his PSK Reporter frequencies while one is free), Rx stays on him, also with Hold Tx on; a refused move stops as the WSJT-X rule does; an operator's own Tx wins until his next message to another call. This replaces the WSJT-X stop for every contact that pauses (a manual contact; a run's own contact with busy pause on), also while it is not pausing. A call is paused when he is busy at its stop point (1.2 s into the period) and is not counted: in a run with busy pause on, not toward leaving or Tx moves; in a manual contact, not toward the Tx watchdog. At most N paused calls per message (N the Tx watchdog limit), so nothing the partner does extends the bound; a pounce, an MCP policy run and a run with busy pause off never pause and keep the WSJT-X stop; unattended there is no pause. The contact snapshot carries busy_with and paused_calls within GET /contact's 4096 bytes, and the QSO pane shows "<call> busy with <other>, not counted (k/N)". Details: WstxContact::BusyPartner, TxWatchdog, AutoSequence; WstxStrategy::BusyPause, FreeTxSlot. */
        attribute implementation : String = "server/src/contact.rs; server/src/freeslot.rs; server/src/automation.rs; server/src/contact_http.rs; client/contact.js";
        attribute coverage : ImplementationState = ImplementationState::partial;
    }
    dependency CL_097_06_to_FR_007 from 'CL-097-06' to 'FR-007';
    dependency CL_097_06_to_FR_008 from 'CL-097-06' to 'FR-008';
    requirement 'CL-097-07' {
        doc /* (#97, interface to #98) A strategy of class contest names a contest id of the contest table, has order [], and has filters {countries, states, cq_targets}: the contest supplies its rules (dupes, points, multipliers, ranking) and the strategy its other settings. Each contest has a read-only contest built-in with leave contest style after 2 Tx changes, tx_move_every {0, 2, 2}, busy_pause off, cq_when_idle on, cq_wait_periods 2 and retry_minutes 10. The contest prompt offers the built-in and the saved contest strategies of that contest; the prompt's choice and period select it. There is no operation choice and no per-contest repetitions or retry pause: with cq_when_idle on the strategy's CQ when idle applies. Details: WstxContest D11, ContestSelection, ContestPrompt, ContestRun, ContestValueOrder; WstxStrategy::StrategyClass, BuiltinStrategies. */
        attribute implementation : String = "server/src/contest.rs; server/src/strategy.rs; server/src/automation.rs; client/contact.js";
        attribute coverage : ImplementationState = ImplementationState::partial;
    }
    dependency CL_097_07_to_FR_007 from 'CL-097-07' to 'FR-007';
    dependency CL_097_07_to_FR_020 from 'CL-097-07' to 'FR-020';
    requirement 'CL-097-08' {
        doc /* (#97 decision 8, operator 2026-11-12) The CQ wait: cq_wait_periods is an integer 1..20, default 2, in every strategy of both classes; anything else, also a missing key, is refused at strategies[i].cq_wait_periods. With cq_when_idle on, the part that starts QSOs calls CQ only after this many consecutive fresh complete publications with nothing callable. Every period counts, in both parities: 2 is 30 s in FT8 and 15 s in FT4. The count starts at 0 at Auto on, after a QSO ends and after a leaving. With cq_when_idle off the value has no effect and is kept. Details: WstxStrategy::Strategy, CqWhenNoTarget, StrategyConfiguration, StrategyEditor. */
        attribute implementation : String = "server/src/strategy.rs; server/src/automation.rs; client/contact.js";
        attribute coverage : ImplementationState = ImplementationState::partial;
    }
    dependency CL_097_08_to_FR_007 from 'CL-097-08' to 'FR-007';
    dependency CL_097_08_to_FR_020 from 'CL-097-08' to 'FR-020';
    verification 'TC-097-001' {
        doc /* TC-097-001 — Strategy schema 4 on the wire
             CL-097-01, CL-097-08
             Setup: the actual station store and router on a disposable HTTPS profile; hand-written configurations; the expected acceptances and refusals written in the test from WstxStrategy::Strategy.
             Steps: PUT one strategy of each class with every key at its bounds (bands null and 32 bands; new with 1 and 7 whats; countries with 64 entries in each list, each {kind "prefix", value of 3 characters, bands null} except one entry with a 13-character prefix and one with 32 bands, states 51, cq_targets 32 of 8 characters; the test asserts the encoded body is below 32768 bytes; order with 16 criteria; each leave mode at its lower and upper bounds; tx_move_every 0 and 20; cq_wait_periods 1 and 20; retry_minutes 1 and 120); then one refusal each: cq_wait_periods 0, 21, "2", null and missing; band "11m", a repeated band, 33 bands; new [] and a repeated what; new_per "slot"; a country entry of kind "call", prefix "VK-9", a prefix of 14 characters, an entry with 33 bands, a country name not in the table, 65 entries; state "XX" and "PR", 52 states; a CQ target of 9 characters and "PO-TA", 33 CQ targets; an order with a repeat and with 17; leave calls 0 and 21, calls_heard below calls and 41, gone_minutes 0 and 61, tx_changes 0 and 21, mode "never"; tx_move_every -1, 21 and a missing case; retry_minutes 0 and 121; a contest strategy with order [most_wanted], with filters.new, with contest null and "unknown"; a class strategy with contest "ww_digi"; class "award" and "casual" (refused values); names "DXCC all" and "casual"; each schema 3 key (goals, needed, value, window, repetitions, quiet_minutes, cq_when_no_target) and builtin; a configuration whose body exceeds 32768 bytes.
             Expected: the first PUT accepted with revision + 1 and read back key for key; each refusal 400 invalid_request naming exactly its field path (strategies[0].bands[0], strategies[0].filters.countries.include[0].value, strategies[0].leave.calls_heard, strategies[0].cq_wait_periods for each CQ wait refusal, strategies[0].class, strategies[1].order, strategies[1].contest, strategies[0].name ...; strategy 0 of class strategy, 1 of class contest), nothing stored; the oversized body refused as every oversized body. Red on the parent: cq_wait_periods is refused as an extra key.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-01';
            verify 'CL-097-08';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    dependency CL_097_01_verified_by_TC_097_001 from 'CL-097-01' to 'TC-097-001';
    dependency CL_097_08_verified_by_TC_097_001 from 'CL-097-08' to 'TC-097-001';
    verification 'TC-097-002' {
        doc /* TC-097-002 — Upgrade of saved strategy.json files to schema 4
             CL-097-01, CL-097-08
             Setup: the actual station store on a disposable profile; hand-written strategy.json files of schema 1, 2, 3 and 4; the expected schema 4 strategies written in the test from the mapping table of WstxStrategy::StrategyConfiguration.
             Steps: a schema 3 file at revision 7 with "Mine" (goals [dxcc_band, new_call], needed not_confirmed, value [new_dxcc_slot, snr], repetitions 5, quiet_minutes 15, cq_when_no_target true, treat_73_as_cq false, window today, region dx), "Grid" (goals [grid]), "DXCC all", "dxcc all copy" and "Casual"; GET /strategy; PUT one change; read the file; a schema 3 file with an otherwise malformed strategy. The schema 2 store cases: a schema 2 file at revision 7 with "Mine" (goals [new_call], calls_per_station 5); GET /strategy; PUT a change; read the file; schema 2 strategies with calls_per_station 0, 21, missing, a bad region and a value key; a schema 3 file holding a schema 2 strategy. A schema 4 file with one strategy without cq_wait_periods and one with cq_wait_periods 5. Then the TC-039-030 goal fixtures evaluated through their mapped schema 4 strategies.
             Expected: revision 7; "Mine" class strategy, new [dxcc, call], new_per band (the most specific of band and ever), new_means not_confirmed, worked_since today, region dx, treat_73_as_cq false, the three lists empty, order [new_dxcc_band_mode, snr], contest null, leave {calls, 5, 10}, tx_move_every {0, 1, 2}, busy_pause true, cq_when_idle true, cq_wait_periods 2, retry_minutes 15; "Grid" new [grid] per ever; "DXCC all" renamed "DXCC all copy 2" ("dxcc all copy" is taken, ignoring case) and "Casual" renamed "Casual copy", configuration_note listing both; the malformed file configuration null with invalid_configuration; after the PUT the file is schema 4 at revision 8 and configuration_note []. Schema 2: revision 7 with "Mine" as schema 3 with value [most_wanted], callers_first true, cq_when_no_target false, repetitions 4 and quiet_minutes 10 reads it, mapped to schema 4 (new [call] per ever, leave {calls 4, calls_heard 8}, retry_minutes 10, cq_wait_periods 2); the PUT writes schema 4 at revision 8; each malformed one configuration null with invalid_configuration. Schema 4: the strategy without the key reads cq_wait_periods 2, the other 5. Each mapped goal gives the verdicts TC-039-030 expects of its goal (property: the same ranked set). Red on the parent: the strategies read without cq_wait_periods.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-01';
            verify 'CL-097-08';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    dependency CL_097_01_verified_by_TC_097_002 from 'CL-097-01' to 'TC-097-002';
    dependency CL_097_08_verified_by_TC_097_002 from 'CL-097-08' to 'TC-097-002';
    verification 'TC-097-003' {
        doc /* TC-097-003 — The built-in strategies and the contest built-ins
             CL-097-01, CL-097-07, CL-097-08
             Setup: the expected table written in the test from the operator's table on #97 and the contest defaults; the actual station router on a disposable HTTPS profile with today's contest profile table; the contact engine and #9 owner on the recording hardware double.
             Steps: GET /strategy; PUT active "DXCC all", "casual", "New calls"; PUT active "WW Digi" without a contest selection and with {ww_digi, start, end}; a station restart; GET /strategy.
             Expected: builtin_strategies exactly DXCC all, New DXCC on band, New DXCC, Casual, POTA/SOTA in this order, all five class strategy, with every key of the table (POTA/SOTA: worked_since today, cq_targets include [POTA, SOTA], cq_when_idle false), then one contest built-in per profile (class contest, contest its id, order [], leave {contest, 2}, tx_move_every {0, 2, 2}, busy_pause false, cq_when_idle true, retry_minutes 10), every built-in with cq_wait_periods 2, "DXCC all" first, no built-in named a default, none in configuration.strategies; "DXCC all" accepted; "casual" and "New calls" refused field active; "WW Digi" refused field contest without the selection and accepted with it; after the restart active None and auto false (DXCC all first in the list, not selected). Red on the parent: the built-ins carry no cq_wait_periods.
             2 — Isolated automated tests; Windows development PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-01';
            verify 'CL-097-07';
            verify 'CL-097-08';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    dependency CL_097_01_verified_by_TC_097_003 from 'CL-097-01' to 'TC-097-003';
    dependency CL_097_07_verified_by_TC_097_003 from 'CL-097-07' to 'TC-097-003';
    dependency CL_097_08_verified_by_TC_097_003 from 'CL-097-08' to 'TC-097-003';
    verification 'TC-097-009' {
        doc /* TC-097-009 — The three leave modes and the retry pause
             CL-097-04
             Setup: as TC-039-043 (the actual router, contact engine and #9 owner on the recording hardware double, virtual UTC, a feed without a connection fed hand-authored spots, a dial of 14074000 Hz, Hold Tx off), Tx watchdog 6; the run calling K1ABC (CQ FN42); one strategy per mode.
             Steps: (a) leave {calls 4, calls_heard 8}: K1ABC silent; the same with a spot of my call 60 s old; the spot ageing past 600 s after the 5th call. (b) leave {until_logged, gone_minutes 10}: K1ABC calling CQ every period for 30 minutes; K1ABC last decoded at t0 then silent, publications at t0 + 9 min 45 s and t0 + 10 min; K1ABC answers -05, then silent. (c) leave {contest, tx_changes 2} with tx_move_every {0, 2, 2}: K1ABC silent with no spot; K1ABC calling CQ with a spot and nothing more valuable for 20 periods; the same with a more valuable callable station listed from the 3rd period, with tx_move_every heard 0 (the contest built-in's) and with heard 1; tx_move_every no_reports 0. (d) An answer after the 3rd call, then silence. (e) retry_minutes 10: K1ABC's CQ after the leaving at 9 min 59 s and 10 min, its call to my call at 5 min. (f) No client for 60 s in each mode. (g) A caller of my call that passes the filters at the 2nd call in each mode.
             Expected (hand-worked from WstxStrategy::LeaveRule): (a) left at the 4th call {K1ABC, repetitions}; with the spot at the 8th; back to 4 once the spot is older than 600 s (left at the 5th); (b) never left while decoded (30 minutes); left {K1ABC, gone} at t0 + 10 min, not at t0 + 9 min 45 s; after the answer left 10 minutes after his last decode; (c) Tx moved after the 2nd and the 4th call and left {K1ABC, tx_changes} at the 6th (three slots); staying all 20 periods; counting from the 3rd: with heard 0 Tx never moves and K1ABC is left {tx_changes} at the 5th call (change points at the 3rd and 4th, leaving at the 5th), with heard 1 Tx moves at the 3rd and 4th and he is left at the 5th; with no_reports 0 Tx never moves and he is left at the 3rd call; (d) the counts back to 0; (e) not selected at 9 min 59 s nor answered at 5 min, selected at 10 min; (f) calls: left at 4 also with the spot; until_logged and contest: no stay, ended by the Tx watchdog's stop at 6; (g) left {K1ABC, caller} and the caller selected from the same publication. Red on the parent: the modes are refused.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-04';
        }
        attribute executable : String = "server/src/strategy97_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_097_04_verified_by_TC_097_009 from 'CL-097-04' to 'TC-097-009';
    verification 'TC-097-011' {
        doc /* TC-097-011 — A busy partner in a strategy run
             CL-097-06
             Setup: as TC-039-043 (the actual router, contact engine and #9 owner on the recording hardware double, virtual UTC, 20m FT8, Hold Tx on, waterfall rows on a flat floor so every candidate is free), a strategy with leave {calls 4, calls_heard 8}, busy_pause on (and off), Tx watchdog 3; the run calling KE1J from Tx 1500, KE1J's CQ at 1800 Hz; hand-authored decodes of KE1J to other calls.
             Steps: (a) KE1J sends W9XYZ KE1J -07 at 1200 Hz for two of his periods, then W9XYZ KE1J RR73, then CQ; (b) KE1J sends W9XYZ KE1J R-09 at 1510 Hz; (c) after (a)'s report, three periods without a decode of KE1J, then W9XYZ KE1J RR73; (d) KE1J busy for 5 periods; (e) KE1J sends HB9BLA KE1J -10 after being busy; (f) (a) and (b) with busy_pause off; (g) KE1J busy at 1510 Hz while the run is unattended; (h) KE1J sends W9XYZ KE1J FN42 and later W9XYZ KE1J 73; (i) KE1J goes on from W9XYZ to K2ABC with a report, then sends free text.
             Expected (hand-worked from WstxContact::BusyPartner and WstxStrategy::BusyPause): (a) our call keyed in every period, leave.busy true, paused 1 and 2, remaining stays 4; the RR73 ends it and the next call counts (remaining 3); (b) Tx moves before our next period to 1410 (the nearest candidate at least 100 Hz from 1510, FT8), Rx stays 1800, Enable Tx stays on, the call goes on; (c) the three calls without his decode stay paused (busy holds), the call after the RR73 counts; (d) 3 paused calls, the 4th and 5th count (N = 3); (e) progress resets every count; (f) the calls count and KE1J is left at the 4th; (b) disarms as partnerWorksOther does; (g) the calls count (no pause unattended) and Tx still moves to 1410, Enable Tx on, until the stop at N; (h) the grid to another starts busy, the 73 ends it; (i) busy holds across K2ABC and ends with the free text; no TxMoveRule move while busy. Red on the parent: the busy calls count and (b) disarms.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-06';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    dependency CL_097_06_verified_by_TC_097_011 from 'CL-097-06' to 'TC-097-011';
    verification 'TC-097-012' {
        doc /* TC-097-012 — Reproduction: a manual call to a busy station (KE1J, #93)
             CL-097-06
             Setup: the actual contact engine and router on the recording hardware double, virtual UTC, 10m FT4, Tx watchdog 6 set by the browser, Hold Tx on, no run; the operator double-clicks CQ KE1J at 1800 Hz with Tx 1500 (KE1J HB9BLA JN37 due).
             Steps: (a) the reproduction of 2026-11-09 14:39 UTC: KE1J works W9XYZ for 8 of his periods (reports at 1200 Hz), then W9XYZ KE1J RR73, then silent; (b) KE1J works a station at 1520 Hz; (c) KE1J busy for 10 periods; (d) after the stop, the operator's Enable Tx; (e) the limit set to 2 and (c) again.
             Expected (oracle: operator #93 "Keep calling, don't count" and the bound of WstxContact::TxWatchdog): (a) our Tx1 keyed in each of the 8 periods, the first 6 paused (WD:6 with " · KE1J busy with W9XYZ, not counted (k/6)", tx_expired false), the 7th and 8th counted (WD:5, WD:4), then counted after the RR73, stopped at the 12th send with "Tx watchdog: same message sent 6 times"; (b) Tx moves to 1380 (the nearest candidate at least 140 Hz from 1520, FT4), Rx stays 1800, Enable Tx stays on, Hold Tx still on; (c) stopped at the 12th send; (d) the counts restart; (e) 2 paused, stopped at the 4th send. Red on the parent: stopped at the 6th send in (a), (b) disarms.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-06';
        }
        attribute executable : String = "server/src/contact_tests.rs";
    }
    dependency CL_097_06_verified_by_TC_097_012 from 'CL-097-06' to 'TC-097-012';
    verification 'TC-097-013' {
        doc /* TC-097-013 — Reproduction: WD:n is the Tx watchdog only, the leave count has its own label (#91)
             CL-097-04
             Setup: the actual router (contact and run snapshots) and Chromium with routed replies and pushed events as TC-039-046; Tx watchdog 6.
             Steps: (a) the #91 run of 2026-11-09: a run calling M7HNI with M7HNI HB9BLA +15, M7HNI repeating his message so that the leave count resets; (b) a run's own contact with leave {calls 4, calls_heard 8}, attended, then unattended; (c) a contest stay; (d) until_logged; (e) a manual contact; (f) a busy partner in the run and in the manual contact; (g) GET /transmit and the receive page's transmit line during (b) attended, (b) unattended and (e).
             Expected (oracle: WstxStrategy::LeaveCountLabel and WstxContact::ContactSnapshot): (a) no WD text in the run's own contact, tx_remaining_calls null, the label "Leave in <n> calls" going back up on his message; (b) "Leave in 4 calls" .. "Leave in 1 calls"; unattended WD:n with the Tx watchdog's count; (c) "Stay · most valuable", never "WD:∞"; (d) "Until logged", then "Until logged · leave if gone <n> min"; (e) WD:6 down to WD:1; (f) the busy suffixes; (g) watchdog.tx_remaining_calls null while armed in (b) attended and the transmit line without a WD part, an integer (the Tx watchdog's) unattended and in (e) with "WD <n> calls". Red on the parent: WD:2 then WD:6 in (a); GET /transmit reports the leave countdown.
             2 — Isolated automated tests and browser test; Windows development PC; no RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-097-04';
        }
        attribute executable : String = "server/src/strategy97_tests.rs; server/src/strategy_tests.rs; server/src/contact_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_097_04_verified_by_TC_097_013 from 'CL-097-04' to 'TC-097-013';
    verification 'TC-097-014' {
        doc /* TC-097-014 — The editor and the selector in the browser
             CL-097-01
             Setup: the actual isolated server and Chromium at 1366x768 and 360x740; routed replies for GET and PUT /strategy and POST /strategy/evaluate; a snapshot with the built-ins, two saved strategies of class strategy (an award-like and a casual-like one) and one of class contest, and configuration_note [{from "Casual", to "Casual copy"}].
             Steps: open the editor; read the decisions of "DXCC all", decision 4's label, decision 8 and every text of the editor; Duplicate "DXCC all"; set every control of the nine decisions (the CQ wait 5); look for a class control; open the contest strategy; enter a country name that the station refuses; Save; close; open the selector; choose the saved contest strategy (contest ww_digi) with no contest in force, then with ww_digi in force, then with another contest in force (FT8 Activity in the test), and Cancel and Start in the prompt it opens.
             Expected (oracle: WstxStrategy::StrategyEditor and StrategySelector): the list grouped Strategy, Contest, no Add; the headings 1 Band .. 9 Retry pause with decision 4 "Calling stations are answered" (its checkbox labelled the same) and decision 8 reading "CQ when idle, after <n> periods with nothing callable" with n 2 for the built-in; no "default" in the editor's text or options; "DXCC all copy" of class strategy with the nine decisions in order and their labels; Save sends exactly one PUT whose strategy is the schema 4 object written in the test, key for key, with cq_wait_periods 5; the class shown and never switchable; the contest strategy shows its contest read-only, only the three lists and "Ranked by the contest's rules"; the refusal shown at the country control; "Renamed Casual to Casual copy" shown once; the selector grouped with "DXCC all" first and no contest built-ins; one evaluate request 400 ms after an edit; no horizontal overflow at 360 px; choosing the contest strategy with no contest or with another contest in force (FT8 Activity in the test) sends nothing and opens the prompt on WW Digi with that strategy chosen and the period pre-filled, Cancel sends nothing and the selector returns to the earlier selection, Start sends one PUT {active the strategy, contest {ww_digi, start, end}}; with ww_digi in force it sends one PUT with that active and the same contest key. Red on the parent: decision 4 is headed "Callers first" and decision 8 has no CQ wait.
             2 — Isolated automated browser test; Windows development PC. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-097-01';
            verify 'CL-097-08';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_097_01_verified_by_TC_097_014 from 'CL-097-01' to 'TC-097-014';
    dependency CL_097_08_verified_by_TC_097_014 from 'CL-097-08' to 'TC-097-014';
    verification 'TC-097-015' {
        doc /* TC-097-015 — Contest strategies: the prompt and the selection
             CL-097-07
             Setup: as TC-039-044 (WW Digi, 20m, the period in force, Auto on with automation_confirmed); the contest built-in "WW Digi" and a saved copy "WW Digi fast"; the prompt in Chromium with routed replies. The contest strategy's run is TC-097-018's.
             Steps: open the prompt, choose WW Digi, Start with the built-in; PUT a contest selection with operation "run"; active a strategy of class strategy with the contest.
             Expected (oracle: WstxContest D11 and WstxStrategy::BuiltinStrategies): the prompt offers "WW Digi" first and "WW Digi fast", with no operation choice and no repetitions or retry pause; Start sends one PUT {active "WW Digi", contest {ww_digi, start, end}}; the PUTs refused 400 field contest.operation and contest. Status "Contest WW Digi · <period> UTC · WW Digi · Auto on". Red on the parent: the prompt offers an operation choice.
             2 — Isolated automated functional and browser tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-07';
        }
        attribute executable : String = "server/src/strategy97_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_097_07_verified_by_TC_097_015 from 'CL-097-07' to 'TC-097-015';
    verification 'TC-097-016' {
        doc /* TC-097-016 — Live: DXCC all and Casual on HB9BLA
             CL-097-01, CL-097-02, CL-097-03, CL-097-04, CL-097-05, CL-097-06, CL-097-07, CL-097-08
             Setup: the gated candidate installed on HB9BLA, IC-7300 on 20m or 40m FT8 within the operator's standing transmit consent (1 W on 40m), Tx watchdog 6, PSK Reporter on and Use PSK Reporter on, Hold Tx on; contact and run snapshots read from GET /contact and GET /automation at each step.
             Steps: select "DXCC all" with Auto off for two periods; Auto on until a QSO is logged or a target is left gone; when a called station works another station, watch it; select "Casual", let it call CQ with nothing callable, answer a caller to a logged QSO and leave a silent station; a duplicate of Casual with Calling stations are answered off while a station calls my call; open the editor; note tx_hz, slot_check and the leave label at each repetition.
             Expected: with Auto off only stations of a DXCC entity not confirmed on this band and mode are marked; Casual calls CQ after 2 empty periods, and again 2 periods after the QSO; with callers off a station calling my call has no mark and is not answered; the editor shows the nine decisions with the CQ wait; a target stays until logged or not decoded for 10 minutes; no slot below 500 Hz is chosen; Tx stays when he hears us, moves every call when he reports and does not hear us, every 2nd call when he does not report; while a target is busy the calls go on, are not counted, and Tx is never within 50 Hz of his signal; the QSO pane shows the leave label and no WD in the run's own contact; Casual leaves after 4 calls (8 while heard) and does not answer a caller worked on the band; recorded on the issue.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-097-01';
            verify 'CL-097-02';
            verify 'CL-097-03';
            verify 'CL-097-04';
            verify 'CL-097-05';
            verify 'CL-097-06';
            verify 'CL-097-07';
            verify 'CL-097-08';
        }
    }
    dependency CL_097_01_verified_by_TC_097_016 from 'CL-097-01' to 'TC-097-016';
    dependency CL_097_04_verified_by_TC_097_016 from 'CL-097-04' to 'TC-097-016';
    dependency CL_097_06_verified_by_TC_097_016 from 'CL-097-06' to 'TC-097-016';
    dependency CL_097_07_verified_by_TC_097_016 from 'CL-097-07' to 'TC-097-016';
    dependency CL_097_08_verified_by_TC_097_016 from 'CL-097-08' to 'TC-097-016';
    verification 'TC-097-017' {
        doc /* TC-097-017 — Busy start and end, the split-frequency table and the busy marker (cases carried over from the #93 draft fca9822fe)
             CL-097-06
             Setup: the actual contact engine and router on the recording hardware double, virtual UTC, FT8 and FT4, Tx watchdog 6 set by the browser, Hold Tx on; a manual contact calling KE1J (CQ at 1800 Hz) from Tx 1500, KE1J HB9BLA JN37 due; hand-authored codec-packed decodes of KE1J published at set offsets into my period; waterfall rows on a flat floor except where a step names a decoded station; a feed without a connection fed hand-authored spots; Chromium with routed replies for the screen steps.
             Steps: (a) start and end: KE1J to W9XYZ with a grid, a report, an R-report; KE1J to "<...>" whose hash is not my call's, and one whose hash is my call's; then each end in turn: RR73, RRR, 73 to W9XYZ, CQ KE1J, free text "TNX QSO", HB9BLA KE1J -10. (b) timing: the publication that starts busy arriving 1.1 s into my period, and in another run 1.3 s (the stop point 1.2 s), with the message at its limit. (c) split table, FT8: KE1J to W9XYZ with |Tx - his frequency| 0, 50, 51, 99, 100 Hz; FT4: 139 and 140 Hz; the only candidates clear of him below 500 Hz and at 500 Hz; a decoded station on the nearest clear candidate; a PSK spot of KE1J decoding another sender within 50 Hz of the nearest clear candidate in my Tx parity, and in the other parity; his decode arriving before the audio start of my next send, and after it; set_frequency refused for the move; the operator clicking Tx onto his signal while he is still busy, then his next message to W9XYZ. (d) marker: GET /contact while busy with W9XYZ, with a 13-character other call and the maximum snapshot shape of TC-007-004; the QSO pane and the station bar.
             Expected (hand-worked from WstxContact::BusyPartner and TxWatchdog): (a) the grid, report and R-report start busy_with W9XYZ; the unresolved hash starts busy_with "<...>", the hash of my call is a message to me (progress, no busy); each end clears busy_with and the next send counts; (b) at 1.1 s the send at the limit is paused and keyed; at 1.3 s it is stopped by the Tx watchdog (Enable Tx off, txWatchdog) and the busy counts from the next send; (c) FT8 0, 50, 51 and 99 Hz move Tx, 100 Hz does not; FT4 139 moves, 140 does not; never below 500 Hz (500 chosen when it is the nearest clear); the decoded station's slot skipped while another is clear; the slot near his PSK frequency of my Tx parity skipped (the other parity does not skip); before the audio start the pending request carries the new offset, after it that send finishes at the old offset and the next is moved; the refused move turns the transmit state off with cause partnerWorksOther (the partnerWorksOther stop), nothing keyed on his signal; the operator's Tx kept until his next message to W9XYZ, then moved again; (d) watchdog.busy_with "W9XYZ" and paused_calls k, GET /contact at most 4096 bytes in the maximum shape with the 13-character call; " · KE1J busy with W9XYZ, not counted (k/6)" after WD:n in the QSO pane and the station bar, gone with busy_with null. Red on the parent: (c) disarms at 0 and 50 Hz, no busy_with key.
             2 — Isolated automated functional and browser tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-097-06';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; server/src/strategy97_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_097_06_verified_by_TC_097_017 from 'CL-097-06' to 'TC-097-017';
    verification 'TC-097-018' {
        doc /* TC-097-018 — The run applies the strategy's settings, and the CQ wait
             CL-097-04, CL-097-08
             Setup: the actual station router, contact engine and #9 owner on the recording hardware double, virtual UTC, 20m FT8, Auto on. For the CQ wait the saved strategy "Casual 20 m" of TC-039-045 (W1AW worked on 20m today) with cq_when_idle and cq_wait_periods set per step, and "Test calls" of TC-039-043 with leave {calls 1, calls_heard 2}, cq_when_idle true and cq_wait_periods 3. For the run: "Test calls" with bands ["20m", "40m"]; the built-in POTA/SOTA; a duplicate of Casual with min SNR -10 (W1AW worked on 20m); the WW Digi built-in and its copy "WW Digi fast" (leave {contest, 1}, cq_when_idle false, countries exclude [country "Japan"]) of TC-097-015 with W1DUP a dupe in the log.
             Steps: (a) cq_when_idle on with cq_wait_periods 1, 2 and 5: empty publications of alternating parity (every 15 s) until the CQ. (b) cq_when_idle off with cq_wait_periods 1: eight empty publications. (c) cq_wait_periods 3: one empty publication, Auto off and on, then empty publications. (d) cq_wait_periods 3: one empty publication, N1NEW FN31 calling my call (a callable station before the CQ is due), his R-05 and 73, then empty publications. (e) "Test calls": one empty publication, then CQ K1ABC FN42 selected, K1ABC silent at the next publication, then empty publications. (f) Bands: the run on 15m with CQ K1ABC FN42 published; the dial to 20m; on 20m in a contact with K1ABC, the dial to 17m. (g) POTA/SOTA with CQ POTA K1ABC FN42; the operator's double-click of it with POTA/SOTA active and Auto off; an MCP select_row of the CQ POTA row; a run of "Test calls" (no POTA on its include list) with CQ POTA K1ABC. (h) The Casual duplicate: W1AW calls my call, then W1AW and N1NEW FN31; a QSO with K1ABC whose answer -05 is decoded at -15 dB; the operator's double-click of W1AW's call. (i) WW Digi: one and two empty publications; CQ JA1XYZ PM95, CQ K1ABC FN42 and the dupe W1DUP calling my call; a JA caller of my call; then "WW Digi fast" with six empty publications, the same stations, K1ABC silent without spots.
             Expected (hand-worked from WstxStrategy::CqWhenNoTarget, StrategyRun, LeaveRule, DirectedCqRule and CL-097-08): (a) waiting after one fewer empty publication than the CQ wait, then calling_cq at exactly that many (state calling, Tx6 "CQ HB9BLA JN47", armed), both parities counted; (b) never a CQ, nothing armed; (c) still waiting after the 2nd empty publication after Auto on, calling_cq at the 3rd; (d) N1NEW answered (report), the QSO completed; then waiting at 2 empty publications and calling_cq at the 3rd; (e) left {K1ABC, repetitions}; then waiting at 2 empty publications and calling_cq at the 3rd; (f) the run waits with reason band and arms nothing on 15m; after the retune it selects K1ABC from the next publication; the retune to 17m disarms and cancels the contact at the next step (no retry entry) and the run waits band; (g) K1ABC selected (the run's own select_row accepted), armed and its Tx1 "K1ABC HB9BLA JN47" keyed in the next own period; the double-click refused 409 directive_not_answerable (the warning); the MCP select_row refused directive_not_answerable; "Test calls" never selects it; (h) W1AW never answered by the run, N1NEW answered; K1ABC's answer is progress (roger report due, not left); the double-click starts a manual QSO with W1AW (state manual); (i) no CQ after one empty publication, the CQ after the second; JA1XYZ selected (first by ContestValueOrder) and the CQ ended, W1DUP never answered, the JA caller answered at once; under "WW Digi fast" no CQ, JA1XYZ and the JA caller without rank, K1ABC selected, moved after the 2nd call (no_reports, every 2nd call) and left {K1ABC, tx_changes} at the 4th. Red on the parent: the CQ after 2 publications for 1 and for 5, and at the 2nd in (c), (d) and (e).
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-04';
            verify 'CL-097-08';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    dependency CL_097_04_verified_by_TC_097_018 from 'CL-097-04' to 'TC-097-018';
    dependency CL_097_08_verified_by_TC_097_018 from 'CL-097-08' to 'TC-097-018';
    verification 'TC-097-019' {
        doc /* TC-097-019 — The model carries no superseded wording
             CL-097-01, CL-097-02, CL-097-03, CL-097-07
             Setup: the files docs/sysml/*.sysml as read by the test; the patterns and scopes written in the test from lists A and B of #97.
             Steps: (1) the doc bodies rewritten into settings or ranking text: WstxStrategy package doc lines D1, D2, D3, D15, D19 and the docs of StrategyClass, NewWhat, NewPer, ValueCriterion, Needed, LeaveMode, PskCase, Strategy, StrategyBands, CountryList, UsStateFilter, UsStateOf, CqTargetList, BuiltinStrategies, StrategyConfiguration, NewNeeded, CallerOfMyCall, Candidate, ValueOrder, Verdict, StrategyEditor; the WstxContest package doc before D1 and its lines D1 and D11, and the docs of ContestSelection, ContestPrompt, ContestValueOrder, ContestView; the docs of CL-039-01, CL-039-02, CL-039-04, CL-039-11, CL-042-01, CL-063-03; each searched for P1 (the run vocabulary: run, runs, StrategyRun, ManualIntervention, the search-and-pounce operation, pounce, policy run, select_row, enable_tx), P2 (a strategy or contest strategy that selects, calls, answers, leaves, arms, transmits or starts) and P3 (a replacement or target note, ignoring case), with the patterns of #97's TC-097-019 written in the test. (2) every file searched for the old setting vocabulary of #97's check 2 (the operation choice, the per-contest repetitions and quiet time, the CQ option and the goals of schema 3, the callers rule of D5 and the old callers label, the award class), except the refused-keys sentences of WstxStrategy::Strategy and WstxContest::ContestSelection, the upgrade text of WstxStrategy::StrategyConfiguration, TC-097-001 and TC-097-002. (3) every file searched for a #97 note or label (the issue number followed by a colon, with or without a parenthesis between).
             Expected: no match in any of the three searches; a failure names each hit as file:line and the matched text. Red on the parent: the hits of lists A and B (search 1 in WstxStrategy D1, D2, D19, CallerOfMyCall, CqTargetList, UsStateOf, Verdict, StrategyEditor, the WstxContest package doc and D11, ContestSelection, ContestPrompt, ContestView, CL-039-01, 02, 04, 11, CL-042-01, CL-063-03; search 2 in Strategy, Contest, Contact, ProductScope and Requirements; search 3 the #97 notes and labels).
             2 — Isolated automated test; Windows development PC; no browser, radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-01';
            verify 'CL-097-02';
            verify 'CL-097-03';
            verify 'CL-097-07';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_097_01_verified_by_TC_097_019 from 'CL-097-01' to 'TC-097-019';
    dependency CL_097_07_verified_by_TC_097_019 from 'CL-097-07' to 'TC-097-019';

}
