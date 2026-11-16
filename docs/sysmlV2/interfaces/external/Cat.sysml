package WstxCat {
    private import ScalarValues::*;
    private import ModelNotes::FollowsSource;

    doc /* The serial link between the CAT adapter and a transceiver, and the frames on
         it. */

    item def CivFrame {
        doc /* One frame as the source defines it, from its two preamble bytes to its end
             byte. The station sends from the controller address E0 (hexadecimal) to the
             address of the radio, or to the broadcast address for the read of the
             transceiver identity.
             On the link every frame the station sends comes back as an echo, and other
             stations of the bus and the radio itself may send frames unasked. */
        attribute maxFrameBytes : Integer = 32 {
            doc /* A longer frame, in or out, is an error of the link. */ }
    }
    attribute def SerialLine {
        doc /* How the adapter sets the serial port. Eight data bits, no parity, one stop
             bit, no handshake. The lines DTR and RTS are switched off before the first
             byte and stay off, because a radio may key its transmitter from either.
             The port is opened for this station alone; a port another program holds
             cannot be opened.
             Opening a port can raise a line for a moment before it is switched off.
             The rates the adapter sets are 4800, 9600, 19200, 38400, 57600 and 115200
             bits per second. */
    }

    port def CatPort {
        doc /* Written from the CAT adapter's side; the transceiver uses the conjugate. */
        out item sent : CivFrame;
        in item received : CivFrame;
    }
    interface def Cat {
        @FollowsSource {
            reference = "Icom IC-7300 Full Manual A7292-4EX-12a, section 19, CI-V "
                + "command table";
        }
        doc /* The CAT adapter and the transceiver's serial link. The frames, the
             commands in them and the codes of their values are the source's. Which
             commands the station sends is radio control's choice
             (WstxRadioControl::ControlOperation, WstxKeying::Keying). */
        end catAdapter : CatPort;
        end radio : ~CatPort;
    }
}
