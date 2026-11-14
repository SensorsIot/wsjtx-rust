package WstxFlexAdapterPart {
    private import ScalarValues::*;
    private import WstxRadioControl::RadioControl;
    private import WstxAudioStreams::CaptureSamples;
    private import WstxFlexApi::FlexApiPort;
    part def FlexAdapter {
        doc /* The whole native Flex session: its samples go to the audio function and its
             control comes from radio control. */
        port control : ~RadioControl;
        port samples : CaptureSamples;
        port radio : FlexApiPort;
    }
}
