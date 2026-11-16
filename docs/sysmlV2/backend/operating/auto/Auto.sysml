package WstxAutoPart {
    private import ScalarValues::*;
    private import WstxAutoControl::AutoControlPort;
    private import WstxDisplayData::DisplayDataPort;
    private import WstxOperatingChain::RankedActivityPort;
    private import WstxOperatingChain::TargetChoicePort;
    private import WstxHearing::TargetHearingPort;
    part def AutoService {
        doc /* Level 2 of the operating chain: selects the station to call, or calls CQ, and
             the transmit slot. */
        port control : ~AutoControlPort;
        port ranked : ~RankedActivityPort;
        port display : ~DisplayDataPort;
        port target : TargetChoicePort;
        port hearing : ~TargetHearingPort {
            doc /* What the station being called hears, for the automatic choice of the
                 transmit frequency (FreeTxSlot): our transmit offset in our parity is
                 occupied at the far end when the target decodes another sender there. */
        }
    }
}
