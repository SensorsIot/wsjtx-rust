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
    private import ModelNotes::FollowsSource;
    private import ModelNotes::DiffersFromSource;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    // ---- The CQ words of the contest ------------------------------------------------------

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
        doc /* The CQ words of the contest.
             Setup: the evaluator alone, for a station in EU with the CQ word EU and a
             sender in NA.
             (a) CQ TEST is for the station under a contest with the CQ word TEST, and
             not without a contest or under one with the word WW. CQ WW is for it with
             WW, not with TEST. CQ FD is for it with FD, not with WW.
             (b) Under a contest with the word WW: CQ NA is not for the station, CQ EU
             is, CQ POTA is not, a CQ without a directive is. CQ WW is for it also while
             both continents are unknown.
             (c) CQ WW K1ABC FN42 under a strategy of class strategy for a new call,
             without a special activity: grey and without a rank.
             (d) Planned, no test yet: CQ WW K1ABC FN42 under a strategy of class
             strategy, with the special activity ww_digi set by the operator: grey and
             without a rank; CQ RU under the activity rtty: grey.
             (e) Planned, no test yet: CQ TEST under a contest with the word TEST, one
             minute before its period and at the first minute after it: grey; in its
             first minute: not grey. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-063-02'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_063_004_the_directive_table_in_a_contest_activity";
        }
    }

    // ---- What the logbook holds of the contest --------------------------------------------

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
             band. band_mode_class: it is counted on the band in the same of phone, CW
             and digital. call: it is counted. band_grid: it is counted on the band
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
        doc /* The points and the multipliers, by hand.
             Setup: the rules alone; the distances worked out apart from the code.
             (a) From JN37 to FN42, JO62, JN38 and PM95: one_plus_per_3000_km gives 2,
             1, 1 and 4; one_plus_per_500_km_up 13, 3, 2 and 21; kilometres 5895, 702,
             112 and 9625.
             (b) From JN37VL to JN37: kilometres 50; one_plus_per_500_km_up 2.
             (c) Without one of the two grids one_plus_per_3000_km gives no points;
             one_per_call gives 1 without any grid.
             (d) vhf_january and vhf_june_september: 1 and 1 on 6m and 2m; 2 and 2 on
             1.25m and 70cm; 4 and 3 on 33cm and 23cm; 8 and 4 on 13cm, 3cm and
             submm.
             (e) field_day: 2 in a digital mode and in CW, 1 in phone.
             (f) field_per_band for fn42 on 20m: the key FN on 20m. grid_per_band for
             FN42 on 6m: FN42 on 6m. none, and a QSO without a grid: no key. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-063-09'; }
        @TestedBy {
            test = "server/src/contest_tests.rs::tc_063_005_the_points_rules_by_hand";
        }
    }

    // ---- The verdict and the order under a contest ----------------------------------------

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
             WstxValueOrder::Candidate: "callsign guard"; under DupeRule::band_grid
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
        doc /* The count of a period, the dupes and the verdicts.
             Setup: the rules and the evaluator alone, with QSOs and decodes written
             by hand, for HB9BLA in EU with the locator JN37; for (j) the station on a
             throw-away profile with a logbook taken from a file.
             (a) WW Digi from 12:00 on a Saturday to 12:00 on the Sunday. K1OUT one
             second before the period; K1END at its end; K1ABC in FN42 on 20m in FT8,
             on 20m in FT4 and on 40m in FT8; W1SSB in SSB; W1WRC on 30m: 2 QSOs, 2
             multipliers, 4 points, score 8. A sender K1ABC is a dupe on 20m and none
             on 15m; K1OUT and K1END are none.
             (b) ARRL June VHF with K1ABC/R logged in FN42 on 6m: a dupe from FN42 and
             without a grid, none from FN43. With K1NOG logged without a grid: a dupe
             from FN42.
             (c) ARRL Field Day with K1ABC logged on 20m in SSB: 1 point, and no dupe
             for a sender in a digital mode.
             (d) FT8 Activity with DL1ABC logged on 2m: a dupe on 70cm; score 1.
             (e) ARRL Digi with W1RTY in RTTY and K1ABC in FN42 in FT8: 1 QSO, 13
             points, score 13.
             (f) WW Digi on 20m with W1DUP in EM12 and K1OLD in FN20 counted. CQ WW
             K1ABC FN42 at +5 dB, CQ WW JA1XYZ PM95 at -18, CQ WW OH1AA KP20 at -3, CQ
             WW W1DUP EM12, CQ NA W1AW FN31, DL1ABC K1ZZZ FN42, DL1ABC W1RRR RR73 at
             -9, HB9BLA VK2ABC QF56 at -20 and HB9BLA K1OLD FN20 at +9: VK2ABC has
             rank 0, JA1XYZ 1, OH1AA 2, K1ABC 3, W1RRR 4. JA1XYZ is a new multiplier
             with 4 points and "new multiplier · 4 points"; K1ABC is none, with 2
             points. W1DUP and K1OLD are dupes without a rank, W1DUP with "dupe". W1AW
             is grey with "CQ NA — not for EU". K1ZZZ has "not a CQ".
             (g) The same on 30m: no record has a rank, JA1XYZ with "band not in the
             contest". Without a count: no record has a rank.
             (h) CQ K1ABC/R FN42 on 6m: under ARRL June VHF rank 0; under IARU R1 50
             MHz MGM "callsign guard".
             (i) ARRL Field Day on 20m with K1OLD counted. A Field Day exchange of
             W9XYZ to HB9BLA: a caller with rank 0 and 2 points; of K1OLD to HB9BLA:
             "dupe"; of W9ABC to K1ABC: "not a CQ".
             (j) WW Digi on 40m for a station in JN47, with W1DUP in EM12 logged in
             the period and K1OLD in FN20 before it. CQ WW of W1DUP, K1OLD and JA1XYZ
             in PM95 at -15 dB: the tally is 1 QSO, 1 multiplier, 3 points, score 3;
             JA1XYZ has rank 0, a new multiplier and 4 points; K1OLD rank 1, a new
             multiplier and 3 points; W1DUP no rank, a dupe, no points. */
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
