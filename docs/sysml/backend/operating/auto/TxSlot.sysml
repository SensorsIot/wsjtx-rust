package WstxTxSlot {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-025';
    private import WstxAutoPart::AutoService;
    private import WstxHearing::HearingState;
    private import WstxOperatingChain::TargetKind;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    doc /* When Auto's Tx moves. Where it goes is qso's (WstxHoldTx::QuietSpace). */

    requirement 'CL-097-05' {
        subject auto : AutoService;
        doc /* Auto MUST ask for a move of the Tx of its contact between unanswered
             repetitions as the PSK case of the called station says, and off a station that
             has come up on it, as MoveRule says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-025'; end #derive ::> 'CL-097-05'; }

    attribute def MoveRule {
        doc /* When Auto asks qso to move Tx (move).
             The PSK case of the called station comes from its TargetReport: heard while it
             hears the profile's call; not heard while it reports and does not hear it; no
             reports while it does not report, while that is unknown, and while the report
             is not in use.
             By the case: between unanswered repetitions of Auto's contact the count of
             repetitions since the call or the last move rises by one, a repetition while
             the station is busy (QsoProgress::busyWith) not counted; at the repetition at
             which it reaches the moveEvery value of AutoKeys for the case, Auto asks for a
             move. A value of 0 never moves. Under the leave mode contest the change points
             move when the value is 1 or more (WstxLeave::LeaveRule). After the station's
             answer the case moves nothing, and no move is asked while the station is busy.
             Off a station: when a station is decoded in a counted period that the last
             setting of Tx did not count, and its signal overlaps the Tx of Auto's contact
             or CQ (QsoProgress::txHz), Auto asks for a move before its next transmission.
             It does not ask for the called station itself, while the report the station
             sent in the contact is -4 dB or better, or while the message due has not been
             repeated. This holds also after the station's answer. Where both reasons come
             at one transmission, Auto asks once.
             A move puts the count back to 0. A move that leaves Tx where it is changes
             nothing and is asked again at the next repetition, the count kept. Rx stays. */
        attribute 'case' : HearingState;
        attribute move : TargetKind;
    }

    verification 'TC-039-022' {
        doc /* Tx at each repetition. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-097-05'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::tc_039_022_the_slot_check_at_every_repetition; "
                + "server/src/strategy_tests.rs::tc_039_022_an_answer_keeps_the_slot; "
                + "server/src/strategy_tests.rs::tc_039_022_a_refused_move_is_checked_again";
        }
    }

    verification 'TC-097-010' {
        doc /* The moves by PSK case. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-097-05'; }
        @TestedBy {
            test = "server/src/strategy97_tests.rs::tc_097_010_the_run_moves_tx_per_psk_case; "
                + "server/src/strategy97_tests.rs::"
                + "tc_097_010_auto_slot_from_500_hz_upper_edge_ties_and_the_move_rule";
        }
    }
}
