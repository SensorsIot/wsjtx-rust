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
    private import WstxModelNotes::FollowsSource;
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
        doc /* Written from auto's side; qso uses the conjugate. A CallTarget of the kinds
             reply, callCq and sendNext is answered by a StartAnswer. QsoProgress is
             given for a contact or a CQ Auto started, whenever one of its values
             changes. */
        out item target : CallTarget;
        in item answer : StartAnswer;
        in item progress : QsoProgress;
    }
    enum def TargetKind {
        doc /* What Auto asks of qso. reply, callCq and sendNext are the starts of
             those names that the operator has, carried out with the cause auto: reply
             calls the station of a record, callCq calls CQ, sendNext sends the message
             due of a started QSO; qso takes each one's Tx offset from its quiet space.
             move asks qso for a new Tx offset of Auto's contact or CQ, from the same
             space. cancel ends Auto's contact or CQ. */
        enum reply;
        enum callCq;
        enum sendNext;
        enum move;
        enum cancel;
    }
    item def CallTarget {
        doc /* A start, a move or an end of Auto's contact or CQ. */
        attribute kind : TargetKind;
        attribute sequence : Integer[0..1] {
            doc /* With reply: the record of the station to call. Rx goes onto it. */ }
    }
    item def StartAnswer {
        attribute blockedBy : TransmitRefusal[0..1];
        doc /* The answer to a start: absent when the start will happen, otherwise the arm
             condition that blocks it, one of clockNotSynchronized, busy by Tune,
             radioUnavailable and transmitUnsupported. A blocked start prepares no
             contact, counts no repetition and sets no message. */
    }
    interface def TargetChoice {
        doc /* What Auto asks of qso, from auto to qso, and what qso answers. */
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
    item def FinishedContact {
        doc /* A completed contact that qso hands to the log (WstxStandardQso::HandOverRule).
             Its values have the form of the LogRecord features of the same name. */
        attribute contactId : String;
        attribute call : String;
        attribute gridsquare : String[0..1];
        attribute mode : WstxModeProcessing::Mode;
        attribute rstSent : String[0..1] {
            doc /* The report of the last sent Tx2 or Tx3; for rtty the 5n9 and for
                 euVhf the RS of the exchange sent (WstxSpecialActivities::ContestLogFields). */ }
        attribute rstRcvd : String[0..1] { doc /* The same of the partner. */ }
        attribute startUtcMs : Integer { doc /* WstxStandardQso::LogTimes. */ }
        attribute endUtcMs : Integer { doc /* WstxStandardQso::LogTimes. */ }
        attribute txHz : Integer { doc /* The Tx offset of the contact. */ }
        attribute activity : WstxQsoControl::Activity;
        attribute stx : String[0..1] { doc /* WstxSpecialActivities::ContestLogFields. */ }
        attribute stxString : String[0..1];
        attribute srx : String[0..1];
        attribute srxString : String[0..1];
        attribute contestId : String[0..1];
        attribute contestClass : String[0..1];
        attribute arrlSect : String[0..1];
        attribute usState : String[0..1];
    }
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
        doc /* A finished contact, and the log's answer (WstxStandardQso::HandOverRule). */
        end producer : CompletedContactPort;
        end consumer : ~CompletedContactPort;
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

    attribute def BusyPartner {
        doc /* When the partner of a contact is in another QSO. It starts with a decoded
             standard message from the partner (the contact's DX call) to another call
             that carries a grid, a report or an R-report; a hashed call that is not
             filled with the profile's call is another call. It holds, however long he is
             not decoded and also when he goes on with a further station, until he ends it:
             his RR73, RRR or 73 to another call, his CQ, his free text, or any message from
             him to the profile's call. A free text has no sender: it counts as his when it
             is decoded in his period within freeTextHz of his last decode. A new contact
             or the end of the contact clears it. The other call is given as decoded, at
             most 13 characters, <...> for an unresolved hash. */
        attribute freeTextHz : Integer = 10;
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
