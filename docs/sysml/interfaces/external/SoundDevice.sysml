package WstxSoundDevice {
    private import ScalarValues::*;
    private import ModelNotes::FollowsSource;

    doc /* The sound device of a radio that gives its audio to the PC as a sound card (the
         USB connection). A radio on its native network connection has no sound device. */

    enum def Encoding {
        doc /* The sample encodings the station takes from and gives to a sound device. */
        enum float32;
        enum pcm16;
        enum pcm24;
        enum pcm32;
    }

    item def Endpoint {
        doc /* One capture or render endpoint of the PC. */
        attribute id : String {
            doc /* The identifier Windows gives the endpoint. The station names an endpoint
                 by it and by nothing else. */ }
        attribute name : String { doc /* The friendly name Windows gives it. */ }
    }
    item def CaptureStream {
        doc /* The packets of one opened capture endpoint: channel 0 is used.
             The station takes a rate of 44100 or 48000 Hz, one or two channels and an
             encoding of Encoding; another format is not opened. */
    }
    item def RenderStream {
        doc /* The frames written to one opened render endpoint, the same mono program on
             every channel.
             The station takes a rate of 48000 Hz, one or two channels and an encoding
             of Encoding; another format is not opened. */
    }

    port def SoundDevicePort {
        doc /* Written from the station's side; the sound device uses the conjugate.
             The station opens the endpoint it names and no other. */
        @FollowsSource {
            reference = "Windows Core Audio: MMDevice API and WASAPI, shared mode, "
                + "event driven";
        }
        in item endpoints : Endpoint[0..*] {
            doc /* The active endpoints, listed without opening one. */ }
        in item capture : CaptureStream;
        out item playing : RenderStream;
    }
    interface def SoundDevice {
        doc /* The audio adapter and the sound-card endpoints. */
        end audioAdapter : SoundDevicePort;
        end device : ~SoundDevicePort;
    }
}
