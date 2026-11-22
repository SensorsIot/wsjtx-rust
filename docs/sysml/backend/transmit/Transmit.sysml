package WstxTransmitPart {
    private import ScalarValues::*;
    private import WstxTransmitControl::TransmitControlPort;
    private import WstxTransmitControl::TransmitConfig;
    private import WstxOperatingChain::MessageToSendPort;
    private import WstxModeProcessing::EncodeProcessing;
    private import WstxAudioStreams::Playback;
    private import WstxStationTime::StationTimePort;
    private import WstxKeying::Keying;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::DetailTests;

    part def TransmitService {
        doc /* The transmit function of the station. It holds the transmit state, takes
             the requests of the contact, and puts each admitted request on the air in
             its period: it has the modes part make the waveform, keys the radio through
             radio control, plays the waveform through audio and releases the radio. It
             stops at once on Halt, plays the Tune tone, and keeps the level of its
             audio. It knows neither the radio type nor the output device. */
        @ImplementedIn {
            module = "server/src/transmit/service.rs; server/src/transmit/schedule.rs; "
                + "server/src/transmit/transmit_http.rs; server/src/transmit/radio_level.rs";
        }
        @DetailTests {
            tests = "server/src/transmit/radio_level_tests.rs";
            covers = "the bound of one meter reading and the seam that lengthens it in a "
                + "test";
        }
        attribute config : TransmitConfig {
            doc /* Its configuration, as the last TransmitProfile gave it. */ }
        port operations : ~TransmitControlPort;
        port contacts : ~MessageToSendPort;
        port encode : EncodeProcessing;
        port audio : Playback;
        port control : Keying;
        port time : ~StationTimePort;
    }
}
