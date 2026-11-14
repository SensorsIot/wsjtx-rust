package WstxStationPart {
    private import ScalarValues::*;
    private import WstxAudioControl::AudioStatus;
    private import WstxProfileAccess::ProfileAccess;
    private import WstxRadioControl::RadioControl;
    private import WstxRecordingTransfer::RecordingTransfer;
    private import WstxStationCommands::StationOperations;
    private import WstxStationCommands::StationStatusPort;
    private import WstxReceiveControl::ReceiveControlPort;
    private import WstxTransmitControl::TransmitControlPort;
    private import WstxQsoControl::QsoControlPort;
    private import WstxRankingControl::RankingControlPort;
    private import WstxAutoControl::AutoControlPort;
    private import WstxLogControl::LogControlPort;
    private import WstxPeriodTiming::ClockStatusPort;
    part def StationService {
        attribute currentOperatingSelection : WstxOperatingReceive::WireSelection;
        attribute resolvedOperatingSelection : WstxOperatingReceive::Selection[0..1];
        attribute activeSelectionOperation : WstxOperatingReceive::OperationRecord[0..1];
        attribute snapshotIdentity : WstxOperatingReceive::SnapshotIdentity;
        attribute preferred160m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred160m;
        attribute preferred80m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred80m;
        attribute preferred60m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred60m;
        attribute preferred40m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred40m;
        attribute preferred30m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred30m;
        attribute preferred20m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred20m;
        attribute preferred17m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred17m;
        attribute preferred15m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred15m;
        attribute preferred12m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred12m;
        attribute preferred10m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred10m;
        attribute preferred6m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred6m;
        attribute preferred4m : WstxOperatingReceive::PreferredBandEntry = WstxOperatingReceive::preferred4m;
        attribute preferredTableSourceCommit : String = WstxOperatingReceive::preferredTableSourceCommit;
        attribute preferredTableSourcePath : String = WstxOperatingReceive::preferredTableSourcePath;
        attribute preferredTableSourceSha256 : String = WstxOperatingReceive::preferredTableSourceSha256;
        attribute minimumSelectionHz : Integer = WstxOperatingReceive::receiveSelectionMinimumHz;
        attribute maximumSelectionHz : Integer = WstxOperatingReceive::receiveSelectionMaximumHz;
        doc /* Mode, band and nominal frequency are live boot/session state, not saved
             profile fields. Preferred entries reference the canonical twelve-band table;
             they do not confer transmit permission or confirm actual radio state. */
        doc /* Own authoritative station state, operations/jobs/transitions and authorization; not HTTP/MCP parsing or device protocol syntax. One owner validates profile/source/generation and rejects obsolete results. */
        doc /* The WSJT-X UDP interface (#40, WstxUdp) is a station-owned adapter of this
             service: it observes station state and results and sends to its configured
             targets; send-only, it enters no command into the station (operator 2026-11-06)
             and owns no station state, modem or transmit authority. */
        doc /* Station-owned validation, state, jobs and operation authority. This owner
             validates uploads before handing them to its selected profile's storage. */
        port webOperations : ~StationOperations;
        port mcpOperations : ~StationOperations;
        port profile : ProfileAccess;
        port receive : ReceiveControlPort;
        port transmit : TransmitControlPort;
        port qso : QsoControlPort;
        port ranking : RankingControlPort;
        port auto : AutoControlPort;
        port log : LogControlPort;
        port udp : StationStatusPort;
        port clock : ~ClockStatusPort;
        port control : RadioControl;
        port upload : ~RecordingTransfer;
        port acceptedRecording : RecordingTransfer;
        port audioStatus : ~AudioStatus;
    }
}
