package WstxKeying {
    private import ScalarValues::*;
    private import WstxRadioProperties::MeterReadings;
    private import WstxModelNotes::CodeDiffers;

    doc /* Transmit switches the radio's transmitter on and off through radio control,
         learns whether the radio can be keyed, and reads the radio's meters while it
         transmits. Transmit does not know which radio it is. */

    enum def KeyFailure {
        doc /* Why a request of transmit was not carried out.
             busy: radio control was held by another exchange until the request's time
             ended, or the request was withdrawn; nothing was sent to the radio.
             unavailable: no radio is connected.
             timeout: the radio did not answer in time.
             rejected: the radio refused the command.
             readbackMismatch: the radio acknowledged the command and then reported the
             other state.
             indeterminate: the radio acknowledged the command and its state could not
             be read. */
        enum busy;
        enum unavailable;
        enum timeout;
        enum rejected;
        enum readbackMismatch;
        enum indeterminate;
    }

    enum def SplitOperation {
        doc /* How the radio transmits a tone shifted into 1500 to 1999 Hz.
             none: on the dial, without a shift.
             rig: on the radio's second VFO, the dial plus the shift.
             fakeIt: the dial moved by the shift while the radio is keyed. */
        enum none;
        enum rig;
        enum fakeIt {
            @CodeDiffers {
                what = "The code has no split operation: radio control keys the radio on "
                    + "its dial.";
            }
        }
    }
    item def KeyRequest {
        doc /* Switch the transmitter on. */
        attribute withinMs : Integer {
            doc /* The time radio control has for it, its wait for a running exchange
                 included. */ }
        attribute split : SplitOperation = SplitOperation::none {
            @CodeDiffers {
                what = "The code has no split operation: a key request carries its time "
                    + "only.";
            }
        }
        attribute shiftHz : Integer = 0 {
            doc /* The shift of the transmit frequency from the dial, a multiple of 500;
                 0 with none. */
            @CodeDiffers {
                what = "The code has no split operation: a key request carries its time "
                    + "only.";
            }
        }
    }
    item def WithdrawKey {
        doc /* Withdraw the KeyRequest that waits. A request whose command has not gone
             to the radio is answered with KeyFailed and busy. */
    }
    item def UnkeyRequest {
        doc /* Switch the transmitter off. */
        attribute withinMs : Integer;
    }
    item def KeyConfirmed {
        doc /* The radio itself reported the state the request asked for. */
        attribute keyed : Boolean { doc /* The state confirmed. */ }
    }
    item def KeyFailed {
        doc /* The state the request asked for is not confirmed. */
        attribute keyed : Boolean { doc /* The state that was asked for. */ }
        attribute reason : KeyFailure;
    }
    item def RadioAvailability {
        doc /* What transmit needs to know of the radio at the moment it is read. */
        attribute ready : Boolean { doc /* A radio is connected and answers. */ }
        attribute transmitting : Boolean[0..1] {
            doc /* What the radio last reported of its transmitter; absent while that
                 report is not confirmed. */ }
        attribute mayBeKeyed : Boolean {
            doc /* True from a KeyRequest until an unkey is confirmed. */ }
    }
    item def ReadMeters {
        doc /* Read the radio's meters once. */
        attribute withinMs : Integer;
    }
    item def MeterValues {
        attribute readings : MeterReadings;
    }
    item def MetersRefused {
        doc /* The meters were not read. */
        attribute reason : KeyFailure;
    }

    port def Keying {
        doc /* Written from transmit's side; radio control uses the conjugate.
             Each KeyRequest and each UnkeyRequest is answered by one KeyConfirmed or
             one KeyFailed, and each ReadMeters by MeterValues or MetersRefused. One
             request is in work at a time; a further one is answered with busy. */
        out item key : KeyRequest;
        out item withdraw : WithdrawKey;
        out item unkey : UnkeyRequest;
        out item readMeters : ReadMeters;
        in item confirmed : KeyConfirmed;
        in item failed : KeyFailed;
        in item availability : RadioAvailability;
        in item meters : MeterValues;
        in item metersRefused : MetersRefused;
    }
    interface def KeyingLink {
        doc /* Transmit keys the radio through radio control. */
        end transmit : Keying;
        end radioControl : ~Keying;
    }
}
