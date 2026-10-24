# WSTX Rust Functional Specification Document

- Status: Incremental functional specification; selected interface clauses and tests are defined below
- Created: 2026-10-24
- Working name: WSTX Rust
- Repository: https://github.com/SensorsIot/wsjtx-rust
- Behavior reference: WSJT-X `v3.3.0-beta4`, released 2026-10-22, commit `0f7d5928449ec747c3d1f6da1306f8c94404c3a9`
- Archived source snapshot: WSJTX/wsjtx, commit `967c85a6119110788b0df3782cf796485b2cee14` on `original`; this is not the beta behavior baseline.

## 1. Purpose

Define the intended behavior and acceptance criteria for a simplified Rust implementation of WSJT-family functionality. The project must preserve on-air interoperability and the workflows needed for weak-signal amateur-radio communication, while keeping the implementation and user experience as simple as possible.

This is a starting specification, not a claim of implemented functionality. Confirmed decisions are listed separately from proposed requirements and open questions. Extract requirements from protocol publications, user documentation, release notes, and observable reference behavior. Write the Rust implementation independently rather than copying or translating the upstream source. Previous source inspection and shared repository history mean this process is not a claim of formal clean-room development.

## 2. Confirmed project decisions

- The project targets the upstream suite's useful functionality in Rust, with a simpler design; repository structure, internal APIs, and implementation details are not parity requirements.
- The primary product is a desktop application. Its first release targets Windows; macOS and Linux are planned desktop targets after the Windows release.
- The project has two applications in one repository: a Rust station server and an HTML/CSS/JavaScript browser client. Both can run on one development computer or on separate station and home computers.
- The station server owns radio state and timing. The browser renders the operator interface and communicates through a defined control/data interface suitable for limited-bandwidth links.
- An MCP interface provides access to the same station operations for FT4/FT8 automation, including station selection and QSO operation. Detailed tools and selection policies are defined in their implementing CRs.
- Use desktop CPU and memory resources effectively, including multicore execution and suitable hardware acceleration. Microcontroller resource limits do not set the primary product's design constraints.
- A microcontroller edition is a possible secondary product, with its own scope and resource limits. It is not part of the first Windows release commitment.
- The experimental behavior baseline is pinned to WSJT-X `v3.3.0-beta4`; newer betas require an explicit baseline update.
- Prefer a small application with shared modules. Add processes, crates, dependencies, or compatibility layers only when a concrete requirement justifies them.
- The `original` branch preserves the imported upstream source and history as a reference.
- The `master` branch is the development branch for the Rust port.
- Project documentation is stored in `docs/`.
- The upstream project is licensed under GPLv3. The port must meet applicable license and attribution requirements when distributed.

The imported upstream implementation remains on `original` and in Git history. The Rust
station server serves a browser status interface; radio functionality is outside the
initial communication slice. Development checks, the full automated suite and Windows
packaging run on the development PC. Hosted execution is an explicitly selected
alternative, not a second automatic run; see [Windows builds](BUILDING.md).

## 3. Scope

The intended end state covers the useful radio functionality represented by WSJT-X, MAP65, and QMAP. Supporting utilities are included when they serve an identified user or validation need; recreating every upstream file or executable is not a goal. Maintain a feature inventory with explicit decisions to include, merge, defer, or omit each capability. Delivery is incremental, with a small initial operating path.

### 3.1 Modes and protocols

The initial mode inventory includes FST4, FST4W, FT4, FT8, JT4, JT9, JT65, MSK144, Q65, WSPR, Echo, and the experimental JTTY mode. Exact variants, submodes, timing options, message types, and special operating modes must be inventoried against the pinned beta's behavior and documentation before implementation is declared complete.

### 3.2 Application capabilities

- Receive and transmit audio processing and digital signal processing.
- Encoding, decoding, synchronization, and protocol message handling.
- Station configuration, radio control, and transmit/receive sequencing.
- Spectrum and waterfall displays, decoded-message views, and operator controls.
- QSO workflows, logging, reporting, and external application integration.
- EME operation, Doppler compensation, and wideband workflows represented by MAP65 and QMAP.
- Supporting command-line tools, data files, documentation, and packaging needed to replace the upstream distribution.

### 3.3 Language boundary

The station server, radio logic, and protocol implementations are written in Rust. The browser client uses HTML, CSS, and JavaScript. Whether native operating-system interfaces, device drivers, or external libraries may be used through bindings remains an open decision. Retaining the existing Fortran or C++ implementation is not the final implementation goal.

### 3.4 Release targets

| Release direction | Target | Scope |
| --- | --- | --- |
| First release | Windows desktop | A usable operating path selected from the functionality inventory, with the existing Windows x64/MSVC build as the initial development target. Exact Windows versions and supported radio hardware remain open. |
| Subsequent desktop releases | macOS and Linux | Reuse the protocol and signal-processing components, adding and validating platform-specific audio, radio access, UI, packaging, and acceleration as needed. |
| Possible secondary edition | Microcontrollers and other constrained devices | Explore after the desktop foundation is established. Select the supported modes, hardware, memory budget, and interface separately; full desktop feature parity is not assumed. |

Keep protocol logic and input/output boundaries portable where practical. Platform-specific performance work is permitted behind those boundaries. Do not require every desktop feature to fit a microcontroller or require the initial Windows release to ship macOS, Linux, or embedded packages.

### 3.5 Station server and operator client

| Application | Responsibilities |
| --- | --- |
| Station server, Rust | Runs beside the radio. Owns audio capture, decoding, encoding, transmit timing, radio control, QSO sequencing, and authoritative station state. Exposes shared station operations to the browser and MCP adapters. |
| Operator client, HTML/CSS/JavaScript | Runs in the operator's home browser. Renders spectrum/waterfall data and decoded messages, filters and sorts displayed results, presents controls and settings, and requests operations from the server. |

The applications share one repository and are versioned together initially. Their implementation directories are `server/` and `client/`; shared documentation and Cargo workspace files remain at the root. Same-machine development uses the same application boundary as remote operation.

The client-server interface carries commands, decoded messages, status updates, and reduced spectrum data. Continuous raw-audio or IQ transfer is not a prerequisite for normal remote FT4/FT8 operation. The server's radio timing is independent of network round trips and browser rendering.

The server reports actual station state; the browser distinguishes confirmed state, pending requests, stale data, and disconnection. Reconnection resynchronizes state before normal control resumes and does not replay old transmit requests. The loss-of-connection policy for an already active operation remains to be settled before remote transmission is implemented.

MCP accesses the same station operations and state as the browser. It supports observing and automating FT4/FT8 workflows, including finding candidate stations, selecting a suitable station, and conducting a QSO. Transport, tool names, authentication/authorization, control ownership, and selection policy are specified before the corresponding implementation. MCP does not define a separate modem or timing engine.

The initial status-only message contract and bandwidth/latency envelope are defined in
the [station communication contract](COMMUNICATION.md). Additional operating commands,
radio control ownership and optional desktop packaging remain to be specified. A browser
client is the initial interface direction; a Tauri or other desktop wrapper has not been selected.

### 3.6 Additional targets: configured instances and direct FlexRadio access

The following targets extend the status-only communication slice. They are **specified,
not implemented or accepted by CR #3**. Their phase numbers describe the requested
sequence for this extension, not completion of the broader delivery milestones.

- **Phase 1:** at least four independent station-server instances on the same Windows
  PC, each with its own port, persisted configuration and separate browser window.
- **Phase 2:** offer an optional direct FlexRadio connection type for a station profile,
  using the native network API and an intended radio/slice association for that profile.

The default connection path uses the ordinary WSJT-X-style audio-device interface,
with optional CAT/PTT rig control as required. Physical or virtual audio devices and
the operator's selected rig-control infrastructure remain supported. That standard
path may use external FlexRadio desktop/CAT/DAX software when the operator chooses it.
The optional native FlexRadio path removes those desktop bridges for profiles selecting it.

Each profile independently selects its connection type. Four concurrent instances may
mix standard audio/rig-control and native FlexRadio profiles. Both paths use the same
HTML browser interface, station operations, DSP/modem functions and future MCP interface;
native FlexRadio support neither replaces the general product nor introduces a separate UI.

Four logical station servers do not imply four separate FlexRadio GUI-client connections,
four physical radios or four independent transmitters. Shared-radio connection/resource
coordination may be implemented inside the Rust system. The supported radio and firmware
must actually supply the slice capacity needed by the selected operating scenario;
four slices are not assumed available on every FlexRadio model.

## 4. Proposed functional requirements

The broad requirements below are refined during the upstream inventory and their
implementing CRs. Section 4.1 specifies the selected FR-019/FR-021 status profile;
the other functional areas retain their proposed scope until settled.

| ID | Area | Required behavior |
| --- | --- | --- |
| FR-001 | Station setup | Configure and persist station identity, locator, devices, radio settings, and operating preferences. Validate values and explain invalid input. |
| FR-002 | Audio | Select supported input and output devices; capture receive audio and play generated transmit audio with the timing and sample handling required by each mode. |
| FR-003 | Receive processing | Process live audio and supported saved recordings; expose mode-appropriate filtering, synchronization, decoding options, and results. |
| FR-004 | Decoding | Decode the baseline mode and message variants, reporting available callsigns, locators, signal measurements, timing, and frequency information. |
| FR-005 | Encoding | Produce protocol-compatible messages, channel symbols, and waveforms for supported transmit modes and variants. |
| FR-006 | Time and sequencing | Schedule receive and transmit periods against UTC and apply each mode's timing rules. Surface clock or device problems that prevent reliable operation. |
| FR-007 | QSO operation | Support the baseline workflows for choosing a decoded station, preparing messages, progressing an exchange, and completing or aborting a contact. |
| FR-008 | Transmit control | Provide clear transmit state and an immediate halt action; handle PTT, radio errors, and device loss without leaving transmit active unintentionally. |
| FR-009 | Radio control | Support baseline radio-control capabilities, including frequency, mode, PTT, split operation, and supported device interfaces. The hardware support matrix is to be inventoried. |
| FR-010 | Displays | Provide spectrum, waterfall, decode, frequency, and operating-state views sufficient to carry out the baseline workflows. Pixel-identical UI reproduction is not yet a requirement. |
| FR-011 | Logging | Record completed contacts and support the baseline log formats, import/export paths, and duplicate or prior-contact indications where applicable. |
| FR-012 | Integrations | Preserve required external protocols and message formats, including baseline UDP integrations and reception-reporting workflows. |
| FR-013 | EME | Provide baseline astronomical information, Doppler handling, and Echo measurement workflows applicable to each application. |
| FR-014 | Wideband reception | Replace MAP65 and QMAP capabilities, including supported wideband input, band maps, polarization processing where applicable, and coordination with the narrowband application. |
| FR-015 | Utilities | Identify the user and validation needs served by upstream utilities. Provide the selected capabilities through the smallest practical interface, documenting any required external compatibility. |
| FR-016 | Settings and migration | Persist Rust application settings reliably. Define compatibility and migration behavior for existing WSJT-X profiles before a user migration release. |
| FR-017 | Help and notices | Provide operating guidance, version information, relevant attribution, license access, and a clear indication that this is an independent port. |
| FR-018 | Recorded audio input | Load and validate recorded receive audio for repeatable processing, preserving source data and reporting unsupported or invalid input. Initial accepted formats and the first import workflow remain to be settled. |
| FR-019 | Browser operator interface | Provide a modern HTML/CSS/JavaScript operator interface that can run on the home computer, rendering station information and sending control requests to the server. |
| FR-020 | MCP automation | Expose shared station operations through MCP for observing and automating FT4/FT8 activity, including station selection and QSO workflows. Exact tools and automation policies are specified in their CRs. |
| FR-021 | Station server and remote operation | Separate the Rust station server and browser client through a defined interface. Support same-machine development and remote operation over limited-bandwidth links, with authoritative server state, explicit connection status, and state resynchronization. |
| FR-022 | Concurrent persisted station profiles — phase 1 target | Run at least four independently startable/stoppable server instances on one Windows PC, using distinct listening ports, separate browser windows and isolated persisted configurations. Preserve instance identity and access isolation across restart and concurrent use. Specified target; not implemented or accepted by CR #3. |
| FR-023 | Optional direct FlexRadio integration — phase 2 target | Offer a selectable native FlexRadio TCP/UDP connection type alongside the default audio-device/optional CAT/PTT path. Native profiles operate without requiring external SmartSDR desktop/CAT/DAX applications, persist intended radio/slice associations and reconcile actual resources on connection. Both paths share the browser/DSP/MCP architecture. Specified target; not implemented or accepted by CR #3. |

### 4.1 Browser–server status functions

These stable clauses refine FR-019 and FR-021. The FSD is the canonical home of their
functional meaning and the test definitions in section 6.1. The clauses retain their
CL-003 identifiers independently of the GitHub issue lifecycle. Issue #3 records change
approval, implementation/review history and execution evidence; closing it does not
retire these clauses or tests.

This section also provides orientation to the detailed interface specification:
message schemas, field bounds, errors, authentication settings, timeouts, resource limits
and numerical traffic budgets have their single canonical home in
[COMMUNICATION.md](COMMUNICATION.md). References below use that contract rather than
redefine its wire format or numeric limits.

| Clause | Promise | Required function | Verification |
|---|---|---|---|
| CL-003-01 | FR-019, FR-021 | The Rust server MUST serve the HTML/CSS/JavaScript operator client. The browser MUST visibly show server version, connection state and an unconfigured radio. Refresh status MUST request a fresh snapshot and update the displayed last-update time. | TC-021-006; TC-021-008 |
| CL-003-02 | FR-021 | Each browser MUST use one versioned WebSocket connection for status requests and responses. The server MUST echo each request ID on the requesting connection and return authoritative version/radio state. Concurrent clients MUST remain independent. | TC-021-005; TC-021-008 |
| CL-003-03 | FR-021 | The server MUST validate request structure, protocol version, command and message size in the contract's order. Rejected input MUST follow the defined error/close behavior; recoverable errors MUST leave the server available without exposing internal details. | TC-021-005 |
| CL-003-04 | FR-019, FR-021 | The browser MUST distinguish stale/disconnected state from current station state, detect a silently unresponsive connection, retry at a bounded rate and obtain a full snapshot before showing Connected again. Recovery MUST not wait indefinitely for an old socket to close. | TC-021-006; TC-021-007 |
| CL-003-05 | FR-021 | The minimal profile MUST support two clients sharing the contract's 32 kbit/s link model and meet its traffic and visible-response budgets. Tests MUST distinguish cold page/assets loading, protocol connection and displayed-status timing, and identify the measurement layer. | TC-021-008 |
| CL-003-06 | FR-021 | Application output buffering and active connections MUST have explicit bounds. An unresponsive client MUST be removed under the contract's liveness/write limits without blocking another client's status requests. Test results MUST distinguish observed liveness removal from an unobserved send-timeout branch or total-memory bound. | TC-021-008, stalled-reader variant; contract/source review |
| CL-003-07 | FR-021 | Remote access MUST use the contract's authenticated TLS path and exact Origin validation. The browser MUST offer token login, and invalid or oversized login requests MUST be refused. Insecure remote startup and invalid access settings MUST fail closed. Explicit loopback development MAY remain unauthenticated. | TC-021-009 |
| CL-003-08 | FR-019, FR-021 | Status MUST use initial/reconnection snapshots, explicit refresh requests and event-driven updates when state changes exist. The client MUST avoid constant status polling and tolerate protocol heartbeats between responses. The initial profile MUST carry no raw audio or spectrum stream and use no application-level compression. | TC-021-007; TC-021-008; peer-helper fixture; protocol/source review |

The initial workflow is open the station page, authenticate when TLS mode requires it,
receive a status snapshot, optionally refresh status and recover from connection loss.
It exposes no radio-control, transmit, decoding, spectrum or MCP commands. Those
functions remain governed by their broader requirements and implementing CRs. Future
spectrum delivery may use compact binary frames with adjustable resolution/rate and
discard obsolete frames; it is outside the status profile specified here.

### 4.2 Concurrent persisted station profiles — target FR-022

These are additional target clauses. The current environment-variable configuration and
single-instance status contract do not establish profile persistence or secure concurrent
four-instance operation.

1. The application MUST support at least four independent station-server instances on
   the same Windows PC. Each MUST have a distinct listening port, its own persisted
   profile and an identifiable browser window. Four windows connected to one server do
   not satisfy this requirement.
2. Each profile MUST retain its instance identity and selected operating configuration
   across server/PC restart. Configuration edits and recovery of one profile MUST NOT
   modify another profile. The configuration format, storage location and editing workflow
   are selected before implementation; they are not defined by the current environment settings.
3. Each server MUST load the explicitly selected profile and fail clearly if its port
   is already occupied or its profile is concurrently owned incompatibly. A collision
   MUST NOT overwrite configuration or silently attach a browser to a different station.
   Stopping/restarting one instance MUST leave the other three usable.
4. Access credentials, login state and station requests MUST remain isolated when the
   four endpoints use the same hostname and the windows share one browser profile.
   Concurrent authentication and reconnection MUST not overwrite another instance's
   session or authorize a request to the wrong station.
5. Each profile MUST independently persist its connection type, defaulting to the standard
   audio-device/optional CAT/PTT path. Once the optional phase-2 type is implemented,
   standard and native FlexRadio profiles MUST run concurrently. Native radio/slice
   association fields apply only to a profile selecting the native FlexRadio type;
   they MUST NOT become required configuration for a standard audio/rig-control profile.
   The persisted association expresses operator intent, not an assumption that an
   observed runtime slice index remains stable after reconnect or radio restart.

HTTP cookies are not isolated by port; see
[RFC 6265, section 8.5](https://www.rfc-editor.org/rfc/rfc6265.html#section-8.5).
The current status server uses the same cookie name/path across ports. A future
multi-instance session design must address that shared-browser collision; the current
single-instance authentication tests do not verify FR-022 clause 4.

### 4.3 Optional native FlexRadio integration — target FR-023

FlexRadio documents direct TCP command/status access and UDP streaming, and lists its
native API separately from the Windows .NET FlexLib option. These are the integration
starting points, not a promise that every model/firmware offers identical resources:
[developer program](https://www.flexradio.com/api/developer-program/),
[API overview](https://www.flexradio.com/api).

1. Phase 2 MUST offer direct native-network integration as an optional profile connection
   type for the selected radio control, status and sample-stream functions. When selected,
   that native path MUST NOT require the external SmartSDR desktop application, SmartSDR
   CAT or DAX applications to be installed/running as bridges. This restriction does not
   prohibit those tools as operator-selected infrastructure for the standard connection
   path. A Rust implementation may coordinate
   shared radio access internally without forcing one hardware GUI-client session per
   logical station server.
2. This independence concerns desktop applications. Compatible radio-side firmware and
   its API remain required; this specification does not promise a FlexRadio operating
   without its SmartSDR radio firmware or an unrestricted firmware compatibility range.
   Pin supported models, firmware/API versions and selected stream formats before implementation.
3. Each native FlexRadio profile MUST persist its intended radio and slice association. On every
   connection/reconnection the system MUST reconcile that intent with authoritative
   discovery/status and current runtime handles. A changed/transient slice index MUST
   NOT redirect a station to another station's slice. Unresolvable associations MUST
   produce a visible unavailable/conflict state rather than guessing a replacement.
4. Control responses and received stream data MUST be routed to the associated station.
   Capacity shortages, occupied resources and incompatible API behavior MUST be reported
   without stealing another profile's slice or silently reducing the requested independence.
   Four-slice hardware validation requires a model/configuration that actually provides
   at least four usable slices.
5. Shared-radio transmit, tuning and other constrained-resource authority MUST be
   coordinated under FR-008/FR-009 before those operations are enabled. Four station
   profiles do not confer simultaneous independent transmit authority. Reconnect/profile
   restoration MUST NOT replay an old transmit request or bypass the future ownership policy.
6. The native path MUST reuse the common browser, station-operation, DSP/modem and future
   MCP interfaces. The default standard connection remains usable without FlexRadio
   hardware or native-profile fields. A mixed set of four instances MUST preserve each
   profile's selected path, configuration and routing independently.

## 5. Proposed quality and compatibility requirements

- **On-air compatibility:** Preserve the protocol definitions and interoperability of the selected upstream baseline. A language rewrite must not silently change message encoding or waveform conventions.
- **Decoder quality:** Measure decoding success, false positives, sensitivity, and runtime against reference recordings and controlled signals. Numeric tolerances and acceptance thresholds must be agreed per mode.
- **Timing:** Meet each mode's receive and transmit deadlines on a documented reference machine. Hardware and performance budgets remain to be selected.
- **Platforms:** Windows is the first release platform. macOS and Linux are subsequent desktop targets. Supported operating-system versions and CPU architectures remain open beyond the initial Windows x64 build environment.
- **Reliability:** Recover from device and connection errors with understandable status information; preserve settings and logs across ordinary restarts.
- **Maintainability:** Keep protocol and signal-processing logic testable independently of the graphical interface and physical radio hardware.
- **Licensing:** Choose dependencies compatible with distribution of the port under GPLv3 and retain applicable third-party notices.

### 5.1 Desktop performance and acceleration

- **Multicore execution:** Use a bounded pool of CPU workers for independent decode work and other suitable tasks. Support automatic worker selection and an operator override, keeping enough capacity for audio, radio control, and the interface. Preserve ordering where processing stages depend on earlier results.
- **CPU optimization:** Evaluate optimized FFT processing, data layout, buffer reuse, and SIMD where profiling identifies a useful benefit. Select instruction-specific paths according to the processor's capabilities and retain a portable CPU path.
- **GPU and other accelerators:** Allow optional acceleration for suitable workloads, such as batched signal processing or spectrum generation. Select APIs and backends after cross-platform feasibility checks and benchmarks; no CUDA, Vulkan, Metal, or other vendor/API dependency has been selected.
- **CPU-only operation:** The application must remain usable without a dedicated GPU. An unavailable or failed optional acceleration backend must fall back to the CPU path with an understandable status message.
- **Correctness:** Compare every acceleration path with the same protocol vectors and recordings used by the CPU reference path. Check message correctness, missed signals, false decodes, numerical tolerances, and cancellation behavior; a faster path must meet the agreed acceptance criteria.
- **Latency and responsiveness:** Measure time from incoming audio to usable decode results, including scheduling, transfers to and from accelerators, and result delivery. Keep the audio and operator-control paths responsive while background processing is active.
- **Evidence before complexity:** Retain an optimization when end-to-end measurements justify its maintenance cost. Record CPU/GPU model, operating system, compiler/build configuration, worker count, workload, memory use, and timing distributions. Raw arithmetic throughput alone is insufficient.

Hardware acceleration is an intended optimization route, not a promise that GPU decoding will ship in the first Windows release. Release-specific performance budgets and supported backends must be selected through measurement. Microcontroller-specific tradeoffs belong to the potential secondary edition.

## 6. Acceptance and validation approach

1. Build a functionality inventory from documentation and observed workflows. Link selected capabilities to requirements, acceptance examples, and Rust components; record deferred and omitted capabilities.
2. Pin the beta reference binary and record its version, hash, relevant runtime settings, and input data. Do not assume the archived `original` snapshot represents the same release.
3. Establish reference vectors for message packing, error-correction coding, symbol generation, and waveforms. Require exact results where the protocol defines discrete values; define justified tolerances for floating-point processing.
4. Compare decoders on the same recordings and controlled signal conditions, including weak signals, overlapping signals, timing offsets, and frequency offsets.
5. Test transmit and receive interoperability with the reference implementation, initially using recorded audio or controlled loopback setups.
6. Validate operator workflows, device behavior, file formats, and integrations using documented scenarios.
7. Run Windows checks for the first release and platform-specific acceptance checks before each subsequent macOS or Linux release. Record unsupported capabilities explicitly.
8. Benchmark one CPU worker, multiple CPU workers, and each available acceleration backend on identical inputs. Track deadline completion, interface responsiveness, peak memory, and decoder quality as well as throughput. No target hardware or numerical speedup threshold has been agreed yet.

Full-project completion requires every inventory item to be implemented and accepted, or explicitly excluded through a documented scope decision. A successful FT8 demonstration alone does not establish full parity.

### 6.1 Browser and server test catalogue

These are durable test definitions, not execution results. Each case names its inputs,
actions, expected observations and executable trace. Source assertions implement the
definition; dated outcomes and limitations belong in the implementing issue and stored
test output. TC-021-001 through TC-021-004 remain associated with the repository-layout
change; the communication cases continue their numbering.

**Execution level for each case below: 2 — Isolated automated tests.** They use temporary
processes, recorded/constructed test inputs and disposable credentials. They require no
physical radio, live station, real user credentials or external service.

**Selected location:** the Windows development PC. The local gate runs the complete
communication suite, including the full bandwidth measurement, and the Rust test suite.
The same cases can run on a GitHub Actions Windows runner only when hosted execution
is explicitly chosen as the alternative mode. Local and hosted runs are not both
routine requirements. Execution procedures and mode enforcement belong to
[Building](BUILDING.md) and the [harness binding](harness/Harness-Overview.md#bindings).

#### TC-021-005 — Message exchange and invalid-input handling

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
[message/error rules](COMMUNICATION.md#messages-and-validation).
**Executable trace:** [communication.test.cjs](../tests/communication.test.cjs),
`TC-021-005: actual-server correlation, negative cases and size boundaries`;
[protocol_tests.rs](../server/src/protocol_tests.rs),
`protocol_returns_specified_response_and_errors`.

#### TC-021-006 — Actual browser interface

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
[communication.test.cjs](../tests/communication.test.cjs),
`TC-021-006: real browser, two clients, desktop and mobile layout`.
Screenshots are `test-results/station-desktop.png` and `test-results/station-mobile.png`.

#### TC-021-007 — Disconnect, retry and state resynchronization

**Clauses:** CL-003-04, CL-003-08. **Promise:** FR-021.
**Level:** 2 — Isolated automated tests.
**Where it runs:** Windows PC, actual candidate server and real browser through a
controllable disposable local proxy, with WebSocket message and attempt timestamps.

**Inputs/actions and expected results:**

1. Connect and observe an unchanged session across a heartbeat interval. Expect an
   initial snapshot request and no periodic station.get polling.
2. Cut the connection and keep it unavailable. Expect visible stale/disconnected state
   and attempts at the bounded reconnect rate from the
   [liveness contract](COMMUNICATION.md#liveness-and-resource-limits).
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
[communication.test.cjs](../tests/communication.test.cjs),
`TC-021-007: dropped connection, bounded retries, fresh snapshot`.

#### TC-021-008 — Thin-link budget and client isolation

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
   [traffic budget](COMMUNICATION.md#thin-link-budget-and-test-model), including heartbeat
   and accounted overhead. Report actual TLS-stream bytes plus the explicit network model;
   do not describe these values as physical packet capture.
3. Click Refresh status concurrently in both existing clients. Expect each visible
   Last updated value to change within the connected-response limit, using the existing
   WebSocket connections rather than creating replacement test connections.
4. The minimal profile MUST contain no audio/spectrum stream or application compression;
   verify that scope against the protocol and implementation. Missing browser, simulator
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
[resource/liveness rules](COMMUNICATION.md#liveness-and-resource-limits).
**Executable trace:** [communication.test.cjs](../tests/communication.test.cjs),
`TC-021-008: 32 kbit/s shared TLS link and 60-second idle budget` and
`TC-021-008: stalled reader cannot block another client`.
The measurement report is `test-results/link-budget.json`.

#### TC-021-009 — Remote access boundary

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

**Oracle:** [access and startup contract](COMMUNICATION.md#connection-and-security),
HTTP/upgrade outcomes and protected cookie attributes. **Executable trace:**
[communication.test.cjs](../tests/communication.test.cjs),
`TC-021-009: TLS login, unauthorized/origin denial, plaintext refusal`.

#### Supporting test-tool fixtures

These fixtures validate the test machinery; they do not replace the actual-server cases
or constitute new radio functions. **Level:** 2 — Isolated automated tests.
**Where they run:** the Windows PC as part of the same full local communication suite.

| Fixture and trace in [communication.test.cjs](../tests/communication.test.cjs) | Input/action | Expected observation |
|---|---|---|
| `peer helper: heartbeat interleaving preserves response and total deadline`; [peer.cjs](../tests/peer.cjs) | Emit an exact protocol heartbeat before a known response, then feed unsupported/unexpected events; repeatedly emit valid heartbeats without a response. | The helper returns the known response, exposes other events to the caller's oracle and times out on one unchanged total deadline; listeners are cleaned up. Supports TC-021-005/008. |
| `link simulator: shared bulk throughput and RTT`; [support.cjs](../tests/support.cjs) | Send concurrent known-size echo transfers through one shared bottleneck, followed by a one-byte round trip. | Independent wall-clock checks reject a link that is either too fast or improperly serialized by propagation delay, and verify the minimum RTT. Supports TC-021-008. |

### 6.2 Planned tests for concurrent persisted profiles

**Status:** planned definitions for FR-022. These tests have no implemented executable
trace or acceptance result yet. They are additional work beyond CR #3; the status-only
tests in section 6.1 do not substitute for them. The selected execution location is the
Windows development PC; hosted execution remains an explicitly chosen alternative.

#### TC-022-001 — Four independent servers and browser windows

**Promise:** FR-022, clauses 1–2 and 5. **Level: 2 — Isolated automated tests.**
**Where it runs:** Windows PC, four candidate server instances and four real browser
windows, using distinct temporary ports/profiles; no radio or live service.

**Inputs/actions:** Prepare four visibly distinct station profiles, start their servers
and open one separate browser window for each endpoint. Refresh/query all four, then
change a setting in one profile through the specified configuration workflow.
Use standard connection profiles for phase 1; once the optional native connection is
available, repeat with mixed standard and native profiles using isolated device/API fixtures.

**Expected results:** Four distinct listening endpoints and station identities are
observable concurrently. Each window displays only its own instance's state. Requests
and the configuration change affect the selected instance; the other profiles/windows
remain unchanged. Four windows on a single endpoint fail this case.

#### TC-022-002 — Persistence and independent restart

**Promise:** FR-022, clauses 2 and 5. **Level: 2 — Isolated automated tests.**
**Where it runs:** Windows PC with disposable profile storage, four local server
instances and real browser windows; no physical radio.

**Inputs/actions:** Save different supported settings for each profile, stop the
instances and restart them using their selected profiles. Repeat after a controlled
application/PC restart. Include intended radio/slice association data once its phase-2
schema is defined; use an emulator for any connection needed to observe it.

**Expected results:** Each instance restores its own saved identity/settings and connection
type without borrowing another profile's configuration. Native profiles also restore
their intended association; standard profiles require no native radio/slice fields. Runtime radio handles
are re-established from current status rather than treated as permanent persisted IDs.
Missing/corrupt configuration follows the agreed recovery behavior without overwriting
another profile; that behavior must be settled before implementing this case.

#### TC-022-003 — Stop isolation and collision refusal

**Promise:** FR-022, clause 3. **Level: 2 — Isolated automated tests.**
**Where it runs:** Windows PC, four local candidate instances with disposable profiles
and controlled occupied-port/profile-lock fixtures.

**Inputs/actions:** While four windows are active, stop one server and continue querying
the other three. Restart the stopped server. Attempt another launch using an occupied
port and, separately, a profile already owned incompatibly by an active instance.

**Expected results:** Only the stopped window becomes stale; the other three remain
usable. Restart reconnects the intended window/profile. Each conflicting launch fails
clearly before it can alter stored configuration or masquerade as another station.

#### TC-022-004 — Four-instance authentication in one browser profile

**Promise:** FR-022, clause 4. **Level: 2 — Isolated automated tests.**
**Where it runs:** Windows PC, four local TLS server endpoints on distinct ports of
the **same hostname**, separate test credentials and four windows sharing the **same
browser profile/cookie store**. Separate browser contexts do not satisfy this case.

**Inputs/actions:** Authenticate independently to each station, refresh all four, then
force each connection to reconnect. Re-authenticate or rotate access for one station
according to the selected access contract. Attempt to use one station's credential or
session at another station's endpoint.

**Expected results:** Each station remains independently authenticated and its requests
reach only that station. Logging in/reconnecting at one port does not invalidate or
overwrite the others' sessions. Cross-station credentials/sessions are denied. Cookie
behavior across ports must be exercised explicitly; the current common-name cookie
implementation is not accepted as satisfying this planned requirement.

### 6.3 Planned tests for direct FlexRadio integration

**Status:** planned definitions for FR-023, not implemented tests or hardware results.
Exact protocol fixtures and supported hardware/firmware are selected and pinned before
implementation. Purely simulated tests do not establish live-radio interoperability.

#### TC-023-001 — Direct protocol and four-station route isolation

**Promise:** FR-023, clauses 1 and 4. **Level: 2 — Isolated automated tests.**
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

#### TC-023-002 — Persisted intent and changed runtime handles

**Promise:** FR-023, clauses 3–5. **Level: 2 — Isolated automated tests.**
**Where it runs:** Windows PC, disposable persisted profiles and a local radio emulator.

**Inputs/actions:** Save intended radio/slice associations, disconnect/restart the
emulated radio and assign different runtime handles before reconnecting. Also present
missing, ambiguous or occupied intended resources and stale status updates.

**Expected results:** Each profile reconciles its intent with current authoritative
resources; transient indices do not route it to another station. Unresolved intent is
reported as unavailable/conflicting without stealing a resource, replaying transmit
requests or accepting stale handles as authority.

#### TC-023-003 — Capability limits and shared-resource coordination

**Promise:** FR-023, clauses 2, 4–6; FR-008/FR-009. **Level: 2 — Isolated automated tests.**
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

#### TC-023-004 — Live direct-radio tuning and slice lifecycle

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
radio state, so this case is not classified as read-only level 3.

#### TC-023-005 — Observational live status, only where genuinely read-only

**Promise:** FR-023. **Level: 3 — Live read-only tests.**
**Where it runs:** An authorized designated FlexRadio station and the Windows PC.

**Inputs/actions:** Observe existing discovery/status/stream identity using a path that
does not allocate/release slices, tune, change configuration or request transmission.

**Expected results:** Reported state matches the designated radio without changing its
operating resources. If the selected API workflow requires such changes, use the level-4
case and operator consent instead; do not relabel a mutating test as observational.

#### TC-023-006 — Conditional future transmit validation

**Promise:** FR-008/FR-009 and FR-023 clause 5.
**Level: 5 — Tests with external effects and explicit operator consent.**
**Where it runs:** A designated authorized physical test station, only after transmit
functionality, its ownership policy and the specific test operation have been approved.

**Inputs/actions:** Under that later approval, request a controlled transmission from
the owning station and a conflicting request from another profile; exercise the
specified abort/device-loss path.

**Expected results:** The agreed single-radio transmit authority is enforced, conflicts
are refused and FR-008 halt/failure behavior is met. This conditional definition does
not authorize transmission now or make it part of the receive-only live test above.

## 7. Proposed delivery milestones

| Milestone | Deliverable | Exit evidence |
| --- | --- | --- |
| M0: Baseline and specification | Preserve `original`; inventory upstream features and licensing; establish the Rust development structure. | Traceability inventory, agreed initial scope, and a reproducible build skeleton. |
| M1: Protocol foundation | Implement shared message and signal primitives; select a first mode after the inventory. | Reference-vector comparisons and an offline encode/decode demonstration. |
| M2: First usable operating path | Connect audio, sequencing, basic operator controls, and the initial radio-control path. | A complete validated operating scenario for the selected mode. |
| M3: WSJT-X parity | Implement the remaining narrowband modes, operating workflows, logging, and integrations. | Requirement coverage and per-mode compatibility results. |
| M4: Suite functional coverage | Implement the selected wideband and EME capabilities and required utilities using shared Rust components. | Every inventory item has an implementation or an explicit defer/omit decision, with end-to-end validation for implemented capabilities. |
| M5: Release preparation | Prepare Windows releases at the selected functional milestones, including branding, notices, documentation, migration, packaging, and measured performance. Schedule macOS and Linux releases after Windows. | Reproducible Windows packages and documented acceptance results for the release's agreed scope. Separate platform validation precedes later releases. |

The first Windows release may occur before full-suite coverage at M3 or M4. Its exact feature set is still to be selected; Windows-first does not mean every upstream feature must be finished before any release. A possible microcontroller edition has no committed milestone. No delivery dates or effort estimates have been agreed.

## 8. Licensing, attribution, and branding

- A distributed port derived from the upstream implementation must comply with GPLv3, including retaining relevant notices, marking modifications and their dates, and providing the complete corresponding source and necessary build files for distributed binaries.
- Translation into Rust does not itself remove the upstream copyright or license obligations.
- Bundled components and assets may have separate terms. Record their provenance and applicable notices as they are reused or translated; the initial license check was not a full dependency audit.
- The upstream trademark policy covers its names and program icons separately from the software license. Select distinct release branding consistent with that policy.
- `WSTX Rust` is the requested working title for this document; it has not been cleared as a product name.
- Private development does not by itself require publishing the repository.

## 9. Open decisions

1. What is the final public product name?
2. Which additional operating commands and control-ownership rules extend the initial browser/server status contract, and how does the MCP adapter expose them?
3. Which mode and user workflow should form the first usable milestone?
4. Which GUI, audio, radio-control, and DSP libraries should be selected?
5. What native-library bindings are permitted within the all-Rust goal?
6. Which Windows versions, reference CPU/GPU configurations, and radio devices are required for the first release? Which macOS and Linux targets follow?
7. What quantitative decoder, timing, and resource targets define acceptable parity?
8. How much compatibility with existing settings, command-line interfaces, and UI layout is required?
9. Which optional legacy workflows and utilities can be merged, deferred, or omitted to simplify the product?
10. Which workloads benefit enough from SIMD or GPU acceleration to justify dedicated implementations, and which cross-platform backends should be supported?
11. If a secondary microcontroller edition is pursued, which devices and mode subset should it support?

## 10. References

- [Experimental beta behavior reference](https://github.com/WSJTX/wsjtx/releases/tag/v3.3.0-beta4)
- [Sample recordings and provenance](SAMPLES.md)
- [FlexRadio native API developer program](https://www.flexradio.com/api/developer-program/)
- [FlexRadio API overview](https://www.flexradio.com/api)
- [HTTP cookies and port isolation, RFC 6265 section 8.5](https://www.rfc-editor.org/rfc/rfc6265.html#section-8.5)
- [Upstream source at the imported baseline](https://github.com/WSJTX/wsjtx/tree/967c85a6119110788b0df3782cf796485b2cee14)
- [Upstream program and mode overview](https://github.com/WSJTX/wsjtx/blob/967c85a6119110788b0df3782cf796485b2cee14/README.md)
- [Upstream GPLv3 license](https://github.com/WSJTX/wsjtx/blob/967c85a6119110788b0df3782cf796485b2cee14/COPYING)
- [Upstream trademark policy](https://github.com/WSJTX/wsjtx/blob/967c85a6119110788b0df3782cf796485b2cee14/TRADEMARK.md)
