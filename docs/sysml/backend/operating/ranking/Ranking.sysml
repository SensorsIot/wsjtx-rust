package WstxRankingPart {
    private import ScalarValues::*;
    private import WstxRankingControl::RankingControlPort;
    private import WstxDecodes::DecodesPort;
    private import WstxOperatingChain::RankedActivityPort;
    private import WstxOperatingChain::WorkedBeforePort;
    private import WstxHearing::HearingPort;
    private import WstxClubLog::ClubLogPort;
    part def RankingService {
        doc /* Level 3 of the operating chain: orders the decoded stations by the rules of
             the active strategy and gives a verdict for each. */
        port control : ~RankingControlPort;
        port decodes : ~DecodesPort;
        port ranked : RankedActivityPort;
        port workedBefore : ~WorkedBeforePort;
        port hearing : ~HearingPort;
        port clubLog : ClubLogPort;
    }
}
