package WstxTransmitPart {
    private import ScalarValues::*;
    private import ModelNotes::Conflict;
    private import ModelBindings::ImplementedIn;
    private import WstxAudioStreams::AudioExchange;
    private import WstxModeProcessing::EncodeProcessing;
    private import WstxKeying::Keying;
    private import WstxTransmitControl::TransmitControlPort;
    private import WstxOperatingChain::MessageToSendPort;
    private import WstxPeriodTiming::PeriodTimingPort;
    part def TransmitService {
        doc /* The transmit function: UTC scheduling, the transmit state, audio and PTT
             coordination and the priority halt, with no browser timer or visualization-queue
             dependency. */
        doc /* Its rules are WstxTransmit::TransmitAuthority, TransmitArming, TransmitTiming and
             HaltTransmit, on the common resource context; WstxRequirements::
             ProcessingAndHaltOwnership separates the priority halt from receive completion and
             cancellation and from display congestion. */
        @ImplementedIn { module = "server/src/transmit/service.rs; server/src/transmit_http.rs"; }
        port operations : ~TransmitControlPort;
        port contacts : ~MessageToSendPort;
        port encode : EncodeProcessing;
        port audio : AudioExchange;
        port control : Keying;
        port timing : ~PeriodTimingPort;
        @Conflict {
            what = "The doc below says contacts carries arm/disarm, TransmitRequest and halt "
                + "requests and returns TransmitOutcome; contacts is typed ~MessageToSendPort, "
                + "which carries only the TransmitRequest.";
        }
        doc /* contacts receives QsoAndLogging's arm/disarm, TransmitRequest and halt requests
             and returns TransmitOutcome. It is the only RF path of the contact workflow. */
    }
}
