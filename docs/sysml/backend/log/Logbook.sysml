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
    private import WstxModelNotes::FollowsSource;
    private import WstxModelNotes::DiffersFromSource;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

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
             The file is contacts.adi in the shack's folder: a header and one line
             for each record, in the order in which the records were added. Every
             station of the shack logs to it.
             A record is written as the fields of LogRecord from call to 'eqsl_qslrdate' in
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
             The record of the contact takes 'station_callsign' and 'my_gridsquare' from
             LogContext, band as the band that contains LogContext::dialHz, and freq
             as that dial plus the Tx offset of the contact; without a dial it has
             neither band nor freq. It has no 'tx_pwr', no 'comment', no
             'app_wstxrust_source' and no confirmation field. Its other fields are the
             FinishedContact's features, each by its wire name (WstxStationLink::WireNames).
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
        doc /* A finished contact is logged once, and the logbook is kept whole. */
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
             While LogContext::contestDupes is DupeRule::bandGrid, a contact whose grid
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
        doc /* The same station in a row is logged once. */
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
        doc /* What counts as the same station, and what is logged again. */
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
        doc /* The newest QSO after a restart, while a record waits, and from outside. */
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

    requirement 'CL-010-20' {
        subject log : LogService;
        doc /* The log MUST keep every decode and every sent message of the station as
             HeardFile says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-011'; end #derive ::> 'CL-010-20'; }

    attribute def HeardFile {
        doc /* The log appends one line for each ResultRecord of a live job and for each
             SentMessage to the file yyyy-MM-ALL.TXT of the month of the line's time in
             LogContext::stationFolder, made when it does not exist. A line is the time
             yyMMdd_hhmmss, the dial in MHz with three decimals right-aligned in 10
             characters and a space, Rx or Tx, a space, the mode left-aligned in 6
             characters, the SNR in 4, the DT with one decimal in 5, the audio frequency
             in Hz in 5, a space and the message. An Rx line has the period's start, the
             dial of LogContext::dialHz and the record's values; a Tx line has the
             period's start, the dial, SNR 0, DT 0.0 and the Tx offset. A line that cannot
             be written is lost, and nothing else waits for it. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: MainWindow::write_all, with "
                + "Split ALL.TXT monthly";
        }
    }

    requirement 'CL-010-21' {
        subject log : LogService;
        doc /* The log MUST answer WstxLogControl::ExportCabrillo with the records of a
             contest's period as a Cabrillo file as CabrilloExport says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-011'; end #derive ::> 'CL-010-21'; }

    attribute def CabrilloExport {
        doc /* An ExportCabrillo is answered by a Cabrillo 3.0 file in parts (ExportChunk):
             START-OF-LOG: 3.0; LOCATION, CONTEST (the contest's name in the Cabrillo
             format), CALLSIGN (the profile's callsign), the categories, CLAIMED-SCORE
             (ExportCabrillo::claimedScore, else empty), OPERATORS, CLUB, NAME and ADDRESS
             from LogShared::cabrillo; one line QSO: for each record whose start lies in
             the period and that carries the contest's id, in the order of the starts,
             with the frequency in kHz, DG, the date and time of the start, the station's
             call, the exchange sent, the call and the exchange received, as the contest's
             exchange names their fields; END-OF-LOG:. An unknown contest or a period
             whose end is not after its start is refused with invalidRequest. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: ExportCabrillo, "
                + "CabrilloLog::export_qsos";
        }
        attribute header : CabrilloHeader { doc /* LogShared::cabrillo. */ }
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
        doc /* The logbook is updated from another program's file and given out. */
        subject log : LogService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-010-18'; }
        @TestedBy {
            test = "server/src/logbook_tests.rs::"
                + "update_reads_a_log4om_shaped_export_keeps_only_log_fields_and_marks_the_source; "
                + "server/src/logbook_tests.rs::"
       + "update_consolidates_within_two_minutes_and_existing_records_win_and_repeat_adds_nothing; "
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
                + "server/src/logbook_tests.rs::"
         + "update_of_twenty_seven_thousand_qsos_is_consolidated_and_worked_before_uses_the_index; "
                + "server/src/logbook_tests.rs::"
                + "export_streams_the_log_in_bounded_chunks_from_a_snapshot_without_the_lock; "
                + "server/src/log/udp_tests.rs::"
                + "tc_011_002_update_logbook_adds_records_without_any_udp_datagram; "
                + "server/src/logbook_tests.rs::"
                + "history_pages_have_stable_indexes_and_stay_within_the_byte_bound; "
                + "server/src/logbook_tests.rs::"
                + "update_refuses_a_broken_tag_a_header_without_eoh_and_a_long_name_whole; "
                + "server/src/logbook_tests.rs::"
                + "an_update_whose_write_fails_stores_none_of_its_records; "
                + "server/src/logbook_http_tests.rs::"
                + "history_and_export_routes_follow_the_wire_contract";
        }
    }

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
             logbook, or those whose 'qso_date' lies from the first to the last date of
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
             A ContestPeriod is answered with the records whose start, from 'qso_date' and
             'time_on', lies in the period, as PeriodQsos. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: WorkedBefore and LogBook::match "
                + "with highlighting by mode off, which the scope of a band in any mode "
                + "follows";
        }
    }

    verification 'TC-011-003' {
        doc /* What has been worked, per call, grid, entity and prefix. */
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
