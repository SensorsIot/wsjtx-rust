package WstxKeying {
    private import ScalarValues::*;
    port def Keying {
        out item command : KeyCommand;
        in item outcome : KeyOutcome;
        in item mayKey : MayKeyAnswer;
        in item availability : RadioAvailability;
    }
    item def KeyCommand { doc /* Key and unkey. */ }
    item def KeyOutcome { doc /* The outcome of a key or unkey command. */ }
    item def MayKeyAnswer { doc /* Whether the radio may be keyed now. */ }
    item def RadioAvailability { doc /* Whether the radio is available for transmit. */ }
    interface def KeyingLink {
        doc /* Transmit keys the radio through radio control and learns whether it may. */
        end transmit : Keying;
        end radioControl : ~Keying;
    }
}
