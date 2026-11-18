package WstxContestRanking {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-026';
    private import WstxRankingPart::RankingService;
    private import WstxRankingControl::*;
    private import WstxStrategies::ContestProfile;
    private import WstxStrategies::ContestTable;
    private import WstxStrategies::DupeRule;
    private import WstxStrategies::PointsRule;
    private import WstxStrategies::MultiplierRule;
    private import WstxStrategies::CountedModes;
    private import WstxOperatingChain::ContestPeriod;
    private import WstxOperatingChain::PeriodQsos;
    private import WstxOperatingChain::PeriodQso;
    private import WstxDecodes::ResultRecord;
    private import WstxDecodes::PeriodView;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelNotes::DiffersFromSource;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    requirement 'CL-063-02' {
        subject ranking : RankingService;
        doc /* Ranking MUST take a CQ that carries a CQ word of the contest it ranks by as
             a CQ for the station (ContestDirective). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-063-02'; }

    attribute def ContestDirective {
        doc /* A CQ whose directive is one of the ContestProfile::cqWords of the contest
             that StrategyRules::contest names in the ContestTable is for the station
             while station time lies in the contest's period (ContestInForce), whatever
             the continents are and also while they are unknown: it is not grey. Before
             and after the period a word of the contest counts as no word. Under a
             strategy of class strategy no word of a contest counts; the special
             activity the operator has set adds no CQ word of its own. */
    }

    verification 'TC-063-004' {
        doc /* The CQ words of the contest. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-063-02'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_063_004_the_directive_table_in_a_contest_activity";
        }
    }

    requirement 'CL-063-09' {
        subject ranking : RankingService;
        doc /* Ranking MUST count the QSOs of the contest's period by the rules of the
             contest, each station once as its dupe rule says, and tell the QSOs, the
             multipliers, the points and the score (ContestCount). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-063-09'; }

    attribute def ContestCount {
        doc /* How the QSOs of a contest are counted. The contest is the ContestProfile
             that ContestInForce::profile names in the ContestTable.
             Ranking asks the log for the PeriodQsos of the ContestPeriod from
             ContestInForce::startUtcMs to endUtcMs.
             A PeriodQso is counted when its start lies in the period, its mode is
             one of the profile's CountedModes, its band is one of the profile's
             bands, and it is no dupe of a QSO counted before it. The QSOs are taken
             in the order of their start. A QSO without a band is not counted.
             The dupe, by the profile's DupeRule. band: the call is counted on the
             band. bandModeClass: it is counted on the band in the same of phone, CW
             and digital. call: it is counted. bandGrid: it is counted on the band
             from the same first four characters of the grid; a QSO without a grid is
             a dupe when the call is counted on the band at all, and every grid is a
             dupe of a counted QSO of the call on the band that has none.
             The ContestTally: qsos is the number of counted QSOs; multipliers the
             number of different keys of the profile's MultiplierRule among them, a
             QSO without a grid giving none; points the sum of their points by the
             profile's PointsRule, with the profile's locator as the station's grid
             and 0 for a QSO whose points need a grid that is not known; score is
             points times multipliers, and the points alone under MultiplierRule::none.
             The count follows the logbook: an EvaluateRequest is answered from a
             count of the logbook as it is; for a PeriodView ranking takes the count
             it has and makes a new one when the logbook has changed.
             While the logbook is unavailable there is no count and no tally. */
        @FollowsSource {
            reference = "The official rules of each contest of WstxStrategies::ContestTable";
        }
        @DiffersFromSource {
            what = "WSJT-X keeps the QSOs of a contest in a log of their own, with the "
                + "dupes by call and band; ranking counts the QSOs of the logbook that "
                + "start in the period.";
        }
    }

    verification 'TC-063-005' {
        doc /* The points and the multipliers, by hand. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-063-09'; }
        @TestedBy {
            test = "server/src/contest_tests.rs::tc_063_005_the_points_rules_by_hand";
        }
    }

    requirement 'CL-063-04' {
        subject ranking : RankingService;
        doc /* Ranking MUST, under a strategy of class contest, give a rank only to a
             station that can be called in the contest and is no dupe, and order those
             stations by what they are worth in the contest (ContestVerdictRule,
             ContestValueOrder). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-063-04'; }

    attribute def ContestVerdictRule {
        doc /* How the Verdict of a record is found under a strategy of class contest.
             A ResultRecord has a verdict when it is decoded and is a standard message
             of a sender with a call, or a Field Day exchange from a call to a call. A
             Field Day exchange has no grid and is no CQ.
             The tests are made in this order, and the first that holds decides, each
             without a rank:
             the sender is ignored (WstxIgnoreLists::IgnoreListsRule);
             the record is a CQ that WstxValueOrder::DirectedCqRule leaves to others:
             grey, with that rule's why;
             the sender is the profile's call: "my own message";
             the station's band is unknown: "band unknown";
             the band is none of the contest's: "band not in the contest";
             the sender is wanted and can be called (WstxWantedList::WantedRule): a
             rank, with the ContestVerdict, whatever the tests below say;
             there is no ContestCount: "log unreadable";
             the sender is a dupe by ContestCount, on the station's band, in a
             digital mode and from the first four characters of the grid in its
             message: "dupe", with ContestVerdict::dupe true, also for a caller;
             the record is no caller, and its call fails the callsign guard of
             WstxValueOrder::Candidate: "callsign guard"; under DupeRule::bandGrid
             the guard is asked of the call without an ending /R;
             the record is no caller and neither a CQ nor an RR73 or 73 to another
             call: "not a CQ".
             Every other record is a caller or a candidate with a ContestVerdict:
             newMultiplier when its key of the MultiplierRule is not among the counted
             ones; points by the PointsRule. Its why names, joined by " · ", "calls my
             call" for a caller, "new multiplier", and the points as "<n> points".
             The strategy then takes the rank from such a record: while the station
             is off the strategy's bands, with the why of
             WstxValueOrder::StrategyBandsRule; when its country, US state or CQ
             target list fails, with the why of that line; and from a caller while
             callersFirst is off, with "not answered". For a caller the last two are
             written after "calls my call · ".
             The records that keep a rank are ordered by ContestValueOrder; the
             others follow in the order of their numbers. */
    }

    attribute def ContestValueOrder {
        doc /* The order of the ranked records under a contest: the wanted records
             first (WstxWantedList::WantedRule), then the callers, each group ordered
             among itself as follows;
             then a new multiplier before none; then the more points, unknown points
             counting as 0; then the stronger SNR, an unknown one last; then the lower
             audio frequency; then the call in the order of its characters. */
        @DiffersFromSource {
            what = "WSJT-X answers the first decoded station that calls; this order "
                + "ranks every station that can be called.";
        }
    }

    verification 'TC-063-006' {
        doc /* The count of a period, the dupes and the verdicts. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-063-04'; verify 'CL-063-09'; }
        @TestedBy {
            test = "server/src/contest_tests.rs::"
                + "tc_063_006_only_the_period_counts_and_each_dupe_rule; "
                + "server/src/contest_tests.rs::tc_063_006_verdicts_callable_by_value; "
                + "server/src/contest_tests.rs::"
                + "tc_063_006_a_field_day_exchange_to_my_call_is_a_caller; "
                + "server/src/strategy_tests.rs::"
                + "tc_063_007_a_contest_selection_store_and_evaluation";
        }
    }
}
