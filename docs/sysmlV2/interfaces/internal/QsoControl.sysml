package WstxQsoControl {
    private import ScalarValues::*;
    private import WstxTransmitControl::DisarmCause;
    private import WstxTransmitControl::TransmitRefusal;
    private import WstxTransmitControl::TransmitFailure;
    private import WstxModeProcessing::Mode;
    private import WstxModeProcessing::PeriodParity;

    doc /* What the supervisor gives the qso function (its context with its
         configuration, the commands of the operator and of agents) and what qso answers
         and reports. An agent's command is the operator's (issue 122). */

    port def QsoControlPort {
        doc /* Written from the supervisor's side; qso uses the conjugate. */
        out item context : QsoContext;
        out item selectRow : SelectRow;
        out item enterDx : EnterDx;
        out item reply : Reply;
        out item callCq : CallCq;
        out item callDx : CallDx;
        out item sendNext : SendNext;
        out item resetRepetitions : ResetRepetitions;
        out item cancelContact : CancelContact;
        out item haltQso : HaltQso;
        out item chooseNext : ChooseNext;
        out item editMessage : EditMessage;
        out item setReport : SetReport;
        out item setTx1Skip : SetTx1Skip;
        out item setTx4 : SetTx4;
        out item setFrequency : SetFrequency;
        out item setHoldTx : SetHoldTx;
        out item setParity : SetParity;
        out item tune : Tune;
        out item confirmLog : ConfirmLog;
        out item discardLog : DiscardLog;
        in item answer : QsoAnswer;
        in item 'state' : QsoState;
        in item openSlots : OpenSlots;
    }
    interface def QsoControl {
        doc /* The supervisor commands the qso function; qso answers each command and
             reports its state. */
        end station : QsoControlPort;
        end qso : ~QsoControlPort;
    }

    attribute def QsoConfig {
        doc /* qso's part of the station config (WstxProfileAccess::StationConfig). */
        attribute autoSeq : Boolean = true {
            doc /* The sequence follows the partner's messages (WstxStandardQso::
                 SequenceRule); off, it only offers the next message. */ }
        attribute callFirst : Boolean = true {
            doc /* Call 1st (WstxStandardQso::CallFirstRule). */ }
        attribute repetitionLimit : Integer = 6 {
            doc /* How often one message is sent (WstxQsoTransmit::RepetitionLimit). From 1
                 to 99. */ }
        attribute activity : Activity = Activity::none {
            doc /* The operator's special activity (WstxSpecialActivities::ActivityRule). */ }
        attribute exchange : String[0..1] {
            doc /* The exchange of field_day and rtty (WstxSpecialActivities::
                 ContestExchange); absent for every other activity. */ }
        attribute rxHz : Integer = 1500 { doc /* The Rx offset at station start. */ }
        attribute txHz : Integer = 1500 { doc /* The Tx offset at station start. */ }
        assert constraint limitRange { repetitionLimit >= 1 and repetitionLimit <= 99 }
    }

    attribute def TxMacro {
        doc /* A free text the operator keeps for Tx5, the same in every station of the
             shack. */
        attribute text : String {
            doc /* At most 13 characters of the free-text alphabet
                 (WstxMessageEncode::EncodeRule), in capitals; it stands once in the list. */ }
    }
    attribute def QsoShared {
        doc /* qso's part of the shack's settings (WstxProfileAccess::ShackSettings). */
        attribute macros : TxMacro[0..*] ordered {
            doc /* The free texts Tx5 offers; at first one, TNX 73 GL. */ }
        attribute logAutomatically : Boolean = true {
            doc /* A contact by hand is logged at its completion; off, it waits for the
                 operator (WstxStandardQso::LogConfirmRule). */ }
    }

    item def QsoContext {
        doc /* qso's configuration and the station's facts that qso uses. The supervisor
             gives them at station start and whenever one changes. */
        attribute config : QsoConfig;
        attribute shared : QsoShared { doc /* qso's part of the shack's settings. */ }
        attribute call : String[0..1] { doc /* The profile's callsign. */ }
        attribute locator : String[0..1] { doc /* The profile's locator. */ }
        attribute band : String[0..1] {
            doc /* The station's band (WstxOperatingSelection::StationBandRule). */ }
        attribute mode : Mode { doc /* The station's operating mode. */ }
    }

    enum def Activity {
        doc /* The special activities of WSJT-X. Each has the number WSJT-X gives it in the
             Status field Special operation: none 0, na_vhf 1, eu_vhf 2, field_day 3,
             rtty 4, ww_digi 5, hound 7, arrl_digi 8. */
        enum none;
        enum na_vhf;
        enum eu_vhf;
        enum ww_digi;
        enum arrl_digi;
        enum field_day;
        enum rtty;
        enum hound;
    }
    enum def TxSlot {
        doc /* The six messages of a contact: Tx1 the grid, Tx2 the report, Tx3 the R and
             report, Tx4 RRR or RR73, Tx5 the 73, Tx6 the CQ. */
        enum tx1;
        enum tx2;
        enum tx3;
        enum tx4;
        enum tx5;
        enum tx6;
    }
    enum def Tx4Form {
        doc /* The text of Tx4. */
        enum rrr;
        enum rr73;
    }
    enum def SequenceState {
        doc /* Where a contact stands (WstxStandardQso::SequenceRule). */
        enum idle;
        enum calling;
        enum replying;
        enum report;
        enum roger_report;
        enum rogers;
        enum signoff;
        enum completed;
        enum cancelled;
    }
    enum def Origin {
        doc /* How a contact was prepared: from a decoded record, from an entered call, or
             as the station's own CQ. */
        enum decoded_row;
        enum manual_entry;
        enum own_cq;
    }

    item def SelectRow {
        doc /* Prepare a contact from a decoded record (WstxStandardQso::PrepareRule). */
        attribute sequence : Integer { doc /* The record of the live job. */ }
        attribute replace : Boolean { doc /* A contact in progress may be replaced. */ }
        attribute directiveConfirmed : Boolean = false {
            doc /* The warning on a CQ not for the station is confirmed
                 (WstxStandardQso::DirectedCqRule). */ }
    }
    item def EnterDx {
        doc /* Prepare a contact from an entered call (WstxStandardQso::PrepareRule). */
        attribute call : String;
        attribute grid : String[0..1];
        attribute replace : Boolean { doc /* A contact in progress may be replaced. */ }
    }
    item def Reply {
        doc /* Start: answer the station of a decoded record (WstxQsoTransmit::StartRule). */
        attribute sequence : Integer { doc /* The record of the live job. */ }
        attribute directiveConfirmed : Boolean = false {
            doc /* As SelectRow::directiveConfirmed. */ }
    }
    item def CallCq { doc /* Start: the own CQ (WstxQsoTransmit::StartRule). */ }
    item def CallDx {
        doc /* Start: call an entered call (WstxQsoTransmit::StartRule). */
        attribute call : String;
        attribute grid : String[0..1];
        attribute replace : Boolean { doc /* A contact in progress may be replaced. */ }
    }
    item def SendNext {
        doc /* Start: send this message next (WstxQsoTransmit::StartRule). */
        attribute slot : TxSlot;
    }
    item def ResetRepetitions {
        doc /* Start the repetition count anew (WstxQsoTransmit::ResetRule). */ }
    item def CancelContact { doc /* End the contact (WstxQsoTransmit::EndRule). */ }
    item def HaltQso {
        doc /* End the contact and stop its transmission: Halt QSO
             (WstxQsoTransmit::EndRule). */ }
    item def ChooseNext {
        doc /* Make this message due (WstxMessageChoice::MessageSet). */
        attribute slot : TxSlot;
    }
    item def EditMessage {
        doc /* Give a message a new text (WstxMessageChoice::MessageSet). */
        attribute slot : TxSlot;
        attribute text : String;
    }
    item def SetReport {
        doc /* The report sent to the partner (WstxMessageChoice::MessageSet). */
        attribute reportDb : Integer;
    }
    item def SetTx1Skip {
        doc /* Skip Tx1 (WstxMessageChoice::MessageSet). */
        attribute enabled : Boolean;
    }
    item def SetTx4 {
        doc /* The text of Tx4 (WstxMessageChoice::MessageSet). */
        attribute form : Tx4Form;
    }
    item def SetFrequency {
        doc /* The Rx offset, the Tx offset or both (WstxHoldTx::OffsetRule). */
        attribute rxHz : Integer[0..1] { doc /* Absent: unchanged. */ }
        attribute txHz : Integer[0..1] { doc /* Absent: unchanged. */ }
    }
    item def SetHoldTx {
        doc /* Hold the Tx offset (WstxHoldTx::HoldTxRule). */
        attribute enabled : Boolean;
    }
    item def SetParity {
        doc /* The parity of the own CQ. */
        attribute parity : PeriodParity;
    }
    item def Tune {
        doc /* Switch the Tune tone of transmit on or off. */
        attribute enabled : Boolean;
    }
    item def ConfirmLog {
        doc /* Log the completed contact that waits (WstxStandardQso::LogConfirmRule). */ }
    item def DiscardLog {
        doc /* Drop the completed contact that waits; nothing is logged. */ }

    enum def QsoRefusal {
        doc /* Why qso refuses a command. A refused command changes nothing.
             contact_active: a contact is in progress and the command does not replace it.
             no_contact: the command needs a contact, or a contact with a partner.
             row_not_standard: the record names no partner (no standard message, or an
             unresolved hashed call).
             invalid_call, invalid_grid: the entered call or grid cannot be sent.
             invalid_message: the text cannot be sent unaltered, or the slot has none.
             invalid_report: a report outside ReportRange.
             invalid_exchange: an exchange outside the activity's rule.
             out_of_range: a value outside its range.
             profile_incomplete: the profile lacks what the messages need.
             state_conflict: the command does not fit the contact's state.
             directive_not_answerable: a CQ not for the station, not confirmed.
             transmit_unavailable, busy, clock_not_synchronized: transmission is not
             possible (WstxQsoTransmit::BlockedStartRule).
             log_pending: a completed contact waits to be logged or discarded
             (WstxStandardQso::LogConfirmRule). */
        enum contact_active;
        enum no_contact;
        enum row_not_standard;
        enum invalid_call;
        enum invalid_grid;
        enum invalid_message;
        enum invalid_report;
        enum invalid_exchange;
        enum out_of_range;
        enum profile_incomplete;
        enum state_conflict;
        enum directive_not_answerable;
        enum transmit_unavailable;
        enum busy;
        enum clock_not_synchronized;
        enum log_pending;
    }
    item def QsoAnswer {
        doc /* The answer to each command of the operator or an agent: accepted, or
             refused. */
        attribute refusal : QsoRefusal[0..1] { doc /* Absent: accepted. */ }
        attribute field : String[0..1] { doc /* The value the refusal is about. */ }
        attribute blockedBy : TransmitRefusal[0..1] {
            doc /* An accepted start that cannot transmit: the reason
                 (WstxQsoTransmit::BlockedStartRule). */ }
    }

    attribute def DialogueEntry {
        doc /* One message of the dialogue (WstxStandardQso::DialogueRule). */
        attribute transmitted : Boolean { doc /* Sent by the station, else received. */ }
        attribute text : String;
        attribute snrDb : Integer[0..1] { doc /* A received message's SNR, rounded. */ }
        attribute periodStartMs : Integer { doc /* The period of its first time. */ }
        attribute count : Integer { doc /* How often it followed itself. */ }
    }
    attribute def QsoContact {
        doc /* The contact as qso reports it. */
        attribute id : String { doc /* The contact's identity: a UUID. */ }
        attribute origin : Origin;
        attribute dxCall : String[0..1] { doc /* The partner; absent for the own CQ. */ }
        attribute dxGrid : String[0..1];
        attribute sequence : SequenceState;
        attribute nextSlot : TxSlot { doc /* The message due. */ }
        attribute suggestedSlot : TxSlot[0..1] {
            doc /* With Auto Seq off: the message the sequence would choose. */ }
        attribute tx4 : Tx4Form;
        attribute messages : String[6] ordered {
            doc /* The texts of Tx1 to Tx6; empty for a slot without text. */ }
        attribute reportSent : String[0..1] { doc /* The report in the last sent Tx2 or Tx3. */ }
        attribute reportRcvd : String[0..1] { doc /* The last report counted from him. */ }
        attribute exchangeSent : String[0..1];
        attribute exchangeRcvd : String[0..1];
        attribute dialogue : DialogueEntry[0..*] ordered;
    }
    item def QsoState {
        doc /* qso's state. qso gives it at station start and whenever a value changes. */
        attribute activity : Activity { doc /* The activity in force. */ }
        attribute exchange : String[0..1];
        attribute serial : Integer { doc /* The contest serial sent next. */ }
        attribute holdTx : Boolean;
        attribute tx1Skip : Boolean;
        attribute parity : PeriodParity { doc /* The parity of the own CQ. */ }
        attribute reportDb : Integer { doc /* The report sent to the next partner. */ }
        attribute rxHz : Integer;
        attribute txHz : Integer;
        attribute txSlot : TxChoice[0..1] {
            doc /* qso's last choice of a Tx offset. Absent before the first. */ }
        attribute contact : QsoContact[0..1];
        attribute logPending : QsoContact[0..1] {
            doc /* A completed contact by hand that waits for ConfirmLog or DiscardLog. */ }
        attribute repetitionsLeft : Integer[0..1] {
            doc /* The sends left of the message due while transmission is on, 0 while it
                 is off; absent while the limit does not bound the contact
                 (WstxQsoTransmit::RepetitionLimit). */ }
        attribute expired : Boolean {
            doc /* The repetition limit stopped transmission; until the next start. */ }
        attribute busyWith : String[0..1] {
            doc /* The call the partner is in another QSO with
                 (WstxOperatingChain::BusyPartner). */ }
        attribute pausedCalls : Integer {
            doc /* The paused calls of the message due (WstxStandardQso::BusyPause). */ }
    }

    attribute def TxChoice {
        doc /* A choice of a Tx offset from the quiet space (WstxHoldTx::QuietSpace). */
        attribute hz : Integer;
        attribute powerDb : Integer[0..1] {
            doc /* The level of the chosen offset in whole dB. Absent when no period was
                 counted. */ }
    }
    attribute def OpenRange {
        doc /* A run of open Tx offsets: from loHz up to, and not including, hiHz. */
        attribute loHz : Integer;
        attribute hiHz : Integer;
    }
    item def OpenSlots {
        doc /* The open Tx slots of one build (WstxHoldTx::OpenSlotRule). Given at each
             build; absent while receive does not run live. */
        attribute atUtcMs : Integer { doc /* The station time of the build. */ }
        attribute mode : Mode;
        attribute rxParity : PeriodParity { doc /* The judged parity. */ }
        attribute qso : Boolean { doc /* A contact or a CQ is in progress. */ }
        attribute periods : Integer { doc /* The number of counted periods. */ }
        attribute open : OpenRange[0..*] ordered { doc /* Ascending and disjoint. */ }
    }

    item def QsoProgress {
        doc /* How a contact or a CQ that Auto started goes on. qso gives it for such a
             contact or CQ only, whenever one of its values changes. */
        attribute answered : Boolean {
            doc /* The partner has sent a message to the profile's call in this contact,
                 other than a repeat of the message he was called on. */ }
        attribute started : Boolean {
            doc /* A started QSO: answered, and a transmission of the station to the
                 partner has started. */ }
        attribute completed : Boolean { doc /* The contact has completed. */ }
        attribute repetitions : Integer {
            doc /* How often the message due has been sent, the paused calls of the busy
                 pause not counted. */ }
        attribute txHz : Integer { doc /* The Tx offset of the contact or CQ. */ }
        attribute reportDb : Integer[0..1] {
            doc /* The report the partner sent in this contact. Absent before it. */ }
        attribute busyWith : String[0..1] {
            doc /* The call the partner is in another QSO with. Absent while he is in
                 none. */ }
        attribute ended : DisarmCause[0..1] {
            doc /* Why transmission went off for the contact or CQ. Absent while it is
                 on. */ }
        attribute refusal : TransmitRefusal[0..1] {
            doc /* With ended refused: the refusal of a request after admission. */ }
        attribute failure : TransmitFailure[0..1] {
            doc /* With ended failed: the failure. */ }
    }
}
