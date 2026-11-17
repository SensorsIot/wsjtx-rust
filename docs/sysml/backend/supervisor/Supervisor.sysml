package WstxSupervisorPart {
    private import ScalarValues::*;
    private import WstxStationCommands::StationOperations;
    private import WstxStationCommands::StartupRecords;
    private import WstxProfileAccess::ProfileAccess;
    private import WstxReceiveControl::ReceiveControlPort;
    private import WstxTransmitControl::TransmitControlPort;
    private import WstxQsoControl::QsoControlPort;
    private import WstxRankingControl::RankingControlPort;
    private import WstxAutoControl::AutoControlPort;
    private import WstxLogControl::LogControlPort;
    private import WstxHearing::SpotsControlPort;
    private import WstxHearing::TargetHearingPort;
    private import WstxUdpControl::UdpControlPort;
    private import WstxStrategies::StrategiesPort;
    private import WstxRadioControl::RadioControl;
    private import WstxAudioControl::AudioStatusPort;
    private import WstxStationTime::ClockStatusPort;
    private import WstxRecordingTransfer::RecordingTransfer;
    private import WstxWebControl::WebControlPort;
    private import ModelBindings::ImplementedIn;

    part def Supervisor {
        doc /* The one gate through which the operator's and the agents' commands enter
             the station, the holder of the operating selection,
             the start of the station, and the source from which every function learns
             what the profile says and what the other functions report. */
        @ImplementedIn {
            module = "server/src/main.rs; server/src/station/selection.rs; "
                + "server/src/selection_http.rs; server/src/receive/receive_startup.rs; "
                + "server/src/recording.rs";
        }
        attribute records : StartupRecords {
            doc /* Its records, as the last MemorySnapshot of the profile gave them. */ }
        port webOperations : ~StationOperations {
            doc /* The operator's commands, through web. */ }
        port mcpOperations : ~StationOperations {
            doc /* The agents' commands, through mcp. */ }
        port profile : ProfileAccess;
        port receive : ReceiveControlPort;
        port transmit : TransmitControlPort;
        port qso : QsoControlPort;
        port ranking : RankingControlPort;
        port auto : AutoControlPort;
        port log : LogControlPort;
        port spots : SpotsControlPort;
        port hearing : ~TargetHearingPort {
            doc /* What the station of the contact in progress hears, for the screen. */ }
        port udp : UdpControlPort;
        port strategies : StrategiesPort;
        port control : RadioControl;
        port audioStatus : ~AudioStatusPort;
        port clock : ~ClockStatusPort;
        port acceptedRecording : RecordingTransfer {
            doc /* A recording the operator imports (StationOperations::recordingChunk),
                 passed on to the profile. */ }
        port web : WebControlPort { doc /* web's context and the start of its listener. */ }
    }
}
