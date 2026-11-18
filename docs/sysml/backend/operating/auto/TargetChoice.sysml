package WstxTargetChoice {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-025';
    private import WstxAutoPart::AutoService;
    private import WstxAutoControl::WaitReason;
    private import WstxOperatingChain::TargetKind;
    private import WstxTransmitControl::TransmitRefusal;
    private import WstxTransmitControl::DisarmCause;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    doc /* Which station Auto calls, when it waits, and what it does when a start of its own
         cannot go out. */

    requirement 'CL-039-05' {
        subject auto : AutoService;
        doc /* Auto MUST, while it is on and has no contact or CQ of its own, call at each
             fresh complete publication the most valuable station that can be called, and
             start nothing while a reason of WaitRule holds (PickRule). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-025'; end #derive ::> 'CL-039-05'; }

    attribute def PickRule {
        doc /* How Auto picks the station it calls.
             A fresh complete publication is a period view that is complete and that Auto
             has not yet used. At each one, while Auto is on, has no contact or CQ of its
             own and no reason of WaitRule holds, Auto calls the station of the first
             verdict of the ranked list of that period that can be called: a reply with
             the record of that verdict.
             A verdict can be called when it has a rank, and its call is not completed on
             this band and mode since Auto went on, not in its retry pause on this band and
             mode (WstxLeave::LeaveRule) and not the station that Halt QSO dropped, at the
             first pick after it (HaltQsoRule). Of the verdicts of one call the first
             counts. The rank already puts the callers of the profile's call first where
             the strategy says so, and leaves out a CQ the station may not answer; a CQ
             whose word is on the CQ target list of the strategy has a rank, and qso
             takes Auto's reply of it.
             With nothing that can be called Auto goes on waiting, or calls CQ
             (WstxCqWhenIdle::CqRule).
             When Auto's contact completes (QsoProgress::completed), its call is completed
             on this band and mode, and Auto picks from the same publication.
             A band or a mode change cancels Auto's contact or CQ; Auto stays on and picks
             from the next publication on the new band or mode. So does a new live job of
             receive.
             Every decision of Auto is taken at the first moment the information it needs
             is there. */
        attribute start : TargetKind;
    }

    attribute def WaitRule {
        doc /* When Auto, being on, starts nothing, and why. Each reason holds while its
             state holds; when it stops holding Auto picks from the next fresh complete
             publication. AutoActivity names the first reason that holds, in the order
             below.
             noReceive: AutoContext::receiving is false.
             autoSeq: AutoContext::autoSeq is false.
             call: AutoContext::standardCall is false.
             activity: AutoContext::specialActivity is true while no contest is in force;
             a contest in force brings its own activity.
             band: the ranked list says offBand: the station's band is none of the bands of
             the strategy, or of its contest.
             outsidePeriod: a contest is in force (AutoStrategy::contest) and the period
             of the newest publication starts before its start or at or after its end.
             contact: AutoContext::operatorContact is true.
             clock: the last start of Auto was answered clockNotSynchronized.
             tune: the last start of Auto was answered busy because Tune is on.
             For clock and tune Auto starts again at each fresh complete publication, and
             the reason ends with the first start that is not blocked so.
             A reason that comes up while Auto calls CQ cancels the CQ. In Auto's contact a
             band change cancels it, and the end of a contest period cancels a contact that
             is no started QSO and lets a started QSO finish (WstxAutoMode::StartedQsoRule);
             Auto waits after it. */
        attribute reason : WaitReason;
    }

    verification 'TC-039-004' {
        doc /* The pick and the waiting. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-039-05'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_039_004_selecting_starts_a_run_that_calls_by_value_and_never_calls_cq; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_004_a_run_goes_on_after_each_qso_without_a_limit; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_004_halt_turns_auto_off_keeps_the_selection_and_esc_and_a_cancel_do_not; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_004_a_strategy_stays_selected_across_receive_and_without_a_grant; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_004_callers_come_first_and_a_cancelled_station_never_again; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_004_a_station_left_is_not_answered_in_its_quiet_time; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_004_a_station_completed_on_one_band_is_called_on_another; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_004_a_station_completed_on_one_band_is_answered_on_another; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_004_a_retune_leaves_the_quiet_time_behind_not_the_operators_give_up";
        }
    }

    verification 'TC-063-009' {
        doc /* The pick under a contest. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-039-05'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
            + "tc_063_009_search_and_pounce_calls_the_most_valuable_and_waits_for_what_it_needs";
        }
    }

    requirement 'CL-119-06' {
        subject auto : AutoService;
        doc /* Auto MUST stay on when Halt QSO ends its contact or its CQ, and leave the
             dropped station out of the next pick only (HaltQsoRule). */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-025'; end #derive ::> 'CL-119-06'; }

    attribute def HaltQsoRule {
        doc /* What Halt QSO does to Auto. Halt QSO is the one start of the operator that
             acts on Auto's contact while Auto is on; Auto knows it as its contact or CQ
             ended contactCancelled without a cancel of its own.
             Auto's contact: cancelled, and Auto stays on. The next pick leaves its station
             out; from the pick after it the station can be called again. It gets no retry
             pause. With nothing else that can be called at that pick, the publication
             counts for the CQ wait as one with nothing to call.
             Auto's CQ: it ends, and Auto calls CQ again only after a whole CQ wait. */
        attribute ended : DisarmCause;
    }

    requirement 'CL-119-08' {
        subject auto : AutoService;
        doc /* Auto MUST ask qso before each start of its own and act on a blocked start and
             on a refusal or failure after admission as StartRule says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-025'; end #derive ::> 'CL-119-08'; }

    attribute def StartRule {
        doc /* What Auto does when a start of its own cannot go out.
             Each reply, callCq and sendNext is answered by StartAnswer before qso
             prepares anything. Auto never asks transmit itself.
             Blocked: clockNotSynchronized makes Auto wait with clock, busy because Tune is
             on makes it wait with tune; radioUnavailable and transmitUnsupported switch
             Auto off (WstxAutoMode::AutoStops). A blocked start prepares nothing, so
             nothing has to be undone.
             After admission (QsoProgress::ended refused or failed): a failure, deviceLost,
             radioUnavailable, transmitUnsupported and a sequence that cannot rise any more
             switch Auto off. clockNotSynchronized and busy because of Tune make Auto wait as
             above. packRefused, frequencyOutOfRange, stalePeriod, misalignedPeriod,
             staleRequest, notArmed and busy for another cause leave Auto on with no
             reason. audioStarted and a repeated sequence change nothing.
             Where Auto stays on: its contact that no station has answered is cancelled,
             and Auto picks again from the next fresh complete publication with no reason;
             the station may be called again and gets no retry pause. Its CQ ends, and
             Auto calls CQ again only after a whole CQ wait. A started QSO keeps its
             state; once no reason holds Auto sends one sendNext of the message due from
             its next own period, and the QSO goes on under its leave rules. */
        attribute blockedBy : TransmitRefusal;
        attribute start : TargetKind;
    }
}
