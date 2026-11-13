package WstxAudioControl {
    private import ScalarValues::*;
    private import WstxArchitecture::AudioOutcome;
    port def AudioStatus { out item outcome : AudioOutcome; }
}
