package WstxStrategySelection {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-026';
    private import WstxOperatingPart::OperatingService;
    private import WstxStrategies::*;
    private import WstxRankingControl::RankingRules;
    private import WstxRankingControl::StrategyRules;
    private import WstxRankingControl::ContestInForce;
    private import ModelNotes::NotStated;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    requirement 'CL-039-11' {
        subject operating : OperatingService;
        doc /* Operating MUST offer the built-in strategies beside the saved ones, each
             to be selected like a saved one and none to be changed (BuiltinOffer). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-039-11'; }

    attribute def BuiltinOffer {
        doc /* How the strategies of WstxStrategies::BuiltinStrategies are offered.
             StrategiesState::builtins gives them, in their order and with every
             value, in every state of operating.
             A built-in is selected by its name as SelectStrategy::active, exactly as
             BuiltinStrategies writes it.
             A built-in is none of the saved strategies: no saved strategy has the
             name of a built-in, without regard to letter case (Strategy::name). A
             strategy with the values of a built-in and another name is a saved
             strategy like any other. */
    }

    verification 'TC-039-032' {
        doc /* A built-in is selected and not saved. */
        subject operating : OperatingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-11'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_039_032_the_builtin_table_and_what_a_configuration_may_say; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_032_a_builtin_is_selected_like_any_strategy_and_never_stored";
        }
    }

    verification 'TC-097-003' {
        doc /* The built-ins as they are listed, and the selection of one. */
        subject operating : OperatingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-11'; verify 'CL-063-03'; }
        @TestedBy {
            test = "server/src/strategy97_tests.rs::"
                + "tc_097_003_the_five_built_ins_the_contest_built_ins_and_active";
        }
    }

    requirement 'CL-063-01' {
        subject operating : OperatingService;
        doc /* Operating MUST know each contest by the facts of its official rules and
             offer for each the period of its next round (ContestOffering). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-063-01'; }

    attribute def ContestOffering {
        doc /* What operating answers to a ReadContests.
             The ContestList names every contest of WstxStrategies::ContestTable, in
             its order. The facts of a contest are its ContestProfile.
             The moment of a ReadContests is the station time operating takes over its
             port time when the ReadContests comes, in UTC.
             ContestOffer::period is the period ScheduleRule offers at that moment:
             of the rounds that have not ended, the one that starts
             first, with the band of that round when the round has one. A round that
             is running is offered until its end; from its end on the next one is.
             A contest whose day is asked has no period.
             A limit of a contest that depends on the place of the station or on the
             class of the entry is one of the notes of its ContestProfile; operating
             offers every contest to every station. */
    }

    verification 'TC-063-001' {
        doc /* The facts of the contests. */
        subject operating : OperatingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-063-01'; }
        @TestedBy {
            test = "server/src/contest_tests.rs::"
                + "tc_063_001_the_profile_table_holds_the_rule_facts";
        }
    }

    verification 'TC-063-002' {
        doc /* The period of a contest from its schedule. */
        subject operating : OperatingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-063-01'; }
        @TestedBy {
            test = "server/src/contest_tests.rs::tc_063_002_the_period_comes_from_the_rule";
        }
    }

    verification 'TC-063-003' {
        doc /* The list of the contests. */
        subject operating : OperatingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-063-01'; }
        @TestedBy {
            test = "server/src/contest_tests.rs::"
                + "tc_063_003_the_list_names_each_profile_with_its_period; "
                + "server/src/strategy_tests.rs::tc_063_003_the_contests_route";
        }
    }

    requirement 'CL-063-03' {
        subject operating : OperatingService;
        doc /* Operating MUST take the operator's selection of the active strategy, put a
             contest in force only with its period and with an active strategy of class
             contest for that contest, and hold the selection until the next one or the
             stop of the station (SelectionRule). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-063-03'; }

    attribute def SelectionRule {
        doc /* What may be selected, and how long a selection holds.
             The selection is SelectStrategy::active and SelectStrategy::contest of the
             last SelectStrategy that was carried out. One strategy is active, or none:
             active is absent, or exactly the name of a saved strategy or of a
             built-in; another name is refused by active.
             A contest is in force exactly while the active strategy is of class
             contest: a ContestSelection is taken only together with such a strategy,
             and only for the contest that strategy names. A contest with no active
             strategy, with one of class strategy or with one for another contest, and
             a strategy of class contest without its contest, are refused by the
             contest.
             ContestSelection::profile is a contest of ContestTable. start and end are
             instants of the calendar to the minute; end is after start and at most
             ContestSelection::periodDaysMax days after it. A value outside these
             rules is refused by its own name. The period is the operator's: it need
             not be one that ScheduleRule offers.
             A selection with no active strategy ends the contest in force.
             A value outside these rules refuses the SelectStrategy
             (StrategiesRefused), and the selection stays as it was. A SelectStrategy
             within them is carried out: operating holds the selection, answers with
             the StrategiesState and gives the shares anew (Shares).
             When a change of the saved strategies (SavedStrategies) leaves out the
             active saved strategy by its name, the selection ends: no strategy is
             active and no contest is in force.
             The selection is held while the station runs and is not kept by the
             settings: at station start no strategy is active and no contest is in
             force. */
    }

    verification 'TC-063-007' {
        doc /* The selection of a contest. */
        subject operating : OperatingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-063-03'; verify 'CL-097-10'; }
        @TestedBy {
            test = "server/src/contest_tests.rs::tc_063_007_a_selection_is_parsed_exactly; "
                + "server/src/contest_tests.rs::"
                + "tc_063_009_a_selection_asks_nothing_and_refuses_colouring_and_the_confirmation; "
                + "server/src/strategy_tests.rs::"
                + "tc_063_007_a_contest_selection_store_and_evaluation; "
                + "server/src/strategy_tests.rs::tc_039_003_store_routes_and_evaluate";
        }
    }

    requirement 'CL-097-10' {
        subject operating : OperatingService;
        doc /* Operating MUST give ranking, Auto and the contact each its share of the
             active strategy, at station start and whenever the selection or a value
             of the share changes (Shares). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-097-10'; }

    attribute def Shares {
        doc /* What each of the three functions inside operating is given, and when.
             Ranking is given RankingRules. active is the StrategyRules of the active
             strategy: its name, Strategy::ranking as the keys, and for class contest
             the ContestInForce with the contest and the two instants of the
             ContestSelection.
             Auto is given AutoRules. active is the AutoStrategy of the active
             strategy: its name, Strategy::auto as the keys, and for class contest the
             ContestSelection and the ContestProfile::automation of its contest.
             The contact is given ContestActivity: whether a contest is in force, and
             the ContestProfile::activity of that contest.
             While no strategy is active, active is absent in both, no contest is in
             force and the activity is absent.
             Operating gives the three at station start, and gives a share anew
             whenever the saved strategies (SavedStrategies) or the selection change a
             value of it. A function is given its own share and no other value of a
             strategy. */
        @NotStated {
            what = "by which rules a strategy that the operator offers as a draft "
                + "for an evaluation is checked before ranking is given it as "
                + "WstxRankingControl::EvaluateRequest::draft: the code holds it to "
                + "StrategyForm, and no command of StrategiesPort carries a draft";
        }
    }
}
