package WstxAutoPart {
    private import ScalarValues::*;
    private import WstxAutoControl::AutoControlPort;
    private import WstxStrategies::AutoSharePort;
    private import WstxDecodes::DecodesPort;
    private import WstxOperatingChain::RankedActivityPort;
    private import WstxOperatingChain::TargetChoicePort;
    private import WstxHearing::TargetHearingPort;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::DetailTests;
    private import WstxModelNotes::CodeDiffers;

    part def AutoService {
        doc /* Level 2 of the operating chain: while Auto is on it calls the most valuable
             station that can be called, or calls CQ, says when its Tx moves, and leaves a
             station by the rules of the active strategy. Where Tx goes is qso's. It stores
             nothing. */
        @ImplementedIn {
            module = "server/src/automation.rs";
        }
        @CodeDiffers {
            what = "Its code stands in server/src/automation.rs, outside "
                + "server/src/operating/auto/ and client/src/operating/auto/.";
        }
        @DetailTests {
            tests = "server/src/automation_tests.rs";
            covers = "the steps of Auto";
        }
        port control : ~AutoControlPort;
        port rules : ~AutoSharePort;
        port ranked : ~RankedActivityPort;
        port decodes : ~DecodesPort {
            doc /* The decoded frames: the calls, frequencies and messages of the records
                 the ranked list names, and the stations decoded in a period. */
        }
        port target : TargetChoicePort;
        port hearing : ~TargetHearingPort {
            doc /* What the station being called hears: the PSK case of its Tx moves. */
        }
    }
}
