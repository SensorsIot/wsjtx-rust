package WstxFlexAdapterPart {
    private import ScalarValues::*;
    private import ModelNotes::Conflict;
    private import WstxRadioControl::RadioControl;
    private import WstxAudioStreams::CaptureSamples;
    private import WstxFlexApi::FlexApiPort;
    part def FlexAdapter {
        doc /* The whole native Flex session: its samples go to the audio function and its
             control comes from radio control. */
        @Conflict {
            what = "WstxArchitecture::StationProcess says native Flex adds no part; "
                + "this part is the Flex session's own part.";
        }
        port control : ~RadioControl;
        port samples : CaptureSamples;
        port radio : FlexApiPort;
    }
}
