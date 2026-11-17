package WstxOperatingPart {
    private import ScalarValues::*;
    private import WstxStrategies::StrategiesPort;
    private import WstxStrategies::RankingSharePort;
    private import WstxStrategies::AutoSharePort;
    private import WstxStrategies::ActivitySharePort;
    private import WstxStationTime::StationTimePort;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::DetailTests;

    part def OperatingService {
        doc /* Owns what a strategy is and its rules, the built-in strategies, the
             contests it knows, and which strategy and contest are selected. It reads
             the strategies the operator has saved, which the settings function
             manages. It holds the three functions that operate by a strategy and gives
             each its share of the active one: ranking what to prefer, Auto when to
             act, the contact the special activity of the contest. */
        @ImplementedIn { module = "server/src/strategy.rs; server/src/contest.rs"; }
        @DetailTests {
            tests = "server/src/strategy_tests.rs; server/src/strategy97_tests.rs; "
                + "server/src/contest_tests.rs";
            covers = "the strategies, their rules, the built-ins and the contests";
        }
        port control : ~StrategiesPort;
        port rankingShare : RankingSharePort;
        port autoShare : AutoSharePort;
        port activityShare : ActivitySharePort;
        port time : ~StationTimePort {
            doc /* The clock. Station time is the moment of a ReadContests. */
        }
    }
}
