package WstxAudioControl {
    private import ScalarValues::*;
    port def AudioStatus {
        in item command : AudioCommand;
        out item outcome : AudioOutcome;
    }
    interface def AudioControl {
        doc /* The station service commands the audio function; audio reports its outcomes. */
        end station : ~AudioStatus;
        end audio : AudioStatus;
    }
    item def AudioCommand { doc /* The device from the profile, open, close. */ }
    item def AudioOutcome;
}
