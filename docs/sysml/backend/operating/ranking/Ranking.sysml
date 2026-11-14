package WstxRankingPart {
    private import ScalarValues::*;
    private import ModelNotes::Conflict;
    private import WstxRankingControl::RankingControlPort;
    private import WstxDecodes::DecodesPort;
    private import WstxOperatingChain::RankedActivityPort;
    private import WstxOperatingChain::WorkedBeforePort;
    private import WstxHearing::HearingPort;
    private import WstxClubLog::ClubLogPort;
    part def RankingService {
        doc /* Level 3 of the operating chain: orders the decoded stations by the rules of
             the active strategy and gives a verdict for each. */
        @Conflict {
            what = "The package doc of WstxArchitecture says the strategy workflows "
                + "introduce no strategy engine; the parts ranking and auto are the "
                + "levels that order and that execute (AutoService).";
        }
        port control : ~RankingControlPort;
        port decodes : ~DecodesPort;
        port ranked : RankedActivityPort;
        port workedBefore : ~WorkedBeforePort;
        port hearing : ~HearingPort;
        port clubLog : ClubLogPort;
    }
}
