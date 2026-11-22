package WstxFlexAdapterPart {
    private import ScalarValues::*;
    private import WstxModelNotes::NotStated;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::DetailTests;
    private import WstxRadioControl::NativeControlPort;
    private import WstxAudioStreams::CaptureSamples;
    private import WstxFlexApi::FlexApiPort;
    private import WstxModelNotes::CodeDiffers;

    part def FlexAdapter {
        doc /* The station's connection to a FlexRadio over the radio's own network API.
             It holds one session with the radio, as a client of its own with one slice
             and one receive stream, gives the stream to audio as packets, tunes the slice
             for radio control, and reports the state of the session. */
        @ImplementedIn {
            module = "server/src/flexAdapter/mod.rs; server/src/flexAdapter/session.rs; "
                + "server/src/flexAdapter/wire.rs; server/src/flexAdapter/flex_http.rs";
        }
        @CodeDiffers {
            what = "Its code stands in server/src/main.rs, outside server/src/flexAdapter/ and "
                + "client/src/flexAdapter/.";
        }
        @DetailTests {
            tests = "server/src/flexAdapter/wire_tests.rs; "
                + "server/src/flexAdapter/session_tests.rs";
            covers = "the reading of the radio's lines, announcements and packets, the "
                + "adapter's record of the radio's clients, slices and streams, the text "
                + "form of a frequency, and the measurement of a packet's time stamp";
        }
        @NotStated {
            what = "which connection carries StreamDiagnosis out of the adapter; radio "
                + "control takes SessionStatus only, and the adapter has no port toward "
                + "the supervisor";
        }
        port control : ~NativeControlPort {
            @NotStated {
                what = "which items of the control connection carry the profile's "
                    + "NativeIntent, the request and the answer of TuneSlice, and "
                    + "SessionStatus; the requests and outcomes of "
                    + "RadioControl name none of them";
            }
        }
        port samples : CaptureSamples {
            doc /* The input is available in the state ready; outside it
                 InputStatus::retryAfterMs is SessionStatus::retryAfterMs. */
        }
        port radio : FlexApiPort;
    }
}
