package WstxLogControl {
    private import ScalarValues::*;
    private import WstxStrategies::DupeRule;
    private import ModelNotes::FollowsSource;
    private import ModelNotes::DiffersFromSource;

    doc /* What the supervisor gives the log function (what the profile and the radio
         say, the operator's log commands) and what the log answers and reports. */

    attribute def LogRecord {
        doc /* One QSO of the logbook, as its ADIF fields.
             The ADIF name of a feature is its name in upper case with an underscore
             before each inner capital (rstSent is RST_SENT). The exceptions are freqMHz
             (FREQ), commentText (COMMENT), contestClass (CLASS), usState (STATE),
             contactId (APP_WSTXRUST_CONTACT_ID), source (APP_WSTXRUST_SOURCE) and activity
             (APP_WSTXRUST_ACTIVITY).
             An absent feature is a field that is not written.
             Two records of one contact have the same fields when they agree in the
             features from call to usState; the confirmation fields, source and activity
             are not compared.
             The sentences on the features say what the log stores for a finished contact
             and for a saved record; a record taken from another program's file keeps
             what that file says, within the wider limits of the update. */
        @FollowsSource {
            reference = "ADIF 3.1.8: the fields and their enumerations; WSJT-X at the "
                + "behaviour baseline: AdifQso to_adif, the field set and its order";
        }
        @DiffersFromSource {
            what = "WSJT-X also writes NAME, OPERATOR, PROP_MODE, SAT_NAME, SAT_MODE and "
                + "FREQ_RX when it has them; the record has no such field.";
        }
        @DiffersFromSource {
            what = "WSJT-X takes \"<\" and \">\" out of a value and writes \"?\" for a "
                + "character outside printable ASCII; the log refuses such a value "
                + "and changes none.";
        }
        attribute contactId : String { doc /* The identity of the contact: a UUID. */ }
        attribute call : String {
            doc /* 3 to 13 characters of A to Z, 0 to 9 and "/", with at least one
                 digit. */ }
        attribute gridsquare : String[0..1] {
            doc /* A Maidenhead locator of 4 or 6 characters; absent when not known. */ }
        attribute mode : String {
            doc /* FT8, or MFSK for FT4. */ }
        attribute submode : String[0..1] {
            doc /* FT4 with the mode MFSK, absent with FT8. The effective mode of a
                 record is its submode when the mode is MFSK, otherwise its mode. */ }
        attribute rstSent : String[0..1] {
            doc /* A signed report of two digits from -50 to +49, an RST 5n9 with n from
                 2 to 9, or an RS from 52 to 59. */ }
        attribute rstRcvd : String[0..1] { doc /* As rstSent. */ }
        attribute qsoDate : String { doc /* The UTC date of the start, YYYYMMDD. */ }
        attribute timeOn : String { doc /* The UTC time of the start, HHMMSS. */ }
        attribute qsoDateOff : String { doc /* The UTC date of the end. */ }
        attribute timeOff : String {
            doc /* The UTC time of the end; the end is not before the start. */ }
        attribute band : String[0..1] {
            doc /* A band of the ADIF enumeration, in lower case. The effective band of a
                 record is its band, without one the band that contains freqMHz, and
                 otherwise unknown. */ }
        attribute freqMHz : String[0..1] {
            doc /* The frequency in MHz with six decimals; it lies in the band. */ }
        attribute stationCallsign : String { doc /* The profile's callsign. */ }
        attribute myGridsquare : String[0..1] {
            doc /* The profile's locator; absent when the profile has none. */ }
        attribute txPwr : String[0..1] {
            doc /* Watts: a positive decimal of at most 16 characters. */ }
        attribute commentText : String[0..1] {
            doc /* One line of 1 to LogLimits::fieldCharactersMax printable ASCII
                 characters without "<" and ">". */ }
        attribute stx : String[0..1] { doc /* The serial sent: 1 to 4 digits. */ }
        attribute stxString : String[0..1] {
            doc /* This and the other contest texts: 1 to 32 printable ASCII characters
                 without "<" and ">". */ }
        attribute srx : String[0..1] { doc /* The serial received: 1 to 4 digits. */ }
        attribute contestId : String[0..1];
        attribute srxString : String[0..1];
        attribute contestClass : String[0..1];
        attribute arrlSect : String[0..1];
        attribute usState : String[0..1];
        attribute lotwQslRcvd : String[0..1] {
            doc /* This, qslRcvd and eqslQslRcvd: a value of the ADIF enumeration QSL Rcvd
                 (Y, N, R, I, V), in either case. A record is confirmed when one of the
                 three is Y or V. */ }
        attribute lotwQslrdate : String[0..1] { doc /* A date, as the other two dates. */ }
        attribute qslRcvd : String[0..1];
        attribute qslrdate : String[0..1];
        attribute qslRcvdVia : String[0..1] {
            doc /* A value of the ADIF enumeration QSL Via (B, D, E, M). */ }
        attribute eqslQslRcvd : String[0..1];
        attribute eqslQslrdate : String[0..1];
        attribute source : String[0..1] {
            doc /* The program a record taken from a file came from: 1 to 32 letters,
                 digits and "-". Absent on the station's own records. */ }
        attribute activity : String[0..1] {
            doc /* The special activity of the contact when it was logged: fieldDay,
                 rtty, euVhf, naVhf, wwDigi, arrlDigi or hound; absent for none. */ }
    }
    attribute def LogLimits {
        doc /* The limits of the log. A value at a limit is taken, one over is refused. */
        attribute importBytesMax : Integer = 67108864 {
            doc /* The largest file of an update. */ }
        attribute importRecordsMax : Integer = 100000 {
            doc /* The most records in the file of an update. The logbook itself has no
                 such limit. */ }
        attribute importChunkBytesMax : Integer = 16384 {
            doc /* The largest part in which the file of an update is given. */ }
        attribute fieldCharactersMax : Integer = 1024 {
            doc /* The longest value of a field. */ }
        attribute fieldNameCharactersMax : Integer = 64 {
            doc /* The longest name of a field. */ }
        attribute historyPageRecordsMax : Integer = 10 {
            doc /* The most records in one page of the history. */ }
        attribute historyPageBytesMax : Integer = 16384 {
            doc /* The size of a page of the history as the station link sends it. */ }
        attribute exportChunkRecords : Integer = 128 {
            doc /* The records in one part of an export. */ }
    }

    item def LogContext {
        doc /* What the log needs to know of the station, given at station start and
             whenever one of the values changes. */
        attribute callsign : String[0..1] {
            doc /* The profile's callsign in upper case; absent while the profile has
                 none. */ }
        attribute locator : String[0..1] {
            doc /* The profile's locator in upper case; absent while it has none. */ }
        attribute dialHz : Integer[0..1] {
            doc /* The dial frequency of the radio; absent while radio control has not
                 confirmed one. */ }
        attribute contestDupes : DupeRule[0..1] {
            doc /* The dupe rule of the contest in force; absent while the active
                 strategy is not a contest strategy. */ }
        attribute folder : String {
            doc /* The shack's folder (WstxProfileAccess::ProfileFolder,
                 its shackPath), in which the log keeps the logbook and the operator's
                 country file, shared by the shack's stations. */ }
        attribute stationFolder : String {
            doc /* The profile's folder (WstxProfileAccess::ProfileFolder::path), in
                 which the log keeps the station's heard files (HeardFile). */ }
        attribute shared : LogShared { doc /* The log's part of the shack's settings. */ }
    }
    attribute def CabrilloHeader {
        doc /* What the operator states once for a Cabrillo log, as WSJT-X's Export
             Cabrillo asks it. Each is a text of at most 70 printable ASCII characters,
             empty when not stated. */
        attribute location : String = "";
        attribute categoryOperator : String = "";
        attribute categoryTransmitter : String = "";
        attribute categoryPower : String = "";
        attribute categoryAssisted : String = "";
        attribute categoryBand : String = "";
        attribute operators : String = "";
        attribute club : String = "";
        attribute name : String = "";
        attribute address : String[0..2] ordered;
    }
    attribute def LogShared {
        doc /* The log's part of the shack's settings (WstxProfileAccess::ShackSettings). */
        attribute cabrillo : CabrilloHeader;
    }
    item def SentMessage {
        doc /* A message that went on the air. The supervisor gives it when transmit
             reports the start of a transmission (WstxTransmitControl::TransmitStatus). */
        attribute periodStartUtcMs : Integer;
        attribute mode : WstxModeProcessing::Mode;
        attribute txOffsetHz : Integer;
        attribute text : String;
    }
    item def ExportCabrillo {
        doc /* Give the records of a contest's period as a Cabrillo file
             (WstxLogbook::CabrilloExport). Answered by ExportChunk, as many as the file
             needs, or by LogRefused. */
        attribute contestId : String { doc /* A contest of WstxStrategies::ContestTable. */ }
        attribute startUtc : String { doc /* The start of the period, YYYY-MM-DDTHH:MMZ. */ }
        attribute endUtc : String { doc /* The end of the period, YYYY-MM-DDTHH:MMZ. */ }
        attribute claimedScore : Integer[0..1] {
            doc /* The score ranking counts for the period, when it has one. */ }
    }
    item def SaveRecord {
        doc /* Store this record. Answered by SaveAnswer or LogRefused. */
        attribute record : LogRecord;
    }
    item def ReserveImport {
        doc /* Begin an update of the logbook from a file. Answered by ImportView or
             LogRefused. */
        attribute importId : String { doc /* A UUID the caller chooses. */ }
        attribute totalBytes : Integer { doc /* 1 to LogLimits::importBytesMax. */ }
        attribute sha256 : String {
            doc /* The SHA-256 of the file: 64 hexadecimal digits in lower case. */ }
    }
    item def ImportChunk {
        doc /* The next part of the file. Answered by ImportView or LogRefused. */
        attribute importId : String;
        attribute startByte : Integer { doc /* Where the part begins in the file. */ }
        attribute totalBytes : Integer;
        attribute bytes : String {
            doc /* 1 to LogLimits::importChunkBytesMax bytes of the file. */ }
    }
    item def ReadImport {
        doc /* Read the update of this id. Answered by ImportView or LogRefused. */
        attribute importId : String;
    }
    item def ExportLog {
        doc /* Give the whole logbook as an ADIF file. Answered by ExportChunk, as many
             as the logbook needs, or by LogRefused. */
    }
    item def ReadHistory {
        doc /* Read a page of the logbook. Answered by HistoryPage or LogRefused. */
        attribute cursor : Integer {
            doc /* The index of the first record wanted: 0 to the number of records. */ }
        attribute limit : Integer {
            doc /* 1 to LogLimits::historyPageRecordsMax. */ }
    }
    item def ReadCountryFile {
        doc /* Read which country file is in use. Answered by CountryFileState. */
    }
    item def ReplaceCountryFile {
        doc /* Use this country file. The supervisor gives it at station start and
             whenever the profile's file changes. Answered by CountryFileState. */
        attribute text : String[0..1] {
            doc /* The country file the settings function keeps
                 (WstxProfileAccess::DefinitionsSnapshot::countryFile); absent: the bundled
                 file. */ }
    }
    item def EntityRequest {
        doc /* Resolve this call to its entity. Answered by EntityAnswer. */
        attribute call : String;
    }
    item def ResendLast {
        doc /* Give the newest record of the logbook again to the programs that are told
             of logged QSOs: the operator's Log QSO. Answered by Resent or LogRefused. */
    }

    enum def SaveOutcome {
        doc /* saved: the record is stored.
             alreadySaved: a record of this contact with the same fields is stored;
             nothing was written.
             conflict: a record of this contact with other fields is stored; nothing was
             written. */
        enum saved;
        enum alreadySaved;
        enum conflict;
    }
    item def SaveAnswer {
        attribute contactId : String;
        attribute outcome : SaveOutcome;
    }
    item def Resent {
        doc /* The answer to a ResendLast. */
        attribute contactId : String[0..1] {
            doc /* The contact of the record given again; absent when the logbook holds
                 no record. */ }
    }
    enum def LogRefusal {
        doc /* Why a command is refused. A refused command changes nothing.
             storageUnavailable: the file cannot be read or written.
             profileIncomplete: the profile has no callsign.
             logInvalidField: a field of the record is outside what LogRecord allows.
             stateConflict: the id is in use with other values, or the part is not the
             next one of an update that is being received.
             busy: another update is being received.
             notFound: no update of this id.
             invalidRequest: a part reaches beyond the end of the file.
             tooLarge: the file of an update, or a part of it, is over its limit.
             importFailed: the file is refused as a whole; ImportView::error says why.
             outOfRange: a number of the command is outside its range. */
        enum storageUnavailable;
        enum profileIncomplete;
        enum logInvalidField;
        enum stateConflict;
        enum busy;
        enum notFound;
        enum invalidRequest;
        enum tooLarge;
        enum importFailed;
        enum outOfRange;
    }
    item def LogRefused {
        attribute reason : LogRefusal;
        attribute field : String[0..1] {
            doc /* The field refused, for logInvalidField, profileIncomplete and
                 outOfRange. */ }
    }
    enum def ImportState {
        enum receiving;
        enum completed;
        enum failed;
    }
    enum def AdiError {
        doc /* What is wrong with a file, a record or a field.
             malformed: a broken tag, a missing end of header or of record, or a field
             given twice.
             lengthMismatch: a length that reaches beyond the file, or text after a
             value.
             unsupportedCharacter: bytes that are not UTF-8, a control character other
             than tab, carriage return and line feed, or a value that is not printable
             ASCII.
             fieldTooLong: a name or a value over its limit.
             tooManyRecords: more records than LogLimits::importRecordsMax.
             missingRequiredField: no CALL, QSO_DATE, TIME_ON or MODE.
             invalidValue: a value outside what its field allows.
             integrityMismatch: the bytes received do not have the SHA-256 reserved. */
        enum malformed;
        enum lengthMismatch;
        enum unsupportedCharacter;
        enum fieldTooLong;
        enum tooManyRecords;
        enum missingRequiredField;
        enum invalidValue;
        enum integrityMismatch;
    }
    attribute def AdiFault {
        doc /* Why a file is refused as a whole. */
        attribute code : AdiError;
        attribute recordIndex : Integer[0..1] {
            doc /* The record at which it was found, counted from 0; absent when it
                 concerns the whole file. */ }
        attribute field : String[0..1] {
            doc /* The name of the field in lower case; absent when none is meant. */ }
    }
    attribute def ReasonGroup {
        doc /* Records skipped, or fields dropped, for one reason. */
        attribute code : AdiError;
        attribute field : String;
        attribute count : Integer;
        attribute firstRecordIndex : Integer;
    }
    item def ImportView {
        doc /* One update of the logbook, while it is received and after it ended. */
        attribute importId : String;
        attribute importState : ImportState;
        attribute receivedBytes : Integer;
        attribute totalBytes : Integer;
        attribute added : Integer { doc /* The records added. */ }
        attribute present : Integer { doc /* The records that were already there. */ }
        attribute confirmed : Integer {
            doc /* The present records that took a confirmation from the file. */ }
        attribute skipped : Integer { doc /* The records left out. */ }
        attribute reasons : ReasonGroup[0..16] ordered {
            doc /* Why records were skipped, in the order of first occurrence. Reasons
                 beyond the sixteenth are not listed; skipped counts every record. */ }
        attribute dropped : ReasonGroup[0..16] ordered {
            doc /* The fields left out of records that were added or present. */ }
        attribute error : AdiFault[0..1] { doc /* Present in the state failed. */ }
    }
    item def ExportChunk {
        doc /* A part of the exported file. The parts come in the order of the file. */
        attribute text : String;
    }
    attribute def HistoryEntry {
        attribute index : Integer {
            doc /* The place of the record in the logbook, from 0. A record keeps its
                 index. */ }
        attribute record : LogRecord {
            doc /* Without the seven confirmation fields and without source and
                 activity. */ }
        attribute unknownFieldCount : Integer {
            doc /* The fields of the stored record that LogRecord does not name. */ }
    }
    item def HistoryPage {
        attribute total : Integer { doc /* The records in the logbook. */ }
        attribute cursor : Integer;
        attribute next : Integer { doc /* The cursor of the page after this one. */ }
        attribute more : Boolean { doc /* Whether next is below total. */ }
        attribute records : HistoryEntry[0..*] ordered;
    }
    enum def CountryFileSource {
        enum bundled;
        enum downloaded;
    }
    item def CountryFileState {
        doc /* The country file in use. */
        attribute source : CountryFileSource;
        attribute version : String[0..1] {
            doc /* The version entry of the file, VER and eight digits of a date; absent
                 when the file has none. */ }
        attribute entities : Integer { doc /* The number of entities. */ }
        attribute entityNames : String[1..*] {
            doc /* The names of the entities, as the file writes them. */ }
    }
    enum def Continent {
        enum AF;
        enum AN;
        enum AS;
        enum EU;
        enum NA;
        enum OC;
        enum SA;
    }
    attribute def CallEntity {
        doc /* The entity a call resolves to, with what the matching entry of the country
             file says for this call. */
        attribute name : String { doc /* The name as the country file writes it. */ }
        attribute shownName : String {
            doc /* The name for a display: 1 to 40 printable ASCII characters. */ }
        attribute primaryPrefix : String;
        attribute continent : Continent;
        attribute cqZone : Integer { doc /* 0 to 40. */ }
        attribute ituZone : Integer { doc /* 0 to 90. */ }
        attribute latitude : Real { doc /* Degrees, positive north. */ }
        attribute longitude : Real { doc /* Degrees, positive east. */ }
    }
    enum def WorkedStatus {
        doc /* A call against the logbook, for one band and one mode.
             notWorked: no QSO with the call.
             workedThisBandAndMode: a QSO with the call on this band in this mode.
             workedOtherBandOrMode: QSOs with the call, none of them so. */
        enum notWorked;
        enum workedOtherBandOrMode;
        enum workedThisBandAndMode;
    }
    item def EntityAnswer {
        attribute entity : CallEntity[0..1] {
            doc /* Absent when the call has no entity. */ }
    }
    enum def LogError {
        doc /* Why the latest finished contact is not saved.
             storageUnavailable: the record could not be stored; the log tries again
             for a short time and then gives it up.
             logInvalidField: the record is outside what LogRecord allows.
             sameStationAgain: the contact was refused. */
        enum storageUnavailable;
        enum logInvalidField;
        enum sameStationAgain;
    }
    item def LogAttempt {
        doc /* What became of the finished contact the log dealt with last. Absent until
             the first one. */
        attribute contactId : String;
        attribute call : String;
        attribute saved : Boolean;
        attribute error : LogError[0..1] { doc /* Absent when saved. */ }
    }

    port def LogControlPort {
        doc /* Written from the supervisor's side; the log uses the conjugate.
             A command and its answer are one exchange: the answer goes to the one
             command it belongs to. */
        out item context : LogContext;
        out item save : SaveRecord;
        out item reserve : ReserveImport;
        out item chunk : ImportChunk;
        out item readImport : ReadImport;
        out item export : ExportLog;
        out item exportCabrillo : ExportCabrillo;
        out item sent : SentMessage;
        out item readHistory : ReadHistory;
        out item readCountryFile : ReadCountryFile;
        out item replaceCountryFile : ReplaceCountryFile;
        out item lookUp : EntityRequest;
        out item resend : ResendLast;
        in item saveAnswer : SaveAnswer;
        in item resent : Resent;
        in item importView : ImportView;
        in item exported : ExportChunk;
        in item history : HistoryPage;
        in item countryFile : CountryFileState;
        in item entity : EntityAnswer;
        in item refused : LogRefused;
        in item attempt : LogAttempt;
    }
    interface def LogControl {
        doc /* The supervisor commands the log function; the log answers and
             reports what became of the latest finished contact. */
        end station : LogControlPort;
        end log : ~LogControlPort;
    }
}
