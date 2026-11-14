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
    private import WstxClockPart::ClockService;
    private import WstxRankingPart::RankingService;
    private import WstxAutoPart::AutoService;
    private import WstxLogPart::LogService;
    private import WstxSpotsPart::SpotsService;
    private import WstxUdpPart::UdpService;
    private import WstxFlexAdapterPart::FlexAdapter;
    private import WstxStationLink::StationLink;
    private import WstxStationCommands::StationCommands;
    private import WstxStationCommands::StationStatus;
    private import WstxReceiveControl::ReceiveControl;
    private import WstxTransmitControl::TransmitControl;
    private import WstxQsoControl::QsoControl;
    private import WstxRankingControl::RankingControl;
    private import WstxAutoControl::AutoControl;
    private import WstxLogControl::LogControl;
    private import WstxAudioControl::AudioControl;
    private import WstxRadioControl::StationRadioControl;
    private import WstxKeying::KeyingLink;
    private import WstxAudioStreams::AudioExchangeLink;
    private import WstxAudioStreams::CaptureSamplesLink;
    private import WstxAudioStreams::ReceiveSamplesLink;
    private import WstxModeProcessing::ReceiveProcessingLink;
    private import WstxModeProcessing::EncodeProcessingLink;
    private import WstxProfileAccess::ProfileAccessLink;
    private import WstxRecordingTransfer::RecordingTransferLink;
    private import WstxDecodes::Decodes;
    private import WstxDisplayData::DisplayData;
    private import WstxHearing::Hearing;
    private import WstxPeriodTiming::PeriodTiming;
    private import WstxPeriodTiming::ClockStatus;
    private import WstxOperatingChain::RankedActivity;
    private import WstxOperatingChain::TargetChoice;
    private import WstxOperatingChain::MessageToSend;
    private import WstxOperatingChain::CompletedContact;
    private import WstxOperatingChain::WorkedBefore;
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

    part def Station {
        doc /* The deployment of the product's functions: the browser client functions
             (frontend) and the server process functions (backend), with their populations
             and connections. Outside things are not parts; OutsideThing lists them. */
        part frontend : Frontend;
        part backend : Backend;
        part browserAttachments[*] : BrowserAttachment {
            ref part :>> browser : BrowserClient :> frontend.browsers;
            ref part :>> station : StationProcess :> backend.stations;
        }
        satisfy WstxRequirements::'FR-021' by browserAttachments;
    }
    part def Frontend {
        doc /* Deployment container only; station exchanges terminate
             directly on selected contained BrowserClient instances. */
        part browsers[*] : BrowserClient;
        satisfy WstxRequirements::'FR-010' by browsers;
        satisfy WstxRequirements::'FR-017' by browsers;
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
        part stations[*] : StationProcess {
            ref part :>> authority : RadioAuthority :> radioAuthority;
        }
        part radioAuthority : RadioAuthority;
    }
    part def BrowserAttachment {
        doc /* One profile-scoped browser/station association carried by the physical IP
             link. This portless association selects one browser and one station, never
             the whole population. The station exchange terminates directly on the
             selected WebAdapter. */
        ref part browser : BrowserClient;
        ref part station : StationProcess;
        interface browserStation : StationLink connect browser.station to station.web.client;
    }
    part def StationProcess {
        part profile : PersistedProfile;
        part station : StationService;
        part web : WebAdapter;
        part mcp : McpAdapter;
        part receive : ReceivePipeline;
        part modes : ModeFunctions;
        part clock : ClockService;
        part audio : AudioInterface;
        part radioControl : RadioControlInterface;
        part transmit : TransmitService;
        part ranking : RankingService;
        part auto : AutoService;
        part qso : QsoAndLogging;
        part log : LogService;
        part spots : SpotsService;
        part udp : UdpService;
        part radioBinding : RadioBinding;
        part flexAdapter[0..1] : FlexAdapter;
        ref part authority : RadioAuthority;
        port authorityRequest : RadioControl;
        port authorizedControl : ~RadioControl;
        doc /* Phase 1 radio-facing parts are independent audio and CAT adapters.
             Logical driver existence does not assert connected control or ready TX.
             FR-023 native Flex runs as a per-station session behind these same audio
             and control boundaries (WstxFlexSession::NativeFlexWireSubset); it adds
             no part, combined backend or common connector to this graph. */
        part audioAdapter : AudioDeviceAdapter;
        part catAdapter : RustRadioDriver;
        interface webOperations : StationCommands connect web.station to station.webOperations;
        interface mcpOperations : StationCommands connect mcp.station to station.mcpOperations;
        interface profileContext : ProfileAccessLink connect station.profile to profile.context;
        interface receiveJobs : ReceiveControl connect station.receive to receive.jobs;
        interface transmitOperations : TransmitControl
            connect station.transmit to transmit.operations;
        interface qsoOperations : QsoControl connect station.qso to qso.operations;
        interface stationControl : StationRadioControl
            connect station.control to radioControl.station;
        interface receiveSamples : ReceiveSamplesLink connect audio.receive to receive.audio;
        interface audioAvailability : AudioControl connect station.audioStatus to audio.status;
        interface receiveModem : ReceiveProcessingLink connect receive.processing to modes.receive;
        interface encodeModem : EncodeProcessingLink connect transmit.encode to modes.encode;
        interface transmitAudio : AudioExchangeLink connect transmit.audio to audio.transmit;
        interface transmitControl : KeyingLink connect transmit.control to radioControl.transmit;
        interface uploadedRecording : RecordingTransferLink
            connect web.recording to station.upload;
        interface validatedRecording : RecordingTransferLink
            connect station.acceptedRecording to profile.upload;
        interface recordedInput : ReceiveSamplesLink
            connect profile.recordedSamples to audio.recorded;
        interface contactStorage : ProfileAccessLink connect log.contacts to profile.contacts;
        interface contactTransmit : MessageToSend connect qso.transmit to transmit.contacts;
        interface selectedAudio : AudioExchangeLink connect audio.backend to audioAdapter.host;
        interface stationRanking : RankingControl connect station.ranking to ranking.control;
        interface stationAuto : AutoControl connect station.auto to auto.control;
        interface stationLog : LogControl connect station.log to log.control;
        interface stationStatus : StationStatus connect station.udp to udp.status;
        interface clockStatus : ClockStatus connect clock.status to station.clock;
        interface decodesRanking : Decodes connect receive.decodes to ranking.decodes;
        interface decodesQso : Decodes connect receive.decodes to qso.decodes;
        interface decodesClock : Decodes connect receive.decodes to clock.decodes;
        interface decodesUdp : Decodes connect receive.decodes to udp.decodes;
        interface displayWeb : DisplayData connect receive.display to web.display;
        interface displayAuto : DisplayData connect receive.display to auto.display;
        interface timingReceive : PeriodTiming connect clock.timing to receive.timing;
        interface timingTransmit : PeriodTiming connect clock.timing to transmit.timing;
        interface timingQso : PeriodTiming connect clock.timing to qso.timing;
        interface rankedActivity : RankedActivity connect ranking.ranked to auto.ranked;
        interface targetChoice : TargetChoice connect auto.target to qso.target;
        interface completedContact : CompletedContact connect qso.completed to log.completed;
        interface loggedContact : CompletedContact connect log.logged to udp.logged;
        interface workedBefore : WorkedBefore connect log.workedBefore to ranking.workedBefore;
        interface hearingRanking : Hearing connect spots.hearing to ranking.hearing;
        interface hearingAuto : Hearing connect spots.hearing to auto.hearing;
        interface hearingQso : Hearing connect spots.hearing to qso.hearing;
        interface nativeSamples : CaptureSamplesLink connect audio.backend to flexAdapter.samples;
        connection nativeControl connect radioControl.backend to flexAdapter.control;
        connection authorityRequestDelegation connect radioControl.backend to authorityRequest;
        connection authorizedControlDelegation connect authorizedControl to catAdapter.authorized;
        connection commonAuthority connect authorityRequest to authority.requests;
        connection authorizedBackend connect authority.authorized to authorizedControl;
        binding requestContext bind authorityRequest.request.resourceContext = radioBinding;
        binding catContext bind catAdapter.authorized.request.resourceContext = radioBinding;
        binding flexContext bind flexAdapter.control.request.resourceContext = radioBinding;
        satisfy WstxRequirements::'FR-001' by station;
        satisfy WstxRequirements::'FR-002' by audio;
        satisfy WstxRequirements::'FR-003' by receive;
        satisfy WstxRequirements::'FR-004' by modes;
        satisfy WstxRequirements::'FR-005' by modes;
        satisfy WstxRequirements::'FR-006' by transmit;
        satisfy WstxRequirements::'FR-006' by receive;
        satisfy WstxRequirements::'FR-007' by qso;
        satisfy WstxRequirements::'FR-008' by transmit;
        satisfy WstxRequirements::'FR-009' by radioControl;
        satisfy WstxRequirements::'FR-011' by qso;
        satisfy WstxRequirements::'FR-012' by station;
        satisfy WstxRequirements::'FR-013' by modes;
        satisfy WstxRequirements::'FR-014' by receive;
        satisfy WstxRequirements::'FR-015' by modes;
        satisfy WstxRequirements::'FR-016' by profile;
        satisfy WstxRequirements::'FR-018' by profile.recordings;
        satisfy WstxRequirements::'FR-019' by web;
        satisfy WstxRequirements::'FR-020' by mcp;
        satisfy WstxRequirements::'FR-022' by profile;
        satisfy WstxRequirements::'FR-025' by auto;
        satisfy WstxRequirements::'FR-026' by ranking;
        satisfy WstxRequirements::'FR-026' by station;
    }

    doc /* Responsibility traces identify the owning boundary for an existing requirement,
         not delivered capability or an executed verification. */
    doc /* WstxOperatingReceive refines coordinated receive controls on the existing
         receive and radio authority path: single-owner release/setup/readback/restart
         and cancellation fences. It introduces no additional station/backend/physical
         connector, sample source or deployment. */
}
