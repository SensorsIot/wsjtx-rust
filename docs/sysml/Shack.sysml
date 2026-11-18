package WstxShack {
    private import ScalarValues::*;
    private import WstxRequirements::*;
    private import WstxBrowserClientPart::BrowserClient;
    private import WstxSupervisorPart::Supervisor;
    private import WstxWebPart::WebAdapter;
    private import WstxMcpPart::McpAdapter;
    private import WstxProfilePart::PersistedProfile;
    private import WstxReceivePart::ReceiveService;
    private import WstxModesPart::ModeFunctions;
    private import WstxClockPart::ClockService;
    private import WstxTransmitPart::TransmitService;
    private import WstxOperatingPart::OperatingService;
    private import WstxRankingPart::RankingService;
    private import WstxAutoPart::AutoService;
    private import WstxQsoPart::QsoService;
    private import WstxLogPart::LogService;
    private import WstxSpotsPart::SpotsService;
    private import WstxUdpPart::UdpService;
    private import WstxAudioPart::AudioInterface;
    private import WstxAudioPart::AudioDeviceAdapter;
    private import WstxRadioControlPart::RadioControlInterface;
    private import WstxRadioControlPart::CatAdapter;
    private import WstxFlexAdapterPart::FlexAdapter;
    private import WstxStationLink::StationLink;
    private import WstxStationCommands::StationCommands;
    private import WstxStationCommands::AgentCommands;
    private import WstxUdpControl::UdpControl;
    private import WstxWebControl::WebControl;
    private import WstxProfileAccess::ProfileAccessLink;
    private import WstxRecordingTransfer::RecordingTransferLink;
    private import WstxRecordingTransfer::RecordedSamplesLink;
    private import WstxReceiveControl::ReceiveControl;
    private import WstxTransmitControl::TransmitControl;
    private import WstxQsoControl::QsoControl;
    private import WstxRankingControl::RankingControl;
    private import WstxAutoControl::AutoControl;
    private import WstxLogControl::LogControl;
    private import WstxAudioControl::AudioControl;
    private import WstxRadioControl::StationRadioControl;
    private import WstxRadioControl::RadioAccessLink;
    private import WstxRadioControl::NativeControl;
    private import WstxKeying::KeyingLink;
    private import WstxAudioStreams::AudioExchangeLink;
    private import WstxAudioStreams::CaptureSamplesLink;
    private import WstxAudioStreams::ReceiveSamplesLink;
    private import WstxAudioStreams::PlaybackLink;
    private import WstxModeProcessing::ReceiveProcessingLink;
    private import WstxModeProcessing::EncodeProcessingLink;
    private import WstxModeProcessing::PackProcessingLink;
    private import WstxDecodes::Decodes;
    private import WstxDisplayData::DisplayData;
    private import WstxHearing::HeardByLink;
    private import WstxHearing::TargetHearingLink;
    private import WstxStrategies::StrategiesControl;
    private import WstxStrategies::RankingShare;
    private import WstxStrategies::AutoShare;
    private import WstxStrategies::ActivityShare;
    private import WstxHearing::SpotsControl;
    private import WstxStationTime::StationTimeLink;
    private import WstxStationTime::ClockStatus;
    private import WstxStationTime::StationsHeard;
    private import WstxOperatingChain::RankedActivity;
    private import WstxOperatingChain::TargetChoice;
    private import WstxOperatingChain::MessageToSend;
    private import WstxOperatingChain::CompletedContact;
    private import WstxOperatingChain::LoggedContactLink;
    private import WstxOperatingChain::WorkedBefore;

    doc /* The shack and its stations: their parts, how they are joined, and which part
         carries which functional requirement. */

    part def Shack {
        doc /* The setup on one PC: one operator and the stations, each with its own profile. What
             the stations share stands in the shack's folder
             (WstxProfileDocument::ShackFolder). */
        part stations[*] : Station;
    }

    part def Station {
        doc /* The program that operates one radio, or one slice of a FlexRadio, with its
             UI: one profile. */
        part frontend : Frontend;
        part backend : Backend;
        interface browserStation : StationLink
            connect frontend.browsers.station to backend.web.client;
    }

    part def Frontend {
        doc /* The station's browser clients. One exists per open browser window. */
        part browsers[*] : BrowserClient;

        satisfy 'FR-010' by browsers;
        satisfy 'FR-017' by browsers;
        satisfy 'FR-019' by browsers;
    }

    part def Backend {
        doc /* The station's process: its functions and their connections. */

        part supervisor : Supervisor;
        part web : WebAdapter;
        part mcp : McpAdapter;
        part profile : PersistedProfile;
        part receive : ReceiveService;
        part modes : ModeFunctions;
        part clock : ClockService;
        part transmit : TransmitService;
        part operating : OperatingService {
            part ranking : RankingService;
            part auto : AutoService;
            part qso : QsoService;
        }
        part log : LogService;
        part spots : SpotsService;
        part udp : UdpService;
        part audio : AudioInterface;
        part radioControl : RadioControlInterface;
        part flexAdapter[0..1] : FlexAdapter {
            doc /* Present on a profile that uses a FlexRadio through its native API. */
        }

        part audioAdapter : AudioDeviceAdapter;
        part catAdapter : CatAdapter;

        interface webOperations : StationCommands
            connect web.supervisor to supervisor.webOperations;
        interface mcpOperations : AgentCommands
            connect mcp.supervisor to supervisor.mcpOperations;
        interface profileContext : ProfileAccessLink connect supervisor.profile to profile.context;
        interface receiveJobs : ReceiveControl connect supervisor.receive to receive.jobs;
        interface transmitOperations : TransmitControl
            connect supervisor.transmit to transmit.operations;
        interface qsoOperations : QsoControl connect supervisor.qso to operating.qso.operations;
        interface supervisorRanking : RankingControl
            connect supervisor.ranking to operating.ranking.control;
        interface supervisorAuto : AutoControl connect supervisor.auto to operating.auto.control;
        interface supervisorLog : LogControl connect supervisor.log to log.control;
        interface supervisorRadioControl : StationRadioControl
            connect supervisor.control to radioControl.supervisor;
        interface audioAvailability : AudioControl connect supervisor.audioStatus to audio.status;
        interface udpControl : UdpControl connect supervisor.udp to udp.control;
        interface webControl : WebControl connect supervisor.web to web.control;
        interface supervisorSpots : SpotsControl connect supervisor.spots to spots.control;
        interface clockStatus : ClockStatus connect clock.status to supervisor.clock;

        interface timeReceive : StationTimeLink connect clock.time to receive.time;
        interface timeTransmit : StationTimeLink connect clock.time to transmit.time;
        interface timeQso : StationTimeLink connect clock.time to operating.qso.time;
        interface timeOperating : StationTimeLink connect clock.time to operating.time;
        interface timeAudio : StationTimeLink connect clock.time to audio.time;
        interface timeWeb : StationTimeLink connect clock.time to web.time;
        interface stationsHeard : StationsHeard connect receive.heard to clock.heard;

        interface selectedAudio : AudioExchangeLink connect audio.device to audioAdapter.host;
        interface nativeSamples : CaptureSamplesLink connect audio.native to flexAdapter.samples;
        interface receiveSamples : ReceiveSamplesLink connect audio.receive to receive.audio;
        interface recordedInput : RecordedSamplesLink
            connect profile.recordedSamples to receive.recorded;
        interface transmitAudio : PlaybackLink connect transmit.audio to audio.transmit;
        interface receiveModem : ReceiveProcessingLink connect receive.processing to modes.receive;
        interface encodeModem : EncodeProcessingLink connect transmit.encode to modes.encode;
        interface packQso : PackProcessingLink connect operating.qso.pack to modes.pack;

        interface decodesRanking : Decodes connect receive.decodes to operating.ranking.decodes;
        interface decodesAuto : Decodes connect receive.decodes to operating.auto.decodes;
        interface decodesQso : Decodes connect receive.decodes to operating.qso.decodes;
        interface decodesUdp : Decodes connect receive.decodes to udp.decodes;
        interface decodesSpots : Decodes connect receive.decodes to spots.decodes;
        interface decodesLog : Decodes connect receive.decodes to log.decodes;
        interface displayWeb : DisplayData connect receive.display to web.display;
        interface displayQso : DisplayData connect receive.display to operating.qso.display;

        interface supervisorStrategies : StrategiesControl
            connect supervisor.strategies to operating.control;
        interface rankingRules : RankingShare
            connect operating.rankingShare to operating.ranking.rules;
        interface autoRules : AutoShare connect operating.autoShare to operating.auto.rules;
        interface contestActivity : ActivityShare
            connect operating.activityShare to operating.qso.activity;

        interface rankedActivity : RankedActivity
            connect operating.ranking.ranked to operating.auto.ranked;
        interface targetChoice : TargetChoice connect operating.auto.target to operating.qso.target;
        interface contactTransmit : MessageToSend
            connect operating.qso.transmit to transmit.contacts;
        interface completedContact : CompletedContact
            connect operating.qso.completed to log.completed;
        interface loggedContact : LoggedContactLink connect log.logged to udp.logged;
        interface workedBefore : WorkedBefore
            connect log.workedBefore to operating.ranking.workedBefore;
        interface heardByRanking : HeardByLink connect spots.heardBy to operating.ranking.hearing;
        interface targetHearingAuto : TargetHearingLink
            connect spots.target to operating.auto.hearing;
        interface targetHearingQso : TargetHearingLink
            connect spots.target to operating.qso.hearing;
        interface targetHearingSupervisor : TargetHearingLink
            connect spots.target to supervisor.hearing;

        interface validatedRecording : RecordingTransferLink
            connect supervisor.acceptedRecording to profile.upload;

        interface transmitControl : KeyingLink connect transmit.control to radioControl.transmit;
        interface nativeControl : NativeControl
            connect radioControl.native to flexAdapter.control;
        interface serialAccess : RadioAccessLink
            connect radioControl.backend to catAdapter.serial;

        satisfy 'FR-001' by profile;
        satisfy 'FR-001' by supervisor;
        satisfy 'FR-002' by audio;
        satisfy 'FR-003' by receive;
        satisfy 'FR-004' by modes;
        satisfy 'FR-005' by modes;
        satisfy 'FR-006' by clock;
        satisfy 'FR-006' by transmit;
        satisfy 'FR-006' by receive;
        satisfy 'FR-007' by operating.qso;
        satisfy 'FR-008' by transmit;
        satisfy 'FR-009' by radioControl;
        satisfy 'FR-011' by log;
        satisfy 'FR-012' by udp;
        satisfy 'FR-012' by spots;
        satisfy 'FR-016' by profile;
        satisfy 'FR-018' by profile;
        satisfy 'FR-020' by mcp;
        satisfy 'FR-021' by web;
        satisfy 'FR-021' by supervisor;
        satisfy 'FR-022' by profile;
        satisfy 'FR-023' by flexAdapter;
        satisfy 'FR-024' by operating.qso;
        satisfy 'FR-025' by operating.auto;
        satisfy 'FR-026' by operating;
        satisfy 'FR-026' by operating.ranking;
        satisfy 'FR-027' by spots;
    }
}
