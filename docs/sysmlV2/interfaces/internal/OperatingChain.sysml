package WstxOperatingChain {
    private import ScalarValues::*;
    private import WstxRankingControl::RankedList;
    private import WstxQsoControl::QsoProgress;
    private import WstxLogControl::LogRecord;
    private import WstxLogControl::EntityRequest;
    private import WstxLogControl::EntityAnswer;
    private import WstxLogControl::WorkedStatus;
    private import WstxTransmitControl::TransmitRefusal;
    private import WstxTransmitControl::Arm;
    private import WstxTransmitControl::Disarm;
    private import WstxTransmitControl::Abort;
    private import WstxTransmitControl::SetTune;
    private import WstxTransmitControl::StepBegins;
    private import WstxTransmitControl::CommandAnswer;
    private import WstxTransmitControl::TransmitOutcome;
    private import WstxTransmitControl::TransmitStatus;
    private import ModelNotes::FollowsSource;
    private import WstxRequirements::'FR-011';
    private import ModelBindings::ImplementationState;
    private import RequirementDerivation::*;
    private import ModelBindings::Status;
    private import ModelBindings::ImplementedIn;
    port def RankedActivityPort {
        doc /* Written from ranking's side; auto uses the conjugate. */
        out item ranked : RankedList;
    }
    interface def RankedActivity {
        doc /* The ranked list of each evaluation, from ranking to auto. */
        end ranking : RankedActivityPort;
        end auto : ~RankedActivityPort;
    }
    port def TargetChoicePort {
        out item target : CallTarget;
        out attribute slot : TxSlot;
        in item answer : StartAnswer;
        in item progress : QsoProgress;
    }
    item def CallTarget { doc /* The station to call, or CQ. */ }
    item def StartAnswer {
        attribute blockedBy : TransmitRefusal[0..1];
        doc /* The answer to a start: absent when the start will happen, otherwise the arm
             condition that blocks it, one of clockNotSynchronized, busy by Tune,
             radioUnavailable and transmitUnsupported. */
    }
    interface def TargetChoice {
        doc /* The station Auto chooses, from auto to qso, and what qso answers. */
        end auto : TargetChoicePort;
        end qso : ~TargetChoicePort;
    }
    port def MessageToSendPort {
        doc /* Written from qso's side; transmit uses the conjugate. The commands are
             those of TransmitControl and are answered as there. */
        out item request : TransmitRequest;
        out item arm : Arm;
        out item disarm : Disarm;
        out item abort : Abort;
        out item tune : SetTune;
        out item step : StepBegins;
        in item answer : CommandAnswer;
        in item outcome : TransmitOutcome;
        in item status : TransmitStatus;
    }
    interface def MessageToSend {
        doc /* The next message of a contact and its period, and the contact's commands
             of the transmit state, from qso to transmit. */
        end qso : MessageToSendPort;
        end transmit : ~MessageToSendPort;
    }
    port def CompletedContactPort {
        out item contact : FinishedContact;
        in item answer : LogAnswer;
    }
    item def FinishedContact { doc /* The finished contact; the logged contact. */ }
    enum def LogAnswerKind {
        enum accepted;
        enum refused;
    }
    item def LogAnswer {
        doc /* The log's answer to one finished contact. */
        attribute kind : LogAnswerKind {
            doc /* refused when the contact is the same station again
                 (LogError::sameStationAgain); accepted for every other contact, also
                 when its record waits or cannot be stored. */ }
    }
    interface def CompletedContact {
        doc /* A finished contact, and the log's answer; the hand-over and its order are
             'CL-085-02'. */
        end producer : CompletedContactPort;
        end consumer : ~CompletedContactPort;
    }
    requirement 'CL-085-02' {
        subject handover : CompletedContact;
        doc /* qso hands each completed contact to the log once, at its completion or by Log
             QSO. The log answers each one with accepted or refused: refused when CL-085-01
             refuses it, accepted otherwise. The answer is given before qso counts the contest
             serial for that contact. A refusal changes nothing else in the QSO: it completes,
             transmission goes off with cause contactCompleted, and a Log QSO of a running QSO
             still closes it (completed, Tx6). Details: WstxOperatingChain::LogAnswer,
             WstxSpecialActivities::ContestSerialRule. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/contact.rs; server/src/contact_http.rs"; }
    }
    #derivation connection {
        end #original ::> 'FR-011';
        end #derive ::> 'CL-085-02';
    }
    port def LoggedContactPort {
        doc /* Written from the log's side; the consumer uses the conjugate. */
        out item logged : LoggedContact;
    }
    item def LoggedContact {
        doc /* A QSO the log has stored for the first time, given once; and the newest
             QSO of the logbook again on the operator's Log QSO (ResendLast). */
        attribute record : LogRecord;
    }
    interface def LoggedContactLink {
        doc /* Each newly stored QSO, from the log to the programs that are told of it. */
        end log : LoggedContactPort;
        end consumer : ~LoggedContactPort;
    }

    // ---- What has been worked: from log to ranking ---------------------------------------

    enum def WorkedCategory {
        doc /* What a logged QSO counts for.
             call: the call, in upper case.
             grid: the first four characters of the grid, in upper case; a QSO without
             them counts for no grid.
             dxcc: the name of the call's entity as the country file writes it.
             continent, cqZone, ituZone: those of the call's entity. A call without an
             entity counts for none of the four.
             prefix: the prefix of the call by the rules of the CQ WPX contest. */
        @FollowsSource { reference = "The rules of the CQ WPX contest: the prefix"; }
        enum call;
        enum grid;
        enum dxcc;
        enum continent;
        enum cqZone;
        enum ituZone;
        enum prefix;
    }
    attribute def Standing {
        doc /* Whether a key is in the logbook, and whether a confirmed QSO holds it. */
        attribute worked : Boolean;
        attribute confirmed : Boolean { doc /* Never true without worked. */ }
    }
    attribute def DateWindow {
        doc /* Which QSOs a WorkedSet counts. */
        attribute firstDate : String[0..1] {
            doc /* The first UTC date, YYYYMMDD; absent for every QSO of the logbook. */ }
        attribute lastDate : String[0..1] { doc /* The last date; given with firstDate. */ }
    }
    item def WorkedWindow {
        doc /* Ask for the WorkedSet of a window. */
        attribute window : DateWindow;
    }
    item def WorkedSet {
        doc /* What the logbook holds, for the QSOs of one WorkedWindow and the country
             file in use.
             For each key of each WorkedCategory it gives a Standing in three scopes:
             ever, on a band in any mode, and on a band in a mode. A key is new in a
             scope when it is not worked there, and needed when it is not worked or not
             confirmed there.
             For a call it also gives the WorkedStatus, whether a QSO with it has no
             grid, and the US state of its latest QSO that names one, a confirmed QSO
             before one that is not; the state is read from every QSO of the logbook,
             whatever the window. */
        attribute window : DateWindow;
    }
    item def ContestPeriod {
        doc /* Ask for the QSOs that started in a period. */
        attribute startUtcMs : Integer { doc /* The first instant of the period. */ }
        attribute endUtcMs : Integer { doc /* The first instant after it. */ }
    }
    attribute def PeriodQso {
        attribute call : String { doc /* In upper case. */ }
        attribute grid : String[0..1];
        attribute band : String[0..1] { doc /* The effective band of the record. */ }
        attribute mode : String { doc /* The effective mode of the record. */ }
        attribute startUtcMs : Integer;
    }
    item def PeriodQsos {
        doc /* The QSOs of a ContestPeriod, in the order of the logbook. */
        attribute qsos : PeriodQso[0..*] ordered;
    }
    port def WorkedBeforePort {
        doc /* Written from the log's side; ranking uses the conjugate. A WorkedWindow is
             answered by its WorkedSet, an EntityRequest by an EntityAnswer, a
             ContestPeriod by PeriodQsos. */
        in item window : WorkedWindow;
        out item worked : WorkedSet;
        in item lookUp : EntityRequest;
        out item entity : EntityAnswer;
        in item period : ContestPeriod;
        out item qsos : PeriodQsos;
    }
    interface def WorkedBefore {
        doc /* What has been worked, and the entity of a call, from log to ranking. */
        end log : WorkedBeforePort;
        end ranking : ~WorkedBeforePort;
    }

    // ---------------------------------------------------------------- messages
    enum def TxSlot { enum tx1; enum tx2; enum tx3; enum tx4; enum tx5; enum tx6; }
    attribute def BusyPartner {
        attribute busyPausedCallsMax : Integer = 6;
        doc /* #97 decision 7 (operator #93 2026-11-09; it replaces the WSJT-X stop of
             partnerWorksOther for the contacts that pause, AutoSequence; the #93 draft fca9822fe
             compared). Starts: a decoded standard message from the partner (the contact's DX
             call) to another call than mine that carries a grid, a report or an R-report (his QSO
             with that station in progress, also his own Tx1 to it); a hashed call "<...>" that is
             not filled with my call (WstxContact's hash table does not resolve it to my call) is
             another call. Holds (operator #93: "we pause counting ... till the called station
             finishes its other qso"): from then on, however long he is not decoded and also when
             he goes on with a further station, until he ends it: his RR73, RRR or 73 to another
             call, his CQ, his free text (a free text has no sender: it counts as his when decoded in
             his period within 10 Hz of his last decode; #97 coordinator default), or any message from him to my call (progress,
             AutoSequence); a new contact or the end of the contact clears it. Nothing but his own
             messages ends it, and the bound of TxWatchdog (N paused calls per message, #97 Q5)
             keeps it from extending a call without limit.
             When it counts: a send is paused when he is busy at its stop point, 1.2 s into its
             period (TxWatchdog): a publication that ends or starts it arriving before the stop
             point (1.1 s) counts for that send, one arriving after it (1.3 s) for the next.
             Split frequency ("check if we are not on his transmit frequency"; it applies to every
             contact that pauses, also while it is not pausing: an unattended run with busy_pause
             on, or a message whose N paused calls are used up): when he sends a decoded message to
             another call (any, busy or not; the trigger of partnerWorksOther, in replying and in a
             Tx1-skipped report) and my Tx signal is not clear of his signal, Tx moves before my next
             own period to the nearest candidate clear of it. Clear: my signal [f, f + width) keeps
             50 Hz from his [d, d + width): |f - d| at least width + 50, FT8 100 Hz, FT4 140 Hz
             (FT8 99 moves, 100 stays; FT4 139 moves, 140 stays). Candidates: WstxStrategy::FreeTxSlot's
             grid from 500 Hz inside the Tx range, clear of his signal and of decoded stations while
             one is free, at least 50 Hz from a frequency his PSK Reporter spots show him decoding in
             my Tx parity while one is free (else that is not used), the nearest to the current Tx,
             the lower on a tie; Rx stays on him. His decode arriving before the audio start of my
             next send moves the pending request (WstxQsoTransmit::TransmitSubmission replaces it); one
             arriving after the audio start lets that send finish where it is and moves the next. A
             refused move (set_frequency refused) falls back to the stop of partnerWorksOther (the
             transmit state off, cause partnerWorksOther), so Tx never stays on his signal. In
             manual operation this is the one automatic Tx move besides Hold Tx's rules, also with Hold Tx on (operator
             2026-11-09, #97 Q7 "yes, both"; an exception to CL-039-08); an explicit Tx action of the
             operator (also a click onto his signal) wins until his next message to another call,
             which moves it again. A contact that does not pause (a pounce, an MCP policy run, a run
             with busy_pause off) keeps partnerWorksOther's stop.
             Shown: the contact snapshot's watchdog carries busy_with (null, or the other call as
             decoded, at most 13 characters, "<...>" for an unresolved hash) and paused_calls (the
             paused calls of the message due next); GET /contact stays within its 4096 bytes in the
             maximum shape with a 13-character busy_with. The browser appends " · <call> busy with
             <other>, not counted (<k>/<N>)" to WD:n in the QSO pane and the station bar while
             busy_with is set (in a run's own contact the leave label carries it,
             WstxStrategy::LeaveCountLabel). busyPausedCallsMax is the default limit; the bound is
             the operator's current limitCalls. */
    }
    item def TransmitRequest {
        attribute contactId : String[0..1];
        attribute requestSequence : Integer;
        attribute mode : WstxModeProcessing::Mode;
        attribute periodStartUtcMs : Integer;
        attribute messageText : String;
        attribute txOffsetHz : Integer;
        doc /* A message of a contact to put on the air in a period. Which request
             transmit admits and how it goes on the air are transmit's (Admission and
             Transmission in the transmit part). */
    }
}
