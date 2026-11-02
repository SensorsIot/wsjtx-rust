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
        doc /* The common browser MUST show exact supported payload fields, unresolved hash identities, UTC period time and relative DT when correlated or explicit unknown timing under4.7.4, lowest-tone audio frequency and calibrated SNR or explicit unavailable SNR, with reliable bounded result delivery. */
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
             hashes, free text, telemetry) to the WSJT-X 77 bits, CRC-14 and LDPC
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
             transmit state in the browser. Details: WstxTransmit::TransmitClock,
             TransmitWire. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/clock.rs; server/src/transmit_http.rs; server/src/main.rs; client/recording.js";
    }
    dependency CL_009_05_to_FR_006 from 'CL-009-05' to 'FR-006';

    verification 'TC-005-001' {
        doc /* TC-005-001 — FT8 message, symbol and waveform encoding
             CL-009-01
             Setup: fixtures/transmit/ft8code-vectors.json generated by
             fixtures/transmit/generate.py with WSJT-X 3.3.0-beta5 ft8code.exe
             (ft8code "<message>", tool hashes recorded, beta4 output identical) for 75
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
             peer.
             Steps: request while disarmed; arm with unsupported/unavailable capability,
             a wrong safety revision and without a grant; FT8 request before the period,
             late, stale, misaligned, unsynchronized/unknown clock, bad text and offset,
             duplicate sequence; replacement before and after audio start; halt
             mid-audio on the virtual clock, through the owner thread and through the
             real actor; audio device loss, CAT loss, key timeout, output open failure,
             safety revision change; restart; Tx watchdog expiry and Tune limit;
             lifecycle polling with the transmit owner present; malformed and extra-key
             wire bodies, wrong Origin, stale boot, retained command_id.
             Oracles: no PTT or audio call/byte while disarmed or unauthorized or
             without an opened output; PTT bytes exactly FE FE 94 E0 1C 00 01 FD and
             1C 00 00 with 1C 00 readback; open before key at the period start, audio at
             period start + 500 ms with skip 0, late skip (t-500 ms)*48; replaced and
             audioStarted outcomes in order; halt releases within 250 ms and disarms;
             every failure stops audio, attempts release and disarms with its cause; an
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
        attribute executable : String = "server/tests/transmit_service.rs; server/src/transmit_http_tests.rs";
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
             ft4sim.exe (ft4sim "<message>" 1500.0 0.0 0 0 1 99, hash recorded) for 86
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
             request.
             Expected (independent hand-written values): (a) Tx4 text
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
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs";
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
        doc /* Present the laptop operating screen of WstxOperatingLayout::OperatingScreen: a top bar with only band, mode, dial, UTC/period, exception chips, Logbook, Settings and HALT; the full-width waterfall with the Rx/Tx strip; Band Activity with the strategy element and the QSO pane with direct buttons and no Enable Tx control; setup and diagnostics in the four-section Settings drawer; themes; WSJT-X keyboard shortcuts; and only the token form for an unauthorized browser. Details: OperatingScreen, RxTxStrip, BandActivityView, QsoPane, SettingsDrawer, ThemeChoice, UnauthorizedView, KeyboardShortcuts, WstxContact::SetEnableTx. */
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
    // CL-010-04 partial coverage, open item: ExportAdi built in memory rather than
    // streamed with backpressure. #41 retired the #10 log review queue: completion and
    // Log QSO log directly (WstxContact::DirectLog); TIME_ON/TIME_OFF come from the
    // contact engine (server/src/contact.rs).
    // CL-010-03 partial: physical RF acceptance (TC-007-007) is unexecuted; MCP exposes
    // the same contact operations through WstxMcp (#12). CL-010-11 partial: since #37 the
    // browser sends no re-decode; the wire redecode stays refused redecode_unavailable.
    // CL-010-13 partial: worked-before marks are not yet shown in the Rx Frequency pane.
    // CL-010-15 partial: TC-007-005 Thin/Off measurement with the new events and MCP.
    requirement 'CL-010-04' {
        doc /* Log every completed contact directly, without a review step (#41, as WSJT-X): at completion and on a manual Log QSO the server stores the contact's record in the profile directory's ADIF 3.1.8 contacts.adi with its contact identity and sends it to the WSJT-X UDP targets as QSO Logged and Logged ADIF; exactly one record per contact identity (an identical re-log adds nothing, completion after an early Log QSO replaces it; each contact is sent to the UDP targets once), a later contact with the same station a new record, Saved only after durable acknowledgement, a failed write visibly unsaved and retried; and ADI import/export/history with the stated limits, identity, duplicate/conflict and unknown-field rules. The former log review queue (OfferLogReview, discard_review, the review form) is retired. Details: WstxContact::LogRecord, DirectLog, SaveContact, ImportAdi, ExportAdi, ContactHistory, AdiLimits; WstxUdp::OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::partial;
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
        doc /* Present bounded Band Activity and the Rx Frequency pane routed as WSJT-X (within +/-10 Hz of the confirmed Rx offset, messages to my call, my call with the DX call, own transmissions labelled Tx); local filtering, sorting, highlighting and clearing change no server decoding, contact state or log. Details: WstxContact::RoutesToRxFrequencyPane. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "client/contact.js; client/recording.js";
    }
    dependency CL_010_06_to_FR_004 from 'CL-010-06' to 'FR-004';
    dependency CL_010_06_to_FR_007 from 'CL-010-06' to 'FR-007';
    dependency CL_010_06_to_FR_021 from 'CL-010-06' to 'FR-021';
    requirement 'CL-010-10' {
        doc /* Bound unattended transmission with a server-owned Tx watchdog (default 6 min, 1..99, counting only while Enable Tx is on, reset by accepted operating requests and changed transmitted text; expiry halts and disarms) and an always-on Tune watchdog (default 90 s, 1..300 s). Details: WstxContact::TxWatchdog, TuneWatchdog. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/transmit/service.rs; client/contact.js";
    }
    dependency CL_010_10_to_FR_008 from 'CL-010-10' to 'FR-008';
    requirement 'CL-010-11' {
        doc /* Set Rx and Tx audio offsets through labelled numeric inputs and waterfall pointer actions (click Rx; shift- or right-click Tx; ctrl-click both; left double-click Rx only; right double-click both; dragging the Rx/Tx markers and the Rx/Tx strip fields with 1 Hz/10 Hz steps), Hold Tx protecting only against implicit moves, each confirmed by the server and none enabling transmission. Details: WstxContact::PointerEffect, FrequencyControls. */
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
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/logbook.rs; server/src/logbook_http.rs; client/logbook.js";
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
             Steps: filter/sort/clear Band Activity; read the Rx Frequency pane over several periods with rows at 1489.9, 1490.0, 1510.0, 1510.1 Hz, "HB9BLA W1XYZ -10" at 400 Hz, "K1ABC HB9BLA R-05" at 2500 Hz, "HB9BLAX K1ABC" and own transmissions; change Rx; exceed 500 pane rows; select rows by click/Enter and by manual DX entry; switch profile.
             Expected (fixed input catalogue): pane contains exactly 1490.0, 1510.0, the HB9BLA and HB9BLA-plus-K1ABC rows and Tx-labelled own messages, not 1489.9, 1510.1 or HB9BLAX; Rx change affects later rows only; at most 500 rows with unread count; clearing the pane or Band Activity sends no request and changes no contact/log; selection sends the exact identity and changes the partner only after acceptance; unresolved/old/wrong-profile rows cannot prepare a contact; no invented UTC/callsign, executable markup or cross-profile state.
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
             Steps: run a UDP listener on 127.0.0.1:2237 enabled as a WSJT-X UDP target with QSO Logged and Logged ADIF; complete at least one contact answering a real CQ and, if band conditions allow, one by calling CQ, with Auto Seq, without pressing Log QSO; then Enable Tx without operator activity until the Tx watchdog (set 1 min for the test) expires; Halt once during a transmission; restart the server.
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
             Steps: Enable Tx with limits 1, 6 (default) and 99 minutes; refuse 0 and 100; let periods pass with identical and changed transmitted texts; send accepted and refused operating requests at 5:59; disarm and re-enable; Tune with 90 s default, 1 and 300 s, refuse 0 and 301; Halt during Tune.
             Expected (hand-computed timeline): expiry exactly at the configured whole minute after the last reset while Enable Tx stays on; changed text and accepted requests reset, identical text and refused requests do not; the counter is 0 while disarmed; at expiry a halt request precedes Enable Tx off, the contact state is kept and "Tx watchdog expired" is shown; Tune ends at its limit through #9; remaining minutes/seconds displayed; startup default 6 min and 90 s.
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
             Steps: at independently computed pixel positions for 200, 1500 and 2950 Hz perform click, shift-click, right-click, ctrl-click, left and right double-click, each with Hold Tx on and off; touch tap; numeric Rx/Tx inputs with 0/3000 Rx and 199/200/2950/2951 Tx.
             Expected: requested offsets equal the independently computed axis frequency rounded to integer Hz; click Rx only, shift/right Tx only, ctrl and right double-click both, left double-click Rx only and no re-decode request; Tx pointer actions apply with Hold Tx on; markers move only after confirmation; out-of-domain refused; no Enable Tx request; the browser context menu does not open on the waterfall.
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
             Steps: complete a contact (transmitted Tx5 73 after the partner's report; received 73 in rogers); repeat the completion events; manual Log QSO before completion, then completion; Log QSO again unchanged; storage failure at completion, then recovery; restart; the same call again as a new contact; SaveContact with power 10 and comment, invalid power -1, comment with CR/LF or 1025 characters, repeat save; second profile; the browser Log QSO button.
             Expected (independent record catalogue and direct file reading): each completion stores exactly one record with the hand-computed CALL, GRIDSQUARE, MODE/SUBMODE, RST_SENT/RST_RCVD, QSO_DATE/TIME_ON (first transmitted Tx2/Tx3 rule), TIME_OFF, BAND, FREQ = dial + Tx offset, STATION_CALLSIGN and MY_GRIDSQUARE, and the UDP target receives one QSO Logged and one Logged ADIF for it; repeated completion and an unchanged Log QSO add no record and no datagram; completion after an early Log QSO replaces that record in place (one record, end time of completion) and sends no second datagram pair; Log QSO of a completed contact keeps its completion record even after a location change; a UDP FreeText command arriving while a retry is due returns (no lock re-entry) and the datagrams follow; a failed write leaves the record unsaved with storage_unavailable shown and is stored by the retry; nothing is logged again after restart; the second contact with the same call is a separate record; SaveContact identical resave alreadySaved, changed resave conflict, invalid fields refused; the browser shows no review form and sends no POST /contacts; no cross-profile record or browser-clock time.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-010-04';
        }
        attribute executable : String = "server/src/logbook_tests.rs; server/src/logbook_http_tests.rs; server/src/contact_tests.rs; server/src/contact_http_tests.rs; tests/contact.test.cjs; tests/ui-operating.test.cjs";
    }
    verification 'TC-011-002' {
        doc /* TC-011-002 — ADI interchange and boundaries
             CL-010-04
             Setup: hand-authored ADIF 3.1.8 ADI fixtures across line/tag/record boundaries and case variations with CALL, GRIDSQUARE, MODE, RST_SENT, RST_RCVD, QSO_DATE, TIME_ON, QSO_DATE_OFF, TIME_OFF, BAND, FREQ, STATION_CALLSIGN, MY_GRIDSQUARE, TX_PWR, COMMENT and APP_WSTXRUST_CONTACT_ID; duplicate/conflicting identities, records without APP_WSTXRUST_CONTACT_ID matching and not matching stored natural keys (CALL case, TIME_ON HHMM vs HHMMSS, BAND vs FREQ only), unknown and other APP_ fields, malformed lengths, unsupported characters, exactly 64 MiB/100,000 records/1024-character field and each one over, a wrong sha256.
             Steps: import, retry the same import_id with identical and different total/sha256, export, reopen, page history at cursor 0, total-1 and total with limit 1/10/11.
             Expected (independent ADI parser): exact field values and lengths, FREQ six decimals in MHz, no silent truncation or commands from data; the independently counted new/duplicate/conflict numbers; any conflict, invalid or over-limit input publishes zero records with record/field context; natural-key matches are duplicates, id matches with a differing field conflicts; new records without id gain one; unknown fields re-export byte-identical; same import_id retry has no second effect, different values state_conflict; history pages hold stable indexes, limit 11 refused, at most 16384 bytes; export then import yields only duplicates.
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
             Expected: K1ABC this band and mode; W1XYZ and DL1ABC other band or mode; N0NEW not worked then this band and mode after the save; hashed unknown; the indication is text/icon plus colour in Band Activity and the Rx Frequency pane; one query per period with at most 64 calls (the 65th unknown); no change to decoding, sequence or log.
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
                envelope, matching ID, candidate package version and radio state unconfigured.
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
        attribute executable : String = "server/tests/decoder_signal.rs::independent_waveforms_decode; server/tests/decoder_signal.rs::quality_corpus; server/tests/decoder_signal.rs::official_modern_recording_baselines";
    }
    verification 'TC-004-002' {
        doc /* TC-004-002 — Offline FT8
             FR-003, FR-004, FR-018; CL-007-01, CL-007-02, CL-007-03, CL-007-04
             Load independently labelled FT8 recordings, select FT8 and run the candidate decoder under the selected signal conditions.
             Decoded fields agree with the independently established expected results; misses, incorrect decodes and runtime meet the agreed FT8 budgets.
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
        attribute executable : String = "server/tests/decoder_signal.rs::quality_corpus; server/tests/decoder_signal.rs::independent_waveforms_decode; server/tests/decoder_signal.rs::crc_valid_unsupported_and_invalid_payloads_are_retained; server/tests/decoder_signal.rs::official_modern_recording_baselines";
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
             Native k256=750Hz and k257=752.9296875Hz remain separate values; Hann leakage/interference is compared to the independent DFT, not an assertion that adjacent equal tones must form two local maxima. 750/756.25Hz signal retains independently predicted bin peaks/valley; no four-bin pooling or frequency resampling. Prequantized error <=0.05dB on independently specified bins above -80dBFS and absolute amplitude error<=2e-6 elsewhere; quantized values differ by <=1 level from independently rounded DFT, exact silence0. One coherent half-amplitude tone gives -6.0206dBFS before PCM error. Row assignment uses global hop480: five starts/full2400-frame row, one to five at EOS, including start2400 in source_frames2401. Independent mean-square amplitude then10log10 differs from Thin maximum and from averaging dB; zero Hann endpoint yields legitimate final silence for2401. Intervals are2400 frames, shortened EOS, sequence<=599. One source/worker, two latest frames, declared workspace/history limits and cancellation release<=250ms remain; stale publications cannot overwrite either profile. Thin numerical expectations from TC-010-001 remain unchanged. */
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
             Cost2, automated Windows real browser/candidate server plus deterministic injected wire fixtures. Exercise cleartext loopback and HTTPS defaults; explicit three-profile changes, old Thin-only/older server, simultaneous Thin/Detailed peers, malformed base64 alphabet/padding/pad bits/decoded lengths/values, unknown/missing keys, safe-integer/interval edges, wrong tuples/old sockets and skipped sequences. Use alternating known quantized levels in adjacent native bins/rows and read actual getImageData at1100x850 and360x640, DPR1/2,200% zoom, splitter extremes, resize and repaint; exercise Auto silence-then-noise, lower-median/round/clamp vectors, freeze/reset/manual overrides and range/legend/readout consistency. Retain actual busy FT8 recording desktop/mobile screenshots and compare their trace/noise contrast, orientation and rulers qualitatively with WSJT-X/FlexRadio reference images. Stall Detailed output with a controlled sink returning Pending, then issue status/control and cancel/off.
             Detail events have exact schema,1024 decoded bytes, canonical1368-char base64 and<=2048 UTF-8 bytes; exactly-at-limit values accepted and malformed/obsolete input leaves canvas/history unchanged. No >5Hz Detailed or >1Hz Thin, backfill or second worker. Thin/control input1024 and binary1003 guards preserved. Optional write test independently requires readiness/control priority,4096 cap,1024+28 control reserve, unchanged2s removal from first pending write; Detailed fast-link status responses display<=2s on unshaped localhost with two peers. TC-010-002 unchanged TLS32kbit/s Thin/Off regression still runs. Every origin defaults Detailed; explicit saved Thin/Off is honored and fallback attempts Thin once and labels unavailability. Pixel oracle computes integer edges/fixed source-time cell edges from contract, samples interiors and both sides of boundaries for exact palette colors/uniform cells, using independently calculated RGB interpolation/rounding from the stated anchors, with grey gaps and dark unobserved areas on a full-height canvas; no blended spatial colors. New rows enter at top; Auto ignores median0 then locks once at median-3dB, manual Black/Range disables it, job/profile reset restores30dB/Auto and original calibrated data remains invariant. Frequency500/100Hz ticks and visible source-time5s ruler agree with pixel/readout positions and clipping. Fixed0..3000Hz axis endpoints/ticks through resize/DPR/zoom, no horizontal frequency scroll, unmodified native1024-value buffer, peak-preserving max projection with every bin contributing at widths below1024, native/projected readout centers/ranges/levels/intervals, keyboard selection, recent-row orientation,600-row cap and no page overflow hold through geometry changes. Thin uses the same integer geometry with128 bins; original numerical/wire values stay unchanged. A narrow strong tone at every native-bin position contributes to its assigned column and never disappears when W<B. Screenshots establish actual layout and independently synthesized data establishes numerical correctness.  Preference persistence: with disposable browser storage and actual server/Chromium, verify unchanged defaults without a valid choice; explicit Detailed/Thin/Off survives reload and reopened browser context; origins/ports and profile UUIDs are isolated while boot/revision changes preserve choice. Invalid value or denied storage uses normal defaults without page error and leaves in-memory selection usable. Inspect only versioned UUID keys and enumerated values, with no secrets. Unknown-command runtime Thin fallback preserves stored Detailed; subsequent explicit Thin replaces it. Existing subscription commands, no retry loop, Detailed bounds and Thin32kbit/s tests remain unchanged; no synthetic decoded records are used. */
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
             Cost2 automated Windows real browser/candidate fixtures. Inject independently known native rows of2,75,600 Detailed or120 Thin values with contrasting bins/rows and gaps; inspect actual RGBA/backing and CSS box dimensions at desktop1100x850/mobile360x640, DPR1/2,200% zoom and splitter bounds. Exercise Sensitivity-30/0/+30 and Speed1/2/8 via input, keyboard and numeric outputs, manual Black/Range, Auto silence/noise/freeze/reset, new jobs/profiles and resize. Replay actual busy FT8 with a red saturated carrier, capture desktop/mobile screenshots and move both live sliders.
             Independent oracle: palette endpoint/saturated cells are exactly[255,0,0,255], floor/no-signal[0,0,12,255], no white signal cells; legend uses identical RGB anchors/endpoints. With base B=-83,R=30, g=+10 yields E=-93 and g=-30 yields E=-53, clamped[-120,-R]; original row arrays, source/job/generation and curve base scale stay unchanged. Sensitivity does not disable/re-estimate Auto; manual Black/Range does, new-job/profile resets only existing base/Auto settings and preserves both slider values. Fixed source-time scrolling, independent pixel movement, clipping, gap and unobserved-region oracles are specified in TC-010-007. Native/projected readouts and rulers agree with that mapping. Spectrum/waterfall CSS heights follow1:5 within2CSSpx rounding, actual bitmap sizes equal rounded CSS boxes times DPR, neither geometry nor intrinsic height drifts over repeated paints. No horizontal overflow/changed0..3000Hz span, interpolation, fake history or network/source-rate change. Real FT8 screenshots show a full-height waterfall canvas with unobserved regions dark, dark floor, red strongest traces and visible working live sliders; original numeric/wire/security/Thin32k assertions remain. */
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
             development PC; no radio, audio device or network service. At 1366x768: no page
             scroll or horizontal overflow; the top bar holds only the TopBarItem set; no Monitor,
             Enable Tx, Start/Stop receive or Next receive mode control exists; no status text or
             chip is shown for a healthy station and each injected exception (stale link, receive
             stopped, unknown receive outcome, audio unavailable) shows its chip, which opens its
             detail; the Rx/Tx strip, Band Activity with the strategy element and the QSO pane are
             visible. At 360x800 the page does not overflow horizontally. The Settings drawer has
             exactly General, Radio, Logging & Reporting and Expert and every control that left the
             operating screen is reachable there, with HALT visible and the waterfall running; a
             restart change during an active contact asks before Apply. Rx/Tx strip steps (1/10 Hz),
             Tx=Rx/Rx=Tx and Hold Tx send exactly the expected contact requests. Band Activity shows
             history newest first with period dividers, double-click replies (select then
             enable_tx) and the right-click menu acts. QSO pane CQ/Reply/RR73/73 send enable_tx with
             the shown safety revision; on a completed contact RR73 and 73 are disabled and a forced
             click sends no enable_tx. With the confirmation popup open during an active QSO its HALT
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
             Independent oracles: the design-interview decisions in the
             model, not the candidate markup. Screenshots at 1366x768 and 360x800. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-010-16';
            verify 'CL-045-01';
            verify 'CL-040-02';
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
                reconciliation reads using recorded CDP initiators and the exact frozen caller
                mapping, joined to validated request/response identity. A pending-context pair is
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
             mode/reconnect retention and profile reset; verify no new server mutations or changed
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
             acceptance (TC-022-010) remains outstanding. */
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
             confirmed in ready. Still target: Thin/Off accounted-traffic companion
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
             Planned companions: tests/communication.test.cjs and tests/recording.test.cjs TC-010-002; same traffic windows and ceilings. */
        attribute automation : AutomationState = AutomationState::planned;
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
             failed close zero reopen, query-only bytes), server/src/auth_tests.rs
             automatic_cat (real grant/commission flow, zero I/O before commission,
             endpoint edit and last-grant revocation release, deprecated routes409
             zero I/O, status retry reason) and tests/radio-selection.test.cjs
             TC-022-009 (browser confirm action, no Connect/Disconnect, retry reason,
             non-fresh frequency). Pending: corrupt-store case, concurrent RF-work
             arbitration case and real Windows native release/cancel measurement. */
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
        doc /* An MCP client observes exactly the browser's station views (profile, receive, selection, radio, transmit, contact, automation and decoded result pages) and operates through the same ContactCommand, HaltTransmit and AutomationCommand bodies, receipts, revisions, command_id idempotency and refusal codes as the browser, for FT8 and FT4. Details: WstxMcp::ToolCatalog, ToolResult. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/mcp.rs; server/src/contact_http.rs; server/src/automation.rs";
    }
    dependency CL_012_02_to_FR_020 from 'CL-012-02' to 'FR-020';
    dependency CL_012_02_to_FR_007 from 'CL-012-02' to 'FR-007';
    requirement 'CL-012-03' {
        doc /* MCP authorization is explicit: exactly one Authorization: Bearer field carrying a current auth-v1 (CL-022-01) grant transport of this station, checked by the same authority owner per request; cookies sent to /mcp are never read, a plaintext profile has no MCP access, a present Origin must be the station's. Transmit-capable operations need that grant like the browser's. Automation is station-owned, unconfigured and stopped at every boot, starts only on an explicit start with a current grant transport and the current acknowledged safety revision, lives no longer than that transport and its maximum duration, is shown read-only in the browser station bar, never takes over an operator's CQ or contact, and stops at Halt (also one racing its arming, answered with a Halt), explicit stop, lost or replaced transport, receive context or mode change, contact change, disarm, no answer, completion or its contact limit, never replaying a transmit action or leaving a selected unarmed contact. Details: WstxMcp::McpCredential, OperatingAutomation, AutomationIndicator. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/mcp.rs; server/src/automation.rs; server/src/authorization_http.rs; server/src/main.rs; client/contact.js";
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
             Setup: (a) actual candidate router on a selected HTTPS profile (HB9BLA, JN47AA) with its auth-v1 owner, the contact engine and the #9 transmit owner on the recording hardware double, an injected FT8 live job and hand-authored codec-packed rows "CQ K1ABC FN42" 1234.6 Hz -12.4 dB and "CQ W1AW FN31" 900.0 Hz -3.0 dB; one enrolled grant; an independent JSON-RPC test client. (b) The compiled executable on a disposable HTTPS profile with a throwaway certificate, the tools/wstx-mcp-credential.cjs helper and a separate browser-style grant.
             Steps: modern server/discover and tools/list; wstx_read of every view and GET of the same browser route; wstx_results and the same GET /receive/results; legacy initialize, notifications/initialized, tools/list and tools/call; (b) helper enroll and header, then tools/list and wstx_read profile/contact against GET /profile.
             Expected (WstxMcp tables and the fixture's own identities): supportedVersions exactly [2026-07-28, 2025-11-25, 2025-06-18]; tools exactly wstx_read, wstx_results, wstx_contact_command, wstx_transmit_halt, wstx_automation_command in this order and identical in both eras; each view equal to the browser response apart from the per-read monotonic_ms/utc_ms; profile_id/boot_id the fixture's; automation configuration and run null; the two rows with their literal text, frequency, SNR and sequences; legacy protocolVersion 2025-11-25, no Mcp-Session-Id, no resultType; the text content equals structuredContent; no PTT exchange.
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
             Setup: as TC-020-001 (a) plus a second HTTPS station with its own grant and a plaintext station; (b) the executable with a browser-style grant.
             Steps: no Authorization, the browser cookie alone, lower-case scheme, a malformed, unknown or other station's token, two Authorization fields, the plaintext station; a foreign Origin, GET, text/plain, BODY_MAX+1 bytes, invalid JSON, a batch, jsonrpc 1.0, id null or 1.5, array params, legacy version 2024-11-05, a legacy request without MCP-Protocol-Version and with 2025-03-26; modern version 1900-01-01, Mcp-Method and Mcp-Name mismatch, a Base64-sentinel Mcp-Name, resources/list, unknown tool wstx_raw_ptt; tool arguments with an extra key, an unknown view, a query-injecting source_id; ContactCommand with another station's profile_id, a future contact_revision, action key_ptt, another job's row, another boot; automation start unconfigured, configure with max_contacts 0, start with safety_revision 4 while 3 is current; then a valid MCP enable_tx, its exact retry and a changed body with the same command_id, and an MCP Halt; (b) the browser cookie on /mcp, the same transport as an explicit bearer, a key file of another origin, enroll with a wrong bootstrap token.
             Expected (independent refusal catalogue): 401 with WWW-Authenticate Bearer realm="wstx" for every credential case and the plaintext station; 403, 405, 415, 413; JSON-RPC -32700, -32600 (each malformed envelope), -32022 with data {supported,requested} (also for 2025-03-26), -32020 (also for the missing legacy header), -32601 with 404, -32602; tool errors status 400 invalid_request with the field (extra, view, source_id) and no station call; station refusals 403 wrong_profile, 409 stale_revision, 400 invalid_request action, 409 row_unavailable, 409 state_conflict boot_id, 409 not_configured, 400 max_contacts, 409 stale_revision safety_revision; before the valid enable_tx the contact revision, contact, arm state, policy revision and PTT log are unchanged; enable_tx 202 and armed, retry 200 with the same receipt, changed body 409 state_conflict command_id; Halt 202 and disarmed; (b) cookie 401, explicit bearer 200, helper exits nonzero without output, refused enroll writes no key file.
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
             Setup: actual candidate router, contact engine and #9 transmit owner on the recording hardware double with virtual UTC (bench set 1 s after an even FT8 period E), injected FT8 or FT4 live job, hand-authored codec-packed rows, the MCP test client with one grant; each run start follows a browser action of the operator (#39: MCP requests never start the Tx watchdog).
             Steps: (a) pure CandidateSelection table: rows 0 CQ K1ABC 1500 Hz -12, 1 CQ W1AW 900 Hz -3, 2 CQ DL1XYZ 2100 Hz unknown SNR, 3 HB9BLA K1ABC -05, 4 CQ HB9BLA, 5 CQ W1AW 950 Hz -1, 6 CQ AA1AA 900 Hz -3, under each ranking, min_snr_db -5 and -3, allowed/blocked lists and a worked call; AutomationConfiguration bounds and every malformed key. (b) A row before start; configure strongest_snr / next_candidate / max_contacts 2 and start; publish K1ABC -12, W1AW -3, DL1XYZ unknown at E; partner "HB9BLA W1AW -05" at E+30 s, "HB9BLA W1AW RR73" at E+60 s; run the own period E+15 s to its end; publish W1AW -1 and K1ABC -12; stop; publish again; stop again. (c) A second start and a configure while running; selection, MCP Halt; retry of the original start command_id; start with the old revisions; a start over the left contact, cancel, start, browser Halt while waiting. (d) first_seen with max_unanswered_periods 2: two publications without the partner; restart; a new live job; restart; revoke the grant. (e) FT4: configure modes [ft4], start ft8 and ft4, publish two CQ rows. (f) max_contacts 1 with next_candidate, one completed contact; then completion_action stop, another completed contact, a later CQ. (g) A Halt injected between select_row and enable_tx. (h) max_run_minutes 1 with the step clock 59 s and 61 s ahead; max_run_minutes 480, start, a newer proof of the same grant, a CQ; start, clock 8 h - 60 s and 8 h + 1 s ahead. (i) While waiting: the operator's Enable Tx (CQ), then a CQ row; the operator's manual contact W1AW, then a CQ row of W1AW; while in the run's contact: operator cancel, operator Enable Tx off, operator replacement by DL1ABC. (j) start with safety_revision 4 while 3 is current; select_row refused with the profile callsign removed; enable_tx refused after transmit became unsupported.
             Expected (hand table): (a) first_seen K1ABC, W1AW, DL1XYZ, AA1AA; strongest_snr AA1AA, W1AW, K1ABC; lowest_frequency AA1AA, W1AW, K1ABC, DL1XYZ; min -5 and -3 W1AW, AA1AA; allowed K1ABC, DL1XYZ; blocked K1ABC, DL1XYZ, AA1AA; worked K1ABC excludes it; null unconfigured, every bound admitted and each malformed value refused with its field. (b) nothing selected before start or from the earlier publication; W1AW selected (candidates 2), replying, Tx1 "W1AW HB9BLA JN47", parity odd, Rx 900, armed; roger_report, signoff with Tx5 "W1AW HB9BLA 73"; after the own period completed, disarmed, last text "W1AW HB9BLA 73", run waiting with completed_contacts 1; K1ABC then selected and armed (W1AW worked); stop 202 stopped, reason stopped, disarmed, no Halt request; no later selection; second stop stale_request. (c) state_conflict run for both; armed then Halt: stopped/halted; retry 200 with the original receipt and no new run; stale_revision expected_run_revision; later rows select nothing and leave W1AW disarmed; state_conflict contact, then a waiting run ended halted by the browser Halt with the contact still cancelled. (d) W1AW selected; no_answer after the second publication, disarmed; context_changed and disarmed after the new job; authority_lost with nothing selected; MCP then 401. (e) not_ready mode for ft8; FT4 W1AW selected, Tx4 rr73, armed. (d) also: own (odd) period publications are not counted (unanswered 0 then 1 after the first even one, no_answer after the second even one). (f) limit_reached with completed_contacts 1; completed, no later selection, disarmed. (g) stopped halted, disarmed, HaltTransmit count + 2, PTT never keyed, no later arming. (h) waiting at 59 s, time_limit at 61 s; authority_lost with nothing selected after the newer proof; waiting at 8 h - 60 s, authority_lost at 8 h + 1 s. (i) contact_changed with the operator's CQ still calling and armed and not taken over by the later row; contact_changed with the manual_entry contact kept; contact_changed after cancel; transmit_stopped without a HaltTransmit; contact_changed with DL1ABC disarmed. (j) 409 stale_revision safety_revision; provider_error with no contact; transmit_refused with the selected contact cancelled (no partner left), disarmed, PTT never used.
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

    // #40 WSJT-X-compatible UDP interface with multiple targets (decisions recorded in
    // WstxUdp and on issue #40, 2026-11-01); detailed contract in WstxUdp.
    requirement 'CL-040-01' {
        doc /* Speak the WSJT-X NetworkMessage protocol (magic 0xADBCCBDA, schema 2 negotiated up to 3, Qt QDataStream big-endian) with id = the configured instance name, and send to each enabled target its selected outbound messages: Heartbeat every 15 s, Status on change, Decode for each new live FT8/FT4 decode, Clear when the live job's decodes are discarded, QSO Logged and Logged ADIF when a contact is saved, Close when a target is disabled or removed. Details: WstxUdp::UdpWire, OutboundRules. */
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
        doc /* Halt Tx from any source always acts as the HALT button (HaltTransmit), whether or not accept_commands is on. Clear, Reply, Replay, Free Text and Highlight Callsign act only from a target with accept_commands on and only on datagrams whose source is that target. No inbound command keys the transmitter: Reply prepares the QSO like a single click (ContactCommand select_row, no transmit authority) and Free Text sets the Tx5 text of a prepared contact (a standard message, as the browser edit); both are refused while Enable Tx is on, and the Send flag is ignored. A datagram too large for the receive buffer is dropped, counted and never holds back the datagrams behind it. Details: WstxUdp::InboundRules. */
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
             Expected: every Halt Tx with this id and schema 2 or 3 disarms (arm_state disarmed, last cause halt, halt count +1) with outcome applied; the schema-4 or foreign-id Halt has no effect; commands from A and from the wrong source have outcome not_accepted and change nothing; C's Reply selects K1ABC (contact replying, Tx1 "K1ABC HB9BLA JN47") with arm_state disarmed; the mismatching Reply is refused no_match; a Reply or Free Text while armed is refused tx_enabled; Free Text without a contact is refused no_contact and a non-standard text invalid_message; Free Text sets Tx5 and leaves arm_state disarmed; Replay sends the retained decodes with New false then Status, to C only; after Clear Replay sends nothing and Reply is refused no_match; highlights list K1ABC then empty; Close and Configure ignored; the 5000-byte datagram is counted ignored and the Halt Tx behind it disarms in the same step; the PTT log stays empty throughout.
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
        doc /* The Tx watchdog counts from the last operator action and is never paused or reset by automation. Only a human action in the browser is an operator action (an Enable Tx, accepted contact request or Auto start from the browser); commands of an automation run, MCP requests (including starting or restarting a run) and UDP commands never reset or extend it; their Enable Tx keeps counting from the last browser action and is refused tx_watchdog when that time is spent, until a human acts in the browser; only the browser may change the watchdog setting (set_watchdogs from MCP, UDP or automation is refused operator_required); a changed message text of a contact they armed does not reset it. HALT from any source stops everything; grant, clock, period and safety-revision checks are unchanged; there is no band hopping. Details: WstxStrategy::WatchdogFromOperator; WstxContact::TxWatchdog. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/service.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/automation.rs; server/src/mcp.rs; server/src/udp.rs";
    }
    dependency CL_039_06_to_FR_008 from 'CL-039-06' to 'FR-008';
    requirement 'CL-039-07' {
        doc /* Outstanding, issue #39 later slices: DXCC entity, CQ/ITU zone and new-DXCC conditions and the rarest sort (the cty.dat entity itself is delivered by #55, CL-055-01); Alert as a third action with history; two-tier ignore lists; Pounce; auto-QRM stop; free Tx slot finder; filtered-out view toggle; freeze Band Activity on hover; per-mode watchdog values; late-duplicate guard and false-decode heuristic; CQ-target prefer; stacked DXpedition replies. Until delivered these conditions and actions are not offered. */
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
             Setup: as TC-039-004 with the Tx watchdog set to 1 minute and role cq; for the unit case the #9 Core on the hardware double.
             Steps: start Auto at E+1 s; transmit the own CQ at E+15 s; publish a caller; transmit the report at E+45 s; move UTC to E+62 s; cancel and start Auto again. Second case, role call: start, let 61 s pass without a candidate, publish a matching CQ. Third case (MCP and browser): an MCP Enable Tx before any browser action; a browser action (watchdog 1 min), an MCP run start at 40 s and a CQ at 61 s; a browser action, MCP set_frequency at 20, 40 and 55 s, an MCP Enable Tx at 61 s, MCP set_watchdogs 99 min, an MCP Enable Tx; a browser action, MCP Enable Tx and off, browser actions at 0 and 50 s, checks at 61 and 111 s. Fourth case (UDP): a browser-path action (watchdog 1 min), a UDP Reply and Free Text from an accepting target at 50 s, check at 61 s. Unit: arm automatically before any operator action is recorded; mark activity, set the watchdog to 2 min, wait 90 s, arm automatically, wait 31 s; disarm and arm as operator.
             Expected: the CQ and the report (new texts) never restart it: at E+62 s the transmitter is disarmed by the watchdog mid-QSO, the run stops tx_watchdog, tx_expired true and last cause tx_watchdog; the new start (an operator action) arms again. Second case: no arm, the run stops tx_watchdog, no contact is left selected, no PTT. Third case: refused tx_watchdog; the MCP run stops tx_watchdog unarmed; still within the minute at 55 s, spent and refused tx_watchdog at 61 s, set_watchdogs refused operator_required and the next Enable Tx still refused tx_watchdog; accepted after the browser action, not spent at 61 s (11 s after the last browser action), spent at 111 s. Fourth case: both applied, spent at 61 s. Unit: watchdog_spent before any action; remaining 1 minute after the automatic arm (counted from the mark), spent after 121 s; an operator arm restarts it at 2 minutes.
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
             Setup: actual isolated server and Chromium at 1366x768 (and 360x740 for the popup); routed fixtures: an FT8 live job with CQ K1ABC FN42, CQ NA W1AW FN31, CQ DL1XYZ JO62, a strategy view (revision 4, "DX first", Highlight off), station verdicts [2 rank 0, 0 rank 1, 1 grey] (with reasons when explain), an automation owner recording commands, the contact snapshot (safety revision 7, watchdog 6 min). A second case uses the real station store.
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
             Setup: the gated candidate installed on HB9BLA, IC-7300 on COM3 at 1 W on 40 m FT8, operator consent; Tx watchdog 5 minutes (at most 10 CQ periods, the operator's limit of 10 unanswered calls).
             Steps: create a strategy (rule 1 CQ and not continent EU, rule 2 CQ; Treat 73 as CQ) and turn Highlight on; then Auto in role cq; then role call.
             Expected: matching decodes marked and on top, CQ NA/AS and same-continent CQ DX greyed; Auto CQ transmits CQ and answers the first caller to a logged QSO, or ends by the watchdog after at most 10 CQs; Auto Call answers only matching CQs; HALT and Esc stop at once; the watchdog is not extended by Auto.
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
        attribute implementation : String = "server/src/dxcc.rs; server/src/receive_http.rs; server/src/strategy.rs; client/recording.js; client/contact.js";
    }
    dependency CL_055_02_to_FR_010 from 'CL-055-02' to 'FR-010';
    dependency CL_055_02_to_FR_019 from 'CL-055-02' to 'FR-019';
    requirement 'CL-055-03' {
        doc /* Settings > General shows the cty.dat in use (its date, bundled or uploaded, entity count) and replaces it by a file upload that the station validates first, or returns to the bundled file; there is no automatic download. A refused upload changes nothing; an unreadable stored upload leaves the bundled file in use and is reported. Details: WstxContact::CountryFile, CountryFileHttp. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/logbook.rs; server/src/logbook_http.rs; server/src/main.rs; client/logbook.js";
    }
    dependency CL_055_03_to_FR_016 from 'CL-055-03' to 'FR-016';
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
             Setup: actual candidate router with the contact engine (HB9BLA JN47AA); hand-authored rows published through the test control peer, including HB9BLA W1XYZ -10 without a grid.
             Steps: wait for the rows; select CQ K1ABC FN42.
             Expected: W1XYZ row DXCC U.S.A. with title "U.S.A. · NA · CQ zone 5 · ITU zone 8 (cty.dat)" and distance "~7706 km"; DL1ABC Germany; K1ABC's distance from its grid without "~"; the QSO header "K1ABC · FN42 · U.S.A. (NA)".
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-055-02';
        }
        attribute executable : String = "tests/contact.test.cjs";
    }
    dependency CL_055_02_verified_by_TC_055_004 from 'CL-055-02' to 'TC-055-004';
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

}
