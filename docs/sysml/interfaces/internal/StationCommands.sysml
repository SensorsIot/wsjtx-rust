package WstxStationCommands {
    private import ScalarValues::*;
    private import WstxModeProcessing::Mode;
    private import WstxReceiveControl::ReceiveMode;
    private import WstxRadioControl::DetectionReport;
    private import WstxModelNotes::CodeDiffers;

    doc /* The supervisor's control interface: the commands the operator (through web)
         and an agent (through mcp) give the station, the same for both but those
         AgentRefusal names, the answers, and the supervisor's own state and records. */

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
        attribute requester : Requester {
            @CodeDiffers {
                what = "The code carries no requester: an agent's command reaches the "
                    + "station's routes under the MCP client's token.";
            }
        }
    }
    item def StationOutcome {
        doc /* The answer to one StationRequest: the answer of the function the command was
             passed to, the answer of the supervisor to one of its own commands, or
             StationRefused. */
    }
    enum def StationRefusal {
        doc /* Why the supervisor refuses a command before it reaches a function.
             wrongProfile: the command names another profile.
             stateConflict: it names another start of the station process, or a profile
             revision the station has left.
             swrFault: an agent's start, Tune or Auto on while the SWR barrier holds
             (WstxStationAuthority::SwrBarrier).
             autoOn: a command for the contact while Auto is on
             (WstxStationAuthority::AutoOnRule).
             audioUnconfigured: a live start on a profile without an input device.
             radioUnavailable: a live start on a profile of a radio's native connection
             whose session is not ready. */
        enum wrongProfile;
        enum stateConflict;
        enum swrFault;
        enum autoOn;
        enum audioUnconfigured;
        enum radioUnavailable;
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
        enum '2m';
        enum '1.25m';
        enum '70cm';
        enum '23cm';
    }
    enum def IaruRegion {
        doc /* An IARU region; 'all' stands for every region. */
        enum 'all';
        enum r1;
        enum r2 { @CodeDiffers { what = "The code has no IARU region."; } }
        enum r3 { @CodeDiffers { what = "The code has no IARU region."; } }
    }
    enum def NominalOrigin {
        doc /* Where the dial frequency of the selection comes from.
             unknown: there is none.
             manual: a selection without radio control; the dial is not known to be there.
             catReadback: radio control set it and read it back, or read it
             (WstxOperatingSelection::ReadbackRule).
             nativeReadback: the radio's native session tuned to it and confirmed it. */
        enum unknown;
        enum manual;
        enum catReadback;
        enum nativeReadback;
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
        attribute region : IaruRegion { doc /* The region the frequency is used in. */ }
    }
    attribute def WorkingFrequencies {
        doc /* The supervisor's part of the shack's settings
             (WstxProfileAccess::ShackSettings). */
        attribute entries : WorkingFrequency[0..200] ordered {
            doc /* At first, and after ResetFrequencies, WSJT-X's default list
                 (WstxOperatingSelection::BandFrequency). */ }
        attribute region : IaruRegion = IaruRegion::'all' {
            doc /* The station's IARU region, as the operator sets it: the station uses the
                 entries of this region and of the region 'all'; with 'all', every entry. */
            @CodeDiffers {
                what = "The code has no region: one fixed table of one frequency per mode "
                    + "and band serves every station.";
            }
        }
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
             releaseBlocked: receive did not give up its job.
             cancelled: it was cancelled. */
        enum releasing;
        enum applying;
        enum restarting;
        enum applied;
        enum failed;
        enum releaseBlocked;
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
             selectBandFirst: a mode with no band known.
             selectionUnavailable: the band has no frequency for the mode, or radio
             control has no such operation for this radio.
             busy: another selection, an import or a replay has not ended; a mode while
             the transmitter is keyed, plays or tunes; radio control kept by another
             exchange.
             radioUnavailable: the radio connection is not ready, the radio transmits,
             or the native session is not ready.
             counterExhausted: the operating revision has reached its end.
             operationSuperseded: a later selection or cancel has come after the one a
             cancel names.
             stateConflict: the profile was saved while the selection ran.
             releaseFailed: receive did not give up its job.
             audioUnconfigured: the profile names no input device.
             audioUnavailable: receive could not start again.
             cancelled, radioTimeout, radioRejected, readbackMismatch,
             radioFailedClose, invalidRequest: radio control's error
             (WstxOperatingSelection::SelectionRule). */
        enum selectBandFirst;
        enum selectionUnavailable;
        enum busy;
        enum radioUnavailable;
        enum counterExhausted;
        enum operationSuperseded;
        enum stateConflict;
        enum releaseFailed;
        enum audioUnconfigured;
        enum audioUnavailable;
        enum cancelled;
        enum radioTimeout;
        enum radioRejected;
        enum readbackMismatch;
        enum radioFailedClose;
        enum invalidRequest;
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
        enum alreadyCancelled;
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
            doc /* The bands with a frequency for the mode of the selection
                 (WstxOperatingSelection::BandFrequency). */ }
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
             startedUntuned: receive runs in the remembered mode on the radio's present
             dial.
             skipped: receive was started by a command before the resume.
             failed: receive could not be started. */
        enum idle;
        enum waiting;
        enum started;
        enum startedUntuned;
        enum skipped;
        enum failed;
    }
    item def StartupState {
        doc /* The resume of this start, given at every change. */
        attribute 'state' : ResumeState;
        attribute error : String[0..1] {
            doc /* With failed: the error of receive or audioUnconfigured. */ }
        attribute lastReceive : ReceiveChoice[0..1];
    }
    item def ProcessEnds {
        doc /* The station process ends. */
    }

    port def StationOperations {
        doc /* The station boundary: every command the operator and agents give the
             station, every read, every answer and every view the station gives back,
             each typed by the item of the function it belongs to. Web gives every
             feature (WstxStationLink::WireRule), mcp every one but the commands
             AgentRefusal names (AgentOperations). Written from the requester's side; the
             supervisor uses the conjugate. */
        out abstract item commands[0..*] {
            doc /* A command: it comes with a StationRequest, may change the station, and
                 is answered by its function's answer or by StationRefused. */ }
        out abstract item reads[0..*] {
            doc /* A read: it comes with a StationRequest, changes nothing, and is answered
                 by the view it asks for. */ }
        in abstract item answers[0..*] { doc /* The answer to one command or read. */ }
        in abstract item views[0..*] {
            doc /* A view of the station's state, given at station start and whenever a
                 value changes. */
            @CodeDiffers {
                what = "The code names no views: each is an event of the socket and the "
                    + "answer to the GET of its route.";
            }
        }

        out item selectMode : SelectMode :> commands {
            @CodeDiffers { what = "The code takes it as the POST of /receive/select with a mode."; }
        }
        out item selectBand : SelectBand :> commands {
            @CodeDiffers { what = "The code takes it as the POST of /receive/select with a band."; }
        }
        out item cancelSelection : CancelSelection :> commands {
            @CodeDiffers {
                what = "The code takes it as the POST of /receive/select with a "
                    + "target_command_id.";
            }
        }
        out item checkSettings : CheckSettings :> commands {
            @CodeDiffers { what = "The code has no settings check."; }
        }
        out item selectRow : WstxQsoControl::SelectRow :> commands;
        out item enterDx : WstxQsoControl::EnterDx :> commands;
        out item reply : WstxQsoControl::Reply :> commands;
        out item callCq : WstxQsoControl::CallCq :> commands;
        out item callDx : WstxQsoControl::CallDx :> commands;
        out item sendNext : WstxQsoControl::SendNext :> commands;
        out item resetRepetitions : WstxQsoControl::ResetRepetitions :> commands;
        out item cancelContact : WstxQsoControl::CancelContact :> commands {
            @CodeDiffers {
                what = "The code takes it as the command cancel of the POST of /contact/command.";
            }
        }
        out item abort : WstxQsoControl::Abort :> commands;
        out item chooseNext : WstxQsoControl::ChooseNext :> commands;
        out item editMessage : WstxQsoControl::EditMessage :> commands;
        out item setReport : WstxQsoControl::SetReport :> commands;
        out item setTx1Skip : WstxQsoControl::SetTx1Skip :> commands;
        out item setTx4 : WstxQsoControl::SetTx4 :> commands;
        out item setFrequency : WstxQsoControl::SetFrequency :> commands;
        out item setHoldTx : WstxQsoControl::SetHoldTx :> commands;
        out item setParity : WstxQsoControl::SetParity :> commands;
        out item tune : WstxQsoControl::Tune :> commands;
        out item confirmLog : WstxQsoControl::ConfirmLog :> commands {
            @CodeDiffers {
                what = "The code has no logging to confirm: a completed contact is logged at "
                    + "once.";
            }
        }
        out item discardLog : WstxQsoControl::DiscardLog :> commands {
            @CodeDiffers {
                what = "The code has no logging to confirm: a completed contact is logged at "
                    + "once.";
            }
        }
        out item switchAuto : WstxAutoControl::SwitchAuto :> commands;
        out item evaluate : WstxRankingControl::EvaluateRequest :> commands;
        out item ignore : WstxRankingControl::IgnoreCommand :> commands;
        out item clearIgnore : WstxRankingControl::ClearIgnoreList :> commands {
            @CodeDiffers {
                what = "The code has no clearing of the list: the POST of /strategy/ignore takes "
                    + "one call at a time.";
            }
        }
        out item clearAlerts : WstxRankingControl::ClearAlerts :> commands;
        out item selectStrategy : WstxStrategies::SelectStrategy :> commands {
            @CodeDiffers {
                what = "The code takes the active strategy and the contest with the PUT of "
                    + "/strategy.";
            }
        }
        out item startLive : WstxReceiveControl::StartLive :> commands {
            @CodeDiffers { what = "The code takes it as the POST of /receive/start."; }
        }
        out item stopLive : WstxReceiveControl::StopLive :> commands {
            @CodeDiffers { what = "The code takes it as the POST of /receive/stop."; }
        }
        out item startReplay : WstxReceiveControl::StartReplay :> commands {
            @CodeDiffers { what = "The code takes it as the POST of /recording/replay."; }
        }
        out item cancelJob : WstxReceiveControl::CancelJob :> commands;
        out item halt : WstxTransmitControl::Halt :> commands;
        out item saveRecord : WstxLogControl::SaveRecord :> commands {
            @CodeDiffers { what = "The code takes it as the POST of /contacts."; }
        }
        out item reserveImport : WstxLogControl::ReserveImport :> commands {
            @CodeDiffers { what = "The code takes it as the POST of /contacts/imports."; }
        }
        out item importChunk : WstxLogControl::ImportChunk :> commands {
            @CodeDiffers {
                what = "The code takes it as the PUT of /contacts/imports/ and the import's id.";
            }
        }
        out item resendLast : WstxLogControl::ResendLast :> commands {
            @CodeDiffers { what = "The code has no command that gives the newest record again."; }
        }
        out item exportCabrillo : WstxLogControl::ExportCabrillo :> commands {
            @CodeDiffers { what = "The code has no Cabrillo export."; }
        }
        out item detectRadios : WstxRadioControl::DetectRadios :> commands {
            @CodeDiffers { what = "The code takes it as the POST of /radio/detect."; }
        }
        out item applyRecommended : WstxRadioControl::ApplyRecommended :> commands {
            @CodeDiffers { what = "The code takes it as the POST of /radio/settings/apply."; }
        }
        out item saveConfig : WstxProfileAccess::SaveProfile :> commands {
            @CodeDiffers { what = "The code takes it as the PUT of /profile."; }
        }
        out item saveShack : WstxProfileAccess::SaveShack :> commands {
            @CodeDiffers {
                what = "The code has no shack's settings; the call sign and the locator are saved "
                    + "with the PUT of /profile.";
            }
        }
        out item createEntry : WstxProfileAccess::CreateEntry :> commands {
            @CodeDiffers {
                what = "The code has no collections of settings: the strategies are saved whole "
                    + "with the PUT of /strategy, the UDP targets with the PUT of /udp.";
            }
        }
        out item updateEntry : WstxProfileAccess::UpdateEntry :> commands {
            @CodeDiffers {
                what = "The code has no collections of settings: the strategies are saved whole "
                    + "with the PUT of /strategy, the UDP targets with the PUT of /udp.";
            }
        }
        out item deleteEntry : WstxProfileAccess::DeleteEntry :> commands {
            @CodeDiffers {
                what = "The code has no collections of settings: the strategies are saved whole "
                    + "with the PUT of /strategy, the UDP targets with the PUT of /udp.";
            }
        }
        out item resetFrequencies : WstxProfileAccess::ResetFrequencies :> commands {
            @CodeDiffers {
                what = "The code has no list of working frequencies to reset: it holds one fixed "
                    + "table.";
            }
        }
        out item updateMostWanted : WstxProfileAccess::UpdateMostWanted :> commands {
            @CodeDiffers {
                what = "The code takes it as the POST of /strategy/most-wanted/download.";
            }
        }
        out item updateCountryFile : WstxProfileAccess::UpdateCountryFile :> commands {
            @CodeDiffers {
                what = "The code downloads no country file: it takes one the operator uploads "
                    + "with the PUT of /dxcc.";
            }
        }
        out item reserveRecording : WstxRecordingTransfer::ReserveImport :> commands {
            @CodeDiffers { what = "The code takes it as the POST of /recording/imports."; }
        }
        out item recordingChunk : WstxRecordingTransfer::ImportChunk :> commands {
            @CodeDiffers {
                what = "The code takes it as the PUT of /recording/imports/ and the import's id.";
            }
        }
        out item cancelRecording : WstxRecordingTransfer::CancelImport :> commands {
            @CodeDiffers {
                what = "The code takes it as the DELETE of /recording/imports/ and the import's "
                    + "id.";
            }
        }

        out item records : WstxReceiveControl::ReadRecords :> reads;
        out item diagnostics : WstxReceiveControl::ReadDiagnostics :> reads;
        out item history : WstxLogControl::ReadHistory :> reads;
        out item logImport : WstxLogControl::ReadImport :> reads {
            @CodeDiffers {
                what = "The code takes it as the GET of /contacts/imports/ and the import's id.";
            }
        }
        out item export : WstxLogControl::ExportLog :> reads;
        out item countryFile : WstxLogControl::ReadCountryFile :> reads {
            @CodeDiffers { what = "The code takes it as the GET of /dxcc."; }
        }
        out item ranking : WstxRankingControl::ReadRankingState :> reads;
        out item operating : WstxStrategies::ReadStrategies :> reads;
        out item contests : WstxStrategies::ReadContests :> reads;
        out item endpoints : WstxAudioControl::ListEndpoints :> reads;
        out item recordingImport : WstxRecordingTransfer::ReadImport :> reads {
            @CodeDiffers {
                what = "The code takes it as the GET of /recording/imports/ and the import's id.";
            }
        }

        in item stationRefused : StationRefused :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the error body of an HTTP answer.";
            }
        }
        in item selectionAdmitted : SelectionAdmitted :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer to the "
                    + "POST of /receive/select.";
            }
        }
        in item selectionRefused : SelectionRefused :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the error body of the answer to the "
                    + "POST of /receive/select.";
            }
        }
        in item checkRefused : CheckRefused :> answers {
            @CodeDiffers { what = "The code has no settings check."; }
        }
        in item radioDetection : RadioDetection :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer to the "
                    + "POST of /radio/detect.";
            }
        }
        in item qsoAnswer : WstxQsoControl::QsoAnswer :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer to the "
                    + "POST of /contact/command.";
            }
        }
        in item autoRefused : WstxAutoControl::AutoRefused :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the error body of an HTTP answer.";
            }
        }
        in item evaluateReply : WstxRankingControl::EvaluateReply :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer to the "
                    + "POST of /strategy/evaluate.";
            }
        }
        in item rankingState : WstxRankingControl::RankingState :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of an HTTP answer of "
                    + "/strategy.";
            }
        }
        in item rankingRefused : WstxRankingControl::RankingRefused :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the error body of an HTTP answer.";
            }
        }
        in item strategiesState : WstxStrategies::StrategiesState :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer to the "
                    + "GET and the PUT of /strategy.";
            }
        }
        in item contestList : WstxStrategies::ContestList :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer to the "
                    + "GET of /strategy/contests.";
            }
        }
        in item strategiesRefused : WstxStrategies::StrategiesRefused :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the error body of an HTTP answer.";
            }
        }
        in item jobAccepted : WstxReceiveControl::JobAccepted :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer to the "
                    + "POST of /receive/start and /recording/replay.";
            }
        }
        in item receiveRefused : WstxReceiveControl::Refused :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the error body of an HTTP answer.";
            }
        }
        in item recordsPage : WstxReceiveControl::RecordsPage :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer to the "
                    + "GET of /receive/results.";
            }
        }
        in item cursorExpired : WstxReceiveControl::CursorExpired :> answers;
        in item diagnosticsView : WstxReceiveControl::DiagnosticsView :> answers;
        in item haltReceipt : WstxTransmitControl::HaltReceipt :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer to the "
                    + "POST of /transmit/halt.";
            }
        }
        in item saveAnswer : WstxLogControl::SaveAnswer :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer to the "
                    + "POST of /contacts.";
            }
        }
        in item resent : WstxLogControl::Resent :> answers {
            @CodeDiffers { what = "The code has no command that gives the newest record again."; }
        }
        in item logImportView : WstxLogControl::ImportView :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer of "
                    + "/contacts/imports.";
            }
        }
        in item exportChunk : WstxLogControl::ExportChunk :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is a part of the body of the GET of "
                    + "/contacts/export.adi.";
            }
        }
        in item historyPage : WstxLogControl::HistoryPage :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer to the "
                    + "GET of /contacts.";
            }
        }
        in item countryFileState : WstxLogControl::CountryFileState :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer of "
                    + "/dxcc.";
            }
        }
        in item logRefused : WstxLogControl::LogRefused :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the error body of an HTTP answer.";
            }
        }
        in item settingsOutcome : WstxRadioControl::SettingsOutcome :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer to the "
                    + "POST of /radio/settings/apply.";
            }
        }
        in item settingsRefused : WstxRadioControl::SettingsRefused :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the error body of an HTTP answer.";
            }
        }
        in item detectRefused : WstxRadioControl::DetectRefused :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the error body of an HTTP answer.";
            }
        }
        in item endpointList : WstxAudioControl::EndpointList :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer to the "
                    + "GET of /audio/endpoints.";
            }
        }
        in item listRefused : WstxAudioControl::ListRefused :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the error body of an HTTP answer.";
            }
        }
        in item saveRefused : WstxProfileAccess::SaveRefused :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the error body of an HTTP answer.";
            }
        }
        in item recordingReserved : WstxRecordingTransfer::ImportReserved :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer to the "
                    + "POST of /recording/imports.";
            }
        }
        in item recordingImportView : WstxRecordingTransfer::ImportView :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the JSON body of the answer of "
                    + "/recording/imports.";
            }
        }
        in item recordingRefused : WstxRecordingTransfer::ImportRefused :> answers {
            @CodeDiffers {
                what = "The code names no such answer: it is the error body of an HTTP answer.";
            }
        }

        in item selection : SelectionState :> views;
        in item startup : StartupState :> views;
        in item settingsCheck : SettingsCheckReport :> views {
            @CodeDiffers { what = "The code has no settings check."; }
        }
        in item qso : WstxQsoControl::QsoState :> views;
        in item openSlots : WstxQsoControl::OpenSlots :> views;
        in item auto : WstxAutoControl::AutoActivity :> views;
        in item ranked : WstxRankingControl::RankedList :> views;
        in item decodedFacts : WstxRankingControl::DecodedFacts :> views {
            @CodeDiffers {
                what = "The code has no view of its own for what ranking adds to a record.";
            }
        }
        in item alerts : WstxRankingControl::Alert :> views;
        in item receive : WstxReceiveControl::ReceiveStatus :> views;
        in item transmit : WstxTransmitControl::TransmitStatus :> views;
        in item txLevel : WstxTransmitControl::TxLevelStatus :> views;
        in item transmitOutcome : WstxTransmitControl::TransmitOutcome :> views {
            @CodeDiffers {
                what = "The code names no such view: transmit's outcomes travel in transmit.state "
                    + "as outcomes.";
            }
        }
        in item logAttempt : WstxLogControl::LogAttempt :> views {
            @CodeDiffers {
                what = "The code names no such view: a completed contact is logged at once.";
            }
        }
        in item radio : WstxRadioControl::RadioStatus :> views;
        in item agc : WstxRadioControl::AgcStatus :> views;
        in item power : WstxRadioControl::PowerStatus :> views;
        in item audio : WstxAudioControl::AudioStatus :> views;
        in item spots : WstxHearing::FeedReport :> views;
        in item target : WstxHearing::TargetReport :> views;
        in item udp : WstxUdpControl::UdpSnapshot :> views;
        in item clock : WstxStationTime::ClockQuality :> views;
        in item config : WstxProfileAccess::ProfileSnapshot :> views;
        in item shack : WstxProfileAccess::ShackSnapshot :> views {
            @CodeDiffers { what = "The code has no shack's settings."; }
        }
        in item definitions : WstxProfileAccess::DefinitionsSnapshot :> views {
            @CodeDiffers {
                what = "The code names no such view: the strategies travel in strategy.state.";
            }
        }
        in item recording : WstxRecordingTransfer::RecordingStatus :> views;
    }
    interface def StationCommands {
        doc /* The operator's commands and reads, given to the supervisor, and the
             station's answers and views. */
        end requester : StationOperations;
        end station : ~StationOperations;
    }
    enum def AgentRefusal {
        doc /* The commands an agent does not give: the station's setup is the operator's.
             Applying radio settings to the rig is operating and no setup.
             saveConfig: the station config, with the profile, the rig, CAT and PTT, the
             connection, the audio devices and the receive settings.
             saveShack: the shack's settings, with the call sign, the locator, the
             strategies file and the targets of UDP and PSK Reporter.
             udpTargets: the collection of the UDP targets, whose CreateEntry,
             UpdateEntry and DeleteEntry an agent does not give. */
        enum saveConfig;
        enum saveShack;
        enum udpTargets;
    }
    attribute def AgentCollection :> WstxProfileAccess::SettingsCollection {
        doc /* The collections whose members an agent creates, changes and deletes: those
             of SettingsCollection that AgentRefusal does not name. */
        assert constraint agentCollections {
            self == WstxProfileAccess::SettingsCollection::strategies
                or self == WstxProfileAccess::SettingsCollection::wantedList
                or self == WstxProfileAccess::SettingsCollection::txMacros
                or self == WstxProfileAccess::SettingsCollection::workingFrequencies
        }
    }
    port def AgentOperations :> StationOperations {
        doc /* The station boundary as an agent has it: StationOperations without the
             commands AgentRefusal names, its entry commands on the collections of
             AgentCollection only. Written from the agent's side; the supervisor uses the
             conjugate. */
        out item :>> saveConfig[0];
        out item :>> saveShack[0];
        out item :>> createEntry { attribute :>> collection : AgentCollection; }
        out item :>> updateEntry { attribute :>> collection : AgentCollection; }
        out item :>> deleteEntry { attribute :>> collection : AgentCollection; }
    }
    interface def AgentCommands {
        doc /* An agent's commands and reads, given to the supervisor, and the station's
             answers and views. */
        end requester : AgentOperations;
        end station : ~AgentOperations;
    }
}
