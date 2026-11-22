package WstxSupervisorPart {
    private import ScalarValues::*;
    private import WstxStationCommands::StationOperations;
    private import WstxStationCommands::AgentOperations;
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
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::DetailTests;
    private import WstxModelNotes::CodeDiffers;

    part def Supervisor {
        doc /* The one gate through which the operator's and the agents' commands enter
             the station, the holder of the operating selection,
             the start of the station, and the source from which every function learns
             what the profile says and what the other functions report. */
        @ImplementedIn {
            module = "server/src/supervisor/selection.rs; server/src/supervisor/selection_http.rs; "
                + "server/src/supervisor/receive_startup.rs; "
                + "server/src/supervisor/authorization.rs; "
                + "server/src/supervisor/authorization_http.rs";
        }
        @CodeDiffers {
            what = "Its code stands in server/src/main.rs, outside server/src/supervisor/ and "
                + "client/src/supervisor/.";
        }
        @DetailTests {
            tests = "server/src/mcp/endpoint_tests.rs; tests/mcp/mcp.test.cjs; "
                + "server/src/auth_tests.rs; server/src/supervisor/authorization_tests.rs; "
                + "server/src/supervisor/selection_http_tests.rs";
            covers = "the MCP client token: its creation, listing, hashed record, audit and "
                + "revocation, and its refusal on the browser routes; "
                + "the authorization of a browser by grant and commissioning, its routes and "
                + "its setup budget; the pacing and the size of the selection's events";
        }
        attribute records : StartupRecords {
            doc /* Its records, as the last MemorySnapshot of the profile gave them. */ }
        port webOperations : ~StationOperations {
            doc /* The operator's commands, through web. */ }
        port mcpOperations : ~AgentOperations {
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
