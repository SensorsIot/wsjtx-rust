package WstxCatControl {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-009';
    private import WstxRadioControlPart::RadioControlInterface;
    private import WstxRadioControl::*;
    private import WstxKeying::*;
    private import WstxRadioProperties::DialRange;
    private import WstxRadioProperties::ModeValue;
    private import WstxRadioProperties::Meter;
    private import WstxCat::CivFrame;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    // ---- The connection to the radio ----------------------------------------------------

    requirement 'CL-008-04' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST control the rig icom.ic7300, an Icom IC-7300, over its
             CI-V serial link, on the port and with the addresses the profile's endpoint
             names (RadioConnection). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-008-04'; }

    attribute def RadioConnection {
        doc /* How the endpoint of ControlSelection is read and the radio connected.
             The endpoint is "COMn", or
             "icom7300://COMn?baud=<rate>&radio=<address>&controller=<address>" with
             exactly these three keys in this order. n is 1 to 256 without a leading
             zero, in capitals or not. The rate is "auto" or one of the rates of the
             serial line. An address is two hexadecimal digits from 01 to EF, and the
             two differ. "COMn" alone means the rate auto, the radio at 94 and the
             controller at E0. Any other text is invalidConfiguration.
             To connect, radio control opens the port (OpenRadio) and asks the radio
             for its frequency; the state is ready when the radio has answered with
             one. These rules are those of the rig icom.ic7300 (ControlSelection::rig);
             the radio's identity is asked only where a rule says so.
             With a rate named, the radio is asked once at that rate. With auto it is
             asked at 9600, 19200, 4800, 115200, 57600 and 38400 in this order until it
             answers; RadioStatus::effectiveBaud is the rate it answered at, and the
             profile stays as it is.
             Without an answer the port is closed and the state is unavailable with the
             error of the last question. A port another station or another program
             holds gives resourceInUse.
             While the state is ready and nothing else is in work, radio control reads
             the five facts once in pollSeconds. A read that fails ends the connection.
             A connection that is asked to close ends the exchange in work with
             cancelled and closes its port.
             A port that does not close leaves the state closing with failedClose. */
        attribute pollSeconds : Integer = 1;
        attribute closeMaxMs : Integer = 250 {
            doc /* From the request to close to the closed port. It bounds the reconnect
                 after another assignment or a Disconnect, which waits for the closed
                 port (CatLifecycle). */ }
    }

    verification 'TC-009-003' {
        doc /* The connection to the radio on a scripted serial port.
             Setup: radio control on a port that answers from hand-written bytes and
             records every frame, rate and close; for (f) two processes of the test on
             one PC. No radio.
             (a) The endpoint "com3": port 3, rate auto, radio 94, controller E0.
             "COM0", "COM257", "COM03", "COM3/other", the keys in another order, the
             radio address FF, the same address twice, a fourth key and a fragment:
             invalidConfiguration.
             (b) Rate auto, the radio silent at 9600 and answering at 19200: the rates
             set are 9600 and 19200, the effective rate is 19200, the endpoint still
             says auto.
             (c) A request to close while an exchange is in work: that exchange ends
             with cancelled and the port is closed within 250 ms.
             (d) One reading of the five facts, then another within the second: busy,
             no frame.
             (e) No answer and a port that does not close: failedClose, the state
             closing.
             (f) A device one process holds: a second process is refused with
             resourceInUse, also when it writes the device's name in other capitals;
             after the release it is granted. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-008-04'; }
        @TestedBy {
            test = "server/tests/radio_control.rs; "
                + "server/tests/receive/radio_native.rs::"
                + "physical_identity_lease_conflicts_across_processes_and_case_aliases";
        }
    }

    verification 'TC-009-002' {
        doc /* The station's own IC-7300, read and set by hand.
             Setup: the station PC with its IC-7300 on COM3; the test is started by
             hand, with the radio's keying lines confirmed off or with the operator's
             word that the radio may be used without that check.
             (a) Without either: no port is opened.
             (b) The five reads are answered, and the port is given up within 500 ms
             of the request to close.
             (c) With the radio at 7074000 Hz, LSB, filter 1, data mode off, receiving
             and without split: receiveSetup to USB, filter 1, data mode on with
             filter 1 is confirmed by the radio; the way back to LSB with the data
             mode off likewise.
             (d) On a scripted port the first question of the connection and the two
             changes of (c) give 21 frames, and the frequency, which already fits, is
             read and not written. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 4; location = TestLocation::station; }
        @Automation { run = AutomationState::partial; method = "started by hand"; }
        objective { verify 'CL-008-04'; }
        @TestedBy { test = "server/tests/receive/radio_hardware.rs"; }
    }

    // ---- What reaches the radio ---------------------------------------------------------

    requirement 'CL-008-06' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST send a radio only the commands of its own operations,
             each as one exchange that ends with an answer of that radio or at a limit
             of time or size (ControlExchange). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-008-06'; }

    attribute def ControlExchange {
        doc /* How an OperationRequest is taken and carried out.
             Before anything is sent the request is checked: a frequency outside
             DialRange, a filter number outside 1 to 3, or a data filter number
             that is not 1 to 3 with the data mode on and 0 with it off, is
             invalidRequest; another connection than the current one is
             staleContext; an operation the station has not for this radio is
             unsupported; a request that is withdrawn is cancelled; a state other than
             ready is unavailable.
             One exchange is in work at a time. A request that meets another exchange,
             a reservation that is not its own, or the keying of the transmitter is
             refused with busy; nothing waits in a queue. ReserveRadio alone waits, up
             to its waitMs, and is refused at once while the transmitter may be keyed.
             An exchange is one frame to the radio and the radio's answer to it. The
             answer is a frame from the radio's address to the controller's that fits
             the command. The echo of the station's own frame, frames of other
             addresses and reports the radio sends unasked are passed over.
             A refusal of the radio is rejected. An answer the source does not allow,
             and a frequency outside DialRange, is protocol.
             A mode the station does not set is kept by its code
             (ModeValue::modeCode).
             A frame is sent once: radio control does not repeat an exchange by
             itself.
             An exchange that fails with anything but rejected and readbackMismatch
             ends the connection: its port is closed and the state is unavailable with
             that error.
             An exchange the radio does not answer in time ends with timeout; what
             arrives meanwhile does not extend it. An operation also ends at the
             withinMs of its request. */
        attribute exchangeMaxBytes : Integer = 4096 {
            doc /* More bytes than this in one exchange is limit. */ }
        attribute exchangeMaxFrames : Integer = 64 {
            doc /* More frames than this in one exchange is limit; so is a frame longer
                 than CivFrame::maxFrameBytes. */ }
    }

    verification 'TC-009-001' {
        doc /* The exchanges with the radio on a scripted serial port.
             Setup: radio control on a port that answers from hand-written bytes and
             records every frame. No radio.
             (a) Set frequency 14074000 Hz goes out as the source's command 05 with the
             bytes 00 40 07 14 00; the answer 03 with these bytes reads 14074000.
             (b) 29999 and 74800001 Hz, the filter numbers 0 and 4, the data mode off
             with filter 1 and on with filter 0 or 4: invalidRequest. 30000 and
             74800000 Hz are taken.
             (c) A mode answer with the code 77 and filter 1: kept as code 77. The
             station's own frame coming back, and an acknowledgement to a read: not an
             answer.
             (d) An answer that arrives one byte at a time: taken, and the time limit
             of its exchange does not move. 64 frames in an exchange: taken; one more:
             limit. 4096 bytes: taken; one more: limit. A frame of 32 bytes: taken; of
             33: limit.
             (e) A request while another is in work: busy, and no frame for it.
             (f) A request naming another connection: staleContext. A request
             withdrawn before it is taken: cancelled. No frame for either.
             (g) A request withdrawn while the answer is awaited: cancelled, no mode
             is recorded, the state is unavailable and the port closed once; the next
             request: unavailable, and no frame.
             (h) A port that takes one byte of a frame: partialWrite, the state
             unavailable.
             (i) During a reservation a request of another origin: busy; the requests
             of the reservation are carried out; 1.1 s pass without a frame of the
             regular reading; after the release a request is taken. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-008-06'; }
        @TestedBy { test = "server/tests/radio_control.rs"; }
    }

    // ---- Changing a value of the radio --------------------------------------------------

    requirement 'CL-044-09' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST change a value of the radio only after reading it and
             only where it differs from the wanted one, and count the change as made
             only when the radio reports the new value (ReadCompareWriteVerify). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-09'; }

    attribute def ReadCompareWriteVerify {
        doc /* The steps of every change: of frequency, mode and data mode
             (ControlOperation), of the AGC (ApplyAgc and at a new connection) and of a
             menu item (ApplyRecommended).
             1. The value is read. A read the radio refuses ends the change with
             rejected.
             2. A value that is the wanted one is not written; the read is the
             confirmation.
             3. For the AGC and a menu item the radio is asked whether it transmits;
             while it does, the change ends with busy.
             4. The value is written. The radio must acknowledge; a refusal is
             rejected.
             5. The value is read again. Another value than the wanted one is
             readbackMismatch; no answer and a refused read are indeterminate.
             Nothing is written a second time and nothing is set back.
             receiveSetup changes the mode, the data mode and the frequency in this
             order, each by these steps. When one of them was written, the three are
             read once more at the end and must be the wanted ones; otherwise it ends
             with readbackMismatch. When none was written, the three reads are the
             confirmation.
             Keying the transmitter is not a change of a value (KeyingRules). */
    }

    verification 'TC-044-012' {
        doc /* Frequency, mode, data mode and a menu item are read before they are set.
             Setup: radio control on a scripted port that records every frame; no
             radio.
             (a) Set frequency 14074000 Hz, set mode USB with filter 2 and set data
             mode on with filter 2, the radio already there: one read each and no
             write.
             (b) The same three with the read refused: rejected, that one frame, the
             state ready and the port open.
             (c) Set frequency 14074000 Hz with the radio at 7074000 Hz: read, write,
             read. The frequency fact is not confirmed while the write goes out and is
             confirmed with 14074000 Hz after the second read.
             (d) receiveSetup to 14074000 Hz, USB, filter 2, data mode on with filter
             2, the radio already there: the reads of mode, data mode and frequency
             and no other frame.
             (e) The same with the radio at USB filter 1, data mode off and
             7074000 Hz: read, write and read for the mode, the data mode and the
             frequency, then the three reads again; twelve frames.
             (f) As (e), the last read giving 14074001 Hz: readbackMismatch, the fact
             shows 14074001 Hz, and no further frame.
             (g) Set mode whose write the radio refuses: rejected after the read and
             the write. Set frequency whose second read is refused: indeterminate.
             Set mode LSB acknowledged by a radio that stays in USB: readbackMismatch,
             and the fact shows USB. Set data mode whose second read gets no answer:
             indeterminate, the state unavailable and the port closed.
             (h) The menu item usbSend to OFF: already OFF: its read alone. The read
             refused: rejected, its read alone. At DTR: its read, the read of the
             transmit state, the write, its read. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-09'; }
        @TestedBy {
            test = "server/tests/radio_control.rs; server/src/radio_control/executor.rs";
        }
    }

    verification 'TC-044-008' {
        doc /* The AGC is read before it is set.
             Setup: the station with its radio connection ready on a scripted IC-7300
             that echoes every frame; the wanted AGC is SLOW. No radio.
             (a) The radio at SLOW: the read of the AGC alone; not written.
             (b) The radio at MID: the read of the AGC, the read of the transmit
             state, the write of SLOW, the read of the AGC; written, and the radio is
             at SLOW.
             (c) The radio at MID and transmitting: busy after the two reads, no
             write, the state ready.
             (d) The radio refuses the write: rejected, the radio stays at MID, the
             state ready.
             (e) The radio acknowledges and stays at MID: readbackMismatch, the state
             ready.
             (f) The radio refuses the read: rejected, the read alone, the state
             ready.
             (g) The source's codes 1, 2 and 3 read FAST, MID and SLOW; 0 and 4 are no
             AGC; the station's own frame coming back is not an answer. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-09'; }
        @TestedBy { test = "server/src/radioControl/radio_agc_tests.rs"; }
    }

    // ---- Keying the transmitter ---------------------------------------------------------

    requirement 'CL-008-09' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST key and unkey the radio for transmit, confirm each only
             by the radio's own report, and keep every other exchange from the radio
             while it may be keyed (KeyingRules). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-008-09'; }

    attribute def KeyingRules {
        doc /* How the requests of the port Keying are carried out.
             A KeyRequest waits until the exchange in work and a reservation have
             ended. When its withinMs ends first, or WithdrawKey arrives before the
             command has gone out, it is answered with KeyFailed and busy, and nothing
             is sent.
             The command to key or to unkey must be acknowledged by the radio; a
             refusal is rejected. Then the radio is asked for its transmit state:
             KeyConfirmed follows when it reports the state asked for; the other state
             is readbackMismatch, no report is indeterminate.
             RadioAvailability::mayBeKeyed is true from the moment a key command is to
             go out until an unkey is confirmed. During that time radio control takes
             no OperationRequest, no reservation, no reading of the facts, no AGC and
             no menu exchange: the next frame to the radio is an unkey or a meter read.
             An UnkeyRequest is carried out whether or not the radio may be keyed, also
             on a connection that is being closed and whose port is still open.
             A connection that closes while the radio may be keyed first sends one
             unkey, with its report, and no key.
             A key or unkey that fails with anything but rejected and readbackMismatch
             ends the connection, as in ControlExchange.
             ReadMeters is carried out only while the radio may be keyed; otherwise it
             is answered with MetersRefused and busy, and nothing is sent. The meters
             are read in the order alc, po, swr. The output power is given in percent
             of the radio's full power, the SWR as ten times the ratio and the ALC in
             percent of the radio's ALC zone, each by the source's table. A KeyRequest or
             UnkeyRequest ends a meter read that is in work. A meter read that fails
             leaves the connection as it is.
             RadioAvailability::ready is the state ready, and transmitting is the
             transmit fact while it is confirmed.
             A failure is given to transmit as one of KeyFailure: timeout also for
             cancelled and partialWrite, indeterminate also for protocol and limit,
             unavailable for every ControlError that KeyFailure does not name. */
        attribute closingUnkeyMaxMs : Integer = 250 {
            doc /* The time for the unkey of a connection that closes. */ }
    }

    verification 'TC-009-007' {
        doc /* Keying and unkeying on a scripted IC-7300.
             Setup: radio control with its connection ready on a scripted radio that
             records every frame with its time; for (e) the station with that radio.
             No radio.
             (a) 1.3 s without a request: only reads go out.
             (b) A KeyRequest, 1.5 s, an UnkeyRequest: the frames are the key command,
             the read of the transmit state, the unkey command, the read of the
             transmit state; no other frame between the key and the unkey; the radio
             is keyed in between and unkeyed after; mayBeKeyed is false at the end.
             (c) A request to close while keyed: one unkey command, the radio
             unkeyed.
             (d) A key whose acknowledgement does not come within 300 ms: timeout,
             mayBeKeyed stays true, and the state is not ready any more.
             (e) A KeyRequest of 2 s during a reservation, withdrawn after 50 ms:
             busy within 250 ms, no key command, mayBeKeyed false.
             (f) ReadMeters while the radio may not be keyed: busy and no frame.
             After a KeyRequest: the reads of alc, po and swr in this order and no
             other frame, and the UnkeyRequest after it is confirmed. A radio that
             refuses the read of alc: alc absent, po read.
             (g) A meter read of 60 ms on a radio that does not answer: timeout, and
             the state stays ready. An UnkeyRequest while a meter read waits for the
             radio: confirmed within 250 ms; the meter read is ended and the state
             stays ready.
             (h) The radio's counts 0, 143 and 213 of the output power: 0, 50 and
             100 percent. Its counts 0, 48, 80 and 120 of the SWR: 1.0, 1.5, 2.0 and
             3.0.
             (i) Planned, no test yet: its counts 0, 10, 60 and 120 of the ALC: 0, 8,
             50 and 100 percent. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-008-09'; }
        @TestedBy {
            test = "server/tests/transmit_service.rs::"
                + "ci_v_ptt_bytes_readback_and_hold_exclude_polling; "
                + "server/tests/transmit_service.rs::"
                + "closing_a_keyed_connection_sends_one_off_only_switch_and_timeouts_close; "
                + "server/tests/transmit_service.rs::"
                + "a_halt_aborts_a_key_waiting_for_the_cat_owner_without_bytes; "
                + "server/src/radio_level_tests.rs::"
                + "meters_are_read_only_under_the_transmit_hold_in_the_manual_frames; "
                + "server/src/radio_level_tests.rs::"
                + "a_stalled_meter_read_gives_way_to_the_release_and_keeps_the_connection; "
                + "server/src/radio_level_tests.rs::meter_scales_follow_the_manual_table";
        }
    }
}
