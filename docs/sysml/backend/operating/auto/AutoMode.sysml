package WstxAutoMode {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-025';
    private import WstxAutoPart::AutoService;
    private import WstxAutoControl::*;
    private import WstxOperatingChain::TargetKind;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    doc /* Auto as a toggle: when it goes on, what switches it off, and what becomes of its
         contact when it goes off. */

    requirement 'CL-039-22' {
        subject auto : AutoService;
        doc /* Auto MUST go on only by a switchOn while a strategy other than Default is
             active and, under a
             contest whose rules forbid automatic operation, only with the operator's
             acknowledgement in the settings, and hold whether it is on in memory alone
             (AutoSwitchRule). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-025'; end #derive ::> 'CL-039-22'; }

    attribute def AutoSwitchRule {
        doc /* How Auto goes on.
             Auto is off at station start. It stores nothing: whether it is on, the
             stations completed since it went on, the retry pauses and every count are
             memory.
             A switchOn while Default is active (AutoRules::active absent) is refused
             with noStrategy. One while a contest is in force whose rules forbid automatic
             operation (AutoStrategy::automation forbidden) is refused with notConfirmed
             unless the operator has acknowledged Auto there (AutoContext::config,
             AutoConfig::forbiddenContests); no switch asks for it. A refused switchOn
             changes nothing.
             Every other switchOn puts Auto on: state waiting, with no station completed
             and no retry pause. A switchOn while Auto is on changes nothing. The switch
             of an agent does what the operator's does.
             While Auto is off a selected strategy only ranks: Auto starts nothing for it.
             A change of the active strategy, of either class, leaves Auto on. Auto is
             never on under a forbidding contest without the acknowledgement: a change of
             the strategy, or of the setting, that brings this about switches it off
             (AutoStops). */
    }

    verification 'TC-039-042' {
        doc /* Auto on and off. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-039-22'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_039_042_auto_starts_and_ends_the_run_and_a_selection_only_marks; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_042_a_silent_contest_switches_auto_on_without_a_confirmation; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_042_a_browser_auto_on_ends_a_watchdog_stop_and_arms";
        }
    }

    requirement 'CL-119-05' {
        subject auto : AutoService;
        doc /* Auto MUST stay on until the operator or an agent switches it off, Default
             becomes active, the station halts, the radio cannot transmit or nobody is connected,
             and then go off with the reason of AutoStops. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-025'; end #derive ::> 'CL-119-05'; }

    attribute def AutoStops {
        doc /* What switches Auto off, and nothing else.
             stopped: a switchOff; AutoRules while Default is active; a contest whose
             rules forbid automatic operation in force without the operator's
             acknowledgement (AutoSwitchRule).
             halted: a halt, whatever its source, also the halt of the station for a radio
             that is not ready or for its SWR fault.
             transmitRefused: a start of Auto answered radioUnavailable or
             transmitUnsupported (StartAnswer).
             transmitStopped: Auto's contact or CQ ended failed, deviceLost, or refused
             for radioUnavailable, transmitUnsupported or a sequence that cannot rise any
             more (QsoProgress).
             noClient: AutoContext::present false. From that moment Auto starts nothing
             new, cancels its CQ and a contact of its own that no station has answered,
             lets a started QSO finish (StartedQsoRule), and then goes off.
             Every other event leaves Auto on: no answer and a leaving; Halt QSO; a band or
             mode change; a change of the active strategy to another one; the end of a
             contest period; the repetition limit of Auto's CQ; every refusal and event
             that WstxTargetChoice::StartRule names.
             When Auto goes off it cancels its CQ and a contact of its own that is no
             started QSO (TargetKind::cancel); a transmission on the air finishes its
             period. After halted, transmitRefused and transmitStopped its contact is as
             Halt or transmit left it. AutoActivity then says stopped with the reason.
             Only a switchOn puts Auto on again. */
        attribute reason : OffReason;
    }

    verification 'TC-063-011' {
        doc /* The stops of Auto under a contest. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-119-05'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_063_011_the_safety_of_a_contest_run_stays_on_the_server";
        }
    }

    verification 'TC-039-033' {
        doc /* Nobody connected. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-119-05'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_039_033_without_a_client_for_60_s_nothing_new_and_the_exchange_ends; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_033_waiting_stops_at_60_s_and_a_client_or_reload_keeps_it";
        }
    }

    requirement 'CL-081-01' {
        subject auto : AutoService;
        doc /* Auto MUST let a started QSO of its own finish as an ordinary contact when it
             goes off for stopped or noClient, and cancel at once its CQ and a contact of
             its own that is no started QSO (StartedQsoRule). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-025'; end #derive ::> 'CL-081-01'; }

    attribute def StartedQsoRule {
        doc /* What becomes of Auto's contact when Auto goes off.
             A started QSO is a contact of Auto with QsoProgress::started: the partner
             has sent a message to the profile's call and a transmission of the station
             to him has started. A station that called the profile's call before the
             transmission to it started, and a station Auto called that has sent nothing
             to the profile's call, are no started QSO.
             When Auto goes off with stopped or noClient, a started QSO stays as it is:
             qso sequences it to its end and logs it once, as an ordinary contact, and
             the repetition limit bounds it. Auto sends nothing more for it, starts
             nothing new and leaves its Tx offset where it is. What ends an ordinary
             contact at once ends it too: Halt, Halt QSO, a band or mode change, and the
             operator's start of another contact.
             When Auto goes off with halted, the halt ends the contact at once.
             A contact that is no started QSO, and Auto's CQ, are cancelled at once; a
             transmission on the air finishes its period and nothing is keyed after it. */
        attribute ending : TargetKind;
    }

    verification 'TC-081-001' {
        doc /* Auto off in a started QSO. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-081-01'; }
        @TestedBy {
            test = "server/src/operating/qso/autofinish_tests.rs::"
                + "tc_081_001_auto_off_in_a_started_qso_finishes_it_and_logs_it_once";
        }
    }

    verification 'TC-081-002' {
        doc /* Which contact is a started QSO. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-081-01'; }
        @TestedBy {
            test = "server/src/operating/qso/autofinish_tests.rs::"
                + "tc_081_002_a_reply_on_the_air_is_a_started_qso; "
                + "server/src/operating/qso/autofinish_tests.rs::"
                + "tc_081_002_b_c_d_no_started_qso_ends_at_once_and_its_period_on_the_air_finishes";
        }
    }

    verification 'TC-081-003' {
        doc /* The other ends that let a started QSO finish. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-081-01'; }
        @TestedBy {
            test = "server/src/operating/qso/autofinish_tests.rs::"
                + "tc_081_003_none_another_strategy_and_auto_off_twice_finish_the_qso; "
                + "server/src/operating/qso/autofinish_tests.rs::"
                + "tc_081_003_a_contest_deselected_or_its_period_end_finishes_the_qso";
        }
    }

    verification 'TC-081-004' {
        doc /* The repetition limit bounds a finishing QSO. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-081-01'; }
        @TestedBy {
            test = "server/src/operating/qso/autofinish_tests.rs::"
                + "tc_081_004_a_b_the_finishing_qso_keeps_the_tx_watchdog_limit; "
                + "server/src/operating/qso/autofinish_tests.rs::"
                + "tc_081_004_c_a_message_past_the_limit_is_not_sent_again_after_the_auto_off";
        }
    }

    verification 'TC-081-005' {
        doc /* What still ends a finishing QSO at once. */
        subject auto : AutoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-081-01'; }
        @TestedBy {
            test = "server/src/operating/qso/autofinish_tests.rs::"
                + "tc_081_005_halt_abort_and_a_double_click_end_a_finishing_qso_at_once; "
                + "server/src/operating/qso/autofinish_tests.rs::"
                + "tc_081_005_band_mode_and_grant_end_a_finishing_qso_at_once; "
                + "server/src/operating/qso/autofinish_tests.rs::"
                + "tc_081_005_h_the_runs_leaving_ends_a_started_qso_at_once";
        }
    }
}
