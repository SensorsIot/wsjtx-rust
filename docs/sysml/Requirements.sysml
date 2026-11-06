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
             Preserve required external protocols and message formats, including baseline UDP integrations and reception-reporting workflows. The WSJT-X UDP interface is specified by issue #40, CL-040-01..04, contract WstxUdp; reception reporting remains target. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/network_message.rs; server/src/udp.rs";
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
             Offer a selectable native FlexRadio TCP/UDP connection type alongside the default audio-device/optional CAT/PTT path. Native profiles operate without requiring external SmartSDR desktop/CAT/DAX applications, persist intended radio/slice associations and reconcile actual resources on connection. Both paths share the browser/DSP/MCP architecture. Phase-two target; not implemented. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    requirement 'FR-024' {
        doc /* Contest, special-activity and DXpedition operation — phase three
             Offer WSJT-X's special operating activities chosen by the operator, the contest exchanges, the Hound role and the nonstandard message types, each with its decode, encode, sequencing and logging, on the shared browser/modem/QSO/log/MCP services. Approved slices (issue #24, operator 2026-11-03, WSJT-X 3.3.0-beta5 reference): S1 nonstandard/compound calls, filled-in hashed calls and free text; S2a grid-exchange contests; S2b Field Day and RTTY Roundup (ADIF contest fields, no Cabrillo); S4 classic Hound; S5 SuperFox Hound. Fox (S6) is out of scope; EU VHF (S3) is backlog. */
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
        doc /* The minimal profile MUST support two clients sharing the contract's 32 kbit/s link model and meet its traffic and visible-response budgets. Tests MUST distinguish cold page/assets loading, protocol connection and displayed-status timing, and identify the measurement layer. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs; client/app.js";
    }
    dependency CL_003_05_to_FR_021 from 'CL-003-05' to 'FR-021';
    requirement 'CL-003-06' {
        doc /* Application output buffering and active connections MUST have explicit bounds. An unresponsive client MUST be removed under the contract's liveness/write limits without blocking another client's status requests. Test results MUST distinguish observed liveness removal from an unobserved send-timeout branch or total-memory bound. */
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
        doc /* Standard audio with optional CAT/PTT remains the default. Audio and control selections MUST persist independently without claiming hardware availability. Native FlexRadio is reserved and refused in this phase. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/profile.rs; client/app.js";
    }
    dependency CL_005_05_to_FR_001 from 'CL-005-05' to 'FR-001';
    dependency CL_005_05_to_FR_022 from 'CL-005-05' to 'FR-022';
    requirement 'CL-013-01' {
        doc /* Phase 2 MUST offer direct native-network integration as an optional profile connection type for the selected radio control, status and sample-stream functions. When selected, that native path MUST NOT require the external SmartSDR desktop application, SmartSDR CAT or DAX applications to be installed/running as bridges. This restriction does not prohibit those tools as operator-selected infrastructure for the standard connection path. A Rust implementation may coordinate shared radio access internally without forcing one hardware GUI-client session per logical station server. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    dependency CL_013_01_to_FR_023 from 'CL-013-01' to 'FR-023';
    requirement 'CL-013-02' {
        doc /* This independence concerns desktop applications. Compatible radio-side firmware and its API remain required; this specification does not promise a FlexRadio operating without its SmartSDR radio firmware or an unrestricted firmware compatibility range. Pin supported models, firmware/API versions and selected stream formats before implementation. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    dependency CL_013_02_to_FR_023 from 'CL-013-02' to 'FR-023';
    requirement 'CL-013-03' {
        doc /* Each native FlexRadio profile MUST persist its intended radio and slice association. On every connection/reconnection the system MUST reconcile that intent with authoritative discovery/status and current runtime handles. A changed/transient slice index MUST NOT redirect a station to another station's slice. Unresolvable associations MUST produce a visible unavailable/conflict state rather than guessing a replacement. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    dependency CL_013_03_to_FR_023 from 'CL-013-03' to 'FR-023';
    requirement 'CL-013-04' {
        doc /* Control responses and received stream data MUST be routed to the associated station. Capacity shortages, occupied resources and incompatible API behavior MUST be reported without stealing another profile's slice or silently reducing the requested independence. Four-slice hardware validation requires a model/configuration that actually provides at least four usable slices. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    dependency CL_013_04_to_FR_023 from 'CL-013-04' to 'FR-023';
    requirement 'CL-013-05' {
        doc /* Shared-radio transmit, tuning and other constrained-resource authority MUST be coordinated under FR-008/FR-009 before those operations are enabled. Four station profiles do not confer simultaneous independent transmit authority. Reconnect/profile restoration MUST NOT replay an old transmit request or bypass the future ownership policy. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    dependency CL_013_05_to_FR_008 from 'CL-013-05' to 'FR-008';
    dependency CL_013_05_to_FR_009 from 'CL-013-05' to 'FR-009';
    dependency CL_013_05_to_FR_023 from 'CL-013-05' to 'FR-023';
    requirement 'CL-013-06' {
        doc /* The native path MUST reuse the common browser, station-operation, DSP/modem and future MCP interfaces. The default standard connection remains usable without FlexRadio hardware or native-profile fields. A mixed set of instances MUST preserve each profile's selected path, configuration and routing independently. */
        attribute coverage : ImplementationState = ImplementationState::target;
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
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/radio_control/mod.rs; server/src/receive.rs";
    }
    dependency CL_008_01_to_FR_001 from 'CL-008-01' to 'FR-001';
    dependency CL_008_01_to_FR_002 from 'CL-008-01' to 'FR-002';
    dependency CL_008_01_to_FR_009 from 'CL-008-01' to 'FR-009';
    dependency CL_008_01_to_FR_022 from 'CL-008-01' to 'FR-022';
    requirement 'CL-008-02' {
        doc /* Deliver immutable canonical 12 kHz mono samples and explicit timing/gaps through one common converter to the existing spectrum/decoder worker, without fabricating samples or UTC accuracy. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/radio_control/mod.rs; server/src/receive.rs";
    }
    dependency CL_008_02_to_FR_002 from 'CL-008-02' to 'FR-002';
    dependency CL_008_02_to_FR_003 from 'CL-008-02' to 'FR-003';
    dependency CL_008_02_to_FR_004 from 'CL-008-02' to 'FR-004';
    requirement 'CL-008-03' {
        doc /* Publish independently truthful audio/control states, bounded live results and explicit loss/recovery while preserving worker, cancellation and thin-link bounds. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/radio_control/mod.rs; server/src/receive.rs";
    }
    dependency CL_008_03_to_FR_002 from 'CL-008-03' to 'FR-002';
    dependency CL_008_03_to_FR_009 from 'CL-008-03' to 'FR-009';
    dependency CL_008_03_to_FR_019 from 'CL-008-03' to 'FR-019';
    dependency CL_008_03_to_FR_021 from 'CL-008-03' to 'FR-021';
    requirement 'CL-008-04' {
        doc /* Support the Windows shared-audio and IC-7300 receive-control matrix below, with independently verified receive-only physical acceptance. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/radio_control/mod.rs; server/src/receive.rs";
    }
    dependency CL_008_04_to_FR_002 from 'CL-008-04' to 'FR-002';
    dependency CL_008_04_to_FR_009 from 'CL-008-04' to 'FR-009';
    requirement 'CL-008-05' {
        doc /* Audio never requires CAT; CAT never opens audio. Unsupported operations fail before device bytes; independent failure never creates false readiness. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/radio_control/mod.rs; server/src/receive.rs";
    }
    dependency CL_008_05_to_FR_002 from 'CL-008-05' to 'FR-002';
    dependency CL_008_05_to_FR_009 from 'CL-008-05' to 'FR-009';
    requirement 'CL-008-06' {
        doc /* Separate a versioned factual radio catalogue, compiled typed operations and bounded protocol execution. Catalogue data cannot authorize raw or transmit commands. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/radio_control/mod.rs; server/src/receive.rs";
    }
    dependency CL_008_06_to_FR_009 from 'CL-008-06' to 'FR-009';
    requirement 'CL-008-07' {
        doc /* Coordinate receive-only operating mode and preferred band changes through the existing station/receive owner and typed CAT actor, with explicit nominal/observed truth, actual release barriers, per-query provenance and cancellation fencing. */
        attribute coverage : ImplementationState = ImplementationState::partial;
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
             status with a GET /transmit fixture.
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
             CODEC) into a dummy load or the station antenna at reduced power, profile
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
        attribute executable : String = "server/tests/audio_contract.rs; server/tests/audio_hardware.rs; server/tests/audio_listen.rs; server/tests/audio_receive.rs; server/tests/receive_integration.rs; server/tests/source_contract.rs";
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
             Independent availability, no false ready state, no cross-profile samples/results, conversion service<=50ms quanta and native-to-canonical software backlog<=200ms under the declared workload, <=250ms normal cancel, <=2s status over the combined32kbit link; failed close retains ownership. No real RF transmission. Delayed pages preserve newer confirmed lifecycle/error state and do not advance cursors; pre-mutation reads cannot clear the unknown-outcome control barrier, while a later explicit reconciliation can. Live progress updates only its matching live owner, with no exception or false disconnection when the recorded-input job is absent.
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
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "client/index.html; client/recording.js; client/recording.css; server/src/recording.rs";
    }
    dependency CL_010_05_to_FR_010 from 'CL-010-05' to 'FR-010';
    dependency CL_010_05_to_FR_019 from 'CL-010-05' to 'FR-019';
    requirement 'CL-010-07' {
        doc /* Show audio, CAT, decoder and transmit availability independently. Label unavailable values and visibly disable unsupported actions with adjacent reasons; status-link connection alone does not establish a radio capability. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "client/index.html; client/recording.js; client/recording.css; server/src/recording.rs";
    }
    dependency CL_010_07_to_FR_001 from 'CL-010-07' to 'FR-001';
    dependency CL_010_07_to_FR_008 from 'CL-010-07' to 'FR-008';
    dependency CL_010_07_to_FR_009 from 'CL-010-07' to 'FR-009';
    dependency CL_010_07_to_FR_019 from 'CL-010-07' to 'FR-019';
    requirement 'CL-010-09' {
        doc /* Band Activity shows only the latest published decode period and signed station timing relative to our clock, selectable presentation sorting and explicit partial/unavailable states. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "client/index.html; client/recording.js; client/recording.css; server/src/recording.rs";
    }
    dependency CL_010_09_to_FR_010 from 'CL-010-09' to 'FR-010';
    dependency CL_010_09_to_FR_019 from 'CL-010-09' to 'FR-019';
    requirement 'CL-010-16' {
        doc /* Present the laptop operating screen of WstxOperatingLayout::OperatingScreen: a top bar with only band, mode, dial, UTC/period, Logbook, Settings and HALT; the full-width waterfall with the Rx/Tx strip; Band Activity with the strategy element and the QSO pane with direct buttons and no Enable Tx control; setup and diagnostics in the four-section Settings drawer; themes; WSJT-X keyboard shortcuts; and only the token form for an unauthorized browser. Details: OperatingScreen, RxTxStrip, BandActivityView, QsoPane, SettingsDrawer, ThemeChoice, UnauthorizedView, KeyboardShortcuts, WstxContact::SetEnableTx. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "client/recording.js; client/recording.css; client/contact.js; client/logbook.js";
    }
    dependency CL_010_16_to_FR_010 from 'CL-010-16' to 'FR-010';
    dependency CL_010_16_to_FR_019 from 'CL-010-16' to 'FR-019';
    dependency CL_010_16_to_FR_021 from 'CL-010-16' to 'FR-021';
    requirement 'CL-010-08' {
        doc /* Preserve keyboard and narrow-screen operation, literal field rendering and existing signal/status transport contracts. Secondary in-page regions keep the persistent station bar and disabled Halt Tx accessible. */
        attribute coverage : ImplementationState = ImplementationState::partial;
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
        doc /* Progress the contact on the server by the WstxContact::AutoSequence table (messages from the partner addressed to my call; repeats resend, other stations ignored, completion after a transmitted RR73/73 or a received 73 after RRR) and show confirmed sequence, next message, last transmitted message, pending requests, stale observations and failures separately. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/main.rs; client/contact.js";
    }
    dependency CL_010_02_to_FR_007 from 'CL-010-02' to 'FR-007';
    dependency CL_010_02_to_FR_008 from 'CL-010-02' to 'FR-008';
    dependency CL_010_02_to_FR_019 from 'CL-010-02' to 'FR-019';
    requirement 'CL-010-03' {
        doc /* Offer explicit Enable Tx, disarm, contact cancellation and immediate Halt Tx (button, Alt+H and Esc; Esc also cancels the contact and closes no panel); every transmission is a TransmitRequest through the #9 transmit service and its transmit authority, never direct PTT; loss, reconnect, retry or duplicates replay no transmit request and create no second contact. The live transmit path consumes the delivered #9 slice B owner (WstxTransmit::TransmitArming, TransmitRequest, TransmitOutcome, HaltTransmit) in-process. Details: WstxContact::SetEnableTx, HaltTx, CancelContact, TransmitSubmission, ContactCommand. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/main.rs; server/src/transmit/service.rs; client/contact.js";
    }
    dependency CL_010_03_to_FR_007 from 'CL-010-03' to 'FR-007';
    dependency CL_010_03_to_FR_008 from 'CL-010-03' to 'FR-008';
    // CL-010-04: ExportAdi is streamed (#10, 2026-11-04). #41 retired the #10 log review queue: completion and
    // Log QSO log directly (WstxContact::DirectLog); TIME_ON/TIME_OFF come from the
    // contact engine (server/src/contact.rs).
    // CL-010-03 partial: physical RF acceptance (TC-007-007) is unexecuted; MCP exposes
    // the same contact operations through WstxMcp (#12). CL-010-11 partial: since #37 the
    // browser sends no re-decode; the wire redecode stays refused redecode_unavailable.
    // CL-010-15 partial: TC-007-005 Thin/Off measurement with the new events and MCP.
    requirement 'CL-010-04' {
        doc /* Log every completed contact directly, without a review step (#41, as WSJT-X): at completion and on a manual Log QSO the server stores the contact's record in the profile directory's ADIF 3.1.8 contacts.adi with its contact identity and sends it to the WSJT-X UDP targets as QSO Logged and Logged ADIF; exactly one record per contact identity (an identical re-log adds nothing, completion after an early Log QSO replaces it; each contact is sent to the UDP targets once), a later contact with the same station a new record, Saved only after durable acknowledgement, a failed write visibly unsaved and retried; ADI export and history with the stated limits; and (#10, operator 2026-11-03) Update logbook from ADIF, the one ADI import: an export of another logger (for example Log4OM) is consolidated into the contact log, repeatable and incremental, a record already present (same contact identity, or same call, band and mode/submode with a start within 2 minutes) adding nothing and the stored record winning, only the log's own fields kept, added records marked with their source, QSO confirmation status (LoTW, QSL and eQSL received with their dates and via) kept and, on a rerun, upgraded on records already present (a confirmation is only added, never removed; #10, operator 2026-11-04), so worked-before and award queries tell worked from confirmed per entity, band and mode, invalid records skipped and invalid optional fields dropped with their reasons in the summary, nothing sent to the UDP targets or elsewhere, and the added records feeding worked-before, DXCC and grid status. The former log review queue (OfferLogReview, discard_review, the review form) is retired. Details: WstxContact::LogRecord, DirectLog, SaveContact, UpdateLogbook, ExportAdi, ContactHistory, AdiLimits, WorkedBeforeQuery; WstxUdp::OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/logbook.rs; server/src/logbook_http.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/main.rs; client/logbook.js; client/contact.js";
    }
    dependency CL_010_04_to_FR_011 from 'CL-010-04' to 'FR-011';
    requirement 'CL-010-15' {
        doc /* Expose the contact operations only through the versioned WstxContact wire contract: exact routes, keys and byte caps, command_id idempotency, contact_revision, the ContactRefusal codes, the contact.state and station.tick events, and the stated Thin/Off byte budget, leaving StatusReply and the compressed-route allowlist unchanged. Details: WstxContact::ContactWire, ContactCommand, CommandReceipt, ContactSnapshot, ContactStateEvent, StationTickEvent. */
        attribute coverage : ImplementationState = ImplementationState::partial;
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
        doc /* Bound unattended transmission with a server-owned Tx watchdog (#39, 2026-11-04: default 6, 1..99 consecutive unanswered own transmissions, reset by an answer from the partner or, to my CQ, from anyone, and by accepted operating requests from the browser; at the limit the next transmission is not keyed and Enable Tx goes off without a halt) and an always-on Tune watchdog (default 90 s, 1..300 s). Details: WstxContact::TxWatchdog, TuneWatchdog. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/transmit/service.rs; client/contact.js";
    }
    dependency CL_010_10_to_FR_008 from 'CL-010-10' to 'FR-008';
    requirement 'CL-010-11' {
        doc /* Set Rx and Tx audio offsets through labelled numeric inputs and waterfall pointer actions (#50: click Tx; double-click Rx and Tx; dragging the 3 px Rx/Tx lines and the Rx/Tx strip fields with 1 Hz/10 Hz steps), Hold Tx protecting only against implicit moves, each confirmed by the server and none enabling transmission. Details: WstxContact::PointerEffect, FrequencyControls. */
        attribute coverage : ImplementationState = ImplementationState::partial;
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
        doc /* Indicate worked-before status of decoded calls in Band Activity and the Rx Frequency pane (this band and mode, other band or mode, not worked, unknown) determined by the server from the profile log, by text or icon as well as colour, with at most one bounded query per published period. Details: WstxContact::WorkedBeforeQuery. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/logbook.rs; server/src/logbook_http.rs; client/logbook.js; client/contact.js";
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
             Expected (independent hand-written table, not candidate output): selection gives dxCall K1ABC, grid FN42, report -12 rendered "-12", Rx and Tx 1235 Hz, odd parity, next Tx1 "K1ABC HB9BLA JN47", Tx2 "K1ABC HB9BLA -12", Tx3 "K1ABC HB9BLA R-12", Tx4 "K1ABC HB9BLA RRR", Tx5 "K1ABC HB9BLA 73", Tx6 "CQ HB9BLA JN47" and no TransmitRequest before Enable Tx. States/next slots follow WstxContact::AutoSequence exactly: (a) replying/Tx1 -> rogerReport/Tx3 -> signoff/Tx5 -> completed after the completed Tx5 outcome, Enable Tx off, one log offer; (b) RRR from the partner gives signoff/Tx5; the contact completes after the first completed Tx5 transmission (AutoSequence sent73), Enable Tx off, one log offer; (c) calling/Tx6 -> report/Tx2 only after selection -> rogers/Tx4 -> completed on 73 (RRR) or on the completed RR73 transmission, Enable Tx off and no further CQ; (d) repeats resend the same text, report-from-rogers returns to Tx3, no second completion or log offer; (e) other/late rows change nothing; (f) with Tx1 skip, selecting the CQ row enters report directly with next Tx2, overrides -50/+49 accepted and rendered "-50"/"+49", -51/+50 and invalid entries refused with no contact; (g) 50 Hz disarms in replying and in the Tx1-skipped report, 51 Hz does not; watchdog expiry while calling returns to idle; (h) Auto Seq off never changes the next slot; Esc and Halt send the halt request first, Esc also cancels; last transmitted text changes only on started outcomes and differs visibly from the next message. Each request carries a fresh requestSequence; a duplicated browser action (same command_id) yields one request; one decoded row delivered twice counts once.
             2 — Isolated automated functional tests; Windows development PC, actual candidate server and browser, independent decoded-row and transmit-outcome fixtures; no RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-010-01';
            verify 'CL-010-02';
            verify 'CL-010-03';
            verify 'CL-010-12';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; tests/contact.test.cjs";
    }
    verification 'TC-007-003' {
        doc /* TC-007-003 — Received views, Rx Frequency pane and partner selection
             CL-010-01, CL-010-06
             Setup: actual server/browser with an independently scripted result source and request recorder; rows with distinct UTC/DT/SNR/frequency/text including literal markup, unresolved hashes, duplicate/old tuples, 2047/2048/2049 retained records and expired cursors; Rx offset 1500 Hz; profile call HB9BLA, DX call K1ABC.
             Steps: filter/sort Band Activity; with no contact, read the QSO pane Others lines for one period with rows at 1449.9, 1450.0, 1489.9, 1510.1, 1550.0 Hz, "HB9BLA W1XYZ -10" at 400 Hz and "HB9BL K1ABC -01" at 2600 Hz (#37); select rows by click/Enter and by manual DX entry; switch profile.
             Expected (fixed input catalogue): the Others lines are exactly the two newest candidates among 1450.0, 1489.9, 1510.1, 1550.0 Hz and the HB9BLA row, plain (no warning sign), each a QSO table row with its period start, calls, exchange, our SNR and, for a report, the Tx SNR (no DT or frequency), and not 1449.9 Hz or HB9BL; sorting Band Activity sends no request and changes no contact/log; selection sends the exact identity and changes the partner only after acceptance; unresolved/old/wrong-profile rows cannot prepare a contact; no invented UTC/callsign, executable markup or cross-profile state.
             2 — Isolated automated functional tests; Windows development PC, real browser/server and independent result source. */
        attribute automation : AutomationState = AutomationState::partial;
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
             Steps: Enable Tx, Tune, Halt, Esc (focus in a text field, in the DX Call input and in an open panel), save and contact change while the link drops; reconnect; replay old requests; unauthenticated, wrong-Origin and wrong-profile requests; Tx offset 199/200/2950/2951 Hz; every ContactCommand action with missing/extra keys, 1024/1025-byte bodies, stale contact_revision (also for cancel and enable_tx false), a retained command_id with identical and different bodies; GET /contact at its 4096-byte maximum shape; Esc on a receive-only station.
             Expected (independent operation/state catalogue): Esc and Halt reach the #9 halt operation first even with panels open; Esc closes no panel; state shows pending/unknown until #9 confirms; reconnect loads the snapshot and replays no arm, tune, next-message or transmit request; no request reaches PTT except through the transmit-service double; unsupported transmit leaves Enable Tx/Tune disabled with a reason; 200 and 2950 accepted, 199/2951 refused; barrier refusals unchanged; no cross-profile contact. Each malformed command returns the independently expected ContactRefusal code and field with no state change; stale revisions refused except cancel/disarm; an identical retained command_id returns the same receipt with no second effect, a different body state_conflict; the maximum snapshot is exactly admitted and GET /contact is never gzip-coded; StatusReply keeps exactly {version,radio}; on the receive-only station Esc cancels the contact and sends no halt, while row selection and Log QSO still work.
             2 — Isolated automated functional tests; Windows development PC, actual candidate server/browser and independent control, audio and transmit emulators. */
        attribute automation : AutomationState = AutomationState::partial;
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
        doc /* TC-007-005 — Thin-link and local presentation
             CL-010-06, CL-010-08, CL-010-15
             Setup: calibrated TLS 32,000 bit/s per direction, 300 ms RTT, two-client fixture for 60 s with the active result/display workload, contact status, worked-before queries and log page/import/export traffic.
             Steps: filter/sort, resize, switch panes, scroll the Rx Frequency pane, run one contact.
             Expected: the request recorder shows no traffic from local presentation, at most one worked-before query of at most 64 calls per period per client and station.tick at 1/s Detailed and 1/5 s Thin/Off, contact.state at most 1/s with one pending GET /contact; with Off and two idle clients the total stays within 1000 B/s per direction, with Thin within 3000 B/s; existing byte envelopes and bounded queues hold; connected status within 2 s and first status within 10 s after page load; overhead counted from the simulator, not packet capture.
             2 — Isolated automated functional tests; Windows development PC, real browser/server and the existing thin-link simulator; no radio. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-010-06';
            verify 'CL-010-08';
            verify 'CL-010-15';
        }
    }
    verification 'TC-007-007' {
        doc /* TC-007-007 — Live FT8 contact on the IC-7300
             CL-010-01, CL-010-02, CL-010-03, CL-010-04, CL-010-10
             Setup: deployed candidate on HB9BLA with the IC-7300 (USB audio and CAT, USB-D, 20 m 14.074 MHz or another FT8 dial frequency), operator present at the radio, low power chosen by the operator, Halt Tx and the radio's own power control within reach; transmit authorized by the operator on 2026-10-31 for this test only. An independent receiver (separate WSJT-X station or PSK Reporter reception reports) observes our transmissions.
             Steps: run a UDP listener on 127.0.0.1:2237 enabled as a WSJT-X UDP target with QSO Logged and Logged ADIF; complete at least one contact answering a real CQ and, if band conditions allow, one by calling CQ, with Auto Seq, without pressing Log QSO; then Enable Tx without operator activity until the Tx watchdog (set to 2 unanswered calls for the test) stops it; Halt once during a transmission; restart the server.
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
             Steps: refuse limits 0 and 100, accept 6 (default) and 1..99; with limit 2 call CQ with no answer for three periods; with limit 2 select a CQ, send Tx1 twice and let the partner answer with a report, then send further unanswered messages; with limit 2 call CQ and let another station answer; send an accepted browser request after one unanswered call; disarm and re-enable; Tune with 90 s default, 1 and 300 s, refuse 0 and 301; Halt during Tune.
             Expected (hand-counted): the third CQ is never keyed: Enable Tx goes off before keying with cause tx_watchdog, tx_expired true, halt_state unchanged (no halt), PTT released; remaining calls 2, 1, 0 while armed; the partner's report resets the count (two more unanswered messages before the stop); an answer to my CQ by anyone resets it; a message from another station to someone else does not; an accepted browser request resets it; the counter is 0 while disarmed; the contact state is kept and "Tx watchdog: 2 unanswered calls" is shown; Tune ends at its limit through #9; startup default 6 calls and 90 s.
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
             Setup: actual Chromium/server with injected spectrum rows, 1100x850 and 360x640, DPR 1/2; request recorder.
             Steps: at independently computed pixel positions for 700, 1000, 1500 and 2950 Hz perform click, double-click, shift-click with Hold Tx on and right-click; numeric Rx/Tx inputs with 199/200/2950/2951 Tx.
             Expected (#50): requested offsets equal the independently computed axis frequency rounded to integer Hz; click Tx only; a double-click exactly one request for Rx and Tx and no re-decode request; shift-click as click and with Hold Tx on; right-click nothing; the markers are 3 px lines (Rx rgb(48,208,80), Tx rgb(255,64,64)) without text at the confirmed values; out-of-domain refused; no Enable Tx request; the browser context menu does not open on the waterfall.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::partial;
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
             Expected (independent record catalogue and direct file reading): each completion stores exactly one record with the hand-computed CALL, GRIDSQUARE, MODE/SUBMODE, RST_SENT/RST_RCVD, QSO_DATE/TIME_ON (first transmitted Tx2/Tx3 rule), TIME_OFF, BAND, FREQ = dial + Tx offset, STATION_CALLSIGN and MY_GRIDSQUARE, and the UDP target receives one QSO Logged and one Logged ADIF for it; repeated completion and an unchanged Log QSO add no record and no datagram; an early Log QSO closes the contact (completed, Enable Tx off, nothing queued), so the partner's later messages neither replace its record nor send a second datagram pair (#37); Log QSO of a completed contact keeps its completion record even after a location change; a UDP FreeText command arriving while a retry is due returns (no lock re-entry) and the datagrams follow; a failed write leaves the record unsaved with storage_unavailable shown and is stored by the retry; nothing is logged again after restart; the second contact with the same call is a separate record; SaveContact identical resave alreadySaved, changed resave conflict, invalid fields refused; the browser shows no review form and sends no POST /contacts; no cross-profile record or browser-clock time.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::partial;
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
        attribute automation : AutomationState = AutomationState::partial;
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
             Expected: K1ABC this band and mode; W1XYZ and DL1ABC other band or mode; N0NEW not worked then this band and mode after the save; hashed unknown; the status is text (hover text and aria-description, BandActivityHover) in Band Activity and the QSO pane's stations calling me, colour only from the enabled new_* slots of the record flags, so worked before on this band and mode has no colour; one query per period with at most 64 calls (the 65th unknown); no change to decoding, sequence or log.
             QSO pane subset (#10 2026-11-04, WstxOperatingLayout::QsoPane item 3). Setup: actual server log K1ABC 20m FT8 and DL1ABC 40m FT8; selection 20m FT8; one period with callers to my call HB9BLA K1ABC FN42 (no flags), HB9BLA W1XYZ FN31 (new_call, new_call_band) and HB9BLA DL1ABC -10 (new_call_band). Steps: wait for the Band Activity worked-before answer; read the callers; turn New call off in Settings; refresh status. Expected: K1ABC no colour, "Worked before on 20m FT8"; W1XYZ the New call colour, "New call", "New call on 20m"; DL1ABC the New call on band colour, "New call on 20m", "Worked before on another band or mode"; each title ends with the double-click hint; no My call colour; with New call off W1XYZ takes New call on band; exactly one worked-before query (the callers add none).
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-010-13';
        }
        attribute executable : String = "server/src/logbook_tests.rs; server/src/logbook_http_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_010_01_verified_by_TC_007_001 from 'CL-010-01' to 'TC-007-001';
    dependency CL_010_01_verified_by_TC_007_003 from 'CL-010-01' to 'TC-007-003';
    dependency CL_010_01_verified_by_TC_007_007 from 'CL-010-01' to 'TC-007-007';
    dependency CL_010_02_verified_by_TC_007_001 from 'CL-010-02' to 'TC-007-001';
    dependency CL_010_02_verified_by_TC_007_004 from 'CL-010-02' to 'TC-007-004';
    dependency CL_010_02_verified_by_TC_007_007 from 'CL-010-02' to 'TC-007-007';
    dependency CL_010_03_verified_by_TC_007_001 from 'CL-010-03' to 'TC-007-001';
    dependency CL_010_03_verified_by_TC_007_004 from 'CL-010-03' to 'TC-007-004';
    dependency CL_010_03_verified_by_TC_007_007 from 'CL-010-03' to 'TC-007-007';
    dependency CL_010_04_verified_by_TC_011_001 from 'CL-010-04' to 'TC-011-001';
    dependency CL_010_04_verified_by_TC_011_002 from 'CL-010-04' to 'TC-011-002';
    dependency CL_010_04_verified_by_TC_007_007 from 'CL-010-04' to 'TC-007-007';
    dependency CL_010_06_verified_by_TC_007_003 from 'CL-010-06' to 'TC-007-003';
    dependency CL_010_06_verified_by_TC_007_005 from 'CL-010-06' to 'TC-007-005';
    dependency CL_010_07_verified_by_TC_007_004 from 'CL-010-07' to 'TC-007-004';
    dependency CL_010_08_verified_by_TC_007_004 from 'CL-010-08' to 'TC-007-004';
    dependency CL_010_08_verified_by_TC_007_005 from 'CL-010-08' to 'TC-007-005';
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
             5. Hold (delay, not drop) every station-to-browser byte for 16s while the page's
                deferred client download is pending, then deliver it. Expect the same socket, no
                stale state and no new connection (#8). Hold beyond 31s with the download pending:
                expect stale detection within the 31s bound plus 1-second scheduler tolerance.

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
        doc /* #### TC-021-008 — Thin-link budget and client isolation

             **Clauses:** CL-003-01, CL-003-02, CL-003-05, CL-003-06, CL-003-08.
             **Promise:** FR-021. **Level:** 2 — Isolated automated tests.
             **Where it runs:** Windows PC, two real browser contexts and the candidate TLS server
             through the shared portable link simulator. The stalled-reader variant uses two
             independent local WebSocket peers against the actual server.

             **Budget variant — inputs/actions and expected results:**

             1. Start two uncached browser contexts sharing the contract's minimum-rate/latency
                profile. Report cold page and asset timings/sizes separately from protocol connection
                and first displayed status. Expect first status within its post-load limit.
             2. Keep both clients connected with unchanged station state for the contract's full
                measurement interval. Expect the aggregate mean in each direction to meet the
                [traffic budget](StationProtocol.sysml), including heartbeat
                and accounted overhead. Report actual TLS-stream bytes plus the explicit network model;
                do not describe these values as physical packet capture.
             3. Click Refresh status concurrently in both existing clients. Expect each visible
                Last updated value to change within the connected-response limit, using the existing
                WebSocket connections rather than creating replacement test connections.
             4. The minimal profile MUST contain no audio/spectrum stream, application payload codec
                or negotiated WebSocket compression; verify that scope against the protocol and
                implementation. HTTP content coding is only the bounded12.1.1 exception, verified
                separately by TC-009-005 case8; this does not replace the existing cold/status tests. Missing browser, simulator
                or measurement prerequisites MUST fail verification rather than silently skip it.

             **Stalled-reader variant — inputs/actions and expected results:**

             1. Connect a peer that stops reading and has automatic Pong replies disabled. Send a
                bounded burst of read-only status requests; concurrently query a healthy peer and
                expect its response within the connected-response limit.
             2. Keep the first peer unresponsive past the Pong deadline plus heartbeat-tick bound,
                then resume reads. Expect its connection to close and the healthy peer to remain usable.
                This verifies bounded liveness removal and isolation; it does not prove that kernel
                buffers filled, the send-timeout branch executed or total process memory was measured.

             **Oracle:** independently timed link simulator, browser-visible updates and
             [resource/liveness rules](StationProtocol.sysml).
             **Executable trace:** [communication.test.cjs](../../tests/communication.test.cjs),
             `TC-021-008: 32 kbit/s shared TLS link and 60-second idle budget` and
             `TC-021-008: stalled reader cannot block another client`.
             The measurement report is `test-results/link-budget.json`. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-003-01';
            verify 'CL-003-02';
            verify 'CL-003-05';
            verify 'CL-003-06';
            verify 'CL-003-08';
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
             Also hold a Refresh GET response, begin and hold a PUT, then release the GET while the
             save remains pending. Save stays disabled and even a repeated form submission sends
             no second PUT. Release the PUT: exactly one revision advances, editable controls and
             Save recover their usable state, and permanently read-only controls remain disabled.
             Repeat with the opposite response order on an unchanged revision-0 station: hold the
             Refresh response, complete the PUT and its follow-up revision-1 GET, then release the
             old response. Visible revision, saved fields and acknowledged-save feedback remain at
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
             `native_flex` and require `unsupported_connection_type`, without an attempted radio
             connection or a change to the standard profile's stored settings.
             Each invalid launch fails nonzero with the defined category and no listener or file rewrite;
             others remain usable. Restore the original bytes and restart successfully. During a
             save inject a deterministic denied-write/atomic-replace failure in disposable storage:
             no acknowledgement, no revision advance, previous complete JSON and current settings
             remain authoritative. At crash-before/after-replacement fault points require either
             complete old or complete new JSON, never a partial file; a lost response is reconciled
             by GET without replay. After a lost save response, ordinary Refresh/background GET or
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
             with disabled control, but creates no grant/commission or native effects; explicit
             removed/null scope cannot be invented or auto-added. Fetch GET `/profile` using
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
             On an established socket hold GET /profile behind a controlled barrier, click Refresh,
             observe its actual correlated WebSocket status and require changed visible updated plus
             enabled Refresh within 2 seconds before releasing HTTP. Repeat Refresh while held: only
             one GET is in flight and one follow-up eventually obtains an independently saved newer
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
             independently specified protocol fixtures, not packets generated by the code under test. */
        attribute automation : AutomationState = AutomationState::planned;
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

             **Inputs/actions:** Save intended radio/slice associations, disconnect/restart the
             emulated radio and assign different runtime handles before reconnecting. Also present
             missing, ambiguous or occupied intended resources and stale status updates.

             **Expected results:** Each profile reconciles its intent with current authoritative
             resources; transient indices do not route it to another station. Unresolved intent is
             reported as unavailable/conflicting without stealing a resource, replaying transmit
             requests or accepting stale handles as authority. */
        attribute automation : AutomationState = AutomationState::planned;
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
             same browser and shared station-operation interfaces, with no cross-profile routing. */
        attribute automation : AutomationState = AutomationState::planned;
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
             Existing independently calibrated shared TLS link: 4000 bytes/s each direction, 150 ms one-way, two real browsers. After upload/page load, replay >=60 s with both thin; issue paired status refresh at ten preselected source times. Repeat off; stall one reader, replace/cancel job and reconnect. Separately upload while refreshing.
             Over 60 steady-state seconds thin total <=3000 accounted bytes/s each direction and every connected refresh displays <=2 s; off preserves existing <=1000 idle budget. No >1 frame/s/peer, >1024-byte event or >1 pending optional frame; no raw audio streaming. Missing rows are gaps, obsolete frames ignored, reconnection obtains snapshot before subscription. Upload bytes/time and cold asset metrics are reported separately; upload must not break status<=2 s. Counter oracle is simulator's actual-stream+defined overhead, not physical-link certification. */
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
             Detail events have exact schema,1024 decoded bytes, canonical1368-char base64 and<=2048 UTF-8 bytes; exactly-at-limit values accepted and malformed/obsolete input leaves canvas/history unchanged. At most 1 Hz Thin and, for Detailed, 5 rows/s steady with catch-up of retained rows at most 5.9 rows/s (#54 TransferDisplay); no second worker. Thin/control input1024 and binary1003 guards preserved. Optional write test independently requires readiness/control priority,4096 cap,1024+28 control reserve, unchanged2s removal from first pending write; Detailed fast-link status responses display<=2s on unshaped localhost with two peers. TC-010-002 unchanged TLS32kbit/s Thin/Off regression still runs. Every origin defaults Detailed; explicit saved Thin/Off is honored and fallback attempts Thin once and labels unavailability. Pixel oracle computes integer edges/fixed source-time cell edges from contract, samples interiors and both sides of boundaries for exact palette colors/uniform cells, using independently calculated RGB interpolation/rounding from the stated anchors, with grey gaps and dark unobserved areas on a full-height canvas; no blended spatial colors. New rows enter at top; Auto ignores median0 then locks once at median-3dB, manual Black/Range disables it, job/profile reset restores30dB/Auto and original calibrated data remains invariant. Frequency500/100Hz ticks and visible source-time5s ruler agree with pixel/readout positions and clipping. Fixed0..3000Hz axis endpoints/ticks through resize/DPR/zoom, no horizontal frequency scroll, unmodified native1024-value buffer, peak-preserving max projection with every bin contributing at widths below1024, native/projected readout centers/ranges/levels/intervals, keyboard selection, recent-row orientation,600-row cap and no page overflow hold through geometry changes. Thin uses the same integer geometry with128 bins; original numerical/wire values stay unchanged. A narrow strong tone at every native-bin position contributes to its assigned column and never disappears when W<B. Screenshots establish actual layout and independently synthesized data establishes numerical correctness.  Preference persistence: with disposable browser storage and actual server/Chromium, verify unchanged defaults without a valid choice; explicit Detailed/Thin/Off survives reload and reopened browser context; origins/ports and profile UUIDs are isolated while boot/revision changes preserve choice. Invalid value or denied storage uses normal defaults without page error and leaves in-memory selection usable. Inspect only versioned UUID keys and enumerated values, with no secrets. Unknown-command runtime Thin fallback preserves stored Detailed; subsequent explicit Thin replaces it. Existing subscription commands, no retry loop, Detailed bounds and Thin32kbit/s tests remain unchanged; no synthetic decoded records are used. */
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
             Independent oracle: palette endpoint/saturated cells are exactly[255,0,0,255], floor/no-signal[0,0,12,255], no white signal cells; legend uses identical RGB anchors/endpoints. With the fixed reference B=-85 and R=50 (#54), g=+10 yields E=-95 and g=-30 yields E=-55, clamped[-120,-R]; original row arrays, source/job/generation and curve base scale stay unchanged. No setting follows the signal or resets on a new job or profile; Sensitivity, Range and Speed persist per browser. Fixed source-time scrolling, independent pixel movement, clipping, gap and unobserved-region oracles are specified in TC-010-007. Native/projected readouts and rulers agree with that mapping. Spectrum/waterfall CSS heights follow1:5 within2CSSpx rounding, actual bitmap sizes equal rounded CSS boxes times DPR, neither geometry nor intrinsic height drifts over repeated paints. No horizontal overflow/changed0..3000Hz span, interpolation, fake history or network/source-rate change. Real FT8 screenshots show a full-height waterfall canvas with unobserved regions dark, dark floor, red strongest traces and visible working live sliders; original numeric/wire/security/Thin32k assertions remain. */
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
             With p=10*v and newest end T, independently calculate each row edges floor((T-b)*p*H/C)..floor((T-a)*p*H/C); a fixed mark advances by2*v CSSpx per Detailed update or10*v per Thin update, independent of N. Minimum speed0.5 gives5CSSpx/s, half Speed1; default2 gives20CSSpx/s. It exits below H and never sticks or repeats. Empty/unobserved pixels are exactly navy with no-measurement readout; explicit gaps grey. Changing height changes capacity C/p, not pixels per source second; changing speed changes displacement without modifying tuples/data/network. Short EOS uses actual duration; no source row means no motion; stale/invalid frames cannot move history. Pointer native/projected intervals, keyboard clamps and5s rulers match the same time mapping. Existing sliders remain visible and keyboard-operable; actual canvas remains full allotted height, spectrum:waterfall1:5 and fixed0..3000Hz. Existing palette/sensitivity, wire/numerical and Thin32kbit/s assertions remain unchanged. */
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
             controls are disabled and produce no requests. Open/close saved settings and recording
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
        attribute automation : AutomationState = AutomationState::partial;
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
             is the edited list, and no receive start, stop or selection; accept_commands is not
             offered for a multicast address; a refusal shows its code and field and keeps the
             edits; the accept_commands warning and each target's status are shown. An IPv6
             group target [ff12::5754:5358]:2237 (#46, CL-040-06) is not offered
             accept_commands, shows the hop-limit/interface-index hint naming the link-local
             need, and saves with the TTL field as hop limit 2 and interface "1"; the same group
             without an interface is refused with targets[0].multicast_interface.
             Compact QSO pane (#37, QsoPane): with a running QSO at 1366x768 the pane shows the
             header, the last partner message "HB9BLA IW9FRA RR73  +17 dB ×3", the QSO
             dialogue as the #60 table (ten entries, oldest first, scrolling inside the card at its newest
             row) and below it the Others as ⚠ rows of the same table oldest first (only
             stations calling me within +/-50 Hz of Rx 1500 Hz or Tx 2100 Hz, not the partner,
             not a station near neither, no DT/frequency; "nobody else calling" when none),
             NEXT "▸ next:
             <message>" while armed, and the buttons, all inside the pane (not clipped), the
             pane content without the QSO area at most 250 px high (the earlier pane needed about 380 px for the
             same contact); item 8 (#60, operator 2026-11-03): the pane height equals its content
             height (within 3 px), at most 300 px at 1366x768, at the top of its column, the QSO
             area at most its header row and 6 rows; at 1920x1080 the area is the header row and
             6 rows, the pane at most 340 px, and the Control panel and the error field follow
             below it (#37 LowerPanel, TC-037-001); there is no LAST row or
             crowding badge; double-clicking an Others line sends select_row with replace true
             then enable_tx. Idle, every station calling me is a table row "HH:MM:SS | <my call> ◂ <caller> | <exchange> |
             <SNR> |" (no CQ, even near Rx) whose double-click sends select_row then enable_tx. When the contact is
             completed (Log QSO or completion) the pane shows "✓ Logged <call>", no NEXT and
             no partner lines, and after loggedNoticeSeconds only the idle pane; a cancelled
             contact is gone at once. At 360x800 nothing overflows horizontally.
             Independent oracles: the design-interview decisions in the
             model, not the candidate markup. Screenshots at 1366x768 and 360x800. */
        attribute automation : AutomationState = AutomationState::partial;
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
             native/CI-V fixtures and the existing encrypted-link model. This is planned coverage,
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
                manual fallback. Include actual allowed8s passive/4s pending Thin/Off selection
                polls, normal receive/results/status, mode/band traffic, stalls and explicit Stop
                in the existing two-browser32kbit/s TLS workload. Assert each-direction mean<=3000B/s,
                visible status<=2s, one pending selection read/ordinary mutation, status/control
                priority and no backlog. Detailed2s/500ms is separately labelled fast-link coverage.

                Cadence evidence classifies actual interval dispatch separately from explicit user/
                reconciliation reads using recorded CDP initiators and the caller mapping derived
                from the served client source (its single selection fetch, its single interval-timer
                caller, every other caller explicit; a missing, ambiguous or unmapped site refuses),
                joined to validated request/response identity. A pending-context pair is
                the last accepted pending snapshot for commandX followed by an automatic interval
                GET while that remains the accepted state, with matching station/profile/boot,
                saved-profile/operating revision and command context, sequential actual transport,
                and no intervening accepted snapshot or unrelated mutation/identity change. Its
                successor may report pending OR terminal for commandX; a fresh receive job/generation
                produced by that same command is permitted. Explicit reconciliation never supplies
                positive automatic-cadence coverage; a broad gesture-time exclusion cannot hide
                an interval request.

                Every measured command/browser must really observe pending at least once and finish
                its fresh known-answer CQ context. For EACH browser in EACH unchanged75s Thin/Off
                window, require at least one actual automatic pending-context pair with start gap
                >=3950ms and<7950ms and at least one automatic passive-context pair with gap>=7950ms.
                The50ms observation tolerance checks the existing4000/8000ms gates; the pending
                upper bound is only a fixture coverage discriminator proving the faster regime,
                not a new maximum product dispatch latency. Priority may lawfully defer a poll.
                ALL classified automatic pairs retain the applicable pending>=3950ms or passive
                >=7950ms lower spacing; a terminal successor does not retroactively reclassify
                its dispatch as passive. Record starts/completions, prior accepted state, timer
                provenance, identity and successor outcome. Missing coverage fails rather than
                fabricating pending values or forcing a legal short command to last longer.
                Frozen negative controls accept pending->terminal and pending->pending in context;
                reject<3950ms, passive-at4s, wrong command/identity, explicit-only, overlap and
                missing qualifying pairs in either browser/window. Preserve all five CQ contexts,
                two transitions/window,26 status refreshes, original bytes/deadlines/Off ACK/frame
                oracles and all75s windows; no product delay, padding or traffic reduction.

             8. Bounded HTTP content coding12.1.1 (same cost2 boundary):
                A. Real application/router + normal TLS/session: authenticate once through existing /session; for each allowlisted successful GET gzip decode must equal identity logical JSON exactly on immutable state, exact shape/caps preserved. Use independent standard decoder (Node zlib) and assert actual raw gzip magic/header/trailer + body rather than fetch auto-decoded size. Check Content-Type/Vary/Content-Length correctness; existing Vary/cache/security headers retained. Mutable facts compare frozen fixture context, never pretend two temporally distinct snapshots must match timestamps.
                B. Table: absent/empty, identity, gzip, GZip case-insensitivity, gzip;q=0, gzip;q=0.5 vs identity;q=1, identity;q=0 with gzip acceptable, br-only, wildcard and explicit exclusions, invalid q/token/multiple header instances. Expected outcomes are frozen in the ordered12.1.1 negotiation table from the pinned source; malformed headers must follow the frozen ordered12.1.1 negotiation table without panic/leak; duplicate/wildcard selection follows the exact table, not a blanket last-q or any-q0 rule. Both gzip+identity explicitly forbidden=>406 only eligible successful GET. Preserve original401/403/404/400/409/500 on excluded error paths even with forbidden encodings.
                C. Every excluded method/path including POST/session, PUT/profile, POST/receive/select and /radio operations remains unencoded and byte/schema compatible; no duplicate mutation effects. Authenticate cookies/tokens never appear in body/debug logs. Authenticated eligible snapshots contain no credential fields; malicious literal decoded text is unchanged. Oversized logical result rejected/capped BEFORE gzip, encoded size cannot admit extra rows; valid max logical result still decodes within original cap. Request Content-Encoding:gzip must not add support or bypass request body limit. HEAD/no-body/range/already-encoded cases must not be double-compressed or misframed.
                D. Actual two Chromium browsers on unchanged shared4000B/s/direction+150ms TLS model, actual native FT4/FT8 + CAT transitions and mode-appropriate fixtures, actual status, pending/passive reads, records and source/operation identities. Preserve all Thin75s/Off75s windows and >=60 checks, five CQ records, status/pending/cadence/original WS oracles. Record Content-Encoding from real response headers, raw encoded sizes via CDP as attribution, and unchanged actual proxy TLS/model counters as sole bandwidth oracle; BOTH directions <=3000B/s and existing Off requirement, all status<=2s. No arithmetic compression estimate counts as PASS. Run original14+new15 suite through ordinary integration/prepush as selected; separate old10s Connected-after-load remains required. Identity path correctness is mandatory; identity workload bandwidth remains unproven unless separately measured.
                The pending/passive cadence proof in7 applies unchanged to8D: an automatic poll
                dispatched from the last accepted pending state may return terminal completion
                for the same command. Preserve per-command pending observation and per-browser/
                profile positive4s and passive8s evidence, exact initiator/identity correlation,
                all lower spacing and negative controls; do not demand two pending-valued replies.
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
        attribute executable : String = "tests/radio-selection.test.cjs; server/src/selection_http_tests.rs; server/src/radio_http_tests.rs; server/src/http_compression_tests.rs";
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
               page/record sizes, single pending/cadence and combined32kbit/s regressions remain.
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
    dependency CL_003_01_verified_by_TC_021_008 from 'CL-003-01' to 'TC-021-008';
    dependency CL_003_02_verified_by_TC_021_005 from 'CL-003-02' to 'TC-021-005';
    dependency CL_003_02_verified_by_TC_021_008 from 'CL-003-02' to 'TC-021-008';
    dependency CL_003_03_verified_by_TC_021_005 from 'CL-003-03' to 'TC-021-005';
    dependency CL_003_04_verified_by_TC_021_006 from 'CL-003-04' to 'TC-021-006';
    dependency CL_003_04_verified_by_TC_021_007 from 'CL-003-04' to 'TC-021-007';
    dependency CL_003_05_verified_by_TC_021_008 from 'CL-003-05' to 'TC-021-008';
    dependency CL_003_06_verified_by_TC_021_008 from 'CL-003-06' to 'TC-021-008';
    dependency CL_003_07_verified_by_TC_021_009 from 'CL-003-07' to 'TC-021-009';
    dependency CL_003_08_verified_by_TC_009_005 from 'CL-003-08' to 'TC-009-005';
    dependency CL_003_08_verified_by_TC_021_007 from 'CL-003-08' to 'TC-021-007';
    dependency CL_003_08_verified_by_TC_021_008 from 'CL-003-08' to 'TC-021-008';
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

    doc /* Issue22 contract. Delivered (partial): CL-022-01 persistent browser key,
         enrollment, challenge/proof transport, retained-key recovery and the
         browser Log out / forget-rejected-credential actions; CL-022-02 durable
         private record, revocation (logout, revoke-all), dispatch fencing of every
         operating HTTP/WS effect under the authority lock, safety-revision
         advance and the commissioning server API (POST /authorization/v1/commission
         and the status condition). Delivered (partial, before live acceptance):
         CL-022-03 'Confirm receive-only setup' UI and the automatic read-only CAT
         lifecycle, CL-022-04 cadence, CL-022-05 CAT status/freshness presentation;
         TC-022-009 automated companions. Still target: CL-022-02 explicit radio
         identity Add/Replace/Remove (ChangeSelectedRadioIdentity, no route yet), the
         CL-022-05 dated freeze reproduction and Thin/Off accounted-traffic companion;
         TC-022-008 and TC-022-010 stay planned.
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
        attribute coverage : ImplementationState = ImplementationState::partial;
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
             Explicit Add/Replace/Remove uses WstxProfiles::ChangeSelectedRadioIdentity,
             not an inferred control-settings edit. Fresh bootstrap alone grants no
             control: ReadBootstrapScope provides its read-only authority tuple before
             enrollment. Add only from absent scope; Replace/Remove require exact current
             scope. Add/Replace assign new UUID/revision1, remove leaves absent scope;
             both invalidate old grants/commissioning atomically after confirmed native
             release, with bounded operation receipt and no automatic mutation replay.
             Subsequent enrollment/commissioning is required; disabled/re-enable alone
             never removes or replaces identity. Endpoint/model/PTT edits
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
             Explicit Add/Replace/Remove remains target.
             Accepted bound: an operating HTTP request is admitted by validating its
             transport (scope, grant, current revocation generation) under the authority
             lock; the lock is then released. Such an admitted request may still be
             queued (body parsing, the recording/native owner lock, the blocking pool)
             when a revocation commits. It is not re-checked, refused or undone: at most
             one in-flight effect per admitted request follows, under the existing
             cancellation/release rules. Every request admitted after the commit is
             refused, and the affected WS closes before its next message. */
        attribute coverage : ImplementationState = ImplementationState::partial;
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
             buttons. CAT disabled remains disabled. No serial enumeration/fallback.
             Missing/revoked/mismatched grant, missing/invalid commissioning, disabled
             CAT and corrupt authorization store cause zero automatic native open,
             query, setter or PTT bytes. One matching unrevoked grant plus valid
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
             acceptance (TC-022-010) remains outstanding.
             Reconnect restores the selection (operator finding 2026-11-02, another
             program held the port and released it): when the lifecycle's eligible
             connection becomes Ready with a confirmed fresh dial while the selection
             band is unknown, the station adopts that dial as the selection exactly as
             WstxOperatingReceive S1 ReadbackSelectionAdoption states (exact preferred
             entry of the station operating mode for one band, origin cat_readback,
             read-only, no receive restart, no revision advance, never replacing a known
             selection), so no band choice by hand is needed after startup or a
             reconnect. */
        attribute coverage : ImplementationState = ImplementationState::partial;
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
        attribute coverage : ImplementationState = ImplementationState::partial;
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
             stream; reuse versioned status publication/heartbeat. Existing Thin/Off
             32kbit/s accounted-traffic regressions include new auth/recovery/status
             messages, explicit errors and multi-peer recovery. Issue10 existing
             continuity/stale fixes are reused; this proposal adds no duplicate helper.
             Actual dated freeze reproduction/root-cause trace remains outstanding.
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
             program'); other unavailable causes keep radio_unavailable. Still target:
             Thin/Off accounted-traffic companion
             including these status reads (TC-022-008) and the freeze trace. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/authorization_http.rs; client/recording.js; client/authorization.js; client/app.js";
    }
    dependency CL_022_05_to_FR_003 from 'CL-022-05' to 'FR-003';
    dependency CL_022_05_to_FR_010 from 'CL-022-05' to 'FR-010';
    dependency CL_022_05_to_FR_021 from 'CL-022-05' to 'FR-021';
    verification 'TC-022-006' {
        doc /* TC-022-006, CL-022-01/02; cost2 profiles/protocol companions
             using existing TLS/browser helpers. Fresh-browser initial journey: POST
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
             challenge-response396, conservative receipt302 and bootstrap response440
             with BOTH current and receipt scopes. Require actual compact serialization
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
             Removed scope returns null; no implicit Add/enrollment. Authorize A once; preserve ordinary
             browser profile/key, close actual browser process, remove/expire only its
             transport cookie under test control, advance injected times across28800s
             and browser-cookie retention boundary, restart server/browser. A becomes
             usable through signed proof with zero bootstrap submissions; no long real
             wait claimed. Test retained identity/revision vs Add/Replace radio, other
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
             browser): hold the first bootstrap-scope response past its 10 s bound;
             the status shows 'Retrying authorization' and becomes connected after one
             token press with one session, two bootstrap-scope and one enrollment.
             A network-failed enrollment is repeated once with the identical operation
             ID and verifier and connects. Network failure of every /session
             attempt stops after exactly 3 attempts with 'Could not authenticate'.
             A 401 bootstrap-scope is never retried. Navigating away during a held
             attempt sends no further setup request.
             Automated companions: tests/profiles.test.cjs TC-022-006 cases and
             server/src/auth_tests.rs, including plaintext runtime-token operating
             access. Radio identity Add/Replace and injected-time restart subsets
             remain pending. */
        attribute automation : AutomationState = AutomationState::partial;
        attribute executable : String = "tests/profiles.test.cjs; server/src/auth_tests.rs";
        objective {
            verify 'CL-022-01';
            verify 'CL-022-02';
        }
    }
    dependency CL_022_01_verified_by_TC_022_006 from 'CL-022-01' to 'TC-022-006';
    dependency CL_022_02_verified_by_TC_022_006 from 'CL-022-02' to 'TC-022-006';
    verification 'TC-022-007' {
        doc /* TC-022-007, CL-022-02; cost2 profiles/protocol and station authority companions.
             With independent durable-state/native-peer oracles exercise explicit
             radio-identity add/replace/remove and bootstrap-scope receipt recovery.
             Add with present scope, replace/remove with absent/stale scope, ordinary
             transport without bootstrap and cross-profile context refuse with no state
             commit/native bytes. Disable/re-enable and endpoint edit preserve UUID;
             endpoint change advances safety revision/invalidates commissioning only.
             Replace at identical endpoint yields different UUID and no inherited
             grant/commissioning; Remove yields null current scope and zero CAT attempts
             despite saved enabled settings. Explicit Add creates another UUID; no
             timer/settings edit auto-Adds. Hold close/fail close: no identity commit,
             quarantine never clears on retry. Fail atomic write: no acknowledged new
             identity; inspect last committed record. Lose response after commit/restart,
             bootstrap again and query same operation receipt: one UUID allocation,
             old grants deleted, no repeated mutation or queued CAT effects. Contrast
             precommit failure/evicted receipt with409 unknown, never claimed success.
             A setup receipt cannot satisfy verifier proof/receipt or grant authority.
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
             Automated: server/src/auth_tests.rs (logout/revoke fencing of every
             operating HTTP route and WS upgrade, foreign grant refusal, commission
             receipts) and station-authority unit tests; tests/profiles.test.cjs
             TC-022-004 covers browser logout and revoke-all. Radio identity
             add/replace/remove cases remain pending with that target slice. */
        attribute automation : AutomationState = AutomationState::partial;
        attribute executable : String = "server/src/auth_tests.rs; server/src/authorization_tests.rs";
        objective {
            verify 'CL-022-02';
        }
    }
    dependency CL_022_02_verified_by_TC_022_007 from 'CL-022-02' to 'TC-022-007';
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
             Dated real freeze
             reproduction and cause tracing remain separate required evidence, not
             replaced by this constructed case. Existing issue10 barriers/unknown state
             assertions remain. Add auth recovery to existing Thin/Off accounted-traffic
             companion tests/recording.test.cjs TC-010-002 and communication tests;
             same ceilings/windows/controls, no assertion or source-pin weakening.
             Automated: tests/profiles.test.cjs TC-022-008 (the original freeze
             reproduction: transport cookie lost under an OPEN WebSocket without
             reload; the 401 read ends 'Connected' within2s, retained-key proof
             reconnects with one OPEN socket and zero token/session/enrollment, every
             status read is POST {"version":1} with the exact page Origin) and
             server/src/auth_tests.rs (status GET405, wrong and missing Origin403
             before auth, strict body/media/size refusals, unknown transport401).
             Still planned: the Thin/Off accounted-traffic companions
             tests/communication.test.cjs and tests/recording.test.cjs TC-010-002; same traffic windows and ceilings. */
        attribute automation : AutomationState = AutomationState::partial;
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
        attribute executable : String = "server/src/cat_lifecycle_tests.rs; server/src/auth_tests.rs; tests/radio-selection.test.cjs";
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
             remains released; zero transmit acceptance is added. Missing physical
             cases/freeze evidence remain missing. Independent source/model review,
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
        doc /* MCP authorization is explicit and separate from the browser (#58): exactly one Authorization: Bearer field carrying an MCP client token of this station, created and revoked in Settings > General > Access & grants, shown once, stored only as its SHA-256 and compared in constant time; cookies sent to /mcp are never read, the station access token and browser grant transports are refused with a hint to the MCP client token, an MCP token is refused on every browser route and never exchanged for a browser cookie or grant, revocation takes effect at the next request, refused bearers are rate limited and every use is audited (name, action, time). Every request carries its principal (browser, mcp, udp, automation) from its credential; only browser is an operator action. A plaintext profile has no MCP access, a present Origin must be the station's. Transmit-capable operations need the MCP client's station transport like the browser's grant. Automation is station-owned, unconfigured and stopped at every boot, starts only on an explicit start with a current grant transport and the current acknowledged safety revision, lives no longer than that transport and its maximum duration, is shown read-only in the browser station bar, never takes over an operator's CQ or contact, and stops at Halt (also one racing its arming, answered with a Halt), explicit stop, lost or replaced transport, receive context or mode change, contact change, disarm, no answer, completion or its contact limit, never replaying a transmit action or leaving a selected unarmed contact. Details: WstxMcp::McpCredential, OperatingAutomation, AutomationIndicator. */
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
        doc /* Any number of targets up to 16, each address:port (unicast, IPv4 multicast with TTL and interface, or IPv6 multicast per CL-040-06), enabled, a per-type outbound message selection (default all) and accept_commands (default off), with per-target status (last send, error, last inbound command). The configuration is persisted in the selected profile directory and served by GET /udp and PUT /udp; the default is one target 127.0.0.1:2237, enabled, accept_commands off, instance name WSTX-Rust. Details: WstxUdp::UdpTarget, UdpConfiguration, TargetStatus, UdpHttp. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs; server/src/profile.rs; server/src/main.rs";
    }
    dependency CL_040_02_to_FR_012 from 'CL-040-02' to 'FR-012';
    dependency CL_040_02_to_FR_001 from 'CL-040-02' to 'FR-001';
    requirement 'CL-040-03' {
        doc /* Halt Tx from any source always acts as the HALT button (HaltTransmit), whether or not accept_commands is on. Clear, Reply, Replay, Free Text and Highlight Callsign act only from a target with accept_commands on and only on datagrams whose source is that target. No inbound command keys the transmitter: Reply prepares the QSO like a single click (ContactCommand select_row, no transmit authority) and Free Text sets the Tx5 text of a prepared contact (as the browser edit: a standard, nonstandard or free-text message of at most 13 characters, #24 CL-024-01); both are refused while Enable Tx is on, and the Send flag is ignored. A datagram too large for the receive buffer is dropped, counted and never holds back the datagrams behind it. Details: WstxUdp::InboundRules. */
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
    requirement 'CL-040-05' {
        doc /* Location (11) from a target with accept_commands on and from that target's address, carrying a 4- or 6-character Maidenhead grid (longer text only after a "GRID:" prefix), sets a session-only station grid: it replaces the profile locator for the Status DE grid, the generated messages and the logged my_gridsquare until the station restarts, and is never saved to the profile. An invalid location is refused invalid_grid and changes nothing. Details: WstxUdp D5, InboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs; server/src/contact_http.rs; server/src/logbook_http.rs";
    }
    dependency CL_040_05_to_FR_012 from 'CL-040-05' to 'FR-012';
    verification 'TC-012-005' {
        doc /* TC-012-005 — Session location
             CL-040-05
             Setup: actual candidate router, UDP owner, contact engine and #9 transmit owner on the recording hardware double (profile HB9BLA, JN47AA); target A accept_commands off and C on, loopback peers; an injected FT8 live job with the row "CQ K1ABC FN42" 1234.6 Hz -12.4 dB at 12:34:30.
             Steps: (a) pure rule table: "JN47", " jn36ab ", "GRID:JN36AB", "grid: fn42", and "", "XX", "JN4", "JN47A", "JN47AA11", "47.1,8.5", "LOC:JN47AA", "ZZ99"; (b) one step; Location "JN36AB" from A; "XX" from C; "GRID:JN36AB" from C; step; Reply to the CQ row from C; POST /contacts with my_gridsquare JN47AA, then JN36AB; read profile.json; open a new owner.
             Expected: (a) JN47, JN36AB, JN36AB, FN42, the rest refused; (b) first Status DE grid JN47AA; A not_accepted; XX refused invalid_grid with no Status; GRID:JN36AB applied and one Status with DE grid JN36AB; Tx1 "K1ABC HB9BLA JN36" and Tx6 "CQ HB9BLA JN36"; the JN47AA log record refused 400 log_invalid_field record.my_gridsquare and the JN36AB one 201; profile.json and the store keep JN47AA; the new owner has no session grid; PTT never keyed.
             2 — Isolated automated functional tests; Windows development PC, loopback UDP only, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-040-05';
        }
        attribute executable : String = "server/src/udp_tests.rs";
    }
    dependency CL_040_05_verified_by_TC_012_005 from 'CL-040-05' to 'TC-012-005';
    requirement 'CL-040-06' {
        doc /* Issue #46: an IPv6 multicast group target (ff00::/8) with a hop limit 1..255 (multicast_ttl) and an interface index (multicast_interface as decimal text, required for interface-local and link-local scope, optional above) is admitted by PUT /udp, saved, and receives its selected outbound messages through a socket with IPV6_MULTICAST_HOPS and IPV6_MULTICAST_IF set. Reserved scopes 0 and 15, interface names and accept_commands on are refused; inbound commands from a host to its socket are not accepted, as for IPv4 multicast. Details: WstxUdp D6, UdpTarget, OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs";
    }
    dependency CL_040_06_to_FR_012 from 'CL-040-06' to 'FR-012';
    verification 'TC-012-006' {
        doc /* TC-012-006 — IPv6 multicast targets
             CL-040-06
             Setup: actual candidate router and UDP owner on a disposable profile; a peer socket joined to the transient link-local group ff12::5754:5358 on the Windows loopback pseudo-interface (index 1); a host socket on [::1].
             Steps: PUT, each alone: scope 0 ff00::1, scope 15 ff0f::1 and ff1f::1, the group without an interface, ff01::1 without an interface, hop limit 0 and 256, accept_commands true, an IPv4 group with interface "1", interfaces "0", "01", "-1", "+1", " 1", "4294967296", "Ethernet", "127.0.0.1", "::1", "" and the number 1; then one PUT of the group at the peer's port with hop limit 2 and interface "1", [ff05::5754:5358]:2237 hop limit 255 interface "1", [ff15::5754:5358]:2238 interface "4000000000", and a disabled [ff08::5754:5358]:2239 without an interface; open a new owner; PUT the list plus a disabled [::1]:2240 with interface "127.0.0.1", then with "1"; read the socket options; one station step; Free Text from the host to the group target's socket; step.
             Expected: each refusal 400 invalid_request with its field (address for the scopes, otherwise the named field) and nothing saved; the PUT admitted with the targets saved as given and unchanged after the reopen; the IPv6 unicast target with "127.0.0.1" admitted and with "1" refused targets[4].multicast_interface; the group socket has hop limit 2, interface 1 and loopback on, the site-local one hop limit 255; the unknown index shows active false, socket_unavailable; the joined peer receives Heartbeat then Status (schema 2, id WSTX-Rust); the Free Text is not_accepted.
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
    requirement 'CL-040-08' {
        doc /* Issue #40: an inbound Highlight Callsign (13) or Clear (3) that a target with accept_commands on applied (CL-040-03) changes the browser's display as WSJT-X 3.3 applies them (widgets/displaytext.cpp DisplayText::highlight_callsign; Clear window 0 Band Activity, 1 Rx Frequency, 2 both): the station announces the current highlights and clear floors to every display-subscribed browser (udp.display), Band Activity colours the rows of a highlighted call with its background and foreground (Highlight last: only rows of the period of the latest decode when it arrived; a call with no valid colour is reset; CLEARALL! removes all), and Clear hides the decoded rows below its floor in Band Activity (window 0, 2) and in the QSO pane's callers that replace the Rx Frequency window (window 1, 2) until later decodes arrive. A UDP highlight marks a station of interest by definition: it colours a row that matches no slot and wins over the Band Activity colour slots (#50 CL-050-02, operator 2026-11-04; the QSO partner marker stays on top, CL-050-08). A target without accept_commands changes nothing. Details: WstxUdp::InboundRules, UdpDisplayEvent; WstxOperatingLayout::BandActivityColours. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/udp.rs; server/src/main.rs; client/recording.js; client/contact.js";
    }
    dependency CL_040_08_to_FR_012 from 'CL-040-08' to 'FR-012';
    verification 'TC-012-008' {
        doc /* TC-012-008 — Highlight Callsign and Clear in the browser
             CL-040-08
             Setup: (a) actual candidate UDP owner on a disposable profile with loopback peers A (accept_commands off) and C (on), an FT8 live job with period P1 (CQ K1ABC FN42, CQ W1AW FN31); (b) the actual candidate router, contact engine and UDP owner started with no target, the browser, and two loopback peers that the test configures through PUT /udp (other: accept_commands off, tool: on) and whose datagrams it packs by hand.
             Steps: (a) from A Highlight K1ABC and Clear; from C: "k1abc" red on white; W1AW green Highlight last; publish P2 (K1ABC W1AW -05); W1AW blue Highlight last; W1AW foreground yellow only; K1ABC without colours Highlight last; K1ABC without colours; " " and "0"; CLEARALL!; Clear window 1; Clear window 2; read the udp.display event. (b) publish P1 (CQ K1ABC FN42, CQ W1AW FN31, HB9BLA DL1XYZ JO62); from other K1ABC red; from tool W1AW green Highlight last without foreground, "dl1xyz" blue on yellow; publish P1+15 s (CQ W1AW FN31, HB9BLA DL1XYZ R-05); DL1XYZ without colours Highlight last; DL1XYZ without colours; K1ABC magenta, then the page given another boot_id and back, then K1ABC without colours; Clear window 1; Clear window 0; publish P1+30 s (CQ K1ABC FN42).
             Expected (hand table from DisplayText::highlight_callsign): (a) A not_accepted, nothing listed, display revision 0; K1ABC listed upper case with period null; W1AW last-only with period P1, then replaced by blue with period P2; the map entry W1AW (background null, foreground #ffff00) replaces the last-only one; the K1ABC reset is a last-only entry with period P2 beside its map entry; the K1ABC removal removes both; " " and "0" ignored without a revision change; CLEARALL! empties the list; window 1 sets only rx_frequency, window 2 both, at the next sequence 3 of the live job; the event is exactly {v 1, type udp.display, data {profile_id, boot_id, display_revision, highlights, clear}}. (b) the other target is not_accepted and K1ABC keeps its look; the P1 W1AW row green with its own text colour; the DL1XYZ row blue on yellow instead of the My call slot; in P1+15 s W1AW uncoloured while P1's stays green, DL1XYZ blue; the last-period reset uncolours only the P1+15 s DL1XYZ row (My call slot) and P1's stays blue; the removal gives both DL1XYZ rows the My call slot again; under another boot_id K1ABC shows its own look, back under the station's boot it is highlighted; window 1 empties the QSO pane callers and keeps the five Band Activity rows; window 0 empties Band Activity; the later decode is the one row shown; no page error.
             2 — Isolated automated functional tests; Windows development PC, loopback UDP on ephemeral ports only (never 2237), no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-040-08';
        }
        attribute executable : String = "server/src/udp_tests.rs; tests/contact.test.cjs; server/src/contact_http_tests.rs";
    }
    dependency CL_040_08_verified_by_TC_012_008 from 'CL-040-08' to 'TC-012-008';
    verification 'TC-012-001' {
        doc /* TC-012-001 — NetworkMessage wire vectors
             CL-040-01, CL-040-03, CL-040-04
             Setup: hand-constructed byte vectors in server/tests/vectors/udp/, each written field by field from WSJT-X v3.3.0-beta5 NetworkMessage.hpp (SHA-256 b640a632...) with the construction steps recorded in the file, independent of the encoder.
             Steps: encode Heartbeat, Status, Decode, Clear, QSO Logged, Close and Logged ADIF from the vector inputs; parse the inbound vectors (Heartbeat with and without maximum schema, Clear with window, Reply, Replay, Halt Tx with and without Auto Tx Only, Free Text, Location, Highlight Callsign with valid and invalid colours, Switch Configuration, Configure, an unknown type, trailing bytes); parse every refused vector (wrong magic, schema 1 and 4, truncated utf8, null id, 4097 bytes).
             Expected: encoded bytes equal each vector exactly; parsed fields equal the vector's fields; refused vectors are refused; arbitrary bytes and every truncation never panic; the decoder text "K1ABC W9XYZ R -09" renders "K1ABC W9XYZ R-09" and "R +03" renders "R+03", other texts unchanged.
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
        doc /* TC-012-003 — Inbound commands and transmit safety
             CL-040-03
             Setup: as TC-012-002 with target A accept_commands off and target C accept_commands on; the PTT log of the hardware double.
             Steps: Halt Tx from A, from C and from an unconfigured third socket (to A's socket) while armed by the browser's enable_tx; Reply, Free Text, Replay, Clear and Highlight Callsign from A; the same from a socket other than C's address to C's socket; from C: Reply matching the published CQ row while disarmed, Reply with a different snr, Reply while armed, Free Text before any contact and "TNX 73 GL", Free Text "K1ABC HB9BLA 73" with Send true, Replay, Clear window 0 then Replay and Reply, Highlight Callsign K1ABC and CLEARALL!, Close, Configure; a 5000-byte datagram followed by Halt Tx while armed; a datagram with another id; a Halt Tx with schema 4.
             Expected: every Halt Tx with this id and schema 2 or 3 disarms (arm_state disarmed, last cause halt, halt count +1) with outcome applied; the schema-4 or foreign-id Halt has no effect; commands from A and from the wrong source have outcome not_accepted and change nothing; C's Reply selects K1ABC (contact replying, Tx1 "K1ABC HB9BLA JN47") with arm_state disarmed; the mismatching Reply is refused no_match; a Reply or Free Text while armed is refused tx_enabled; Free Text without a contact is refused no_contact and a text that packs as no slot message (a 17-character free text, #24) invalid_message; Free Text sets Tx5 and leaves arm_state disarmed; Replay sends the retained decodes with New false then Status, to C only; after Clear Replay sends nothing and Reply is refused no_match; highlights list K1ABC then empty; Close and Configure ignored; the 5000-byte datagram is counted ignored and the Halt Tx behind it disarms in the same step; the PTT log stays empty throughout.
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
             Steps: GET /udp; PUT a list of A (unicast, decode only), B (239.255.0.1:2237 multicast, ttl 2, interface 127.0.0.1, accept_commands off); open a new owner on the same profile; PUT with a stale revision, another profile, another boot, an unknown key, 17 targets, a duplicate address, port 0, 0.0.0.0, ff02::1 without an interface, ttl 0 and 256, an interface that is not IPv4, a duplicated or unknown message name, accept_commands on the multicast target, an empty and a 65-byte instance name, v 2, text/plain, 8193 bytes, a query; GET on the invalid profile.
             Expected: the default {instance_name WSTX-Rust, one target 127.0.0.1:2237 enabled, all seven messages, multicast_ttl 1, interface null, accept_commands false} at revision 0; the PUT returns revision 1 with the messages in enum order and survives the reopen unchanged; each refusal with its status, code and field and nothing saved; the invalid profile shows configuration null and configuration_error invalid_configuration with no socket; a row published then is not sent after a valid PUT (only Heartbeat and Status).
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
        doc /* When the station starts with its profile, and monitor_off_at_startup is false and last_receive is stored, it resumes that receive once, without a browser or operator action, using the profile's current audio input (none configured: resume failed audio_unconfigured). An FT4/FT8 choice with a band is resumed as the same band selection the band button makes (receive-only CAT setup under configured CAT; nominal dial from the preferred table); with configured CAT it waits up to 20 s for the CAT lifecycle (CL-022-03/04) to report the radio ready, retrying the transient admission refusals radio_unavailable, busy and state_conflict every 250 ms within that wait, and if the radio is not ready in time or the selection fails it starts receive on the stored mode on the radio's present dial (resume started_untuned) and keeps the stored band. A spectrum choice or a choice without a band starts receive on the stored mode. A missing audio device follows the existing live-audio error/retry state of the started job; the resume never exits or restarts the process. With monitor_off_at_startup true (resume off) or nothing stored (resume idle) no receive starts; a receive, selection or import that exists before the resume acts (operator or MCP) is never replaced (resume skipped). */
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
             transmit owner; the actual server and Chromium with GET /transmit and GET
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
             CODEC, FT8 receive on a band with at least ten stations heard. Steps (1)-(4)
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
        attribute automation : AutomationState = AutomationState::implemented;
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
        attribute automation : AutomationState = AutomationState::implemented;
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
        attribute automation : AutomationState = AutomationState::implemented;
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
        doc /* Every CI-V change of a radio setting by the station is read, compare, write, verify: the station first reads the setting's current value; when it already equals the wanted value no write frame is sent and the read is the confirmation; otherwise it sends the write only after the radio reports RX (1C 00 00), requires its ACK (FB; FA is refused radio_rejected) and reads the setting back, a different value being readback_mismatch and a failed readback indeterminate. No write is sent while this station's transmit hold is taken (the CAT owner's single lease excludes it). The transmit switch 1C 00 is a keying action, not a setting, and is not subject to this rule (CL-009 PTT readback). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_control/executor.rs; server/src/radio_control/actor.rs";
    }
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
        attribute executable : String = "server/src/radio_agc_tests.rs";
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
        doc /* Band Activity on the Detailed display profile shows a published decode view without waiting for a refresh cadence: each new or grown latest_decode publication is announced to every Detailed WebSocket peer at once as a receive.state event (unchanged exact data; Thin and Off peers keep the 2 s receive tick), and a Detailed browser then reads GET /receive and fetches the view's records immediately, page after page (limit 16), until its cursor reaches the view's frozen end, instead of at most once per 4 s. A failed result read (which falls back to at most once per 4 s until a page succeeds) and the Thin rules (one pending request, limit 1, at most once per 4 s, page at most 3072 bytes) are unchanged; with no announced or unread view and no failed GET /receive or result read, the idle read on every display profile is only a safety read at most once per 30 s (#10 WstxStationProtocol::PushedStationState), so the two-browser 32 kbit/s budget still holds. On a LAN every row of a published view is painted at most 0.3 s after its publication; "Loading results" shows only while records of the view are still being fetched. */
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
        doc /* The modem decodes on all CPU cores with headroom: its parallel stages use up to the logical CPU count minus one threads (at least one; the calling thread included), scoped to each stage, so capture, display and transmit threads keep a core; the native audio capture and transmit render threads run at raised (highest) thread priority. Parallel stages are the rows of the FT8 detection spectrum, the FT8 sync-peak qualification, the verification of each pass's candidates (demodulation, channel decode, refinement, physical check and, for a supported complete FT8 frame, its SNR signal power; at most sixteen at once, each holding one 1.2 MB known-word waveform while it refines) and the synthesis of the waveforms to subtract; peak blocking, the duplicate checks, the SNR baseline (per period) and SNR value, publication and the residual subtraction stay in candidate order. The decode set and its order (payload, start frame, frequency and SNR) are identical for every thread count. At most four subtraction waveforms are built at a time: the next four are built on other threads while the previous four are subtracted, so at most eight are held, bounding their memory. The last pass's verified frames are not subtracted, because no later pass reads that residual (#57: these keep a busy FT8 prompt window at about 0.3 s of decode, below the 0.5 s row budget of TC-057-002). The CL-007-04 per-CPU-worker runtime, memory and four-profile budgets are measured with one decode thread per worker. Parallel work runs in rounds of about 10 ms, each started item finishing, and the decode future yields and checks cancellation between rounds, so the station worker keeps draining capture and a cancellation returns as before. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/decoder/parallel.rs; server/src/decoder/search.rs; server/src/decoder/synchronization.rs; server/src/decoder/baseband.rs; server/src/audio/windows.rs; server/src/playback/windows.rs";
    }
    dependency CL_057_02_to_FR_003 from 'CL-057-02' to 'FR-003';
    dependency CL_057_02_to_FR_004 from 'CL-057-02' to 'FR-004';
    verification 'TC-057-002' {
        doc /* TC-057-002 — Parallel decode: identical result, wall time by thread count
             CL-057-02, CL-057-01
             Setup: release build; the hash-pinned busy recording websdr_test7.wav as the UTC-aligned FT8 prompt window (as TC-004-004); for the end-to-end case the TC-057-001 live path and Detailed browser.
             Steps: decode the window three times each on 1, 4 and 12 threads; order-preserving map of 200 items on 1, 2, 4 and 8 threads with one slow item, and with cancellation from inside the work; the TC-057-001 run with the default thread count.
             Expected (independent oracle: the single-threaded decode of the same window and the input order): the records on 4 and 12 threads equal those on 1 thread bit for bit and in order, at least 25 records; best wall times are reported per thread count (busy corpus period); the map returns every item once in input order and a cancelled caller ends with Cancelled; the cooperative-quanta and quality cases of TC-004-001 stay green; end to end (TC-057-001 setup, two busy periods), every row of the better period is painted at most 0.5 s after its prompt window completes at +13.8 s.
             2 — Isolated automated functional tests; Windows PC, no radio (decoder-quality, wstx-rust and live-station-browser suites). */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-057-02';
            verify 'CL-057-01';
        }
        attribute executable : String = "server/tests/decoder_signal.rs; server/src/decoder/parallel.rs; server/src/receive_http_tests.rs";
    }
    dependency CL_057_02_verified_by_TC_057_002 from 'CL-057-02' to 'TC-057-002';
    dependency CL_057_01_verified_by_TC_057_002 from 'CL-057-01' to 'TC-057-002';
    verification 'TC-057-003' {
        doc /* TC-057-003 — Live decode display on HB9BLA
             CL-057-01, CL-057-02
             Setup: the gated candidate installed on HB9BLA, IC-7300 on COM3 receiving a busy FT8 band, one browser on the LAN on the Detailed profile; no transmission.
             Steps: watch Band Activity over 10 consecutive FT8 periods; read GET /receive audio over the same periods.
             Expected: no "Loading results" visible in normal operation; each period's rows appear at about +14.0 to +14.5 s of the period; under that decode load no audio_stalled loss (#49): loss_epochs unchanged.
             4 — Live on the station, receive only; not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-057-01';
            verify 'CL-057-02';
        }
    }
    dependency CL_057_02_verified_by_TC_057_003 from 'CL-057-02' to 'TC-057-003';
    dependency CL_057_01_verified_by_TC_057_003 from 'CL-057-01' to 'TC-057-003';
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

    // #39 Strategy engine: Highlight and Auto, editor popup, directed-CQ rule (decisions
    // on #37/#39/#42, 2026-11-01); detailed contract in WstxStrategy.
    requirement 'CL-039-01' {
        doc /* Named strategies are a station setting of the selected profile: strategy.json beside profile.json holds {continent, active, highlight, strategies} with up to 16 strategies, each a name, 1..8 rules in priority order of 0..12 negatable conditions, a sort, Treat 73 as CQ, and the Auto settings (role, switch after, skip after, callers). GET /strategy and PUT /strategy (revision-checked, exact keys) read and save it; my continent for the directed-CQ rule is configurable there (Settings > General) and otherwise the cty.dat continent of my callsign (#55). Details: WstxStrategy::StrategyConfiguration, Strategy, Condition, StrategyHttp. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/contact_http.rs; server/src/main.rs; client/contact.js";
    }
    dependency CL_039_01_to_FR_007 from 'CL-039-01' to 'FR-007';
    dependency CL_039_01_to_FR_016 from 'CL-039-01' to 'FR-016';
    requirement 'CL-039-02' {
        doc /* One station evaluator gives each decoded standard message a verdict: the first rule whose conditions all hold (message type, new call or grid ever or on this band and mode from the internal log, continent of the sender's cty.dat entity, distance and azimuth from the message grid, SNR, DT, audio frequency, call prefix, CQ target, band; each negatable) and the display order by rank, then strongest, weakest, furthest or newest. POST /strategy/evaluate returns the verdicts of retained live records for the saved strategy or a draft, with the reason when asked; the browser never evaluates a strategy itself. Details: WstxStrategy::Condition, Verdict, ContinentOfCall, StrategyHttp. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/logbook.rs; server/src/recording.rs; server/src/dxcc.rs";
    }
    dependency CL_039_02_to_FR_007 from 'CL-039-02' to 'FR-007';
    dependency CL_039_02_to_FR_011 from 'CL-039-02' to 'FR-011';
    requirement 'CL-039-03' {
        doc /* Hard rule before every strategy: a directed CQ not addressed to my continent ("CQ <continent>" of another continent; "CQ DX" from my own or an unknown continent) is shown greyed, never matches and is never answered by Auto. Other CQ targets (TEST, POTA, a country such as CQ JA, a number) are answered by Auto only when the matched rule asks for that target with a non-negated CQ-target condition; Highlight leaves them to the rules. Details: WstxStrategy::DirectedCqRule, AutoStrategyRun. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/automation.rs; client/contact.js";
    }
    dependency CL_039_03_to_FR_007 from 'CL-039-03' to 'FR-007';
    requirement 'CL-039-04' {
        doc /* The strategy element above Band Activity offers the strategy name, the editor and Highlight | Auto. Highlight colours matching decodes with their rule, sorts them to the top of their period and greys directed CQs not for me, from the station's verdicts. The editor is a popup with its own HALT that keeps receive running, previews the unsaved draft against the latest period with the reason per decode, and applies on Save at once; choosing or saving never restarts receive. Details: WstxStrategy::HighlightView, StrategyEditor; WstxOperatingLayout::OperatingScreen. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_039_04_to_FR_010 from 'CL-039-04' to 'FR-010';
    dependency CL_039_04_to_FR_019 from 'CL-039-04' to 'FR-019';
    requirement 'CL-039-05' {
        doc /* Auto answers only strategy matches through the existing station automation and contact engine (no second engine): Auto Call answers the best matching CQ (with Treat 73 as CQ also a station that just ended a QSO, keeping my Tx frequency), Auto CQ calls CQ and answers the best caller (not after its RR73/73), Alternate switches between them after N consecutive tries without a contact; a station unanswered after N calls is skipped for the run; calls must pass the callsign guard. Auto never runs without the active strategy, asks once per page session, shows its state in the button, cannot switch the strategy while it runs, and stops by HALT/Esc, a second click, a manual contact change, the Tx watchdog or the existing automation stops. No QSO or time limit is offered. Details: WstxStrategy::AutoStrategyRun, SaneCall; WstxMcp::OperatingAutomation. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/strategy.rs; client/contact.js";
    }
    dependency CL_039_05_to_FR_020 from 'CL-039-05' to 'FR-020';
    dependency CL_039_05_to_FR_007 from 'CL-039-05' to 'FR-007';
    requirement 'CL-039-06' {
        doc /* The Tx watchdog counts consecutive unanswered own transmissions (WstxContact::TxWatchdog, 2026-11-04) and is never paused or reset by automation; only an answer from the partner (to my CQ: from anyone) or a human action in the browser resets it. Only a human action in the browser is an operator action (an Enable Tx, accepted contact request or Auto start from the browser), decided by the request principal the station reads from its credential at the auth boundary (#58: an MCP client has its own token and is never the browser principal on any route, including a direct /contact/command); commands of an automation run, MCP requests (including starting or restarting a run) and UDP commands never reset or extend it; their Enable Tx keeps the count and is refused tx_watchdog when the limit is used up or no browser action was seen this boot; only the browser may change the watchdog setting (set_watchdogs from MCP, UDP or automation is refused operator_required); a new target chosen by a run does not reset it. At the limit Enable Tx goes off without a halt and a run stops tx_watchdog; the station and its automation never use HALT in normal flow (HALT is the operator's emergency stop: HALT button, Alt+H, MCP wstx_transmit_halt, UDP Halt Tx). HALT from any source stops everything; grant, clock, period and safety-revision checks are unchanged; there is no band hopping. Details: WstxStrategy::WatchdogFromOperator; WstxContact::TxWatchdog. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/service.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/automation.rs; server/src/mcp.rs; server/src/udp.rs; server/src/authorization.rs";
    }
    dependency CL_039_06_to_FR_008 from 'CL-039-06' to 'FR-008';
    requirement 'CL-039-07' {
        doc /* Outstanding, issue #39/#42 later slices: DXCC entity and CQ/ITU zone list conditions and the rarest sort (the cty.dat entity is delivered by #55, CL-055-01; the new DXCC, continent and zone conditions by #42, CL-042-01) (the two-tier ignore lists, Pounce and Alert as a third action with history are delivered by #42, CL-042-02, CL-042-03 and CL-042-04); auto-QRM stop; free Tx slot finder; filtered-out view toggle; freeze Band Activity on hover; per-mode watchdog values; late-duplicate guard and false-decode heuristic; CQ-target prefer; stacked DXpedition replies. Until delivered these conditions and actions are not offered. */
        attribute coverage : ImplementationState = ImplementationState::target;
    }
    dependency CL_039_07_to_FR_007 from 'CL-039-07' to 'FR-007';
    verification 'TC-039-008' {
        doc /* TC-039-008 — Later strategy slices (outstanding)
             CL-039-07
             Setup: actual candidate router with a pinned cty.dat fixture and hand-authored rows.
             Steps: evaluate DXCC, zone and new-DXCC conditions and the rarest sort; Alert, ignore lists, Pounce and auto-QRM stop scenarios.
             Expected: defined when the slice is prepared; until then these conditions are refused at PUT /strategy.
             2 — Isolated automated functional tests; Windows development PC; not implemented. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-039-07';
        }
    }
    dependency CL_039_07_verified_by_TC_039_008 from 'CL-039-07' to 'TC-039-008';
    requirement 'CL-042-01' {
        doc /* The strategy's New matrix is complete: besides new call and new grid, a condition holds for a sender whose DXCC entity, continent, CQ zone or ITU zone (from its cty.dat entity, #55) is not in the internal log, ever or on this band and mode, each negatable; a sender without an entity, an unknown station band (for the band form) or an unreadable log never counts as new. The editor offers the four conditions with the same ever / on this band and mode choice; the live preview names a failing one. Details: WstxStrategy::Condition, NewEntity. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/dxcc.rs; server/src/logbook.rs; client/contact.js";
    }
    dependency CL_042_01_to_FR_007 from 'CL-042-01' to 'FR-007';
    dependency CL_042_01_to_FR_011 from 'CL-042-01' to 'FR-011';
    verification 'TC-042-001' {
        doc /* TC-042-001 — New DXCC, continent and zone conditions
             CL-042-01
             Setup: the bundled cty.dat; a worked set from a hand log: DL1ABC 40m FT8 (Fed. Rep. of Germany, EU, CQ 14, ITU 28), JA1XYZ 20m FT8 (Japan, AS, 25, 45), F1ABC 40m FT4 (France, EU, 14, 27), K2ABC with no band (United States, NA, 5, 8), Q1ABC 40m FT8 (no entity); station HB9BLA JN47AA on 40m FT8; rows CQ DL2XYZ, CQ F5ABC, CQ JA2ABC, CQ VK2ABC (Australia, OC, 30, 59), CQ K1ABC, CQ XX1ABC (no entity). A browser editor case on the actual isolated station.
             Steps: parse and serialize each of the four kinds with ever and band; refuse value any, a values key and a missing value; evaluate each kind and scope as a one-condition rule, and negated; the same with the station band unknown and with the log unreadable; the reason of a failing condition; in the editor add a condition and choose each new kind.
             Expected (entity columns of the cited cty.dat lines): new_dxcc ever VK2ABC only, band F5ABC JA2ABC VK2ABC K1ABC; new_continent ever VK2ABC, band JA2ABC VK2ABC K1ABC; new_cq_zone ever VK2ABC, band JA2ABC VK2ABC K1ABC; new_itu_zone ever VK2ABC, band F5ABC JA2ABC VK2ABC K1ABC; XX1ABC never; negation the complement among the six rows; band unknown: every band form false, ever unchanged; log unreadable: every form false; the reasons "no match (rule 1: new DXCC on band)" and "no match (rule 1: not new ITU zone)"; the editor lists New DXCC, New continent, New CQ zone and New ITU zone, each with ever / on this band and mode, and the station saves and returns the draft conditions {kind, negate, value} at revision 1.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-01';
        }
        attribute executable : String = "server/src/strategy_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_042_01_verified_by_TC_042_001 from 'CL-042-01' to 'TC-042-001';
    requirement 'CL-042-02' {
        doc /* Two-tier ignore lists govern the strategy: a permanent list of calls (Settings > General, saved in the strategy configuration) and a session list in station memory (Band Activity right-click "Ignore <call>" / "Stop ignoring <call>", POST /strategy/ignore), whose entries end after the configured minutes (1..720, default 30) and which the station empties on any change of the station band. An ignored sender (exact call) never matches a rule: Highlight gives it no mark, Auto Call never selects it and Auto CQ never answers it, also when Auto CQ answers every caller; a contact already in progress and a manual Reply or Select are not changed. A saved configuration from before the lists reads with empty lists and 30 minutes. Details: WstxStrategy::IgnoreLists. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/automation.rs; server/src/contact_http.rs; server/src/main.rs; client/contact.js; client/recording.css";
    }
    dependency CL_042_02_to_FR_007 from 'CL-042-02' to 'FR-007';
    dependency CL_042_02_to_FR_010 from 'CL-042-02' to 'FR-010';
    dependency CL_042_02_to_FR_020 from 'CL-042-02' to 'FR-020';
    verification 'TC-042-002' {
        doc /* TC-042-002 — Ignore lists in the evaluator, the store, the routes and Auto
             CL-042-02
             Setup: hand-authored rows CQ K1ABC FN42, CQ DL1XYZ JO62, CQ NA W1AW FN31, HB9BLA VK2ABC QF56; the station HB9BLA JN47AA on 40m; the actual station router, contact engine and #9 transmit owner on the recording hardware double (virtual UTC; no audio, PTT or radio); synthetic monotonic instants for the session expiry.
             Steps: parse the configuration with ignore_calls and session_ignore_minutes and refuse a duplicate, a lower-case or a 14-character call, 101 calls, minutes 0 and 721; read a saved pre-#42 file without both keys and with only one of them; evaluate a CQ-matching strategy with K1ABC on the permanent list, on the session list and on both, and with W1AW (greyed) ignored; the session list: add, renew, remove, expiry at the minute boundary, 65 adds, a band change and a band unknown; POST /strategy/ignore accepted and refused (extra key, bad call, wrong profile, stale boot), GET /strategy session_ignore; the station tick on another band; Auto Call with the strongest matching CQ ignored; Auto CQ (apply_to_callers off) with an ignored caller.
             Expected: the round trip keeps both keys; the refusals name ignore_calls[i], ignore_calls and session_ignore_minutes; the pre-#42 file reads with [] and 30, the one-key file is invalid_configuration; K1ABC rank null, grey false, why "K1ABC is ignored (permanent list)", "(session list)", session first when on both; W1AW also not greyed when ignored; an entry ends exactly at added + minutes and reports remaining_s rounded up; renewal moves it last with a new expiry; the 65th add drops the oldest; a band change (also to unknown) empties the list; the route returns the snapshot at an unchanged revision with the refusal codes and fields of PUT /strategy; Auto Call selects the next matching CQ, never the ignored one; Auto CQ answers the other caller, never the ignored one; no transmit key in any evaluation.
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
             Setup: the browser fixture of the operating screen with the actual isolated station and its fixture live decodes; Highlight on with a CQ strategy.
             Steps: right-click a decoded row with a resolved sender; choose Ignore; open the menu again on that row; open Settings > General; enter two calls in the permanent list; change the session minutes; remove the session entry.
             Expected: the menu offers Reply, Select, Set Rx here, "Pounce <call>" (#42 CL-042-03) and "Ignore <call>", Ignore sends POST /strategy/ignore {call, ignore true} and does not set the Rx frequency; the row loses its Highlight mark after the station's new verdicts; the menu then offers "Stop ignoring <call>"; Settings lists the call with its remaining minutes; the permanent list saves with PUT /strategy as ignore_calls in upper case, the minutes as session_ignore_minutes; remove sends ignore false and the list is empty; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_042_02_verified_by_TC_042_003 from 'CL-042-02' to 'TC-042-003';
    requirement 'CL-042-03' {
        doc /* Pounce waits for one chosen call and answers it: an operator action (Band Activity right-click "Pounce <call>") starts a station automation run with pounce <call> on the current band and mode (one run at a time, so never beside Auto Call or Auto CQ, and needing a known band); when that call is decoded sending a CQ that the directed-CQ rule leaves to me, or an RR73/73 ending another QSO (then my Tx frequency is held), and it is on no ignore list, the station answers it as a double-click does (select_row, enable_tx; the contact engine calls in the next own period and Auto Seq runs the QSO). The pounce ends when that contact completes, on a station band change (band_changed), on HALT, the Tx watchdog or the operator's Stop pounce; a contact without an answer for max_unanswered_periods partner periods is cancelled and the pounce waits again. While it runs the QSO pane and the strategy element show it. Details: WstxStrategy::Pounce, WstxMcp::AutomationConfiguration, OperatingAutomation. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/mcp.rs; client/contact.js";
    }
    dependency CL_042_03_to_FR_007 from 'CL-042-03' to 'FR-007';
    dependency CL_042_03_to_FR_020 from 'CL-042-03' to 'FR-020';
    verification 'TC-042-004' {
        doc /* TC-042-004 — Pounce at the station: configuration, answer, ignore, band change and end
             CL-042-03
             Setup: hand-authored rows; the station HB9BLA JN47AA on 40m; the actual station router, contact engine and #9 transmit owner on the recording hardware double (virtual UTC; no audio, PTT or radio); FT8 live job; the browser's grant.
             Steps: parse configurations with pounce absent, null, K1ABC, lower case, 2 characters, K1ABC/R, with strategy true and with K1ABC in blocked_calls; start a pounce with the station band unknown; start a pounce on K1ABC on 40m; publish CQ W1AW FN31 and CQ DL1XYZ JO62; publish CQ K1ABC FN42; run the own period; the partner's report, RR73 and the own 73 period; start again and configure or start a second run while it waits; publish W1AW K1ABC RR73; a pounce on K1ABC with K1ABC on the session ignore list and a CQ K1ABC; a pounce with CQ NA K1ABC (not for EU); a pounce waiting when the station band changes to 20m; a pounce in its contact with max_unanswered_periods 2 and two partner periods without an answer.
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
             Expected: the menu offers "Pounce K1ABC"; the confirmation is the Auto one; configure sends exactly {modes [ft8], ranking first_seen, min_snr_db null, allowed_calls [], blocked_calls [], max_contacts 1, max_unanswered_periods 5, completion_action stop, max_run_minutes 480, strategy false, pounce K1ABC}, then start with the shown safety revision; no contact command (no enable_tx) is sent by the browser; the QSO pane reads "Pouncing on K1ABC (40m) · waiting for CQ or 73", the status "Pounce K1ABC waiting · HALT ends it", the Auto button is disabled; the menu then offers "Stop pouncing K1ABC"; Stop pounce sends stop with the run id; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-03';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_042_03_verified_by_TC_042_005 from 'CL-042-03' to 'TC-042-005';
    requirement 'CL-042-04' {
        doc /* Alert is a third action beside Highlight and Auto: a strategy rule can be marked alert; when a decode matches an alert rule of the active strategy (an ignored sender and a directed CQ not for me never alert), the station records an alert (time, call, message, rule, band, mode, SNR, DXCC entity) in a history of the last 100 alerts in station memory (kept across page reloads, empty after a station restart), at most one per call and band in 10 minutes, and announces it to the browser; the browser plays a short sound and/or shows a browser notification as the operator chose in Settings > General (both off by default; the notification permission is asked only on the operator's click; no sound while the page is hidden), and lists the history with a Clear. An alert never transmits or changes a contact or automation run. An MCP client may read the history (wstx_read alerts), not clear it. Details: WstxStrategy::Alert, Strategy, StrategyEditor; WstxMcp::ToolCatalog. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/contact_http.rs; server/src/main.rs; server/src/mcp.rs; client/contact.js";
    }
    dependency CL_042_04_to_FR_007 from 'CL-042-04' to 'FR-007';
    dependency CL_042_04_to_FR_020 from 'CL-042-04' to 'FR-020';
    verification 'TC-042-006' {
        doc /* TC-042-006 — Alert at the station: rule key, match, dedupe, ignore and directed-CQ rule, history and routes
             CL-042-04
             Setup: hand-authored rows and strategies; the station HB9BLA JN47AA on 40m; the actual station router and contact engine on the recording hardware double (virtual UTC; no audio, PTT or radio); FT8 live job.
             Steps: parse a rule with alert true, false, absent and "yes"; evaluate a strategy whose rule 1 (no alert) and rule 2 (alert) both hold; publish CQ JA1XYZ PM95 before any rule is marked alert, then save the strategy "Alerts" (rule 1 call K without alert, rule 2 message CQ with alert); publish in one period CQ K1ABC FN42 (-12 dB), CQ DL1XYZ JO62 (-3 dB), CQ NA W1AW FN31, CQ G4ABC IO91 with G4ABC on the session ignore list and HB9BLA VK2ABC QF56; publish CQ K1ABC FN42 30 s later and 10 minutes after the first; change the band to 20m and publish CQ K1ABC again; read GET /strategy/alerts and wstx_read alerts; clear with an extra key, a wrong profile, a wrong boot and correctly; read GET /strategy/alerts with the MCP principal's cookie and POST the clear with it; publish 101 CQs from different calls in one period.
             Expected: true reads back with alert true, false and absent without the key, "yes" is invalid_request strategies[0].rules[0].alert; the alert rule is rule 2 although the rank is rule 1; no alert for JA1XYZ; alerts exactly K1ABC {utc of the period, message "CQ K1ABC FN42", rule "Alerts rule 2", band 40m, mode ft8, snr_db -12, dxcc United States} and DL1XYZ (Fed. Rep. of Germany), ids 1 and 2, revision 2, none for W1AW, G4ABC or the message to me; nothing 30 s later; a third K1ABC alert 10 minutes later and a fourth on 20m; wstx_read alerts equals the browser's GET; the refusals 400 invalid_request, 403 wrong_profile, 409 state_conflict boot_id leave the history; the clear empties it with revision + 1; the MCP cookie may GET and is refused 401 on the clear; after 101 alerts the history holds the last 100; no contact, no selection and no keying throughout.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-042-04';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_042_04_verified_by_TC_042_006 from 'CL-042-04' to 'TC-042-006';
    verification 'TC-042-007' {
        doc /* TC-042-007 — Alert checkbox in the editor, the Settings alert history, sound and browser notification
             CL-042-04
             Setup: the browser fixture of the operating screen with the actual isolated station; the strategy and alert routes are hand-written fixtures; the page's Notification and AudioContext are recording test doubles (no sound device).
             Steps: open the editor, tick Alert on rule 1 and Save; open Settings > General with one alert in the history; announce alert.state with a second alert; tick Sound and announce a third; tick Browser notification (the double grants) and announce a fourth; make the page hidden and announce a fifth; reload; Clear.
             Expected: the PUT carries rule 1 with alert true; Sound and Browser notification are unchecked by default and the history line reads "12:00:00 K1ABC CQ K1ABC FN42 · CQ rule 1 · 40m FT8 · -12 dB · United States"; the second alert is listed first with no tone, no notification and no permission request; the third plays one tone and no notification; the permission is asked exactly once, on the click; the fourth plays one tone and shows one notification "Alert JA1XYZ" with body "CQ JA1XYZ PM95 · CQ rule 1"; the hidden page's fifth plays no tone and shows one notification; after the reload both checkboxes stay as chosen and nothing is announced; Clear sends exactly {v, profile_id, boot_id} to POST /strategy/alerts/clear and the list is empty; no page errors.
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
             Setup: hand-written configuration JSON with one strategy "NA first" (two rules), the parser only.
             Steps: parse the valid configuration and serialize it; parse variants each with one refused value: continent XX, active not listed, highlight 1, a padded or empty name, no rules, sort rarest, skip_after 0, switch_after 21, auto_role pounce, a non-boolean flag, condition kind dxcc, message value any, a duplicated or empty continent list, two names equal ignoring case, snr min > max, a range with both bounds null, an extra condition key, 17 strategies; an azimuth range 300..60.
             Expected: the valid one round-trips to the same JSON with role alternate; each refusal names exactly its field path (e.g. strategies[0].rules[0].conditions[1].values[1]); the wrapping azimuth range is accepted.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-01';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_01_verified_by_TC_039_001 from 'CL-039-01' to 'TC-039-001';
    verification 'TC-039-002' {
        doc /* TC-039-002 — Evaluator, continent and directed-CQ tables
             CL-039-02, CL-039-03
             Setup: hand-authored codec-packed rows for HB9BLA JN47AA (continent EU) on 40m: CQ K1ABC FN42 -12, CQ DL1XYZ JO62 -3, CQ NA W1AW FN31 -5, CQ EU G4ABC IO91 -8, CQ DX OH1AA KP20 -1, CQ DX JA1XYZ PM95 -15, W1AW K1ABC RR73 -6, HB9BLA VK2ABC QF56 -20, CQ TEST N1MM FN31 -2; log facts K1ABC worked on another band, DL1XYZ and JO62 worked here; continents from the cty.dat entities of the senders, distances from the square centres computed independently (JN47AA-FN42 5989 km, bearings FN42 296, IO91 311, JO62 28, PM95 38 degrees).
             Steps: continent (cty.dat entity) of HB9BLA K1ABC OH1AA JA1XYZ VK2ABC PY1AA ZS6AA CE9AA UA9ABC Q1ABC K1ABC/MM; DirectedCqRule for EU/NA/DX/TEST/POTA with known and unknown continents; strategy [CQ and continent NA], [CQ] with each sort; Treat 73 as CQ; an empty rule; my continent unknown; each condition kind with its expected matching set and its negation (the complement among the CQs); the reasons.
             Expected (hand table, continent column of the cited cty.dat lines): EU NA EU AS OC SA AF SA AS, none, none; ranks 0,1,grey,1,grey,1,none,none,0; strongest order 8,0,1,3,5, weakest 0,8,5,3,1, newest 8,0,5,3,1, furthest ends 5,3,1; with Treat 73 as CQ the RR73 of K1ABC (no grid, NA by its entity) has rank 0 and a call to me is never cq-like; an empty rule leaves only the two greyed rows unmatched; unknown continent greys rows 2,3,4,5; each condition set and complement as written in the test; reasons "no match (rule 1: SNR 0.. dB)" and "CQ NA is not addressed to my continent (EU)"; the callsign guard refuses K1, ABCDE and W1AW/R.
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
             Steps: GET /strategy; PUT a configuration; read strategy.json; open a new owner; PUT with a stale revision, another profile, another boot, v 2, an extra key, a foreign Origin; GET without credentials; PUT continent AS; evaluate the saved strategy, a draft with explain, another job id, a 2049-record range.
             Expected: default {null,null,false,[]} revision 0 with my_continent EU; revision 1 and the file {schema_version 1, profile_id, revision 1, configuration}; the new owner reads it; 409 stale_revision, 403 wrong_profile, 409 state_conflict boot_id, 400 unsupported_version, 400 invalid_request, 403, 401; my_continent AS; verdicts [{0,rank 0},{3,rank 1},{1,grey}] in display order; the draft lists all four with the call to me first ("matches rule 1"); 409 stale_request; 400 next_sequence; no PTT exchange.
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
        doc /* TC-039-004 — Auto strategy runs
             CL-039-03, CL-039-05
             Setup: as TC-039-003 with the contact engine and #9 transmit owner on the recording hardware double (virtual UTC set 1 s after an even FT8 period E; own periods odd); Auto started from the browser path (cookie grant) with the strategy "NA first" (rule 1 CQ from NA, rule 2 any CQ, Treat 73 as CQ, skip after 2, switch after 2).
             Steps: (a) start without a strategy; save the strategy as role call; start; PUT a configuration without active; publish CQ NA W1AW (strongest), CQ JA JA1XYZ, CQ 290 N1MM, CQ DL1XYZ, CQ K1ABC; two empty partner periods; publish CQ K1ABC and W1AW DL1XYZ RR73 at 1700 Hz; browser HALT. (b) role alternate: publish only CQ NA W1AW, then an empty period; tick; publish HB9BLA OH1AA RR73 and HB9BLA K1ABC FN42; R-05; 73; tick twice; two empty partner periods.
             Expected: (a) not_configured strategy; 409 state_conflict active; K1ABC selected and armed (replying, role call, 2 candidates; W1AW, JA1XYZ and N1MM never); after two unanswered periods disarmed, waiting, skipped [K1ABC], no stop reason; DL1XYZ selected (Tx1 "DL1XYZ HB9BLA JN47", armed) with Rx 1700 and Tx unchanged; HALT stops halted. (b) after two tries an own CQ "CQ HB9BLA JN47" armed (calling_cq, role cq); K1ABC answered (report, armed), never OH1AA; rogers, completed; calling again with 1 completed contact; after two empty partner periods waiting in role call, disarmed. No PTT exchange in either case.
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
        doc /* TC-039-005 — The Tx watchdog is never reset by automation
             CL-039-06
             Setup: as TC-039-004 with role cq; for the unit cases the #9 Core on the hardware double; counts per WstxContact::TxWatchdog (#39, 2026-11-04).
             Steps: (1) browser limit 2; browser Auto start; transmit the own CQ at E+15 s; publish a caller at E+30 s; transmit the report at E+45 s and its repeat at E+75 s; reach E+105 s; cancel and start Auto again from the browser. (2) MCP and browser: an MCP Enable Tx before any browser action; browser limit 1; an MCP Enable Tx (CQ) transmitted at E+15 s; MCP set_frequency; MCP set_watchdogs 99; reach E+45 s; a station calls HB9BLA in period E+30 s; an MCP Enable Tx; an MCP run start and a matching CQ; a browser action and an MCP Enable Tx. (3) MCP route: browser limit 1, an MCP Enable Tx and its CQ, MCP-principal commands through the tool and straight to /contact/command, then MCP Enable Tx on both. (4) UDP: a UDP Reply and Free Text from an accepting target before any browser action, then a browser-path action. Unit: automatic arm before any operator action; activity, limit 2, automatic arm; operator arm.
             Expected: (1) remaining calls 1 after the CQ, 2 after the caller's answer (the run's selection does not reset it), the request at E+105 s is never keyed, the run stops tx_watchdog, tx_expired true, last cause tx_watchdog and halt_state unchanged (no halt); the browser start arms again. (2) refused tx_watchdog; spent after the one CQ, still spent after the MCP command, set_watchdogs refused operator_required, the next CQ never keyed, still spent after the caller (an answer after a stop resets nothing), the MCP Enable Tx refused tx_watchdog, the MCP run stops tx_watchdog unarmed with no further key; after the browser action not spent and the MCP Enable Tx arms. (3) spent after every MCP request, both Enable Tx refused tx_watchdog, one key in total. (4) spent before and after both applied commands; not spent after the browser action. Unit: spent before any action; not spent after the activity; remaining 2 after the automatic arm and after the operator arm.
             2 — Isolated automated functional tests; Windows development PC, transmit double; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-06';
        }
        attribute executable : String = "server/src/strategy_tests.rs; server/src/udp_tests.rs";
    }
    dependency CL_039_06_verified_by_TC_039_005 from 'CL-039-06' to 'TC-039-005';
    verification 'TC-039-006' {
        doc /* TC-039-006 — Strategy element, Highlight, editor popup and Auto in the browser
             CL-039-01, CL-039-04, CL-039-05
             Setup: actual isolated server and Chromium at 1366x768 (and 360x740 for the popup); routed fixtures: an FT8 live job with CQ K1ABC FN42, CQ NA W1AW FN31, CQ DL1XYZ JO62, a strategy view (revision 4, "DX first", Highlight off), station verdicts [2 rank 0, 0 rank 1, 1 grey] (with reasons when explain), an automation owner recording commands, the contact snapshot (safety revision 7, watchdog 6 unanswered calls). A second case uses the real station store.
             Steps: wait; click Highlight; open the editor; read the preview; resize to 360 px; change the sort to weakest; tick "not" on the first condition; Save; Close; click Auto, Cancel; click Auto, Start Auto; announce automation.state; click Auto again. Second case: choose continent AS in Settings > General.
             Expected: no evaluation request while Highlight is off; one PUT {expected_revision 4, highlight true}; one evaluation {the live identity, 0..3, strategy null, explain false}; rows DL1XYZ (rule 1), K1ABC (rule 2), W1AW greyed; the popup HALT has the top-bar state; preview rows "#1 CQ DL1XYZ JO62 matches rule 1", "#2 ...", "— CQ NA W1AW FN31 CQ NA is not addressed to my continent (EU)" from a draft evaluation with explain; no horizontal overflow at 360 px; an edit re-runs the preview; Save sends exactly the edited strategy at expected_revision 5; the confirmation names the strategy, role and watchdog; Cancel sends nothing; Start sends configure {strategy true, the maxima} then start {policy 1, run 0, ft8, safety 7}; the button shows "Auto · waiting" pressed and the name is locked; the second click sends stop with the run id; no enable_tx from the browser. Second case: PUT saved continent AS (my_continent AS) and no browser storage key.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-01';
            verify 'CL-039-04';
            verify 'CL-039-05';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_039_01_verified_by_TC_039_006 from 'CL-039-01' to 'TC-039-006';
    dependency CL_039_04_verified_by_TC_039_006 from 'CL-039-04' to 'TC-039-006';
    dependency CL_039_05_verified_by_TC_039_006 from 'CL-039-05' to 'TC-039-006';
    verification 'TC-039-007' {
        doc /* TC-039-007 — Live Highlight and Auto on HB9BLA
             CL-039-03, CL-039-04, CL-039-05, CL-039-06
             Setup: the gated candidate installed on HB9BLA, IC-7300 on COM3 at 1 W on 40 m FT8, operator consent; Tx watchdog 6 unanswered calls (the profile default).
             Steps: create a strategy (rule 1 CQ and not continent EU, rule 2 CQ; Treat 73 as CQ) and turn Highlight on; then Auto in role cq; then role call.
             Expected: matching decodes marked and on top, CQ NA/AS and same-continent CQ DX greyed; Auto CQ transmits CQ and answers the first caller to a logged QSO, or ends by the watchdog after 6 unanswered CQs; Auto Call answers only matching CQs; HALT and Esc stop at once; the watchdog is not extended by Auto.
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
        doc /* Band Activity colours, hover text and order (operator 2026-11-03). Operator decision deviating from WSJT-X, which colours only CQ/QRZ and calling-me lines: the sender of every decoded standard message (CQ, replies to others, reports, R-reports, RR73, 73) is coloured by the same new DXCC, continent, zone, grid and call flags (the whole row for a CQ or QRZ, only the sender's call otherwise, #50 CL-050-08); a message to my call keeps the calling-me colour on top; a row without a flag has no colour (there is no CQ slot, #50, and worked before never colours). Every row with a reason carries hover text (title and aria-description, on the row and its colour mark) naming each reason in value order (#50 CL-050-08 replaces this Band Activity hover by its one-line reason tip; the QSO pane callers keep it): calling me, the strategy verdict, each new flag with its entity, zone, grid or band, then the worked-before status, for example "New DXCC: Romania", "New DXCC on 40m", "New CQ zone 20", "New grid KN34", "New call", "Worked before on 40m FT8". Within each period the rows are sorted by value (1 calling me, 2 strategy hits by their rank, 3 new DXCC, 4 new DXCC on this band, 5 new CQ or ITU zone, 6 new grid, 7 new call, 8 no flag), then by SNR strongest first, ties in decode order; the column headers still choose another order and the DXCC header returns to it. Details: WstxOperatingLayout::BandActivityColours, BandActivityValue, BandActivityHover, ActivityOrdering. */
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
             Expected: K1ABC dxcc {U.S.A., NA, 5, 8, 7706 km} without flags (no band), then only new_call_band and new_grid_band (the US is worked on 20m); W1AW worked on 20m in FT4 has no flag (band, not mode); DL2XYZ Germany 465 km with only new_call and new_call_band, none after it is logged; JA1XYZ all twelve flags; G4ABC new call, grid, DXCC and ITU zone (EU and CQ 14 worked); free text unchanged; calls compare case-insensitively, grids by square; Sicily counts as its own name.
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
             Setup: actual router with a selected profile whose log holds DL1ABC JO62 20m FT8 (TC-055-002); in the browser the operating fixture with routed result records carrying #55 flags and dxcc, selection band 20m, a worked-before query answered by the actual server.
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
             Setup: (a) actual candidate server with a logged K1ABC on 20m FT8; routed live job with CQ K1ABC, CQ W1XYZ, a report K9XX W2AB R-05 and a free-text row; (b) the same server with routed records carrying the station's #55 flags and routed /contact/worked statuses for CQ K1AA (no flag, worked_this_band_and_mode), CQ K2BB (new_call_band, worked_other_band_or_mode), CQ K3CC (new_call and new_call_band, not_worked) and HB9BLA K1AA R-05 to my call; Chromium.
             Steps: wait for the worked-before query; read row slots and backgrounds; turn New call off in Settings; append synthetic rows with slot sets for the #55 flags.
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
        doc /* (#37) While an own CQ runs the QSO pane header reads "Calling CQ" with the Tx period; the message line reads "▶ TX now: <message>" with the seconds left while the station reports transmitting ("▶ TX now: Tune" with the Tune seconds left during Tune) and "▸ next: <message> · Tx in <n> s" otherwise; the Others, below the QSO dialogue, list only stations calling my call, with time and SNR: during a QSO those other than the partner within +/-50 Hz of my Rx or Tx offset (⚠, a double-click switches the contact with Enable Tx kept), otherwise every caller on any frequency as soon as decoded; an empty list is one muted line "nobody calling" ("nobody else calling" during a QSO). Details: WstxOperatingLayout::QsoPane. */
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
             Steps: (ui-operating TC-050-005) read the header after a receive refresh, the message line with transmitting true (4 s into my period), with a transmit view whose last_text of this period differs from the next message, during Tune, and with transmitting false at the next odd period start, and the Others with no row; (ui-operating TC-007-009) the Others idle and during a QSO with Rx 1500 Hz and Tx 2100 Hz, with callers of my call at 400, 1505 (the partner), 1530, 2130 and 1600 Hz and CQs near Rx, then with Rx and Tx at 2800 Hz; (contact.test TC-007-003) the Others with a caller and CQs near Rx on the actual server; screenshots of calling CQ, TX now and between periods.
             Expected: header "Calling CQ" with "Tx even (1st)"; "▶ TX now:" "CQ HB9BLA JN47" with "10 s left", then "K1ABC HB9BLA -05" (the text on the air), "▶ TX now:" "Tune" with "80 s left"; "▸ next:" "CQ HB9BLA JN47" with "Tx in 15 s"; "nobody calling" for an empty list; idle every caller as a QSO table row "HH:MM:SS | <my call> ◂ <caller> | …" oldest first and no CQ; during the QSO only the 1530 and 2130 Hz callers as rows "HH:MM:SS ⚠ | …", never the partner or 1600 Hz, "nobody else calling" at 2800 Hz, and a double-click sends select_row replace true then enable_tx.
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
        doc /* Band Activity marks each decoded row by what makes it interesting, highest first (WstxOperatingLayout::BandActivityScheme, BandActivityRowMark): (1) the current QSO partner, from the contact preparation until the contact is logged or cancelled, taken from the contact snapshot the page already holds (no further request): its rows are moved to the top of Band Activity with a red separator stripe below them and carry a red left bar, a "◆ QSO" badge after the message and a bold message, without a slot background; (2) a row to my call from another station (also <MYCALL> and a nonstandard i3=4 'to', #24): the whole row in the My call colour, also when the sender was worked before on this band and mode; (3) a CQ or QRZ from a station with an enabled new_* slot: the whole row in that slot's colour; (4) any other row from a station with an enabled new_* slot (in QSO with another station): only the sender's call is coloured, the rest of the row is plain; (5) everything else has no colour. The Settings slot choice applies to every mark; an accepted UDP highlight (CL-040-08) wins over every slot colour, and on a partner row the partner marker stays. A row's reason tip is one compact line naming only the reasons of its colour that the row does not show, joined by " · ": per kind (continent, DXCC, zone, grid, call) the strongest enabled one, so an overall flag never also names its on-band form, the on-band call reason with the worked-before status in parentheses, then "UDP highlight" and the strategy verdict, e.g. "New DXCC · New call", "New on 40m (worked on another band or mode)"; no country, continent, distance or "Calls you" (the row shows them); a row without such a reason has no tip. It uses the #55 record data and the existing worked-before answers only (WstxOperatingLayout::BandActivityHover). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/recording.js; client/contact.js; client/recording.css";
    }
    dependency CL_050_08_to_FR_019 from 'CL-050-08' to 'FR-019';
    verification 'TC-050-008' {
        doc /* TC-050-008 — Band Activity row marks: partner first with the stripe, calls me, CQ of interest, sender-only colour, one-line reason tip
             CL-050-08
             Setup: actual release candidate (fixture station) and Chromium at 1440x900; routed receive pages for a kept period 12:00:00 (CQ K1PT FN42 new_call_band; CQ K7OLD FN42; K9XX W1AA R-03) and a latest period 12:00:15 (HB9BLA K1PT FN42 new_call_band; HB9BLA K2CM -05; HB9BLA K3NB R-07 new_call_band; CQ OA4DX FH17 and K9XX YO3ABC -07 with new_dxcc, new_dxcc_band, new_call, new_call_band and dxcc Peru/Romania; CQ K1WB FN42; W9AA W2CD 73; CQ JA1ZZ PM95 new_cq_zone, new_cq_zone_band, CQ zone 25), selection band 40m, routed /contact/worked statuses (K2CM, K1WB and W2CD worked on 40m FT8, K3NB on another band or mode, the others not worked) and routed contact snapshots.
             Steps: with no contact read each row's marks, message cell and sender-call backgrounds and reason tip; hover the YO3ABC message, its DXCC cell and an uncoloured row; focus the K3NB row; route a contact with K1PT in replying and reload the snapshot; read the order, stripe and marker; read the stripe at 360x800; sort by Freq and back; turn My call and New call off in Settings; deliver a udp.display event highlighting K1PT (blue) and YO3ABC (green); route the contact completed and reload.
             Expected: no contact: no stripe; the three rows to my call whole row rgba(255,102,102,0.32) with tips "New on 40m", none (worked on this band and mode, no flag) and "New on 40m (worked on another band or mode)"; CQ OA4DX whole row rgba(255,0,255,0.26) tip "New DXCC · New call"; K9XX YO3ABC -07 message cell transparent with only the YO3ABC span rgba(255,0,255,0.26) and the same tip; CQ JA1ZZ whole row rgba(255,191,0,0.26) tip "New CQ zone 25"; the rows without a flag uncoloured without a tip; no row has a native title and the aria-description equals the tip; the tip box is one line at the pointer, absent over the DXCC cell and over an uncoloured row, shown for the focused row and gone after focus moves. Prepared K1PT: HB9BLA K1PT FN42 then CQ K1PT FN42 first, then one stripe row (no text, rgb(255,64,64)), then the other rows in the earlier order with the kept divider; the partner rows have no slot background or tip, a 4 px rgb(255,64,64) inset left bar, a bold message and the badge " ◆ QSO"; at 360x800 the stripe is a 3 px full-width rgb(255,64,64) bar; the partner block stays first after the Freq sort. With My call and New call off: K2CM uncoloured, K3NB whole row rgba(153,255,255,0.2), the OA4DX and YO3ABC tips "New DXCC · New on 40m". UDP: both K1PT rows rgb(0,0,255) with the marker kept and tip "UDP highlight"; the YO3ABC row rgb(0,255,0) without the sender mark, tip ending "· UDP highlight". Completed: no stripe and no partner row; HB9BLA K1PT FN42 is a calls-me row; one worked-before query per published period (two: 3 and 8 calls), none added by the marks, the partner or the tip; no page error.
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
             Then (QsoPane Others) the same rows during a QSO with PJ4/K1ABC, Rx 1000 Hz and Tx 1300 Hz.
             Expected: the rows to <HB9BLA> or HB9BLA carry the mycall mark (ba-tome) and sort first as value 1 (calling me, #55 BandActivityValue), the unresolved one does not and follows them; the QSO pane Others list exactly the three rows to my call, oldest first, and not the unresolved one; during the QSO only "<HB9BLA> K1ABC -12" (1300 Hz, not the partner PJ4/K1ABC's nonstandard row at 1000 Hz, not the row at 1100 Hz); Tx5 is enabled without a message while the other empty slots and the Tx5 Next choice are not; edit_message {slot tx5, text "tnx 73 gl"} is sent and nothing transmits; no page errors.
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
        doc /* (#60) The QSO pane shows the QSO dialogue as a table with the header row "UTC | Direction | Exchange | Rep | Rx SNR | Tx SNR", and the stations calling me (Others, ⚠ after the time while a QSO runs) as rows of the same table and columns below a thin separator. UTC is the period start HH:MM:SS with no ◂/▸ mark after it. Direction is the two calls in the Band Activity order, recipient first and sender second, with "◂" between them pointing to the recipient ("HB9BLA ◂ CT1BFP" received from CT1BFP, "CT1BFP ◂ HB9BLA" sent by me; a hashed call as decoded); a CQ is "CQ <call>" or "CQ DX <call>" without an arrow and its grid is the Exchange. Exchange is the message after the two calls; a message that is neither (free text) is all Exchange. Rep is "×N" when the identical message repeated N > 1 times, else empty (operator 2026-11-03: its own column). On every dialogue row, received and sent alike (operator 2026-11-03), Rx SNR is our measured SNR, signed, of the latest received dialogue entry at or before that row, and Tx SNR is the latest report the partner sent us at or before that row ("R-02" gives "−2", a plain report "-05" gives "−5"); each is empty only while no such value exists yet. An Others row shows its own SNR and its own report, if any. The pane is content high at the top of its column, its table area at most the header row and 6 rows, scrolling inside at its newest row, so the height below the pane is free for the #37 Control panel and error field (#37 item 8, operator 2026-11-03: "The QSO part is way too long"); it does not grow the page (TC-007-009) and the table fits 360 CSS px, the titles abbreviated and the Direction calls wrapping at their spaces there. Details: WstxOperatingLayout::QsoPane items 3 and 7. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js";
    }
    dependency CL_060_01_to_FR_007 from 'CL-060-01' to 'FR-007';
    dependency CL_060_01_to_FR_019 from 'CL-060-01' to 'FR-019';
    verification 'TC-060-001' {
        doc /* TC-060-001 — QSO pane dialogue table
             CL-060-01
             Setup: actual candidate server and Chromium at 1366x768; routed ContactSnapshot of a running QSO of HB9BLA with CT1BFP whose dialogue holds a sent CQ, the operator's #60 example (received IM59 +8, sent +08, received R-02 +7, sent RR73, received 73 +9, here repeated twice with my call hashed and unknown) and a sent free text; routed live rows of callers of my call: DL1ABC JO31, an unknown hashed call with RR73, a known hashed call <PJ4/K1ABC> with the report -05, and EA8BIA IL18 near my Rx.
             Steps: read the header cells and every #qso-dialogue and #qso-others row's cells idle and while the QSO runs, the separator above the Others, the page scroll and the header position, then at 360x800 the table and page widths; screenshots at 1366x768 and 360x800.
             Expected (independent oracle: the literal operator table of #60 and its 2026-11-03 Rep and every-row SNR requests): header UTC, Direction, Exchange, Rep, Rx SNR, Tx SNR; idle Others [12:00:15, HB9BLA ◂ DL1ABC, JO31, "", −8, ""], [12:00:15, HB9BLA ◂ <...>, RR73, "", −12, ""], [12:00:15, HB9BLA ◂ <PJ4/K1ABC>, -05, "", −5, −5], [12:00:15, HB9BLA ◂ EA8BIA, IL18, "", 0, ""]; dialogue [22:51:00, CQ HB9BLA, JN37, "", "", ""], [22:51:15, HB9BLA ◂ CT1BFP, IM59, "", +8, ""], [22:51:30, CT1BFP ◂ HB9BLA, +08, "", +8, ""], [22:51:45, HB9BLA ◂ CT1BFP, R-02, "", +7, −2], [22:52:00, CT1BFP ◂ HB9BLA, RR73, "", +7, −2], [22:52:15, <...> ◂ CT1BFP, 73, ×2, +9, −2], [22:52:30, "", TNX 73 GL, "", +9, −2]; during the QSO the Others [12:00:15 ⚠, HB9BLA ◂ EA8BIA, IL18, "", 0, ""] with a 1 px top border; no page scroll at 1366x768, the header row visible with the area at its newest row; at 360 px no horizontal overflow and the table within the pane.
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
        doc /* (#37) The error field, a small block below the Control panel that replaces the top-bar exception chips, lists only the problems that still apply and need the operator to act (CAT or radio, audio input missing or its level too low or too high, clock unsynchronized or unknown, a transmit refusal the operator must fix, a failed band/mode change, receive stopped, the station connection lost, a station update or rejected data), one line each with its cause and "since HH:MM" UTC. An entry disappears by itself when its condition clears; there is no acknowledge control and no history; transient events (a retried refusal, busy, stale revision, a receive restart) are no entries. With no entry it shows "No problems". A click opens the entry's detail as the chip did. Details: WstxOperatingLayout::ErrorField, ErrorFieldEntry. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.css";
    }
    dependency CL_037_02_to_FR_019 from 'CL-037-02' to 'FR-019';
    requirement 'CL-037-03' {
        doc /* (#37, operator 2026-11-03 "We have two HALT buttons ...") The operating view shows one HALT, the QSO pane's; the top-bar HALT shows whenever the QSO pane HALT is not fully on screen (a page or the Settings drawer covers the workspace, or the stacked pane is scrolled out of view), so a pointer HALT is always on screen; Esc and Alt+H halt everywhere. The QSO pane's direct buttons are CQ, Tune, HALT and Log QSO: RR73 and 73 are gone (Auto Seq sends them) and each Tx1-Tx6 line of the fold-out has Next and Now, Now choosing it next and turning Enable Tx on (from the next own period), disabled on a completed or cancelled contact. Reply is gone since the #50 double-click fix is installed: a double-click on a Band Activity or Others row, or the row menu Reply, starts the reply. Details: WstxOperatingLayout::OperatingScreen, QsoPane item 5. */
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
             Setup: actual station Router and browser client with scripted contact snapshots and contact command replies (explicit presentation fixtures).
             Steps: click CQ while the station refuses one command with stale_revision and moves its revision; click CQ while it refuses three.
             Expected (independent: the scripted revisions): CQ sends enable_tx with revision 3, then 4 (accepted); then 4, 5, 6 and shows the refusal. On the parent client CQ sends once.
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
             Setup: the gated candidate installed on HB9BLA, 40 m FT8 and FT4, CQ at 1 W, one browser on the LAN.
             Steps: call CQ for at least three own periods; watch Band Activity, the waterfall, the meter and the error field; read GET /receive during a Tx period.
             Expected: each Tx period shows the Tx marker and no empty block, its waterfall rows are Tx rows, no "Audio level low" entry appears in or right after a Tx period, the receive periods decode and show their level; audio.loss_epochs does not grow from the transmissions; HALT stops the transmission as before.
             3 — Live on the station with transmission; with the operator at acceptance. */
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
             Setup: actual station Router and browser client at 1366x768 (device scale 1) with a scripted correlated live receive and Detailed frames, Speed 1 (10 CSS px/s) (explicit presentation fixtures).
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
             Setup: the installed station on HB9BLA, IC-7300, the operator's browser in its usual theme.
             Steps: run a QSO with several Tx periods and look at the waterfall during and after them.
             Expected: each Tx period shows only a thin dark red band; no white or grey band appears while transmitting; the time labels below a band are the source times of those rows.
             3 — Live on the station with transmission; with the operator at acceptance. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-061-05';
        }
    }
    dependency CL_061_05_verified_by_TC_061_009 from 'CL-061-05' to 'TC-061-009';

}
