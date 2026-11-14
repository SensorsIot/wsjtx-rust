package WstxBrowserClientPart {
    private import ScalarValues::*;
    private import WstxStationLink::BrowserExchange;
    private import WstxRadioProperties::FrequencyRange;
    private import WstxOperatorInteraction::OperatorInteractionPort;
    part def BrowserClient {
        attribute localDisplayLevels : WstxSignalArea::DisplayLevels;
        attribute localDisplayPreference : WstxSettings::BrowserDisplayPreference;
        attribute localActivityOrdering : WstxOperatingLayout::ActivityOrdering;
        attribute observedPresentation : WstxOperatingLayout::OperatingPresentation;
        attribute receivePresentation : WstxSignalArea::ReceivePresentation;
        attribute browserWaterfallSpanHz : FrequencyRange;
        doc /* Presentation and preferences are frontend-owned. Waterfall frequency span
             is independent of physical receiver filter width and the radio's own scope. */
        doc /* Own presentation/local filtering/color, pending/stale state and requests; not authoritative radio state, timing-critical modulation or transmit authority. */
        doc /* Holds station state from one snapshot plus the station's pushed events and does not poll it (WstxStationLink::PushedStationState, the governing rule of this exchange). */
        port station : BrowserExchange;
        port operator : OperatorInteractionPort;
    }
}
