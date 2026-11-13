package WstxAudioStreams {
    private import ScalarValues::*;
    private import WstxArchitecture::AudioOutcome;
    private import WstxArchitecture::SampleBlock;
    port def AudioExchange {
        out item playback : SampleBlock;
        in item capture : SampleBlock;
        in item outcome : AudioOutcome;
    }
    port def ReceiveSamples {
        out item samples : SampleBlock;
        out item outcome : AudioOutcome;
    }
}
