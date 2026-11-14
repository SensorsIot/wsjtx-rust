// Canonical authority: SysML
package WstxRequirements {
    private import ScalarValues::*;
    private import WstxArchitecture::Station;
    private import WstxArchitecture::Frontend;
    private import WstxArchitecture::Backend;
    private import WstxArchitecture::StationProcess;
    doc /* Canonical functional requirements and durable verification definitions.
         The other Wstx packages own detailed typed contracts; validation does not execute tests.
         Coverage flags describe implemented source slices, not acceptance or whole-project parity. */
    enum def ImplementationState { enum target; enum partial; enum implemented; }
    enum def AutomationState { enum planned; enum partial; enum implemented; }

    requirement PhysicalDeploymentStructure {
        doc /* The model MUST contain the frontend and backend containers of the product's
             functions. Frontend and Backend are pure deployment containers without
             forwarding ports or functional policy. Browser and station exchanges MUST
             connect selected functional endpoints directly, retaining profile-scoped
             browser and station selection. Audio and radio control MUST stay separate
             functions. No outside thing is a part or has a port; each is an entry of
             OutsideThing with one owning function. Variable browser and station
             populations MUST NOT become a fixed station count, all-to-all routing, or an
             additional detached deployment. */
    }
    requirement StationResourceIdentity {
        doc /* Architectural refinement of WstxProfiles and
             WstxFlexSession::NativeFlexBoundary: each station MUST compose one profile,
             one audio device adapter, one CAT driver and one selected-radio binding, and
             reference the common authority contained in Backend. All control requests
             and outcomes MUST retain request/resource identity through that authority
             to the selected CAT driver. Audio and CAT MUST be separate direct station parts,
             with no combined radio-backend wrapper or variation. Both adapters MUST
             serve the radio the station's radio binding selects, and control MUST NOT
             bypass the common authority.
             A native FlexRadio profile instead reaches its radio through the one native
             session of its station (WstxFlexSession::NativeFlexWireSubset), owned by the
             station's receive owner, with no CAT driver in the path. */
    }
    requirement ResponsibilityAndExchangeBoundaries {
        doc /* Architectural refinement of WstxRequirements::SharedDataOwnership,
             ProcessingAndHaltOwnership, RemoteDeliveryPolicy and TransmitSafetyPolicy:
             the declared owners MUST retain their separate typed/directed exchanges.
             Recording storage MUST feed the common receive path; receive and encode
             MUST connect to pure mode functions; audio and control MUST stay separate.
             Browser/MCP adapters MUST use station operations rather than direct radio
             adapter access. The ownership explanations and existing policy contracts apply
             together; target parts do not claim runtime delivery or settled policy. */
    }
    dependency deploymentOwnership from Station to PhysicalDeploymentStructure;
    dependency stationIdentityOwnership from Backend::stations to StationResourceIdentity;
    dependency boundaryOwnership from Backend::stations to ResponsibilityAndExchangeBoundaries;

    verification ResolvedArchitectureGraph {
        subject deployment : Station;
        doc /* Level 2 isolated automated model test on the development PC; no radio,
             device or runtime service. Resolve the accepted model and legal negative
             mutations with the pinned semantic validator. Independent expectations are
             literal required endpoints, complete item-kind/direction signatures,
             population/reference subsets, separate audio/CAT adapter ownership and identity
             bindings
             in the existing architecture integrity oracle, not candidate-derived counts.
             Expect selected-browser-to-web/station direct
             connections through portless associations; frontend/backend containers MUST
             have no forwarding ports. Expect exactly one AudioDeviceAdapter and one
             RustRadioDriver directly
             composed by each station, without combined backend or native-Flex topology;
             audio.backend connects to audioAdapter.host and authorizedControl connects
             to catAdapter.authorized; upload-to-profile-to-receive,
             receive-to-mode and encode-to-mode paths; exactly one effective authority
             whose bound request/outcome and resource context reach that CAT driver.
             Missing direct browser/encode connections, added container forwarding ports,
             reversed provider/waveform direction, wrong item kind, redirected association
             or context, weakened identity binding, split or bypassed authority, missing,
             duplicate or detached audio/CAT adapters, mixed audio/CAT paths, detached
             stations, view-created structure and a port joined to no function
             MUST be rejected even if legal SysML. Two deployment containers and the
             portless browser association population retain selected endpoint identity;
             counts alone are insufficient. This case checks structure, not runtime
             timing, persistence, failure handling, platform operation or RF safety. */
        objective {
            verify PhysicalDeploymentStructure;
            verify StationResourceIdentity;
            verify ResponsibilityAndExchangeBoundaries;
        }
        attribute automation : WstxRequirements::AutomationState = WstxRequirements::AutomationState::implemented;
        attribute executable : String = "tools/sysml.py check; tools/sysml/tests/test_architecture_integrity.py";
        attribute executionStatus : String = "defined automated companion; declaration records no execution verdict";
    }
    verification ArchitecturalOwnershipReview {
        subject deployment : Station;
        doc /* Manual contract review on the development PC, without external effects.
             Compare this decomposition with WstxRequirements::ReleasePolicy,
             SharedDataOwnership, ProcessingAndHaltOwnership, RemoteDeliveryPolicy,
             TransmitSafetyPolicy and NativeFlexBoundary, plus existing FR responsibility
             dependencies below and their canonical verification cases. Independently
             expect server-owned state/results/contacts, profile-owned storage, pure
             mode calculations, one conversion owner, independent audio/CAT failure
             boundaries, station-scoped browser/MCP access and priority halt outside
             receive/display work. Check local/remote roles and Windows-first scope
             without asserting later-platform acceptance, fixed radio capacity or
             native-session lifetime decisions. Strategy remains target and introduces
             no service or selection policy. Reject duplicate policy definitions,
             inferred delivery or any ownership/safety weakening.
             ResolvedArchitectureGraph covers only graph/signature/identity obligations;
             this review covers responsibility prose and policy correspondence. Existing
             WstxRequirements cases own executable product behaviour coverage. Target
             TX/MCP/native and future-platform acceptance remain planned where declared
             there; neither this review nor semantic validation executes those cases. */
        objective {
            verify PhysicalDeploymentStructure;
            verify StationResourceIdentity;
            verify ResponsibilityAndExchangeBoundaries;
        }
        attribute method : String = "manual independent contract correspondence review";
        attribute executionStatus : String = "planned review; no verdict recorded by this declaration";
    }

    requirement ComponentPropertyOwnership {
        doc /* Public values MUST be navigable under their owning parts using canonical
             types and value references. Backend-owned persisted profile configuration,
             private runtime input, frontend-owned preference, requested settings and
             observed state MUST remain distinct. A property attachment MUST NOT create
             persistence fields, controls, credentials, workers or another authority. */
    }
    requirement RadioModelReferenceSeparation {
        doc /* A physical radio's model identifier, sparse capabilities, requested
             settings and actual observations MUST remain separate. Current driver
             coverage MUST NOT limit the intended physical-radio property domains.
             Capability observations MUST NOT grant command or transmit permission.
             Receiver filter width MUST NOT be inferred from a named filter or either
             the radio scope span or the browser waterfall span. */
    }
    dependency browserPropertyOwnership from Frontend::browsers to ComponentPropertyOwnership;
    dependency stationPropertyOwnership from Backend::stations to ComponentPropertyOwnership;
    dependency radioPropertyOwnership from StationProcess::radioControl
        to RadioModelReferenceSeparation;

    verification ComponentPropertyInventoryReview {
        subject deployment : Station;
        objective {
            verify ComponentPropertyOwnership;
            verify RadioModelReferenceSeparation;
        }
        doc /* Level 2 isolated independent manual contract review on the development PC;
             no device, credential or external effects. Compare the public properties
             and interface signatures against the owning canonical profile, station,
             receive, layout and radio contracts. Expect backend-owned saved profile
             configuration distinct from runtime inputs, frontend-owned preferences,
             boot/live station selection with twelve canonical preferred-band references,
             and requested radio settings distinct from confirmed state and readonly
             meters. Expect optional model/context-dependent semantic radio controls,
             explicit physical units and multivalued/compound states without C codes,
             universal defaults or driver-support ceilings. RadioControl retains the
             common authority/resource and reply identities; audio remains separate.
             Reject catalogue/inventory/driver management, implementation algorithms,
             invented filter widths, conflation of the three Hz spans and inferred
             delivery. Existing graph validation and product verification cases remain
             companions; this declaration records no review or runtime verdict.
             For radio property verification, read pinned Hamlib rig.h standard IDs and
             channel/channel_cap definitions independently, then compare the companion
             tools/sysml/tests/radio_source_coverage.tsv and owning types. Check all114
             standard meanings, stored28members, units, exact native metadata-owner links,
             context-conditioned ranges/power/steps/filter choices and separate access.
             Remove/misroute a metadata owner or change a Hz field to fraction: focused
             tests must refuse it. Expect one current value per property/context, separate
             capabilities, typed temporary query/set parameters, readonly meters, explicit
             failure/stale/unknown semantics, and no requested value confirmed by ACK.
             Inspect unresolved extension limits rather than accepting a completeness claim.
             Run focused tests on this PC at cost2, full Pilot/graph validation and99traces;
             parser success does not execute these planned action contracts. */
        attribute method : String = "manual independent public-property and interface correspondence review";
        attribute executionStatus : String = "planned; semantic resolution does not establish review or runtime acceptance";
    }
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
    doc /* Canonical product scope and navigation. WstxRequirements owns stable
         FR/CL/TC declarations. WstxArchitecture owns parts/ports/connections;
         WstxStationProtocol the shared status/auth/transport contract;
         WstxProfiles configuration/persistence; WstxRecordingReceive recording/display;
         WstxModemDecode pure FT4/FT8 decoding; WstxOfflineDecode payloads; WstxRadioIO live
         capture/conversion/CAT; WstxOperatingLayout presentation and WstxOperatingReceive receive selection/content coding;
         WstxTransmit FT8/FT4 message packing, waveform and transmit period scheduling;
         WstxContact the standard FT8 contact, sequencing, log and operator displays;
         WstxStrategy strategies of class strategy and contest, their settings and ranking,
         and the run that applies them;
         WstxContest the contest strategies and their profiles from the official rules.
         Requirements and exact algorithm/interface/verification semantics in these
         packages are one functional authority. A view renders existing facts; it is
         not an extra architecture. Declared coverage is not an execution verdict.
         Process/build/skill documentation remains outside the product model. */

    attribute def BehaviorBaseline {
        attribute suite : String = "WSJT-X";
        attribute release : String = "v3.3.0-beta4";
        attribute sourceCommit : String = "0f7d5928449ec747c3d1f6da1306f8c94404c3a9";
        attribute releaseReference : String = "https://github.com/WSJTX/wsjtx/releases/tag/v3.3.0-beta4";
        attribute portableCodecManifest : String = "fixtures/decoder/reference-manifest.json";
        doc /* Extract useful documented/observed suite behaviour, not its file/module
             layout or every utility executable. The imported original branch remains
             an archive, not this current behaviour baseline. A newer beta requires an
             explicit baseline change. Selected GPL-compatible numerical routines may
             be adapted into Rust with provenance/attribution retained. Rust is the
             station/protocol implementation; HTML/CSS/JavaScript is the browser.
             Existing native Windows audio/CAT bindings are allowed only at their
             reviewed safe-interface boundary; Fortran/C++ is not the final runtime. */
    }
    enum def BaselineMode { enum FST4; enum FST4W; enum FT4; enum FT8; enum JT4; enum JT9;
        enum JT65; enum MSK144; enum Q65; enum WSPR; enum Echo; enum JTTY; }
    attribute def ModeCapability {
        attribute mode : BaselineMode;
        attribute receive : WstxRequirements::ImplementationState;
        attribute encode : WstxRequirements::ImplementationState;
        attribute operation : WstxRequirements::ImplementationState;
        doc /* Initial inventory, not a claim of implemented support. Only FT4/FT8
             have partial live-receive implementations in the current baseline.
             Transmission and full QSO remain target for both; all other listed modes
             require variant/submode/timing/message/special-workflow inventory before
             implementation completeness. A decoder alone never enables transmit.
             Unsupported operations are refused rather than silently using another mode. */
    }
    attribute def ReleasePolicy {
        attribute firstDesktopPlatform : String = "Windows x64/MSVC";
        attribute laterDesktopPlatforms : String = "macOS; Linux";
        attribute firstReleaseIncludesMicrocontrollers : Boolean = false;
        attribute optionalSecondaryEdition : String = "microcontrollers and constrained devices";
        doc /* Exact supported Windows versions and final hardware matrix remain
             unsettled beyond the initial x64 development target. Validate platform
             audio/control/UI/packaging/performance before claiming a later desktop
             target. A secondary edition chooses its own modes/hardware/memory/link
             limits; desktop features need not fit a microcontroller. Keep protocol
             and DSP boundaries portable where practical. No fixed physical radio
             count follows from station count. Four concurrent stations is a minimum
             reference acceptance workload, not a software limit or hardware promise. */
    }
    requirement ProductCapabilities {
        doc /* Intended useful WSJT-X/MAP65/QMAP scope includes receive/transmit audio
             and DSP; encoding/decoding/synchronization/message handling; station/radio
             configuration and sequencing; spectrum/waterfall/decode/operator displays;
             QSO/logging/reporting and external protocols; EME astronomical/Doppler/Echo
             workflows; wideband/IQ/polarization/application coordination; selected
             command-line/data/help/packaging utilities. Each selected capability has
             an owner and explicit target/partial/implemented state. Do not infer full
             suite parity from FT4/FT8 receive or construct speculative services.
             Exact inventories for logging compatibility, external UDP/reporting,
             EME, wideband and utilities remain unresolved before their implementation.
             Wideband/complex/multichannel input requires explicit typed capabilities,
             never reinterpretation as mono real audio. Modes need not share FT8's
             timing or interactive-QSO assumptions. */
    }
    attribute def AccelerationPolicy {
        attribute coverage : WstxRequirements::ImplementationState = WstxRequirements::ImplementationState::target;
        attribute cpuOnlyRequired : Boolean = true;
        attribute cpuWorkersBounded : Boolean = true;
        attribute automaticWorkersAccountForAllProfiles : Boolean = true;
        attribute operatorWorkerOverrideRequired : Boolean = true;
        attribute preserveDependentStageOrder : Boolean = true;
        attribute gpuRequiredForFirstRelease : Boolean = false;
        attribute selectedGpuApi : String[0..1];
        doc /* Planned desktop optimization route, not implemented acceleration.
             Use bounded CPU workers for independent jobs while reserving audio,
             control and UI capacity. Automatic selection cannot assume each station
             owns the whole PC. Profile optimized FFT/layout/buffer reuse/SIMD first;
             capability-select instruction paths and retain a portable CPU path.
             GPU or other batch/spectrum acceleration is optional; no CUDA/Vulkan/
             Metal/vendor API has been selected. Unavailable/failed optional backends
             fall back to CPU with understandable status. All paths use the same
             independent protocol vectors/recordings, correctness/missed/false-result
             criteria, numeric tolerances and cancellation obligations.
             Measure full audio-to-usable-result latency, scheduling/transfers/delivery,
             interface responsiveness and memory, not just arithmetic throughput.
             Keep an optimization only when measured end-to-end benefit justifies
             maintenance. Evidence names CPU/GPU/OS/compiler/build/workers/workload,
             memory and timing distributions. Benchmark one/multiple workers and each
             available backend on identical inputs; release-specific acceleration
             budgets and supported backends require measured agreement. */
    }
    requirement QualityAndVerification {
        doc /* Preserve selected on-air message and waveform interoperability. Exact
             discrete packing/FEC/symbol vectors and justified floating tolerances are
             independent expectations. Evaluate success, false positives, sensitivity,
             runtime, weak/overlapping/offset signals and device/operator workflows.
             WstxModemDecode fixes its current mode-specific numeric/resource limits;
             those concrete limits supersede general unsettled-budget language.
             Reference decoder output alone is not exhaustive truth. Pin reference
             binary/version/hash/settings/input; do not substitute the original archive.
             Compare receive/transmit interoperability through recordings/controlled
             loopback before applicable live operations. Preserve configuration/logs
             across ordinary restart and report device/connection failure truthfully.
             DSP/protocol processing remains independently testable without GUI/radio.
             Dependencies must be GPLv3-compatible with applicable notices retained.
             Windows acceptance precedes its first release; each later platform has
             its own validation and explicit unsupported capability declarations. */
    }
    requirement SharedDataOwnership {
        doc /* Profile/boot identity, revision, authentication, Origin, HTTP/WebSocket
             validation and liveness have one shared owner. Native audio/conversion,
             canonical immutable sample blocks, shared receive jobs, FFT spectrum and
             pure FT4/FT8 modem are implemented boundaries, not a second profile or
             transport authority. WstxRecordingReceive defines source schema/lifetime,
             WstxRadioIO native conversion/timing and WstxModemDecode numerical work.
             Integer-to-real PCM mapping is not AGC/filtering/normalization. Native
             rate conversion has one owner; no recorded/live-specific modem resamplers.
             RustFFT provider/conventions are shared while mode/display plans remain
             scoped by their contracts. No speculative FFT wrapper or duplicate cache.
             Context carries stable profile/display identity, validated config revision
             and boot; ports/names are not identity. Secrets are not ordinary snapshots.
             Operations distinguish caller authority, request/operation ID, result/error,
             current revision, pending and completion. Reconnection snapshots never
             replay a stale transmit request. Concrete wire mappings are explicit,
             never serialization of whole internal objects. File transfer is separate
             from small control messages and selects recording identity, not client paths. */
    }
    requirement ProcessingAndHaltOwnership {
        doc /* One station owner serializes validated state transitions while bounded
             CPU work runs outside it and returns job-tagged output. Validate profile,
             source and generation on input/completion/cancel; obsolete results cannot
             overwrite a new source/mode. Clients distinguish confirmed/pending/stale;
             required results, radio/QSO/contact state remain server-owned.
             Recorded/live samples share one receive boundary; sample clock differs
             from optional UTC metadata. Live device/sample-to-UTC mapping never uses
             browser timers. Network execution is not a decoder work queue. All jobs,
             buffers/concurrency have declared bounds and an operator-visible budget
             across profiles. Cooperative cancellation has bounded checkpoints; halt
             MUST NOT wait for decode completion, receive cancellation or visualization.
             Unbounded blocking workers are not a CPU scheduler; an already running
             blocking task is not claimed abortable. Concrete shared executor and
             acceleration choices require measured workloads, with CPU correctness. */
    }
    requirement RemoteDeliveryPolicy {
        doc /* Commands/state/results have priority over discardable visualization.
             Server produces reduced display data; JavaScript renders/colors/local
             filters it. Visualization may be disabled. Raw audio is an explicit
             source/transfer, not mandatory continuous remote browser traffic.
             Commands are accepted/refused/failed explicitly, never silently dropped.
             Old display frames may be replaced; required state/QSO/decode information
             instead has delivery/resynchronization or explicit loss reporting. Refuse
             new work at its budget without disrupting other instances. Restart/link
             loss cancels or marks operations unavailable according to their contract.
             No single-instance status test proves aggregate audio/DSP/display for N
             instances; each workload names its limits and measurement layer. */
    }
    attribute def FixtureProvenance {
        attribute ft8Manifest : String = "fixtures/decoder/manifest.json";
        attribute ft4Manifest : String = "fixtures/decoder/ft4-manifest.json";
        attribute codecReference : String = "fixtures/decoder/reference-manifest.json";
        attribute simulatorManifest : String = "fixtures/decoder/simulator-cases.json";
        attribute sampleSource : String = "https://github.com/kgoba/ft8_lib/tree/9fec6ca39886edbf96f4f5e71edc76da5074e871/test/wav";
        doc /* Manifests pin identity/hashes/source/license limitations. Existing text
             outputs are historical references, NOT exhaustive independently verified
             ground truth. Independently synthetic/noise/overlap/offset inputs accompany
             live recordings to measure sensitivity, false decodes and numeric error.
             Evaluate interoperability/quality/latency rather than adopting embedded
             resource limits. Sample use does not require importing its decoder.
             fixtures/decoder holds the concrete protocol/physical fixture expectations and
             simulator admission; README retains attribution and sample licensing.
             Investigation dates or discovery history are not functional obligations. */
    }
    package ContractIndex {
        doc /* Numeric references inside model prose are local contract aliases. 4.1/6.1/12.1..12.4:
             SharedProtocol. 4.2/6.2/12.5: Profiles. 4.3/6.3: NativeFlex plus FR-023
             and its six TC-023 cases. 4.4/6.4: RecordingAndDisplay, ProfileRecordings and Modem;
             4.5/12.8: LiveRadio. 4.7/6.6: Operating. 11: Architecture.
             12.1.1/4.7.3/4.7.5/12.8.1: OperatingReceive. 12.6: RecordingAndDisplay. 12.7: SharedRecord. 13.6: ModemDecode's cases
             TC-004-001 and TC-004-002. Other scope/quality/provenance clauses are in this package.
             These aliases are resolved model elements, not external file references. */
        alias SharedProtocol for WstxStationProtocol;
        alias Profiles for WstxProfiles;
        alias ProfileRecordings for WstxProfileRecordings;
        alias NativeFlex for WstxFlexSession::NativeFlexBoundary;
        alias RecordingAndDisplay for WstxRecordingReceive;
        alias Modem for WstxOfflineDecode;
        alias ModemDecode for WstxModemDecode;
        alias LiveRadio for WstxRadioIO;
        alias Operating for WstxOperatingLayout;
        alias OperatingReceive for WstxOperatingReceive;
        alias Architecture for WstxArchitecture;
        alias Transmit for WstxTransmit;
        alias Contact for WstxContact;
        alias Mcp for WstxMcp;
        alias Udp for WstxUdp;
        alias Strategy for WstxStrategy;
        alias ContestStrategies for WstxContest;
        alias SharedRecord for WstxDecodes::ResultRecord;
        alias ReceiveSpectrum for WstxReceiveSpectrum;
        alias LiveReceive for WstxLiveReceive;
        alias ReceiveStartup for WstxReceiveStartup;
        alias FlexSession for WstxFlexSession;
        alias McpEndpointPackage for WstxMcpEndpoint;
        alias AudioDevicePackage for WstxAudio;
        alias AudioCapturePackage for WstxAudioCapture;
        alias AudioEndpointsPackage for WstxAudioEndpoints;
        alias AudioPlaybackPackage for WstxAudioPlayback;
        alias CatLifecyclePackage for WstxCatLifecycle;
        alias RadioFactsPackage for WstxRadioFacts;
        alias RadioSetupPackage for WstxRadioSetup;
        alias RadioPropertiesPackage for WstxRadioProperties;
        alias HttpContentCodingPackage for WstxHttpContentCoding;
        alias StationAuthorityPackage for WstxStationAuthority;
        alias TransmitSchedulePackage for WstxTransmitSchedule;
        alias TransmitClockPackage for WstxTransmitClock;
        alias TxLevelPackage for WstxTxLevel;
        alias MessageEncodePackage for WstxMessageEncode;
        alias StandardQsoPackage for WstxStandardQso;
        alias SpecialActivitiesPackage for WstxSpecialActivities;
        alias QsoTransmitPackage for WstxQsoTransmit;
        alias LogbookPackage for WstxLogbook;
        alias CountryFilePackage for WstxCountryFile;
        alias QsoWirePackage for WstxQsoWire;
        alias BandActivityPackage for WstxBandActivity;
        alias SignalAreaPackage for WstxSignalArea;
        alias QsoPanePackage for WstxQsoPane;
        alias LowerPanelPackage for WstxLowerPanel;
        alias SettingsPackage for WstxSettings;
        alias UnitsPackage for WstxUnits;
    }
    dependency scopeBoundary from ProductCapabilities to WstxRequirements::'FR-004';
    dependency deliveryBoundary from RemoteDeliveryPolicy to WstxRequirements::'FR-021';

}
