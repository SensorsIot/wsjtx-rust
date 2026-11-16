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

    // ---- The built-in strategies ----------------------------------------------------------

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
        doc /* A built-in is selected and not saved.
             Setup: the rules alone for (a); for (d) and (e) the station on a
             throw-away profile on 20m.
             (a) The selection of Casual with no saved strategy: taken, and the active
             strategy is the built-in, with new call. The selection of casual:
             refused, naming active.
             (d) Read without a strategies file: the built-ins are listed and no
             strategy is saved.
             (e) The selection of Casual with no saved strategy: the strategies file
             holds no strategy and no active name, and after a station start none is
             active. */
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
        doc /* The built-ins as they are listed, and the selection of one.
             Setup: the station on a throw-away profile without a strategies file.
             (a) Read: builtins holds DXCC all, New DXCC on band, New DXCC, Casual and
             POTA/SOTA, then one for each contest of ContestTable in its order under
             the name of the contest, each with the values BuiltinStrategies gives
             it; every one has a CQ wait of 2; no strategy is saved.
             (b) The selection of DXCC all: taken. The selection of casual or of New
             calls: refused, naming active.
             (c) The selection of WW Digi without a contest: refused, naming contest.
             With the contest ww_digi from 12:00 on the Saturday to 12:00 on the
             Sunday of its weekend: taken.
             (d) An operating that starts on the folder after that has none active. */
        subject operating : OperatingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-11'; verify 'CL-063-03'; }
        @TestedBy {
            test = "server/src/strategy97_tests.rs::"
                + "tc_097_003_the_five_built_ins_the_contest_built_ins_and_active";
        }
    }

    // ---- The contests ---------------------------------------------------------------------

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
        doc /* The facts of the contests.
             Setup: the table of the contests alone, against a table written by hand
             from the rules of the contests.
             (a) The nine contests of ContestTable in its order, each with the
             activity, the dupe rule, the points rule, the multiplier rule and the
             automation clause of its line.
             (b) The bands: ww_digi exactly 160m, 80m, 40m, 20m, 15m and 10m;
             arrl_digi those and 6m; iaru_50_mgm 6m; iaru_70_mgm 4m; ft8_activity 2m,
             70cm and 23cm; arrl_vhf_jun with 6m and without 10m; arrl_field_day with
             40m and without 30m; both of them with 6m, 5m, 4m, 2m and submm.
             (c) No contest rtty or arrl_rtty, and no id twice.
             (d) The texts for the operator: the automation clause of ww_digi says
             that a human operator must initiate each call, and its Cabrillo name
             WW-DIGI is confirmed; that of arrl_field_day says that fully automated
             contacts are prohibited, and its Cabrillo name is not confirmed; those
             of iaru_50_mgm and ft8_activity say that the rules do not address
             automatic operation. The notes of arrl_vhf_jun name the W/VE limit,
             those of arrl_field_day the check-log, those of arrl_digi the 24 of 30
             hours, those of iaru_50_mgm the 6 hours.
             (e) Planned, no test yet: the CQ words: WW for ww_digi, TEST for
             arrl_digi, arrl_vhf_jan, arrl_vhf_jun and arrl_vhf_sep, FD for
             arrl_field_day, none for iaru_50_mgm, iaru_70_mgm and ft8_activity. */
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
        doc /* The period of a contest from its schedule.
             Setup: the schedule alone; the days taken from a calendar.
             (a) Asked on 1 January 2026: ww_digi from 29 August 12:00 to 30 August
             12:00; arrl_digi from 6 June 18:00 to 8 June 00:00; arrl_field_day from
             27 June 18:00 to 28 June 21:00; arrl_vhf_jun from 13 June 18:00 to 15
             June 03:00; arrl_vhf_sep from 12 September 18:00 to 14 September 03:00;
             iaru_50_mgm from 18 April 14:00 to 19 April 14:00; iaru_70_mgm from 16
             May 14:00 to 17 May 14:00; arrl_vhf_jan none.
             (b) ww_digi asked one second before 30 August 2026 12:00: the same
             period. Asked at 12:00: from 28 August 2027 12:00 to 29 August 12:00.
             (c) The full weekend: ww_digi in 2024 starts on 24 August, because the
             Sunday after Saturday 31 August lies in September; arrl_digi in 2025
             starts on 7 June, because 1 June is a Sunday.
             (d) ft8_activity asked on 1 November 2026: 4 November 17:00 to 21:00 on
             2m. Asked on 4 November at 21:00: 11 November on 70cm. Asked on 12
             November: 18 November on 23cm. Asked on 17 December: 6 January 2027 on
             2m. */
        subject operating : OperatingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-063-01'; }
        @TestedBy {
            test = "server/src/contest_tests.rs::tc_063_002_the_period_comes_from_the_rule";
        }
    }

    verification 'TC-063-003' {
        doc /* The list of the contests.
             Setup: the list alone for (a); for (b) the station on a throw-away
             profile.
             (a) Asked on 1 August 2026: the nine contests in the order of
             ContestTable. ww_digi has the period from 29 August 12:00 to 30 August
             12:00 without a band, the activity ww_digi, forbidden, band,
             one_plus_per_3000_km and field_per_band. arrl_vhf_jan has no period.
             iaru_50_mgm is silent and has no activity.
             (b) Asked of the station: as many contests as ContestTable has, ww_digi
             first and forbidden, with a period that has not ended.
             (c) Planned, no test yet: asked of the station while station time is one
             minute before the end of a round and the clock of the PC is past it: that
             round is offered. */
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

    // ---- The selection ----------------------------------------------------------------------

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
        doc /* The selection of a contest.
             Setup: the rules alone for (a) and (b); for (c) to (e) the station on a
             throw-away profile of HB9BLA on 40m with decodes written by hand. The
             period is that of ww_digi, from 12:00 on the Saturday to 12:00 on the
             Sunday.
             (a) ww_digi with that period: taken, and given back value for value.
             (b) Refused, each naming its value. The contest rtty, and a number as the
             contest: contest.profile. A start that is not written as an instant, one
             on 31 February, and one with seconds: contest.start. An end at the
             start, a day before it, or 32 days and a minute after it: contest.end.
             The keys operation, repetitions,
             quiet_minutes and automation_confirmed: each by its name. Another key
             more, and a number as the selection: contest.
             (c) The selection of the built-in WW Digi with the contest: taken, and
             the state gives the contest. The strategies file holds no active name and
             no contest, and an operating that starts on the folder has no contest.
             (d) The selection of the strategy Test calls of class strategy with the
             contest: refused, naming contest. A selection with the end at the start:
             contest.end.
             (e) With the contest in force ranking evaluates under the name WW Digi.
             After the selection of none the state has no contest,
             and ranking refuses an evaluation that names no strategy.
             (f) With the strategy Test calls saved and no strategy active, ranking
             refuses an evaluation that names no strategy. After the selection of Test
             calls, the same evaluation of HB9BLA G4ABC IO91 at +1 dB, CQ DL1XYZ JO62
             at -1, CQ K1ABC FN42 at -12 and CQ NA W1AW FN31 gives G4ABC rank 0,
             DL1XYZ 1, K1ABC 2, and W1AW grey without a rank.
             (g) Planned, no test yet: Auto is given AutoRules and the contact
             ContestActivity, at station start and at a change of the selection. */
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

    // ---- The share of each function ---------------------------------------------------------

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
             ContestSelection.
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
