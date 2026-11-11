package WstxStandardContact {
    private import ScalarValues::*;
    private import WstxRequirements::*;
    private import WstxContact::TxSlot;
    private import WstxContact::SequenceStateName;
    private import ModelNotes::*;
    doc /* The standard contact of the contact engine WstxArchitecture::QsoAndLogging (usage
         qso): choosing a partner, the first message, the automatic sequence of the standard
         messages up to completion, and Enable Tx, cancel, abort and halt as far as they act
         on the sequence. The data the engine's functions share, message texts, contests,
         Hound, modes, watchdogs, logging and the wire are WstxContact; keying and timing
         are WstxTransmit. Declared coverage is not an execution result. */

    // ------------------------------------------------------------ the function
    action def StandardContact {
        doc /* The function of QsoAndLogging that this package describes; the part performs
             it as its action standardContact. The browser and MCP clients send requests and
             show confirmed state; they run no sequence. Its detail tests are the engine's
             tests on a virtual clock in server/src/contact_tests.rs, which also holds bound
             contract tests. */
        @FollowsSource { reference = "WSJT-X 3.3.0-beta5: widgets/mainwindow.cpp, " +
            "DecodedMessageReaction.cpp, AutoRespondPeriod.cpp"; }
        attribute implementation : String = "server/src/contact.rs";
        attribute settings : WstxContact::SequenceSettings;
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
    metadata sourceRelease : Conflict about StandardContact, WstxProductScope::BehaviorBaseline {
        what = "3.3.0-beta5 in StandardContact; v3.3.0-beta4 in BehaviorBaseline; the WSJT-X " +
            "checkout named as master for message sequencing is v3.3.0-beta6";
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
        @DiffersFromSource { what = "never turns Enable Tx on; in WSJT-X a double-click " +
            "does (Configuration quick_call)"; }
        @NotStated { what = "what txOffsetHz does when Hold Tx is off and the row frequency " +
            "lies outside the Tx offset domain (contact.rs then keeps the Tx offset)"; }
        in rowIdentity : String;
        in replace : Boolean;
        out prepared : WstxContact::Contact[0..1];
        out refusal : WstxContact::ContactRefusal[0..1] {
            @NotStated { what = "which WstxContact::ContactRefusal each refused selection " +
                "or entry gets, apart from contact_active, invalid_call and invalid_grid " +
                "(contact.rs: row_not_standard, row_unavailable, profile_incomplete, " +
                "storage_unavailable)"; }
        }
        calc firstSlot : FirstSlotOnSelection;
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
             - The messages are generated and Prepared is raised with firstSlot.
             A partner other than that of a contact with a partner needs replace
             (ChangeContact); without it the selection is refused contact_active. Selecting
             that contact's partner again keeps the contact identity and what
             WstxContact::ContactSnapshot says about its dialogue. */
    }
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
             operating mode (WstxContact::StationOperatingMode), and Prepared is raised with tx1,
             or tx2 while Tx1 is skipped. The partner rule of SelectDecodedRow applies. */
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
        @FollowsSource { reference = "WSJT-X respond policy CQ: First " +
            "(AutoRespondPeriod.cpp)"; }
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
             station's operating mode, and CqStarted is raised. Its refusals are
             WstxContact::ContactCommand and WstxContact::StandardMessageSet. Off disarms
             with cause operator: no further request is made and a transmission already
             started finishes. Off changes no sequence state. */
    }
    action def TransmitSubmission {
        @LeftOpen { what = "how long before a period the request is first submitted, " +
            "provided a partner message counted before the audio start still changes that " +
            "period's message"; }
        doc /* While Enable Tx is on and the sequence is calling or with a partner, the
             engine keeps one WstxTransmit::TransmitRequest pending for the next period of
             the contact's Tx parity, carrying the text of the next message, the Tx offset
             and the contact's mode. Every transmission of the engine is such a request to
             the transmit service; the engine keys no PTT, opens no audio and addresses no
             radio. A change of text, offset or mode alters the pending request until its
             audio starts and applies to the following period after that. The same message
             is sent again in each of my periods until the sequence changes; only
             WstxContact::TxWatchdog bounds the repetition. lastTransmittedText changes only
             on a started outcome. A refused or failed outcome leaves Enable Tx off with the
             refusal shown (WstxTransmit::TransmitOutcome), and the engine does not submit
             the refused request again unchanged. A lost link, a reconnect and a retried or
             duplicated command submit no request again and create no second contact. */
    }
    calc def PartnerWorksOther {
        @DiffersFromSource { what = "the transmission is stopped by an abort; WSJT-X " +
            "clicks Halt Tx"; }
        in sequenceState : SequenceStateName;
        in startedWithTx1Skipped : Boolean;
        in autoSequence : Boolean {
            @Conflict { what = "here and in contact.rs the stop needs Auto Seq on; WSJT-X " +
                "(DecodedMessageReaction.cpp planAutoSequence) needs Enable Tx on and does " +
                "not read Auto Seq; adopting WSJT-X here is decided and not yet done"; }
        }
        in rowFrequencyHz : Real;
        in txOffsetHz : Integer;
        attribute toleranceHz : Integer = 50;
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
             it as TransmitStopped with cause halt. The engine itself never sends
             HaltTransmit: it stops a transmission only by a disarm or by
             WstxTransmit::AbortTransmission (WstxTransmit::TransmitHaltUse). */
    }

    // ------------------------------------------------------------ the sequence
    item def Prepared {
        attribute firstSlot : TxSlot;
        doc /* Raised when a contact is prepared: by the operator's selection of a decoded
             row or entry of a DX station (WstxContact::ContactCommand select_row, enter_dx),
             or by the received row that CallFirst answers. firstSlot is one of tx1 to
             tx5. */
    }
    item def NextChosen {
        @Conflict { what = "in completed and cancelled contact.rs keeps the state and " +
            "changes only the next message; WSJT-X (mainwindow_slots.cpp on_txbN_clicked) " +
            "sets the QSO progress of the chosen message in every state; the model does " +
            "not say whether the next message changes there; adopting WSJT-X here is " +
            "decided and not yet done"; }
        @NotStated { what = "what a choice does when there is no contact or the contact " +
            "lacks the chosen message (contact.rs refuses no_contact and invalid_message)"; }
        attribute slot : TxSlot;
        doc /* Raised by the operator's choice of the next message
             (WstxContact::ContactCommand choose_next; WSJT-X Tx button of a message). From
             idle, calling and every state with a partner the sequence enters the state
             whose message is slot: tx1 replying, tx2 report, tx3 rogerReport, tx4 rogers,
             tx5 signoff, tx6 calling. In completed and cancelled the state is kept. */
    }
    item def CqStarted {
        doc /* Raised by the operator's request to turn Enable Tx on (SetEnableTx) while the
             sequence is idle, completed or cancelled. */
    }
    item def PartnerMessage {
        @Conflict { what = "here and in contact.rs a counted message advances the sequence " +
            "whether Enable Tx is on or off; WSJT-X (DecodedMessageReaction.cpp " +
            "planAutoSequence) advances only while Enable Tx is on; adopting WSJT-X here " +
            "is decided and not yet done"; }
        @LeftOpen { what = "how many counted rows the engine remembers for the count-once " +
            "rule, provided no row of the current and the previous period counts twice"; }
        attribute kind : ReceivedKind;
        doc /* Raised by each received decoded row that is counted, while Auto Seq is on. A
             decoded row is counted when the sequence is with a partner, the row has the
             contact's mode, it reads as a message from the contact's DX call to my profile
             call (either may be a hash the station filled in), and it was decoded in a
             period of the parity opposite to my Tx parity, at any audio frequency. A row
             counts once however often it is delivered, and a repeated decode of one period
             with the same text counts once. With Auto Seq off a counted message raises
             nothing; WstxContact::ContactSnapshot offers the step as suggested_slot. */
    }
    item def SignoffSent {
        doc /* Raised by a completed WstxTransmit::TransmitOutcome that the transmit service
             returns for this contact's Tx5, or for its Tx4 when that is RR73. */
    }
    item def Cancelled {
        doc /* Raised by the operator's request to cancel or abort (CancelContact,
             AbortQso) and by a change of the station's operating mode
             (WstxContact::ModeChange). */
    }
    item def LoggedByOperator {
        doc /* Raised by the operator's request to log a contact with a partner now
             (WstxContact::DirectLog). */
    }
    item def TransmitStopped {
        attribute cause : WstxTransmit::DisarmCause;
        doc /* Raised when the transmit service reports WstxTransmit::TransmitArming gone
             from armed to disarmed; cause is its lastDisarmCause. */
    }
    action def CompleteContact {
        @DiffersFromSource { what = "Enable Tx goes off; WSJT-X leaves it on with Tx6 " +
            "selected after a 73 received in rogers"; }
        doc /* Enable Tx off (WstxTransmit::DisarmCause contactCompleted), tx6 selected, and a
             contact with a DX call handed once to WstxContact::DirectLog. The sequence
             starts no further contact by itself. */
    }
    state def AutoSequence {
        @FollowsSource { reference = "WSJT-X processMessage and auto_sequence " +
            "(DecodedMessageReaction.cpp planProcessMessage, planAutoSequence)"; }
        @DiffersFromSource { what = "a 73 received in rogerReport is answered with one 73, " +
            "as a partner RRR or RR73 is"; }
        @Conflict { what = "a grid in rogerReport, rogers or signoff, a report without R in " +
            "signoff and a report with R in signoff change nothing here and in contact.rs; " +
            "WSJT-X (DecodedMessageReaction.cpp planProcessMessage) goes back to Tx2, Tx3 " +
            "and Tx4; adopting WSJT-X here is decided and not yet done"; }
        @NotStated { what = "whether turning Tx1 skip on (WstxContact::ToggleTx1Skip) moves " +
            "a replying sequence to report (contact.rs does, while tx1 is next)"; }
        doc /* One sequence for each station profile. Its nine states without substates are
             those of SequenceStateName; open and ended only group them for Prepared and
             CqStarted, and "with a partner" means a state inside withPartner. NextChosen
             has no transition here: its mapping is on the event. Entering a state makes its message
             the next one: replying tx1, report tx2, rogerReport tx3, rogers tx4, signoff
             tx5, every other state tx6.
             Default: any other event in a state that has no transition for it changes
             nothing, so a repeated partner message makes the same message go out again
             and messages after completed or cancelled are ignored. */
        entry; then open;
        state open {
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
            transition first calling accept Cancelled then idle;
            transition first calling accept s : TransmitStopped
                if s.cause == WstxTransmit::DisarmCause::halt or
                    s.cause == WstxTransmit::DisarmCause::txWatchdog then idle;
        }
        state ended {
            state completed { entry action complete : CompleteContact; }
            state cancelled;
        }
        transition first open.idle accept CqStarted then open.calling;
        transition first ended accept CqStarted then open.calling;
        transition first open accept p : Prepared
            if p.firstSlot == TxSlot::tx1 then open.withPartner.replying;
        transition first open accept p : Prepared
            if p.firstSlot == TxSlot::tx2 then open.withPartner.report;
        transition first open accept p : Prepared
            if p.firstSlot == TxSlot::tx3 then open.withPartner.rogerReport;
        transition first open accept p : Prepared
            if p.firstSlot == TxSlot::tx4 then open.withPartner.rogers;
        transition first open accept p : Prepared
            if p.firstSlot == TxSlot::tx5 then open.withPartner.signoff;
        transition first ended accept p : Prepared
            if p.firstSlot == TxSlot::tx1 then open.withPartner.replying;
        transition first ended accept p : Prepared
            if p.firstSlot == TxSlot::tx2 then open.withPartner.report;
        transition first ended accept p : Prepared
            if p.firstSlot == TxSlot::tx3 then open.withPartner.rogerReport;
        transition first ended accept p : Prepared
            if p.firstSlot == TxSlot::tx4 then open.withPartner.rogers;
        transition first ended accept p : Prepared
            if p.firstSlot == TxSlot::tx5 then open.withPartner.signoff;
        transition first open.withPartner.rogers accept m : PartnerMessage
            if m.kind == ReceivedKind::seventyThree then ended.completed;
        transition first open.withPartner.rogers accept SignoffSent then ended.completed;
        transition first open.withPartner.signoff accept SignoffSent then ended.completed;
        transition first open.withPartner accept LoggedByOperator then ended.completed;
        transition first open.withPartner accept Cancelled then ended.cancelled;
    }

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
    requirement 'CL-010-03' {
        doc /* The contact engine MUST accept Enable Tx on and off, contact cancellation,
             Abort QSO and Halt Tx as explicit operator operations (SetEnableTx,
             CancelContact, AbortQso, HaltTx) and transmit only by TransmitSubmission. */
        subject qso : WstxArchitecture::QsoAndLogging;
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String =
            "server/src/contact.rs; server/src/contact_http.rs; server/src/transmit/service.rs";
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
    satisfy 'CL-010-03' by WstxArchitecture::physicalStation.backend.stations.qso;
    satisfy 'CL-010-17' by WstxArchitecture::physicalStation.backend.stations.qso;

    dependency CL_010_01_to_FR_007 from 'CL-010-01' to 'FR-007';
    dependency CL_010_18_to_FR_007 from 'CL-010-18' to 'FR-007';
    dependency CL_010_18_to_FR_008 from 'CL-010-18' to 'FR-008';
    dependency CL_010_19_to_FR_007 from 'CL-010-19' to 'FR-007';
    dependency CL_010_02_to_FR_007 from 'CL-010-02' to 'FR-007';
    dependency CL_010_02_to_FR_008 from 'CL-010-02' to 'FR-008';
    dependency CL_010_02_to_FR_019 from 'CL-010-02' to 'FR-019';
    dependency CL_010_03_to_FR_007 from 'CL-010-03' to 'FR-007';
    dependency CL_010_03_to_FR_008 from 'CL-010-03' to 'FR-008';
    dependency CL_010_17_to_FR_007 from 'CL-010-17' to 'FR-007';
    dependency contactPromise from AutoSequence to 'FR-007';
    dependency transmitBoundary from TransmitSubmission to WstxTransmit::TransmitRequest;
    dependency transmitOwner from TransmitSubmission to WstxArchitecture::TransmitService;
    dependency changeContactClause from ChangeContact to 'CL-050-04';
    dependency reportFromRange from SelectDecodedRow to WstxContact::ReportRange;

    // ------------------------------------------------------------ verification cases
    verification 'TC-007-001' {
        doc /* Standard FT8 contact through server and browser. This defines a case, not an
             execution result.
             Setup: candidate server and Chromium on a virtual UTC clock, profile HB9BLA
             JN47, scripted decoded rows and a transmit-service double that records requests
             and returns outcomes (no audio, PTT or radio). The expected values are written
             by hand, independent of candidate output.
             (a) Responder: select "CQ K1ABC FN42" (SNR -12.4, 1234.6 Hz, even period),
                 Enable Tx, feed "HB9BLA K1ABC -05", then "HB9BLA K1ABC RR73". The selection
                 gives K1ABC, FN42, report -12, Rx and Tx 1235 Hz, odd parity, Tx1 "K1ABC
                 HB9BLA JN47" next, Tx2 "K1ABC HB9BLA -12", Tx3 "K1ABC HB9BLA R-12", Tx4
                 "K1ABC HB9BLA RRR", Tx5 "K1ABC HB9BLA 73", Tx6 "CQ HB9BLA JN47" and no
                 request before Enable Tx; then replying with Tx1, rogerReport with Tx3,
                 signoff with Tx5, completed after the completed Tx5, Enable Tx off, logged
                 once.
             (b) Responder, the partner sends "HB9BLA K1ABC RRR": signoff with Tx5,
                 completed after the first completed Tx5.
             (c) Caller: Enable Tx with no partner, select "HB9BLA K1ABC FN42", feed "HB9BLA
                 K1ABC R-07", then "HB9BLA K1ABC 73" with Tx4 RRR, and once with Tx4 RR73:
                 calling with Tx6, report with Tx2 only after the selection, rogers with
                 Tx4, completed on the 73 or on the completed RR73, Enable Tx off, no
                 further CQ.
             (d) The partner repeats each message one to three times and resends its report
                 in rogers: the same text again, the report in rogers returns to Tx3, one
                 completion.
             (e) "HB9BLA W1XYZ -10" during the contact, a row of the previous partner after
                 ChangeContact, a reply after completion: nothing changes.
             (f) Tx1 skip; report overrides -50, +49, -51, +50; entry DL1ABC JO62 and the
                 entries AB1, <...> and grid SS00: selecting the CQ row gives report with
                 Tx2 at once; -50 and +49 are accepted and rendered "-50" and "+49"; -51,
                 +50 and the three invalid entries are refused with no contact.
             (g) The partner answers another call 50 Hz and 51 Hz from my Tx offset, in
                 replying and in report after a Tx1-skipped start; the Tx watchdog expires
                 while calling: Enable Tx off at 50 Hz, on at 51 Hz; the watchdog gives
                 idle.
             (h) Auto Seq off; Esc, Halt, disarm and cancel in every state; a browser action
                 with one command_id and a decoded row each delivered twice: the next
                 message never changes; Halt sends the halt first, Esc one abort and no
                 halt; the last transmitted text changes only on started outcomes; one
                 request and one count. */
        subject qso : WstxArchitecture::QsoAndLogging;
        objective {
            verify 'CL-010-01';
            verify 'CL-010-02';
            verify 'CL-010-03';
            verify 'CL-010-12';
            verify 'CL-010-18';
        }
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, no RF";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String =
            "server/src/contact_tests.rs; server/src/contact_http_tests.rs; tests/contact.test.cjs";
    }
    verification 'TC-007-010' {
        doc /* A partner's RRR or RR73 before my 73. This defines a case, not an execution
             result.
             Setup: the contact engine on a virtual UTC clock, profile HB9BLA JN37, Auto Seq
             on, Call 1st off, Tx watchdog 6, hand-authored rows in the partner's parity and
             a transmit-service double (no audio, PTT or radio). The expected values are
             written by hand from the WSJT-X source, independent of candidate output.
             (a) Tx4 RRR; own CQ, select "HB9BLA SV2CLJ KN10", after my Tx2 feed "HB9BLA
                 SV2CLJ R+02", after my Tx4 feed "HB9BLA SV2CLJ RR73", run four own periods,
                 feed "HB9BLA SV2CLJ 73": report with Tx2, rogers with Tx4 "SV2CLJ HB9BLA
                 RRR", after the RR73 signoff; the next own period carries "SV2CLJ HB9BLA
                 73", exactly one 73 and no RRR after it; then completed with tx6, Enable Tx
                 off with cause contactCompleted, one log entry for SV2CLJ with RST_RCVD
                 +02, nothing sent in the following periods; the late 73 changes and logs
                 nothing.
             (b) As (a), the partner answers my RRR with "HB9BLA SV2CLJ RRR": as (a).
             (c) FT4, and FT8 with Tx4 RR73: my RR73 is halted (rogers kept), the partner's
                 RR73 arrives, Enable Tx again: one 73, completed, one log entry.
             (d) "CQ K1ABC FN42" selected, after my Tx1 "HB9BLA K1ABC RR73"; a caller's
                 "HB9BLA K1ABC FN42" selected, after my Tx2 "HB9BLA K1ABC RRR": signoff with
                 Tx5 "K1ABC HB9BLA 73", one 73, completed, one log entry with RST_RCVD
                 absent.
             (e) In rogers the RR73 is counted while my next Tx4 is pending, before and
                 after its audio start: before, that period carries Tx5 instead of Tx4;
                 after, that Tx4 is sent and Tx5 follows in my next period; one 73 and one
                 log entry either way.
             (f) Auto Seq off, the partner's RR73 in rogers, replying and report: state and
                 next message unchanged, suggested_slot tx5, nothing completed or logged.
             (g) In rogers "HB9BLA W1XYZ RR73", "W1XYZ SV2CLJ RR73", the partner's RR73 in a
                 period of my own parity, and one RR73 row delivered twice; "HB9BLA K1ABC
                 73" in replying and in report; "HB9BLA SV2CLJ 73" in rogers: the first
                 three change nothing; the twice-delivered row gives one 73 and one log
                 entry; the 73 in replying or report changes nothing; the 73 in rogers
                 completes at once with no 73 sent and one log entry.
             (h) WW Digi, the partner's RR73 after my Tx4 RRR: signoff with Tx5, one 73,
                 completed, one log entry.
             (i) As (a), my 73 is halted, then Enable Tx again: signoff kept and nothing
                 logged; then one 73, completed and one log entry. */
        subject qso : WstxArchitecture::QsoAndLogging;
        objective {
            verify 'CL-010-02';
        }
        attribute level : Integer = 2;
        attribute location : String = "Windows development PC, isolated, no RF";
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "server/src/contact_tests.rs";
    }
    verification 'TC-010-010' {
        doc /* Call 1st answers the first caller of my CQ. This defines a case, not an
             execution result.
             Setup: the contact engine against the transmit owner core on a virtual clock,
             and the snapshot wire; profile HB9BLA JN47; an own CQ with Enable Tx (calling,
             odd parity), Hold Tx on, Tx offset 1500 Hz; hand-authored rows of a recorded CQ
             run in their decode order.
             (a) In one even period "HB9BLA EA4HTI IM69" (1678 Hz, -8) then "HB9BLA F1PBZ
                 -13" (2144 Hz, -10), delivered in reverse slice order: the contact is
                 EA4HTI with grid IM69, in report with Tx2 "EA4HTI HB9BLA -08" next at once,
                 still armed, the Tx offset 1500 Hz kept, sent in the next odd period.
             (b) Later "HB9BLA EA8BIA -11" and "HB9BLA SV1DZB KM18": nothing changes.
             (c) Call 1st off, Auto Seq off, or callers sending only RR73, 73, RRR and
                 R-10: the sequence stays calling and the next odd period sends "CQ HB9BLA
                 JN47".
             (d) The same callers after Enable Tx off: calling, nothing sent.
             (e) The snapshot settings of a started station: call_first true. */
        subject qso : WstxArchitecture::QsoAndLogging;
        objective {
            verify 'CL-010-17';
        }
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
}
