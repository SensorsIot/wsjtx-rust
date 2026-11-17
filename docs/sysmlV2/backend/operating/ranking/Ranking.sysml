package WstxRankingPart {
    private import ScalarValues::*;
    private import WstxRankingControl::RankingControlPort;
    private import WstxStrategies::RankingSharePort;
    private import WstxDecodes::DecodesPort;
    private import WstxOperatingChain::RankedActivityPort;
    private import WstxOperatingChain::WorkedBeforePort;
    private import WstxHearing::HeardByPort;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::DetailTests;

    part def RankingService {
        doc /* Orders the decoded stations by the rules of the active strategy and gives
             a verdict for each. It says what is new about each decoded station, keeps
             the ignore list and the Most Wanted list, counts the QSOs of a contest and
             records an alert for each station worth calling. It starts no contact and
             transmits nothing. */
        @ImplementedIn {
            module = "server/src/strategy.rs; server/src/contest.rs; "
                + "server/src/most_wanted.rs";
        }
        @DetailTests {
            tests = "server/src/strategy_tests.rs; server/src/strategy97_tests.rs; "
                + "server/src/contest_tests.rs";
            covers = "the verdicts and the value order of the decoded stations";
        }
        port control : ~RankingControlPort;
        port rules : ~RankingSharePort;
        port decodes : ~DecodesPort;
        port ranked : RankedActivityPort;
        port workedBefore : ~WorkedBeforePort;
        port hearing : ~HeardByPort;
    }
}
