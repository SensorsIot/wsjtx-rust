package WstxArchitecture {
    private import ScalarValues::*;
    doc /* Product structure: one selected-radio deployment context, its four physical
         participants, software owners and typed exchanges. The viewer may run locally
         on the controller computer or remotely over the station link; the logical
         roles and profile-scoped protocol remain the same. Windows x64/MSVC is the
         first desktop target; portability and later platforms follow
         WstxProductScope::ReleasePolicy, not an assertion of platform acceptance.
         WstxRequirements owns stable capability/status and verification declarations.
         WstxProductScope owns capability scope, shared data ownership, processing/halt,
         remote delivery and transmit safety policies. This structure includes target
         responsibilities; a part or connection does not assert delivered capability.
         System processes classify technical capabilities in the existing receive,
         mode, transport and device owners. Operating workflows classify operator
         QSO actions in station/transmit/QSO and browser responsibilities; configuration
         workflows classify persisted settings in profile/station responsibilities.
         Strategy workflows classify objectives, ranking and automation, all target
         only; selection/ownership policies remain planned. These four behavioural
         groups do not introduce additional runtime services or a strategy engine.
         Items below describe semantic responsibilities, not wire schemas or Rust APIs.
         Detailed behaviour stays with WstxStationProtocol, WstxProfiles,
         WstxRecordingReceive, WstxOfflineDecode, WstxRadioIO,
         WstxOperatingLayout and WstxOperatingReceive. */

    part physicalStation {
        doc /* One selected-radio reference context with user, viewer, controller and radio
             roles. Viewer/controller roles may share a computer. This is not universal
             radio cardinality or a radio count derived from station count. */
        part user : Operator;
        part viewer : ViewerComputer;
        part controller : StationControllerComputer;
        part radio : Radio;
        connection localInteraction connect user.interaction to viewer.operator;
        connection stationLink connect viewer.stationLink to controller.viewerLink {
            part attachments[*] : BrowserAttachment;
        }
        connection radioAudio connect controller.radioAudio to radio.audio {
            part channels[*] : RadioAudioAttachment;
        }
        connection radioControl connect controller.radioControl to radio.control {
            part channels[*] : RadioControlAttachment;
        }
    }
    view physicalInterconnection : StandardViewDefinitions::InterconnectionView {
        expose physicalStation::*;
    }

    requirement PhysicalDeploymentStructure {
        doc /* Architectural refinement of the existing deployment scope: the model MUST
             contain the user/viewer/controller/radio context and its operator, station,
             separate audio and control paths, with profile-scoped endpoint selection.
             Variable browser and station populations MUST NOT become a fixed station
             count, all-to-all routing, or an additional detached deployment. */
    }
    requirement StationResourceIdentity {
        doc /* Architectural refinement of WstxProfiles and
             WstxProductScope::NativeFlexBoundary: each station MUST compose one profile,
             one selected backend variation and one selected-radio binding, and reference
             the controller's common authority. All control requests/outcomes MUST retain
             request/resource identity through that authority to the selected backend.
             A backend or native session MUST NOT introduce an authority bypass. */
    }
    requirement ResponsibilityAndExchangeBoundaries {
        doc /* Architectural refinement of WstxProductScope::SharedDataOwnership,
             ProcessingAndHaltOwnership, RemoteDeliveryPolicy and TransmitSafetyPolicy:
             the declared owners MUST retain their separate typed/directed exchanges.
             Recording storage MUST feed the common receive path; receive and encode
             MUST connect to pure mode functions; audio and control MUST stay separate.
             Browser/MCP adapters MUST use station operations rather than direct backend
             access. The ownership explanations and existing policy contracts apply
             together; target parts do not claim runtime delivery or settled policy. */
    }
    dependency deploymentOwnership from physicalStation to PhysicalDeploymentStructure;
    dependency stationIdentityOwnership from physicalStation::controller::stations to StationResourceIdentity;
    dependency boundaryOwnership from physicalStation::controller::stations to ResponsibilityAndExchangeBoundaries;

    verification ResolvedArchitectureGraph {
        subject deployment :> physicalStation;
        doc /* Level 2 isolated automated model test on the development PC; no radio,
             device or runtime service. Resolve the accepted model and legal negative
             mutations with the pinned semantic validator. Independent expectations are
             literal required endpoints, complete item-kind/direction signatures,
             population/reference subsets, backend alternatives and identity bindings
             in the existing architecture integrity oracle, not candidate-derived counts.
             Expect user-to-viewer, profile-selected viewer-to-web/station and separate
             backend-to-selected-radio audio/control paths; upload-to-profile-to-receive,
             receive-to-mode and encode-to-mode paths; exactly one effective authority
             whose bound request/outcome and resource context reach that same backend.
             Missing delegation/encode, reversed provider/waveform direction, wrong item
             kind, redirected association/context, weakened identity binding, split or
             bypassed authority, duplicate backend, detached stations and view-created
             structure MUST be rejected even if legal SysML. The unchanged graph has
             33 parts, 8 references, 80 ports and 69 connections; counts alone are
             insufficient. This case checks structure, not runtime timing, persistence,
             failure handling, platform operation or RF safety. */
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
        subject deployment :> physicalStation;
        doc /* Manual contract review on the development PC, without external effects.
             Compare this decomposition with WstxProductScope::ReleasePolicy,
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

    item def OperatorRequest;
    item def Presentation;
    item def StationRequest;
    item def StationOutcome;
    item def Recording;
    item def SampleBlock {
        doc /* Immutable recorded and live samples feed the same receive boundary.
             WstxRecordingReceive::SampleBlock owns concrete recorded element units,
             clocks, ownership/lifetime and bounds; WstxRadioIO owns live adaptation.
             Source-specific metadata and discontinuities must be explicit; a generic
             architectural item does not settle every future live format. */
    }
    item def AudioOutcome;
    item def ControlRequest { ref part resourceContext : RadioBinding; }
    item def ControlOutcome { ref item request : ControlRequest; }
    item def ProcessingRequest {
        doc /* Receive job/cancel lifecycle correlates profile, boot, source, job and
             generation with immutable settings/results. WstxRecordingReceive owns
             recorded spectrum lifetimes, bounds and cancellation; WstxOfflineDecode
             refines mode settings/results on that lifecycle. Transmit lifecycle and
             independent halt remain outside receive jobs. */
    }
    item def ProcessingResult {
        doc /* WstxRecordingReceive::SpectrumFrame owns spectrum units, identity,
             bounds and replaceable display delivery. WstxOfflineDecode::ResultRecord
             and ResultPage own mode payloads and required result delivery/retention.
             These have different delivery obligations despite sharing processing. */
    }
    item def EncodeRequest;
    item def Waveform;
    item def ProfileRequest;
    item def ProfileOutcome;
    item def NativeSessionOperation;
    item def NativeSessionOutcome;

    port def LocalInteraction {
        out item request : OperatorRequest;
        in item presentation : Presentation;
    }
    port def StationOperations {
        out item request : StationRequest;
        in item outcome : StationOutcome;
    }
    port def BrowserExchange :> StationOperations {
        out item upload : Recording;
    }
    port def RecordingTransfer { out item recording : Recording; }
    port def ProfileAccess {
        out item request : ProfileRequest;
        in item outcome : ProfileOutcome;
    }
    port def AudioExchange {
        out item playback : SampleBlock;
        in item capture : SampleBlock;
        in item outcome : AudioOutcome;
    }
    port def AudioStatus { out item outcome : AudioOutcome; }
    port def ReceiveSamples {
        out item samples : SampleBlock;
        out item outcome : AudioOutcome;
    }
    port def ReceiveProcessing {
        out item request : ProcessingRequest;
        in item result : ProcessingResult;
    }
    port def EncodeProcessing {
        out item request : EncodeRequest;
        in item waveform : Waveform;
    }
    port def RadioControl {
        out item request : ControlRequest;
        in item outcome : ControlOutcome;
        binding replyContext bind outcome.request = request;
    }
    port def SessionAccess {
        out item operation : NativeSessionOperation;
        in item outcome : NativeSessionOutcome;
    }

    part def Operator { port interaction : LocalInteraction; }
    part def BrowserClient {
        doc /* Own presentation/local filtering/color, pending/stale state and requests; not authoritative radio state, timing-critical modulation or transmit authority. */
        port operator : ~LocalInteraction;
        port station : BrowserExchange;
    }
    part def McpClient { port station : StationOperations; }
    part def ViewerComputer {
        port operator : ~LocalInteraction;
        port stationLink : BrowserExchange;
        part browsers[*] : BrowserClient;
        connection operatorDelegation connect operator to browsers.operator;

    }
    part def Radio {
        port audio : ~AudioExchange;
        port control : ~RadioControl;
    }
    part def StationControllerComputer {
        doc /* One controller role hosts variable N station processes. The common authority
             is effective shared-radio responsibility, not a per-process mutex.
             Cross-process placement/leases and actual hardware capacity are constrained
             by WstxProductScope::NativeFlexBoundary and WstxRadioIO. Profile-scoped
             routing is not all-to-all delivery or simultaneous transmission. */
        port viewerLink : ~BrowserExchange;
        port radioAudio : AudioExchange;
        port radioControl : RadioControl;
        part stations[*] : StationProcess;
        ref part mcpClients[*] : McpClient;
        doc /* MCP clients are referenced, not deployed onto this computer by composition.
             Controller attachments own routing associations only. Client placement and
             detailed authority remain unresolved before MCP implementation. */
        part radioAuthority : RadioAuthority;

        part mcpAttachments[*] : McpAttachment;

    }
    part def BrowserAttachment {
        doc /* One profile-scoped browser/station association carried by the physical IP
             link. Each endpoint reference selects one member, never the whole population. */
        ref part browser : BrowserClient :> physicalStation.viewer.browsers;
        ref part station : StationProcess :> physicalStation.controller.stations;
        port clientBoundary : ~BrowserExchange;
        connection browserDelegation connect browser.station to clientBoundary;
        connection webDelegation connect clientBoundary to station.web.client;
    }
    part def McpAttachment {
        ref part client : McpClient :> physicalStation.controller.mcpClients;
        ref part station : StationProcess :> physicalStation.controller.stations;
        connection mcpClientOperations connect client.station to station.mcp.client;
    }
    part def RadioBinding {
        doc /* Persisted intent resolves the selected physical radio/resource at connection.
             WstxProductScope::NativeFlexBoundary leaves native slice/handle schema
             and actual radio capacity as implementation prerequisites. */
        ref part radio : Radio :> physicalStation.radio;
    }
    part def RadioAudioAttachment {
        ref part station : StationProcess :> physicalStation.controller.stations;
        connection audioDelegation connect station.backend.radioAudio to station.radioBinding.radio.audio;
    }
    part def RadioControlAttachment {
        ref part station : StationProcess :> physicalStation.controller.stations;
        connection controlDelegation connect station.backend.radioControl to station.radioBinding.radio.control;
    }
    part def RadioAuthority {
        doc /* One effective authority for constrained resources and transmit access across
             all station/backend choices. This is not a new process placement decision. */
        port requests : ~RadioControl;
        port authorized : RadioControl;
        binding authorizedContext bind authorized.request = requests.request;
        binding returnedContext bind requests.outcome = authorized.outcome;
    }
    part def StationService {
        doc /* Own authoritative station state, operations/jobs/transitions and authorization; not HTTP/MCP parsing or device protocol syntax. One owner validates profile/source/generation and rejects obsolete results. */
        doc /* Station-owned validation, state, jobs and operation authority. This owner
             validates uploads before handing them to its selected profile's storage. */
        port webOperations : ~StationOperations;
        port mcpOperations : ~StationOperations;
        port profile : ProfileAccess;
        port receive : StationOperations;
        port transmit : StationOperations;
        port qso : StationOperations;
        port control : RadioControl;
        port upload : ~RecordingTransfer;
        port acceptedRecording : RecordingTransfer;
        port audioStatus : ~AudioStatus;
    }
    part def WebAdapter {
        doc /* Own embedded client, HTTP/file transfer/versioned WebSocket, transport authentication and Origin checks; no second QSO/modem engine or direct radio writes. */
        doc /* WstxStationProtocol owns shared authentication, Origin and HTTP/WebSocket
             semantics. WstxOperatingReceive::HttpContentCodingBoundary refines bounded
             GET coding after handler/auth/errors/caps, with one dispatch and unchanged
             JSON/WebSocket identity; it creates no second transport authority. */
        port client : ~BrowserExchange;
        port station : StationOperations;
        port recording : RecordingTransfer;
    }
    part def McpAdapter {
        doc /* Own protocol validation/caller context and configured station-selection/automation requests. No independent station state, backend access or separate transmit permission; same station operations and safety policy as browser. */
        port client : ~StationOperations;
        port station : StationOperations;
    }
    part def PersistedProfile {
        doc /* Bootstrap/profile owns selection, stable identity, endpoints, exclusive ownership, validation and storage; not DSP or browser state. */
        doc /* Exactly one explicitly selected profile per process owns stable identity,
             configuration, contacts and recordings. WstxProfiles owns its schema,
             persistence, validation and session behaviour. */
        port context : ~ProfileAccess;
        port contacts : ~ProfileAccess;
        port upload : ~RecordingTransfer;
        port recordedSamples : ReceiveSamples;
        part recordings : RecordedSource;
        connection storedUpload connect upload to recordings.upload;
        connection storedSamples connect recordings.samples to recordedSamples;
    }
    part def RecordedSource {
        doc /* Validated profile-owned recording, selected by identity rather than arbitrary
             client paths. No live audio device is required for this input. */
        port upload : ~RecordingTransfer;
        port samples : ReceiveSamples;
    }
    part def ReceivePipeline {
        doc /* Own sample-window handling, normalization/resampling and bounded jobs/spectrum; not file dialogs, HTTP, CAT or UI rendering. PCM-unit mapping is not gain control and native conversion has one owner. */
        doc /* One shared native-format/rate conversion owner feeds canonical samples;
             no source-specific modem resamplers. PCM unit mapping differs from AGC
             and modem normalization. WstxRecordingReceive owns recorded spectrum,
             shared RustFFT 6.4.1 ordering/scaling and buffer obligations;
             WstxOfflineDecode owns mode window/history/decoder quanta and independent
             vectors; WstxRadioIO owns live adapter/conversion semantics. */
        port jobs : ~StationOperations;
        port audio : ~ReceiveSamples;
        port processing : ReceiveProcessing;
    }
    part def ModeFunctions {
        doc /* Pure protocol/symbol/waveform and decoding calculations with independent vectors; no filesystem/hardware/network/wall-clock dependency. */
        doc /* Pure receive calculations and encoding/waveform generation depend on no
             device, filesystem, wall-clock or network. WstxOfflineDecode owns concrete
             mode contracts and status; hardware format adaptation and common rate
             conversion remain outside this boundary. */
        port receive : ~ReceiveProcessing;
        port encode : ~EncodeProcessing;
    }
    part def TransmitService {
        doc /* Own UTC scheduling, transmit state, audio/PTT coordination and priority halt; no browser timer or visualization-queue dependency. Defaults UNARMED on startup. Halt never waits for decode, receive cancellation or congestion. Controller/device loss and authority-expiry policy are settled before hardware TX and cannot be replaced in MCP. */
        doc /* UTC scheduling, operation authority and audio/PTT coordination reuse the
             common resource context. WstxProductScope::TransmitSafetyPolicy owns
             unresolved deadlines/controller-loss/expiry policy before hardware TX;
             WstxProductScope::ProcessingAndHaltOwnership separates priority halt from
             receive completion/cancellation and optional display congestion. */
        port operations : ~StationOperations;
        port encode : EncodeProcessing;
        port audio : AudioExchange;
        port control : RadioControl;
    }
    part def QsoAndLogging {
        doc /* Own exchange/completion/cancel and durable contacts; never bypass transmit authority or another profile storage. Stable completion identity and explicit persisted/unsaved outcome prevent silent duplicate contacts when completion replays. Concrete log schema/compatibility remains a target decision. */
        port operations : ~StationOperations;
        port contacts : ProfileAccess;
    }
    part def AudioInterface {
        doc /* Own sources/sinks, device/channel sample movement, metadata and device failures. No CAT/PTT, mode decoding or QSO decisions. CAT-disabled audio and control without an open audio device remain independent. */
        doc /* Independent samples, timing and failures; CAT-disabled live input and stored
             recordings use the same receive boundary. Does not issue control commands. */
        port status : AudioStatus;
        port recorded : ~ReceiveSamples;
        port receive : ReceiveSamples;
        port transmit : ~AudioExchange;
        port backend : AudioExchange;
    }
    part def RadioControlInterface {
        doc /* Own selected capabilities, typed CAT/control/PTT/status/resource claims; not audio samples/sound devices, browser/MCP policy or duplicate modem logic. */
        doc /* Capabilities, CAT/PTT/status, independent failures and resource claims. No
             samples; Rust control subset only, no full Hamlib port/API or mandatory library. */
        port station : ~RadioControl;
        port transmit : ~RadioControl;
        port backend : RadioControl;
    }
    part def AudioDeviceAdapter {
        port host : ~AudioExchange;
        port radio : AudioExchange;
    }
    part def RustRadioDriver {
        port authorized : ~RadioControl;
        port radio : RadioControl;
    }
    abstract part def RadioBackend {
        port audio : ~AudioExchange;
        port control : ~RadioControl;
        port radioAudio : AudioExchange;
        port radioControl : RadioControl;
    }
    part def StandardBackend :> RadioBackend {
        doc /* Standard selected audio devices and optional CAT/PTT capabilities. Logical
             driver existence does not assert connected/available control or ready TX. */
        part audioDevices : AudioDeviceAdapter;
        part controlDriver : RustRadioDriver;
        connection audioHost connect audio to audioDevices.host;
        connection audioRadio connect audioDevices.radio to radioAudio;
        connection controlHost connect control to controlDriver.authorized;
        connection controlRadio connect controlDriver.radio to radioControl;
    }
    part def NativeAudio :> AudioDeviceAdapter { port session : SessionAccess; }
    part def NativeControl :> RustRadioDriver { port session : SessionAccess; }
    part def NativeSession {
        doc /* A managed native session may serve audio and control. It is not a second
             arbitration authority. WstxProductScope::NativeFlexBoundary leaves session
             ownership/sharing/lifetime unresolved; this provider type does not require
             a separate session per station. */
        port audio : ~SessionAccess;
        port control : ~SessionAccess;
    }
    part def NativeBackend :> RadioBackend {
        doc /* Optional Phase 2 alternate without external SmartSDR/CAT/DAX bridges.
             Logical associations select no native API schema or physical streams.
             The session is referenced, not composed by this backend. Required
             ownership/sharing/lifetime decisions in WstxProductScope::NativeFlexBoundary
             remain prerequisites; this alternative does not assert full native delivery. */
        part audioDevices : NativeAudio;
        part controlDriver : NativeControl;
        ref part session : NativeSession;
        connection audioHost connect audio to audioDevices.host;
        connection audioRadio connect audioDevices.radio to radioAudio;
        connection controlHost connect control to controlDriver.authorized;
        connection controlRadio connect controlDriver.radio to radioControl;
        connection audioSession connect audioDevices.session to session.audio;
        connection controlSession connect controlDriver.session to session.control;
    }
    part def StationProcess {
        part profile : PersistedProfile;
        part station : StationService;
        part web : WebAdapter;
        part mcp : McpAdapter;
        part receive : ReceivePipeline;
        part modes : ModeFunctions;
        part audio : AudioInterface;
        part radioControl : RadioControlInterface;
        part transmit : TransmitService;
        part qso : QsoAndLogging;
        part radioBinding : RadioBinding;
        ref part authority : RadioAuthority :> physicalStation.controller.radioAuthority;
        port authorityRequest : RadioControl;
        port authorizedControl : ~RadioControl;
        variation part backend : RadioBackend {
            doc /* Exactly one backend selection per station; alternatives are not concurrent
                 instances. Cardinality/selection are structural review obligations. */
            variant part standardDevices : StandardBackend;
            variant part nativeFlex : NativeBackend;
        }
        connection webOperations connect web.station to station.webOperations;
        connection mcpOperations connect mcp.station to station.mcpOperations;
        connection profileContext connect station.profile to profile.context;
        connection receiveJobs connect station.receive to receive.jobs;
        connection transmitOperations connect station.transmit to transmit.operations;
        connection qsoOperations connect station.qso to qso.operations;
        connection stationControl connect station.control to radioControl.station;
        connection receiveSamples connect audio.receive to receive.audio;
        connection audioAvailability connect audio.status to station.audioStatus;
        connection receiveModem connect receive.processing to modes.receive;
        connection encodeModem connect transmit.encode to modes.encode;
        connection transmitAudio connect transmit.audio to audio.transmit;
        connection transmitControl connect transmit.control to radioControl.transmit;
        connection uploadedRecording connect web.recording to station.upload;
        connection validatedRecording connect station.acceptedRecording to profile.upload;
        connection recordedInput connect profile.recordedSamples to audio.recorded;
        connection contactStorage connect qso.contacts to profile.contacts;
        connection selectedAudio connect audio.backend to backend.audio;
        connection authorityRequestDelegation connect radioControl.backend to authorityRequest;
        connection authorizedControlDelegation connect authorizedControl to backend.control;
        connection commonAuthority connect authorityRequest to authority.requests;
        connection authorizedBackend connect authority.authorized to authorizedControl;
        binding requestContext bind authorityRequest.request.resourceContext = radioBinding;
        binding backendContext bind backend.control.request.resourceContext = radioBinding;
    }

    dependency audioPromise from AudioInterface to WstxRequirements::'FR-002';
    dependency controlPromise from RadioControlInterface to WstxRequirements::'FR-009';
    dependency profilesPromise from PersistedProfile to WstxRequirements::'FR-022';
    dependency flexPromise from NativeBackend to WstxRequirements::'FR-023';
    doc /* Responsibility traces identify the owning boundary for an existing requirement,
         not delivered capability or an executed verification. */
    dependency configurationPromise from StationService to WstxRequirements::'FR-001';
    dependency receivePromise from ReceivePipeline to WstxRequirements::'FR-003';
    dependency decodePromise from ModeFunctions to WstxRequirements::'FR-004';
    dependency encodePromise from ModeFunctions to WstxRequirements::'FR-005';
    dependency timingPromise from TransmitService to WstxRequirements::'FR-006';
    dependency receiveTimingPromise from ReceivePipeline to WstxRequirements::'FR-006';
    dependency qsoPromise from QsoAndLogging to WstxRequirements::'FR-007';
    dependency haltPromise from TransmitService to WstxRequirements::'FR-008';
    dependency displayPromise from BrowserClient to WstxRequirements::'FR-010';
    dependency loggingPromise from QsoAndLogging to WstxRequirements::'FR-011';
    dependency integrationPromise from StationService to WstxRequirements::'FR-012';
    dependency emePromise from ModeFunctions to WstxRequirements::'FR-013';
    dependency widebandPromise from ReceivePipeline to WstxRequirements::'FR-014';
    dependency utilitiesPromise from ModeFunctions to WstxRequirements::'FR-015';
    dependency persistencePromise from PersistedProfile to WstxRequirements::'FR-016';
    dependency helpPromise from BrowserClient to WstxRequirements::'FR-017';
    dependency recordingPromise from RecordedSource to WstxRequirements::'FR-018';
    dependency htmlPromise from WebAdapter to WstxRequirements::'FR-019';
    dependency mcpPromise from McpAdapter to WstxRequirements::'FR-020';
    dependency linkPromise from BrowserAttachment to WstxRequirements::'FR-021';
    package ImplementedStatusSlice {
        doc /* Implemented status/TLS subset alongside WstxProfiles profile functionality.
             The target deployment does not assert full radio/modem or MCP delivery;
             detailed coverage remains in WstxRequirements and the owning packages. */
        part def StatusServer;
        dependency statusScope from StatusServer to WstxRequirements::'CL-003-01';
        dependency statusProtocol from StatusServer to WstxRequirements::'CL-003-02';
    }
    dependency coordinatedReceivePromise from ReceivePipeline to WstxRequirements::'CL-008-07';
    doc /* WstxOperatingReceive refines coordinated receive controls on the existing
         receive and radio authority path: single-owner release/setup/readback/restart
         and cancellation fences. It introduces no additional station/backend/physical
         connector, sample source or deployment. */
}
