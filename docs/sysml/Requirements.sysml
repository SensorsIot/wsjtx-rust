// Canonical authority: SysML
package WstxRequirements {
    private import ScalarValues::*;
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
             Offer a selectable native FlexRadio TCP/UDP connection type alongside the default audio-device/optional CAT/PTT path. Native profiles operate without requiring external SmartSDR desktop/CAT/DAX applications, persist their receive intent (never a radio identity, slice index or handle) and reconcile actual resources on connection. Both paths share the browser/DSP/MCP architecture. Receive and control at isolated level 2 are delivered (WstxProductScope::NativeFlexWireSubset); live hardware qualification TC-023-004/005 and transmit TC-023-006 remain open. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/flex/session.rs; server/src/flex/wire.rs; server/src/flex_http.rs; server/src/profile.rs; client/recording.js";
    }
    requirement 'FR-024' {
        doc /* Contest, special-activity and DXpedition operation — phase three
             Offer WSJT-X's special operating activities chosen by the operator, the contest exchanges, the Hound role and the nonstandard message types, each with its decode, encode, sequencing and logging, on the shared browser/modem/QSO/log/MCP services. Approved slices (issue #24, operator 2026-11-03, WSJT-X 3.3.0-beta5 reference): S1 nonstandard/compound calls, filled-in hashed calls and free text; S2a grid-exchange contests; S2b Field Day and RTTY Roundup (ADIF contest fields, no Cabrillo); S4 classic Hound. S5 SuperFox Hound moved to its own phase-two issue #77 (operator 2026-11-08); Fox (S6) was dropped; EU VHF (S3) is backlog. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/decoder/hashes.rs; server/src/recording.rs; server/src/contact.rs; server/src/transmit/pack.rs";
    }
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
    requirement 'CL-003-03' {
        doc /* The server MUST validate request structure, protocol version, command and message size in the contract's order. Rejected input MUST follow the defined error/close behavior; recoverable errors MUST leave the server available without exposing internal details. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs; client/app.js";
    }
    dependency CL_003_03_to_FR_021 from 'CL-003-03' to 'FR-021';
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
        attribute implementation : String = "server/src/main.rs; client/app.js";
    }
    dependency CL_003_05_to_FR_021 from 'CL-003-05' to 'FR-021';
    requirement 'CL-003-06' {
        doc /* Application output buffering and active connections MUST have explicit bounds (WstxStationProtocol::Limits; design bounds, checked by review). A peer that stops answering (no Pong for more than 15 s) MUST be removed at the next heartbeat tick, without delaying another client's status requests (#80: the one liveness case that matters in normal operation, a browser that vanishes without closing). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs; client/app.js";
    }
    dependency CL_003_06_to_FR_021 from 'CL-003-06' to 'FR-021';
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
    requirement 'CL-005-01' {
        doc /* A selected profile owns one process/listener; N is variable and storage, process and browser collections MUST NOT assume four entries. Four concurrent servers are sufficient for CR #5 acceptance; the implementation has no four-instance ceiling. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; client/app.js";
    }
    dependency CL_005_01_to_FR_022 from 'CL-005-01' to 'FR-022';
    requirement 'CL-005-02' {
        doc /* Stable identity, schema, validated settings, revision and acknowledged saves MUST survive process restart. The browser MUST identify the selected profile and permit the bounded edits below. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/profile.rs; client/app.js";
    }
    dependency CL_005_02_to_FR_001 from 'CL-005-02' to 'FR-001';
    dependency CL_005_02_to_FR_016 from 'CL-005-02' to 'FR-016';
    dependency CL_005_02_to_FR_019 from 'CL-005-02' to 'FR-019';
    dependency CL_005_02_to_FR_022 from 'CL-005-02' to 'FR-022';
    requirement 'CL-005-03' {
        doc /* Profile lifecycle, revision, configuration and authenticated sessions MUST be independent, including one browser cookie store on one hostname with distinct TLS ports. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; client/app.js";
    }
    dependency CL_005_03_to_FR_019 from 'CL-005-03' to 'FR-019';
    dependency CL_005_03_to_FR_021 from 'CL-005-03' to 'FR-021';
    dependency CL_005_03_to_FR_022 from 'CL-005-03' to 'FR-022';
    requirement 'CL-005-04' {
        doc /* Ownership, invalid storage, occupied endpoints and unavailable startup resources MUST fail explicitly without replacing saved configuration or disrupting a running instance. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; client/app.js";
    }
    dependency CL_005_04_to_FR_016 from 'CL-005-04' to 'FR-016';
    dependency CL_005_04_to_FR_021 from 'CL-005-04' to 'FR-021';
    dependency CL_005_04_to_FR_022 from 'CL-005-04' to 'FR-022';
    requirement 'CL-005-05' {
        doc /* Standard audio with optional CAT/PTT remains the default. Audio and control selections MUST persist independently without claiming hardware availability. A schema-1 document naming native_flex stays refused; a native profile is a separate schema-2 document chosen at profile creation (FR-023, WstxProfiles::NativeProfileDocument). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; client/app.js";
    }
    dependency CL_005_05_to_FR_001 from 'CL-005-05' to 'FR-001';
    dependency CL_005_05_to_FR_022 from 'CL-005-05' to 'FR-022';
    requirement 'CL-013-01' {
        doc /* Phase 2 MUST offer direct native-network integration as an optional profile connection type for the selected radio control, status and sample-stream functions. When selected, that native path MUST NOT require the external SmartSDR desktop application, SmartSDR CAT or DAX applications to be installed/running as bridges. This restriction does not prohibit those tools as operator-selected infrastructure for the standard connection path. A Rust implementation may coordinate shared radio access internally without forcing one hardware GUI-client session per logical station server. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/flex/session.rs; server/src/main.rs";
    }
    dependency CL_013_01_to_FR_023 from 'CL-013-01' to 'FR-023';
    requirement 'CL-013-02' {
        doc /* This independence concerns desktop applications. Compatible radio-side firmware and its API remain required; this specification does not promise a FlexRadio operating without its SmartSDR radio firmware or an unrestricted firmware compatibility range. Pin supported models, firmware/API versions and selected stream formats before implementation. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/flex/wire.rs; server/src/flex/session.rs";
    }
    dependency CL_013_02_to_FR_023 from 'CL-013-02' to 'FR-023';
    requirement 'CL-013-03' {
        doc /* Each native FlexRadio profile MUST persist its receive intent: its own client identity and receive antenna, and no radio identity (operator decision 2026-11-06 on #22: the station uses whichever radio discovery finds available). Where discovery cannot reach the radio, the profile may also save the radio's address (operator decision 2026-11-06 on #13): a locator for that one radio, not compared with anything. On every connection/reconnection the system MUST reconcile that intent with authoritative discovery/status and current runtime handles. A changed/transient slice index MUST NOT redirect a station to another station's slice. Unresolvable associations MUST produce a visible unavailable/conflict state rather than guessing a replacement. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/flex/session.rs; server/src/profile.rs";
    }
    dependency CL_013_03_to_FR_023 from 'CL-013-03' to 'FR-023';
    requirement 'CL-013-04' {
        doc /* Control responses and received stream data MUST be routed to the associated station. Capacity shortages, occupied resources and incompatible API behavior MUST be reported without stealing another profile's slice or silently reducing the requested independence. Four-slice hardware validation requires a model/configuration that actually provides at least four usable slices. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/flex/session.rs";
    }
    dependency CL_013_04_to_FR_023 from 'CL-013-04' to 'FR-023';
    requirement 'CL-013-05' {
        doc /* Shared-radio transmit, tuning and other constrained-resource authority MUST be coordinated under FR-008/FR-009 before those operations are enabled. Four station profiles do not confer simultaneous independent transmit authority. Reconnect/profile restoration MUST NOT replay an old transmit request or bypass the future ownership policy. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/flex/session.rs; server/src/transmit_http.rs";
    }
    dependency CL_013_05_to_FR_008 from 'CL-013-05' to 'FR-008';
    dependency CL_013_05_to_FR_009 from 'CL-013-05' to 'FR-009';
    dependency CL_013_05_to_FR_023 from 'CL-013-05' to 'FR-023';
    requirement 'CL-013-06' {
        doc /* The native path MUST reuse the common browser, station-operation, DSP/modem and future MCP interfaces. The default standard connection remains usable without FlexRadio hardware or native-profile fields. A mixed set of instances MUST preserve each profile's selected path, configuration and routing independently. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/recording.rs; server/src/receive_http.rs; server/src/selection_http.rs; client/recording.js; client/contact.js";
    }
    dependency CL_013_06_to_FR_023 from 'CL-013-06' to 'FR-023';
    requirement 'CL-006-01' {
        doc /* Import only the bounded WAV capability below; preserve original bytes and expose immutable, explicitly timed samples without a codec or implicit resampler. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/recording.rs; server/src/recording_http.rs; server/src/spectrum.rs; client/recording.js";
    }
    dependency CL_006_01_to_FR_003 from 'CL-006-01' to 'FR-003';
    dependency CL_006_01_to_FR_018 from 'CL-006-01' to 'FR-018';
    requirement 'CL-006-02' {
        doc /* Profile-owned import/replay/cancellation have explicit pending, terminal and recoverable error states; replacement never destroys the previous committed source before commit. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/recording.rs; server/src/recording_http.rs; server/src/spectrum.rs; client/recording.js";
    }
    dependency CL_006_02_to_FR_018 from 'CL-006-02' to 'FR-018';
    dependency CL_006_02_to_FR_019 from 'CL-006-02' to 'FR-019';
    requirement 'CL-006-03' {
        doc /* Show measured spectrum and source-time waterfall together above station controls in one station page; use the defined axes/math, accessible divider and bounded selectable Detailed/Thin/Off display. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/recording.rs; server/src/recording_http.rs; server/src/spectrum.rs; client/recording.js";
    }
    dependency CL_006_03_to_FR_010 from 'CL-006-03' to 'FR-010';
    dependency CL_006_03_to_FR_019 from 'CL-006-03' to 'FR-019';
    dependency CL_006_03_to_FR_021 from 'CL-006-03' to 'FR-021';
    requirement 'CL-006-04' {
        doc /* Bound import, sample, worker and visualization resources; refuse excess work explicitly, discard obsolete display work, preserve status service and invalidate late receive output on cancellation/replacement. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/recording.rs; server/src/recording_http.rs; server/src/spectrum.rs; client/recording.js";
    }
    dependency CL_006_04_to_FR_021 from 'CL-006-04' to 'FR-021';
    requirement 'CL-007-01' {
        doc /* Explicit FT4/FT8 selection MUST process the immutable canonical 12 kHz live source through the existing receive-job authority. Independent recorded fixtures MUST exercise the same pure modem without a physical radio; no file-decoding product operation is provided. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/decoder/mod.rs; server/src/receive.rs; client/recording.js";
    }
    dependency CL_007_01_to_FR_003 from 'CL-007-01' to 'FR-003';
    dependency CL_007_01_to_FR_004 from 'CL-007-01' to 'FR-004';
    dependency CL_007_01_to_FR_018 from 'CL-007-01' to 'FR-018';
    requirement 'CL-007-02' {
        doc /* The common browser MUST show exact supported payload fields, hash identities (filled in by the station per CL-024-01 or unresolved), UTC period time and relative DT when correlated or explicit unknown timing under4.7.4, lowest-tone audio frequency and calibrated SNR or explicit unavailable SNR, with reliable bounded result delivery. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/decoder/mod.rs; server/src/receive.rs; client/recording.js";
    }
    dependency CL_007_02_to_FR_003 from 'CL-007-02' to 'FR-003';
    dependency CL_007_02_to_FR_004 from 'CL-007-02' to 'FR-004';
    dependency CL_007_02_to_FR_019 from 'CL-007-02' to 'FR-019';
    requirement 'CL-007-03' {
        doc /* Each mode MUST satisfy independent payload/channel/waveform oracles; reference decoder output alone MUST NOT define exhaustive truth or make a hash reversible. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/decoder/mod.rs; server/src/receive.rs; client/recording.js";
    }
    dependency CL_007_03_to_FR_003 from 'CL-007-03' to 'FR-003';
    dependency CL_007_03_to_FR_004 from 'CL-007-03' to 'FR-004';
    dependency CL_007_03_to_FR_018 from 'CL-007-03' to 'FR-018';
    requirement 'CL-007-04' {
        doc /* CPU-only decoding MUST meet the per-mode quality, rejection, runtime, memory, repeatability, cancellation and link budgets below, with explicit bounded-work failure. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/decoder/mod.rs; server/src/receive.rs; client/recording.js";
    }
    dependency CL_007_04_to_FR_003 from 'CL-007-04' to 'FR-003';
    dependency CL_007_04_to_FR_004 from 'CL-007-04' to 'FR-004';
    dependency CL_007_04_to_FR_019 from 'CL-007-04' to 'FR-019';
    dependency CL_007_04_to_FR_021 from 'CL-007-04' to 'FR-021';
    requirement 'CL-007-05' {
        doc /* Live decode latency (#47). With a correlated UTC source clock, on the reference PC HB9BLA under normal station load (receive, waterfall, one browser, UDP enabled), for any session length: live FT8 MUST publish every decode of a frame with DT -1.6 s to +0.56 s by its period start + 15.0 s, and live FT4 every decode with DT -1.4 s to +0.86 s by period start + 7.5 s. Every frame with DT -1.6 s to +2.4 s (FT8) or -1.4 s to +2.2 s (FT4) MUST be published, the later ones from a late window early in the next period, which waits for the prompt decode instead of cutting it short, and extends its period's view with them under the same view id (nothing new publishes nothing), so clients keep their rows and cursor. The receive owner MUST measure the capture clock against UTC continuously (each timestamped packet's canonical frame against its QPC/system-time UTC, averaged over about 1 s, a jump above 0.2 s restarting the average) and re-anchor the window schedule, period UTC and DT whenever the measured offset moved by more than 50 ms, without dropping, repeating or reordering a window for a correction of any size; the measured offset and rate are read on demand from GET /receive/clock (capture_drift_ms, capture_drift_ppm), never added to the high-frequency GET /receive snapshot, whose clock object and thin-link size stay unchanged. (At zero offset the prompt windows hold FT8 DT -1.7..+0.66 s and FT4 -1.5..+0.96 s, prompt plus late windows FT8 -1.7..+2.56 s and FT4 -1.5..+2.36 s; the ranges above keep 0.1 s for the re-anchoring residual: the 50 ms threshold and drift within one period.) No per-period decode count cap applies; the only search bound is the existing 256 qualified-candidate limit with explicit SearchLimited. Without a correlated UTC clock the source-counter window grid of AdvanceDecode applies and no latency is promised. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/receive.rs; server/src/recording.rs; server/src/decoder/search.rs; server/src/decoder/subtraction.rs";
    }
    dependency CL_007_05_to_FR_003 from 'CL-007-05' to 'FR-003';
    dependency CL_007_05_to_FR_004 from 'CL-007-05' to 'FR-004';
    dependency CL_007_05_to_FR_021 from 'CL-007-05' to 'FR-021';
    requirement 'CL-008-01' {
        doc /* Persist independently selected audio and typed IC-7300 control intent through the existing profile revision/atomic-store boundary; settings never assert device availability. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/radio_control/mod.rs; server/src/receive.rs";
    }
    dependency CL_008_01_to_FR_001 from 'CL-008-01' to 'FR-001';
    dependency CL_008_01_to_FR_002 from 'CL-008-01' to 'FR-002';
    dependency CL_008_01_to_FR_009 from 'CL-008-01' to 'FR-009';
    dependency CL_008_01_to_FR_022 from 'CL-008-01' to 'FR-022';
    requirement 'CL-008-02' {
        doc /* Deliver immutable canonical 12 kHz mono samples and explicit timing/gaps through one common converter to the existing spectrum/decoder worker, without fabricating samples or UTC accuracy. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/radio_control/mod.rs; server/src/receive.rs";
    }
    dependency CL_008_02_to_FR_002 from 'CL-008-02' to 'FR-002';
    dependency CL_008_02_to_FR_003 from 'CL-008-02' to 'FR-003';
    dependency CL_008_02_to_FR_004 from 'CL-008-02' to 'FR-004';
    requirement 'CL-008-03' {
        doc /* Publish independently truthful audio/control states, bounded live results and explicit loss/recovery while preserving worker, cancellation and thin-link bounds. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/radio_control/mod.rs; server/src/receive.rs";
    }
    dependency CL_008_03_to_FR_002 from 'CL-008-03' to 'FR-002';
    dependency CL_008_03_to_FR_009 from 'CL-008-03' to 'FR-009';
    dependency CL_008_03_to_FR_019 from 'CL-008-03' to 'FR-019';
    dependency CL_008_03_to_FR_021 from 'CL-008-03' to 'FR-021';
    requirement 'CL-008-04' {
        doc /* Support the Windows shared-audio and IC-7300 receive-control matrix below, with independently verified receive-only physical acceptance. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/radio_control/mod.rs; server/src/receive.rs";
    }
    dependency CL_008_04_to_FR_002 from 'CL-008-04' to 'FR-002';
    dependency CL_008_04_to_FR_009 from 'CL-008-04' to 'FR-009';
    requirement 'CL-008-05' {
        doc /* Audio never requires CAT; CAT never opens audio. Unsupported operations fail before device bytes; independent failure never creates false readiness. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/radio_control/mod.rs; server/src/receive.rs";
    }
    dependency CL_008_05_to_FR_002 from 'CL-008-05' to 'FR-002';
    dependency CL_008_05_to_FR_009 from 'CL-008-05' to 'FR-009';
    requirement 'CL-008-06' {
        doc /* Separate a versioned factual radio catalogue, compiled typed operations and bounded protocol execution. Catalogue data cannot authorize raw or transmit commands. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/radio_control/mod.rs; server/src/receive.rs";
    }
    dependency CL_008_06_to_FR_009 from 'CL-008-06' to 'FR-009';
    requirement 'CL-008-07' {
        doc /* Coordinate receive-only operating mode and preferred band changes through the existing station/receive owner and typed CAT actor, with explicit nominal/observed truth, actual release barriers, per-query provenance and cancellation fencing. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/selection.rs; server/src/selection_http.rs; server/src/radio_http.rs; server/src/radio_control/actor.rs; client/recording.js";
    }
    dependency CL_008_07_to_FR_002 from 'CL-008-07' to 'FR-002';
    dependency CL_008_07_to_FR_009 from 'CL-008-07' to 'FR-009';
    // #9 transmit preparation; detailed contract in WstxTransmit.
    requirement 'CL-009-01' {
        doc /* Pack every supported FT8 message family (standard i3=1/2 with CQ forms,
             reports, R/RRR/RR73/73 and /R /P, i3=4 nonstandard calls with WSJT-X
             hashes, free text, telemetry, and since #24 S2b ARRL Field Day i3=0
             n3=3/4 and RTTY Roundup i3=3, CL-024-03) to the WSJT-X 77 bits, CRC-14 and LDPC
             codeword and 79 tones, and generate the FT8 GFSK waveform at 12 kHz and
             48 kHz within the declared WSJT-X reference tolerance. Unsupported,
             invalid or altered messages and out-of-range audio frequencies are
             explicit refusals. Details: WstxTransmit::PackMessage, ChannelFrame, Ft8WaveformContract. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/mod.rs; server/src/transmit/pack.rs; server/src/transmit/waveform.rs";
    }
    dependency CL_009_01_to_FR_005 from 'CL-009-01' to 'FR-005';
    requirement 'CL-009-02' {
        doc /* Plan an FT8 transmission start for a named even/odd 15 s UTC period from a
             virtual clock: 500 ms audio delay, late start up to 75 % of the period by
             skipping the elapsed prefix, refusal for an unsynchronized/unknown clock,
             an unaligned period or a stale request, and no catch-up or replay of a
             missed period. Details: WstxTransmit::Ft8Schedule, PlanTransmitStart. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/schedule.rs";
    }
    dependency CL_009_02_to_FR_006 from 'CL-009-02' to 'FR-006';
    dependency CL_009_02_to_FR_005 from 'CL-009-02' to 'FR-005';
    requirement 'CL-009-03' {
        doc /* Manage PTT and transmit audio through the station's one transmit owner and
             its explicit transmit authority: arm only by an explicit operator request
             with a current CL-022 grant and the current safety revision on a profile
             with CAT PTT and an exact output device (receive-only commissioning is not
             authority); disarmed at every start; admit, replace (until audio start) or
             refuse TransmitRequests; key CI-V PTT with readback before audio, play the
             48 kHz waveform from its planned sample, release PTT with readback after the
             last sample; Tune and the Tx watchdog; report every TransmitOutcome. The
             automatic CAT lifecycle never emits PTT. Details: WstxTransmit::
             TransmitAuthority, TransmitArming, TransmitRequest, TransmitOutcome,
             TransmitTiming, TransmitClock, PttControl, AudioPlayback, SetTune,
             TransmitWatchdog, TransmitWire. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/service.rs; server/src/transmit_http.rs; server/src/playback.rs; server/src/radio_control/actor.rs; server/src/radio_control/executor.rs; server/src/radio_control/codec.rs";
    }
    dependency CL_009_03_to_FR_008 from 'CL-009-03' to 'FR-008';
    dependency CL_009_03_to_FR_009 from 'CL-009-03' to 'FR-009';
    dependency CL_009_03_to_FR_002 from 'CL-009-03' to 'FR-002';
    requirement 'CL-009-04' {
        doc /* Provide an immediate Halt that stops audio and releases PTT with readback
             within 250 ms while CAT answers, cancels pending requests and disarms; make
             audio device loss, CAT errors or timeouts, authority changes, an
             unsynchronized clock and late or stale requests release or never key PTT,
             report an unconfirmed release as indeterminate and recover it off-only, and
             never resume or replay a transmission after a restart or reconnect; after a
             boot, a radio found transmitting before the boot ever keyed gets exactly one
             off-only release with readback. Details: WstxTransmit::HaltTransmit,
             TransmitTiming, PttControl, StartupSafetyRelease, TransmitOutcome. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/service.rs; server/src/transmit_http.rs; server/src/radio_control/actor.rs; server/src/radio_control/executor.rs";
    }
    dependency CL_009_04_to_FR_008 from 'CL-009-04' to 'FR-008';
    dependency CL_009_04_to_FR_006 from 'CL-009-04' to 'FR-006';
    requirement 'CL-009-05' {
        doc /* Determine the station clock state for transmit from the station's own SNTP
             measurement, off the transmit and audio threads, at start and every 60 s
             with the servers ch.pool.ntp.org, time.windows.com, pool.ntp.org in that
             order (the next when one does not answer validly within 1.5 s):
             synchronized when the latest measurement is at most 10 min old and its
             |offset| is at most 500 ms, unsynchronized when outside, unknown without a
             recent measurement or when the system clock stepped by more than 100 ms
             since it; report the offset, server and age on GET /transmit and with the
             transmit state in the browser. #43: the profile's clock source (CL-043-01)
             selects the state transmit is admitted by: NTP (default) this SNTP state;
             From the air the AirClock state (synchronized only when the air estimate is
             confident and the applied correction keeps the residual |estimate - applied|
             at most 500 ms; unknown while too few stations are heard, so transmit is
             refused rather than guessed); Both the SNTP state while it is synchronized,
             else the air state (CL-043-03). GET /transmit also reports clock_source and
             clock_warning. Details: WstxTransmit::TransmitClock, AirClock, TransmitWire. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/clock.rs; server/src/transmit/air.rs; server/src/transmit_http.rs; server/src/main.rs; client/recording.js";
    }
    dependency CL_009_05_to_FR_006 from 'CL-009-05' to 'FR-006';

    verification 'TC-005-001' {
        doc /* TC-005-001 — FT8 message, symbol and waveform encoding
             CL-009-01
             Setup: fixtures/transmit/ft8code-vectors.json generated by
             fixtures/transmit/generate.py with WSJT-X 3.3.0-beta5 ft8code.exe
             (ft8code "<message>", tool hashes recorded, beta4 output identical) for 119
             messages covering every supported family and refusal shape, plus two
             zero-noise ft8sim WAVs (ft8sim "<message>" f0 0.0 0 0 1 99).
             Steps: pack and encode each message; generate 12 kHz and 48 kHz waveforms;
             compare to the ft8sim WAVs; decode the waveforms with the receive decoder;
             apply out-of-range frequencies, invalid tones and malformed messages.
             Oracles: ft8code bits, CRC, parity and tones match exactly for every message
             WSJT-X encodes unaltered in a supported family; every other fixture is
             refused; ft8sim within referenceTolerance with the one-sample and 0.01 Hz
             negative controls failing; 48 kHz decimated within rateConsistencyTolerance;
             the receive decoder returns the same payload; refusals are explicit.
             2 — Isolated automated tests; Windows development PC, no audio device, radio
             or WSJT-X installation at test time. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-009-01';
        }
        attribute executable : String = "server/tests/transmit_vectors.rs";
    }
    verification 'TC-006-001' {
        doc /* TC-006-001 — FT8 transmit period scheduling
             CL-009-02
             Setup: virtual UTC clock values around period boundaries, both parities,
             12 kHz and 48 kHz, every clock state.
             Steps: select the next slot and plan starts before the period, at the audio
             delay, late, at the 75 % boundary, after it, in the wrong period, for
             unaligned periods and unsynchronized/unknown clocks.
             Oracles: WSJT-X values (Modulator.cpp delay_ms=500 and late-start m_ic,
             TxStartPolicy.hpp 0.75, mainwindow.cpp even/odd t mod 30 s): exact audio
             start and skipped-sample counts; 11249 ms admitted and 11250 ms stale;
             stale requests never move to a later period.
             2 — Isolated automated tests; Windows development PC, no clock, audio or radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-009-02';
        }
        attribute executable : String = "server/tests/transmit_vectors.rs";
    }
    verification 'TC-006-003' {
        doc /* TC-006-003 — Station SNTP clock measurement
             CL-009-05, CL-009-02
             Setup: hand-computed NTP timestamps; fake SNTP responders on 127.0.0.1
             (silent, kiss-of-death stratum 0, answering a fixed offset ahead of the
             request) with a fake station clock; a scripted blocking measurement
             source; the actual station router with an injected clock monitor.
             Steps: compute offsets and round trips including an NTP era boundary;
             present short, wrong-mode, stratum 0/16, zero-transmit, wrong-origin and
             leap-alarm replies; measure over silent, refusing, answering and later
             servers; a fake station clock stepping +10 s during the exchange; derive
             states at |offset| 500/501 ms, ages 10 min / 10 min + 1 ms and system
             clock steps of +-100/+-101/+-2000 ms after the measurement; plan FT8 and
             FT4 starts with each derived state; read the state while a measurement
             blocks; GET /transmit before and after measurements; the browser transmit
             status with a transmit.state fixture.
             Oracles: RFC 4330/5905 arithmetic by hand (590/20 ms, -705/10 ms, 495/10
             ms); every invalid reply refused, stratum 1 and 15 accepted; servers asked
             once each in order, none after the first valid answer, none answering
             gives no measurement; a step during the exchange leaves the offset at
             3 s (not -2 s); 500 ms synchronized, 501 ms unsynchronized, older than
             10 min unknown, a step above 100 ms unknown; only synchronized admitted (else
             clockNotSynchronized); reading never waits for a measurement; exact
             clock_measurement keys {server,offset_ms,round_trip_ms,age_ms}, null and
             unknown before the first answer; the status reads "clock synchronized
             +12 ms ch.pool.ntp.org 34 s ago".
             2 — Isolated automated tests; Windows development PC, loopback UDP only, no
             public time server, audio or radio; the actual server and Chromium for the
             status line. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-009-05';
            verify 'CL-009-02';
        }
        attribute executable : String = "server/tests/transmit_clock.rs; server/src/transmit_http_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_009_05_verified_by_TC_006_003 from 'CL-009-05' to 'TC-006-003';
    dependency CL_009_02_verified_by_TC_006_003 from 'CL-009-02' to 'TC-006-003';
    dependency CL_009_01_verified_by_TC_005_001 from 'CL-009-01' to 'TC-005-001';
    dependency CL_009_02_verified_by_TC_006_001 from 'CL-009-02' to 'TC-006-001';
    verification 'TC-008-003' {
        doc /* TC-008-003 — Transmit authority, halt and failure handling
             CL-009-03, CL-009-04
             (Planned on issue #9 as TC-008-001; that ID was taken by #10 for the Tx and
             Tune watchdogs, so the #9 halt/failure case is TC-008-003.)
             Setup: the actual transmit owner on a virtual UTC clock with a recording
             hardware double; the actual CI-V actor against an independent emulated
             IC-7300 peer; the actual station router, CL-022 lifecycle and scripted CI-V
             peer; the contact engine against the actual owner core on the virtual
             clock (contact_tests).
             Steps: request while disarmed; arm with unsupported/unavailable capability,
             a wrong safety revision and without a grant; FT8 request before the period,
             late, stale, misaligned, unsynchronized/unknown clock, bad text and offset,
             duplicate sequence; replacement before and after audio start; a request
             for another period while the pending one is keyed before its audio, also
             from the engine stepping between the key and the audio of a late start
             (#10); halt
             mid-audio on the virtual clock, through the owner thread and through the
             real actor; audio device loss, CAT loss, key timeout, output open failure,
             safety revision change; an end report 300/900 ms late and one seen only
             by an owner step after the deadline; a device that stops consuming half
             way (FT8, late FT8, FT4); the render fill decisions against a modelled
             10 ms engine with and without 40 ms render delays (#49); restart; Tx
             watchdog expiry and Tune limit;
             lifecycle polling with the transmit owner present; malformed and extra-key
             wire bodies, wrong Origin, stale boot, retained command_id.
             Oracles: no PTT or audio call/byte while disarmed or unauthorized or
             without an opened output; PTT bytes exactly FE FE 94 E0 1C 00 01 FD and
             1C 00 00 with 1C 00 readback; open before key at the period start, audio at
             period start + 500 ms with skip 0, late skip (t-500 ms)*48; replaced and
             audioStarted outcomes in order; a request for another period while keyed
             before audio is accepted as the next one, plays in its own period after
             the keyed one, never busy, still armed (#10); halt releases within 250 ms
             and disarms;
             every failure stops audio, attempts release and disarms with its cause; a
             late end report inside the bound completes, stays armed and the next
             request plays; a device that never reports the end is released at audio
             end + 1000 ms (FT8 P+14140 <= P+14500, FT4 P+6340 <= P+7000) as
             audioStalled, disarmed deviceLost; the 100 ms buffer starts the program
             within 30 ms and reports the end within 100 ms without underrun; an
             unconfirmed release is indeterminate and recovered off-only; restart is
             disarmed (startup) with nothing pending; watchdog expiry at the configured
             minute; no poll during the transmit hold; one off-only release on close of
             a keyed connection; exact wire shapes and refusals; a radio in TX at boot
             gets exactly one 1C 00 00 then a 1C 00 readback, a radio in RX at boot sees
             zero setter bytes.
             2 — Isolated automated tests; Windows development PC, no audio device,
             radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-009-03';
            verify 'CL-009-04';
        }
        attribute executable : String = "server/tests/transmit_service.rs; server/src/transmit_http_tests.rs; server/src/contact_tests.rs";
    }
    verification 'TC-008-002' {
        doc /* TC-008-002 — Physical controlled FT8 transmit
             CL-009-03, CL-009-04
             Setup: separately approved operation on the HB9BLA IC-7300 (COM3, USB Audio
             CODEC) into a dummy load or the station antenna, RF power set low by the test before the first Tx (CI-V 14 0A, value 0003, with the station stopped and idle, because it holds COM3; read back; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported), profile
             with control.ptt cat and the IC-7300 USB output, system clock
             synchronized by the station's SNTP measurement (CL-009-05), the radio's own transmit time-out timer set
             (mandatory, e.g. 3 min) and read back before any keying.
             Steps: arm, transmit FT8 messages in both parities, replace before audio
             start, halt mid-transmission, Tune and its limit, pull the USB audio or CAT
             cable during a transmission, restart the station.
             Oracles: PSK Reporter spots of HB9BLA for the transmitted CQ by
             independent receivers (frequency, time); the radio's TX indication, power
             meter and ALC follow PTT; halt and
             each failure end RF within the settled bound; restart does not transmit.
             5 — Tests with external effects and explicit operator consent; HB9BLA radio
             PC, physical IC-7300. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-009-03';
            verify 'CL-009-04';
        }
    }
    dependency CL_009_03_verified_by_TC_008_003 from 'CL-009-03' to 'TC-008-003';
    dependency CL_009_04_verified_by_TC_008_003 from 'CL-009-04' to 'TC-008-003';
    dependency CL_009_03_verified_by_TC_008_002 from 'CL-009-03' to 'TC-008-002';
    dependency CL_009_04_verified_by_TC_008_002 from 'CL-009-04' to 'TC-008-002';
    // #11 FT4 transmit preparation (slice A); detailed contract in WstxTransmit.
    requirement 'CL-011-01' {
        doc /* Encode every supported message family for FT4 with the shared FT8 packer
             (same 77 bits and refusals), scramble with the WSJT-X rvec, add CRC-14 and
             LDPC(174,91) parity and map to the 103 genft4 tones; generate the native
             WSJT-X FT4 transmit waveform (gen_ft4wave convention, 105 symbols with
             ramps, 60480 samples at 12 kHz and 241920 at 48 kHz) within the declared
             ft4sim tolerance; plan FT4 starts for named even/odd 7.5 s UTC periods
             with the 300 ms audio delay and the FT8 refusals; a start is stale from
             the earlier of 75 % of the period and the end of the waveform's audio
             (5340 ms), deliberately not WSJT-X's fTR < 0.75 empty-start quirk.
             The mode is explicit per request and FT8 behaviour is unchanged.
             Mode selection and QSO/log rules are CL-011-02..04.
             Details: WstxTransmit::Ft4ChannelFrame, Ft4WaveformContract, Ft4Schedule,
             PlanTransmitStart. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/mod.rs; server/src/transmit/waveform.rs; server/src/transmit/schedule.rs";
    }
    dependency CL_011_01_to_FR_005 from 'CL-011-01' to 'FR-005';
    dependency CL_011_01_to_FR_006 from 'CL-011-01' to 'FR-006';
    verification 'TC-005-002' {
        doc /* TC-005-002 — FT4 message, symbol and waveform encoding
             CL-011-01
             Setup: fixtures/transmit/ft4/ft4sim-vectors.json generated by
             fixtures/transmit/generate.py --ft4sim with the WSJT-X 3.3.0-beta5 utilities
             ft4sim.exe (ft4sim "<message>" 1500.0 0.0 0 0 1 99, hash recorded) for 122
             messages (the FT8 fixture messages plus an FT4 exchange): payload bits,
             codeword read back from the printed tones, 103 tones; payload bits
             identical to ft8code for every shared unaltered message; two zero-noise
             ft4sim WAVs (f0 1500 and 637.5 Hz).
             Steps: encode each message for FT4; generate 12 kHz and 48 kHz waveforms;
             compare with the in-phase (analytic-signal) component of the ft4sim WAVs;
             decode the waveforms with the receive FT4 decoder; apply out-of-range
             frequencies and invalid tones.
             Oracles: bits, codeword and tones match exactly for every message ft4sim
             encodes unaltered in a supported family, every other fixture is refused;
             waveform within Ft4WaveformContract::referenceTolerance with the one-sample
             shift, 0.01 Hz and one-sample-late ramp controls failing; 241920 samples at
             48 kHz, decimated within rateConsistencyTolerance; the receive decoder
             returns the same payload at the placed frequency and start.
             2 — Isolated automated tests; Windows development PC, no audio device, radio
             or WSJT-X installation at test time. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-011-01';
        }
        attribute executable : String = "server/tests/transmit_ft4_vectors.rs";
    }
    verification 'TC-006-002' {
        doc /* TC-006-002 — FT4 timing and mode changes
             CL-011-01 (FT4 period timing), CL-011-02 (mid-workflow mode selection)
             Setup: virtual UTC clock values around 7.5 s boundaries, both parities,
             12 kHz and 48 kHz, every clock state, FT8 requests at the same instants;
             for CL-011-02 the actual router with the contact engine and the actual #9
             transmit owner on a hardware double, live FT4/FT8 jobs with hand-authored
             rows.
             Steps: select the next FT4 slot and plan starts before the period, at the
             300 ms delay, late, at the 75 % boundary, after it, for unaligned periods,
             FT4-only boundaries requested as FT8, and unsynchronized/unknown clocks.
             CL-011-02: with an FT4 live job read station.tick and prepare a manual
             entry; request an operating selection with action mode while Tune is on,
             while PTT is keyed before the audio, while the FT4 waveform plays, and after
             Tune ends; stop FT4 receive with an active FT4 contact.
             CL-011-02 oracles (WstxContact::StationOperatingMode, ModeChange):
             station.tick period_ms 7500 in FT4 and 15000 in FT8; the manual contact
             uses FT4 (Tx4 RR73); the mode selection while Tune is on, PTT keyed or
             transmitting is 409 busy and nothing changes (operating revision, receive
             mode ft4); after Tune it is not refused busy; after the receive stop the
             period stays 7500 and the FT4 contact stays replying with K1ABC.
             Oracles: WSJT-X values (Modulator.cpp FT4 delay_ms=300 and late-start m_ic,
             TxStartPolicy.hpp 0.75, mainwindow.cpp m_TRperiod=7.5 and t mod 15 s
             parity): exact audio start and skipped samples. Deliberately not WSJT-X's
             fTR < 0.75 empty start: 5339 ms admitted (skip below the waveform's sample
             count), 5340 ms and 5624 ms stale at 12 kHz and 48 kHz, also for the next
             slot; FT8 keeps 15 s periods, 500 ms delay and its 11.25 s limit.
             2 — Isolated automated tests; Windows development PC, no clock, audio or radio. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-011-01';
            verify 'CL-011-02';
        }
        attribute executable : String = "server/tests/transmit_ft4_vectors.rs; server/src/contact_http_tests.rs";
    }
    dependency CL_011_01_verified_by_TC_005_002 from 'CL-011-01' to 'TC-005-002';
    dependency CL_011_01_verified_by_TC_006_002 from 'CL-011-01' to 'TC-006-002';
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
    requirement 'CL-011-03' {
        doc /* Complete and log FT4 contacts through the common contact engine with the
             FT4 rules: the contact's mode fixed at preparation and carried in every
             TransmitRequest (7.5 s periods, t mod 15 s parity, 300 ms audio delay and
             the FT4 waveform through the #9 owner), Tx4 always RR73, Tx offset
             200..2916 Hz, TIME_ON one 7.5 s period before the first Tx3, log MODE MFSK
             SUBMODE FT4 and worked-before by effective mode FT4; only rows of the
             contact's mode count. Details: WstxContact::ContactMode, FT4-NOTE rules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/logbook.rs";
    }
    dependency CL_011_03_to_FR_007 from 'CL-011-03' to 'FR-007';
    dependency CL_011_03_to_FR_011 from 'CL-011-03' to 'FR-011';
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
    dependency CL_011_03_verified_by_TC_007_008 from 'CL-011-03' to 'TC-007-008';
    dependency CL_011_04_verified_by_TC_007_008 from 'CL-011-04' to 'TC-007-008';
    dependency CL_008_07_to_FR_019 from 'CL-008-07' to 'FR-019';
    dependency CL_008_07_to_FR_021 from 'CL-008-07' to 'FR-021';
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
        attribute executable : String = "server/tests/audio_contract.rs; server/tests/audio_receive.rs; server/tests/receive_integration.rs; server/tests/source_contract.rs";
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
    verification 'TC-009-002' {
        doc /* TC-009-002 — Controlled IC-7300 receive station
             CL-008-02, CL-008-04, CL-008-05, CL-008-07
             On the designated Windows IC-7300 PC, verify receive inhibit/keying settings, selected USB input and COM3 identity; inspect readback against radio indications, capture known on-air/reference receive signals, restore original receive settings. Compare decoded payloads with simultaneous reference receive observations.
             Correct physical input/port, no transmission, authoritative CAT observations, visible live spectrum/decodes and independent source timing/error records. Loss/reconnect and clock-quality labels agree with actual state. Reference counts alone are not exhaustive decoder truth.
             4 — Controlled live tests; HB9BLA radio PC and development browser, physical IC-7300, operator-authorized receive-only setup. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-008-02';
            verify 'CL-008-04';
            verify 'CL-008-05';
            verify 'CL-008-07';
        }
        attribute executable : String = "server/tests/radio_hardware.rs";
        attribute method : String = "manual";
    }
    verification 'TC-002-003' {
        doc /* TC-002-003 — Audio without CAT
             CL-008-02, CL-008-05
             Stream known packets with CAT disabled/unavailable and inject audio loss; exercise live spectrum and decoder fixture consumer.
             Correct samples/spectrum/results without any CAT bytes; own errors/reopen/epochs visible; engine glitches keep job/generation; GET /receive audio.loss_epochs counts unknown-loss rotations only and audio.last_loss names the latest trigger (null iff0); no default-device substitution or audio archiving.
             2 — Isolated automated tests; Windows PC, actual receive service and independent device/control fixtures. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-008-02';
            verify 'CL-008-05';
        }
        attribute executable : String = "server/tests/audio_contract.rs; server/tests/audio_receive.rs";
    }
    verification 'TC-009-003' {
        doc /* TC-009-003 — Control without audio
             CL-008-05, CL-008-06
             Exercise every supported query and receive setter while audio is closed/unavailable.
             Exact control/status and capability failures without activating any audio endpoint; catalogue cannot enable raw/TX operations.
             2 — Isolated automated tests; Windows PC, actual Rust control module and serial emulator. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-008-05';
            verify 'CL-008-06';
        }
        attribute executable : String = "server/tests/radio_control.rs";
    }
    verification 'TC-009-004' {
        doc /* TC-009-004 — Independent failure and shared worker
             CL-008-03, CL-008-05, CL-010-05, CL-010-07, CL-010-08
             Lose either interface, overrun/stop/reopen capture, stall CAT and combine native48k conversion, display and bounded decoder quanta for four profiles; seed live result counters2047/2048/2049, eviction/cursor and safe-integer boundaries; simulate later TX/halt ownership. Hold and release result-page/snapshot responses across a confirmed cancellation and unknown Start outcome; inject a current live frame while the recorded-input job is null.
             Independent availability, no false ready state, no cross-profile samples/results, conversion service<=50ms quanta and native-to-canonical software backlog<=200ms under the declared workload, <=250ms normal cancel, <=2s status (no 32 kbit/s link scenario, #80); failed close retains ownership. No real RF transmission. Delayed pages preserve newer confirmed lifecycle/error state and do not advance cursors; pre-mutation reads cannot clear the unknown-outcome control barrier, while a later explicit reconciliation can. Live progress updates only its matching live owner, with no exception or false disconnection when the recorded-input job is absent.
             2 — Isolated automated tests; Windows PC, actual services/browser/link model, independently scripted device/control and decoder-step fixtures. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-008-03';
            verify 'CL-008-05';
            verify 'CL-010-05';
            verify 'CL-010-07';
            verify 'CL-010-08';
        }
        attribute executable : String = "tests/receive-integration.test.cjs; tests/ui-operating.test.cjs; server/tests/audio_receive.rs; server/tests/radio_control.rs; server/tests/source_contract.rs; server/src/receive_http_tests.rs; server/src/recording_tests.rs";
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
    requirement 'CL-010-16' {
        doc /* Present the laptop operating screen of WstxOperatingLayout::OperatingScreen: a top bar with only band, mode, dial, UTC/period, Logbook, Settings, HALT and Abort QSO (Esc); the full-width waterfall with the Rx/Tx strip; Band Activity with the strategy element and the QSO pane with direct buttons and no Enable Tx control; setup and diagnostics in the four-section Settings drawer; themes; WSJT-X keyboard shortcuts; and only the token form for an unauthorized browser. Details: OperatingScreen, RxTxStrip, BandActivityView, QsoPane, SettingsDrawer, ThemeChoice, UnauthorizedView, KeyboardShortcuts, WstxContact::SetEnableTx. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/recording.css; client/contact.js; client/logbook.js";
    }
    dependency CL_010_16_to_FR_010 from 'CL-010-16' to 'FR-010';
    dependency CL_010_16_to_FR_019 from 'CL-010-16' to 'FR-019';
    dependency CL_010_16_to_FR_021 from 'CL-010-16' to 'FR-021';
    requirement 'CL-010-08' {
        doc /* Preserve keyboard and narrow-screen operation, literal field rendering and existing signal/status transport contracts. Secondary in-page regions keep the persistent station bar and disabled Halt Tx accessible. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/index.html; client/recording.js; client/recording.css; server/src/recording.rs";
    }
    dependency CL_010_08_to_FR_019 from 'CL-010-08' to 'FR-019';
    dependency CL_010_08_to_FR_021 from 'CL-010-08' to 'FR-021';
    // #10 standard FT8 contact (decisions: issue #10 comment 6539901776, 2026-10-31);
    // detailed contract in WstxContact. FT4 rules marked FT4-NOTE there belong to #11.
    requirement 'CL-010-01' {
        doc /* Prepare a contact only from an acknowledged decoded row identity or an operator-entered DX Call/Grid that packs as a standard message; preparation sets partner, grid, report, Rx/Tx offsets, period parity and the six standard messages, and never arms or starts transmission; a receive-only station can prepare contacts and log. Details: WstxContact::SelectDecodedRow, EnterDxStation, FirstSlotOnSelection, ChangeContact. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/main.rs; client/contact.js";
    }
    dependency CL_010_01_to_FR_007 from 'CL-010-01' to 'FR-007';
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
    // CL-010-04: ExportAdi is streamed (#10, 2026-11-04). #41 retired the #10 log review queue: completion and
    // Log QSO log directly (WstxContact::DirectLog); TIME_ON/TIME_OFF come from the
    // contact engine (server/src/contact.rs).
    // #10 closing reconcile (2026-11-08): CL-010-03 implemented; TC-007-007 was accepted by the
    // operator through the live QSOs (#10 comment 6718939269) and stays automation planned, as a
    // manual live case has no executable binding. MCP exposes the same contact operations
    // through WstxMcp (#12). CL-010-11 and TC-010-008 implemented: the #50 pointer actions (click Tx,
    // double-click Rx and Tx, dragging the lines and strip fields) were accepted live
    // (#50 comment 6719539569); since #37 the browser sends no re-decode, the wire
    // redecode stays refused redecode_unavailable.
    // CL-010-15 implemented (operator 2026-11-08): the Thin/Off byte budget is the browsers'
    // (StationTickEvent), a target judged from the link byte log since #80 (CL-003-05,
    // TC-080-001); MCP traffic is outside that budget.
    requirement 'CL-010-04' {
        doc /* Log every completed contact directly, without a review step (#41, as WSJT-X): at completion and on a manual Log QSO the server stores the contact's record in the profile directory's ADIF 3.1.8 contacts.adi with its contact identity and sends it to the WSJT-X UDP targets as QSO Logged and Logged ADIF; exactly one record per contact identity (an identical re-log adds nothing, completion after an early Log QSO replaces it; each contact is sent to the UDP targets once), a later contact with the same station a new record, Saved only after durable acknowledgement, a failed write visibly unsaved and retried; ADI export and history with the stated limits; and (#10, operator 2026-11-03) Update logbook from ADIF, the one ADI import: an export of another logger (for example Log4OM) is consolidated into the contact log, repeatable and incremental, a record already present (same contact identity, or same call, band and mode/submode with a start within 2 minutes) adding nothing and the stored record winning, only the log's own fields kept, added records marked with their source, QSO confirmation status (LoTW, QSL and eQSL received with their dates and via) kept and, on a rerun, upgraded on records already present (a confirmation is only added, never removed; #10, operator 2026-11-04), so worked-before and award queries tell worked from confirmed per entity, band and mode, invalid records skipped and invalid optional fields dropped with their reasons in the summary, nothing sent to the UDP targets or elsewhere, and the added records feeding worked-before, DXCC and grid status. The former log review queue (OfferLogReview, discard_review, the review form) is retired. Details: WstxContact::LogRecord, DirectLog, SaveContact, UpdateLogbook, ExportAdi, ContactHistory, AdiLimits, WorkedBeforeQuery; WstxUdp::OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/logbook.rs; server/src/logbook_http.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/main.rs; client/logbook.js; client/contact.js";
    }
    dependency CL_010_04_to_FR_011 from 'CL-010-04' to 'FR-011';
    requirement 'CL-010-15' {
        doc /* Expose the contact operations only through the versioned WstxContact wire contract: exact routes, keys and byte caps, command_id idempotency, contact_revision, the ContactRefusal codes, the contact.state and station.tick events, and the stated Thin/Off byte budget, leaving StatusReply and the compressed-route allowlist unchanged. Details: WstxContact::ContactWire, ContactCommand, CommandReceipt, ContactSnapshot, ContactStateEvent, StationTickEvent. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact_http.rs; server/src/logbook_http.rs; server/src/main.rs";
    }
    dependency CL_010_15_to_FR_019 from 'CL-010-15' to 'FR-019';
    dependency CL_010_15_to_FR_021 from 'CL-010-15' to 'FR-021';
    requirement 'CL-010-06' {
        doc /* Present bounded Band Activity and, since #37, the compact QSO pane (WstxOperatingLayout::QsoPane: the running QSO's last partner message, its QSO dialogue and, below it, at most eight stations calling my call with time and SNR: during a QSO those within +/-50 Hz of my Rx or Tx offset, otherwise every caller, #37) in place of the Rx Frequency pane; local filtering, sorting, highlighting and clearing change no server decoding, contact state or log. Details: WstxOperatingLayout::QsoPane, QsoPaneCrowding. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.js";
    }
    dependency CL_010_06_to_FR_004 from 'CL-010-06' to 'FR-004';
    dependency CL_010_06_to_FR_007 from 'CL-010-06' to 'FR-007';
    dependency CL_010_06_to_FR_021 from 'CL-010-06' to 'FR-021';
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
    requirement 'CL-010-12' {
        doc /* Generate the WSJT-X standard messages Tx1 grid, Tx2 report, Tx3 R+report, Tx4 RRR or RR73, Tx5 73 and Tx6 CQ on the server with the -50..+49 report rendering, operator report override, Tx1 skip and the RRR/RR73 toggle (FT8 default RRR); Now buttons and F11/F12 steps are not offered. Details: WstxContact::StandardMessageSet, ReportRange, OverrideReport, ToggleTx1Skip, ToggleTx4Form. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; client/contact.js";
    }
    dependency CL_010_12_to_FR_005 from 'CL-010-12' to 'FR-005';
    dependency CL_010_12_to_FR_007 from 'CL-010-12' to 'FR-007';
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

    verification 'TC-007-001' {
        doc /* TC-007-001 — Standard FT8 contact
             CL-010-01, CL-010-02, CL-010-03, CL-010-12
             Setup: actual candidate server and Chromium; profile HB9BLA/JN47; virtual UTC clock; independently scripted decoded-result source and a #9 transmit-service double that records TransmitRequests and returns started/completed/halted/refused outcomes (no audio, PTT or radio).
             Steps: (a) responder: select a hand-authored "CQ K1ABC FN42" row (SNR -12.4, 1234.6 Hz, even period); Enable Tx; feed "HB9BLA K1ABC -05", then "HB9BLA K1ABC RR73"; (b) responder with RRR: feed "HB9BLA K1ABC RRR", then nothing; (c) caller: Enable Tx with no partner (Tx6, state calling), feed "HB9BLA K1ABC FN42" and select that row (prepareReply with firstSlot tx2), feed "HB9BLA K1ABC R-07", once with Tx4 RRR then "HB9BLA K1ABC 73", once toggled to RR73; (d) repeats: partner repeats each message one to three times; partner misses my Tx3 and resends its report from rogers; (e) other stations and late rows: "HB9BLA W1XYZ -10" during the contact, a row of the previous partner after ChangeContact, a reply after completion; (f) Tx1 skip, report override -50/+49/-51/+50, manual entry "DL1ABC" grid JO62 and invalid "AB1", "<...>" and grid "SS00"; (g) partner answers another call at 50 Hz and at 51 Hz from my Tx offset, in replying and again in report after a Tx1-skipped start; the watchdog expires while calling CQ; (h) Auto Seq off; Esc, Halt, disarm and cancel in every state.
             Expected (independent hand-written table, not candidate output): selection gives dxCall K1ABC, grid FN42, report -12 rendered "-12", Rx and Tx 1235 Hz, odd parity, next Tx1 "K1ABC HB9BLA JN47", Tx2 "K1ABC HB9BLA -12", Tx3 "K1ABC HB9BLA R-12", Tx4 "K1ABC HB9BLA RRR", Tx5 "K1ABC HB9BLA 73", Tx6 "CQ HB9BLA JN47" and no TransmitRequest before Enable Tx. States/next slots follow WstxContact::AutoSequence exactly: (a) replying/Tx1 -> rogerReport/Tx3 -> signoff/Tx5 -> completed after the completed Tx5 outcome, Enable Tx off, one log offer; (b) RRR from the partner gives signoff/Tx5; the contact completes after the first completed Tx5 transmission (AutoSequence sent73), Enable Tx off, one log offer; (c) calling/Tx6 -> report/Tx2 only after selection -> rogers/Tx4 -> completed on 73 (RRR) or on the completed RR73 transmission, Enable Tx off and no further CQ; (d) repeats resend the same text, report-from-rogers returns to Tx3, no second completion or log offer; (e) other/late rows change nothing; (f) with Tx1 skip, selecting the CQ row enters report directly with next Tx2, overrides -50/+49 accepted and rendered "-50"/"+49", -51/+50 and invalid entries refused with no contact; (g) 50 Hz disarms in replying and in the Tx1-skipped report, 51 Hz does not; watchdog expiry while calling returns to idle; (h) Auto Seq off never changes the next slot; Halt and Alt+H send the halt request first; Esc sends one abort and no halt; last transmitted text changes only on started outcomes and differs visibly from the next message. Each request carries a fresh requestSequence; a duplicated browser action (same command_id) yields one request; one decoded row delivered twice counts once.
             2 — Isolated automated functional tests; Windows development PC, actual candidate server and browser, independent decoded-row and transmit-outcome fixtures; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-01';
            verify 'CL-010-02';
            verify 'CL-010-03';
            verify 'CL-010-12';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; tests/contact.test.cjs";
    }
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
             Expected (independent operation/state catalogue): Alt+H and Halt reach the #9 halt operation first even with panels open (exactly one halt per Alt+H); Esc sends exactly one ContactCommand abort and no halt, stops the transmission now (PTT released, outcome aborted, halt_state unchanged), cancels the contact with nothing logged and leaves the station ready for the next QSO; Cancel lets a transmission on the air finish; the partner-works-other stop releases PTT without a halt; Esc closes no panel; state shows pending/unknown until #9 confirms; reconnect loads the snapshot and replays no arm, tune, next-message or transmit request; no request reaches PTT except through the transmit-service double; unsupported transmit leaves Enable Tx/Tune disabled with a reason; 200 and 2950 accepted, 199/2951 refused; barrier refusals unchanged; no cross-profile contact. Each malformed command returns the independently expected ContactRefusal code and field with no state change; stale revisions refused except cancel/abort/disarm; an identical retained command_id returns the same receipt with no second effect, a different body state_conflict; the maximum snapshot is exactly admitted and GET /contact is never gzip-coded; StatusReply keeps exactly {version,radio}; on the receive-only station Alt+H sends no halt, while row selection and Log QSO still work.
             2 — Isolated automated functional tests; Windows development PC, actual candidate server/browser and independent control, audio and transmit emulators. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-02';
            verify 'CL-010-03';
            verify 'CL-010-07';
            verify 'CL-010-08';
            verify 'CL-010-15';
        }
        attribute executable : String = "server/src/contact_http_tests.rs; tests/contact.test.cjs; tests/ui-operating.test.cjs";
    }
    verification 'TC-007-005' {
        doc /* TC-007-005 — Pushed contact, transmit and receive state without polling
             CL-010-15
             #80 (operator 2026-11-09): the two-browser 32 kbit/s link workload is retired; the link budgets are targets judged from the link byte log (CL-003-05, TC-080-001). What remains are the unshaped pushed-state cases (WstxStationProtocol::PushedStationState).
             Setup: actual candidate server and Chromium on an unshaped local connection, the contact engine and #9 transmit owner on the recording hardware double, hand-authored result rows published by a test-only control peer, a request recorder.
             Steps: another client changes the contact and the transmit state; an own contact command, a command right after another, a stale safety revision, Esc and CQ during unanswered commands; an older GET /contact held across events; contact.js loaded after the socket's first event; a running Tune on Thin and on Detailed; receive.state with a job, audio and a refused event; contact.state carrying a contact and its dialogue rows.
             Expected: transmit.state and contact.state carry all fields first and then only what changed, shown with no GET /transmit and no GET /contact; an own command reads no GET /contact and a refusal shows its code; the next command goes with the receipt's revision; a stale safety revision is read at once and the CQ retried; nothing queued follows an abort; an older read never replaces a pushed change; a contact client loading after the first event has the state without a read; a Tune countdown alone at most once per 5 s below Detailed; receive.state carries the job and the audio, read again only for a new state, a refused event or a failed read; dialogue rows in order including a continuation at the same sequence.
             2 — Isolated automated functional tests; Windows development PC, real browser/server, no link simulator; no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/contact.test.cjs; server/src/contact_http_tests.rs; server/src/receive_http_tests.rs; tests/ui-operating.test.cjs";
        objective {
            verify 'CL-010-15';
        }
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
        attribute executable : String = "server/src/contact_tests.rs";
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
    verification 'TC-011-001' {
        doc /* TC-011-001 — Direct logging, exactly once per contact
             CL-010-04
             Setup: actual server/browser, disposable profile directories, a UDP target socket bound on 127.0.0.1, independent failure injection (failed write, failed atomic replace), contacts with known identities and fields, transmit double.
             Steps: complete a contact (transmitted Tx5 73 after the partner's report; received 73 in rogers); repeat the completion events; manual Log QSO before completion, then the partner's later messages; Log QSO again unchanged; storage failure at completion, then recovery; restart; the same call again as a new contact; SaveContact with power 10 and comment, invalid power -1, comment with CR/LF or 1025 characters, repeat save; second profile; the browser Log QSO button.
             Expected (independent record catalogue and direct file reading): each completion stores exactly one record with the hand-computed CALL, GRIDSQUARE, MODE/SUBMODE, RST_SENT/RST_RCVD, QSO_DATE/TIME_ON (first transmitted Tx2/Tx3 rule), TIME_OFF, BAND, FREQ = dial + Tx offset, STATION_CALLSIGN and MY_GRIDSQUARE, and the UDP target receives one QSO Logged and one Logged ADIF for it; repeated completion and an unchanged Log QSO add no record and no datagram; an early Log QSO closes the contact (completed, Enable Tx off, nothing queued), so the partner's later messages neither replace its record nor send a second datagram pair (#37); Log QSO of a completed contact keeps its completion record even after a location change; a due retry stores the record in the contact step and the datagrams follow; a failed write leaves the record unsaved with storage_unavailable shown and is stored by the retry; nothing is logged again after restart; the second contact with the same call is a separate record; SaveContact identical resave alreadySaved, changed resave conflict, invalid fields refused; the browser shows no review form and sends no POST /contacts; no cross-profile record or browser-clock time.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-04';
        }
        attribute executable : String = "server/src/logbook_tests.rs; server/src/logbook_http_tests.rs; server/src/contact_tests.rs; server/src/contact_http_tests.rs; tests/contact.test.cjs; tests/ui-operating.test.cjs";
    }
    verification 'TC-011-002' {
        doc /* TC-011-002 — ADI interchange, Update logbook from ADIF and boundaries
             CL-010-04
             Setup: hand-authored ADIF ADI fixtures across line/tag/record boundaries and case variations with CALL, GRIDSQUARE, MODE, RST_SENT, RST_RCVD, QSO_DATE, TIME_ON, QSO_DATE_OFF, TIME_OFF, BAND, FREQ, STATION_CALLSIGN, MY_GRIDSQUARE, TX_PWR, COMMENT and APP_WSTXRUST_CONTACT_ID; the confirmation fields LOTW_QSL_RCVD, LOTW_QSLRDATE, QSL_RCVD, QSLRDATE, QSL_RCVD_VIA, EQSL_QSL_RCVD, EQSL_QSLRDATE with valid, invalid (X, a bad date, an unknown via) and QSL_SENT values, a rerun that confirms (N, R, I, absent to Y/V) and one that says N for a confirmed record, a stored log with repeated or invalid verbatim QSL fields; a synthetic export shaped like Log4OM 2 (UTF-8 byte order mark, '#' banner lines, ADIF_VER 3.1.0, PROGRAMID LOG4OM2, non-ASCII NAME/ADDRESS values with LEN in characters, about 60 fields per record, MODE MFSK SUBMODE FT4 and MODE FT4, SSB with SUBMODE LSB/USB, records without FREQ or DXCC); a station log with its own records; records within and beyond 120 s of a stored one (same call, band and effective mode; another band; another mode), a stored contact id with differing fields, two copies in one file; invalid required fields (no CALL, bad QSO_DATE), invalid optional fields (a 5-character GRIDSQUARE, FREQ -1, a non-ASCII COMMENT); malformed lengths and tags, unsupported characters between fields, exactly 64 MiB/100,000 records/1024-character field and each one over, a wrong sha256; a UDP target socket.
             Steps: update the logbook, update again with the same file and with a grown file, retry the same import_id with identical and different total/sha256, export, reopen, page history at cursor 0, total-1 and total with limit 1/10/11; in the browser pick the file in Settings > Logging & Reporting and press Update logbook.
             Expected (independent ADI parser and hand-counted catalogue): the independently counted added/already present/skipped numbers with the skip reasons {code,field} and dropped fields; the stored station records unchanged byte for byte (existing wins) except an upgraded confirmation: a rerun sets Y/V with its date and via on present records (also records added earlier from the same file), never downgrades or removes one, changes no other stored field, and a repeat writes nothing; DirectLog replacing a record keeps its confirmation and SaveContact of it stays already saved; invalid confirmation values are dropped with their reason and QSL_SENT is not stored; the worked set answers worked vs confirmed per DXCC entity, entity x band and entity x band x mode (needed = not worked or not confirmed) and is rebuilt after an upgrade; a rerun of 27,000 QSOs all confirmed upgrades all of them within seconds; a stored log with repeated or invalid verbatim QSL fields stays readable; a record within 120 s of a stored one with the same call, band and effective mode present, one beyond or on another band or mode added; MFSK/FT4 and FT4 consolidated as one mode; added records carry APP_WSTXRUST_SOURCE LOG4OM2 and a new contact id and only the kept fields (no NAME, ADDRESS, EMAIL or other field stored); a second update adds nothing, a grown file only its new records; a structural fault or over-limit input publishes zero records with record/field context; same import_id retry has no second effect, different values state_conflict; no datagram reaches the UDP target; the added calls and grids answer worked-before; history pages hold stable indexes, limit 11 refused, at most 16384 bytes; export then update adds nothing; the browser shows "Logbook updated: N added, M already present (C confirmations updated), K skipped" with the reasons, and "Logbook not updated" for a refused file.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-04';
        }
        attribute executable : String = "server/src/logbook_tests.rs; server/src/logbook_http_tests.rs; tests/ui-operating.test.cjs";
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
    dependency CL_010_01_verified_by_TC_007_001 from 'CL-010-01' to 'TC-007-001';
    dependency CL_010_01_verified_by_TC_007_003 from 'CL-010-01' to 'TC-007-003';
    dependency CL_010_01_verified_by_TC_007_007 from 'CL-010-01' to 'TC-007-007';
    dependency CL_010_02_verified_by_TC_007_001 from 'CL-010-02' to 'TC-007-001';
    dependency CL_010_02_verified_by_TC_007_004 from 'CL-010-02' to 'TC-007-004';
    dependency CL_010_02_verified_by_TC_007_007 from 'CL-010-02' to 'TC-007-007';
    dependency CL_010_02_verified_by_TC_007_010 from 'CL-010-02' to 'TC-007-010';
    dependency CL_010_03_verified_by_TC_007_001 from 'CL-010-03' to 'TC-007-001';
    dependency CL_010_03_verified_by_TC_007_004 from 'CL-010-03' to 'TC-007-004';
    dependency CL_010_03_verified_by_TC_007_007 from 'CL-010-03' to 'TC-007-007';
    dependency CL_010_04_verified_by_TC_011_001 from 'CL-010-04' to 'TC-011-001';
    dependency CL_010_04_verified_by_TC_011_002 from 'CL-010-04' to 'TC-011-002';
    dependency CL_010_04_verified_by_TC_007_007 from 'CL-010-04' to 'TC-007-007';
    dependency CL_010_06_verified_by_TC_007_003 from 'CL-010-06' to 'TC-007-003';
    dependency CL_010_07_verified_by_TC_007_004 from 'CL-010-07' to 'TC-007-004';
    dependency CL_010_08_verified_by_TC_007_004 from 'CL-010-08' to 'TC-007-004';
    dependency CL_010_10_verified_by_TC_008_001 from 'CL-010-10' to 'TC-008-001';
    dependency CL_010_10_verified_by_TC_007_007 from 'CL-010-10' to 'TC-007-007';
    dependency CL_010_11_verified_by_TC_010_008 from 'CL-010-11' to 'TC-010-008';
    dependency CL_010_12_verified_by_TC_007_001 from 'CL-010-12' to 'TC-007-001';
    dependency CL_010_13_verified_by_TC_011_003 from 'CL-010-13' to 'TC-011-003';
    dependency CL_010_14_verified_by_TC_010_009 from 'CL-010-14' to 'TC-010-009';
    dependency CL_010_15_verified_by_TC_007_004 from 'CL-010-15' to 'TC-007-004';
    dependency CL_010_15_verified_by_TC_007_005 from 'CL-010-15' to 'TC-007-005';
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
             **Executable trace:** [communication.test.cjs](../../tests/communication.test.cjs),
             `TC-021-005: actual-server correlation, negative cases and size boundaries`;
             [protocol_tests.rs](../../server/src/protocol_tests.rs),
             `protocol_returns_specified_response_and_errors`. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-003-02';
            verify 'CL-003-03';
        }
        attribute executable : String = "tests/communication.test.cjs; server/src/protocol_tests.rs";
    }
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
             [communication.test.cjs](../../tests/communication.test.cjs),
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
                [liveness contract](StationProtocol.sysml).
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
    verification 'TC-080-001' {
        doc /* TC-080-001 — Link byte log
             CL-003-05
             Setup: the actual router in the test process on a selected HTTPS profile with a disposable directory, one enrolled browser grant and one MCP client; the log's period clock and the operating mode are driven by the test; raw test peers hold their own TCP sockets, count every TCP byte they write and read, run their TLS client on top, write and read HTTP/1.1 text and WebSocket frames themselves, and one peer speaks HTTP/2; each step waits until its exchanges are complete before the period clock moves.
             Steps: (a) FT8: in one period the browser's socket subscribes Thin and sends station.get three times; on the browser's credentialed connection GET /profile, POST /authorization/v1/status and POST /receive/select with a malformed body (refused 400); the MCP client makes one tools/call; the period ends. (b) A second socket of the same grant on Off in the next period. (c) FT4: two 7.5 s periods. (d) A mode change FT8 to FT4 at 5.2 s into a period. (e) No mode selected. (f) A TLS connection without credentials: GET / and a request refused 401. (g) The browser's GET /profile over HTTP/2. (h) Lines written past the rotation size. (i) A plaintext loopback profile.
             Expected (WstxStationProtocol::LinkTrafficLog): one JSON line per client with traffic at each period end, none for a client without traffic. bytes each way equals the TCP bytes the client's peers wrote and read in that period. Each type's count and bytes equal the peers' own counts by the log's rule: WebSocket frames header plus payload (mask included from the client); HTTP the request as written (request line, header fields, body) and the response as received minus the fields the HTTP server adds itself (date, and the content-length or transfer-encoding these routes leave unset) and minus chunk framing, re-serialized as HTTP/1.1 text; the same reconstruction for the HTTP/2 exchange. other = bytes - sum of types. estimate equals the hand calculation of the log's formula. The refused POST /receive/select is on the browser's line; the MCP client has its own line and the browser line holds no MCP bytes; (f) is on a local line on TLS. display lists each socket's profile (thin, then thin and off). FT4 lines are 7500 ms apart; the mode change gives (start, 5200, FT8), (change, until the next FT4 start, FT4), then 7500 ms FT4 lines; with no mode the lines say mode none and are 15000 ms apart. No line holds a cookie, token or proof. The file moves to link-traffic.1.log at its rotation size, replacing the older one. Nothing of the log reaches a socket or response. On the plaintext profile t is 0 and the client is local.
             2 — Isolated automated functional test; Windows development PC; no browser, link simulator or radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-003-05';
        }
        attribute executable : String = "server/src/link_log_tests.rs";
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
             [communication.test.cjs](../../tests/communication.test.cjs),
             `TC-021-009: TLS login, unauthorized/origin denial, plaintext refusal`. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-003-07';
            verify 'FR-021';
        }
        attribute executable : String = "tests/communication.test.cjs";
    }
    verification 'TC-022-001' {
        doc /* #### TC-022-001 — Variable independent servers and browser windows

             **Promises:** FR-001, FR-019, FR-021, FR-022; CL-005-01, CL-005-02, CL-005-03,
             CL-005-05. **Level:** 2 — isolated automated tests.
             **Where:** Windows PC, N real server processes and separate real browser windows.

             **Setup partition:** Operational browser windows and save/readiness regressions
             use four saved HTTPS localhost endpoints and legitimate selected grants in one
             browser context, per WstxProfiles::IndependentVerification. Plaintext trusted
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
    verification 'TC-022-002' {
        doc /* #### TC-022-002 — Persistence and independent restart

             **Promises:** FR-001, FR-016, FR-022; CL-005-02, CL-005-04, CL-005-05.
             **Level:** 2 — isolated automated tests. **Where:** Windows PC, disposable storage,
             N real processes/windows. No full OS reboot is required or claimed by this case.

             **Setup partition:** Browser saves, recovery and restart observations use the
             common operational HTTPS/grant fixture; trusted plaintext loopback HTTP/startup
             compatibility remains independently mandatory, including the complete validation,
             error/storage/file invariants and exact8192 response-budget fixture. An ordinary
             unchanged-bootstrap restart retains unrevoked grants, without enrollment replay.

             **Steps:** Create an additional profile with `--create-profile`, independently check
             all creation defaults and UUID v4, and verify creation exits without listening. Save
             different editable values through each table profile's browser, record acknowledged
             revisions/UUIDs, stop all processes, clear inherited WSTX variables and restart using
             only the same paths plus explicit required TLS/token inputs. Reopen/refresh windows.
             Stop/restart only profile 1 again; then kill it after an acknowledged save and restart.

             **Oracle/outcome:** Saved fields, fixed endpoints, profile UUIDs and revisions exactly
             match the independent input/edit table; boot IDs change. Other profiles remain unchanged.
             A stale lock marker does not block restart and an orphan temporary file is never loaded.
             The fresh-process restart is evidence for process-independent storage; actual OS reboot
             is unexecuted unless separately reported from a disposable Windows VM.

             **Recovery/error variants:** Preserve independent byte hashes of all profile files.
             With the target stopped, test missing file, truncated JSON, malformed UTF-8, duplicate/
             unknown/missing fields, invalid UUID, schema 0/2, port 0/65536 and a 16,385-byte file;
             an otherwise valid 16,384-byte file padded with whitespace is accepted. Also try
             a schema-1 document naming `native_flex` and require `unsupported_connection_type`, without an attempted radio
             connection or a change to the standard profile's stored settings.
             Each invalid launch fails nonzero with the defined category and no listener or file rewrite;
             others remain usable. Restore the original bytes and restart successfully. During a
             save inject a deterministic denied-write/atomic-replace failure in disposable storage:
             no acknowledgement, no revision advance, previous complete JSON and current settings
             remain authoritative. At crash-before/after-replacement fault points require either
             complete old or complete new JSON, never a partial file; a lost response is reconciled
             by GET without replay. After a lost save response, ordinary Refresh, an announced GET or
             reconnect MUST NOT permit a second save: Save remains disabled until an explicit reload
             successfully validates the current authoritative profile. A failed explicit reload keeps
             that guard; a successful one recovers the committed revision without a second PUT.
             Test a relative profile argument from another working directory,
             a directory alias, absent parent on creation, existing empty/nonempty creation target,
             unknown/duplicate CLI flags and forbidden WSTX_BIND/WSTX_ORIGIN overrides. No fallback
             or mutation is permitted. This does not certify power-loss durability or WSJT-X migration.
             The cross-field response-budget fixture remains plaintext numeric loopback with
             an independently long saved Origin, not a protected browser/TLS/DNS/grant fixture.
             For the cross-field response budget, independently build the maximum-encoded-settings
             vector in 12.5. With the selected origin sized so its complete representation is exactly
             8,192 UTF-8 bytes, startup and GET succeed; save from revision 9,007,199,254,740,990 to
             9,007,199,254,740,991 and require a successful response of exactly 8,192 bytes. Increase
             that origin by one unescaped ASCII byte, then separately use a 9,000-character hostname:
             both launches fail `invalid_profile` before readiness without changing stored bytes.
             Use the numeric loopback address to transport the fixture requests and the saved origin
             as the exact Origin header; no external DNS or service is contacted. Other instances
             remain usable. These expectations come from the independent byte calculation, not the
             candidate's admission helper. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-005-02';
            verify 'CL-005-04';
            verify 'CL-005-05';
            verify 'FR-001';
            verify 'FR-016';
            verify 'FR-022';
        }
        attribute executable : String = "tests/profiles.test.cjs; server/src/profile_tests.rs";
    }
    verification 'TC-022-003' {
        doc /* #### TC-022-003 — Stop isolation and collision refusal

             **Promises:** FR-021, FR-022; CL-005-03, CL-005-04.
             **Level:** 2 — isolated automated tests. **Where:** Windows PC, N real server/browser
             instances, OS port reservations, ownership aliases/copies and disposable resource fixtures.

             **Setup partition:** Operational windows use the common four-process HTTPS/
             grant fixture; retain separate plaintext launch/configuration variants. Each
             negative launch has otherwise valid transport-specific TLS/token inputs, so the
             intended single fault is not replaced by a missing prerequisite or scheme mismatch.

             **Steps:** Stop profile 1 and query the other N-1 before, during and after its restart.
             While the original is running attempt: the same profile path, an alias to that directory,
             a copied directory retaining its UUID, and a new UUID/profile requesting an occupied
             port. For separate stopped copies test denied directory access, missing/unreadable TLS
             certificate/key, incomplete TLS pair, absent/invalid token and insecure remote binding.
             Test saved-origin port mismatch separately from a runtime scheme mismatch; the 4.2
             table supplies their distinct expected categories.
             Use a controlled startup resource failure for any exhaustion branch; never exhaust the
             operator PC. After failed launch remove the failing condition and launch successfully.

             **Oracle/outcome:** Only the stopped window becomes stale. N-1 Refresh requests continue
             to match their table identities within two seconds. Restart returns profile 1's UUID and
             saved revision with a fresh boot ID. Every conflicting launch fails within the ten-second
             fixture deadline, nonzero, with exactly the category mapped to its single injected
             fault by 4.2's startup-error table; no readiness, browser attachment, settings rewrite
             or existing-session interruption occurs. Pre/post byte hashes of saved files agree.
             Killing a process releases its ownership claim; a stale marker alone does not own it.
             A copied UUID is rejected until the owning process exits, irrespective of directory name.

             **Automation coverage:** Existing companions retain delivered profile launch,
             fault and lifecycle-isolation subsets. The operational HTTPS/grant browser
             fixture conversion and complete transport-partition companions remain pending;
             the expanded case is partial, with every existing launch/error oracle retained. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-005-03';
            verify 'CL-005-04';
            verify 'FR-021';
            verify 'FR-022';
        }
        attribute executable : String = "tests/profiles.test.cjs; server/src/profile_tests.rs";
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
    verification 'TC-023-001' {
        doc /* #### TC-023-001 — Direct protocol and four-station route isolation

             **Promise:** FR-023; CL-013-01, CL-013-04. **Level: 2 — Isolated automated tests.**
             **Where it runs:** Windows PC, candidate Rust system, four station profiles/windows
             and an independent local FlexRadio protocol emulator; no real radio or external service.

             **Inputs/actions:** Run with external SmartSDR desktop/CAT/DAX applications absent or
             stopped. Exercise the selected native TCP command/status exchange and UDP sample-stream
             path against pinned reference fixtures. Give each emulated slice distinguishable state
             and data; send concurrent operations from the four logical station servers.

             **Expected results:** The Rust system connects directly to the emulated API without a
             desktop bridge. Each response/state update/stream reaches the intended station and no
             other station. Operations change only the associated emulated resource. The oracle uses
             independently specified protocol fixtures, not packets generated by the code under test.

             **Level-2 realization:** tests/native-flex.test.cjs starts the independent loopback
             emulator tests/flex-emulator.cjs (TCP command/status, unicast loopback discovery and
             VITA-49 DAX float 24 kHz streams at the radio's 187.5 packets/s in the form a real
             FLEX-6600 sent, its encoder checked byte for byte against that captured packet; no code
             shared with the candidate) and four real
             station servers with disposable schema-2 HTTPS profiles. Each emulated slice carries
             a 1 kHz tone of a slice-specific amplitude, and every eighth packet another client's
             stream ID is sent at amplitude 0.95. Oracle: the emulator's own slice/stream/owner
             records and command log. Each station owns exactly one slice and stream whose index
             and ID its /native-flex snapshot repeats; its accepted channel-0 peak equals its own
             slice amplitude within 1e-4 with foreign packets counted. Four concurrent band
             selections through /receive/select tune only the selecting client's slice and return
             control native/origin native_readback; the restarted live receive runs on device
             native_flex with advancing source frames and a correlated UTC anchor within 2 s of the
             test's own clock. Read first: repeating a selection whose slice already reports the
             frequency sends no slice tune and no mode write (command log count unchanged); an
             emulator that does not report the new frequency makes the selection fail visibly with
             error radio_timeout and leaves no native_readback origin. The emulator reports a tune
             only when asked, as the real radio does; a selection is confirmed also with its replies
             and statuses 130 to 260 ms late, and a repeated selection also sends no sub slice all. One packet in 60 delayed by 4 places counts neither lost nor late; delayed by 6
             places it counts lost once and late once. Neither opens an epoch or changes the rate. A 400 ms
             outage after which the count comes back shifted by 9 opens an epoch (native_discontinuity)
             and changes neither lost nor late: the count starts over, and what waited goes on first.
             Rust unit tests also check that a duplicate is dropped, whether its first copy still waits or
             its turn has passed, and the burst limit: 7 lost in a row count lost, 8 read as late. Two stations whose DAX
             status arrives 300 ms late end on different channels, the emulator's audio following
             the channel, not the owner. Datagrams with the own stream ID from another address
             (127.0.0.2, amplitude 0.95) are never accepted. No slice command targets another
             client's slice and no transmit, disconnect or persistence command is sent. Rust unit
             tests check the captured packet and the pinned independent vector field by field, their
             negative cases, documented control lines and the 4096-byte line bound. The live check
             script tests/flex-live-check.cjs, run against the emulator streaming the verified FT8
             vector on the UTC period at 24 kHz with one packet in 64 lost, measures that loss, reports jitter, shows the
             vector's expected text from the station's decoder with DT within 0.3 s from arrival
             anchoring, saves the windows and leaves no slice or client. It stops as occupied with a
             client or slice present, whichever way round the replies come, as unverified when a
             reply is refused, reports not_released for a slice left behind or a closing look it cannot
             verify, and reports the loss it saw. One packet in four
             lost is counted at 25% and filled with silence, with the canonical frame rate kept and no new epoch, and a
             120 ms stall reads as at least 90 ms of jitter; a 400 ms stall with packets missing opens a
             new epoch (native_discontinuity). Another model on the admitted API connects and its announced
             model, serial and firmware are shown. GET /native-flex reports the packet's timestamp
             kind and this host's clock minus its time, which a new session without own packets
             shows as null. A saved address connects with nothing announced and no discovery
             listener; model, serial and firmware then come from the radio's info reply; the stream
             arrives only after client udp_register from the stream's port, which repeats, and no
             command names a local address. A full radio on a saved address reports
             radio_refused. */
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/native-flex.test.cjs; server/src/flex/wire_tests.rs; server/src/flex/session_tests.rs";
        objective {
            verify 'CL-013-01';
            verify 'CL-013-04';
            verify 'FR-023';
        }
    }
    verification 'TC-023-002' {
        doc /* #### TC-023-002 — Persisted intent and changed runtime handles

             **Promise:** FR-023; CL-013-03, CL-013-04, CL-013-05. **Level: 2 — Isolated automated tests.**
             **Where it runs:** Windows PC, disposable persisted profiles and a local radio emulator.

             **Inputs/actions:** Save the native receive intent, disconnect/restart the
             emulated radio and assign different runtime handles before reconnecting. Also present
             missing, ambiguous or occupied intended resources and stale status updates.

             **Expected results:** Each profile reconciles its intent with current authoritative
             resources; transient indices do not route it to another station. Unresolved intent is
             reported as unavailable/conflicting without stealing a resource, replaying transmit
             requests or accepting stale handles as authority.

             **Level-2 realization:** two native stations on the loopback emulator. The emulator is
             stopped and restarted with new client handles, reversed slice indices, new stream IDs
             and the old stream IDs replayed: each station reports transport_lost, then a new session
             reaches ready on its own newly created slice (emulator owner record), the old stream
             IDs are only counted as foreign, the accepted peak follows the new own slice, and a
             receive job running before the restart stays the operator's running job and advances
             again after a new source epoch, without an operator action. Occupied: an external
             connected client carries station A's saved client identity; A shows
             conflict/client_identity_in_use, sends no client gui and creates no slice while B is
             ready, and recovers once the identity disappears. Ambiguous: a slice already attributed
             to A's fresh handle yields conflict/ownership_ambiguous with no slice/stream command
             from A. Missing: nothing is announced; both report radio_not_found with zero TCP
             connections. Next available: of two emulators on one discovery port, the one announcing
             available_clients=0 receives no connection and the station becomes ready on the other.
             A selected frequency returns on the new slice after a restart, and the same occupied
             case holds when the radio answers before it lists the clients. Without a session a
             new receive start is refused radio_unavailable. Startup resume (CL-045-02): a
             spectrum and a band choice resume started, the band on the slice, and with no radio
             the resume ends failed/radio_unavailable after 15 to 30 s.
             Authorization: a native station without a grant makes no TCP connection and, after
             its only grant is revoked, its client and slice leave the emulator.
             profile.json bytes stay unchanged and hold no radio identity (no serial key). */
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/native-flex.test.cjs; server/src/flex/wire_tests.rs; server/src/flex/session_tests.rs; server/src/profile_tests.rs";
        objective {
            verify 'CL-013-03';
            verify 'CL-013-04';
            verify 'CL-013-05';
            verify 'FR-023';
        }
    }
    verification 'TC-023-003' {
        doc /* #### TC-023-003 — Capability limits and shared-resource coordination

             **Promise:** FR-023; FR-008/FR-009; CL-013-02, CL-013-04, CL-013-05, CL-013-06. **Level: 2 — Isolated automated tests.**
             **Where it runs:** Windows PC, four logical station servers and an API/resource emulator.

             **Inputs/actions:** Emulate sufficient and insufficient slice capacities, incompatible
             supported-version conditions and concurrent conflicting resource requests. Include a
             mixed set of standard audio/rig-control profiles and native FlexRadio profiles, with
             the standard device/rig-control side represented by independent local fixtures. Exercise
             the shared-radio authority policy once specified; use simulated transmit intent only.

             **Expected results:** Supported capacity permits the requested independent receive
             resources; insufficient capacity/version incompatibility is explicit and preserves
             existing station ownership. Conflicting operations follow the agreed coordination
             policy. Four server instances never imply four independently authorized transmitters.
             Standard profiles continue through their selected audio/rig-control path without native
             FlexRadio settings; native profiles use the direct API. Both are presented through the
             same browser and shared station-operation interfaces, with no cross-profile routing.

             **Level-2 realization:** emulator capacity two slices with three native stations: two
             become ready, the third reports capacity_slices, and the two owners' slice records stay
             identical. Announced available_clients=0 yields capacity_clients with zero connections;
             API version 1.5.0.0 yields incompatible_api with zero commands. A schema-1 standard
             station on the same PC returns 404 for /native-flex, control manual and the unchanged
             audio_unconfigured receive refusal and makes no connection to a radio it could hear, while the native
             station reports control native and starts receive. Safety: on both, transmit capability
             is unsupported, Enable Tx is refused with the same error, and HALT answers with the same
             status and halt state; no transmit command reaches the radio. A native settings edit
             naming an audio device or CAT control and Detect radio are refused without changing
             profile.json. One real browser shows Standard and Native FlexRadio as read-only
             connection types. The native status line and error-field entry arrive only by the
             radio.native WebSocket push: the page sends no /native-flex request, and stopping the
             emulator changes the line without a request or reload. The error field never shows
             No audio input for it. The line stands in the receive details, not in the top bar, and
             opens from its error-field entry; the screen has no page scroll at 1366x768. Stopping
             the station turns the line stale. No page errors. */
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/native-flex.test.cjs";
        objective {
            verify 'CL-013-02';
            verify 'CL-013-04';
            verify 'CL-013-05';
            verify 'CL-013-06';
            verify 'FR-008';
            verify 'FR-009';
            verify 'FR-023';
        }
    }
    verification 'TC-023-004' {
        doc /* #### TC-023-004 — Live direct-radio tuning and slice lifecycle

             **Promise:** FR-023; FR-009. **Level: 4 — Controlled live tests with operator consent.**
             **Where it runs:** Windows PC and a designated FlexRadio test station, using a recorded
             supported model/firmware and hardware capacity of at least four usable slices.

             **Inputs/actions:** With explicit consent, stop the external SmartSDR desktop/CAT/DAX
             applications, connect the candidate directly, establish the intended slice associations
             and perform approved receive tuning and slice allocation/release/reconnection. Record
             and restore the test station's agreed operating state. Do not transmit in this case.

             **Expected results:** Direct control/status and selected receive streams operate without
             those desktop applications. Each station retains its intended slice and other stations
             remain isolated through the approved lifecycle actions. Live tuning/allocation changes
             radio state, so this case is not classified as read-only level 3. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'FR-009';
            verify 'FR-023';
        }
    }
    verification 'TC-023-005' {
        doc /* #### TC-023-005 — Observational live status, only where genuinely read-only

             **Promise:** FR-023. **Level: 3 — Live read-only tests.**
             **Where it runs:** An authorized designated FlexRadio station and the Windows PC.

             **Inputs/actions:** Observe existing discovery/status/stream identity using a path that
             does not allocate/release slices, tune, change configuration or request transmission.

             **Expected results:** Reported state matches the designated radio without changing its
             operating resources. If the selected API workflow requires such changes, use the level-4
             case and operator consent instead; do not relabel a mutating test as observational. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'FR-023';
        }
    }
    verification 'TC-023-006' {
        doc /* #### TC-023-006 — Conditional future transmit validation

             **Promise:** FR-008/FR-009, FR-023; CL-013-05.
             **Level: 5 — Tests with external effects and explicit operator consent.**
             **Where it runs:** A designated authorized physical test station, only after transmit
             functionality, its ownership policy and the specific test operation have been approved.

             **Inputs/actions:** Under that later approval, request a controlled transmission from
             the owning station and a conflicting request from another profile; exercise the
             specified abort/device-loss path.

             **Expected results:** The agreed single-radio transmit authority is enforced, conflicts
             are refused and FR-008 halt/failure behavior is met. This conditional definition does
             not authorize transmission now or make it part of the receive-only live test above. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-013-05';
            verify 'FR-008';
            verify 'FR-009';
            verify 'FR-023';
        }
    }
    verification 'TC-004-001' {
        doc /* TC-004-001 — Offline FT4
             FR-003, FR-004, FR-018; CL-007-01, CL-007-02, CL-007-03, CL-007-04
             Load independently labelled FT4 recordings, select FT4 and run the candidate decoder. Include the selected message variants and controlled signal conditions.
             Decoded fields agree with the independently established expected results; misses, incorrect decodes and runtime meet the agreed FT4 budgets.
             SNR (#52): every decoded observation of the pinned modern FT4 recording reports a whole-dB SNR within 1 dB of the pinned reference jt9 report in recording-baselines.json; every corpus SNR is a whole dB at or above -21.
             A-priori decoding (#56 slice 5, WstxStationDecode::APrioriHypotheses): in FT4 a weak CQ decodes through type 1 without context and a weak HB9BLA K1ABC RR73 through type 6 only with the right calls.
             2 — Isolated automated tests; Windows PC, offline fixtures and real candidate server/browser. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-007-01';
            verify 'CL-007-02';
            verify 'CL-007-03';
            verify 'CL-007-04';
            verify 'FR-003';
            verify 'FR-004';
            verify 'FR-018';
        }
        attribute executable : String = "server/tests/decoder_signal.rs::independent_waveforms_decode; server/tests/decoder_signal.rs::quality_corpus; server/tests/decoder_signal.rs::official_modern_recording_baselines; server/src/decoder/search_test.rs::ft4_a_priori_recovers_weak_cq_and_qso_words";
    }
    verification 'TC-004-002' {
        doc /* TC-004-002 — Offline FT8
             FR-003, FR-004, FR-018; CL-007-01, CL-007-02, CL-007-03, CL-007-04
             Load independently labelled FT8 recordings, select FT8 and run the candidate decoder under the selected signal conditions.
             Decoded fields agree with the independently established expected results; misses, incorrect decodes and runtime meet the agreed FT8 budgets.
             Recorded corpus (22 FT8 recordings, the official FT8 and the modern FT4 recording, #56): the decoder finds at least the pinned number of the 409 complete-frame decodes of WSJT-X 3.3.0-beta5 jt9 -8/-5 -d 3 (fixtures/decoder/jt9-deep-reference.json; same text, carrier within 5 Hz, or, for the one pinned case PA3EPP SP8NFO KN09 in 191111_110615, the same text on another carrier of the period: the station publishes the +23 dB 906 Hz signal, jt9 its 1056 Hz image, each publishing a message once per period, the first copy its own order verifies); jt9 is a lower bound, not exhaustive truth. A strong FT8 frame that began before the window, or runs past its end, masks a weak complete frame on the same carrier: the weak frame decodes and the partial frame is never published; a frame starting at most half a symbol before the window is published at start 0, one starting earlier is not (#56 Ft8PaddedResidual). The same word on a carrier more than 50 Hz away is published once and subtracted, so a weak frame under the second copy decodes. The weak-word guard rejects exactly an FT8 word with at most 10 Costas hits and a measured SNR below -25 dB. A weak word that fails at its fine point decodes at the nearby data point (#56 slice 4 Ft8DataPoint). A failed FT8 candidate overlapped by a frame subtracted in the same pass is qualified again on the next pass (Ft8RetryOverlapped); its evidence is the parity count (WA2FZW DL5AXX RR73 in the official recording is found only through it), not a dedicated synthetic test. A-priori decoding (#56 slice 5, WstxStationDecode::APrioriHypotheses): the type table per QSO state, lapcqonly, MyCall/DxCall availability and the 50 Hz Rx/Tx width match WSJT-X; the fixed bits are the packed message bits (FT4 scrambled); in FT8 a weak synthetic HB9BLA K1ABC FN42 (report state, type 3 at its true point) and HB9BLA K1ABC RR73 (rogers state, type 6 at its true point) below the unassisted limit decode only with the right MyCall, DxCall, state and Rx/Tx, and the full decode publishes them with an a_priori type of the state (2..the expected one); a wrong DxCall in every state, FT8 and FT4, over many seeds and levels never yields a word other than the transmitted one, and noise none; an a-priori word is published only with a decoded payload and at WSJT-X confidence qual >= 0.17 (except FT8 type 1); the live station sets MyCall, DxCall, state and Rx/Tx from the profile and the current contact, and cq-only until Enable Tx is on and again 300 s after it went off. The mode-independent evidence, the confidence boundary (server/src/decoder/apriori_test.rs::low_confidence_boundary) and the live station context (server/src/contact_http_tests.rs::a_priori_context_follows_profile_and_contact), is traced by its Proves tags, not bound here (CL-007-03: each mode case binds only tests that select its mode).
             SNR (#52): every decoded observation of the pinned official FT8 recording reports a whole-dB SNR within 1 dB of the pinned reference jt9 report in recording-baselines.json; every corpus SNR is a whole dB at or above -25. Through the live worker with a correlated UTC clock, the published SNR of a synthetic FT8 period (louder noise in its first 0.25 s and before it) equals the file decode of the same period-aligned audio.
             2 — Isolated automated tests; Windows PC, offline fixtures and real candidate server/browser. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-007-01';
            verify 'CL-007-02';
            verify 'CL-007-03';
            verify 'CL-007-04';
            verify 'FR-003';
            verify 'FR-004';
            verify 'FR-018';
        }
        attribute executable : String = "server/tests/decoder_signal.rs::quality_corpus; server/tests/decoder_signal.rs::independent_waveforms_decode; server/tests/decoder_signal.rs::crc_valid_unsupported_and_invalid_payloads_are_retained; server/tests/decoder_signal.rs::official_modern_recording_baselines; server/src/recording_tests.rs::live_ft8_snr_measures_from_the_utc_period_start; server/tests/decoder_signal.rs::recorded_corpus_reaches_jt9_deep_decodes; server/src/decoder/bitmetrics_test.rs::cq_a_priori_bits_recover_a_buried_cq_word; server/src/decoder/search_test.rs::partial_frame_interferer_is_subtracted_not_published; server/src/decoder/search_test.rs::frame_past_the_window_end_is_subtracted_not_published; server/src/decoder/search_test.rs::half_symbol_publication_boundary; server/src/decoder/search_test.rs::duplicate_on_a_distant_carrier_is_subtracted_and_published_once; server/src/decoder/search_test.rs::weak_word_guard_boundaries; server/src/decoder/search_test.rs::failed_fine_point_retries_at_the_data_point; server/src/decoder/apriori_test.rs::a_priori_types_follow_the_wsjtx_state_table; server/src/decoder/apriori_test.rs::a_priori_bits_are_the_packed_message_bits; server/src/decoder/bitmetrics_test.rs::a_priori_words_need_a_decoded_payload_and_confidence; server/src/decoder/search_test.rs::weak_qso_words_decode_only_with_the_right_calls; server/src/decoder/search_test.rs::wrong_dx_call_never_yields_a_false_word";
    }
    verification 'TC-004-003' {
        doc /* TC-004-003 — Invalid and nonmatching input
             FR-003, FR-004, FR-018; CL-007-01, CL-007-02, CL-007-03, CL-007-04
             Exercise unsupported/truncated audio, silence/noise, an explicit mode mismatch and a second offline run.
             Invalid input is reported without corrupting station state; false decodes meet the agreed rejection criteria; replay produces equivalent results within defined tolerances. Use hand-specified errors and independent reference fixtures.
             Runtime matrix qualification (#36 decision): a poll whose wall time exceeds 50 ms leaves that configuration's 50 ms CPU quantum unmeasured, which is neither a pass nor a violation. The configuration is re-measured, at most three attempts; the runtime (including the four-worker 2x bound), cold-start and 64 MiB budgets bind every attempt, and any exceedance is a failure. A configuration still unmeasured after the third attempt makes the matrix inconclusive. The ordinary push gate keeps the matrix as a regression detector: an inconclusive matrix exits with the harness NOT RUN code 77, so the gate lists the suite as not run, records it as not-run, never memoises it as passed and does not block the push; such a run is never a pass and never CL-007-04 evidence. CL-007-04 runtime evidence comes only from the strict exclusive-window run on the reference PC, which refuses an inconclusive matrix.
             Station process case (#71): receive_http_tests::resource_station_process_delta_and_owner_release (private-commit delta at most 96 MiB over idle, receive-owner release at most 250 ms after Stop, FT8 and FT4, after a decode and during a busy window) runs in the release timing suite live-station-latency, alone, as a regression detector. A gate run of it is never CL-007-04 evidence; that evidence comes only from the strict exclusive-window run on the reference PC.
             2 — Isolated automated tests; Windows PC with disposable recordings, no radio or live service. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-007-01';
            verify 'CL-007-02';
            verify 'CL-007-03';
            verify 'CL-007-04';
            verify 'FR-003';
            verify 'FR-004';
            verify 'FR-018';
        }
        attribute executable : String = "server/tests/decoder_signal.rs::quality_corpus; server/tests/decoder_signal.rs::independent_waveforms_decode; server/tests/decoder_signal.rs::crc_valid_unsupported_and_invalid_payloads_are_retained; server/tests/decoder_signal.rs::unmodulated_sources_are_not_frames; server/tests/decoder_signal.rs::physical_noise_reproduction_has_no_frame; server/tests/decoder_signal.rs::physical_wrong_mode_reproduction_has_no_frame_or_search_error; server/tests/decoder_signal.rs::release_runtime_and_overlapping_window_history; server/src/receive_http_tests.rs::resource_station_process_delta_and_owner_release";
    }
    verification 'TC-004-004' {
        doc /* TC-004-004 — Live decode latency on a recorded busy period (#47)
             FR-003, FR-004, FR-021; CL-007-04, CL-007-05
             Cost 2 (release, decoder-quality suite, Windows PC, no radio): the hash-pinned busy recording websdr_test7.wav (27 decodes) is presented as the UTC-aligned FT8 prompt window, 15 s of audio completing at period start + 13.8 s, to the live modem history. The time from window completion to the last published decode is at most 1.0 s (best of three runs, leaving 0.2 s of the 1.2 s budget for capture and publication) and at least 25 distinct decodes are published, so no per-period cap applies. Cost 1: the UTC schedule places FT8 prompt/late windows at +13.8 s/+15.7 s and FT4 at +6.5 s/+7.9 s of the period from a correlated anchor, and none without one; the window buffer emits each scheduled window at its source-counter residue with its own length and wait flag; a late window arriving during the prompt decode waits for it, with no overrun and a complete prompt result. Cost 1 (drift, #47 re-review): through the live worker's clock tracking and the real window buffer, a capture clock 2000 ppm slow over 600 s plus a +0.4 s system clock step (1.6 s in all) keeps every prompt window within 0.1 s of +13.8 s UTC and holding a DT 0 frame, while the same capture without re-anchoring completes more than 1.2 s late; GET /receive/clock reports the offset and rate while the /receive clock object keeps its exact keys; the on-demand read has the operating-read authorization and refuses a query. Cost 1: a re-anchored schedule moves completions for a forward shift and a backward step without dropping or repeating a window, and UTC steps of +2 s, -2 s and +8 s taken just before a prompt completion still complete every period's prompt and late window exactly once, in order (coinciding completions one after the other, no shift by a period). Cost 1: the FT8 late window at its real geometry (UTC +0.7..+15.7 s), analysed by the live worker, leaves latest_decode and the whole snapshot unchanged when it adds nothing, and with a DT +1.2 s late starter keeps the view id and only grows next_sequence. Cost 2 (browser): a correlated period view extended in place (same id, period and first_sequence; next_sequence grown, complete false to true) adds the late row from the existing cursor, without clearing rows, moving the period to history or an error state, while any other same-id change stays a descriptor error. Cost 1: band-ranked known-word refinement agrees with the exhaustive full-rate grid search on a crowded synthetic frame within 32 frames and 0.02 Hz and returns a full-rate score.
             Cost 5 acceptance: live on HB9BLA, 10 consecutive FT8 periods publish their last decode by +15.0 s and FT4 by +7.5 s, with decode parity against jt9 on the same captured periods unchanged or better; the run records the receive session age and GET /receive/clock. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-007-04';
            verify 'CL-007-05';
            verify 'FR-003';
            verify 'FR-004';
            verify 'FR-021';
        }
        attribute executable : String = "server/tests/decoder_signal.rs::live_busy_period_publishes_every_decode_promptly; server/tests/receive_integration.rs::receive_schedule_completes_windows_at_period_residues; server/src/recording_tests.rs::live_window_schedule_follows_the_utc_period_grid; server/src/recording_tests.rs::late_window_waits_for_the_prompt_decode_without_overrun; server/src/recording_tests.rs::drifting_capture_clock_keeps_prompt_windows_on_the_utc_period; server/src/recording_tests.rs::late_window_republishes_its_period_view_with_late_starters; server/tests/receive_integration.rs::receive_reschedule_moves_completions_without_dropping_or_repeating; server/tests/receive_integration.rs::receive_clock_steps_keep_each_period_window_once_and_in_order; server/src/auth_tests.rs::plaintext_profile_operating_routes_and_ws_require_runtime_token; tests/ui-operating.test.cjs; server/src/decoder/search_test.rs::ranked_refinement_matches_exhaustive_grid_search";
    }
    verification 'TC-018-001' {
        doc /* TC-018-001
             CL-006-01, CL-006-02
             Construct byte-level PCM WAVs with 1, 2048, 4096, 4097 and 1,440,000 frames, endpoint samples -32768,-1,0,1,32767 and legal ancillary/padding chunks. Import, inspect blocks/metadata, replay twice and restart. Use the pinned actual recordings from chapter13 after retaining their license/provenance manifest; the verified22 inputs all fit the selected PCM capability.
             Provenance sweep (issue70, tests/recording-fixtures.test.cjs, no server): every one of the 22 FT8 and 3 FT4 original recordings in WSTX_SAMPLE_DIR has the sha256 of its manifest entry, and its hand-parsed RIFF/fmt header is PCM, 1 channel, 16 bit, 12000 Hz with a data size within the import cap; the enumeration equals the two manifests (25 files). Import (tests/recording.test.cjs): the first .wav entry of each manifest, one FT8 and one FT4 original, imports with rate_hz 12000, file_bytes equal to its length and stored bytes unchanged, and its replay paints waterfall rows.
             Hand-authored RIFF byte offsets/counts and exact signed-value/32768 mapping match; concatenated blocks equal input samples, <=4096 per block, contiguous offsets and one EOS; original bytes unchanged. Source UUID survives restart and repeats; job IDs differ, generations advance within a boot and reset to0 on restart, recording UTC remains null and no device opens. Analytical spectra repeat within 0.5 dB quantization plus 0.05 dB numerical tolerance. The actual recording proves non-synthetic input; it is not the calibration oracle. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-006-01';
            verify 'CL-006-02';
        }
        attribute executable : String = "tests/recording-fixtures.test.cjs; tests/recording.test.cjs; server/src/recording_tests.rs";
    }
    verification 'TC-018-002' {
        doc /* TC-018-002
             CL-006-01, CL-006-02, CL-006-04
             Table-mutate each required WAV field/chunk, zero data, odd data, duplicate fmt/data, RIFF mismatch/overflow, truncation at each header/data boundary, rate/channel/format changes, 65 chunks, frame count max+1 and file cap+1; create legal exactly-at-cap ancillary data. Exercise slow/aborted/timed-out upload, cancel before/after validation commit and storage write/flush/manifest/cleanup failures, including restart at commit boundaries.
             Hand-specified errors follow 12.6; unsupported capability differs from malformed structure, exact limits accepted. Before manifest commit old bytes/ID remain; after it new bytes/ID remain even with lost response. No partial source becomes replayable, no unbounded pending file remains; startup cleanup keeps committed data and reports failure explicitly. Other station/profile/status remains available. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-006-01';
            verify 'CL-006-02';
            verify 'CL-006-04';
        }
        attribute executable : String = "tests/recording-fixtures.test.cjs; tests/recording.test.cjs; server/src/recording_tests.rs";
    }
    verification 'TC-018-003' {
        doc /* TC-018-003
             CL-006-02, CL-006-04
             Two independent authenticated clients race import/replay/cancel using current/stale/wrong boot, profile, generation and token IDs; inject a late worker publication, disconnect/reconnect, restart during replay; separately restart during an uncommitted reserved/receiving import, then query the fresh snapshot and old import/job IDs before starting new work; run maximum source and four processes. In a separate current running job with no cancellation, hold worker release, report processing failure, then source completion, inspect state before release and finally release the worker. Enumerate every 12.6 endpoint with missing/wrong Origin/cookie, method, media type, body/schema and token errors. In a real browser, reject the reservation POST with known409 busy and separately503 storage_unavailable; observe local pending/error display and all subsequent requests.
             Exactly one serialized start wins. A known rejected reservation ends local pending and visibly reports its exact error, sends no PUT/DELETE/retried POST and preserves authoritative busy/degraded/identity state; it cannot fabricate an accepted import or successful snapshot. Restart preserves the last committed source UUID/bytes but changes boot, resets generation0 and returns import:null/job:null; prior import resource and job DELETE return404, with no cancelled-job record or automatic replay. Errors and snapshots match fixed state-transition table, lost-response recovery never auto-replays. Wrong identities cannot affect selected station. Replay cancel invalidates output before ack and reaches terminal/worker release <=250 ms under stated workload; import cancel prevents commit when accepted before committing, acknowledges locally<=250ms, cleans normally<=1s or becomes failed/storage_unavailable by5s with slot/files quarantined and no false deletion; progress never exceeds frame count. The held-worker failure vector stays running/nonterminal before release, becomes failed on release and is never completed, including simultaneous source completion. Instrument retained block/worker/slot counts against contract bounds; this is not a total RSS claim. Original station.get/auth/profile regression assertions remain in force. Also corrupt the committed original/metadata/manifest in separate fixtures, restart, open a fresh browser, obtain200 snapshot with source_error and valid identities, then import a valid replacement using those identities: replacement succeeds, clears source_error and replays; replay before replacement returns409 recording_unavailable. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-006-02';
            verify 'CL-006-04';
        }
        attribute executable : String = "tests/recording.test.cjs; server/src/recording_tests.rs";
    }
    verification 'TC-010-001' {
        doc /* TC-010-001
             CL-006-03
             Independently synthesize silence, DC, coherent tones at 750/1500/2250 Hz at amplitudes 0.5/0.25, two simultaneous tones, a noncoherent tone, clipped input and a burst with specified source-frame start/end. Compute selected windows using a direct DFT test oracle; replay through real browser.
             Direct DFT uses published formula without candidate FFT/provider helpers; peak group equals floor(k/4) for coherent bins and row interval follows window-start rule. Half-amplitude change is -6.0206 dB within 0.05 dB prequantization; quantized levels add <=0.5 dB. Silence equals floor; DC uses one-sided exception. Require normal and portable scalar FFT paths against the same direct DFT oracle, then compare full selected rows, axes/legend/row gaps in DOM/canvas sampling and source metadata, not screenshot resemblance alone. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-006-03';
        }
        attribute executable : String = "tests/recording.test.cjs; server/src/recording_tests.rs";
    }
    verification 'TC-010-002' {
        doc /* TC-010-002
             CL-006-03, CL-006-04
             #80 (operator 2026-11-09): the two-browser 32 kbit/s replay, Off and upload measurements, the stalled thin subscriber and the paced optional-output case are retired; the link budget is judged from the link byte log (CL-003-05, TC-080-001) and dead peer removal is TC-021-008. Actual server and browser on an unshaped local connection: import and replay a recording, an independent peer subscribes Off and another stays unsubscribed, another actor replays and imports; a read failing after an announcement; injected Thin frames with gaps, obsolete identities and more than 120 rows.
             The browser sends no recording.get and no timer GET /recording; a subscribed peer (Off included) receives one recording.state after subscribing and then only on a change, within 2 s, with received_bytes alone at most once per 5 s, shown without a read; a peer without a subscription receives none. A failed read after an announcement closes the socket and the reconnect reads again. The browser keeps at most 120 rows, shows missing rows as gaps and ignores obsolete identities. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-006-03';
            verify 'CL-006-04';
        }
        attribute executable : String = "tests/recording.test.cjs; server/src/protocol_tests.rs";
    }
    verification 'TC-010-003' {
        doc /* TC-010-003
             CL-006-03
             Real browser at 1100x850 and 360x640: import actual recording, verify one station page, drag divider beyond both extremes, use keyboard/touch/zoom and resize during replay. Repeat four independent station windows.
             Measured pane bounds meet 160/200 px minima, separator is 12 px and accessible, keyboard steps16px/Home/End clamp, small-height page scrolls, no horizontal page overflow, controls and axes remain reachable. Pointer/keyboard actions change only that station's pane, no second waterfall window appears and data/source identity survives resize. Browser assertions plus desktop/narrow screenshots verify actual layout. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-006-03';
        }
        attribute executable : String = "tests/recording.test.cjs";
    }
    verification 'TC-010-004' {
        doc /* TC-010-004
             CL-006-03, CL-006-04
             Cost2, automated Windows Rust numerical tests and real browser/server fixtures. Synthesize independent PCM16 vectors: silence/DC, single tones at native k256 and k257 separately and summed with fixed phases/amplitudes; simultaneous750 and756.25 Hz tones; amplitude0.5/0.25 and bursts at source frames1920/2400/2880 and sources of1/2399/2400/2401/2879/2880/2881 frames with short/EOS windows. Compare N4096 normal/scalar FFT bins and complete selected power-averaged rows against a test-only f64 direct DFT of the hand-specified periodic Hann formula, without candidate FFT/window/quantizer helpers. Replay one source with simultaneous Thin and Detailed peers, then race cancellation/replacement.
             Native k256=750Hz and k257=752.9296875Hz remain separate values; Hann leakage/interference is compared to the independent DFT, not an assertion that adjacent equal tones must form two local maxima. 750/756.25Hz signal retains independently predicted bin peaks/valley; no four-bin pooling or frequency resampling. Prequantized error <=0.05dB on independently specified bins above -80dBFS and absolute amplitude error<=2e-6 elsewhere; quantized values differ by <=1 level from independently rounded DFT, exact silence0. One coherent half-amplitude tone gives -6.0206dBFS before PCM error. Row assignment uses global hop480: five starts/full2400-frame row, one to five at EOS, including start2400 in source_frames2401. Independent mean-square amplitude then10log10 differs from Thin maximum and from averaging dB; zero Hann endpoint yields legitimate final silence for2401. Intervals are2400 frames, shortened EOS, sequence<=599. One source/worker, the latest Thin frame and the retained Detailed rows (#54, at most 25), declared workspace/history limits and cancellation release<=250ms remain; stale publications cannot overwrite either profile. Thin numerical expectations from TC-010-001 remain unchanged. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-006-03';
            verify 'CL-006-04';
        }
        attribute executable : String = "server/src/recording_tests.rs";
    }
    verification 'TC-010-005' {
        doc /* TC-010-005
             CL-006-03, CL-006-04
             Cost2, automated Windows real browser/candidate server plus deterministic injected wire fixtures. Exercise cleartext loopback and HTTPS defaults; explicit three-profile changes, old Thin-only/older server, simultaneous Thin/Detailed peers, malformed base64 alphabet/padding/pad bits/decoded lengths/values, unknown/missing keys, safe-integer/interval edges, wrong tuples/old sockets and skipped sequences. Use alternating known quantized levels in adjacent native bins/rows and read actual getImageData at1100x850 and360x640, DPR1/2,200% zoom, splitter extremes, resize and repaint; exercise the fixed level mapping (#54 DisplayLevels: reference, Zero/Gain sliders, no automatic level) and range/legend/readout consistency. Retain actual busy FT8 recording desktop/mobile screenshots and compare their trace/noise contrast, orientation and rulers qualitatively with WSJT-X/FlexRadio reference images. Stall Detailed output with a controlled sink returning Pending, then issue status/control and cancel/off.
             Detail events have exact schema,1024 decoded bytes, canonical1368-char base64 and<=2048 UTF-8 bytes; exactly-at-limit values accepted and malformed/obsolete input leaves canvas/history unchanged. At most 1 Hz Thin and, for Detailed, 5 rows/s steady with catch-up of retained rows at most 5.9 rows/s (#54 TransferDisplay); no second worker. Thin/control input1024 and binary1003 guards preserved. Optional write test independently requires readiness/control priority,4096 cap,1024+28 control reserve; Detailed fast-link status responses display<=2s on unshaped localhost with two peers. The 32 kbit/s Thin/Off budget is judged from the link byte log (#80, TC-080-001). Every origin defaults Detailed; explicit saved Thin/Off is honored and fallback attempts Thin once and labels unavailability. Pixel oracle computes integer edges/fixed source-time cell edges from contract, samples interiors and both sides of boundaries for exact palette colors/uniform cells, using independently calculated RGB interpolation/rounding from the stated anchors, with grey gaps and dark unobserved areas on a full-height canvas; no blended spatial colors. New rows enter at top; Auto ignores median0 then locks once at median-3dB, manual Black/Range disables it, job/profile reset restores30dB/Auto and original calibrated data remains invariant. Frequency500/100Hz ticks and visible source-time5s ruler agree with pixel/readout positions and clipping. Fixed0..3000Hz axis endpoints/ticks through resize/DPR/zoom, no horizontal frequency scroll, unmodified native1024-value buffer, peak-preserving max projection with every bin contributing at widths below1024, native/projected readout centers/ranges/levels/intervals, keyboard selection, recent-row orientation,600-row cap and no page overflow hold through geometry changes. Thin uses the same integer geometry with128 bins; original numerical/wire values stay unchanged. A narrow strong tone at every native-bin position contributes to its assigned column and never disappears when W<B. Screenshots establish actual layout and independently synthesized data establishes numerical correctness.  Preference persistence: with disposable browser storage and actual server/Chromium, verify unchanged defaults without a valid choice; explicit Detailed/Thin/Off survives reload and reopened browser context; origins/ports and profile UUIDs are isolated while boot/revision changes preserve choice. Invalid value or denied storage uses normal defaults without page error and leaves in-memory selection usable. Inspect only versioned UUID keys and enumerated values, with no secrets. Unknown-command runtime Thin fallback preserves stored Detailed; subsequent explicit Thin replaces it. Existing subscription commands, no retry loop and Detailed bounds remain unchanged; no synthetic decoded records are used. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-006-03';
            verify 'CL-006-04';
        }
        attribute executable : String = "tests/recording.test.cjs; tests/ui-operating.test.cjs; server/src/protocol_tests.rs";
    }
    verification 'TC-010-006' {
        doc /* TC-010-006
             CL-006-03, CL-006-04
             Cost2 automated Windows real browser/candidate fixtures. Inject independently known native rows of2,75,600 Detailed or120 Thin values with contrasting bins/rows and gaps; inspect actual RGBA/backing and CSS box dimensions at desktop1100x850/mobile360x640, DPR1/2,200% zoom and splitter bounds. Exercise Sensitivity-30/0/+30 and Speed1/2/8 via input, keyboard and numeric outputs, Range 10/50/80 (#54), new jobs/profiles and resize. Replay actual busy FT8 with a red saturated carrier, capture desktop/mobile screenshots and move both live sliders.
             Independent oracle: palette endpoint/saturated cells are exactly[255,0,0,255], floor/no-signal[0,0,12,255], no white signal cells; legend uses identical RGB anchors/endpoints. With the fixed reference B=-85 and R=50 (#54), g=+10 yields E=-95 and g=-30 yields E=-55, clamped[-120,-R]; original row arrays, source/job/generation and curve base scale stay unchanged. No setting follows the signal or resets on a new job or profile; Sensitivity, Range and Speed persist per browser. Fixed source-time scrolling, independent pixel movement, clipping, gap and unobserved-region oracles are specified in TC-010-007. Native/projected readouts and rulers agree with that mapping. Spectrum/waterfall CSS heights follow1:5 within2CSSpx rounding, actual bitmap sizes equal rounded CSS boxes times DPR, neither geometry nor intrinsic height drifts over repeated paints. No horizontal overflow/changed0..3000Hz span, interpolation, fake history or network/source-rate change. Real FT8 screenshots show a full-height waterfall canvas with unobserved regions dark, dark floor, red strongest traces and visible working live sliders; original numeric/wire/security assertions remain. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-006-03';
            verify 'CL-006-04';
        }
        attribute executable : String = "tests/recording.test.cjs";
    }
    verification 'TC-010-007' {
        doc /* TC-010-007
             CL-006-03, CL-006-04
             Cost2 automated on the Windows development PC with real Chromium/candidate server and independently injected accepted source rows. Start empty; inject a uniquely marked row then successive Detailed0.2s rows and Thin1s rows, at Speed0.5/1/2/8. Inspect actual RGBA before/after each update, through enough source time to move the mark off the bottom. Exercise short/EOS rows, gaps, no input/completion/cancel/disconnect, invalid/stale frames, new replay/profile, resize, DPR1/2,200% zoom and minimum splitter height at360CSSpx, desktop and2048px width.
             With p=10*v and newest end T, independently calculate each row edges floor((T-b)*p*H/C)..floor((T-a)*p*H/C); a fixed mark advances by2*v CSSpx per Detailed update or10*v per Thin update, independent of N. Minimum speed0.5 gives5CSSpx/s, half Speed1; default2 gives20CSSpx/s. It exits below H and never sticks or repeats. Empty/unobserved pixels are exactly navy with no-measurement readout; explicit gaps grey. Changing height changes capacity C/p, not pixels per source second; changing speed changes displacement without modifying tuples/data/network. Short EOS uses actual duration; no source row means no motion; stale/invalid frames cannot move history. Pointer native/projected intervals, keyboard clamps and5s rulers match the same time mapping. Existing sliders remain visible and keyboard-operable; actual canvas remains full allotted height, spectrum:waterfall1:5 and fixed0..3000Hz. Existing palette/sensitivity and wire/numerical assertions remain unchanged. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-006-03';
            verify 'CL-006-04';
        }
        attribute executable : String = "tests/recording.test.cjs";
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
        attribute executable : String = "tests/receive-integration.test.cjs; tests/ui-operating.test.cjs";
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
             before the drawer opens); editing a target, adding one and Save send exactly one PUT
             /udp {v 1, profile_id, boot_id, expected_revision, configuration} whose configuration
             is the edited list, and no receive start, stop or selection; no Accept commands control exists; a refusal
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
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
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
        attribute executable : String = "tests/radio-selection.test.cjs; server/src/selection_http_tests.rs; server/src/http_compression_tests.rs; server/src/recording_tests.rs";
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

    // Reciprocal ownership is verification intent, not an execution verdict.
    dependency CL_003_01_verified_by_TC_021_006 from 'CL-003-01' to 'TC-021-006';
    dependency CL_003_02_verified_by_TC_021_005 from 'CL-003-02' to 'TC-021-005';
    dependency CL_003_02_verified_by_TC_021_008 from 'CL-003-02' to 'TC-021-008';
    dependency CL_003_03_verified_by_TC_021_005 from 'CL-003-03' to 'TC-021-005';
    dependency CL_003_04_verified_by_TC_021_006 from 'CL-003-04' to 'TC-021-006';
    dependency CL_003_04_verified_by_TC_021_007 from 'CL-003-04' to 'TC-021-007';
    dependency CL_003_05_verified_by_TC_080_001 from 'CL-003-05' to 'TC-080-001';
    dependency CL_003_06_verified_by_TC_021_008 from 'CL-003-06' to 'TC-021-008';
    dependency CL_003_07_verified_by_TC_021_009 from 'CL-003-07' to 'TC-021-009';
    dependency CL_003_08_verified_by_TC_009_005 from 'CL-003-08' to 'TC-009-005';
    dependency CL_003_08_verified_by_TC_021_007 from 'CL-003-08' to 'TC-021-007';
    dependency CL_005_01_verified_by_TC_022_001 from 'CL-005-01' to 'TC-022-001';
    dependency CL_005_02_verified_by_TC_022_001 from 'CL-005-02' to 'TC-022-001';
    dependency CL_005_02_verified_by_TC_022_002 from 'CL-005-02' to 'TC-022-002';
    dependency CL_005_02_verified_by_TC_022_005 from 'CL-005-02' to 'TC-022-005';
    dependency CL_005_03_verified_by_TC_022_001 from 'CL-005-03' to 'TC-022-001';
    dependency CL_005_03_verified_by_TC_022_003 from 'CL-005-03' to 'TC-022-003';
    dependency CL_005_03_verified_by_TC_022_004 from 'CL-005-03' to 'TC-022-004';
    dependency CL_005_03_verified_by_TC_022_005 from 'CL-005-03' to 'TC-022-005';
    dependency CL_005_04_verified_by_TC_022_002 from 'CL-005-04' to 'TC-022-002';
    dependency CL_005_04_verified_by_TC_022_003 from 'CL-005-04' to 'TC-022-003';
    dependency CL_005_04_verified_by_TC_022_004 from 'CL-005-04' to 'TC-022-004';
    dependency CL_005_05_verified_by_TC_022_001 from 'CL-005-05' to 'TC-022-001';
    dependency CL_005_05_verified_by_TC_022_002 from 'CL-005-05' to 'TC-022-002';
    dependency CL_006_01_verified_by_TC_018_001 from 'CL-006-01' to 'TC-018-001';
    dependency CL_006_01_verified_by_TC_018_002 from 'CL-006-01' to 'TC-018-002';
    dependency CL_006_02_verified_by_TC_018_001 from 'CL-006-02' to 'TC-018-001';
    dependency CL_006_02_verified_by_TC_018_002 from 'CL-006-02' to 'TC-018-002';
    dependency CL_006_02_verified_by_TC_018_003 from 'CL-006-02' to 'TC-018-003';
    dependency CL_006_03_verified_by_TC_010_001 from 'CL-006-03' to 'TC-010-001';
    dependency CL_006_03_verified_by_TC_010_002 from 'CL-006-03' to 'TC-010-002';
    dependency CL_006_03_verified_by_TC_010_003 from 'CL-006-03' to 'TC-010-003';
    dependency CL_006_03_verified_by_TC_010_004 from 'CL-006-03' to 'TC-010-004';
    dependency CL_006_03_verified_by_TC_010_005 from 'CL-006-03' to 'TC-010-005';
    dependency CL_006_03_verified_by_TC_010_006 from 'CL-006-03' to 'TC-010-006';
    dependency CL_006_03_verified_by_TC_010_007 from 'CL-006-03' to 'TC-010-007';
    dependency CL_006_04_verified_by_TC_010_002 from 'CL-006-04' to 'TC-010-002';
    dependency CL_006_04_verified_by_TC_010_004 from 'CL-006-04' to 'TC-010-004';
    dependency CL_006_04_verified_by_TC_010_005 from 'CL-006-04' to 'TC-010-005';
    dependency CL_006_04_verified_by_TC_010_006 from 'CL-006-04' to 'TC-010-006';
    dependency CL_006_04_verified_by_TC_010_007 from 'CL-006-04' to 'TC-010-007';
    dependency CL_006_04_verified_by_TC_018_002 from 'CL-006-04' to 'TC-018-002';
    dependency CL_006_04_verified_by_TC_018_003 from 'CL-006-04' to 'TC-018-003';
    dependency CL_006_04_verified_by_TC_022_005 from 'CL-006-04' to 'TC-022-005';
    dependency CL_007_01_verified_by_TC_004_001 from 'CL-007-01' to 'TC-004-001';
    dependency CL_007_01_verified_by_TC_004_002 from 'CL-007-01' to 'TC-004-002';
    dependency CL_007_01_verified_by_TC_004_003 from 'CL-007-01' to 'TC-004-003';
    dependency CL_007_02_verified_by_TC_004_001 from 'CL-007-02' to 'TC-004-001';
    dependency CL_007_02_verified_by_TC_004_002 from 'CL-007-02' to 'TC-004-002';
    dependency CL_007_02_verified_by_TC_004_003 from 'CL-007-02' to 'TC-004-003';
    dependency CL_007_02_verified_by_TC_007_006 from 'CL-007-02' to 'TC-007-006';
    dependency CL_007_03_verified_by_TC_004_001 from 'CL-007-03' to 'TC-004-001';
    dependency CL_007_03_verified_by_TC_004_002 from 'CL-007-03' to 'TC-004-002';
    dependency CL_007_03_verified_by_TC_004_003 from 'CL-007-03' to 'TC-004-003';
    dependency CL_007_04_verified_by_TC_004_001 from 'CL-007-04' to 'TC-004-001';
    dependency CL_007_04_verified_by_TC_004_002 from 'CL-007-04' to 'TC-004-002';
    dependency CL_007_04_verified_by_TC_004_003 from 'CL-007-04' to 'TC-004-003';
    dependency CL_007_04_verified_by_TC_004_004 from 'CL-007-04' to 'TC-004-004';
    dependency CL_007_05_verified_by_TC_004_004 from 'CL-007-05' to 'TC-004-004';
    dependency CL_008_01_verified_by_TC_002_001 from 'CL-008-01' to 'TC-002-001';
    dependency CL_008_01_verified_by_TC_009_001 from 'CL-008-01' to 'TC-009-001';
    dependency CL_008_02_verified_by_TC_002_001 from 'CL-008-02' to 'TC-002-001';
    dependency CL_008_02_verified_by_TC_002_003 from 'CL-008-02' to 'TC-002-003';
    dependency CL_008_02_verified_by_TC_009_002 from 'CL-008-02' to 'TC-009-002';
    dependency CL_008_03_verified_by_TC_002_001 from 'CL-008-03' to 'TC-002-001';
    dependency CL_008_03_verified_by_TC_009_001 from 'CL-008-03' to 'TC-009-001';
    dependency CL_008_03_verified_by_TC_009_004 from 'CL-008-03' to 'TC-009-004';
    dependency CL_008_03_verified_by_TC_009_005 from 'CL-008-03' to 'TC-009-005';
    dependency CL_008_04_verified_by_TC_009_001 from 'CL-008-04' to 'TC-009-001';
    dependency CL_008_04_verified_by_TC_009_002 from 'CL-008-04' to 'TC-009-002';
    dependency CL_008_05_verified_by_TC_002_003 from 'CL-008-05' to 'TC-002-003';
    dependency CL_008_05_verified_by_TC_009_002 from 'CL-008-05' to 'TC-009-002';
    dependency CL_008_05_verified_by_TC_009_003 from 'CL-008-05' to 'TC-009-003';
    dependency CL_008_05_verified_by_TC_009_004 from 'CL-008-05' to 'TC-009-004';
    dependency CL_008_05_verified_by_TC_009_005 from 'CL-008-05' to 'TC-009-005';
    dependency CL_008_06_verified_by_TC_009_001 from 'CL-008-06' to 'TC-009-001';
    dependency CL_008_06_verified_by_TC_009_003 from 'CL-008-06' to 'TC-009-003';
    dependency CL_008_07_verified_by_TC_009_002 from 'CL-008-07' to 'TC-009-002';
    dependency CL_008_07_verified_by_TC_009_005 from 'CL-008-07' to 'TC-009-005';
    dependency CL_010_05_verified_by_TC_007_002 from 'CL-010-05' to 'TC-007-002';
    dependency CL_010_16_verified_by_TC_007_009 from 'CL-010-16' to 'TC-007-009';
    dependency CL_037_03_verified_by_TC_007_009 from 'CL-037-03' to 'TC-007-009';
    dependency CL_045_01_verified_by_TC_007_009 from 'CL-045-01' to 'TC-007-009';
    dependency CL_040_02_verified_by_TC_007_009 from 'CL-040-02' to 'TC-007-009';
    dependency CL_010_05_verified_by_TC_009_004 from 'CL-010-05' to 'TC-009-004';
    dependency CL_010_05_verified_by_TC_009_005 from 'CL-010-05' to 'TC-009-005';
    dependency CL_010_07_verified_by_TC_007_002 from 'CL-010-07' to 'TC-007-002';
    dependency CL_010_07_verified_by_TC_009_004 from 'CL-010-07' to 'TC-009-004';
    dependency CL_010_07_verified_by_TC_009_005 from 'CL-010-07' to 'TC-009-005';
    dependency CL_010_08_verified_by_TC_007_002 from 'CL-010-08' to 'TC-007-002';
    dependency CL_010_08_verified_by_TC_009_004 from 'CL-010-08' to 'TC-009-004';
    dependency CL_010_08_verified_by_TC_009_005 from 'CL-010-08' to 'TC-009-005';
    dependency CL_010_09_verified_by_TC_007_006 from 'CL-010-09' to 'TC-007-006';
    dependency CL_013_01_verified_by_TC_023_001 from 'CL-013-01' to 'TC-023-001';
    dependency CL_013_02_verified_by_TC_023_003 from 'CL-013-02' to 'TC-023-003';
    dependency CL_013_03_verified_by_TC_023_002 from 'CL-013-03' to 'TC-023-002';
    dependency CL_013_04_verified_by_TC_023_001 from 'CL-013-04' to 'TC-023-001';
    dependency CL_013_04_verified_by_TC_023_002 from 'CL-013-04' to 'TC-023-002';
    dependency CL_013_04_verified_by_TC_023_003 from 'CL-013-04' to 'TC-023-003';
    dependency CL_013_05_verified_by_TC_023_002 from 'CL-013-05' to 'TC-023-002';
    dependency CL_013_05_verified_by_TC_023_003 from 'CL-013-05' to 'TC-023-003';
    dependency CL_013_05_verified_by_TC_023_006 from 'CL-013-05' to 'TC-023-006';
    dependency CL_013_06_verified_by_TC_023_003 from 'CL-013-06' to 'TC-023-003';

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
    requirement 'CL-022-03' {
        doc /* Target replacement for explicit Connect/per-click receive_only_verified:
             configuration UI has a one-time per-safety-revision action 'Confirm
             receive-only setup', showing selected radio, endpoint, model and PTT
             configuration. It requires a valid matching grant, explicit operator
             acknowledgement and durable commit. It never opens CAT or transmits as
             part of confirmation. Existing transceiver-test consent is not silently
             converted into a persisted acknowledgement; migration starts unconfirmed.
             Invalidated commissioning displays 'Confirm changed receive-only setup'
             and exposes that same recovery action; no normal Connect/Disconnect CAT
             buttons. CAT disabled remains disabled and there is no serial
             enumeration/fallback, except the read-only discovery of CL-044-15 after its
             persisted keying confirmation, which may also save a found radio as CAT control.
             Missing/revoked/mismatched grant, missing/invalid commissioning, disabled
             CAT and corrupt authorization store cause zero automatic native open,
             query, setter or PTT bytes (the sole exception is that same discovery, which
             opens and sends 19 00 only). One matching unrevoked grant plus valid
             commissioning authorizes the station's automatic read-only CAT lifecycle
             even when that browser is closed; it does not authorize another browser's
             HTTP controls. Last-grant revocation cancels that lifecycle and releases
             the native owner through existing rules. Station startup/radio return
             obtains actual fresh readback automatically after preconditions hold.
             Selection/query/set refer to the same current observable values and
             identity/provenance. Automatic lifecycle never sends a setter/PTT command,
             replays user commands, starts audio/decoder or grants transmit authority;
             the single permitted exception is the #9 StartupSafetyRelease (WstxTransmit): one off-only PTT release 1C 00 00 with readback, once per boot, only when the first fresh 1C 00 readback of the boot shows TX before that boot ever keyed, sent by the transmit owner through the same actor. It never keys and never grants transmit authority.
             Delivered (issue22 slice B): the browser operating panel shows the
             action with radio identity, endpoint, model, PTT and setup revision,
             requires an explicit receive-only acknowledgement checkbox and posts the
             existing commission API; the label reads 'Confirm changed receive-only
             setup' when the safety revision is above1. A selected plaintext profile
             has no grant authority and therefore never runs the lifecycle (zero CAT
             I/O); its automatic CAT is unavailable by design. Live IC-7300
             acceptance (TC-022-010) passed on 2026-11-08 (6719540079).
             Reconnect restores the selection (operator finding 2026-11-02, another
             program held the port and released it): when the lifecycle's eligible
             connection becomes Ready with a confirmed fresh dial while the selection
             band is unknown, the station adopts that dial as the selection exactly as
             WstxOperatingReceive S1 ReadbackSelectionAdoption states (exact preferred
             entry of the station operating mode for one band, origin cat_readback,
             read-only, no receive restart, no revision advance, never replacing a known
             selection), so no band choice by hand is needed after startup or a
             reconnect. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/cat_lifecycle.rs; server/src/recording.rs; server/src/authorization.rs; server/src/authorization_http.rs; server/src/radio_http.rs; server/src/main.rs; client/recording.js";
    }
    dependency CL_022_03_to_FR_008 from 'CL-022-03' to 'FR-008';
    dependency CL_022_03_to_FR_009 from 'CL-022-03' to 'FR-009';
    dependency CL_022_03_to_FR_021 from 'CL-022-03' to 'FR-021';
    requirement 'CL-022-04' {
        doc /* Selected target cadence: after confirmed released failed attempt wait
             1,2,4,8seconds on successive failures, then8seconds capped. Use one timer
             and one in-flight task under existing station authority; no catch-up or
             backlog. Delays use monotonic time, start after attempt completion and
             confirmed release; reset only after actual fresh successful readback.
             Startup/explicit enable/new valid selected configuration gets one immediate
             attempt; disable/identity change/revocation/invalid commissioning cancels
             timer and current attempt. Re-enable starts a fresh series only after
             release confirmation. Simultaneous browsers do not create extra attempts.
             Preserve setup<=5s, exchange<=1s, cancellation checkpoint<=50ms and ordinary
             RF-context release<=250ms. Bounds are not permissions to assume release.
             Real close failure quarantines the resource; no timed reopen until an
             explicit recovery proves release. Stop/Halt invalidates relevant receive/
             RF-operation tokens and pending resume; CAT housekeeping may not restart
             audio or setters. Late results are identity/generation fenced. Existing
             shared native owner/resource arbitration with RF work stays authoritative.
             Delivered: one station-wide50ms lifecycle tick (one timer, at most one
             tick and one actor in flight) evaluates the grant/commissioning gate under
             the profile store and authority locks, then the policy. A delay starts at
             the first tick observing the confirmed released failure (<=one tick
             after release). Explicit recovery from a failed-close quarantine is a
             station restart; no in-process action clears it. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/cat_lifecycle.rs; server/src/recording.rs; server/src/authorization_http.rs; server/src/main.rs";
    }
    dependency CL_022_04_to_FR_008 from 'CL-022-04' to 'FR-008';
    dependency CL_022_04_to_FR_009 from 'CL-022-04' to 'FR-009';
    dependency CL_022_04_to_FR_021 from 'CL-022-04' to 'FR-021';
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
    dependency CL_073_01_verified_by_TC_022_006 from 'CL-073-01' to 'TC-022-006';
    dependency CL_022_01_verified_by_TC_022_006 from 'CL-022-01' to 'TC-022-006';
    dependency CL_022_02_verified_by_TC_022_006 from 'CL-022-02' to 'TC-022-006';
    // #73 the save reply is the save's outcome (operator 2026-11-08, candidate A).
    requirement 'CL-073-01' {
        doc /* (#73) Save outcome: the reply to the page's PUT /profile is the save's outcome. A 200 whose body is a valid ProfileRepresentation (the same checks as a GET /profile body) shows "Saved revision N" (N its revision) and is applied as the authoritative snapshot exactly like a GET: SnapshotApplicable, then a reload of the form, the edited revision and the shown profile (no newer same-boot snapshot is overwritten). A received 400, 409 or 503 shows its existing refusal text and state. No follow-up GET /profile is sent for the outcome, and no check of the socket, the authorization epoch or the displayed snapshot after the reply decides it: a control save (mode, endpoint, PTT) advances the CL-022 safety revision, so the server drops this page's transport and socket while the reply is on its way, and the page re-authorizes and reconnects by the existing rules without a token. "Save outcome unknown. Reload saved settings before retrying." with Save disabled until an explicit reload stays only for a save without a readable reply: network failure, the 10 s timeout, abort, an unreadable or invalid body, or a reply the authorization component discards because its headers arrived after a renewal began (accepted rare case). The server, the safety revision rule and every other caller of the authorization component are unchanged. Details: WstxProfiles::PresentAndEditProfile, WstxProfiles::BrowserSaveLifecycle. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/app.js";
    }
    dependency CL_073_01_to_FR_019 from 'CL-073-01' to 'FR-019';
    dependency CL_073_01_to_FR_022 from 'CL-073-01' to 'FR-022';
    verification 'TC-073-001' {
        doc /* TC-073-001 — Reproduction: Apply ⟳ of a CAT change reports the committed save
             CL-073-01
             Setup: actual candidate server on a disposable selected HTTPS profile (the TC-022-006 fixture: TLS localhost, token login, enrolled grant) and Chromium; control disabled at revision 0; request recorder for PUT /profile.
             Steps: connect; set CAT mode cat, endpoint fixture-cat-1, PTT disabled; press Apply ⟳; wait until the page is Connected again; read the result line, Save, the form, the shown revision, profile.json and the grant status scope.
             Expected (oracle: the contract above and the fixture's edit, not candidate output): exactly one PUT; the result line "Saved revision 1" and never "Save outcome unknown" at any time; profile.json revision 1 with control cat/fixture-cat-1/disabled; the scope's safety_revision advanced by 1 (the session-dropping path was taken); Connected again within 10 s with no token entry; Save enabled without Reload saved settings; the form shows fixture-cat-1 and the shown revision is 1. Red on the parent: "Save outcome unknown" and Save disabled.
             2 — Isolated automated browser test; Windows development PC, no radio, serial port or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/profiles.test.cjs";
        objective {
            verify 'CL-073-01';
        }
    }
    dependency CL_073_01_verified_by_TC_073_001 from 'CL-073-01' to 'TC-073-001';
    verification 'TC-073-002' {
        doc /* TC-073-002 — Received replies are known, missing replies stay unknown
             CL-073-01
             Setup: as TC-073-001; PUT /profile replies held, replaced or cut by a route fixture after the real server committed or refused them; a second window on the same profile.
             Steps (each from a fresh revision): (a) hold a committed display-name save's 200 reply, close the page's socket and let it reconnect, then release; (b) hold a committed 200 reply, announce the new revision so the page's background GET loads revision 1 first, then release; (c) hold a 409 reply (stale revision) across a socket reconnect, then release; (d) hold window A's committed revision-1 reply while window B saves revision 2 and A loads it, then release; (e) fetch a committed PUT and abort its delivery; (f) fulfil a committed PUT with status 200 and the body cut after 20 bytes; (g) with a body that is JSON but without revision; (h) hold the reply past 10 s.
             Expected (hand-written table): (a) and (b) "Saved revision 1", Save enabled, the form and shown revision 1; (c) the existing 409 text, Save disabled until reload, no "unknown"; (d) "Saved revision 1" while the shown revision stays 2 and the form is not overwritten; (e) to (h) "Save outcome unknown. Reload saved settings before retrying.", Save disabled, Refresh or a reconnect leave it disabled and an explicit reload enables it; exactly one PUT in every case (no replay); no GET /profile is sent for a save outcome in (a) to (d) beyond the socket's own initial read and the announced read. Red on the parent: (a), (b) and (d) unknown.
             2 — Isolated automated browser tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/profiles.test.cjs";
        objective {
            verify 'CL-073-01';
        }
    }
    dependency CL_073_01_verified_by_TC_073_002 from 'CL-073-01' to 'TC-073-002';
    verification 'TC-073-003' {
        doc /* TC-073-003 — Live Apply ⟳ of a CAT change on HB9BLA
             CL-073-01
             Setup: the gated candidate installed on HB9BLA, the operator's browser over HTTPS with its grant, IC-7300 on COM3; no transmission.
             Steps: note the shown revision R; in Settings > Radio change the CAT endpoint from COM3 to icom7300://COM3?baud=9600&radio=94&controller=e0 and press Apply ⟳; after the page is Connected again change it back to COM3 and press Apply ⟳; give the receive-only confirmation; change the display name and back with Apply ⟳.
             Expected (oracle: the shown revision before each save, the operator's look): each Apply ⟳ shows "Saved revision R+1", R+2, ... and never "Save outcome unknown"; after each CAT save the page is Connected again within 10 s with no token entry and Apply ⟳ is enabled without Reload saved settings; CAT shows waiting for the receive-only confirmation, then ready after it; the endpoint ends at the operator's COM3.
             4 — Live on the station, configuration change and back, no RF; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-073-01';
        }
    }
    dependency CL_073_01_verified_by_TC_073_003 from 'CL-073-01' to 'TC-073-003';
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
    verification 'TC-022-009' {
        doc /* TC-022-009 CL-022-03/04 cost2 existing station/native scripted peer + injected
             monotonic time. Test immediate available startup, absent/openfail/timeout/
             removal/return, concurrent observers/RF work, identity change mid-attempt,
             exact1/2/4/8/8 scheduling/reset/disable/re-enable, one timer/owner, no catchup,
             late completion and failedclose zero subsequent opens. Test missing/revoked/
             wrong grant, corrupt store, disabled CAT, absent/invalidation commissioning
             with zero native open/query/set/PTT; explicit confirmation persists only
             after commit, no native I/O in confirmation. Endpoint/model/PTT edit needs
             re-confirmation; ordinary USB return does not. Independent raw-byte peer
             rejects all setter/PTT, not merely reported TX=false. Separate real Windows
             cost2 native fixture release/cancel measurements prove unchanged250/50ms
             bounds and required four-profile workload; injected time is no substitute.
             Use R4 provider/consumer fixtures, no second native builder.
             Automated: server/src/cat_lifecycle_tests.rs (injected-time policy:
             immediate startup, exact1/2/4/8/8, reset only on readback, no catch-up,
             disable/revoke/identity cancel, quarantine; scripted CI-V peer through
             the real Actor/Executor: absent/open failure/timeout/removal/return,
             failed close zero reopen, query-only bytes; port held by another program
             reports port_in_use, then its release reconnects and adopts the exact
             operating-mode dial as the selection with zero setter bytes and unchanged
             operating revision; a non-matching dial or an already known selection
             is left unchanged), server/src/auth_tests.rs
             automatic_cat (real grant/commission flow, zero I/O before commission,
             endpoint edit and last-grant revocation release, deprecated routes409
             zero I/O, status retry reason) and tests/radio-selection.test.cjs
             TC-022-009 (browser confirm action, no Connect/Disconnect, retry reason,
             non-fresh frequency). Corrupt store: auth_tests automatic_cat
             failed_store_write_quarantines_and_releases_cat_with_zero_reopen (a failed
             write/flush/replace while CAT is ready quarantines the authority, the owner
             is released, zero later open/byte, status503) with profile_tests startup
             refusal of a corrupt/missing expected record. RF work: cat_lifecycle_tests
             station_rf_work_shares_the_one_owner_without_lifecycle_interference (an
             operator band selection on the same owner: no attempt/open/close by the
             lifecycle or status observers, lifecycle bytes stay query-only),
             station_revocation_during_rf_work_cancels_it_and_releases_without_reopen
             (<=250ms release, work failed, no reopen/replay) and
             policy_attempt_deferred_by_rf_work_is_not_a_failure. Pending: real Windows
             native release/cancel measurement. */
        attribute automation : AutomationState = AutomationState::partial;
        attribute executable : String = "server/src/cat_lifecycle_tests.rs; server/src/auth_tests.rs; server/src/selection_http_tests.rs; tests/radio-selection.test.cjs";
        objective {
            verify 'CL-022-03';
            verify 'CL-022-04';
        }
    }
    dependency CL_022_03_verified_by_TC_022_009 from 'CL-022-03' to 'TC-022-009';
    dependency CL_022_04_verified_by_TC_022_009 from 'CL-022-04' to 'TC-022-009';
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
    dependency CL_022_02_verified_by_TC_022_010 from 'CL-022-02' to 'TC-022-010';
    dependency CL_022_03_verified_by_TC_022_010 from 'CL-022-03' to 'TC-022-010';
    dependency CL_022_04_verified_by_TC_022_010 from 'CL-022-04' to 'TC-022-010';
    dependency CL_022_05_verified_by_TC_022_010 from 'CL-022-05' to 'TC-022-010';

    // #12 MCP access and configured FT4/FT8 automation (decisions recorded in WstxMcp
    // and on issue #12, 2026-11-01); detailed contract in WstxMcp.
    requirement 'CL-012-01' {
        doc /* Serve MCP on the station's own listener at POST /mcp (Streamable HTTP, MCP 2026-07-28 and legacy 2025-11-25/2025-06-18, stateless, JSON responses only) and map every tool onto exactly one existing versioned station operation dispatched in-process through the station router: no second station state, modem, QSO engine, transmit-authority path, raw CAT/PTT/audio tool or MCP-owned retry. Details: WstxMcp::McpEndpoint, ProtocolEras, ToolCatalog, ToolResult. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/mcp.rs; server/src/main.rs";
    }
    dependency CL_012_01_to_FR_020 from 'CL-012-01' to 'FR-020';
    dependency CL_012_01_to_FR_021 from 'CL-012-01' to 'FR-021';
    requirement 'CL-012-02' {
        doc /* An MCP client observes exactly the browser's station views (profile, receive, selection, radio, transmit, contact, automation, strategy, the #42 alert history and decoded result pages, and the strategy verdicts of POST /strategy/evaluate, read-only) and operates through the same ContactCommand, HaltTransmit and AutomationCommand bodies, receipts, revisions, command_id idempotency and refusal codes as the browser, for FT8 and FT4. Details: WstxMcp::ToolCatalog, ToolResult. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/mcp.rs; server/src/contact_http.rs; server/src/automation.rs";
    }
    dependency CL_012_02_to_FR_020 from 'CL-012-02' to 'FR-020';
    dependency CL_012_02_to_FR_007 from 'CL-012-02' to 'FR-007';
    requirement 'CL-012-03' {
        doc /* MCP authorization is explicit and separate from the browser (#58): exactly one Authorization: Bearer field carrying an MCP client token of this station, created and revoked in Settings > General > Access & grants, shown once, stored only as its SHA-256 and compared in constant time; cookies sent to /mcp are never read, the station access token and browser grant transports are refused with a hint to the MCP client token, an MCP token is refused on every browser route and never exchanged for a browser cookie or grant, revocation takes effect at the next request, refused bearers are rate limited and every use is audited (name, action, time). Every request carries its principal (browser, mcp, automation) from its credential; only browser is an operator action. A plaintext profile has no MCP access, a present Origin must be the station's. Transmit-capable operations need the MCP client's station transport like the browser's grant. Automation is station-owned, unconfigured and stopped at every boot, starts only on an explicit start with a current grant transport and the current acknowledged safety revision, lives no longer than that transport and its maximum duration, is shown read-only in the browser station bar, never takes over an operator's CQ or contact, and stops at Halt (also one racing its arming, answered with a Halt), explicit stop, lost or replaced transport, receive context or mode change, contact change, disarm, no answer, completion or its contact limit, never replaying a transmit action or leaving a selected unarmed contact. Details: WstxMcp::McpCredential, OperatingAutomation, AutomationIndicator. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/mcp.rs; server/src/automation.rs; server/src/authorization.rs; server/src/authorization_http.rs; server/src/contact_http.rs; server/src/profile.rs; server/src/main.rs; client/contact.js";
    }
    dependency CL_012_03_to_FR_020 from 'CL-012-03' to 'FR-020';
    dependency CL_012_03_to_FR_008 from 'CL-012-03' to 'FR-008';
    requirement 'CL-012-04' {
        doc /* The exact tool catalog, schemas and result envelope, the AutomationConfiguration (every key required, no default policy), the deterministic CandidateSelection (eligibility, first_seen / strongest_snr / lowest_frequency ranking, call-then-sequence tie) and the run states, counters, receipts and bounds are those of WstxMcp; contact progression and logging remain WstxContact's. Details: WstxMcp::ToolCatalog, AutomationConfiguration, CandidateSelection, OperatingAutomation, AutomationWire. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/mcp.rs; server/src/automation.rs";
    }
    dependency CL_012_04_to_FR_020 from 'CL-012-04' to 'FR-020';
    verification 'TC-020-001' {
        doc /* TC-020-001 — Shared observation
             CL-012-01, CL-012-02, CL-012-04
             Setup: (a) actual candidate router on a selected HTTPS profile (HB9BLA, JN47AA) with its auth-v1 owner, the contact engine and the #9 transmit owner on the recording hardware double, an injected FT8 live job and hand-authored codec-packed rows "CQ K1ABC FN42" 1234.6 Hz -12.4 dB and "CQ W1AW FN31" 900.0 Hz -3.0 dB; one enrolled grant; an independent JSON-RPC test client. (b) The compiled executable on a disposable HTTPS profile with a throwaway certificate and a browser-style grant that creates the MCP client token; the browser saves the strategy "NA first" (rule 1 CQ from continent NA, rule 2 any CQ, sort strongest) as active.
             Steps: modern server/discover and tools/list; wstx_read of every view and GET of the same browser route; wstx_results and the same GET /receive/results; wstx_strategy_evaluate of sequences [0, 2) with the saved strategy and the same POST /strategy/evaluate from the browser; legacy initialize, notifications/initialized, tools/list and tools/call; (b) create an MCP client token in Settings (POST /authorization/v1/mcp-clients/create), then tools/list and wstx_read profile/contact/strategy against GET /profile and GET /strategy.
             Expected (WstxMcp tables and the fixture's own identities): supportedVersions exactly [2026-07-28, 2025-11-25, 2025-06-18]; tools exactly wstx_read, wstx_results, wstx_contact_command, wstx_transmit_halt, wstx_automation_command, wstx_strategy_evaluate in this order and identical in both eras, wstx_read's view enum the nine views (alerts last, #42), wstx_strategy_evaluate readOnlyHint and the wstx_automation_command description naming every AutomationConfiguration key (max_run_minutes and strategy included); each view (strategy included: active "NA first", my_continent EU) equal to the browser response apart from the per-read monotonic_ms/utc_ms; profile_id/boot_id the fixture's; automation configuration and run null; the two rows with their literal text, frequency, SNR and sequences; the verdicts equal the browser's: K1ABC (FN42, NA) rank 0 and W1AW (FN31, NA) rank 0, W1AW first (strongest); legacy protocolVersion 2025-11-25, no Mcp-Session-Id, no resultType; the text content equals structuredContent; no PTT exchange.
             2 — Isolated automated functional tests; Windows development PC, actual candidate router and executable, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-012-01';
            verify 'CL-012-02';
            verify 'CL-012-04';
        }
        attribute executable : String = "server/src/mcp_tests.rs; tests/mcp.test.cjs";
    }
    dependency CL_012_01_verified_by_TC_020_001 from 'CL-012-01' to 'TC-020-001';
    dependency CL_012_02_verified_by_TC_020_001 from 'CL-012-02' to 'TC-020-001';
    dependency CL_012_04_verified_by_TC_020_001 from 'CL-012-04' to 'TC-020-001';
    verification 'TC-020-002' {
        doc /* TC-020-002 — Validation and authority
             CL-012-01, CL-012-02, CL-012-03
             Setup: as TC-020-001 (a) plus a second HTTPS station with its own MCP client and a plaintext station; (b) the executable with a browser-style grant.
             Steps: no Authorization, the browser cookie alone, lower-case scheme, a malformed or unknown token, an unknown wstx_mcp_ token, another station's MCP client token, this station's own browser grant transport, two Authorization fields, the plaintext station; a foreign Origin, GET, text/plain, BODY_MAX+1 bytes, invalid JSON, a batch, jsonrpc 1.0, id null or 1.5, array params, legacy version 2024-11-05, a legacy request without MCP-Protocol-Version and with 2025-03-26; modern version 1900-01-01, Mcp-Method and Mcp-Name mismatch, a Base64-sentinel Mcp-Name, resources/list, unknown tool wstx_raw_ptt; tool arguments with an extra key, an unknown view, a query-injecting source_id, wstx_strategy_evaluate without request and with request a string; ContactCommand with another station's profile_id, a future contact_revision, action key_ptt, another job's row, another boot; automation start unconfigured, configure with max_contacts 0, start with safety_revision 4 while 3 is current; then a valid MCP enable_tx, its exact retry and a changed body with the same command_id, and an MCP Halt; (b) the browser cookie on /mcp, the same transport and the station access token as an explicit bearer.
             Expected (independent refusal catalogue): 401 with WWW-Authenticate Bearer realm="wstx" for every credential case and the plaintext station; 403, 405, 415, 413; JSON-RPC -32700, -32600 (each malformed envelope), -32022 with data {supported,requested} (also for 2025-03-26), -32020 (also for the missing legacy header), -32601 with 404, -32602; tool errors status 400 invalid_request with the field (extra, view, source_id, request twice) and no station call; station refusals 403 wrong_profile, 409 stale_revision, 400 invalid_request action, 409 row_unavailable, 409 state_conflict boot_id, 409 not_configured, 400 max_contacts, 409 stale_revision safety_revision; before the valid enable_tx the contact revision, contact, arm state, policy revision and PTT log are unchanged; enable_tx 202 and armed, retry 200 with the same receipt, changed body 409 state_conflict command_id; Halt 202 and disarmed; (b) cookie 401, both bearers 401 with reason mcp_token_required and the Settings hint.
             2 — Isolated automated functional tests; Windows development PC, actual candidate router and executable with transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-012-01';
            verify 'CL-012-02';
            verify 'CL-012-03';
        }
        attribute executable : String = "server/src/mcp_tests.rs; tests/mcp.test.cjs; server/src/automation_tests.rs";
    }
    dependency CL_012_01_verified_by_TC_020_002 from 'CL-012-01' to 'TC-020-002';
    dependency CL_012_02_verified_by_TC_020_002 from 'CL-012-02' to 'TC-020-002';
    dependency CL_012_03_verified_by_TC_020_002 from 'CL-012-03' to 'TC-020-002';
    verification 'TC-020-003' {
        doc /* TC-020-003 — Operating automation
             CL-012-02, CL-012-03, CL-012-04
             Setup: actual candidate router, contact engine and #9 transmit owner on the recording hardware double with virtual UTC (bench set 1 s after an even FT8 period E), injected FT8 or FT4 live job, hand-authored codec-packed rows, the MCP test client with its MCP client token; each run start follows a browser action of the operator (#39: MCP requests never start the Tx watchdog).
             Steps: (a) pure CandidateSelection table: rows 0 CQ K1ABC 1500 Hz -12, 1 CQ W1AW 900 Hz -3, 2 CQ DL1XYZ 2100 Hz unknown SNR, 3 HB9BLA K1ABC -05, 4 CQ HB9BLA, 5 CQ W1AW 950 Hz -1, 6 CQ AA1AA 900 Hz -3, under each ranking, min_snr_db -5 and -3, allowed/blocked lists and a worked call; AutomationConfiguration bounds and every malformed key. (b) A row before start; configure strongest_snr / next_candidate / max_contacts 2 and start; publish K1ABC -12, W1AW -3, DL1XYZ unknown at E; partner "HB9BLA W1AW -05" at E+30 s, "HB9BLA W1AW RR73" at E+60 s; run the own period E+15 s to its end; publish W1AW -1 and K1ABC -12; stop; publish again; stop again. (c) A second start and a configure while running; selection, MCP Halt; retry of the original start command_id; start with the old revisions; a start over the left contact, cancel, start, browser Halt while waiting. (d) first_seen with max_unanswered_periods 2: two publications without the partner; restart; a new live job; restart; revoke the MCP client in Settings. (e) FT4: configure modes [ft4], start ft8 and ft4, publish two CQ rows. (f) max_contacts 1 with next_candidate, one completed contact; then completion_action stop, another completed contact, a later CQ. (g) A Halt injected between select_row and enable_tx. (h) max_run_minutes 1 with the step clock 59 s and 61 s ahead; max_run_minutes 480, start, a newer proof of the browser's grant, a step, stop; start, clock 8 h - 60 s and 8 h + 1 s ahead. (i) While waiting: the operator's Enable Tx (CQ), then a CQ row; the operator's manual contact W1AW, then a CQ row of W1AW; while in the run's contact: operator cancel, operator Enable Tx off, operator replacement by DL1ABC. (j) start with safety_revision 4 while 3 is current; select_row refused with the profile callsign removed; enable_tx refused after transmit became unsupported.
             Expected (hand table): (a) first_seen K1ABC, W1AW, DL1XYZ, AA1AA; strongest_snr AA1AA, W1AW, K1ABC; lowest_frequency AA1AA, W1AW, K1ABC, DL1XYZ; min -5 and -3 W1AW, AA1AA; allowed K1ABC, DL1XYZ; blocked K1ABC, DL1XYZ, AA1AA; worked K1ABC excludes it; null unconfigured, every bound admitted and each malformed value refused with its field. (b) nothing selected before start or from the earlier publication; W1AW selected (candidates 2), replying, Tx1 "W1AW HB9BLA JN47", parity odd, Rx 900, armed; roger_report, signoff with Tx5 "W1AW HB9BLA 73"; after the own period completed, disarmed, last text "W1AW HB9BLA 73", run waiting with completed_contacts 1; K1ABC then selected and armed (W1AW worked); stop 202 stopped, reason stopped, disarmed, no Halt request; no later selection; second stop stale_request. (c) state_conflict run for both; armed then Halt: stopped/halted; retry 200 with the original receipt and no new run; stale_revision expected_run_revision; later rows select nothing and leave W1AW disarmed; state_conflict contact, then a waiting run ended halted by the browser Halt with the contact still cancelled. (d) W1AW selected; no_answer after the second publication, disarmed; context_changed and disarmed after the new job; authority_lost with nothing selected; MCP then 401. (e) not_ready mode for ft8; FT4 W1AW selected, Tx4 rr73, armed. (d) also: own (odd) period publications are not counted (unanswered 0 then 1 after the first even one, no_answer after the second even one). (f) limit_reached with completed_contacts 1; completed, no later selection, disarmed. (g) stopped halted, disarmed, HaltTransmit count + 2, PTT never keyed, no later arming. (h) waiting at 59 s, time_limit at 61 s; still waiting after the browser's newer proof (another credential, #58), then stopped; waiting at 8 h - 60 s, authority_lost at 8 h + 1 s. (i) contact_changed with the operator's CQ still calling and armed and not taken over by the later row; contact_changed with the manual_entry contact kept; contact_changed after cancel; transmit_stopped without a HaltTransmit; contact_changed with DL1ABC disarmed. (j) 409 stale_revision safety_revision; provider_error with no contact; transmit_refused with the selected contact cancelled (no partner left), disarmed, PTT never used.
             2 — Isolated automated functional tests; Windows development PC, simulated FT4/FT8 traffic and real station services; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-012-02';
            verify 'CL-012-03';
            verify 'CL-012-04';
        }
        attribute executable : String = "server/src/automation_tests.rs";
    }
    dependency CL_012_02_verified_by_TC_020_003 from 'CL-012-02' to 'TC-020-003';
    dependency CL_012_03_verified_by_TC_020_003 from 'CL-012-03' to 'TC-020-003';
    dependency CL_012_04_verified_by_TC_020_003 from 'CL-012-04' to 'TC-020-003';
    verification 'TC-020-004' {
        doc /* TC-020-004 — Separate MCP client credential (#58)
             CL-012-03, CL-039-06
             Setup: (a) actual candidate router on a selected HTTPS profile (HB9BLA, JN47AA) with its auth-v1 owner, contact engine and #9 transmit owner on the recording hardware double with virtual UTC, one enrolled browser grant and an MCP client created by it; (b) the compiled executable on a disposable HTTPS profile with a browser-style grant; (c) the browser page in Chromium with the MCP client routes answered by the test.
             Steps: (a) create "Claude Code"; list; read authorization.json; the MCP token as session cookie and as bearer on GET /contact, GET /profile, POST /contact/command and POST /automation/command; the MCP token to POST /session, MCP client list/create and auth-v1 status; the internal MCP-principal transport to MCP client list/create/revoke and auth-v1 status; the browser cookie, the browser grant transport and the station access token on /mcp; tools/list and wstx_read contact with the MCP token; list and read mcp-audit.log; revoke; the token and its internal transport again; revoke again; create 7 more and a ninth; 10 refused bearers. Watchdog: a browser set_watchdogs 1 unanswered call; an MCP Enable Tx and its one CQ; MCP set_frequency by the tool and by the internal transport straight to POST /contact/command; set_watchdogs 99 by the internal transport; the internal transport on POST /transmit/command set_watchdogs, PUT /profile, PUT /strategy, GET /contacts and GET /ws; the MCP token as cookie on /contact/command; then Enable Tx by the internal transport and by the tool. (b) as (a) through HTTPS. (c) open Settings; create "Codex"; Done; Revoke the first client and confirm.
             Expected: token "wstx_mcp_" + 43 characters; the listing names fixture agent and Claude Code with created time and last used null, without token or digest; the record holds the SHA-256 and never the token; every browser route 401 with no effect; /session 401 without Set-Cookie; MCP client routes and status 401 for both; /mcp 401 for the cookie, 401 reason mcp_token_required with the Settings > ... MCP clients hint for both legacy bearers, 200 for the MCP token; recent newest first: "tools/call wstx_read contact" status 200 then "tools/list" by Claude Code, last used set, the same line last in mcp-audit.log with the client id and no token; revoke 200 listing one client; then /mcp 401 reason mcp_token_invalid and the internal transport 401; second revoke 409; the other client and the browser unaffected; the ninth client 429; seven 401 then 429 (budget 10/60 s). Watchdog: both set_frequency 202, set_watchdogs operator_required, the five non-tool routes 401, the MCP token 401, still spent after every MCP request, both Enable Tx refused tx_watchdog, PTT keyed and released only for the one CQ. (c) nothing read before Settings opens; list "Claude <Code> · created 2026-11-02 08:00 UTC · last used never" as text, the new token shown with "shown only once", cleared by Done; the confirmation names the client; exact requests list, create, list, revoke.
             2 — Isolated automated functional tests; Windows development PC, actual candidate router, executable and Chromium with transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-012-03';
            verify 'CL-039-06';
        }
        attribute executable : String = "server/src/mcp_tests.rs; tests/mcp.test.cjs; tests/ui-operating.test.cjs";
    }
    dependency CL_012_03_verified_by_TC_020_004 from 'CL-012-03' to 'TC-020-004';
    dependency CL_039_06_verified_by_TC_020_004 from 'CL-039-06' to 'TC-020-004';

    // #40 WSJT-X-compatible UDP interface with multiple targets (decisions recorded in
    // WstxUdp and on issue #40, 2026-11-01); detailed contract in WstxUdp.
    requirement 'CL-040-01' {
        doc /* Speak the WSJT-X NetworkMessage protocol (magic 0xADBCCBDA, schema 2 negotiated up to 3, Qt QDataStream big-endian) with id = the configured instance name, and send to each enabled target its selected outbound messages: Heartbeat every 15 s, Status on change, on each live decoder window and with each Heartbeat pulse (CL-040-07), Decode for each new live FT8/FT4 decode, Clear when the live job's decodes are discarded, QSO Logged and Logged ADIF when a contact is saved, Close when a target is disabled or removed. Details: WstxUdp::UdpWire, OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/network_message.rs; server/src/udp.rs; server/src/logbook_http.rs";
    }
    dependency CL_040_01_to_FR_012 from 'CL-040-01' to 'FR-012';
    requirement 'CL-040-02' {
        doc /* Any number of targets up to 16, each address:port (unicast, IPv4 multicast with TTL and interface, or IPv6 multicast per CL-040-06), enabled, a per-type outbound message selection (default all), with per-target status (last send, error). The configuration is persisted in the selected profile directory and served by GET /udp and PUT /udp; the default is one target 127.0.0.1:2237, enabled, instance name WSTX-Rust. Details: WstxUdp::UdpTarget, UdpConfiguration, TargetStatus, UdpHttp. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs; server/src/profile.rs; server/src/main.rs";
    }
    dependency CL_040_02_to_FR_012 from 'CL-040-02' to 'FR-012';
    dependency CL_040_02_to_FR_001 from 'CL-040-02' to 'FR-001';
    requirement 'CL-040-03' {
        doc /* Send-only (operator decision 2026-11-06: "GridTracker just listens. We only react to the front end or to the MCP."; "The UI has to be able to halt the station in emergency halt."). No inbound UDP message acts on the station: Clear, Reply, Close, Replay, Halt Tx, Free Text, Location, Highlight Callsign, Switch Configuration, Configure and unknown types from any source have no effect, change no state and are not answered. All control comes from the browser and MCP; the emergency off is the browser's HALT and MCP's halt. Only a Heartbeat from a target's own address with the configured id raises that target's header schema (2 to 3, never lowered), as the WSJT-X protocol negotiates it. A datagram too large for the receive buffer never holds back the datagrams behind it. Details: WstxUdp::InboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs; server/src/network_message.rs";
    }
    dependency CL_040_03_to_FR_012 from 'CL-040-03' to 'FR-012';
    dependency CL_040_03_to_FR_008 from 'CL-040-03' to 'FR-008';
    requirement 'CL-040-04' {
        doc /* Decode texts use the WSJT-X form: a standard message with R before a signal report is "R-09" / "R+03", never the decoder's separated "R -09". Details: WstxUdp::OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs";
    }
    dependency CL_040_04_to_FR_012 from 'CL-040-04' to 'FR-012';
    // CL-040-05 and TC-012-005 (Location session grid) retired by the operator decision
    // 2026-11-06 recorded in CL-040-03 and WstxUdp; the identities are not reused.
    requirement 'CL-040-06' {
        doc /* Issue #46: an IPv6 multicast group target (ff00::/8) with a hop limit 1..255 (multicast_ttl) and an interface index (multicast_interface as decimal text, required for interface-local and link-local scope, optional above) is admitted by PUT /udp, saved, and receives its selected outbound messages through a socket with IPV6_MULTICAST_HOPS and IPV6_MULTICAST_IF set. Reserved scopes 0 and 15 and interface names are refused. Details: WstxUdp D6, UdpTarget, OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs";
    }
    dependency CL_040_06_to_FR_012 from 'CL-040-06' to 'FR-012';
    verification 'TC-012-006' {
        doc /* TC-012-006 — IPv6 multicast targets
             CL-040-06
             Setup: actual candidate router and UDP owner on a disposable profile; a peer socket joined to the transient link-local group ff12::5754:5358 on the Windows loopback pseudo-interface (index 1);
             Steps: PUT, each alone: scope 0 ff00::1, scope 15 ff0f::1 and ff1f::1, the group without an interface, ff01::1 without an interface, hop limit 0 and 256, an IPv4 group with interface "1", interfaces "0", "01", "-1", "+1", " 1", "4294967296", "Ethernet", "127.0.0.1", "::1", "" and the number 1; then one PUT of the group at the peer's port with hop limit 2 and interface "1", [ff05::5754:5358]:2237 hop limit 255 interface "1", [ff15::5754:5358]:2238 interface "4000000000", and a disabled [ff08::5754:5358]:2239 without an interface; open a new owner; PUT the list plus a disabled [::1]:2240 with interface "127.0.0.1", then with "1"; read the socket options; one station step.
             Expected: each refusal 400 invalid_request with its field (address for the scopes, otherwise the named field) and nothing saved; the PUT admitted with the targets saved as given and unchanged after the reopen; the IPv6 unicast target with "127.0.0.1" admitted and with "1" refused targets[4].multicast_interface; the group socket has hop limit 2, interface 1 and loopback on, the site-local one hop limit 255; the unknown index shows active false, socket_unavailable; the joined peer receives Heartbeat then Status (schema 2, id WSTX-Rust).
             2 — Isolated automated functional tests; Windows development PC, loopback IPv6 multicast only, nothing leaves the machine. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-040-06';
        }
        attribute executable : String = "server/src/udp_tests.rs";
    }
    dependency CL_040_06_verified_by_TC_012_006 from 'CL-040-06' to 'TC-012-006';
    requirement 'CL-040-07' {
        doc /* Issue #40 live acceptance (GridTracker, 2026-11-02): Status is sent as WSJT-X sends it, so a tool that waits for a Status sees the station within one T/R period. Its decoding field is true while the live decoder processes an analysis window and false once that decode returns (completed, abandoned, failed or cancelled); every toggle sends a Status, and a window that begins and ends between two station steps still sends one, so at least one Status goes out per decoded window and therefore per T/R period (WSJT-X v3.3.0-beta5 widgets/mainwindow.cpp MainWindow::beginDecode and endDecode call updateDecodeControls, which calls statusUpdate; MessageClient::status_update sends unconditionally). In addition, the Status is resent unchanged at each pulse, together with the Heartbeat every 15 s (MessageClient heartbeat_timer_, NetworkMessage::pulse), also to a target that selects status without heartbeat, so a tool started later learns the state within 15 s; the resend is this station's choice, WSJT-X has none. A target that does not select status receives none of these. Details: WstxUdp::OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs; server/src/recording.rs";
    }
    dependency CL_040_07_to_FR_012 from 'CL-040-07' to 'FR-012';
    verification 'TC-012-007' {
        doc /* TC-012-007 — Status cadence with decoder windows and the pulse
             CL-040-07
             Setup: (a) actual candidate UDP owner, contact engine and #9 transmit owner on the recording hardware double (profile HB9BLA, JN47AA); loopback peers A (all messages), B (status only) and C (heartbeat and decode); (b) the actual live worker on the recording fixture with zero-sample FT8 windows and a capture poll that records the decoder activity while the decode in progress drives it.
             Steps: (a) step; step; twice: begin a window decode through the recording's decoder signal, step, step, end it, step; begin and end one window, step, step; back-date the stored pulse instant by 14 s, step; by 15 s, step; step. (b) analyze one window with a waiting late window, and with a replacing window (overrun).
             Expected (hand table): (a) activation A Heartbeat then Status decoding 0, B Status, C Heartbeat only; then nothing; each window begin one Status decoding 1 to A and B, no repeat while it decodes, its end one Status decoding 0; the window begun and ended between steps one Status decoding 0 to A and B; nothing at 14 s; at 15 s A Heartbeat then a Status byte-identical to the last one sent, B the Status, C the Heartbeat only; then nothing; C never receives a Status. (b) before: (false, 0); polled values all decoding true, first (true, 1), then (true, 2); after: (false, 2), in both cases.
             2 — Isolated automated functional tests; Windows development PC, loopback UDP on ephemeral ports only, deterministic time (no sleep for the pulse), no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-040-07';
        }
        attribute executable : String = "server/src/udp_tests.rs; server/src/recording_tests.rs";
    }
    dependency CL_040_07_verified_by_TC_012_007 from 'CL-040-07' to 'TC-012-007';
    // CL-040-08 and TC-012-008 (udp.display: Highlight Callsign and Clear in the browser)
    // retired by the operator decision 2026-11-06 recorded in CL-040-03 and WstxUdp; the
    // identities are not reused.
    verification 'TC-012-001' {
        doc /* TC-012-001 — NetworkMessage wire vectors
             CL-040-01, CL-040-03, CL-040-04
             Setup: hand-constructed byte vectors in server/tests/vectors/udp/, each written field by field from WSJT-X v3.3.0-beta5 NetworkMessage.hpp (SHA-256 b640a632...) with the construction steps recorded in the file, independent of the encoder.
             Steps: encode Heartbeat, Status, Decode, Clear, QSO Logged, Close and Logged ADIF from the vector inputs; read the Heartbeat vectors (schema 3 with its fields, schema 2 without them, trailing bytes); read every refused vector (each former command and an unknown type: Clear, Reply, Close, Replay, Halt Tx, Free Text, Location, Highlight Callsign, Switch Configuration, Configure, type 18; a Heartbeat with wrong magic, schema 1 and 4, truncated utf8, invalid utf8, null id, 4097 bytes).
             Expected: encoded bytes equal each vector exactly; the read header equals the vector's schema and id; refused vectors give nothing; arbitrary bytes and every truncation never panic; the decoder text "K1ABC W9XYZ R -09" renders "K1ABC W9XYZ R-09" and "R +03" renders "R+03", other texts unchanged.
             2 — Isolated automated tests; Windows development PC, no network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-040-01';
            verify 'CL-040-03';
            verify 'CL-040-04';
        }
        attribute executable : String = "server/tests/udp_vectors.rs; server/src/udp_tests.rs";
    }
    dependency CL_040_01_verified_by_TC_012_001 from 'CL-040-01' to 'TC-012-001';
    dependency CL_040_03_verified_by_TC_012_001 from 'CL-040-03' to 'TC-012-001';
    dependency CL_040_04_verified_by_TC_012_001 from 'CL-040-04' to 'TC-012-001';
    verification 'TC-012-002' {
        doc /* TC-012-002 — Outbound messages to several targets
             CL-040-01, CL-040-02, CL-040-04
             Setup: actual candidate router, UDP owner, contact engine and #9 transmit owner on the recording hardware double (profile HB9BLA, JN47AA), an injected FT8 live job, hand-authored codec-packed rows "CQ K1ABC FN42" 1234.6 Hz -12.4 dB and "HB9BLA W9XYZ R-09" (decoder text "HB9BLA W9XYZ R -09") 900.0 Hz -3.0 dB; two loopback UDP peers on ephemeral ports configured as targets by PUT /udp (A all messages, B only decode).
             Steps: one station step; publish the rows; step; change the operating report; step; start a second live job; step; save a contact through POST /contacts, repeat it with the same and with a new command_id; disable target A by PUT /udp; step.
             Expected (hand table): A receives Heartbeat (id WSTX-Rust, max schema 3) and Status (mode FT8, DE HB9BLA JN47AA, Tx enabled false), then Decode New true Time = period ms since midnight, snr -12, df 1235, Mode "~", "CQ K1ABC FN42", and snr -3, df 900, "HB9BLA W9XYZ R-09"; a changed Status; Clear after the new job; QSO Logged (DX call, mode FT8, times) then Logged ADIF beginning with the ADIF header and containing <call:5>K1ABC and ending " <EOR>", nothing for the retained receipt or already_saved; Close after disable while B keeps its socket. B receives exactly the two Decode datagrams. GET /udp shows last_send_utc_ms for both and error null.
             2 — Isolated automated functional tests; Windows development PC, loopback UDP on ephemeral ports only, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-040-01';
            verify 'CL-040-02';
            verify 'CL-040-04';
        }
        attribute executable : String = "server/src/udp_tests.rs";
    }
    dependency CL_040_01_verified_by_TC_012_002 from 'CL-040-01' to 'TC-012-002';
    dependency CL_040_02_verified_by_TC_012_002 from 'CL-040-02' to 'TC-012-002';
    dependency CL_040_04_verified_by_TC_012_002 from 'CL-040-04' to 'TC-012-002';
    verification 'TC-012-003' {
        doc /* TC-012-003 — No inbound message acts; Heartbeat negotiates the schema
             CL-040-03
             Setup: as TC-012-002 with one target A and another socket X; a published CQ row; the browser's enable_tx has armed the station; the PTT log of the hardware double.
             Steps: from A and from X to A's socket: Halt Tx, Clear, a Reply matching the row, Close, Replay, Free Text, Location "JN36AB", Highlight Callsign, Switch Configuration, Configure; one step; read arm state, last disarm cause, contact, profile grid, the datagrams at A, and GET-shape of the snapshot. Then, one step each: a schema-3 Heartbeat from X; from A a schema-3 Heartbeat with another id, a schema-4 Heartbeat, a schema-3 Replay and a schema-3 Halt Tx. Then from A a 5000-byte datagram followed by a schema-3 Heartbeat, one step; a schema-2 Heartbeat, one step; publish a further decode, one step.
             Expected: still armed with the disarm cause unchanged, no contact prepared, the grid and the Status DE grid the profile's, at A no Decode with New false (only Status); the snapshot keys exactly v, profile_id, boot_id, revision, configuration, configuration_error, status and a status entry exactly active, address, error, last_send_utc_ms, schema; the schema stays 2 through each of the single steps, becomes 3 in the step of the oversize datagram and its Heartbeat, stays 3 after the schema-2 Heartbeat, and the next datagrams at A carry header schema 3.
             2 — Isolated automated functional tests; Windows development PC, loopback UDP only, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-040-03';
        }
        attribute executable : String = "server/src/udp_tests.rs";
    }
    dependency CL_040_03_verified_by_TC_012_003 from 'CL-040-03' to 'TC-012-003';
    verification 'TC-012-004' {
        doc /* TC-012-004 — Target configuration and persistence
             CL-040-02
             Setup: actual candidate router on a disposable profile directory without udp.json; a second profile with an invalid udp.json.
             Steps: GET /udp; PUT a list of A (unicast, decode only), B (239.255.0.1:2237 multicast, ttl 2, interface 127.0.0.1); open a new owner on the same profile; PUT with a stale revision, another profile, another boot, an unknown key, 17 targets, a duplicate address, port 0, 0.0.0.0, ff02::1 without an interface, ttl 0 and 256, an interface that is not IPv4, a duplicated or unknown message name, accept_commands on a target (a retired key), an empty and a 65-byte instance name, v 2, text/plain, 8193 bytes, a query; GET on the invalid profile; open an owner on a udp.json whose target also names accept_commands true, then PUT.
             Expected: the default {instance_name WSTX-Rust, one target 127.0.0.1:2237 enabled, all seven messages, multicast_ttl 1, interface null} at revision 0; the PUT returns revision 1 with the messages in enum order and survives the reopen unchanged; each refusal with its status, code and field and nothing saved; the invalid profile shows configuration null and configuration_error invalid_configuration with no socket; a row published then is not sent after a valid PUT (only Heartbeat and Status); the file with accept_commands loads without configuration error, its target unchanged but for that key and active, and the PUT writes a file without the key.
             2 — Isolated automated functional tests; Windows development PC, loopback only. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-040-02';
        }
        attribute executable : String = "server/src/udp_tests.rs";
    }
    dependency CL_040_02_verified_by_TC_012_004 from 'CL-040-02' to 'TC-012-004';

    // #45 Resume receive (Monitor) after a station restart (defaults recorded on issue #45).
    requirement 'CL-045-01' {
        doc /* The station persists its last started receive choice and the "Monitor off at startup" setting in receive-startup.json next to profile.json of the selected profile, written atomically like the profile's other private files: {schema_version 1, profile_id, monitor_off_at_startup boolean (default false, as WSJT-X), last_receive null | {mode spectrum|ft4|ft8, band one of the preferred-table bands or null, input_device the audio input it opened}}. A successful receive start (POST /receive/start, or a band/mode selection that restarted receive) records mode, the station's band at that moment and the input; the operator's POST /receive/stop clears last_receive; a receive that ends by failure keeps it. A missing file reads as the defaults; a foreign, malformed, oversize (over 1024 bytes) or out-of-domain file reads as the defaults with storage_error invalid_startup and is replaced by the next write; a failed write leaves receive unchanged and reports storage_error storage_unavailable. GET /receive/startup (operating access, no query, empty body) returns {v 1, profile_id, boot_id, monitor_off_at_startup, last_receive, storage_error, resume {state idle|off|waiting|started|started_untuned|skipped|failed, error}}; POST /receive/startup {v, profile_id, boot_id, monitor_off_at_startup boolean}, exact keys, same Origin/authorization and refusal codes as POST /receive/stop, sets the setting for the next station start and returns the view. The setting's operator control is Settings > General (layout of #37). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/receive_startup.rs; server/src/recording.rs; server/src/receive_http.rs; server/src/main.rs; server/src/profile.rs";
    }
    dependency CL_045_01_to_FR_016 from 'CL-045-01' to 'FR-016';
    dependency CL_045_01_to_FR_003 from 'CL-045-01' to 'FR-003';
    requirement 'CL-045-02' {
        doc /* When the station starts with its profile, and monitor_off_at_startup is false and last_receive is stored, it resumes that receive once, without a browser or operator action, using the profile's current audio input (none configured: resume failed audio_unconfigured; a native FlexRadio profile's input is its session, for which it waits up to the same 20 s, then fails radio_unavailable). An FT4/FT8 choice with a band is resumed as the same band selection the band button makes (receive-only CAT setup under configured CAT; nominal dial from the preferred table); with configured CAT it waits up to 20 s for the CAT lifecycle (CL-022-03/04) to report the radio ready, retrying the transient admission refusals radio_unavailable, busy and state_conflict every 250 ms within that wait, and if the radio is not ready in time or the selection fails it starts receive on the stored mode on the radio's present dial (resume started_untuned) and keeps the stored band. A spectrum choice or a choice without a band starts receive on the stored mode. A missing audio device follows the existing live-audio error/retry state of the started job; the resume never exits or restarts the process. With monitor_off_at_startup true (resume off) or nothing stored (resume idle) no receive starts; a receive, selection or import that exists before the resume acts (operator or MCP) is never replaced (resume skipped). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/receive_startup.rs; server/src/main.rs";
    }
    dependency CL_045_02_to_FR_003 from 'CL-045-02' to 'FR-003';
    dependency CL_045_02_to_FR_021 from 'CL-045-02' to 'FR-021';
    requirement 'CL-045-03' {
        doc /* Resuming receive never arms, keys or tunes the transmitter: the transmit owner stays disarmed with no PTT exchange, and the only CAT writes are the receive-only setup of a band selection, refused while the radio reports TX. TC-008-002 "restart does not transmit" stays true. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/receive_startup.rs";
    }
    dependency CL_045_03_to_FR_008 from 'CL-045-03' to 'FR-008';
    verification 'TC-045-001' {
        doc /* TC-045-001 — Persisted receive choice and startup resume
             CL-045-01, CL-045-02, CL-045-03
             Setup: actual Recording owner on a disposable profile directory with the injected native-packet live input (receive_http_tests::Input), no radio actor; for HTTP the actual station router (contact_http_tests fixture); for transmit a transmit-capable fixture with CAT PTT configured and the recording hardware double (Bench).
             Steps: (a) start ft8 on input first-input; band selection 40m ft4 on band-input; set Monitor-off; reopen; operator Stop; reopen. (b) receive-startup.json with a foreign profile_id, mode jt65, band 2m, an extra key, schema_version 2, empty input_device, 1024 padding bytes, malformed JSON; resume. (c) stored ft4/20m, manual control, resume. (d) Monitor-off true with a stored choice; start then Stop then reopen; an operator start before the resume. (e) stored ft8/40m with configured CAT that never becomes ready, wait 300 ms; stored ft8/40m whose first three admissions are refused radio_unavailable, busy, state_conflict. (f) GET/POST /receive/startup valid, other profile, other boot, extra key, v 2, string boolean, foreign Origin, a query. (g) resume on the transmit-capable fixture, manual band path and configured-CAT fallback.
             Expected (issue #45 defaults and the canonical preferred table, hand-written file contents): (a) file {schema_version 1, profile_id, monitor_off_at_startup false, last_receive {ft8, null, first-input}}, then {ft4, 40m, band-input}; reopened view Monitor-off true and the same choice; after Stop last_receive null with Monitor-off kept. (b) every case: defaults, storage_error invalid_startup, resume idle, no job. (c) resume started, selection band 20m mode ft4 nominal_hz 14080000, job ft4 running on profile-input. (d) resume off and generation 0; resume idle with no job; resume skipped with the operator's ft8 job unchanged. (e) resume started_untuned, ft8 job running, selection band null, file band 40m kept; after the three refusals resume started, selection 40m nominal_hz 7074000, job running. (f) 200 and file true; 403 wrong_profile, 409 state_conflict, 400 invalid_request, 400 unsupported_version, 400 invalid_request, 403 forbidden_origin, 400; setting unchanged by refusals. (g) resume started / started_untuned, transmit arm/PTT/transmitting/outcomes unchanged, Bench PTT log empty.
             2 — Isolated automated functional tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-045-01';
            verify 'CL-045-02';
            verify 'CL-045-03';
        }
        attribute executable : String = "server/src/receive_startup_tests.rs";
    }
    dependency CL_045_01_verified_by_TC_045_001 from 'CL-045-01' to 'TC-045-001';
    dependency CL_045_02_verified_by_TC_045_001 from 'CL-045-02' to 'TC-045-001';
    dependency CL_045_03_verified_by_TC_045_001 from 'CL-045-03' to 'TC-045-001';
    verification 'TC-045-002' {
        doc /* TC-045-002 — Live resume after a station restart
             CL-045-01, CL-045-02, CL-045-03
             Setup: the gated candidate installed on HB9BLA, IC-7300 on COM3 with commissioned receive-only CAT, USB Audio CODEC input, no browser connected during the restarts.
             Steps: FT8 receive on a band, restart the station task; set Monitor off at startup, restart; clear it, Stop receive, restart.
             Expected: within one FT8 period after the station answers, GET /receive shows a running ft8 job and GET /receive/selection the same band, GET /receive/startup resume started; with Monitor-off no job (resume off); after Stop no job (resume idle); PTT released and transmit disarmed throughout, no RF.
             4 — Live on the station with the operator's consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-045-01';
            verify 'CL-045-02';
            verify 'CL-045-03';
        }
    }
    dependency CL_045_01_verified_by_TC_045_002 from 'CL-045-01' to 'TC-045-002';
    dependency CL_045_02_verified_by_TC_045_002 from 'CL-045-02' to 'TC-045-002';
    dependency CL_045_03_verified_by_TC_045_002 from 'CL-045-03' to 'TC-045-002';

    // #43 Optional clock from the air (defaults chosen on the CR, recorded in AirClock).
    requirement 'CL-043-01' {
        doc /* Each station profile selects its clock source: ntp (default, the CL-009-05
             SNTP measurement, unchanged behaviour), air (the clock from the air,
             CL-043-02) or both (NTP preferred, air as fallback and cross-check). The
             source is persisted in clock.json next to profile.json of the selected
             profile, written atomically like the profile's other private files:
             {schema_version 1, profile_id, source ntp|air|both}. A missing file reads as
             ntp; a foreign, malformed, oversize (over 1024 bytes), extra-key or
             out-of-domain file reads as ntp with storage_error invalid_clock and is
             replaced by the next save; a failed write keeps the previous source and
             reports storage_error storage_unavailable. GET /clock (operating access, no
             query, empty body) returns exactly {v 1, profile_id, boot_id, source, state
             synchronized|unsynchronized|unknown, basis ntp|air, correction_ms, ntp {state,
             measurement null | {server, offset_ms, round_trip_ms, age_ms}}, air {state,
             applied_ms, estimate null | {offset_ms, stations, heard, confidence_pct,
             age_ms}}, disagreement_ms null | integer, warning null | ntp_air_disagree,
             storage_error null | invalid_clock | storage_unavailable}. POST /clock {v,
             profile_id, boot_id, source}, exact keys, with the same Origin, authorization,
             media, 1024-byte body and refusal codes as POST /receive/startup (an unknown
             source is invalid_request), saves the source, applies it at once (no restart)
             and returns the view. The operator control is Settings > General > Clock: a
             source select saved on change, and a status line with state, basis,
             correction, the air offset, stations used of stations heard, confidence and
             age, and the disagreement warning; the browser reads GET /clock only when
             the Settings drawer opens (at most every 10 s) or the General tab is chosen,
             never on a timer, so the thin link carries no clock polling. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/clock_http.rs; server/src/main.rs; server/src/recording.rs; client/contact.js";
    }
    dependency CL_043_01_to_FR_006 from 'CL-043-01' to 'FR-006';
    dependency CL_043_01_to_FR_016 from 'CL-043-01' to 'FR-016';
    requirement 'CL-043-02' {
        doc /* The station estimates its clock offset from the decodes of its live receive
             (WstxTransmit::AirClock): every published decode whose message names a
             concrete sending call (the from call of the standard, field day, RTTY and VHF
             families, the full call of a nonstandard CQ) with a known SNR of at least
             -20 dB and |raw DT| at most 3000 ms is an observation; raw DT is the DT
             against the uncorrected system clock (the capture drift of CL-007-05
             included, the station clock correction of CL-043-03 not). Decodes of the
             profile's own call (any case: the station's own echo) never count. The
             observations of the last 120 s of system time form the estimate: one vote per
             distinct station (the median of its DT); no estimate from fewer than 3
             stations; the votes further than 400 ms from the median of all votes are
             trimmed (stations with a bad clock); offset_ms = -median of the rest (true
             UTC minus system UTC, the sign of an SNTP offset); stations = the votes kept,
             heard = all votes, confidence_pct = floor(100 stations / heard). An estimate
             is confident with at least 4 stations and confidence_pct at least 60. Medians
             of an even count are the floor of the mean of the middle pair. A system clock
             step of more than 100 ms between observations (system time elapsed minus
             monotonic time elapsed) discards all observations and the estimate and
             subtracts the step from the applied correction (CL-043-03), so station UTC
             stays continuous (a step that corrected the system clock leaves 0); a
             correction beyond 3000 ms after that restarts at 0 with acquisition. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/air.rs; server/src/recording.rs; server/src/transmit_http.rs";
    }
    dependency CL_043_02_to_FR_006 from 'CL-043-02' to 'FR-006';
    dependency CL_043_02_to_FR_004 from 'CL-043-02' to 'FR-004';
    requirement 'CL-043-03' {
        doc /* Each completed live decode window (prompt and late) re-estimates; when the
             estimate is confident and differs from the applied correction by more than
             50 ms (hysteresis) the applied correction moves toward it by at most 1000 ms
             (rate limit). The station clock basis is air for source air, and for source
             both while the SNTP state is not synchronized; otherwise ntp. On the air
             basis station UTC is the system clock plus the applied correction (on the ntp
             basis plus 0, as before), used alike for live receive window alignment,
             period_start_utc and DT of results (in addition to the capture drift, #47),
             transmit planning and audio start (CL-009-02), the contact engine and UDP
             times; the Windows clock is never set. The air state is synchronized when
             the latest estimate is confident, at most 60 s old and unstepped and its
             |offset - applied| is at most 500 ms, unsynchronized when confident, recent
             and unstepped but beyond it, else unknown. Both: synchronized when either
             state is, unsynchronized when either is, else unknown. Because the estimate
             is taken from raw DT, applying the correction never changes the estimate's
             input: the correction converges without oscillating, and with the live window
             coverage of corrected DT (-1.7 s to +2.56 s) acquires offsets (true minus
             system UTC) of about -2.5 s to +1.7 s directly. Acquisition: until the first
             confident estimate since start (or since a restart at 0), every 4 completed
             windows without one alternate the applied correction between 0 and +1000 ms,
             which moves the coverage to raw DT -2.7 s to +1.56 s, so a system clock up to
             about 2.7 s slow is acquired too; after the first confident estimate there is
             no alternation. Outside about -2.5 s to +2.7 s too few stations decode and the
             state stays unknown (transmit refused). When a current SNTP measurement (state not
             unknown) and a confident air estimate both exist, disagreement_ms = |SNTP
             offset - air offset|; with source both a disagreement above 200 ms is the
             warning ntp_air_disagree. Exception chips (CL-010-16 layout): a clock chip
             only while transmit is configured and not synchronized (unsynchronized: Clock
             off; unknown with source air or both: Clock unknown), and a warning chip for
             ntp_air_disagree. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/air.rs; server/src/recording.rs; server/src/transmit_http.rs; client/contact.js; client/recording.js";
    }
    dependency CL_043_03_to_FR_006 from 'CL-043-03' to 'FR-006';
    dependency CL_043_03_to_FR_005 from 'CL-043-03' to 'FR-005';
    verification 'TC-043-001' {
        doc /* TC-043-001 — Clock from the air: estimates of known DT distributions
             CL-043-02, CL-043-03, CL-009-05
             Setup: hand-written raw DT sets around a twelve-station crowd with true DT
             -250, -150, -100, -50, 0, 0, 50, 100, 150, 200, 300, 400 ms (median 25 ms);
             the pure AirClock and StationClock on explicit or real clocks with a fake
             SNTP monitor; no receive, radio or network.
             Steps: estimate the crowd for a station clock 2 s ahead and 1.5 s behind; add
             a station with a bad clock (+1.2 s); one station decoded twenty times; two and
             three stations; four agreeing; five agreeing among nine scattered; a crowd
             split 1 s; observe the own call (any case), SNR -20.5/None/NaN, |DT| 3001 and
             3000; run windows through the rate limit, hysteresis, age 60 s / 60 s + 1 ms,
             a 100/101 ms system clock step, the 2 s fast system clock stepped back to
             UTC, a +5 s step, residuals 500/501 ms and a quiet band; the
             source combination table; Both with SNTP +12 ms, -1900 ms, -2226 ms and
             -2225 ms against the air.
             Oracles (hand-computed): -2025 ms 12/12 100 %; +1475 ms; with the bad clock
             -2025 ms 12 of 13 92 %; the chatty station one vote (-2050 ms 13/13); none
             from two, -1850 ms not confident from three; four confident; 5 of 9 (55 %) not
             confident; the split crowd 0 stations; only the two in-range observations
             admitted; applied -1000 (unsynchronized) then -2000 (synchronized) and kept;
             unknown after 60 s + 1 ms or a 101 ms step; stepping back clears the window
             and leaves correction 0, the +5 s step restarts at 0;
             500 ms synchronized, 501 ms unsynchronized; quiet unknown with nothing
             applied; only synchronized plans a transmit start; ntp source uncorrected
             and unknown without SNTP, air corrected -2000 ms and synchronized; Both on
             SNTP +12 ms uncorrected with disagreement 2037 ms warned, on the air basis
             -2000 ms at -1900 ms (125 ms, no warning), warned at 201 ms, not at 200 ms.
             2 — Isolated automated tests; Windows development PC, no audio, radio or
             network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-043-02';
            verify 'CL-043-03';
            verify 'CL-009-05';
        }
        attribute executable : String = "server/tests/transmit_air_clock.rs";
    }
    dependency CL_043_02_verified_by_TC_043_001 from 'CL-043-02' to 'TC-043-001';
    dependency CL_043_03_verified_by_TC_043_001 from 'CL-043-03' to 'TC-043-001';
    dependency CL_009_05_verified_by_TC_043_001 from 'CL-009-05' to 'TC-043-001';
    verification 'TC-043-002' {
        doc /* TC-043-002 — Clock from the air: stable feedback with the receive windows
             CL-043-03, CL-007-05
             Setup: (a) the AirClock in a closed receive loop of 40 FT8 periods: the crowd
             of TC-043-001 plus a +1.2 s bad clock, decodable only while their corrected DT
             lies in the live window coverage -1.7 s to +2.56 s, both windows completing
             each period; (b) the actual live worker, window buffer and ClockTracker with
             a scripted capture clock 300 ppm slow (actual Recording, clock source air).
             Steps: (a) station clock errors -2 s, +1.5 s, +0.6 s, 0, +2 s and +3 s; the negative
             control replaces the correction in full by an estimate from corrected DT;
             (b) 301 s of capture, the air correction becoming -2000 ms at 150 s; then
             publish one CQ K1ABC decode 17.0 s after the anchor with 0.5 s drift at
             correction -2000 ms and 0; (c) the live worker analyzes the FT8 prompt window
             of a period-aligned CQ K1ABC with the system clock 2 s slow and correction
             +2000 ms.
             Oracles: (a) the applied correction settles within 50 ms of error - 25 ms
             within two periods, never moves again and approaches monotonically (+2 s
             through the +1000 ms acquisition shift after four windows, settling at
             +1975 ms); +3 s never synchronizes over 20 periods, the correction only 0 or
             +1000 ms; the negative control alternates
             -2025, 0, -2025, ...; (b) 20 prompt windows (none lost or repeated), each after
             the first completing within 100 ms of +13.8 s of corrected UTC across the
             drift and the correction; the decode at period 00:00:15 with DT 0.0 s at
             -2000 ms and 2.0 s uncorrected, the estimator receiving raw DT 2000 ms both
             times; (c) the record, the FT8 SNR period start and the window diagnostics
             (period start frame and UTC, window offset -1200 ms) equal those of a correct
             clock, the SNR that of the file decode of the same period.
             2 — Isolated automated tests; Windows development PC, no audio device, radio
             or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-043-03';
            verify 'CL-007-05';
        }
        attribute executable : String = "server/tests/transmit_air_clock.rs; server/src/recording_tests.rs";
    }
    dependency CL_043_03_verified_by_TC_043_002 from 'CL-043-03' to 'TC-043-002';
    dependency CL_007_05_verified_by_TC_043_002 from 'CL-007-05' to 'TC-043-002';
    verification 'TC-043-003' {
        doc /* TC-043-003 — Clock source setting, wire and display
             CL-043-01, CL-043-03, CL-009-05
             Setup: the actual station router on a disposable profile directory with the
             station clock as main wires it (SNTP monitor that never measures); the actual
             transmit owner; the actual server and Chromium with transmit.state and GET
             /clock fixtures where stated.
             Steps: load clock.json missing, air, both, gps, AIR, a foreign profile,
             schema 2, an extra key, 1024 padding bytes and malformed JSON; GET /clock;
             POST air; GET /transmit; hear twelve stations in two windows; POST with another
             profile, another boot, v 2, source gps, an extra key, a missing key, a foreign
             or missing Origin and a query; reopen; on the transmit owner with source air
             hear two then six stations, read its clock and UTC, switch to ntp. In the
             browser: requests before Settings opens; open Settings > General; choose From
             the air; an estimate and a Both-disagreement fixture; a refused save; transmit
             views unknown/air, unknown/ntp, synchronized/air, synchronized/both with the
             warning, unsynchronized/both.
             Oracles: ntp for missing and every invalid file (invalid_clock), air/both read;
             exact view keys, default ntp unknown; the file exactly {schema_version 1,
             profile_id, source air}; GET /transmit clock_source air, clock_warning null,
             clock unknown; estimate -1555 ms 12/12 100 % with correction -1555 ms
             synchronized; 403 wrong_profile, 409 state_conflict, 400 unsupported_version,
             400 invalid_request (three), 403 forbidden_origin (two), 400; source still air
             and read back after reopen; the owner unknown with two stations, synchronized
             with six, station UTC 2000 ms (+-10 ms) behind the system clock, ntp unknown
             and uncorrected. Browser: no /clock request before Settings opens; one POST
             {v 1, profile_id, boot_id, source air}; the status line exactly "Clock
             synchronized by the air, correction -1980 ms · from the air: -1985 ms, 12 of
             14 stations (85 %), 3 s ago, synchronized"; the disagreement text; a refusal
             shows its code and restores the shown source; chips exactly Clock unknown ·
             Tx blocked, none, none, NTP and air clock disagree, Clock off · Tx blocked;
             the Clock line names the air correction.
             2 — Isolated automated tests; Windows development PC, loopback only, no
             public time server, audio or radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-043-01';
            verify 'CL-043-03';
            verify 'CL-009-05';
        }
        attribute executable : String = "server/src/clock_http_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_043_01_verified_by_TC_043_003 from 'CL-043-01' to 'TC-043-003';
    dependency CL_043_03_verified_by_TC_043_003 from 'CL-043-03' to 'TC-043-003';
    dependency CL_009_05_verified_by_TC_043_003 from 'CL-009-05' to 'TC-043-003';
    verification 'TC-043-004' {
        doc /* TC-043-004 — Live clock from the air on HB9BLA
             CL-043-01, CL-043-02, CL-043-03, CL-009-05
             Setup: the gated candidate installed on HB9BLA, IC-7300 on COM3, USB Audio
             CODEC, FT8 receive on a band with at least ten stations heard; for the transmit steps, RF power set by the test to at least 30 W before the first Tx (CI-V 14 0A, starting at 0090, with the station stopped and idle, because it holds COM3; read back; the first Tx must read Po at least 30 %; if below, raise the value and repeat; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported). Steps (1)-(4)
             keep the PC clock disciplined by NTP and need no administrator rights (agents
             have none); step (5), the issue's offset-clock check, is performed by the
             operator with administrator rights.
             Steps: (1) source ntp: read GET /clock for three periods (SNTP offset, air
             estimate). (2) choose From the air in Settings > General > Clock; read GET
             /clock and GET /transmit for three periods; read Band Activity DT. (3) choose
             Both, then ntp again. (4) with the operator's consent for transmit, with From
             the air synchronized, arm and send one CQ; check PSK Reporter spots of
             HB9BLA and a partner's DT. (5) operator, administrator: stop Windows Time
             (w32time) and any clock tool, set source From the air, set the PC clock
             1.5 s fast, wait four FT8 periods, read GET /clock, GET /transmit and Band
             Activity DT; repeat with the PC clock 1.5 s slow and 2.0 s slow; restore the
             clock and its service and source ntp.
             Expected: (1) state synchronized by NTP with |SNTP offset| at most 500 ms,
             the air estimate confident and within 200 ms of the SNTP offset (the Both
             disagreement bound; the crowd's own mean DT bias, typically +0.1 to +0.2 s,
             is recorded), disagreement_ms reported; (2) state synchronized by the air,
             correction_ms equal to the applied estimate within 50 ms, |correction_ms|
             within 200 ms, Band Activity median DT near 0 (within +-0.2 s), GET /transmit
             clock synchronized and clock_source air; no clock chip; (3) Both on the ntp
             basis with no warning while they agree within 200 ms; (4) the transmission is
             admitted, starts at the period start + 0.5 s of station UTC, and PSK Reporter
             spots and the partner's DT (within +-0.5 s) confirm the transmitted timing;
             (5) within four periods state synchronized by the air with correction_ms
             within 200 ms of -1500, +1500 and +2000 ms respectively, Band Activity median
             DT within +-0.2 s, GET /transmit clock synchronized (transmit admitted); a
             transmission under step (4)'s consent is spotted on time.
             Steps (1)-(3) and (5) without transmit are receive-only, cost 4; transmit
             steps are cost 5.
             5 — Live with transmit and external effects; explicit operator consent;
             HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-043-01';
            verify 'CL-043-02';
            verify 'CL-043-03';
            verify 'CL-009-05';
        }
    }
    dependency CL_043_01_verified_by_TC_043_004 from 'CL-043-01' to 'TC-043-004';
    dependency CL_043_02_verified_by_TC_043_004 from 'CL-043-02' to 'TC-043-004';
    dependency CL_043_03_verified_by_TC_043_004 from 'CL-043-03' to 'TC-043-004';
    dependency CL_009_05_verified_by_TC_043_004 from 'CL-009-05' to 'TC-043-004';

    // #44 Automatic radio detection and setup (operator decision 2026-11-01 on issue #44:
    // IC-7300 settings may be written via CI-V, each read back, old values kept for undo).
    // IC-7300 1A 05 item numbers: Icom IC-7300 Full Manual, section 19 "Control command",
    // command table pages 19-4/19-5.
    requirement 'CL-044-01' {
        doc /* POST /radio/detect {v 1, profile_id, boot_id, keying_inhibit_confirmed} (operating access and Origin as POST /receive/stop, exact keys, empty query) enumerates the present COM ports (port, friendly name, USB VID/PID, device instance), at most one detection at a time (a second is refused busy). Opening a port can pulse DTR/RTS before they are disabled (RadioIO: no guarantee of no initial USB-line glitch; USB SEND/CW/RTTY OFF or an independent inhibit before open), so detection is refused confirmation_required unless keying_inhibit_confirmed is true, the operator's confirmation that USB SEND and USB keying are OFF or the radio is on a dummy load; and only ports of a known radio USB bridge (Silicon Labs CP210x, VID 10C4 PID EA60) are opened, others are reported not_radio_bridge and never opened. Each such port is probed read-only: it is opened exclusively under the same per-device ownership claim as the CAT owner, with DTR and RTS disabled before the first byte and kept disabled, at 9600, 19200, 38400 and 115200 baud; at each rate it sends the CI-V broadcast "read transceiver ID" FE FE 00 E0 19 00 FD and, when no reply arrives, the same command addressed to each address of the model table. A reply FE FE E0 <address> 19 00 <id> FD identifies the address, the model and the rate; the station's own echo, collision (FC) frames, other traffic, garbage and timeouts are not replies. Probing never writes any other frame than these ID reads and the menu reads of CL-044-03: never a transmit, frequency, mode or setting command. Model table: 94h IC-7300 (station CAT supported), A4h IC-705, A2h IC-9700, 98h IC-7610 (identified, configured manually); Yaesu, Kenwood and Elecraft text CAT is not probed (listed as manual). A port held by another program or station reports in_use; the port of this station's running CAT owner (CL-022-03/04) is never opened a second time: it is reported from that owner, whose ID and menu reads go through the owner's single I/O lease. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_control/setup.rs; server/src/radio_control/windows.rs; server/src/radio_control/executor.rs; server/src/radio_control/actor.rs; server/src/radio_setup.rs; server/src/main.rs";
    }
    dependency CL_044_01_to_FR_009 from 'CL-044-01' to 'FR-009';
    dependency CL_044_01_to_FR_001 from 'CL-044-01' to 'FR-001';
    dependency CL_044_01_to_FR_008 from 'CL-044-01' to 'FR-008';
    requirement 'CL-044-02' {
        doc /* For each identified radio the detection matches the USB audio endpoints to its serial port by the shared USB parent: an active capture or render endpoint matches when its device has the same Windows container ID as the serial device (not the null container), or when the nearest USB device of both has the same parent hub and that parent is not a root hub. Exactly one matching capture and one matching render endpoint are proposed by their WASAPI endpoint IDs with their friendly names for display; none or several leave that side unproposed (state none or ambiguous). The response holds the proposal of the single supported radio found (none or several: proposal null): {port COMn, model, civ_address, baud, control {mode cat, endpoint icom7300://COMn?baud=<rate>&radio=<address>&controller=e0, ptt cat}, audio {input_device, output_device}}. Applying it is the operator's PUT /profile and the existing receive-only confirmation (CL-022-03); detection writes nothing. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_control/setup.rs; server/src/radio_control/windows.rs; server/src/audio/windows.rs; server/src/radio_setup.rs";
    }
    dependency CL_044_02_to_FR_002 from 'CL-044-02' to 'FR-002';
    dependency CL_044_02_to_FR_001 from 'CL-044-02' to 'FR-001';
    requirement 'CL-044-03' {
        doc /* For an identified IC-7300 the detection reads (1A 05, never written while detecting) DATA OFF MOD 0066, DATA MOD 0067, USB MOD level 0065, CI-V transceive 0071, USB SEND 0078, USB keying CW 0079 and USB keying RTTY 0080, and reports each value with guidance: USB SEND, CW and RTTY keying not OFF are blocking (a DTR/RTS line can key the transmitter; this station keys by CI-V 1C 00); DATA MOD other than USB is blocking (MIC/USB is advice); USB MOD level 0 is blocking; CI-V transceive ON is advice; DATA OFF MOD is information. The CI-V baud rate is not readable by CI-V and is reported as the rate the radio answered at. A refused (FA) read is reported unreadable. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_control/setup.rs; server/src/radio_setup.rs";
    }
    dependency CL_044_03_to_FR_009 from 'CL-044-03' to 'FR-009';
    dependency CL_044_03_to_FR_008 from 'CL-044-03' to 'FR-008';
    requirement 'CL-044-04' {
        doc /* "Apply recommended radio settings" is a separate operator action, never part of detection: POST /radio/settings/apply {v 1, profile_id, boot_id, connection_generation} (same access rules) requires this station's CAT owner ready on an IC-7300 (ID read 94h), the transmitter disarmed and the radio reporting RX. It reads the items, plans USB SEND OFF, USB keying CW OFF, USB keying RTTY OFF, DATA MOD USB and CI-V transceive OFF for each item that differs, saves the undo record radio-settings-undo.json in the profile directory {schema_version 1, profile_id, civ_address, items [{item, old, new}]} before the first write (an item already recorded keeps its first old value), then writes each item through the owner's lease and reads it back; a refused write, a mismatching readback or an exchange failure stops the remaining writes and is reported with the items done, and the record then keeps only items that may have changed (recorded before, written in this run, or the failed item unless it was refused FA or refused before its frame), so that undo restores them; an empty record is removed. POST /radio/settings/undo (same body and rules) writes each recorded old value back in reverse order with readback and removes the record only when all succeeded; without a record it is refused nothing_to_undo. Apply and undo never key the transmitter and never change frequency, mode or the profile. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_control/setup.rs; server/src/radio_control/executor.rs; server/src/radio_control/actor.rs; server/src/radio_setup.rs; server/src/profile.rs";
    }
    dependency CL_044_04_to_FR_009 from 'CL-044-04' to 'FR-009';
    dependency CL_044_04_to_FR_008 from 'CL-044-04' to 'FR-008';
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
    requirement 'CL-044-07' {
        doc /* GET /audio/endpoints (operating read access as GET /audio/devices, empty query and body) lists the audio endpoints by name without opening any audio device or serial port: exactly {v 1, profile_id, boot_id, inputs, outputs}; inputs are the active capture endpoints, outputs the active render endpoints, at most 64 each (more: device_limit), each exactly {id, name, label, present, radio}. name is the Windows friendly name (PKEY_Device_FriendlyName) with whitespace runs collapsed, trimmed, and no space after "(" or before ")" ("Microphone (USB Audio CODEC )" is "Microphone (USB Audio CODEC)"); the names of POST /radio/detect (input_name, output_name, audio name) are the same names. label is name; when two or more present endpoints of one flow have the same name, each of them gets " #n" (n from 1 in the order of their endpoint IDs), never the ID; when the profile's control is CAT on COMn and exactly one endpoint of the flow shares that port's USB parent (CL-044-02, from the present-port list; no port is opened), radio is "IC-7300" and the label ends " — IC-7300", else radio is null. A saved settings.audio.input_device or output_device that is not present is one more entry of its flow with present false, radio null, name its last known name or null, and label "<last known name> · not present" ("Unknown device · not present" without one). The station remembers the last known name of each saved endpoint in the profile document audio-endpoint-names.json {schema_version 1, names {id: name}} (only the saved endpoints, written only when it changes), refreshed at station start and on each listing; GET /receive audio.device_name is the known name of device_id (the names seen in the latest listing or the remembered ones), else null. An enumeration failure is 409 audio_unavailable, as GET /audio/devices. Strings are literal data. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_control/setup.rs; server/src/radio_setup.rs; server/src/recording.rs; server/src/main.rs";
    }
    dependency CL_044_07_to_FR_002 from 'CL-044-07' to 'FR-002';
    dependency CL_044_07_to_FR_019 from 'CL-044-07' to 'FR-019';
    requirement 'CL-044-08' {
        doc /* Settings > Radio has one Audio section (#settings-audio, a restart setting marked ⟳) holding all audio settings: the Input select with the Rx level meter beside it, the Output select, and the radio's recommendation. Each select offers "None" (null) and the endpoints of its flow from GET /audio/endpoints (read when the Settings drawer opens, at most every 5 s, and after Reload saved settings or a save); an option's text is the label of CL-044-07, its value the endpoint ID, and the ID appears only in the option's hover title and in Settings > Expert ("Audio endpoint IDs": the saved input and output IDs). A saved endpoint that is not present is shown as the selected, disabled option "<last known name> · not present"; while the listing is unavailable the saved value stays selected as "Saved device". There is no free-text endpoint input and no separate input listing. When an endpoint is marked with the radio, the section shows "Recommended: <input label> / <output label>" and the button "Use IC-7300 audio", which selects those endpoints and saves them with the same Apply ⟳ (one PUT /profile, with its usual confirmation); choosing in a select alone saves nothing. The Audio capability line in Expert names the running input by /receive audio.device_name. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/index.html; client/app.js; client/recording.js";
    }
    dependency CL_044_08_to_FR_019 from 'CL-044-08' to 'FR-019';
    dependency CL_044_08_to_FR_002 from 'CL-044-08' to 'FR-002';
    verification 'TC-044-006' {
        doc /* TC-044-006 — Endpoint names, labels and remembered names
             CL-044-07
             Setup: hand-written endpoint and port lists (no audio device): the CODEC capture "Microphone (USB Audio CODEC )" and render "Speakers (USB Audio CODEC )" under the IC-7300's USB hub with COM3, two capture endpoints both named "Headset Microphone (Sennheiser Communication Audio)" elsewhere; the actual router on a disposable profile with the injected detection hardware double.
             Steps: (a) label the capture and render lists with the profile control on COM3; (b) the same with control disabled; (c) a saved input that is absent, with and without a remembered name; (d) GET /audio/endpoints with the saved CODEC input, then with the CODEC unplugged from the double; GET /receive audio.device_name for a live receive on that input; reopen the remembered names; (e) a query, an enumeration failure.
             Expected: (a) "Microphone (USB Audio CODEC) — IC-7300" radio IC-7300, "Speakers (USB Audio CODEC) — IC-7300", the two headsets "... #1" and "... #2" ordered by ID, no label containing "{"; (b) the same names without the radio suffix, radio null; (c) "Microphone (USB Audio CODEC) · not present" present false, and "Unknown device · not present"; (d) exact key sets, the remembered name file holding only the saved IDs, after unplugging the saved input listed not present with its last name, device_name "Microphone (USB Audio CODEC)", the name still known after reopening; (e) 400 invalid_request, 409 audio_unavailable.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-07';
        }
        attribute executable : String = "server/src/radio_control/setup_tests.rs; server/src/radio_setup_tests.rs";
    }
    dependency CL_044_07_verified_by_TC_044_006 from 'CL-044-07' to 'TC-044-006';
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
    verification 'TC-044-001' {
        doc /* TC-044-001 — Read-only probe on scripted serial ports
             CL-044-01, CL-044-03
             Setup: the probe and the IC-7300 menu reader driven over scripted fake serial transports that record every configure, write and line state, independent hand-written CI-V byte scripts.
             Steps: (a) IC-7300 at 94h answering the broadcast only at 19200, with echo of every frame; (b) IC-705 answering only the addressed read at A4h at 115200; (c) collision frames FE FE FC FC FC FD and garbage bytes before the reply; (d) a silent port; (e) a port whose reads time out; (f) an unknown ID 99h; (g) the IC-7300 menu read with values 0078=01, 0079=00, 0080=02, 0066=00, 0067=03, 0065 0128, 0071=01, and a FA refusal of 0065; (h) a station whose CAT owner holds COM3, other CP210x ports and an FTDI port.
             Expected (hand table): (a) IC-7300, 94h, 19200; (b) IC-705, A4h, 115200, manual; (c) identified as (a); (d) and (e) no_reply after all four rates; (f) unknown_model with ID 99h; every written frame is FE FE 00 E0 19 00 FD, FE FE <table address> E0 19 00 FD or FE FE 94 E0 1A 05 00 <item> FD, the lines are disabled before the first write and never raised; (g) values and guidance: usb_send DTR blocking, rtty RTS blocking, data_mod USB ok, level 128 ok, transceive advice, FA unreadable; (h) COM3 is never opened, reported station_cat from the owner, the CP210x ports probed, the FTDI port not_radio_bridge and never opened.
             2 — Isolated automated tests; Windows development PC, no serial port, radio or RF. */
        // Partial: the line state (lines disabled before the first write, never raised) is not asserted: the fake records configure and write only.
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-044-01';
            verify 'CL-044-03';
        }
        attribute executable : String = "server/src/radio_control/setup_tests.rs; server/src/radio_setup_tests.rs";
    }
    dependency CL_044_01_verified_by_TC_044_001 from 'CL-044-01' to 'TC-044-001';
    dependency CL_044_03_verified_by_TC_044_001 from 'CL-044-03' to 'TC-044-001';
    verification 'TC-044-002' {
        doc /* TC-044-002 — Audio matching, proposal, validation and migration
             CL-044-01, CL-044-02, CL-044-05
             Setup: fake port and endpoint lists with hand-written container IDs and USB parents; the actual router on a disposable profile with an injected detection hardware double.
             Steps: (a) one IC-7300 port and its CODEC capture and render under the same hub, a webcam microphone elsewhere; (b) two capture endpoints under the hub; (c) same container ID, different parents; (d) only a root-hub parent shared; (e) POST /radio/detect valid, other profile, other boot, extra key, v 2, without keying_inhibit_confirmed, with it false, foreign Origin, a query, a concurrent second detect; (f) PUT /profile with "Speakers (USB Audio CODEC )", a capture ID as output, a render ID as input, valid IDs, null; (g) startup migration with a unique name, a duplicated name, an unknown name and an ID.
             Expected: (a) proposal COM3 IC-7300 94h 19200, endpoint icom7300://COM3?baud=19200&radio=94&controller=e0, ptt cat, both CODEC endpoint IDs; (b) input ambiguous, output proposed; (c) matched; (d) none; (e) 200 report, 403 wrong_profile, 409 state_conflict, 400 invalid_request, 400 unsupported_version, 400 invalid_request, 409 confirmation_required, 403 forbidden_origin, 400, 409 busy; (f) 400 audio_device_not_endpoint with the field for the first three, 200 for the rest; (g) ID saved with revision + 1, the others unchanged with reasons ambiguous, not_found, unchanged.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        // Partial: (e) the concurrent second detect is not run (the test sets busy itself); (a) no test proposes COM3 at 19200 (the tests show COM3 at 9600 from the station CAT and an unconfigured COM4 at 19200).
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-044-01';
            verify 'CL-044-02';
            verify 'CL-044-05';
        }
        attribute executable : String = "server/src/radio_control/setup_tests.rs; server/src/radio_setup_tests.rs; tests/profiles.test.cjs";
    }
    dependency CL_044_01_verified_by_TC_044_002 from 'CL-044-01' to 'TC-044-002';
    dependency CL_044_02_verified_by_TC_044_002 from 'CL-044-02' to 'TC-044-002';
    dependency CL_044_05_verified_by_TC_044_002 from 'CL-044-05' to 'TC-044-002';
    verification 'TC-044-003' {
        doc /* TC-044-003 — Apply recommended radio settings and undo
             CL-044-04
             Setup: the actual Recording owner and CAT actor on a scripted IC-7300 transport holding menu values 0078=01, 0079=00, 0080=02, 0067=00, 0071=01; the actual router on a disposable profile.
             Steps: apply; read the undo record; apply again; undo; undo again; apply with the radio reporting TX; apply with the transmitter armed; apply with a radio that answers FA to 0080; apply with a radio whose readback of 0067 stays 00; apply against an IC-705 ID; HTTP refusals as TC-044-002 (e).
             Expected: writes FE FE 94 E0 1A 05 00 78 00 FD, 00 80 00, 00 67 03, 00 71 00 each acknowledged and read back, never 0079; the record holds {0078 1→0, 0080 2→0, 0067 0→3, 0071 1→0} before the first write; the second apply writes nothing and keeps the record; undo writes 0071=01, 0067=00, 0080=02, 0078=01 in that order and removes the record; the second undo nothing_to_undo; TX and armed refused with no write; FA stops after 0078 with the failed item named and the record reduced to 0078 1→0, a following undo writes 0078=01 and removes the record; TX leaves no record; mismatch reported readback_mismatch; IC-705 refused unsupported_radio; no 1C 00 01, frequency or mode frame in any case.
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        // Partial: the undo record is read only after apply returns, not before the first write; no test checks for 1C 00 01, frequency or mode frames in the TX, FA and readback-mismatch cases.
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-044-04';
        }
        attribute executable : String = "server/src/radio_setup_tests.rs";
    }
    dependency CL_044_04_verified_by_TC_044_003 from 'CL-044-04' to 'TC-044-003';
    verification 'TC-044-004' {
        doc /* TC-044-004 — Live detection and setup on HB9BLA
             CL-044-01, CL-044-02, CL-044-03, CL-044-04, CL-044-05
             Setup: the gated candidate installed on HB9BLA with only the IC-7300 plugged in, its USB Audio CODEC, the operator present.
             Steps: Detect radio; compare the proposal; apply it with the receive-only confirmation; read the settings check; Apply recommended radio settings; Undo; Apply again; FT8 transmit test on a dummy load or a clear frequency.
             Expected: proposal COM3, IC-7300, 94h, the station baud, the CODEC capture and render endpoint IDs; CAT ready after apply; the radio never keys during detection; the menu values match the radio's menu; undo restores them; the transmit test produces RF with audio from USB.
             4 — Live on the station with the operator's consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-044-01';
            verify 'CL-044-02';
            verify 'CL-044-03';
            verify 'CL-044-04';
            verify 'CL-044-05';
        }
    }
    dependency CL_044_01_verified_by_TC_044_004 from 'CL-044-01' to 'TC-044-004';
    dependency CL_044_02_verified_by_TC_044_004 from 'CL-044-02' to 'TC-044-004';
    dependency CL_044_03_verified_by_TC_044_004 from 'CL-044-03' to 'TC-044-004';
    dependency CL_044_04_verified_by_TC_044_004 from 'CL-044-04' to 'TC-044-004';
    dependency CL_044_05_verified_by_TC_044_004 from 'CL-044-05' to 'TC-044-004';

    // #44 AGC as a station-managed radio setting (operator decision 2026-11-04 on #44,
    // comment 6626074726: AGC SLOW removed the IC-7300 AGC recovery line between FT8
    // periods, #54) and the operator rule of 2026-11-04: CI-V reads first and changes a
    // setting only when it does not fit. IC-7300 AGC: Icom IC-7300 Full Manual section 19,
    // command table "16 12 AGC" (01 FAST, 02 MID, 03 SLOW; read: the command without data).
    requirement 'CL-044-09' {
        doc /* Every CI-V change of a radio setting by the station is read, compare, write, verify: the station first reads the setting's current value; when it already equals the wanted value no write frame is sent and the read is the confirmation; otherwise it sends the write with the radio in RX (1C 00 00, checked as stated at the end of this clause), requires its ACK (FB; FA is refused radio_rejected) and reads the setting back, a different value being readback_mismatch and a failed readback indeterminate. No write is sent while this station's transmit hold is taken (the CAT owner's single lease excludes it). The transmit switch 1C 00 is a keying action, not a setting, and is not subject to this rule (CL-009 PTT readback). The rule holds for every setter path of the station: the AGC (16 12, CL-044-10); the receive setup of a mode or band selection, where mode (06), DATA mode (1A 06) and frequency (05) are each read first and written only when they differ, and the final state is read again only after a write (with nothing written the three reads are the confirmation); the CAT owner's single setter operations SetFrequency, SetMode and SetData, which answer from the read without a write when the value fits (POST /radio/operation itself refuses these three with selection_unavailable and sends no frame); and the IC-7300 menu writes of Apply recommended radio settings and Undo (1A 05, CL-044-04), where an item already at its value is not written again. A setter whose read is refused (FA) is refused radio_rejected without a write. The RX check of a write is per write for 16 12 and 1A 05; the 05, 06 and 1A 06 setters of a selection's receive setup rely on the selection's single RX read (1C 00) inside its CAT reservation, before the first of them. With all three differing a receive setup is twelve exchanges inside the 5 s composite bound (TC-009-005 proves it at 360 ms per exchange, down from 470 ms for the nine exchanges without the reads); the CAT owner's single setter operations have no RX check of their own, and no route reaches them. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_control/executor.rs; server/src/radio_control/actor.rs";
    }
    verification 'TC-044-012' {
        doc /* TC-044-012 — Existing CI-V setters read first
             CL-044-09
             Setup: the actual executor on the scripted CI-V transport of TC-009-001 (hand-written replies, every written frame recorded).
             Steps: (a) the CAT owner's SetFrequency 14.074 MHz, SetMode USB FIL2 and SetData ON FIL2 with the radio already there, then each with its read answered FA; (b) SetFrequency with the radio at 7.074 MHz; (c) the receive setup 14.074 MHz USB-D FIL2 with the radio already there; (d) with the radio at USB FIL1, DATA OFF, 7.074 MHz; (e) a 1A 05 write of USB SEND OFF with the item already OFF, and with it at DTR.
             Expected: (a) one read frame each (03, 04, 1A 06) and no setter frame; with FA radio_rejected, the same single frame and the connection open; (b) 03, 05 00 40 07 14 00, 03, the frequency fact unconfirmed when the setter frame is sent and confirmed by the read-back; (c) 04, 1A 06, 03 and nothing else; (d) 04, 06 01 02, 04, 1A 06, 1A 06 01 02, 1A 06, 03, 05 00 40 07 14 00, 03, then the final 04, 1A 06, 03; (e) only FE FE 94 E0 1A 05 00 78 FD, then 1A 05 00 78, 1C 00, 1A 05 00 78 00, 1A 05 00 78; a read answered FA is refused with no further frame.
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-09';
        }
        attribute executable : String = "server/tests/radio_control.rs; server/src/radio_control/executor.rs";
    }
    dependency CL_044_09_verified_by_TC_044_012 from 'CL-044-09' to 'TC-044-012';
    dependency CL_044_09_to_FR_009 from 'CL-044-09' to 'FR-009';
    requirement 'CL-044-10' {
        doc /* The radio profile holds the radio settings the station manages: settings.radio {agc FAST|MID|SLOW}, present exactly when settings.control is CAT with an endpoint that is a supported IC-7300 CI-V configuration (the only radio with a known CI-V AGC command; every other control has no settings.radio key and the setting is hidden). GET /profile and the PUT response carry it; PUT /profile refuses settings.radio for an unmanaged control (400 invalid_settings, field radio) and settings.radio.agc outside FAST/MID/SLOW (400 invalid_settings, field settings.radio.agc); a PUT without settings.radio keeps the saved value, or takes SLOW for a newly managed radio. settings.radio is not part of settings.control, so changing it never changes the receive-only CAT confirmation's checked control (CL-022-03); like every profile save it advances the revision, which reconnects CAT. Migration: a profile saved without radio whose control is IC-7300 CAT is read with agc SLOW (the FT8/FT4 default); other profiles stay without it; the file is rewritten only by a later save. The station applies the saved AGC with one read-compare-write-verify exchange (CL-044-09; CI-V read FE FE <address> E0 16 12 FD, write FE FE <address> E0 16 12 <01|02|03> FD) through its CAT owner: once per ready connection (a refusal busy, e.g. the lease held or the radio reporting TX, is tried again after 2 s; any other outcome ends the attempt for that connection) and on each FT8 or FT4 mode selection inside the selection's CAT reservation, after its receive setup and before receive restarts. Nothing is sent while the transmitter is armed, tuning or transmitting (the connection attempt waits for disarm). An AGC failure never fails the selection. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; server/src/main.rs; server/src/radio_agc.rs; server/src/radio_control/setup.rs; server/src/radio_control/executor.rs; server/src/radio_control/actor.rs; server/src/recording.rs; server/src/authorization_http.rs";
    }
    dependency CL_044_10_to_FR_009 from 'CL-044-10' to 'FR-009';
    dependency CL_044_10_to_FR_001 from 'CL-044-10' to 'FR-001';
    requirement 'CL-044-11' {
        doc /* The server pushes the AGC state (client-server rule of #10): each WebSocket peer with a display subscription receives radio.agc {v 1, type radio.agc, data {profile_id, boot_id, target, connection_generation, value, result, trigger}} once the station has an AGC target and then after each change (target the saved AGC or null; value the AGC the radio reported last or null; result unchanged, written or the radio error code, null before the first exchange; trigger connect or selection); nothing is polled. Settings > Radio, CAT group: an AGC select FAST/MID/SLOW, shown only while the form's control is CAT with an IC-7300 endpoint, saved with Apply ⟳ as settings.radio.agc (a hidden select sends no radio key), and below it the read-back line from radio.agc: "Radio AGC <value> · read back, already as set", "Radio AGC <value> · set to <target> and read back", "Radio AGC <target> not applied · <result>". Detect radio (CL-044-02) proposes radio {agc SLOW} with the IC-7300 proposal, shows the row "AGC SLOW · recommended for FT8/FT4", and "Use this setup" sets the AGC select. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_agc.rs; server/src/main.rs; server/src/radio_setup.rs; client/index.html; client/app.js; client/recording.js";
    }
    dependency CL_044_11_to_FR_019 from 'CL-044-11' to 'FR-019';
    dependency CL_044_11_to_FR_009 from 'CL-044-11' to 'FR-009';
    verification 'TC-044-008' {
        doc /* TC-044-008 — AGC CI-V read, compare, write, verify on the scripted IC-7300
             CL-044-09, CL-044-10
             Setup: the actual CAT actor and executor on a scripted IC-7300 transport (echo of each frame, hand-written replies) holding AGC 01, 02 or 03; independent byte expectations from the IC-7300 command table.
             Steps: (a) EnsureAgc SLOW with the radio at SLOW; (b) with the radio at MID; (c) with the radio reporting TX and MID; (d) a radio that answers FA to the write; (e) a radio that acknowledges but stays MID; (f) a radio that answers FA to the read; (h) the codec: frames and decoding of 16 12 replies, an unknown code 04.
             Expected: (a) exactly one written frame FE FE 94 E0 16 12 FD, reply SLOW, written false; (b) frames FE FE 94 E0 16 12 FD, FE FE 94 E0 1C 00 FD, FE FE 94 E0 16 12 03 FD, FE FE 94 E0 16 12 FD in this order, written true; (c) busy after the read and the RX check, no 16 12 03 frame; (d) radio_rejected; (e) readback_mismatch; (f) radio_rejected and no write; (h) FAST 01, MID 02, SLOW 03; 04 is no AGC. CAT stays ready in (a)-(f).
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-09';
            verify 'CL-044-10';
        }
        attribute executable : String = "server/src/radio_agc_tests.rs";
    }
    dependency CL_044_09_verified_by_TC_044_008 from 'CL-044-09' to 'TC-044-008';
    dependency CL_044_10_verified_by_TC_044_008 from 'CL-044-10' to 'TC-044-008';
    verification 'TC-044-009' {
        doc /* TC-044-009 — AGC applied on connect and FT8/FT4 selection, never while transmitting; profile field and migration
             CL-044-10, CL-044-11
             Setup: the actual router, Recording owner, CAT lifecycle tick and CAT actor on a disposable profile with a scripted IC-7300 on COM3.
             Steps: (a) profile with IC-7300 CAT and agc SLOW, radio at MID: AGC tick after ready, then another tick; (b) radio already at SLOW; (c) radio reporting TX: tick, then RX after 2 s; (d) the transmitter armed: tick; (e) FT8 band selection with the radio changed to FAST meanwhile; (f) FT4 mode selection with the radio at SLOW; (g) radio.agc event before and after (a); (h) profile files: IC-7300 CAT without radio, CAT disabled without radio, GET /profile; PUT without radio, with agc MID, with agc LOW, with radio for a disabled control; (i) Detect radio proposal.
             Expected: (a) one 16 12 03 write after the read, read back, status written SLOW, the second tick sends nothing; (b) only the read, status unchanged; (c) no write while TX (busy), the write after RX; (d) no AGC frame at all; (e) a 16 12 03 write inside the selection after the dial setter, trigger selection; (f) only the AGC read, result unchanged, trigger selection; (g) target SLOW with result null, then value SLOW result written; (h) settings.radio {agc SLOW} for IC-7300, no radio key for disabled, the file unchanged; PUT keeps SLOW, saves MID, 400 settings.radio.agc, 400 radio; (i) proposal radio {agc SLOW}.
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-10';
            verify 'CL-044-11';
        }
        attribute executable : String = "server/src/radio_agc_tests.rs; server/src/radio_setup_tests.rs";
    }
    dependency CL_044_10_verified_by_TC_044_009 from 'CL-044-10' to 'TC-044-009';
    dependency CL_044_11_verified_by_TC_044_009 from 'CL-044-11' to 'TC-044-009';
    verification 'TC-044-010' {
        doc /* TC-044-010 — AGC field and read-back in Settings > Radio
             CL-044-11
             Setup: actual candidate server on a disposable plaintext profile with IC-7300 CAT (not authorized, so no CAT owner opens anything) and Chromium; radio.agc events injected into the page's station-message stream as the server sends them; /radio/detect answered by a route fixture with the IC-7300 proposal.
             Steps: open Settings > Radio; read the AGC select; deliver radio.agc written SLOW, then a busy result; choose MID and Apply ⟳; GET /profile; set control Disabled; restore CAT, Detect radio with the proposal and Use this setup; 360 px width.
             Expected: the AGC select in the CAT group shows SLOW (migrated default); the read-back line "Radio AGC SLOW · set to SLOW and read back", then "Radio AGC SLOW not applied · busy"; the saved profile holds settings.radio.agc MID; with control Disabled the select and line are hidden; the proposal row "AGC SLOW · recommended for FT8/FT4" and the select set to SLOW; no horizontal scroll at 360 px; no page error.
             2 — Isolated automated browser test; Windows development PC, no radio, serial port or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-11';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_044_11_verified_by_TC_044_010 from 'CL-044-11' to 'TC-044-010';
    // Operator decisions 2026-11-04 (#44 comments 6627977497, 6628000054): Tx audio level.
    // IC-7300 meters: Icom IC-7300 Full Manual section 19, command table "15 11 Po" (0000 0 %,
    // 0143 50 %, 0213 100 %), "15 12 SWR" (0000 1.0, 0048 1.5, 0080 2.0, 0120 3.0), "15 13 ALC"
    // (0000..0120 the ALC zone); data two BCD bytes 0000..0255. The repository holds no copy of
    // that table beyond this citation; TC-044-015 confirms it on the radio.
    requirement 'CL-044-12' {
        doc /* Tx level and Set level. The Tx level is a digital attenuation of the station's Tx audio, -40..0 dB in whole dB below the playback scale (Transmit TransmitTiming playbackScale), stored per radio profile in tx-level.json of the profile directory {schema_version 1, level_db}; storing it does not advance the profile revision and so does not reconnect CAT. Without a stored level, or with an invalid file, it is 0 dB. Set level is the default way to set it: POST /radio/tx-level {v, profile_id, boot_id, command_id, action set_level, tx_offset_hz} (transmit authority as Tune: a current CL-022 grant, otherwise 401 unauthorized; malformed 400 invalid_request; reply 200 {v, profile_id, boot_id, command_id, accepted, refusal}, refused busy while a transmission, a pending request, a Tune or another run is active, otherwise with the transmit refusal). It arms when disarmed and disarms again at its end, starts Tune at -30 dB and, every 400 ms, reads the meters and decides: ALC above 0 or Po above the profile power settings.radio.power_limit_pct (1..100; absent: no limit but the radio's own RF power setting) stores one step below the current level, never below -40 dB (result stored); 0 dB reached without either stores 0 dB (result max_without_alc); otherwise one step up. SWR at or above 3.0 (raw 0120) stops without storing (result high_swr); an ALC read refused FA stops without storing (result no_alc). It always ends with Tune stopped. HALT, the Tune limit or any other loss of Tune aborts it without storing (result aborted), and every failure leaves the prior level. A manual level (action manual, level_db -40..0) exists only after the radio refused the ALC read (otherwise refused alc_available) and applies to a running Tune at once. A transmission takes the level at its audio start and keeps it to its end. A meter read is one burst of reads FE FE <address> E0 15 13 FD, 15 11, 15 12 (one reply each; FA: that meter is missing), bounded at 400 ms in total, admitted only while this station holds the transmit hold (otherwise Busy with no byte). It takes no lease, so no operation or poll can start through it and it cannot delay a key; a PTT exchange cancels it at once, so the 250 ms halt bound holds; a timeout or cancel leaves the connection open. While Tune runs outside Set level the station reads the meters once per second on its own thread. Reads only: this slice writes no radio setting. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_level.rs; server/src/radio_control/actor.rs; server/src/radio_control/executor.rs; server/src/radio_control/setup.rs; server/src/transmit/service.rs; server/src/transmit_http.rs; server/src/playback.rs; server/src/profile.rs";
    }
    dependency CL_044_12_to_FR_009 from 'CL-044-12' to 'FR-009';
    requirement 'CL-044-13' {
        doc /* The server pushes the Tx level state (client-server rule of #10): each WebSocket peer with a display subscription receives radio.tx_level {v 1, type radio.tx_level, data {profile_id, boot_id, managed, level_db, stored, alc unknown|available|unavailable, assistant, result, meters null|{alc, po_pct, swr_x10}, power_limit_pct, warnings [...] (CL-044-14), keying_confirmed (CL-044-15)}} after each change; nothing is polled. Settings > Radio > Audio shows, for an IC-7300 CAT control only, a Set level button, a line with the level and the last result, the last ALC, Po and SWR, and the optional Profile power field (settings.radio.power_limit_pct) saved with Apply; the Tx level slider is shown only with alc unavailable. Set level and the slider send POST /radio/tx-level; a refusal is shown on the line. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_level.rs; server/src/main.rs; client/recording.js; client/app.js";
    }
    dependency CL_044_13_to_FR_019 from 'CL-044-13' to 'FR-019';
    dependency CL_044_13_to_FR_009 from 'CL-044-13' to 'FR-009';
    // Operator decision 2026-11-04 (#44 comment 6628026397): monitoring in normal operation.
    // Operator decision 2026-11-06 (#44, live ALC 31-32 at Po 102 %): the level lowers above ALC 10.
    requirement 'CL-044-14' {
        doc /* In normal operation the station reads the radio's meters exactly once per transmission, in the middle of its audio: the transmit step calls the read when half of the audio remaining at audio start has played, once per transmission, on no Tune, and not at all when less than 2 s of audio remained at audio start. The call returns at once and the burst (CL-044-12: 15 13, 15 11, 15 12) runs on its own thread, so the transmit step, the audio and the release never wait for the radio, and a PTT exchange cancels the burst. Nothing is read while Set level runs. From the reading the level moves by at most one step, stored like CL-044-12 and taken by the next transmission's audio start only: ALC above raw 0010 or Po above the profile power: one down, not below -40 dB; else ALC exactly 0 and Po below 80 % of the profile power: one up, not above 0 dB and not back to the ceiling; otherwise unchanged. A lowering on the reading right after a step up makes the level just left the ceiling, so a level reading 0 below a level reading above 0010 settles on the lower one; any other lowering leaves the step up free, so the level follows a drive that falls later. The ceiling lives in memory until a stored Set level, a changed profile power or a restart. Set level's stop (CL-044-12, ALC 0, one step below the first rise) is inside this window, and one step up from it, the ALC onset (reads 4-7, about 6 per dB on the IC-7300), stays inside it. Without a profile power Po is neither over nor low, so there is no step up. Persistent trouble is an entry in the error field, from the third transmission in a row until a reading without it: alc_high (ALC at or above raw 0060, half the ALC zone; lowering below that is routine and shows no entry), po_low (Po below half the profile power), swr_high (SWR at or above 2.0, raw 0080). A clear fault, SWR at or above 3.0 (raw 0120), stops transmitting at once through the priority halt (DisarmCause halt) with the entry swr_fault, and automation may not arm again until an operator action (WatchdogFromOperator); the entry stays until a later reading below 3.0 or a stored Set level. The radio.tx_level data carries these as warnings [...]. A failed read judges nothing. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_level.rs; server/src/transmit/service.rs; server/src/transmit_http.rs; client/recording.js; client/contact.js";
    }
    dependency CL_044_14_to_FR_009 from 'CL-044-14' to 'FR-009';
    verification 'TC-044-017' {
        doc /* TC-044-017 — One meter read per transmission and its bounded correction
             CL-044-14
             Setup: the actual transmit core on a virtual clock; the actual Recording, transmit owner on a recording double and CAT actor on a scripted IC-7300 reporting set meter values.
             Steps: (a) the decision table; (b) two FT8 transmissions and a Tune on the virtual clock; (c) the call without the hold, then with ALC 0060; (d) three transmissions in a row, then a good one; (e) SWR 0120, a reading without SWR, then the operator arms and SWR is clear; (f) the call while Set level runs; (g) the transmit step's call through the station's boxed hardware to the sink, and the sink startup installs; (h) ALC 0060 with the level file unwritable; (i) a radio reading ALC 0 at -10 dB and 0011 at -9 dB with low Po, 40 transmissions; (j) ALC 0031 at -9 dB moving 6 per dB, 40 transmissions; (k) Set level and then the correction on a radio with ALC 0 up to -9 dB and 0007 at -8 dB, rising 6 per dB, with low Po; (l) a step up, ALC 0011 and then 0 with low Po, the same profile power and then a changed one, again a step up and ALC 0011, and a stored Set level at the ceiling; (m) ALC 0013 with no step up before it, then ALC 0 twice with low Po, then 0005, 0013 and 0.
             Expected: (a) one down at ALC 0011, none at 0010, no warning from three readings of 0059, the floor and 0 dB hold, one up only with ALC 0 and Po below 80 %, none without a profile power, one down above it, none without ALC, fault at 0120 and not at 0119, warnings from the third reading, cleared by one good reading; (b) due exactly once at period + 6 820 ms in each, none for Tune, none for audio starting at period + 11 200 ms; (c) no byte without the hold; with it exactly 15 13, 15 11, 15 12, level -11 stored, nothing handed to the running audio; (d) alc_high from the third, level -13, gone with the good one; (e) one halt, disarmed halt, automation refused, entry swr_fault; the entry stays with the reading without SWR; after the clear reading no entry and still armed; (f) no byte; (g) one call reaches the sink, one burst from the installed sink; (h) the level stays -10, stored false, and the next Tune plays -10; (i) -10 dB for good after at most two transmissions from -10 dB and three from -9 dB, no warning; (j) -10, -11, -12, -13 dB and then unchanged, no warning; (k) Set level stores -9 dB, the correction takes it to -8 dB and stays, from -7 dB it comes back to -8 dB and stays; (l) the level stays with ALC 0 and the same profile power, and goes up one after the changed profile power and after the stored Set level; (m) -13, -12, -11, -11, -12, -11 dB.
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-14';
        }
        attribute executable : String = "server/src/radio_level_tests.rs; server/src/transmit_http_tests.rs; server/tests/transmit_service.rs";
    }
    dependency CL_044_14_verified_by_TC_044_017 from 'CL-044-14' to 'TC-044-017';
    verification 'TC-044-018' {
        doc /* TC-044-018 — Tx trouble in the error field
             CL-044-14
             Setup: candidate server and Chromium; radio.tx_level events injected.
             Steps: inject the four warnings, then none.
             Expected: one error field entry each, swr_fault with error severity and the others warn, all gone after the empty list.
             2 — Isolated automated browser test; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-14';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_044_14_verified_by_TC_044_018 from 'CL-044-14' to 'TC-044-018';
    verification 'TC-044-019' {
        doc /* TC-044-019 — Monitoring on HB9BLA
             CL-044-14
             Setup: the gated candidate installed on HB9BLA with the IC-7300, the operator's consent, 40 m, RF power set by the test to at least 30 W before the first Tx (CI-V 14 0A, starting at 0090, with the station stopped and idle, because it holds COM3; read back; the first Tx must read Po at least 30 %; if below, raise the value and repeat; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported). The mismatched-antenna / SWR 3.0 stop step is dropped by operator decision of 2026-11-08 ("bad SWR is handled by the transceiver"); the station's own stop at and above SWR 3.0 stays (CL-044-14), covered offline; the SWR display is #68.
             Steps: transmit during normal operation and record the radio.tx_level frames and the transmit timing; transmit with ALC above 0010. The evidence is the CI-V readback and the radio.tx_level frames, not the radio's display or a CI-V log (operator decision of 2026-11-08; the station keeps no CI-V log).
             Expected: at most one radio.tx_level meter frame per transmission (sent only when the values change); decode by another station unaffected; ALC above 0010 goes down one step at the next transmission until it reads 0010 or less, with no entry below 0060.
             5 — Live with RF on the station, operator consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-044-14';
        }
    }
    dependency CL_044_14_verified_by_TC_044_019 from 'CL-044-14' to 'TC-044-019';
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
    // Operator requirement 2026-11-06 (#44 comment 6679345317, from #22): pragmatic discovery.
    requirement 'CL-044-15' {
        doc /* Coordinator default pending the operator (#44 comment 6682191117): the keying risk of an open is not accepted, so nothing opens automatically without the persisted confirmation. Discovery opens no port at all until the operator has confirmed keying inhibit once: the tick and press of Detect radio (CL-044-01) stores it in radio-keying-confirmed.json of the profile, and Settings > Radio says so until then (radio.tx_level data keying_confirmed). A commissioned saved radio still opens under CL-022-03 through the CAT lifecycle regardless. With the confirmation, on start, before the CAT lifecycle first runs, the station discovers its radio read-only: the same port opening as Detect radio (the per-device ownership claim, DTR and RTS low) and the same probe (CI-V 19 00 only, CL-044-01). A profile with control cat whose saved endpoint's port is present and answers with a radio this station has CAT for keeps its radio, and no other port is opened. Otherwise (the port is held by another station process or another program, is absent or silent), and on a profile never saved (revision 0, control disabled), the ports on a known radio USB bridge are tried in port order, without the saved one and within the budget: a port that cannot be opened is passed over, which is how a radio another station process holds is recognised, and a radio discovery chose or kept is also reserved for the life of the process (a lock per port under radio-reservation), so a station waiting for its confirmation holds it too; a port reserved by another process is passed over, so each process takes the next free radio and more than one transceiver on one PC works. The first that answers with such a radio is saved as the profile's control (icom7300://COMn?baud=b&radio=aa&controller=e0, ptt kept from a CAT control, otherwise cat), with the capture and render endpoints that match it and none otherwise (never the old radio's audio); settings.radio stays or takes the default; its stored Tx level (CL-044-12) and settings undo (CL-044-03) are removed, they belonged to the other radio. This is a profile save, so the revision advances and the receive-only confirmation (CL-022-03) binds to the new control: CAT opens only after the operator confirmed this radio. Nothing is found: nothing changes and the lifecycle keeps retrying the saved endpoint. A control of an operator's saved Disabled, or an endpoint that does not parse, is left alone and no port is opened. Discovery runs once per process start, before the station listens and before anything loads the Tx level or the audio names, so a port that does not answer delays listening by its probe; all of discovery, saved port included, ends within 40 s (each probe is cut at that bound). It does not write a radio setting. WSTX_RADIO_DISCOVERY=off turns it off, for the test stations. Limit: a saved radio reserved by another process with no other radio free changes nothing, and the lifecycle retries it. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_setup.rs; server/src/radio_level.rs; server/src/main.rs; client/recording.js";
    }
    dependency CL_044_15_to_FR_009 from 'CL-044-15' to 'FR-009';
    verification 'TC-044-020' {
        doc /* TC-044-020 — Discovery on start
             CL-044-15
             Setup: the actual profile store and authorization owner, a detection hardware double of ports, held ports, radios and audio endpoints, recording every frame.
             Steps: (a) saved COM3 answers, COM5 too; (b) saved COM3 held, COM4 held, COM5 silent, COM6 an IC-7300 with matching audio; (c) saved silent, the other held; (d) an operator's saved Disabled with a radio present; (e) a profile never saved with an FTDI board, an IC-705 and an IC-7300; (f) three stations in turn on two free radios, the third with a saved one already reserved; (g) no confirmation with a radio present, never saved and saved, then Detect radio without and with the tick; (h) three silent ports with a 200 ms budget.
             Expected: (a) nothing saved, only COM3 opened; (b) control COM6 with the probed rate and address, a disabled ptt kept, the matching endpoints, settings.radio kept, the Tx level and undo files gone, revision +1, ports opened 3, 4, 5, 6; on the actual authorization owner, a commissioned control moved this way gives CommissioningRequired, no commissioning, safety revision +1 and the new checked control; (c) nothing saved; (d) no port opened; (e) COM6, ptt cat, the FTDI board never opened; (f) COM3, then COM6, and the third keeps its saved control; (g) no port opened, keying_confirmed false; no file after the refused Detect, the file and keying_confirmed true after the other, and only then the saved port is opened; (h) only the first opened, over in under 2 s; in all of them only 19 00 frames are written.
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-15';
        }
        attribute executable : String = "server/src/radio_setup_tests.rs; server/src/auth_tests.rs";
    }
    dependency CL_044_15_verified_by_TC_044_020 from 'CL-044-15' to 'TC-044-020';
    verification 'TC-044-022' {
        doc /* TC-044-022 — The one-time confirmation in Settings
             CL-044-15
             Setup: candidate server and Chromium; radio.tx_level events injected.
             Steps: inject keying_confirmed false, then true.
             Expected: the Detect radio section says discovery is off until confirmed once, then that it is on.
             2 — Isolated automated browser test; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-15';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_044_15_verified_by_TC_044_022 from 'CL-044-15' to 'TC-044-022';
    verification 'TC-044-021' {
        doc /* TC-044-021 — Discovery on HB9BLA
             CL-044-15
             Setup: the gated candidate on HB9BLA, the IC-7300 on COM3, keying inhibit confirmed through Detect radio on both profiles; a second station process on its own profile; the operator's consent.
             Steps: start the station with COM3 saved; start a second process with COM3 saved while the first holds it; start it with a second transceiver connected, if one is available; with two transceivers, start two processes on unconfirmed CAT, so one holds its radio only by reservation. The second-transceiver steps can't run on this station, which has only one radio.
             Expected: the first keeps COM3; the second reports port_in_use with nothing changed when no other radio is free, and takes the second transceiver when one is; a radio reserved but not yet held is passed over.
             4 — Live on the station with the operator's consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-044-15';
        }
    }
    dependency CL_044_15_verified_by_TC_044_021 from 'CL-044-15' to 'TC-044-021';
    // Live finding 2026-11-06 (#44 comment 6683284855): a band change from the operator must simply work.
    requirement 'CL-044-16' {
        doc /* A selection of POST /receive/select that finds the CAT lease held by the 1 s poll, a menu or AGC exchange or another transition waits for it up to 3 s, without a queue, off the async runtime, and then proceeds: a poll no longer refuses a band change. After the wait the preflight runs again as before. A lease still held at 3 s refuses busy, as does a transmit hold, at once, since a transmission lasts far longer than the wait. The busy refusal of a held lease comes at 3 s from the request, never before, with a margin of at most 250 ms for scheduling and request handling: on the development PC (HB9BLA, 2026-11-07, 35 runs) it came 2 to 82 ms after 3 s, the most beside a build, so 250 ms is about three times the worst seen and well below a 3.5 s wait. A refusal changes nothing: the operating revision and the selection stay as they were, and the Band control shows the band the station is on, with "Selection refused · busy". */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_control/actor.rs; server/src/recording.rs; server/src/selection.rs; server/src/selection_http.rs";
    }
    dependency CL_044_16_to_FR_009 from 'CL-044-16' to 'FR-009';
    verification 'TC-044-023' {
        doc /* TC-044-023 — A band change meets a held CAT lease
             CL-044-16
             Setup: the actual router, Recording and CAT actor on a scripted IC-7300; Chromium with one refusal injected.
             Steps: (a) POST /receive/select while the lease is held for 300 ms; (b) while it stays held; (c) reserve the lease under a transmit hold; (d) in the browser, select a band and answer 409 busy.
             Expected: (a) 202 after the wait; (b) 409 busy at least 3000 ms and under 3250 ms after the request (3 s plus the 250 ms margin of CL-044-16; a red under load is rerun once), with the operating revision and selection unchanged; (c) Busy at once; (d) "Selection refused · busy" and the Band control back on the current band.
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-16';
        }
        attribute executable : String = "server/src/radio_level_tests.rs; tests/radio-selection.test.cjs";
    }
    dependency CL_044_16_verified_by_TC_044_023 from 'CL-044-16' to 'TC-044-023';
    verification 'TC-044-013' {
        doc /* TC-044-013 — Meter burst under the transmit hold; level timing
             CL-044-12
             Setup: the actual CAT actor and executor on a scripted IC-7300 transport (echo of each frame, hand-written replies); the actual transmit core on a virtual clock.
             Steps: (a) read without the hold, then with it; (b) ALC refused FA; (c) a timeout, then a stalled read released by PTT off; (d) raw values through the scales; (e) a level set before and during a transmission and during Tune.
             Expected: (a) Busy and no byte, then exactly the frames 15 13, 15 11, 15 12, and the release still works; (b) ALC missing, Po read; (c) the connection stays Ready, the release returns within 250 ms and the read returns Cancelled; (d) Po 0143 50 %, 0213 100 %, SWR 0048 1.5, 0080 2.0, 0120 3.0; (e) the level reaches the hardware immediately before the play, not during the transmission, at once during Tune; 0 dB is the playback scale, -20 dB a tenth of it.
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-12';
        }
        attribute executable : String = "server/src/radio_level_tests.rs; server/tests/transmit_service.rs";
    }
    dependency CL_044_12_verified_by_TC_044_013 from 'CL-044-12' to 'TC-044-013';
    verification 'TC-044-014' {
        doc /* TC-044-014 — Set level, manual level, push and route
             CL-044-12, CL-044-13
             Setup: the actual router, Recording owner and transmit owner on a recording hardware double, the CAT actor on a scripted IC-7300 whose ALC follows the double's level.
             Steps: (a) the decision table; (b) a run with the ALC rising at -27 dB; (c) HALT during a run; (d) a radio refusing the ALC read, then the manual level, also during Tune; (e) stored and invalid level files at startup; (f) ticks with and without Tune; (g) malformed requests and a request without a grant; (h) the profile field.
             Expected: (a) up, stored one below, -40 floor, power limit 49/50 % at Po 50 %, max_without_alc, no_alc, high_swr; (b) levels -30, -29, -28, -27, -28 stored, Tune off, disarmed, the profile revision unchanged, the next Tune at -28, no setter frame; (c) aborted, no file, prior level, Tune off, disarmed; (d) no_alc, alc unavailable, the slider action refused alc_available before, range refused, -10 stored, Tune follows; (e) -17 applied, invalid files ignored; (f) no read without Tune, one burst per second with it, exact event keys and values; (g) 400 and 401, Tune stays off; (h) absent by default, saved, 0 and 101 refused.
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-12';
            verify 'CL-044-13';
        }
        attribute executable : String = "server/src/radio_level_tests.rs";
    }
    dependency CL_044_12_verified_by_TC_044_014 from 'CL-044-12' to 'TC-044-014';
    dependency CL_044_13_verified_by_TC_044_014 from 'CL-044-13' to 'TC-044-014';
    verification 'TC-044-015' {
        doc /* TC-044-015 — Tx level in Settings > Radio > Audio
             CL-044-13
             Setup: candidate server and Chromium; radio.tx_level events injected, POST /radio/tx-level answered by a route fixture.
             Steps: open the Audio section for an IC-7300 CAT control; inject meters, a run, its result, alc unavailable; click Set level; move the slider; save a power limit; hide for a disabled control; 360 px.
             Expected: the button is in #settings-audio, no slider before alc unavailable, the line and meters show the pushed values, a malformed event is ignored, the click sends exactly one set_level, the slider sends one manual, Apply saves radio.power_limit_pct, all of it hidden when control is Disabled, no horizontal overflow at 360 px.
             2 — Isolated automated browser test; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-13';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_044_13_verified_by_TC_044_015 from 'CL-044-13' to 'TC-044-015';
    verification 'TC-044-016' {
        doc /* TC-044-016 — Set level on HB9BLA
             CL-044-12, CL-044-13
             Setup: the gated candidate installed on HB9BLA with the IC-7300, the operator's consent, a dummy load or the station antenna, RF power set low by the test before the first Tx (CI-V 14 0A, value 0003, with the station stopped and idle, because it holds COM3; read back; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported).
             Steps: read 15 13, 15 11, 15 12 during Tune over CI-V; press Set level; press HALT during a second run. The evidence is the CI-V readback and the radio.tx_level frames, not the radio's display (operator decision of 2026-11-08).
             Expected: the meter values read back agree with the radio.tx_level frames and the manual's scales; the run ends with the ALC just below rising, the level stored and Tune off; HALT stops it at once and keeps the stored level.
             5 — Live with RF on the station, operator consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-044-12';
            verify 'CL-044-13';
        }
    }
    dependency CL_044_12_verified_by_TC_044_016 from 'CL-044-12' to 'TC-044-016';
    dependency CL_044_13_verified_by_TC_044_016 from 'CL-044-13' to 'TC-044-016';
    verification 'TC-044-011' {
        doc /* TC-044-011 — AGC on HB9BLA
             CL-044-09, CL-044-10, CL-044-11
             Setup: the gated candidate installed on HB9BLA with the IC-7300, the operator present.
             Steps: set the radio's AGC to FAST by hand; restart CAT (Apply ⟳); read the Settings line and the radio display; select FT8 40 m; select FT4; watch the waterfall between periods.
             Expected: the radio shows AGC SLOW after connect and the line reads "set to SLOW and read back"; the following selections read "already as set" with no write; no AGC recovery line between periods.
             4 — Live on the station with the operator's consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-044-09';
            verify 'CL-044-10';
            verify 'CL-044-11';
        }
    }
    dependency CL_044_09_verified_by_TC_044_011 from 'CL-044-09' to 'TC-044-011';
    dependency CL_044_10_verified_by_TC_044_011 from 'CL-044-10' to 'TC-044-011';
    dependency CL_044_11_verified_by_TC_044_011 from 'CL-044-11' to 'TC-044-011';

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
             2 — Isolated automated functional test; Windows PC, release build, WSTX_SAMPLE_DIR, no radio or audio device (live-station-browser suite). */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-057-01';
        }
        attribute executable : String = "server/src/receive_http_tests.rs; tests/receive-latency.test.cjs";
    }
    dependency CL_057_01_verified_by_TC_057_001 from 'CL-057-01' to 'TC-057-001';
    requirement 'CL-057-02' {
        doc /* The modem decodes on all CPU cores with headroom: its parallel stages use up to the logical CPU count minus one threads (at least one; the calling thread included), scoped to each stage, so capture, display and transmit threads keep a core; the native audio capture and transmit render threads run at raised (highest) thread priority. Parallel stages are the rows of the FT8 detection spectrum, the FT8 sync-peak qualification, the verification of each pass's candidates (demodulation, channel decode, refinement, physical check and, for a supported complete FT8 frame, its SNR signal power; at most sixteen at once, each holding one 1.2 MB known-word waveform while it refines) and the synthesis of the waveforms to subtract; peak blocking, the duplicate checks, the SNR baseline (per period) and SNR value, publication and the residual subtraction stay in candidate order. The decode set and its order (payload, start frame, frequency and SNR) are identical for every thread count. At most four subtraction waveforms are built at a time: the next four are built on other threads while the previous four are subtracted, so at most eight are held, bounding their memory. The last pass's verified frames are not subtracted, because no later pass reads that residual (#57: these keep a busy FT8 prompt window at about 0.3 s of decode, well inside the CL-007-05 publication bound of period start + 15.0 s; #72: no bound from window completion to painted row is promised beyond CL-007-05 and CL-057-01). The CL-007-04 per-CPU-worker runtime, memory and four-profile budgets are measured with one decode thread per worker. Parallel work runs in rounds of about 10 ms, each started item finishing, and the decode future yields and checks cancellation between rounds, so the station worker keeps draining capture and a cancellation returns as before. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/decoder/parallel.rs; server/src/decoder/search.rs; server/src/decoder/synchronization.rs; server/src/decoder/baseband.rs; server/src/audio/windows.rs; server/src/playback/windows.rs";
    }
    dependency CL_057_02_to_FR_003 from 'CL-057-02' to 'FR-003';
    dependency CL_057_02_to_FR_004 from 'CL-057-02' to 'FR-004';
    verification 'TC-057-002' {
        doc /* TC-057-002 — Parallel decode: identical result, wall time by thread count
             CL-057-02, CL-057-01, CL-007-05
             Setup: release build; the hash-pinned busy recording websdr_test7.wav as the UTC-aligned FT8 prompt window (as TC-004-004); for the end-to-end case the TC-057-001 live path and Detailed browser.
             Steps: decode the window three times each on 1, 4 and 12 threads; order-preserving map of 200 items on 1, 2, 4 and 8 threads with one slow item, and with cancellation from inside the work; the TC-057-001 run with the default thread count.
             Expected (independent oracle: the single-threaded decode of the same window and the input order): the records on 4 and 12 threads equal those on 1 thread bit for bit and in order, at least 25 records; best wall times are reported per thread count (busy corpus period); the map returns every item once in input order and a cancelled caller ends with Cancelled; the cooperative-quanta and quality cases of TC-004-001 stay green; end to end (TC-057-001 setup, two busy periods), each period's view is published by its period start + 15.0 s on the server timeline (CL-007-05) and its rows are painted at most 300 ms after that publication (CL-057-01), so every row is painted by period start + 15.3 s; the time from window completion (+13.8 s) to the painted rows is reported, not asserted (#72: no contract states that bound).
             2 — Isolated automated functional tests; Windows PC, no radio (decoder-quality, wstx-rust and live-station-browser suites). */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-057-02';
            verify 'CL-057-01';
            verify 'CL-007-05';
        }
        attribute executable : String = "server/tests/decoder_signal.rs; server/src/decoder/parallel.rs; server/src/receive_http_tests.rs";
    }
    dependency CL_057_02_verified_by_TC_057_002 from 'CL-057-02' to 'TC-057-002';
    dependency CL_057_01_verified_by_TC_057_002 from 'CL-057-01' to 'TC-057-002';
    dependency CL_007_05_verified_by_TC_057_002 from 'CL-007-05' to 'TC-057-002';
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
    dependency CL_057_02_verified_by_TC_057_003 from 'CL-057-02' to 'TC-057-003';
    dependency CL_057_01_verified_by_TC_057_003 from 'CL-057-01' to 'TC-057-003';
    dependency CL_007_05_verified_by_TC_057_003 from 'CL-007-05' to 'TC-057-003';
    requirement 'CL-057-03' {
        doc /* Band Activity shows only the latest even and the latest odd T/R period of the current receive identity (operator 2026-11-02, #37): the latest published period on top and, below a divider with its period UTC, the period it replaced when that one has the other parity; each period sorted by value or by the chosen column (ActivityOrdering, #55 CL-055-04); all decodes of a period; #39 highlight and #50 colours as before. When a new period arrives, the older period of the same parity disappears; a same-parity successor (a skipped period) or an uncorrelated period leaves only the latest. Older periods are neither kept, paged nor fetched: the browser reads only the latest view's records (the replaced period's rows are the ones it already has). The logbook and worked-before status are unaffected. After a page load or reload (for example the #51 reload after a station update) only the latest period is shown until the next period arrives, because the receive snapshot describes only the latest view; the previous period is not fetched back. A period in which this station transmitted is the exception of CL-061-03: it adds no block, and the period kept below it stays until a receive period replaces it. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/contact.js";
    }
    dependency CL_057_03_to_FR_010 from 'CL-057-03' to 'FR-010';
    dependency CL_057_03_to_FR_019 from 'CL-057-03' to 'FR-019';
    verification 'TC-057-004' {
        doc /* TC-057-004 — Only the latest even and odd periods in Band Activity
             CL-057-03
             Setup: actual station Router and browser client with a scripted correlated FT8 receive snapshot and results route (explicit presentation fixtures, never modem truth).
             Steps: publish three consecutive periods 12:00:00, 12:00:15 and 12:00:30 UTC (3, 2 and 2 records), then 12:01:00 (one record, a skipped period); record every results read with the view current at that moment.
             Expected (independent: the scripted periods): after the second period, its rows on top and the 12:00:00 rows below one divider; after the third, only the 12:00:30 rows on top and the 12:00:15 rows below one divider (never more than two periods, the older same-parity period gone); after 12:01:00 only its row, no divider; no results read below the current view's first sequence; no page error.
             2 — Isolated automated browser test; Windows PC, no radio (operating-layout suite). Live acceptance: #37 items 1-2 on HB9BLA (FT8 and FT4). */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-057-03';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_057_03_verified_by_TC_057_004 from 'CL-057-03' to 'TC-057-004';

    // #52 Decode window diagnostics (approved on #52, 2026-11-02): what the station decoded.
    requirement 'CL-052-01' {
        doc /* For every live analysis window the receive owner keeps, in memory, the counters of the latest 20 windows: {mode, origin, frames, late, period_start_frame, period_start_utc, window_offset_ms (window start minus UTC period start), zero_samples (samples exactly 0), longest_zero_run, early_buffer_zero_samples (zeros inside the FT8 early buffer, the first 41*3456 frames of the period; null without a correlated clock), zero_filled_frames (frames the capture engine delivered as silence and the source filled with zeros), glitch_frames (frames of engine glitches accepted on a continuous timeline), capture (the capture's cumulative queue_contention, queue_full, pool_exhausted, invalid_packet, clock_step, timestamp_error, native_discontinuity, frame_backstep counters), capture_drift_ms, dump}; the capture counts are null when the input does not report them. GET /receive/diagnostics (receive read authorization, no query, empty body) returns exactly {v 1, profile_id, boot_id, window_dump, storage_error, dump_error, dumped_windows, windows}; it is read when Settings opens (at most every 30 s) or on Refresh, never polled, and nothing of it is added to GET /receive. The FT8 prompt-window dump is off by default and per profile: receive-diagnostics.json next to profile.json holds exactly {schema_version 1, profile_id, window_dump boolean}, written atomically; a missing file is off, a foreign, malformed or other-schema file is off with storage_error invalid_diagnostics. POST /receive/diagnostics {v 1, profile_id, boot_id, window_dump} with operator authority sets it (wrong profile wrong_profile, other boot state_conflict, any other key or type invalid_request) and acts from the next window without a restart; Settings > Expert shows it as "Save FT8 decode windows" with the latest window's counters. While on, each FT8 prompt window (not the late window, not FT4) is written off the decode path as diagnostic-windows/<origin, 15 digits>-<period UTC without separators>.wav, 12 kHz mono PCM16 as jt9 reads it, with a .json sidecar {v 1, rate_hz 12000, sample_format pcm16_mono, window: its counters}; the folder keeps the newest 20 windows within 16 MiB, deleting the oldest; a failed write sets dump_error dump_failed and never affects decoding. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/receive_diagnostics.rs; server/src/recording.rs; server/src/receive_http.rs; server/src/main.rs; server/src/audio.rs; server/src/audio/windows.rs; client/contact.js";
    }
    dependency CL_052_01_to_FR_003 from 'CL-052-01' to 'FR-003';
    verification 'TC-052-001' {
        doc /* TC-052-001 — Decode window diagnostics
             CL-052-01
             Setup: actual Recording owner on a disposable profile directory; the actual station router (contact_http_tests fixture); the real PacketQueue/LiveSource with injected native packets; the browser on the actual station.
             Steps: (a) counters of a hand-built window with zeros at known frames and a known early buffer; (b) a PCM16 WAV of 0, 0.5, -1, 1; (c) defaults, POST on, reopen, foreign/other-schema/extra-key files, wrong profile and boot; (d) windows noted with the dump off, a late window, then 27 prompt windows with it on; (e) five windows of a third of the cap; (f) GET/POST through the router with refused bodies, a foreign origin and a query; (g) 100 native 480-frame packets at 48 kHz with packets 10 and 11 silent, 40 and 70 accepted glitches, then a timestamp error; one signal packet followed by 600 silent ones; (h) the Expert toggle in the browser.
             Expected (hand-calculated): (a) 6 zeros, longest run 3, 4 in the early buffer (frames 104, 110, 118, 119); (b) RIFF/WAVE, PCM 1 channel 12000 Hz 16 bit, samples 0, 16384, -32768, 32767; (c) off, then {schema_version 1, profile_id, window_dump true} and on after reopening, each bad file off with invalid_diagnostics, refusals wrong_profile and state_conflict; (d) nothing written while off or for the late window, then <origin>-20261102T0916000000000Z.wav and .json with the window's counters, the newest 20 windows kept, the view's last 20 windows from origin 10, dumped_windows 27; (e) the two newest windows kept; (f) 200 views, 403 wrong_profile and forbidden_origin, 409 state_conflict, 400 invalid_request, GET /receive without window counters; (g) zero-filled 240 and glitch 240 canonical frames in [0, 12000), 180 and 60 in [1260, 4860), none after the new epoch; 72000 zero-filled frames, counted in full beyond the 512-mark limit; (h) the checkbox in Settings > Expert reads back the saved value and one POST per change.
             2 — Isolated automated tests; Windows PC, no radio or audio device. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-052-01';
        }
        attribute executable : String = "server/src/receive_diagnostics_tests.rs; server/tests/audio_contract.rs::audio_zero_filled_and_glitch_frames_are_marked_per_window; tests/ui-operating.test.cjs";
    }
    dependency CL_052_01_verified_by_TC_052_001 from 'CL-052-01' to 'TC-052-001';

    // #39 Strategy engine: selection, value order, editor popup, directed-CQ rule (decisions
    // on #37/#39/#42, 2026-11-01); detailed contract in WstxStrategy.
    requirement 'CL-039-01' {
        doc /* Named strategies are a station setting of the selected profile: strategy.json (schema 3) beside profile.json holds {continent, strategies, ignore lists} with up to 16 strategies of class award (contest is #63, refused on the wire), each exactly a name, goals, needed, region, minimum SNR, value (the ordered criteria), Callers of my call first, CQ when no target, repetitions before leaving, quiet time, Treat 73 as CQ and a worked window. Exactly one strategy is active, or None; active never survives a station restart. A file of schema 1 (with rules) reads as: strategies dropped, active None, continent and ignore lists kept; a file of schema 2 (with calls per station) reads with calls per station dropped and the strategydef defaults added (value Most Wanted rank, callers first on, CQ when no target off, 4 repetitions, 10 minutes). GET /strategy and PUT /strategy (revision-checked, exact keys) read and save it; my continent is configurable there (Settings > General) and otherwise the cty.dat continent of my callsign (#55). Details: WstxStrategy::StrategyConfiguration, Strategy, StrategyHttp. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/contact_http.rs; server/src/main.rs; client/contact.js";
    }
    dependency CL_039_01_to_FR_007 from 'CL-039-01' to 'FR-007';
    dependency CL_039_01_to_FR_016 from 'CL-039-01' to 'FR-016';
    requirement 'CL-039-02' {
        doc /* One station evaluator gives each decoded standard message a verdict. The filter is yes or no and every line must hold: at least one goal needed (dxcc, dxcc_band, dxcc_slot, waz, wpx, grid, new_call, new_call_band, read from the log in the strategy's window: all time, the UTC date, or from-to UTC dates, needed as not worked or not worked-or-confirmed; a missing grid is unknown, never new), not ignored, region, minimum SNR, the directed-CQ rule, a CQ or with Treat 73 as CQ an RR73/73, and in a run not worked in this run. A caller of my call is always answered whatever the filter (D5). The value is an ordered list of criteria (new DXCC, new DXCC on band, new DXCC on band and mode, new grid, new grid on band, new call, new call on band, Most Wanted rank, distance farther first, SNR stronger first): the first decides and the next breaks a tie; SNR is always the hidden last tie-breaker, then for an exact tie the lower audio frequency and the call; decode order is never a ranking. Distance is from the profile locator to the message grid, else to the cty.dat entity centre. With Callers of my call first the callers come first, else they are ranked with the candidates. POST /strategy/evaluate returns the verdicts of retained live records for the saved strategy or a draft, with the reason when asked; the browser never evaluates a strategy itself. Details: WstxStrategy::GoalNeeded, WpxPrefix, WorkedWindow, CallerOfMyCall, Candidate, ValueOrder, StationDistance, Verdict, StrategyHttp. */
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
    requirement 'CL-039-04' {
        doc /* The strategy element above Band Activity offers the strategy selector (None and the names), the editor and a Value sort control. While a strategy is active Band Activity marks what it would call and lists rows by value from the station's verdicts, only after a new publication event; a column click overrides until Value is chosen again; colours stay per #50 (only interesting stations). The editor is a popup with its own HALT that keeps receive running, holds exactly the strategy settings in three parts (Filter; Value with the ordered criteria list, "then SNR" and Callers of my call first; Exit with repetitions before leaving and quiet time; and CQ when no target), previews the unsaved draft against the latest period with the reason per decode, and applies on Save at once without selecting; selecting or saving never restarts receive. Details: WstxStrategy::ValueView, StrategySelector, StrategyEditor; WstxOperatingLayout::OperatingScreen. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_039_04_to_FR_010 from 'CL-039-04' to 'FR-010';
    dependency CL_039_04_to_FR_019 from 'CL-039-04' to 'FR-019';
    requirement 'CL-039-05' {
        doc /* Selecting a strategy marks its candidates; it transmits only while Auto is on (CL-039-22), through the existing station automation and contact engine (no second engine), with no confirmation and no client decision: the browser sends only the selection and the toggle, and HALT is always on screen. An award strategy calls CQ only with CQ when no target (CL-039-22) and goes on after each QSO without a contact limit, waiting for the next opportunity, for at most 8 hours from its start, also with a browser open (operator decision 2026-11-06: a new start gives a new 8 hours); it answers callers of my call (first with Callers of my call first), then the best candidate; it leaves a station by the leave rule (CL-039-23) and may call it again after its quiet time; it never selects a station the operator cancelled or aborted again in that run, nor one completed in that run on this band and mode. It follows its grant, not the transport of the starting request: a page reload or a second tab does not stop it, a revoked grant does. Unattended (operator decision, #39 comment 6685226511) and at the run limit ("Finish the QSO first", operator 2026-11-07): with no authenticated client (a status WebSocket session, or an authenticated MCP request) for 60 s, or past 8 hours, it selects no new station and answers no caller, its own CQ ends at once, a QSO the partner is answering is completed, otherwise the contact ends at x repetitions, and it stops with the reason no_client or run_limit; only an Auto on restarts it, never an AutomationCommand start. A band or mode change by the operator and HALT end the contact at once; Auto off, None, another selection, a contest deselected and the end of a contest period end at once a contact that is no started QSO and let a started QSO finish (#81, CL-081-01). It waits instead of stopping across a receive restart; a refused start or a stop turns Auto off with the reason shown and leaves the strategy selected. HALT from any source stops the run and turns Auto off, pushed to the browser; the selection stays. Esc does not. A double-click is always possible and is a manual intervention: the run waits for that QSO to end and resumes. An MCP principal cannot select a strategy nor switch Auto. Details: WstxStrategy::StrategyRun, AutoToggle, StrategySelector, ManualIntervention, SaneCall; WstxMcp::OperatingAutomation. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/strategy.rs; client/contact.js";
    }
    dependency CL_039_05_to_FR_020 from 'CL-039-05' to 'FR-020';
    dependency CL_039_05_to_FR_007 from 'CL-039-05' to 'FR-007';
    requirement 'CL-039-06' {
        doc /* The Tx watchdog limits the repetitions of one message (WstxContact::TxWatchdog, 2026-11-06) and is never paused by automation; only a different message, a new contact or an operator Enable Tx restarts its count, and only an Enable Tx or a strategy selection from the browser ends its stop. Only a human action in the browser is an operator action (an Enable Tx, accepted contact request or strategy selection from the browser), decided by the request principal the station reads from its credential at the auth boundary (#58: an MCP client has its own token and is never the browser principal on any route, including a direct /contact/command); commands of an automation run and MCP requests (including starting or restarting a run) never end a stop or extend the limit; their Enable Tx is refused tx_watchdog after a stop or when no browser action was seen this boot; only the browser may change the watchdog setting (set_watchdogs from MCP or automation is refused operator_required); a new target chosen by a run is a different message, so the watchdog bounds a run per message, not in total. At the limit Enable Tx goes off without a halt and a pounce or MCP policy run stops tx_watchdog, while a strategy run's own contact has no stop and is bounded by CL-039-21 instead; the station and its automation never use HALT in normal flow (HALT is the operator's emergency stop: HALT button, Alt+H, MCP wstx_transmit_halt). HALT from any source stops everything; grant, clock, period and safety-revision checks are unchanged; there is no band hopping. Details: WstxStrategy::WatchdogFromOperator; WstxContact::TxWatchdog. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/service.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/automation.rs; server/src/mcp.rs; server/src/authorization.rs";
    }
    dependency CL_039_06_to_FR_008 from 'CL-039-06' to 'FR-008';
    requirement 'CL-039-07' {
        doc /* Outstanding, issue #39/#42 later slices: auto-QRM stop; filtered-out view toggle; freeze Band Activity on hover; per-mode watchdog values; late-duplicate guard and false-decode heuristic; CQ-target prefer; stacked DXpedition replies. Delivered meanwhile: the free Tx slot finder (CL-039-09) and contests (#63). Until delivered these are not offered. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    dependency CL_039_07_to_FR_007 from 'CL-039-07' to 'FR-007';
    verification 'TC-039-008' {
        doc /* TC-039-008 — Later strategy slices (outstanding: auto-QRM stop and the other CL-039-07 slices)
             CL-039-07
             Setup: actual candidate router with a pinned cty.dat fixture and hand-authored rows.
             Steps: auto-QRM stop scenarios.
             Expected: defined when the slice is prepared; until then contest is refused at PUT /strategy.
             2 — Isolated automated functional tests; Windows development PC; not implemented. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-039-07';
        }
    }
    dependency CL_039_07_verified_by_TC_039_008 from 'CL-039-07' to 'TC-039-008';
    requirement 'CL-039-21' {
        doc /* A strategy or contest run never stops its own contact for the Tx watchdog; the leave rule bounds it instead (CL-039-23). Slot check at every repetition (operator 2026-11-07): while the target has not answered in this contact and is not known to hear us (no spot, Use PSK Reporter off, the feed off or unreachable), Tx takes the quietest slot again (CL-039-09), keeping the current slot when it ties for quietest so that it does not jump between near-equal slots (a tie rule only, no threshold); a target known to hear us keeps its slot, and a target that has answered keeps it for the whole exchange. With Hold Tx on (#39 holdtx, operator 2026-11-07: "if the other station does not hear us we are allowed to change the frequency to a quiet place, but never to the Rx frequency") this is the only move of Tx in the contact and Tx moves alone: Rx stays on the station, and the slot keeps 50 Hz from the called station's signal and from Rx; with Hold Tx off Rx and Tx move together. A pounce has no slot check. Manual operation, a pounce and an MCP policy run keep the stop at N, and so does a run's CQ; unattended or past the run limit the stop at N is back at once. Details: WstxStrategy::StrategyWatchdog, HearingFeed, FreeTxSlot; WstxContact::TxWatchdog. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/freeslot.rs; server/src/pskr.rs";
    }
    dependency CL_039_21_to_FR_007 from 'CL-039-21' to 'FR-007';
    dependency CL_039_21_to_FR_008 from 'CL-039-21' to 'FR-008';
    requirement 'CL-039-22' {
        doc /* Mode (operator grill 2026-11-07, Q5, Q11, Q12, Q17, Q29, Q35, Q40). Auto is a toggle above the QSO pane next to CQ, green on and grey off, not part of a strategy, one toggle for strategies and contests; the station owns it in memory: off after a station restart, after HALT from any source and after every run end, and only the browser switches it (POST /strategy/auto; an MCP principal is refused). With Auto off a selected strategy or contest only marks its candidates; switching it on needs a selection and starts the run, and a contest whose rules forbid automatic operation asks the existing warning and needs its confirmation; switching it off ends the run at once, and a QSO the run has started is finished as an ordinary contact (#81, CL-081-01: Auto only decides whether new QSOs start); selecting None turns it off, another selection with Auto on starts that one. CQ when no target is a strategy option, off by default: with it on the run calls CQ after 2 publications with no candidate, answers callers (always, D5) and calls a candidate that appears; the Tx watchdog stops its CQ. With Hold Tx on (#39 holdtx round 1 Q3) the CQ goes out on the held Tx without a slot decision; with Hold Tx off it takes the slot quiet in my Rx parity (CL-039-09, #66). Details: WstxStrategy::AutoToggle, CqWhenNoTarget, StrategyRun, PskrUse; WstxOperatingLayout::QsoPane. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/automation.rs; server/src/contact_http.rs; client/contact.js";
    }
    dependency CL_039_22_to_FR_007 from 'CL-039-22' to 'FR-007';
    dependency CL_039_22_to_FR_020 from 'CL-039-22' to 'FR-020';
    requirement 'CL-039-23' {
        doc /* Exit (operator grill 2026-11-07, Q6, Q7, Q13-Q16, Q19-Q28). A repetition is a fresh complete publication of the target's parity after an own transmission without progress; any message of the target to my call is progress, also a repeated one, except a selected caller repeating the message it was selected on. Both situations count alike: he repeats, because he does not hear us (decoded, a CQ again or another station), and we repeat, because we do not hear him (not decoded). x, repetitions before leaving, is a strategy setting (default 4) and a contest setting (default 2); a fresh PSK Reporter spot that he hears us doubles it. A strategy run leaves at x (2x); a contest run too, except that in the first situation it stays while he hears us and is still the most valuable. Nothing changes before an exit criterion, even for a more valuable station; a caller of my call (in a contest only a non-dupe caller) is answered at once while the target has not answered, with Callers of my call first on. After every leaving the station gets a quiet time (strategy and contest setting, default 10 min) before it is called or answered again. Unattended or past the run limit x is never doubled and there is no contest stay. A contest dupe caller never ends a stay. Details: WstxStrategy::LeaveRule, QuietTime, StrategyRun; WstxContest::ContestRun. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/strategy.rs; server/src/contest.rs; server/src/pskr.rs";
    }
    dependency CL_039_23_to_FR_007 from 'CL-039-23' to 'FR-007';
    dependency CL_039_23_to_FR_020 from 'CL-039-23' to 'FR-020';
    verification 'TC-039-022' {
        doc /* TC-039-022 — The slot check at every repetition
             CL-039-21
             Setup: the actual station router, contact engine, automation and #9 transmit owner on the recording hardware double, virtual UTC, a feed without a connection fed hand-authored spots, a dial of 14074000 Hz; Tx watchdog 2; a strategy run with Auto on, on 20 m, repetitions 4, calling K1ABC (CQ at 1800 Hz) from Tx 1500; hand-authored waterfall rows whose quietest slot changes between periods.
             Steps: 4 repetitions with: no spot; a spot of my call to K1ABC 60 s old, 590 s old, 601 s old, on 40 m; the spot with Use PSK Reporter off; the spot with the feed off. The quietest slot moving 1400, 1300 between repetitions, and staying tied with the current one. The partner's report after the 2nd repetition, then silent periods. The engine alone: the run's own contact past the watchdog limit, then another contact; a run's CQ at the limit. Unattended (no client 60 s) and past the run limit with the spot: N 2 back at once, also without a publication. A refused move.
             Expected (hand-worked from WstxStrategy::FreeTxSlot): every repetition keyed while the run is attended, tx_expired false. WD (repetitions 4): WD:4, 3, 2, 1, then the leaving; with the spot WD:8 down to 1; in a contest stay (TC-039-044 (c)) WD:∞, and back to a number when the spot ages past 600 s. No spot, 601 s, 40 m, Use off, feed off: Tx and Rx 1400 after the 1st, 1300 after the 2nd, kept when tied, slot_check hears_us false. Heard (60 s, 590 s): Tx stays 1500, hears_us true. After the partner's report Tx never moves again in that exchange. Engine: the run's own contact sends past N; another contact and the run's CQ stop at N (cause tx_watchdog). Unattended: the stop at N back, no further key, stopped no_client or run_limit. A refused move: unchanged, checked again at the next repetition. Manual stop at N: TC-008-001; a pounce stops at N: TC-039-005.
             #39 holdtx: these steps run with Hold Tx explicitly off (Tx and Rx move together); with Hold Tx on only Tx moves and Rx stays on 1800: TC-039-049.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF, no network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-21';
        }
        attribute executable : String = "server/src/strategy_tests.rs; server/src/contact_tests.rs; server/src/freeslot_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_039_21_verified_by_TC_039_022 from 'CL-039-21' to 'TC-039-022';
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
        doc /* Hold Tx is on by default (operator decision 2026-11-04, #39; consistent with the split-frequency rule): a station starts with settings.hold_tx true, in manual operation and for a strategy alike, so selecting or answering a station moves Rx and never Tx; Tx stays on the operator's chosen slot until an explicit Tx action (the Tx input, a waterfall Tx pointer action, MCP set_frequency, the Hound's own rule). Automation (#39 holdtx, operator 2026-11-07: "Hold Tx on: the automation never moves Tx", corrected to "if the other station does not hear us we are allowed to change the frequency to a quiet place, but never to the Rx frequency"; this replaces "a run's free slot" as an explicit Tx action): with Hold Tx on a strategy or contest run or a pounce keeps Tx at a selection, before its CQ and when answering a caller from it, and moves Tx in exactly two cases: the station selected or answered is within 50 Hz of Tx (then Tx goes to the nearest slot 50 Hz away from it, round 1 Q2), and the slot check of a target that does not hear us (CL-039-21); Rx stays on the station. The operator may switch it off with set_hold_tx; the choice lasts for the station's running session, since contact settings are not persisted, so no stored value can override the default; the run reads it at each decision. Details: WstxStrategy::FreeTxSlot. */
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
             2 — Isolated automated tests; Windows PC, no radio (wstx-rust, contact-browser suites). */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-08';
        }
        attribute executable : String = "server/src/contact_tests.rs::hold_tx_is_on_by_default_and_a_selection_keeps_tx; server/src/strategy_tests.rs::tc_039_004_selecting_starts_a_run_that_calls_by_value_and_never_calls_cq; tests/contact.test.cjs";
    }
    dependency CL_039_08_verified_by_TC_039_009 from 'CL-039-08' to 'TC-039-009';
    requirement 'CL-039-09' {
        doc /* A strategy or contest run or a pounce calls from the quietest Tx slot: the slot where the target can answer us, a free slot on my side, judged in every decision (a selection, a slot check, a CQ) in my Rx periods only (his Tx parity; #66 operator 2026-11-08 "judge the parity I will receive in"), and only in recent ones: the counted periods among the last 4 periods of my Rx parity on the clock (#66 "Only if recent"), periods I transmitted in never counted. Slots are compared with each other across the whole passband (#66, operator 2026-11-08 "We want to have the quiet slots overall. Across the entire bandwidth of FT8."), not by their own usual level: in each counted period a slot's rise is its level minus the WSJT-X passband floor fitted to that period (so the receive filter's roll-off does not favour the edges), and its value is its largest rise over the counted periods clamped at 0 (#66, operator 2026-11-08 "At or under floor = free": a slot at or below the floor is free, so a sharp filter knee the floor cannot follow never makes the edges win); compared in whole dB, the lowest value winning; a tie keeps the current Tx when it is among the quietest, else goes nearer the current Tx, then lower; there is no threshold. A slot whose signal overlaps a station decoded in a counted period (less than one signal width from his decoded frequency) is left out while any other is free. Where known it is free at his end: at least 50 Hz from every frequency his PSK Reporter spots show him decoding, counting only spots from my Tx parity (ignored when that leaves no slot). Hold Tx off: Rx = Tx, the slot sets both, decided at each selection, before a CQ and at each slot check (CL-039-21). Hold Tx on (CL-039-08): Rx stays on the station and the slot sets Tx alone, only at the slot check of a target that does not hear us, or as the nearest slot 50 Hz away when the station is within 50 Hz of Tx; a CQ goes out on the held Tx. Every slot the run chooses lies inside the Tx range (FT8 300..2650, FT4 300..2610) and at least 50 Hz from the called station's signal and from Rx; without power data the current Tx is kept. Details: WstxStrategy::FreeTxSlot. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/freeslot.rs; server/src/automation.rs; server/src/contact_http.rs; client/contact.js";
    }
    dependency CL_039_09_to_FR_007 from 'CL-039-09' to 'FR-007';
    dependency CL_039_09_to_FR_020 from 'CL-039-09' to 'FR-020';
    verification 'TC-039-010' {
        doc /* TC-039-010 — The quietest Tx slot
             CL-039-09
             Setup: the pure slot function with hand-authored power tables (levels in dB per 10 Hz candidate, written in the test) and hand-authored spot frequencies; the actual station Router with the contact engine and #9 owner on the hardware double, an injected FT8 live job whose detailed waterfall rows are hand-authored (a flat floor of 20 with raised bands), a selected strategy with Auto on, a pounce, a plain MCP run; virtual UTC.
             Steps: choose on tables: one lowest slot; the current Tx tying the lowest; two lowest without the current Tx, at different distances from it and at equal distances; levels 40.4 and 40.0 (one whole dB, a tie) against 40.6 and 40.0 (no tie); the range edges for FT8 (300..2650) and FT4 (300..2610, width 90); the called station on the quietest slot; his decoded frequencies of my Tx parity and of the other parity near the quietest; his frequencies excluding every candidate; listening only, with one parity quiet and the other loud; no power yet, with the called station on and away from the current Tx. Router: periods of both parities with a quiet band at 1800 Hz only in my Rx parity; the 5th oldest period of the parity quiet at 600 Hz; a period I transmitted in; then a candidate CQ on 1500 Hz; a QSO to its end; a station band change within the job; Hold Tx off; a caller on my slot; a pounce; a plain MCP run.
             Expected (oracle: the operator's rule, hand-computed in the test): that slot; the current Tx kept; the nearer one, then the lower; 40.4 and 40.0 tie and keep the current Tx, 40.6 does not; never outside the range; never within 50 Hz of the called station; his frequency of my Tx parity excludes the slot within 50 Hz and the other parity does not; all excluded: his end ignored, his_end no; listening only (#66): judged on my Rx parity alone, the parity loud only in my Tx periods not avoided; no power: the current Tx kept, or the nearest away from the called station, power_db null. Router: Tx and Rx 1800 before the first call (the 5th period and the transmitted period ignored), tx_slot {hz 1800, power_db 20, his_end unknown}; Tx stays 1800 through the whole QSO; after the band change only the new band's periods count; with Hold Tx off Tx back on its slot; the caller answered from the quietest slot away from it; the pounce calls from the quietest slot; the plain run has tx_slot null and keeps its Tx.
             #39 holdtx: the Router steps run with Hold Tx explicitly off (the Rx = Tx rule); with Hold Tx on they are TC-039-049. The tables give the compared value instead of the absolute power, and power_db is that value. #66: the compared value is the largest rise above the passband floor clamped at 0 (TC-039-050), so the Router's tx_slot reads power_db 0 on the flat floor of 20 (floor 20.65, rise -0.65 clamped); the decoded-station rule is TC-066-002.
             2 — Isolated automated tests; Windows PC, no radio (wstx-rust, ui-operating suites). */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-09';
        }
        attribute executable : String = "server/src/freeslot_tests.rs; server/src/strategy_tests.rs";
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
             Steps: each goal with worked and confirmed fixtures in both needed settings; grid with no message grid and with a logged QSO without a grid; region all, dx and selected for an EU and a non-EU profile; window all, today and from-to with an undated record; the worked set for the station step after a log write; min_snr_db; a caller against a Most Wanted station with a goal, region and SNR that exclude it; value order with and without a list; the WPX prefix table; contest class; the old file upgrade.
             Expected: the tables of the tests; a caller ranks 0 before the Most Wanted station; without a list strongest first; with one the listed first by rank, the others after them strongest first; unknown grid is never needed; the step gets the last set at once and the new one follows on its own thread; contest is refused invalid_request strategies[0].class.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-01';
            verify 'CL-039-02';
            verify 'CL-039-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs; server/src/dxcc_tests.rs";
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
        doc /* Read-only built-in strategies are offered beside the user's, in this order: New DXCC, New DXCC on band, DXCC slots, New calls, DX hunting (new call, region DX), Strongest new on band (new call on band, value SNR), Farthest new on band (new call on band, value distance) and Casual 20 m (new call on band in today's UTC window, value SNR, CQ when no target on); all needed not worked, Callers of my call first on, 4 repetitions, 10 minutes quiet time, Treat 73 as CQ on, window all time and value Most Wanted rank unless stated. They come from one server table, are listed with builtin true in the snapshot, can be selected like any strategy, cannot be edited through PUT /strategy (a user strategy with such a name is refused) and can be copied to a user strategy in the editor. Details: WstxStrategy::BuiltinStrategies, StrategyEditor, StrategySelector. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; client/contact.js";
    }
    dependency CL_039_11_to_FR_007 from 'CL-039-11' to 'FR-007';
    verification 'TC-039-032' {
        doc /* TC-039-032 — Built-in strategies: the table, selection, refusal and copy
             CL-039-11
             Setup: the expected table written in the test; the actual station router on a disposable HTTPS profile with the contact engine and #9 transmit owner on the recording hardware double; a browser case on the actual isolated station.
             Steps: GET /strategy; parse a configuration with active "DX hunting", with "dx hunting", with a user strategy "New DXCC" and "new dxcc", with the key builtin; PUT active "DX hunting", Auto on, and publish CQ DL1XYZ JO62 and CQ K1ABC FN42; read strategy.json; open a new owner; a saved file with a strategy named "New calls"; HALT. Browser: the selector; open the editor with no user strategy; Save; open a built-in; try to change it; Duplicate; Save; rename the copy to "new calls" and Save.
             Expected: exactly the eight of the table in its order with builtin true and their value, callers_first, cq_when_no_target, repetitions and quiet_minutes, none in configuration.strategies; active accepted exact only, refused active; strategies[0].name refused; strategies[0] refused; the run answers K1ABC (region DX), never DL1XYZ; the file holds no built-in and active null; the new owner reads None; the saved strategy is dropped and the built-in stays; HALT turns Auto off and keeps "DX hunting". Browser: None and the eight names; the editor shows the first built-in, Save sends no strategy and active null; the built-in's fields disabled, Delete disabled, no PUT of a built-in; the copy "New DXCC copy" the only user strategy saved; the colliding rename refused with its field shown.
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
             Steps: select and Auto on; at 59 s publish CQ K1ABC; at 60 s run the exchange to its end; publish a CQ and a call to my call; an MCP start; Auto on again; at 60 s without a contact publish a CQ; a session held from 0 s and released at 120 s, ticks at 179 s and 180 s; an MCP request at 59 s, a tick, ticks at 118 s and 119 s; a client back at 59 s of a contact past 60 s; at 60 s with K1ABC silent and a spot of my call at K1ABC; a CQ of a strategy with CQ when no target at 60 s; an actual status WebSocket upgrade with the browser cookie, past 60 s, then closed. Run limit, a client connected throughout: a CQ just before 8 h; at 8 h the exchange to its end; a CQ; Auto on again; again just before and at 8 h after that start.
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
             Steps: goal new_call_band with value [snr], [distance], [most_wanted], [most_wanted, distance], [new_dxcc, snr]; goal new_call (every station of the rows a candidate) with each needed-first criterion alone before [snr]: [new_dxcc] (log: a DL QSO on 40 m), [new_dxcc_band] (on 20 m: DL worked on 40 m only), [new_dxcc_slot] (an FT4 QSO with JA on 20 m), [new_call] (K1ABC logged), [new_call_band], [new_grid] (FN42 logged on 40 m), [new_grid_band] (FN42 logged on 40 m; a row without grid; a call with a logged 20 m QSO without grid); the same with the station band unknown; goal new_call; window today; DL1XYZ and OH1AA at the same SNR (an exact tie except frequency); two verdicts at the same SNR and frequency; callers_first on and off with value [snr]; an empty value list; the caller W1AW failing every filter line (worked, region, minimum SNR -10).
             Expected (hand-worked): each needed-first criterion puts the needed stations before the others and leaves SNR order inside each group: [new_dxcc] DL1XYZ after the rest; [new_dxcc_band] DL1XYZ needed on 20 m; [new_dxcc_slot] JA1XYZ needed (FT4 is another mode); [new_call] K1ABC and W1AW after; [new_call_band] K1ABC, W1AW and OH1AA after; [new_grid] K1ABC (FN42) after; [new_grid_band] K1ABC (FN42 not on 20 m) needed, the row without grid and the call with an unknown grid status not needed, a band unknown nothing needed; new_call_band excludes K1ABC and W1AW as candidates (worked on 20 m) and keeps DL1XYZ; [snr]: DL1XYZ, OH1AA (frequency 1400 before 1500 when tied: OH1AA first), ZS6AA, JA1XYZ, VK2ABC; [distance]: VK2ABC, JA1XYZ, ZS6AA (entity centre), OH1AA, DL1XYZ; [most_wanted]: JA1XYZ, VK2ABC, then the rest by SNR; [most_wanted, distance] the same for the listed, then by distance; band unknown: no candidate for new_call_band; window today: OH1AA not needed by new_call_band; the exact tie of SNR and frequency ordered by call; callers_first on: W1AW first; off with [snr]: W1AW last (weakest); the empty list: SNR order; W1AW always has a rank, whatever the filter; the reasons name the needed goals; sequence (decode order) never changes an order. Red on the parent: the criteria do not exist.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-02';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_02_verified_by_TC_039_040 from 'CL-039-02' to 'TC-039-040';
    verification 'TC-039-041' {
        doc /* TC-039-041 — The schema 3 store and its upgrade
             CL-039-01, CL-039-11
             Setup: the actual station store on a disposable profile; hand-written strategy.json files of schema 2 and 3.
             Steps: a schema 2 file with a strategy "Mine" (calls_per_station 5) at revision 7; GET /strategy; PUT a change; read the file; a schema 2 strategy that is otherwise malformed; GET /strategy builtin_strategies.
             Expected: revision 7 with "Mine" holding value [most_wanted], callers_first true, cq_when_no_target false, repetitions 4, quiet_minutes 10 and no calls_per_station; the file after the PUT is schema 3 at revision 8 with those keys; the malformed one reads configuration null, invalid_configuration; the eight built-ins as in TC-039-032.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-01';
            verify 'CL-039-11';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_01_verified_by_TC_039_041 from 'CL-039-01' to 'TC-039-041';
    dependency CL_039_11_verified_by_TC_039_041 from 'CL-039-11' to 'TC-039-041';
    verification 'TC-039-042' {
        doc /* TC-039-042 — The Auto toggle
             CL-039-22, CL-039-05
             Setup: the actual station router (HB9BLA JN47AA) with the contact engine and #9 transmit owner on the recording hardware double, virtual UTC, 20 m; a status session held open; the browser cookie grant; an MCP token.
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
             Setup: as TC-039-042 with Auto on, strategy "Test" (goal new_call, value [snr], repetitions 4, quiet_minutes 10, callers_first true), the feed without a connection fed hand-authored spots, a dial of 14074000 Hz; the run calling K1ABC (CQ FN42).
             Steps: (a) K1ABC silent (not decoded) for 5 partner periods. (b) K1ABC calling CQ again each period. (c) As (a) with a spot of my call at K1ABC 60 s old; the same with Use PSK Reporter off. (d) K1ABC answers with -05 after the 2nd repetition and repeats -05 for 6 periods (the #63 fix). (e) A caller W1AW selected, repeating its first call 5 times. (f) A stronger new CQ DL1XYZ from the 2nd repetition on. (g) A caller JA1XYZ at the 2nd repetition; the same with callers_first off; with JA1XYZ in its quiet time; after K1ABC has answered. (h) After (a): K1ABC's CQ alone at 9 min 59 s and at 10 min, and its call to my call at 5 min. (i) repetitions 1. (j) The band changed to 40 m in a stay; a new live identity (FT4); Auto off; HALT.
             Expected (hand-worked from the operator's rule): (a) and (b) armed after 3, disarmed and cancelled at the 4th, left {K1ABC, repetitions}, quiet K1ABC 600 s, waiting; (c) armed after 7, left at the 8th; with Use off left at the 4th; (d) never left during the 6 repeats, unanswered back to 0 at each (red on the parent, which leaves at the calls); (e) left at the 4th; (f) K1ABC kept, DL1XYZ never selected before the 4th, selected at the next step after it; (g) left {K1ABC, caller} at once and JA1XYZ selected from the same publication; callers_first off, in quiet time or after an answer: K1ABC kept; (h) not selected at 9 min 59 s nor answered at 5 min, selected at 10 min; (i) left at the 1st; (j) disarmed and cancelled at the next step, no quiet entry, left null, the run waiting (band, mode) and selecting from the next publication, stopped (Auto off, HALT); in a stay K1ABC has not answered, so no QSO has started and Auto off disarms at once (#81, CL-081-01).
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-23';
            verify 'CL-039-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_23_verified_by_TC_039_043 from 'CL-039-23' to 'TC-039-043';
    dependency CL_039_05_verified_by_TC_039_043 from 'CL-039-05' to 'TC-039-043';
    verification 'TC-039-044' {
        doc /* TC-039-044 — Leaving in a contest run
             CL-039-23, CL-063-05
             Setup: as TC-063-009 (WW Digi, 20 m, S&P, the period in force, W1DUP a dupe in the log) with Auto on and automation_confirmed, contest repetitions 2 and quiet_minutes 10; the feed fed hand-authored spots; the run calling K1ABC FN42 (new multiplier).
             Steps: (a) K1ABC silent, no spot. (b) K1ABC silent with a spot of my call at K1ABC. (c) K1ABC calling CQ again for 10 periods with the spot; then CQ JA1XYZ PM95 (new multiplier, more points) from the 6th; again with JA1XYZ from the 1st repetition. (d) W1DUP (dupe) calling my call for 8 periods during (c) (the #63 fix). (e) A non-dupe caller K2NEW FN31 at the 1st repetition. (f) Run: CQ, caller K2NEW answered, then silent; K2NEW calling again during its quiet time. (g) Repetitions 3 and quiet_minutes 1 in the selection. (h) The station clock past the period end in a contact; the contest deselected (None) in a contact.
             Expected (hand-worked): (a) left at the 2nd; (b) left at the 4th; (c) stays all 10 with the spot and nothing more valuable; JA1XYZ at the 6th leaves at once and JA1XYZ is selected; JA1XYZ from the 1st: K1ABC kept until the 2nd, then left and JA1XYZ selected; (d) the stay holds, W1DUP never selected or answered (red on the parent, where the dupe ends the stay); (e) left {K1ABC, caller} at once, K2NEW selected; (f) K2NEW answered from the CQ's slot (Tx and Rx stay on 900, the CQ quiet in my Rx parity, #66), left at the 2nd, calling_cq again, K2NEW not answered while quiet; (g) left at the 3rd, called again after 1 minute; (h) disarmed and cancelled at once, waiting outside_period; stopped, Auto off (K1ABC has not answered the call in (h), so no QSO has started; a started contest QSO at the period end or deselection finishes: #81, TC-081-003).
             #39 holdtx: these steps run with Hold Tx explicitly off (they test the run logic; Rx = Tx on the slot); with Hold Tx on the Run's CQ stays on the held Tx: TC-039-049 (j).
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-23';
            verify 'CL-063-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_23_verified_by_TC_039_044 from 'CL-039-23' to 'TC-039-044';
    dependency CL_063_05_verified_by_TC_039_044 from 'CL-063-05' to 'TC-039-044';
    verification 'TC-039-045' {
        doc /* TC-039-045 — CQ when no target
             CL-039-22
             Setup: as TC-039-042 with Auto on and "Casual 20 m" (new call on band today, value [snr], cq_when_no_target true); the log holds W1AW on 20 m today; Tx watchdog 6.
             Steps: two publications with nothing callable; a third; W1AW (worked today) calls my call; its QSO to the end; two empty publications; CQ DL1XYZ JO62 while calling CQ; callers at 1200 Hz and at 920 Hz with the CQ on 900; the same strategy with cq_when_no_target false for 6 empty publications; Tx watchdog 2 with an unanswered CQ; no client for 60 s while calling CQ; the slot of the CQ with one parity loud.
             Expected: waiting after the first, calling_cq after the second, armed, Tx6 "CQ HB9BLA JN47"; a caller is answered from the CQ's slot: with the CQ on 900 (quiet in my Rx parity, #66) a caller at 1200 Hz keeps Tx and Rx on 900, a caller at 920 Hz moves them to 820, the nearest candidate 50 Hz away from it; W1AW answered (a caller, whatever the filter) with select_row {replace false} and Enable Tx kept; completed, then calling_cq again after two empty publications; DL1XYZ selected and called, the CQ ended; off: never a CQ, nothing armed; watchdog 2: stopped tx_watchdog, Auto off, not keyed again; unattended: the CQ disarmed and cancelled at once, stopped no_client; the CQ's slot the quietest in my Rx parity, the loud parity ignored when it is my Tx parity (#66: the CQ judges only my Rx periods).
             #39 holdtx: these steps run with Hold Tx explicitly off; with Hold Tx on the CQ goes out on the held Tx and the callers are TC-039-049 (h).
             #66: the step "the slot of the CQ with one parity loud" is run twice, the loud parity my Tx parity (ignored) and my Rx parity (avoided); a caller's nearest candidate 50 Hz away also skips a station decoded in my Rx periods (TC-066-002 (h)).
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
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
             Steps: open with no selection; select "New calls"; click Auto; push the snapshot with auto true; push a HALT (auto false); click PSK; push enabled false (Settings off); push a run with hearing {heard, 75 s old, -12} and tx_slot {1420, his_end yes}, then {heard, 600 s}, {no}, {unknown} and his_end no and unknown; Use off; 10 s with no event; open the editor: add Distance, move it up, remove Most Wanted rank, change repetitions to 6 and quiet time to 15, set Callers of my call first off and CQ when no target on, Save; a contest prompt for WW Digi: the fields, Start; Auto on with the warning declined, then confirmed; FT8 Activity.
             Status (the station element and the contest status, from pushed automation.state and strategy.state): a waiting run, calling_cq, Auto off, a contest S&P with Auto on and Run with Auto off; the contact snapshot without transmit capability.
             Expected: the strategy element reads "Strategy New calls waiting", "Strategy New calls · calling CQ" and "Strategy New calls · Auto off"; the contest status "Contest WW Digi · <period> UTC · S&P · Auto on" and "· Run · Auto off"; Auto disabled with the reason "Receive only" as its title without transmit capability; Auto disabled with its reason without a selection; selecting sends one PUT and nothing else; the click sends exactly one POST /strategy/auto {auto true}; the button green only after the push and grey after the HALT push; PSK sends POST /pskr/use {use false} and is disabled with "PSK Reporter is off in Settings" when the switch is off; the lines "Hears us: 75 s ago · −12 dB" and "Tx 1420 Hz · open at his end: yes", then "Hears us: 10 min ago · −12 dB", "Hears us: no", "Hears us: unknown", "· no", "· unknown"; no lines with Use off or without a target; no request during the silence (no polling); the editor shows Filter, Value with "then SNR" and Exit, and Save sends exactly value [distance], callers_first false, cq_when_no_target true, repetitions 6, quiet_minutes 15; the prompt offers S&P and Run, repetitions 2 and quiet time 10, no colouring, and Start sends one PUT without automation_confirmed; Auto on for WW Digi shows the clause, sends nothing when declined and one POST with automation_confirmed true when confirmed; no warning for FT8 Activity; no horizontal overflow at 360 px and the QSO pane keeps its height.
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
    dependency CL_039_04_verified_by_TC_039_046 from 'CL-039-04' to 'TC-039-046';
    dependency CL_039_20_verified_by_TC_039_046 from 'CL-039-20' to 'TC-039-046';
    dependency CL_039_22_verified_by_TC_039_046 from 'CL-039-22' to 'TC-039-046';
    dependency CL_063_05_verified_by_TC_039_046 from 'CL-063-05' to 'TC-039-046';
    verification 'TC-039-047' {
        doc /* TC-039-047 — Live strategydef on HB9BLA at 30 W, 20 m FT8
             CL-039-02, CL-039-09, CL-039-20, CL-039-21, CL-039-22, CL-039-23
             Setup: the gated candidate installed on HB9BLA, IC-7300 on COM3 on 20 m FT8 (14.074 MHz), RF power set by the test to at least 30 W before the first Tx (CI-V 14 0A, starting at 0090, with the station stopped and idle, because it holds COM3; read back; the first Tx must read Po at least 30 %; if below, raise the value and repeat; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported), operator consent; Tx watchdog 6; PSK Reporter on in Settings and Use PSK Reporter on.
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
    dependency CL_039_21_verified_by_TC_039_047 from 'CL-039-21' to 'TC-039-047';
    dependency CL_039_22_verified_by_TC_039_047 from 'CL-039-22' to 'TC-039-047';
    dependency CL_039_23_verified_by_TC_039_047 from 'CL-039-23' to 'TC-039-047';
    verification 'TC-039-048' {
        doc /* TC-039-048 — PSK Reporter use, reported SNR, his decodes by parity and the hearing state
             CL-039-20, CL-039-23, CL-039-09
             Setup: as TC-039-020 (no network, a local MQTT peer, hand-authored payloads, the actual station router) with the contact engine and #9 owner on the recording hardware double, virtual UTC, a dial of 14074000 Hz; a strategy run with Auto on calling K1ABC from Tx 1500; a contest run (WW Digi, S&P) for the subscription; hand-authored waterfall rows.
             Steps: parse spots with rp -5, -99, 99, absent, 100, "x" and 2.5; spots to K1ABC from other senders at 14075200 Hz with t_tx in an even and in an odd period, twice the same offset in both parities; pskr.json of schema 1, schema 2 with use false, broken; POST /pskr/use {use false} and true, with an extra key, another profile, a stale boot, from the MCP principal; GET /pskr; a pskr.state subscriber; Use off and on during the run, and the subscription of a contest run's target; hearing with the feed connected and no spot, a spot 60 s old with rp -12, 601 s old, the feed not connected, a target call with a slash; the slot with his decoded offset of my Tx parity at the quietest slot, of the other parity there, and none.
             Expected: rp -5, -99 and 99 kept; absent, 100, "x" and 2.5 read as unknown and the spot still counts; offsets [1200] with their parities, the same offset kept once per parity; schema 1 reads use true and is written as schema 2 at the next change, use false read, the broken file reads enabled true and use true with invalid_pskr; use saved and returned by GET /pskr and pskr.state, the refusals 400 invalid_request, 403 wrong_profile, 409 state_conflict boot_id, 401 for MCP; with Use off no target subscription (UNSUBSCRIBE seen) and the run's hearing state unknown, with Use on SUBSCRIBE pskr/filter/v2/+/+/+/K1ABC/# again, also for the contest target; hearing {no, null, null}, {heard, t, -12}, {no}, {unknown}, {unknown}; his_end no when the slot within 50 Hz of his offset of my Tx parity was the only choice and else the next quietest slot with his_end yes, the other parity's offset not excluding, his_end unknown without spots. Red on the parent: rp, use and the parity do not exist.
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
    dependency CL_039_23_verified_by_TC_039_048 from 'CL-039-23' to 'TC-039-048';
    dependency CL_039_09_verified_by_TC_039_048 from 'CL-039-09' to 'TC-039-048';
    verification 'TC-039-049' {
        doc /* TC-039-049 — Hold Tx on in a run: Tx stays, Rx on the station, Tx alone moves when he does not hear us
             CL-039-08, CL-039-09, CL-039-21, CL-039-22
             Setup: as TC-039-022 (the actual station router, contact engine, automation and #9 transmit owner on the recording hardware double, virtual UTC, a feed without a connection fed hand-authored spots, a dial of 14074000 Hz, hand-authored waterfall rows), Hold Tx on (the default), Tx 1500, FT8 and FT4; a strategy run with Auto on (repetitions 4), a contest S&P run, a pounce, a plain MCP run; "Casual 20 m" for the CQ.
             Steps: (a) select K1ABC (CQ at 1800 Hz). (b) 2 repetitions with no spot, the quietest slot 1400, then 1300. (c) A repetition whose quietest slot lies within 50 Hz of Rx (1800 signal). (d) A spot of my call at K1ABC 60 s old. (e) His report after the 1st repetition, then silent periods. (f) Select a station at 1520 Hz (within 50 Hz of the held Tx), and a caller at 1530 Hz. (g) The held Tx at 2700 (FT4), a station at 1000; then an unanswered repetition with no spot. (h) The CQ when no target from the held Tx 900, one parity loud; callers at 1200 and at 920. (i) Hold Tx switched off during the contact, then the next repetition. (j) Contest S&P: (a) and (b); contest Run: (h) (its CQ from the held Tx 900, callers at 1200 and at 920). (k) Pounce on K1ABC. (l) Plain MCP run.
             Expected (hand-worked from the operator's rule, #39 holdtx round 1): (a) Tx 1500, Rx 1800, no set_frequency of Tx, tx_slot.hz 1500; (b) Tx 1400 then 1300, Rx 1800 both times, slot_check {repetitions, hears_us false, hz}; (c) that slot excluded, the next quietest chosen; (d) Tx stays, hears_us true; (e) Tx never moves after the report; (f) Tx to the nearest slot 50 Hz clear of the station's signal (the lower on a tie), Rx on the station; (g) Tx 2700 kept at the selection, Rx 1000; at the repetition Tx moves to the quietest slot inside 300..2610 (2700 is no candidate, round 3 Q6), Rx stays 1000; (h) the CQ keyed on 900 with no slot decision; the caller at 1200 answered from 900, Rx 1200; the caller at 920 moves Tx to the nearest slot 50 Hz clear of it, Rx 920; (i) Tx and Rx together on the slot (Hold Tx off rule); (j) S&P as (a) and (b), Run as (h); (k) Tx stays 1500, Rx on K1ABC, never moved; (l) tx_slot null, Tx kept. Red on the parent: (a), (b), the selection of (g), (h), the Run of (j) and (k) set Rx = Tx on the slot (the repetition of (g) is green on the parent, which also moves Tx into the range).
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF (wstx-rust). */
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
    dependency CL_039_21_verified_by_TC_039_049 from 'CL-039-21' to 'TC-039-049';
    dependency CL_039_22_verified_by_TC_039_049 from 'CL-039-22' to 'TC-039-049';
    verification 'TC-039-050' {
        doc /* TC-039-050 — Quietness above the passband floor (#66 replaces the usual level)
             CL-039-09
             Setup: the slot function and the per-period waterfall power with hand-authored detailed rows (levels in dB per bin, written in the test), FT4 and FT8, no decoded station unless a step names one; the actual station router for the status. Floor oracle: a flat floor F gives the floor F + 0.65 exactly (the lowest tenth of every segment is F); a sloped table's floor is a reference vector from an independent least-squares fourth-order fit (numpy.polynomial, version recorded with the vector) through the lowest-tenth points of its ten segments, plus 0.65 dB, stored next to the test with its source.
             Steps: (a) the FT4 roll-off table: a floor of 30 dB flat to 2400 Hz and falling linearly to 15 dB at 2700 Hz (5 dB per 100 Hz, a sharp knee the fourth-order floor cannot follow: the roll-off slots read about 2 dB below it) in all 4 counted Rx periods, and AA3B 12 dB above the floor at 2621 Hz (width 90), not decoded, the reproduction of 2026-11-07 (tx_slot 2610 power_db 29); twice: the current Tx 1500 on the flat floor, and the current Tx 1500 on an undecoded station 18 dB above the floor at 1500.5..1590.5 Hz (an FT4 signal; level and position chosen so that the parent's rule makes the same choice). The fixture is authored so that every candidate deciding the choice (those no farther from the current Tx than the chosen slot) has its compared value, its largest rise clamped at 0, at least 0.1 dB from a half dB (the vector's margin_db), so the whole-dB rounding of the choice is unambiguous. (b) FT8 flat floor 30, the current Tx 1500 on a slot 5 dB above the floor in all 4 periods, every other slot on the floor. (c) Busiest period: slot A on the floor in 3 periods and 6 dB above it in one, slot B 3 dB above it in all 4, every other candidate covered 10 dB above the floor. (d) The floor 30 in the two older periods and 32 in the two later, everywhere. (e) One counted period only, the current Tx on a slot 4 dB above the floor. (f) A period I transmitted in; a 5th older Rx period quiet at another slot; after the Tx parity changed, my last counted Rx periods 3 minutes old. (g) A station band change. (h) Values 0.4 against 0.0 (a tie) and 0.6 against 0.0. (i) Coverage: one period whose levels end at bin 921 (2698.2 Hz) and one whose levels end at bin 920 (2695.3 Hz), the other periods unchanged; a flat-floor period with one segment where only its 8 lowest bins sit at the floor (the minimum of 8 points from that segment). (j) No counted period. (k) The status of each.
             Expected (hand computation recorded in the test, the floor from the reference vector): (a) the roll-off slots below the floor read 0 (clamped), the same as the free mid-band slots, never lower; the slots on AA3B stay positive; with Tx 1500 on the flat floor Tx stays 1500 (value 0, the current Tx kept); with Tx 1500 on the station Tx goes to 1410 (value 0), the free slot nearest 1500, the lower on equal distance; never a slot in 2400..2610 and never 2530 (raw level alone would choose 2530 at 21 dB on the roll-off; the unclamped floor rule chose 2530 at about -2); (b) Tx leaves 1500 for the nearest floor slot, value 0 (rise -0.65 clamped), the slot at 1500 value 4; (c) B wins, values 2 against 5 (the mean would choose A); (d) a floor slot reads 0 in every period (rise -0.65), not raised by the floor change; (e) one period compares: Tx leaves for the nearest floor slot; (f) the transmitted period, the 5th older period and the 3-minute-old periods never count: no power, Tx kept, power_db null; (g) after the band change only later periods count; (h) 0.4 ties and keeps the current Tx, 0.6 does not; (i) the period ending at bin 921 counts and the one ending at bin 920 does not (its slot values and decodes absent from the result, periods now one less); the 8-point segment fits the floor of the hand computation (the cutoff is its 8th lowest level); (j) the current Tx kept, power_db null; (k) tx_slot.power_db is the whole-dB value of the chosen slot, never negative; free_tx_slots rise_db the same value while level_db and floor_db are the busiest period's as measured (level_db 30 and floor_db 31 on the flat floor of 30). Red on the parent: (b) and (e) keep the current Tx (every rise 0 over its own usual level); (a) is a regression guard, green on the parent and red on the unclamped floor rule.
             #82: (k) free_tx_slots carries no per-slot numbers; only tx_slot.power_db is checked, and the chosen floor slot lies in an open range of the same build when it overlaps no decode.
             2 — Isolated automated tests; Windows development PC, no radio (wstx-rust). */
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
             Steps: select "Farthest new on band", Auto on, let it call stations to one logged QSO and through a station that does not answer; note tx_hz and rx_hz before and after each selection and at each repetition; select "Casual 20 m" and let it call CQ; switch Hold Tx off and let it call one station; HALT.
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
    dependency CL_039_21_verified_by_TC_039_051 from 'CL-039-21' to 'TC-039-051';
    dependency CL_039_22_verified_by_TC_039_051 from 'CL-039-22' to 'TC-039-051';
    requirement 'CL-042-01' {
        doc /* The award goals read the sender's cty.dat entity (#55) against the internal log: DXCC entity ever, on this band, on this band and mode, and CQ zone ever (WstxStrategy::GoalNeeded, #39 2026-11-04, which replaces the former New conditions on continent and ITU zone); a sender without an entity, an unknown station band (for the band forms) or an unreadable log never counts as needed. The editor offers them as goals; the live preview names why. Details: WstxStrategy::GoalNeeded. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/dxcc.rs; server/src/logbook.rs; client/contact.js";
    }
    dependency CL_042_01_to_FR_007 from 'CL-042-01' to 'FR-007';
    dependency CL_042_01_to_FR_011 from 'CL-042-01' to 'FR-011';
    verification 'TC-042-001' {
        doc /* TC-042-001 — DXCC and CQ zone goals against a hand log
             CL-042-01
             Setup: the bundled cty.dat; a worked set from a hand log: DL1ABC 40m FT8 unconfirmed (Fed. Rep. of Germany, EU, CQ 14, ITU 28), JA1XYZ 20m FT8 confirmed (Japan, AS, 25, 45), F1ABC 40m FT4 confirmed (France, EU, 14, 27), K2ABC with no band (United States, NA, 5, 8), Q1ABC 40m FT8 (no entity); station HB9BLA JN47AA on 40m FT8; rows CQ DL2XYZ, CQ F5ABC, CQ JA2ABC, CQ VK2ABC (Australia, OC, 30, 59), CQ K1ABC, CQ XX1ABC (no entity), CQ DL1ABC. A browser case: the editor offers the goals and the station keeps them.
             Steps: evaluate one-goal strategies dxcc, dxcc_band, dxcc_slot and waz, needed not_worked; the same with the station band unknown and with the log unreadable.
             Expected (entity columns of the cited cty.dat lines; the log of the test): dxcc VK2ABC only; dxcc_band JA2ABC VK2ABC K1ABC; dxcc_slot also F5ABC; waz VK2ABC only; XX1ABC never; band unknown: the band goals false, dxcc and waz unchanged; log unreadable: every goal false.
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
        doc /* Alert has no setting: for each new candidate of the active strategy (an ignored sender, a directed CQ not for me and a caller of my call never alert), the station records an alert (time, call, message, strategy name, band, mode, SNR, DXCC entity) in a history of the last 100 alerts in station memory (kept across page reloads, empty after a station restart), at most one per call and band in 10 minutes, and announces it to the browser; the browser plays a short sound and/or shows a browser notification as the operator chose in Settings > General (both off by default; the notification permission is asked only on the operator's click; no sound while the page is hidden), and lists the history with a Clear. An alert never transmits or changes a contact or automation run. An MCP client may read the history (wstx_read alerts), not clear it. Details: WstxStrategy::Alert; WstxMcp::ToolCatalog. */
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
             Setup: hand-written configuration JSON with one strategy "NA first", the parser only.
             Steps: parse the valid configuration (value [most_wanted, distance], callers_first false, cq_when_no_target true, repetitions 5, quiet_minutes 15) and serialize it; parse variants each with one refused value: continent XX, active not listed, highlight present, a padded or empty name, class contest, a goal twice or unknown, no goals, needed any, region kind other, selected without continents, a continent twice, dx with continents, min_snr_db 50, repetitions 0 and 21, quiet_minutes 0 and 121, a value criterion unknown or twice, 11 criteria, a non-boolean callers_first or cq_when_no_target, the key calls_per_station, a non-boolean treat_73_as_cq, window kind other, a bad date, from after to, an extra key (rules), two names equal ignoring case, 17 strategies; an empty value list.
             Expected: the valid one round-trips to the same JSON; the empty value list is valid; each refusal names exactly its field path (e.g. strategies[0].window.to, strategies[0].value[1], strategies[0].calls_per_station).
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
        attribute executable : String = "server/src/strategy_tests.rs";
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
             Setup: as TC-039-003 with the contact engine and #9 transmit owner on the recording hardware double (virtual UTC set 1 s after an even FT8 period E; own periods odd); the strategy selected from the browser path (cookie grant) with "Test calls" (goal new_call, Treat 73 as CQ, repetitions 2, quiet_minutes 1, value [snr], callers_first true) and Auto switched on from the browser (POST /strategy/auto).
             Steps: (a) PUT with active and Auto on: the run starts, no CQ; publish CQ NA W1AW (strongest), CQ JA JA1XYZ, CQ 290 N1MM, CQ DL1XYZ, CQ K1ABC; two empty partner periods; CQ K1ABC and W1AW DL1XYZ RR73 at 1700 Hz; CQ K1ABC alone afterwards, before and after its quiet minute; PUT None; PUT active again and Auto on; HALT; Esc. (b) A QSO to its end, then the next station, repeatedly past the former limits; the deadline seam moved past 480 minutes. (c) A caller against a candidate; a browser select_row and enable_tx during the run's contact and while it waits; the partner's RR73; a new CQ; a run contact cancelled by the browser followed by the same station's CQ and its call to me; a browser selection racing the run's select_row and enable_tx; stop and Halt while manual. (d) Selecting with no receive; receive starts; the live identity changes during a contact; Auto on without a grant transport; an MCP configure with strategy true; an MCP stop then start; a station restart. (e) A station completed on 40m, as a caller on 40m and as a CQ and a caller on 20m; a retune with a station in its quiet time and with a station the operator gave up. (f) A new proof of the grant during a contact; past the transport's 8 h; the grant revoked.
             Expected: (a) no CQ is ever armed; DL1XYZ or K1ABC selected by value (W1AW, JA1XYZ and N1MM never); after two unanswered periods disarmed, waiting, left {DL1XYZ or K1ABC, repetitions}, no stop reason; the next publication goes to the other station with Rx and Tx on its slot; the left station is not called while in its quiet time, also alone, and is called again after it; None stops the run, disarms and turns Auto off; HALT stops halted, turns Auto off with a new revision and keeps active; Esc leaves active, Auto and the run. (b) The run stays waiting after each completion, no limit_reached, no time_limit. (c) the caller first, whatever goal, region or SNR; a double-click during the run: the run is manual, the strategy stays active, the run neither disarms nor cancels; the manual QSO completed: the run waits and answers the next match; the operator's cancel of the run's contact: that station is not selected again, also not as a caller; the race leaves the operator's contact and the state manual, no stop; Halt while manual stops halted. (d) waiting with reason no_receive and no contact; waiting without a reason after receive starts and it answers; the contact disarmed and cancelled at once and the run waiting on the new identity; strategy_refusal transmit_unavailable, Auto off, the strategy still selected; operator_required strategy, also for the start, nothing armed, an MCP policy of its own starts as ever; active None and Auto off after the restart. (e) not answered again on 40m, called and answered on 20m; the station in its quiet time on 40m is called on 20m, the given-up one is not. (f) the run and its contact go on through the proof and the deadline; the revocation stops authority_lost, disarms and turns Auto off. No PTT exchange.
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
    verification 'TC-039-005' {
        doc /* TC-039-005 — The Tx watchdog stop is never ended by automation
             CL-039-06
             Setup: as TC-039-004; for the unit cases the #9 Core on the hardware double; counts per WstxContact::TxWatchdog (#39, 2026-11-06).
             Steps: (1) browser limit 2; a pounce on K1ABC started from the browser (a strategy run has no stop: TC-039-022); publish CQ K1ABC at E; transmit the call at E+15 s and its repeat at E+45 s; reach E+75 s; cancel, select a strategy from the browser and publish another CQ. (2) MCP and browser: an MCP Enable Tx before any browser action; browser limit 1; an MCP Enable Tx (CQ) transmitted at E+15 s; MCP set_frequency; MCP set_watchdogs 99; reach E+45 s; a station calls HB9BLA in period E+30 s; an MCP Enable Tx; an MCP run start and a matching CQ; a browser action and an MCP Enable Tx. (3) MCP route: browser limit 1, an MCP Enable Tx and its CQ, MCP-principal commands through the tool and straight to /contact/command, then MCP Enable Tx on both. Unit: automatic arm before any operator action; activity, limit 2, automatic arm; operator arm.
             Expected: (1) remaining calls 1 after the first call (the run's selection does not extend it), the request at E+75 s is never keyed, the run stops tx_watchdog, tx_expired true, last cause tx_watchdog and halt_state unchanged (no halt); the selection arms again. (2) refused tx_watchdog; not spent after the one CQ and the MCP command, set_watchdogs refused operator_required, the next CQ never keyed and spent, still spent after the caller (an answer after a stop ends nothing), the MCP Enable Tx refused tx_watchdog, the MCP run stops tx_watchdog unarmed with no further key; still spent after an unrelated browser action; after a browser Enable Tx not spent and the MCP Enable Tx arms. (3) after the stop spent after every MCP request, both Enable Tx refused tx_watchdog, one key in total. Unit: spent before any action; not spent after the activity; remaining 2 after the automatic arm and after the operator arm.
             2 — Isolated automated functional tests; Windows development PC, transmit double; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-06';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_06_verified_by_TC_039_005 from 'CL-039-06' to 'TC-039-005';
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
    dependency CL_039_04_verified_by_TC_039_006 from 'CL-039-04' to 'TC-039-006';
    dependency CL_039_05_verified_by_TC_039_006 from 'CL-039-05' to 'TC-039-006';
    dependency CL_039_10_verified_by_TC_039_006 from 'CL-039-10' to 'TC-039-006';
    verification 'TC-039-007' {
        doc /* TC-039-007 — Live strategy on HB9BLA
             CL-039-03, CL-039-04, CL-039-05, CL-039-06
             Setup: the gated candidate installed on HB9BLA, IC-7300 on COM3 on 40 m FT8, RF power set by the test to at least 30 W before the first Tx (CI-V 14 0A, starting at 0090, with the station stopped and idle, because it holds COM3; read back; the first Tx must read Po at least 30 %; if below, raise the value and repeat; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported), operator consent; Tx watchdog 6 repetitions (the profile default).
             Steps: create an award strategy (goal new_call, region dx, Treat 73 as CQ); select it with Auto off for two periods; switch Auto on; let it work two stations; HALT; switch Auto on again; Esc during a QSO; select None; in Settings > General click Update Most Wanted once.
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
    dependency CL_039_04_verified_by_TC_039_007 from 'CL-039-04' to 'TC-039-007';
    dependency CL_039_05_verified_by_TC_039_007 from 'CL-039-05' to 'TC-039-007';
    dependency CL_039_06_verified_by_TC_039_007 from 'CL-039-06' to 'TC-039-007';
    // ---------------------------------------------------------------- #55 DXCC from cty.dat
    requirement 'CL-055-01' {
        doc /* The station resolves each call to its DXCC entity from AD1C's cty.dat exactly as WSJT-X does: exact =CALL entries, the longest matching prefix, operating suffixes (/P, /QRP, /M, a digit and the other WSJT-X suffixes), compound calls by their shorter side, /MM and /AM without entity, the KG4 rule, and the zone, position and continent overrides of the matching entry; names are shown in the WSJT-X short form with WAE entities shown as their DXCC. The cty.dat WSJT-X 3.3.0-beta5 ships (VER20250115) is bundled with its source and permission notice. Details: WstxContact::CountryFile, EntityOfCall. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/dxcc.rs";
    }
    dependency CL_055_01_to_FR_011 from 'CL-055-01' to 'FR-011';
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
    requirement 'CL-055-04' {
        doc /* Band Activity colours, hover text and order (operator 2026-11-03). Operator decision deviating from WSJT-X, which colours only CQ/QRZ and calling-me lines: the sender of every decoded message (CQ, replies to others, reports, R-reports, RR73, 73; the sender call of WstxContact::DecodedEntity) is coloured by the same new DXCC, continent, zone, grid and call flags (the whole row for a CQ or QRZ, only the sender's call otherwise, #50 CL-050-08); a message to my call keeps the calling-me colour on top; a row without a flag has no colour (there is no CQ slot, #50, and worked before never colours). Every row with a reason carries hover text (title and aria-description, on the row and its colour mark) naming each reason in value order (#50 CL-050-08 replaces this Band Activity hover by its one-line reason tip; the QSO pane callers keep it): calling me, the strategy verdict, each new flag with its entity, zone, grid or band, then the worked-before status, for example "New DXCC: Romania", "New DXCC on 40m", "New CQ zone 20", "New grid KN34", "New call", "Worked before on 40m FT8". Within each period the rows are sorted by value (1 calling me, 2 strategy hits by their rank, 3 new DXCC, 4 new DXCC on this band, 5 new CQ or ITU zone, 6 new grid, 7 new call, 8 no flag), then by SNR strongest first, ties in decode order; the column headers still choose another order and the DXCC header returns to it. Details: WstxOperatingLayout::BandActivityColours, BandActivityValue, BandActivityHover, ActivityOrdering. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/contact.js; client/logbook.js";
    }
    dependency CL_055_04_to_FR_019 from 'CL-055-04' to 'FR-019';
    requirement 'CL-055-05' {
        doc /* Band Activity rows are tighter so more stations fit (operator 2026-11-03): less vertical padding and line height on decode rows and period dividers at the same font size, at most 24 px per row with a mouse; touch (coarse pointer) and the stacked narrow layout keep tappable rows. Details: WstxOperatingLayout::BandActivityView. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.css";
    }
    dependency CL_055_05_to_FR_019 from 'CL-055-05' to 'FR-019';
    verification 'TC-055-001' {
        doc /* TC-055-001 — Entity resolution known answers
             CL-055-01
             Setup: the bundled cty.dat; a hand-written file with every override kind; malformed files.
             Steps: effective prefix of WSJT-X's own test_radio_callsign vectors with "", /P, /QRP, /P/QRP; resolve HB9BLA, K1ABC, DL1XYZ, EA8ABC, HB9BLA/P, HB9BLA/QRP, W1AW/4, DL/HB9BLA, HB9BLA/DL, EA8/K1ABC, K1ABC/EA8, HB9BLA/MM, K1ABC/AM, KG4AB, KG4ABC, KG4AB/P, 3D2CR, 3D2CR/P, 3D2AG/P, W1AW/KG4, RA0DAA, RA0ABC, KG4IJS/0, IT9ABC, 4U1VIC, 2M0BDR, GB3LER, FO5ABC, UA3ABC, Q1ABC, a non-ASCII text; parse the override file and each malformed file (also CQ zone 41, ITU zone 91, an empty, a 41-character and a non-ASCII name).
             Expected (from the cited cty.dat lines and AD1CCty.cpp): Switzerland, U.S.A., Germany, Canary Is. with their zones; compound and suffixed calls by their effective prefix; /MM and /AM none; KG4 5 characters Guantanamo Bay, else U.S.A.; exact entries only for the whole call (3D2CR Conway Reef, 3D2CR/P Fiji, 3D2AG/P Rotuma Is.); zone overrides RA0 19/33, RA0A 18/32, KG4IJS/0 4/7; Sicily, Vienna Intl Ctr and Shetland shown as Italy, Austria, Scotland; the first entry of a duplicate key (GB3LER Scotland); version VER20250115, 346 entities; overrides applied; malformed files refused with their line.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-055-01';
        }
        attribute executable : String = "server/src/dxcc_tests.rs";
    }
    dependency CL_055_01_verified_by_TC_055_001 from 'CL-055-01' to 'TC-055-001';
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
    dependency CL_055_04_verified_by_TC_055_006 from 'CL-055-04' to 'TC-055-006';
    dependency CL_055_02_verified_by_TC_055_006 from 'CL-055-02' to 'TC-055-006';
    verification 'TC-055-007' {
        doc /* TC-055-007 — Dense Band Activity rows
             CL-055-05
             Setup: operating fixture at 1366x768 with a period of 30 routed decodes; Chromium.
             Steps: wait for the rows; measure a row, the font size and the rows fully visible in the table; read the coarse-pointer rule.
             Expected: a row at most 24 px high (41 px before), the font size unchanged (the normal operating font), at least 8 rows visible (5 before), and a pointer:coarse rule keeping at least 8 px cell padding; screenshot band-activity-density-1366.png (before and after on the issue).
             2 — Isolated automated (functional) tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-055-05';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_055_05_verified_by_TC_055_007 from 'CL-055-05' to 'TC-055-007';
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

    // #51 An open page recovers after a station update (chosen defaults: WstxStationProtocol::PageUpdate).
    requirement 'CL-051-01' {
        doc /* The station identifies the browser client it serves with WstxStationProtocol::ClientBuild: the first 16 lower-case hex digits of the SHA-256 over its served client files in route order. The served page carries it as body data-build and every station.status reply carries it as data.build (data exactly {version, radio, build}). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs";
    }
    dependency CL_051_01_to_FR_021 from 'CL-051-01' to 'FR-021';
    requirement 'CL-051-02' {
        doc /* A page whose build differs from the build in a station.status reloads itself once for that station build, keeping its browser storage (WstxStationProtocol::PageUpdate). The operating screen holds the reload while a contact or transmission is in progress, a popup is open or the Settings form has unsaved edits, and shows the "Station updated · reload" chip instead; the chip's click reloads. A second mismatch for a build the tab already reloaded for shows the chip and never loops. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/app.js; client/recording.js";
    }
    dependency CL_051_02_to_FR_021 from 'CL-051-02' to 'FR-021';
    requirement 'CL-051-03' {
        doc /* A receive snapshot, result page, operating selection snapshot, contact snapshot or waterfall frame of an unknown shape that the page rejects by its validation is never silent: the top bar shows the error chip "Station data not understood (<which>) · reload", whose click reloads the page; a later valid snapshot of that kind clears it. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/contact.js";
    }
    dependency CL_051_03_to_FR_021 from 'CL-051-03' to 'FR-021';
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
    dependency CL_051_01_verified_by_TC_051_001 from 'CL-051-01' to 'TC-051-001';
    dependency CL_051_02_verified_by_TC_051_001 from 'CL-051-02' to 'TC-051-001';
    verification 'TC-051-002' {
        doc /* TC-051-002 — A held update and a rejected snapshot show the reload chip
             CL-051-02, CL-051-03
             Setup: actual candidate server and Chromium at 1366x768; routed contact snapshot with a contact calling CQ; the receive snapshot routed through, optionally with an unknown key dxcc; the proxy of TC-051-001.
             Steps: read receive with the unknown key, then without; the same for a result page, the operating selection snapshot and a contact snapshot; announce a spectrum.detail.frame of the current job with an unknown key; restart the station with build fedcba9876543210 while calling CQ; wait 1.5 s; click the chip; open a confirmation popup and reconnect to a status with another build.
             Expected: the error chip "Station data not understood (receive) · reload" in the error field, hidden again after the valid read; the same with (results), (selection) and (contact); (waterfall) for the frame; while calling CQ the warn chip "Station updated · reload" and no reload; the click reloads once and the reloaded page receives with no chip; with the popup open the chip and no reload; no page error.
             2 — Isolated automated functional tests; Windows development PC, loopback only. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-051-02';
            verify 'CL-051-03';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_051_02_verified_by_TC_051_002 from 'CL-051-02' to 'TC-051-002';
    dependency CL_051_03_verified_by_TC_051_002 from 'CL-051-03' to 'TC-051-002';
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
    dependency CL_051_01_verified_by_TC_051_003 from 'CL-051-01' to 'TC-051-003';
    dependency CL_051_02_verified_by_TC_051_003 from 'CL-051-02' to 'TC-051-003';

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

    // #50 Operating screen operator feedback and #54 continuous WSJT-X-like waterfall (one CR, 2026-11-02).
    requirement 'CL-050-01' {
        doc /* The top bar shows UTC without a period bar; the period progress is the QSO pane's NEXT bar. The waterfall Rx and Tx markers are 3 px green and red lines without text labels, draggable. A waterfall click sets Tx (sent after 250 ms), a double-click sets Rx and Tx with one request; modifiers do not change the effect and a right-click sets nothing (WstxContact::PointerEffect). The help overview states this mapping. A double-click on a decoded Band Activity row selects the station and starts the reply, as Reply. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.js; client/recording.css";
    }
    dependency CL_050_01_to_FR_007 from 'CL-050-01' to 'FR-007';
    dependency CL_050_01_to_FR_019 from 'CL-050-01' to 'FR-019';
    requirement 'CL-050-02' {
        doc /* Band Activity rows use the WSJT-X 3.3 default highlight colours and priority with its default on/off except as stated here (WstxOperatingLayout::BandActivityColours), with no text marks other than the a-priori marker aN after an a-priori word's message (#56 slice 5): My call from the message, the New call, New call on band, grid, DXCC, continent and zone slots from the record flags the station supplies (#55; a never-worked call carries both New call flags), for every decoded sender (operator decision, CL-055-04, not only CQ/QRZ lines as in WSJT-X; what a slot colours, whole row or the sender's call only, and the QSO partner's marker: CL-050-08); New call and New call on band are on by default (WSJT-X: off). Only stations of interest are coloured (operator 2026-11-03, deliberately unlike WSJT-X): there is no CQ slot, so a CQ from a station worked before on this band and mode, and every other row that carries no enabled slot, has no colour, while My call still applies. The slots are chosen per browser in Settings > General > Display. The #39 strategy highlight stays an accent and never replaces these colours. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/logbook.js; client/recording.css";
    }
    dependency CL_050_02_to_FR_019 from 'CL-050-02' to 'FR-019';
    requirement 'CL-054-01' {
        doc /* A Detailed waterfall subscriber receives every Detailed row of the current job in order after a processing stall: the station retains the last 25 rows and sends each peer the oldest row it has not sent, 200 ms apart, 170 ms apart while rows wait (WstxRecordingReceive::TransferDisplay). Live Thin sends keep a fixed 2 s grid from the previous deadline, restarted at a send more than 1 s late, so sends stay at least 1 s apart. The browser draws a gap row only for a real gap; one or two live Thin rows paced out between two sent rows are drawn with the next row. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/recording.rs; server/src/main.rs; client/recording.js";
    }
    dependency CL_054_01_to_FR_019 from 'CL-054-01' to 'FR-019';
    dependency CL_054_01_to_FR_021 from 'CL-054-01' to 'FR-021';
    requirement 'CL-054-02' {
        doc /* The waterfall colour follows a fixed dBFS mapping (WstxRecordingReceive::DisplayLevels): reference -85 dBFS, Sensitivity as WSJT-X Zero, a Range slider as WSJT-X Gain (default 50 dB), no automatic level and no reset on a new job, source or profile; optional Flatten across frequency. The spectrum line is a Settings option (default off) with a [E,0] dBFS scale that never clips; the default signal height is 330 px and the default speed 10 px/s, about two FT8 periods. All are per-browser settings that apply at once. Cells keep one native bin per column range, nearest-neighbour, without smoothing. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/recording.css";
    }
    dependency CL_054_02_to_FR_019 from 'CL-054-02' to 'FR-019';
    verification 'TC-050-001' {
        doc /* TC-050-001 — Waterfall pointer, lines, top bar and double-click to call
             CL-050-01
             Setup: actual release candidate with the contact engine (contact_http_tests::contact_browser_operating_flow) and Chromium; the operating screen fixture of ui-operating with routed Band Activity rows.
             Steps: as TC-010-008; read the top bar and the QSO pane; double-click a CQ row and a row to my call.
             Expected: TC-010-008's #50 expectations; the top bar holds UTC only (one child, no period bar) and the QSO pane keeps #qso-progress; a row double-click sends select_row then enable_tx with the shown safety revision, one each; the help names "Waterfall click / double-click: Set Tx / Rx and Tx".
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-050-01';
        }
        attribute executable : String = "tests/contact.test.cjs; tests/ui-operating.test.cjs";
    }
    dependency CL_050_01_verified_by_TC_050_001 from 'CL-050-01' to 'TC-050-001';
    verification 'TC-050-002' {
        doc /* TC-050-002 — WSJT-X Band Activity colours
             CL-050-02
             Setup: (a) actual candidate server; routed live job with CQ K1ABC (worked_this_band_and_mode), CQ W1XYZ, a report K9XX W2AB R-05 (both not_worked) and a free-text row; (b) the same server with routed records carrying the station's #55 flags and worked_status: CQ K1AA (no flag, worked_this_band_and_mode), CQ K2BB (new_call_band, worked_other_band_or_mode), CQ K3CC (new_call and new_call_band, not_worked) and HB9BLA K1AA R-05 to my call; Chromium.
             Steps: wait for the worked-before status of the rows; read row slots and backgrounds; turn New call off in Settings; append synthetic rows with slot sets for the #55 flags.
             Expected: no text marks; no CQ slot in Settings and no row slot cq; (a) the CQ W1XYZ row and the sender call of the non-CQ row K9XX W2AB R-05 (flags new_call, new_call_band; CL-055-04; only the call, CL-050-08) rgba(0,255,255,0.24) by default and rgba(153,255,255,0.2) with New call off; K1ABC (worked on this band and mode, no flag) and the free-text row no slot, background rgba(0,0,0,0); the choice saved in browser storage; priority My call > New continent > New DXCC, New grid and ITU zone off by default; (b) K1AA no slot and rgba(0,0,0,0); K2BB new_call_band, rgba(153,255,255,0.2); K3CC new_call and new_call_band, rgba(0,255,255,0.24); the row to my call from K1AA mycall only, rgba(255,102,102,0.32).
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-050-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_050_02_verified_by_TC_050_002 from 'CL-050-02' to 'TC-050-002';
    // #50/#10 operator feedback 2026-11-02 evening (US5WFL/YO3GNF, TC2TR, the 22:48 CQ run on 40 m).
    requirement 'CL-050-04' {
        doc /* Replacing an active contact (ChangeContact, select_row or enter_dx with replace true) keeps Enable Tx as it is: with Enable Tx on, the next period of the new contact's parity carries the new contact's next message, and after a transmission already on the air nothing more goes to the old partner. A double-click (or Reply) on another station's Band Activity row, idle, after a completed contact, during a contact or during my CQ, also when the rows are redrawn between its two clicks or during its second press, is that selection without a confirmation, followed by Enable Tx on (WSJT-X double-click with "Double-click on call sets Tx enable"), each request retried at most twice after a stale_revision refusal; Auto Seq then runs the QSO to its completion and log. During a station automation run an operator replacement of the run's contact ends the run, which disarms (WstxMcp, TC-020-003). A single click only offers "Change contact to <call>" during a contact and never turns Enable Tx on. Details: WstxContact::ChangeContact, SelectDecodedRow, WstxOperatingLayout::BandActivity. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; client/contact.js";
    }
    dependency CL_050_04_to_FR_007 from 'CL-050-04' to 'FR-007';
    dependency CL_050_04_to_FR_008 from 'CL-050-04' to 'FR-008';
    requirement 'CL-010-17' {
        doc /* (#10) Call 1st (WSJT-X "CQ: First"), an operator setting next to Auto Seq, initially on: while my own CQ runs with Enable Tx and Auto Seq on, the first decoded message to my call of a step, in decode order, whose exchange is a grid or a report is answered at once as a selection of that row with Enable Tx kept, so the next own period answers that caller. Off, a CQ moves only on an operator selection. Details: WstxContact::CallFirst. */
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
    // #50/#37 CR 2 (operator 2026-11-02): period bar, QSO pane lines, QSO dialogue.
    requirement 'CL-050-03' {
        doc /* The QSO pane's period bar shows the elapsed part of the current period (15 s FT8, 7.5 s FT4) on the station's clock, the UTC the transmitter keys on including the #43 correction, never the browser's wall clock: the browser takes the largest offset of the station's utc_ms over its own monotonic time among the observations of the last 20 s and redraws at least every 100 ms without animation. An offset more than 500 ms below the estimate is a backward step of the station clock and restarts the estimate at once. The bar is red in a period of my Tx parity while Enable Tx is on and whenever the station reports transmitting, green in every other period. Details: WstxContact::OperatorDisplays StationPeriodClock, WstxOperatingLayout::QsoPane. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_050_03_to_FR_008 from 'CL-050-03' to 'FR-008';
    dependency CL_050_03_to_FR_019 from 'CL-050-03' to 'FR-019';
    requirement 'CL-050-05' {
        doc /* (#37) While an own CQ runs the QSO pane header reads "Calling CQ" with the Tx period; the message line reads "▶ TX now: <message>" with the seconds left while the station reports transmitting ("▶ TX now: Tune" with the Tune seconds left during Tune) and "▸ next: <message> · Tx in <n> s" otherwise; the Calling me section below the QSO dialogue lists only stations calling my call, one line per station with call, SNR, grid and country: every caller other than the partner on any frequency as soon as decoded, during a QSO ⚠ marking one within +/-50 Hz of my Rx or Tx offset and a double-click switching the contact with Enable Tx kept; an empty list shows the placeholder "Nobody is calling" (#37 2026-11-04, CL-037-04). Details: WstxOperatingLayout::QsoPane. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_050_05_to_FR_007 from 'CL-050-05' to 'FR-007';
    dependency CL_050_05_to_FR_019 from 'CL-050-05' to 'FR-019';
    requirement 'CL-050-06' {
        doc /* (#37) The contact snapshot carries the QSO dialogue of the current contact, at most 16 entries: each partner message the engine counted (with SNR) and each of our transmissions of that contact as sent, with its period start and a repeat count; the QSO pane shows it while the QSO runs, oldest first and newest at the bottom, scrolling inside the card without growing the page, and drops it with the QSO. Details: WstxContact::ContactSnapshot dialogue, WstxOperatingLayout::QsoPane. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; client/contact.js; client/recording.css";
    }
    dependency CL_050_06_to_FR_007 from 'CL-050-06' to 'FR-007';
    dependency CL_050_06_to_FR_019 from 'CL-050-06' to 'FR-019';
    verification 'TC-050-003' {
        doc /* TC-050-003 — Period bar colour and station clock
             CL-050-03
             Setup: actual candidate server and Chromium; the operating screen with a routed ContactSnapshot (Enable Tx on, own CQ, parity even) whose utc_ms is the browser's time plus a station offset; station.tick events dispatched to the page.
             Steps: read #qso-progress width and colour in an even and an odd station period, with transmitting true in the odd period, and after a 1 s backward step of the station clock; screenshots at 1366x768 and 360 px of a receive (green) and a transmit (red) period.
             Expected: the width is (station time mod period)/period within 4 percentage points, not the browser-clock phase, also right after the backward step; the even period (my Tx parity) and a transmitting period rgb(255, 64, 64), the odd receive period rgb(48, 208, 80); no width transition.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-050-03';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_050_03_verified_by_TC_050_003 from 'CL-050-03' to 'TC-050-003';
    verification 'TC-050-005' {
        doc /* TC-050-005 — QSO pane while calling CQ and transmitting (#37)
             CL-050-05
             Setup: actual candidate server and Chromium; routed ContactSnapshot of an own CQ with Enable Tx on; station.tick events dispatched to the page; routed live rows.
             Steps: (ui-operating TC-050-005) read the header after a receive refresh, the message line with transmitting true (4 s into my period), with a transmit view whose last_text of this period differs from the next message, during Tune, and with transmitting false at the next odd period start, and Calling me with no row; (ui-operating TC-007-009) Calling me idle and during a QSO with Rx 1500 Hz and Tx 2100 Hz, with callers of my call at 400, 1505 (the partner), 1530, 2130 and 1600 Hz and CQs near Rx, then with Rx and Tx at 2800 Hz; (contact.test TC-007-003) Calling me with a caller and CQs near Rx on the actual server; screenshots of calling CQ, TX now and between periods.
             Expected: header "Calling CQ" with "Tx even (1st)"; "▶ TX now:" "CQ HB9BLA JN47" with "10 s left", then "K1ABC HB9BLA -05" (the text on the air), "▶ TX now:" "Tune" with "80 s left"; "▸ next:" "CQ HB9BLA JN47" with "Tx in 15 s"; "Nobody is calling" for an empty list; idle every caller as a Calling me row "<caller> | <SNR> | <grid> | <country>" oldest first and no CQ; during the QSO every caller but the partner, the 1530 and 2130 Hz callers marked ⚠ ("SV1DZB ⚠"), none marked at 2800 Hz, and a double-click on any caller sends select_row replace true then enable_tx.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-050-05';
        }
        attribute executable : String = "tests/ui-operating.test.cjs; tests/contact.test.cjs";
    }
    dependency CL_050_05_verified_by_TC_050_005 from 'CL-050-05' to 'TC-050-005';
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
    // #50 waterfall frequency mapping and Rx/Tx brackets (operator 2026-11-03 about 09:45).
    requirement 'CL-050-07' {
        doc /* The waterfall pointer, the Rx and Tx lines and the frequency axis share one mapping of the fixed 0..3000 Hz span onto the waterfall canvas's own box: a click, double-click or marker drag selects the frequency under the pointer, and the confirmed line and the axis tick of that frequency are drawn within 1 px of the pointer position, at every page width, display option (speed, Flatten, spectrum line) and devicePixelRatio. The Rx (green) and Tx (red) lines mark the lowest tone and each carries a WSJT-X bracket (goalpost) at the top of the waterfall over the occupied width to its right, 50 Hz in FT8 and 83.3 Hz in FT4, following the station's operating mode. Details: WstxOperatingLayout::RxTxStrip, WstxContact::PointerEffect. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.js; client/recording.css";
    }
    dependency CL_050_07_to_FR_007 from 'CL-050-07' to 'FR-007';
    dependency CL_050_07_to_FR_019 from 'CL-050-07' to 'FR-019';
    verification 'TC-050-007' {
        doc /* TC-050-007 — Waterfall pointer, lines and axis on one frequency mapping; Rx/Tx brackets
             CL-050-07
             Setup: actual release candidate (fixture station) and Chromium with routed contact snapshots and recorded contact commands; station.tick delivered through the page's own listener.
             Steps: at 1366x768 double-click and click at the 500, 1500 and 2500 Hz axis ticks and drag the Tx line to the 2000 Hz tick, confirming each value in the contact snapshot; repeat at 900x700 and at 360x800, with Flatten and the spectrum line on, at speed 4 and with devicePixelRatio 2; read the bracket of each line in FT8 and after an FT4 tick.
             Expected: each request carries the tick's frequency within 2 Hz; each confirmed line's centre and each tick lie within 1 px of the pointer position; the bracket starts within 1 px of its line and is as wide as 50 Hz (FT8) or 83.3 Hz (FT4) on the mapping, within 1 px, green for Rx and red for Tx; a click inside a bracket still reaches the waterfall.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-050-07';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_050_07_verified_by_TC_050_007 from 'CL-050-07' to 'TC-050-007';
    // #50 operator design 2026-11-04 (refines the 2026-11-03 colour rule).
    requirement 'CL-050-08' {
        doc /* Band Activity marks each decoded row by what makes it interesting, highest first (WstxOperatingLayout::BandActivityScheme, BandActivityRowMark): (1) the current QSO partner, from the contact preparation until the contact is logged or cancelled, taken from the contact snapshot the page already holds (no further request): its rows are moved to the top of Band Activity with a red separator stripe below them and carry a red left bar, a "◆ QSO" badge after the message and a bold message, without a slot background; (2) a row to my call from another station (also <MYCALL> and a nonstandard i3=4 'to', #24): the whole row in the My call colour, also when the sender was worked before on this band and mode; (3) a CQ or QRZ from a station with an enabled new_* slot: the whole row in that slot's colour; (4) any other row from a station with an enabled new_* slot (in QSO with another station): only the sender's call is coloured, the rest of the row is plain; (5) everything else has no colour. The Settings slot choice applies to every mark. A row's reason tip is one compact line naming only the reasons of its colour that the row does not show, joined by " · ": per kind (continent, DXCC, zone, grid, call) the strongest enabled one, so an overall flag never also names its on-band form, the on-band call reason with the worked-before status in parentheses, then the strategy verdict, e.g. "New DXCC · New call", "New on 40m (worked on another band or mode)"; no country, continent, distance or "Calls you" (the row shows them); a row without such a reason has no tip. It uses only the #55 record data and the record's worked_status (WstxOperatingLayout::BandActivityHover). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/contact.js; client/recording.css";
    }
    dependency CL_050_08_to_FR_019 from 'CL-050-08' to 'FR-019';
    verification 'TC-050-008' {
        doc /* TC-050-008 — Band Activity row marks: partner first with the stripe, calls me, CQ of interest, sender-only colour, one-line reason tip
             CL-050-08
             Kept status (#50, live 2026-11-06): a row with the tip "New on 20m (worked on another band or mode)" keeps that tip when the next period of the other parity moves it below the divider, while that period is partial and after it is complete, with no worked-before query.
             Setup: actual release candidate (fixture station) and Chromium at 1440x900; routed receive pages for a kept period 12:00:00 (CQ K1PT FN42 new_call_band; CQ K7OLD FN42; K9XX W1AA R-03) and a latest period 12:00:15 (HB9BLA K1PT FN42 new_call_band; HB9BLA K2CM -05; HB9BLA K3NB R-07 new_call_band; CQ OA4DX FH17 and K9XX YO3ABC -07 with new_dxcc, new_dxcc_band, new_call, new_call_band and dxcc Peru/Romania; CQ K1WB FN42; W9AA W2CD 73; CQ JA1ZZ PM95 new_cq_zone, new_cq_zone_band, CQ zone 25), selection band 40m, the records' worked_status (K2CM, K1WB and W2CD worked on 40m FT8, K3NB on another band or mode, the others not worked) and routed contact snapshots.
             Steps: with no contact read each row's marks, message cell and sender-call backgrounds and reason tip; hover the YO3ABC message, its DXCC cell and an uncoloured row; focus the K3NB row; route a contact with K1PT in replying and reload the snapshot; read the order, stripe and marker; read the stripe at 360x800; sort by Freq and back; turn My call and New call off in Settings; route the contact completed and reload.
             Expected: no contact: no stripe; the three rows to my call whole row rgba(255,102,102,0.32) with tips "New on 40m", none (worked on this band and mode, no flag) and "New on 40m (worked on another band or mode)"; CQ OA4DX whole row rgba(255,0,255,0.26) tip "New DXCC · New call"; K9XX YO3ABC -07 message cell transparent with only the YO3ABC span rgba(255,0,255,0.26) and the same tip; CQ JA1ZZ whole row rgba(255,191,0,0.26) tip "New CQ zone 25"; the rows without a flag uncoloured without a tip; no row has a native title and the aria-description equals the tip; the tip box is one line at the pointer, absent over the DXCC cell and over an uncoloured row, shown for the focused row and gone after focus moves. Prepared K1PT: HB9BLA K1PT FN42 then CQ K1PT FN42 first, then one stripe row (no text, rgb(255,64,64)), then the other rows in the earlier order with the kept divider; the partner rows have no slot background or tip, a 4 px rgb(255,64,64) inset left bar, a bold message and the badge " ◆ QSO"; at 360x800 the stripe is a 3 px full-width rgb(255,64,64) bar; the partner block stays first after the Freq sort. With My call and New call off: K2CM uncoloured, K3NB whole row rgba(153,255,255,0.2), the OA4DX and YO3ABC tips "New DXCC · New on 40m". Completed: no stripe and no partner row; HB9BLA K1PT FN42 is a calls-me row; no worked-before query, none added by the marks, the partner or the tip; no page error.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-050-08';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_050_08_verified_by_TC_050_008 from 'CL-050-08' to 'TC-050-008';
    verification 'TC-010-010' {
        doc /* TC-010-010 — Call 1st answers the first caller of my CQ
             CL-010-17
             Setup: the contact engine against the actual #9 transmit owner core on a virtual clock (contact_tests); hand-authored rows of the 2026-11-02 22:48 CQ run; the snapshot wire (contact_http_tests).
             Steps: Enable Tx with no partner (calling, odd parity), Hold Tx on; after my CQ deliver in one even period, decode order "HB9BLA EA4HTI IM69" (1678 Hz, -8) then "HB9BLA F1PBZ -13" (2144 Hz, -10), in reverse slice order; later "HB9BLA EA8BIA -11" and "HB9BLA SV1DZB KM18"; repeat with Call 1st off, with Auto Seq off, and with only "HB9BLA DL1ABC RR73", "HB9BLA DL2ABC 73", "HB9BLA DL3ABC RRR", "HB9BLA DL4ABC R-10".
             Also: the same callers after Enable Tx off (disarmed, still calling).
             Expected: Call 1st on: the contact is EA4HTI (grid IM69) in report with next Tx2 "EA4HTI HB9BLA -08" at once, still armed, Tx offset 1500 Hz kept, the next odd period sends it; the later callers change nothing; Call 1st off, Auto Seq off, Enable Tx off or only continuing exchanges: still calling (with Enable Tx off nothing is sent) and the next odd period sends "CQ HB9BLA JN47"; the snapshot settings carry call_first true by default.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-17';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs";
    }
    dependency CL_010_17_verified_by_TC_010_010 from 'CL-010-17' to 'TC-010-010';
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
    verification 'TC-054-002' {
        doc /* TC-054-002 — Fixed level mapping, Zero/Gain sliders, Flatten and the spectrum line option
             CL-054-02
             Setup: actual candidate and Chromium at 1366x768; injected Detailed rows with known levels (noise q=40, a -40 dBFS carrier, a passband slope).
             Steps: read cells; move Sensitivity to +10 and Range to 30; reload; start a new job; turn Flatten and Show spectrum line on.
             Expected: E=-85 and span 50 by default (q=40 -> t=0.1, -40 dBFS -> t=0.9 by the palette anchors); g=+10 gives E=-95, R=30 the span 30; values survive a reload and a new job (no auto level, no reset); Flatten evens the slope across frequency within one palette step while the native readout is unchanged; the spectrum canvas is hidden by default and shown on request; signal height 330 px, speed 10 px/s.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-054-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_054_02_verified_by_TC_054_002 from 'CL-054-02' to 'TC-054-002';
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
    dependency CL_054_02_verified_by_TC_054_003 from 'CL-054-02' to 'TC-054-003';
    dependency CL_050_01_verified_by_TC_054_003 from 'CL-050-01' to 'TC-054-003';
    dependency CL_050_02_verified_by_TC_054_003 from 'CL-050-02' to 'TC-054-003';
    requirement 'CL-024-01' {
        doc /* #24 S1. The station keeps one session hash table per station instance, fed by every concrete call decoded or sent and by my own call, and shows a hashed call as <CALL> once it resolves, otherwise <...>, as packjt77 does (this reverses the earlier StationDecode rule that a hash is never filled in). It generates and accepts the WSJT-X message sets for exactly one nonstandard or compound call with the bracket rules of genStdMsgs and refuses two nonstandard calls. It accepts free text of at most 13 characters (0.0) in an operator-edited slot. Every transmitted text packs unaltered. Slice S1a: the hash table and fill-in (WstxOfflineDecode::HashResolution); slice S1b: compound/nonstandard QSOs through the contact engine (WstxContact::StandardMessageSet, SelectDecodedRow, EnterDxStation), the nonstandard DX-call fill-in rule, free text in an operator-edited slot with Tx5 editable from the operating screen, and Band Activity marking <MYCALL> rows as to me. The 0.1 DXpedition DX-call rule (hashdx10) is #24 S4a, TC-024-010. Station automation (Auto Call, Auto CQ, Pounce, the strategy) and Call 1st stay standard-only: a run does not start with a nonstandard profile callsign (not_ready call). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/decoder/hashes.rs; server/src/decoder/payload.rs; server/src/recording.rs; server/src/transmit/service.rs; server/src/contact.rs; server/src/contact_http.rs; client/contact.js; client/recording.js";
    }
    dependency CL_024_01_to_FR_024 from 'CL-024-01' to 'FR-024';
    dependency CL_024_01_to_FR_004 from 'CL-024-01' to 'FR-004';
    verification 'TC-024-001' {
        doc /* TC-024-001 — Hash table learning and fill-in, known and unknown calls
             CL-024-01
             Setup: the pure payload codec and the hash table of WstxOfflineDecode::HashResolution; the transmit owner on its recording hardware double (virtual clock; no audio, PTT or radio).
             Steps: unpack "<PJ4/K1ABC> W9XYZ -05" with no table and with an empty table; learn the decodes "CQ PJ4/K1ABC" (i3=4), "CQ K1ABC/R FN42", "CQ K1ABC FN42", "W9XYZ DL1ABC JO62" and "VK9/K1XX <W9XYZ>" (hash 'from'); fill in "<PJ4/K1ABC> W9XYZ -05", "<K1ABC/R> W9XYZ", "<DL1ABC> PA/K1XX", "<W9XYZ> PA/K1XX", "<VK9/K1XX> W9XYZ", "PA/K1XX <DL1ABC> RR73", a DXpedition 0.1 "K1ABC RR73; W9XYZ <KH1/KH7Z> -12" before and after KH1/KH7Z is learned and an EU VHF i3=5 message; set my call HB9BLA and fill in "<HB9BLA> PJ4/K1ABC", "<HB9BLA> K1ABC -05", "PJ4/K1ABC <HB9BLA> RR73" (i3=4, hash 'from') and "<HB9BLA> <K1ABC> R 570001 JN37VL" (EU VHF); learn 1000 more calls; two calls with the same 12-bit hash one after the other; the transmit owner with the table attached accepts "<VP2X/K1JT> HB9BLA" and "CQ YW18FIFA" and refuses (not armed) "<3D2CR/P> HB9BLA".
             Expected: without a table the text is "<...> W9XYZ -05" with to {kind hash, text null, hash_bits 22}; the 'from' calls K1ABC/R, DL1ABC and the nonstandard CQ call are learned, the 'to' call W9XYZ of "W9XYZ DL1ABC JO62" and the nonstandard full 'to' call of a hash-'from' message are not; filled-in texts "<PJ4/K1ABC> W9XYZ -05" with to {kind hash, text PJ4/K1ABC, hash_bits 22, the same hash_value}, "<K1ABC/R> W9XYZ", "<DL1ABC> PA/K1XX", "<...> PA/K1XX", "<...> W9XYZ", "PA/K1XX <DL1ABC> RR73"; the DXpedition hash "<...>" then "<KH1/KH7Z>"; my call fills "<HB9BLA>" in the 'to' slot of standard, nonstandard and EU VHF messages but not the nonstandard hash 'from' slot ("PJ4/K1ABC <...> RR73"), and still after 1000 more calls have pushed it out of the 22-bit list, where the oldest call is then "<...>"; the later of two calls with one 12-bit hash wins; the accepted requests teach VP2X/K1JT and YW18FIFA, the refused one nothing; the pure unpack of every message is unchanged.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-01';
        }
        attribute executable : String = "server/src/decoder/hashes_test.rs; server/tests/transmit_service.rs";
    }
    dependency CL_024_01_verified_by_TC_024_001 from 'CL-024-01' to 'TC-024-001';
    verification 'TC-024-002' {
        doc /* TC-024-002 — The station's live publication fills in hashed calls
             CL-024-01
             Setup: the actual station Recording owner with a fixture live FT8 job and hand-authored decodes; my call HB9BLA set on the Recording; the station fixture with its transmit owner on the recording hardware double; the real profile PUT handler.
             Steps: publish "<VP2X/K1JT> W9XYZ -05", then "CQ VP2X/K1JT", then "<VP2X/K1JT> W9XYZ -05" again, "<HB9BLA> VP2X/K1JT" and "<DL/K1ABC> W9XYZ"; read the published records, their UDP Decode messages and the strategy facts; change my call to HB9BLB and publish "<HB9BLB> VP2X/K1JT"; run the station's startup hash wiring with the profile call hb9bla; save a profile with callsign HB9BLA through PUT /profile.
             Expected: the first record keeps "<...> W9XYZ -05" (no rewriting of history); the later one reads "<VP2X/K1JT> W9XYZ -05" with to {kind hash, text VP2X/K1JT}, "<HB9BLA> VP2X/K1JT" and "<...> W9XYZ" with text null; the UDP Decode messages carry the same texts; the strategy has no facts for a record whose 'from' is hashed and unchanged facts otherwise; after the change "<HB9BLB> VP2X/K1JT"; after the startup wiring the transmit owner holds the Recording's own table and my call is HB9BLA; after the profile save my call is HB9BLA.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-01';
        }
        attribute executable : String = "server/src/recording_tests.rs; server/src/contact_http_tests.rs; server/src/auth_tests.rs";
    }
    dependency CL_024_01_verified_by_TC_024_002 from 'CL-024-01' to 'TC-024-002';
    requirement 'CL-024-02' {
        doc /* #24 S2a. An operator-chosen special activity of none, WW Digi, ARRL Digi or NA VHF generates "CQ WW"/"CQ TEST" and the grid exchange (Tx2 grid, Tx3 "R grid"), sequences on the received grid and R+grid, logs on RRR/RR73/73 like any contact and shows dupes through the existing worked-before indication per band and mode; UDP Status carries the activity as WSJT-X's special operation value; station automation does not start in a contest activity (observe only). Details: WstxContact::GridExchangeContest. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/udp.rs; client/contact.js";
    }
    dependency CL_024_02_to_FR_024 from 'CL-024-02' to 'FR-024';
    verification 'TC-024-005' {
        doc /* TC-024-005 — Grid-exchange contests through the contact engine
             CL-024-02
             Setup: the contact engine against the actual #9 transmit owner core on a virtual UTC clock with its recording hardware double (no audio, PTT or radio); hand-authored standard rows; HB9BLA JN47AA; the station fixture over POST /contact/command and its UDP Status.
             Steps: (a) set_activity ww_digi, Enable Tx with no partner, select the caller "HB9BLA S52XYZ JN76", the partner sends "HB9BLA S52XYZ RR73"; (b) set_activity na_vhf, select "CQ TEST K1ABC FN42", Enable Tx, the CQer sends "HB9BLA K1ABC R FN42"; (c) arrl_digi with my call DL/HB9BLA; (e) during a running CQ with an edited Tx6 set ww_digi, then set_report; with an active contact switch none, ww_digi, none; start station automation with ww_digi set; (d) set_activity none, an unknown activity "eu_vhf", and the settings and UDP Status of each activity.
             Expected: (a) Tx6 "CQ WW HB9BLA JN47"; the caller's grid selects Tx3 "S52XYZ HB9BLA R JN47" (rogerReport) with Tx2 "S52XYZ HB9BLA JN47"; after RR73 Tx5 is sent, the contact completes and is logged with grid JN76 and no reports; (b) Tx6 "CQ TEST HB9BLA JN47", "K1ABC HB9BLA JN47" sent (as Tx2 since #24 S2b: Tx1 is disabled in contests), the R FN42 moves to Tx4 "K1ABC HB9BLA RRR", which completes after it is sent and the partner's 73; (c) Tx6 "CQ DL/HB9BLA" and Tx2 "K1ABC <DL/HB9BLA> JN47"; (d) none restores the report exchange (Tx2 "K1ABC HB9BLA -15"), eu_vhf is refused invalid_request field activity, settings.activity reads the choice and UDP Status special operation 0/1/5/8; (e) Tx6 becomes "CQ WW HB9BLA JN47" and a later set_report keeps it, the active contact's Tx2/Tx3 switch between "-NN"/"R-NN" and "JN47"/"R JN47", and automation start is refused not_ready activity.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-02';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_024_02_verified_by_TC_024_005 from 'CL-024-02' to 'TC-024-005';
    verification 'TC-024-006' {
        doc /* TC-024-006 — The Activity choice in the QSO fold-out
             CL-024-02
             Setup: the browser fixture of the operating screen with a hand-written contact snapshot; contact commands are recorded.
             Steps: open the fold-out; read the Activity choice with settings.activity ww_digi; choose ARRL Digi.
             Expected: the choice offers None, NA VHF, WW Digi and ARRL Digi (since #24 S2b also Field Day and RTTY Roundup, TC-024-009, since #24 S4b also Hound, TC-024-013) and shows WW Digi; choosing sends set_activity {activity arrl_digi}; nothing transmits; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_024_02_verified_by_TC_024_006 from 'CL-024-02' to 'TC-024-006';
    requirement 'CL-024-03' {
        doc /* #24 S2b. Field Day (i3=0 n3=3/4) and FT/RTTY Roundup (i3=3) exchanges come from the configured class/section and state/province or DX serial, with 5x9 reports, FT4 "TU;", and pack/unpack identical to ft8code. Contest exchange values go into ADIF CONTEST_ID/STX/SRX/STX_STRING/SRX_STRING/CLASS/ARRL_SECT/STATE as WSJT-X AdifQso writes them. Slice S2b1: the two packer families, exact against ft8code and ft4sim (WstxTransmit::PackMessage), so the transmit owner accepts such a message; the contact engine still refuses them in its slots; unpack and pack share the WSJT-X 3.3.0-beta5 section (86) and RTTY exchange (171) tables, which replace the QEX 2020 tables (WstxOfflineDecode sectionTable/stateProvinceTable). Slice S2b2: the field_day and rtty activities with their configured exchange and the contest serial, the 5x9 mapping, FT4 TU;, the Tx2 start of every contest activity, sequencing on the received exchange, the contact's exchange_sent/exchange_rcvd, the ADIF contest fields of the log (WstxContact::ContestExchange, LogRecord), UDP Status special operation 3/4 and the Activity choice with its Exchange entry; station automation still does not start in a contest activity. Cabrillo is not offered (operator decision S2b-1). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/pack.rs; server/src/decoder/payload.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/logbook.rs; server/src/logbook_http.rs; client/contact.js";
    }
    dependency CL_024_03_to_FR_004 from 'CL-024-03' to 'FR-004';
    dependency CL_024_03_to_FR_024 from 'CL-024-03' to 'FR-024';
    dependency CL_024_03_to_FR_005 from 'CL-024-03' to 'FR-005';
    verification 'TC-024-007' {
        doc /* TC-024-007 — Field Day and RTTY Roundup messages pack exactly as WSJT-X
             CL-024-03
             Setup: fixtures/transmit/ft8code-vectors.json and fixtures/transmit/ft4/ft4sim-vectors.json regenerated by fixtures/transmit/generate.py with WSJT-X 3.3.0-beta5 ft8code.exe (beta4 output identical) and ft4sim.exe, with 20 Field Day and RTTY Roundup messages WSJT-X encodes unaltered (counts 1, 10, 16, 17, 32; classes A-F; R; sections EMA, NB, WI, DX; TU;; serials 0001, 0013, 7999; multipliers MA, WI, ON, PEI, X99) and 19 contest shapes it alters or rejects (a nonstandard, /R or <CALL> call slot; counts 0, 06, 33; class G; Q-prefix call; serials 0000, 8000; reports 519; exchanges 13, DX; TU; without an exchange, a repeated TU;, a missing exchange).
             Steps: pack and encode every fixture message for FT8 and FT4; read the family, i3/n3 and refusal of named messages; unpack the fixed payload-boundary cases of fixtures/decoder/payload-boundary-cases.json (fixtures/decoder/independent-vector-tool/boundary_cases.py) for section 84/85/86/87 and exchange 8065/8066/8171/8172.
             Expected: for every message the oracle encodes unaltered as 0.3, 0.4 or 3., bits, CRC, parity and tones (FT8) and bits, codeword and tones (FT4) equal the oracle and the text equals its rendering; families fieldDay (n3 3 for counts 1-16, 4 for 17-32) and rttyRoundup; every altered or rejected contest shape is refused, a hashed contest call slot (PJ4/K1ABC, K1ABC/R) as notExact, "K1ABC RR73; W9XYZ <KH1/KH7Z> -08" still unsupportedFamily; sections 84 DX, 85 PE and 86 NB and exchanges 8065 DC, 8066 DR and 8171 X99 decode, 87 and 8172 are invalid_payload.
             2 — Isolated automated tests; Windows development PC, no radio, audio, RF or WSJT-X installation at test time. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-03';
        }
        attribute executable : String = "server/tests/transmit_vectors.rs; server/tests/transmit_ft4_vectors.rs; server/tests/decoder_vectors.rs";
    }
    dependency CL_024_03_verified_by_TC_024_007 from 'CL-024-03' to 'TC-024-007';
    verification 'TC-024-008' {
        doc /* TC-024-008 — Field Day and RTTY Roundup through the contact engine and the log
             CL-024-03
             Setup: the contact engine against the actual #9 transmit owner core on a virtual UTC clock with its recording hardware double (no audio, PTT or radio); rows built the way the station builds them (pack, unpack, row reader); HB9BLA JN47AA; the station fixture over POST /contact/command with its log and UDP Status; the logbook record validation.
             Steps: (a) set_activity field_day "1a  ema", Enable Tx with no partner, select the caller "HB9BLA K1ABC 2A WI", the partner answers my Tx3 with "HB9BLA K1ABC RR73"; (b) set_activity rtty "DX", select "CQ RU W9XYZ EN37" with SNR -3, Enable Tx, the CQer sends "TU; HB9BLA W9XYZ R 579 MA", then a second selection; (c) rtty "MA" in FT4: after my Tx3 and the partner's RR73, select the next caller 0.5 s after the RR73 was counted, and in a second run 3 s after it; (d) refusals: field_day without an exchange or with "0A EMA", "33A EMA", "1G EMA", "1A XX" or a non-ASCII character; rtty "DXX" or "8000" (a fixed "0013" is accepted); an exchange with ww_digi; a nonstandard DX call in field_day; a Field Day row while rtty is set; (e) settings and contact snapshot keys, UDP Status special operation; edit_message tx2 "K1ABC HB9BLA 3A WI"; (f) validate_record of the logged records, RST 519 and a contest field with '<'; history record keys.
             Expected: (a) exchange "1A EMA", Tx6 "CQ FD HB9BLA JN47", the caller's exchange selects Tx3 "K1ABC HB9BLA R 1A EMA" with exchange_rcvd "2A WI"; after their RR73 Tx5 is sent, the contact completes and is logged with STX_STRING "1A EMA", CONTEST_ID ARRL-FIELD-DAY, SRX_STRING "2A WI", CLASS 2A, ARRL_SECT WI and no RST; serial 2 afterwards; (b) Tx6 "CQ RU HB9BLA JN47", the selection starts with Tx2 "W9XYZ HB9BLA 559 0001" (Tx1 disabled), the R exchange moves to Tx4, exchange_rcvd "579 MA", the record has RST_SENT 559, RST_RCVD 579, STX 0001, STATE MA; the second selection's Tx2 carries 0002; (c) Tx3 "TU; W9XYZ HB9BLA R 559 MA" in the first run only; (d) invalid_request field exchange, invalid_call, the row is classified other; (e) settings activity/exchange/serial, contact exchange_sent/exchange_rcvd, special operation 3 and 4; the edited Field Day text is accepted unaltered; (f) the records are valid, RST 519 and '<' are refused, history records carry stx..state.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-03';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; server/src/logbook_tests.rs";
    }
    dependency CL_024_03_verified_by_TC_024_008 from 'CL-024-03' to 'TC-024-008';
    verification 'TC-024-009' {
        doc /* TC-024-009 — The Field Day / RTTY Roundup choice and its Exchange entry
             CL-024-03
             Setup: the browser fixture of the operating screen with a hand-written contact snapshot; contact commands are recorded.
             Steps: open the fold-out with settings activity rtty, exchange DX, serial 7; enter "1A EMA" in the Exchange entry and choose Field Day; change the exchange to "2B WI".
             Expected: the choice offers None, NA VHF, WW Digi, ARRL Digi, Field Day and RTTY Roundup; it shows RTTY Roundup, the entry DX and the next serial 0007; choosing sends set_activity {activity field_day, exchange "1A EMA"}, the change sends {field_day, "2B WI"}; nothing transmits; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-03';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_024_03_verified_by_TC_024_009 from 'CL-024-03' to 'TC-024-009';
    requirement 'CL-024-04' {
        doc /* #24 S4. Classic Hound follows HoundTransmissionPolicy: second-period only, Tx1/Tx3 only, random 1000-2998 Hz calling when the Tx offset is below 999 Hz, Tx3 on the Fox frequency after the Fox's report and Fox +-300 Hz on a repeat, completion and logging on the Fox's RR73 in standard or 0.1 form, the reply timeout and the Hound watchdog, and Fox selection limited to rows decoded at :00/:30 (not R+report rows of other Hounds). set_activity hound is FT8 only; UDP Status special operation 7; station automation does not start as a Hound. Slice S4a is the 0.1 hashdx10 rule (CL-024-01, TC-024-010); slice S4b is the Hound operation (WstxContact::HoundOperation). SuperFox (S5) stays excluded. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; client/contact.js";
    }
    dependency CL_024_04_to_FR_024 from 'CL-024-04' to 'FR-024';
    verification 'TC-024-011' {
        doc /* TC-024-011 — Classic Hound through the contact engine
             CL-024-04
             Setup: the contact engine against the actual #9 transmit owner core on a virtual UTC clock with its recording hardware double (no audio, PTT or radio); rows built the way the station builds them (pack, or 0.1 payloads built from their fields, unpack, HashTable fill-in with my call HB9BLA and the DX call, row reader); a deterministic random source; HB9BLA JN47AA; Fox KH7Z.
             Steps: (a) set_activity hound with parity even and Tx 800 Hz; select "CQ KH7Z BL01" at 812 Hz (:00) with SNR -9, Enable Tx; the Fox sends "HB9BLA KH7Z -12" at 812 Hz with SNR -7; my Tx3 is sent; the Fox is silent one period; it sends "HB9BLA KH7Z RR73"; (b) the same with the Fox at 450 Hz, its report inside "W9XYZ RR73; HB9BLA <KH7Z> -12" and its RR73 inside "HB9BLA RR73; K1ABC <KH7Z> -08"; a repeated Fox report after my first Tx3; (c) refusals: Enable Tx without a DX call, a row at :15, "KH7Z W9XYZ R-05" at :00, a 0.1 row, set_parity even, choose_next tx2/tx4/tx5/tx6, choose_next tx1 with Skip Tx1 on; a station mode change to FT4, then set_activity hound; (d) not counted: "HB9BLA K1ABC RR73" (not the DX call), a 0.1 RR73 and a 0.1 report to me with another hashed call, a Fox report while Tune is on (the transmit owner armed with Tune and no request); (e) the reply timeout 165 s after the Fox's report, and again with Enable Tx turned off and on 150 s after it, the Hound watchdog after 300 s of Tx1, and a station Tx watchdog of 1 unanswered call while Tx3 repeats (99 calls for the Hound watchdog case); (f) with Tx 1500 Hz Tx1 keeps its offset.
             Expected: (a) parity odd and Hold Tx on; the selection keeps Tx 800 Hz and gives Tx1 "KH7Z HB9BLA JN47"; Tx1 goes out in the odd period at the random offset within 1000..2998 Hz; the report gives report_rcvd -12, Tx3 "KH7Z HB9BLA R-07" at 812 Hz, the repeat at 512 Hz; the RR73 completes the contact with Enable Tx off (contactCompleted) and logs KH7Z with RST_SENT -07 and RST_RCVD -12; (b) Tx3 at 450 Hz, the repeat at 750 Hz, a repeated report back to 450 Hz, the 0.1 RR73 completes and logs; (c) no_contact for Enable Tx, row_not_standard for the 0.1 row, state_conflict for the others, Tx1 stays next with Skip Tx1, the activity reads none after the change to FT4 and hound is then state_conflict; (d) nothing changes; while Tune only the Fox frequency is recorded; (e) Enable Tx off with cause txWatchdog at each deadline, not before; the slot stays tx3 after the reply timeout, the re-armed station stays armed past 165 s, tx1 after the Hound watchdog (Tx watchdog not expired), and the expired Tx watchdog returns the slot to tx1; (f) 1500 Hz unchanged.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-04';
        }
        attribute executable : String = "server/src/contact_tests.rs";
    }
    dependency CL_024_04_verified_by_TC_024_011 from 'CL-024-04' to 'TC-024-011';
    verification 'TC-024-012' {
        doc /* TC-024-012 — Hound through the station: wire, UDP Status, automation and the 0.1 row reader
             CL-024-04
             Setup: the station fixture over POST /contact/command and GET /contact with its UDP Status; the station's row reader on published 0.1 records; station automation readiness.
             Steps: set_activity hound, then with an exchange; read settings and UDP Status; read a published "HB9BLA RR73; K1ABC <KH7Z> -08" record; start station automation with hound set.
             Expected: settings.activity hound, parity odd, hold_tx true; an exchange is refused invalid_request field exchange; UDP Status special operation 7; the row reader gives the 0.1 fields (RR73 to HB9BLA, report to K1ABC -08, hashed <KH7Z>) and no standard message; automation start not_ready activity.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-04';
        }
        attribute executable : String = "server/src/contact_http_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_024_04_verified_by_TC_024_012 from 'CL-024-04' to 'TC-024-012';
    verification 'TC-024-013' {
        doc /* TC-024-013 — The Hound choice in the QSO fold-out
             CL-024-04
             Setup: the browser fixture of the operating screen with a hand-written contact snapshot; contact commands are recorded.
             Steps: open the fold-out with settings activity hound; choose Hound from None.
             Expected: the choice offers Hound after RTTY Roundup and shows it; choosing sends set_activity {activity hound} without an exchange; nothing transmits; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-04';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_024_04_verified_by_TC_024_013 from 'CL-024-04' to 'TC-024-013';
    verification 'TC-024-014' {
        doc /* TC-024-014 — Hound QSO with a scripted Fox over an audio loopback (no RF)
             CL-024-04
             Setup: the strongest automated equivalent of two station instances over an audio loopback: the Hound is the actual contact engine and #9 transmit owner core on a virtual UTC clock whose hardware double captures the 48 kHz waveform it plays (no PTT, audio device or radio); the scripted Fox synthesizes its FT8 frames (standard texts packed, its 0.1 frames built from their fields) with the station's waveform generator. Each 15 s period is the sum of the frames of that period plus noise at 12 kHz (the Hound's own audio decimated from 48 kHz), decoded by the station's FT8 decoder; the Hound's records pass the station's HashTable (my call, learned calls, the DX call) and row reader, the Fox decodes the Hound's audio with the same decoder. No second process, sound card or virtual cable.
             Steps: Fox "CQ KH7Z BL01" at 800 Hz; the operator selects it and enables Tx with Tx 700 Hz; the Fox answers the decoded Tx1 with "W9XYZ RR73; HB9BLA <KH7Z> -12"; it ignores the first decoded Tx3 for one period and answers the repeat with "HB9BLA RR73; K1ABC <KH7Z> -08".
             Expected: the Fox decodes "KH7Z HB9BLA JN47" in the odd period at a frequency within 1000..2998 Hz (+-3 Hz of the planned random offset); the Hound decodes the 0.1 report with <KH7Z> filled in; the Fox decodes the Hound's "KH7Z HB9BLA R-NN" at 800 Hz (+-3 Hz) and the repeat at 500 Hz; after the 0.1 RR73 the Hound's contact is completed, Enable Tx off and KH7Z logged with RST_RCVD -12; the Hound never transmitted in an even period.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. The level-4 acceptance (two station processes over a physical or virtual audio loopback) and the level-5 on-air QSO with a classic DXpedition are opportunistic and not part of this test. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-04';
        }
        attribute executable : String = "server/src/contact_tests.rs";
    }
    dependency CL_024_04_verified_by_TC_024_014 from 'CL-024-04' to 'TC-024-014';
    verification 'TC-024-003' {
        doc /* TC-024-003 — Compound and nonstandard QSOs through the contact engine
             CL-024-01
             Setup: the contact engine against the actual #9 transmit owner core on a virtual UTC clock with its recording hardware double (no audio, PTT or radio); rows built as the station builds them: packed, unpacked, filled in by a HashTable with my call set, and read by the station's row reader; HB9BLA JN47AA, or DL/HB9BLA.
             Steps: (a) HB9BLA selects "CQ PJ4/K1ABC" (i3=4), Enable Tx; the partner sends "HB9BLA <PJ4/K1ABC> -12", then "<HB9BLA> PJ4/K1ABC RR73"; (b) as DL/HB9BLA, Enable Tx with no partner; the partner sends "<DL/HB9BLA> K1ABC FN42", which is selected, then "<DL/HB9BLA> K1ABC R-07", then "DL/HB9BLA <K1ABC> 73"; (c) enter the DX calls YW18FIFA, PJ4/K1ABC/P, a 12-character call and, as DL/HB9BLA, PA/K1XX, and select "W9XYZ <...> -10" and "PJ4/K9YY <...> RR73" (unresolved 'from') and "<...> W9XYZ RR73" (unresolved 'to', concrete 'from'); (d) edit Tx5 to "tnx 73 gl", and on an own CQ without a partner choose that Tx5 and send it, "TNX FER QSO 73 GL" (17 characters) and "HI, 73" (outside the free-text alphabet); (e) Call 1st on while calling CQ as HB9BLA: "<HB9BLA> PA/K1XX" and "HB9BLA <PJ4/K1ABC> -12" then "HB9BLA W9XYZ -10"; (f) the station's contact step with the manual entry PJ4/K1ABC over POST /contact/command; a table with a 12-bit collision X of HB9BLA in calls12, DX call PJ4/K1ABC, then "<HB9BLA> PJ4/K1ABC" filled in.
             (g) start a station automation run with the profile callsign DL/HB9BLA, then HB9BLA.
             Expected: (a) the message set "<PJ4/K1ABC> HB9BLA JN47", "<PJ4/K1ABC> HB9BLA -NN", "<PJ4/K1ABC> HB9BLA R-NN", "PJ4/K1ABC <HB9BLA> RRR", "PJ4/K1ABC <HB9BLA> 73", "CQ HB9BLA JN47"; the station sends Tx1, Tx3, Tx5, completes and logs PJ4/K1ABC with rcvd -12; (b) Tx6 "CQ DL/HB9BLA", then Tx2 "K1ABC <DL/HB9BLA> -NN", Tx4 "<K1ABC> DL/HB9BLA RRR", completed after the partner's 73, logged K1ABC grid FN42; (c) YW18FIFA and PJ4/K1ABC/P accepted with their nonstandard sets, the 12-character call and PA/K1XX as DL/HB9BLA (two nonstandard calls) invalid_call, the rows from an unresolved hash refused row_not_standard and the one from W9XYZ selected; (d) Tx5 "TNX 73 GL" stored, the long text and a text that would not pack unaltered invalid_message; the own-CQ free text is sent once, the contact completes and nothing is handed to the log; (e) Call 1st skips the nonstandard and the hashed caller and answers W9XYZ; (f) the entry is accepted with Tx1 "<PJ4/K1ABC> HB9BLA JN47" and after the step the station's table holds DX call PJ4/K1ABC; the filled-in 'to' is <HB9BLA>, not <X> (and <X> without the DX call); (g) not_ready call with DL/HB9BLA, then the next readiness check (not_configured strategy) with HB9BLA.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-01';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; server/src/decoder/hashes_test.rs; server/src/strategy_tests.rs";
    }
    dependency CL_024_01_verified_by_TC_024_003 from 'CL-024-01' to 'TC-024-003';
    verification 'TC-024-010' {
        doc /* TC-024-010 — The 0.1 DXpedition DX-call rule (hashdx10)
             CL-024-01
             Setup: the pure payload codec and the hash table of WstxOfflineDecode::HashResolution; 0.1 payloads built from their fields (the packer refuses 0.1).
             Steps: resolve "K1ABC RR73; W9XYZ <KH1/KH7Z> -12" with no DX call, with the DX call KH1/KH7Z set, with KH1/KH7Z set while calls10 holds another call of the same 10-bit hash, with the DX call K1ABC (another hash) and with the 2-character DX call KH on a payload built for the DXpedition call KH, so its hash matches; my call HB9BLA in the 0.1 hash slot.
             Expected: "<...>" without a DX call; "<KH1/KH7Z>" with the DX call set, also over the colliding calls10 entry; the calls10 entry (or "<...>") for another DX call and "<...>" for KH although its hash matches (hashdx10 needs at least 3 characters); the received 0.1 hash slot is not filled with my call (unpack77 applies hashmy10 only to nrx=0); the pure unpack is unchanged.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-01';
        }
        attribute executable : String = "server/src/decoder/hashes_test.rs";
    }
    dependency CL_024_01_verified_by_TC_024_010 from 'CL-024-01' to 'TC-024-010';
    verification 'TC-024-004' {
        doc /* TC-024-004 — Tx5 free text and <MYCALL> rows in the operating screen
             CL-024-01
             Setup: the browser fixture of the operating screen with the actual isolated station, hand-written live records and a hand-written contact snapshot of an own CQ (no partner, only Tx6), the profile call HB9BLA; contact commands are recorded (the station's validation of the text is TC-024-003).
             Steps: publish rows "<HB9BLA> PJ4/K1ABC" (nonstandard, 'to' filled in), "HB9BLA <PJ4/K1ABC> -12" (standard, 'from' filled in), "<...> PJ4/K1ABC" and "<HB9BLA> K1ABC -12" (standard, 'to' filled in); open the message fold-out and type "tnx 73 gl" into Tx5.
             Then (QsoPane Calling me) the same rows during a QSO with PJ4/K1ABC, Rx 1000 Hz and Tx 1300 Hz.
             Expected: the rows to <HB9BLA> or HB9BLA carry the mycall mark (ba-tome) and sort first as value 1 (calling me, #55 BandActivityValue), the unresolved one does not and follows them; the QSO pane Calling me lists one line per station calling my call, oldest first: PJ4/K1ABC by its newest row "HB9BLA <PJ4/K1ABC> -12" and "<HB9BLA> K1ABC -12", not the unresolved one; during the QSO only "<HB9BLA> K1ABC -12" (the partner PJ4/K1ABC's rows are not callers); Tx5 is enabled without a message while the other empty slots and the Tx5 Next choice are not; edit_message {slot tx5, text "tnx 73 gl"} is sent and nothing transmits; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_024_01_verified_by_TC_024_004 from 'CL-024-01' to 'TC-024-004';
    // #60 QSO pane dialogue as a table (operator 2026-11-03, final spec).
    requirement 'CL-060-01' {
        doc /* (#60) The QSO pane shows the QSO dialogue as a table with the header row "UTC | Direction | Exchange | Rep | Rx SNR | Tx SNR", and, since #37 CL-037-04 (2026-11-04), the stations calling me in their own Calling me section, no longer rows of this table. UTC is the period start HH:MM:SS with no ◂/▸ mark after it. Direction is the two calls in the Band Activity order, recipient first and sender second, with "◂" between them pointing to the recipient ("HB9BLA ◂ CT1BFP" received from CT1BFP, "CT1BFP ◂ HB9BLA" sent by me; a hashed call as decoded); a CQ is "CQ <call>" or "CQ DX <call>" without an arrow and its grid is the Exchange. Exchange is the message after the two calls; a message that is neither (free text) is all Exchange. Rep is "×N" when the identical message repeated N > 1 times, else empty (operator 2026-11-03: its own column). On every dialogue row, received and sent alike (operator 2026-11-03), Rx SNR is our measured SNR, signed, of the latest received dialogue entry at or before that row, and Tx SNR is the latest report the partner sent us at or before that row ("R-02" gives "−2", a plain report "-05" gives "−5"); each is empty only while no such value exists yet. The table is the QSO section of the fixed-height pane (#37 CL-037-04): its header row and 12 rows without scrolling (6 at most 48em wide), more scrolling inside at its newest row; it does not grow the page (TC-007-009) and the table fits 360 CSS px, the titles abbreviated and the Direction calls wrapping at their spaces there. Details: WstxOperatingLayout::QsoPane items 7 and 8. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js";
    }
    dependency CL_060_01_to_FR_007 from 'CL-060-01' to 'FR-007';
    dependency CL_060_01_to_FR_019 from 'CL-060-01' to 'FR-019';
    verification 'TC-060-001' {
        doc /* TC-060-001 — QSO pane dialogue table
             CL-060-01
             Setup: actual candidate server and Chromium at 1366x768; routed ContactSnapshot of a running QSO of HB9BLA with CT1BFP whose dialogue holds a sent CQ, the operator's #60 example (received IM59 +8, sent +08, received R-02 +7, sent RR73, received 73 +9, here repeated twice with my call hashed and unknown) and a sent free text; routed live rows of callers of my call: DL1ABC JO31, an unknown hashed call with RR73, a known hashed call <PJ4/K1ABC> with the report -05, and EA8BIA IL18 near my Rx.
             Steps: read the header cells and every #qso-dialogue row's cells and the #37 Calling me rows idle and while the QSO runs, the page scroll, the header row and the newest row position, then at 360x800 the table and page widths; screenshots at 1366x768 and 360x800.
             Expected (independent oracle: the literal operator table of #60 and its 2026-11-03 Rep and every-row SNR requests): header UTC, Direction, Exchange, Rep, Rx SNR, Tx SNR; idle no dialogue row ("No QSO") and the callers in Calling me [DL1ABC, −8, JO31, ""], [<...>, −12, JO31, ""], [<PJ4/K1ABC>, −5, JO31, ""], [EA8BIA, 0, JO31, ""]; dialogue [22:51:00, CQ HB9BLA, JN37, "", "", ""], [22:51:15, HB9BLA ◂ CT1BFP, IM59, "", +8, ""], [22:51:30, CT1BFP ◂ HB9BLA, +08, "", +8, ""], [22:51:45, HB9BLA ◂ CT1BFP, R-02, "", +7, −2], [22:52:00, CT1BFP ◂ HB9BLA, RR73, "", +7, −2], [22:52:15, <...> ◂ CT1BFP, 73, ×2, +9, −2], [22:52:30, "", TNX 73 GL, "", +9, −2]; during the QSO the same callers in Calling me, EA8BIA as "EA8BIA ⚠", and none of them a row of the QSO table; no page scroll at 1366x768, the header row and the newest row visible; at 360 px no horizontal overflow and the table within the pane.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-060-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_060_01_verified_by_TC_060_001 from 'CL-060-01' to 'TC-060-001';

    // #61 An audio gap keeps the display (operator 2026-11-03; decision recorded on issue #61).
    requirement 'CL-061-01' {
        doc /* An unknown-loss source epoch inside the same receive does not clear the operator display, as in WSJT-X. The station keeps its contract (RadioIO: fresh source, job and generation, results from sequence 0); the browser recognises the epoch from GET /receive: the same profile and boot, a running job of the same mode on the same audio.device_id, audio.loss_epochs larger than before, no receive start/stop or band/mode change by this page within 15 s and an unchanged operating revision. Then Band Activity keeps the periods already shown (the latest and, of the other parity, the one before it) below a divider, and they stay until the new receive's first view arrives; that view keeps exactly the kept period one T/R period before it (CL-057-03), the others disappear. Results are then read only under the new identity, from its first sequence; a kept row stays bound to its old identity, so a selection of it is refused by the station as before (row_unavailable). The waterfall keeps its rows: they move in front of the new epoch's frame origin, with one gap row (RGB(96,96,96)) marking the epoch, and the new epoch's rows follow. The gap row marks the loss; the error field stays empty, a receive restart being informational and no entry (#37 CL-037-02, decision recorded on #61 and #37). Anything else that changes the receive identity clears both as before: a Stop/Start, a different input or mode, a band/mode change, a station restart (new boot) or a profile change. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js";
    }
    dependency CL_061_01_to_FR_019 from 'CL-061-01' to 'FR-019';
    verification 'TC-061-001' {
        doc /* TC-061-001 — An audio loss epoch keeps the waterfall and Band Activity
             CL-061-01
             Setup: actual station Router and browser client with a scripted correlated FT8 receive snapshot, results route and live Detailed waterfall frames (explicit presentation fixtures, never modem truth).
             Steps: publish the periods 12:00:00 and 12:00:15 (2 and 1 records) and four waterfall rows; then announce a loss epoch: new source, job and generation, loss_epochs 1, results from sequence 0; send two waterfall rows of the new epoch from sequence 0; publish 12:00:30 under the new identity; then a Stop/Start (new identity, loss_epochs 0) with one row.
             Expected (independent: the scripted periods and rows): after the epoch the 12:00:15 and 12:00:00 rows stay below their dividers and the six waterfall rows are the four old ones, one gap row and the two new ones in that order; the error field shows no entry for the epoch; after 12:00:30 its row is on top and the 12:00:15 rows below one divider, read with the new source, job and generation from cursor 0; after the Stop/Start Band Activity and the waterfall hold only the new receive's content. On the parent client the epoch clears both.
             2 — Isolated automated browser test; Windows PC, no radio (operating-layout suite). */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-061-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_061_01_verified_by_TC_061_001 from 'CL-061-01' to 'TC-061-001';
    verification 'TC-061-002' {
        doc /* TC-061-002 — Audio gaps on HB9BLA keep the display
             CL-061-01
             Setup: the gated candidate installed on HB9BLA, 40 m FT8 receive, one browser on the LAN; no transmission.
             Steps: watch the waterfall and Band Activity until GET /receive audio.loss_epochs has grown at least once.
             Expected: at each growth the waterfall keeps its history with one grey gap row and Band Activity keeps its periods; the error field shows no entry for it; a mode change still clears both.
             3 — Live, read-only on the station; with the operator at acceptance. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-061-01';
        }
    }
    dependency CL_061_01_verified_by_TC_061_002 from 'CL-061-01' to 'TC-061-002';
    // #37 lower panel below the compact QSO pane (operator 2026-11-03).
    requirement 'CL-037-01' {
        doc /* (#37) The right column of the workspace is one vertical stack at every width: the QSO pane, below it the Control panel and below that the error field, each with the left and right edges of the QSO pane card. The Control panel is always visible (no fold-out) and holds DX Call and DX Grid with Generate, Report, Auto Seq, Call 1st, Hold Tx and the Tx period Even / 1st or Odd / 2nd, laid out in rows across its width; each control sends the same single contact request as before and shows only the server-confirmed value. Tx1-Tx6 stay in the QSO pane fold-out; Rx/Tx and dial frequency stay under the waterfall and in the top bar; there is no level meter. The stack fits the fixed 1366x768 screen and 360 CSS px without horizontal overflow. Details: WstxOperatingLayout::LowerPanel, ControlPanel. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_037_01_to_FR_007 from 'CL-037-01' to 'FR-007';
    dependency CL_037_01_to_FR_019 from 'CL-037-01' to 'FR-019';
    requirement 'CL-037-02' {
        doc /* (#37) The error field, a small block below the Control panel that replaces the top-bar exception chips, lists only the problems that still apply and need the operator to act (CAT or radio, audio input missing or its level too low or too high, clock unsynchronized or unknown, a transmit refusal the operator must fix, a failed band/mode change, receive stopped, the station connection lost, a station update or rejected data), each with its cause and "since HH:MM" UTC, on one line where it fits. An entry disappears by itself when its condition clears; there is no acknowledge control and no history; transient events (a retried refusal, busy, stale revision, a receive restart) are no entries. With no entry it shows "No problems". A click opens the entry's detail as the chip did. Details: WstxOperatingLayout::ErrorField, ErrorFieldEntry. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_037_02_to_FR_019 from 'CL-037-02' to 'FR-019';
    requirement 'CL-037-03' {
        doc /* (#37, operator 2026-11-03 "We have two HALT buttons ...") The operating view shows one HALT, the QSO pane's; the top-bar HALT shows whenever the QSO pane HALT is not fully on screen (a page or the Settings drawer covers the workspace, or the stacked pane is scrolled out of view), so a pointer HALT is always on screen; Alt+H halts everywhere; Esc is Abort QSO. The QSO pane's direct buttons are CQ, Tune, HALT, Abort QSO (Esc) and Log QSO: RR73 and 73 are gone (Auto Seq sends them) and each Tx1-Tx6 line of the fold-out has Next and Now, Now choosing it next and turning Enable Tx on (from the next own period), disabled on a completed or cancelled contact. Reply is gone since the #50 double-click fix is installed: a double-click on a Band Activity or Others row, or the row menu Reply, starts the reply. Details: WstxOperatingLayout::OperatingScreen, QsoPane item 5. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_037_03_to_FR_008 from 'CL-037-03' to 'FR-008';
    dependency CL_037_03_to_FR_019 from 'CL-037-03' to 'FR-019';
    dependency CL_037_02_to_FR_021 from 'CL-037-02' to 'FR-021';
    verification 'TC-037-001' {
        doc /* TC-037-001 — Control panel below the QSO pane
             CL-037-01
             Setup: actual candidate server and Chromium at 1366x768, 1920x1080 and 360x800; routed ContactSnapshot of a running QSO.
             Steps: without opening the fold-out read the visibility of #dx-call, #dx-grid, #dx-generate, #contact-report, #contact-auto, #contact-call-first, #contact-hold and #contact-parity; read the bounding boxes of the QSO pane, #qso-control and #error-field; change each control and record the contact requests; check the fold-out holds the Tx1-Tx6 rows and no longer the moved controls, and the Rx/Tx strip holds no Hold Tx.
             Expected (oracle: the operator's #37 comments of 2026-11-03): every control visible with the fold-out closed and inside #qso-control; the three blocks stacked top to bottom (pane bottom <= control top, control bottom <= error-field top) with equal left and right edges (within 1 px) at all three sizes; the controls span at least 80% of the panel width at 1366x768 (rows, not a narrow column); Report 7 sends set_report {report 7}, Auto Seq off set_auto_seq false, Call 1st off set_call_first false, Hold Tx on set_hold_tx true, Odd / 2nd set_parity odd, DX Call W1AW with Enter sends enter_dx; no page scroll at 1366x768 and no horizontal overflow at 360 px; screenshots at 1366x768 and 360x800.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-037-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_037_01_verified_by_TC_037_001 from 'CL-037-01' to 'TC-037-001';
    verification 'TC-037-002' {
        doc /* TC-037-002 — Error field lists current problems only
             CL-037-02
             Setup: actual candidate server and Chromium at 1366x768 with a CAT profile; routed CAT status, contact snapshot transmit refusal and connection state.
             Long text (live 2026-11-06): with a CAT status text wrapping to several lines, and one far longer than the block, the block and its last entry can be scrolled fully into view on the 1366x768 screen, with no page scroll and the Control panel top unchanged; one wheel notch moves the block by at most its visible height; at 360x800 no horizontal overflow.
             Steps: healthy station; inject a CAT status not ready; then a transmit refusal radio_lost and a stale_revision-like transient refusal busy; then clear the CAT condition; then clear the refusal; then make the station link stale; read #error-field each time and the top bar.
             Expected (oracle: the operator's #37 correction "NO history"): healthy, the field shows "No problems" and no entry; the CAT entry names the CAT status and "since HH:MM" with the current UTC hour and minute; radio_lost adds "Tx refused · radio lost", busy adds nothing; after the CAT condition clears its entry is gone without any operator action and the refusal entry stays; after the refusal clears the field shows "No problems" again; with the link stale the field shows "Station connection lost · reconnecting"; the field has no acknowledge or dismiss control; the top bar holds no exception chips.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-037-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_037_02_verified_by_TC_037_002 from 'CL-037-02' to 'TC-037-002';
    // #65 Free Tx slots (operator 2026-11-08, three grill-me rounds).
    requirement 'CL-065-01' {
        doc /* (#65, replaced by #82, operator 2026-11-09: "open slots are shown all the time as a part of the waterfall"; "we want to signal the other station a free frequency on our side when he will be transmitting"; "we just want to mark open slots, nothing else on screen. auto mode could use a quality ranking for its decision which of them to select") Open Tx slots: the station builds, with or without an automation run, a QSO or Auto, the open slots of my Rx parity, the periods the other station transmits in: in a QSO (Enable Tx on, my own CQ included, or a contact in progress; by a run or by hand) the contact's Rx parity; otherwise, while only listening, the parity of the period in progress, the Rx parity for transmitting in the next period, so it alternates every period. Counted periods, floor and value are #66's (WstxStrategy::FreeTxSlot: the last 4 periods of that parity before the period in progress, the largest rise above the WSJT-X passband floor clamped at 0 in whole dB), of the station's live job and operating mode, from the last station band change on. A Tx frequency of the 10 Hz candidate grid inside the Tx range (FT8 300..2650, FT4 300..2610) is open when its value is 0 and its signal (FT8 50 Hz, FT4 90 Hz wide) overlaps no station decoded in a counted period; no other filter, no fallback, no ranking, no limit. The open signals join into open ranges [lo_hz, hi_hz) (overlapping ones join, touching ones stay separate). It is built at each period start, again when the decodes of a counted period are published (operator 2026-11-09, "Rebuild on decodes": the build at a period start counts the period just ended before its decodes exist), and at once when a QSO starts or ends or the live job, mode or band changes. The value null (no live receive) or {at_utc_ms, mode, rx_parity, qso, periods (the counted number), open [[lo_hz, hi_hz], ...]} is the top-level free_tx_slots of GET /automation and the MCP automation view, and is pushed at each build as free_tx_slots.state to every Detailed and Thin peer (at most 1024 bytes; once as null when it becomes null; once to a peer that subscribes while a value exists; never to Off), also while automation is never used, within the Thin link envelope. Auto's choice and tx_slot are unchanged (its own ranking, not shown); #65's five best of each run decision, its run_id and "no list without a run" go. Details: WstxStrategy::FreeTxSlots (D18), WstxMcp::AutomationWire, WstxStationProtocol::PushedStationState. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/freeslot.rs; server/src/automation.rs; server/src/main.rs; server/src/contact_http.rs";
    }
    dependency CL_065_01_to_FR_020 from 'CL-065-01' to 'FR-020';
    dependency CL_065_01_to_FR_007 from 'CL-065-01' to 'FR-007';
    requirement 'CL-065-02' {
        doc /* (#65, #82 operator 2026-11-09: "open slots are shown all the time as a part of the waterfall", "we just want to mark open slots, nothing else on screen") Open slot marks: always part of the waterfall, with no setting (#82 removes the Settings > Expert checkbox "Show free Tx slots") and with or without a run, a QSO or Auto: each open range [lo_hz, hi_hz) of the latest held free_tx_slots (CL-065-01) is a bar in the frequency ruler directly above the waterfall over lo to hi on the waterfall's one frequency mapping (CL-050-07), taking no pointer input. The held value is replaced by each free_tx_slots.state in socket order, by a GET /automation reply only with a later at_utc_ms (never by its null or an older value), and dropped at a new boot (#74) and when the page's display is switched to Off; the marks are redrawn on every new value and go when it is null or open is []. No request or poll beyond the snapshot and the event. Look (#76, operator 2026-11-08): each bar 8 CSS px high, shortened by 2 CSS px at each end (from x(lo) + 2 to x(hi) - 2), so touching ranges show a 4 px gap (where a range is narrower than both insets, on a phone, the bar may vanish); no text on the marks (no rank, no rise, no number); one pale green in the base theme, remapped by Day and Night like the page, whose drawn pixel differs in each theme from the drawn Rx line, Tx line and ruler background by at least 40 in the sum of the R, G and B differences. Details: WstxOperatingLayout::FreeTxSlotMarks. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "client/contact.js; client/recording.js; client/recording.css; client/app.js";
    }
    dependency CL_065_02_to_FR_019 from 'CL-065-02' to 'FR-019';
    verification 'TC-065-001' {
        doc /* TC-065-001 — The five best non-overlapping candidates
             CL-065-01
             Setup: the list function with hand-authored power tables (dB per candidate, written in the test), FT8 and FT4.
             Steps: seven separate quiet places; three candidates only; no power; rises 0.4 against 0.0 and 0.6 against 0.0; equal rises either side of the current Tx; FT8 a candidate 40 Hz and one 50 Hz from a listed one, FT4 80 Hz and 90 Hz; a candidate within 50 Hz of the called station; one within 50 Hz of my Rx with Hold Tx on and off; his frequencies of my Tx parity near some candidates, and everywhere; a rise of -1.4; listening with one parity higher.
             Expected (hand computation recorded in the test): 5 of seven in rank order; 3; empty; 0.4 ties and the current Tx is first, 0.6 does not; the nearer first, at equal distance the lower; 40 Hz skipped and 50 Hz listed, 80 Hz skipped and 90 Hz listed; the called station's neighbour never listed; my Rx's neighbour not listed with Hold Tx on, listed with it off; candidates near his frequencies excluded, his frequencies everywhere leave all; -1.4 listed as -1; level_db the larger parity's; the first listed equals quietest_clear's chosen hz for every table. Red on the parent: no list.
             #66: the tables give the largest rise above the passband floor, and the compared value is that rise clamped at 0: the rise of -1.4 is listed with rise_db 0 (not -1), tying with a rise of 0.0 by the tie rule, and its level_db and floor_db stay as measured; "listening with one parity higher" becomes my Tx parity higher, which changes nothing (only my Rx parity is judged), and level_db and floor_db are those of the busiest Rx period; a candidate overlapping a decoded station is not listed while a free one exists (TC-066-002).
             #82: the five-best list is gone (WstxStrategy D18); this case is replaced by TC-082-001 (the open ranges), and its test is rewritten to it. The choice parts ("the first listed equals quietest_clear's chosen hz") go with the list; the choice stays covered by TC-039-050 and TC-066-002.
             2 — Isolated automated tests; Windows development PC, no radio (wstx-rust). */
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
             2 — Isolated automated tests; Windows development PC, no radio (wstx-rust). */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_065_01_verified_by_TC_065_002 from 'CL-065-01' to 'TC-065-002';
    verification 'TC-065-003' {
        doc /* TC-065-003 — Free Tx slots marks above the waterfall
             CL-065-02
             Setup: actual candidate server and Chromium at 1366x768, 1920x1080 and 360x800, also devicePixelRatio 2; routed automation snapshot with a run, announced by a pushed automation.state (the browser reads GET /automation only after it, #74), and pushed free_tx_slots.state events, FT8 and FT4.
             Steps: open Settings > Expert; with a value pushed and the checkbox off read #frequency-ruler; turn it on; push a value whose slots include FT8 2110 and 2160 Hz (exactly one width apart); in the Dark, Day and Night themes take a screenshot and read the pixel at each bar's centre, at the Rx line's and the Tx line's centre and at the ruler background beside the bars; push a newer value; an FT4 value with slots 90 Hz apart; one of another run_id; one with empty slots; route run null; reload and open a second browser context; click and double-click the waterfall at a mark's frequency and drag the Tx marker across a mark.
             Expected (oracle: CL-050-07 mapping, the operator's #65 and #76 answers): the checkbox "Show free Tx slots" off by default; no mark while off; on at 1366x768 and 1920x1080 (also devicePixelRatio 2): one bar per listed slot, each 8 CSS px high (within 0.5 px) at the bottom of the ruler, with left and right edges within 1 px of x(hz) + 2 and x(hz + width) - 2 (width 50 Hz FT8, 90 Hz FT4); the 2110 and 2160 Hz bars (and the FT4 pair) two bars with a gap of 4 px (within 1 px) between them; no text in the ruler's marks layer (no rank, no rise); in each theme the drawn bar pixel differs from the drawn Rx line, Tx line and ruler background pixel by at least 40 in the sum of the R, G and B differences; the waterfall top and height unchanged; redrawn on the newer value; none for another run_id, for empty slots and with run null; on after reload, off in the other context; the same set_frequency requests as without marks, Rx and Tx lines unchanged; no request after an event and no timer request; at 360x800 no bar is required, no horizontal overflow and no page error. Red on the parent: 4 px bars over the full slot (no gap between 2110 and 2160 Hz), labels in the ruler.
             #82: replaced by TC-082-004. No checkbox (always shown), no run and no run_id match, bars over open ranges [lo, hi) instead of listed slots; its test is rewritten to TC-082-004.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_065_02_verified_by_TC_065_003 from 'CL-065-02' to 'TC-065-003';
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
    dependency CL_065_02_verified_by_TC_065_004 from 'CL-065-02' to 'TC-065-004';
    verification 'TC-066-001' {
        doc /* TC-066-001 — The 10:28:58 capture: free Tx slots off the busy 800-1330 Hz region
             CL-039-09, CL-065-01
             Setup: the slot decision and list functions with hand-authored per-period bin levels modelled on the HB9BLA capture of 2026-11-08 10:28:58 UTC (10 m FT8, D:/wstx-tmp/live-20261108c/slots-102901.json and its waterfall): a run's CQ decision (listening), my Tx parity odd and Rx parity even, Hold Tx on, Tx 1930, Rx 906. Counted even periods 10:27:30, 10:28:00, 10:28:30 and odd periods 10:28:15, 10:28:45, each a flat floor of 30 dB (32 dB in the latest period of each parity), every station the capture decoded in that period as its decode (audio frequency, period) and as a band [hz, hz + 50) 12 dB above 30 dB (live, occupied slots read 4-12 dB above clear ones, #66 comment 6720568259); RK3AW's band at 1198.5 Hz also in both odd periods, undecoded there (the capture's 1180 Hz slot: level 50 against usual 48, busy in the odd periods too).
             Steps: the decision with Hold Tx on (no choice, the list only); the same with Hold Tx off (the choice).
             Expected (hand computation recorded in the test): the even decodes leave the candidates 300..400, 720..800, 1010..1050, 1250..1310, 1450..1680, 1890..1960, 2120..2130 and 2240..2650 (810..1000 within 50 Hz of Rx 906 with Hold Tx on); each reads 0 (floor 30.65 or 32.65, rise -0.65 clamped at 0, #66 "At or under floor = free"); the list is 1930, 2120, 1680, 1630, 2240 (the current Tx kept as free, then the free slots by distance), each {rise_db 0, level_db 32, floor_db 33} (level and floor of the latest, busiest period as measured); no listed slot overlaps a station decoded in my even periods and none lies in 800-1330 Hz; the odd stations (DL5XU at 1976, A61DD at 765) do not count; periods {even {now 3}, odd {now null}}; Hold Tx off: the CQ's slot is 1930, tx_slot power_db 0, the first listed. Red on the parent: its list holds slots on RK3AW (rise 0 there against 1 on the free slots, the live failure's ranks 2 and 3).
             #82: the list parts become the open ranges of the same tables (TC-082-001's rule: value 0 and no even decode overlapped, no clearance of Rx or the called station), hand-computed in the test; no open range overlaps a station decoded in my even periods, and the odd stations close nothing. The choice parts (Hold Tx off: the CQ's slot 1930, tx_slot power_db 0) stand.
             2 — Isolated automated tests; Windows development PC, no radio (wstx-rust). */
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
             2 — Isolated automated tests; Windows development PC, no radio (wstx-rust). */
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
             Steps: Auto on with a strategy with CQ when no target; let it call CQ, answer or call through at least one QSO and one slot check; switch Hold Tx off for one call; at each decision record free_tx_slots and the decodes of my last 4 Rx periods on the issue; HALT, Auto off.
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
             2 — Isolated automated tests; Windows development PC, no radio (wstx-rust). */
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
             2 — Isolated automated tests; Windows development PC, no radio (wstx-rust). */
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
             2 — Isolated automated tests; Windows development PC, no radio (wstx-rust). */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-01';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_065_01_verified_by_TC_082_003 from 'CL-065-01' to 'TC-082-003';
    verification 'TC-082-004' {
        doc /* TC-082-004 — Open slot marks always on the waterfall
             CL-065-02
             Setup: actual candidate server and Chromium at 1366x768, 1920x1080 and 360x800, also devicePixelRatio 2; pushed free_tx_slots.state events, FT8 and FT4; automation never used unless a step names a GET /automation reply (announced by automation.state, #74); the Dark, Day and Night themes.
             Steps: open Settings > Expert; push FT8 open [[300, 1000], [1050, 2700]]; push [[2110, 2160], [2160, 2210]]; FT4 [[300, 390], [390, 480]]; a newer value; open []; null; while a value is held a GET /automation reply with an older value, one with null, then one with a later value; an event that arrives before the contact client's script has loaded; a new boot; in each theme read the pixel at a bar's centre, at the Rx and Tx lines' centre and at the ruler background; click and double-click the waterfall at a mark and drag the Tx marker across it; an Off page.
             Expected (oracle: CL-050-07 mapping, the operator's #76 and #82 answers): no "Show free Tx slots" checkbox; one bar per range, 8 CSS px high (within 0.5 px) at the bottom of the ruler, edges within 1 px of x(lo) + 2 and x(hi) - 2; the touching ranges two bars with a 4 px gap (within 1 px), also FT4; no text in the marks layer; in each theme the bar pixel differs from the drawn Rx line, Tx line and ruler background by at least 40 in the sum of the R, G and B differences; the waterfall top and height unchanged; redrawn on the newer value; none for [] and for null; the older and the null GET reply leave the marks unchanged, the later one replaces them; the early event's marks drawn once the client has loaded, with no request; from the new boot on no mark of the old boot until the new boot's first event; the same set_frequency requests as without marks, Rx and Tx lines unchanged; no request after an event and no timer request; at 360x800 no horizontal overflow and no page error; the Off page no marks and no event. Red on the parent: no mark without a run, and none with the checkbox off by default.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-065-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_065_02_verified_by_TC_082_004 from 'CL-065-02' to 'TC-082-004';
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
    dependency CL_065_02_verified_by_TC_082_005 from 'CL-065-02' to 'TC-082-005';
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
    dependency CL_065_02_verified_by_TC_082_006 from 'CL-065-02' to 'TC-082-006';
    // #37 fixed-height QSO pane with a QSO and a Calling me section (operator 2026-11-04).
    requirement 'CL-037-04' {
        doc /* (#37, operator 2026-11-04: "The QSO panel should contain all needed information for the operator. And it should be fixed in size that the things below it do not move all the time up and down. We probably have a section for the QSO and a section for who is calling"; "you can make this section big enough to accommodate also longer QSOs. We have enough space") The QSO pane has a fixed height that depends on the screen only, never on its content, so the Control panel and the error field below it do not move when a QSO starts or ends, dialogue rows or callers are added or a message line appears. It has two sections of fixed height that scroll inside: QSO, below the header (partner call, grid, country, distance, reports) and the message lines (state, NEXT, last partner message), holds the #60 dialogue table with its header row and 12 rows without scrolling on a laptop screen (6 at most 48em wide), more rows scrolling inside with the newest row always visible, and the placeholder "No QSO" while no QSO runs; Calling me lists every station calling my call except the partner, one line per station with call, SNR, grid and country, at least 5 rows high, double-click (or Enter) to work it, with the #10 worked-before marks, and the placeholder "Nobody is calling". At 360 CSS px both sections stack with fixed heights, and Band Activity, with a fixed height, shows compact rows (numbers and distance, then message and country, wrapping only between whole fields, usually two lines) instead of labelled cards, at least six on screen at 360x800. The Calling me hover follows the compact #50 BandActivityHover rule (one line, only the enabled colour reasons, the strongest per kind). No new request or poll: the sections show the contact snapshot and the result rows the page already reads. Details: WstxOperatingLayout::QsoPane items 3, 7 and 8, BandActivityView. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_037_04_to_FR_007 from 'CL-037-04' to 'FR-007';
    dependency CL_037_04_to_FR_019 from 'CL-037-04' to 'FR-019';
    verification 'TC-037-003' {
        doc /* TC-037-003 — Fixed-height QSO pane with QSO and Calling me sections
             CL-037-04
             Setup: actual candidate server and Chromium at 1366x768, then 1920x1080 and 360x800; routed live rows of one period with ten CQs, later joined by three callers of my call (a later publication announced by receive.state, #10) (DL1ABC JO31 Fed. Rep. of Germany at 600 Hz, IW9FRA JM68 Sicily, EA8BIA IL18 Canary Islands at 1520 Hz, near my Rx 1500 Hz); routed ContactSnapshots idle, of a running QSO with IW9FRA with 1, 12 and 15 dialogue entries, armed and disarmed, and completed.
             Steps: at each step read the top and height of the QSO pane, the QSO section, the Calling me section and the top of the Control panel (in the coordinates of the scrolled workspace), the section placeholders, the Calling me cells and whether the dialogue rows lie inside the QSO section; at 360x800 scroll the workspace to the first Band Activity row and count the rows fully on screen and their height; screenshots at each size.
             Expected (independent oracle: the operator's 2026-11-04 #37 design and the live finding 2026-11-04): idle "No QSO" and "Nobody is calling" shown; with the callers the Calling me header Calling me, SNR, Grid, Country and rows [DL1ABC, −8, JO31, Fed. Rep. of Germany], [IW9FRA, +17, JM68, Sicily], [EA8BIA, 0, IL18, Canary Islands]; during the QSO no "No QSO", the partner gone from Calling me and EA8BIA marked ⚠; 12 dialogue rows all inside the section without scrolling and the section on screen at 1366x768 and 1920x1080; 6 dialogue rows all inside the section without scrolling at 360x800 (live 2026-11-06, its header one row high); with 15 rows the section scrolls and the newest row is inside it; after completion "No QSO" again; at each size the Control panel top, the pane height and both section heights are the same at every step; Calling me holds its header and 5 rows; no page scroll at 1366x768 with the Control panel, the error field and the pane HALT on screen; at 360x800 no horizontal overflow, at least six Band Activity rows on screen, each at most 48 px high, and the newest dialogue row visible.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-037-04';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_037_04_verified_by_TC_037_003 from 'CL-037-04' to 'TC-037-003';
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
    // Found in the #61 gate (TC-050-004, CQ right after a completed contact refused stale_revision).
    requirement 'CL-061-02' {
        doc /* The QSO pane CQ button is an explicit operator choice like the double-click (CL-050-04): a stale_revision refusal of its enable_tx (the contact revision moves with every transmit step, also when the last period of a just completed contact ends) is retried at most twice with the reloaded snapshot; a third refusal stays shown. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js";
    }
    dependency CL_061_02_to_FR_007 from 'CL-061-02' to 'FR-007';
    verification 'TC-061-003' {
        doc /* TC-061-003 — CQ retries a stale_revision refusal
             CL-061-02
             Setup: actual station Router and browser client with scripted contact snapshots, contact command replies and contact.state events pushed through the station-message handler of the client, each carrying the moved revision, a snapshot_sequence one above the shown snapshot and its transmit, settings, contact, log and watchdog in changed (explicit presentation fixtures); Playwright page clock, paused once CQ is enabled.
             Steps: click CQ while the station refuses one command with stale_revision, moves its revision and sends no contact.state; once the refusal is shown, move the page clock by 2499 ms, then by 1 ms. Click CQ while it refuses three, sending a contact.state with the moved revision after each; after the third refusal, wait for revision 7 in the snapshot, then click Tune.
             Expected (independent: the scripted revisions, the contract wait of 2.5 s and limit of two retries): after 2499 ms no GET /contact and no second command; after 2500 ms one GET /contact and CQ sends enable_tx with revision 4 after revision 3 (accepted); then 4, 5, 6 and the refusal is shown; the next command is tune, with no fourth enable_tx. Every wait is on an event, with a 10 s hang guard (#83). On the parent client CQ sends once (#61).
             2 — Isolated automated browser test; Windows PC, no radio (operating-layout suite). */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-061-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_061_02_verified_by_TC_061_003 from 'CL-061-02' to 'TC-061-003';
    // #61 operator report 2026-11-03: after each own transmission Band Activity looked as if reception had stopped.
    // Operator decision 2026-11-04 (#61): "distinguish exactly between TX and RX ... do not listen to audio when you do TX";
    // the station decides the Tx period (CL-061-04) and the browser renders its marker (CL-061-03).
    requirement 'CL-061-03' {
        doc /* Band Activity renders the station's Tx period marker (CL-061-04); the browser no longer infers it from station.tick or the contact snapshot. While the latest view is a Tx period (latest_decode.transmitted true) the header reads "Tx · <MODE> period <UTC> UTC · this station transmitted, no decode", the top row is one marker row (data-period "tx", text "Tx <UTC> · this station transmitted · no decode") and the receive period it replaced follows below its divider "<MODE> period <UTC> UTC" when it has the other parity (CL-057-03); there is no empty-period block ("No stations decoded") for it; the count is the number of rows shown below the marker. When the next period arrives the Tx marker disappears and the receive period kept below it stays below the new one with its divider (it replaces the Tx period, not the receive period before it). A receive period that decodes nothing keeps its note "No stations decoded" as before. The station's receive results and records are unchanged. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/recording.css";
    }
    dependency CL_061_03_to_FR_010 from 'CL-061-03' to 'FR-010';
    dependency CL_061_03_to_FR_019 from 'CL-061-03' to 'FR-019';
    verification 'TC-061-004' {
        doc /* TC-061-004 — A Tx period shows the station's Tx marker, no empty block
             CL-061-03
             Setup: actual station Router and browser client with a scripted correlated FT8 receive snapshot and results route (explicit presentation fixtures, never modem truth).
             Steps: publish 12:00:00 UTC with 3 records; publish 12:00:15 as a Tx period (latest_decode transmitted true, no records); publish 12:00:30 with 2 records; publish 12:00:45 (a receive period) with no records. No station.tick says transmitting.
             Expected (independent: the scripted periods and the marker): after 12:00:15 Band Activity shows the marker row "Tx 12:00:15 · this station transmitted · no decode" on top, then the divider "FT8 period 12:00:00 UTC" and the three 12:00:00 rows; no "No stations decoded" and no "No verified stations" text; header "Tx · FT8 period 12:00:15 UTC · this station transmitted, no decode"; count "3 messages"; after 12:00:30 its 2 rows on top and the 12:00:00 rows below the divider "FT8 period 12:00:00 UTC", no marker; after 12:00:45 the note "No stations decoded" with the 12:00:30 rows below their divider; no page error. On the parent client the 12:00:15 view is refused (unknown key) and no marker shows.
             2 — Isolated automated browser test; Windows PC, no radio (operating-layout suite). Live acceptance: TC-061-007. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-061-03';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_061_03_verified_by_TC_061_004 from 'CL-061-03' to 'TC-061-004';
    requirement 'CL-061-04' {
        doc /* The station treats every T/R period in which it is on the air as a Tx period and decides it itself (WstxStationProtocol client-server rule, #10: the server decides and pushes, the browser renders). On the air means the transmit owner's PTT is keyed or not confirmed released, a transmission's audio runs, or Tune is on; the station records the period start (its UTC on the transmit owner's clock, the clock the transmitter keys on) of every such observation and the start of the last transmitted period (transmit.last_period_utc), the latest 16. The receive path reads this without waiting for the transmit owner. For a Tx period: (1) no decode attempt: the live worker skips its analysis windows (prompt and late), no record and no UDP decode is published for it and the decoder is not marked busy; the job's latest_decode for that period carries "transmitted": true with an empty range (first_sequence = next_sequence = the frozen publication end) and complete false (RadioIO LatestDecodePeriod); (2) no Rx level measurement while on the air and for the rest of that Tx period: station.tick rx_level_db is null then, and the measurement restarts with the next receive period, so a level and the "Audio level low/overdriven" error-field entries refer to receive periods only (the browser shows "Tx · not measured" while station.tick says transmitting); (3) the waterfall rows of a Tx period carry "tx": true (spectrum.frame and spectrum.detail.frame, the key present only then) and the browser paints them as Tx rows (RGB(90,20,30)) without a spectrum trace, never as received silence; (4) the period bar (red), the QSO pane line "TX now", the Band Activity marker (CL-061-03) and the meter state Tx while the error field shows no level entry. Audio capture keeps running throughout: no device stop or start and no loss epoch; only the use of the samples is suspended. HALT, the Tx watchdog and PTT release are unchanged. Without a correlated receive clock no period can be named: decoding continues and only the level stops while on the air. Deliberate differences from WSJT-X 3.3 (half duplex: MainWindow::transmitDisplay calls monitor(false), which suspends the audio input stream and cancels a pending FT8 decode, and stopTx resumes it with monitor(true); the signal meter is set to 0 and the waterfall receives no rows while transmitting): this station keeps capturing (one continuous source, no restart), marks the Tx rows instead of leaving them out, publishes the Tx period as a marked view, reports the level as unavailable (null) rather than 0 and suspends it to the end of the Tx period rather than to the end of the transmission. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/recording.rs; server/src/transmit/service.rs; client/recording.js; client/contact.js";
    }
    dependency CL_061_04_to_FR_007 from 'CL-061-04' to 'FR-007';
    dependency CL_061_04_to_FR_010 from 'CL-061-04' to 'FR-010';
    dependency CL_061_04_to_FR_019 from 'CL-061-04' to 'FR-019';
    verification 'TC-061-005' {
        doc /* TC-061-005 — The station does not decode or measure in its Tx period
             CL-061-04
             Setup: actual Recording manager and live worker with a correlated FT8 live ring anchored at 2026-10-27T12:00:00 UTC; the Tx periods noted directly on the station's Tx period record (an explicit fixture of the transmit owner's observation).
             Steps: note 12:00:15 as a Tx period; analyze the window of 12:00:15 (prompt) and its late window; analyze the window of 12:00:30; push live blocks inside 12:00:15 with full-scale samples while not on the air, then blocks in 12:00:30; push a block while on the air; then attach the actual transmit owner with a frozen-clock hardware double (no radio) at 12:00:23 in FT8 and in FT4, arm it and turn Tune on, push a block of a receive period, turn Tune off.
             Expected (independent: the noted period and the scripted windows): the 12:00:15 view has transmitted true, complete false, first_sequence = next_sequence and the late window keeps that view; the decoder busy count did not move for it; the 12:00:30 view has no transmitted key and complete true; no level is measured (rx_level null) during the 12:00:15 blocks; the 12:00:30 blocks give a level again after 1 s; while on the air rx_level is null and the waterfall rows carry tx true, receive rows carry no tx key; with the transmit owner on the air rx_level is null at once and the block adds no level, and after the release the recorded Tx period is exactly 12:00:15 (FT8) or 12:00:22.5 (FT4). On the parent code the 12:00:15 window is decoded and published complete.
             2 — Isolated Rust tests; Windows PC, no radio (wstx-rust suite). */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-061-04';
        }
        attribute executable : String = "server/src/recording_tx_tests.rs";
    }
    dependency CL_061_04_verified_by_TC_061_005 from 'CL-061-04' to 'TC-061-005';
    verification 'TC-061-006' {
        doc /* TC-061-006 — The browser renders Tx rows and shows level warnings only for receive periods
             CL-061-04
             Setup: actual station Router and browser client with a scripted correlated live receive, Detailed waterfall frames and station.tick events (explicit presentation fixtures).
             Steps: deliver a station.tick with rx_level_db 5 (low) while receiving; then a tick with transmitting true and rx_level_db null; then a tick after the transmission with rx_level_db null; then a tick of the next receive period with rx_level_db 5; send two Detailed rows with tx true and one without.
             Expected (independent: the scripted ticks and rows): the error field shows "Audio level low" for the first tick; while transmitting the meter reads "Tx · not measured" and neither "Audio level low" nor "Audio overdriven" is listed, nor after the transmission while rx_level_db is null; the receive tick shows "Audio level low" again; the waterfall paints the tx rows RGB(90,20,30) and the receive row with its levels. On the parent client the meter reads "Unavailable" while transmitting and the tx frames are refused (unknown key); on the parent station the level is still measured in the Tx period (TC-061-005).
             2 — Isolated automated browser test; Windows PC, no radio (operating-layout suite). */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-061-04';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_061_04_verified_by_TC_061_006 from 'CL-061-04' to 'TC-061-006';
    verification 'TC-061-007' {
        doc /* TC-061-007 — Tx periods on HB9BLA
             CL-061-04
             Setup: the gated candidate installed on HB9BLA, 40 m FT8 and FT4, CQ, RF power set low by the test before the first Tx (CI-V 14 0A, value 0003, with the station stopped and idle, because it holds COM3; read back; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported), the operator's consent, one browser on the LAN.
             Steps: call CQ for at least three own periods; watch Band Activity, the waterfall, the meter and the error field; read GET /receive during a Tx period.
             Expected: each Tx period shows the Tx marker and no empty block, its waterfall rows are Tx rows, no "Audio level low" entry appears in or right after a Tx period, the receive periods decode and show their level; audio.loss_epochs does not grow from the transmissions; HALT stops the transmission as before.
             5 — Live with RF on the station, operator consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-061-04';
        }
    }
    dependency CL_061_04_verified_by_TC_061_007 from 'CL-061-04' to 'TC-061-007';
    requirement 'CL-061-05' {
        doc /* A Tx period takes only a thin marker band in the waterfall (operator 2026-11-04 and 2026-11-06, #61: "the Tx area in the waterfall can be much shorter", "we still have a white band when the TX runs"). The browser collapses each run of consecutive rows the station marked tx (CL-061-04; it adds no polling and no new station data, #10 client-server rule) to one band of 4 CSS pixels in RGB(90,20,30), whatever the run's source time: while the station transmits the picture holds still once the band stands; receive rows keep the Speed scale. The time ruler stays exact: T at the top, no label inside a band, and a source time t beyond a band at floor((T-t)*p*H/C) less the collapsed source time of the bands above it, plus their height; the readout's projected source range over a band names the whole Tx run. A row the station did not deliver between two Tx rows at most 7.5 s apart is a Tx row of that band, never a grey gap stripe; a longer hole stays a gap. In the Day theme the signal canvases keep their colours: the waterfall's background stays dark and the Tx band dark red, never pale (the canvas counter-filter was overridden by #signal canvas{filter:none}, so the page's inversion turned both nearly white). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/recording.css";
    }
    dependency CL_061_05_to_FR_019 from 'CL-061-05' to 'FR-019';
    verification 'TC-061-008' {
        doc /* TC-061-008 — A Tx period is a thin band, the time axis stays exact, nothing pale
             CL-061-05
             Setup: actual station Router and browser client at 1366x1200 (device scale 1; a plot holding 20 s at 10 px/s, which the #37 default split at 1366x768 does not) with a scripted correlated live receive and Detailed frames, Speed 1 (10 CSS px/s) (explicit presentation fixtures).
             Steps: deliver 12 s of receive rows; one Tx row; the rest of a 15 s Tx period with two missing rows; 12 s of receive rows; read the canvas column and the time ruler; hover the band; set the Day theme and read the rendered page pixels; deliver Tx rows after a 7.4 s hole and after a 7.6 s hole.
             Expected (independent: computed from the 0.2 s rows and 10 px/s with y(s)=floor(s*10*H/C)): after the first Tx row the band covers rows 0-3 and the receive rows start at 4; the remaining Tx rows leave that picture unchanged; after the 12 s of receive the band covers rows y(12) to y(12)+3, receive rows above and below it and no grey row; labels 39.0 s at 0, 35.0 s at y(4), 30.0 s at y(9), then 10.0 s at y(14)+4, none of 25, 20, 15 s; the band's readout names the source range 12.0-27.000 s; the Day page pixels of the band are dark red; the 7.4 s hole is part of the band and the 7.6 s hole stays grey. On the parent client the Tx rows take 150 px, the labels ignore the band and the Day pixels are pale.
             2 — Isolated automated browser test; Windows PC, no radio (operating-layout suite). Live acceptance: TC-061-009. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-061-05';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_061_05_verified_by_TC_061_008 from 'CL-061-05' to 'TC-061-008';
    verification 'TC-061-009' {
        doc /* TC-061-009 — The Tx band on HB9BLA
             CL-061-05
             Setup: the installed station on HB9BLA, IC-7300, RF power set by the test to at least 30 W before the first Tx (CI-V 14 0A, starting at 0090, with the station stopped and idle, because it holds COM3; read back; the first Tx must read Po at least 30 %; if below, raise the value and repeat; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported), the operator's consent, the operator's browser in its usual theme.
             Steps: run a QSO with several Tx periods and look at the waterfall during and after them.
             Expected: each Tx period shows only a thin dark red band; no white or grey band appears while transmitting; the time labels below a band are the source times of those rows.
             5 — Live with RF on the station, operator consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-061-05';
        }
    }
    dependency CL_061_05_verified_by_TC_061_009 from 'CL-061-05' to 'TC-061-009';
    requirement 'CL-063-01' {
        doc /* The station holds one profile per contest from the official rules: WW Digi, ARRL Digi, ARRL Field Day, ARRL January, June and September VHF, IARU R1 50 MHz and 70 MHz MGM and FT8 Activity, usable everywhere in the world; a limit that depends on the location or the entry class is a note, not a refusal. Each profile holds the schedule rule, bands, modes, exchange, dupe, points and multiplier rules, the automation clause as the rules word it, notes and the source, as data, so that a new contest is one more entry. Its period is pre-computed from the schedule rule for the current or next occurrence; ARRL January VHF is not computed. GET /strategy/contests reads them. Details: WstxContest::ContestProfile, ScheduleRule, AutomationClause, ProfileTable, ContestHttp. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contest.rs; server/src/strategy.rs; server/src/main.rs";
    }
    dependency CL_063_01_to_FR_024 from 'CL-063-01' to 'FR-024';
    requirement 'CL-063-02' {
        doc /* In a contest activity a CQ with the activity's own word (na_vhf and arrl_digi CQ TEST, ww_digi CQ WW, field_day CQ FD, rtty CQ RU) is answerable: it is no longer greyed and an operator's selection needs no confirmation. Outside the matching activity it stays not answerable, with the warning of CL-039-03. Details: WstxContest::ContestDirective, WstxStrategy::DirectedCqRule. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/contact_http.rs; server/src/contact.rs";
    }
    dependency CL_063_02_to_FR_024 from 'CL-063-02' to 'FR-024';
    dependency CL_063_02_to_FR_007 from 'CL-063-02' to 'FR-007';
    verification 'TC-063-001' {
        doc /* TC-063-001 — The profile table
             CL-063-01
             Setup: the profile table as compiled; an expected table written by hand from the rule sources listed on #63.
             Steps: read id, activity, dupes, points, multipliers, automation clause, bands, Cabrillo mark and the notes of each profile.
             Expected: the nine ids in selector order; WW Digi bands 160 to 10 m, dupes per band, 1 + 1 per 3000 km, grid field per band, forbidden; ARRL Digi with 6 m, 1 + 1 per 500 km rounded up, no multiplier, forbidden; Field Day per band and mode class, forbidden, check-log note, Cabrillo unconfirmed; the three VHF per band and grid, grid per band, forbidden, W/VE note; Field Day and VHF with every ADIF band from 50 MHz (6 m, 5 m, 4 m, 2 m up to submm); IARU 6 m and 4 m, kilometres, grid per band, silent, 6 hours note; FT8 Activity 2 m, 70 cm, 23 cm, one per call, silent; no RTTY Roundup; no id twice.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-01';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_001_the_profile_table_holds_the_rule_facts";
    }
    dependency CL_063_01_verified_by_TC_063_001 from 'CL-063-01' to 'TC-063-001';
    verification 'TC-063-002' {
        doc /* TC-063-002 — The period from the schedule rule
             CL-063-01
             Setup: instants chosen by a calendar, not by the code.
             Steps: the current or next occurrence of each profile at 2026-01-01; WW Digi during and at the end of its period; WW Digi 2024 and ARRL Digi 2025 for the full-weekend edge; FT8 Activity at the start and between its rounds and across the year end.
             Expected: WW Digi 2026-08-29 12:00 to 08-30 12:00, ARRL Digi 2026-06-06 18:00 to 06-08 00:00, Field Day 2026-06-27 18:00 to 06-28 21:00, June VHF 2026-06-13 18:00 to 06-15 03:00, September VHF 2026-09-12 18:00 to 09-14 03:00, IARU 2026-04-18 and 2026-05-16 14:00 to 14:00, end exclusive; January VHF none; at the end the next year's 2027-08-28; 2024-08-24 and 2025-06-07; FT8 Activity 2026-11-04 2 m, 11-11 70 cm, 11-18 23 cm, 2027-01-06 2 m, 17:00 to 21:00.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-01';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_002_the_period_comes_from_the_rule";
    }
    dependency CL_063_01_verified_by_TC_063_002 from 'CL-063-01' to 'TC-063-002';
    verification 'TC-063-003' {
        doc /* TC-063-003 — GET /strategy/contests
             CL-063-01
             Setup: the pure list at 2026-08-01; the actual station router on a disposable selected HTTPS profile with one grant.
             Steps: the list; GET with the browser cookie, without credentials and with a query; POST.
             Expected: the nine ids in order, WW Digi with period {2026-08-29T12:00Z, 2026-08-30T12:00Z, band null}, its activity and rule names; January VHF period null; the route returns v 1, the profile id and the list with a period that has not ended; 401 unauthorized; 400 invalid_request; 405.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-01';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_003_the_list_names_each_profile_with_its_period; server/src/strategy_tests.rs::tc_063_003_the_contests_route";
    }
    dependency CL_063_01_verified_by_TC_063_003 from 'CL-063-01' to 'TC-063-003';
    verification 'TC-063-004' {
        doc /* TC-063-004 — The directive rule in a contest activity
             CL-063-02
             Setup: a hand table of activity, directive and answerable; the actual router with an injected FT8 live job for the selection.
             Steps: the table with EU and NA continents and with my continent unknown; the verdict of CQ WW K1ABC with and without the activity; the browser's select_row of that row in none and in ww_digi.
             Expected: TEST answerable in na_vhf and arrl_digi only, WW in ww_digi, FD in field_day, RU in rtty, not in another activity or hound; NA stays not answerable and EU answerable in an activity; greyed without the activity, rank 0 with it; 409 directive_not_answerable in none, accepted in ww_digi without directive_confirmed.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-02';
        }
        attribute executable : String = "server/src/strategy_tests.rs::tc_063_004_the_directive_table_in_a_contest_activity; server/src/strategy_tests.rs::tc_063_004_a_selection_of_the_activitys_cq_needs_no_confirmation";
    }
    dependency CL_063_02_verified_by_TC_063_004 from 'CL-063-02' to 'TC-063-004';

    requirement 'CL-063-03' {
        doc /* The operator selects a contest with its period, its operation (S&P or Run), its repetitions before leaving (default 2) and its quiet time (default 10 min) through a prompt pre-filled from the schedule rule (empty for ARRL January VHF, which the prompt asks), shown with the strategy and editable; with Auto off it only colours (CL-039-22). It is exclusive with an award strategy, is held in station memory only, and None ends it. The log is evaluated only inside that period: dupes by the profile's rule, multipliers, points and the score. Choosing an activity sets no strategy and selecting a contest sets no activity. Details: WstxContest::ContestSelection, ContestLog, ContestPrompt. */
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
             Steps: each refused selection form; PUT with a contest; read strategy.json; a new owner; the automation snapshot; PUT with a strategy and a contest; a period with end not after start; evaluate; PUT without contest; evaluate.
             Expected: each field named; the configuration echoes the contest, the file holds none, a new owner has none, no run; 400 field contest and contest.end; verdicts JA1XYZ rank 0 new multiplier 4 points, K1OLD rank 1, W1DUP dupe with rank null; tally 1 QSO, 1 multiplier, 3 points, score 3 (JN47-EM12 8469.4 km); strategy WW Digi; after None the key is gone and evaluate says not_configured.
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
             Expected: the toggle hidden, the selector unchanged, nothing evaluated and no read of /strategy/contests without a contest; one read at the prompt, and one after the reload, which names the contest in the selector; the rule's period pre-filled, the clause, the activity line, colouring only checked; January empty and refused with no request; one PUT with active null and the contest; one evaluation; the row to my call stays beside JA1XYZ with the multiplier colour and K1ABC, the status with period and tally; no all-time slot colour and no new-call or new-DXCC reason on any row; a partner row is listed first while its contact stands, and hidden after; Show all adds the dupe and the directed CQ dimmed, without a slot colour, with no new request; no request during the silence; the period in force on reopening; None sends no contest, shows every row and brings the slot colour back; no sideways overflow on the phone.
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
        doc /* With Auto on a contest runs as S&P or Run. S&P calls the most valuable callable station, Run calls CQ with the contest's message and answers the most valuable non-dupe caller (new multiplier, QSO points, SNR), not the first decoded; a dupe caller is never answered and never ends a stay. Leaving follows CL-039-23 with the contest's repetitions and quiet time. Where the rules forbid automatic operation the browser shows the clause as a warning when Auto is switched on and transmits only after the operator's confirmation, and the station refuses Auto on without it; where they are silent a short note. It waits while the activity, the band or the period do not fit the contest; a contest can still be operated by hand. Details: WstxContest::ContestRun, AutomationClause, ContestSelection; WstxStrategy::AutoToggle, LeaveRule. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/contest.rs; server/src/strategy.rs; server/src/logbook.rs; client/contact.js";
    }
    dependency CL_063_05_to_FR_024 from 'CL-063-05' to 'FR-024';
    dependency CL_063_05_to_FR_020 from 'CL-063-05' to 'FR-020';
    requirement 'CL-063-06' {
        doc /* The safety of a contest run stays on the server and is that of an award strategy run: HALT from any source ends it and turns Auto off (the contest stays), Abort QSO (Esc) ends the QSO only, the Tx watchdog stops its CQ, with no client for 60 s or after 8 hours it starts nothing new, finishes the QSO in progress and its own CQ ends at once, only the browser's Auto on starts it, and a double-click is a manual intervention it resumes after. Details: WstxContest::ContestRun, WstxStrategy::StrategyRun, AutoToggle, ManualIntervention, WatchdogFromOperator. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/strategy.rs";
    }
    dependency CL_063_06_to_FR_024 from 'CL-063-06' to 'FR-024';
    dependency CL_063_06_to_FR_020 from 'CL-063-06' to 'FR-020';
    verification 'TC-063-009' {
        doc /* TC-063-009 — Search and pounce, and the automation clause
             CL-063-05
             Setup: the selection form table; the actual station router (HB9BLA JN47AA) with the contact engine and #9 transmit owner on the recording hardware double, virtual UTC, on 20 m, an imported QSO with W1DUP inside the period; a status session held open; for the manual QSO, the CAT owner on a scripted IC-7300 whose dial reads 14.074 MHz, confirmed, and an empty log.
             Steps: each forbidding and silent profile with sp and run, then Auto on with and without the confirmation; a selection with operation colouring or with automation_confirmed; set_activity alone; sp with Auto on and activity none, on 30 m, then fitting; CQ WW W1DUP (strongest), K1ABC and JA1XYZ (weakest); empty partner periods; W1DUP alone; a selection whose period starts in an hour; a run with a manual replacing QSO with W9XYZ to its end, nothing imported, the log rebuilt, then W9XYZ's CQ alone.
             Expected: Auto on refused field automation_confirmed where forbidden, accepted where silent; colouring and automation_confirmed refused on PUT with their field; no run with Auto off, after the refused Auto on and after set_activity; reasons activity, band, none; never a CQ; JA1XYZ selected and armed, Tx2 with the grid; after 2 partner periods without progress waiting, disarmed, JA1XYZ in its quiet time; nothing armed for the dupe alone; outside_period and nothing armed; the log holds exactly W9XYZ EN52 20m FT8, written by the completed QSO itself; the manual QSO's station a dupe, nothing armed.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-05';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_009_a_selection_asks_nothing_and_refuses_colouring_and_the_confirmation; server/src/strategy_tests.rs::tc_063_009_search_and_pounce_calls_the_most_valuable_and_waits_for_what_it_needs; server/src/strategy_tests.rs::tc_063_009_a_manual_qso_of_the_period_is_a_dupe_for_the_next_evaluation";
    }
    dependency CL_063_05_verified_by_TC_063_009 from 'CL-063-05' to 'TC-063-009';
    verification 'TC-063-010' {
        doc /* TC-063-010 — Run: CQ and the most valuable caller
             CL-063-05
             Setup: as TC-063-009 with the scripted IC-7300 on 14.074 MHz, activity ww_digi, run selected.
             Steps: a step; callers W1DUP (dupe, strongest), K1ABC (first non-dupe decoded), JA1XYZ (weakest, new multiplier, most points); its R and 73; steps; nothing imported; JA1XYZ again; once the log is rebuilt, callers JA2ABC PM85 (more points) and K1NEW FN42; Abort of that QSO; an empty period; Abort of the run's own CQ; the band leaves the contest and returns (the dial to 10.136 MHz and back); the station clock past the period's end.
             Expected: calling_cq, armed, Tx6 "CQ WW HB9BLA JN47"; JA1XYZ answered with 2 candidates, not the first, not the strongest, not the dupe; completed, then calling_cq again with 1 completed; the log holds W1DUP EM12 and JA1XYZ PM95 20m FT8, the latter written by the completed QSO itself; not answered again; K1NEW selected, PM being no new multiplier any more; after that Abort calling_cq; the CQ goes on; after Abort of the CQ calling_cq, armed, with a new contact id and operation run; waiting band and disarmed, then calling_cq and armed again; waiting outside_period and disarmed.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-05';
        }
        attribute executable : String = "server/src/strategy_tests.rs::tc_063_010_run_calls_cq_and_answers_the_most_valuable_caller";
    }
    dependency CL_063_05_verified_by_TC_063_010 from 'CL-063-05' to 'TC-063-010';
    verification 'TC-063-011' {
        doc /* TC-063-011 — The safety of a contest run
             CL-063-06
             Setup: as TC-063-010, the run calling CQ with Auto on.
             Steps: an MCP configure with strategy true; a browser's replace selection of a CQ; Abort; HALT by route; Auto on, the clock past 8 hours; Auto on, every session gone and the clock past 60 s; Auto on, then Auto off, then Auto on; a watchdog limit of 2 with two CQs sent, the third period and a caller; Auto on, Enable Tx off, Auto off, Auto on.
             Expected: operator_required; manual with the operator's contact; after Abort calling_cq with operation run; halted, Auto off, the contest and operation run kept, disarmed; run_limit and no_client, disarmed, Auto off, the contest selected with its operation; stopped and disarmed at Auto off, calling_cq again with no CQ left behind; tx_watchdog, not keyed again, still disarmed with the caller, Auto off, the contest selected with operation run; transmit_stopped, then calling_cq again.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-06';
        }
        attribute executable : String = "server/src/strategy_tests.rs::tc_063_011_the_safety_of_a_contest_run_stays_on_the_server; server/src/strategy_tests.rs::tc_063_011_the_tx_watchdog_stops_a_run_on_a_silent_band";
    }
    dependency CL_063_06_verified_by_TC_063_011 from 'CL-063-06' to 'TC-063-011';
    verification 'TC-063-012' {
        doc /* TC-063-012 — Fully automatic in the browser
             CL-063-05
             Setup: actual browser with hand-written replies for GET and PUT /strategy, POST /strategy/auto, GET /strategy/contests and GET /automation.
             Steps: Run on WW Digi, Start; Auto on, decline; Auto on, confirm; 1.5 s of silence; automation.state pushes for calling_cq, waiting outside_period and stopped run_limit; reopen and Start the same selection; reopen; FT8 Activity with S&P and Auto on.
             Expected: Start sends one PUT with operation run, repetitions 2, quiet_minutes 10 and no automation_confirmed; the warning with the clause on Auto on, nothing sent when declined; one POST /strategy/auto with automation_confirmed true when confirmed; no read of /automation during the silence; the status names each; Start of the same selection sends nothing new to the run (Auto stays as pushed); the operation in force on reopening, S&P as the default of another contest, the note; no warning and no automation_confirmed for FT8 Activity.
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
             Setup: as TC-039-042 (the actual station router, HB9BLA JN47AA, with the contact engine, automation and #9 transmit owner on the recording hardware double, virtual UTC, 20 m FT8, a status session held open, the browser cookie grant); strategy "New calls" selected, Auto on; Tx watchdog 6; an empty log.
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
             Setup: as TC-081-001; for (a), (b) and (d) "Casual 20 m" (cq_when_no_target true) calling CQ after two empty publications, Hold Tx off; each case from a new run.
             Steps: (a) W1AW FN31 calls my call during the CQ; the run answers; POST /strategy/auto {auto false} 2 s into the period in which our reply to W1AW is keyed; W1AW then sends R-.. and RR73 in turn. (b) The same, with Auto false after W1AW is selected and our reply armed, before its period starts; W1AW calls my call again for three periods. (c) "New calls" calling CQ K1ABC FN42, K1ABC silent; Auto false 2 s into the period of our second Tx1; then K1ABC answers HB9BLA K1ABC -05. (d) Auto false 2 s into a period in which the run's CQ is keyed, no caller.
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
             Setup: as TC-081-001; for (c) and (d) the contest WW Digi S&P in force with automation_confirmed (as TC-063-009); for (e) a pounce on K1ABC started by MCP with Auto off (as TC-039-042); for (f) and (g) an MCP policy run (as TC-020-003) with max_run_minutes 1 for (g) and the automation clock moved by the seam. Each case runs into the same started QSO: K1ABC FN42 called by the run, his answer HB9BLA K1ABC -05 decoded, then the end below, then his RR73 after our R-report.
             Steps: (a) PUT /strategy with active None; (b) PUT /strategy with "Farthest new on band" while Auto is on, and CQ JA1XYZ PM95 published during the QSO and after its completion; (c) PUT /strategy without the contest; (d) the station clock past the contest period's end; (e) POST /strategy/auto {auto true} with "New calls" selected; (f) AutomationCommand stop of the run; (g) the run deadline passed; (h) POST /strategy/auto {auto false} sent twice, 1 s apart.
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
             Setup: as TC-081-001 with the Tx watchdog set to 2 by the browser, strategy repetitions 4, a spot of my call at K1ABC 60 s old (he hears us: the leave rule would double x to 8), K1ABC called from Tx 1500 with the quietest slot elsewhere; the started QSO of TC-081-001.
             Steps: (a) Auto false after our 1st R-report; K1ABC sends RR73 after our 2nd R-report. (b) Auto false after our 1st R-report; K1ABC repeats HB9BLA K1ABC -05 every period. (c) Auto stays on while K1ABC repeats -05 until our R-report has been keyed 3 times (past the limit under the run's exemption, StrategyWatchdog); then Auto false.
             Expected (oracle: WstxContact::TxWatchdog, limit 2, and CL-081-01): (a) the 2nd R-report keyed, then 73, completed, one log entry (the limit not passed); (b) the R-report keyed a 2nd time, never a 3rd: 1.2 s into that period Enable Tx goes off with cause txWatchdog, no halt, nothing logged; (c) the R-report not keyed again after the Auto off, Enable Tx off with cause txWatchdog at 1.2 s into the next due period; in every case after the Auto off no leaving (left null, no quiet entry), no slot check (tx_hz stays 1500, slot_check unchanged), the hearing subscription of K1ABC dropped, and the contact snapshot's tx_remaining_calls that of the Tx watchdog. Red on the parent: (a) disarmed at the Auto off, never completed.
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
             Steps: Auto on with "Strongest new on band"; when a station has answered our call (his report decoded) switch Auto off in the browser; watch to the end of the QSO and two more periods; Auto on with "Casual 20 m" until it calls CQ; switch Auto off while the CQ is keyed.
             Expected: after the first Auto off the Auto button grey and the line "Strategy Strongest new on band · Auto off" at once, the QSO goes on to RR73/73 and is logged once (one new log entry of that call), then nothing is keyed; after the second Auto off the CQ period ends normally and nothing is keyed after it; recorded on the issue.
             5 — Live with RF on the station, operator consent; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-081-01';
        }
    }
    dependency CL_081_01_verified_by_TC_081_007 from 'CL-081-01' to 'TC-081-007';

}
