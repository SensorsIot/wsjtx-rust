package WstxLogbook {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-011';
    private import WstxLogPart::LogService;
    private import WstxLogControl::*;
    private import WstxOperatingChain::FinishedContact;
    private import WstxOperatingChain::LogAnswer;
    private import WstxOperatingChain::LoggedContact;
    private import WstxOperatingChain::WorkedSet;
    private import WstxOperatingChain::WorkedWindow;
    private import WstxOperatingChain::WorkedCategory;
    private import WstxOperatingChain::ContestPeriod;
    private import WstxOperatingChain::PeriodQsos;
    private import WstxStrategies::DupeRule;
    private import ModelNotes::FollowsSource;
    private import ModelNotes::DiffersFromSource;
    private import ModelNotes::NotStated;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    // ---- Logging a finished contact -------------------------------------------------------

    requirement 'CL-010-04' {
        subject log : LogService;
        doc /* Log MUST store every finished contact it is handed as one record of the
             profile's logbook, call it saved only when the record is durable, and keep a
             record it cannot store for a later attempt (Logbook, DirectLog,
             SaveContact). */
        @Status { build = ImplementationState::partial; }
        @ImplementedIn { module = "server/src/contact_http.rs"; }
    }
    #derivation connection { end #original ::> 'FR-011'; end #derive ::> 'CL-010-04'; }

    attribute def Logbook {
        doc /* The logbook of a profile and the file that holds it.
             The file is contacts.adi in the operator's folder: a header and one line
             for each record, in the order in which the records were added. Every
             station of the operator logs to it.
             A record is written as the fields of LogRecord from call to eqslQslrdate in
             the order of their declaration, then contactId, source and activity, then
             the fields LogRecord does not name, each with its name, type and value as
             it was read.
             The header names ADIF 3.1.8, the time the logbook was opened, and the
             program WSTXRUST with its version.
             The logbook holds one record for each contactId. A record is added at the
             end and keeps its index. A stored record is not changed and not removed;
             the one exception is a confirmation that UpdateLogbook adds to it.
             The log changes the file only while it holds the file's lock, which a
             log of another station waits for. A new record is appended to the end of
             the file and made durable; a change of a confirmation writes the whole
             file anew beside the old one, makes it durable and puts it in the old
             one's place in one step. A change that fails leaves the file and the
             logbook as they were, and no other file behind.
             Before the log uses the logbook (to store, to answer, to give a worked
             set, to export or to page), it takes in the records another station has
             added since it last read the file.
             At station start the file is read. A missing file is an empty logbook.
             A record of the file keeps UpdateLogbook's limits for a file, the contest
             fields apart, which are taken as they are. Only a confirmation field that
             is given twice or is outside those limits is kept as a field LogRecord
             does not name.
             The logbook is unavailable when the file cannot be read, when it is not a
             well-formed ADIF file, when a record has another fault, lacks one of CALL,
             QSO_DATE, TIME_ON and MODE, or has no contactId, and when two records
             share a contactId. An unavailable logbook refuses every command with
             LogRefusal::storageUnavailable and leaves the file as it is. */
        @FollowsSource {
            reference = "ADIF 3.1.8, the ADI file format; WSJT-X at the behaviour "
                + "baseline: AdifQso to_adif";
        }
        @DiffersFromSource {
            what = "WSJT-X writes GRIDSQUARE also when it is empty; the logbook writes "
                + "no field without a value.";
        }
    }

    attribute def DirectLog {
        doc /* What the log does with a FinishedContact. Each one is answered with one
             LogAnswer.
             The record of the contact takes stationCallsign and myGridsquare from
             LogContext, band as the band that contains LogContext::dialHz, and freqMHz
             as that dial plus the Tx offset of the contact; without a dial it has
             neither band nor freqMHz. It has no txPwr, no commentText, no source and no
             confirmation field.
             A contact that is the same station again is refused (SameStationAgain).
             A record outside what LogRecord allows is not stored
             (LogError::logInvalidField); its contact is answered accepted.
             Every other record waits to be stored, in the place of a waiting record of
             the same contact.
             A waiting record is stored at once, the oldest first. A contactId the
             logbook does not hold is added, and the record is given once as
             LoggedContact. A contactId it holds changes nothing: a stored record is
             not changed by a contact handed over again.
             When a record cannot be stored it waits, with those behind it
             (LogError::storageUnavailable), and the log tries again a few times
             within a short time, for a short blockage of the file. A record that
             still cannot be stored is given up: it is not in the logbook and is not
             given. How often and how long are values of the code.
             LogAttempt tells what became of the contact dealt with last. */
        @NotStated {
            what = "FinishedContact has no feature. The record needs from it: the "
                + "identity of the contact, the partner's call and grid, the mode, the "
                + "two reports, "
                + "start and end, the contest fields, the activity and the Tx offset.";
        }
    }

    attribute def SaveContact {
        doc /* What the log does with a SaveRecord.
             Without a callsign in LogContext it is refused
             (LogRefusal::profileIncomplete).
             A record outside what LogRecord allows is refused
             (LogRefusal::logInvalidField); LogRefused::field names a field that is
             outside.
             A contactId the logbook does not hold is added (SaveOutcome::saved), and
             the record is given once as LoggedContact.
             A contactId it holds is answered alreadySaved when the stored record has
             the same fields and none that LogRecord does not name, and conflict
             otherwise; nothing is written.
             A record that cannot be stored is refused
             (LogRefusal::storageUnavailable); the same record can be given again. */
    }

    requirement 'CL-010-19' {
        subject log : LogService;
        doc /* Log MUST give the newest record of the logbook again as LoggedContact when
             the operator asks for it (ResendRule). */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-011'; end #derive ::> 'CL-010-19'; }

    attribute def ResendRule {
        doc /* What the log does with a ResendLast: the operator's Log QSO, for a logging
             program that was not running when the QSO was logged.
             The newest record is the last record of the logbook, whatever wrote it.
             The log gives it as LoggedContact and answers Resent with its contactId;
             the logbook is not written. A logbook without a record gives nothing and
             answers Resent without a contactId. An unavailable logbook refuses the
             command with LogRefusal::storageUnavailable. */
    }

    verification 'TC-011-001' {
        doc /* A finished contact is logged once, and the logbook is kept whole.
             Setup: the station on a throw-away profile HB9BLA in JN47AA with a scripted
             clock, hand-written decodes and a listener for logged contacts; for (f) to
             (l) the log alone on a throw-away folder. No radio.
             (a) K1ABC in FN42, entered at 12:34:20 on 20261101; his R-09 and then
             his 73: nothing is stored before the 73; then one record with CALL K1ABC,
             GRIDSQUARE FN42, MODE FT8, RST_RCVD -09, QSO_DATE 20261101, TIME_ON 123420,
             TIME_OFF 123515, STATION_CALLSIGN HB9BLA, MY_GRIDSQUARE JN47AA and no
             RST_SENT, BAND or FREQ; it is given once; the attempt says saved.
             (b) His 73 once more after the profile's locator changed to JN46AA: the
             record is unchanged and nothing is given.
             (d) A third contact while the file cannot be written: the attempt says
             unsaved with storageUnavailable; with the fault gone nothing is stored
             before the next attempt is due; then the record is stored and given once.
             A logbook opened anew holds two records.
             (f) An FT4 contact with K1ABC in FN42, reports -12 and -09, from 12:34:45
             to 12:35:15, with the dial 14.080000 MHz, the Tx offset 1234 Hz and the
             locator JN47: MODE MFSK, SUBMODE FT4, BAND 20m, FREQ 14.081234,
             MY_GRIDSQUARE JN47; the record is within LogRecord.
             (g) A record of K1ABC saved: saved. A second record whose writing, making
             durable or putting in place fails: refused with storageUnavailable, the
             file byte for byte as before, no other file left. The second record
             again: saved; once more: alreadySaved; with TX_PWR 5 in place of 10:
             conflict. A record of another contact with K1ABC: saved. A logbook opened
             anew holds the three records.
             (h) A record K1ABC, FN42, FT8, -12, -05, 20261031 from 123015 to 123200,
             20m, 14.075500, HB9BLA, JN47AA, 10 W, "Tnx QSO": taken, also as MFSK with
             FT4, also without grid, reports, band, frequency, power and comment.
             Refused, each with its field: the call k1abc; the grid FN4; the mode SSB;
             FT8 with the submode FT4; the reports -51 and +50; the date 20260230; the
             start 1230; the end 123000; the band 21m; the frequencies 14.0755 and
             7.074000; the callsign HB9XYZ; the power -1; a comment with a line break,
             an empty one, one with "<" or ">" and one of 1025 characters, while 1024
             are taken; an identity that is no UUID; a profile without a locator.
             (i) The reports 559 and 579, STX 0001 and STATE MA: taken, and written as
             stx and state before the identity of the contact. The report 519,
             SRX_STRING "2A <WI>" and STX 00001: refused.
             (j) A record with a field APP_OTHER_NOTE of type M that holds a tab and a
             line break: written as one line in the order of Logbook, the field last
             with its type, and read back as it was.
             (k) A file with a header of free text, tags in upper and mixed case, type
             indicators, line breaks between fields and an empty GRIDSQUARE: two
             records, the grid absent, a field USERDEF1 kept. A file that is empty or
             only a header: no record. A file with a length that is too short or
             reaches beyond the end, a record without its end, a length that is no
             number, a call with a letter outside ASCII or a tab, the date 20261032,
             the time 1260, FREQ -1, a grid of five characters, a record without MODE,
             or a header without its end: refused. A stored record with QSL_RCVD Y,
             QSL_RCVD N and LOTW_QSL_RCVD "yes": read with qslRcvd Y and two fields
             LogRecord does not name.
             (l) contacts.adi that is a folder, and one that holds a call with a wrong
             length: every command is refused with storageUnavailable and the file is
             left as it is.
             (m) Planned, no test yet: a fault of the file that lasts beyond the tries
             again: the contact is given up, the logbook does not hold it, and it is
             not given.
             (n) Planned, no test yet: after (a), a ResendLast: the record of K1ABC is
             given once more, Resent names its contact, contacts.adi is byte for byte
             as before. On an empty logbook: nothing is given, Resent has no
             contactId. */
        subject log : LogService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-010-04'; verify 'CL-010-19'; }
        @TestedBy {
            test = "server/src/log/udp_tests.rs::"
                + "tc_011_001_a_completed_contact_logs_itself_once_and_reaches_the_udp_target; "
                + "server/src/contact_http_tests.rs::"
                + "direct_log_record_fields_from_the_confirmed_dial; "
                + "server/src/logbook_tests.rs::"
                + "save_is_exactly_once_and_injected_failures_leave_no_torn_file; "
                + "server/src/logbook_tests.rs::"
                + "review_validation_refuses_each_invalid_field_with_its_key; "
                + "server/src/logbook_tests.rs::contest_fields_and_rtty_rst_are_validated; "
                + "server/src/logbook_tests.rs::"
                + "adi_record_is_written_in_wsjtx_field_order_with_exact_lengths_and_round_trips; "
                + "server/src/logbook_tests.rs::"
                + "adi_parser_accepts_header_case_variants_and_line_breaks_between_fields; "
                + "server/src/logbook_tests.rs::"
                + "adi_parser_refuses_malformed_length_character_and_missing_fields_with_context; "
                + "server/src/logbook_tests.rs::"
                + "stored_log_with_former_verbatim_qsl_fields_stays_readable; "
                + "server/src/logbook_tests.rs::"
                + "unreadable_stored_log_is_unavailable_and_left_untouched; "
                + "server/src/logbook_tests.rs::"
                + "invalid_stored_log_is_unavailable_and_never_rewritten";
        }
    }

    // ---- The same station again -----------------------------------------------------------

    requirement 'CL-085-01' {
        subject log : LogService;
        doc /* Log MUST refuse a finished contact when the newest QSO of the logbook is
             with the same station on the same band and in the same mode
             (SameStationAgain). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/contact_http.rs"; }
    }
    #derivation connection { end #original ::> 'FR-011'; end #derive ::> 'CL-085-01'; }

    attribute def SameStationAgain {
        doc /* When a finished contact is the same station again.
             The newest QSO is the record that began to wait last, while one waits,
             and otherwise the last record of the logbook, whatever wrote it. A record
             of the contact itself is not the newest QSO.
             The contact is the same station again when its call equals the call of the
             newest QSO without regard to letter case, its effective band equals that
             record's, and its effective mode equals that record's. K1ABC/P is another
             station than K1ABC. An unknown band equals only an unknown band.
             While LogContext::contestDupes is DupeRule::band_grid, a contact whose grid
             and the grid of the newest QSO are both known and differ in their first
             four characters is not the same station again.
             A refused contact writes no record, changes no stored one and is not given
             as LoggedContact; its LogAttempt says LogError::sameStationAgain and its
             LogAnswer says refused.
             Time plays no part, and the newest QSO is read from the file after a
             station start.
             The rule holds for finished contacts only: a SaveRecord and an update of
             the logbook are stored as they are, and their records can be the newest
             QSO. */
        @DiffersFromSource {
            what = "WSJT-X at the behaviour baseline (LogBook::add) adds every logged "
                + "QSO without comparing it with the one before.";
        }
    }

    verification 'TC-085-001' {
        doc /* The same station in a row is logged once.
             Setup: the station on a throw-away profile HB9BLA with a scripted clock,
             hand-written decodes of K1ABC in FT8, a scripted transmitter and a
             listener for logged contacts; for (e) the station with Auto on. No radio.
             (a) A QSO with K1ABC from his CQ: one record, given once. His RR73 once
             more, answered: the new contact completes; contacts.adi is byte for byte
             as before, nothing is given, and the attempt names the new contact and
             K1ABC as unsaved with sameStationAgain.
             (b) A whole further QSO from his CQ, the third in a row: one record still,
             nothing given.
             (c) After QSOs with W1AW and K1ABC, my CQ answered by K1ABC with his grid
             and completed on his 73: no record, nothing given.
             (e) After a QSO by hand with K1ABC, Auto answers K1ABC calling and the QSO
             completes: no record, the attempt says sameStationAgain. */
        subject log : LogService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-085-01'; }
        @TestedBy {
            test = "server/src/contact_http_tests.rs::"
                + "tc_085_001_the_same_station_in_a_row_is_not_logged; "
                + "server/src/contact_http_tests.rs::"
                + "tc_085_001_log_qso_pending_records_and_restart; "
                + "server/src/contact_http_tests.rs::"
                + "tc_085_001_g_auto_answers_the_station_logged_last_and_nothing_is_logged";
        }
    }

    verification 'TC-085-002' {
        doc /* What counts as the same station, and what is logged again.
             Setup: for (a) to (e) records as the log writes them for a finished
             contact, compared by the rule alone; for (f) to (h) as TC-085-001.
             (a) After K1ABC on 14.074 MHz in FT8: K1ABC on 14.074 MHz in FT8 is the
             same station again; on 7.074 MHz it is not; in FT4 it is not; FT4 after
             FT4 is.
             (b) After a record with FREQ 14.074500 and no BAND: a QSO on 14.074 MHz
             is; after one with FREQ 7.074000 it is not.
             (c) After k1abc: K1ABC is. After K1ABC: K1ABC/P is not, and W1AW is not.
             (d) Both without a band: it is. One with a band and one without, either
             way round: it is not.
             (e) Under band_grid, after K1ABC/R on 50.313 MHz in FN42: from FN43 it is
             not; from FN42, from fn42ab and without a grid it is. Under band,
             band_mode_class and call: from FN43 it is. Under call on 14.074 MHz: it
             is not.
             (f) K1ABC, then W1AW, then K1ABC: three records, each given.
             (g) An empty logbook and a cancelled QSO with K1ABC: the QSO with K1ABC
             that follows is logged.
             (h) A second profile with an empty logbook logs K1ABC while the first
             profile's logbook ends with K1ABC. */
        subject log : LogService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-085-01'; }
        @TestedBy {
            test = "server/src/logbook_tests.rs::tc_085_002_terms_of_the_same_station_again; "
                + "server/src/contact_http_tests.rs::"
                + "tc_085_001_the_same_station_in_a_row_is_not_logged; "
                + "server/src/contact_http_tests.rs::"
                + "tc_085_001_log_qso_pending_records_and_restart; "
                + "server/src/contact_http_tests.rs::"
                + "tc_085_003_the_newest_record_whatever_wrote_it";
        }
    }

    verification 'TC-085-003' {
        doc /* The newest QSO after a restart, while a record waits, and from outside.
             Setup: as TC-085-001; for (c) and (d) a scripted radio with the dial
             7.074 MHz confirmed and a logbook written by hand.
             (a) K1ABC is logged and the station started anew: the next QSO with K1ABC
             is refused and the file is unchanged.
             (b) The record of W1AW waits after a store that failed; a second QSO with
             W1AW completes: refused. After the next attempt the logbook holds W1AW
             once, given once.
             (c) A logbook whose only record is K1ABC on 40m in FT8, written by another
             program: a QSO with K1ABC is refused and the file is unchanged.
             (d) An update of the logbook adds DL1ABC: the next QSO with K1ABC is
             logged, on 40m.
             (e) A record of K1ABC saved with SaveRecord right after a logged QSO with
             K1ABC: stored. */
        subject log : LogService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-085-01'; }
        @TestedBy {
            test = "server/src/contact_http_tests.rs::"
                + "tc_085_001_log_qso_pending_records_and_restart; "
                + "server/src/contact_http_tests.rs::"
                + "tc_085_003_the_newest_record_whatever_wrote_it";
        }
    }

    // ---- The logbook and other logging programs -------------------------------------------

    requirement 'CL-010-18' {
        subject log : LogService;
        doc /* Log MUST take the QSOs of another logging program's ADIF file into the
             logbook so that each QSO stands in it once, and give the logbook out, whole
             as an ADIF file and page by page (UpdateLogbook, ExportAdi,
             ContactHistory). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-011'; end #derive ::> 'CL-010-18'; }

    attribute def UpdateLogbook {
        doc /* How the logbook is updated from the file of another program.
             Receiving. One update is received at a time: a ReserveImport with another
             id is refused with busy while an update is being received and its
             reservation or last part came less than idleSeconds ago. The same id with
             the same size and SHA-256 is answered with the update as it stands and has
             no second effect;
             with other values it is refused with stateConflict. A part is taken when
             it begins where the last one ended; the part that completes the file ends
             the update. An ended update is kept, for ReadImport, until the next one is
             reserved or the station stops.
             The file. It is UTF-8; a byte order mark at its start is skipped. A file
             that does not begin with a tag has a header of any text and fields up to
             EOH. A tag is NAME:LENGTH or NAME:LENGTH:TYPE between "<" and ">", in
             either case; the length counts characters. A record ends with EOR. Between
             the fields of a record stands white space only. The PROGRAMID of the
             header names the program when it is 1 to 32 letters, digits and "-";
             otherwise the program is ADIF.
             A file is refused as a whole, and nothing of it is stored, when its
             SHA-256 is not the one reserved, which is checked first, and for each
             AdiError that concerns the file: bytes that are not UTF-8 and a control
             character outside a value; a broken tag, a missing EOH or EOR; a length
             beyond the end of the file; a name over
             LogLimits::fieldNameCharactersMax; more records than
             LogLimits::importRecordsMax. AdiFault names the record at which it was
             found.
             A record. Only the fields of LogRecord are taken; every other field is
             left out. A value is faulty when it is longer than
             LogLimits::fieldCharactersMax, holds a character that is not printable
             ASCII, is followed by other text than white space, or is outside the
             limits for a file. An empty value is an absent field.
             The limits for a file: CALL and STATION_CALLSIGN are 1 to 32 letters,
             digits and "/"; a grid is a Maidenhead locator of 2, 4, 6 or 8
             characters; MODE and SUBMODE are 1 to 32 letters, digits and "-"; a report
             has at most 16 characters; a date is a day of the calendar from 1930 on; a
             time is HHMM or HHMMSS; BAND is of the ADIF enumeration in either case;
             FREQ and TX_PWR are positive decimals; every other field is as LogRecord
             says.
             A record is skipped when CALL, QSO_DATE, TIME_ON or MODE is missing or
             faulty, or when a field of LogRecord occurs twice. Any other faulty field
             is dropped and its record is taken without it.
             Values are stored as they are written.
             A record is already present when its contactId is in the logbook or was
             added before it from this file, or when such a record has the same call
             without regard to letter case, the same effective band, the same effective
             mode, and a start at most consolidationSeconds from its own. A time
             without seconds starts at second 0.
             A present record stays as it is, but for its confirmation: for each of
             LoTW, QSL card and eQSL that the file's record confirms with Y or V and the
             present record does not, the present record takes the status and, where
             the file gives them, its date and its via. A confirmation is not taken
             away or lowered.
             Every other record is added at the end, in the order of the file, with a
             new contactId when it has none and with the file's program as source when
             it names none.
             The records added and the records whose confirmation changed are written
             in one change of the file; when that fails none is, and the update has
             failed.
             No record of an update is given as LoggedContact. */
        attribute idleSeconds : Integer = 60;
        attribute consolidationSeconds : Integer = 120;
        @FollowsSource { reference = "ADIF 3.1.8, the ADI file format"; }
    }

    attribute def ExportAdi {
        doc /* How the logbook is given out as a file.
             The export is the logbook as it is when asked for; a change made while
             the export runs is in the next one.
             It begins with a header as the logbook's file has it, with the time of
             the export, and holds every record as the file holds it.
             It is given in parts: the header with the first
             LogLimits::exportChunkRecords records, then that many records in each
             part. */
    }

    attribute def ContactHistory {
        doc /* How the logbook is read page by page.
             A page holds the records from ReadHistory::cursor on, in the order of the
             logbook: at most ReadHistory::limit, and fewer when the page would be
             larger than LogLimits::historyPageBytesMax, but one at least.
             A cursor at the number of records gives a page without a record.
             A cursor beyond it, and a limit outside its range, are refused
             (LogRefusal::outOfRange). */
    }

    verification 'TC-011-002' {
        doc /* The logbook is updated from another program's file and given out.
             Setup: the log alone on a throw-away folder with hand-written ADIF files;
             for (l) the station with a listener for logged contacts.
             (a) A file as Log4OM 2 writes it, with a byte order mark, lines of "#",
             PROGRAMID LOG4OM2, names and addresses outside ASCII, and K1ABC on 30m in
             FT8, DL1ABC on 20m in MFSK with FT4 and W1XYZ on 40m in SSB with LSB at
             0815: three added, none skipped, no field dropped; each is stored with the
             fields of LogRecord only, a new contactId and the source LOG4OM2. DL1ABC on
             20m in FT4 thirty seconds later: present. A file without PROGRAMID: the
             source ADIF.
             (b) The logbook holds K1ABC on 20m in FT8 from 12:30:15. A file with that
             QSO at 12:32:15; as k1abc at 12:28:15 with FREQ 14.075500 and the mode
             ft8; at 12:32:16; on 40m; in MFSK with FT4; at 1233; and a record with the
             stored contactId: three added and four present, the stored record byte for
             byte as before. The file again: none added, seven present, the logbook's
             file unchanged. The file with one QSO more: one added. An export given
             back as an update: none added.
             (c) Records without CALL, with QSO_DATE 20261032, with CALL twice, with a
             CALL outside ASCII and with text after CALL: six skipped, by
             missingRequiredField, invalidValue, malformed, unsupportedCharacter and
             lengthMismatch. A grid of five characters, FREQ -1, a comment outside
             ASCII and text after a grid: dropped, their records added. A value of
             1025 characters: nothing for a field LogRecord does not name, dropped for
             COMMENT, skipped for CALL. 33 records that each give another field twice:
             33 skipped, 16 reasons listed.
             (d) A length beyond the end, a file that ends within a record, a control
             character after a record and bytes that are not UTF-8: the update fails
             with lengthMismatch, malformed and unsupportedCharacter, record 1 for the
             first three, and the logbook's file is unchanged.
             (e) A value of 1024 characters and a name of 64: taken; 1025 and 65:
             fieldTooLong. 100000 records: taken; one more: tooManyRecords at record
             100000. A file of 67108864 bytes: taken; a reservation of one byte more
             and a part of 16385 bytes: refused.
             (f) A reservation given twice: the same update. With another size or
             SHA-256: stateConflict. Another id meanwhile: busy. A part that does not
             begin at the next byte: stateConflict. The whole file: completed; the
             reservation again: the same result; the part again: stateConflict. A file
             with another SHA-256 than reserved: failed with integrityMismatch. An
             update left for 61 s without a part: the next reservation is taken.
             (g) STX 12A, SRX 12345, a CONTEST_ID of 33 characters and SRX_STRING
             "2A <WI>": dropped with invalidValue, the record added with STATE MA. STX
             0001, SRX 7, a CONTEST_ID of 32 characters and CLASS 3A: kept.
             (h) LOTW_QSL_RCVD Y with 20250301, QSL_RCVD V with 20250402 by D and
             EQSL_QSL_RCVD n: kept as written, the record confirmed; QSL_SENT is not
             stored. LOTW_QSL_RCVD X, QSLRDATE 20251301 and QSL_RCVD_VIA Q: dropped,
             the record added and not confirmed. A page of the history shows no
             confirmation field; the export does, and given back it changes nothing.
             (i) A second file for QSOs that are present: N becomes V with its date; Y
             stays Y with its date against N; I adds nothing; R becomes Y with date and
             via B; a second record of one QSO adds eQSL Y; the station's own record
             takes LoTW Y with its date and keeps its grid, report and time; a QSO
             given twice is added once and its repeat confirms it: one added, six
             present, five confirmed. The file again: none confirmed, the logbook's
             file unchanged. A file that says N for a confirmed QSO: unchanged. The
             own record saved again: alreadySaved.
             (j) 27000 QSOs in a file of about 27 MB: 27000 added. The file again with
             every QSO confirmed: 27000 present and 27000 confirmed.
             (k) A logbook of 300 records exported: parts of 128, 128 and 44 records,
             the first beginning with the header; together they hold the records as
             the file does. A record saved while the export runs is stored and is in
             the next export, of 301 records.
             (l) An update that adds two QSOs: nothing is given as LoggedContact.
             (m) Twelve records whose comments of 1024 characters double in size on a
             page: a page with the limit 10 holds 1 to 9 records in at most 16384
             bytes and says more. The cursor 11: the record of index 11, no more. The
             cursor 12: no record. */
        subject log : LogService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-010-18'; }
        @TestedBy {
            test = "server/src/logbook_tests.rs::"
                + "update_reads_a_log4om_shaped_export_keeps_only_log_fields_and_marks_the_source; "
                + "server/src/logbook_tests.rs::update_consolidates_within_two_minutes_"
                + "and_existing_records_win_and_repeat_adds_nothing; "
                + "server/src/logbook_tests.rs::"
                + "update_skips_invalid_records_drops_invalid_fields_and_refuses_a_broken_file; "
                + "server/src/logbook_tests.rs::"
                + "adi_limits_admit_exact_maximum_and_refuse_one_over; "
                + "server/src/logbook_tests.rs::"
                + "import_of_exactly_sixty_four_mebibytes_is_admitted_and_published; "
                + "server/src/logbook_http_tests.rs::"
                + "adi_import_over_http_reserves_chunks_retries_and_fails_atomically; "
                + "server/src/logbook_tests.rs::"
                + "import_retry_by_id_and_sha256_has_no_second_effect_and_mismatch_is_refused; "
                + "server/src/logbook_tests.rs::"
                + "update_drops_contest_values_that_save_would_refuse_and_keeps_conforming_ones; "
                + "server/src/logbook_tests.rs::"
                + "update_keeps_each_confirmation_field_and_the_export_round_trips_them; "
                + "server/src/logbook_tests.rs::"
                + "update_rerun_upgrades_confirmations_of_present_records_and_never_removes_one; "
                + "server/src/logbook_tests.rs::update_of_twenty_seven_thousand_qsos_"
                + "is_consolidated_and_worked_before_uses_the_index; "
                + "server/src/logbook_tests.rs::"
                + "export_streams_the_log_in_bounded_chunks_from_a_snapshot_without_the_lock; "
                + "server/src/log/udp_tests.rs::"
                + "tc_011_002_update_logbook_adds_records_without_any_udp_datagram; "
                + "server/src/logbook_tests.rs::"
                + "history_pages_have_stable_indexes_and_stay_within_the_byte_bound";
        }
    }

    // ---- What has been worked -------------------------------------------------------------

    requirement 'CL-010-13' {
        subject log : LogService;
        doc /* Log MUST tell ranking, from the profile's logbook and the country file in
             use, what has been worked and what is confirmed (WorkedBeforeQuery). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-011'; end #derive ::> 'CL-010-13'; }

    attribute def WorkedBeforeQuery {
        doc /* How the log makes a WorkedSet and answers a ContestPeriod.
             A WorkedSet counts the records of its WorkedWindow: every record of the
             logbook, or those whose qsoDate lies from the first to the last date of
             the window, both included.
             A record counts for its keys of WorkedCategory ever; on its effective
             band, when it has one; and on that band in its effective mode. Bands
             compare in lower case and modes in upper case.
             A key is confirmed in a scope when a confirmed record counts for it
             there.
             WorkedStatus is told by the call without regard to letter case; a record
             without a band is never on this band.
             A WorkedSet follows the logbook and the country file: after a change of
             either a set is made anew. Ranking is given the set made last at once,
             and the set that holds the change when that is made.
             An unavailable logbook gives no set.
             A ContestPeriod is answered with the records whose start, from qsoDate and
             timeOn, lies in the period, as PeriodQsos. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: WorkedBefore and LogBook::match "
                + "with highlighting by mode off, which the scope of a band in any mode "
                + "follows";
        }
    }

    verification 'TC-011-003' {
        doc /* What has been worked, per call, grid, entity and prefix.
             Setup: the log alone on a throw-away folder with hand-written QSOs and the
             bundled country file.
             (a) The logbook holds K1ABC on 20m in FT8, W1XYZ on 40m in FT8 and DL1ABC
             with FREQ 14.080 in MFSK with FT4. For 20m and FT8: K1ABC and k1abc
             workedThisBandAndMode, W1XYZ and DL1ABC workedOtherBandOrMode, N0NEW
             notWorked. DL1ABC for 20M and FT4: workedThisBandAndMode. N0NEW saved on
             20m in FT8: workedThisBandAndMode. A QSO without a band, asked for an
             empty band: workedOtherBandOrMode.
             (b) DL1ABC on 20m in FT8 with LoTW Y, DL2XYZ on 40m in FT8 with LoTW N,
             DL3QRP on 40m in FT4 with QSL V, F1ABC on 20m in FT8. Germany: worked and
             confirmed ever, on 20m, on 40m, on 20m in FT8 and on 40m in FT4; worked and
             not confirmed on 40m in FT8; not worked on 15m. France: worked and not
             confirmed. Japan: not worked. After an update that confirms F1ABC:
             France confirmed on 20m in FT8.
             (c) DL1ABC in JO62 on 20m, K1ABC without a band, and a call without an
             entity on 40m. DL2XYZ on 20m: entity, continent and zones not new; on 40m:
             all four new on the band; without a band: none new. HB9BLA on 20m: the
             entity new ever and on the band, the others not. W1AW on 20m: all four
             new on the band only. JA1XYZ on 20m: all four new ever and on the band.
             dl1abc with jo62xx on 20m: call and grid not new; on 40m: both new on the
             band. A call and the grid AA00 that are not logged: both new. IT9ABC after
             a QSO with I1ABC: the entity new.
             (d) DL1ABC in JO62AB not confirmed, DL1XYZ in JO62 confirmed, K1ABC once
             without a grid and once in FN42 confirmed, F1ABC with the grid JN. dl1abc:
             worked, not confirmed. K1ABC: confirmed. G4ABC: not worked. JO62XX: worked
             and confirmed. IO91: not worked. The prefix of DL1QQQ: worked and
             confirmed; of DL2QQQ: not worked. K1ABC and F1ABC have a QSO without a
             grid; DL1ABC and G4ABC have none.
             (e) The prefixes N8 of N8BJQ, HG19 of HG19ABC, XE0 of XEFTJW, KH9 of
             N8BJQ/KH9 and of KH9/N8BJQ, PA0 of PA/N8BJQ, N3 of N8BJQ/3, N8 of N8BJQ/P.
             (f) DL1ABC on 20250101 and F1ABC on 20250103. The window 20250101 to
             20250102 holds DL1ABC only, the window 20250103 to 20250103 F1ABC only,
             no window both. After G1ABC is added on 20250104 the window 20250103 to
             20250110 holds it.
             (g) After a QSO is added, the set made before is given at once and the
             set that holds the QSO follows. A window not asked for before gives
             nothing at first and then its set.
             (h) Twenty country files given one after the other, each with another
             name for the entity of the logged TT1A: after each, that entity is not
             new for TT2B on 20m.
             (i) Planned, no test yet: the US state of a call, and the QSOs of a
             ContestPeriod. */
        subject log : LogService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-010-13'; }
        @TestedBy {
            test = "server/src/logbook_tests.rs::"
                + "worked_before_matches_call_case_insensitively_and_band_with_mode; "
                + "server/src/logbook_tests.rs::"
                + "update_reads_a_log4om_shaped_export_keeps_only_log_fields_and_marks_the_source; "
                + "server/src/logbook_tests.rs::"
                + "worked_set_reports_worked_and_confirmed_per_entity_band_and_mode; "
                + "server/src/dxcc_tests.rs::"
                + "tc_055_002_new_dxcc_band_continent_and_zone_against_the_log; "
                + "server/src/dxcc_tests.rs::"
                + "tc_039_030_worked_set_keeps_call_grid_prefix_standing_and_gridless_calls; "
                + "server/src/dxcc_tests.rs::tc_039_030_wpx_prefix_table; "
                + "server/src/logbook_tests.rs::"
                + "worked_window_reads_only_the_dated_records_and_is_cached_per_revision; "
                + "server/src/logbook_tests.rs::"
                + "worked_latest_returns_the_last_set_and_builds_off_the_caller; "
                + "server/src/dxcc_tests.rs::tc_055_002_worked_set_follows_each_uploaded_table";
        }
    }
}
