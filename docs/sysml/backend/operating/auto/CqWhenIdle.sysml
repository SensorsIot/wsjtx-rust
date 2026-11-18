package WstxCqWhenIdle {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-025';
    private import WstxAutoPart::AutoService;
    private import WstxOperatingChain::TargetKind;
    private import WstxTransmitControl::DisarmCause;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    doc /* Auto's CQ: when Auto calls CQ, whom it answers from it, and the pause after a CQ
         nobody answered. */

    requirement 'CL-097-08' {
        subject auto : AutoService;
        doc /* Auto MUST, with CQ when idle on, call CQ after cqWaitPeriods fresh complete
             publications with nothing to call, and answer from its CQ the most valuable
             station that calls the profile's call (CqRule). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-025'; end #derive ::> 'CL-097-08'; }

    attribute def CqRule {
        doc /* When Auto calls CQ, and how its CQ goes on.
             With AutoKeys::cqWhenIdle on, Auto, waiting with no reason, counts the fresh
             complete publications in which nothing can be called, of every period of
             either parity. At AutoKeys::cqWaitPeriods of them it calls CQ (callCq).
             The count starts at 0 at a
             switchOn, after a QSO, after a leaving, and after every end of Auto's CQ that
             leaves Auto on. The publication in which Auto's contact completed or its
             station was left counts as the first, when nothing in it can be called. A CQ
             pause (CqPause) takes the place of the count while it lasts.
             With cqWhenIdle off Auto never calls CQ; cqWaitPeriods is kept.
             During Auto's CQ, at each fresh complete publication of the parity the
             partner transmits in, Auto calls the first verdict that can be called
             (WstxTargetChoice::PickRule) with a reply, which ends the CQ; a station
             answering the CQ is called as a caller of the profile's call; where Tx then
             transmits is qso's (WstxHoldTx::TooCloseRule). With nothing to call the CQ
             goes on.
             A reason of WaitRule that comes up cancels the CQ. The CQ that the repetition
             limit ends (QsoProgress::ended txWatchdog) leaves Auto on. */
        attribute start : TargetKind;
    }

    verification 'TC-039-045' {
        doc /* CQ when idle. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-097-08'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_039_045_cq_when_no_target_calls_answers_and_calls_a_candidate; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_045_the_cqs_slot_is_judged_in_my_rx_parity; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_045_a_caller_is_answered_from_the_cqs_slot";
        }
    }

    verification 'TC-063-010' {
        doc /* Auto's CQ under a contest. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-097-08'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_063_010_run_calls_cq_and_answers_the_most_valuable_caller";
        }
    }

    verification 'TC-097-018' {
        doc /* The CQ wait. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-097-08'; }
        @TestedBy {
            test = "server/src/strategy97_tests.rs::tc_097_018_cq_after_exactly_the_cq_wait; "
                + "server/src/strategy97_tests.rs::tc_097_018_the_cq_wait_starts_again";
        }
    }

    verification 'TC-089-004' {
        doc /* When Auto decides its CQ. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-097-08'; }
        @TestedBy {
            test = "server/src/operating/qso/newest_rx_tests.rs::"
                + "tc_089_004_a_contest_strategy_cq_counts_the_newest_rx_period; "
                + "server/src/operating/qso/newest_rx_tests.rs::"
                + "tc_089_004_hold_tx_stop_and_a_second_auto_on";
        }
    }

    verification 'TC-097-015' {
        doc /* A contest strategy under Auto. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-097-08'; }
        @TestedBy {
            test = "server/src/strategy97_tests.rs::"
                + "tc_097_015_the_contest_built_in_and_a_saved_contest_strategy_run";
        }
    }

    requirement 'CL-097-11' {
        subject auto : AutoService;
        doc /* Auto MUST, after its CQ ended at the repetition limit with no caller answered,
             call no CQ for cqQuietPeriods periods and still call every station that can be
             called (CqPause). */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-025'; end #derive ::> 'CL-097-11'; }

    attribute def CqPause {
        doc /* The pause after Auto's CQ that nobody answered.
             It starts when the repetition limit ends Auto's CQ (QsoProgress::ended
             txWatchdog) with no caller answered from it. Every other end of the CQ (Halt
             QSO, a refusal, a station called from it) is followed by the ordinary CQ
             wait.
             It lasts AutoKeys::cqQuietPeriods fresh complete publications, of every period
             of either parity, counted as the CQ wait is. During it Auto calls no CQ and
             still calls every station that can be called; a QSO in between ends the
             pause, and the ordinary CQ wait follows it.
             After it Auto calls CQ at the first fresh complete publication with nothing to
             call: the pause takes the place of the CQ wait, they do not add. With
             cqQuietPeriods 0 there is no pause and the ordinary CQ wait follows.
             AutoActivity::cqPauseLeft shows the periods left. */
        attribute ended : DisarmCause;
    }
}
