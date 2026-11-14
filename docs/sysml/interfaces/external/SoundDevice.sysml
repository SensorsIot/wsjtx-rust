package WstxSoundDevice {
    private import ScalarValues::*;

    port def SoundDevicePort;
    item def SoundDeviceItem { doc /* What the audio adapter and the sound device exchange. */ }
    interface def SoundDevice {
        doc /* The audio adapter and the sound-card endpoints. */
        end audioAdapter : SoundDevicePort;
        end device : ~SoundDevicePort;
        item exchange : SoundDeviceItem;
    }
}
