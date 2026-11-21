package WstxSpecialActivities {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-024';
    private import WstxQsoPart::QsoService;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    doc /* The special activities of WSJT-X in a contact: the contest exchanges, EU VHF, the
         Hound, and the contest serial. */

    attribute def ActivityRule {
        doc /* The activity in force is the activity of the contest in force
             (WstxStrategies::ContestActivity; none for a contest without one) while a
             contest is in force, otherwise the operator's (WstxQsoControl::QsoConfig). The
             exchange of fieldDay and rtty is always the operator's. A change of the
             activity in force renews the messages of the contact in progress and of the
             own CQ at once. Each activity has its CQ word after CQ: TEST for naVhf,
             euVhf and arrlDigi, WW for wwDigi, FD for fieldDay, RU for rtty. */
    }

    requirement 'CL-024-02' {
        subject qso : QsoService;
        doc /* qso MUST run a contact under naVhf, wwDigi and arrlDigi with the grid
             exchange of GridExchangeRule. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-024'; end #derive ::> 'CL-024-02'; }

    attribute def GridExchangeRule {
        doc /* The exchange is the grid: Tx2 "DX MY GRID", Tx3 "DX MY R GRID". A contest
             activity has no Tx1: a contact starts with Tx2. A received grid counts as a
             report and a received R and grid as an R-report
             (WstxStandardQso::SequenceRule). The contact is handed over with the grid and
             without reports. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: the special operations NA VHF, "
                + "WW Digi and ARRL Digi";
        }
    }

    requirement 'CL-024-03' {
        subject qso : QsoService;
        doc /* qso MUST run a contact under fieldDay and rtty with the exchanges of
             ContestExchange. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-024'; end #derive ::> 'CL-024-03'; }

    attribute def ContestExchange {
        doc /* fieldDay: the exchange is the transmitter count from 1 to 32 with the class A
             to F and the ARRL or RAC section, written in capitals with one space ("1A
             EMA"). rtty: the state or province, or DX or # for the serial, or a fixed
             serial from 0001 to 7999; the station sends "5n9" with n from its report and
             the multiplier or the serial (ContestSerialRule). Tx2 "DX MY exchange", Tx3 "DX
             MY R exchange". In FT4 rtty a selection within 3 s after a counted RR73 of the
             previous partner sends "TU; " before Tx3. An exchange outside its rule, an
             exchange with another activity, and a nonstandard call under fieldDay are
             refused (invalidExchange, invalidCall). A record of another family counts
             as no message of the contact. The received exchange is kept with the
             contact. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: ARRL Field Day and RTTY Roundup, "
                + "the section and exchange tables";
        }
    }

    attribute def ContestLogFields {
        doc /* What a handed-over contact carries of its exchange
             (WstxOperatingChain::FinishedContact): an exchange of a word and a serial gives
             stx or srx; fieldDay gives stxString, and for the received exchange
             contestId ARRL-FIELD-DAY, srxString, contestClass and arrlSect; rtty gives the
             5n9 as rstSent and rstRcvd, and usState of a received state or province; euVhf
             gives the four serial digits as stx and srx and the RS as rstSent and rstRcvd;
             any other exchange of more than one word stxString or srxString. */
    }

    requirement 'CL-099-02' {
        subject qso : QsoService;
        doc /* qso MUST run a contact under euVhf as EuVhfRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-024'; end #derive ::> 'CL-099-02'; }

    attribute def EuVhfRule {
        doc /* euVhf needs a profile locator of 6 characters (profileIncomplete) and a
             callsign of at most 11 (invalidCall); it takes no exchange (invalidExchange);
             the two calls of a contact together have at most 16 characters (invalidCall,
             also for the choice while such a contact is in progress). Tx6 and Tx1 carry the
             first four locator characters; Tx1 is sent. Tx2 "<DX> <MY> 5nSSSS LOCATOR6" and
             Tx3 "<DX> <MY> R 5nSSSS LOCATOR6" with n from the report and the serial of
             ContestSerialRule up to 2047 (outOfRange beyond). A message of the family
             counts only from the partner's hash to the profile's call's hash and only under
             euVhf; a record of it to the profile's call starts at Tx3 with its exchange
             and 6-character grid. An edited text follows WstxMessageChoice::MessageSet. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: the EU VHF Contest message";
        }
    }

    requirement 'CL-024-04' {
        subject qso : QsoService;
        doc /* qso MUST run the Hound exactly as WSJT-X, as HoundRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-024'; end #derive ::> 'CL-024-04'; }

    attribute def HoundRule {
        doc /* The Hound of WSJT-X, without automation: FT8 only (a
             change to FT4 ends it, hound with FT4 is stateConflict); it transmits in the
             second period with Hold Tx on and sends only Tx1 and Tx3; it calls no CQ
             (noContact). It selects a Fox record of :00 or :30 that is not another
             Hound's Tx3 (stateConflict); a multi-message record names no partner
             (rowNotStandard). Its Tx follows its own rules, not
             WstxHoldTx::TooCloseRule, the quiet space or the busy pause: Tx1 goes out at a
             random offset from 1000 to 2998 Hz when Tx is below 999 Hz; after the Fox's
             report, standard or inside a multi-message, Tx3 carries the SNR of the Fox's
             decode and goes on the Fox's frequency, a repeat 300 Hz above it (Fox at or
             below 600 Hz) or below it, a repeated report back on it. While Tune is on only
             the Fox's frequency is noted. The Fox's RR73 to the profile's call, standard or
             inside a multi-message, completes the contact. Auto does not run under it. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: HoundTransmissionPolicy "
                + "(planClassicTxStart, planFoxReportReply), mainwindow hound_reply";
        }
    }

    requirement 'CL-111-10' {
        subject qso : QsoService;
        doc /* qso MUST switch a Hound's transmission off at HoundLimits. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-024'; end #derive ::> 'CL-111-10'; }

    attribute def HoundLimits {
        doc /* While the Hound calls with Tx1, transmission goes off (cause txWatchdog)
             callingMs after the last accepted start; Reset does not restart it. After the
             Fox's report Tx3 stays due, and transmission goes off when replyPeriods
             periods pass without the Fox's RR73; a start ends that wait. The repetition
             limit returns the Hound to Tx1. */
        attribute callingMs : Integer = 300000;
        attribute replyPeriods : Integer = 11;
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: the Hound's reply timeout and its "
                + "calling limit";
        }
    }

    requirement 'CL-085-03' {
        subject qso : QsoService;
        doc /* qso MUST send the contest serial of ContestSerialRule. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-024'; end #derive ::> 'CL-085-03'; }

    attribute def ContestSerialRule {
        doc /* While a contest is in force the serial sent next is 1 plus the highest serial
             sent (stx) of the contest period's contacts in the log, also of those handed
             over and not yet stored, and 1 when there is none; a restart goes on from
             there. Without a contest it starts at 1 at station start. A
             contact counts once, at its first hand-over, and only when the log answers
             accepted; a refused contact leaves the serial, and the next partner gets the
             same. */
    }

    verification 'TC-024-005' {
        doc /* The grid-exchange activities. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-024-02'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
                + "ww_digi_answers_a_caller_grid_with_r_grid_and_logs_on_rr73; "
                + "server/src/contact_tests.rs::na_vhf_moves_to_rogers_on_r_grid; "
                + "server/src/contact_tests.rs::"
                + "arrl_digi_with_a_nonstandard_own_call_and_back_to_none; "
                + "server/src/contact_tests.rs::set_activity_regenerates_the_running_contact; "
                + "server/src/contact_http_tests.rs::"
                + "set_activity_reads_back_and_reaches_udp_status";
        }
    }

    verification 'TC-024-008' {
        doc /* Field Day and RTTY Roundup. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-024-03'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
                + "field_day_cq_answers_the_exchange_and_logs_the_contest_fields; "
                + "server/src/contact_tests.rs::"
                + "rtty_roundup_answers_cq_ru_with_tx2_and_logs_rst_stx_and_state; "
                + "server/src/contact_tests.rs::ft4_rtty_selection_right_after_rr73_prefixes_tu; "
                + "server/src/contact_tests.rs::"
                + "contest_exchanges_are_validated_and_rows_of_another_family_are_other; "
                + "server/src/contact_http_tests.rs::"
                + "contest_activity_with_its_exchange_reads_back_and_reaches_udp_status";
        }
    }

    verification 'TC-099-002' {
        doc /* EU VHF. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-099-02'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::tc_099_002_eu_vhf_run_and_reply_through_the_log; "
                + "server/src/contact_tests.rs::tc_099_002_eu_vhf_in_ft4; "
                + "server/src/contact_tests.rs::"
                + "tc_099_002_eu_vhf_messages_count_only_by_both_hashes_in_eu_vhf; "
                + "server/src/contact_tests.rs::tc_099_002_eu_vhf_refusals_change_nothing; "
                + "server/src/contact_tests.rs::"
                + "tc_099_002_eu_vhf_rows_are_selectable_and_edits_must_pack; "
                + "server/src/contact_tests.rs::"
                + "tc_099_002_eu_vhf_refuses_a_pair_of_calls_over_16_characters; "
                + "server/src/contact_tests.rs::"
                + "tc_099_002_eu_vhf_sends_the_first_six_locator_characters; "
                + "server/src/contact_http_tests.rs::"
                + "eu_vhf_reads_back_refuses_with_its_fields_and_reaches_udp_status";
        }
    }

    verification 'TC-024-011' {
        doc /* The Hound. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-024-04'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
                + "a_hound_calls_at_a_random_offset_and_answers_the_fox_report_on_its_frequency; "
                + "server/src/contact_tests.rs::"
                + "a_hound_answers_a_0_1_report_moves_300_hz_on_a_repeat_and_logs_the_0_1_rr73; "
                + "server/src/contact_tests.rs::"
                + "a_hound_refuses_wrong_period_rows_other_hounds_other_slots_and_ft4; "
                + "server/src/contact_tests.rs::"
                + "a_hound_ignores_rr73_of_other_stations_and_replies_nothing_while_tuning; "
                + "server/src/transmit_state_tests.rs::"
                + "tc_111_003_a_stale_safety_revision_prepares_nothing_and_a_hound_calls_no_cq";
        }
    }

    verification 'TC-024-012' {
        doc /* The Hound chosen at the station. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-024-04'; }
        @TestedBy {
            test = "server/src/contact_http_tests.rs::"
                + "hound_reads_back_reaches_udp_status_and_the_row_reader_keeps_0_1_fields";
        }
    }

    verification 'TC-024-014' {
        doc /* A Hound QSO with a scripted Fox over an audio loopback. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-024-04'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
                + "a_hound_works_a_scripted_fox_over_an_audio_loopback";
        }
    }

    verification 'TC-111-016' {
        doc /* The Hound's limits. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-111-10'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
                + "hound_reply_timeout_hound_watchdog_and_tx_watchdog; "
                + "server/src/transmit_state_tests.rs::"
                + "tc_111_016_the_hound_stops_300_s_after_its_last_start";
        }
    }

    verification 'TC-085-007' {
        doc /* The contest serial counts only for an accepted contact. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-085-03'; }
        @TestedBy {
            test = "server/src/contact_http_tests.rs::"
                + "tc_085_004_the_contest_serial_counts_only_on_accepted";
        }
    }
}
