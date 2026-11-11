package WstxStandardContact {
    private import ScalarValues::*;
    private import WstxRequirements::*;
    doc /* The standard contact of the contact engine WstxArchitecture::QsoAndLogging (usage
         qso): choosing a partner, the first message, the automatic sequence of the standard
         messages up to completion, and Enable Tx, cancel, abort and halt as far as they act
         on the sequence. Message texts, contests, Hound, modes, watchdogs, logging and the
         wire are WstxContact; keying and timing are WstxTransmit. Declared coverage is not
         an execution result. */

    // ------------------------------------------------------------ the function
    action def StandardContact {
        doc /* The function of QsoAndLogging that this package describes; the part performs
             it as its action standardContact. The browser and MCP clients send requests and
             show confirmed state; they run no sequence. detailTests names the engine's unit
             tests on a virtual clock, which also hold the bound contract tests. */
        attribute implementation : String = "server/src/contact.rs";
        attribute detailTests : String = "server/src/contact_tests.rs";
        attribute source : String = "WSJT-X 3.3.0-beta5: widgets/mainwindow.cpp, " +
            "DecodedMessageReaction.cpp, AutoRespondPeriod.cpp";
        attribute settings : SequenceSettings;
        action selectDecodedRow : SelectDecodedRow;
        action enterDxStation : EnterDxStation;
        action changeContact : ChangeContact;
        action callFirst : CallFirst;
        action setEnableTx : SetEnableTx;
        action transmitSubmission : TransmitSubmission;
        action cancelContact : CancelContact;
        action abortQso : AbortQso;
        action haltTx : HaltTx;
        calc partnerWorksOther : PartnerWorksOther;
        state sequence : AutoSequence;
    }
    comment sourceRelease about StandardContact::source
        /* CONFLICT: 3.3.0-beta5 here; v3.3.0-beta4 in WstxProductScope::BehaviorBaseline;
           the WSJT-X checkout named as master for message sequencing is v3.3.0-beta6. */

    attribute def SequenceSettings {
        attribute autoSequence : Boolean default true;
        attribute callFirst : Boolean default true;
        attribute differsFromSource : String = "both start on; WSJT-X starts both off";
        doc /* Operator settings of the station (WstxContact::ContactCommand set_auto_seq,
             set_call_first). */
    }
    comment settingsKept about SequenceSettings
        /* CONFLICT: contact.rs starts both on at every station start and saves neither;
           WSJT-X saves AutoSeq and RespondCQ in its settings; the model says only that both
           start on. */

    // ------------------------------------------------------------ vocabulary
    enum def TxSlot {
        enum tx1; enum tx2; enum tx3; enum tx4; enum tx5; enum tx6;
        doc /* The six standard messages; their texts are WstxContact::StandardMessageSet. */
    }
    enum def ContactOrigin { enum decodedRow; enum manualEntry; enum ownCq; }
    attribute def SequenceStateFacts { attribute nextSlot : TxSlot; }
    enum def SequenceStateName :> SequenceStateFacts {
        enum idle { :>> nextSlot = TxSlot::tx6; }
        enum calling { :>> nextSlot = TxSlot::tx6; }
        enum replying { :>> nextSlot = TxSlot::tx1; }
        enum report { :>> nextSlot = TxSlot::tx2; }
        enum rogerReport { :>> nextSlot = TxSlot::tx3; }
        enum rogers { :>> nextSlot = TxSlot::tx4; }
        enum signoff { :>> nextSlot = TxSlot::tx5; }
        enum completed { :>> nextSlot = TxSlot::tx6; }
        enum cancelled { :>> nextSlot = TxSlot::tx6; }
        doc /* The states of AutoSequence as WstxContact::Contact shows them, each with the
             message that is next when the sequence enters it. "With a partner" means
             one of the five states inside AutoSequence::withPartner. */
    }
    enum def ReceivedKind {
        enum grid; enum signalReport; enum rogerReport; enum rogers; enum seventyThree;
        enum other;
        doc /* How the exchange of a message reads: a grid; a report without R; a report with
             R; RRR or RR73; 73; anything else. A contest activity reads its own exchanges as
             signalReport and rogerReport (WstxContact::GridExchangeContest, ContestExchange,
             EuVhfExchange). */
    }

    // ------------------------------------------------------------ choosing a partner
    action def SelectDecodedRow {
        in rowIdentity : String;
        in replace : Boolean;
        out prepared : WstxContact::Contact[0..1];
        out refusal : WstxContact::ContactRefusal[0..1];
        calc firstSlot : FirstSlotOnSelection;
        attribute differsFromSource : String = "never turns Enable Tx on; in WSJT-X a " +
            "double-click does (Configuration quick_call)";
        doc /* Prepares a contact with the sender of a decoded row. rowIdentity names one row
             of the current live results (WstxContact::ContactCommand select_row). Exactly
             one of prepared and refusal results; a refusal changes nothing.
             Selectable is a row read as a standard message whose sender is a concrete call
             or a hash the station filled in (WstxOfflineDecode::HashResolution). Which
             nonstandard, contest and Fox rows are selectable as well is
             WstxContact::StandardMessageSet, EuVhfExchange and HoundOperation. Every other
             row, a row of other results and a sender that gives no message set with my call
             are refused.
             Effects on WstxContact::Contact and WstxContact::FrequencyControls:
             - dxCall is the sender. dxGrid is the row's grid; a row without a grid keeps the
               grid known for the same partner in the same mode.
             - The report is formed from the row SNR by WstxContact::ReportRange.
             - rxOffsetHz is the row frequency rounded to whole Hz. txOffsetHz takes the same
               value only when Hold Tx is off and the row is not addressed to my call.
             - txParity is the parity opposite to the row's period; mode is the row's mode
               (WstxContact::ContactMode).
             - The messages are generated and nextSlot is firstSlot (AutoSequence Prepared).
             A partner other than that of a contact with a partner needs replace
             (ChangeContact); without it the selection is refused contact_active. Selecting
             that contact's partner again keeps the contact identity and what
             WstxContact::ContactSnapshot says about its dialogue. */
    }
    comment txFollowOutsideDomain about SelectDecodedRow
        /* NOT STATED: what txOffsetHz does when Hold Tx is off and the row frequency lies
           outside the Tx offset domain (contact.rs then keeps the Tx offset). */
    comment selectionRefusalCodes about SelectDecodedRow::refusal
        /* NOT STATED: which WstxContact::ContactRefusal each refused selection or entry
           gets, apart from contact_active, invalid_call and invalid_grid (contact.rs:
           row_not_standard, row_unavailable, profile_incomplete, storage_unavailable). */
    calc def FirstSlotOnSelection {
        in addressedToMe : Boolean;
        in received : ReceivedKind;
        in tx1Skipped : Boolean;
        return slot : TxSlot =
            if not addressedToMe ? (if tx1Skipped ? TxSlot::tx2 else TxSlot::tx1)
            else if received == ReceivedKind::signalReport ? TxSlot::tx3
            else if received == ReceivedKind::rogerReport ? TxSlot::tx4
            else if received == ReceivedKind::rogers or
                received == ReceivedKind::seventyThree ? TxSlot::tx5
            else TxSlot::tx2;
        doc /* The first message after a selection, from the row's exchange (WSJT-X
             processMessage). tx1Skipped is WstxContact::ToggleTx1Skip or a contest activity
             that disables Tx1 (WstxContact::GridExchangeContest). */
    }
    action def EnterDxStation {
        in dxCallText : String;
        in dxGridText : String[0..1];
        in replace : Boolean;
        out prepared : WstxContact::Contact[0..1];
        out refusal : WstxContact::ContactRefusal[0..1];
        doc /* Prepares a contact with a station that was not decoded (WSJT-X DX Call and DX
             Grid entry). The call is taken in upper case and must give a message set with my
             call (WstxContact::StandardMessageSet), else invalid_call. The grid is optional:
             4 or 6 Maidenhead characters, AA00..RR99 with an optional subsquare AA..XX, else
             invalid_grid. The contact has origin manualEntry, exactly the grid entered, the
             current report, unchanged Rx and Tx offsets and Tx parity, the station's
             operating mode (WstxContact::StationOperatingMode) and nextSlot tx1, or tx2
             while Tx1 is skipped. The partner rule of SelectDecodedRow applies. */
    }
    action def ChangeContact {
        doc /* A selection or entry with replace for another partner while the sequence is
             with a partner: the contact is replaced, not logged, and Enable Tx keeps its
             state (WSJT-X double-click on another station). While Enable Tx is on, the next
             period of the new contact's Tx parity carries its next message, by the
             replacement rules of WstxTransmit::TransmitRequest. In every other state a
             selection or entry needs no replace. What a replacement does to an automation or
             strategy run is WstxMcp::OperatingAutomation and
             WstxStrategy::ManualIntervention. */
    }
    action def CallFirst {
        attribute source : String = "WSJT-X respond policy CQ: First (AutoRespondPeriod.cpp)";
        doc /* While the sequence is calling for a CQ the operator started, with Enable Tx,
             Auto Seq and Call 1st on, the first eligible row of the rows decoded together,
             in decode order, is answered at once as SelectDecodedRow of that row without
             replace. Eligible is a standard message of the station's operating mode to my
             call from a concrete call (neither call a filled-in hash), decoded in a period of
             the parity opposite to my Tx parity, whose exchange reads grid or signalReport.
             Enable Tx keeps its state, and the answer is not operator activity for
             WstxContact::TxWatchdog. A refused row is passed over for the next eligible one.
             In every other case a calling sequence leaves calling only by an operator
             selection. A CQ that automation started is answered by its run (WstxMcp,
             WstxContest::ContestRun). */
    }

    // ------------------------------------------------------------ transmitting
    action def SetEnableTx {
        in enable : Boolean;
        doc /* On arms WstxTransmit::TransmitArming with the safety revision the operator was
             shown, and TransmitSubmission then sends. When the sequence is idle, completed
             or cancelled, on starts an own CQ: a new contact of origin ownCq in the
             station's operating mode (AutoSequence CqStarted). Its refusals are
             WstxContact::ContactCommand and WstxContact::StandardMessageSet. Off disarms
             with cause operator: no further request is made and a transmission already
             started finishes. Off changes no sequence state. */
    }
    action def TransmitSubmission {
        doc /* While Enable Tx is on and the sequence is calling or with a partner, the
             engine keeps one WstxTransmit::TransmitRequest pending for the next period of
             the contact's Tx parity, carrying the nextSlot text, the Tx offset and the
             contact's mode. A change of any of them alters the pending request until its
             audio starts and applies to the following period after that. The same message
             is sent again in each of my periods until the sequence changes; only
             WstxContact::TxWatchdog bounds the repetition. lastTransmittedText changes only
             on a started outcome. A refused or failed outcome leaves Enable Tx off with the
             refusal shown (WstxTransmit::TransmitOutcome), and the engine does not submit
             the refused request again unchanged. Apart from SignoffSent, no outcome changes
             the sequence state. */
    }
    comment submissionLead about TransmitSubmission
        /* LEFT OPEN: how long before a period the request is first submitted, provided a
           partner message counted before the audio start still changes that period's
           message. */
    calc def PartnerWorksOther {
        in sequenceState : SequenceStateName;
        in startedWithTx1Skipped : Boolean;
        in autoSequence : Boolean;
        in rowFrequencyHz : Real;
        in txOffsetHz : Integer;
        attribute toleranceHz : Integer = 50;
        attribute differsFromSource : String = "the transmission is stopped by an abort; " +
            "WSJT-X clicks Halt Tx";
        return stop : Boolean = autoSequence and
            (sequenceState == SequenceStateName::replying or
             (sequenceState == SequenceStateName::report and startedWithTx1Skipped)) and
            rowFrequencyHz - txOffsetHz <= toleranceHz and
            txOffsetHz - rowFrequencyHz <= toleranceHz;
        doc /* Evaluated for each decoded message of the contact's mode that the DX call
             sends to a call other than mine. On stop, Enable Tx goes off with cause operator
             and a transmission already started is stopped by
             WstxTransmit::AbortTransmission; the sequence state is kept (WSJT-X
             auto_sequence stop tolerance). */
    }
    comment stopCondition about PartnerWorksOther::autoSequence
        /* CONFLICT: here and in contact.rs the stop needs Auto Seq on; WSJT-X
           (DecodedMessageReaction.cpp planAutoSequence) needs Enable Tx on and does not
           read Auto Seq. */
    action def CancelContact {
        doc /* Ends the contact without logging it: Enable Tx off (WstxTransmit::DisarmCause
             contactCancelled), DX call, DX grid, Tx1 to Tx5 and the dialogue cleared, tx6
             selected (WSJT-X abortQSO). A transmission on the air finishes. A completed
             contact keeps its fields; only tx6 is selected. Raises Cancelled. */
    }
    action def AbortQso {
        doc /* CancelContact, and the current transmission or Tune stops at once by
             WstxTransmit::AbortTransmission with cause contactCancelled. It is no halt:
             halt_state and the halt count are unchanged. Like cancel it is accepted with any
             older contact revision. */
    }
    action def HaltTx {
        doc /* The operator's emergency stop, WstxTransmit::HaltTransmit. The sequence sees
             it as TransmitStopped with cause halt. */
    }

    // ------------------------------------------------------------ the sequence
    item def Prepared {
        attribute firstSlot : TxSlot;
        doc /* Raised when SelectDecodedRow, EnterDxStation or CallFirst prepared a contact. */
    }
    item def NextChosen {
        attribute slot : TxSlot;
        doc /* Raised when the operator chooses the next message (WstxContact::ContactCommand
             choose_next; WSJT-X Tx button of a message). */
    }
    comment nextChosenAfterEnd about NextChosen
        /* CONFLICT: in completed and cancelled contact.rs keeps the state and changes only
           the next message; WSJT-X (mainwindow_slots.cpp on_txbN_clicked) sets the QSO
           progress of the chosen message in every state; the model does not say. */
    item def CqStarted {
        doc /* Raised by SetEnableTx on while the sequence is idle, completed or cancelled. */
    }
    item def PartnerMessage {
        attribute kind : ReceivedKind;
        doc /* A counted partner message, raised while Auto Seq is on. A decoded row is
             counted when the sequence is with a partner, the row has the contact's mode, it
             reads as a message from the contact's DX call to my profile call (either may be
             a hash the station filled in), and it was decoded in a period of the parity
             opposite to my Tx parity, at any audio frequency. A row counts once however
             often it is delivered, and a repeated decode of one period with the same text
             counts once. With Auto Seq off a
             counted message raises nothing; WstxContact::ContactSnapshot offers the step as
             suggested_slot. */
    }
    comment advanceWhileDisarmed about PartnerMessage
        /* CONFLICT: here and in contact.rs a counted message advances the sequence whether
           Enable Tx is on or off; WSJT-X (DecodedMessageReaction.cpp planAutoSequence)
           advances only while Enable Tx is on. */
    comment countedMemory about PartnerMessage
        /* LEFT OPEN: how many counted rows the engine remembers for the count-once rule,
           provided no row of the current and the previous period counts twice. */
    item def SignoffSent {
        doc /* Raised by a completed WstxTransmit::TransmitOutcome of this contact's Tx5, or
             of its Tx4 when that is RR73. */
    }
    item def Cancelled {
        doc /* Raised by CancelContact, AbortQso and WstxContact::ModeChange. */
    }
    item def LoggedByOperator {
        doc /* Raised by a manual Log QSO of a contact with a partner
             (WstxContact::DirectLog). */
    }
    item def TransmitStopped {
        attribute cause : WstxTransmit::DisarmCause;
        doc /* Raised when WstxTransmit::TransmitArming goes from armed to disarmed; cause
             is its lastDisarmCause. */
    }
    action def CompleteContact {
        attribute differsFromSource : String = "Enable Tx goes off; WSJT-X leaves it on " +
            "with Tx6 selected after a 73 received in rogers";
        doc /* Enable Tx off (WstxTransmit::DisarmCause contactCompleted), tx6 selected, and a
             contact with a DX call handed once to WstxContact::DirectLog. The sequence
             starts no further contact by itself. */
    }
    state def AutoSequence {
        attribute source : String = "WSJT-X processMessage and auto_sequence " +
            "(DecodedMessageReaction.cpp planProcessMessage, planAutoSequence)";
        attribute differsFromSource : String = "a 73 received in rogerReport is answered " +
            "with one 73, as a partner RRR or RR73 is";
        doc /* One sequence for each station profile; its states are SequenceStateName.
             Default: an event in a state that has no transition for it changes nothing, so
             a repeated partner message makes the same message go out again and messages
             after completed or cancelled are ignored. Two events are stated here instead of
             one transition for each state: Prepared enters, from every state, the state
             whose nextSlot is its firstSlot; NextChosen does the same for its slot, tx6
             meaning calling, from every state but completed and cancelled. */
        entry; then idle;
        state idle;
        state calling;
        state withPartner {
            state replying;
            state report;
            state rogerReport;
            state rogers;
            state signoff;
            transition first replying accept m : PartnerMessage
                if m.kind == ReceivedKind::grid then report;
            transition first replying accept m : PartnerMessage
                if m.kind == ReceivedKind::signalReport then rogerReport;
            transition first replying accept m : PartnerMessage
                if m.kind == ReceivedKind::rogerReport then rogers;
            transition first replying accept m : PartnerMessage
                if m.kind == ReceivedKind::rogers then signoff;
            transition first report accept m : PartnerMessage
                if m.kind == ReceivedKind::signalReport then rogerReport;
            transition first report accept m : PartnerMessage
                if m.kind == ReceivedKind::rogerReport then rogers;
            transition first report accept m : PartnerMessage
                if m.kind == ReceivedKind::rogers then signoff;
            transition first rogerReport accept m : PartnerMessage
                if m.kind == ReceivedKind::rogerReport then rogers;
            transition first rogerReport accept m : PartnerMessage
                if m.kind == ReceivedKind::rogers or m.kind == ReceivedKind::seventyThree
                then signoff;
            transition first rogers accept m : PartnerMessage
                if m.kind == ReceivedKind::signalReport then rogerReport;
            transition first rogers accept m : PartnerMessage
                if m.kind == ReceivedKind::rogers then signoff;
        }
        state completed { entry action complete : CompleteContact; }
        state cancelled;
        transition first withPartner.rogers accept m : PartnerMessage
            if m.kind == ReceivedKind::seventyThree then completed;
        transition first withPartner.rogers accept SignoffSent then completed;
        transition first withPartner.signoff accept SignoffSent then completed;
        transition first idle accept CqStarted then calling;
        transition first completed accept CqStarted then calling;
        transition first cancelled accept CqStarted then calling;
        transition first calling accept Cancelled then idle;
        transition first withPartner accept Cancelled then cancelled;
        transition first withPartner accept LoggedByOperator then completed;
        transition first calling accept s : TransmitStopped
            if s.cause == WstxTransmit::DisarmCause::halt or
                s.cause == WstxTransmit::DisarmCause::txWatchdog then idle;
    }
    comment earlierMessageLate about AutoSequence
        /* CONFLICT: a grid in rogerReport, rogers or signoff, a report without R in signoff
           and a report with R in signoff change nothing here and in contact.rs; WSJT-X
           (DecodedMessageReaction.cpp planProcessMessage) goes back to Tx2, Tx3 and Tx4. */

    // ------------------------------------------------------------ elements the text names
    dependency from StandardContact to WstxProductScope::BehaviorBaseline;
    dependency from SequenceSettings, NextChosen to WstxContact::ContactCommand;
    dependency from TxSlot to WstxContact::StandardMessageSet;
    dependency from ReceivedKind to WstxContact::GridExchangeContest,
        WstxContact::ContestExchange, WstxContact::EuVhfExchange;
    dependency from SelectDecodedRow to WstxContact::ContactCommand,
        WstxOfflineDecode::HashResolution, WstxContact::StandardMessageSet,
        WstxContact::EuVhfExchange, WstxContact::HoundOperation,
        WstxContact::FrequencyControls, WstxContact::ReportRange, WstxContact::ContactMode,
        WstxContact::ContactSnapshot;
    dependency from FirstSlotOnSelection to WstxContact::ToggleTx1Skip,
        WstxContact::GridExchangeContest;
    dependency from EnterDxStation to WstxContact::StandardMessageSet,
        WstxContact::StationOperatingMode;
    dependency from ChangeContact to WstxMcp::OperatingAutomation,
        WstxStrategy::ManualIntervention, WstxTransmit::TransmitRequest;
    dependency from CallFirst to WstxContact::TxWatchdog, WstxContest::ContestRun;
    dependency from SetEnableTx to WstxTransmit::TransmitArming, WstxContact::ContactCommand,
        WstxContact::StandardMessageSet;
    dependency from TransmitSubmission to WstxContact::TxWatchdog,
        WstxTransmit::TransmitOutcome;
    dependency from PartnerWorksOther, AbortQso to WstxTransmit::AbortTransmission;
    dependency from HaltTx to WstxTransmit::HaltTransmit;
    dependency from PartnerMessage to WstxContact::ContactSnapshot;
    dependency from SignoffSent to WstxTransmit::TransmitOutcome;
    dependency from Cancelled to WstxContact::ModeChange;
    dependency from LoggedByOperator, CompleteContact to WstxContact::DirectLog;
    dependency from TransmitStopped to WstxTransmit::TransmitArming;

    // ------------------------------------------------------------ requirements
    requirement 'CL-010-01' {
        doc /* The contact engine MUST prepare a contact with a partner only by
             SelectDecodedRow of an acknowledged decoded row or by EnterDxStation of a DX
             call the operator entered. */
        subject qso : WstxArchitecture::QsoAndLogging;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String =
            "server/src/contact.rs; server/src/contact_http.rs";
    }
    requirement 'CL-010-18' {
        doc /* Preparing or replacing a contact MUST NOT turn Enable Tx on or start a
             transmission. */
        subject qso : WstxArchitecture::QsoAndLogging;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs";
    }
    requirement 'CL-010-19' {
        doc /* On a station without transmit capability the contact engine MUST still prepare
             contacts and log them. */
        subject qso : WstxArchitecture::QsoAndLogging;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs";
    }
    requirement 'CL-010-02' {
        doc /* The contact engine MUST advance the contact on the server by AutoSequence. */
        subject qso : WstxArchitecture::QsoAndLogging;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String =
            "server/src/contact.rs; server/src/contact_http.rs";
    }
    requirement 'CL-010-20' {
        doc /* The contact engine MUST report the sequence state, the next message, the last
             transmitted message, the pending request and a transmit failure as separate
             observations (WstxContact::ContactSnapshot). */
        subject qso : WstxArchitecture::QsoAndLogging;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String =
            "server/src/contact.rs; server/src/contact_http.rs";
    }
    requirement 'CL-010-03' {
        doc /* The contact engine MUST accept Enable Tx on and off, contact cancellation,
             Abort QSO and Halt Tx as explicit operator operations (SetEnableTx,
             CancelContact, AbortQso, HaltTx). */
        subject qso : WstxArchitecture::QsoAndLogging;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String =
            "server/src/contact.rs; server/src/contact_http.rs; server/src/transmit/service.rs";
    }
    requirement 'CL-010-22' {
        doc /* Abort QSO MUST stop the current transmission or Tune at once and cancel the
             contact without a halt. */
        subject qso : WstxArchitecture::QsoAndLogging;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String =
            "server/src/contact.rs; server/src/transmit/service.rs";
    }
    requirement 'CL-010-23' {
        doc /* The contact engine MUST NOT send WstxTransmit::HaltTransmit; it stops a
             transmission only by a disarm or by WstxTransmit::AbortTransmission. */
        subject qso : WstxArchitecture::QsoAndLogging;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs";
    }
    requirement 'CL-010-24' {
        doc /* Every transmission of the contact engine MUST be a
             WstxTransmit::TransmitRequest to the transmit service; the engine keys no PTT,
             opens no audio and addresses no radio. */
        subject qso : WstxArchitecture::QsoAndLogging;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs";
    }
    requirement 'CL-010-25' {
        doc /* A lost link, a reconnect, a retried or a duplicated command MUST NOT replay a
             transmit request or create a second contact. */
        subject qso : WstxArchitecture::QsoAndLogging;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String =
            "server/src/contact.rs; server/src/contact_http.rs";
    }
    requirement 'CL-010-17' {
        doc /* While an own CQ that the operator started runs with Enable Tx, Auto Seq and
             Call 1st on, the contact engine MUST answer its first caller by CallFirst. */
        subject qso : WstxArchitecture::QsoAndLogging;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String =
            "server/src/contact.rs; server/src/contact_http.rs";
    }
    satisfy 'CL-010-01' by WstxArchitecture::physicalStation.backend.stations.qso;
    satisfy 'CL-010-18' by WstxArchitecture::physicalStation.backend.stations.qso;
    satisfy 'CL-010-19' by WstxArchitecture::physicalStation.backend.stations.qso;
    satisfy 'CL-010-02' by WstxArchitecture::physicalStation.backend.stations.qso;
    satisfy 'CL-010-20' by WstxArchitecture::physicalStation.backend.stations.qso;
    satisfy 'CL-010-03' by WstxArchitecture::physicalStation.backend.stations.qso;
    satisfy 'CL-010-22' by WstxArchitecture::physicalStation.backend.stations.qso;
    satisfy 'CL-010-23' by WstxArchitecture::physicalStation.backend.stations.qso;
    satisfy 'CL-010-24' by WstxArchitecture::physicalStation.backend.stations.qso;
    satisfy 'CL-010-25' by WstxArchitecture::physicalStation.backend.stations.qso;
    satisfy 'CL-010-17' by WstxArchitecture::physicalStation.backend.stations.qso;

    dependency CL_010_01_to_FR_007 from 'CL-010-01' to 'FR-007';
    dependency CL_010_18_to_FR_007 from 'CL-010-18' to 'FR-007';
    dependency CL_010_18_to_FR_008 from 'CL-010-18' to 'FR-008';
    dependency CL_010_19_to_FR_007 from 'CL-010-19' to 'FR-007';
    dependency CL_010_02_to_FR_007 from 'CL-010-02' to 'FR-007';
    dependency CL_010_02_to_FR_008 from 'CL-010-02' to 'FR-008';
    dependency CL_010_02_to_FR_019 from 'CL-010-02' to 'FR-019';
    dependency CL_010_20_to_FR_007 from 'CL-010-20' to 'FR-007';
    dependency CL_010_20_to_FR_019 from 'CL-010-20' to 'FR-019';
    dependency CL_010_03_to_FR_007 from 'CL-010-03' to 'FR-007';
    dependency CL_010_03_to_FR_008 from 'CL-010-03' to 'FR-008';
    dependency CL_010_22_to_FR_008 from 'CL-010-22' to 'FR-008';
    dependency CL_010_23_to_FR_008 from 'CL-010-23' to 'FR-008';
    dependency CL_010_24_to_FR_008 from 'CL-010-24' to 'FR-008';
    dependency CL_010_25_to_FR_007 from 'CL-010-25' to 'FR-007';
    dependency CL_010_25_to_FR_008 from 'CL-010-25' to 'FR-008';
    dependency CL_010_17_to_FR_007 from 'CL-010-17' to 'FR-007';
    dependency contactPromise from AutoSequence to 'FR-007';
    dependency transmitBoundary from TransmitSubmission to WstxTransmit::TransmitRequest;
    dependency transmitOwner from TransmitSubmission to WstxArchitecture::TransmitService;
    dependency changeContactClause from ChangeContact to 'CL-050-04';

    // ------------------------------------------------------------ verification cases
    verification 'TC-007-001' {
        doc /* Standard FT8 contact through server and browser. This defines a case, not an
             execution result. */
        subject qso : WstxArchitecture::QsoAndLogging;
        objective {
            verify 'CL-010-01';
            verify 'CL-010-02';
            verify 'CL-010-03';
            verify 'CL-010-12';
            verify 'CL-010-18';
            verify 'CL-010-20';
            verify 'CL-010-25';
        }
        attribute setup : String = "candidate server and Chromium; profile HB9BLA/JN47; " +
            "virtual UTC clock; scripted decoded rows; a transmit-service double that " +
            "records TransmitRequests and returns outcomes (no audio, PTT or radio)";
        attribute steps : String = "(a) responder: select CQ K1ABC FN42 (SNR -12.4, " +
            "1234.6 Hz, even period), Enable Tx, feed the partner's report -05, then RR73; " +
            "(b) responder: the partner sends RRR; (c) caller: Enable Tx with no partner, " +
            "select the caller's grid row, feed R-07, then 73 with Tx4 RRR and once with " +
            "Tx4 RR73; (d) the partner repeats each message one to three times and resends " +
            "its report in rogers; (e) another station's message to me, a row of the " +
            "previous partner after ChangeContact, a reply after completion; (f) Tx1 skip, " +
            "report override -50, +49, -51, +50, entry DL1ABC JO62, invalid AB1, <...> and " +
            "grid SS00; (g) the partner answers another call 50 Hz and 51 Hz from my Tx " +
            "offset, in replying and in report after a Tx1-skipped start; the Tx watchdog " +
            "expires while calling; (h) Auto Seq off; Esc, Halt, disarm and cancel in every " +
            "state; a browser action and a decoded row each delivered twice";
        attribute expected : String = "selection gives K1ABC, FN42, report -12, Rx and Tx " +
            "1235 Hz, odd parity, Tx1 next, the six texts of StandardMessageSet and no " +
            "TransmitRequest before Enable Tx; (a) replying, rogerReport, signoff, " +
            "completed after the completed Tx5, Enable Tx off, logged once; (b) signoff, " +
            "completed after the first completed Tx5; (c) calling, report only after the " +
            "selection, rogers, completed on the 73 or on the completed RR73, no further " +
            "CQ; (d) the same text again, the report in rogers returns to Tx3, one " +
            "completion; (e) nothing changes; (f) report and Tx2 at once, -50 and +49 " +
            "accepted, the others refused with no contact; (g) Enable Tx off at 50 Hz, on " +
            "at 51 Hz; the watchdog while calling gives idle; (h) the next slot never " +
            "changes; Halt sends the halt first, Esc one abort and no halt; the last " +
            "transmitted text changes only on started outcomes; one request and one count";
        attribute oracle : String = "hand-written table of states, next slots and texts, " +
            "independent of candidate output";
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, no RF";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String =
            "server/src/contact_tests.rs; server/src/contact_http_tests.rs; tests/contact.test.cjs";
    }
    verification 'TC-007-010' {
        doc /* A partner's RRR or RR73 before my 73. This defines a case, not an execution
             result. */
        subject qso : WstxArchitecture::QsoAndLogging;
        objective {
            verify 'CL-010-02';
        }
        attribute setup : String = "the contact engine on a virtual UTC clock; profile " +
            "HB9BLA/JN37; Auto Seq on, Call 1st off, Tx watchdog 6; hand-authored rows in " +
            "the partner's parity; a transmit-service double (no audio, PTT or radio)";
        attribute steps : String = "(a) Tx4 RRR: own CQ, select HB9BLA SV2CLJ KN10, after " +
            "Tx2 feed R+02, after Tx4 feed RR73, run four own periods, feed 73; (b) as (a), " +
            "the partner answers my RRR with RRR; (c) FT4, and FT8 with Tx4 RR73: my RR73 " +
            "is halted, the partner's RR73 arrives, Enable Tx again; (d) the partner signs " +
            "off with RR73 in replying and with RRR in report; (e) the RR73 is counted " +
            "while my next Tx4 is pending, before and after its audio start; (f) Auto Seq " +
            "off in rogers, replying and report; (g) in rogers: RR73 from another station, " +
            "from the partner to another call, in my own parity, one row delivered twice; " +
            "73 in replying, report and rogers; (h) ww_digi: after my RRR the partner's " +
            "RR73; (i) as (a), my 73 is halted, then Enable Tx again";
        attribute expected : String = "(a) report, rogers, after the RR73 signoff; the " +
            "next own period carries one 73 and no RRR; after its completed outcome " +
            "completed with tx6, Enable Tx off with cause contactCompleted, one log entry " +
            "with RST_RCVD +02, nothing sent afterwards, the late 73 changes nothing; (b), " +
            "(c) and (h) the same; (d) signoff, one 73, completed, one log entry with " +
            "RST_RCVD absent; (e) before the audio start that period carries Tx5, after it " +
            "Tx5 follows in my next period; one 73 and one log entry either way; (f) state " +
            "and next slot unchanged, suggested_slot tx5, nothing logged; (g) the other " +
            "rows change nothing, the twice-delivered row gives one 73, 73 in replying or " +
            "report changes nothing, 73 in rogers completes with no 73 sent; (i) signoff " +
            "kept and nothing logged, then one 73, completed and one log entry";
        attribute oracle : String = "hand-written table from WSJT-X " +
            "DecodedMessageReaction.cpp and mainwindow.cpp, independent of candidate output";
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, no RF";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "server/src/contact_tests.rs";
    }
    verification 'TC-010-010' {
        doc /* Call 1st answers the first caller of my CQ. This defines a case, not an
             execution result. */
        subject qso : WstxArchitecture::QsoAndLogging;
        objective {
            verify 'CL-010-17';
        }
        attribute setup : String = "the contact engine against the transmit owner core on " +
            "a virtual clock; the snapshot wire; Enable Tx with no partner (calling, odd " +
            "parity), Hold Tx on";
        attribute steps : String = "after my CQ deliver in one even period HB9BLA EA4HTI " +
            "IM69 (1678 Hz, -8) then HB9BLA F1PBZ -13 (2144 Hz, -10), in reverse slice " +
            "order; later two more callers; repeat with Call 1st off, with Auto Seq off, " +
            "after Enable Tx off, and with callers sending only RR73, 73, RRR and R-10";
        attribute expected : String = "Call 1st on: the contact is EA4HTI, grid IM69, in " +
            "report with Tx2 EA4HTI HB9BLA -08 next at once, still armed, Tx offset 1500 Hz " +
            "kept, sent in the next odd period; later callers change nothing. In every " +
            "other run the sequence stays calling and the next odd period sends the CQ, or " +
            "nothing with Enable Tx off. The snapshot settings carry call_first true";
        attribute oracle : String = "hand-authored rows of a recorded CQ run and their " +
            "decode order";
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, no radio or RF";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String =
            "server/src/contact_tests.rs; server/src/contact_http_tests.rs";
    }
    dependency CL_010_01_verified_by_TC_007_001 from 'CL-010-01' to 'TC-007-001';
    dependency CL_010_01_verified_by_TC_007_003 from 'CL-010-01' to 'TC-007-003';
    dependency CL_010_01_verified_by_TC_007_007 from 'CL-010-01' to 'TC-007-007';
    dependency CL_010_02_verified_by_TC_007_001 from 'CL-010-02' to 'TC-007-001';
    dependency CL_010_02_verified_by_TC_007_004 from 'CL-010-02' to 'TC-007-004';
    dependency CL_010_02_verified_by_TC_007_007 from 'CL-010-02' to 'TC-007-007';
    dependency CL_010_02_verified_by_TC_007_010 from 'CL-010-02' to 'TC-007-010';
    dependency CL_010_03_verified_by_TC_007_001 from 'CL-010-03' to 'TC-007-001';
    dependency CL_010_03_verified_by_TC_007_004 from 'CL-010-03' to 'TC-007-004';
    dependency CL_010_03_verified_by_TC_007_007 from 'CL-010-03' to 'TC-007-007';
    dependency CL_010_17_verified_by_TC_010_010 from 'CL-010-17' to 'TC-010-010';
    dependency CL_010_18_verified_by_TC_007_001 from 'CL-010-18' to 'TC-007-001';
    dependency CL_010_19_verified_by_TC_007_004 from 'CL-010-19' to 'TC-007-004';
    dependency CL_010_20_verified_by_TC_007_001 from 'CL-010-20' to 'TC-007-001';
    dependency CL_010_22_verified_by_TC_007_004 from 'CL-010-22' to 'TC-007-004';
    dependency CL_010_23_verified_by_TC_007_004 from 'CL-010-23' to 'TC-007-004';
    dependency CL_010_24_verified_by_TC_007_004 from 'CL-010-24' to 'TC-007-004';
    dependency CL_010_25_verified_by_TC_007_001 from 'CL-010-25' to 'TC-007-001';
    dependency CL_010_25_verified_by_TC_007_004 from 'CL-010-25' to 'TC-007-004';
}
