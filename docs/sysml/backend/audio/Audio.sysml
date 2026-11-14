package WstxAudioPart {
    private import ScalarValues::*;
    private import WstxAudioStreams::AudioExchange;
    private import WstxAudioControl::AudioStatus;
    private import WstxAudioStreams::ReceiveSamples;
    private import WstxSoundDevice::SoundDevicePort;
    part def AudioInterface {
        attribute configuredIntent : WstxAudio::DeviceIntent;
        attribute observedState : WstxAudio::AudioState;
        attribute observedNativeFormat : WstxAudioStreams::NativeFormat[0..1];
        attribute observedNativeRateHz : Integer[0..1];
        attribute observedNativeChannels : Integer[0..1];
        attribute observedNativeEndpointId : String[0..1];
        doc /* Own sources/sinks, device/channel sample movement, metadata and device failures. No CAT/PTT, mode decoding or QSO decisions. CAT-disabled audio and control without an open audio device remain independent. */
        doc /* Independent samples, timing and failures; CAT-disabled live input and stored
             recordings use the same receive boundary. Does not issue control commands. */
        port status : AudioStatus;
        port recorded : ~ReceiveSamples;
        port receive : ReceiveSamples;
        port transmit : ~AudioExchange;
        port backend : AudioExchange;
    }
    part def AudioDeviceAdapter {
        port host : ~AudioExchange;
        port device : SoundDevicePort;
    }
}
