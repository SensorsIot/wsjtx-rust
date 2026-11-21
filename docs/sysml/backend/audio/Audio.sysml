package WstxAudioPart {
    private import ScalarValues::*;
    private import WstxAudioControl::AudioStatusPort;
    private import WstxAudioControl::AudioConfig;
    private import WstxAudioControl::AudioRecords;
    private import WstxAudioStreams::ReceiveSamples;
    private import WstxAudioStreams::Playback;
    private import WstxAudioStreams::AudioExchange;
    private import WstxAudioStreams::CaptureSamples;
    private import WstxStationTime::StationTimePort;
    private import WstxSoundDevice::SoundDevicePort;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::DetailTests;
    private import WstxModelNotes::CodeDiffers;

    part def AudioInterface {
        doc /* The audio of the station. It turns the packets of the profile's radio
             connection into the receive stream, keeps that stream tied to station time,
             and plays the transmit program on the sound device.
             The packets come from one of two connections, by the profile's radio type:
             the sound device of a radio on USB, through the audio adapter, or the native
             network connection of a radio, through its own adapter. The receive stream is
             the same for both. A sound device is listed, opened and played to only on
             the first. */
        @ImplementedIn {
            module = "server/src/audio.rs; server/src/transmit/playback.rs; server/src/source.rs; "
                + "server/src/audio/windows.rs";
        }
        @CodeDiffers {
            what = "Its code stands in server/src/audio.rs, server/src/radioControl/setup.rs, "
                + "server/src/radioControl/radio_setup.rs, server/src/source.rs, "
                + "server/src/transmit/playback.rs, outside server/src/audio/ and "
                + "client/src/audio/.";
        }
        @DetailTests {
            tests = "server/tests/source_contract.rs";
            covers = "the checks of a sample block and of an epoch's timing record";
        }
        attribute config : AudioConfig {
            doc /* Its configuration, as the last AudioDevices gave it. */ }
        attribute records : AudioRecords {
            doc /* Its records, as the last AudioMemory of the supervisor gave
                 them. */ }
        port status : AudioStatusPort;
        port time : ~StationTimePort;
        port receive : ReceiveSamples;
        port transmit : ~Playback;
        port device : ~AudioExchange;
        port native : ~CaptureSamples;
    }

    part def AudioDeviceAdapter {
        doc /* Joins audio to the sound endpoints of the PC: it lists them, opens the one
             audio names, and passes packets in and frames out. */
        @ImplementedIn {
            module = "server/src/audio/windows.rs; server/src/modes/playback/windows.rs";
        }
        port host : AudioExchange;
        port device : SoundDevicePort;
    }
}
