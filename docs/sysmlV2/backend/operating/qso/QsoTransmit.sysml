package WstxQsoTransmit {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-007';
    private import WstxQsoPart::QsoService;
    private import ModelNotes::DiffersFromSource;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    doc /* When a contact transmits: the starts that switch transmission on, the ends, and
         the repetition limit. Transmission is transmit's state; qso switches it over
         WstxOperatingChain::MessageToSend and gives each message as a TransmitRequest. */

    requirement 'CL-111-02' {
        subject qso : QsoService;
        doc /* qso MUST switch transmission on by a start only, as StartRule says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-111-02'; }

    attribute def StartRule {
        doc /* The starts are Reply, CallCq, CallDx, SendNext and ResetRepetitions of the
             operator or an agent, and Auto's reply, call_cq and send_next
             (WstxOperatingChain::CallTarget). A start switches transmission on (Arm, cause
             operator or auto) and its message goes in the next own period whose start
             window is open (WstxTransmitControl::StartWindow). Nothing else switches it
             on: not a preparation, a chosen message, a setting or a partner message.
             Reply prepares from the record (WstxStandardQso::PrepareRule): another partner
             is a new contact, the current partner goes on at the record's message.
             CallDx prepares from the entered call as EnterDx.
             CallCq starts the own CQ, or goes on with the own CQ that is kept; with a
             contact with a partner in progress it is contact_active; a Hound has none
             (no_contact).
             SendNext makes the slot due and switches on; without a contact with a partner
             in progress it is no_contact, a slot without text invalid_message.
             ResetRepetitions is ResetRule.
             A start in the step in which transmission went off
             (WstxTransmitControl::TransmitStatus) is state_conflict; in the next step it is
             a start again. */
    }

    requirement 'CL-111-05' {
        subject qso : QsoService;
        doc /* qso MUST call CQ on a CallCq or Auto's call_cq only (StartRule). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-111-05'; }

    requirement 'CL-111-07' {
        subject qso : QsoService;
        doc /* qso MUST answer a start that cannot transmit as BlockedStartRule says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-111-07'; }

    attribute def BlockedStartRule {
        doc /* While transmission is not possible (no transmit capability, the radio
             unavailable, the clock not synchronized, Tune on, or transmit refuses to arm),
             a Reply or CallDx is accepted and prepares the contact; transmission stays
             off with its cause, and the answer names the reason (QsoAnswer::blockedBy).
             Nothing starts by itself when the reason goes; a new start transmits.
             CallCq, SendNext and ResetRepetitions are refused with the reason
             (transmit_unavailable, busy, clock_not_synchronized) and change nothing.
             Auto's starts are answered before anything is prepared
             (WstxOperatingChain::StartAnswer). */
    }

    requirement 'CL-111-08' {
        subject qso : QsoService;
        doc /* qso MUST start the repetition count anew on ResetRepetitions as ResetRule
             says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-111-08'; }

    attribute def ResetRule {
        doc /* ResetRepetitions acts on a contact with a partner. While transmission is on it
             starts the count of the message due anew. While transmission is off by the
             repetition limit it starts the count anew, switches transmission on (cause
             operator) and the message due goes in the next own period. After another stop
             it is state_conflict; without a contact with a partner in progress (no contact,
             the own CQ, completed, cancelled) no_contact; while on but unable to transmit
             (BlockedStartRule) refused with the reason, the count unchanged. */
    }

    requirement 'CL-010-03' {
        subject qso : QsoService;
        doc /* qso MUST end a contact on CancelContact and HaltQso as EndRule says, and give
             transmit each message once. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-010-03'; }

    attribute def EndRule {
        doc /* CancelContact switches transmission off (Disarm, cause contactCancelled) and lets a
             transmission on the air finish; the contact is cancelled: partner and Tx1 to
             Tx5 cleared, Tx6 due, the dialogue empty. HaltQso stops the transmission now
             (WstxTransmitControl::Abort): PTT released, no halt, the contact cancelled as by
             CancelContact; nothing is
             handed over. The emergency Halt is the supervisor's.
             qso keeps at most one request pending. A request transmit refuses without
             switching off is not given again unchanged; a refused duplicate switches
             transmission off with the cause refused. */
    }

    requirement 'CL-039-06' {
        subject qso : QsoService;
        doc /* qso MUST stop transmission before a message would be sent more often than the
             repetition limit allows (RepetitionLimit), without a halt. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-039-06'; }

    attribute def RepetitionLimit {
        doc /* The limit is WstxQsoControl::QsoConfig::repetitionLimit. The count of the
             message due is the count of the newest sent entry of the dialogue when it
             holds that message, otherwise 0, less its paused calls
             (WstxStandardQso::BusyPause). A different message, a new contact, a start and
             Reset start it anew; partner messages, settings and a selection of the
             partner's record restart nothing. When the send due next would exceed the
             limit, it is never keyed: transmission goes off with the cause txWatchdog,
             nothing is halted, a transmission on the air finishes, the contact is kept and
             the own CQ goes to idle; the station shows that the limit stopped it
             (QsoState::expired) until the next start. A request still pending beyond a
             lowered limit, or for a message chosen again at its limit, is dropped at once.
             A message counted from the partner before that moment still changes the
             message due. While transmission is on the sends left are shown
             (QsoState::repetitionsLeft), while it is off 0. Auto's contact has no limit
             and no sends left; Auto's CQ has the limit. */
        @DiffersFromSource {
            what = "WSJT-X stops after a time without operator action (Tx watchdog in "
                + "minutes); the station counts the repetitions of one message (operator "
                + "rule, issue 39).";
        }
    }

    requirement 'CL-039-21' {
        subject qso : QsoService;
        doc /* qso MUST NOT stop Auto's contact by the repetition limit (RepetitionLimit);
             Auto's leave rule bounds it. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-039-21'; }

    verification 'TC-008-001' {
        doc /* The repetition limit. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-06'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
                + "tc_008_001_the_watchdog_stops_at_n_repetitions_"
                + "whatever_the_partner_or_browser_does; "
                + "server/src/contact_tests.rs::"
                + "tc_008_001_the_partner_advancing_at_the_limit_sends_the_next_message; "
                + "server/src/contact_tests.rs::"
                + "tc_008_001_clicks_on_the_partner_and_enable_tx_while_armed_restart_nothing; "
                + "server/src/contact_tests.rs::"
                + "tc_008_001_a_partner_row_with_another_snr_restarts_nothing; "
                + "server/src/contact_tests.rs::"
                + "tc_008_001_a_partner_row_keeps_an_edited_message_and_its_count; "
                + "server/src/contact_tests.rs::"
                + "tc_008_001_a_pending_send_beyond_a_lowered_limit_is_never_keyed; "
                + "server/src/contact_tests.rs::"
                + "tc_008_001_going_back_to_a_message_at_its_limit_cancels_the_pending_send; "
                + "server/src/contact_tests.rs::"
                + "tc_008_001_identical_cqs_stop_and_an_answered_cq_starts_again; "
                + "server/src/contact_tests.rs::"
                + "tc_008_001_tx_watchdog_counts_unanswered_calls_and_tune_ends_at_its_limit";
        }
    }

    verification 'TC-039-054' {
        doc /* Auto's contact past the limit. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-21'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
                + "tc_039_022_only_the_runs_own_contact_sends_past_the_limit";
        }
    }

    verification 'TC-007-004' {
        doc /* CancelContact, HaltQso and the requests. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-010-03'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
                + "abort_stops_the_transmission_now_and_cancels_without_a_halt; "
                + "server/src/contact_tests.rs::"
                + "auto_seq_off_cancel_halt_and_watchdog_while_calling; "
                + "server/src/contact_tests.rs::"
                + "a_non_disarming_refusal_is_not_resubmitted_every_step";
        }
    }

    verification 'TC-111-002' {
        doc /* What is no start never transmits. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-111-02'; }
        @TestedBy {
            test = "server/src/transmit_state_tests.rs::"
                + "tc_111_002_what_is_not_a_start_never_transmits";
        }
    }

    verification 'TC-111-003' {
        doc /* A start of the own CQ kept off, and a late start. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-111-02'; }
        @TestedBy {
            test = "server/src/transmit_state_tests.rs::"
                + "tc_111_003_call_cq_on_an_own_cq_kept_off; "
                + "server/src/contact_tests.rs::"
                + "a_late_start_keyed_before_audio_queues_the_next_own_period_without_disarming";
        }
    }

    verification 'TC-111-018' {
        doc /* A stop against a start in one step. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-111-02'; }
        @TestedBy {
            test = "server/src/transmit_state_tests.rs::"
                + "tc_111_013_a_stop_wins_over_a_start_in_one_step";
        }
    }

    verification 'TC-111-011' {
        doc /* A start that cannot transmit. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-111-07'; }
        @TestedBy {
            test = "server/src/transmit_state_tests.rs::"
                + "tc_111_011_a_start_that_cannot_transmit_prepares_and_stays_off; "
                + "server/src/transmit_state_tests.rs::"
                + "tc_111_011_a_start_the_transmit_owner_cannot_arm_is_refused; "
                + "server/src/transmit_state_tests.rs::"
                + "tc_111_011_reset_while_on_but_unable_to_transmit_is_refused";
        }
    }

    verification 'TC-111-012' {
        doc /* Reset. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-111-08'; }
        @TestedBy {
            test = "server/src/transmit_state_tests.rs::"
                + "tc_111_012_reset_starts_the_count_anew_and_continues_after_the_limit";
        }
    }
}
