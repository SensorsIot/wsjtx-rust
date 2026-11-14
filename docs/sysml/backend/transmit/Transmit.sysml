package WstxTransmitPart {
    private import ScalarValues::*;
    private import WstxAudioStreams::AudioExchange;
    private import WstxModeProcessing::EncodeProcessing;
    private import WstxKeying::Keying;
    private import WstxTransmitControl::TransmitControlPort;
    private import WstxOperatingChain::MessageToSendPort;
    private import WstxPeriodTiming::PeriodTimingPort;
    part def TransmitService {
        doc /* Own UTC scheduling, transmit state, audio/PTT coordination and priority halt; no browser timer or visualization-queue dependency. Defaults UNARMED on startup. Halt never waits for decode, receive cancellation or congestion. Backend/device loss and authority-expiry policy are settled before hardware TX and cannot be replaced in MCP. */
        doc /* UTC scheduling, operation authority and audio/PTT coordination reuse the
             common resource context. WstxTransmit::TransmitSafetyPolicy owns
             unresolved deadlines/backend-loss/expiry policy before hardware TX;
             WstxRequirements::ProcessingAndHaltOwnership separates priority halt from
             receive completion/cancellation and optional display congestion. */
        port operations : ~TransmitControlPort;
        port contacts : ~MessageToSendPort;
        port encode : EncodeProcessing;
        port audio : AudioExchange;
        port control : Keying;
        port timing : ~PeriodTimingPort;
        doc /* contacts receives QsoAndLogging's arm/disarm, TransmitRequest and halt
             requests and returns TransmitOutcome (WstxTransmit #9 slice B consumer
             contract, target). It is the only RF path of the contact workflow. */
    }
}
