// Canonical architecture SHA256: 8e7a28689eee4ef1e3c764c292b658d85964a6d008bd9723d2bfab71cdd89486
package WstxArchitecture {
    doc /* Target architecture from docs/WSTX Rust FSD.md chapter 11, which remains authoritative.
         One physical deployment with software decomposition; not implemented radio support.
         Items are semantic responsibilities, not wire schemas or Rust API definitions.
         CR #6 concrete data/state/HTTP/display/oracles refine existing usages in
         WstxRecordingReceive (RecordingReceive.sysml), FSD4.4/6.4/12.6. This recorded
         input/display slice is delivered; review, validation and acceptance evidence remains on issue #6. */

    doc /* Approved CR #5 profile behavior/data/state/HTTP/session implementation
         contract is WstxProfiles in Profiles.sysml. It refines the existing station
         profile/service/web and viewer browser usages below without adding another
         deployment, runtime part, hardware capability or view. Four independent
         servers suffice for CR #5 acceptance; stations[*] remains variable. */

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
    item def SampleBlock {
        doc /* FSD 11.3 shared receive data: #6 owns one typed immutable sample contract;
             #6 recorded and #8 live producers feed the existing receive path. Element
             type/units, rate, frame clock, optional UTC, discontinuity, buffer owner,
             lifetime, bounds, version and backpressure must be settled before code.
             Concrete version1 recorded samples and spectrum-path bounds are defined by
             WstxRecordingReceive::SampleBlock and FSD4.4; #8 live details remain gated. */
    }
    item def AudioOutcome;
    item def ControlRequest { ref part resourceContext : RadioBinding; }
    item def ControlOutcome { ref item request : ControlRequest; }
    item def ProcessingRequest {
        doc /* FSD 11.3/11.7: #6 owns receive job/cancel lifecycle only. Profile, boot,
             source, job and generation correlate immutable settings and results;
             concrete recorded spectrum types/lifetimes/bounds/cancellation are defined
             in RecordingReceive.sysml; #7 target mode settings/results refine that same
             lifecycle in StationDecode.sysml, pending independent readiness review.
             Receive jobs do not own transmit lifecycle or independent halt. */
    }
    item def ProcessingResult {
        doc /* FSD 11.3: #7 owns mode-specific decoded payload/units/oracles and required
             result delivery/retention; #6 owns spectrum frame units/identity/bounds and
             replaceable display delivery. Concrete spectrum schema/lifetimes are WstxRecordingReceive::SpectrumFrame;
             #7 target decoded payload/retention is WstxOfflineDecode::ResultRecord and
             ResultPage, FSD4.4/6.4/12.7; implementation/readiness not asserted. */
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
        doc /* FSD 11.3/11.7: extend existing shared profile/auth/Origin/HTTP/WebSocket
             services once; dependent issues do not add parallel transport authorities. */
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
        doc /* FSD 11.3/11.7/11.8: #6 establishes common sample and receive job contracts;
             #8 owns one common native-format/rate conversion stage; #7 consumes canonical
             12k samples. PCM unit mapping is distinct from AGC
             or modem normalization. No source-specific modem resamplers. #6/#7 settle
             one shared FFT provider, ordering/scaling, buffer policy and independent
             oracles before either writes FFT code; no speculative wrapper is required.
             FSD4.4 and RecordingReceive.sysml now select shared RustFFT6.4.1 and the
             delivered recorded spectrum contract; review and acceptance evidence remains on issue #6.
             #7 target sizes/history/decoderquanta are in StationDecode.sysml; its independent
             readiness review and #8 live adapter contract remain separate gates. */
        port jobs : ~StationOperations;
        port audio : ~ReceiveSamples;
        port processing : ReceiveProcessing;
    }
    part def ModeFunctions {
        doc /* Pure receive calculations and encoding/waveform generation. No device,
             filesystem, wall-clock or network dependency; mode support is CR-specific.
             FSD 11.3/11.7: #7 owns pure receive functions and mode result payloads;
             hardware/device-format adaptation and common rate conversion stay outside. */
        port receive : ~ReceiveProcessing;
        port encode : ~EncodeProcessing;
    }
    part def TransmitService {
        doc /* UTC mapping/scheduling, operation authority, bounded halt and audio/PTT
             coordination. #9 settles deadlines/controller-loss policy before hardware TX.
             FSD 11.3/11.7: transmit lifecycle/halt is distinct from #6 receive jobs;
             halt cannot wait for receive cancellation, work or congestion. Existing
             context/resource authority is reused rather than recreated. */
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
        doc /* Legacy status/TLS subset retained alongside Profiles.sysml's implemented
             CR #5 profile functionality. Target deployment above is not an assertion of implemented
             radio, modem or MCP support. */
        part def StatusServer;
        dependency statusScope from StatusServer to WstxRequirements::'CL-003-01';
        dependency statusProtocol from StatusServer to WstxRequirements::'CL-003-02';
    }
}
