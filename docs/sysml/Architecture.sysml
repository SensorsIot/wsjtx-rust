// Canonical architecture SHA256: 51bd47fb9c8cb09f2b406bd9ca2767a04402609450805c4e93d2746f4b02c9bb
package WstxArchitecture {
    doc /* Target architecture from docs/ARCHITECTURE.md, which remains authoritative.
         One physical deployment with software decomposition; not implemented radio support.
         Items are semantic responsibilities, not wire schemas or Rust API definitions. */

    part physicalStation {
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

    item def OperatorRequest;
    item def Presentation;
    item def StationRequest;
    item def StationOutcome;
    item def Recording;
    item def SampleBlock;
    item def AudioOutcome;
    item def ControlRequest { ref part resourceContext : RadioBinding; }
    item def ControlOutcome { ref item request : ControlRequest; }
    item def ProcessingRequest;
    item def ProcessingResult;
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
             denotes the effective shared-radio responsibility, not an in-process mutex.
             #8/#13 settle cross-process placement/leases and actual hardware limits.
             Browser routing is profile-scoped; these population connections do not assert
             all-to-all request delivery or simultaneous transmission. */
        port viewerLink : ~BrowserExchange;
        port radioAudio : AudioExchange;
        port radioControl : RadioControl;
        part stations[*] : StationProcess;
        part mcpClients[*] : McpClient;
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
        doc /* Persisted intent resolves a selected physical radio/resource at connection.
             Native slice/handle schema and actual radio capacity remain #13 decisions. */
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
        port client : ~BrowserExchange;
        port station : StationOperations;
        port recording : RecordingTransfer;
    }
    part def McpAdapter {
        port client : ~StationOperations;
        port station : StationOperations;
    }
    part def PersistedProfile {
        doc /* Exactly one explicitly selected profile per process, exclusive ownership,
             stable identity, configuration/contact/recording storage. #5 owns schema. */
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
        port jobs : ~StationOperations;
        port audio : ~ReceiveSamples;
        port processing : ReceiveProcessing;
    }
    part def ModeFunctions {
        doc /* Pure receive calculations and encoding/waveform generation. No device,
             filesystem, wall-clock or network dependency; mode support is CR-specific. */
        port receive : ~ReceiveProcessing;
        port encode : ~EncodeProcessing;
    }
    part def TransmitService {
        doc /* UTC mapping/scheduling, operation authority, bounded halt and audio/PTT
             coordination. #9 settles deadlines/controller-loss policy before hardware TX. */
        port operations : ~StationOperations;
        port encode : EncodeProcessing;
        port audio : AudioExchange;
        port control : RadioControl;
    }
    part def QsoAndLogging {
        port operations : ~StationOperations;
        port contacts : ProfileAccess;
    }
    part def AudioInterface {
        doc /* Independent samples, timing and failures; CAT-disabled live input and stored
             recordings use the same receive boundary. Does not issue control commands. */
        port status : AudioStatus;
        port recorded : ~ReceiveSamples;
        port receive : ReceiveSamples;
        port transmit : ~AudioExchange;
        port backend : AudioExchange;
    }
    part def RadioControlInterface {
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
        doc /* A managed native session may serve both implementations. This session is
             not a second arbitration authority and cannot bypass the common authority. */
        port audio : ~SessionAccess;
        port control : ~SessionAccess;
    }
    part def NativeBackend :> RadioBackend {
        doc /* Optional Phase 2 alternate, no external SmartSDR/CAT/DAX bridge required.
             These logical associations select no native API schema or physical streams. */
        part audioDevices : NativeAudio;
        part controlDriver : NativeControl;
        part session : NativeSession;
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
    package ImplementedStatusSlice {
        doc /* Current status/TLS server and embedded client only. Target deployment above
             is not an assertion of implemented profiles, radio, modem or MCP support. */
        part def StatusServer;
        dependency statusScope from StatusServer to WstxRequirements::'CL-003-01';
        dependency statusProtocol from StatusServer to WstxRequirements::'CL-003-02';
    }
}
