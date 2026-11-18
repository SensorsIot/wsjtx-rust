package WstxLeave {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-025';
    private import WstxAutoPart::AutoService;
    private import WstxAutoControl::LeaveReason;
    private import WstxAutoControl::LeaveCount;
    private import WstxAutoControl::RetryPause;
    private import WstxStrategies::LeaveMode;
    private import WstxOperatingChain::TargetKind;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    doc /* How Auto's contact ends: when Auto leaves a station that does not answer, the
         retry pause after it, and that nothing else interrupts the contact. */

    requirement 'CL-097-04' {
        subject auto : AutoService;
        doc /* Auto MUST leave the station of its contact by the leave mode of the active
             strategy, call it again on that band and mode only after its retry pause, and
             show how far the contact is from being left (LeaveRule). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-025'; end #derive ::> 'CL-097-04'; }

    attribute def LeaveRule {
        doc /* When Auto leaves a station, and what follows.
             A repetition is a fresh complete publication of the parity the station
             transmits in, after a transmission of Auto's contact, that brings no
             progress. Progress is a decoded message of the station to the profile's call,
             also one it repeats; a station called on its call to the profile's call that
             repeats that same call makes no progress. Progress puts every count of the
             contact back to 0. A repetition while the station is busy
             (QsoProgress::busyWith) counts for nothing.
             The leave mode of AutoKeys decides.
             calls: the station is left at the repetition that makes leaveCalls, or
             leaveCallsHeard while the station hears the profile's call (TargetReport).
             untilLogged: the station is left at the first publication of its parity
             whose period starts goneMinutes or more after its newest decode, also after
             its answer, and in which it is not decoded.
             contest: while the station is decoded, hears the profile's call and no station
             that can be called stands before it in the order of the ranking, it stays and
             no repetition counts. Otherwise a repetition at which the count of its PSK case
             reaches its moveEvery value, or every repetition while that value is 0, is a
             change point: with txChanges changes made the station is left, else one more
             change is made (and Auto asks for a move, WstxTxSlot::MoveRule).
             Leaving: Auto cancels its contact, AutoActivity::left names the station and
             the reason (repetitions, gone, txChanges), and the station's retry pause
             starts. Auto picks from the same publication; with nothing that can be called
             it counts for the CQ wait.
             The retry pause lasts retryMinutes. During it the station is neither called
             nor answered on the band and mode it was left on; on another band or mode it
             can be. It is memory: a switchOn starts with none, and a band change, a mode
             change, a stop and Halt start none.
             The leave count (LeaveCount) says, for Auto's contact, the calls, minutes or
             Tx changes left and whether the station stays. For Auto's
             contact the repetitions left of the repetition limit are not shown. */
        attribute mode : LeaveMode;
        attribute reason : LeaveReason;
        attribute count : LeaveCount;
        attribute pause : RetryPause;
    }

    verification 'TC-039-043' {
        doc /* Leaving after a number of calls. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-097-04'; verify 'CL-119-04'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_039_043_a_silent_or_repeating_target_is_left_at_the_4th; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_043_a_target_that_hears_us_is_left_at_2x_and_use_off_at_x; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_043_a_repeated_report_is_progress_and_never_leaves; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_043_a_caller_repeating_its_first_call_is_left_at_the_4th; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_043_a_more_valuable_cq_waits_for_the_exit; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_043_the_quiet_time_excludes_selection_and_answering; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_043_one_repetition_leaves_at_the_first; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_043_band_mode_auto_off_and_halt_end_the_contact_at_once";
        }
    }

    verification 'TC-039-044' {
        doc /* Leaving under a contest. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-097-04'; verify 'CL-119-04'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_039_044_a_contest_leaves_at_2_and_at_4_with_a_spot; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_044_a_heard_target_stays_until_a_more_valuable_station; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_044_run_leaves_a_silent_caller_and_keeps_it_quiet; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_044_period_end_and_deselect_end_the_contact_at_once";
        }
    }

    verification 'TC-097-009' {
        doc /* The three leave modes. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-097-04'; }
        @TestedBy {
            test = "server/src/strategy97_tests.rs::"
                + "tc_097_009_a_the_spot_ageing_past_600_s_brings_the_leaving_back_to_calls; "
                + "server/src/strategy97_tests.rs::"
                + "tc_097_009_b_until_logged_leaves_only_when_gone_10_minutes; "
                + "server/src/strategy97_tests.rs::"
                + "tc_097_009_c_contest_style_change_points_and_the_stay; "
                + "server/src/strategy97_tests.rs::"
                + "tc_097_009_d_e_an_answer_resets_and_the_retry_pause";
        }
    }

    verification 'TC-097-013' {
        doc /* The leave count. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-097-04'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_097_013_no_wd_in_the_runs_own_contact_and_the_leave_count; "
                + "server/src/strategy97_tests.rs::"
                + "tc_097_013_get_transmit_null_only_in_the_attended_runs_own_contact";
        }
    }

    requirement 'CL-119-04' {
        subject auto : AutoService;
        doc /* Auto MUST end its contact only as ContactEndRule says, so that a more
             valuable station or a caller of the profile's call never interrupts it. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-025'; end #derive ::> 'CL-119-04'; }

    attribute def ContactEndRule {
        doc /* What ends Auto's contact, and nothing else: its completion, logged once; a
             leaving by LeaveRule; a stop of Auto
             (WstxAutoMode::AutoStops); Halt QSO (WstxTargetChoice::HaltQsoRule); a band
             or mode change or a new live job; the end of a contest period for a contact
             that is no started QSO; a refusal of WstxTargetChoice::StartRule.
             A more valuable station and a caller of the profile's call wait for the next
             pick: a caller is answered at once only during Auto's CQ
             (WstxCqWhenIdle::CqRule).
             A change of the active strategy leaves the contact as it is; from then on the
             leave rules of the new strategy apply to it. */
        attribute ending : TargetKind;
    }
}
