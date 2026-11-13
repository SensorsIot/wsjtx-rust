package WstxArchitecture {
    private import ScalarValues::*;
    private import ModelNotes::FollowsSource;
    private import WstxRadioProperties::RadioCapabilities;
    private import WstxRadioProperties::RadioResultStatus;
    private import WstxRadioProperties::RadioState;
    private import WstxRadioProperties::RadioSettings;
    private import WstxRadioProperties::RadioMeters;
    private import WstxRadioProperties::FrequencyRange;
    private import WstxRadioProperties::RadioAudioSettings;
    private import WstxRadioProperties::RadioDigitalValues;
    private import WstxRadioProperties::RadioFrontPanelValues;
    private import WstxRadioProperties::RadioKeyerSettings;
    private import WstxRadioProperties::RadioMemoryValues;
    private import WstxRadioProperties::RadioReceiverSettings;
    private import WstxRadioProperties::RadioScanningValues;
    private import WstxRadioProperties::RadioScopeSettings;
    private import WstxRadioProperties::RadioSpectrum;
    private import WstxRadioProperties::RadioToneSettings;
    private import WstxRadioProperties::RadioTransmitterSettings;
    private import WstxRadioProperties::RadioTuningValues;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    private import WstxStationLink::BrowserExchange;
    private import WstxRadioControl::RadioControl;
    private import WstxAudioControl::AudioStatus;
    private import WstxProfileAccess::ProfileAccess;
    private import WstxRecordingTransfer::RecordingTransfer;
    private import WstxStationCommands::StationOperations;
    private import WstxAudioStreams::ReceiveSamples;
    private import WstxModeProcessing::ReceiveProcessing;
    private import WstxModeProcessing::EncodeProcessing;
    private import WstxAudioStreams::AudioExchange;
    private import WstxBrowserClientPart::BrowserClient;
    private import WstxRadioControlPart::RadioAuthority;
    private import WstxAudioPart::AudioDeviceAdapter;
    private import WstxAudioPart::AudioInterface;
    private import WstxMcpPart::McpAdapter;
    private import WstxModesPart::ModeFunctions;
    private import WstxProfiles::PersistedProfile;
    private import WstxQsoPart::QsoAndLogging;
    private import WstxRadioControlPart::RadioBinding;
    private import WstxRadioControlPart::RadioControlInterface;
    private import WstxReceivePart::ReceivePipeline;
    private import WstxRadioControlPart::RustRadioDriver;
    private import WstxStationPart::StationService;
    private import WstxTransmitPart::TransmitService;
    private import WstxWebPart::WebAdapter;
    private import WstxProfileRecordings::RecordedSource;
    doc /* Product structure: one selected-radio deployment context, its frontend and backend
         containers of the product's functions, software owners and typed exchanges.
         The frontend may run locally on the backend computer or remotely over the
         station link; the logical
         roles and profile-scoped protocol remain the same. Windows x64/MSVC is the
         first desktop target; portability and later platforms follow
         WstxRequirements::ReleasePolicy, not an assertion of platform acceptance.
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
         WstxRecordingReceive, WstxOfflineDecode, WstxModemDecode, WstxRadioIO,
         WstxOperatingLayout and WstxOperatingReceive. */

    part physicalStation {
        doc /* The deployment of the product's functions: the browser client functions
             (frontend) and the server process functions (backend), with their populations
             and connections. Outside things are not parts; OutsideThing lists them. */
        part frontend : Frontend;
        part backend : Backend;
        part browserAttachments[*] : BrowserAttachment;
    }
    view physicalInterconnection : StandardViewDefinitions::InterconnectionView {
        expose physicalStation::*;
    }
    part def Frontend {
        doc /* Deployment container only; station exchanges terminate
             directly on selected contained BrowserClient instances. */
        part browsers[*] : BrowserClient;
    }
    part def Backend {
        doc /* The variable station population has no architecture-imposed numeric limit. */
        doc /* One backend role hosts variable N station processes. The common authority
             is effective shared-radio responsibility, not a per-process mutex.
             Cross-process placement/leases and actual hardware capacity are constrained
             by WstxFlexSession::NativeFlexBoundary and WstxRadioIO. Profile-scoped
             routing is not all-to-all delivery or simultaneous transmission. */
        doc /* Deployment container only; no host forwarding interfaces. Release and
             acceleration policy remain owned by WstxProductScope. */
        part stations[*] : StationProcess;
        part radioAuthority : RadioAuthority;
    }
    part def BrowserAttachment {
        doc /* One profile-scoped browser/station association carried by the physical IP
             link. This portless association selects one browser and one station, never
             the whole population. The station exchange terminates directly on the
             selected WebAdapter. */
        ref part browser : BrowserClient :> physicalStation.frontend.browsers;
        ref part station : StationProcess :> physicalStation.backend.stations;
        connection browserStation connect browser.station to station.web.client;
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
        ref part authority : RadioAuthority :> physicalStation.backend.radioAuthority;
        port authorityRequest : RadioControl;
        port authorizedControl : ~RadioControl;
        doc /* Phase 1 radio-facing parts are independent audio and CAT adapters.
             Logical driver existence does not assert connected control or ready TX.
             FR-023 native Flex runs as a per-station session behind these same audio
             and control boundaries (WstxFlexSession::NativeFlexWireSubset); it adds
             no part, combined backend or common connector to this graph. */
        part audioAdapter : AudioDeviceAdapter;
        part catAdapter : RustRadioDriver;
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
        connection contactTransmit connect qso.transmit to transmit.contacts;
        connection selectedAudio connect audio.backend to audioAdapter.host;
        connection authorityRequestDelegation connect radioControl.backend to authorityRequest;
        connection authorizedControlDelegation connect authorizedControl to catAdapter.authorized;
        connection commonAuthority connect authorityRequest to authority.requests;
        connection authorizedBackend connect authority.authorized to authorizedControl;
        binding requestContext bind authorityRequest.request.resourceContext = radioBinding;
        binding catContext bind catAdapter.authorized.request.resourceContext = radioBinding;
    }

    dependency audioPromise from AudioInterface to WstxRequirements::'FR-002';
    dependency controlPromise from RadioControlInterface to WstxRequirements::'FR-009';
    dependency profilesPromise from PersistedProfile to WstxRequirements::'FR-022';
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
    doc /* WstxOperatingReceive refines coordinated receive controls on the existing
         receive and radio authority path: single-owner release/setup/readback/restart
         and cancellation fences. It introduces no additional station/backend/physical
         connector, sample source or deployment. */
}
