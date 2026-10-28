package WstxProductScope {
    private import ScalarValues::*;
    private import WstxRequirements::*;
    private import WstxArchitecture::*;
    private import WstxStationProtocol::*;
    private import WstxProfiles::*;
    private import WstxRecordingReceive::*;
    private import WstxOfflineDecode::*;
    private import WstxRadioIO::*;
    private import WstxOperatingLayout::*;
    private import WstxOperatingReceive::*;
    doc /* Canonical product scope and navigation. WstxRequirements owns stable
         FR/CL/TC declarations. WstxArchitecture owns parts/ports/connections;
         WstxStationProtocol the shared status/auth/transport contract;
         WstxProfiles configuration/persistence; WstxRecordingReceive recording/display;
         WstxOfflineDecode pure FT4/FT8 processing and payloads; WstxRadioIO live
         capture/conversion/CAT; WstxOperatingLayout presentation and WstxOperatingReceive receive selection/content coding.
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
             WstxOfflineDecode fixes its current mode-specific numeric/resource limits;
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
             WstxRadioIO native conversion/timing and WstxOfflineDecode numerical work.
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
    requirement CompletedContactIdentity {
        attribute coverage : WstxRequirements::ImplementationState = WstxRequirements::ImplementationState::target;
        doc /* QSO/logging owns stable completion identity, agreed fields and explicit
             persisted-versus-unsaved outcome. Replayed completion cannot silently
             create a second contact. Each profile owns contact storage; the browser,
             MCP and reconnect path cannot bypass station/transmit authority or another
             profile's storage. Exact fields/format/compatibility and duplicate/recovery
             behaviour are settled before this capability is implemented. */
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
    attribute def TransmitSafetyPolicy {
        attribute coverage : WstxRequirements::ImplementationState = WstxRequirements::ImplementationState::target;
        attribute armedOnStartup : Boolean = false;
        attribute haltWaitsForDecode : Boolean = false;
        attribute mcpMayOverrideLossPolicy : Boolean = false;
        doc /* Transmission is not enabled by the receive baseline. Before hardware
             TX, settle controller/device loss and authority expiry, local stop deadline
             and resource/VOX policy. MCP cannot invent a different safety policy.
             Obtain common authority, prepare selected audio and radio/PTT, schedule,
             then handle completion/halt/failure. Audio failure leaves control-side
             halt/release usable; control failure never fabricates radio-ready state.
             Browser timers or optional display congestion cannot hold transmit authority. */
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
    requirement NativeFlexBoundary {
        attribute coverage : WstxRequirements::ImplementationState = WstxRequirements::ImplementationState::target;
        doc /* Phase2 optional native radio path retains standard independent audio/CAT
             and browser/DSP/QSO/MCP boundaries, without external SmartSDR desktop,
             CAT or DAX bridges. Radio-side firmware/API support still matters. Audio
             and control may reference one managed session; ownership/sharing/lifetime,
             API/stream formats, capacity and leases remain implementation prerequisites.
             Persist profile intent, physical radio identity and slice association;
             reconcile transient handles on connection, never guess another slice or
             replay transmit intent. One effective arbitration authority spans shared
             physical resources and transmission; an in-process mutex per station is
             insufficient. A verified API may justify a common connector, but its
             lifetime cannot depend on one station whose stop must leave others usable.
             No fixed four-GUI-client or simultaneous independent transmitter promise. */
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
             WstxOfflineDecode owns concrete protocol/physical fixture expectations and
             simulator admission; README retains attribution and sample licensing.
             Investigation dates or discovery history are not functional obligations. */
    }
    package ContractIndex {
        doc /* Numeric references inside model prose are local contract aliases. 4.1/6.1/12.1..12.4:
             SharedProtocol. 4.2/6.2/12.5: Profiles. 4.3/6.3: NativeFlex plus FR-023
             and its six TC-023 cases. 4.4/6.4: RecordingAndDisplay and Modem;
             4.5/12.8: LiveRadio. 4.7/6.6: Operating. 11: Architecture.
             12.1.1/4.7.3/4.7.5/12.8.1: OperatingReceive. 12.6: RecordingAndDisplay. 12.7: SharedRecord. 13.6: Modem's simulator
             verifications. Other scope/quality/provenance clauses are in this package.
             These aliases are resolved model elements, not external file references. */
        alias SharedProtocol for WstxStationProtocol;
        alias Profiles for WstxProfiles;
        alias NativeFlex for WstxProductScope::NativeFlexBoundary;
        alias RecordingAndDisplay for WstxRecordingReceive;
        alias Modem for WstxOfflineDecode;
        alias LiveRadio for WstxRadioIO;
        alias Operating for WstxOperatingLayout;
        alias OperatingReceive for WstxOperatingReceive;
        alias Architecture for WstxArchitecture;
        alias SharedRecord for WstxOfflineDecode::ResultRecord;
    }
    dependency scopeBoundary from ProductCapabilities to WstxRequirements::'FR-004';
    dependency contactBoundary from CompletedContactIdentity to WstxRequirements::'FR-011';
    dependency safetyBoundary from TransmitSafetyPolicy to WstxRequirements::'FR-008';
    dependency nativeBoundary from NativeFlexBoundary to WstxRequirements::'FR-023';
    dependency deliveryBoundary from RemoteDeliveryPolicy to WstxRequirements::'FR-021';
}
