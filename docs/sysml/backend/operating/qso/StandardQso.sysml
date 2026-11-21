package WstxStandardQso {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-007';
    private import WstxQsoPart::QsoService;
    private import WstxOperatingChain::BusyPartner;
    private import WstxMessageChoice::'CL-010-12';
    private import WstxHoldTx::'CL-010-11';
    private import WstxModelNotes::FollowsSource;
    private import WstxModelNotes::DiffersFromSource;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    doc /* The standard contact: how it is prepared, how it goes on message by message, how
         it ends and how it reaches the log. */

    requirement 'CL-010-01' {
        subject qso : QsoService;
        doc /* qso MUST prepare a contact as PrepareRule says, and never switch transmission
             on by a preparation. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-010-01'; }

    attribute def PrepareRule {
        doc /* SelectRow prepares a contact from a decoded record of the live job that
             names a partner: a standard message, or one of an activity
             (WstxSpecialActivities), whose sender is resolved; EnterDx from an entered
             call and grid whose messages modes packs (WstxModeProcessing::PackAnswer;
             WstxMessageChoice::NonstandardRule). The
             contact gets an identity, the partner's call, his grid (from a record of
             him the known grid stays; an entry sets exactly the grid entered), the report
             from the record's SNR rounded into ReportRange (an entry keeps the current
             report), Rx on the record's frequency and Tx by WstxHoldTx::HoldTxRule, the
             parity opposite to the record's period, the station's mode, the six messages
             (WstxMessageChoice::MessageSet) and the message due by FirstSlot.
             FirstSlot: a record not to the profile's call gives Tx1 (Tx2 with Tx1
             skipped); to the profile's call his grid gives Tx2, his report Tx3, his
             R-report Tx4, his RRR, RR73 or 73 Tx5.
             A record of the current partner keeps the contact: its identity, its dialogue,
             its Tx4 form, each text already sent and, once a Tx2 or Tx3 was sent, the
             report; the state and the message due come from the record.
             A contact in progress is replaced only with replace (ReplaceRule); otherwise
             the command is refused contactActive. A profile without callsign or locator
             is profileIncomplete; a record without a partner rowNotStandard. A station
             that cannot transmit prepares contacts as any. */
    }

    requirement 'CL-010-02' {
        subject qso : QsoService;
        doc /* qso MUST take a contact on message by message as SequenceRule says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-010-02'; }

    attribute def SequenceRule {
        doc /* A partner message counts when it is to the profile's call, from the partner,
             decoded in his parity in the contact's mode, and not counted before (one per
             decoded record; a second decode of the period is the same message). Messages
             of other stations, of the station's own parity, of another mode and anything
             after completed or cancelled change nothing.
             While Auto Seq is on and transmission is on, a counted message sets the state
             and the message due, in every state from replying to signoff:
             his grid: report, Tx2; his report: rogerReport, Tx3; his R-report: rogers,
             Tx4; his RRR or RR73: signoff, Tx5; his 73 in rogerReport: signoff, Tx5; his
             73 in rogers: completed, nothing more is sent. Every other message changes
             nothing.
             While Auto Seq is off, or transmission is off, a counted message changes
             neither state nor message due and completes nothing: its report, its place in
             the dialogue and the end of the contact are recorded, and the message the
             sequence would choose is offered (QsoContact::suggestedSlot) until a message is
             chosen. The contact goes on by a start (WstxQsoTransmit::StartRule).
             A message due that changes before the audio of the next transmission starts
             is the one sent; one counted after it is sent in the next own period.
             The contact completes at the completed outcome of a Tx5 sent in signoff, of
             a Tx4 RR73 sent in rogers, or at his 73 in rogers; then transmission goes off
             with the cause contactCompleted and the contact is handed over (HandOverRule).
             A transmission halted, aborted or refused completes nothing. */
        @FollowsSource {
            reference = "WSJT-X v3.3.0-beta6, commit 7255454: DecodedMessageReaction "
                + "planProcessMessage and planAutoSequence";
        }
        @DiffersFromSource {
            what = "SequenceRule follows WSJT-X v3.3.0-beta6, not the release of the "
                + "behaviour baseline.";
        }
        @DiffersFromSource {
            what = "WSJT-X answers a 73 in roger_report with Tx3 again; the station sends one "
                + "73 and completes.";
        }
        @DiffersFromSource {
            what = "WSJT-X logs at the start of its first 73; the station completes at the "
                + "completed outcome of the 73, and a message counted before it keeps the "
                + "contact going.";
        }
    }

    requirement 'CL-109-01' {
        subject qso : QsoService;
        doc /* qso MUST take a completed contact up again when a message is chosen for it
             (ReopenRule). */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-109-01'; }

    attribute def ReopenRule {
        doc /* ChooseNext of Tx1 to Tx5 with a text sets the state of that slot (Tx1
             replying, Tx2 report, Tx3 rogerReport, Tx4 rogers, Tx5 signoff), also on a
             completed contact, which is then in progress again with its partner, messages
             and dialogue. It transmits nothing by itself. Tx6 on a completed or cancelled
             contact makes the CQ due and leaves the state. A contact completed again is
             not handed over again (HandOverRule). */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: mainwindow_slots.cpp, the Tx "
                + "message chosen after the end";
        }
    }

    requirement 'CL-010-17' {
        subject qso : QsoService;
        doc /* qso MUST answer the first caller of the own CQ as CallFirstRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-010-17'; }

    attribute def CallFirstRule {
        doc /* While Call 1st and Auto Seq are on and the own CQ transmits (calling,
             transmission on), the first counted message to the profile's call in decode
             order whose message is a grid or a report, from a standard call, is answered
             at once as a selection of that record: the contact goes to report or
             rogerReport, transmission stays on and the next own period answers him. A
             continuing exchange (R-report, RRR, RR73, 73), a hashed or nonstandard caller
             and later callers change nothing. Off, the CQ goes on until a start.
             Auto's CQ answers callers by Auto's own rule (WstxCqWhenIdle::CqRule). */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: Call 1st (AutoRespondPeriod, "
                + "isDirectAutoRespondCandidate)";
        }
    }

    requirement 'CL-050-04' {
        subject qso : QsoService;
        doc /* qso MUST keep transmission on when a contact in progress is replaced
             (ReplaceRule). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-050-04'; }

    attribute def ReplaceRule {
        doc /* SelectRow, EnterDx, Reply and CallDx with replace end the contact in
             progress and prepare the new one; transmission stays as it is. The next own
             period of the new contact's parity carries its message; nothing more goes to
             the old partner after a transmission already on the air. A replacement before
             the audio of the keyed period starts sends the new message in that period;
             one to the other parity lets the keyed message finish and sends the new one
             in its next period. */
    }

    requirement 'CL-050-06' {
        subject qso : QsoService;
        doc /* qso MUST keep the dialogue of the contact as DialogueRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-050-06'; }

    attribute def DialogueRule {
        doc /* The dialogue (WstxQsoControl::DialogueEntry) holds each counted partner message
             of the contact, also the selected record when it is to the profile's call,
             and each transmission of the contact whose audio started, oldest first. A
             message equal to the newest entry of its direction counts that entry up; it
             keeps its first period and takes the latest SNR that is not absent. A new
             contact starts with an empty dialogue; a CancelContact empties it. Only the newest
             entries are kept; how many is a value of the code. */
    }

    requirement 'CL-011-03' {
        subject qso : QsoService;
        doc /* qso MUST run an FT4 contact as an FT8 one, with the rules of FtModeRule. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-011-03'; }

    attribute def FtModeRule {
        doc /* A contact has the station's mode at its preparation and keeps it; every request
             carries it and only records of it count. In FT4 Tx4 is always RR73
             (SetTx4 rrr is outOfRange). The periods, the start windows and the waveform
             are transmit's and modes'. */
        @FollowsSource { reference = "WSJT-X at the behaviour baseline: FT4 Tx4 RR73"; }
    }

    requirement 'CL-011-04' {
        subject qso : QsoService;
        doc /* qso MUST end a contact of another mode when the station's mode changes
             (ModeChangeRule). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-011-04'; }

    attribute def ModeChangeRule {
        doc /* A change of the station's mode cancels a contact of the old mode: transmission
             goes off with the cause modeChanged, the partner and Tx1 to Tx5 are cleared and
             the own CQ goes to idle. A completed contact keeps its fields. Tx is brought
             into the Tx range of the new mode (WstxHoldTx::OffsetRule). A Hound ends with
             FT8 (WstxSpecialActivities::HoundRule). */
    }

    requirement 'CL-039-24' {
        subject qso : QsoService;
        doc /* qso MUST ask for a confirmation before it prepares a contact from a CQ that
             is not for the station (DirectedCqRule). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-039-24'; }

    attribute def DirectedCqRule {
        doc /* A SelectRow or Reply of a CQ that WstxValueOrder::DirectedCqRule leaves to
             others is refused directiveNotAnswerable with the reason (as "CQ NA - not
             for EU") unless it carries directiveConfirmed; nothing is prepared. A CQ with
             the CQ word of the activity in force needs no confirmation; a word on the
             strategy's CQ target list still needs it. Auto's reply needs none: ranking
             gives Auto only callable stations. The check comes before contactActive. */
    }

    requirement 'CL-097-06' {
        subject qso : QsoService;
        doc /* qso MUST count no repetition of a send to a partner who is in another QSO, as
             BusyPause says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-097-06'; }

    attribute def BusyPause {
        doc /* The busy pause, for every contact, made by hand or started by Auto. A send of
             the message due while the partner is busy (BusyPartner) at the moment the
             repetition limit judges that send is a paused call: it counts no repetition.
             At most as many paused calls as the repetition limit allows sends are made of
             one message; a further send while he is busy counts. So one message is sent at
             most twice the limit. A new message or a new contact starts the paused count
             anew. The paused calls of the message due are shown with the partner's other
             call. A Hound has no busy pause. */
        attribute busy : BusyPartner;
    }

    requirement 'CL-085-02' {
        subject qso : QsoService;
        doc /* qso MUST hand each completed contact to the log once, as HandOverRule says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-085-02'; }

    attribute def HandOverRule {
        doc /* At its first completion a contact with a partner is given to the log as a
             WstxOperatingChain::FinishedContact, once; a contact completed again after
             ReopenRule, and an own CQ, are not. The log answers it (LogAnswer) before the
             contest serial counts for it (WstxSpecialActivities::ContestSerialRule). A
             refusal changes nothing else in the contact. Log QSO is the log's: it gives
             the newest record again and changes no contact. A contact that LogConfirmRule
             holds is given at ConfirmLog instead. */
    }

    requirement 'CL-085-04' {
        subject qso : QsoService;
        doc /* qso MUST let the operator confirm the logging of a contact by hand as
             LogConfirmRule says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-085-04'; }

    attribute def LogConfirmRule {
        doc /* While QsoShared::logAutomatically is off, a contact the operator started that
             completes is not given to the log: it waits as QsoState::logPending. ConfirmLog
             gives it to the log as HandOverRule says; DiscardLog drops it, and nothing is
             logged. At most one contact waits: a start by the operator while one waits is
             refused with logPending. A contact Auto started is given to the log at its
             completion whatever the setting. */
    }

    attribute def LogTimes {
        doc /* The start of a handed-over contact is the period of its first sent Tx2,
             otherwise one period before its first sent Tx3, otherwise the period of its
             first sent message, otherwise its preparation. Its end is the end of the last
             period with a counted message, and not before the start. */
    }

    verification 'TC-007-001' {
        doc /* The standard contact. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-010-01'; verify 'CL-010-02'; verify 'CL-010-12'; verify 'CL-010-11';
        }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
                + "selecting_a_cq_row_prepares_the_independent_message_set_without_any_request; "
                + "server/src/contact_tests.rs::"
                + "responder_progresses_tx1_tx3_tx5_and_completes_once_after_the_transmitted_73; "
                + "server/src/contact_tests.rs::"
                + "caller_cq_then_selected_reply_reaches_rogers_and_completes_on_73_or_sent_rr73; "
                + "server/src/contact_tests.rs::"
                + "other_stations_wrong_period_and_previous_partner_rows_change_nothing; "
                + "server/src/contact_tests.rs::"
                + "tx1_skip_report_override_and_manual_entry_follow_the_domains; "
                + "server/src/contact_tests.rs::"
                + "a_manual_entry_of_the_same_partner_sets_exactly_the_grid_entered; "
                + "server/src/contact_tests.rs::"
                + "auto_seq_off_offers_tx5_after_the_partners_rr73_and_choosing_it_completes; "
                + "server/src/contact_tests.rs::"
                + "ft8_rrr_or_rr73_after_my_roger_report_sends_73_once_completes_and_logs_once; "
                + "server/src/contact_tests.rs::"
                + "choose_next_without_a_contact_or_for_a_slot_without_text_is_refused; "
                + "server/src/contact_tests.rs::"
                + "receive_only_station_prepares_and_logs_but_refuses_transmit; "
                + "server/src/contact_tests.rs::"
                + "a_free_text_tx5_on_an_own_cq_is_sent_once_and_never_logged";
        }
    }

    verification 'TC-007-010' {
        doc /* The partner's RRR or RR73 before the station's 73. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-010-02'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
                + "tc_007_010_a_the_partners_rr73_after_my_rrr_sends_73_once_and_logs_once; "
                + "server/src/contact_tests.rs::"
                + "tc_007_010_b_the_partners_rrr_after_my_rrr_sends_73_once_and_logs_once; "
                + "server/src/contact_tests.rs::"
            + "tc_007_010_d_rogers_in_replying_and_report_send_73_once_and_log_without_rst_rcvd; "
                + "server/src/contact_tests.rs::"
            + "tc_007_010_e_rr73_while_my_next_tx4_is_pending_before_and_after_its_audio_start; "
                + "server/src/contact_tests.rs::"
            + "tc_007_010_f_auto_seq_off_offers_tx5_after_rogers_in_rogers_replying_and_report; "
                + "server/src/contact_tests.rs::"
                + "tc_007_010_g_only_the_partners_counted_rogers_lead_to_one_73; "
                + "server/src/contact_tests.rs::"
                + "tc_007_010_h_ww_digi_rr73_after_my_rrr_sends_73_once_and_logs_once; "
                + "server/src/contact_tests.rs::"
                + "tc_007_010_i_a_halted_73_keeps_signoff_and_enable_tx_sends_it_once";
        }
    }

    verification 'TC-010-010' {
        doc /* Call 1st. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-010-17'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
                + "call_first_answers_the_first_caller_of_my_cq_in_the_next_own_period; "
                + "server/src/contact_tests.rs::"
                + "call_first_off_auto_seq_off_or_a_sign_off_keep_the_cq_running";
        }
    }

    verification 'TC-050-004' {
        doc /* Another station called while transmission is on. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-050-04'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
    + "changing_the_contact_while_armed_keeps_enable_tx_and_the_next_period_calls_the_new_station; "
                + "server/src/contact_tests.rs::"
                + "a_switch_in_the_keyed_window_before_audio_sends_the_new_contact_in_that_period; "
                + "server/src/contact_tests.rs::"
                + "a_parity_switch_in_the_keyed_window_keeps_enable_tx_and_queues_the_new_period; "
                + "server/src/contact_http_tests.rs::"
                + "tc_111_starts_are_single_commands_and_a_band_change_stops_the_station";
        }
    }

    verification 'TC-050-006' {
        doc /* The dialogue. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-050-06'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
                + "the_contact_dialogue_holds_the_exchanged_messages_in_order";
        }
    }

    verification 'TC-007-008' {
        doc /* The FT4 contact and a change of the mode. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-011-03'; verify 'CL-011-04'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
            + "ft4_responder_transmits_in_odd_7_5_s_periods_and_completes_with_an_ft4_log_offer; "
                + "server/src/contact_tests.rs::"
                + "ft4_caller_keeps_rr73_completes_on_the_sent_rr73_and_bounds_tx_at_2916_hz; "
                + "server/src/contact_tests.rs::"
                + "rows_of_the_other_mode_never_count_and_a_mode_change_disarms_and_cancels; "
                + "server/src/contact_tests.rs::"
                + "ft4_rr73_after_my_roger_report_sends_73_once_completes_and_logs_once; "
                + "server/src/contact_http_tests.rs::"
                + "published_ft4_partner_records_advance_the_contact_to_signoff_after_rr73; "
                + "server/src/contact_http_tests.rs::"
                + "armed_ft4_station_answers_the_partners_rr73_with_73_and_logs_once; "
                + "server/src/contact_http_tests.rs::"
        + "ft4_live_job_sets_the_contact_mode_and_tick_period_and_tune_blocks_a_mode_change; "
                + "server/src/contact_http_tests.rs::"
        + "simultaneous_ft4_and_ft8_stations_stay_isolated_and_a_mode_switch_cancels_only_its_own";
        }
    }

    verification 'TC-039-053' {
        doc /* A CQ of the activity's own word. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-039-24'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_063_004_a_selection_of_the_activitys_cq_needs_no_confirmation; "
                + "server/src/strategy_tests.rs::"
                + "tc_099_002_cq_test_needs_no_confirmation_in_eu_vhf; "
                + "server/src/strategy_tests.rs::"
            + "tc_039_002_a_selection_of_a_cq_not_for_me_is_a_warning_only_the_browser_confirms; "
                + "server/src/strategy_tests.rs::"
                + "a_reply_to_a_cq_not_for_the_station_needs_the_confirmation";
        }
    }

    verification 'TC-097-011' {
        doc /* The busy partner. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-097-06'; }
        @TestedBy {
            test = "server/src/strategy97_tests.rs::"
                + "tc_097_011_a_busy_target_pauses_the_runs_count; "
                + "server/src/strategy97_tests.rs::"
                + "tc_097_011_h_a_grid_to_another_starts_busy_and_his_73_ends_it; "
                + "server/src/strategy97_tests.rs::"
                + "tc_097_011_i_busy_holds_across_a_further_station_and_ends_with_his_free_text";
        }
    }

    verification 'TC-097-012' {
        doc /* A call by hand to a busy station. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-097-06'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
                + "tc_097_012_a_manual_call_to_a_busy_station_keeps_calling_uncounted";
        }
    }

    verification 'TC-097-017' {
        doc /* When the partner is busy, and which send a busy start pauses. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-097-06'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
                + "tc_097_017_a_busy_starts_and_ends_by_his_own_messages; "
                + "server/src/contact_tests.rs::"
                + "tc_097_017_a_his_free_text_within_10_hz_in_his_period_ends_busy; "
                + "server/src/contact_tests.rs::"
                + "tc_097_017_b_the_stop_point_decides_which_send_a_busy_start_counts_for; "
                + "server/src/contact_http_tests.rs::"
                + "tc_097_017_d_get_contact_carries_the_busy_partner";
        }
    }
}
