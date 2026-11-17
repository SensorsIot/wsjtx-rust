package WstxStationCommands {
    private import ScalarValues::*;
    private import WstxModeProcessing::Mode;
    private import WstxReceiveControl::ReceiveMode;
    private import WstxRadioControl::DetectionReport;

    doc /* The supervisor's control interface: the commands the operator (through web)
         and an agent (through mcp) give the station, the same for both, the answers, and
         the supervisor's own state and records. */

    enum def Requester {
        doc /* Who gave a command. operator: through the browser. agent: through MCP. */
        enum operator;
        enum agent;
    }
    item def StationRequest {
        doc /* A command for the station: one of the supervisor's own commands below,
             or a command of a function's control interface that the supervisor
             passes on (WstxStationAuthority::GateRule). */
        attribute profileId : String { doc /* The profile of the station it is meant for. */ }
        attribute bootId : String {
            doc /* The start of the station process it was made in. */ }
        attribute commandId : String {
            doc /* Names the command: a UUID of version 4 in lower case, chosen by the
                 requester (WstxStationAuthority::ReceiptRule). */ }
        attribute requester : Requester;
    }
    item def StationOutcome {
        doc /* The answer to one StationRequest: the answer of the function the command was
             passed to, the answer of the supervisor to one of its own commands, or
             StationRefused. */
    }
    enum def StationRefusal {
        doc /* Why the supervisor refuses a command before it reaches a function.
             wrong_profile: the command names another profile.
             state_conflict: it names another start of the station process, or a profile
             revision the station has left.
             swr_fault: an agent's start, Tune or Auto on while the SWR barrier holds
             (WstxStationAuthority::SwrBarrier).
             auto_on: a command for the contact while Auto is on
             (WstxStationAuthority::AutoOnRule).
             audio_unconfigured: a live start on a profile without an input device.
             radio_unavailable: a live start on a profile of a radio's native connection
             whose session is not ready. */
        enum wrong_profile;
        enum state_conflict;
        enum swr_fault;
        enum auto_on;
        enum audio_unconfigured;
        enum radio_unavailable;
    }
    item def StationRefused :> StationOutcome {
        doc /* A command refused by the supervisor. Nothing has changed. */
        attribute reason : StationRefusal;
    }

    enum def EndpointMatch {
        doc /* How many sound endpoints of one direction audio lists at a radio's place.
             one: exactly one. none: none. ambiguous: more than one. */
        enum one;
        enum 'none';
        enum ambiguous;
    }
    attribute def ProposedEndpoint {
        attribute match : EndpointMatch;
        attribute endpointId : String[0..1] { doc /* With one. */ }
        attribute name : String[0..1] { doc /* With one: its name as audio lists it. */ }
        attribute count : Integer[0..1] { doc /* With ambiguous. */ }
    }
    item def RadioDetection :> StationOutcome {
        doc /* The answer to a DetectRadios: radio control's report and, when it proposes
             a radio, the input and output endpoint audio lists at the radio's place
             (WstxStationAuthority::GateRule). */
        item report : DetectionReport;
        attribute input : ProposedEndpoint[0..1];
        attribute output : ProposedEndpoint[0..1];
    }

    enum def OperatingBand {
        doc /* The bands the station operates on, in this order. */
        enum '160m';
        enum '80m';
        enum '60m';
        enum '40m';
        enum '30m';
        enum '20m';
        enum '17m';
        enum '15m';
        enum '12m';
        enum '10m';
        enum '6m';
        enum '4m';
    }
    enum def NominalOrigin {
        doc /* Where the dial frequency of the selection comes from.
             unknown: there is none.
             manual: a selection without radio control; the dial is not known to be there.
             cat_readback: radio control set it and read it back, or read it
             (WstxOperatingSelection::ReadbackRule).
             native_readback: the radio's native session tuned to it and confirmed it. */
        enum unknown;
        enum manual;
        enum cat_readback;
        enum native_readback;
    }
    attribute def OperatingSelection {
        doc /* The mode, band and dial frequency the station operates on. Band and dial
             frequency are both absent or both present. */
        attribute mode : Mode;
        attribute band : OperatingBand[0..1];
        attribute nominalHz : Integer[0..1] { doc /* The dial frequency. */ }
        attribute origin : NominalOrigin;
        attribute confirmedCommandId : String[0..1] {
            doc /* The selection that set it; absent for unknown and for a dial read. */ }
    }
    item def SelectionRequest :> StationRequest {
        doc /* A change of the operating mode or band. It names the state it was made from
             (WstxOperatingSelection::SelectionRule). */
        attribute profileRevision : Integer;
        attribute operatingRevision : Integer;
    }
    item def SelectMode :> SelectionRequest { attribute mode : Mode; }
    item def SelectBand :> SelectionRequest {
        attribute band : OperatingBand;
        attribute nominalHz : Integer[0..1] {
            doc /* A working frequency of the mode on the band; absent: the first
                 (WstxOperatingSelection::BandFrequency). */ }
    }
    attribute def WorkingFrequency {
        doc /* A dial frequency the band selector offers. */
        attribute mode : Mode;
        attribute band : OperatingBand;
        attribute nominalHz : Integer {
            doc /* Within the band's limits as ADIF gives them. A mode, band and frequency
                 stand once in the list. */ }
    }
    attribute def WorkingFrequencies {
        doc /* The supervisor's part of the shack's settings
             (WstxProfileAccess::ShackSettings). */
        attribute entries : WorkingFrequency[0..200] ordered {
            doc /* At first, and after ResetFrequencies, WSJT-X's default list
                 (WstxOperatingSelection::BandFrequency). */ }
    }
    item def CancelSelection :> StationRequest {
        doc /* End a selection, or keep one from being carried out
             (WstxOperatingSelection::CancelRule). */
        attribute operatingRevision : Integer;
        attribute targetCommandId : String;
    }
    enum def SelectionPhase {
        doc /* Where a selection stands.
             releasing: receive gives up its live job.
             applying: the radio is set.
             restarting: the selection is set and receive starts again.
             applied: done.
             failed: it ended with an error.
             release_blocked: receive did not give up its job.
             cancelled: it was cancelled. */
        enum releasing;
        enum applying;
        enum restarting;
        enum applied;
        enum failed;
        enum release_blocked;
        enum cancelled;
    }
    enum def SelectionResult {
        enum pending;
        enum success;
        enum failed;
        enum cancelled;
    }
    enum def SelectionError {
        doc /* Why a selection is refused, or ended without success.
             select_band_first: a mode with no band known.
             selection_unavailable: the band has no frequency for the mode, or radio
             control has no such operation for this radio.
             busy: another selection, an import or a replay has not ended; a mode while
             the transmitter is keyed, plays or tunes; radio control kept by another
             exchange.
             radio_unavailable: the radio connection is not ready, the radio transmits,
             or the native session is not ready.
             counter_exhausted: the operating revision has reached its end.
             operation_superseded: a later selection or cancel has come after the one a
             cancel names.
             state_conflict: the profile was saved while the selection ran.
             release_failed: receive did not give up its job.
             audio_unconfigured: the profile names no input device.
             audio_unavailable: receive could not start again.
             cancelled, radio_timeout, radio_rejected, readback_mismatch,
             radio_failed_close, invalid_request: radio control's error
             (WstxOperatingSelection::SelectionRule). */
        enum select_band_first;
        enum selection_unavailable;
        enum busy;
        enum radio_unavailable;
        enum counter_exhausted;
        enum operation_superseded;
        enum state_conflict;
        enum release_failed;
        enum audio_unconfigured;
        enum audio_unavailable;
        enum cancelled;
        enum radio_timeout;
        enum radio_rejected;
        enum readback_mismatch;
        enum radio_failed_close;
        enum invalid_request;
    }
    attribute def RequestedSelection {
        attribute mode : Mode;
        attribute band : OperatingBand;
        attribute nominalHz : Integer;
    }
    attribute def SelectionOperation {
        doc /* The latest selection admitted since station start. */
        attribute commandId : String;
        attribute baseRevision : Integer {
            doc /* The operating revision it was made from. */ }
        attribute revision : Integer { doc /* The operating revision it was admitted at. */ }
        attribute requested : RequestedSelection;
        attribute phase : SelectionPhase;
        attribute result : SelectionResult;
        attribute error : SelectionError[0..1];
        attribute monitorBefore : Boolean {
            doc /* A live job of receive ran when it was admitted. */ }
        attribute monitorWanted : Boolean {
            doc /* Receive is to run when it ends; false once it failed or was
                 cancelled. */ }
        attribute oldJobId : String[0..1];
        attribute newJobId : String[0..1];
    }
    enum def CancelResult {
        enum cancelled;
        enum fenced;
        enum already_cancelled;
    }
    attribute def SelectionCancellation {
        doc /* The latest cancel accepted since station start. */
        attribute commandId : String;
        attribute targetCommandId : String;
        attribute revision : Integer;
        attribute result : CancelResult;
    }
    item def CheckSettings :> StationRequest {
        doc /* Check the station's settings (WstxSettingsCheck::CheckRule). */
        attribute withTune : Boolean = false {
            doc /* The operator has agreed that the check keys the radio for a Tune
                 tone. */ }
    }
    enum def CheckArea {
        doc /* The areas of the settings check, in the order of the settings drawer. */
        enum station;
        enum radio;
        enum power;
        enum audio;
        enum clock;
        enum operating;
        enum files;
        enum destinations;
    }
    enum def CheckOutcome {
        enum passed;
        enum failed;
        enum skipped;
    }
    attribute def CheckLine {
        doc /* One check of the settings check. */
        attribute area : CheckArea;
        attribute checked : String { doc /* What was checked, as the settings name it. */ }
        attribute outcome : CheckOutcome;
        attribute reason : String[0..1] {
            doc /* Present for failed and skipped: why, and where to change it. */ }
    }
    item def SettingsCheckReport {
        doc /* The latest settings check, given after each line and at its end. */
        attribute commandId : String { doc /* The CheckSettings it answers. */ }
        attribute running : Boolean;
        attribute lines : CheckLine[0..*] ordered;
        attribute ready : Boolean[0..1] {
            doc /* At the end: true when no line failed. */ }
    }
    enum def CheckError {
        doc /* busy: a contact is in progress, the transmitter is not at rest, a
             selection is pending or a check runs. */
        enum busy;
    }
    item def CheckRefused :> StationOutcome {
        doc /* A settings check that was not started. */
        attribute error : CheckError;
    }
    item def SelectionAdmitted :> StationOutcome {
        doc /* The answer to an admitted SelectMode or SelectBand, and to an accepted
             CancelSelection (phase cancelled). */
        attribute commandId : String;
        attribute operatingRevision : Integer;
        attribute phase : SelectionPhase;
    }
    item def SelectionRefused :> StationOutcome {
        doc /* A selection or a cancel that was not admitted. Nothing has changed. */
        attribute error : SelectionError;
    }
    item def SelectionState {
        doc /* The selection as the supervisor holds it, given at every change. */
        attribute profileRevision : Integer;
        attribute operatingRevision : Integer {
            doc /* Counts the admitted selections and accepted cancels since station start,
                 from 0. */ }
        attribute selection : OperatingSelection;
        attribute availableBands : OperatingBand[0..*] ordered {
            doc /* The bands with a frequency for the mode of the selection. */ }
        attribute operation : SelectionOperation[0..1];
        attribute cancellation : SelectionCancellation[0..1];
    }

    attribute def ReceiveChoice {
        doc /* A receive the station started. */
        attribute mode : ReceiveMode;
        attribute band : OperatingBand[0..1];
        attribute inputDevice : String { doc /* The input device it was started on. */ }
    }
    attribute def StartupRecords {
        doc /* What the supervisor wants kept across the sessions of the station.
             No menu shows a record. */
        attribute lastReceive : ReceiveChoice[0..1] {
            doc /* The receive to resume at the next start (WstxStartup::ResumeRule). */ }
    }
    enum def ResumeState {
        doc /* Where the resume of receive at station start stands.
             idle: there is nothing to resume.
             waiting: it waits for the radio.
             started: receive runs on the remembered band and mode.
             started_untuned: receive runs in the remembered mode on the radio's present
             dial.
             skipped: receive was started by a command before the resume.
             failed: receive could not be started. */
        enum idle;
        enum waiting;
        enum started;
        enum started_untuned;
        enum skipped;
        enum failed;
    }
    item def StartupState {
        doc /* The resume of this start, given at every change. */
        attribute 'state' : ResumeState;
        attribute error : String[0..1] {
            doc /* With failed: the error of receive or audio_unconfigured. */ }
        attribute lastReceive : ReceiveChoice[0..1];
    }

    port def StationOperations {
        doc /* The station boundary: every command the operator and agents give the
             station, every read, every answer and every view the station gives back,
             each typed by the item of the function it belongs to. Web and mcp give the
             same features (WstxStationLink::WireRule). Written from the requester's
             side; the supervisor uses the conjugate. */
        out abstract item commands[0..*] {
            doc /* A command: it comes with a StationRequest, may change the station, and
                 is answered by its function's answer or by StationRefused. */ }
        out abstract item reads[0..*] {
            doc /* A read: it comes with a StationRequest, changes nothing, and is answered
                 by the view it asks for. */ }
        in abstract item answers[0..*] { doc /* The answer to one command or read. */ }
        in abstract item views[0..*] {
            doc /* A view of the station's state, given at station start and whenever a
                 value changes. */ }

        out item selectMode : SelectMode :> commands;
        out item selectBand : SelectBand :> commands;
        out item cancelSelection : CancelSelection :> commands;
        out item checkSettings : CheckSettings :> commands;
        out item selectRow : WstxQsoControl::SelectRow :> commands;
        out item enterDx : WstxQsoControl::EnterDx :> commands;
        out item reply : WstxQsoControl::Reply :> commands;
        out item callCq : WstxQsoControl::CallCq :> commands;
        out item callDx : WstxQsoControl::CallDx :> commands;
        out item sendNext : WstxQsoControl::SendNext :> commands;
        out item resetRepetitions : WstxQsoControl::ResetRepetitions :> commands;
        out item cancelContact : WstxQsoControl::CancelContact :> commands;
        out item haltQso : WstxQsoControl::HaltQso :> commands;
        out item chooseNext : WstxQsoControl::ChooseNext :> commands;
        out item editMessage : WstxQsoControl::EditMessage :> commands;
        out item setReport : WstxQsoControl::SetReport :> commands;
        out item setTx1Skip : WstxQsoControl::SetTx1Skip :> commands;
        out item setTx4 : WstxQsoControl::SetTx4 :> commands;
        out item setFrequency : WstxQsoControl::SetFrequency :> commands;
        out item setHoldTx : WstxQsoControl::SetHoldTx :> commands;
        out item setParity : WstxQsoControl::SetParity :> commands;
        out item tune : WstxQsoControl::Tune :> commands;
        out item confirmLog : WstxQsoControl::ConfirmLog :> commands;
        out item discardLog : WstxQsoControl::DiscardLog :> commands;
        out item switchAuto : WstxAutoControl::SwitchAuto :> commands;
        out item evaluate : WstxRankingControl::EvaluateRequest :> commands;
        out item ignore : WstxRankingControl::IgnoreCommand :> commands;
        out item clearIgnore : WstxRankingControl::ClearIgnoreList :> commands;
        out item clearAlerts : WstxRankingControl::ClearAlerts :> commands;
        out item selectStrategy : WstxStrategies::SelectStrategy :> commands;
        out item startLive : WstxReceiveControl::StartLive :> commands;
        out item stopLive : WstxReceiveControl::StopLive :> commands;
        out item startReplay : WstxReceiveControl::StartReplay :> commands;
        out item cancelJob : WstxReceiveControl::CancelJob :> commands;
        out item halt : WstxTransmitControl::Halt :> commands;
        out item saveRecord : WstxLogControl::SaveRecord :> commands;
        out item reserveImport : WstxLogControl::ReserveImport :> commands;
        out item importChunk : WstxLogControl::ImportChunk :> commands;
        out item resendLast : WstxLogControl::ResendLast :> commands;
        out item exportCabrillo : WstxLogControl::ExportCabrillo :> commands;
        out item detectRadios : WstxRadioControl::DetectRadios :> commands;
        out item applyRecommended : WstxRadioControl::ApplyRecommended :> commands;
        out item saveConfig : WstxProfileAccess::SaveProfile :> commands;
        out item saveShack : WstxProfileAccess::SaveShack :> commands;
        out item createEntry : WstxProfileAccess::CreateEntry :> commands;
        out item updateEntry : WstxProfileAccess::UpdateEntry :> commands;
        out item deleteEntry : WstxProfileAccess::DeleteEntry :> commands;
        out item resetFrequencies : WstxProfileAccess::ResetFrequencies :> commands;
        out item updateMostWanted : WstxProfileAccess::UpdateMostWanted :> commands;
        out item updateCountryFile : WstxProfileAccess::UpdateCountryFile :> commands;
        out item reserveRecording : WstxRecordingTransfer::ReserveImport :> commands;
        out item recordingChunk : WstxRecordingTransfer::ImportChunk :> commands;
        out item cancelRecording : WstxRecordingTransfer::CancelImport :> commands;

        out item records : WstxReceiveControl::ReadRecords :> reads;
        out item diagnostics : WstxReceiveControl::ReadDiagnostics :> reads;
        out item history : WstxLogControl::ReadHistory :> reads;
        out item logImport : WstxLogControl::ReadImport :> reads;
        out item export : WstxLogControl::ExportLog :> reads;
        out item countryFile : WstxLogControl::ReadCountryFile :> reads;
        out item ranking : WstxRankingControl::ReadRankingState :> reads;
        out item operating : WstxStrategies::ReadStrategies :> reads;
        out item contests : WstxStrategies::ReadContests :> reads;
        out item endpoints : WstxAudioControl::ListEndpoints :> reads;
        out item recordingImport : WstxRecordingTransfer::ReadImport :> reads;

        in item stationRefused : StationRefused :> answers;
        in item selectionAdmitted : SelectionAdmitted :> answers;
        in item selectionRefused : SelectionRefused :> answers;
        in item checkRefused : CheckRefused :> answers;
        in item radioDetection : RadioDetection :> answers;
        in item qsoAnswer : WstxQsoControl::QsoAnswer :> answers;
        in item autoRefused : WstxAutoControl::AutoRefused :> answers;
        in item evaluateReply : WstxRankingControl::EvaluateReply :> answers;
        in item rankingState : WstxRankingControl::RankingState :> answers;
        in item rankingRefused : WstxRankingControl::RankingRefused :> answers;
        in item strategiesState : WstxStrategies::StrategiesState :> answers;
        in item contestList : WstxStrategies::ContestList :> answers;
        in item strategiesRefused : WstxStrategies::StrategiesRefused :> answers;
        in item jobAccepted : WstxReceiveControl::JobAccepted :> answers;
        in item receiveRefused : WstxReceiveControl::Refused :> answers;
        in item recordsPage : WstxReceiveControl::RecordsPage :> answers;
        in item cursorExpired : WstxReceiveControl::CursorExpired :> answers;
        in item diagnosticsView : WstxReceiveControl::DiagnosticsView :> answers;
        in item haltReceipt : WstxTransmitControl::HaltReceipt :> answers;
        in item saveAnswer : WstxLogControl::SaveAnswer :> answers;
        in item resent : WstxLogControl::Resent :> answers;
        in item logImportView : WstxLogControl::ImportView :> answers;
        in item exportChunk : WstxLogControl::ExportChunk :> answers;
        in item historyPage : WstxLogControl::HistoryPage :> answers;
        in item countryFileState : WstxLogControl::CountryFileState :> answers;
        in item logRefused : WstxLogControl::LogRefused :> answers;
        in item settingsOutcome : WstxRadioControl::SettingsOutcome :> answers;
        in item settingsRefused : WstxRadioControl::SettingsRefused :> answers;
        in item detectRefused : WstxRadioControl::DetectRefused :> answers;
        in item endpointList : WstxAudioControl::EndpointList :> answers;
        in item listRefused : WstxAudioControl::ListRefused :> answers;
        in item saveRefused : WstxProfileAccess::SaveRefused :> answers;
        in item recordingReserved : WstxRecordingTransfer::ImportReserved :> answers;
        in item recordingImportView : WstxRecordingTransfer::ImportView :> answers;
        in item recordingRefused : WstxRecordingTransfer::ImportRefused :> answers;

        in item selection : SelectionState :> views;
        in item startup : StartupState :> views;
        in item settingsCheck : SettingsCheckReport :> views;
        in item qso : WstxQsoControl::QsoState :> views;
        in item openSlots : WstxQsoControl::OpenSlots :> views;
        in item auto : WstxAutoControl::AutoActivity :> views;
        in item ranked : WstxRankingControl::RankedList :> views;
        in item decodedFacts : WstxRankingControl::DecodedFacts :> views;
        in item alerts : WstxRankingControl::Alert :> views;
        in item receive : WstxReceiveControl::ReceiveStatus :> views;
        in item transmit : WstxTransmitControl::TransmitStatus :> views;
        in item txLevel : WstxTransmitControl::TxLevelStatus :> views;
        in item transmitOutcome : WstxTransmitControl::TransmitOutcome :> views;
        in item logAttempt : WstxLogControl::LogAttempt :> views;
        in item radio : WstxRadioControl::RadioStatus :> views;
        in item agc : WstxRadioControl::AgcStatus :> views;
        in item power : WstxRadioControl::PowerStatus :> views;
        in item audio : WstxAudioControl::AudioStatus :> views;
        in item spots : WstxHearing::FeedReport :> views;
        in item target : WstxHearing::TargetReport :> views;
        in item udp : WstxUdpControl::UdpSnapshot :> views;
        in item clock : WstxStationTime::ClockQuality :> views;
        in item config : WstxProfileAccess::ProfileSnapshot :> views;
        in item shack : WstxProfileAccess::ShackSnapshot :> views;
        in item definitions : WstxProfileAccess::DefinitionsSnapshot :> views;
        in item recording : WstxRecordingTransfer::RecordingStatus :> views;
    }
    interface def StationCommands {
        doc /* The operator's or an agent's commands and reads, given to the
             supervisor, and the station's answers and views. */
        end requester : StationOperations;
        end station : ~StationOperations;
    }
}
