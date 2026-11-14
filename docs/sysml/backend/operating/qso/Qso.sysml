package WstxQsoPart {
    private import ScalarValues::*;
    private import WstxQsoControl::QsoControlPort;
    private import WstxDecodes::DecodesPort;
    private import WstxPeriodTiming::PeriodTimingPort;
    private import WstxOperatingChain::TargetChoicePort;
    private import WstxOperatingChain::CompletedContactPort;
    private import WstxOperatingChain::MessageToSendPort;
    private import WstxHearing::HearingPort;
    part def QsoAndLogging {
        doc /* Own exchange/completion/cancel and durable contacts; never bypass transmit authority or another profile storage. Stable completion identity and explicit persisted/unsaved outcome prevent silent duplicate contacts when completion replays. Concrete log schema/compatibility remains a target decision. */
        port operations : ~QsoControlPort;
        port transmit : MessageToSendPort;
        port decodes : ~DecodesPort;
        port timing : ~PeriodTimingPort;
        port target : ~TargetChoicePort;
        port completed : CompletedContactPort;
        port hearing : ~HearingPort;
        doc /* transmit carries contact transmissions only to TransmitService (WstxContact);
             no PTT, audio or radio port exists here. */
    }
}
